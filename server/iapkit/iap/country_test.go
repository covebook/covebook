package iap

import "testing"

func TestCountry(t *testing.T) {
	for in, want := range map[string]string{
		"KOR": "KR", "KR": "KR", "kr": "KR", " KOR ": "KR", // 애플·구글 둘 다 KR로
		"PRK": "KP", "USA": "US", "GBR": "GB", "TWN": "TW", "HKG": "HK",
		"XKS": "XK", "XK": "XK", // 코소보: 애플만 ISO 밖 코드를 쓴다
		"": "", "ZZZ": "", "K": "", "KORE": "", "419": "", // 모르는 값·지역 코드는 빈 값(NULL로 저장)
	} {
		if got := Country(in); got != want {
			t.Errorf("Country(%q) = %q, want %q", in, got, want)
		}
	}
}
