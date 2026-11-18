package iap

import (
	"context"
	"fmt"
)

// Fake는 시험용 Store다. 스토어에 "있는" 거래를 미리 넣어 두고 쓴다.
type Fake struct {
	R         Route
	Purchases map[string]Purchase // 거래 ID → 거래
	Err       error               // 값이 있으면 조회가 항상 이 오류로 실패한다(통신 장애 흉내)
}

func (f *Fake) Route() Route { return f.R }

func (f *Fake) LookupTransaction(_ context.Context, transactionID string) (Purchase, error) {
	if f.Err != nil {
		return Purchase{}, f.Err
	}
	p, ok := f.Purchases[transactionID]
	if !ok {
		return Purchase{}, fmt.Errorf("fake %s: %w", transactionID, ErrNotFound)
	}
	return p, nil
}

// 컴파일할 때 "Store를 구현했는지" 확인한다. Java의 implements 자리.
var (
	_ Store = (*Apple)(nil)
	_ Store = (*Fake)(nil)
)
