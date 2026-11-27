package iapkit

import (
	"context"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// 스토어가 한도(429)에 걸려 쉬는 동안 대조는 그 경로를 부르지 않는다. 쉬는 시간이 끝나면 이어서 한다
func TestIAPSweepSkipsRestingStore(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	tok := iapTestID(t, "tok")
	e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2026))
	e.google.ConfirmErr = errors.New("503")
	e.submit(token, "google", e.shelf, tok, false)
	e.google.ConfirmErr = nil
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET created_at=now()-interval '5 minutes' WHERE transaction_id=$1", tok); err != nil {
		t.Fatal(err)
	}
	confirmed := func() bool {
		var at *time.Time
		if err := e.db.QueryRow(e.ctx, "SELECT confirmed_at FROM iap_purchases WHERE transaction_id=$1", tok).Scan(&at); err != nil {
			t.Fatal(err)
		}
		return at != nil
	}

	e.google.RestUntil = time.Now().Add(time.Hour)
	calls := e.google.Calls
	res := e.sweep()
	if confirmed() || e.google.Calls != calls {
		t.Fatalf("쉬는 중인데 스토어를 부름: 확인 %v, 호출 %d→%d", confirmed(), calls, e.google.Calls)
	}
	if res.Resting == 0 {
		t.Fatal("건너뛴 건이 결과에 없음")
	}

	e.google.RestUntil = time.Time{}
	if e.sweep(); !confirmed() {
		t.Fatal("쉬는 시간이 끝났는데 확인을 다시 하지 않음")
	}
}

// 느린 스토어 하나가 앞 단계를 붙잡아도, 단계 마감 시각 덕에 뒤 단계(구독 재확인)는 돈다
func TestIAPSweepSlowStoreDoesNotStarveLaterStages(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	account := e.accountToken(token)

	// 구글: 확인을 못 마친 거래 3건. 확인 한 번에 2초 걸린다
	e.google.ConfirmErr = errors.New("503")
	var toks []string // 시험 DB를 다른 시험과 같이 쓰므로 이 시험의 거래만 본다
	for i := 0; i < 3; i++ {
		tok := iapTestID(t, "slow")
		toks = append(toks, tok)
		e.google.Purchases[tok] = e.shelfPurchase(tok, e.shelfToken(token, 2020+i))
		e.submit(token, "google", e.shelf, tok, false)
	}
	e.google.ConfirmErr = nil
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_purchases SET created_at=now()-interval '5 minutes' WHERE transaction_id = ANY($1)", toks); err != nil {
		t.Fatal(err)
	}
	// 애플: 만료가 지난 구독. 스토어는 갱신됐다고 답한다
	orig, txn := iapTestID(t, "orig"), iapTestID(t, "txn")
	e.apple.Purchases[txn] = e.subscription(orig, txn, account, time.Now().Add(time.Hour))
	e.submit(token, "apple", e.plus, txn, false)
	if _, err := e.db.Exec(e.ctx, "UPDATE iap_subscriptions SET expires_at=now()-interval '1 minute', updated_at=now()-interval '1 hour' WHERE original_id=$1", orig); err != nil {
		t.Fatal(err)
	}

	saved := iapSweepStages
	t.Cleanup(func() { iapSweepStages = saved })
	iapSweepStages.confirm = 300 * time.Millisecond
	iapSweepStages.catchUp = 400 * time.Millisecond
	iapSweepStages.notices = 500 * time.Millisecond
	iapSweepStages.refunds = 600 * time.Millisecond
	iapSweepStages.subscriptions = 5 * time.Second
	e.google.Delay = 2 * time.Second // 마감이 없으면 확인 3건에 6초가 걸려 아래 4초 검사에 걸린다

	begin := time.Now()
	res := e.sweep()
	if took := time.Since(begin); took > 4*time.Second {
		t.Fatalf("대조 한 바퀴가 %v 걸림(앞 단계가 마감을 넘김)", took)
	}
	if res.Confirmed != 0 || res.Cut == 0 {
		t.Fatalf("확인 단계가 마감에 끊기지 않음: confirmed=%d cut=%d", res.Confirmed, res.Cut)
	}
	if res.Refreshed == 0 || !plusIn(e.me(token)) {
		t.Fatalf("느린 구글 때문에 애플 구독 재확인이 못 돎: refreshed=%d", res.Refreshed)
	}

	// 스토어가 빨라지면 남은 확인을 다음 바퀴에 마친다
	e.google.Delay = 0
	var left int
	e.sweep()
	if err := e.db.QueryRow(e.ctx, "SELECT count(*) FROM iap_purchases WHERE transaction_id = ANY($1) AND confirmed_at IS NULL", toks).Scan(&left); err != nil || left != 0 {
		t.Fatalf("다음 바퀴 뒤에도 확인 못 한 거래 %d건 %v", left, err)
	}
}

// 결제 트랜잭션에만 제한 시간이 걸리고, 연결이 풀로 돌아가면 남지 않는다
func TestIAPBeginTimeouts(t *testing.T) {
	e := newIAPEnv(t)
	conn, err := e.db.Acquire(e.ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Release()
	var before string
	if err := conn.QueryRow(e.ctx, "SHOW lock_timeout").Scan(&before); err != nil {
		t.Fatal(err)
	}
	tx, err := iapBegin(e.ctx, conn)
	if err != nil {
		t.Fatal(err)
	}
	var lock, stmt string
	if err := tx.QueryRow(e.ctx, "SELECT current_setting('lock_timeout'), current_setting('statement_timeout')").Scan(&lock, &stmt); err != nil {
		t.Fatal(err)
	}
	if lock != iapLockTimeout || stmt != iapStatementTimeout {
		t.Fatalf("트랜잭션 안 제한 시간 %s/%s", lock, stmt)
	}
	if err := tx.Commit(e.ctx); err != nil {
		t.Fatal(err)
	}
	var after string
	if err := conn.QueryRow(e.ctx, "SHOW lock_timeout").Scan(&after); err != nil || after != before {
		t.Fatalf("커밋 뒤에도 제한 시간이 남음: %s → %s %v", before, after, err)
	}

	// 잠금을 오래 기다리면 끊기고(55P03), 요청에는 503으로 답한다
	holder, err := e.db.Begin(e.ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer holder.Rollback(e.ctx)
	if _, err := holder.Exec(e.ctx, "SELECT pg_advisory_xact_lock(hashtextextended('iapkit.test.busy', 0))"); err != nil {
		t.Fatal(err)
	}
	waiter, err := iapBegin(e.ctx, e.db)
	if err != nil {
		t.Fatal(err)
	}
	defer waiter.Rollback(e.ctx)
	if _, err := waiter.Exec(e.ctx, "SELECT set_config('lock_timeout', '100ms', true)"); err != nil {
		t.Fatal(err)
	}
	_, err = waiter.Exec(e.ctx, "SELECT pg_advisory_xact_lock(hashtextextended('iapkit.test.busy', 0))")
	if !iapDBBusy(err) {
		t.Fatalf("잠금 대기 초과가 아님: %v", err)
	}
	w := httptest.NewRecorder()
	fail(w, err)
	if w.Code != 503 || !strings.Contains(w.Body.String(), "iap_busy") {
		t.Fatalf("응답 %d %s", w.Code, w.Body.String())
	}
	// 문장 시간 초과(57014)도 같다
	if !iapDBBusy(&pgconn.PgError{Code: "57014"}) || iapDBBusy(&pgconn.PgError{Code: "23505"}) {
		t.Fatal("코드 판정이 틀림")
	}
}

// 대조 단계 마감이 환불 요청 도중에 지나도, 시작한 환불은 끝까지 하고 "요청함"을 적는다.
// 끊기면 스토어는 환불했는데 원장에는 안 한 것으로 남아 다음 바퀴가 같은 주문을 또 환불하려 한다
func TestIAPRefundSurvivesStageDeadline(t *testing.T) {
	e := newIAPEnv(t)
	token, _ := e.user()
	y := e.shelfToken(token, 2027)
	e.shelfToken(token, 2027)
	a, b := iapTestID(t, "g1"), iapTestID(t, "g2")
	e.google.Purchases[a] = e.shelfPurchase(a, y)
	e.google.Purchases[b] = e.shelfPurchase(b, y)
	e.submit(token, "google", e.shelf, a, false)
	e.google.RefundErr = errors.New("구글 장애")
	if code, body := e.submit(token, "google", e.shelf, b, false); code != 200 || body["overCap"] != true || body["autoRefund"] != false {
		t.Fatalf("상한 넘긴 구매가 환불 대기로 남지 않음: %d %v", code, body)
	}
	e.google.RefundErr = nil

	// 단계 마감 300ms, 환불 요청은 500ms 걸린다
	e.google.Delay = 500 * time.Millisecond
	ctx, cancel := context.WithTimeout(e.ctx, 300*time.Millisecond)
	defer cancel()
	if !e.srv.iapRefundOverCap(ctx, e.google, b, "GPA."+b) {
		t.Fatal("마감에 환불 요청이 끊김")
	}
	var requested bool
	if err := e.db.QueryRow(e.ctx, "SELECT refund_requested_at IS NOT NULL FROM iap_purchases WHERE route='google' AND transaction_id=$1", b).Scan(&requested); err != nil || !requested {
		t.Fatalf("환불했는데 기록이 없음: %v %v", requested, err)
	}
}
