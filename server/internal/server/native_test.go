package server

import (
	"bytes"
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// 앱 안 로그인(SDK 토큰을 서버가 확인): 카카오 app_id, Google aud·azp, Apple nonce·코드 교환·번들 ID로 연결 끊기, 이메일 저장
func TestNativeLogin(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err = Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PUBLIC_BASE_URL", "https://api.example.test")
	t.Setenv("FILE_DIR", t.TempDir())
	t.Setenv("S3_BUCKET", "")
	t.Setenv("KAKAO_REST_KEY", "test")
	t.Setenv("KAKAO_ADMIN_KEY", "admin-test")
	t.Setenv("KAKAO_APP_ID", "1234")
	t.Setenv("GOOGLE_CLIENT_ID", "555-web.apps.googleusercontent.com")
	t.Setenv("GOOGLE_CLIENT_SECRET", "secret")
	clientKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(clientKey)
	t.Setenv("APPLE_PRIVATE_KEY", string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})))
	t.Setenv("APPLE_CLIENT_ID", "web.services.id")
	t.Setenv("APPLE_TEAM_ID", "TEAM")
	t.Setenv("APPLE_KEY_ID", "KEY")
	t.Setenv("APPLE_TOKEN_ENCRYPTION_KEY", base64.StdEncoding.EncodeToString(make([]byte, 32)))

	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	enc := base64.RawURLEncoding.EncodeToString
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]any{"kty": "RSA", "kid": "k", "use": "sig", "alg": "RS256", "n": enc(key.N.Bytes()), "e": enc(big.NewInt(int64(key.E)).Bytes())}}})
	sign := func(claims map[string]any) string {
		header, _ := json.Marshal(map[string]any{"alg": "RS256", "kid": "k", "typ": "JWT"})
		body, _ := json.Marshal(claims)
		payload := enc(header) + "." + enc(body)
		sum := sha256.Sum256([]byte(payload))
		sig, _ := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, sum[:])
		return payload + "." + enc(sig)
	}
	now := time.Now().Unix()
	stamp := fmt.Sprintf("%d", time.Now().UnixNano())
	kakaoID, kakaoApp := stamp[len(stamp)-12:], "1234"
	appleSub := "apple-native-" + stamp
	appleServerToken := ""
	var revokeClient string
	s := New(db)
	s.HTTP = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		body, code := "", 200
		switch {
		case r.URL.Host == "kapi.kakao.com" && r.URL.Path == "/v1/user/access_token_info":
			body = `{"id":` + kakaoID + `,"expires_in":3600,"app_id":` + kakaoApp + `}`
		case r.URL.Host == "kapi.kakao.com" && r.URL.Path == "/v2/user/me":
			body = `{"id":` + kakaoID + `,"kakao_account":{"profile":{"nickname":"카카오 독자"},"email":"Reader@Kakao.test","is_email_valid":true,"is_email_verified":true}}`
		case r.URL.Host == "kapi.kakao.com" && r.URL.Path == "/v1/user/unlink":
			body = `{"id":` + kakaoID + `}`
		case r.URL.Host == "www.googleapis.com", r.URL.Path == "/auth/keys":
			body = string(jwks)
		case r.URL.Path == "/auth/token":
			_ = r.ParseForm()
			if r.Form.Get("client_id") != "app.covebook" || r.Form.Get("redirect_uri") != "" {
				code = 400
			}
			b, _ := json.Marshal(map[string]any{"refresh_token": "refresh-native", "access_token": "a", "token_type": "Bearer", "id_token": appleServerToken})
			body = string(b)
		case r.URL.Path == "/auth/revoke":
			_ = r.ParseForm()
			revokeClient = r.Form.Get("client_id")
		default:
			t.Fatalf("unexpected request %s", r.URL)
		}
		return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{"Content-Type": []string{"application/json"}}}, nil
	})}
	h := s.Handler()
	req := func(method, path, token string, body any) *httptest.ResponseRecorder {
		t.Helper()
		b, _ := json.Marshal(body)
		r := httptest.NewRequest(method, path, bytes.NewReader(b))
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	parse := func(w *httptest.ResponseRecorder) map[string]any {
		var v map[string]any
		if e := json.Unmarshal(w.Body.Bytes(), &v); e != nil {
			t.Fatalf("response %s", w.Body)
		}
		return v
	}
	account := func() string {
		w := req("POST", "/auth/device", "", nil)
		if w.Code != 201 {
			t.Fatal(w.Body)
		}
		return parse(w)["token"].(string)
	}
	if p := parse(req("GET", "/auth/providers", "", nil)); p["native"] != true {
		t.Fatalf("providers must announce native login: %v", p)
	}

	// 카카오: 다른 앱의 토큰은 거절, 우리 앱 토큰은 연결 + 이메일
	first := account()
	if w := req("POST", "/auth/kakao/native", first, map[string]string{"accessToken": "t"}); w.Code != 426 {
		t.Fatalf("old client accepted %d", w.Code)
	}
	kakaoApp = "9999"
	if w := req("POST", "/auth/kakao/native", first, map[string]string{"accessToken": "t", "accountLifecycle": "1"}); w.Code != 401 {
		t.Fatalf("foreign app token accepted %d %s", w.Code, w.Body)
	}
	kakaoApp = "1234"
	w := req("POST", "/auth/kakao/native", first, map[string]string{"accessToken": "t", "accountLifecycle": "1"})
	if w.Code != 200 || parse(w)["switched"] != false || parse(w)["nickname"] != "카카오 독자" {
		t.Fatalf("kakao native %d %s", w.Code, w.Body)
	}
	first = parse(w)["token"].(string)

	// Google: aud는 웹 클라이언트, azp는 같은 프로젝트(555-)의 Android 클라이언트
	googleToken := func(azp string) string {
		return sign(map[string]any{"iss": "https://accounts.google.com", "sub": "g-" + stamp, "aud": "555-web.apps.googleusercontent.com", "azp": azp, "iat": now, "exp": now + 3600, "email": "reader@gmail.test", "email_verified": true, "name": "구글 독자"})
	}
	if w = req("POST", "/auth/google/native", first, map[string]string{"idToken": googleToken("777-other.apps.googleusercontent.com"), "accountLifecycle": "1"}); w.Code != 401 {
		t.Fatalf("other project azp accepted %d", w.Code)
	}
	if w = req("POST", "/auth/google/native", first, map[string]string{"idToken": "not-a-jwt", "accountLifecycle": "1"}); w.Code != 401 {
		t.Fatalf("garbage token accepted %d", w.Code)
	}
	w = req("POST", "/auth/google/native", first, map[string]string{"idToken": googleToken("555-android.apps.googleusercontent.com"), "accountLifecycle": "1"})
	if w.Code != 200 || parse(w)["switched"] != false {
		t.Fatalf("google native %d %s", w.Code, w.Body)
	}
	first = parse(w)["token"].(string)

	// Apple(iOS): 기기 토큰의 nonce가 맞아야 하고, 코드는 번들 ID 클라이언트로 교환한다
	appleToken := func(nonce string) string {
		return sign(map[string]any{"iss": "https://appleid.apple.com", "sub": appleSub, "aud": "app.covebook", "iat": now, "exp": now + 600, "nonce": nonce, "email": "abc@privaterelay.appleid.com", "email_verified": "true"})
	}
	appleServerToken = appleToken("")
	if w = req("POST", "/auth/apple/native", first, map[string]string{"idToken": appleToken("n1"), "authorizationCode": "c", "nonce": "n2", "accountLifecycle": "1"}); w.Code != 401 {
		t.Fatalf("wrong nonce accepted %d", w.Code)
	}
	w = req("POST", "/auth/apple/native", first, map[string]string{"idToken": appleToken("n1"), "authorizationCode": "c", "nonce": "n1", "name": "애플 독자", "accountLifecycle": "1"})
	if w.Code != 200 || parse(w)["switched"] != false || parse(w)["nickname"] != "애플 독자" {
		t.Fatalf("apple native %d %s", w.Code, w.Body)
	}
	first = parse(w)["token"].(string)

	me := parse(req("GET", "/me", first, nil))
	emails, _ := me["emails"].(map[string]any)
	if me["kakao"] != true || me["google"] != true || me["apple"] != true || emails["kakao"] != "reader@kakao.test" || emails["google"] != "reader@gmail.test" || emails["apple"] != "abc@privaterelay.appleid.com" {
		t.Fatalf("me %v", me)
	}

	// 다른 기기에서 같은 카카오로 로그인하면 그 계정으로 바뀐다
	second := account()
	w = req("POST", "/auth/kakao/native", second, map[string]string{"accessToken": "t", "accountLifecycle": "1"})
	if w.Code != 200 || parse(w)["switched"] != true {
		t.Fatalf("switch %d %s", w.Code, w.Body)
	}
	if w = req("GET", "/me", second, nil); w.Code != 401 {
		t.Fatalf("old device token still valid %d", w.Code)
	}

	// 회원탈퇴: 앱 안에서 받은 Apple 토큰은 번들 ID로 끊는다
	if w = req("DELETE", "/me", first, map[string]string{"confirmation": "DELETE"}); w.Code != 202 {
		t.Fatalf("delete %d %s", w.Code, w.Body)
	}
	if err = s.processDeletionJobs(ctx); err != nil {
		t.Fatal(err)
	}
	if revokeClient != "app.covebook" {
		t.Fatalf("apple revoke client %q", revokeClient)
	}
}

// 소개 홈페이지·개인정보 처리방침(Google 브랜딩 인증용)은 DB 없이 열린다
func TestSitePages(t *testing.T) {
	h := New(nil).Handler()
	for path, want := range map[string]string{"/": "책장 한켠", "/privacy": "개인정보 처리방침", "/icon.png": "\x89PNG"} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if w.Code != 200 || !strings.Contains(w.Body.String(), want) {
			t.Fatalf("%s %d", path, w.Code)
		}
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/nope", nil))
	if w.Code != 404 {
		t.Fatalf("unknown path %d", w.Code)
	}
}
