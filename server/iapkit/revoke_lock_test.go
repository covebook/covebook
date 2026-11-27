package iapkit

import (
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit/iap"
)

// 상한 개수를 바꾸는 쓰기(환불 회수, 환불 되돌림)가 제출·상한 판정과 같은 유저 줄 잠금 위에서 도는지 본다.

// 애플이 환불을 되돌렸는데 그사이 같은 대상을 또 샀으면, 되돌린 거래가 상한을 넘은 거래가 된다.
// 되돌린 뒤 상한을 다시 판정하지 않으면 같은 대상에 유효 거래가 4칸(상한 3칸)이 되고, 사용자는 넘김 고지도 환불 안내도 받지 못한다.
func TestIAPRefundReversalRechecksCap(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	state := func(txn string) (st string, over bool) {
		t.Helper()
		if err := e.db.QueryRow(e.ctx, "SELECT state, over_cap FROM iap_purchases WHERE route='apple' AND transaction_id=$1", txn).Scan(&st, &over); err != nil {
			t.Fatal(err)
		}
		return
	}

	// 거래 A(2칸)를 사고 환불받는다
	txnA := iapTestID(t, "A")
	a := e.shelfPurchase(txnA, e.shelfToken(token, 2026))
	a.Route, a.TransactionID, a.Acknowledged = iap.RouteApple, txnA, true
	e.apple.Purchases[txnA] = a
	if code, body := e.submit(token, "apple", e.shelf, txnA, false); code != 200 {
		t.Fatalf("A 제출 %d %v", code, body)
	}
	a.State = iap.StateRevoked
	e.apple.Purchases[txnA] = a
	e.notify("apple", iap.Notice{ID: iapTestID(t, "refund"), Type: "REFUND", Target: &iap.Ref{Kind: iap.KindProduct, ID: txnA}}, "")
	e.sweep()
	if shelvesIn(e.me(token), 2026) != 0 {
		t.Fatalf("환불 뒤 선반 %v", e.me(token)["unitsByTarget"])
	}

	// 환불된 동안 같은 대상에 거래 B(2칸)를 산다. 상한 3칸 안이라 준다
	txnB := iapTestID(t, "B")
	b := e.shelfPurchase(txnB, e.shelfToken(token, 2026))
	b.Route, b.TransactionID, b.Acknowledged = iap.RouteApple, txnB, true
	e.apple.Purchases[txnB] = b
	if code, body := e.submit(token, "apple", e.shelf, txnB, false); code != 200 {
		t.Fatalf("B 제출 %d %v", code, body)
	}
	if shelvesIn(e.me(token), 2026) != 2 {
		t.Fatalf("B 뒤 선반 %v", e.me(token)["unitsByTarget"])
	}

	// 애플이 A의 환불을 되돌린다. A가 다시 유효해지면 2+2=4칸 > 3칸이라 A는 넘은 거래다
	a.State = iap.StatePaid
	e.apple.Purchases[txnA] = a
	e.notify("apple", iap.Notice{ID: iapTestID(t, "reversed"), Type: "REFUND_REVERSED", Target: &iap.Ref{Kind: iap.KindProduct, ID: txnA}}, "")
	e.sweep()
	if st, over := state(txnA); st != "paid" || !over {
		t.Fatalf("되돌린 A: state=%s over_cap=%v (paid, true여야 함)", st, over)
	}
	if st, over := state(txnB); st != "paid" || over {
		t.Fatalf("먼저 받은 B는 그대로여야: state=%s over_cap=%v", st, over)
	}
	if n := shelvesIn(e.me(token), 2026); n != 2 {
		t.Fatalf("되돌림 뒤 선반 %v칸 (B의 2칸이어야 함)", n)
	}
	var notices int
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notices WHERE kind=$1 AND dedupe_key=$2",
		noticeProductOverCap, iapOverCapDedupe(iap.RouteApple, txnA)).Scan(&notices); err != nil || notices != 1 {
		t.Fatalf("넘김 고지 %d건 %v (1건이어야 함)", notices, err)
	}
	// 같은 되돌림이 다시 와도 고지는 한 번이다
	e.notify("apple", iap.Notice{ID: iapTestID(t, "reversed2"), Type: "REFUND_REVERSED", Target: &iap.Ref{Kind: iap.KindProduct, ID: txnA}}, "")
	e.sweep()
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_notices WHERE kind=$1 AND dedupe_key=$2",
		noticeProductOverCap, iapOverCapDedupe(iap.RouteApple, txnA)).Scan(&notices); err != nil || notices != 1 {
		t.Fatalf("되돌림을 두 번 받은 뒤 넘김 고지 %d건 %v", notices, err)
	}
}

// 회수는 유저 줄 잠금을 기다린다. 같은 유저의 제출이 상한을 세는 동안 회수가 끼어들면
// 제출은 회수 전 개수로 판정한다(READ COMMITTED). 잠금을 쥔 트랜잭션이 끝나야 회수가 반영되는지 본다.
func TestIAPRevokeWaitsForUserLock(t *testing.T) {
	e := newIAPEnv(t)
	token, user := e.user()
	id := iapTestID(t, "g")
	p := e.shelfPurchase(id, e.shelfToken(token, 2026))
	e.google.Purchases[p.TransactionID] = p
	if code, body := e.submit(token, "google", e.shelf, p.TransactionID, false); code != 200 {
		t.Fatalf("제출 %d %v", code, body)
	}
	key := iapTransactionKey(iap.KindProduct, p)
	stateOf := func() string {
		var st string
		if err := e.db.QueryRow(e.ctx, "SELECT state FROM iap_purchases WHERE route='google' AND transaction_id=$1", key).Scan(&st); err != nil {
			t.Fatal(err)
		}
		return st
	}

	// 다른 결제 트랜잭션이 이 유저의 줄을 잠그고 있다(제출이 상한을 세는 중)
	holder, err := iapBegin(e.ctx, e.db)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(e.ctx)
	if err := iapLockUser(e.ctx, holder, user); err != nil {
		t.Fatal(err)
	}

	done := make(chan error, 1)
	go func() {
		_, _, err := e.srv.iapApplyPurchaseState(e.ctx, iap.RouteGoogle, key, iap.StateRevoked, time.Now().UTC())
		done <- err
	}()
	select {
	case err := <-done:
		t.Fatalf("유저 줄이 잠긴 동안 회수가 끝남(err=%v). 잠금 없이 쓰고 있다", err)
	case <-time.After(500 * time.Millisecond):
	}
	if st := stateOf(); st != "paid" {
		t.Fatalf("잠금을 쥔 동안 원장이 바뀜: %s", st)
	}
	if err := holder.Commit(e.ctx); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("잠금이 풀린 뒤에도 회수가 끝나지 않음")
	}
	if st := stateOf(); st != "revoked" {
		t.Fatalf("잠금이 풀린 뒤 원장 %s", st)
	}
}

// 유저 줄 잠금은 FOR NO KEY UPDATE다. 결제끼리는 막고, 유저를 FK로 가리키는 다른 테이블의 쓰기(FOR KEY SHARE)는 막지 않는다
func TestIAPUserLockAllowsForeignKeyWrites(t *testing.T) {
	e := newIAPEnv(t)
	_, user := e.user()
	holder, err := iapBegin(e.ctx, e.db)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(e.ctx)
	if err := iapLockUser(e.ctx, holder, user); err != nil {
		t.Fatal(err)
	}

	other, err := e.db.Begin(e.ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Rollback(e.ctx)
	if _, err := other.Exec(e.ctx, "SET LOCAL lock_timeout = '1s'"); err != nil {
		t.Fatal(err)
	}
	// FK 확인이 잡는 잠금. 기다리지 않아야 한다
	if _, err := other.Exec(e.ctx, "SELECT 1 FROM users WHERE id=$1 FOR KEY SHARE", user); err != nil {
		t.Fatalf("결제 잠금이 FK 쓰기를 막음: %v", err)
	}
	// 다른 결제 트랜잭션은 기다린다(1초 뒤 55P03)
	_, err = other.Exec(e.ctx, "SELECT 1 FROM users WHERE id=$1 FOR NO KEY UPDATE", user)
	if pe, ok := err.(*pgconn.PgError); !ok || pe.Code != "55P03" {
		t.Fatalf("결제끼리 막히지 않음: %v", err)
	}
}

// 교착(40P01)도 잠금 대기 초과·문장 취소처럼 "잠시 뒤 다시"(503)다. 500으로 답하면 원인을 서버 버그로 오해한다
func TestIAPDeadlockIsBusy(t *testing.T) {
	for _, code := range []string{"55P03", "57014", "40P01"} {
		if !iapDBBusy(&pgconn.PgError{Code: code}) {
			t.Errorf("%s를 바쁨으로 보지 않음", code)
		}
	}
	if iapDBBusy(&pgconn.PgError{Code: "23505"}) {
		t.Error("유일 키 위반을 바쁨으로 봄")
	}
}

func TestIAPAlerts(t *testing.T) {
	if a := iapAlerts(iapBacklog{OldestUnconfirmedSecs: 47 * 3600}); len(a) != 0 {
		t.Fatalf("47시간은 아직 경보가 아님: %v", a)
	}
	a := iapAlerts(iapBacklog{OldestUnconfirmedSecs: 49 * 3600, RefundsGaveUp: 2, NoticesGaveUp: 1, StuckSecs: 3 * 3600})
	if len(a) != 4 {
		t.Fatalf("경보 4개여야 함: %v", a)
	}
}

// 앞선 확인이 구글에는 적용됐는데 원장 기록만 실패하면, 대조가 다시 확인을 요청하고 구글은 400(invalidPurchaseState)을 준다.
// 스토어에 다시 물어 이미 확인된 구매면 확인을 마친 것으로 적는다
func TestIAPConfirmRetryAlreadyConfirmed(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	p := e.shelfPurchase(tok, e.shelfToken(token, 2026))
	e.google.Purchases[tok] = p
	e.google.ConfirmErr = errors.New("503")
	e.submit(token, "google", e.shelf, tok, false)
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET created_at = now() - interval '2 minutes' WHERE transaction_id=$1", tok); err != nil {
		t.Fatal(err)
	}
	e.google.ConfirmErr = errors.New("400 invalidPurchaseState")
	defer func() { e.google.ConfirmErr = nil }()
	var confirmed *time.Time
	confirmedAt := func() *time.Time {
		t.Helper()
		if err := e.db.QueryRow(e.ctx, "SELECT confirmed_at FROM iap_purchases WHERE transaction_id=$1", tok).Scan(&confirmed); err != nil {
			t.Fatal(err)
		}
		return confirmed
	}
	// 선반은 소비하는 상품이다. 확인(acknowledge)만 되고 소비가 안 됐으면 끝난 것이 아니다(다시 살 수 없음). 재시도를 계속한다
	p.Acknowledged = true
	e.google.Purchases[tok] = p
	if e.sweep(); confirmedAt() != nil {
		t.Fatal("소비 안 된 구매를 확인 완료로 적음")
	}
	// 소비까지 됐으면 확인을 마친 것으로 적는다
	p.Consumed = true
	e.google.Purchases[tok] = p
	if e.sweep(); confirmedAt() == nil {
		t.Fatal("이미 소비된 구매가 미확인으로 남음")
	}
}

// 앱이 제출하기 전에 환불된 구글 거래의 알림은 원장에 거래가 없어 일부러 실패로 남는다. 사람이 할 일이 없으니 "알림 포기" 경보에서 뺀다
func TestIAPGaveUpNoticesSkipsPreSubmitRefunds(t *testing.T) {
	e := newIAPEnv(t)
	count := func() int {
		t.Helper()
		b, err := iapBacklogNow(e.ctx, e.db)
		if err != nil {
			t.Fatal(err)
		}
		return b.NoticesGaveUp
	}
	before := count()
	insert := func(id, kind, target string) {
		t.Helper()
		if _, err := e.db.Exec(e.ctx, `INSERT INTO iap_notifications(route,notification_id,kind,payload,target_kind,target_id,result,received_at)
			VALUES('google',$1,$2,'{}','product',$3,'failed',now()-interval '9 days')`, id, kind, target); err != nil {
			t.Fatal(err)
		}
	}
	insert(iapTestID(t, "pre"), "voided/1", iapTestID(t, "unknown-token"))
	if n := count(); n != before {
		t.Fatalf("제출 전 환불 알림을 포기로 셈: %d → %d", before, n)
	}
	insert(iapTestID(t, "other"), "4", iapTestID(t, "tok"))
	if n := count(); n != before+1 {
		t.Fatalf("다른 실패 알림을 세지 않음: %d → %d", before, n)
	}
}
