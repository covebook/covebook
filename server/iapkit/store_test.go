package iapkit

import (
	"context"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit/iap"
)

// 결제 테이블과 저장소 함수 시험. 실제 PostgreSQL이 있어야 돈다(TEST_DATABASE_URL).
func iapTestDB(t *testing.T) (context.Context, *pgxpool.Pool) {
	t.Helper()
	if iapTestDSN == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, iapTestDSN)
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

// 결제 의도: 대상은 계정 연결 값이 아니라 서버에 남긴 의도로 찾는다(D1, 2026-11-27).
// 앱이 붙인 번호가 먼저, 없거나 맞지 않으면 결제보다 먼저 남긴 의도 중 같은 수량, 그다음 다른 수량의 가장 새것
func TestIAPIntentTarget(t *testing.T) {
	ctx, db := iapTestDB(t)
	user, other := iapTestUser(t, ctx, db), iapTestUser(t, ctx, db)
	intent := func(u int64, target string, units int, ago time.Duration) iapReservation {
		t.Helper()
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		// 상한 0: 잡지 않고 의도만 남긴다
		r, wait, err := iapReserve(ctx, tx, u, target, units, 0, 0, 0, time.Hour)
		if err != nil || wait != 0 || r.ID == "" {
			t.Fatalf("의도를 남기지 못함: %+v %v %v", r, wait, err)
		}
		if _, err = tx.Exec(ctx, "UPDATE iap_reservations SET created_at = now() - make_interval(secs => $2) WHERE id=$1::uuid", r.ID, ago.Seconds()); err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		return r
	}
	a := intent(user, "2026", 1, 10*time.Minute)
	b := intent(user, "2027", 1, 5*time.Minute)
	c := intent(user, "2025", 3, 6*time.Minute)
	now := time.Now()
	for _, tc := range []struct {
		name        string
		user        int64
		reservation string
		units       int
		at          time.Time
		want        string // 빈 값이면 모름
		id          string
	}{
		{"번호가 먼저", user, a.ID, 1, now, "2026", a.ID},
		{"번호는 대문자여도", user, strings.ToUpper(a.ID), 1, now, "2026", a.ID},
		{"번호가 없으면 같은 수량의 가장 새것", user, "", 1, now, "2027", b.ID},
		{"결제보다 뒤에 남긴 의도는 쓰지 않는다", user, "", 1, now.Add(-7 * time.Minute), "2026", a.ID},
		{"수량이 다르면 다른 의도", user, "", 3, now, "2025", c.ID},
		{"같은 수량이 없으면 수량이 다른 가장 새것", user, "", 2, now, "2027", b.ID},
		{"결제보다 뒤의 번호는 쓰지 않고 수량으로 찾는다", user, b.ID, 1, now.Add(-7 * time.Minute), "2026", a.ID},
		{"앞선 의도가 하나도 없으면 모름", user, a.ID, 1, now.Add(-20 * time.Minute), "", ""},
		{"남의 번호는 쓰지 않는다", other, a.ID, 1, now, "", ""},
		{"모양이 틀린 번호", user, "x", 3, now, "2025", c.ID},
		{"결제 시각을 모르면 가장 새것", user, "", 1, time.Time{}, "2027", b.ID},
	} {
		id, got, known, err := iapIntentTarget(ctx, db, tc.user, tc.reservation, tc.units, tc.at)
		if err != nil || got != tc.want || known != (tc.want != "") || id != tc.id {
			t.Errorf("%s: %q %q %v %v (기대 %q %q)", tc.name, id, got, known, err, tc.id, tc.want)
		}
	}

	// 보관 시간이 지난 의도는 수량으로 찾지 않고, 다음에 의도를 남길 때 지운다
	if _, err := db.Exec(ctx, "UPDATE iap_reservations SET keep_until = now() - interval '1 second' WHERE id=$1::uuid", b.ID); err != nil {
		t.Fatal(err)
	}
	if id, _, _, err := iapIntentTarget(ctx, db, user, "", 1, now); err != nil || id != a.ID {
		t.Fatalf("보관 시간이 지난 b 대신 a: %q %v", id, err)
	}
	intent(user, "2028", 2, 0)
	var n int
	if err := db.QueryRow(ctx, "SELECT count(*) FROM iap_reservations WHERE id=$1::uuid", b.ID).Scan(&n); err != nil || n != 0 {
		t.Fatalf("보관 시간이 지난 의도가 남음: %d %v", n, err)
	}
	// 상한이 없는 의도는 아무것도 잡지 않는다: 같은 대상에 상한 3으로 3칸을 잡을 수 있다
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if r, wait, err := iapReserve(ctx, tx, user, "2026", 3, 0, 3, time.Minute, time.Hour); err != nil || r.ID == "" || wait != 0 {
		t.Fatalf("의도만 남긴 줄이 상한을 잡음: %+v %v %v", r, wait, err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}

	// 계정 연결 값은 계정마다 하나다. 한 번 사는 상품도 같은 값을 쓴다(D7)
	token := func(u int64) string {
		t.Helper()
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		v, err := iapAccountToken(ctx, tx, u)
		if err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		return v
	}
	if first, again, theirs := token(user), token(user), token(other); first == "" || first != again || first == theirs {
		t.Fatalf("계정 연결 값 %q %q %q", first, again, theirs)
	}
}

func TestIAPPurchaseLedgerAndShelves(t *testing.T) {
	ctx, db := iapTestDB(t)
	user := iapTestUser(t, ctx, db)
	shelf := iapTestID(t, "shelf")
	if _, err := db.Exec(ctx, "INSERT INTO iap_products(route,product_id,kind,units) VALUES('apple',$1,'product',2)", shelf); err != nil {
		t.Fatal(err)
	}
	// 대상은 넣을 때 모름(NULL)이고 iapSetTarget이 채운다(구매 제출·알림이 결제 의도로 찾은 값)
	setTarget := func(key, target string) {
		t.Helper()
		if got, known, _, err := iapSetTarget(ctx, db, iap.RouteApple, key, target); err != nil || !known || got != target {
			t.Fatalf("대상 %q: %q %v %v", target, got, known, err)
		}
	}
	p := iap.Purchase{Route: iap.RouteApple, TransactionID: iapTestID(t, "tx"), ProductID: shelf, State: iap.StatePaid, Env: iap.EnvSandbox,
		PurchasedAt: time.Now().UTC(), Currency: "KRW", PriceMilli: 1_100_000, Country: "KR"}
	p.OriginalTransactionID = p.TransactionID

	// 같은 거래를 동시에 여러 번 넣어도 한 번만 들어간다
	inserted := make(chan bool, 10)
	var wg sync.WaitGroup
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, p, true)
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
	setTarget(p.TransactionID, "2026")
	// 한 번 정한 대상은 바꾸지 않는다
	if got, _, filled, err := iapSetTarget(ctx, db, iap.RouteApple, p.TransactionID, "2027"); err != nil || got != "2026" || filled {
		t.Fatalf("정한 대상이 바뀜: %q %v %v", got, filled, err)
	}
	shelvesAre := func(want map[int]int) {
		t.Helper()
		_, got, err := iapEntitlements(ctx, db, user, true, 3)
		if err != nil || len(got) != len(want) {
			t.Fatalf("선반 %v %v (기대 %v)", got, err, want)
		}
		for y, n := range want {
			if got[strconv.Itoa(y)] != n {
				t.Fatalf("선반 %v (기대 %v)", got, want)
			}
		}
	}
	shelvesAre(map[int]int{2026: 2})
	var year *string
	if err := db.QueryRow(ctx, "SELECT target FROM iap_purchases WHERE route='apple' AND transaction_id=$1", p.TransactionID).Scan(&year); err != nil || year == nil || *year != "2026" {
		t.Fatalf("거래에 적힌 연도 %v %v", year, err)
	}
	// 이 거래는 샌드박스다. 샌드박스를 받지 않는 서버에서는 세지 않는다
	if _, shelves, err := iapEntitlements(ctx, db, user, false, 3); err != nil || len(shelves) != 0 {
		t.Fatalf("샌드박스 거래가 세어짐: %v %v", shelves, err)
	}

	// 두 번째 거래는 더해지지만 한 책장에서 3칸을 넘지 않는다(넘은 거래도 원장에는 남는다)
	p2 := p
	p2.TransactionID = iapTestID(t, "tx2")
	p2.OriginalTransactionID = p2.TransactionID
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, p2, true); err != nil || !ok {
		t.Fatal(ok, err)
	}
	setTarget(p2.TransactionID, "2026")
	shelvesAre(map[int]int{2026: covebookIAPRules.Cap})

	// 다른 연도 책장의 칸은 따로 센다
	p3 := p
	p3.TransactionID = iapTestID(t, "tx-2027")
	p3.OriginalTransactionID = p3.TransactionID
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, p3, true); err != nil || !ok {
		t.Fatal(ok, err)
	}
	setTarget(p3.TransactionID, "2027")
	shelvesAre(map[int]int{2026: 3, 2027: 2})

	// 환불하면 줄은 남고 그 연도 책장의 칸 수에서만 빠진다. 두 번 환불해도 한 번만 바뀐다
	if ok, err := iapRevokePurchase(ctx, db, iap.RouteApple, p.TransactionID, time.Now()); err != nil || !ok {
		t.Fatal(ok, err)
	}
	if ok, _ := iapRevokePurchase(ctx, db, iap.RouteApple, p.TransactionID, time.Now()); ok {
		t.Fatal("이미 환불된 거래가 다시 바뀜")
	}
	shelvesAre(map[int]int{2026: 2, 2027: 2})

	// 대상을 정하지 않은 거래는 계정 연결 값이 있든 없든 기록만 하고 어느 책장에도 칸을 주지 않는다
	tx, err := db.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	plain, err := iapAccountToken(ctx, tx, user)
	if err != nil {
		t.Fatal(err)
	}
	if err = tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	for _, tok := range []string{plain, ""} {
		q := p
		q.TransactionID, q.AccountToken = iapTestID(t, "tx-noyear"), tok
		q.OriginalTransactionID = q.TransactionID
		if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, q, true); err != nil || !ok {
			t.Fatal(ok, err)
		}
	}
	shelvesAre(map[int]int{2026: 2, 2027: 2})

	// 결제가 끝나지 않은 거래는 원장에 넣지 않는다
	pending := p
	pending.TransactionID, pending.State = iapTestID(t, "tx3"), iap.StatePending
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, pending, true); err == nil || ok {
		t.Fatal("대기 중인 거래가 들어감")
	}

	// 구글처럼 금액·주문 ID가 없는 거래: 빈 값은 NULL로, 유일 키는 구매 토큰으로
	g := iap.Purchase{Route: iap.RouteGoogle, OriginalTransactionID: iapTestID(t, "token"), ProductID: shelf, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC()}
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, g, true); err != nil || !ok {
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
	if ok, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, g, true); err != nil || ok {
		t.Fatal("같은 구매 토큰이 두 번 들어감", ok, err)
	}
	// 구글 구독 갱신은 토큰이 같고 주문 ID가 달라서 거래 줄이 따로 생긴다
	sub := iap.Purchase{Route: iap.RouteGoogle, OriginalTransactionID: iapTestID(t, "subtoken"), ProductID: shelf, State: iap.StatePaid, Env: iap.EnvProduction, PurchasedAt: time.Now().UTC()}
	for i, order := range []string{iapTestID(t, "GPA.0"), iapTestID(t, "GPA.1")} {
		sub.TransactionID = order
		if ok, err := iapRecordPurchase(ctx, db, user, iap.KindSubscription, sub, true); err != nil || !ok {
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
		ents, _, err := iapEntitlements(ctx, db, u, true, 3)
		if err != nil {
			t.Fatal(err)
		}
		return slices.Contains(ents, "plus")
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

// 계정을 지워도 거래, 구독, 고지 줄은 남고 유저 연결만 끊긴다(거래 기록 보존, 알렸다는 증빙). 계정 연결 값은 지워진다.
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
	if _, err = iapRecordPurchase(ctx, tx, user, iap.KindSubscription, p, true); err != nil {
		t.Fatal(err)
	}
	notice := "purchase_done:apple:" + p.TransactionID
	if err = iapWriteNotice(ctx, tx, user, noticePurchaseDone, iap.EnvProduction, notice, map[string]any{"route": "apple"}); err != nil {
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
	var notices int
	var noticeOwner *int64
	if err = db.QueryRow(ctx, "SELECT count(*)::int, max(user_id) FROM iap_notices WHERE dedupe_key=$1", notice).Scan(&notices, &noticeOwner); err != nil {
		t.Fatal(err)
	}
	if notices != 1 || noticeOwner != nil {
		t.Fatalf("고지 %d줄, 유저 %v: 탈퇴해도 고지는 남고 주인만 비어야 한다", notices, noticeOwner)
	}
}

// 선반 결제 중 예약: 산 칸 + 예약 칸 + 이번 칸이 3칸을 넘으면 잡지 않고 기다릴 시간을 준다(D1)
func TestIAPShelfReservation(t *testing.T) {
	ctx, db := iapTestDB(t)
	user, other := iapTestUser(t, ctx, db), iapTestUser(t, ctx, db)
	reserve := func(u int64, year, units, paid int) (iapReservation, time.Duration) {
		t.Helper()
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		r, wait, err := iapReserve(ctx, tx, u, strconv.Itoa(year), units, paid, covebookIAPRules.Cap, covebookIAPRules.Hold, covebookIAPRules.keep())
		if err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
		return r, wait
	}

	// 1칸씩 두 기기: 1+1 ≤ 3이라 둘 다 잡힌다
	a, _ := reserve(user, 2026, 1, 0)
	b, _ := reserve(user, 2026, 1, 0)
	if a.ID == "" || b.ID == "" || a.ID == b.ID {
		t.Fatalf("1칸 두 개가 따로 잡혀야 함: %q %q", a.ID, b.ID)
	}
	if left := time.Until(a.ExpiresAt); left < 4*time.Minute || left > 6*time.Minute {
		t.Fatalf("예약은 5분: 남은 시간 %v", left)
	}
	// 3칸 묶음은 예약 2칸이 있어 막힌다. 기다릴 시간은 가장 먼저 끝나는 예약까지
	if r, wait := reserve(user, 2026, 3, 0); r.ID != "" || wait < 4*time.Minute || wait > 6*time.Minute {
		t.Fatalf("예약 때문에 막혀야 함: %+v wait=%v", r, wait)
	}
	// 다른 해 책장, 다른 유저는 상관없다
	if r, _ := reserve(user, 2027, 3, 0); r.ID == "" {
		t.Fatal("다른 해 책장은 따로")
	}
	if r, _ := reserve(other, 2026, 3, 0); r.ID == "" {
		t.Fatal("다른 유저는 따로")
	}
	// 산 칸도 센다: 1칸 샀고 예약 2칸이면 1칸도 안 된다
	if r, _ := reserve(user, 2026, 1, 1); r.ID != "" {
		t.Fatal("산 1칸 + 예약 2칸 + 1칸 = 4칸")
	}

	// 남의 예약, 없는 예약, 모양이 틀린 값은 아무 일도 없다
	for _, id := range []string{a.ID, "00000000-0000-0000-0000-000000000000", "x"} {
		if err := iapReleaseReservation(ctx, db, other, id); err != nil {
			t.Fatal(err)
		}
	}
	var n int
	if err := db.QueryRow(ctx, "SELECT count(*) FROM iap_reservations WHERE user_id=$1 AND target='2026'", user).Scan(&n); err != nil || n != 2 {
		t.Fatalf("남이 푼 예약이 지워짐: %d %v", n, err)
	}
	// 내 예약을 풀면 그만큼 다시 잡힌다
	if err := iapReleaseReservation(ctx, db, user, strings.ToUpper(a.ID)); err != nil {
		t.Fatal(err)
	}
	if r, _ := reserve(user, 2026, 2, 0); r.ID == "" {
		t.Fatal("예약 1칸을 풀었으니 1+2 ≤ 3")
	}
	// 결제 의도는 예약보다 오래 남는다(기본 4일)
	var secs float64
	if err := db.QueryRow(ctx, "SELECT extract(epoch FROM keep_until - expires_at)::float8 FROM iap_reservations WHERE id=$1::uuid", b.ID).Scan(&secs); err != nil ||
		time.Duration(secs*float64(time.Second)) < 95*time.Hour || time.Duration(secs*float64(time.Second)) > 96*time.Hour {
		keep := time.Duration(secs * float64(time.Second))
		t.Fatalf("의도 보관 시간 - 예약 시간 %v %v", keep, err)
	}

	// 끝난 예약은 세지 않는다(의도는 남아 있어도)
	if _, err := db.Exec(ctx, "UPDATE iap_reservations SET expires_at = now() - interval '1 second' WHERE user_id=$1", user); err != nil {
		t.Fatal(err)
	}
	if r, _ := reserve(user, 2026, 3, 0); r.ID == "" {
		t.Fatal("끝난 예약은 세지 않아야 함")
	}
}

// 3칸을 넘게 산 거래(over_cap)는 칸 수에 세지 않는다
func TestIAPOverCapNotCounted(t *testing.T) {
	ctx, db := iapTestDB(t)
	user := iapTestUser(t, ctx, db)
	one := iapTestID(t, "shelf1")
	if _, err := db.Exec(ctx, "INSERT INTO iap_products(route,product_id,kind,units) VALUES('apple',$1,'product',1)", one); err != nil {
		t.Fatal(err)
	}
	for i := range 2 {
		p := iap.Purchase{Route: iap.RouteApple, TransactionID: iapTestID(t, "tx") + string(rune('a'+i)), ProductID: one,
			State: iap.StatePaid, Env: iap.EnvSandbox, PurchasedAt: time.Now().UTC()}
		p.OriginalTransactionID = p.TransactionID
		if _, err := iapRecordPurchase(ctx, db, user, iap.KindProduct, p, true); err != nil {
			t.Fatal(err)
		}
		if _, _, _, err := iapSetTarget(ctx, db, iap.RouteApple, p.TransactionID, "2026"); err != nil {
			t.Fatal(err)
		}
		if i == 1 {
			if _, err := db.Exec(ctx, "UPDATE iap_purchases SET over_cap=true WHERE route='apple' AND transaction_id=$1", p.TransactionID); err != nil {
				t.Fatal(err)
			}
		}
	}
	if _, shelves, err := iapEntitlements(ctx, db, user, true, 3); err != nil || shelves["2026"] != 1 {
		t.Fatalf("넘게 산 거래는 세지 않음: %v %v", shelves, err)
	}
}

// 스토어에서 읽은 뒤 다른 곳(알림 처리)이 고친 구독 줄은 그 옛 상태로 덮어쓰지 않는다. 주인은 바꾼다(코드 리뷰 #43)
func TestIAPUpsertKeepsNewerState(t *testing.T) {
	ctx, db := iapTestDB(t)
	user, other := iapTestUser(t, ctx, db), iapTestUser(t, ctx, db)
	orig := iapTestID(t, "stale")
	write := func(u int64, s iapSubscription) {
		t.Helper()
		tx, err := db.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		if _, err = iapUpsertSubscription(ctx, tx, u, s); err != nil {
			t.Fatal(err)
		}
		if err = tx.Commit(ctx); err != nil {
			t.Fatal(err)
		}
	}
	state := func() (st string, owner int64) {
		t.Helper()
		if err := db.QueryRow(ctx, "SELECT state, user_id FROM iap_subscriptions WHERE route='apple' AND original_id=$1", orig).Scan(&st, &owner); err != nil {
			t.Fatal(err)
		}
		return
	}
	base := iapSubscription{Route: iap.RouteApple, OriginalID: orig, ProductID: "plus", Env: iap.EnvSandbox, ExpiresAt: time.Now().Add(time.Hour), AutoRenew: true}
	revoked, stale, fresh := base, base, base
	revoked.State = iap.StateRevoked
	stale.State, stale.ReadAgo = iap.StatePaid, time.Minute
	fresh.State, fresh.ReadAgo = iap.StatePaid, 5*time.Millisecond

	write(user, revoked) // 알림 처리가 방금 환불로 바꿨다
	write(other, stale)  // 1분 전에 paid를 읽은 제출이 뒤늦게 쓴다
	if st, owner := state(); st != "revoked" || owner != other {
		t.Fatalf("옛 상태로 덮어씀: %s %d", st, owner)
	}
	time.Sleep(30 * time.Millisecond)
	write(other, fresh) // 줄을 고친 뒤에 읽은 값이면 쓴다
	if st, _ := state(); st != "paid" {
		t.Fatalf("새로 읽은 상태를 안 씀: %s", st)
	}
	write(other, revoked) // ReadAgo가 없으면(알림 처리) 늘 쓴다
	if st, _ := state(); st != "revoked" {
		t.Fatalf("알림 처리가 못 씀: %s", st)
	}
}
