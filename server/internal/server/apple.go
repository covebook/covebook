package server

import (
	"context"
	"encoding/hex"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/appleauth"
	"net/http"
	"os"
	"strings"
)

func (s *Server) appleClient() (*appleauth.Client, error) {
	return appleauth.FromEnv(strings.TrimRight(os.Getenv("PUBLIC_BASE_URL"), "/")+"/auth/apple/callback", s.HTTP)
}
func (s *Server) appleEnabled() bool { _, err := s.appleClient(); return err == nil }

func (s *Server) appleStart(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
	if err != nil {
		return err
	}
	if !s.appleEnabled() {
		return apiError{503, "not_configured", "Apple 로그인이 아직 준비되지 않았어요"}
	}
	var body struct {
		ReturnURL string `json:"returnUrl"`
		Lifecycle string `json:"accountLifecycle"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if body.Lifecycle != "1" {
		return lifecycleError()
	}
	if body.ReturnURL != "chaekjang://auth/apple" {
		return bad
	}
	state, err := random(32)
	if err != nil {
		return err
	}
	nonce, err := random(32)
	if err != nil {
		return err
	}
	verifier, err := random(32)
	if err != nil {
		return err
	}
	if _, err = s.DB.Exec(r.Context(), "DELETE FROM apple_logins WHERE expires_at<=now()"); err != nil {
		return err
	}
	if _, err = s.DB.Exec(r.Context(), "DELETE FROM apple_login_tickets WHERE expires_at<=now()"); err != nil {
		return err
	}
	if _, err = s.DB.Exec(r.Context(), "INSERT INTO apple_logins(state_hash,user_id,return_url,nonce_hash,upstream_verifier) VALUES($1,$2,$3,$4,$5)", hash(state), user, body.ReturnURL, hash(nonce), verifier); err != nil {
		return err
	}
	client, _ := s.appleClient()
	writeJSON(w, 200, map[string]string{"url": client.AuthorizationURL(state, nonce)})
	return nil
}

func (s *Server) appleCallback(w http.ResponseWriter, r *http.Request) error {
	r.Body = http.MaxBytesReader(w, r.Body, 16384)
	if r.ParseForm() != nil {
		return bad
	}
	if !s.appleEnabled() {
		return upstream
	}
	state := r.PostForm.Get("state")
	if state == "" || len(state) > 200 {
		return expired
	}
	var source int64
	var ret, nonceHash, verifier string
	err := s.DB.QueryRow(r.Context(), "DELETE FROM apple_logins WHERE state_hash=$1 AND expires_at>now() RETURNING user_id,return_url,nonce_hash,upstream_verifier", hash(state)).Scan(&source, &ret, &nonceHash, &verifier)
	if errors.Is(err, pgx.ErrNoRows) {
		return expired
	}
	if err != nil {
		return err
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	code := r.PostForm.Get("code")
	if r.PostForm.Get("error") != "" || code == "" || len(code) > 4096 {
		http.Redirect(w, r, redirectParam(ret, "error", "denied"), http.StatusFound)
		return nil
	}
	nonceBytes, err := hex.DecodeString(nonceHash)
	if err != nil {
		return expired
	}
	client, _ := s.appleClient()
	identity, err := client.Exchange(r.Context(), code, nonceBytes)
	if err != nil {
		http.Redirect(w, r, redirectParam(ret, "error", "failed"), http.StatusFound)
		return nil
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	if _, err = tx.Exec(r.Context(), "INSERT INTO auth_identities(provider,subject,user_id) VALUES('apple',$1,$2) ON CONFLICT DO NOTHING", identity.Subject, source); err != nil {
		return err
	}
	var result int64
	if err = tx.QueryRow(r.Context(), "SELECT user_id FROM auth_identities WHERE provider='apple' AND subject=$1", identity.Subject).Scan(&result); err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "INSERT INTO apple_tokens(user_id,subject,sealed_refresh) VALUES($1,$2,$3) ON CONFLICT(subject) DO UPDATE SET sealed_refresh=EXCLUDED.sealed_refresh", result, identity.Subject, identity.SealedRefresh); err != nil {
		return err
	}
	ticket, err := random(32)
	if err != nil {
		return err
	}
	if _, err = tx.Exec(r.Context(), "INSERT INTO apple_login_tickets(ticket_hash,source_user_id,result_user_id) VALUES($1,$2,$3)", hash(ticket), source, result); err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	http.Redirect(w, r, redirectParam(ret, "ticket", ticket), http.StatusFound)
	return nil
}

func (s *Server) appleClaim(w http.ResponseWriter, r *http.Request) error {
	source, err := s.user(r)
	if err != nil {
		return err
	}
	var body struct {
		Ticket string `json:"ticket"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if body.Ticket == "" || len(body.Ticket) > 200 {
		return bad
	}
	tx, err := s.DB.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	var result int64
	err = tx.QueryRow(r.Context(), "DELETE FROM apple_login_tickets WHERE ticket_hash=$1 AND source_user_id=$2 AND expires_at>now() RETURNING result_user_id", hash(body.Ticket), source).Scan(&result)
	if errors.Is(err, pgx.ErrNoRows) {
		return expired
	}
	if err != nil {
		return err
	}
	if err = recordSwitch(r.Context(), tx, source, result); err != nil {
		return err
	}
	token, err := issueToken(r.Context(), tx, result)
	if err != nil {
		return err
	}
	var nickname string
	if err = tx.QueryRow(r.Context(), "SELECT COALESCE(nickname,'') FROM users WHERE id=$1", result).Scan(&nickname); err != nil {
		return err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return err
	}
	writeJSON(w, 200, map[string]any{"userId": result, "token": token, "switched": result != source, "nickname": nickname})
	return nil
}

func (s *Server) revokeApple(ctx context.Context, tx pgx.Tx, user int64) error {
	rows, err := tx.Query(ctx, "SELECT subject,sealed_refresh FROM apple_tokens WHERE user_id=$1 FOR UPDATE", user)
	if err != nil {
		return err
	}
	type token struct{ subject, sealed string }
	var tokens []token
	for rows.Next() {
		var t token
		if err = rows.Scan(&t.subject, &t.sealed); err != nil {
			rows.Close()
			return err
		}
		tokens = append(tokens, t)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	if len(tokens) == 0 {
		return nil
	}
	client, err := s.appleClient()
	if err != nil {
		return err
	}
	for _, t := range tokens {
		if err = client.Revoke(ctx, t.subject, t.sealed); err != nil {
			return err
		}
	}
	return nil
}
