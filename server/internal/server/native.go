package server

import (
	"context"
	"crypto/subtle"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/jackc/pgx/v5"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/appleauth"
)

// 앱 안 로그인(공급자 SDK). 앱이 SDK로 받은 토큰을 보내면 서버가 공급자에게 직접 확인하고, 브라우저 흐름의
// callback과 claim을 한 거래로 처리한다(2026-11-18 사용자: 카카오톡·Apple·Google 앱 안 로그인).
//   kakao: accessToken  → access_token_info의 app_id가 KAKAO_APP_ID인지 본 뒤 사용자 정보
//   google: idToken     → Google 서명·aud(GOOGLE_CLIENT_ID, 앱의 serverClientId)·azp(같은 프로젝트의 클라이언트)
//   apple: idToken+authorizationCode+nonce → 기기 토큰의 nonce, 번들 ID 클라이언트로 코드 교환(회원탈퇴 때 끊을 갱신 토큰)

var loginFailed = apiError{401, "login_failed", "로그인을 확인하지 못했어요. 다시 시도해 주세요"}

// 로그인을 계정에 잇는다: 처음 보는 로그인이면 source 계정에 붙이고, 이미 있으면 그 계정. 이메일·닉네임은 새 값이 있을 때만 바꾼다
func linkIdentity(ctx context.Context, tx pgx.Tx, provider, subject, email, nickname string, source int64) (int64, error) {
	var mail any
	if email != "" {
		mail = email
	}
	var result int64
	if err := tx.QueryRow(ctx, "INSERT INTO auth_identities(provider,subject,user_id,email) VALUES($1,$2,$3,$4) ON CONFLICT (provider,subject) DO UPDATE SET email=COALESCE(EXCLUDED.email,auth_identities.email) RETURNING user_id", provider, subject, source, mail).Scan(&result); err != nil {
		return 0, err
	}
	if nickname != "" {
		if _, err := tx.Exec(ctx, "UPDATE users SET nickname=$1 WHERE id=$2", nickname, result); err != nil {
			return 0, err
		}
	}
	return result, nil
}

func (s *Server) nativeLogin(w http.ResponseWriter, r *http.Request) error {
	provider := r.PathValue("provider")
	source, err := s.user(r)
	if err != nil {
		return err
	}
	var body struct {
		Lifecycle   string `json:"accountLifecycle"`
		AccessToken string `json:"accessToken"`
		IDToken     string `json:"idToken"`
		Code        string `json:"authorizationCode"`
		Nonce       string `json:"nonce"`
		Name        string `json:"name"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if body.Lifecycle != "1" {
		return lifecycleError()
	}
	ctx := r.Context()
	var subject, email, nickname, sealed string
	switch provider {
	case "kakao":
		if !kakaoEnabled() {
			return apiError{503, "not_configured", "카카오 로그인이 아직 준비되지 않았어요"}
		}
		u, e := s.kakaoNative(body.AccessToken)
		if e != nil {
			return loginFailed
		}
		subject, email, nickname = u.Subject, u.Email, u.Nickname
	case "google":
		if !googleEnabled() {
			return apiError{503, "not_configured", "Google 로그인이 아직 준비되지 않았어요"}
		}
		u, e := s.googleNative(ctx, body.IDToken)
		if e != nil {
			return loginFailed
		}
		subject, email, nickname = u.Subject, u.Email, u.Nickname
	case "apple":
		client, e := appleauth.NativeFromEnv(s.HTTP)
		if e != nil || !s.appleEnabled() {
			return apiError{503, "not_configured", "Apple 로그인이 아직 준비되지 않았어요"}
		}
		id, e := client.ExchangeNative(ctx, body.Code, body.IDToken, body.Nonce)
		if e != nil {
			return loginFailed
		}
		// Apple은 이름을 처음 로그인할 때 기기에만 한 번 준다
		subject, email, sealed, nickname = id.Subject, id.Email, id.SealedRefresh, trimName(body.Name)
	default:
		return apiError{404, "not_found", "없는 로그인 방법이에요"}
	}
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	result, err := linkIdentity(ctx, tx, provider, subject, email, nickname, source)
	if err != nil {
		return err
	}
	if provider == "apple" {
		if _, err = tx.Exec(ctx, "INSERT INTO apple_tokens(user_id,subject,sealed_refresh,client_id) VALUES($1,$2,$3,$4) ON CONFLICT(subject) DO UPDATE SET sealed_refresh=EXCLUDED.sealed_refresh,client_id=EXCLUDED.client_id", result, subject, sealed, appleauth.NativeID()); err != nil {
			return err
		}
	}
	if err = recordSwitch(ctx, tx, source, result); err != nil {
		return err
	}
	token, err := issueToken(ctx, tx, result)
	if err != nil {
		return err
	}
	var nick string
	if err = tx.QueryRow(ctx, "SELECT COALESCE(nickname,'') FROM users WHERE id=$1", result).Scan(&nick); err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	writeJSON(w, 200, map[string]any{"userId": result, "token": token, "switched": result != source, "nickname": nick})
	return nil
}

func trimName(v string) string {
	n := []rune(strings.TrimSpace(v))
	if len(n) > 200 {
		n = n[:200]
	}
	return string(n)
}

type googleIdentity struct{ Subject, Nickname, Email string }

func (s *Server) googleIDVerifier() *oidc.IDTokenVerifier {
	s.googleOnce.Do(func() {
		keyCtx := oidc.ClientContext(context.Background(), s.HTTP)
		keys := oidc.NewRemoteKeySet(keyCtx, "https://www.googleapis.com/oauth2/v3/certs")
		s.googleVerifier = oidc.NewVerifier("https://accounts.google.com", keys, &oidc.Config{ClientID: os.Getenv("GOOGLE_CLIENT_ID"), SupportedSigningAlgs: []string{"RS256"}})
	})
	return s.googleVerifier
}

type googleClaims struct {
	Nonce    string `json:"nonce"`
	Name     string `json:"name"`
	Azp      string `json:"azp"`
	Email    string `json:"email"`
	Verified bool   `json:"email_verified"`
}

func (c googleClaims) identity(subject string) googleIdentity {
	g := googleIdentity{Subject: subject, Nickname: trimName(c.Name)}
	if c.Verified {
		g.Email = cleanEmail(c.Email)
	}
	return g
}

// 앱 안 Google 로그인(Android 자격 증명 관리자)의 ID 토큰. aud는 serverClientId(웹 클라이언트), azp는 같은 프로젝트의 Android 클라이언트다
func (s *Server) googleNative(ctx context.Context, raw string) (googleIdentity, error) {
	if raw == "" || len(raw) > 16000 {
		return googleIdentity{}, errors.New("google_id_token_missing")
	}
	id, err := s.googleIDVerifier().Verify(ctx, raw)
	if err != nil {
		return googleIdentity{}, errors.New("google_id_token_invalid")
	}
	var claims googleClaims
	project, _, _ := strings.Cut(os.Getenv("GOOGLE_CLIENT_ID"), "-")
	if err = id.Claims(&claims); err != nil || id.Subject == "" || len(id.Subject) > 255 || id.IssuedAt.IsZero() || id.IssuedAt.After(time.Now().Add(time.Minute)) || project == "" || subtle.ConstantTimeCompare([]byte(strings.SplitN(claims.Azp, "-", 2)[0]), []byte(project)) != 1 {
		return googleIdentity{}, errors.New("google_id_token_invalid")
	}
	return claims.identity(id.Subject), nil
}
