package server

import (
	"context"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 결제 표와 저장소 함수 시험. 실제 PostgreSQL이 있어야 돈다(TEST_DATABASE_URL).
func iapTestDB(t *testing.T) (context.Context, *pgxpool.Pool) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(db.Close)
	if err = Migrate(ctx, db); err != nil {
		t.Fatal(err)
	}
	return ctx, db
}

func iapTestUser(t *testing.T, ctx context.Context, db *pgxpool.Pool) int64 {
	t.Helper()
	var user int64
	if err := db.QueryRow(ctx, "INSERT INTO users DEFAULT VALUES RETURNING id").Scan(&user); err != nil {
		t.Fatal(err)
	}
	return user
}

// 시험마다 겹치지 않는 상품·거래 ID를 쓴다(같은 DB를 다른 시험과 함께 쓴다).
func iapTestID(t *testing.T, name string) string {
	return name + "-" + t.Name() + "-" + time.Now().Format("150405.000000000")
}

func TestIAPAccountToken(t *testing.T) {
	ctx, db := iapTestDB(t)
	user, other := iapTestUser(t, ctx, db), iapTestUser(t, ctx, db)

	// 동시에 여러 번 불러도 값은 하나만 생긴다
	tokens := make([]string, 8)
	var wg sync.WaitGroup
	for i := range tokens {
		wg.Add(1)
		go func() {
			defer wg.Done()
			tx, err := db.Begin(ctx)
			if err != nil {
				t.Error(err)
				return
			}
			defer tx.Rollback(ctx)
			if tokens[i], err = iapAccountToken(ctx, tx, user); err != nil {
				t.Error(err)
				return
			}
			if err = tx.Commit(ctx); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	for _, tok := range tokens {
		if tok == "" || tok != tokens[0] {
			t.Fatalf("계정 연결 값이 하나가 아님: %v", tokens)
		}
	}
	var n int
	if err := db.QueryRow(ctx, "SELECT count(*) FROM iap_account_tokens WHERE user_id=$1", user).Scan(&n); err != nil || n != 1 {
		t.Fatalf("줄 수 %d %v", n, err)
	}

	for _, c := range []struct {
		user  int64
		token string
		want  bool
	}{
		{user, tokens[0], true},
		{other, tokens[0], false}, // 남의 값
		{user, "00000000-0000-0000-0000-000000000000", false},
		{user, "", false},
		{user, "uuid가 아닌 값", false}, // 오류가 아니라 false
	} {
		got, err := iapOwnsToken(ctx, db, c.user, c.token)
		if err != nil || got != c.want {
			t.Errorf("iapOwnsToken(%d,%q)=%v,%v 기대 %v", c.user, c.token, got, err, c.want)
		}
	}
}

func TestIAPPurchaseLedgerAndShelves(t *testing.T) {
	ctx, db := iapTestDB(t)
	user := iapTestUser(t, ctx, db)
	shelf := iapTestID(t, "shelf")
	if _, err := db.Exec(ctx, "INSERT INTO iap_products(route,product_id,kind,shelves) VALUES('apple',$1,'product',2)", shelf); err != nil {
		t.Fatal(err)
	}
	p := iap.Purchase{Route: iap.RouteApple, TransactionID: iapTestID(t, "tx"), ProductID: shelf, State: iap.StatePaid, Env: iap.EnvSandbox,
		PurchasedAt: time.Now().UTC(), Currency: "KRW", PriceMilli: 1_100_000, Country: "KOR"}
	p.OriginalTransactionID = p.TransactionID

	// 같은 거래를 동시에 여러 번 넣어도 한 번만 들어간다
	inserted := make(chan bool, 10)
	var wg sync.WaitGroup
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, p)
			if err != nil {
				t.Error(err)
			}
			inserted <- ok
		}()
	}
	wg.Wait()
	close(inserted)
	count := 0
	for ok := range inserted {
		if ok {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("처음 들어갔다고 답한 횟수 %d (1이어야 함)", count)
	}
	if _, shelves, err := iapEntitlements(ctx, db, user, true); err != nil || shelves != 2 {
		t.Fatalf("선반 %d %v", shelves, err)
	}

	// 이 거래는 샌드박스다. 샌드박스를 받지 않는 서버에서는 세지 않는다
	if _, shelves, err := iapEntitlements(ctx, db, user, false); err != nil || shelves != 0 {
		t.Fatalf("샌드박스 거래가 세어짐: %d %v", shelves, err)
	}
	// 두 번째 거래는 더해진다
	p2 := p
	p2.TransactionID = iapTestID(t, "tx2")
	p2.OriginalTransactionID = p2.TransactionID
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, p2); err != nil || !ok {
		t.Fatal(ok, err)
	}
	if _, shelves, _ := iapEntitlements(ctx, db, user, true); shelves != 4 {
		t.Fatalf("선반 %d (4여야 함)", shelves)
	}

	// 환불하면 줄은 남고 칸 수에서만 빠진다. 두 번 환불해도 한 번만 바뀐다
	if ok, err := iapRevokePurchase(ctx, db, iap.RouteApple, p.TransactionID, time.Now()); err != nil || !ok {
		t.Fatal(ok, err)
	}
	if ok, _ := iapRevokePurchase(ctx, db, iap.RouteApple, p.TransactionID, time.Now()); ok {
		t.Fatal("이미 환불된 거래가 다시 바뀜")
	}
	if _, shelves, _ := iapEntitlements(ctx, db, user, true); shelves != 2 {
		t.Fatalf("환불 뒤 선반 %d (2여야 함)", shelves)
	}

	// 결제가 끝나지 않은 거래는 원장에 넣지 않는다
	pending := p
	pending.TransactionID, pending.State = iapTestID(t, "tx3"), iap.StatePending
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, pending); err == nil || ok {
		t.Fatal("대기 중인 거래가 들어감")
	}

	// 구글처럼 금액·주문 ID가 없는 거래: 빈 값은 NULL로, 유일 키는 구매 토큰으로
	g := iap.Purchase{Route: iap.RouteGoogle, OriginalTransactionID: iapTestID(t, "token"), ProductID: shelf, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC()}
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, g); err != nil || !ok {
		t.Fatal(ok, err)
	}
	var key string
	var currency *string
	var price *int64
	if err := db.QueryRow(ctx, "SELECT transaction_id,currency,price_milli FROM iap_purchases WHERE route='google' AND original_id=$1", g.OriginalTransactionID).Scan(&key, &currency, &price); err != nil {
		t.Fatal(err)
	}
	if key != g.OriginalTransactionID || currency != nil || price != nil {
		t.Fatalf("구글 거래: key=%s currency=%v price=%v", key, currency, price)
	}
	// 구글 한 번 사는 상품은 주문 ID가 있어도 구매 토큰이 유일 키다. 같은 토큰에 주문 ID만 달라도 한 번만 들어간다
	g.TransactionID = "GPA.다른-주문"
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, g); err != nil || ok {
		t.Fatal("같은 구매 토큰이 두 번 들어감", ok, err)
	}
	// 구글 구독 갱신은 토큰이 같고 주문 ID가 달라서 거래 줄이 따로 생긴다
	sub := iap.Purchase{Route: iap.RouteGoogle, OriginalTransactionID: iapTestID(t, "subtoken"), ProductID: shelf, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC()}
	for i, order := range []string{iapTestID(t, "GPA.0"), iapTestID(t, "GPA.1")} {
		sub.TransactionID = order
		if ok, err := iapRecordPurchase(ctx, db, user, iap.KindSubscription, sub); err != nil || !ok {
			t.Fatalf("구독 갱신 %d: %v %v", i, ok, err)
		}
	}
}

func TestIAPSubscriptionAndPlus(t *testing.T) {
	ctx, db := iapTestDB(t)
	user, other := iapTestUser(t, ctx, db), iapTestUser(t, ctx, db)
	product := iapTestID(t, "plus")
	if _, err := db.Exec(ctx, "INSERT INTO iap_products(route,product_id,kind,entitlement) VALUES('apple',$1,'subscription','plus')", product); err != nil {
		t.Fatal(err)
	}
	sub := iapSubscription{Route: iap.RouteApple, OriginalID: iapTestID(t, "orig"), ProductID: product, Env: iap.EnvSandbox,
		State: iap.StatePaid, ExpiresAt: time.Now().Add(time.Hour), AutoRenew: true}
	upsert := func(u int64, s iapSubscription) int64 {
		t.Helper()
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		prev, err := iapUpsertSubscription(ctx, tx, u, s)
		if err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		return prev
	}
	plus := func(u int64) bool {
		t.Helper()
		ok, _, err := iapEntitlements(ctx, db, u, true)
		if err != nil {
			t.Fatal(err)
		}
		return ok
	}

	if prev := upsert(user, sub); prev != 0 || !plus(user) || plus(other) {
		t.Fatalf("새 구독: prev=%d plus=%v", prev, plus(user))
	}
	// 만료되면 권한이 없다
	expired := sub
	expired.ExpiresAt = time.Now().Add(-time.Minute)
	if upsert(user, expired); plus(user) {
		t.Fatal("만료된 구독에 권한이 있음")
	}
	// 만료됐어도 유예 기간 안이면 유지한다(D11)
	grace := expired
	grace.GraceUntil = time.Now().Add(time.Hour)
	if upsert(user, grace); !plus(user) {
		t.Fatal("유예 기간인데 권한이 없음")
	}
	// 유예가 끝나면 다시 없다. 유예 값이 비면 NULL로 돌아간다
	if upsert(user, expired); plus(user) {
		t.Fatal("유예가 끝났는데 권한이 있음")
	}
	// 해지 예약(자동 갱신 꺼짐)은 만료일까지 유효하다(D12)
	cancelled := sub
	cancelled.AutoRenew = false
	if upsert(user, cancelled); !plus(user) {
		t.Fatal("해지 예약인데 만료 전에 권한이 없음")
	}
	// 환불·보류 상태면 기간이 남아도 없다
	for _, st := range []iap.State{iap.StateRevoked, iap.StateInactive} {
		s := sub
		s.State = st
		if upsert(user, s); plus(user) {
			t.Fatalf("%s 상태에 권한이 있음", st)
		}
	}
	// 구매 복원: 다른 계정이 같은 구독을 가져가면 한 계정만 가진다(D8)
	if prev := upsert(other, sub); prev != user || plus(user) || !plus(other) {
		t.Fatalf("이전: prev=%d", prev)
	}
	var n int
	if err := db.QueryRow(ctx, "SELECT count(*) FROM iap_subscriptions WHERE route='apple' AND original_id=$1", sub.OriginalID).Scan(&n); err != nil || n != 1 {
		t.Fatalf("구독 줄 수 %d %v", n, err)
	}
}

func TestIAPNotificationOnce(t *testing.T) {
	ctx, db := iapTestDB(t)
	id := iapTestID(t, "note")
	apple := iap.Notice{Route: iap.RouteApple, ID: id, Type: "DID_RENEW", Target: &iap.Ref{Kind: iap.KindSubscription, ID: "300"}, OriginalID: "100"}
	first, err := iapRecordNotification(ctx, db, apple, `{"a":1}`)
	if err != nil || !first {
		t.Fatal(first, err)
	}
	if again, err := iapRecordNotification(ctx, db, apple, `{"a":1}`); err != nil || again {
		t.Fatal("같은 알림이 두 번 들어감", err)
	}
	// 다른 스토어의 같은 ID는 다른 알림이다. 다시 물어볼 대상이 없는 알림도 들어간다
	if ok, err := iapRecordNotification(ctx, db, iap.Notice{Route: iap.RouteGoogle, ID: id, Type: "test"}, `{}`); err != nil || !ok {
		t.Fatal(ok, err)
	}
	var kind, target, original string
	if err := db.QueryRow(ctx, "SELECT target_kind,target_id,original_id FROM iap_notifications WHERE route='apple' AND notification_id=$1", id).Scan(&kind, &target, &original); err != nil || kind != "subscription" || target != "300" || original != "100" {
		t.Fatal(kind, target, original, err)
	}
	if err := iapFinishNotification(ctx, db, iap.RouteApple, id, "processed", ""); err != nil {
		t.Fatal(err)
	}
	var result string
	var errText *string
	var attempts int
	if err := db.QueryRow(ctx, "SELECT result,error,attempts FROM iap_notifications WHERE route='apple' AND notification_id=$1", id).Scan(&result, &errText, &attempts); err != nil || result != "processed" || errText != nil || attempts != 1 {
		t.Fatal(result, errText, attempts, err)
	}
}

// 계정을 지워도 거래와 구독 줄은 남고 유저 연결만 끊긴다(거래 기록 보존). 계정 연결 값은 지워진다.
func TestIAPSurvivesAccountDeletion(t *testing.T) {
	ctx, db := iapTestDB(t)
	user := iapTestUser(t, ctx, db)
	product := iapTestID(t, "plus")
	if _, err := db.Exec(ctx, "INSERT INTO iap_products(route,product_id,kind,entitlement) VALUES('apple',$1,'subscription','plus')", product); err != nil {
		t.Fatal(err)
	}
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	token, err := iapAccountToken(ctx, tx, user)
	if err != nil {
		t.Fatal(err)
	}
	orig := iapTestID(t, "orig")
	if _, err = iapUpsertSubscription(ctx, tx, user, iapSubscription{Route: iap.RouteApple, OriginalID: orig, ProductID: product, Env: iap.EnvProduction, State: iap.StatePaid, ExpiresAt: time.Now().Add(time.Hour), AutoRenew: true}); err != nil {
		t.Fatal(err)
	}
	p := iap.Purchase{Route: iap.RouteApple, TransactionID: iapTestID(t, "tx"), OriginalTransactionID: orig, ProductID: product, AccountToken: token, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC()}
	if _, err = iapRecordPurchase(ctx, tx, user, iap.KindSubscription, p); err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}

	if _, err = db.Exec(ctx, "DELETE FROM users WHERE id=$1", user); err != nil {
		t.Fatalf("결제 기록이 있는 계정을 지울 수 없음: %v", err)
	}
	var purchases, subs, tokens int
	var owner *int64
	if err = db.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM iap_purchases WHERE transaction_id=$1),
		(SELECT count(*) FROM iap_subscriptions WHERE original_id=$2),
		(SELECT count(*) FROM iap_account_tokens WHERE token::text=$3),
		(SELECT user_id FROM iap_purchases WHERE transaction_id=$1)`, p.TransactionID, orig, token).Scan(&purchases, &subs, &tokens, &owner); err != nil {
		t.Fatal(err)
	}
	if purchases != 1 || subs != 1 || tokens != 0 || owner != nil {
		t.Fatalf("거래 %d, 구독 %d, 연결 값 %d, 유저 %v", purchases, subs, tokens, owner)
	}
}
