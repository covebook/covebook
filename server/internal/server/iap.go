package server

import (
	"context"
	"net/http"
	"strconv"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit"
)

// 결제는 결제 키트(server/iapkit)가 맡는다. 여기에는 책장 한켠만의 것만 둔다: 규칙(무엇을 어디에 얼마나 파는지), 로그인·운영자 확인 연결.

// covebookIAPRules는 책장 한켠의 규칙이다: 연도 책장마다 추가 선반 3칸까지(책장 6칸 중 3칸 무료, D1).
var covebookIAPRules = iapkit.Rules{
	TargetRequired: true,
	ValidTarget:    covebookShelfYear,
	Cap:            3,
	Hold:           5 * time.Minute,
	Messages: map[string]string{
		"iap_cap_full":       "이 책장의 추가 선반을 모두 열었어요",
		"iap_cap_too_many":   "이 책장에 남은 칸보다 많아요",
		"iap_target_busy":    "다른 기기에서 이 책장의 선반을 결제하고 있어요. 잠시 뒤 다시 시도해 주세요",
		"iap_target_missing": "어느 해 책장의 선반인지 알 수 없어요. 문의해 주시면 확인해 드릴게요",
		"iap_granted_owner":  "결제한 다른 계정에 선반을 넣었어요. 그 계정으로 로그인하면 보여요",
		"iap_owner_refunded": "결제한 계정이 탈퇴해 선반을 열 수 없어요. 결제는 환불돼요",
		"iap_owner_later":    "결제한 계정이 탈퇴해 선반을 열 수 없어요. 결제는 며칠 안에 환불돼요",
		"iap_owner_apple":    "결제한 계정이 탈퇴해 선반을 열 수 없어요. App Store에서 환불을 요청해 주세요",
	},
}

// covebookShelfYear는 연도 책장 값인지 본다. 연도 책장 테이블(bookcases)과 같은 범위이고, "02026"처럼 같은 해가 둘로 나뉘는 모양은 받지 않는다.
func covebookShelfYear(s string) bool {
	y, err := strconv.Atoi(s)
	return err == nil && y >= 2000 && y <= 9999 && strconv.Itoa(y) == s
}

// newIAPKit은 환경 변수로 결제 키트를 만든다. 결제 스위치가 꺼져 있으면 경로가 없는 키트다.
func (s *Server) newIAPKit() *iapkit.Kit {
	k := iapkit.New(s.DB, iapkit.StoresFromEnv(), covebookIAPRules, iapkit.SandboxFromEnv())
	k.Auth = func(w http.ResponseWriter, r *http.Request) (int64, bool) {
		user, err := s.user(r)
		if err != nil {
			fail(w, err)
			return 0, false
		}
		return user, true
	}
	k.Admin = adminOK
	return k
}

// StartIAPWorker는 결제 정기 처리를 돌린다. 결제가 꺼져 있으면 아무 일도 하지 않는다.
func (s *Server) StartIAPWorker(ctx context.Context) { s.IAP.StartWorker(ctx) }
