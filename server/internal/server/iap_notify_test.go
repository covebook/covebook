package server

import (
	"bytes"
	"encoding/json"
	"errors"
	"math/rand"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// notify는 스토어 알림을 보낸다. 가짜 스토어는 본문을 iap.Notice의 JSON으로 읽는다.
func (e *iapEnv) notify(route string, n any, auth string) int {
	e.t.Helper()
	var body []byte
	switch v := n.(type) {
	case string:
		body = []byte(v)
	default:
		body, _ = json.Marshal(v)
	}
	req := httptest.NewRequest("POST", "/iap/notifications/"+route, bytes.NewReader(body))
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	return rec.Code
}

func subNotice(id, txn, original string) iap.Notice {
	return iap.Notice{ID: id, Type: "DID_RENEW", Target: &iap.Ref{Kind: iap.KindSubscription, ID: txn}, OriginalID: original}
}

func (e *iapEnv) sweep() iapSweepResult {
	e.t.Helper()
	res, err := e.srv.iapSweep(e.ctx)
	if err != nil {
		e.t.Fatal(err)
	}
	return res
}

func (e *iapEnv) noticeResult(route, id string) (result, note string, attempts int) {
	e.t.Helper()
	var n *string
	if err := e.db.QueryRow(e.ctx, "SELECT result, error, attempts FROM iap_notifications WHERE route=$1 AND notification_id=$2", route, id).Scan(&result, &n, &attempts); err != nil {
		e.t.Fatal(err)
	}
	if n != nil {
		note = *n
	}
	return
}

func (e *iapEnv) me(token string) map[string]any {
	e.t.Helper()
	_, body := e.call("GET", "/iap/me", token, nil)
	return body
}

func TestIAPNotifyReceive(t *testing.T) {
	e := newIAPEnv(t)
	id := iapTestID(t, "n")
	count := func() (n int) {
		if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notifications WHERE notification_id=$1", id).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return
	}
	// 같은 알림이 여러 번 와도 한 줄만 남고 매번 200
	for range 3 {
		if code := e.notify("apple", subNotice(id, "txn", "orig"), ""); code != 200 {
			t.Fatalf("알림 수신 %d", code)
		}
	}
	if count() != 1 {
		t.Fatalf("알림 줄 수 %d", count())
	}
	if result, _, _ := e.noticeResult("apple", id); result != "received" {
		t.Fatalf("받기만 한 상태여야 함: %s", result)
	}
	// 연결 확인용 알림은 받자마자 끝낸다
	test := iapTestID(t, "test")
	if code := e.notify("apple", iap.Notice{ID: test, Type: "TEST", Test: true}, ""); code != 200 {
		t.Fatal(code)
	}
	if result, _, _ := e.noticeResult("apple", test); result != "ignored" {
		t.Fatalf("테스트 알림: %s", result)
	}
	// 형식이 틀린 본문: 애플은 400, 구글은 200(Pub/Sub이 계속 다시 보내지 않게)
	if code := e.notify("apple", "not json", ""); code != 400 {
		t.Fatalf("애플 틀린 본문 %d", code)
	}
	if code := e.notify("google", "not json", "Bearer pubsub"); code != 200 {
		t.Fatalf("구글 틀린 본문 %d", code)
	}
	// 다른 앱의 알림은 받았다고 답하고 버린다
	if code := e.notify("apple", `{"app":"other","ID":"x"}`, ""); code != 200 {
		t.Fatalf("다른 앱 %d", code)
	}
	// 서명 확인 실패는 5xx: 스토어가 다시 보내게 한다
	if code := e.notify("apple", `{"bad":"signature","ID":"x"}`, ""); code != 500 {
		t.Fatalf("서명 실패 %d", code)
	}
	// 구글 알림은 인증 토큰이 맞아야 받는다
	g := iapTestID(t, "g")
	if code := e.notify("google", subNotice(g, "tok", "tok"), ""); code != 401 {
		t.Fatalf("인증 없이 %d", code)
	}
	if code := e.notify("google", subNotice(g, "tok", "tok"), "Bearer wrong"); code != 401 {
		t.Fatalf("틀린 인증 %d", code)
	}
	if code := e.notify("google", subNotice(g, "tok", "tok"), "Bearer pubsub"); code != 200 {
		t.Fatalf("맞는 인증 %d", code)
	}
	// 인증 설정이 없는 서버는 구글 알림 경로를 열지 않는다
	srv := New(e.db)
	srv.IAP = map[iap.Route]iap.Store{iap.RouteGoogle: e.google}
	rec := httptest.NewRecorder()
	srv.Handler().ServeHTTP(rec, httptest.NewRequest("POST", "/iap/notifications/google", bytes.NewReader([]byte("{}"))))
	if rec.Code != 404 {
		t.Fatalf("인증 설정 없는 서버의 구글 알림 경로: %d", rec.Code)
	}
}

func TestIAPNotifyRenewalAndOrder(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	orig, txn1 := iapTestID(t, "orig"), iapTestID(t, "txn1")
	first := time.Now().Add(time.Hour)
	e.apple.Purchases[txn1] = e.subscription(orig, txn1, account, first)
	if code, body := e.submit(token, "apple", e.plus, txn1, false); code != 200 || body["plus"] != true {
		t.Fatalf("구독 제출: %d %v", code, body)
	}
	// 스토어에서 갱신됨: 새 거래와 새 만료일
	txn2 := iapTestID(t, "txn2")
	renewed := time.Now().Add(31 * 24 * time.Hour).UTC().Truncate(time.Second)
	e.apple.Purchases[txn2] = e.subscription(orig, txn2, account, renewed)

	// 알림이 겹치고 순서가 섞여 와도 결과는 스토어의 지금 상태다
	ids := []string{iapTestID(t, "a"), iapTestID(t, "b"), iapTestID(t, "c"), iapTestID(t, "d")}
	notices := []iap.Notice{
		subNotice(ids[0], txn2, orig), // 갱신
		subNotice(ids[1], txn1, orig), // 늦게 온 옛 알림
		subNotice(ids[2], txn2, orig), // 식별자만 다른 같은 내용
		subNotice(ids[0], txn2, orig), // 재전송
	}
	rand.Shuffle(len(notices), func(i, j int) { notices[i], notices[j] = notices[j], notices[i] })
	for _, n := range notices {
		if code := e.notify("apple", n, ""); code != 200 {
			t.Fatal(code)
		}
	}
	e.sweep()
	for _, id := range ids[:3] {
		if result, _, attempts := e.noticeResult("apple", id); result != "processed" || attempts != 1 {
			t.Fatalf("알림 %s: %s, 시도 %d", id, result, attempts)
		}
	}
	sub, _ := e.me(token)["subscription"].(map[string]any)
	if sub == nil || sub["expiresAt"] != renewed.Format(time.RFC3339) || sub["active"] != true {
		t.Fatalf("갱신 뒤 구독: %v (기대 만료 %s)", sub, renewed.Format(time.RFC3339))
	}
	var subs, txns int
	if err := e.db.QueryRow(e.ctx, "SELECT (SELECT count(*) FROM iap_subscriptions WHERE original_id=$1),(SELECT count(*) FROM iap_purchases WHERE original_id=$1)", orig).Scan(&subs, &txns); err != nil || subs != 1 || txns != 2 {
		t.Fatalf("구독 줄 %d, 거래 줄 %d", subs, txns)
	}
	// 한 번 처리한 알림은 다시 처리하지 않는다
	e.sweep()
	if _, _, attempts := e.noticeResult("apple", ids[0]); attempts != 1 {
		t.Fatalf("다시 처리됨: 시도 %d", attempts)
	}
}

// 구독을 넘겨받은 뒤에도 스토어는 옛 주인의 계정 연결 값을 보낸다. 알림이 주인을 되돌리면 안 된다.
func TestIAPNotifyKeepsOwnerAfterTransfer(t *testing.T) {
	e := newIAPEnv(t)
	a, _ := e.user()
	b, _ := e.user()
	accountA := e.accountToken(a)
	e.accountToken(b)
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[txn] = e.subscription(orig, txn, accountA, time.Now().Add(time.Hour))
	e.submit(a, "apple", e.plus, txn, false)
	if code, _ := e.submit(b, "apple", e.plus, txn, true); code != 200 {
		t.Fatal("복원 실패")
	}
	e.notify("apple", subNotice(iapTestID(t, "n"), txn, orig), "")
	e.sweep()
	if e.me(a)["plus"] != false || e.me(b)["plus"] != true {
		t.Fatalf("알림 뒤 주인이 바뀜: a=%v b=%v", e.me(a)["plus"], e.me(b)["plus"])
	}
}

// 앱이 제출하기 전에 알림이 먼저 오면(앱이 꺼짐) 계정 연결 값으로 주인을 찾아 지급하고 스토어 확인까지 한다.
func TestIAPNotifyBeforeSubmit(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)

	// 구글 구독
	subTok := iapTestID(t, "subtok")
	sub := e.subscription(subTok, iapTestID(t, "GPA"), account, time.Now().Add(time.Hour))
	sub.Route, sub.Acknowledged = iap.RouteGoogle, false
	e.google.Purchases[subTok] = sub
	e.notify("google", subNotice(iapTestID(t, "n1"), subTok, subTok), "Bearer pubsub")
	// 구글 한 번 사는 상품(2026년 책장)
	shelfTok := iapTestID(t, "shelftok")
	e.google.Purchases[shelfTok] = e.shelfPurchase(shelfTok, e.shelfToken(token, 2026))
	shelfNote := iapTestID(t, "n2")
	e.notify("google", iap.Notice{ID: shelfNote, Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: shelfTok}}, "Bearer pubsub")
	// 주인을 모르는 구매(계정 연결 값 없음): 지급하지 않고 스토어 확인도 하지 않는다
	orphan := iapTestID(t, "orphan")
	e.google.Purchases[orphan] = e.shelfPurchase(orphan, "")
	orphanNote := iapTestID(t, "n3")
	e.notify("google", iap.Notice{ID: orphanNote, Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: orphan}}, "Bearer pubsub")
	e.sweep()
	body := e.me(token)
	if body["plus"] != true || shelvesIn(body, 2026) != 2 {
		t.Fatalf("알림만으로 지급: %v", body)
	}
	if _, note, _ := e.noticeResult("google", shelfNote); !strings.Contains(note, "2026년") {
		t.Fatalf("선반 알림 처리 기록에 연도가 없음: %q", note)
	}
	confirmed := map[string]bool{}
	for _, id := range e.google.Confirmed {
		confirmed[id] = true
	}
	if !confirmed[subTok] || !confirmed[shelfTok] || confirmed[orphan] {
		t.Fatalf("스토어 확인: %v", e.google.Confirmed)
	}
	if result, note, _ := e.noticeResult("google", orphanNote); result != "processed" || note == "" {
		t.Fatalf("주인 모르는 구매: %s %q", result, note)
	}
	// 나중에 앱이 그 구매를 내면 연결된다. 계정 연결 값이 없으니 앱이 보낸 연도 책장에 준다
	if code, b := e.submitYear(token, "google", e.shelf, orphan, 2027); code != 200 || shelvesIn(b, 2027) != 2 || shelvesIn(b, 2026) != 2 {
		t.Fatalf("나중에 제출: %d %v", code, b)
	}
	// 앱이 뒤늦게 같은 구매를 내도 한 번만 센다
	if code, b := e.submit(token, "google", e.shelf, shelfTok, false); code != 200 || b["status"] != "already" || shelvesIn(b, 2026) != 2 {
		t.Fatalf("알림 뒤 제출: %d %v", code, b)
	}
}

func TestIAPNotifyRefund(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	shelfAccount := e.shelfToken(token, 2026)
	state := func(route, key string) (st string) {
		if err := e.db.QueryRow(e.ctx, "SELECT state FROM iap_purchases WHERE route=$1 AND transaction_id=$2", route, key).Scan(&st); err != nil {
			t.Fatal(err)
		}
		return
	}

	// 구글 선반 환불: 구글의 환불 알림이 곧 근거다. 조회가 여전히 "결제됨"이라고 답해도 선반이 빠진다. 줄은 남는다
	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, shelfAccount)
	e.submit(token, "google", e.shelf, tok, false)
	e.notify("google", iap.Notice{ID: iapTestID(t, "r1"), Type: "voided/2", Voided: true, OrderID: "GPA.x", Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
	e.sweep()
	if shelvesIn(e.me(token), 2026) != 0 || state("google", tok) != "revoked" {
		t.Fatalf("구글 환불 뒤 선반 %v, 원장 %s", e.me(token)["shelvesByYear"], state("google", tok))
	}
	// 그 뒤 같은 구매의 다른 알림이 와도(조회는 계속 "결제됨") 환불 표시가 되살아나지 않는다
	e.notify("google", iap.Notice{ID: iapTestID(t, "r1b"), Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
	e.sweep()
	if shelvesIn(e.me(token), 2026) != 0 || state("google", tok) != "revoked" {
		t.Fatalf("환불 표시가 되살아남: 선반 %v, 원장 %s", e.me(token)["shelvesByYear"], state("google", tok))
	}
	// 스토어가 그 토큰을 더는 모른다고 답해도 환불은 반영된다
	gone := iapTestID(t, "gone")
	e.google.Purchases[gone] = e.shelfPurchase(gone, shelfAccount)
	e.submit(token, "google", e.shelf, gone, false)
	delete(e.google.Purchases, gone)
	e.notify("google", iap.Notice{ID: iapTestID(t, "r1c"), Type: "voided/2", Voided: true, Target: &iap.Ref{Kind: iap.KindProduct, ID: gone}}, "Bearer pubsub")
	e.sweep()
	if state("google", gone) != "revoked" {
		t.Fatalf("스토어가 모르는 토큰의 환불: %s", state("google", gone))
	}

	// 애플 선반 환불과 환불 되돌림: 애플은 거래마다 환불 여부를 알려 준다
	txn := iapTestID(t, "atxn")
	a := e.shelfPurchase(txn, shelfAccount)
	a.Route, a.TransactionID, a.Acknowledged = iap.RouteApple, txn, true
	e.apple.Purchases[txn] = a
	e.submit(token, "apple", e.shelf, txn, false)
	a.State = iap.StateRevoked
	e.apple.Purchases[txn] = a
	e.notify("apple", iap.Notice{ID: iapTestID(t, "r2"), Type: "REFUND", Target: &iap.Ref{Kind: iap.KindProduct, ID: txn}}, "")
	e.sweep()
	if shelvesIn(e.me(token), 2026) != 0 || state("apple", txn) != "revoked" {
		t.Fatalf("애플 환불 뒤 선반 %v", e.me(token)["shelvesByYear"])
	}
	a.State = iap.StatePaid
	e.apple.Purchases[txn] = a
	e.notify("apple", iap.Notice{ID: iapTestID(t, "r3"), Type: "REFUND_REVERSED", Target: &iap.Ref{Kind: iap.KindProduct, ID: txn}}, "")
	e.sweep()
	if shelvesIn(e.me(token), 2026) != 2 || state("apple", txn) != "paid" {
		t.Fatalf("애플 환불 되돌림 뒤 선반 %v", e.me(token)["shelvesByYear"])
	}

	// 구독 환불: 구독 상태가 환불로 바뀌어 권한이 없어진다
	orig, stxn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[stxn] = e.subscription(orig, stxn, account, time.Now().Add(time.Hour))
	e.submit(token, "apple", e.plus, stxn, false)
	sp := e.apple.Purchases[stxn]
	sp.State = iap.StateRevoked
	e.apple.Purchases[stxn] = sp
	e.notify("apple", iap.Notice{ID: iapTestID(t, "r4"), Type: "REFUND", Target: &iap.Ref{Kind: iap.KindSubscription, ID: stxn}, OriginalID: orig}, "")
	e.sweep()
	if e.me(token)["plus"] != false {
		t.Fatal("환불된 구독에 권한이 남음")
	}
	// 구글 구독 갱신 거래의 환불은 주문 ID로 원장 줄을 찾는다. 그 뒤 다른 알림이 와도 표시가 남는다
	subTok, order := iapTestID(t, "subtok"), iapTestID(t, "GPA")
	g := e.subscription(subTok, order, account, time.Now().Add(time.Hour))
	g.Route = iap.RouteGoogle
	e.google.Purchases[subTok] = g
	e.submit(token, "google", e.plus, subTok, false)
	e.notify("google", iap.Notice{ID: iapTestID(t, "r5"), Type: "voided/1", Voided: true, OrderID: order, Target: &iap.Ref{Kind: iap.KindSubscription, ID: subTok}, OriginalID: subTok}, "Bearer pubsub")
	e.sweep()
	e.notify("google", subNotice(iapTestID(t, "r6"), subTok, subTok), "Bearer pubsub")
	e.sweep()
	if state("google", order) != "revoked" {
		t.Fatalf("구글 구독 환불 원장 상태 %s", state("google", order))
	}
}

// 스토어 조회가 실패하면 알림을 버리지 않고 간격을 늘려 다시 시도한다.
func TestIAPNotifyRetry(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[txn] = e.subscription(orig, txn, e.accountToken(token), time.Now().Add(time.Hour))
	id := iapTestID(t, "n")
	e.notify("apple", subNotice(id, txn, orig), "")
	e.apple.Err = errors.New("timeout")
	e.sweep()
	if result, note, attempts := e.noticeResult("apple", id); result != "failed" || attempts != 1 || note == "" {
		t.Fatalf("실패 기록: %s %d %q", result, attempts, note)
	}
	e.apple.Err = nil
	// 방금 실패한 것은 바로 다시 시도하지 않는다
	e.sweep()
	if _, _, attempts := e.noticeResult("apple", id); attempts != 1 {
		t.Fatalf("간격 없이 다시 시도: 시도 %d", attempts)
	}
	// 시간이 지나면 다시 시도해서 성공한다
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_notifications SET processed_at=now()-interval '10 minutes' WHERE notification_id=$1", id); err != nil {
		t.Fatal(err)
	}
	e.sweep()
	if result, _, attempts := e.noticeResult("apple", id); result != "processed" || attempts != 2 {
		t.Fatalf("다시 시도 뒤: %s %d", result, attempts)
	}
	if e.me(token)["plus"] != true {
		t.Fatal("다시 시도로 지급되지 않음")
	}
}

func TestIAPSweepConfirmAndRefresh(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)

	// 스토어 확인을 못 마친 거래: 대조 작업이 다시 시도한다
	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
	e.google.ConfirmErr = errors.New("503")
	e.submit(token, "google", e.shelf, tok, false)
	e.google.ConfirmErr = nil
	var confirmed *time.Time
	confirmedAt := func() *time.Time {
		if err := e.db.QueryRow(e.ctx, "SELECT confirmed_at FROM iap_purchases WHERE transaction_id=$1", tok).Scan(&confirmed); err != nil {
			t.Fatal(err)
		}
		return confirmed
	}
	// 방금 넣은 것은 아직 대상이 아니다(제출 요청이 스스로 확인하는 중일 수 있다)
	if e.sweep(); confirmedAt() != nil {
		t.Fatal("방금 넣은 거래를 대조 작업이 확인함")
	}
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET created_at=now()-interval '5 minutes' WHERE transaction_id=$1", tok); err != nil {
		t.Fatal(err)
	}
	if e.sweep(); confirmedAt() == nil {
		t.Fatal("확인 재시도 뒤에도 확인 시각이 없음")
	}

	// 만료가 지난 구독: 알림이 안 와도 대조 작업이 스토어에 물어 갱신을 반영한다
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[txn] = e.subscription(orig, txn, account, time.Now().Add(time.Hour))
	e.submit(token, "apple", e.plus, txn, false)
	old := func() {
		if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET expires_at=now()-interval '1 minute', updated_at=now()-interval '1 hour' WHERE original_id=$1", orig); err != nil {
			t.Fatal(err)
		}
	}
	old()
	if plus := e.me(token)["plus"]; plus != false {
		t.Fatalf("만료됐는데 권한: %v", plus)
	}
	if e.sweep(); e.me(token)["plus"] != true {
		t.Fatal("만료 뒤 재확인으로 갱신이 반영되지 않음")
	}
	// 방금 확인한 구독은 다시 묻지 않는다: 스토어 값을 바꿔도 다음 대조에서 그대로다
	later := e.apple.Purchases[txn]
	later.ExpiresAt = time.Now().Add(72 * time.Hour)
	e.apple.Purchases[txn] = later
	before := e.me(token)["subscription"].(map[string]any)["expiresAt"]
	if e.sweep(); e.me(token)["subscription"].(map[string]any)["expiresAt"] != before {
		t.Fatal("방금 확인한 구독을 또 물음")
	}
	// 스토어가 더는 그 구독을 모르면 권한 없음으로 확정한다
	old()
	delete(e.apple.Purchases, txn)
	e.sweep()
	var state string
	if err := e.db.QueryRow(e.ctx, "SELECT state FROM iap_subscriptions WHERE original_id=$1", orig).Scan(&state); err != nil || state != "inactive" {
		t.Fatalf("스토어에 없는 구독의 상태 %s %v", state, err)
	}
}

// 구글 요금제 변경: 새 구매 토큰이 옛 토큰을 대신한다. 옛 줄기를 끝내고 주인을 이어받는다.
func TestIAPGoogleLinkedToken(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	oldTok := iapTestID(t, "old")
	old := e.subscription(oldTok, iapTestID(t, "GPA1"), account, time.Now().Add(time.Hour))
	old.Route = iap.RouteGoogle
	e.google.Purchases[oldTok] = old
	e.submit(token, "google", e.plus, oldTok, false)

	// 새 토큰에는 계정 연결 값이 없다고 하자(앱이 다시 넘기지 않은 경우). 옛 줄기의 주인을 이어받는다
	newTok := iapTestID(t, "new")
	fresh := e.subscription(newTok, iapTestID(t, "GPA2"), "", time.Now().Add(48*time.Hour))
	fresh.Route, fresh.LinkedID, fresh.Acknowledged = iap.RouteGoogle, oldTok, false
	e.google.Purchases[newTok] = fresh
	e.notify("google", subNotice(iapTestID(t, "n"), newTok, newTok), "Bearer pubsub")
	e.sweep()

	var oldState, newState string
	var owners int
	if err := e.db.QueryRow(e.ctx, `SELECT
		(SELECT state FROM iap_subscriptions WHERE original_id=$1),
		(SELECT state FROM iap_subscriptions WHERE original_id=$2),
		(SELECT count(DISTINCT user_id) FROM iap_subscriptions WHERE original_id IN ($1,$2))`, oldTok, newTok).Scan(&oldState, &newState, &owners); err != nil {
		t.Fatal(err)
	}
	if oldState != "inactive" || newState != "paid" || owners != 1 {
		t.Fatalf("옛 줄기 %s, 새 줄기 %s, 주인 수 %d", oldState, newState, owners)
	}
	if e.me(token)["plus"] != true {
		t.Fatal("요금제 변경 뒤 권한이 없음")
	}
}

// 샌드박스 알림은 스위치가 꺼져 있으면 지급으로 이어지지 않는다.
func TestIAPNotifySandboxIgnored(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	p := e.shelfPurchase(tok, e.shelfToken(token, 2026))
	p.Env = iap.EnvSandbox
	e.google.Purchases[tok] = p
	id := iapTestID(t, "n")
	e.notify("google", iap.Notice{ID: id, Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: tok}}, "Bearer pubsub")
	e.sweep()
	if result, _, _ := e.noticeResult("google", id); result != "processed" {
		t.Fatalf("샌드박스 알림 결과: %s", result)
	}
	var n int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_purchases WHERE transaction_id=$1", tok).Scan(&n); err != nil || n != 0 {
		t.Fatalf("샌드박스 거래가 원장에 들어감: %d", n)
	}
}

// 샌드박스 스위치를 끈 뒤 남은 샌드박스 구독 줄: 대조 작업이 이 줄만 되풀이하지 않게 "확인했다"고 남긴다.
func TestIAPSweepSkipsUnacceptedLines(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	e.srv.IAPSandbox = true
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	p := e.subscription(orig, txn, e.accountToken(token), time.Now().Add(time.Hour))
	p.Env = iap.EnvSandbox
	e.apple.Purchases[txn] = p
	if code, _ := e.submit(token, "apple", e.plus, txn, false); code != 200 {
		t.Fatal("샌드박스 구독 제출 실패")
	}
	e.srv.IAPSandbox = false
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET expires_at=now()-interval '1 minute', updated_at=now()-interval '1 hour' WHERE original_id=$1", orig); err != nil {
		t.Fatal(err)
	}
	e.sweep()
	var fresh bool
	if err := e.db.QueryRow(e.ctx, "SELECT updated_at > now() - interval '1 minute' FROM iap_subscriptions WHERE original_id=$1", orig).Scan(&fresh); err != nil || !fresh {
		t.Fatalf("받지 않는 줄이 확인 표시 없이 남음 (다음 대조에서 또 뽑힘): %v %v", fresh, err)
	}
	// 스토어 조회가 실패한 줄도 마찬가지다
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET updated_at=now()-interval '1 hour' WHERE original_id=$1", orig); err != nil {
		t.Fatal(err)
	}
	e.apple.Err = errors.New("timeout")
	e.sweep()
	e.apple.Err = nil
	if err := e.db.QueryRow(e.ctx, "SELECT updated_at > now() - interval '1 minute' FROM iap_subscriptions WHERE original_id=$1", orig).Scan(&fresh); err != nil || !fresh {
		t.Fatalf("조회 실패한 줄이 확인 표시 없이 남음: %v %v", fresh, err)
	}
}

// 줄이 아직 없을 때 "다른 계정의 복원 제출"과 "알림 처리"가 동시에 돌아도, 알림이 제출한 사람의 구독을 덮어쓰지 않는다.
func TestIAPSubmitAndNoticeRace(t *testing.T) {
	e := newIAPEnv(t)
	a, _ := e.user()
	b, _ := e.user()
	accountA := e.accountToken(a)
	e.accountToken(b)
	for round := range 8 {
		orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
		e.apple.Purchases[txn] = e.subscription(orig, txn, accountA, time.Now().Add(time.Hour))
		done := make(chan struct{})
		go func() {
			defer close(done)
			if _, err := e.srv.iapSyncSubscription(e.ctx, e.apple, orig); err != nil {
				t.Error(err)
			}
		}()
		code, body := e.submit(b, "apple", e.plus, txn, true)
		<-done
		if code != 200 || body["plus"] != true {
			t.Fatalf("%d번째: 복원 제출 %d %v", round, code, body)
		}
		var owner int64
		var bID int64
		if err := e.db.QueryRow(e.ctx, "SELECT s.user_id, (SELECT user_id FROM iap_account_tokens WHERE user_id<>(SELECT user_id FROM iap_account_tokens WHERE token::text=$2) AND user_id=s.user_id LIMIT 1) FROM iap_subscriptions s WHERE original_id=$1", orig, accountA).Scan(&owner, &bID); err != nil {
			t.Fatalf("%d번째: 복원한 계정이 주인이 아님 (알림이 덮어씀): %v", round, err)
		}
		if owner != bID {
			t.Fatalf("%d번째: 주인 %d", round, owner)
		}
		// 다음 판을 위해 b의 구독을 끝낸다
		if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET state='inactive' WHERE original_id=$1", orig); err != nil {
			t.Fatal(err)
		}
	}
}

// 알림이 앱보다 먼저 온 선반 구매: 그 해 예약 하나를 풀고, 3칸을 넘었으면 칸을 주지 않고 환불을 요청한다.
// 환불 요청이 실패하면 정기 처리가 다시 시도한다. 애플의 넘은 거래는 다시 시도하지 않는다
func TestIAPNotifyOverCap(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	_, res := e.call("POST", "/iap/shelf-token", token, map[string]any{"year": 2026, "shelves": 2})
	y := res["token"].(string)

	first, second := iapTestID(t, "t1"), iapTestID(t, "t2")
	e.google.Purchases[first] = e.shelfPurchase(first, y)
	e.google.Purchases[second] = e.shelfPurchase(second, y)
	e.notify("google", iap.Notice{ID: iapTestID(t, "n1"), Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: first}}, "Bearer pubsub")
	e.sweep()
	var held int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_shelf_reservations WHERE user_id=$1", user).Scan(&held); err != nil || held != 0 {
		t.Fatalf("알림으로 지급하면 예약이 풀려야 함: %d %v", held, err)
	}
	// 두 번째(예약을 지나친 구매)는 환불 요청이 실패한다
	e.google.RefundErr = errors.New("구글 장애")
	n2 := iapTestID(t, "n2")
	e.notify("google", iap.Notice{ID: n2, Type: "product/1", Target: &iap.Ref{Kind: iap.KindProduct, ID: second}}, "Bearer pubsub")
	if r := e.sweep(); r.Refunds != 0 {
		t.Fatalf("장애 중 환불: %+v", r)
	}
	if _, note, _ := e.noticeResult("google", n2); !strings.Contains(note, "3칸 넘음") {
		t.Fatalf("처리 기록: %q", note)
	}
	if body := e.me(token); shelvesIn(body, 2026) != 2 {
		t.Fatalf("넘은 거래는 칸을 주지 않음: %v", body)
	}
	if len(e.google.Refunded) != 0 {
		t.Fatalf("실패했는데 환불 기록: %v", e.google.Refunded)
	}
	// 장애가 풀리면 다음 정기 처리가 다시 요청한다. 한 번만
	e.google.RefundErr = nil
	if r := e.sweep(); r.Refunds != 1 || len(e.google.Refunded) != 1 || e.google.Refunded[0] != "GPA."+second {
		t.Fatalf("다시 요청: %+v %v", r, e.google.Refunded)
	}
	if r := e.sweep(); r.Refunds != 0 || len(e.google.Refunded) != 1 {
		t.Fatalf("한 번 요청한 거래를 또 요청: %+v %v", r, e.google.Refunded)
	}

	// 애플의 넘은 거래는 기록만 하고 다시 시도 목록에 들어가지 않는다
	ya := e.shelfToken(token, 2027)
	for _, id := range []string{iapTestID(t, "a1"), iapTestID(t, "a2")} {
		p := e.shelfPurchase(id, ya)
		p.Route, p.TransactionID, p.Acknowledged = iap.RouteApple, id, true
		e.apple.Purchases[id] = p
		e.submit(token, "apple", e.shelf, id, false)
	}
	rows, err := iapOverCapToRefund(e.ctx, e.db, []string{"google"}, 50)
	if err != nil || len(rows) != 0 {
		t.Fatalf("애플 거래가 다시 시도 목록에: %v %v", rows, err)
	}
}

// 연도를 모르는 선반: 제출이 일부러 소비하지 않았으니 정기 대조도 소비하지 않는다(구글 3일 자동 환불을 지킨다).
// 연도와 함께 다시 내면 그때 지급하고 확인한다
func TestIAPSweepSkipsShelfWithoutYear(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	// 연도별 값이 아닌 계정 연결 값으로 결제했고 예약도 없다: 서버는 어느 해 책장인지 모른다
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.accountToken(token))
	if code, body := e.submit(token, "google", e.shelf, tok, false); code != 422 || errCode(body) != "iap_shelf_year_missing" {
		t.Fatalf("연도 모르는 선반 제출: %d %v", code, body)
	}
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET created_at=now()-interval '5 minutes' WHERE transaction_id=$1", tok); err != nil {
		t.Fatal(err)
	}
	e.sweep()
	for _, id := range e.google.Confirmed {
		if id == tok {
			t.Fatal("연도 모르는 선반을 대조 작업이 소비함")
		}
	}
	// 연도를 붙여 다시 내면 지급하고 소비한다
	if code, _ := e.submitYear(token, "google", e.shelf, tok, 2026); code != 200 {
		t.Fatalf("연도와 다시 제출: %d", code)
	}
	found := false
	for _, id := range e.google.Confirmed {
		found = found || id == tok
	}
	if !found {
		t.Fatal("연도와 다시 낸 선반을 소비하지 않음")
	}
}

// 알림 하나가 처리 중 패닉을 내도 그 알림만 실패로 남고, 뒤의 알림은 처리된다
func TestIAPNotifyPanicIsolated(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)
	badOrig, badTxn := iapTestID(t, "bad-orig"), iapTestID(t, "bad-txn")
	e.apple.Purchases[badTxn] = e.subscription(badOrig, badTxn, account, time.Now().Add(time.Hour))
	goodOrig, goodTxn := iapTestID(t, "good-orig"), iapTestID(t, "good-txn")
	e.apple.Purchases[goodTxn] = e.subscription(goodOrig, goodTxn, account, time.Now().Add(time.Hour))
	e.apple.PanicOn = badOrig
	bad, good := iapTestID(t, "bad-n"), iapTestID(t, "good-n")
	e.notify("apple", subNotice(bad, badTxn, badOrig), "")
	e.notify("apple", subNotice(good, goodTxn, goodOrig), "")
	e.sweep()
	if result, note, attempts := e.noticeResult("apple", bad); result != "failed" || attempts != 1 || !strings.Contains(note, "패닉") {
		t.Fatalf("패닉 난 알림: %s %d %q", result, attempts, note)
	}
	if result, note, _ := e.noticeResult("apple", good); result != "processed" {
		t.Fatalf("뒤의 알림: %s %q", result, note)
	}
}
