package server

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 결제 표(V21)를 읽고 쓰는 함수들. 지급 판단은 여기서 하지 않는다. 부르는 쪽이 스토어 조회와 iap.Check를 끝낸 뒤 부른다.

// dbtx는 연결 풀(s.DB)과 트랜잭션(pgx.Tx)이 둘 다 가진 메서드다.
// 이 타입을 받는 함수는 트랜잭션 안에서도 밖에서도 부를 수 있다.
type dbtx interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// iapPaidShelfMax는 연도 책장 하나에서 돈을 내고 여는 칸의 최대 수다. 책장 6칸 중 3칸은 무료다(D1).
// 이 수를 넘게 산 거래도 원장에는 남기고, 칸 수만 여기서 자른다. 넘은 거래는 운영자가 환불한다.
const iapPaidShelfMax = 3

// iapAccountToken은 유저의 구독용 계정 연결 값을 돌려준다. 없으면 만든다. 앱이 스토어에 넘길 값이다(D7).
// 여러 개면 가장 먼저 만든 것을 준다. 유저 줄을 잠가서 동시에 두 개가 생기지 않게 한다.
// 추가 선반에는 이 값을 쓰지 않는다. 연도 책장마다 따로 받는다(iapShelfToken).
func iapAccountToken(ctx context.Context, tx pgx.Tx, user int64) (string, error) {
	var locked int64
	if err := tx.QueryRow(ctx, "SELECT id FROM users WHERE id=$1 FOR UPDATE", user).Scan(&locked); err != nil {
		return "", err
	}
	var token string
	err := tx.QueryRow(ctx, "SELECT token::text FROM iap_account_tokens WHERE user_id=$1 AND year IS NULL ORDER BY created_at, token LIMIT 1", user).Scan(&token)
	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, "INSERT INTO iap_account_tokens(user_id) VALUES($1) RETURNING token::text", user).Scan(&token)
	}
	return token, err
}

// iapShelfToken은 그 연도 책장의 추가 선반을 살 때 스토어에 넘길 계정 연결 값을 돌려준다. 없으면 만든다(D1).
// 연도 하나에 값 하나다. 두 요청이 동시에 와도 유일 색인 때문에 같은 값을 받는다.
func iapShelfToken(ctx context.Context, q dbtx, user int64, year int) (string, error) {
	if _, err := q.Exec(ctx, `INSERT INTO iap_account_tokens(user_id, year) VALUES($1,$2)
		ON CONFLICT (user_id, year) WHERE year IS NOT NULL DO NOTHING`, user, year); err != nil {
		return "", err
	}
	var token string
	err := q.QueryRow(ctx, "SELECT token::text FROM iap_account_tokens WHERE user_id=$1 AND year=$2", user, year).Scan(&token)
	return token, err
}

// iapTokenYear는 계정 연결 값이 어느 연도 책장의 것인지 알려 준다. 구독용 값이거나, 없거나, UUID 모양이 아니면 0이다.
func iapTokenYear(ctx context.Context, q dbtx, token string) (int, error) {
	var year *int
	err := q.QueryRow(ctx, "SELECT year FROM iap_account_tokens WHERE token::text=lower($1)", token).Scan(&year)
	if errors.Is(err, pgx.ErrNoRows) || year == nil {
		return 0, nil
	}
	return *year, err
}

// iapOwnsToken은 그 계정 연결 값이 이 유저의 것인지 알려 준다. UUID 모양이 아니면 false다.
func iapOwnsToken(ctx context.Context, q dbtx, user int64, token string) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM iap_account_tokens
		WHERE user_id=$1 AND token::text=lower($2))`, user, token).Scan(&ok)
	return ok, err
}

// iapProduct는 상품 표의 한 줄이다.
type iapProduct struct {
	Kind        iap.Kind
	Entitlement string
	Shelves     int
	Consume     bool // 구글에서 소비 처리할지
	Active      bool
}

// iapFindProduct는 상품을 찾는다. 없으면 pgx.ErrNoRows다.
func iapFindProduct(ctx context.Context, q dbtx, route iap.Route, productID string) (iapProduct, error) {
	var p iapProduct
	err := q.QueryRow(ctx, `SELECT kind, coalesce(entitlement,''), coalesce(shelves,0), consume, active
		FROM iap_products WHERE route=$1 AND product_id=$2`, string(route), productID).Scan(&p.Kind, &p.Entitlement, &p.Shelves, &p.Consume, &p.Active)
	return p, err
}

// iapRecordPurchase는 거래를 원장에 넣는다. 처음 들어갔으면 true, 이미 있던 거래면 false다.
// "먼저 조회하고 없으면 넣기"를 하지 않는다. 유일 키에 맡기고 들어간 줄 수로 판단한다(D6).
// 결제가 끝난 거래만 받는다.
// 선반 거래는 계정 연결 값으로 연도 책장을 찾아 함께 적는다. 연도용 값이 아니면 연도는 NULL이고 어느 책장에도 칸을 주지 않는다.
func iapRecordPurchase(ctx context.Context, q dbtx, user int64, kind iap.Kind, p iap.Purchase) (bool, error) {
	if p.State != iap.StatePaid {
		return false, errors.New("iap: 결제가 끝나지 않은 거래는 원장에 넣지 않는다")
	}
	tag, err := q.Exec(ctx, `INSERT INTO iap_purchases
		(route,transaction_id,original_id,user_id,account_token,product_id,kind,env,state,purchased_at,currency,price_milli,country,shelf_year)
		VALUES($1,$2,$3,$4,nullif($5,'')::uuid,$6,$7,$8,'paid',$9,nullif($10,''),nullif($11,0),nullif($12,''),
			CASE WHEN $7='product' THEN (SELECT year FROM iap_account_tokens WHERE token=nullif($5,'')::uuid) END)
		ON CONFLICT (route,transaction_id) DO NOTHING`,
		string(p.Route), iapTransactionKey(kind, p), p.OriginalTransactionID, user, p.AccountToken, p.ProductID, string(kind), string(p.Env),
		p.PurchasedAt, p.Currency, p.PriceMilli, p.Country)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// iapTransactionKey는 원장의 유일 키에 쓸 값이다.
//   - 애플: 거래 ID
//   - 구글 한 번 사는 상품: 구매 토큰. 구글은 주문 ID를 유일 키로 쓰지 말라고 한다(프로모션 코드 구매는 주문 ID가 없다)
//   - 구글 구독: 주문 ID. 갱신마다 토큰은 그대로이고 주문 ID가 새로 생긴다. 없으면 구매 토큰
func iapTransactionKey(kind iap.Kind, p iap.Purchase) string {
	if p.Route == iap.RouteGoogle && kind == iap.KindProduct {
		return p.OriginalTransactionID
	}
	if p.TransactionID != "" {
		return p.TransactionID
	}
	return p.OriginalTransactionID
}

// iapRevokePurchase는 환불·취소를 원장에 남긴다. 줄을 지우지 않는다. 바뀐 줄이 있으면 true다.
func iapRevokePurchase(ctx context.Context, q dbtx, route iap.Route, transactionID string, at time.Time) (bool, error) {
	tag, err := q.Exec(ctx, `UPDATE iap_purchases SET state='revoked', revoked_at=$3, updated_at=now()
		WHERE route=$1 AND transaction_id=$2 AND state='paid'`, string(route), transactionID, at)
	return tag.RowsAffected() == 1, err
}

// iapSubscription은 구독 한 줄기의 지금 상태다.
type iapSubscription struct {
	Route       iap.Route
	OriginalID  string
	ProductID   string
	PlanID      string
	Env         iap.Env
	State       iap.State // paid, inactive, revoked
	ExpiresAt   time.Time
	GraceUntil  time.Time // 유예 중이 아니면 zero
	AutoRenew   bool
	LatestTxnID string
}

// iapUpsertSubscription은 구독 상태를 넣거나 고친다. 스토어에 다시 물어 받은 최신 상태를 그대로 덮어쓴다.
// user가 다르면 소유자가 바뀐다(구매 복원, D8). 이전 소유자의 번호를 돌려준다(없었거나 같으면 0).
func iapUpsertSubscription(ctx context.Context, tx pgx.Tx, user int64, s iapSubscription) (int64, error) {
	var previous *int64
	err := tx.QueryRow(ctx, "SELECT user_id FROM iap_subscriptions WHERE route=$1 AND original_id=$2 FOR UPDATE", string(s.Route), s.OriginalID).Scan(&previous)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return 0, err
	}
	var grace *time.Time
	if !s.GraceUntil.IsZero() {
		grace = &s.GraceUntil
	}
	_, err = tx.Exec(ctx, `INSERT INTO iap_subscriptions
		(route,original_id,user_id,product_id,plan_id,env,state,expires_at,grace_until,auto_renew,latest_transaction_id)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,nullif($11,''))
		ON CONFLICT (route,original_id) DO UPDATE SET
			user_id=EXCLUDED.user_id, product_id=EXCLUDED.product_id, plan_id=EXCLUDED.plan_id, env=EXCLUDED.env,
			state=EXCLUDED.state, expires_at=EXCLUDED.expires_at, grace_until=EXCLUDED.grace_until,
			auto_renew=EXCLUDED.auto_renew, latest_transaction_id=EXCLUDED.latest_transaction_id, updated_at=now()`,
		string(s.Route), s.OriginalID, user, s.ProductID, s.PlanID, string(s.Env), string(s.State), s.ExpiresAt, grace, s.AutoRenew, s.LatestTxnID)
	if err != nil {
		return 0, err
	}
	if previous != nil && *previous != user {
		return *previous, nil
	}
	return 0, nil
}

// iapEntitlements는 유저가 지금 가진 것을 계산한다. 따로 저장한 값이 없고 매번 표에서 센다(D5).
//   - plus: 결제된 구독이 있고, 만료 전이거나 유예 기간 안이다(D11). 만료 판단은 DB 서버 시계다(D23).
//   - shelves: 연도 책장마다, 환불되지 않은 선반 거래가 준 칸 수의 합. iapPaidShelfMax에서 자른다(D1).
//     산 칸이 없는 연도는 들어 있지 않다. 연도를 모르는 거래는 어느 책장에도 세지 않는다.
func iapEntitlements(ctx context.Context, q dbtx, user int64) (plus bool, shelves map[int]int, err error) {
	err = q.QueryRow(ctx, `SELECT
		EXISTS(SELECT 1 FROM iap_subscriptions s JOIN iap_products p ON p.route=s.route AND p.product_id=s.product_id
			WHERE s.user_id=$1 AND s.state='paid' AND p.entitlement='plus'
			AND (s.expires_at > now() OR s.grace_until > now()))`, user).Scan(&plus)
	if err != nil {
		return
	}
	rows, err := q.Query(ctx, `SELECT b.shelf_year, least(sum(p.shelves), $2)::int
		FROM iap_purchases b JOIN iap_products p ON p.route=b.route AND p.product_id=b.product_id
		WHERE b.user_id=$1 AND b.kind='product' AND b.state='paid' AND b.shelf_year IS NOT NULL
		GROUP BY b.shelf_year`, user, iapPaidShelfMax)
	if err != nil {
		return
	}
	defer rows.Close()
	shelves = map[int]int{}
	for rows.Next() {
		var year, n int
		if err = rows.Scan(&year, &n); err != nil {
			return
		}
		shelves[year] = n
	}
	err = rows.Err()
	return
}

// iapRecordNotification은 받은 알림을 남긴다. 처음 받은 알림이면 true, 이미 받은 알림이면 false다(D6).
// 원문과 함께 "다시 물어볼 대상"을 적어 둔다. 처리는 뒤에서 한다.
func iapRecordNotification(ctx context.Context, q dbtx, n iap.Notice, payload string) (bool, error) {
	var kind, target *string
	if n.Target != nil {
		k, t := string(n.Target.Kind), n.Target.ID
		kind, target = &k, &t
	}
	tag, err := q.Exec(ctx, `INSERT INTO iap_notifications(route,notification_id,kind,payload,target_kind,target_id,original_id,order_id)
		VALUES($1,$2,$3,$4,$5,$6,nullif($7,''),nullif($8,''))
		ON CONFLICT (route,notification_id) DO NOTHING`, string(n.Route), n.ID, n.Type, payload, kind, target, n.OriginalID, n.OrderID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// iapFinishNotification은 알림 처리 결과를 남긴다. result는 processed, ignored, failed 중 하나다.
func iapFinishNotification(ctx context.Context, q dbtx, route iap.Route, id, result, errText string) error {
	_, err := q.Exec(ctx, `UPDATE iap_notifications SET result=$3, error=nullif($4,''), processed_at=now(), attempts=attempts+1
		WHERE route=$1 AND notification_id=$2`, string(route), id, result, errText)
	return err
}
