package iap

import "errors"

// Expect는 "이 요청이라면 거래가 이래야 한다"는 우리 쪽 기준이다.
type Expect struct {
	BundleID     string          // 우리 앱 (app.covebook)
	Products     map[string]bool // 우리가 파는 상품 ID
	AccountToken string          // 요청한 유저의 결제용 UUID
}

// Check가 돌려주는 오류. 호출하는 쪽은 errors.Is로 구분한다.
var (
	ErrWrongApp       = errors.New("iap: 다른 앱의 거래")
	ErrUnknownProduct = errors.New("iap: 우리가 팔지 않는 상품")
	ErrWrongAccount   = errors.New("iap: 다른 계정의 거래")
	ErrRevoked        = errors.New("iap: 환불·취소된 거래")
	ErrNotPaid        = errors.New("iap: 결제가 끝나지 않았거나 권한이 없는 상태의 거래")
)

var errTODO = errors.New("iap: Check 구현 전")

// Check는 스토어가 확인해 준 거래가 이 요청에 지급해도 되는 거래인지 본다.
// 서명 검증(라이브러리) 뒤에 우리가 두는 두 번째 방어선이다(ADR-0001 결정 9).
// 문제가 없으면 nil을 돌려준다.
//
// TODO(범수): 아래를 정해서 5~10줄로 채운다. 설명은 docs/guides/iap-go-notes.md 7장.
//   - 번들 ID가 다르면 ErrWrongApp
//   - 상품 ID가 Products에 없으면 ErrUnknownProduct
//   - p.State가 StateRevoked면 ErrRevoked, StatePaid가 아닌 나머지(대기, 비활성)는 ErrNotPaid
//   - 계정 값이 다르면 ErrWrongAccount
//   - 정할 것 1: 거래의 AccountToken이 빈 문자열일 때 통과시킬지, 막을지
//   - 정할 것 2: 여러 개가 동시에 틀렸을 때 어느 오류를 먼저 돌려줄지
func Check(p Purchase, want Expect) error {
	return errTODO
}
