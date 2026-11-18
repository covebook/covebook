package iap

import (
	"encoding/base64"
	"fmt"
	"strings"
)

// 환경변수 이름. 값은 서버 환경(KoDeploy)에만 넣고 저장소·이슈·PR에 적지 않는다.
const (
	envAppleKey    = "IAP_APPLE_KEY_P8"    // .p8 내용. 그대로 또는 base64
	envAppleKeyID  = "IAP_APPLE_KEY_ID"    // 키 ID
	envAppleIssuer = "IAP_APPLE_ISSUER_ID" // 발급자 ID
	envAppleBundle = "IAP_APPLE_BUNDLE_ID" // 번들 ID
	envGoogleKey   = "IAP_GOOGLE_KEY_JSON" // 서비스 계정 키. 그대로 또는 base64
	envGooglePkg   = "IAP_GOOGLE_PACKAGE"  // 패키지 이름
)

// FromEnv는 환경변수로 설정된 스토어만 만들어 돌려준다.
// 한 스토어의 값이 전부 비어 있으면 그 스토어는 꺼진 것이다(오류 아님).
// 일부만 있으면 오류다. 반쯤 설정된 채로 켜지는 것을 막는다.
// getenv를 인자로 받는 것은 시험에서 가짜 환경을 넣기 위해서다. 실제로는 os.Getenv를 넘긴다.
func FromEnv(getenv func(string) string) (map[Route]Store, error) {
	stores := map[Route]Store{}

	apple := []string{envAppleKey, envAppleKeyID, envAppleIssuer, envAppleBundle}
	on, err := allOrNone(getenv, apple)
	if err != nil {
		return nil, err
	}
	if on {
		key, err := decodeKey(getenv(envAppleKey), "-----BEGIN")
		if err != nil {
			return nil, fmt.Errorf("%s: %w", envAppleKey, err)
		}
		stores[RouteApple] = NewApple(AppleConfig{
			KeyP8: key, KeyID: getenv(envAppleKeyID), IssuerID: getenv(envAppleIssuer), BundleID: getenv(envAppleBundle),
		})
	}

	on, err = allOrNone(getenv, []string{envGoogleKey, envGooglePkg})
	if err != nil {
		return nil, err
	}
	if on {
		key, err := decodeKey(getenv(envGoogleKey), "{")
		if err != nil {
			return nil, fmt.Errorf("%s: %w", envGoogleKey, err)
		}
		g, err := NewGoogle(key, getenv(envGooglePkg))
		if err != nil {
			return nil, err
		}
		stores[RouteGoogle] = g
	}
	return stores, nil
}

// allOrNone은 이름들이 전부 채워졌으면 true, 전부 비었으면 false, 섞였으면 오류를 돌려준다.
// 오류에는 빠진 이름만 적는다. 값은 적지 않는다.
func allOrNone(getenv func(string) string, names []string) (bool, error) {
	var missing []string
	for _, n := range names {
		if strings.TrimSpace(getenv(n)) == "" {
			missing = append(missing, n)
		}
	}
	switch len(missing) {
	case 0:
		return true, nil
	case len(names):
		return false, nil
	}
	return false, fmt.Errorf("iap 설정이 일부만 있음. 빠진 것: %s", strings.Join(missing, ", "))
}

// decodeKey는 키를 그대로 넣었든 base64로 넣었든 원래 내용으로 돌려준다.
// 여러 줄 값을 못 넣는 배포 환경을 위해 base64와 글자 "\n"도 받는다.
func decodeKey(v, prefix string) ([]byte, error) {
	v = strings.TrimSpace(v)
	if strings.HasPrefix(v, prefix) {
		return []byte(strings.ReplaceAll(v, `\n`, "\n")), nil
	}
	raw, err := base64.StdEncoding.DecodeString(v)
	if err != nil || !strings.HasPrefix(strings.TrimSpace(string(raw)), prefix) {
		return nil, fmt.Errorf("키 형식을 알 수 없음 (%q로 시작하는 내용이나 그 base64여야 함)", prefix)
	}
	return raw, nil
}
