package iap

import (
	"errors"
	"slices"
	"strings"
)

// Expect는 "이 요청이라면 거래가 이래야 한다"는 우리 쪽 기준이다.
type Expect struct {
	BundleID      string          // 우리 앱 (Store.AppID)
	Products      map[string]bool // 우리가 파는 상품 ID
	AccountTokens []string        // 요청한 유저의 결제용 UUID(소문자)
	AllowSandbox  bool            // 샌드박스(시험) 거래에도 지급할지. 운영에서는 기본 false
}

// Check가 돌려주는 오류. 호출하는 쪽은 errors.Is로 구분한다.
var (
	ErrWrongApp       = errors.New("iap: 다른 앱의 거래")
	ErrUnknownProduct = errors.New("iap: 우리가 팔지 않는 상품")
	ErrWrongAccount   = errors.New("iap: 다른 계정의 거래")
	ErrRevoked        = errors.New("iap: 환불·취소된 거래")
	ErrNotPaid        = errors.New("iap: 결제가 끝나지 않았거나 권한이 없는 상태의 거래")
	ErrSandbox        = errors.New("iap: 샌드박스 거래는 받지 않음")
)

// Check는 스토어가 확인해 준 거래가 이 요청에 지급해도 되는 거래인지 본다.
// 서명 검증(라이브러리) 뒤에 우리가 두는 두 번째 방어선이다(ADR-0001 결정 9).
// 문제가 없으면 nil을 돌려준다.
//
// 순서: 가장 근본적인 것부터 본다. 다른 앱 → 모르는 상품 → 샌드박스 → 환불 → 결제 안 끝남 → 다른 계정.
// 샌드박스 거래는 실제 결제가 아니다. 허용하지 않으면 TestFlight나 샌드박스 계정으로 운영 권한을 공짜로 얻는다.
// 계정을 맨 뒤에 두는 이유: "다른 계정"은 구매 복원에서 구독을 넘겨받을 수 있는 경우라,
// 그 판단은 거래 자체가 멀쩡하다는 것이 확인된 뒤에 해야 한다.
//
// 계정 연결 값이 빈 거래는 통과시킨다. 앱을 거치지 않은 구매(오퍼 코드, 스토어에서 직접 한 구독)는 값이 없고,
// 업계 기본은 거래를 제출한 유저에게 붙이는 것이다(조사 종합 8-2 T10, 이슈 #29).
// 값이 있는데 다르면 거절한다. 구글 공식 문서가 서버에서 대조하라고 한다.
func Check(p Purchase, want Expect) error {
	if p.BundleID != want.BundleID {
		return ErrWrongApp
	}
	if !want.Products[p.ProductID] {
		return ErrUnknownProduct
	}
	if p.Env != EnvProduction && !want.AllowSandbox {
		return ErrSandbox
	}
	if p.State == StateRevoked {
		return ErrRevoked
	}
	if p.State != StatePaid {
		return ErrNotPaid
	}
	if p.AccountToken != "" && !slices.Contains(want.AccountTokens, strings.ToLower(p.AccountToken)) {
		return ErrWrongAccount
	}
	return nil
}
