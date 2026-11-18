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

// Kind는 상품 종류다. 구글은 종류마다 조회 주소가 달라서 물어볼 때 알려 줘야 한다.
type Kind string

const (
	KindSubscription Kind = "subscription"
	KindProduct      Kind = "product" // 한 번 사는 상품 (추가 선반)
)

// State는 지급 판단에 쓰는 거래 상태다. 구독 만료는 여기 없다. ExpiresAt과 서버 시계로 따로 본다(ADR-0002 D23).
type State string

const (
	StatePaid     State = "paid"     // 결제 끝남
	StatePending  State = "pending"  // 결제 대기 (구글의 편의점 결제 등). 아직 지급하면 안 된다
	StateInactive State = "inactive" // 일시정지·보류·만료처럼 권한이 없는 상태. 모르는 값도 여기로 둔다
	StateRevoked  State = "revoked"  // 환불·취소
)

// Ref는 스토어에 물어볼 거래를 가리킨다. 앱이 보낸 값이라 믿지 않고 조회에만 쓴다.
type Ref struct {
	Kind Kind
	ID   string // 애플: 거래 ID. 구글: 구매 토큰
}

// Purchase는 스토어가 확인해 준 거래 한 건이다. 앱이 보낸 값이 아니라 스토어에 다시 물어 받은 값만 담는다.
type Purchase struct {
	Route                 Route
	TransactionID         string // 애플: 거래 ID. 구글: 주문 ID (없을 수 있다)
	OriginalTransactionID string // 구독이 갱신돼도 같은 값. 애플: 원 거래 ID. 구글: 구매 토큰
	BundleID              string
	ProductID             string
	PlanID                string // 구글 구독의 요금제(base plan). 애플은 상품 ID가 요금제라 비어 있다
	State                 State
	AccountToken          string // 우리가 유저마다 발급한 결제용 UUID. 스토어에 안 넘겼으면 빈 문자열(ADR-0002 D7)
	Env                   Env
	PurchasedAt           time.Time
	ExpiresAt             time.Time // 구독만. 없으면 zero
	RevokedAt             time.Time // 환불·취소된 시각. 애플만 준다
	Currency              string    // ISO 4217. 구글 구매 조회에는 없어서 비어 있다
	PriceMilli            int64     // 금액 x 1000 (ADR-0002 D20). 구글은 0
	Country               string    // 판매 국가. 스토어가 준 코드 그대로
}

// ErrNotFound는 스토어에 그 거래가 없다는 뜻이다. 통신 실패와 구분해서 다룬다.
var ErrNotFound = errors.New("iap: 스토어에 없는 거래")

// Store는 결제 경로 하나다. 애플·구글 구현과 시험용 가짜가 이 모양을 따른다.
// 메서드는 필요해질 때 늘린다(구독 상태 조회, 알림 해석, 확인은 이슈 #10~#12).
type Store interface {
	Route() Route
	// Lookup은 스토어에 다시 물어본다. 없으면 ErrNotFound를 감싼 오류를 돌려준다.
	Lookup(ctx context.Context, ref Ref) (Purchase, error)
}
