// Package iap은 스토어(애플, 구글)에 거래를 물어보고 그 답을 우리 형식으로 바꾼다.
// 지급 판단과 DB 저장은 여기서 하지 않는다. 결정 기록: docs/adr/0001, 0002.
package iap

import (
	"context"
	"errors"
	"time"
)

// Route는 결제 경로다. DB의 결제 경로 칸에 이 문자열이 그대로 들어간다(ADR-0002 D19).
type Route string

const (
	RouteApple  Route = "apple"
	RouteGoogle Route = "google"
)

// Env는 거래가 생긴 환경이다. 샌드박스 거래도 받되 기록해 둔다(ADR-0002 D15).
type Env string

const (
	EnvProduction Env = "production"
	EnvSandbox    Env = "sandbox"
)

// Purchase는 스토어가 확인해 준 거래 한 건이다. 앱이 보낸 값이 아니라 스토어에 다시 물어 받은 값만 담는다.
type Purchase struct {
	Route                 Route
	TransactionID         string
	OriginalTransactionID string // 구독은 갱신돼도 이 값이 같다
	BundleID              string
	ProductID             string
	AccountToken          string // 우리가 유저마다 발급한 결제용 UUID. 스토어에 안 넘겼으면 빈 문자열(ADR-0002 D7)
	Env                   Env
	PurchasedAt           time.Time
	ExpiresAt             time.Time // 구독만. 없으면 zero
	RevokedAt             time.Time // 환불·취소된 시각. 없으면 zero
	Currency              string    // ISO 4217
	PriceMilli            int64     // 금액 x 1000 (ADR-0002 D20)
	Country               string    // 판매 국가. 스토어가 준 코드 그대로
}

// Revoked는 환불·취소된 거래인지 알려 준다.
func (p Purchase) Revoked() bool { return !p.RevokedAt.IsZero() }

// ErrNotFound는 스토어에 그 거래가 없다는 뜻이다. 통신 실패와 구분해서 다룬다.
var ErrNotFound = errors.New("iap: 스토어에 없는 거래")

// Store는 결제 경로 하나다. 애플·구글 구현과 시험용 가짜가 이 모양을 따른다.
// 메서드는 필요해질 때 늘린다(구독 상태 조회, 알림 해석, 확인은 이슈 #10~#12).
type Store interface {
	Route() Route
	// LookupTransaction은 거래 ID로 스토어에 다시 물어본다. 없으면 ErrNotFound를 감싼 오류를 돌려준다.
	LookupTransaction(ctx context.Context, transactionID string) (Purchase, error)
}
