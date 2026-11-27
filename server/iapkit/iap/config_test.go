package iap

import (
	"encoding/base64"
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func TestFromEnv(t *testing.T) {
	// 아무것도 없으면 결제가 꺼진 것이다
	stores, err := FromEnv(env(nil))
	if err != nil || len(stores) != 0 {
		t.Fatalf("빈 환경: %v %v", stores, err)
	}
	// 애플만 설정
	stores, err = FromEnv(env(map[string]string{
		envAppleKey: "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----", envAppleKeyID: "K", envAppleIssuer: "I", envAppleBundle: "app.covebook",
	}))
	if err != nil || stores[RouteApple] == nil || stores[RouteGoogle] != nil {
		t.Fatalf("애플만: %v %v", stores, err)
	}
	// 일부만 있으면 켜지지 않고, 오류에 빠진 이름은 나오되 값은 나오지 않는다
	_, err = FromEnv(env(map[string]string{envAppleKey: "-----BEGIN secret", envAppleKeyID: "K"}))
	if err == nil || !strings.Contains(err.Error(), envAppleIssuer) || strings.Contains(err.Error(), "secret") {
		t.Fatalf("일부 설정: %v", err)
	}
	_, err = FromEnv(env(map[string]string{envGooglePkg: "app.covebook"}))
	if err == nil || !strings.Contains(err.Error(), envGoogleKey) {
		t.Fatalf("구글 일부 설정: %v", err)
	}
	// 구글만 틀려도 제대로 된 애플은 켜진다(오류는 함께 준다)
	stores, err = FromEnv(env(map[string]string{
		envAppleKey: "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----", envAppleKeyID: "K", envAppleIssuer: "I", envAppleBundle: "app.covebook",
		envGooglePkg: "app.covebook",
	}))
	if err == nil || stores[RouteApple] == nil || stores[RouteGoogle] != nil {
		t.Fatalf("구글만 틀림: %v %v", stores, err)
	}
}

func TestDecodeKey(t *testing.T) {
	pem := "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----"
	for name, in := range map[string]string{
		"그대로":    pem,
		"글자 \\n": strings.ReplaceAll(pem, "\n", `\n`),
		"base64": base64.StdEncoding.EncodeToString([]byte(pem)),
		"앞뒤 공백":  "  " + pem + "\n",
	} {
		got, err := decodeKey(in, "-----BEGIN")
		if err != nil || string(got) != pem {
			t.Errorf("%s: %q %v", name, got, err)
		}
	}
	for _, bad := range []string{"", "아무 글자", base64.StdEncoding.EncodeToString([]byte("not a key"))} {
		if _, err := decodeKey(bad, "-----BEGIN"); err == nil {
			t.Errorf("%q가 통과됨", bad)
		}
	}
}
