package iapkit

import "time"

// Rules는 앱마다 다른 결제 규칙이다. 키트는 선반·연도 같은 앱의 말을 모르고 이 값만 본다(README.md "앱 규칙").
//
// 한 번 사는 상품은 "대상(target)"에 "수량(units)"을 더한다. 대상은 문자열이고 뜻은 앱이 정한다.
//   - 책장 한켠: 대상은 연도 책장("2026"), 수량은 선반 칸, 대상마다 3칸까지
//   - 대상이 없는 앱(계정 전체에 붙는 상품): TargetRequired=false. 대상은 빈 문자열(”)이다
type Rules struct {
	// TargetRequired면 한 번 사는 상품은 대상이 정해져야 준다. 대상을 모르는 거래는 기록만 하고
	// 스토어 확인(소비)을 하지 않으며, 2일 안에 앱이 대상과 함께 다시 내지 않으면 환불한다(D1).
	TargetRequired bool
	// ValidTarget은 앱이 보낸 대상 값이 올바른지 본다. TargetRequired일 때만 부른다. 64자를 넘으면 부르기 전에 거절한다
	ValidTarget func(string) bool
	// Cap은 대상 하나에서 돈을 내고 살 수 있는 수량의 최대다. 0이면 상한이 없다(예약·넘김 환불을 하지 않는다)
	Cap int
	// Hold는 결제 중 예약이 살아 있는 시간이다. 결제가 끝나거나 취소되면 앱이 바로 푼다. 0이면 5분이다
	// (0을 그대로 쓰면 예약이 만들어지자마자 끝나 두 기기가 동시에 사는 것을 막지 못한다)
	Hold time.Duration
	// Messages는 오류 코드별 사용자 문구다. 없는 코드는 DefaultMessages를 쓴다(앱 언어·말투에 맞춰 바꾼다)
	Messages map[string]string
}

// iapHoldDefault는 Rules.Hold가 0일 때 쓰는 예약 시간이다.
const iapHoldDefault = 5 * time.Minute

// hold는 결제 중 예약 시간이다.
func (r Rules) hold() time.Duration {
	if r.Hold <= 0 {
		return iapHoldDefault
	}
	return r.Hold
}

// iapTargetMax는 대상 값의 최대 길이다(DB CHECK와 같다).
const iapTargetMax = 64

// target은 앱이 보낸 대상을 확인한다. 빈 값은 "보내지 않음"이라 ok다.
func (r Rules) target(raw string) (string, bool) {
	if raw == "" {
		return "", true
	}
	if !r.TargetRequired || len(raw) > iapTargetMax || r.ValidTarget == nil || !r.ValidTarget(raw) {
		return "", false
	}
	return raw, true
}

// message는 오류 코드의 사용자 문구다.
func (r Rules) message(code string) string {
	if m, ok := r.Messages[code]; ok {
		return m
	}
	return DefaultMessages[code]
}

// DefaultMessages는 앱이 문구를 주지 않은 오류의 기본 문구다(대상·수량을 모르는 말로 쓴다).
// 키는 문구 키다. 응답 코드와 다른 것이 있다: iap_cap_too_many → 응답 iap_cap_full, iap_granted_owner → iap_other_account,
// iap_owner_* → iap_owner_gone. 같은 응답 코드에 상황마다 다른 문구를 주려는 것이다(README의 오류 코드 표).
var DefaultMessages = map[string]string{
	"iap_cap_full":       "더 살 수 없어요",
	"iap_cap_too_many":   "남은 수량보다 많아요",
	"iap_target_busy":    "다른 기기에서 결제하고 있어요. 잠시 뒤 다시 시도해 주세요",
	"iap_target_missing": "어디에 쓸 구매인지 알 수 없어요. 문의해 주시면 확인해 드릴게요",
	"iap_granted_owner":  "결제한 다른 계정에 넣었어요. 그 계정으로 로그인하면 보여요",
	"iap_owner_refunded": "결제한 계정이 탈퇴해 받을 수 없어요. 결제는 환불돼요",
	"iap_owner_later":    "결제한 계정이 탈퇴해 받을 수 없어요. 결제는 며칠 안에 환불돼요",
	"iap_owner_apple":    "결제한 계정이 탈퇴해 받을 수 없어요. App Store에서 환불을 요청해 주세요",
}
