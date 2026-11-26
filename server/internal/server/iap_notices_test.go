package server

import (
	"encoding/json"
	"errors"
	"net/http/httptest"
	"reflect"
	"sort"
	"testing"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// notices는 알림함을 읽는다(최신순).
func (e *iapEnv) notices(token string) []map[string]any {
	e.t.Helper()
	code, body := e.call("GET", "/iap/notices", token, nil)
	if code != 200 {
		e.t.Fatalf("/iap/notices %d %v", code, body)
	}
	list, _ := body["notices"].([]any)
	out := make([]map[string]any, 0, len(list))
	for _, v := range list {
		out = append(out, v.(map[string]any))
	}
	return out
}

// noticeKinds는 알림함에 있는 고지의 종류를 정렬해서 돌려준다.
func (e *iapEnv) noticeKinds(token string) []string {
	e.t.Helper()
	kinds := []string{}
	for _, n := range e.notices(token) {
		kinds = append(kinds, n["kind"].(string))
	}
	sort.Strings(kinds)
	return kinds
}

func (e *iapEnv) wantKinds(token, when string, want ...string) {
	e.t.Helper()
	sort.Strings(want)
	if got := e.noticeKinds(token); !reflect.DeepEqual(got, append([]string{}, want...)) {
		e.t.Fatalf("%s: 고지 %v, 기대 %v", when, got, want)
	}
}

// 선반: 새로 지급하면 결제 완료를 한 번, 환불되면 환불을 한 번 알린다. 같은 제출·같은 알림을 되풀이해도 한 줄이다.
func TestIAPNoticeShelf(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	e.wantKinds(token, "처음")
	if e.me(token)["unreadNotices"] != float64(0) {
		t.Fatalf("처음 안 읽은 수: %v", e.me(token))
	}

	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
	for range 3 { // 앱이 같은 구매를 여러 번 내도(재전송, 앱 재시작) 한 번만 알린다
		if code, body := e.submit(token, "google", e.shelf, tok, false); code != 200 {
			t.Fatalf("제출 %d %v", code, body)
		}
	}
	e.wantKinds(token, "구매 뒤", noticePurchaseDone)
	n := e.notices(token)[0]
	params := n["params"].(map[string]any)
	if n["template"] != "T3" || n["readAt"] != nil || params["route"] != "google" || params["productId"] != e.shelf || params["kind"] != "product" || params["shelves"] != float64(2) || params["year"] != float64(2026) || params["overCap"] != nil {
		t.Fatalf("결제 완료 고지: %v", n)
	}
	for k := range params { // 금액을 넣지 않는다
		if k == "price" || k == "priceMilli" || k == "currency" {
			t.Fatalf("고지에 금액이 들어감: %v", params)
		}
	}
	if _, err := time.Parse(time.RFC3339, n["createdAt"].(string)); err != nil {
		t.Fatalf("만든 시각: %v", n["createdAt"])
	}

	// 환불: 같은 환불 알림이 두 번 와도, 뒤에 다른 알림이 와도 한 번만 알린다
	for _, id := range []string{"r1", "r2"} {
		e.notify("google", iap.Notice{ID: iapTestID(t, id), Type: "voided/2", Voided: true, Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
		e.sweep()
	}
	e.wantKinds(token, "환불 뒤", noticePurchaseDone, noticeShelfRefunded)
	refund := e.notices(token)[0]
	rp := refund["params"].(map[string]any)
	if refund["kind"] != noticeShelfRefunded || refund["template"] != "T9" || rp["shelves"] != float64(2) || rp["year"] != float64(2026) || rp["kind"] != "product" {
		t.Fatalf("환불 고지(최신이 먼저): %v", refund)
	}
	if _, err := time.Parse(time.RFC3339, rp["revokedAt"].(string)); err != nil {
		t.Fatalf("환불 시각: %v", rp["revokedAt"])
	}
	if e.me(token)["unreadNotices"] != float64(2) {
		t.Fatalf("안 읽은 수: %v", e.me(token)["unreadNotices"])
	}
}

// 알림으로 먼저 지급된 구매도 결제 완료를 알리고, 뒤에 앱이 제출해도 다시 알리지 않는다. 복원으로 낸 것은 알리지 않는다.
func TestIAPNoticeGrantedByNotificationAndRestore(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
	e.notify("google", iap.Notice{ID: iapTestID(t, "n"), Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
	e.sweep()
	e.wantKinds(token, "알림으로 지급", noticePurchaseDone)
	if code, body := e.submit(token, "google", e.shelf, tok, false); code != 200 || body["status"] != "already" {
		t.Fatalf("뒤늦은 제출: %d %v", code, body)
	}
	e.wantKinds(token, "뒤늦은 제출 뒤", noticePurchaseDone)

	// 구매 복원으로 넘겨받은 구독은 새 결제가 아니다
	owner, _ := e.user()
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[txn] = e.subscription(orig, txn, e.accountToken(owner), time.Now().Add(time.Hour))
	e.submit(owner, "apple", e.plus, txn, false)
	e.wantKinds(owner, "구독 구매", noticePurchaseDone)
	if code, body := e.submit(token, "apple", e.plus, txn, true); code != 200 || body["plus"] != true {
		t.Fatalf("복원: %d %v", code, body)
	}
	e.wantKinds(token, "복원 뒤(늘지 않음)", noticePurchaseDone)
	// 넘겨준 쪽에도 만료·환불 같은 고지가 생기지 않는다
	e.wantKinds(owner, "넘겨준 뒤", noticePurchaseDone)
}

// 구독: 결제 완료 → 해지 접수 → (다시 켬) → 결제 실패 유예 → 만료. 바뀐 순간마다 한 번씩만 알린다.
func TestIAPNoticeSubscriptionLifecycle(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	expires := time.Now().Add(time.Hour).UTC().Truncate(time.Second)
	set := func(change func(p *iap.Purchase)) {
		p := e.subscription(orig, txn, account, expires)
		change(&p)
		e.apple.Purchases[txn] = p
	}
	// 같은 내용의 알림을 두 번 보내고 두 번 처리한다. 대조 작업이 같은 줄을 다시 본 것과 같다
	twice := func(name string) {
		for _, suffix := range []string{"a", "b"} {
			if code := e.notify("apple", subNotice(iapTestID(t, name+suffix), txn, orig), ""); code != 200 {
				t.Fatal(code)
			}
			e.sweep()
		}
	}

	set(func(*iap.Purchase) {})
	if code, body := e.submit(token, "apple", e.plus, txn, false); code != 200 || body["status"] != "granted" {
		t.Fatalf("구독 제출: %d %v", code, body)
	}
	e.submit(token, "apple", e.plus, txn, false) // already
	e.wantKinds(token, "구독 구매", noticePurchaseDone)
	done := e.notices(token)[0]["params"].(map[string]any)
	if done["kind"] != "subscription" || done["expiresAt"] != expires.Format(time.RFC3339) {
		t.Fatalf("결제 완료 고지 값: %v", done)
	}

	// 아무것도 안 바뀐 갱신 확인은 알리지 않는다
	twice("same")
	e.wantKinds(token, "변화 없음", noticePurchaseDone)

	// 자동 갱신을 껐다: 해지 접수
	set(func(p *iap.Purchase) { p.AutoRenew = false })
	twice("cancel")
	e.wantKinds(token, "해지 접수", noticePurchaseDone, noticeCancelScheduled)
	cancel := e.notices(token)[0]
	if cancel["template"] != "T10" || cancel["params"].(map[string]any)["expiresAt"] != expires.Format(time.RFC3339) {
		t.Fatalf("해지 접수 고지: %v", cancel)
	}
	// 다시 켰다가(알리지 않음) 같은 기간에 또 껐다: 같은 만료일의 해지 접수는 한 번만
	set(func(*iap.Purchase) {})
	twice("resume")
	set(func(p *iap.Purchase) { p.AutoRenew = false })
	twice("cancel2")
	e.wantKinds(token, "다시 켰다 끔", noticePurchaseDone, noticeCancelScheduled)

	// 결제 실패: 유예가 시작됐다
	grace := time.Now().Add(16 * 24 * time.Hour).UTC().Truncate(time.Second)
	set(func(p *iap.Purchase) { p.GraceUntil = grace })
	twice("grace")
	e.wantKinds(token, "유예 시작", noticePurchaseDone, noticeCancelScheduled, noticePaymentFailed)
	failed := e.notices(token)[0]
	if failed["template"] != "T7" || failed["params"].(map[string]any)["graceUntil"] != grace.Format(time.RFC3339) {
		t.Fatalf("결제 실패 고지: %v", failed)
	}

	// 만료: 스토어가 권한 없음으로 답한다
	set(func(p *iap.Purchase) { p.State, p.AutoRenew = iap.StateInactive, false })
	twice("expire")
	e.wantKinds(token, "만료", noticePurchaseDone, noticeCancelScheduled, noticePaymentFailed, noticeExpired)
	if last := e.notices(token)[0]; last["kind"] != noticeExpired || last["template"] != "T8" {
		t.Fatalf("만료 고지: %v", last)
	}
	if e.me(token)["plus"] != false || e.me(token)["unreadNotices"] != float64(4) {
		t.Fatalf("만료 뒤: %v", e.me(token))
	}
}

// 구독 환불: 환불을 한 번 알리고, 같은 일로 만료를 따로 알리지 않는다. 스토어가 구독을 더 알려 주지 않을 때의 만료도 알린다.
func TestIAPNoticeSubscriptionRefundAndGone(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	p := e.subscription(orig, txn, account, time.Now().Add(time.Hour))
	e.apple.Purchases[txn] = p
	e.submit(token, "apple", e.plus, txn, false)
	p.State = iap.StateRevoked
	e.apple.Purchases[txn] = p
	for _, id := range []string{"r1", "r2"} {
		e.notify("apple", iap.Notice{ID: iapTestID(t, id), Type: "REFUND", Target: &iap.Ref{Kind: iap.KindSubscription, ID: txn}, OriginalID: orig}, "")
		e.sweep()
	}
	e.wantKinds(token, "구독 환불", noticePurchaseDone, noticeSubRefunded)
	// 환불 뒤 스토어가 만료로 답해도 만료를 따로 알리지 않는다
	p.State = iap.StateInactive
	e.apple.Purchases[txn] = p
	e.notify("apple", subNotice(iapTestID(t, "after"), txn, orig), "")
	e.sweep()
	e.wantKinds(token, "환불 뒤 만료", noticePurchaseDone, noticeSubRefunded)

	// 다른 구독: 스토어가 더는 모른다고 답하면(구글은 만료 60일 뒤) 만료로 확정하고 알린다
	other, _ := e.user()
	orig2, txn2 := iapTestID(t, "orig2"), iapTestID(t, "txn2")
	e.apple.Purchases[txn2] = e.subscription(orig2, txn2, e.accountToken(other), time.Now().Add(time.Hour))
	e.submit(other, "apple", e.plus, txn2, false)
	delete(e.apple.Purchases, txn2)
	for _, id := range []string{"g1", "g2"} {
		e.notify("apple", subNotice(iapTestID(t, id), txn2, orig2), "")
		e.sweep()
	}
	e.wantKinds(other, "스토어가 모르는 구독", noticePurchaseDone, noticeExpired)
}

// 알림함 읽기: 내 것만 읽음으로 바꾸고, 남의 번호는 조용히 지나친다. 로그인이 필요하다.
func TestIAPNoticeRead(t *testing.T) {
	e := newIAPEnv(t)
	a, _ := e.user()
	b, _ := e.user()
	buy := func(token string) {
		tok := iapTestID(t, "tok")
		e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
		if code, body := e.submit(token, "google", e.shelf, tok, false); code != 200 {
			t.Fatalf("제출 %d %v", code, body)
		}
	}
	buy(a)
	buy(a)
	buy(b)
	mine, theirs := e.notices(a), e.notices(b)
	if len(mine) != 2 || len(theirs) != 1 {
		t.Fatalf("고지 수: %d, %d", len(mine), len(theirs))
	}
	if code, _ := e.call("GET", "/iap/notices", "", nil); code != 401 {
		t.Fatalf("로그인 없이 목록: %d", code)
	}
	if code, _ := e.call("POST", "/iap/notices/read", "", map[string]any{"all": true}); code != 401 {
		t.Fatalf("로그인 없이 읽음: %d", code)
	}
	// 남의 고지 번호와 없는 번호를 섞어 보낸다: 내 것 하나만 읽음이 된다
	code, body := e.call("POST", "/iap/notices/read", a, map[string]any{"ids": []any{mine[0]["id"], theirs[0]["id"], 999999999}})
	if code != 200 || body["unread"] != float64(1) {
		t.Fatalf("읽음 처리: %d %v", code, body)
	}
	if e.notices(b)[0]["readAt"] != nil || e.me(b)["unreadNotices"] != float64(1) {
		t.Fatalf("남의 고지가 읽음으로 바뀜: %v", e.notices(b))
	}
	after := e.notices(a)
	if after[0]["readAt"] == nil || after[1]["readAt"] != nil {
		t.Fatalf("읽음 표시: %v", after)
	}
	first := after[0]["readAt"]
	// 전부 읽음. 이미 읽은 것의 읽은 시각은 그대로다
	if code, body = e.call("POST", "/iap/notices/read", a, map[string]any{"all": true}); code != 200 || body["unread"] != float64(0) {
		t.Fatalf("전부 읽음: %d %v", code, body)
	}
	if after = e.notices(a); after[0]["readAt"] != first || after[1]["readAt"] == nil || e.me(a)["unreadNotices"] != float64(0) {
		t.Fatalf("전부 읽은 뒤: %v", after)
	}
	// 빈 요청은 아무것도 바꾸지 않는다
	if code, body = e.call("POST", "/iap/notices/read", b, map[string]any{}); code != 200 || body["unread"] != float64(1) {
		t.Fatalf("빈 요청: %d %v", code, body)
	}
}

// 계정을 지우면 고지도 지워진다. 주인이 없는 거래의 환불은 고지를 쓰지 않는다.
func TestIAPNoticeCascadeAndOwnerless(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
	e.submit(token, "google", e.shelf, tok, false)
	count := func() (n int) {
		if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notices WHERE user_id=$1", user).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return
	}
	if count() != 1 {
		t.Fatalf("지우기 전 고지 %d", count())
	}
	if _, err := e.db.Exec(e.ctx, "DELETE FROM users WHERE id=$1", user); err != nil {
		t.Fatal(err)
	}
	if count() != 0 {
		t.Fatalf("계정을 지웠는데 고지가 남음: %d", count())
	}
	// 거래 줄은 남고(user_id NULL) 환불이 반영되지만, 알릴 사람이 없으니 고지는 없다
	var before int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notices").Scan(&before); err != nil {
		t.Fatal(err)
	}
	if changed, err := iapRevokePurchase(e.ctx, e.db, iap.RouteGoogle, tok, time.Now().UTC()); err != nil || !changed {
		t.Fatalf("주인 없는 거래 환불: %v %v", changed, err)
	}
	var withKey int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notices WHERE dedupe_key=$1", "shelf_refunded:google:"+tok).Scan(&withKey); err != nil || withKey != 0 {
		t.Fatalf("주인 없는 거래에 고지가 생김: %d %v", withKey, err)
	}
}

// 샌드박스: 스위치가 꺼져 있으면 지급도 고지도 없다. 켜져 있을 때 생긴 고지는 스위치를 끄면 보이지 않는다.
func TestIAPNoticeSandbox(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	p := e.shelfPurchase(tok, e.shelfToken(token, 2026))
	p.Env = iap.EnvSandbox
	e.google.Purchases[tok] = p
	if code, _ := e.submit(token, "google", e.shelf, tok, false); code != 422 {
		t.Fatalf("스위치 꺼짐: %d", code)
	}
	e.notify("google", iap.Notice{ID: iapTestID(t, "n"), Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
	e.sweep()
	e.wantKinds(token, "스위치 꺼짐")

	e.srv.IAPSandbox = true
	if code, body := e.submit(token, "google", e.shelf, tok, false); code != 200 {
		t.Fatalf("스위치 켬: %d %v", code, body)
	}
	e.wantKinds(token, "스위치 켬", noticePurchaseDone)
	e.srv.IAPSandbox = false
	e.wantKinds(token, "다시 끔")
	if e.me(token)["unreadNotices"] != float64(0) {
		t.Fatalf("끈 뒤 안 읽은 수: %v", e.me(token)["unreadNotices"])
	}
}

func TestIAPAdminStatsNotices(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
	e.submit(token, "google", e.shelf, tok, false)
	t.Setenv("ADMIN_TOKEN", "test-admin-token")
	req := httptest.NewRequest("GET", "/admin/iap/stats", nil)
	req.Header.Set("X-Admin-Token", "test-admin-token")
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	out := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	counts, _ := out["notices30Days"].(map[string]any)
	if rec.Code != 200 || counts == nil || counts[noticePurchaseDone].(float64) < 1 {
		t.Fatalf("운영 숫자의 고지 수: %d %v", rec.Code, out)
	}
	if _, ok := out["pendingNotifications"].(float64); !ok {
		t.Fatalf("기존 숫자가 빠짐: %v", out)
	}
}

// 연도를 모르는 선반 거래는 칸을 주지 않았으니 결제 완료를 알리지 않는다. 연도를 채운 순간 한 번 알린다.
// 한 책장에서 3칸을 넘게 산 거래는 결제 완료 대신 넘김 고지(shelf_over_cap)를 쓴다.
func TestIAPNoticeShelfYear(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	orphan := iapTestID(t, "orphan")
	e.google.Purchases[orphan] = e.shelfPurchase(orphan, "")
	if code, body := e.submit(token, "google", e.shelf, orphan, false); code != 422 || errCode(body) != "iap_shelf_year_missing" {
		t.Fatalf("연도 모름: %d %v", code, body)
	}
	e.wantKinds(token, "연도 모름")
	for range 2 {
		if code, body := e.submitYear(token, "google", e.shelf, orphan, 2026); code != 200 {
			t.Fatalf("연도와 다시 제출: %d %v", code, body)
		}
	}
	e.wantKinds(token, "연도를 채운 뒤", noticePurchaseDone)
	if p := e.notices(token)[0]["params"].(map[string]any); p["year"] != float64(2026) || p["overCap"] != nil {
		t.Fatalf("결제 완료 params: %v", p)
	}
	// 같은 해에 2칸을 더 사면 4칸 → 넘음
	more := iapTestID(t, "more")
	e.google.Purchases[more] = e.shelfPurchase(more, e.shelfToken(token, 2026))
	if code, body := e.submit(token, "google", e.shelf, more, false); code != 200 || body["overCap"] != true {
		t.Fatalf("넘는 구매: %d %v", code, body)
	}
	e.wantKinds(token, "넘는 구매 뒤", noticePurchaseDone, noticeShelfOverCap)
	n := e.notices(token)[0]
	if p := n["params"].(map[string]any); n["kind"] != noticeShelfOverCap || n["template"] != "T15" || p["year"] != float64(2026) || p["shelves"] != float64(2) || p["autoRefund"] != true || p["route"] != "google" {
		t.Fatalf("넘김 고지: %v", n)
	}
	// 구글 환불이 처리돼 환불 알림이 와도 선반 환불 고지를 또 쓰지 않는다(닫을 칸이 없다)
	e.notify("google", iap.Notice{ID: iapTestID(t, "r"), Type: "voided/2", Voided: true, Target: &iap.Ref{Kind: iap.KindProduct, ID: more}}, "Bearer pubsub")
	e.sweep()
	e.wantKinds(token, "넘은 거래 환불 뒤", noticePurchaseDone, noticeShelfOverCap)
	if body := e.me(token); shelvesIn(body, 2026) != 2 {
		t.Fatalf("넘은 거래가 환불돼도 칸 수는 그대로: %v", body)
	}
}

// 넘김 고지의 autoRefund: 애플은 false(사용자가 애플에 요청). 구글은 처음 요청이 실패하면 false였다가 정기 처리가 요청하면 true
func TestIAPNoticeShelfOverCapRefund(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	overCap := func(route string, year int) map[string]any {
		t.Helper()
		y := e.shelfToken(token, year)
		for range 2 {
			id := iapTestID(t, route)
			p := e.shelfPurchase(id, y)
			if route == "apple" {
				p.Route, p.TransactionID, p.Acknowledged = iap.RouteApple, id, true
				e.apple.Purchases[id] = p
			} else {
				e.google.Purchases[id] = p
			}
			e.submit(token, route, e.shelf, id, false)
		}
		for _, n := range e.notices(token) {
			if n["kind"] == noticeShelfOverCap && n["params"].(map[string]any)["year"] == float64(year) {
				return n["params"].(map[string]any)
			}
		}
		t.Fatalf("%d년 넘김 고지가 없음", year)
		return nil
	}
	if p := overCap("apple", 2026); p["autoRefund"] != false || p["route"] != "apple" {
		t.Fatalf("애플 넘김 고지: %v", p)
	}
	e.google.RefundErr = errors.New("구글 장애")
	if p := overCap("google", 2027); p["autoRefund"] != false {
		t.Fatalf("구글 요청 실패: %v", p)
	}
	e.google.RefundErr = nil
	// 실패한 환불은 간격(2분부터)이 지나야 다시 한다
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET updated_at=now()-interval '10 minutes' WHERE over_cap AND refund_requested_at IS NULL"); err != nil {
		t.Fatal(err)
	}
	if r := e.sweep(); r.Refunds != 1 {
		t.Fatalf("다시 요청: %+v", r)
	}
	for _, n := range e.notices(token) {
		if p := n["params"].(map[string]any); n["kind"] == noticeShelfOverCap && p["year"] == float64(2027) && p["autoRefund"] != true {
			t.Fatalf("다시 요청한 뒤 넘김 고지: %v", p)
		}
	}
}

// 갱신 결제도 결제 완료를 알린다(ADR-0003 L7). 알림으로 와도, 앱이 갱신 거래를 내도 거래마다 한 줄이다
func TestIAPNoticeRenewalPaid(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	orig, first := iapTestID(t, "orig"), iapTestID(t, "first")
	e.apple.Purchases[first] = e.subscription(orig, first, account, time.Now().Add(time.Hour))
	if code, _ := e.submit(token, "apple", e.plus, first, false); code != 200 {
		t.Fatal(code)
	}
	e.wantKinds(token, "처음 구매", noticePurchaseDone)

	// 한 달 뒤 갱신: 알림이 오고 대조가 두 번 돈다
	second := iapTestID(t, "second")
	e.apple.Purchases[second] = e.subscription(orig, second, account, time.Now().Add(31*24*time.Hour))
	for _, s := range []string{"a", "b"} {
		e.notify("apple", subNotice(iapTestID(t, "renew-"+s), second, orig), "")
		e.sweep()
	}
	// 앱도 같은 갱신 거래를 낸다(iOS)
	e.submit(token, "apple", e.plus, second, false)
	e.wantKinds(token, "첫 갱신", noticePurchaseDone, noticePurchaseDone)

	// 다음 갱신은 앱이 먼저 낸다
	third := iapTestID(t, "third")
	e.apple.Purchases[third] = e.subscription(orig, third, account, time.Now().Add(62*24*time.Hour))
	e.submit(token, "apple", e.plus, third, false)
	e.notify("apple", subNotice(iapTestID(t, "renew-c"), third, orig), "")
	e.sweep()
	e.wantKinds(token, "둘째 갱신", noticePurchaseDone, noticePurchaseDone, noticePurchaseDone)

	// 구매 복원은 새 결제가 아니다
	e.submit(token, "apple", e.plus, third, true)
	e.wantKinds(token, "복원", noticePurchaseDone, noticePurchaseDone, noticePurchaseDone)
}
