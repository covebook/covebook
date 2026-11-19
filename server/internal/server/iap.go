package server

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
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

// 결제 스위치(IAP_ENABLED=1): 꺼져 있으면 API가 아예 없다. 스토어 키가 없거나 틀려도 꺼진다(서버는 뜬다).
func iapEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("IAP_ENABLED"))) {
	case "1", "true", "on", "yes":
		return true
	}
	return false
}

// iapFromEnv는 스위치가 켜져 있을 때 환경변수로 스토어를 만든다. 실패하면 결제를 끈 채로 둔다.
func iapFromEnv() map[iap.Route]iap.Store {
	if !iapEnabled() {
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

// 샌드박스 스위치(IAP_ALLOW_SANDBOX=1): 샌드박스(TestFlight, 심사, 시험 계정) 거래에도 지급한다.
// 기본은 꺼짐이다. 켜 두면 실제로 결제하지 않은 사람이 운영 권한을 받는다(조사 종합 6-1장, 이슈 #31).
// 심사와 내부 시험 기간에만 켠다. 끄면 전에 준 샌드박스 권한도 함께 사라진다.
func iapSandboxAllowed() bool {
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
func (s *Server) iapAllow(user int64, now time.Time) bool {
	s.iapMu.Lock()
	defer s.iapMu.Unlock()
	if s.iapHits == nil || len(s.iapHits) > 10000 {
		s.iapHits = map[int64]iapHit{}
	}
	h := s.iapHits[user]
	if now.Sub(h.window) >= time.Minute {
		h = iapHit{window: now}
	}
	h.count++
	s.iapHits[user] = h
	return h.count <= iapSubmitLimit
}

func (s *Server) routeIAP(m *http.ServeMux) {
	if len(s.IAP) == 0 {
		return
	}
	m.HandleFunc("GET /iap/me", wrap(s.iapMe))
	m.HandleFunc("POST /iap/purchases", wrap(s.iapSubmit))
	m.HandleFunc("POST /iap/shelf-token", wrap(s.iapShelfTokenFor))
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
	iapShelfFull        = apiError{409, "iap_shelf_full", "이 책장의 추가 선반을 모두 열었어요"}
	iapShelfYearMissing = apiError{422, "iap_shelf_year_missing", "어느 해 책장의 선반인지 알 수 없어요. 문의해 주시면 확인해 드릴게요"}
)

// iapMe는 결제에 필요한 내 정보를 준다: 스토어에 넘길 계정 연결 값, 지금 가진 것, 구독 상태, 파는 상품.
// 앱은 결제를 시작하기 전에 이것을 불러 계정 연결 값을 받는다.
func (s *Server) iapMe(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
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
	writeJSON(w, 200, out)
	return nil
}

// iapStatus는 지금 가진 것을 표에서 계산한다. 따로 저장한 값이 없다(D5).
func (s *Server) iapStatus(ctx context.Context, user int64) (map[string]any, error) {
	plus, shelves, err := iapEntitlements(ctx, s.DB, user, s.IAPSandbox)
	if err != nil {
		return nil, err
	}
	sub, err := iapCurrentSubscription(ctx, s.DB, user, s.IAPSandbox)
	if err != nil {
		return nil, err
	}
	// 연도 책장마다 산 칸 수. 키는 연도 문자열("2026"), 산 칸이 없는 해는 없다. 칸 수는 iapPaidShelfMax를 넘지 않는다
	return map[string]any{"plus": plus, "shelvesByYear": shelves, "paidShelfMax": iapPaidShelfMax, "subscription": sub}, nil
}

// iapShelfTokenFor는 그 연도 책장의 추가 선반을 살 때 스토어에 넘길 계정 연결 값을 준다(D1).
// 앱은 선반 결제를 시작하기 직전에 이것을 부르고, 받은 값을 애플 appAccountToken·구글 obfuscatedAccountId로 넘긴다.
// 서버는 거래에 돌아온 이 값으로 어느 해 책장의 칸인지 찾는다.
//
// 요청: {"year":2026}
// 응답 200: {"token":"uuid", "year":2026, "shelves":n}  shelves는 그 해에 이미 산 칸 수
// 응답 409 iap_shelf_full: 그 해 책장의 유료 칸을 모두 열었다. 결제를 시작하지 않는다
func (s *Server) iapShelfTokenFor(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
	if err != nil {
		return err
	}
	var body struct {
		Year int `json:"year"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if !iapValidYear(body.Year) {
		return bad
	}
	if !s.iapAllow(user, time.Now()) {
		return iapTooMany
	}
	ctx := r.Context()
	paid, err := iapShelfPaid(ctx, s.DB, user, body.Year, s.IAPSandbox)
	if err != nil {
		return err
	}
	if paid >= iapPaidShelfMax {
		return iapShelfFull
	}
	token, err := iapShelfToken(ctx, s.DB, user, body.Year)
	if err != nil {
		return err
	}
	writeJSON(w, 200, map[string]any{"token": token, "year": body.Year, "shelves": paid})
	return nil
}

// iapValidYear는 연도 책장 표(bookcases)와 같은 범위다.
func iapValidYear(year int) bool { return year >= 2000 && year <= 9999 }

// iapSubmit은 앱이 제출한 구매를 스토어에 확인하고 지급한다.
//
// 요청: {"route":"apple|google", "productId":"...", "proof":"애플: 스토어가 서명한 거래(JWS). 구글: 구매 토큰", "restore":false, "year":2026}
//
// year는 추가 선반에만 쓴다. 어느 해 책장의 칸인지는 거래에 돌아온 계정 연결 값(POST /iap/shelf-token)으로 정하고,
// 그 값이 연도를 모를 때만(앱 밖에서 산 구매 등) year를 쓴다. 둘 다 없으면 거래는 기록하고 422 iap_shelf_year_missing이다.
//
// proof는 "내가 이 구매를 한 기기"라는 증거다. 애플 거래 ID(숫자)는 받지 않는다. 추측할 수 있어서
// 남의 구매를 내거나 restore로 남의 구독을 가져갈 수 있기 때문이다. 서명된 거래는 구매한 기기만 가진다.
// 응답 200: {"status":"granted|already|inactive", "plus":bool, "shelvesByYear":{"2026":n}, "subscription":{...}}
//
//	추가 선반이면 "year"(칸이 열린 책장)도 준다. 그 해에 3칸을 넘게 샀으면 "overCap":true(넘은 칸은 환불 대상)
//
//	granted  새로 지급했다        already  전에 지급한 거래다        inactive  구독이 만료·보류 상태라 권한이 없다
//
// 응답 202: {"status":"pending"}  결제가 아직 끝나지 않았다(구글 결제 대기). 지급하지 않았다
//
// 앱이 거래를 끝내도 되는 때: 200, 그리고 다시 보내도 결과가 같은 409·422.
// 끝내면 안 되는 때: 202, 503, 5xx. 스토어가 다시 전달하면 다시 제출한다.
func (s *Server) iapSubmit(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
	if err != nil {
		return err
	}
	var body struct {
		Route     string `json:"route"`
		ProductID string `json:"productId"`
		Proof     string `json:"proof"`
		Restore   bool   `json:"restore"`
		Year      int    `json:"year"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	store := s.IAP[iap.Route(body.Route)]
	if store == nil || body.ProductID == "" || body.Proof == "" || len(body.Proof) > 16384 || (body.Year != 0 && !iapValidYear(body.Year)) {
		return bad
	}
	if !s.iapAllow(user, time.Now()) {
		return iapTooMany
	}
	ctx := r.Context()
	route := store.Route()

	// 1. 우리 표로 상품 종류를 정한다. 구글은 종류에 따라 조회 주소가 다르다.
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
	submitted, err := store.Lookup(storeCtx, ref)
	if err != nil {
		return iapStoreError(route, err)
	}
	// 구독은 그 거래가 아니라 구독 줄기의 지금 상태로 판단한다(갱신·유예·해지 예약이 여기에 있다).
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
		return iapRefunded
	case errors.Is(verdict, iap.ErrNotPaid):
		writeJSON(w, 202, map[string]any{"status": "pending"})
		return nil
	default: // 다른 앱, 모르는 상품
		log.Printf("iap rejected: route=%s user=%d reason=%v", route, user, verdict)
		return iapRejected
	}
	// 스토어가 알려 준 상품이 물어본 상품과 종류가 다르면 받지 않는다.
	bought, err := iapFindProduct(ctx, s.DB, route, current.ProductID)
	if err != nil {
		return err
	}
	if bought.Kind != asked.Kind {
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
	key := iapTransactionKey(asked.Kind, submitted)
	shelfYear, overCap := 0, false // 추가 선반만
	if asked.Kind == iap.KindSubscription {
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
		if _, err = iapUpsertSubscription(ctx, tx, user, iapSubscription{
			Route: route, OriginalID: current.OriginalTransactionID, ProductID: current.ProductID, PlanID: current.PlanID, Env: current.Env,
			State: current.State, ExpiresAt: current.ExpiresAt, GraceUntil: current.GraceUntil, AutoRenew: current.AutoRenew, LatestTxnID: current.TransactionID,
		}); err != nil {
			return err
		}
		// 제출된 거래 자체도 원장에 남긴다. 이미 있으면 그대로 둔다.
		if submitted.State == iap.StatePaid {
			if _, err = iapRecordPurchase(ctx, tx, user, asked.Kind, submitted); err != nil {
				return err
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
		// 한 번 사는 상품은 다른 계정으로 옮기지 않는다(D8).
		if !mine && (owner.found || wrongAccount) {
			return iapProductNoRestore
		}
		inserted, e := iapRecordPurchase(ctx, tx, user, asked.Kind, submitted)
		if e != nil {
			return e
		}
		if !inserted {
			status = "already"
		}
		// 어느 해 책장의 칸인지(D1). 넣을 때 계정 연결 값으로 이미 적었다. 값이 연도를 몰랐으면 앱이 보낸 연도로 채운다
		if shelfYear, e = iapSetShelfYear(ctx, tx, route, key, body.Year); e != nil {
			return e
		}
		if shelfYear > 0 {
			paid, e := iapShelfPaid(ctx, tx, user, shelfYear, s.IAPSandbox)
			if e != nil {
				return e
			}
			// 두 기기에서 동시에 사면 3칸을 넘을 수 있다. 칸은 3칸까지만 열고, 넘은 거래는 운영자가 환불한다
			if overCap = paid > iapPaidShelfMax; overCap {
				log.Printf("iap shelf over cap: route=%s user=%d year=%d paid=%d", route, user, shelfYear, paid)
			}
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}

	// 5. 커밋 뒤 스토어 확인. 실패해도 지급은 유지한다. 확인 안 된 줄은 다시 시도한다(이슈 #26, #27).
	if !submitted.Acknowledged && submitted.State == iap.StatePaid {
		consume := asked.Kind == iap.KindProduct && bought.Consume
		if e := store.Confirm(storeCtx, ref, submitted.ProductID, consume); e != nil {
			log.Printf("iap confirm failed (will retry): route=%s product=%s err=%v", route, submitted.ProductID, e)
		} else if e = iapMarkConfirmed(ctx, s.DB, route, key); e != nil {
			log.Printf("iap confirm not recorded: route=%s err=%v", route, e)
		}
	}

	if asked.Kind == iap.KindProduct && shelfYear == 0 {
		log.Printf("iap shelf year missing: route=%s user=%d product=%s", route, user, submitted.ProductID)
		return iapShelfYearMissing
	}

	out, err := s.iapStatus(ctx, user)
	if err != nil {
		return err
	}
	out["status"] = status
	if shelfYear > 0 {
		out["year"] = shelfYear
		if overCap {
			out["overCap"] = true // 이 해 책장에 3칸을 넘게 샀다. 넘은 칸은 환불 대상
		}
	}
	writeJSON(w, 200, out)
	return nil
}

// iapStoreError는 스토어 조회 실패를 가른다. "그런 거래 없음"은 거절이고, 나머지는 결과를 모르는 것이라 다시 시도하게 한다.
func iapStoreError(route iap.Route, err error) error {
	if errors.Is(err, iap.ErrNotFound) {
		return iapNotFound
	}
	log.Printf("iap store lookup failed: route=%s err=%v", route, err)
	return iapStoreDown
}
