package iapkit

import (
	"strings"
	"testing"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit/iap"
)

// 수량 구매(2개 이상)는 알림이 제출보다 먼저 와도 받지 않는다(제출 경로와 같다). 1칸 값만 주면 2배를 내고 1칸을 받는다
func TestIAPNotifyRejectsQuantity(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	p := e.shelfPurchase(tok, e.shelfToken(token, 2026))
	p.Quantity = 2
	e.google.Purchases[tok] = p
	note := iapTestID(t, "n")
	e.notify("google", iap.Notice{ID: note, Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
	e.sweep()
	if n := shelvesIn(e.me(token), 2026); n != 0 {
		t.Fatalf("수량 구매에 칸을 줌: %v", n)
	}
	if res, msg, _ := e.noticeResult("google", note); res != "processed" || !strings.Contains(msg, "수량") {
		t.Fatalf("알림 결과 %s %q", res, msg)
	}
	var rows int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_purchases WHERE route='google' AND original_id=$1", tok).Scan(&rows); err != nil || rows != 0 {
		t.Fatalf("수량 구매를 원장에 적음: %d %v", rows, err)
	}
	for _, id := range e.google.Confirmed {
		if id == tok {
			t.Fatal("받지 않는 수량 구매를 소비함(구글 자동 환불이 막힘)")
		}
	}
}

// 유효한 구독도 하루에 한 번 스토어에 다시 묻는다. 환불 알림을 놓쳐도 만료일까지 유효로 남지 않게
func TestIAPDailySubscriptionRecheck(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	orig := iapTestID(t, "orig")
	sub := e.subscription(orig, iapTestID(t, "txn"), account, time.Now().Add(300*24*time.Hour))
	e.apple.Purchases[orig] = sub
	if code, body := e.submit(token, "apple", e.plus, orig, false); code != 200 || !plusIn(body) {
		t.Fatalf("구독 제출 %d %v", code, body)
	}
	// 환불됐는데 알림이 오지 않았다
	sub.State = iap.StateRevoked
	e.apple.Purchases[orig] = sub
	if e.sweep(); !plusIn(e.me(token)) {
		t.Fatal("방금 확인한 구독을 바로 다시 물음(하루에 한 번이어야 함)")
	}
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET updated_at = now() - interval '25 hours' WHERE original_id=$1", orig); err != nil {
		t.Fatal(err)
	}
	if e.sweep(); plusIn(e.me(token)) {
		t.Fatal("하루가 지나도 다시 묻지 않아 환불된 구독이 유효로 남음")
	}
}

// 같은 권한의 다른 구독이 유효한데 한 구독이 끝나면 "구독이 끝났습니다"(T8)를 쓰지 않는다(구글 요금제 교체, 중복 구독).
// 마지막 구독이 끝날 때는 쓴다
func TestIAPExpiredNoticeSkippedWhenStillEntitled(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	account := e.accountToken(token)
	a, b := iapTestID(t, "a"), iapTestID(t, "b")
	subA := e.subscription(a, iapTestID(t, "ta"), account, time.Now().Add(time.Minute))
	subB := e.subscription(b, iapTestID(t, "tb"), account, time.Now().Add(30*24*time.Hour))
	e.apple.Purchases[a], e.apple.Purchases[b] = subA, subB
	for _, id := range []string{a, b} {
		if code, body := e.submit(token, "apple", e.plus, id, true); code != 200 {
			t.Fatalf("구독 제출 %d %v", code, body)
		}
	}
	expired := func() int {
		t.Helper()
		var n int
		if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notices WHERE user_id=$1 AND kind='expired'", user).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	expire := func(id string, p iap.Purchase) {
		t.Helper()
		p.State, p.ExpiresAt, p.AutoRenew = iap.StateInactive, time.Now().Add(-time.Minute), false
		e.apple.Purchases[id] = p
		if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET expires_at=now()-interval '1 minute', updated_at=now()-interval '2 days' WHERE original_id=$1", id); err != nil {
			t.Fatal(err)
		}
		e.sweep()
	}
	expire(a, subA)
	if n := expired(); n != 0 || !plusIn(e.me(token)) {
		t.Fatalf("다른 구독이 유효한데 만료 고지 %d건", n)
	}
	expire(b, subB)
	if n := expired(); n != 1 || plusIn(e.me(token)) {
		t.Fatalf("마지막 구독이 끝났는데 만료 고지 %d건", n)
	}
}

// 구글 설정이 틀려도 애플은 켜지고, 틀린 설정은 경보로 올라간다(전에는 두 스토어가 함께 조용히 꺼졌다)
func TestIAPStoreConfigProblemIsAlerted(t *testing.T) {
	t.Setenv("IAP_ENABLED", "1")
	t.Setenv("IAP_APPLE_KEY_P8", "-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----")
	t.Setenv("IAP_APPLE_KEY_ID", "K")
	t.Setenv("IAP_APPLE_ISSUER_ID", "I")
	t.Setenv("IAP_APPLE_BUNDLE_ID", "app.covebook")
	t.Setenv("IAP_GOOGLE_PACKAGE", "app.covebook") // 키 없이 패키지만
	t.Setenv("IAP_GOOGLE_KEY_JSON", "")
	stores := StoresFromEnv()
	t.Cleanup(func() { storeConfigProblem = "" })
	if stores[iap.RouteApple] == nil || stores[iap.RouteGoogle] != nil {
		t.Fatalf("구글만 틀렸는데 스토어 %v", stores)
	}
	k := New(nil, stores, Rules{}, false)
	alerts := iapAlerts(iapBacklog{ConfigProblems: k.iapConfigProblems})
	if len(alerts) != 1 || !strings.Contains(alerts[0].Msg, "IAP_GOOGLE_KEY_JSON") {
		t.Fatalf("설정 문제 경보 %v", alerts)
	}
}
