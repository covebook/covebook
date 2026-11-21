package server

import (
	"encoding/json"
	"errors"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

func (e *iapEnv) purchases(token string) []map[string]any {
	e.t.Helper()
	code, body := e.call("GET", "/iap/purchases", token, nil)
	if code != 200 {
		e.t.Fatalf("/iap/purchases %d %v", code, body)
	}
	list, _ := body["purchases"].([]any)
	out := make([]map[string]any, 0, len(list))
	for _, v := range list {
		out = append(out, v.(map[string]any))
	}
	return out
}

func TestIAPPurchaseHistory(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	other, _ := e.user()
	account := e.accountToken(token)

	// 로그인하지 않으면 볼 수 없고, 산 것이 없으면 빈 목록이다
	if code, _ := e.call("GET", "/iap/purchases", "", nil); code != 401 {
		t.Fatalf("토큰 없이 %d", code)
	}
	if got := e.purchases(token); len(got) != 0 {
		t.Fatalf("산 것이 없는데 %v", got)
	}

	// 어제 산 구글 선반(금액 없음)과 방금 산 애플 구독(금액 있음. 시험용 통화와 값)
	shelfID, orig, txn := iapTestID(t, "tok"), iapTestID(t, "orig"), iapTestID(t, "txn")
	shelf := e.shelfPurchase(shelfID, e.shelfToken(token, 2026))
	shelf.PurchasedAt = time.Now().Add(-24 * time.Hour).UTC().Truncate(time.Second)
	e.google.Purchases[shelfID] = shelf
	sub := e.subscription(orig, txn, account, time.Now().Add(time.Hour))
	sub.Currency, sub.PriceMilli = "XTS", 1234
	e.apple.Purchases[txn] = sub
	if code, body := e.submit(token, "google", e.shelf, shelfID, false); code != 200 {
		t.Fatalf("선반 제출 %d %v", code, body)
	}
	if code, body := e.submit(token, "apple", e.plus, txn, false); code != 200 {
		t.Fatalf("구독 제출 %d %v", code, body)
	}
	got := e.purchases(token)
	if len(got) != 2 {
		t.Fatalf("내역 %v", got)
	}
	// 최신순: 구독이 먼저
	first, second := got[0], got[1]
	if first["route"] != "apple" || first["productId"] != e.plus || first["kind"] != "subscription" || first["state"] != "paid" ||
		first["currency"] != "XTS" || first["priceMilli"] != float64(1234) {
		t.Fatalf("구독 줄: %v", first)
	}
	if _, has := first["year"]; has {
		t.Fatalf("구독 줄에 연도가 있음: %v", first)
	}
	if _, has := first["shelves"]; has {
		t.Fatalf("구독 줄에 선반 칸이 있음: %v", first)
	}
	if second["route"] != "google" || second["kind"] != "product" || second["shelves"] != float64(2) || second["year"] != float64(2026) || second["purchasedAt"] != shelf.PurchasedAt.Format(time.RFC3339) {
		t.Fatalf("선반 줄: %v", second)
	}
	for _, k := range []string{"currency", "priceMilli", "revokedAt"} {
		if _, has := second[k]; has {
			t.Fatalf("선반 줄에 %s가 있음: %v", k, second)
		}
	}
	// 남의 내역은 보이지 않는다
	if got = e.purchases(other); len(got) != 0 {
		t.Fatalf("다른 계정에 내역이 보임: %v", got)
	}
	// 환불된 줄은 지워지지 않고 환불됨으로 보인다
	if _, err := iapRevokePurchase(e.ctx, e.db, iap.RouteGoogle, shelfID, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	got = e.purchases(token)
	if len(got) != 2 || got[1]["state"] != "revoked" || got[1]["revokedAt"] == nil {
		t.Fatalf("환불 뒤 내역: %v", got)
	}
}

func TestIAPPurchaseHistoryHidesSandbox(t *testing.T) {
	e := newIAPEnv(t)
	e.srv.IAPSandbox = true
	token, _ := e.user()
	id := iapTestID(t, "tok")
	p := e.shelfPurchase(id, e.shelfToken(token, 2026))
	p.Env = iap.EnvSandbox
	e.google.Purchases[id] = p
	if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 {
		t.Fatalf("샌드박스 제출 %d %v", code, body)
	}
	if got := e.purchases(token); len(got) != 1 {
		t.Fatalf("스위치가 켜졌는데 내역 %v", got)
	}
	e.srv.IAPSandbox = false
	if got := e.purchases(token); len(got) != 0 {
		t.Fatalf("스위치를 껐는데 샌드박스 내역이 보임: %v", got)
	}
}

func TestIAPSeller(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	if _, has := e.me(token)["seller"]; has {
		t.Fatal("설정이 없는데 사업자 정보가 나옴")
	}
	// 시험용 가짜 값. 모르는 칸과 글자가 아닌 값은 내보내지 않는다
	t.Setenv("IAP_SELLER_JSON", `{"name":"시험 상호","owner":"시험 대표","bizNo":"000-00-00000","secret":"내보내면 안 됨","phone":123,"email":""}`)
	seller, _ := e.me(token)["seller"].(map[string]any)
	if len(seller) != 3 || seller["name"] != "시험 상호" || seller["owner"] != "시험 대표" || seller["bizNo"] != "000-00-00000" {
		t.Fatalf("사업자 정보: %v", seller)
	}
	for _, broken := range []string{`not json`, `[]`, `{}`, `{"name":""}`} {
		t.Setenv("IAP_SELLER_JSON", broken)
		if _, has := e.me(token)["seller"]; has {
			t.Fatalf("깨진 설정 %q인데 사업자 정보가 나옴", broken)
		}
	}
}

// 알림을 못 받았어도 스토어의 알림 이력으로 되찾는다.
func TestIAPBackfillNotices(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	orig, txn1 := iapTestID(t, "orig"), iapTestID(t, "txn1")
	e.apple.Purchases[txn1] = e.subscription(orig, txn1, account, time.Now().Add(time.Hour))
	if code, body := e.submit(token, "apple", e.plus, txn1, false); code != 200 {
		t.Fatalf("구독 제출 %d %v", code, body)
	}
	e.sweep() // 첫 메우기(이력이 비어 있다)

	// 스토어에서 갱신됐지만 알림은 우리에게 오지 않았다. 스토어의 이력에는 남아 있다
	txn2 := iapTestID(t, "txn2")
	renewed := time.Now().Add(31 * 24 * time.Hour).UTC().Truncate(time.Second)
	e.apple.Purchases[txn2] = e.subscription(orig, txn2, account, renewed)
	missed, known, test := iapTestID(t, "missed"), iapTestID(t, "known"), iapTestID(t, "test")
	if code := e.notify("apple", subNotice(known, txn1, orig), ""); code != 200 { // 이것은 받았다
		t.Fatal(code)
	}
	e.apple.History = []iap.Notice{subNotice(known, txn1, orig), subNotice(missed, txn2, orig), {ID: test, Type: "TEST", Test: true}}

	// 6시간이 안 됐으면 이력을 다시 받지 않는다
	if res := e.sweep(); res.Backfilled != 0 {
		t.Fatalf("간격이 안 됐는데 메움: %+v", res)
	}
	e.srv.iapCatchUpAt = nil // 간격이 지난 것으로
	res := e.sweep()
	if res.Backfilled != 2 { // 못 받은 것과 연결 확인 알림. 이미 받은 것은 다시 넣지 않는다
		t.Fatalf("메운 건수: %+v", res)
	}
	// 넣은 알림은 같은 대조에서 바로 처리되고 구독이 갱신된다
	if result, _, attempts := e.noticeResult("apple", missed); result != "processed" || attempts != 1 {
		t.Fatalf("메운 알림: %s 시도 %d", result, attempts)
	}
	if result, _, _ := e.noticeResult("apple", test); result != "ignored" {
		t.Fatalf("연결 확인 알림: %s", result)
	}
	sub, _ := e.me(token)["subscription"].(map[string]any)
	if sub == nil || sub["expiresAt"] != renewed.Format(time.RFC3339) {
		t.Fatalf("메운 뒤 구독: %v", sub)
	}
	// 다시 돌려도 같은 알림을 또 넣지 않는다
	e.srv.iapCatchUpAt = nil
	if res = e.sweep(); res.Backfilled != 0 {
		t.Fatalf("다시 메움: %+v", res)
	}
	var n int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notifications WHERE notification_id = ANY($1)", []string{missed, known, test}).Scan(&n); err != nil || n != 3 {
		t.Fatalf("알림 줄 %d %v", n, err)
	}
	// 이력 조회가 실패해도 다른 대조는 돈다
	e.srv.iapCatchUpAt = nil
	e.apple.Err = errors.New("timeout")
	if _, err := e.srv.iapSweep(e.ctx); err != nil {
		t.Fatalf("이력 조회 실패가 대조를 멈춤: %v", err)
	}
}

// 환불 알림을 못 받았어도 스토어의 무효 구매 목록으로 환불을 반영한다.
func TestIAPVoidedList(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	shelfID, kept := iapTestID(t, "tok"), iapTestID(t, "kept")
	e.google.Purchases[shelfID] = e.shelfPurchase(shelfID, e.shelfToken(token, 2026))
	e.google.Purchases[kept] = e.shelfPurchase(kept, e.shelfToken(token, 2027))
	for _, id := range []string{shelfID, kept} {
		if code, body := e.submit(token, "google", e.shelf, id, false); code != 200 {
			t.Fatalf("선반 제출 %d %v", code, body)
		}
	}
	// 구글 구독: 구매 토큰이 줄기이고 주문 ID가 거래의 키다
	subToken, order := iapTestID(t, "subtok"), iapTestID(t, "GPA")
	gsub := e.subscription(subToken, order, account, time.Now().Add(time.Hour))
	gsub.Route = iap.RouteGoogle
	e.google.Purchases[subToken] = gsub
	if code, body := e.submit(token, "google", e.plus, subToken, false); code != 200 || body["plus"] != true {
		t.Fatalf("구독 제출 %d %v", code, body)
	}
	e.sweep()
	if me := e.me(token); shelvesIn(me, 2026) != 2 || shelvesIn(me, 2027) != 2 || me["plus"] != true {
		t.Fatalf("환불 전: %v", me)
	}

	// 스토어가 선반 하나와 구독을 환불했다. 우리 원장에 없는 구매도 목록에 섞여 있다
	revoked := gsub
	revoked.State = iap.StateRevoked
	e.google.Purchases[subToken] = revoked
	voidedAt := time.Now().Add(-time.Hour).UTC().Truncate(time.Second)
	e.google.VoidedList = []iap.VoidedPurchase{{Token: shelfID, OrderID: iapTestID(t, "GPA-shelf"), VoidedAt: voidedAt}, {Token: subToken, OrderID: order}, {Token: iapTestID(t, "unknown")}}
	e.srv.iapCatchUpAt = nil
	if res := e.sweep(); res.Voided != 2 {
		t.Fatalf("반영한 환불: %+v", res)
	}
	if me := e.me(token); shelvesIn(me, 2026) != 0 || shelvesIn(me, 2027) != 2 || me["plus"] != false {
		t.Fatalf("환불 뒤: %v", me)
	}
	var state string
	var at time.Time
	if err := e.db.QueryRow(e.ctx, "SELECT state, revoked_at FROM iap_purchases WHERE route='google' AND transaction_id=$1", shelfID).Scan(&state, &at); err != nil || state != "revoked" || !at.Equal(voidedAt) {
		t.Fatalf("원장: %s %v %v", state, at, err)
	}
	// 다시 받아도 같은 환불을 또 세지 않는다
	e.srv.iapCatchUpAt = nil
	if res := e.sweep(); res.Voided != 0 {
		t.Fatalf("다시 반영: %+v", res)
	}
}

func TestIAPAdminStats(t *testing.T) {
	e := newIAPEnv(t)
	get := func(token string) (int, map[string]any) {
		req := httptest.NewRequest("GET", "/admin/iap/stats", nil)
		if token != "" {
			req.Header.Set("X-Admin-Token", token)
		}
		rec := httptest.NewRecorder()
		e.h.ServeHTTP(rec, req)
		out := map[string]any{}
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	// 운영자 토큰이 설정되지 않았거나 틀리면 없는 경로처럼 답한다
	if code, _ := get("anything"); code != 404 {
		t.Fatalf("토큰 설정 없이 %d", code)
	}
	t.Setenv("ADMIN_TOKEN", "test-admin-token")
	if code, _ := get("wrong-admin-token"); code != 404 {
		t.Fatalf("틀린 토큰 %d", code)
	}
	// 처리 전 알림을 하나 넣고 숫자에 잡히는지 본다(다른 시험과 DB를 같이 써서 정확한 값은 단정하지 않는다)
	if code := e.notify("apple", subNotice(iapTestID(t, "n"), "txn", "orig"), ""); code != 200 {
		t.Fatal(code)
	}
	code, body := get("test-admin-token")
	if code != 200 {
		t.Fatalf("운영자 조회 %d %v", code, body)
	}
	for _, k := range []string{"pendingNotifications", "failedNotifications", "unconfirmedPurchases", "oldestPendingSeconds", "activeSubscriptions", "revokedPurchases30Days", "shelfOverCap", "shelfOverCapRefunded", "shelfOverCapApple", "shelfNoYear"} {
		if _, ok := body[k].(float64); !ok {
			t.Fatalf("%s 없음: %v", k, body)
		}
	}
	if body["pendingNotifications"].(float64) < 1 {
		t.Fatalf("대기 알림이 잡히지 않음: %v", body)
	}
	b, err := iapBacklogNow(e.ctx, e.db)
	if err != nil || b.PendingNotices < 1 || b.OldestPendingSecs < 0 {
		t.Fatalf("밀린 일: %+v %v", b, err)
	}
	e.srv.iapLogSweep(e.ctx, iapSweepResult{}) // 로그 한 줄이 패닉 없이 나가는지

	// 한 책장에서 3칸을 넘게 산 거래와 연도를 모르는 선반 거래가 숫자에 잡힌다(차이로 본다)
	token, _ := e.user()
	year := e.shelfToken(token, 2026)
	for _, c := range []struct {
		account string
		code    int
	}{{year, 200}, {year, 200}, {"", 422}} { // 2칸 + 2칸(넘음), 연도 모름
		id := iapTestID(t, "tok")
		e.google.Purchases[id] = e.shelfPurchase(id, c.account)
		if code, body := e.submit(token, "google", e.shelf, id, false); code != c.code {
			t.Fatalf("선반 제출 %d %v", code, body)
		}
	}
	// 구글의 넘은 거래는 서버가 환불을 요청했다
	after, err := iapBacklogNow(e.ctx, e.db)
	if err != nil || after.ShelfOverCap != b.ShelfOverCap || after.ShelfOverCapRefunded != b.ShelfOverCapRefunded+1 || after.ShelfNoYear != b.ShelfNoYear+1 {
		t.Fatalf("구글 넘은 거래 %+v → %+v %v", b, after, err)
	}
	// 애플의 넘은 거래는 사용자가 환불을 요청해야 해서 남는다
	ya := e.shelfToken(token, 2027)
	for range 2 {
		id := iapTestID(t, "apple")
		p := e.shelfPurchase(id, ya)
		p.Route, p.TransactionID, p.Acknowledged = iap.RouteApple, id, true
		e.apple.Purchases[id] = p
		e.submit(token, "apple", e.shelf, id, false)
	}
	last, err := iapBacklogNow(e.ctx, e.db)
	if err != nil || last.ShelfOverCap != after.ShelfOverCap+1 || last.ShelfOverCapApple != after.ShelfOverCapApple+1 {
		t.Fatalf("애플 넘은 거래 %+v → %+v %v", after, last, err)
	}
	// 구매 내역에도 넘은 거래가 보인다
	_, list := e.call("GET", "/iap/purchases", token, nil)
	over := 0
	for _, it := range list["purchases"].([]any) {
		if it.(map[string]any)["overCap"] == true {
			over++
		}
	}
	if over != 2 {
		t.Fatalf("구매 내역의 넘은 거래 %d (구글 1, 애플 1)", over)
	}
}
