package iap

import (
	"context"
	"fmt"
)

// Fake는 시험용 Store다. 스토어에 "있는" 거래를 미리 넣어 두고 쓴다.
type Fake struct {
	R          Route
	Purchases  map[string]Purchase // Ref.ID → 거래
	Err        error               // 값이 있으면 조회가 항상 이 오류로 실패한다(통신 장애 흉내)
	Confirmed  []string            // Confirm이 불린 Ref.ID. 순서대로
	ConfirmErr error               // 값이 있으면 Confirm이 실패한다
}

func (f *Fake) Route() Route { return f.R }

func (f *Fake) Lookup(_ context.Context, ref Ref) (Purchase, error) {
	if f.Err != nil {
		return Purchase{}, f.Err
	}
	p, ok := f.Purchases[ref.ID]
	if !ok {
		return Purchase{}, fmt.Errorf("fake %s: %w", ref.ID, ErrNotFound)
	}
	return p, nil
}

// 컴파일할 때 "Store를 구현했는지" 확인한다. Java의 implements 자리.
var (
	_ Store = (*Apple)(nil)
	_ Store = (*Google)(nil)
	_ Store = (*Fake)(nil)
)

// Subscription은 Purchases에서 원 거래 ID가 같은 것을 찾는다. 여러 개면 만료가 가장 늦은 것이다.
func (f *Fake) Subscription(_ context.Context, originalID string) (Purchase, error) {
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

func (f *Fake) Confirm(_ context.Context, ref Ref, _ string, _ bool) error {
	if f.ConfirmErr != nil {
		return f.ConfirmErr
	}
	f.Confirmed = append(f.Confirmed, ref.ID)
	return nil
}
