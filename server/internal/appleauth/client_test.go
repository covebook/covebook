package appleauth

import (
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
	"io"
	"math/big"
	"net/http"
	"strings"
	"testing"
	"time"
)

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func jwt(t *testing.T, key *rsa.PrivateKey, claims map[string]any) string {
	t.Helper()
	b, _ := json.Marshal(claims)
	raw := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"RS256","kid":"test"}`)) + "." + base64.RawURLEncoding.EncodeToString(b)
	sum := sha256.Sum256([]byte(raw))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	return raw + "." + base64.RawURLEncoding.EncodeToString(sig)
}
func TestAppleExchangeValidationAndRevocation(t *testing.T) {
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	clientKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	der, _ := x509.MarshalPKCS8PrivateKey(clientKey)
	t.Setenv("APPLE_PRIVATE_KEY", string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})))
	t.Setenv("APPLE_CLIENT_ID", "app.example.web")
	t.Setenv("APPLE_TEAM_ID", "TEAM")
	t.Setenv("APPLE_KEY_ID", "KEY")
	t.Setenv("APPLE_TOKEN_ENCRYPTION_KEY", base64.StdEncoding.EncodeToString(make([]byte, 32)))
	var raw string
	revoked := false
	httpClient := &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		var body string
		switch r.URL.Path {
		case "/auth/keys":
			b, _ := json.Marshal(map[string]any{"keys": []any{map[string]any{"kty": "RSA", "kid": "test", "alg": "RS256", "use": "sig", "n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()), "e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes())}}})
			body = string(b)
		case "/auth/token", "/auth/revoke":
			_ = r.ParseForm()
			if r.PostForm.Get("client_id") != "app.example.web" {
				t.Error("wrong client")
			}
			parts := strings.Split(r.PostForm.Get("client_secret"), ".")
			if len(parts) != 3 {
				t.Fatal("missing client secret")
			}
			sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
			sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
			if len(sig) != 64 || !ecdsa.Verify(&clientKey.PublicKey, sum[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
				t.Fatal("invalid ES256 secret")
			}
			if r.URL.Path == "/auth/revoke" {
				revoked = true
				if r.PostForm.Get("token") != "refresh-secret" || r.PostForm.Get("token_type_hint") != "refresh_token" {
					t.Error("wrong revocation token")
				}
			} else {
				b, _ := json.Marshal(map[string]string{"id_token": raw, "refresh_token": "refresh-secret"})
				body = string(b)
			}
		default:
			t.Fatalf("unexpected request: %s", r.URL.Path)
		}
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body))}, nil
	})}
	c, err := FromEnv("https://example.com/auth/apple/callback", httpClient)
	if err != nil {
		t.Fatal(err)
	}
	nonce := sha256.Sum256([]byte("server-nonce"))
	claims := func() map[string]any {
		return map[string]any{"iss": issuer, "aud": c.ID, "sub": "apple-subject", "iat": time.Now().Unix(), "exp": time.Now().Add(time.Hour).Unix(), "nonce": "server-nonce", "email": "hidden@privaterelay.appleid.com", "email_verified": "true"}
	}
	raw = jwt(t, key, claims())
	id, err := c.Exchange(context.Background(), "one-time-code", nonce[:])
	if err != nil {
		t.Fatal(err)
	}
	if id.Subject != "apple-subject" || id.Email != "hidden@privaterelay.appleid.com" || strings.Contains(id.SealedRefresh, "refresh-secret") {
		t.Fatal("identity or token storage incorrect")
	}
	if err = c.Revoke(context.Background(), id.Subject, id.SealedRefresh); err != nil || !revoked {
		t.Fatal("revocation failed", err)
	}
	if c.Revoke(context.Background(), "other-subject", id.SealedRefresh) == nil {
		t.Fatal("ciphertext accepted for another subject")
	}
	for _, tc := range []struct {
		name, claim string
		value       any
	}{
		{"audience", "aud", "another-app"}, {"issuer", "iss", "https://evil.invalid"}, {"expired", "exp", time.Now().Add(-time.Hour).Unix()},
		{"nonce", "nonce", "other-nonce"}, {"no-subject", "sub", ""}, {"future-issued", "iat", time.Now().Add(time.Hour).Unix()},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := claims()
			m[tc.claim] = tc.value
			raw = jwt(t, key, m)
			if _, err = c.Exchange(context.Background(), "code", nonce[:]); err == nil {
				t.Fatal("invalid token accepted")
			}
		})
	}
	other, _ := rsa.GenerateKey(rand.Reader, 2048)
	raw = jwt(t, other, claims())
	if _, err = c.Exchange(context.Background(), "code", nonce[:]); err == nil {
		t.Fatal("invalid signature accepted")
	}
	m := claims()
	m["email_verified"] = false
	raw = jwt(t, key, m)
	id, err = c.Exchange(context.Background(), "code", nonce[:])
	if err != nil || id.Email != "" {
		t.Fatal("unverified email trusted")
	}
	t.Setenv("APPLE_TOKEN_ENCRYPTION_KEY", "bad")
	if _, err = FromEnv(c.Redirect, httpClient); err == nil {
		t.Fatal("invalid encryption key accepted")
	}
}
