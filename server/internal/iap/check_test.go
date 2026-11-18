package iap

import (
	"errors"
	"testing"
)

func TestCheck(t *testing.T) {
	want := Expect{BundleID: "app.covebook", Products: map[string]bool{"plus.monthly": true}, AccountTokens: []string{"u-1", "u-old"}}
	ok := Purchase{BundleID: "app.covebook", ProductID: "plus.monthly", AccountToken: "u-1", State: StatePaid, Env: EnvProduction}
	// 샌드박스 거래는 허용했을 때만 통과한다. 환경 값이 비어 있어도 운영으로 치지 않는다
	sandbox, unknownEnv := ok, ok
	sandbox.Env, unknownEnv.Env = EnvSandbox, ""
	if err := Check(sandbox, want); !errors.Is(err, ErrSandbox) {
		t.Fatalf("샌드박스가 통과: %v", err)
	}
	if err := Check(unknownEnv, want); !errors.Is(err, ErrSandbox) {
		t.Fatalf("환경을 모르는 거래가 통과: %v", err)
	}
	allow := want
	allow.AllowSandbox = true
	if err := Check(sandbox, allow); err != nil {
		t.Fatalf("허용했는데 샌드박스가 막힘: %v", err)
	}

	// 표 하나에 경우를 늘어놓고 같은 코드로 돌린다(Go에서 흔한 모양)
	cases := []struct {
		name   string
		change func(*Purchase) // 정상 거래에서 한 군데만 바꾼다
		err    error
	}{
		{"정상", func(*Purchase) {}, nil},
		{"다른 앱", func(p *Purchase) { p.BundleID = "com.other" }, ErrWrongApp},
		{"모르는 상품", func(p *Purchase) { p.ProductID = "plus.lifetime" }, ErrUnknownProduct},
		{"다른 계정", func(p *Purchase) { p.AccountToken = "u-2" }, ErrWrongAccount},
		{"환불됨", func(p *Purchase) { p.State = StateRevoked }, ErrRevoked},
		{"결제 대기", func(p *Purchase) { p.State = StatePending }, ErrNotPaid},
		{"보류·일시정지", func(p *Purchase) { p.State = StateInactive }, ErrNotPaid},
		{"상태 값이 비어 있음", func(p *Purchase) { p.State = "" }, ErrNotPaid},
		{"넘겨받은 구독의 옛 값도 내 것", func(p *Purchase) { p.AccountToken = "u-old" }, nil},
		{"대문자로 와도 같은 값", func(p *Purchase) { p.AccountToken = "U-1" }, nil},
		{"빈 값은 통과 (앱 밖 구매)", func(p *Purchase) { p.AccountToken = "" }, nil},
		// 여러 개가 틀리면 더 근본적인 것이 먼저 나온다
		{"다른 앱이면서 다른 계정", func(p *Purchase) { p.BundleID, p.AccountToken = "com.other", "u-2" }, ErrWrongApp},
		{"환불됐고 다른 계정", func(p *Purchase) { p.State, p.AccountToken = StateRevoked, "u-2" }, ErrRevoked},
		{"결제 대기이고 다른 계정", func(p *Purchase) { p.State, p.AccountToken = StatePending, "u-2" }, ErrNotPaid},
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
