// Package appleauth implements Apple's web authorization-code flow and the in-app (iOS) flow. Secrets stay on the server.
package appleauth

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
)

const issuer = "https://appleid.apple.com"

var keysets sync.Map

type Client struct {
	ID, Team, KeyID, Redirect string
	Key                       *ecdsa.PrivateKey
	SealKey                   []byte
	HTTP                      *http.Client
	verifier                  *oidc.IDTokenVerifier
}
type Identity struct{ Subject, Email, SealedRefresh string }

// FromEnv is the web client (Services ID, APPLE_CLIENT_ID) that uses the https callback.
func FromEnv(redirect string, httpClient *http.Client) (*Client, error) {
	u, err := url.Parse(redirect)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		return nil, errors.New("apple_not_configured")
	}
	return newClient(os.Getenv("APPLE_CLIENT_ID"), redirect, httpClient)
}

// NativeID is the client of in-app Sign in with Apple on iOS: the app's bundle ID.
func NativeID() string {
	if v := os.Getenv("APPLE_BUNDLE_ID"); v != "" {
		return v
	}
	return "app.covebook"
}

// NativeFromEnv is the in-app (iOS) client. Same team and key as the web client, but tokens are issued to the bundle ID.
func NativeFromEnv(httpClient *http.Client) (*Client, error) {
	if os.Getenv("APPLE_CLIENT_ID") == "" {
		return nil, errors.New("apple_not_configured")
	}
	return newClient(NativeID(), "", httpClient)
}

func newClient(id, redirect string, httpClient *http.Client) (*Client, error) {
	var err error
	c := &Client{ID: id, Team: os.Getenv("APPLE_TEAM_ID"), KeyID: os.Getenv("APPLE_KEY_ID"), Redirect: redirect, HTTP: httpClient}
	if c.ID == "" || c.Team == "" || c.KeyID == "" {
		return nil, errors.New("apple_not_configured")
	}
	block, _ := pem.Decode([]byte(strings.ReplaceAll(os.Getenv("APPLE_PRIVATE_KEY"), `\n`, "\n")))
	if block == nil {
		return nil, errors.New("apple_key_invalid")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.New("apple_key_invalid")
	}
	c.Key, _ = key.(*ecdsa.PrivateKey)
	if c.Key == nil || c.Key.Curve != elliptic.P256() {
		return nil, errors.New("apple_key_invalid")
	}
	c.SealKey, err = base64.StdEncoding.DecodeString(os.Getenv("APPLE_TOKEN_ENCRYPTION_KEY"))
	if err != nil || len(c.SealKey) != 32 {
		return nil, errors.New("apple_encryption_key_invalid")
	}
	if c.HTTP == nil {
		c.HTTP = &http.Client{Timeout: 10 * time.Second}
	}
	keys, _ := keysets.LoadOrStore(c.HTTP, oidc.NewRemoteKeySet(oidc.ClientContext(context.Background(), c.HTTP), issuer+"/auth/keys"))
	c.verifier = oidc.NewVerifier(issuer, keys.(oidc.KeySet), &oidc.Config{ClientID: c.ID, SupportedSigningAlgs: []string{oidc.RS256}})
	return c, nil
}

func (c *Client) AuthorizationURL(state, nonce string) string {
	return issuer + "/auth/authorize?" + url.Values{"client_id": {c.ID}, "redirect_uri": {c.Redirect}, "response_type": {"code"}, "response_mode": {"form_post"}, "scope": {"email"}, "state": {state}, "nonce": {nonce}}.Encode()
}

func (c *Client) secret() (string, error) {
	enc := func(v any) string { b, _ := json.Marshal(v); return base64.RawURLEncoding.EncodeToString(b) }
	now := time.Now().Unix()
	raw := enc(map[string]any{"alg": "ES256", "kid": c.KeyID, "typ": "JWT"}) + "." + enc(map[string]any{"iss": c.Team, "sub": c.ID, "aud": issuer, "iat": now, "exp": now + 300})
	sum := sha256.Sum256([]byte(raw))
	r, s, err := ecdsa.Sign(rand.Reader, c.Key, sum[:])
	if err != nil {
		return "", err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return raw + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

func (c *Client) post(ctx context.Context, path string, form url.Values, result any) error {
	secret, err := c.secret()
	if err != nil {
		return err
	}
	form.Set("client_id", c.ID)
	form.Set("client_secret", secret)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, issuer+path, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := c.HTTP.Do(req)
	if err != nil {
		return errors.New("apple_unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return errors.New("apple_request_failed")
	}
	if result != nil && json.NewDecoder(io.LimitReader(res.Body, 65536)).Decode(result) != nil {
		return errors.New("apple_response_invalid")
	}
	return nil
}

// expectedNonceHash is SHA-256 of the one-time nonce stored with the OAuth state.
func (c *Client) Exchange(ctx context.Context, code string, expectedNonceHash []byte) (Identity, error) {
	if code == "" || len(code) > 4096 || len(expectedNonceHash) != 32 {
		return Identity{}, errors.New("apple_callback_invalid")
	}
	var token struct {
		IDToken string `json:"id_token"`
		Refresh string `json:"refresh_token"`
	}
	if err := c.post(ctx, "/auth/token", url.Values{"grant_type": {"authorization_code"}, "code": {code}, "redirect_uri": {c.Redirect}}, &token); err != nil {
		return Identity{}, err
	}
	if len(token.IDToken) > 32768 || token.Refresh == "" {
		return Identity{}, errors.New("apple_token_missing")
	}
	id, err := c.verifier.Verify(ctx, token.IDToken)
	if err != nil {
		return Identity{}, errors.New("apple_token_invalid")
	}
	sum := sha256.Sum256([]byte(id.Nonce))
	if len(id.Audience) != 1 || id.Audience[0] != c.ID || id.Subject == "" || len(id.Subject) > 255 || id.Nonce == "" || subtle.ConstantTimeCompare(sum[:], expectedNonceHash) != 1 || id.IssuedAt.IsZero() || id.IssuedAt.After(time.Now().Add(time.Minute)) {
		return Identity{}, errors.New("apple_claims_invalid")
	}
	out := Identity{Subject: id.Subject, Email: verifiedEmail(id)}
	out.SealedRefresh, err = c.seal(id.Subject, token.Refresh)
	return out, err
}

// ExchangeNative checks an in-app sign-in: identityToken came from the device (its nonce must be the one the app
// sent to Apple), and the one-time authorization code is redeemed here for the refresh token used to revoke on account deletion.
func (c *Client) ExchangeNative(ctx context.Context, code, identityToken, nonce string) (Identity, error) {
	if code == "" || len(code) > 4096 || identityToken == "" || len(identityToken) > 32768 || nonce == "" || len(nonce) > 256 {
		return Identity{}, errors.New("apple_native_invalid")
	}
	device, err := c.verifier.Verify(ctx, identityToken)
	if err != nil || len(device.Audience) != 1 || device.Audience[0] != c.ID || device.Subject == "" || len(device.Subject) > 255 || device.IssuedAt.IsZero() || device.IssuedAt.After(time.Now().Add(time.Minute)) || subtle.ConstantTimeCompare([]byte(device.Nonce), []byte(nonce)) != 1 {
		return Identity{}, errors.New("apple_token_invalid")
	}
	var token struct {
		IDToken string `json:"id_token"`
		Refresh string `json:"refresh_token"`
	}
	if err = c.post(ctx, "/auth/token", url.Values{"grant_type": {"authorization_code"}, "code": {code}}, &token); err != nil {
		return Identity{}, err
	}
	if token.IDToken == "" || len(token.IDToken) > 32768 || token.Refresh == "" {
		return Identity{}, errors.New("apple_token_missing")
	}
	server, err := c.verifier.Verify(ctx, token.IDToken)
	if err != nil || server.Subject != device.Subject {
		return Identity{}, errors.New("apple_token_invalid")
	}
	out := Identity{Subject: device.Subject, Email: verifiedEmail(device)}
	out.SealedRefresh, err = c.seal(device.Subject, token.Refresh)
	return out, err
}

func verifiedEmail(id *oidc.IDToken) string {
	var claims struct {
		Email    string          `json:"email"`
		Verified json.RawMessage `json:"email_verified"`
	}
	if id.Claims(&claims) != nil || len(claims.Email) > 254 || !(string(claims.Verified) == "true" || string(claims.Verified) == `"true"`) {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(claims.Email))
}

func (c *Client) aead() (cipher.AEAD, error) {
	b, e := aes.NewCipher(c.SealKey)
	if e != nil {
		return nil, e
	}
	return cipher.NewGCM(b)
}
func (c *Client) seal(subject, token string) (string, error) {
	a, e := c.aead()
	if e != nil {
		return "", e
	}
	n := make([]byte, a.NonceSize())
	if _, e = rand.Read(n); e != nil {
		return "", e
	}
	return base64.StdEncoding.EncodeToString(a.Seal(n, n, []byte(token), []byte(c.ID+":"+subject))), nil
}
func (c *Client) Revoke(ctx context.Context, subject, sealed string) error {
	a, e := c.aead()
	if e != nil {
		return e
	}
	b, e := base64.StdEncoding.DecodeString(sealed)
	if e != nil || len(b) < a.NonceSize() {
		return errors.New("apple_stored_token_invalid")
	}
	token, e := a.Open(nil, b[:a.NonceSize()], b[a.NonceSize():], []byte(c.ID+":"+subject))
	if e != nil {
		return errors.New("apple_stored_token_invalid")
	}
	return c.post(ctx, "/auth/revoke", url.Values{"token": {string(token)}, "token_type_hint": {"refresh_token"}}, nil)
}
