package iapkit

import (
	"context"
	"errors"
	"log"
	"math"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit/iap"
)

// 인앱결제 API. 결정 기록: docs/adr/0002-iap-design.md, 근거: docs/reports/2026-11-19-iap-pitfalls.md
//
// 원칙
//   - 앱이 보낸 값은 "무엇을 물어볼지"에만 쓴다. 지급 근거는 스토어에 다시 물어 받은 답이다.
//   - 스토어를 부르는 동안에는 DB 트랜잭션을 열지 않는다. 트랜잭션은 "주인 확인 → 원장에 넣기 → 커밋"만 한다.
//   - 스토어 조회가 실패하면 지급하지 않고 503을 준다. 앱이 거래를 끝내지 않으면 스토어가 다시 전달한다(D18).
//   - 같은 거래가 다시 와도 성공으로 답한다. 오류를 주면 앱이 거래를 끝내지 못해 계속 다시 보낸다.
//   - 스토어 확인(구글 acknowledge·consume)은 커밋 뒤에 한다. 실패해도 지급은 유지하고 나중에 다시 시도한다(D10).

// iapStoreTimeout은 요청 하나가 스토어 조회를 기다리는 시간이다. 값은 이슈 #23에서 다시 정한다.
// 참고: 애플 공식 서버 라이브러리의 기본 제한 시간은 30초, RevenueCat SDK는 경우에 따라 2~30초.
const iapStoreTimeout = 15 * time.Second

// EnvEnabled는 결제 스위치(IAP_ENABLED=1)다. 꺼져 있으면 API가 아예 없다. 스토어 키가 없거나 틀려도 꺼진다(서버는 뜬다).
func EnvEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("IAP_ENABLED"))) {
	case "1", "true", "on", "yes":
		return true
	}
	return false
}

// StoresFromEnv는 스위치가 켜져 있을 때 환경변수로 스토어를 만든다(iap.FromEnv, README의 환경 변수 표). 실패하면 결제를 끈 채로 둔다.
func StoresFromEnv() map[iap.Route]iap.Store {
	if !EnvEnabled() {
		return nil
	}
	stores, err := iap.FromEnv(os.Getenv)
	if err != nil {
		log.Printf("iap disabled: %v", err)
		return nil
	}
	if len(stores) == 0 {
		log.Printf("iap disabled: IAP_ENABLED is set but no store keys are configured")
	}
	return stores
}

// SandboxFromEnv는 샌드박스 스위치(IAP_ALLOW_SANDBOX=1)다. 샌드박스(TestFlight, 심사, 시험 계정) 거래에도 지급한다.
// 기본은 꺼짐이다. 켜 두면 실제로 결제하지 않은 사람이 운영 권한을 받는다(조사 종합 6-1장, 이슈 #31).
// 책장 한켠은 운영에서도 계속 켠다(2026-11-26 결정, 이슈 #31: TestFlight 참가자에게도 선반을 준다). 샌드박스 거래는 env로 따로 남아 매출에서 빠진다. 끄면 전에 준 샌드박스 권한도 함께 사라진다.
func SandboxFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("IAP_ALLOW_SANDBOX"))) {
	case "1", "true", "on", "yes":
		return true
	}
	return false
}

// iapSubmitLimit은 한 유저가 1분에 낼 수 있는 구매 제출 횟수다. 증거를 추측해 넣어 보는 것을 늦춘다.
// 정상 사용은 구매·복원 때 몇 번뿐이다. 서버 한 대의 메모리에서만 센다.
const iapSubmitLimit = 30

type iapHit struct {
	window time.Time
	count  int
}

// iapAllow는 이 유저의 이번 제출을 받아도 되는지 알려 준다.
func (s *Kit) iapAllow(user int64, now time.Time) bool {
	s.iapMu.Lock()
	defer s.iapMu.Unlock()
	if s.iapHits == nil {
		s.iapHits = map[int64]iapHit{}
	}
	// 맵이 커지면 1분이 지난 것만 지운다(전부 비우면 모든 유저의 횟수가 함께 풀린다)
	if len(s.iapHits) > 10000 {
		for u, h := range s.iapHits {
			if now.Sub(h.window) >= time.Minute {
				delete(s.iapHits, u)
			}
		}
	}
	h := s.iapHits[user]
	if now.Sub(h.window) >= time.Minute {
		h = iapHit{window: now}
	}
	h.count++
	s.iapHits[user] = h
	return h.count <= iapSubmitLimit
}

func (s *Kit) routeIAP(m *http.ServeMux) {
	if len(s.IAP) == 0 {
		return
	}
	m.HandleFunc("GET /iap/me", wrap(s.iapMe))
	m.HandleFunc("POST /iap/purchases", wrap(s.iapSubmit))
	m.HandleFunc("POST /iap/target-token", wrap(s.iapTargetTokenFor))
	m.HandleFunc("GET /iap/purchases", wrap(s.iapPurchases))
	m.HandleFunc("GET /iap/notices", wrap(s.iapNotices))
	m.HandleFunc("POST /iap/notices/read", wrap(s.iapNoticesRead))
	m.HandleFunc("GET /admin/iap/stats", wrap(s.iapAdminStats))
	m.HandleFunc("POST /iap/target-token/release", wrap(s.iapRelease))
}

var (
	iapUnknownProduct   = apiError{422, "iap_unknown_product", "판매하지 않는 상품이에요"}
	iapNotFound         = apiError{404, "iap_purchase_not_found", "스토어에서 이 구매를 찾을 수 없어요"}
	iapStoreDown        = apiError{503, "iap_store_unavailable", "스토어에서 구매를 확인하고 있어요. 잠시 뒤 다시 확인할게요"}
	iapRejected         = apiError{422, "iap_purchase_rejected", "이 앱의 구매가 아니에요"}
	iapRefunded         = apiError{409, "iap_purchase_refunded", "환불된 구매예요"}
	iapBadProof         = apiError{422, "iap_bad_proof", "구매 정보를 확인할 수 없어요"}
	iapSandbox          = apiError{422, "iap_sandbox_not_allowed", "시험 환경의 구매는 받지 않아요"}
	iapTooMany          = apiError{429, "iap_too_many", "요청이 너무 많아요. 잠시 뒤 다시 시도해 주세요"}
	iapOtherAccount     = apiError{409, "iap_other_account", "다른 계정에 연결된 구매예요. 구독은 구매 복원으로 이 계정에 옮길 수 있어요"}
	iapProductNoRestore = apiError{409, "iap_other_account", "다른 계정에 연결된 구매예요"}
)

// 문구가 앱마다 다른 오류(대상·수량을 말하는 것). 문구는 Rules.Messages에서 가져온다
func (s *Kit) iapGrantedToOwner() apiError {
	return apiError{409, "iap_other_account", s.IAPRules.message("iap_granted_owner")}
}

// 결제한 계정이 탈퇴한 거래(iapSubmit의 grantee == 0). 앱은 409라 거래를 끝낸다. 주지 않고 환불한다
func (s *Kit) iapOwnerGone(how string) apiError {
	return apiError{409, "iap_owner_gone", s.IAPRules.message("iap_owner_" + how)}
}
func (s *Kit) iapCapFull() apiError {
	return apiError{409, "iap_cap_full", s.IAPRules.message("iap_cap_full")}
}
func (s *Kit) iapCapTooMany() apiError {
	return apiError{409, "iap_cap_full", s.IAPRules.message("iap_cap_too_many")}
}
func (s *Kit) iapTargetMissing() apiError {
	return apiError{422, "iap_target_missing", s.IAPRules.message("iap_target_missing")}
}

// iapMe는 결제에 필요한 내 정보를 준다: 스토어에 넘길 계정 연결 값, 지금 가진 것, 구독 상태, 파는 상품.
// 앱은 결제를 시작하기 전에 이것을 불러 계정 연결 값을 받는다.
func (s *Kit) iapMe(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(w, r)
	if err != nil {
		return err
	}
	ctx := r.Context()
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	token, err := iapAccountToken(ctx, tx, user)
	if err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	out, err := s.iapStatus(ctx, user)
	if err != nil {
		return err
	}
	out["accountToken"] = token
	// 알림함에서 아직 읽지 않은 고지 수
	if out["unreadNotices"], err = iapUnreadNotices(ctx, s.DB, user, s.IAPSandbox); err != nil {
		return err
	}
	// 지금 파는 상품. 켜져 있는 경로의 것만 준다
	all, err := iapProductList(ctx, s.DB)
	if err != nil {
		return err
	}
	products := []map[string]any{}
	for _, p := range all {
		if s.IAP[iap.Route(p["route"].(string))] != nil {
			products = append(products, p)
		}
	}
	out["products"] = products
	routes := make([]string, 0, len(s.IAP))
	for route := range s.IAP {
		routes = append(routes, string(route))
	}
	sort.Strings(routes)
	out["routes"] = routes
	// 사업자 정보(ADR-0003 L14). 설정돼 있을 때만 준다
	if seller := iapSeller(); seller != nil {
		out["seller"] = seller
	}
	writeJSON(w, 200, out)
	return nil
}

// iapStatus는 지금 가진 것을 테이블에서 계산한다. 따로 저장한 값이 없다(D5).
//   - entitlements: 지금 유효한 구독이 주는 권한 이름 목록(책장 한켠: ["plus"] 또는 [])
//   - unitsByTarget: 대상마다 산 수량(책장 한켠: {"2026": 2}). 산 것이 없는 대상은 없다. 수량은 capPerTarget을 넘지 않는다
//   - capPerTarget: 대상 하나의 상한. 0이면 상한이 없다
func (s *Kit) iapStatus(ctx context.Context, user int64) (map[string]any, error) {
	entitlements, units, err := iapEntitlements(ctx, s.DB, user, s.IAPSandbox, s.IAPRules.Cap)
	if err != nil {
		return nil, err
	}
	sub, err := iapCurrentSubscription(ctx, s.DB, user, s.IAPSandbox)
	if err != nil {
		return nil, err
	}
	return map[string]any{"entitlements": entitlements, "unitsByTarget": units, "capPerTarget": s.IAPRules.Cap, "subscription": sub}, nil
}

// iapTargetTokenFor는 한 번 사는 상품을 살 때 스토어에 넘길 계정 연결 값을 준다(D1).
// 앱은 결제를 시작하기 직전에 이것을 부르고, 받은 값을 애플 appAccountToken·구글 obfuscatedAccountId로 넘긴다.
// 서버는 거래에 돌아온 이 값으로 어느 대상의 구매인지 찾는다(책장 한켠: 어느 해 책장의 선반인지).
//
// 상한이 있으면(Rules.Cap) 값을 주면서 그 대상에 "결제 중" 예약을 잡는다(Rules.Hold). 두 기기가 동시에 사서 상한을 넘지 않게 막는다.
// 결제가 끝나면(구매 제출) 서버가 풀고, 취소하면 앱이 POST /iap/target-token/release로 푼다. 앱이 꺼지면 시간이 지나 풀린다.
//
// 요청: {"target":"2026", "units":1}  target은 대상(대상이 없는 앱은 비운다), units는 살 상품의 수량(1칸, 3칸 묶음). 없으면 1
// 응답 200: {"token":"uuid", "target":"2026", "units":n, "reservation":"uuid", "expiresAt":"..."}  units는 그 대상에서 이미 산 수량.
//
//	상한이 없으면 reservation·expiresAt이 없다
//
// 응답 409 iap_cap_full: 그 대상의 상한을 다 샀거나 남은 수량보다 많다. 결제를 시작하지 않는다
// 응답 409 iap_target_busy: 다른 기기가 그 대상을 결제하는 중이다. "retryAfter"(초) 뒤 다시 시도한다
func (s *Kit) iapTargetTokenFor(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(w, r)
	if err != nil {
		return err
	}
	var body struct {
		Target string `json:"target"`
		Units  int    `json:"units"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if body.Units == 0 {
		body.Units = 1
	}
	rules := s.IAPRules
	target, ok := rules.target(body.Target)
	if !ok || (rules.TargetRequired && target == "") || body.Units < 1 || (rules.Cap > 0 && body.Units > rules.Cap) {
		return bad
	}
	if !s.iapAllow(user, time.Now()) {
		return iapTooMany
	}
	ctx := r.Context()
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	// 유저 줄을 잠근다. 두 기기의 요청이 차례로 예약을 본다
	var locked int64
	if err = tx.QueryRow(ctx, "SELECT id FROM users WHERE id=$1 FOR UPDATE", user).Scan(&locked); err != nil {
		return err
	}
	paid, err := iapTargetPaid(ctx, tx, user, target, s.IAPSandbox)
	if err != nil {
		return err
	}
	out := map[string]any{"target": target, "units": paid}
	if rules.Cap > 0 {
		if paid >= rules.Cap {
			return s.iapCapFull()
		}
		if paid+body.Units > rules.Cap {
			return s.iapCapTooMany()
		}
		res, wait, err := iapReserve(ctx, tx, user, target, body.Units, paid, rules.Cap, rules.Hold)
		if err != nil {
			return err
		}
		if res.ID == "" {
			secs := int(math.Ceil(wait.Seconds()))
			w.Header().Set("Retry-After", strconv.Itoa(secs))
			writeJSON(w, 409, map[string]any{
				"error":      map[string]string{"code": "iap_target_busy", "message": rules.message("iap_target_busy")},
				"retryAfter": secs,
			})
			return nil
		}
		out["reservation"], out["expiresAt"] = res.ID, res.ExpiresAt.UTC().Format(time.RFC3339)
	}
	if out["token"], err = iapTargetToken(ctx, tx, user, target); err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	writeJSON(w, 200, out)
	return nil
}

// iapRelease는 결제 중 예약을 푼다. 앱이 결제를 취소했거나 실패했을 때 부른다.
// 요청: {"reservation":"uuid"}. 없거나 남의 예약이어도 204다(다시 불러도 같다).
func (s *Kit) iapRelease(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(w, r)
	if err != nil {
		return err
	}
	var body struct {
		Reservation string `json:"reservation"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if err = iapReleaseReservation(r.Context(), s.DB, user, body.Reservation); err != nil {
		return err
	}
	w.WriteHeader(204)
	return nil
}

// iapSubmit은 앱이 제출한 구매를 스토어에 확인하고 지급한다.
//
// 요청: {"route":"apple|google", "productId":"...", "proof":"애플: 스토어가 서명한 거래(JWS). 구글: 구매 토큰", "restore":false, "target":"2026", "reservation":"uuid"}
//
// reservation은 POST /iap/target-token이 준 결제 중 예약이다. 처리한 뒤 푼다. 없으면 그 대상의 가장 오래된 예약 하나를 푼다.
//
// target은 대상이 있는 한 번 사는 상품에만 쓴다(Rules.TargetRequired). 어느 대상의 구매인지는 이 순서로 정한다
// (POST /iap/target-token이 값과 예약을 함께 준다).
//  1. reservation: 새로 넣은 거래이고 이 유저의 예약이면 그 대상
//  2. 거래에 돌아온 계정 연결 값의 대상
//  3. target: 위 둘이 대상을 모를 때(앱 밖에서 산 구매 등)
//
// 셋 다 없으면 거래는 기록하고 422 iap_target_missing이다.
//
// proof는 "내가 이 구매를 한 기기"라는 증거다. 애플 거래 ID(숫자)는 받지 않는다. 추측할 수 있어서
// 남의 구매를 내거나 restore로 남의 구독을 가져갈 수 있기 때문이다. 서명된 거래는 구매한 기기만 가진다.
// 응답 200: {"status":"granted|already|inactive", ...iapStatus의 값}
//
//	한 번 사는 상품이면 "target"(받은 대상)도 준다. 그 대상의 상한을 넘게 샀으면 "overCap":true. 이 거래는 주지 않고 환불한다.
//	"autoRefund":true면 서버가 스토어에 환불을 요청했다(구글). false면 사용자가 스토어에 환불을 요청해야 한다(애플)
//
//	granted  새로 지급했다        already  전에 지급한 거래다        inactive  구독이 만료·보류 상태라 권한이 없다
//
// 응답 202: {"status":"pending"}  결제가 아직 끝나지 않았다(구글 결제 대기). 지급하지 않았다
//
// 앱이 스토어 거래를 끝낼지(애플 finishTransaction. 구글은 서버가 확인·소비한다):
//
//	끝낸다     200 granted·already·inactive
//	           409 iap_purchase_refunded, iap_other_account(구독은 구매 복원 restore=true로 다시 내면 옮길 수 있다.
//	               한 번 사는 상품은 결제한 계정을 알면 그 계정에 넣은 뒤 이 코드를 준다), iap_owner_gone
//	           422 iap_purchase_rejected, iap_sandbox_not_allowed
//	끝내지 않음 202 pending, 404 iap_purchase_not_found, 422 iap_bad_proof, 422 iap_target_missing, 422 iap_unknown_product,
//	           429 iap_too_many, 503 iap_store_unavailable, 그 밖의 5xx. 스토어가 다시 전달하면 다시 낸다
//
// iap_target_missing은 소비하지 않고 돌려준다. 앱이 대상을 붙여 다시 낼 수 있고, 끝내 못 내면 서버가 2일 뒤 환불한다(구글 3일 자동 환불이 받친다).
func (s *Kit) iapSubmit(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(w, r)
	if err != nil {
		return err
	}
	var body struct {
		Route     string `json:"route"`
		ProductID string `json:"productId"`
		Proof     string `json:"proof"`
		Restore   bool   `json:"restore"`
		Target    string `json:"target"`
		// 결제 중 예약(POST /iap/target-token). 처리한 뒤 푼다
		Reservation string `json:"reservation"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	store := s.IAP[iap.Route(body.Route)]
	asked0, targetOK := s.IAPRules.target(body.Target)
	if store == nil || body.ProductID == "" || body.Proof == "" || len(body.Proof) > 16384 || !targetOK {
		return bad
	}
	body.Target = asked0
	targeted := s.IAPRules.TargetRequired
	if !s.iapAllow(user, time.Now()) {
		return iapTooMany
	}
	ctx := r.Context()
	route := store.Route()

	// 1. 우리 테이블로 상품 종류를 정한다. 구글은 종류에 따라 조회 주소가 다르다.
	products, err := iapProductSet(ctx, s.DB, route)
	if err != nil {
		return err
	}
	if !products[body.ProductID] {
		return iapUnknownProduct
	}
	asked, err := iapFindProduct(ctx, s.DB, route, body.ProductID)
	if err != nil {
		return err
	}
	tokens, err := iapUserTokens(ctx, s.DB, user)
	if err != nil {
		return err
	}

	// 2. 증거를 확인하고(애플은 서명) 스토어에 다시 묻는다. 트랜잭션 밖이다.
	ref, err := store.Verify(asked.Kind, body.Proof)
	if err != nil {
		if errors.Is(err, iap.ErrWrongApp) {
			return iapRejected
		}
		return iapBadProof
	}
	storeCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
	defer cancel()
	// 스토어에서 읽기 시작한 때. 그 뒤에 알림 처리가 고친 구독 줄은 이 요청이 읽은 옛 상태로 덮어쓰지 않는다
	lookupStart := time.Now()
	submitted, err := store.Lookup(storeCtx, ref)
	if err != nil {
		return iapStoreError(route, err)
	}
	// 구독은 그 거래가 아니라 구독 1건의 지금 상태로 판단한다(갱신·유예·해지 예약이 여기에 있다).
	current := submitted
	if asked.Kind == iap.KindSubscription {
		if current, err = store.Subscription(storeCtx, submitted.OriginalTransactionID); err != nil {
			return iapStoreError(route, err)
		}
	}

	// 3. 이 요청에 지급해도 되는 거래인지 본다. 계정 문제는 주인을 확인한 뒤 트랜잭션 안에서 정한다.
	expect := iap.Expect{BundleID: store.AppID(), Products: products, AccountTokens: tokens, AllowSandbox: s.IAPSandbox}
	inactive := asked.Kind == iap.KindSubscription && current.State == iap.StateInactive
	checked := current
	if inactive {
		checked.State = iap.StatePaid // 만료·보류된 구독도 기록은 한다. 상태만 빼고 나머지를 본다
	}
	verdict := iap.Check(checked, expect)
	wrongAccount := errors.Is(verdict, iap.ErrWrongAccount)
	switch {
	case verdict == nil || wrongAccount:
	case errors.Is(verdict, iap.ErrSandbox):
		return iapSandbox
	case errors.Is(verdict, iap.ErrRevoked):
		// 스토어가 환불이라고 답했다. 알림을 놓쳤을 수 있으니 알림 처리와 같은 길로 원장·구독 줄을 고친다(회수와 고지).
		// 실패해도 409는 그대로 준다. 정기 대조가 다시 본다
		s.iapSyncRevoked(ctx, store, asked.Kind, ref, checked.OriginalTransactionID)
		return iapRefunded
	case errors.Is(verdict, iap.ErrUnknownProduct):
		// 스토어에는 있는데 우리 상품 테이블에 없다. 우리 설정 문제라 앱은 거래를 끝내지 않고 다시 낸다(구글은 소비하지 않아 3일 뒤 환불)
		log.Printf("iap unknown product: route=%s user=%d product=%s", route, user, checked.ProductID)
		return iapUnknownProduct
	case errors.Is(verdict, iap.ErrNotPaid):
		writeJSON(w, 202, map[string]any{"status": "pending"})
		return nil
	default: // 다른 앱, 모르는 상품
		log.Printf("iap rejected: route=%s user=%d reason=%v", route, user, verdict)
		return iapRejected
	}
	// 스토어가 알려 준 상품이 물어본 상품과 종류가 다르면 받지 않는다.
	bought := asked
	if current.ProductID != body.ProductID {
		if bought, err = iapFindProduct(ctx, s.DB, route, current.ProductID); err != nil {
			return err
		}
	}
	if bought.Kind != asked.Kind {
		return iapRejected
	}
	// 수량 구매(Play Console의 multi-quantity)를 켜지 않았다. 켜져 2개 이상 샀으면 1칸 값만 주지 않게 받지 않는다.
	// 소비하지 않으므로 구글이 3일 뒤 환불한다
	if submitted.Quantity > 1 {
		log.Printf("iap quantity purchase rejected: route=%s product=%s quantity=%d", route, submitted.ProductID, submitted.Quantity)
		return iapRejected
	}

	// 4. 짧은 트랜잭션: 주인 확인 → 원장 → 커밋.
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var locked int64
	if err = tx.QueryRow(ctx, "SELECT id FROM users WHERE id=$1 FOR UPDATE", user).Scan(&locked); err != nil {
		return err
	}
	status := "granted"
	grantee := user // 받을 계정. 보통 낸 사람이고, 다른 계정이 결제한 한 번 사는 상품이면 그 계정이다
	key := iapTransactionKey(asked.Kind, submitted)
	// 한 번 사는 상품만: 받은 대상(known이 false면 모름), 상한을 넘었는지
	target, known, overCap := "", false, false
	if asked.Kind == iap.KindSubscription {
		// 같은 구독 1건을 다루는 다른 제출·알림 처리와 순서를 맞춘다(줄이 아직 없을 때의 경쟁을 막는다)
		if err = iapLockLine(ctx, tx, route, current.OriginalTransactionID); err != nil {
			return err
		}
		owner, e := iapSubscriptionOwner(ctx, tx, route, current.OriginalTransactionID)
		if e != nil {
			return e
		}
		mine := owner.found && owner.user == user
		taken := owner.found && owner.user != 0 && owner.user != user
		// 다른 계정의 구독은 "구매 복원"일 때만 이 계정으로 옮긴다. 한 번에 한 계정만 가진다(D8).
		if !mine && (taken || wrongAccount) && !body.Restore {
			return iapOtherAccount
		}
		if mine {
			status = "already"
		}
		if !mine && taken {
			log.Printf("iap subscription moved: route=%s from=%d to=%d", route, owner.user, user)
		}
		// 고치기 전의 값을 읽어 둔다. 고지는 상태가 바뀐 순간에만 쓴다
		before, e := iapSubBeforeOf(ctx, tx, route, current.OriginalTransactionID)
		if e != nil {
			return e
		}
		sub := iapSubscription{
			Route: route, OriginalID: current.OriginalTransactionID, ProductID: current.ProductID, PlanID: current.PlanID, Env: current.Env,
			State: current.State, ExpiresAt: current.ExpiresAt, GraceUntil: current.GraceUntil, AutoRenew: current.AutoRenew, LatestTxnID: current.TransactionID,
			ReadAgo: time.Since(lookupStart),
		}
		if _, err = iapUpsertSubscription(ctx, tx, user, sub); err != nil {
			return err
		}
		if err = iapNoteSubscriptionChange(ctx, tx, user, before, sub, time.Now()); err != nil {
			return err
		}
		// 새로 지급한 구독이면 결제 완료를 알린다(T3). 전에 지급한 것, 구매 복원, 만료된 구독은 알리지 않는다
		if !mine && !body.Restore && !inactive && current.State == iap.StatePaid {
			if err = iapNotePurchaseDone(ctx, tx, user, asked.Kind, current, iapGrant{}); err != nil {
				return err
			}
		}
		// 구글: 이 구독이 옛 구독을 대신한 것이면(요금제 변경, 만료 전 재가입) 옛 줄기를 끝낸다.
		if err = iapEndLinked(ctx, tx, route, current.LinkedID, current.OriginalTransactionID); err != nil {
			return err
		}
		// 제출된 거래 자체도 원장에 남긴다. 이미 있으면 그대로 둔다.
		if submitted.State == iap.StatePaid {
			inserted, e := iapRecordPurchase(ctx, tx, user, asked.Kind, submitted, targeted)
			if e != nil {
				return e
			}
			// 내 구독의 처음 보는 결제 거래(iOS는 갱신 거래를 앱에도 준다): 갱신 결제 완료를 알린다(T3).
			// 처음 구매는 위에서 알렸다. 구매 복원은 새 결제가 아니라 알리지 않는다
			if inserted && mine && !body.Restore {
				if err = iapNotePurchaseDone(ctx, tx, user, asked.Kind, submitted, iapGrant{}); err != nil {
					return err
				}
			}
		}
		if inactive {
			status = "inactive"
		}
	} else {
		owner, e := iapPurchaseOwner(ctx, tx, route, key)
		if e != nil {
			return e
		}
		mine := owner.found && owner.user == user
		// 주인 없는 줄인데 대상도 없으면 한 번도 주지 않은 거래다(결제한 계정이 탈퇴). 다시 내도 같은 답과 환불이다.
		// 대상이 있으면 받은 뒤 탈퇴한 것이라 아래처럼 거절한다
		if owner.found && owner.user == 0 {
			var got *string
			if e = tx.QueryRow(ctx, "SELECT target FROM iap_purchases WHERE route=$1 AND transaction_id=$2", string(route), key).Scan(&got); e != nil {
				return e
			}
			if got == nil {
				return s.iapOwnerGoneReply(ctx, tx, store, asked.Kind, submitted, key, user, false)
			}
		}
		// 한 번 사는 상품은 다른 계정으로 옮기지 않는다(D8).
		if !mine && owner.found {
			return iapProductNoRestore
		}
		if !owner.found && wrongAccount {
			// 결제한 뒤 제출하기 전에 계정을 바꾼 경우다. 계정 연결 값으로 결제한 계정을 알면 그 계정에 넣고 확인(소비)까지 한다.
			// 그냥 409를 주면 앱이 거래를 끝내 결제한 사람은 돈만 내고 칸을 못 받는다(애플은 끝낸 소모성 거래를 다시 주지 않는다)
			if grantee, e = iapTokenOwner(ctx, tx, submitted.AccountToken); e != nil {
				return e
			}
			if _, perr := uuid.Parse(submitted.AccountToken); grantee == 0 && perr != nil {
				// UUID 모양이 아니면 우리가 발급한 값이 아니다. 탈퇴로 보지 않고 남의 값으로 거절한다(환불도 하지 않는다)
				return iapProductNoRestore
			}
			if grantee == 0 {
				// 결제한 계정이 탈퇴해 계정 연결 값 줄이 함께 지워졌다. 낸 계정에 주지 않는다(D8: 한 번 사는 상품은 계정을 옮기지 않는다, 2026-11-26 결정).
				// 주인 없이 원장에 남기고(거래 기록 보존) 커밋 뒤 환불한다. 기록 없이 거절하면 iOS는 거래를 끝내 돈만 나가고 남는 것이 없다.
				// 소비(확인)는 하지 않는다. 구글 환불이 실패해도 정기 대조가 2일 뒤 다시 환불하고, 그것도 안 되면 3일 자동 환불이 받친다
				return s.iapOwnerGoneReply(ctx, tx, store, asked.Kind, submitted, key, user, true)
			}
			log.Printf("iap product for other account: route=%s submitter=%d owner=%d", route, user, grantee)
		}
		inserted, e := iapRecordPurchase(ctx, tx, grantee, asked.Kind, submitted, targeted)
		if e != nil {
			return e
		}
		if !inserted {
			// 넣지 못했으면 그사이 누가 넣었다. 같은 거래를 다른 계정이 동시에 냈으면 진 쪽은 여기서 멈춘다
			// (위에서 주인을 볼 때는 줄이 없었다. 계정마다 잠그는 줄이 달라 서로 기다리지 않는다)
			again, e := iapPurchaseOwner(ctx, tx, route, key)
			if e != nil {
				return e
			}
			if again.user != grantee {
				return iapProductNoRestore
			}
			// 환불로 닫힌 거래를 다시 내면 "이미 지급"이 아니라 환불됐다고 답한다
			var st string
			if e := tx.QueryRow(ctx, "SELECT state FROM iap_purchases WHERE route=$1 AND transaction_id=$2", string(route), key).Scan(&st); e != nil {
				return e
			}
			if st == "revoked" {
				return iapRefunded
			}
			status = "already"
		}
		// 어느 대상의 구매인지(D1). 넣을 때 계정 연결 값으로 이미 적었다(대상이 없는 앱은 '').
		// 앱이 결제 전에 받은 예약이 있으면 그 대상을 먼저 쓴다. 애플이 새 계정 연결 값 대신 처음 값을 돌려준다는 보고가 있어서다
		// (docs/spec/erd.md 3.7). 예약은 서버가 이 유저에게 준 것이고 상한은 아래 iapSettleCap이 그대로 본다.
		// 새로 넣은 거래만 바꾼다. 알림으로 먼저 들어와 이미 셈한 거래의 대상은 건드리지 않는다
		// 예약은 이 결제를 위해 받은 것만 쓴다: 낸 사람의 것, 예약보다 뒤에 끝난 결제.
		// 앱은 그때 들고 있는 예약 번호를 붙여 내므로, 전에 끝내지 못한 옛 거래가 지금 결제의 예약을 가져가지 않게 한다
		resTarget, resKnown := "", false
		if grantee == user && body.Reservation != "" {
			if resTarget, resKnown, e = iapReservationTarget(ctx, tx, user, body.Reservation, submitted.PurchasedAt); e != nil {
				return e
			}
		}
		// 예약과 앱이 보낸 대상은 낸 사람의 것이다. 다른 계정(결제한 계정)에 넣는 거래에는 쓰지 않는다(그 계정의 대상은 계정 연결 값으로만 안다)
		if inserted && resKnown && grantee == user {
			prev, changed, e := iapPreferTarget(ctx, tx, route, key, resTarget)
			if e != nil {
				return e
			}
			if changed && prev != "" {
				log.Printf("iap target from reservation: route=%s user=%d token_target=%s reservation_target=%s", route, user, prev, resTarget)
			}
		}
		// 값도 예약도 대상을 몰랐으면 앱이 보낸 대상으로 채운다
		askedTarget := body.Target
		if grantee != user {
			askedTarget = ""
		}
		filled := false
		if target, known, filled, e = iapSetTarget(ctx, tx, route, key, askedTarget); e != nil {
			return e
		}
		if known {
			// 예약을 지나쳐 상한을 넘었으면(예약이 끝난 뒤 결제가 끝남 등) 이 거래는 주지 않고 환불한다
			if overCap, e = iapSettleCap(ctx, tx, grantee, route, key, s.IAPSandbox, s.IAPRules.Cap); e != nil {
				return e
			}
			if overCap {
				log.Printf("iap over cap: route=%s user=%d target=%s", route, user, target)
			}
			// 고지는 대상이 정해진 때 한 번 쓴다: 새로 넣으면서 대상을 안 때, 또는 대상을 몰랐던 거래에 이번에 대상을 채운 때.
			// 줬으면 결제 완료(T3), 상한을 넘었으면 넘김 고지(주지 않고 환불)
			if (inserted || filled) && !body.Restore {
				if err = iapNoteProductGrant(ctx, tx, grantee, submitted, iapGrant{Units: bought.Units, Target: target, OverCap: overCap}); err != nil {
					return err
				}
			}
		}
		// 결제 중 예약을 푼다. 번호를 모르면 새로 넣은 거래일 때만 그 대상의 가장 오래된 것 하나를 푼다
		if resKnown {
			e = iapReleaseReservation(ctx, tx, user, body.Reservation)
		} else if body.Reservation == "" && inserted && known && grantee == user {
			e = iapReleaseOldestReservation(ctx, tx, user, target)
		}
		if e != nil {
			return e
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}

	// 대상을 모르는 거래는 소비하지 않는다. 소비한 뒤 돌려보내면 앱이 거래를 끝내 돈만 받은 것이 된다.
	// 소비하지 않으면 앱이 대상을 붙여 다시 낼 수 있고, 끝내 못 내면 서버가 2일 뒤 환불한다(구글 3일 자동 환불이 받친다). 우리 앱은 늘 대상을 보낸다
	targetMissing := asked.Kind == iap.KindProduct && !known

	// 5. 커밋 뒤 스토어 확인. 실패해도 지급은 유지한다. 확인 안 된 줄은 다시 시도한다(이슈 #26, #27).
	// 요청과 떼어 낸 컨텍스트에 제한 시간을 따로 준다. 조회가 시간을 거의 다 썼거나 사용자가 앱을 닫아도 확인은 끝까지 한다
	after, cancelAfter := context.WithTimeout(context.WithoutCancel(ctx), iapStoreTimeout)
	defer cancelAfter()
	if !targetMissing && !submitted.Acknowledged && submitted.State == iap.StatePaid {
		consume := asked.Kind == iap.KindProduct && bought.Consume
		if e := store.Confirm(after, ref, submitted.ProductID, consume); e != nil {
			log.Printf("iap confirm failed (will retry): route=%s product=%s err=%v", route, submitted.ProductID, e)
		} else if e = iapMarkConfirmed(after, s.DB, route, key); e != nil {
			log.Printf("iap confirm not recorded: route=%s err=%v", route, e)
		}
	}

	// 6. 넘게 산 거래는 환불을 요청한다(구글만 된다). 소비한 뒤에 한다
	autoRefund := false
	if overCap {
		// 확인과 15초를 나눠 쓰지 않게 환불은 자기 제한 시간을 쓴다(iapRefundOverCap 안에서 준다)
		autoRefund = s.iapRefundOverCap(context.WithoutCancel(ctx), store, key, submitted.TransactionID)
	}

	if grantee != user {
		// 대상을 몰라 소비하지 않았어도 결제한 계정의 원장에는 남았다. 운영자가 noTarget으로 본다
		return s.iapGrantedToOwner()
	}
	if targetMissing {
		log.Printf("iap target missing (not consumed): route=%s user=%d product=%s", route, user, submitted.ProductID)
		return s.iapTargetMissing()
	}

	out, err := s.iapStatus(ctx, user)
	if err != nil {
		return err
	}
	out["status"] = status
	if known {
		out["target"] = target
		if overCap {
			out["overCap"] = true // 이 대상의 상한을 넘게 샀다. 주지 않고 환불한다
			out["autoRefund"] = autoRefund
		}
	}
	writeJSON(w, 200, out)
	return nil
}

// iapRefundOverCap은 상한을 넘게 산 거래의 환불을 스토어에 요청한다. DB 커밋 뒤에 부른다.
// 환불할 수 있는 스토어(구글)이면 요청하고 결과를 남긴다. 이미 요청한 거래면 다시 요청하지 않고 true다.
// 애플은 개발자가 환불할 수 없어 false다(사용자에게 애플 환불 요청을 안내한다). 실패하면 정기 처리가 다시 시도한다.
func (s *Kit) iapRefundOverCap(ctx context.Context, store iap.Store, key, orderID string) bool {
	rf, ok := store.(iap.Refunder)
	if !ok {
		return false
	}
	route := store.Route()
	var requested bool
	if err := s.DB.QueryRow(ctx, `SELECT refund_requested_at IS NOT NULL FROM iap_purchases
		WHERE route=$1 AND transaction_id=$2 AND over_cap`, string(route), key).Scan(&requested); err != nil {
		log.Printf("iap over cap refund: route=%s err=%v", route, err)
		return false
	}
	if requested {
		return true
	}
	if orderID == "" {
		// 주문 ID가 없으면(프로모션 코드로 받은 구매 등) 환불을 요청할 수 없다. 다시 해도 같으니 시도 상한으로 올려 대조에서 빼고 운영자가 처리한다
		log.Printf("iap over cap refund needs manual handling: route=%s key=%s (no order id)", route, iapShortKey(key))
		if e := iapGiveUpRefund(ctx, s.DB, route, key); e != nil {
			log.Printf("iap over cap refund not recorded: route=%s err=%v", route, e)
		}
		return false
	}
	refundCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
	defer cancel()
	err := rf.Refund(refundCtx, orderID)
	if err != nil {
		log.Printf("iap over cap refund failed (will retry): route=%s err=%v", route, err)
	}
	if e := iapNoteRefundAttempt(ctx, s.DB, route, key, err == nil); e != nil {
		log.Printf("iap over cap refund not recorded: route=%s err=%v", route, e)
	}
	// 넘김 고지에 "서버가 환불을 요청했다"를 적는다(처음 요청이 실패해 정기 처리가 다시 요청한 때도)
	if err == nil {
		if _, e := s.DB.Exec(ctx, `UPDATE iap_notices SET params = jsonb_set(params, '{autoRefund}', 'true')
			WHERE kind=$1 AND dedupe_key=$2`, noticeProductOverCap, iapOverCapDedupe(route, key)); e != nil {
			log.Printf("iap over cap notice not updated: route=%s err=%v", route, e)
		}
	}
	return err == nil
}

// iapStoreError는 스토어 조회 실패를 가른다. "그런 거래 없음"은 거절이고, 나머지는 결과를 모르는 것이라 다시 시도하게 한다.
func iapStoreError(route iap.Route, err error) error {
	if errors.Is(err, iap.ErrNotFound) {
		return iapNotFound
	}
	log.Printf("iap store lookup failed: route=%s err=%v", route, err)
	return iapStoreDown
}

// iapShortKey는 로그에 남길 거래 열쇠의 앞부분이다. 구글 구매 토큰은 비밀 값이라 통째로 남기지 않는다
func iapShortKey(key string) string {
	if len(key) > 8 {
		return key[:8] + "…"
	}
	return key
}

// iapOwnerGoneReply는 결제한 계정이 탈퇴해 주인이 없는 한 번 사는 상품 거래에 답한다. 주지 않는다(D8, 2026-11-26 결정).
// record면 주인 없이 원장에 넣는다(거래 기록 보존). 기록 없이 거절하면 iOS는 거래를 끝내 돈만 나가고 남는 것이 없다.
// 커밋한 뒤 환불한다. 소비(확인)는 하지 않는다: 구글 환불이 실패해도 정기 대조가 2일 뒤 다시 하고, 3일 자동 환불이 마지막으로 받친다
func (s *Kit) iapOwnerGoneReply(ctx context.Context, tx pgx.Tx, store iap.Store, kind iap.Kind, p iap.Purchase, key string, submitter int64, record bool) error {
	if record {
		if _, err := iapRecordPurchase(ctx, tx, 0, kind, p, s.IAPRules.TargetRequired); err != nil {
			return err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	log.Printf("iap owner gone: route=%s submitter=%d", store.Route(), submitter)
	if _, ok := store.(iap.Refunder); !ok {
		return s.iapOwnerGone("apple")
	}
	if s.iapRefundPurchase(context.WithoutCancel(ctx), store, key, p.TransactionID) {
		return s.iapOwnerGone("refunded")
	}
	return s.iapOwnerGone("later")
}

// iapRefundPurchase는 주지 않은 거래(결제한 계정이 탈퇴, 끝내 대상을 모름)의 환불을 스토어에 요청한다. DB 커밋 뒤에 부른다.
// 구글만 된다(orders.refund). 상한 넘김(iapRefundOverCap)과 같은 순서지만, 넘김 고지를 고치지 않고 over_cap 줄로 좁히지 않는다.
// 구글 권고: 받을 수 없는 구매는 3일 자동 환불에 맡기지 말고 서버가 환불한다. 이미 요청했으면 다시 부르지 않고 true다
func (s *Kit) iapRefundPurchase(ctx context.Context, store iap.Store, key, orderID string) bool {
	rf, ok := store.(iap.Refunder)
	if !ok {
		return false
	}
	route := store.Route()
	var requested bool
	if err := s.DB.QueryRow(ctx, `SELECT refund_requested_at IS NOT NULL FROM iap_purchases WHERE route=$1 AND transaction_id=$2`,
		string(route), key).Scan(&requested); err != nil {
		log.Printf("iap refund: route=%s err=%v", route, err)
		return false
	}
	if requested {
		return true
	}
	if orderID == "" {
		log.Printf("iap refund needs manual handling: route=%s key=%s (no order id)", route, iapShortKey(key))
		if e := iapGiveUpRefund(ctx, s.DB, route, key); e != nil {
			log.Printf("iap refund not recorded: route=%s err=%v", route, e)
		}
		return false
	}
	refundCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
	defer cancel()
	err := rf.Refund(refundCtx, orderID)
	if err != nil {
		log.Printf("iap refund failed (will retry): route=%s err=%v", route, err)
	}
	if _, e := s.DB.Exec(ctx, `UPDATE iap_purchases SET refund_attempts=refund_attempts+1,
		refund_requested_at=CASE WHEN $3 THEN coalesce(refund_requested_at, now()) ELSE refund_requested_at END, updated_at=now()
		WHERE route=$1 AND transaction_id=$2`, string(route), key, err == nil); e != nil {
		log.Printf("iap refund not recorded: route=%s err=%v", route, e)
	}
	return err == nil
}
