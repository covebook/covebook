package iap

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// Fake는 시험용 Store다. 스토어에 "있는" 거래를 미리 넣어 두고 쓴다.
type Fake struct {
	R          Route
	App        string              // AppID가 돌려줄 값
	Purchases  map[string]Purchase // Ref.ID → 거래
	Err        error               // 값이 있으면 조회가 항상 이 오류로 실패한다(통신 장애 흉내)
	Confirmed  []string            // Confirm이 불린 Ref.ID. 순서대로
	ConfirmErr error               // 값이 있으면 Confirm이 실패한다
	History    []Notice            // NoticeHistory가 돌려줄, 스토어가 보냈던 알림
	VoidedList []VoidedPurchase    // Voided가 돌려줄, 스토어가 환불한 구매
	PanicOn    string              // Ref.ID나 원 거래 ID가 이 값이면 조회가 패닉한다(알림 하나의 패닉이 다른 처리를 막지 않는지 보는 시험용)
	RestUntil  time.Time           // 이 시각 전에는 모든 스토어 호출이 한도 초과(RateLimitError)로 실패한다(429 흉내)
	Calls      int                 // 스토어 API를 부른 횟수(쉬는 중에 부르지 않는지 보는 시험용)
	Delay      time.Duration       // 조회·확인이 이만큼 걸린다(느린 스토어 흉내). ctx가 먼저 끝나면 그 오류로 실패한다
}

// slow는 Delay만큼 기다린다. 진짜 클라이언트처럼 ctx의 마감을 지킨다.
func (f *Fake) slow(ctx context.Context) error {
	if f.Delay <= 0 {
		return nil
	}
	select {
	case <-time.After(f.Delay):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// RestingUntil은 한도 초과 흉내가 언제까지인지 준다(Rester).
func (f *Fake) RestingUntil() time.Time { return f.RestUntil }

// limited는 한도 초과 흉내 중이면 오류를 준다. 아니면 호출 횟수를 센다.
func (f *Fake) limited() error {
	if time.Now().Before(f.RestUntil) {
		return &RateLimitError{Route: f.R, Until: f.RestUntil}
	}
	f.Calls++
	return nil
}

func (f *Fake) Route() Route  { return f.R }
func (f *Fake) AppID() string { return f.App }

// Verify는 증거를 그대로 조회 대상으로 쓴다. "forged"로 시작하면 서명이 틀린 것으로 본다.
func (f *Fake) Verify(kind Kind, proof string) (Ref, error) {
	if proof == "" || strings.HasPrefix(proof, "forged") {
		return Ref{}, fmt.Errorf("fake: %w", ErrBadProof)
	}
	return Ref{Kind: kind, ID: proof}, nil
}

func (f *Fake) Lookup(ctx context.Context, ref Ref) (Purchase, error) {
	if err := f.limited(); err != nil {
		return Purchase{}, err
	}
	if err := f.slow(ctx); err != nil {
		return Purchase{}, err
	}
	if f.PanicOn != "" && ref.ID == f.PanicOn {
		panic("fake panic " + ref.ID)
	}
	if f.Err != nil {
		return Purchase{}, f.Err
	}
	p, ok := f.Purchases[ref.ID]
	if !ok {
		return Purchase{}, fmt.Errorf("fake %s: %w", ref.ID, ErrNotFound)
	}
	return p, nil
}

// FakeRefunder는 환불할 수 있는 스토어(구글)를 흉내 낸다. Fake에는 Refund가 없어서 애플 시험에 끼어들지 않는다.
type FakeRefunder struct {
	*Fake
	Refunded  []string // Refund가 불린 주문 ID. 순서대로
	RefundErr error    // 값이 있으면 Refund가 실패한다
}

func (f *FakeRefunder) Refund(_ context.Context, orderID string) error {
	if err := f.limited(); err != nil {
		return err
	}
	if f.RefundErr != nil {
		return f.RefundErr
	}
	if orderID == "" {
		return fmt.Errorf("fake: 주문 ID 없음")
	}
	f.Refunded = append(f.Refunded, orderID)
	return nil
}

// 컴파일할 때 "Store를 구현했는지" 확인한다. Java의 implements 자리.
var (
	_ Store    = (*Apple)(nil)
	_ Store    = (*Google)(nil)
	_ Store    = (*Fake)(nil)
	_ Refunder = (*Google)(nil)
	_ Refunder = (*FakeRefunder)(nil)
)

// Subscription은 Purchases에서 원 거래 ID가 같은 것을 찾는다. 여러 개면 만료가 가장 늦은 것이다.
func (f *Fake) Subscription(ctx context.Context, originalID string) (Purchase, error) {
	if err := f.limited(); err != nil {
		return Purchase{}, err
	}
	if err := f.slow(ctx); err != nil {
		return Purchase{}, err
	}
	if f.PanicOn != "" && originalID == f.PanicOn {
		panic("fake panic " + originalID)
	}
	if f.Err != nil {
		return Purchase{}, f.Err
	}
	var best Purchase
	found := false
	for _, p := range f.Purchases {
		if p.OriginalTransactionID == originalID && (!found || p.ExpiresAt.After(best.ExpiresAt)) {
			best, found = p, true
		}
	}
	if !found {
		return Purchase{}, fmt.Errorf("fake 구독 %s: %w", originalID, ErrNotFound)
	}
	return best, nil
}

func (f *Fake) Confirm(ctx context.Context, ref Ref, _ string, _ bool) error {
	if err := f.limited(); err != nil {
		return err
	}
	if err := f.slow(ctx); err != nil {
		return err
	}
	if f.ConfirmErr != nil {
		return f.ConfirmErr
	}
	f.Confirmed = append(f.Confirmed, ref.ID)
	return nil
}

// ParseNotice는 본문을 Notice의 JSON으로 읽는다. 시험에서 알림을 직접 만들어 넣을 때 쓴다.
// {"bad":"signature"}는 서명 실패, 읽을 수 없는 본문은 형식 오류, {"app":"other"}는 다른 앱의 알림이다.
func (f *Fake) ParseNotice(body []byte) (Notice, error) {
	var probe struct{ Bad, App string }
	if err := json.Unmarshal(body, &probe); err != nil {
		return Notice{}, fmt.Errorf("fake 알림: %w", ErrBadNotice)
	}
	if probe.Bad != "" {
		return Notice{}, fmt.Errorf("fake 알림 서명 확인 실패")
	}
	if probe.App != "" {
		return Notice{}, fmt.Errorf("fake 알림: %w", ErrWrongApp)
	}
	var n Notice
	if err := json.Unmarshal(body, &n); err != nil || n.ID == "" {
		return Notice{}, fmt.Errorf("fake 알림: %w", ErrBadNotice)
	}
	n.Route = f.R
	return n, nil
}
