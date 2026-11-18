package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 구매 검증 API 시험. 실제 PostgreSQL과 가짜 스토어(iap.Fake)를 쓴다.
type iapEnv struct {
	srv    *Server
	t      *testing.T
	ctx    context.Context
	db     *pgxpool.Pool
	h      http.Handler
	apple  *iap.Fake
	google *iap.Fake
	shelf  string // 선반 상품 ID (칸 2개)
	plus   string // 구독 상품 ID
}

func newIAPEnv(t *testing.T) *iapEnv {
	ctx, db := iapTestDB(t)
	e := &iapEnv{t: t, ctx: ctx, db: db, shelf: iapTestID(t, "shelf"), plus: iapTestID(t, "plus"),
		apple:  &iap.Fake{R: iap.RouteApple, App: "app.covebook", Purchases: map[string]iap.Purchase{}},
		google: &iap.Fake{R: iap.RouteGoogle, App: "app.covebook", Purchases: map[string]iap.Purchase{}}}
	for _, route := range []string{"apple", "google"} {
		if _, err := db.Exec(ctx, `INSERT INTO iap_products(route,product_id,kind,entitlement,shelves) VALUES
			($1,$2,'product',NULL,2), ($1,$3,'subscription','plus',NULL)`, route, e.shelf, e.plus); err != nil {
			t.Fatal(err)
		}
	}
	srv := New(db)
	srv.IAP = map[iap.Route]iap.Store{iap.RouteApple: e.apple, iap.RouteGoogle: e.google}
	e.srv, e.h = srv, srv.Handler()
	return e
}

// user는 기기 계정을 하나 만들고 토큰과 번호를 돌려준다.
func (e *iapEnv) user() (token string, id int64) {
	e.t.Helper()
	code, body := e.call("POST", "/auth/device", "", nil)
	if code != 201 {
		e.t.Fatalf("기기 계정 %d %v", code, body)
	}
	return body["token"].(string), int64(body["userId"].(float64))
}

func (e *iapEnv) call(method, path, token string, body any) (int, map[string]any) {
	e.t.Helper()
	var data []byte
	if body != nil {
		data, _ = json.Marshal(body)
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(data))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

func (e *iapEnv) submit(token, route, product, id string, restore bool) (int, map[string]any) {
	e.t.Helper()
	return e.call("POST", "/iap/purchases", token, map[string]any{"route": route, "productId": product, "proof": id, "restore": restore})
}

func (e *iapEnv) accountToken(token string) string {
	e.t.Helper()
	code, body := e.call("GET", "/iap/me", token, nil)
	if code != 200 {
		e.t.Fatalf("/iap/me %d %v", code, body)
	}
	return body["accountToken"].(string)
}

func errCode(body map[string]any) string {
	if m, ok := body["error"].(map[string]any); ok {
		return m["code"].(string)
	}
	return ""
}

func (e *iapEnv) shelfPurchase(id, accountToken string) iap.Purchase {
	return iap.Purchase{Route: iap.RouteGoogle, OriginalTransactionID: id, BundleID: "app.covebook", ProductID: e.shelf,
		AccountToken: accountToken, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC()}
}

func (e *iapEnv) subscription(original, txn, accountToken string, expires time.Time) iap.Purchase {
	return iap.Purchase{Route: iap.RouteApple, TransactionID: txn, OriginalTransactionID: original, BundleID: "app.covebook", ProductID: e.plus,
		AccountToken: accountToken, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC(), ExpiresAt: expires, AutoRenew: true, Acknowledged: true}
}

func TestIAPRoutesOffByDefault(t *testing.T) {
	_, db := iapTestDB(t)
	h := New(db).Handler() // 결제 스위치가 꺼진 서버
	for _, path := range []string{"/iap/me", "/iap/purchases"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest("GET", path, nil))
		if rec.Code != 404 && rec.Code != 405 {
			t.Fatalf("%s: 꺼져 있는데 %d", path, rec.Code)
		}
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/healthz", nil))
	var health map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &health)
	if health["iap"] != false {
		t.Fatalf("healthz iap=%v", health["iap"])
	}
}

func TestIAPMe(t *testing.T) {
	e := newIAPEnv(t)
	if code, _ := e.call("GET", "/iap/me", "", nil); code != 401 {
		t.Fatalf("로그인 없이 %d", code)
	}
	token, _ := e.user()
	first := e.accountToken(token)
	if len(first) != 36 || e.accountToken(token) != first {
		t.Fatalf("계정 연결 값이 매번 같아야 함: %q", first)
	}
	other, _ := e.user()
	if e.accountToken(other) == first {
		t.Fatal("다른 유저와 값이 같음")
	}
	_, body := e.call("GET", "/iap/me", token, nil)
	if body["plus"] != false || body["shelves"] != float64(0) || body["subscription"] != nil {
		t.Fatalf("산 것이 없는 상태: %v", body)
	}
	if routes, _ := body["routes"].([]any); len(routes) != 2 || routes[0] != "apple" {
		t.Fatalf("routes: %v", body["routes"])
	}
	// 파는 상품 목록: 이 시험이 넣은 상품이 경로마다 들어 있고 가격은 없다
	mine := 0
	for _, raw := range body["products"].([]any) {
		p := raw.(map[string]any)
		if _, hasPrice := p["price"]; hasPrice {
			t.Fatal("상품 목록에 가격이 있음")
		}
		switch p["productId"] {
		case e.shelf:
			if p["kind"] != "product" || p["shelves"] != float64(2) {
				t.Fatalf("선반 상품: %v", p)
			}
			mine++
		case e.plus:
			if p["kind"] != "subscription" || p["entitlement"] != "plus" {
				t.Fatalf("구독 상품: %v", p)
			}
			mine++
		}
	}
	if mine != 4 {
		t.Fatalf("내 상품 %d개 (경로 2 x 상품 2 = 4여야 함)", mine)
	}
}

func TestIAPShelfPurchase(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	account := e.accountToken(token)
	id := iapTestID(t, "tok")

	// 스토어에 없는 구매
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 404 || errCode(body) != "iap_purchase_not_found" {
		t.Fatalf("없는 구매: %d %v", code, body)
	}
	// 스토어 장애: 지급하지 않고 503. 원장에 아무것도 남지 않는다
	e.google.Purchases[id] = e.shelfPurchase(id, account)
	e.google.Err = errors.New("timeout")
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 503 || errCode(body) != "iap_store_unavailable" {
		t.Fatalf("스토어 장애: %d %v", code, body)
	}
	if _, shelves, _ := iapEntitlements(e.ctx, e.db, user, false); shelves != 0 {
		t.Fatal("스토어 장애인데 지급됨")
	}
	e.google.Err = nil

	// 정상 지급. 커밋 뒤 스토어 확인이 불리고 기록된다
	code, body := e.submit(token, "google", e.shelf, id, false)
	if code != 200 || body["status"] != "granted" || body["shelves"] != float64(2) {
		t.Fatalf("지급: %d %v", code, body)
	}
	if len(e.google.Confirmed) != 1 || e.google.Confirmed[0] != id {
		t.Fatalf("스토어 확인: %v", e.google.Confirmed)
	}
	var confirmed *time.Time
	if err := e.db.QueryRow(e.ctx, "SELECT confirmed_at FROM iap_purchases WHERE route='google' AND transaction_id=$1", id).Scan(&confirmed); err != nil || confirmed == nil {
		t.Fatalf("확인 시각이 안 남음: %v %v", confirmed, err)
	}
	// 같은 구매를 다시 내면 성공으로 답하고 더 주지 않는다
	if code, body = e.submit(token, "google", e.shelf, id, false); code != 200 || body["status"] != "already" || body["shelves"] != float64(2) {
		t.Fatalf("다시 제출: %d %v", code, body)
	}
	// 다른 유저가 같은 구매를 내면 거절. 한 번 사는 상품은 복원으로도 옮기지 않는다
	thief, _ := e.user()
	e.accountToken(thief)
	for _, restore := range []bool{false, true} {
		if code, body = e.submit(thief, "google", e.shelf, id, restore); code != 409 || errCode(body) != "iap_other_account" {
			t.Fatalf("남의 구매(restore=%v): %d %v", restore, code, body)
		}
	}
	// 계정 연결 값이 남의 것인 새 구매도 거절
	id2 := iapTestID(t, "tok2")
	e.google.Purchases[id2] = e.shelfPurchase(id2, account)
	if code, body = e.submit(thief, "google", e.shelf, id2, false); code != 409 {
		t.Fatalf("남의 값: %d %v", code, body)
	}
	// 계정 연결 값이 빈 구매(앱 밖 구매)는 낸 사람에게 준다
	id3 := iapTestID(t, "tok3")
	e.google.Purchases[id3] = e.shelfPurchase(id3, "")
	if code, body = e.submit(thief, "google", e.shelf, id3, false); code != 200 || body["shelves"] != float64(2) {
		t.Fatalf("빈 값: %d %v", code, body)
	}
}

func TestIAPRejections(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	account := e.accountToken(token)
	put := func(change func(*iap.Purchase)) string {
		id := iapTestID(t, "tok")
		p := e.shelfPurchase(id, account)
		change(&p)
		e.google.Purchases[id] = p
		return id
	}
	for _, c := range []struct {
		name   string
		change func(*iap.Purchase)
		code   int
		err    string
	}{
		{"다른 앱", func(p *iap.Purchase) { p.BundleID = "com.other" }, 422, "iap_purchase_rejected"},
		{"스토어가 알려 준 상품이 우리 것이 아님", func(p *iap.Purchase) { p.ProductID = "모르는 상품" }, 422, "iap_purchase_rejected"},
		{"환불됨", func(p *iap.Purchase) { p.State = iap.StateRevoked }, 409, "iap_purchase_refunded"},
	} {
		if code, body := e.submit(token, "google", e.shelf, put(c.change), false); code != c.code || errCode(body) != c.err {
			t.Errorf("%s: %d %v", c.name, code, body)
		}
	}
	// 결제 대기: 202, 지급도 스토어 확인도 없다
	before := len(e.google.Confirmed)
	if code, body := e.submit(token, "google", e.shelf, put(func(p *iap.Purchase) { p.State = iap.StatePending }), false); code != 202 || body["status"] != "pending" {
		t.Fatalf("결제 대기: %d %v", code, body)
	}
	if len(e.google.Confirmed) != before {
		t.Fatal("결제 대기인데 스토어 확인을 부름")
	}
	// 우리가 팔지 않는 상품 ID로 요청
	if code, body := e.submit(token, "google", "없는 상품", "x", false); code != 422 || errCode(body) != "iap_unknown_product" {
		t.Fatalf("없는 상품: %d %v", code, body)
	}
	// 스토어가 알려 준 상품의 종류가 물어본 것과 다름(선반으로 물었는데 구독이 옴)
	if code, _ := e.submit(token, "google", e.shelf, put(func(p *iap.Purchase) { p.ProductID = e.plus }), false); code != 422 {
		t.Fatalf("종류가 다름: %d", code)
	}
	// 틀린 요청
	for _, b := range []map[string]any{{"route": "toss", "productId": e.shelf, "proof": "x"}, {"route": "google", "productId": e.shelf}, {"route": "google", "proof": "x"},
		{"route": "google", "productId": e.shelf, "id": "x"}} { // 옛 모양(id)은 받지 않는다
		if code, _ := e.call("POST", "/iap/purchases", token, b); code != 400 {
			t.Errorf("틀린 요청 %v: %d", b, code)
		}
	}
	if code, _ := e.submit("", "google", e.shelf, "x", false); code != 401 {
		t.Fatalf("로그인 없이 %d", code)
	}
	if plus, shelves, _ := iapEntitlements(e.ctx, e.db, user, false); plus || shelves != 0 {
		t.Fatalf("거절뿐인데 지급됨: %v %d", plus, shelves)
	}
}

func TestIAPConfirmRetry(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	id := iapTestID(t, "tok")
	e.google.Purchases[id] = e.shelfPurchase(id, e.accountToken(token))
	// 스토어 확인이 실패해도 지급은 된다. 확인 시각은 비어 있다
	e.google.ConfirmErr = errors.New("503")
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 || body["shelves"] != float64(2) {
		t.Fatalf("확인 실패 시 지급: %d %v", code, body)
	}
	var confirmed *time.Time
	q := "SELECT confirmed_at FROM iap_purchases WHERE route='google' AND transaction_id=$1"
	if err := e.db.QueryRow(e.ctx, q, id).Scan(&confirmed); err != nil || confirmed != nil {
		t.Fatalf("확인 실패인데 확인 시각이 있음: %v %v", confirmed, err)
	}
	// 다시 제출하면 확인을 다시 시도한다
	e.google.ConfirmErr = nil
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 || body["status"] != "already" {
		t.Fatalf("다시 제출: %d %v", code, body)
	}
	if err := e.db.QueryRow(e.ctx, q, id).Scan(&confirmed); err != nil || confirmed == nil {
		t.Fatal("다시 시도했는데 확인 시각이 없음")
	}
	// 이미 확인된 구매는 스토어 확인을 부르지 않는다
	id2 := iapTestID(t, "tok2")
	p := e.shelfPurchase(id2, "")
	p.Acknowledged = true
	e.google.Purchases[id2] = p
	before := len(e.google.Confirmed)
	if code, _ := e.submit(token, "google", e.shelf, id2, false); code != 200 || len(e.google.Confirmed) != before {
		t.Fatalf("이미 확인된 구매: %d %v", code, e.google.Confirmed)
	}
}

func TestIAPSubscriptionAndRestore(t *testing.T) {
	e := newIAPEnv(t)
	a, _ := e.user()
	b, _ := e.user()
	accountA := e.accountToken(a)
	e.accountToken(b)
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[txn] = e.subscription(orig, txn, accountA, time.Now().Add(time.Hour))

	code, body := e.submit(a, "apple", e.plus, txn, false)
	if code != 200 || body["status"] != "granted" || body["plus"] != true {
		t.Fatalf("구독 지급: %d %v", code, body)
	}
	sub, _ := body["subscription"].(map[string]any)
	if sub == nil || sub["route"] != "apple" || sub["active"] != true || sub["autoRenew"] != true {
		t.Fatalf("구독 정보: %v", body["subscription"])
	}
	if code, body = e.submit(a, "apple", e.plus, txn, false); code != 200 || body["status"] != "already" {
		t.Fatalf("다시 제출: %d %v", code, body)
	}
	// 다른 계정은 그냥은 못 가져간다
	if code, body = e.submit(b, "apple", e.plus, txn, false); code != 409 || errCode(body) != "iap_other_account" {
		t.Fatalf("남의 구독: %d %v", code, body)
	}
	// 구매 복원이면 옮긴다. 한 번에 한 계정만 가진다
	if code, body = e.submit(b, "apple", e.plus, txn, true); code != 200 || body["plus"] != true {
		t.Fatalf("복원: %d %v", code, body)
	}
	if _, body = e.call("GET", "/iap/me", a, nil); body["plus"] != false {
		t.Fatalf("옮긴 뒤에도 원래 계정에 권한이 있음: %v", body)
	}
	// 옮겨 받은 계정은 계정 연결 값이 옛 주인의 것이어도 그냥 제출할 수 있다(주인은 우리 표가 정한다)
	if code, body = e.submit(b, "apple", e.plus, txn, false); code != 200 || body["status"] != "already" {
		t.Fatalf("옮겨 받은 뒤 제출: %d %v", code, body)
	}
	// 원래 계정은 복원 없이는 되찾지 못한다
	if code, _ = e.submit(a, "apple", e.plus, txn, false); code != 409 {
		t.Fatalf("원래 계정의 재제출: %d", code)
	}
	// 갱신: 같은 줄기에 새 거래. 구독 줄은 하나로 유지되고 거래 줄은 늘어난다
	txn2 := iapTestID(t, "txn2")
	e.apple.Purchases[txn2] = e.subscription(orig, txn2, accountA, time.Now().Add(48*time.Hour))
	if code, body = e.submit(b, "apple", e.plus, txn2, false); code != 200 || body["plus"] != true {
		t.Fatalf("갱신 제출: %d %v", code, body)
	}
	var subs, txns int
	if err := e.db.QueryRow(e.ctx, "SELECT (SELECT count(*) FROM iap_subscriptions WHERE original_id=$1),(SELECT count(*) FROM iap_purchases WHERE original_id=$1)", orig).Scan(&subs, &txns); err != nil || subs != 1 || txns != 2 {
		t.Fatalf("구독 줄 %d, 거래 줄 %d, %v", subs, txns, err)
	}
}

func TestIAPInactiveSubscription(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	p := e.subscription(orig, txn, e.accountToken(token), time.Now().Add(-time.Hour))
	p.State = iap.StateInactive
	e.apple.Purchases[txn] = p
	// 만료·보류된 구독: 오류가 아니라 "권한 없음"으로 답하고 상태는 기록한다
	code, body := e.submit(token, "apple", e.plus, txn, true)
	if code != 200 || body["status"] != "inactive" || body["plus"] != false {
		t.Fatalf("만료된 구독: %d %v", code, body)
	}
	if sub, _ := body["subscription"].(map[string]any); sub == nil || sub["active"] != false || sub["state"] != "inactive" {
		t.Fatalf("구독 정보: %v", body["subscription"])
	}
	// 만료 시각은 지났는데 스토어 상태를 아직 못 받아 "결제됨"으로 남은 줄: 권한은 없고 /iap/me는 정상 응답해야 한다
	// (유예 끝이 NULL일 때 `만료 지남 OR NULL`이 NULL이 되어 500이 나던 버그의 회귀 시험)
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET state='paid', expires_at=now()-interval '1 minute', grace_until=NULL WHERE original_id=$1", orig); err != nil {
		t.Fatal(err)
	}
	if code, me := e.call("GET", "/iap/me", token, nil); code != 200 || me["plus"] != false {
		t.Fatalf("만료 직후의 /iap/me: %d %v", code, me)
	} else if sub, _ := me["subscription"].(map[string]any); sub == nil || sub["active"] != false || sub["state"] != "paid" {
		t.Fatalf("만료 직후의 구독 정보: %v", me["subscription"])
	}
	// 유예 중이면 만료 시각이 지나도 권한이 있다
	p.State, p.GraceUntil = iap.StatePaid, time.Now().Add(time.Hour)
	e.apple.Purchases[txn] = p
	if code, body = e.submit(token, "apple", e.plus, txn, false); code != 200 || body["plus"] != true {
		t.Fatalf("유예 중: %d %v", code, body)
	}
}

// 같은 구매를 동시에 여러 번 내도 한 번만 지급된다.
func TestIAPConcurrentSubmit(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	id := iapTestID(t, "tok")
	p := e.shelfPurchase(id, e.accountToken(token))
	p.Acknowledged = true // 가짜 스토어의 확인 기록은 동시 쓰기에 안전하지 않아 여기서는 부르지 않게 한다
	e.google.Purchases[id] = p
	statuses := make(chan string, 12)
	var wg sync.WaitGroup
	for range 12 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			code, body := e.submit(token, "google", e.shelf, id, false)
			if code != 200 {
				t.Errorf("동시 제출 %d %v", code, body)
			}
			statuses <- body["status"].(string)
		}()
	}
	wg.Wait()
	close(statuses)
	granted := 0
	for s := range statuses {
		if s == "granted" {
			granted++
		}
	}
	if _, shelves, _ := iapEntitlements(e.ctx, e.db, user, false); granted != 1 || shelves != 2 {
		t.Fatalf("granted %d번, 선반 %d칸 (1번, 2칸이어야 함)", granted, shelves)
	}
}

// 구매 증거가 스토어가 서명한 것이 아니면 스토어에 묻지도 않고 거절한다.
// 애플 거래 ID는 추측할 수 있어서, 번호만으로 남의 구매를 내거나 복원으로 남의 구독을 가져가는 것을 막는다.
func TestIAPForgedProof(t *testing.T) {
	e := newIAPEnv(t)
	owner, _ := e.user()
	thief, thiefID := e.user()
	e.accountToken(thief)
	orig := iapTestID(t, "orig")
	// 스토어에는 owner의 구독이 있다. 가짜 스토어는 forged로 시작하는 증거를 서명 실패로 본다
	forged := "forged-" + iapTestID(t, "txn")
	e.apple.Purchases[forged] = e.subscription(orig, forged, e.accountToken(owner), time.Now().Add(time.Hour))
	for _, restore := range []bool{false, true} {
		if code, body := e.submit(thief, "apple", e.plus, forged, restore); code != 422 || errCode(body) != "iap_bad_proof" {
			t.Fatalf("위조 증거(restore=%v): %d %v", restore, code, body)
		}
	}
	if plus, _, _ := iapEntitlements(e.ctx, e.db, thiefID, true); plus {
		t.Fatal("위조 증거로 구독을 가져감")
	}
}

// 샌드박스 거래는 스위치를 켰을 때만 지급한다. 끄면 전에 준 것도 사라진다.
func TestIAPSandboxSwitch(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	id := iapTestID(t, "tok")
	p := e.shelfPurchase(id, e.accountToken(token))
	p.Env = iap.EnvSandbox
	e.google.Purchases[id] = p
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 422 || errCode(body) != "iap_sandbox_not_allowed" {
		t.Fatalf("스위치 꺼짐: %d %v", code, body)
	}
	e.srv.IAPSandbox = true
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 || body["shelves"] != float64(2) {
		t.Fatalf("스위치 켜짐: %d %v", code, body)
	}
	e.srv.IAPSandbox = false
	if _, body := e.call("GET", "/iap/me", token, nil); body["shelves"] != float64(0) {
		t.Fatalf("스위치를 껐는데 샌드박스 선반이 남음: %v", body)
	}
}

// 한 유저가 짧은 시간에 너무 많이 내면 막는다(증거를 추측해 넣어 보는 것을 늦춘다).
func TestIAPSubmitLimit(t *testing.T) {
	e := newIAPEnv(t)
	token, id := e.user()
	other, _ := e.user()
	last := 0
	for range iapSubmitLimit + 1 {
		last, _ = e.submit(token, "google", e.shelf, "없는 토큰", false)
	}
	if last != 429 {
		t.Fatalf("한도를 넘겼는데 %d", last)
	}
	// 다른 유저는 영향받지 않는다
	if code, _ := e.submit(other, "google", e.shelf, "없는 토큰", false); code != 404 {
		t.Fatalf("다른 유저: %d", code)
	}
	// 1분이 지나면 다시 받는다
	if !e.srv.iapAllow(id, time.Now().Add(2*time.Minute)) {
		t.Fatal("1분 뒤에도 막힘")
	}
}
