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
	"github.com/jackc/pgx/v5/pgxpool"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

func TestAppleLogin(t *testing.T) {
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

	clientKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(clientKey)
	t.Setenv("APPLE_PRIVATE_KEY", string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})))
	t.Setenv("APPLE_CLIENT_ID", "client-test")
	t.Setenv("APPLE_TEAM_ID", "TEAM")
	t.Setenv("APPLE_KEY_ID", "KEY")
	t.Setenv("APPLE_TOKEN_ENCRYPTION_KEY", base64.StdEncoding.EncodeToString(make([]byte, 32)))
	t.Setenv("PUBLIC_BASE_URL", "https://api.example.test")
	t.Setenv("FILE_DIR", t.TempDir())
	t.Setenv("S3_BUCKET", "")
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	otherKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	enc := base64.RawURLEncoding.EncodeToString
	exponent := big.NewInt(int64(key.E)).Bytes()
	jwks, _ := json.Marshal(map[string]any{"keys": []any{map[string]any{"kty": "RSA", "kid": "key1", "use": "sig", "alg": "RS256", "n": enc(key.N.Bytes()), "e": enc(exponent)}}})
	nonce := ""
	subject := "apple-" + time.Now().Format("150405.000000000")
	badNonce, badAudience, badSignature, expiredToken := false, false, false, false
	sign := func() string {
		header, _ := json.Marshal(map[string]any{"alg": "RS256", "kid": "key1", "typ": "JWT"})
		n := nonce
		if badNonce {
			n = "wrong"
		}
		aud := "client-test"
		if badAudience {
			aud = "other-client"
		}
		exp := time.Now().Add(time.Hour).Unix()
		if expiredToken {
			exp = time.Now().Add(-time.Hour).Unix()
		}
		body, _ := json.Marshal(map[string]any{"iss": "https://appleid.apple.com", "sub": subject, "aud": aud, "iat": time.Now().Unix(), "exp": exp, "nonce": n, "name": "Reader"})
		payload := enc(header) + "." + enc(body)
		sum := sha256.Sum256([]byte(payload))
		signingKey := key
		if badSignature {
			signingKey = otherKey
		}
		sig, e := rsa.SignPKCS1v15(rand.Reader, signingKey, crypto.SHA256, sum[:])
		if e != nil {
			t.Fatal(e)
		}
		return payload + "." + enc(sig)
	}
	revoked := false
	s := New(db)
	s.HTTP = &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		body := ""
		switch r.URL.Path {
		case "/auth/token":
			b, _ := json.Marshal(map[string]any{"refresh_token": "refresh-test", "access_token": "test", "token_type": "Bearer", "id_token": sign()})
			body = string(b)
		case "/auth/revoke":
			revoked = true
		case "/auth/keys":
			body = string(jwks)
		default:
			t.Fatalf("unexpected provider host: %s", r.URL.Host)
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{"Content-Type": []string{"application/json"}}}, nil
	})}
	h := s.Handler()
	req := func(method, path, token string, body any) *httptest.ResponseRecorder {
		t.Helper()
		b, _ := json.Marshal(body)
		r := httptest.NewRequest(method, path, bytes.NewReader(b))
		if strings.HasPrefix(path, "/auth/apple/callback?") {
			u, _ := url.Parse(path)
			r = httptest.NewRequest("POST", u.Path, strings.NewReader(u.RawQuery))
			r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		}
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	parse := func(w *httptest.ResponseRecorder) map[string]any {
		var v map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
			t.Fatalf("response: %s", w.Body)
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
	login := func(token string) string {
		w := req("POST", "/auth/apple/start", token, map[string]string{"returnUrl": "chaekjang://auth/apple", "accountLifecycle": "1"})
		if w.Code != 200 {
			t.Fatalf("start %d %s", w.Code, w.Body)
		}
		auth, e := url.Parse(parse(w)["url"].(string))
		if e != nil {
			t.Fatal(e)
		}
		nonce = auth.Query().Get("nonce")
		state := auth.Query().Get("state")
		if nonce == "" || auth.Query().Get("response_mode") != "form_post" {
			t.Fatal("missing form_post or nonce")
		}
		w = req("GET", "/auth/apple/callback?state="+url.QueryEscape(state)+"&code=test", "", nil)
		if w.Code != 302 {
			t.Fatalf("callback %d %s", w.Code, w.Body)
		}
		if replay := req("GET", "/auth/apple/callback?state="+url.QueryEscape(state)+"&code=test", "", nil); replay.Code != 400 {
			t.Fatalf("state replay %d", replay.Code)
		}
		target, e := url.Parse(w.Header().Get("Location"))
		if e != nil {
			t.Fatal(e)
		}
		if badNonce || badAudience || badSignature || expiredToken {
			if target.Query().Get("error") != "failed" {
				t.Fatal("invalid nonce accepted")
			}
			return ""
		}
		ticket := target.Query().Get("ticket")
		if ticket == "" {
			t.Fatalf("missing ticket: %s", w.Header().Get("Location"))
		}
		return ticket
	}
	first, second := account(), account()
	badNonce = true
	login(first)
	badNonce = false
	badAudience = true
	login(first)
	badAudience = false
	badSignature = true
	login(first)
	badSignature = false
	expiredToken = true
	login(first)
	expiredToken = false
	ticket := login(first)
	if w := req("POST", "/auth/apple/claim", second, map[string]string{"ticket": ticket}); w.Code != 400 {
		t.Fatalf("foreign claim %d", w.Code)
	}
	w := req("POST", "/auth/apple/claim", first, map[string]string{"ticket": ticket})
	if w.Code != 200 || parse(w)["switched"] != false {
		t.Fatalf("first claim %d %s", w.Code, w.Body)
	}
	if w = req("POST", "/auth/apple/claim", first, map[string]string{"ticket": ticket}); w.Code != 400 {
		t.Fatalf("reused ticket %d", w.Code)
	}
	ticket = login(second)
	w = req("POST", "/auth/apple/claim", second, map[string]string{"ticket": ticket})
	if w.Code != 200 || parse(w)["switched"] != true {
		t.Fatalf("switched %d %s", w.Code, w.Body)
	}
	if w = req("GET", "/me", second, nil); w.Code != 401 {
		t.Fatalf("old anonymous token remains valid: %d", w.Code)
	}
	if w = req("POST", "/auth/apple/start", first, map[string]string{"returnUrl": "chaekjang://auth/apple"}); w.Code != 426 {
		t.Fatalf("old client accepted: %d", w.Code)
	}
	if w = req("POST", "/auth/apple/start", first, map[string]string{"returnUrl": "https://attacker.example", "accountLifecycle": "1"}); w.Code != 400 {
		t.Fatalf("invalid return %d", w.Code)
	}
	if w = req("DELETE", "/me", first, map[string]string{"confirmation": "DELETE"}); w.Code != 202 {
		t.Fatalf("delete %d %s", w.Code, w.Body)
	}
	if err = s.processDeletionJobs(ctx); err != nil {
		t.Fatal(err)
	}
	if !revoked {
		t.Fatal("Apple grant not revoked")
	}
	if w = req("GET", "/me", first, nil); w.Code != 401 {
		t.Fatal("deleted session still usable")
	}

}
