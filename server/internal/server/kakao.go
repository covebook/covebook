package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/jackc/pgx/v5"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
)

var expired = apiError{400, "login_expired", "로그인 시간이 지났어요. 다시 시도해 주세요"}

func callbackURL() string {
	return strings.TrimRight(os.Getenv("PUBLIC_BASE_URL"), "/") + "/auth/kakao/callback"
}
func validReturn(raw string) bool {
	return raw == "chaekjang://auth/kakao"
}
func kakaoLoginKey() string {
	if key := os.Getenv("KAKAO_LOGIN_REST_KEY"); key != "" {
		return key
	}
	return os.Getenv("KAKAO_REST_KEY")
}
func kakaoEnabled() bool {
	return kakaoLoginKey() != "" && os.Getenv("KAKAO_ADMIN_KEY") != "" && os.Getenv("KAKAO_APP_ID") != "" && os.Getenv("PUBLIC_BASE_URL") != ""
}
func redirectParam(raw, key, val string) string {
	sep := "?"
	if strings.Contains(raw, "?") {
		sep = "&"
	}
	return raw + sep + key + "=" + url.QueryEscape(val)
}
func (s *Server) kakaoStart(w http.ResponseWriter, r *http.Request) error {
	user, e := s.user(r)
	if e != nil {
		return e
	}
	key := kakaoLoginKey()
	if !kakaoEnabled() {
		return apiError{503, "not_configured", "카카오 로그인이 아직 준비되지 않았어요"}
	}
	var body struct {
		ReturnURL string `json:"returnUrl"`
		Lifecycle string `json:"accountLifecycle"`
	}
	if e = decode(r, &body); e != nil {
		return e
	}
	if body.Lifecycle != "1" {
		return lifecycleError()
	}
	if !validReturn(body.ReturnURL) {
		return bad
	}
	state, e := random(24)
	if e != nil {
		return e
	}
	ctx := r.Context()
	if _, e = s.DB.Exec(ctx, "DELETE FROM kakao_logins WHERE created_at < now() - interval '15 minutes'"); e != nil {
		return e
	}
	if _, e = s.DB.Exec(ctx, "INSERT INTO kakao_logins(state_hash,user_id,return_url) VALUES($1,$2,$3)", hash(state), user, body.ReturnURL); e != nil {
		return e
	}
	v := url.Values{"response_type": {"code"}, "client_id": {key}, "redirect_uri": {callbackURL()}, "state": {state}}
	writeJSON(w, 200, map[string]any{"url": "https://kauth.kakao.com/oauth/authorize?" + v.Encode()})
	return nil
}
func (s *Server) exchange(code string) (kakaoUser, error) {
	form := url.Values{"grant_type": {"authorization_code"}, "client_id": {kakaoLoginKey()}, "redirect_uri": {callbackURL()}, "code": {code}}
	if v := os.Getenv("KAKAO_CLIENT_SECRET"); v != "" {
		form.Set("client_secret", v)
	}
	res, e := s.HTTP.PostForm("https://kauth.kakao.com/oauth/token", form)
	if e != nil {
		return kakaoUser{}, e
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return kakaoUser{}, fmt.Errorf("kakao token status %d", res.StatusCode)
	}
	var tok struct {
		Access string `json:"access_token"`
	}
	if e = json.NewDecoder(res.Body).Decode(&tok); e != nil || tok.Access == "" {
		return kakaoUser{}, fmt.Errorf("invalid kakao token")
	}
	return s.kakaoMe(tok.Access)
}

type kakaoUser struct{ Subject, Nickname, Email string }

// 카카오 사용자 정보(회원번호·닉네임, 확인된 이메일이 있으면 이메일)
func (s *Server) kakaoMe(access string) (kakaoUser, error) {
	req, e := http.NewRequest("GET", "https://kapi.kakao.com/v2/user/me", nil)
	if e != nil {
		return kakaoUser{}, e
	}
	req.Header.Set("Authorization", "Bearer "+access)
	res, e := s.HTTP.Do(req)
	if e != nil {
		return kakaoUser{}, e
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return kakaoUser{}, fmt.Errorf("kakao me status %d", res.StatusCode)
	}
	var who struct {
		ID      json.Number `json:"id"`
		Account struct {
			Profile struct {
				Nickname string `json:"nickname"`
			} `json:"profile"`
			Email    string `json:"email"`
			Valid    bool   `json:"is_email_valid"`
			Verified bool   `json:"is_email_verified"`
		} `json:"kakao_account"`
		Properties struct {
			Nickname string `json:"nickname"`
		} `json:"properties"`
	}
	if e = json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(&who); e != nil || who.ID == "" {
		return kakaoUser{}, fmt.Errorf("invalid kakao identity")
	}
	u := kakaoUser{Subject: string(who.ID), Nickname: who.Account.Profile.Nickname}
	if u.Nickname == "" {
		u.Nickname = who.Properties.Nickname
	}
	if who.Account.Valid && who.Account.Verified {
		u.Email = cleanEmail(who.Account.Email)
	}
	return u, nil
}

// 앱 안 카카오 로그인(SDK)의 액세스 토큰: 우리 앱(KAKAO_APP_ID)에 발급된 토큰인지 먼저 보고 사용자 정보를 받는다
func (s *Server) kakaoNative(access string) (kakaoUser, error) {
	if access == "" || len(access) > 4096 {
		return kakaoUser{}, fmt.Errorf("invalid kakao token")
	}
	req, e := http.NewRequest("GET", "https://kapi.kakao.com/v1/user/access_token_info", nil)
	if e != nil {
		return kakaoUser{}, e
	}
	req.Header.Set("Authorization", "Bearer "+access)
	res, e := s.HTTP.Do(req)
	if e != nil {
		return kakaoUser{}, e
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return kakaoUser{}, fmt.Errorf("kakao token info status %d", res.StatusCode)
	}
	var info struct {
		ID    json.Number `json:"id"`
		AppID json.Number `json:"app_id"`
	}
	if e = json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(&info); e != nil || info.ID == "" || string(info.AppID) != os.Getenv("KAKAO_APP_ID") {
		return kakaoUser{}, fmt.Errorf("kakao token for another app")
	}
	u, e := s.kakaoMe(access)
	if e != nil || u.Subject != string(info.ID) {
		return kakaoUser{}, fmt.Errorf("invalid kakao identity")
	}
	return u, nil
}

func cleanEmail(v string) string {
	v = strings.ToLower(strings.TrimSpace(v))
	if len(v) > 254 || !strings.Contains(v, "@") {
		return ""
	}
	return v
}
func (s *Server) kakaoCallback(w http.ResponseWriter, r *http.Request) error {
	state := r.URL.Query().Get("state")
	if state == "" || len(state) > 200 {
		return expired
	}
	ctx := r.Context()
	var user int64
	var ret string
	e := s.DB.QueryRow(ctx, "UPDATE kakao_logins SET exchange_started=true WHERE state_hash=$1 AND exchange_started=false AND ticket_hash IS NULL AND created_at>now()-interval '10 minutes' RETURNING user_id,return_url", hash(state)).Scan(&user, &ret)
	if errors.Is(e, pgx.ErrNoRows) {
		return expired
	}
	if e != nil {
		return e
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	code := r.URL.Query().Get("code")
	if r.URL.Query().Get("error") != "" || code == "" {
		_, e = s.DB.Exec(ctx, "DELETE FROM kakao_logins WHERE state_hash=$1", hash(state))
		if e != nil {
			return e
		}
		http.Redirect(w, r, redirectParam(ret, "error", "denied"), 302)
		return nil
	}
	who, e := s.exchange(code)
	if e != nil {
		_, e = s.DB.Exec(ctx, "DELETE FROM kakao_logins WHERE state_hash=$1", hash(state))
		if e != nil {
			return e
		}
		http.Redirect(w, r, redirectParam(ret, "error", "failed"), 302)
		return nil
	}
	tx, e := s.DB.Begin(ctx)
	if e != nil {
		return e
	}
	defer tx.Rollback(ctx)
	result, e := linkIdentity(ctx, tx, "kakao", who.Subject, who.Email, who.Nickname, user)
	if e != nil {
		return e
	}
	ticket, e := random(24)
	if e != nil {
		return e
	}
	tag, e := tx.Exec(ctx, "UPDATE kakao_logins SET ticket_hash=$1,result_user_id=$2 WHERE state_hash=$3 AND ticket_hash IS NULL", hash(ticket), result, hash(state))
	if e != nil {
		return e
	}
	if tag.RowsAffected() != 1 {
		return expired
	}
	if e = tx.Commit(ctx); e != nil {
		return e
	}
	http.Redirect(w, r, redirectParam(ret, "ticket", ticket), 302)
	return nil
}
func (s *Server) kakaoClaim(w http.ResponseWriter, r *http.Request) error {
	user, e := s.user(r)
	if e != nil {
		return e
	}
	var body struct {
		Ticket string `json:"ticket"`
	}
	if e = decode(r, &body); e != nil {
		return e
	}
	if body.Ticket == "" || len(body.Ticket) > 200 {
		return bad
	}
	ctx := r.Context()
	tx, e := s.DB.Begin(ctx)
	if e != nil {
		return e
	}
	defer tx.Rollback(ctx)
	var result int64
	e = tx.QueryRow(ctx, "DELETE FROM kakao_logins WHERE ticket_hash=$1 AND user_id=$2 AND created_at>now()-interval '10 minutes' RETURNING result_user_id", hash(body.Ticket), user).Scan(&result)
	if errors.Is(e, pgx.ErrNoRows) {
		return expired
	}
	if e != nil {
		return e
	}
	if e = recordSwitch(ctx, tx, user, result); e != nil {
		return e
	}
	token, e := issueToken(ctx, tx, result)
	if e != nil {
		return e
	}
	var nick string
	if e = tx.QueryRow(ctx, "SELECT COALESCE(nickname,'') FROM users WHERE id=$1", result).Scan(&nick); e != nil {
		return e
	}
	if e = tx.Commit(ctx); e != nil {
		return e
	}
	writeJSON(w, 200, map[string]any{"userId": result, "token": token, "switched": user != result, "nickname": nick})
	return nil
}
