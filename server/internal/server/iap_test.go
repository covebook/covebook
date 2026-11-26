package server

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
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
	google *iap.FakeRefunder // 구글은 개발자가 환불할 수 있다
	shelf  string            // 선반 상품 ID (칸 2개. 시험에서 3칸 넘김을 보려고 1칸·3칸이 아니라 2칸으로 둔다)
	plus   string            // 구독 상품 ID
}

func newIAPEnv(t *testing.T) *iapEnv {
	ctx, db := iapTestDB(t)
	e := &iapEnv{t: t, ctx: ctx, db: db, shelf: iapTestID(t, "shelf"), plus: iapTestID(t, "plus"),
		apple:  &iap.Fake{R: iap.RouteApple, App: "app.covebook", Purchases: map[string]iap.Purchase{}},
		google: &iap.FakeRefunder{Fake: &iap.Fake{R: iap.RouteGoogle, App: "app.covebook", Purchases: map[string]iap.Purchase{}}}}
	for _, route := range []string{"apple", "google"} {
		if _, err := db.Exec(ctx, `INSERT INTO iap_products(route,product_id,kind,entitlement,shelves) VALUES
			($1,$2,'product',NULL,2), ($1,$3,'subscription','plus',NULL)`, route, e.shelf, e.plus); err != nil {
			t.Fatal(err)
		}
	}
	srv := New(db)
	srv.IAP = map[iap.Route]iap.Store{iap.RouteApple: e.apple, iap.RouteGoogle: e.google}
	// 구글 알림 요청의 인증: 시험에서는 "Bearer pubsub"만 통과시킨다
	srv.iapPushAuth = func(_ context.Context, header string) error {
		if header != "Bearer pubsub" {
			return errors.New("bad token")
		}
		return nil
	}
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

// shelfToken은 그 해 책장의 선반을 살 때 스토어에 넘길 값을 받는다. 같이 잡힌 결제 중 예약은 바로 푼다(값만 쓰는 시험용)
func (e *iapEnv) shelfToken(token string, year int) string {
	e.t.Helper()
	code, body := e.call("POST", "/iap/shelf-token", token, map[string]any{"year": year})
	if code != 200 {
		e.t.Fatalf("/iap/shelf-token %d %v", code, body)
	}
	e.release(token, body)
	return body["token"].(string)
}

// release는 /iap/shelf-token 응답의 결제 중 예약을 푼다.
func (e *iapEnv) release(token string, body map[string]any) {
	e.t.Helper()
	if code, out := e.call("POST", "/iap/shelf-token/release", token, map[string]any{"reservation": body["reservation"]}); code != 204 {
		e.t.Fatalf("예약 풀기 %d %v", code, out)
	}
}

func (e *iapEnv) submitYear(token, route, product, id string, year int) (int, map[string]any) {
	e.t.Helper()
	return e.call("POST", "/iap/purchases", token, map[string]any{"route": route, "productId": product, "proof": id, "year": year})
}

// shelvesIn은 응답의 shelvesByYear에서 그 해 칸 수를 꺼낸다. 없으면 0이다.
func shelvesIn(body map[string]any, year int) float64 {
	m, _ := body["shelvesByYear"].(map[string]any)
	n, _ := m[strconv.Itoa(year)].(float64)
	return n
}

func errCode(body map[string]any) string {
	if m, ok := body["error"].(map[string]any); ok {
		return m["code"].(string)
	}
	return ""
}

func (e *iapEnv) shelfPurchase(id, accountToken string) iap.Purchase {
	return iap.Purchase{Route: iap.RouteGoogle, TransactionID: "GPA." + id, OriginalTransactionID: id, BundleID: "app.covebook", ProductID: e.shelf,
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
	if byYear, _ := body["shelvesByYear"].(map[string]any); body["plus"] != false || byYear == nil || len(byYear) != 0 || body["subscription"] != nil || body["paidShelfMax"] != float64(3) {
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
	account := e.shelfToken(token, 2026)
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
	if _, shelves, _ := iapEntitlements(e.ctx, e.db, user, false); len(shelves) != 0 {
		t.Fatal("스토어 장애인데 지급됨")
	}
	e.google.Err = nil

	// 정상 지급. 커밋 뒤 스토어 확인이 불리고 기록된다
	code, body := e.submit(token, "google", e.shelf, id, false)
	if code != 200 || body["status"] != "granted" || shelvesIn(body, 2026) != 2 {
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
	if code, body = e.submit(token, "google", e.shelf, id, false); code != 200 || body["status"] != "already" || shelvesIn(body, 2026) != 2 {
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
	// 계정 연결 값이 UUID 모양이 아닌 구매: 요청이 실패하지 않고, 남의 값으로 보아 거절한다
	odd := iapTestID(t, "odd")
	e.google.Purchases[odd] = e.shelfPurchase(odd, "uuid가-아닌-값")
	if code, body = e.submit(thief, "google", e.shelf, odd, false); code != 409 || errCode(body) != "iap_other_account" {
		t.Fatalf("UUID가 아닌 값: %d %v", code, body)
	}
	// 계정 연결 값이 빈 구매(앱 밖 구매)는 낸 사람에게, 앱이 보낸 연도 책장에 준다
	id3 := iapTestID(t, "tok3")
	e.google.Purchases[id3] = e.shelfPurchase(id3, "")
	if code, body = e.submitYear(thief, "google", e.shelf, id3, 2026); code != 200 || shelvesIn(body, 2026) != 2 {
		t.Fatalf("빈 값: %d %v", code, body)
	}
}

func TestIAPRejections(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	account := e.shelfToken(token, 2026)
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
		{"스토어가 알려 준 상품이 우리 것이 아님(우리 설정 문제라 끝내지 않게 따로 답함)", func(p *iap.Purchase) { p.ProductID = "모르는 상품" }, 422, "iap_unknown_product"},
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
	if plus, shelves, _ := iapEntitlements(e.ctx, e.db, user, false); plus || len(shelves) != 0 {
		t.Fatalf("거절뿐인데 지급됨: %v %v", plus, shelves)
	}
}

func TestIAPConfirmRetry(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	id := iapTestID(t, "tok")
	e.google.Purchases[id] = e.shelfPurchase(id, e.shelfToken(token, 2026))
	// 스토어 확인이 실패해도 지급은 된다. 확인 시각은 비어 있다
	e.google.ConfirmErr = errors.New("503")
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 || shelvesIn(body, 2026) != 2 {
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
	if code, _ := e.submitYear(token, "google", e.shelf, id2, 2026); code != 200 || len(e.google.Confirmed) != before {
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
	// 옮겨 받은 계정은 계정 연결 값이 옛 주인의 것이어도 그냥 제출할 수 있다(주인은 우리 테이블이 정한다)
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
	p := e.shelfPurchase(id, e.shelfToken(token, 2026))
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
	if _, shelves, _ := iapEntitlements(e.ctx, e.db, user, false); granted != 1 || shelves[2026] != 2 {
		t.Fatalf("granted %d번, 선반 %v (1번, 2026년 2칸이어야 함)", granted, shelves)
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
	p := e.shelfPurchase(id, e.shelfToken(token, 2026))
	p.Env = iap.EnvSandbox
	e.google.Purchases[id] = p
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 422 || errCode(body) != "iap_sandbox_not_allowed" {
		t.Fatalf("스위치 꺼짐: %d %v", code, body)
	}
	e.srv.IAPSandbox = true
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 || shelvesIn(body, 2026) != 2 {
		t.Fatalf("스위치 켜짐: %d %v", code, body)
	}
	e.srv.IAPSandbox = false
	if _, body := e.call("GET", "/iap/me", token, nil); shelvesIn(body, 2026) != 0 {
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

// 추가 선반은 연도 책장마다 따로 열고, 한 책장에서 돈을 내고 여는 칸은 3칸까지다(D1).
// shelfProduct는 칸 수가 n인 선반 상품을 하나 더 만든다(두 경로 모두).
func (e *iapEnv) shelfProduct(n int) string {
	e.t.Helper()
	id := iapTestID(e.t, "shelf"+strconv.Itoa(n))
	if _, err := e.db.Exec(e.ctx, `INSERT INTO iap_products(route,product_id,kind,shelves) VALUES('apple',$1,'product',$2),('google',$1,'product',$2)`, id, n); err != nil {
		e.t.Fatal(err)
	}
	return id
}

func TestIAPShelfYears(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()

	// 연도 토큰: 로그인 필요, 책장 테이블과 같은 연도 범위, 같은 해에는 같은 값
	if code, _ := e.call("POST", "/iap/shelf-token", "", map[string]any{"year": 2026}); code != 401 {
		t.Fatalf("로그인 없이 %d", code)
	}
	for _, y := range []any{1999, 10000, 0, "2026"} {
		if code, _ := e.call("POST", "/iap/shelf-token", token, map[string]any{"year": y}); code != 400 {
			t.Errorf("연도 %v: %d", y, code)
		}
	}
	y2026 := e.shelfToken(token, 2026)
	if len(y2026) != 36 || e.shelfToken(token, 2026) != y2026 || e.shelfToken(token, 2027) == y2026 || e.accountToken(token) == y2026 {
		t.Fatal("연도 토큰이 해마다 하나가 아님")
	}

	buy := func(accountToken string, year int) (int, map[string]any) {
		t.Helper()
		id := iapTestID(t, "tok")
		e.google.Purchases[id] = e.shelfPurchase(id, accountToken)
		return e.submitYear(token, "google", e.shelf, id, year)
	}
	// 2026년 책장에 2칸
	code, body := buy(y2026, 0)
	if code != 200 || body["year"] != float64(2026) || shelvesIn(body, 2026) != 2 || body["overCap"] != nil {
		t.Fatalf("2026년 첫 구매: %d %v", code, body)
	}
	if _, body = e.call("POST", "/iap/shelf-token", token, map[string]any{"year": 2026}); body["shelves"] != float64(2) {
		t.Fatalf("연도 토큰의 산 칸 수: %v", body)
	}
	e.release(token, body)
	// 앱이 다른 연도를 보내도 연도 토큰이 정한다
	code, body = buy(y2026, 2030)
	if code != 200 || body["year"] != float64(2026) || shelvesIn(body, 2030) != 0 {
		t.Fatalf("연도 토큰과 다른 연도: %d %v", code, body)
	}
	// 2칸 + 2칸 = 4칸: 넘은 거래는 통째로 칸을 주지 않고 환불한다(구글은 서버가 요청)
	if shelvesIn(body, 2026) != 2 || body["overCap"] != true || body["autoRefund"] != true {
		t.Fatalf("3칸 넘김: %v", body)
	}
	if paid, _ := iapShelfPaid(e.ctx, e.db, user, 2026, false); paid != 2 {
		t.Fatalf("원장의 2026년 칸 합 %d (넘은 거래는 빼고 2여야 함)", paid)
	}
	// 남은 칸(1칸)보다 많은 상품은 결제를 시작하지 않게 연도 토큰을 주지 않는다
	if code, body = e.call("POST", "/iap/shelf-token", token, map[string]any{"year": 2026, "shelves": 2}); code != 409 || errCode(body) != "iap_shelf_full" {
		t.Fatalf("남은 칸보다 많음: %d %v", code, body)
	}
	for _, n := range []any{4, -1, "1"} {
		if code, _ = e.call("POST", "/iap/shelf-token", token, map[string]any{"year": 2026, "shelves": n}); code != 400 {
			t.Errorf("칸 수 %v: %d", n, code)
		}
	}
	// 1칸을 더 사서 3칸을 채우면 다 연 해가 된다
	one := e.shelfProduct(1)
	oneID := iapTestID(t, "one")
	p1 := e.shelfPurchase(oneID, y2026)
	p1.ProductID = one
	e.google.Purchases[oneID] = p1
	if code, body = e.submitYear(token, "google", one, oneID, 0); code != 200 || shelvesIn(body, 2026) != 3 || body["overCap"] != nil {
		t.Fatalf("1칸 더: %d %v", code, body)
	}
	if code, body = e.call("POST", "/iap/shelf-token", token, map[string]any{"year": 2026}); code != 409 || errCode(body) != "iap_shelf_full" {
		t.Fatalf("다 연 해: %d %v", code, body)
	}
	// 다른 해 책장은 따로
	code, body = buy(e.shelfToken(token, 2027), 0)
	if code != 200 || shelvesIn(body, 2027) != 2 || shelvesIn(body, 2026) != 3 {
		t.Fatalf("2027년: %d %v", code, body)
	}

	// 연도를 모르는 선반 거래(구독용 값, 빈 값에 연도도 안 보냄): 기록은 하고 칸은 주지 않는다
	for _, account := range []string{e.accountToken(token), ""} {
		id := iapTestID(t, "noyear")
		e.google.Purchases[id] = e.shelfPurchase(id, account)
		if code, body = e.submit(token, "google", e.shelf, id, false); code != 422 || errCode(body) != "iap_shelf_year_missing" {
			t.Fatalf("연도 모름(%q): %d %v", account, code, body)
		}
		var year *int
		if err := e.db.QueryRow(e.ctx, "SELECT shelf_year FROM iap_purchases WHERE route='google' AND transaction_id=$1", id).Scan(&year); err != nil || year != nil {
			t.Fatalf("연도 모르는 거래가 기록되지 않음: %v %v", year, err)
		}
		// 소비하지 않았다: 앱이 연도를 붙여 다시 낼 수 있고, 끝내 못 내면 구글이 환불한다(코드 리뷰 #43)
		if iapTestHas(e.google.Confirmed, id) {
			t.Fatalf("연도 모르는 거래를 소비함(%q)", account)
		}
		// 같은 거래를 연도와 함께 다시 내면 그 해에 준다
		if code, body = e.submitYear(token, "google", e.shelf, id, 2028); code != 200 || body["status"] != "already" || body["year"] != float64(2028) {
			t.Fatalf("연도와 다시 제출(%q): %d %v", account, code, body)
		}
		if !iapTestHas(e.google.Confirmed, id) {
			t.Fatalf("연도를 붙인 뒤에도 소비 안 함(%q)", account)
		}
	}
	// 2028년: 2칸 + 2칸이라 뒤의 것은 넘은 거래
	if code, body = e.call("GET", "/iap/me", token, nil); shelvesIn(body, 2028) != 2 || shelvesIn(body, 2026) != 3 || shelvesIn(body, 2027) != 2 {
		t.Fatalf("/iap/me: %v", body)
	}
	// 틀린 연도는 받지 않는다
	if code, _ = e.submitYear(token, "google", e.shelf, "x", 1999); code != 400 {
		t.Fatalf("틀린 연도: %d", code)
	}
}

// 결제 중 예약: 한 기기가 결제하는 동안 다른 기기가 그 해 책장에 3칸을 넘게 사지 못하게 막는다(D1)
func TestIAPShelfReservationAPI(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	other, _ := e.user()
	reserve := func(tok string, year, n int) (int, map[string]any) {
		t.Helper()
		return e.call("POST", "/iap/shelf-token", tok, map[string]any{"year": year, "shelves": n})
	}
	held := func() int {
		t.Helper()
		var n int
		if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_shelf_reservations WHERE user_id=$1 AND expires_at > now()", user).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}

	// 태블릿이 3칸 묶음 결제창을 띄웠다 → 휴대폰은 1칸도 막힌다. 기다릴 시간을 준다
	code, tablet := reserve(token, 2026, 3)
	if code != 200 || tablet["reservation"] == nil || tablet["expiresAt"] == nil || tablet["token"] == nil {
		t.Fatalf("예약: %d %v", code, tablet)
	}
	code, phone := reserve(token, 2026, 1)
	if retry, _ := phone["retryAfter"].(float64); code != 409 || errCode(phone) != "iap_shelf_busy" || retry < 250 || retry > 300 {
		t.Fatalf("다른 기기 결제 중: %d %v", code, phone)
	}
	// 다른 해 책장은 상관없다
	if code, body := reserve(token, 2027, 3); code != 200 {
		t.Fatalf("다른 해: %d %v", code, body)
	} else {
		e.release(token, body)
	}
	// 남이 풀어도 그대로, 태블릿이 결제를 취소하면 풀린다
	e.release(other, tablet)
	if held() != 1 {
		t.Fatal("남이 내 예약을 풀었음")
	}
	e.release(token, tablet)
	e.release(token, tablet) // 다시 불러도 204
	if code, phone = reserve(token, 2026, 1); code != 200 {
		t.Fatalf("풀린 뒤: %d %v", code, phone)
	}
	// 1칸씩 두 기기: 1+1 ≤ 3이라 둘 다 된다
	if code, tablet = reserve(token, 2026, 1); code != 200 {
		t.Fatalf("1칸 두 기기: %d %v", code, tablet)
	}
	// 앱이 꺼져 예약이 남아도 5분이 지나면 무시한다
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_shelf_reservations SET expires_at = now() - interval '1 second' WHERE user_id=$1", user); err != nil {
		t.Fatal(err)
	}
	code, tablet = reserve(token, 2026, 3)
	if code != 200 {
		t.Fatalf("끝난 예약 뒤: %d %v", code, tablet)
	}
	// 결제를 마치고 제출하면 그 예약이 풀린다
	id := iapTestID(t, "tok")
	e.google.Purchases[id] = e.shelfPurchase(id, tablet["token"].(string))
	if code, body := e.call("POST", "/iap/purchases", token, map[string]any{"route": "google", "productId": e.shelf, "proof": id, "reservation": tablet["reservation"]}); code != 200 {
		t.Fatalf("제출: %d %v", code, body)
	}
	if held() != 0 {
		t.Fatalf("제출 뒤 예약이 남음: %d", held())
	}
	// 예약 번호 없이 제출해도(옛 앱) 그 해의 가장 오래된 예약 하나를 푼다
	code, phone = reserve(token, 2026, 1)
	if code != 200 {
		t.Fatalf("예약: %d %v", code, phone)
	}
	id2 := iapTestID(t, "tok2")
	one := e.shelfProduct(1)
	p := e.shelfPurchase(id2, phone["token"].(string))
	p.ProductID = one
	e.google.Purchases[id2] = p
	if code, body := e.submit(token, "google", one, id2, false); code != 200 || shelvesIn(body, 2026) != 3 {
		t.Fatalf("번호 없이 제출: %d %v", code, body)
	}
	if held() != 0 {
		t.Fatalf("번호 없이 제출 뒤 예약이 남음: %d", held())
	}
}

// 예약을 지나쳐 3칸을 넘은 거래: 칸을 주지 않고 환불한다. 구글은 서버가 요청하고, 애플은 사용자가 요청해야 한다
// 애플이 새 계정 연결 값 대신 처음 쓴 값을 돌려줘도(포럼 보고, docs/spec/erd.md 3.7) 결제 중 예약의 연도로 칸을 연다
func TestIAPShelfYearFromReservation(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	other, _ := e.user()
	one, three := e.shelfProduct(1), e.shelfProduct(3)
	reserve := func(tok string, year, n int) map[string]any {
		t.Helper()
		code, body := e.call("POST", "/iap/shelf-token", tok, map[string]any{"year": year, "shelves": n})
		if code != 200 {
			t.Fatalf("%d년 예약: %d %v", year, code, body)
		}
		return body
	}
	// buy는 애플이 first(처음 쓴 계정 연결 값)를 돌려준 거래를 예약 번호와 함께 낸다. id가 비면 새 거래
	first := ""
	buy := func(product, id string, reservation any) (map[string]any, string) {
		t.Helper()
		if id == "" {
			id = iapTestID(t, "a")
			p := e.shelfPurchase(id, first)
			p.Route, p.TransactionID, p.ProductID, p.Acknowledged = iap.RouteApple, id, product, true
			e.apple.Purchases[id] = p
		}
		code, body := e.call("POST", "/iap/purchases", token, map[string]any{"route": "apple", "productId": product, "proof": id, "reservation": reservation})
		if code != 200 {
			t.Fatalf("제출: %d %v", code, body)
		}
		return body, id
	}
	held := func() int {
		t.Helper()
		var n int
		if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_shelf_reservations WHERE user_id=$1", user).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}

	// 2026년 1칸: 값과 예약이 같은 해
	r := reserve(token, 2026, 1)
	first = r["token"].(string)
	if body, _ := buy(one, "", r["reservation"]); body["year"] != float64(2026) || shelvesIn(body, 2026) != 1 {
		t.Fatalf("2026년: %v", body)
	}
	// 바로 2027년 1칸. 애플이 2026년 값을 돌려줌 → 예약대로 2027년
	r = reserve(token, 2027, 1)
	if r["token"] == first {
		t.Fatal("해마다 값이 달라야 시험이 됨")
	}
	body, moved := buy(one, "", r["reservation"])
	if body["year"] != float64(2027) || shelvesIn(body, 2027) != 1 || shelvesIn(body, 2026) != 1 {
		t.Fatalf("예약 연도가 먼저여야 함: %v", body)
	}
	// 결제 완료 고지(T3)에도 예약의 연도가 적힌다
	var noticeYear string
	if err := e.db.QueryRow(e.ctx, "SELECT params->>'year' FROM iap_notices WHERE user_id=$1 AND kind='purchase_done' AND dedupe_key LIKE '%'||$2||'%'", user, moved).Scan(&noticeYear); err != nil || noticeYear != "2027" {
		t.Fatalf("결제 완료 고지의 연도: %q %v", noticeYear, err)
	}
	// 3칸 묶음도. 값의 연도(2026, 1칸 있음)로 셌다면 3칸을 넘어 칸을 못 받았을 거래
	r = reserve(token, 2028, 3)
	if body, _ = buy(three, "", r["reservation"]); body["year"] != float64(2028) || shelvesIn(body, 2028) != 3 || body["overCap"] == true || shelvesIn(body, 2026) != 1 {
		t.Fatalf("3칸 묶음: %v", body)
	}
	// 결제창에서 5분을 넘겨 예약이 끝났어도 지워지기 전이면 그 연도
	r = reserve(token, 2029, 1)
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_shelf_reservations SET expires_at = now() - interval '1 second' WHERE id::text=$1", r["reservation"]); err != nil {
		t.Fatal(err)
	}
	if body, _ = buy(one, "", r["reservation"]); body["year"] != float64(2029) {
		t.Fatalf("끝난 예약: %v", body)
	}
	// 남의 예약 번호는 무시하고 값의 연도
	r = reserve(other, 2030, 1)
	if body, _ = buy(one, "", r["reservation"]); body["year"] != float64(2026) || shelvesIn(body, 2026) != 2 || shelvesIn(body, 2030) != 0 {
		t.Fatalf("남의 예약: %v", body)
	}
	// 이미 넣은 거래를 다른 해 예약과 다시 내도 연도는 그대로. 예약은 풀린다
	r = reserve(token, 2031, 1)
	if body, _ = buy(one, moved, r["reservation"]); body["status"] != "already" || body["year"] != float64(2027) || shelvesIn(body, 2031) != 0 {
		t.Fatalf("다시 낸 거래: %v", body)
	}
	if held() != 0 {
		t.Fatalf("예약이 남음: %d", held())
	}
}

func TestIAPOverCapRefund(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	refunded := func(route, key string) (requested bool, attempts int) {
		t.Helper()
		if err := e.db.QueryRow(e.ctx, `SELECT refund_requested_at IS NOT NULL, refund_attempts FROM iap_purchases
			WHERE route=$1 AND transaction_id=$2`, route, key).Scan(&requested, &attempts); err != nil {
			t.Fatal(err)
		}
		return
	}
	y := e.shelfToken(token, 2026)

	// 구글: 2칸 + 2칸
	first, second := iapTestID(t, "g1"), iapTestID(t, "g2")
	e.google.Purchases[first] = e.shelfPurchase(first, y)
	e.google.Purchases[second] = e.shelfPurchase(second, y)
	if code, body := e.submit(token, "google", e.shelf, first, false); code != 200 || body["overCap"] != nil {
		t.Fatalf("첫 구매: %d %v", code, body)
	}
	code, body := e.submit(token, "google", e.shelf, second, false)
	if code != 200 || body["overCap"] != true || body["autoRefund"] != true || shelvesIn(body, 2026) != 2 {
		t.Fatalf("넘은 구매: %d %v", code, body)
	}
	if len(e.google.Refunded) != 1 || e.google.Refunded[0] != "GPA."+second {
		t.Fatalf("환불 요청: %v", e.google.Refunded)
	}
	// 소비(consume)는 그대로 한다
	if len(e.google.Confirmed) != 2 {
		t.Fatalf("소비: %v", e.google.Confirmed)
	}
	if ok, n := refunded("google", second); !ok || n != 1 {
		t.Fatalf("환불 기록: %v %d", ok, n)
	}
	// 같은 거래를 다시 내도 환불을 또 요청하지 않는다
	if code, body = e.submit(token, "google", e.shelf, second, false); code != 200 || body["autoRefund"] != true || len(e.google.Refunded) != 1 {
		t.Fatalf("다시 제출: %d %v %v", code, body, e.google.Refunded)
	}
	// 앞선 거래가 환불돼도 넘은 거래에 칸을 주지 않는다(이미 환불을 요청했다)
	if _, err := iapRevokePurchase(e.ctx, e.db, iap.RouteGoogle, first, time.Now()); err != nil {
		t.Fatal(err)
	}
	if code, body = e.submit(token, "google", e.shelf, second, false); shelvesIn(body, 2026) != 0 || body["overCap"] != true {
		t.Fatalf("앞선 거래 환불 뒤: %d %v", code, body)
	}

	// 구글 환불 요청 실패: 기록만 하고 다시 시도할 대상으로 남긴다
	y27 := e.shelfToken(token, 2027)
	a, b := iapTestID(t, "g3"), iapTestID(t, "g4")
	e.google.Purchases[a] = e.shelfPurchase(a, y27)
	e.google.Purchases[b] = e.shelfPurchase(b, y27)
	e.submit(token, "google", e.shelf, a, false)
	e.google.RefundErr = errors.New("구글 장애")
	if code, body = e.submit(token, "google", e.shelf, b, false); code != 200 || body["overCap"] != true || body["autoRefund"] != false {
		t.Fatalf("환불 실패: %d %v", code, body)
	}
	if ok, n := refunded("google", b); ok || n != 1 {
		t.Fatalf("실패 기록: %v %d", ok, n)
	}
	e.google.RefundErr = nil

	// 애플: 개발자가 환불할 수 없다. autoRefund=false
	ya := e.shelfToken(token, 2028)
	for i, id := range []string{iapTestID(t, "a1"), iapTestID(t, "a2")} {
		p := e.shelfPurchase(id, ya)
		p.Route, p.TransactionID, p.Acknowledged = iap.RouteApple, id, true
		e.apple.Purchases[id] = p
		code, body = e.submit(token, "apple", e.shelf, id, false)
		if i == 1 && (code != 200 || body["overCap"] != true || body["autoRefund"] != false || shelvesIn(body, 2028) != 2) {
			t.Fatalf("애플 넘은 구매: %d %v", code, body)
		}
		if i == 1 {
			if ok, n := refunded("apple", id); ok || n != 0 {
				t.Fatalf("애플은 환불을 시도하지 않음: %v %d", ok, n)
			}
		}
	}
}

func iapTestHas(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// 주문 ID가 없는 구글 구매(프로모션 코드 등)가 3칸을 넘으면 환불을 요청하지 않고 시도도 쌓지 않는다(코드 리뷰 #43)
func TestIAPOverCapRefundNoOrderID(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	y := e.shelfToken(token, 2026)
	first, second := iapTestID(t, "n1"), iapTestID(t, "n2")
	e.google.Purchases[first] = e.shelfPurchase(first, y)
	p := e.shelfPurchase(second, y)
	p.TransactionID = ""
	e.google.Purchases[second] = p
	if code, body := e.submit(token, "google", e.shelf, first, false); code != 200 || body["overCap"] != nil {
		t.Fatalf("첫 구매: %d %v", code, body)
	}
	for range 2 {
		code, body := e.submit(token, "google", e.shelf, second, false)
		if code != 200 || body["overCap"] != true || body["autoRefund"] != false {
			t.Fatalf("주문 ID 없는 넘은 구매: %d %v", code, body)
		}
	}
	if iapTestHas(e.google.Refunded, "") {
		t.Fatal("주문 ID 없이 환불을 요청함")
	}
	var attempts int
	if err := e.db.QueryRow(e.ctx, "SELECT refund_attempts FROM iap_purchases WHERE route='google' AND transaction_id=$1", second).Scan(&attempts); err != nil || attempts != 0 {
		t.Fatalf("시도가 쌓임: %d %v", attempts, err)
	}
}

// 결제한 뒤 제출하기 전에 계정을 바꿨다: 선반은 결제한 계정에 넣고 소비한다. 낸 계정에는 409(앱이 거래를 끝내도 된다)(코드 리뷰 #43)
func TestIAPShelfPaidByOtherAccount(t *testing.T) {
	e := newIAPEnv(t)
	payer, _ := e.user()
	other, _ := e.user()
	id := iapTestID(t, "switch")
	e.google.Purchases[id] = e.shelfPurchase(id, e.shelfToken(payer, 2026))
	if code, body := e.submit(other, "google", e.shelf, id, false); code != 409 || errCode(body) != "iap_other_account" {
		t.Fatalf("다른 계정이 냄: %d %v", code, body)
	}
	if !iapTestHas(e.google.Confirmed, id) {
		t.Fatal("결제한 계정에 넣고도 소비하지 않음")
	}
	if _, body := e.call("GET", "/iap/me", payer, nil); shelvesIn(body, 2026) != 2 {
		t.Fatalf("결제한 계정에 칸이 없음: %v", body)
	}
	if _, body := e.call("GET", "/iap/me", other, nil); shelvesIn(body, 2026) != 0 {
		t.Fatalf("낸 계정에 칸이 생김: %v", body)
	}
	// 결제한 계정이 나중에 내면 이미 지급
	if code, body := e.submit(payer, "google", e.shelf, id, false); code != 200 || body["status"] != "already" {
		t.Fatalf("결제한 계정의 제출: %d %v", code, body)
	}
}

// 결제한 계정이 제출 전에 탈퇴했다(계정 연결 값 줄이 함께 지워짐). 같은 기기의 새 계정이 그 거래를 내면
// 칸을 주지 않고, 주인 없이 원장에 남기고, 구글은 서버가 환불한다. 애플은 사용자에게 환불 요청을 안내한다. 소비하지 않는다
func TestIAPShelfOwnerGone(t *testing.T) {
	e := newIAPEnv(t)
	for _, route := range []string{"google", "apple"} {
		payer, payerID := e.user()
		other, _ := e.user()
		id := iapTestID(t, "gone-"+route)
		p := e.shelfPurchase(id, e.shelfToken(payer, 2026))
		if route == "google" {
			e.google.Purchases[id] = p
		} else {
			p.Route = iap.RouteApple
			e.apple.Purchases[id] = p
		}
		if _, err := e.db.Exec(e.ctx, "DELETE FROM users WHERE id=$1", payerID); err != nil {
			t.Fatal(err)
		}
		code, body := e.submit(other, route, e.shelf, id, false)
		if code != 409 || errCode(body) != "iap_owner_gone" {
			t.Fatalf("%s 주인 없는 선반: %d %v", route, code, body)
		}
		msg, _ := body["error"].(map[string]any)["message"].(string)
		if route == "apple" && !strings.Contains(msg, "App Store") {
			t.Fatalf("애플 안내: %q", msg)
		}
		var owner *int64
		var requested bool
		if err := e.db.QueryRow(e.ctx, "SELECT user_id, refund_requested_at IS NOT NULL FROM iap_purchases WHERE transaction_id IN ($1, $2)", id, p.TransactionID).Scan(&owner, &requested); err != nil {
			t.Fatalf("%s 원장에 없음: %v", route, err)
		}
		if owner != nil {
			t.Fatalf("%s 주인이 생김: %d", route, *owner)
		}
		if requested != (route == "google") || iapTestHas(e.google.Refunded, p.TransactionID) != (route == "google") {
			t.Fatalf("%s 환불 요청 %v, 구글 환불 %v", route, requested, e.google.Refunded)
		}
		if iapTestHas(e.google.Confirmed, id) {
			t.Fatalf("%s 주인 없는 선반을 소비함", route)
		}
		if _, me := e.call("GET", "/iap/me", other, nil); shelvesIn(me, 2026) != 0 {
			t.Fatalf("%s 낸 계정에 칸이 생김: %v", route, me)
		}
		// 다시 내도 같은 답이고 환불은 한 번이다
		before := len(e.google.Refunded)
		if code, body := e.submit(other, route, e.shelf, id, false); code != 409 || errCode(body) != "iap_owner_gone" || len(e.google.Refunded) != before {
			t.Fatalf("%s 다시 제출: %d %v 환불 %d→%d", route, code, body, before, len(e.google.Refunded))
		}
	}
}

// 다른 계정(결제한 계정)에 넣는 선반 거래에는 낸 사람이 보낸 연도를 쓰지 않는다. 그 계정이 고르지 않은 해에 칸이 열리지 않게
func TestIAPShelfOwnerYearNotFromSubmitter(t *testing.T) {
	e := newIAPEnv(t)
	payer, _ := e.user()
	other, _ := e.user()
	id := iapTestID(t, "owner-year")
	// 연도별 값이 아닌 계정 연결 값으로 결제했다: 결제한 계정의 어느 해 책장인지 모른다
	e.google.Purchases[id] = e.shelfPurchase(id, e.accountToken(payer))
	if code, body := e.submitYear(other, "google", e.shelf, id, 2026); code != 409 || errCode(body) != "iap_other_account" {
		t.Fatalf("다른 계정이 연도와 냄: %d %v", code, body)
	}
	if _, body := e.call("GET", "/iap/me", payer, nil); shelvesIn(body, 2026) != 0 {
		t.Fatalf("결제한 계정에 낸 사람의 연도로 칸이 열림: %v", body)
	}
	if iapTestHas(e.google.Confirmed, id) {
		t.Fatal("연도를 모르는 선반을 소비함")
	}
}

// 처음 넣을 때 금액을 못 받았으면(구글 주문 조회 실패) 다시 낼 때 채운다. 한 번 채운 금액은 바꾸지 않는다
func TestIAPPriceFilledLater(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	id := iapTestID(t, "price")
	p := e.shelfPurchase(id, e.shelfToken(token, 2026))
	e.google.Purchases[id] = p
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 {
		t.Fatalf("제출: %d %v", code, body)
	}
	price := func() *int64 {
		var v *int64
		if err := e.db.QueryRow(e.ctx, "SELECT price_milli FROM iap_purchases WHERE transaction_id=$1", id).Scan(&v); err != nil {
			t.Fatal(err)
		}
		return v
	}
	if price() != nil {
		t.Fatal("금액이 없던 거래에 금액이 있음")
	}
	p.Currency, p.PriceMilli = "KRW", 3_300_000
	e.google.Purchases[id] = p
	e.submit(token, "google", e.shelf, id, false)
	if v := price(); v == nil || *v != 3_300_000 {
		t.Fatalf("다시 낼 때 금액을 채우지 않음: %v", v)
	}
	p.PriceMilli = 9_900_000
	e.google.Purchases[id] = p
	e.submit(token, "google", e.shelf, id, false)
	if v := price(); *v != 3_300_000 {
		t.Fatalf("채운 금액이 바뀜: %d", *v)
	}
}

// 앱이 지금 결제의 예약 번호를 붙여 옛 거래를 내도 옛 거래는 그 예약을 쓰지도 풀지도 않는다(코드 리뷰 #43)
func TestIAPOldPurchaseKeepsReservation(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	old := iapTestID(t, "old")
	p := e.shelfPurchase(old, e.shelfToken(token, 2025))
	p.PurchasedAt = time.Now().Add(-time.Hour).UTC()
	e.google.Purchases[old] = p
	code, r := e.call("POST", "/iap/shelf-token", token, map[string]any{"year": 2026, "shelves": 2})
	if code != 200 {
		t.Fatalf("예약: %d %v", code, r)
	}
	code, body := e.call("POST", "/iap/purchases", token, map[string]any{"route": "google", "productId": e.shelf, "proof": old, "reservation": r["reservation"]})
	if code != 200 || body["year"] != float64(2025) || shelvesIn(body, 2026) != 0 {
		t.Fatalf("옛 거래가 예약 연도로 감: %d %v", code, body)
	}
	var held int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_shelf_reservations WHERE user_id=$1 AND id::text=$2", user, r["reservation"]).Scan(&held); err != nil || held != 1 {
		t.Fatalf("지금 결제의 예약이 풀림: %d %v", held, err)
	}
}

// 환불로 닫힌 거래를 다시 내면 409 환불됨, 구글 수량 구매는 받지 않고 소비하지도 않는다(코드 리뷰 #43)
func TestIAPRevokedAndQuantity(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	y := e.shelfToken(token, 2026)
	id := iapTestID(t, "rev")
	e.google.Purchases[id] = e.shelfPurchase(id, y)
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 {
		t.Fatalf("지급: %d %v", code, body)
	}
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET state='revoked', revoked_at=now() WHERE route='google' AND transaction_id=$1", id); err != nil {
		t.Fatal(err)
	}
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 409 || errCode(body) != "iap_purchase_refunded" {
		t.Fatalf("환불된 거래 다시 제출: %d %v", code, body)
	}
	q := iapTestID(t, "qty")
	p := e.shelfPurchase(q, y)
	p.Quantity = 2
	e.google.Purchases[q] = p
	if code, body := e.submit(token, "google", e.shelf, q, false); code != 422 || errCode(body) != "iap_purchase_rejected" {
		t.Fatalf("수량 구매: %d %v", code, body)
	}
	if iapTestHas(e.google.Confirmed, q) {
		t.Fatal("수량 구매를 소비함")
	}
}

// 알림을 놓쳤어도, 앱이 낸 거래를 스토어가 환불이라고 답하면 그때 권한을 거둔다(코드 리뷰 #43, 이슈 #32)
func TestIAPRevokedOnSubmit(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	orig, txn := iapTestID(t, "rorig"), iapTestID(t, "rtxn")
	p := e.subscription(orig, txn, e.accountToken(token), time.Now().Add(time.Hour))
	e.apple.Purchases[txn] = p
	if code, body := e.submit(token, "apple", e.plus, txn, false); code != 200 || body["plus"] != true {
		t.Fatalf("구독 지급: %d %v", code, body)
	}
	p.State, p.RevokedAt = iap.StateRevoked, time.Now().UTC()
	e.apple.Purchases[txn] = p
	if code, body := e.submit(token, "apple", e.plus, txn, false); code != 409 || errCode(body) != "iap_purchase_refunded" {
		t.Fatalf("환불된 구독 제출: %d %v", code, body)
	}
	if _, body := e.call("GET", "/iap/me", token, nil); body["plus"] != false {
		t.Fatalf("환불 뒤에도 plus: %v", body)
	}
	// 선반도 같다
	y := e.shelfToken(token, 2026)
	id := iapTestID(t, "rshelf")
	sp := e.shelfPurchase(id, y)
	e.google.Purchases[id] = sp
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 || shelvesIn(body, 2026) != 2 {
		t.Fatalf("선반 지급: %d %v", code, body)
	}
	sp.State, sp.RevokedAt = iap.StateRevoked, time.Now().UTC()
	e.google.Purchases[id] = sp
	if code, _ := e.submit(token, "google", e.shelf, id, false); code != 409 {
		t.Fatalf("환불된 선반 제출: %d", code)
	}
	if _, body := e.call("GET", "/iap/me", token, nil); shelvesIn(body, 2026) != 0 {
		t.Fatalf("환불 뒤에도 칸: %v", body)
	}
}
