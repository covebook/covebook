package iap

import (
	"errors"
	"testing"
)

func TestCheck(t *testing.T) {
	want := Expect{BundleID: "app.covebook", Products: map[string]bool{"plus.monthly": true}, AccountToken: "u-1"}
	ok := Purchase{BundleID: "app.covebook", ProductID: "plus.monthly", AccountToken: "u-1", Env: EnvSandbox}
	if errors.Is(Check(ok, want), errTODO) {
		t.Skip("check.go의 Check를 먼저 채운다")
	}

	// 표 하나에 경우를 늘어놓고 같은 코드로 돌린다(Go에서 흔한 모양)
	cases := []struct {
		name   string
		change func(*Purchase) // 정상 거래에서 한 군데만 바꾼다
		err    error
	}{
		{"정상", func(*Purchase) {}, nil},
		{"샌드박스도 받는다", func(p *Purchase) { p.Env = EnvSandbox }, nil},
		{"다른 앱", func(p *Purchase) { p.BundleID = "com.other" }, ErrWrongApp},
		{"모르는 상품", func(p *Purchase) { p.ProductID = "plus.lifetime" }, ErrUnknownProduct},
		{"다른 계정", func(p *Purchase) { p.AccountToken = "u-2" }, ErrWrongAccount},
		{"환불됨", func(p *Purchase) { p.RevokedAt = p.RevokedAt.AddDate(2026, 0, 0) }, ErrRevoked},
		// TODO(범수): 빈 AccountToken 경우를 정한 대로 한 줄 추가
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := ok
			c.change(&p)
			if got := Check(p, want); !errors.Is(got, c.err) {
				t.Fatalf("기대 %v, 실제 %v", c.err, got)
			}
		})
	}
}
