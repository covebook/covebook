package server

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 결제 테이블(V21)을 읽고 쓰는 함수들. 지급 판단은 여기서 하지 않는다. 부르는 쪽이 스토어 조회와 iap.Check를 끝낸 뒤 부른다.

// dbtx는 연결 풀(s.DB)과 트랜잭션(pgx.Tx)이 둘 다 가진 메서드다.
// 이 타입을 받는 함수는 트랜잭션 안에서도 밖에서도 부를 수 있다.
type dbtx interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// iapPaidShelfMax는 연도 책장 하나에서 돈을 내고 여는 칸의 최대 수다. 책장 6칸 중 3칸은 무료다(D1).
// 두 겹으로 지킨다
//   - 결제 전: 결제 중 예약(iap_shelf_reservations)으로 두 기기가 동시에 3칸을 넘게 사지 못하게 막는다
//   - 결제 뒤: 그래도 넘은 거래는 over_cap으로 표시해 칸을 주지 않고 환불한다. 칸 수를 셀 때도 3에서 한 번 더 자른다
const iapPaidShelfMax = 3

// iapShelfHold는 선반 결제 중 예약이 살아 있는 시간이다. 결제가 끝나거나 취소되면 앱이 바로 푼다.
// 앱이 결제 중에 꺼지면 이 시간이 지나야 다른 기기가 그 해 선반을 살 수 있다.
const iapShelfHold = 5 * time.Minute

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
		err = tx.QueryRow(ctx, "INSERT INTO iap_account_tokens(token, user_id) VALUES($1,$2) RETURNING token::text", uuid.NewString(), user).Scan(&token)
	}
	return token, err
}

// iapShelfToken은 그 연도 책장의 추가 선반을 살 때 스토어에 넘길 계정 연결 값을 돌려준다. 없으면 만든다(D1).
// 연도 하나에 값 하나다. 두 요청이 동시에 와도 유일 색인 때문에 같은 값을 받는다.
func iapShelfToken(ctx context.Context, q dbtx, user int64, year int) (string, error) {
	if _, err := q.Exec(ctx, `INSERT INTO iap_account_tokens(token, user_id, year) VALUES($1,$2,$3)
		ON CONFLICT (user_id, year) WHERE year IS NOT NULL DO NOTHING`, uuid.NewString(), user, year); err != nil {
		return "", err
	}
	var token string
	err := q.QueryRow(ctx, "SELECT token::text FROM iap_account_tokens WHERE user_id=$1 AND year=$2", user, year).Scan(&token)
	return token, err
}

// iapTokenYear는 계정 연결 값이 어느 연도 책장의 것인지 알려 준다. 구독용 값이거나, 없거나, UUID 모양이 아니면 0이다.
func iapTokenYear(ctx context.Context, q dbtx, token string) (int, error) {
	if !iapIsUUID(token) {
		return 0, nil
	}
	var year *int
	err := q.QueryRow(ctx, "SELECT year FROM iap_account_tokens WHERE token=$1::uuid", token).Scan(&year)
	if errors.Is(err, pgx.ErrNoRows) || year == nil {
		return 0, nil
	}
	return *year, err
}

// iapSetShelfYear는 선반 거래가 어느 해 책장의 것인지 정하고 그 연도를 돌려준다(D1).
// 넣을 때 계정 연결 값으로 적은 연도가 있으면 그대로 둔다. 없을 때만 year(앱이 보낸 연도)로 채운다. 끝내 모르면 0이다.
// filled는 이번에 연도를 채웠는지다(그때 결제 완료를 알린다).
func iapSetShelfYear(ctx context.Context, q dbtx, route iap.Route, transactionKey string, year int) (got int, filled bool, err error) {
	var now *int
	err = q.QueryRow(ctx, `WITH old AS (
			SELECT id, shelf_year FROM iap_purchases WHERE route=$1 AND transaction_id=$2 AND kind='product' FOR UPDATE
		)
		UPDATE iap_purchases b SET shelf_year=coalesce(old.shelf_year, nullif($3,0)),
			updated_at=CASE WHEN old.shelf_year IS NULL AND $3<>0 THEN now() ELSE b.updated_at END
		FROM old WHERE b.id=old.id
		RETURNING b.shelf_year, old.shelf_year IS NULL AND $3<>0`, string(route), transactionKey, year).Scan(&now, &filled)
	if errors.Is(err, pgx.ErrNoRows) || now == nil {
		return 0, false, nil
	}
	return *now, filled, err
}

// iapReservationYear는 이 유저의 결제 중 예약이 어느 해 책장의 것인지 알려 준다.
// 5분이 지난 예약도 아직 지워지지 않았으면 연도를 준다(결제창에서 오래 머문 경우). 없거나 남의 예약이거나 UUID 모양이 아니면 0이다.
func iapReservationYear(ctx context.Context, q dbtx, user int64, id string, purchasedAt time.Time) (int, error) {
	// 예약보다 먼저 끝난 결제는 이 예약의 결제가 아니다. 스토어와 우리 시계의 차이를 1분 봐준다
	var year int
	err := q.QueryRow(ctx, `SELECT year FROM iap_shelf_reservations WHERE user_id=$1 AND id::text=lower($2)
		AND ($3::timestamptz IS NULL OR created_at <= $3::timestamptz + interval '1 minute')`,
		user, id, iapNullTime(purchasedAt)).Scan(&year)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return year, err
}

// iapPreferShelfYear는 선반 거래의 연도를 year로 바꾼다(결제 중 예약의 연도를 계정 연결 값의 연도보다 먼저 쓸 때).
// 바뀌었으면 원래 연도(몰랐으면 0)와 true를 돌려준다. 같으면 아무것도 하지 않는다.
func iapPreferShelfYear(ctx context.Context, q dbtx, route iap.Route, transactionKey string, year int) (prev int, changed bool, err error) {
	err = q.QueryRow(ctx, `WITH cur AS (
			SELECT id, shelf_year FROM iap_purchases WHERE route=$1 AND transaction_id=$2 AND kind='product')
		UPDATE iap_purchases b SET shelf_year=$3, updated_at=now() FROM cur
		WHERE b.id=cur.id AND cur.shelf_year IS DISTINCT FROM $3 RETURNING coalesce(cur.shelf_year,0)`,
		string(route), transactionKey, year).Scan(&prev)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, nil
	}
	return prev, err == nil, err
}

// iapShelfPaid는 그 해 책장에서 환불되지 않은 선반 거래가 준 칸 수의 합이다. 3칸을 넘게 산 거래(over_cap)는 세지 않는다.
func iapShelfPaid(ctx context.Context, q dbtx, user int64, year int, allowSandbox bool) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT coalesce(sum(p.shelves),0)::int
		FROM iap_purchases b JOIN iap_products p ON p.route=b.route AND p.product_id=b.product_id
		WHERE b.user_id=$1 AND b.kind='product' AND b.state='paid' AND b.shelf_year=$2 AND NOT b.over_cap
			AND ($3 OR b.env='production')`, user, year, allowSandbox).Scan(&n)
	return n, err
}

// iapSettleShelf는 연도가 정해진 선반 거래가 그 해 유료 칸(3칸)을 넘는지 정하고 over_cap을 돌려준다(D1).
// 다른 거래(넘지 않은 것)의 칸 합 + 이 거래의 칸이 3을 넘으면 over_cap=true로 바꾼다. 거래를 통째로 넘은 것으로 본다
// (3칸 묶음의 일부만 인정하지 않는다. 넘은 거래는 통째로 환불하므로).
// 한 번 true가 되면 false로 돌리지 않는다. 앞선 거래가 나중에 환불돼도 이미 환불을 요청한 거래에 칸을 주지 않게.
// 유저 줄을 잠그고 센다. 같은 유저의 두 거래가 동시에 정해지면 나중 것이 앞의 것을 보고 정한다.
func iapSettleShelf(ctx context.Context, tx pgx.Tx, user int64, route iap.Route, transactionKey string, allowSandbox bool) (overCap bool, err error) {
	var locked int64
	if err = tx.QueryRow(ctx, "SELECT id FROM users WHERE id=$1 FOR UPDATE", user).Scan(&locked); err != nil {
		return
	}
	err = tx.QueryRow(ctx, `WITH me AS (
			SELECT b.id, b.shelf_year, b.over_cap, p.shelves FROM iap_purchases b
			JOIN iap_products p ON p.route=b.route AND p.product_id=b.product_id
			WHERE b.route=$1 AND b.transaction_id=$2 AND b.kind='product' AND b.shelf_year IS NOT NULL AND b.user_id=$3
		), others AS (
			SELECT coalesce(sum(p.shelves),0) AS n FROM iap_purchases b
			JOIN iap_products p ON p.route=b.route AND p.product_id=b.product_id, me
			WHERE b.user_id=$3 AND b.kind='product' AND b.state='paid' AND b.shelf_year=me.shelf_year AND NOT b.over_cap
				AND b.id<>me.id AND ($4 OR b.env='production')
		)
		UPDATE iap_purchases b SET over_cap = me.over_cap OR others.n + me.shelves > $5,
			updated_at = CASE WHEN NOT me.over_cap AND others.n + me.shelves > $5 THEN now() ELSE b.updated_at END
		FROM me, others WHERE b.id=me.id RETURNING b.over_cap`,
		string(route), transactionKey, user, allowSandbox, iapPaidShelfMax).Scan(&overCap)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return
}

// iapOverCapRow는 환불을 다시 요청할 넘은 거래다.
type iapOverCapRow struct {
	Route iap.Route
	Key   string // 원장의 transaction_id(구글 한 번 사는 상품은 구매 토큰)
}

// iapOverCapToRefund는 3칸을 넘게 산 거래 중 환불 요청을 아직 못 마친 것을 오래된 순으로 준다.
// routes는 개발자가 환불할 수 있는 경로(구글)만 준다. 애플 거래가 목록을 차지해 구글 거래가 밀리지 않게.
// 20번 넘게 실패한 거래는 빼고 운영자가 본다(/admin/iap/stats).
func iapOverCapToRefund(ctx context.Context, q dbtx, routes []string, limit int) ([]iapOverCapRow, error) {
	rows, err := q.Query(ctx, `SELECT route, transaction_id FROM iap_purchases
		WHERE over_cap AND refund_requested_at IS NULL AND state='paid' AND refund_attempts < 20 AND route = ANY($1)
		ORDER BY created_at LIMIT $2`, routes, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []iapOverCapRow
	for rows.Next() {
		var r iapOverCapRow
		var route string
		if err = rows.Scan(&route, &r.Key); err != nil {
			return nil, err
		}
		r.Route = iap.Route(route)
		out = append(out, r)
	}
	return out, rows.Err()
}

// iapNoteRefundAttempt는 넘게 산 거래의 환불 요청을 시도했다고 남긴다. ok면 요청한 시각도 적는다.
func iapNoteRefundAttempt(ctx context.Context, q dbtx, route iap.Route, transactionKey string, ok bool) error {
	_, err := q.Exec(ctx, `UPDATE iap_purchases SET refund_attempts=refund_attempts+1,
		refund_requested_at=CASE WHEN $3 THEN coalesce(refund_requested_at, now()) ELSE refund_requested_at END, updated_at=now()
		WHERE route=$1 AND transaction_id=$2 AND over_cap`, string(route), transactionKey, ok)
	return err
}

// iapOwnsToken은 그 계정 연결 값이 이 유저의 것인지 알려 준다. UUID 모양이 아니면 false다.
func iapOwnsToken(ctx context.Context, q dbtx, user int64, token string) (bool, error) {
	if !iapIsUUID(token) {
		return false, nil
	}
	var ok bool
	err := q.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM iap_account_tokens WHERE user_id=$1 AND token=$2::uuid)", user, token).Scan(&ok)
	return ok, err
}

var iapUUID = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// iapIsUUID는 계정 연결 값이 UUID 모양인지 본다. 스토어가 다른 모양을 돌려주면(다른 앱이 넣은 값 등) 빈 값처럼 다룬다.
// DB에 그대로 넘기면 변환 오류로 요청 전체가 실패한다.
func iapIsUUID(s string) bool { return iapUUID.MatchString(s) }

// iapProduct는 상품 테이블의 한 줄이다.
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
// 결제가 끝난 거래만 받는다. user가 0이면 주인 없이(user_id NULL) 넣는다(결제한 계정이 탈퇴한 거래).
// 선반 거래는 계정 연결 값으로 연도 책장을 찾아 함께 적는다. 연도용 값이 아니면 연도는 NULL이고 어느 책장에도 칸을 주지 않는다.
func iapRecordPurchase(ctx context.Context, q dbtx, user int64, kind iap.Kind, p iap.Purchase) (bool, error) {
	if p.State != iap.StatePaid {
		return false, errors.New("iap: 결제가 끝나지 않은 거래는 원장에 넣지 않는다")
	}
	account := p.AccountToken
	if !iapIsUUID(account) {
		account = ""
	}
	tag, err := q.Exec(ctx, `INSERT INTO iap_purchases
		(route,transaction_id,original_id,user_id,account_token,product_id,kind,env,state,purchased_at,currency,price_milli,country,confirmed_at,shelf_year)
		VALUES($1,$2,$3,nullif($4::bigint,0),nullif($5,'')::uuid,$6,$7,$8,'paid',$9,nullif($10,''),nullif($11,0),nullif($12,''),CASE WHEN $13 THEN now() END,
			CASE WHEN $7='product' THEN (SELECT year FROM iap_account_tokens WHERE token=nullif($5,'')::uuid) END)
		ON CONFLICT (route,transaction_id) DO NOTHING`,
		string(p.Route), iapTransactionKey(kind, p), p.OriginalTransactionID, user, account, p.ProductID, string(kind), string(p.Env),
		p.PurchasedAt, p.Currency, p.PriceMilli, p.Country, p.Acknowledged)
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
// 같은 SQL 문에서 환불 고지(T9)도 쓴다: 상태만 바뀌고 고지가 빠지는 일이 없게 한다(주인이 있는 줄만).
// 선반은 거래마다, 구독은 구독 1건마다 한 번 알린다. 3칸을 넘게 산 선반 거래(over_cap)는 알리지 않는다.
// 연도를 몰라 칸을 열지 않은 선반은 opened=false를 붙인다. 주인 없는 줄(결제한 계정이 탈퇴)은 받을 사람이 없어 알리지 않는다.
func iapRevokePurchase(ctx context.Context, q dbtx, route iap.Route, transactionID string, at time.Time) (bool, error) {
	var changed int
	err := q.QueryRow(ctx, `WITH r AS (
			UPDATE iap_purchases SET state='revoked', revoked_at=$3, updated_at=now()
			WHERE route=$1 AND transaction_id=$2 AND state='paid'
			RETURNING user_id, kind, product_id, original_id, transaction_id, env, revoked_at, shelf_year, over_cap
		), n AS (
			INSERT INTO iap_notices (user_id, kind, template, params, env, dedupe_key)
			SELECT r.user_id,
				CASE WHEN r.kind='product' THEN 'shelf_refunded' ELSE 'subscription_refunded' END, 'T9',
				jsonb_strip_nulls(jsonb_build_object('route', $1::text, 'productId', r.product_id, 'kind', r.kind,
					'shelves', CASE WHEN r.kind='product' THEN p.shelves END,
					'year', r.shelf_year,
					-- 연도를 몰라 칸을 열지 않은 선반(서버가 환불함). 앱이 "선반이 잠겼다" 대신 "열지 못해 환불했다"고 쓴다
					'opened', CASE WHEN r.kind='product' AND r.shelf_year IS NULL THEN false END,
					'revokedAt', to_char(r.revoked_at AT TIME ZONE 'UTC', `+iapStampSQL+`))),
				r.env,
				CASE WHEN r.kind='product' THEN 'shelf_refunded:' || $1::text || ':' || r.transaction_id
					ELSE 'subscription_refunded:' || $1::text || ':' || r.original_id END
			FROM r LEFT JOIN iap_products p ON p.route=$1 AND p.product_id=r.product_id
			-- 3칸을 넘게 사서 칸을 주지 않은 선반은 환불돼도 알리지 않는다(넘김 고지로 이미 알렸고 닫을 칸이 없다)
			WHERE r.user_id IS NOT NULL AND NOT (r.kind='product' AND r.over_cap)
			ON CONFLICT (user_id, dedupe_key) DO NOTHING
		) SELECT count(*)::int FROM r`, string(route), transactionID, at).Scan(&changed)
	return changed == 1, err
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
	// 0이 아니면 이만큼 전에 스토어에서 읽은 상태다. 그 뒤에 다른 곳(알림 처리)이 고친 줄은 상태를 덮어쓰지 않고
	// 주인만 바꾼다. 읽고 잠그기 전에 환불 알림이 revoked로 바꿨는데 옛 paid로 되돌리는 일을 막는다
	ReadAgo time.Duration
}

// iapUpsertSubscription은 구독 상태를 넣거나 고친다. 스토어에 다시 물어 받은 최신 상태를 그대로 덮어쓴다.
// user가 다르면 소유자가 바뀐다(구매 복원, D8). 이전 소유자의 번호를 돌려준다(없었거나 같으면 0).
func iapUpsertSubscription(ctx context.Context, tx pgx.Tx, user int64, s iapSubscription) (int64, error) {
	var previous *int64
	if err := iapLockSubscription(ctx, tx, s.Route, s.OriginalID); err != nil {
		return 0, err
	}
	err := tx.QueryRow(ctx, "SELECT user_id FROM iap_subscriptions WHERE route=$1 AND original_id=$2 FOR UPDATE", string(s.Route), s.OriginalID).Scan(&previous)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return 0, err
	}
	var grace *time.Time
	if !s.GraceUntil.IsZero() {
		grace = &s.GraceUntil
	}
	// 읽은 뒤 다른 곳이 고친 줄이면(updated_at이 읽기 시작보다 뒤) 상태 칸은 그 값을 둔다. DB의 지금 시각(clock_timestamp, 잠금을 기다린 시간 포함)에서 거슬러 재서 서버와 DB의 시계 차이를 타지 않는다
	var readAgo *float64
	if s.ReadAgo > 0 {
		sec := s.ReadAgo.Seconds()
		readAgo = &sec
	}
	fresh := "($12::float8 IS NULL OR iap_subscriptions.updated_at <= clock_timestamp() - make_interval(secs => $12::float8))"
	pick := func(col string) string {
		return col + "=CASE WHEN " + fresh + " THEN EXCLUDED." + col + " ELSE iap_subscriptions." + col + " END"
	}
	set := []string{"user_id=EXCLUDED.user_id"}
	for _, col := range []string{"product_id", "plan_id", "env", "state", "expires_at", "grace_until", "auto_renew", "latest_transaction_id"} {
		set = append(set, pick(col))
	}
	_, err = tx.Exec(ctx, `INSERT INTO iap_subscriptions
		(route,original_id,user_id,product_id,plan_id,env,state,expires_at,grace_until,auto_renew,latest_transaction_id)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,nullif($11,''))
		ON CONFLICT (route,original_id) DO UPDATE SET `+strings.Join(set, ", ")+`, updated_at=now()`,
		string(s.Route), s.OriginalID, user, s.ProductID, s.PlanID, string(s.Env), string(s.State), s.ExpiresAt, grace, s.AutoRenew, s.LatestTxnID, readAgo)
	if err != nil {
		return 0, err
	}
	if previous != nil && *previous != user {
		return *previous, nil
	}
	return 0, nil
}

// iapEntitlements는 유저가 지금 가진 것을 계산한다. 따로 저장한 값이 없고 매번 테이블에서 센다(D5).
//   - plus: 결제된 구독이 있고, 만료 전이거나 유예 기간 안이다(D11). 만료 판단은 DB 서버 시계다(D23).
//   - shelves: 연도 책장마다, 환불되지 않은 선반 거래가 준 칸 수의 합. 3칸을 넘게 산 거래(over_cap)는 세지 않고, iapPaidShelfMax에서 한 번 더 자른다(D1).
//     산 칸이 없는 연도는 들어 있지 않다. 연도를 모르는 거래는 어느 책장에도 세지 않는다.
//
// allowSandbox가 false면 샌드박스(시험) 거래는 세지 않는다. 스위치를 끄면 전에 준 샌드박스 권한도 함께 사라진다.
func iapEntitlements(ctx context.Context, q dbtx, user int64, allowSandbox bool) (plus bool, shelves map[int]int, err error) {
	err = q.QueryRow(ctx, `SELECT
		EXISTS(SELECT 1 FROM iap_subscriptions s JOIN iap_products p ON p.route=s.route AND p.product_id=s.product_id
			WHERE s.user_id=$1 AND s.state='paid' AND p.entitlement='plus' AND ($2 OR s.env='production')
			AND (s.expires_at > now() OR s.grace_until > now()))`, user, allowSandbox).Scan(&plus)
	if err != nil {
		return
	}
	rows, err := q.Query(ctx, `SELECT b.shelf_year, least(sum(p.shelves), $3)::int
		FROM iap_purchases b JOIN iap_products p ON p.route=b.route AND p.product_id=b.product_id
		WHERE b.user_id=$1 AND b.kind='product' AND b.state='paid' AND ($2 OR b.env='production') AND b.shelf_year IS NOT NULL AND NOT b.over_cap
		GROUP BY b.shelf_year`, user, allowSandbox, iapPaidShelfMax)
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

// iapUserTokens는 유저가 가진 계정 연결 값 전부를 돌려준다(소문자). 없으면 빈 목록이다.
func iapUserTokens(ctx context.Context, q dbtx, user int64) ([]string, error) {
	rows, err := q.Query(ctx, "SELECT token::text FROM iap_account_tokens WHERE user_id=$1", user)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var t string
		if err = rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// iapProductSet은 그 경로에서 우리가 아는 상품 ID 전부다. 더 팔지 않는 상품도 들어 있다(이미 산 것은 인정한다).
func iapProductSet(ctx context.Context, q dbtx, route iap.Route) (map[string]bool, error) {
	rows, err := q.Query(ctx, "SELECT product_id FROM iap_products WHERE route=$1", string(route))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		if err = rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// iapOwner는 줄의 주인이다. found가 false면 그런 줄이 없다. 줄은 있는데 user가 0이면 주인이 계정을 지운 것이다.
type iapOwner struct {
	found bool
	user  int64
}

// iapPurchaseOwner는 원장에 있는 거래의 주인을 찾는다.
func iapPurchaseOwner(ctx context.Context, q dbtx, route iap.Route, key string) (iapOwner, error) {
	var user *int64
	err := q.QueryRow(ctx, "SELECT user_id FROM iap_purchases WHERE route=$1 AND transaction_id=$2", string(route), key).Scan(&user)
	return iapOwnerOf(user, err)
}

// iapSubscriptionOwner는 구독 1건의 지금 주인을 찾고 그 줄을 잠근다. 트랜잭션 안에서만 부른다.
func iapSubscriptionOwner(ctx context.Context, tx pgx.Tx, route iap.Route, originalID string) (iapOwner, error) {
	if err := iapLockSubscription(ctx, tx, route, originalID); err != nil {
		return iapOwner{}, err
	}
	var user *int64
	err := tx.QueryRow(ctx, "SELECT user_id FROM iap_subscriptions WHERE route=$1 AND original_id=$2 FOR UPDATE", string(route), originalID).Scan(&user)
	return iapOwnerOf(user, err)
}

func iapOwnerOf(user *int64, err error) (iapOwner, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return iapOwner{}, nil
	}
	if err != nil {
		return iapOwner{}, err
	}
	if user == nil {
		return iapOwner{found: true}, nil
	}
	return iapOwner{found: true, user: *user}, nil
}

// iapMarkConfirmed는 스토어 확인을 마쳤다고 남긴다.
func iapMarkConfirmed(ctx context.Context, q dbtx, route iap.Route, key string) error {
	_, err := q.Exec(ctx, "UPDATE iap_purchases SET confirmed_at=now(), updated_at=now() WHERE route=$1 AND transaction_id=$2 AND confirmed_at IS NULL", string(route), key)
	return err
}

// iapCurrentSubscription은 구독 관리 화면에 보일 구독 하나를 고른다. 지금 유효한 것이 먼저, 그다음 만료가 늦은 것. 없으면 nil이다.
//
// 주의: 유예 끝(grace_until)이 NULL이면 `만료 지남 OR NULL`은 NULL이다. coalesce로 false로 만들지 않으면 참·거짓으로 읽다가 실패한다.
func iapCurrentSubscription(ctx context.Context, q dbtx, user int64, allowSandbox bool) (map[string]any, error) {
	var route, product, plan, state string
	var expires time.Time
	var grace *time.Time
	var autoRenew, active bool
	err := q.QueryRow(ctx, `SELECT route, product_id, plan_id, state, expires_at, grace_until, auto_renew,
			coalesce(state='paid' AND (expires_at > now() OR grace_until > now()), false) AS active
		FROM iap_subscriptions WHERE user_id=$1 AND ($2 OR env='production') ORDER BY active DESC, expires_at DESC LIMIT 1`, user, allowSandbox).
		Scan(&route, &product, &plan, &state, &expires, &grace, &autoRenew, &active)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	out := map[string]any{"route": route, "productId": product, "planId": plan, "state": state, "active": active,
		"expiresAt": expires.UTC().Format(time.RFC3339), "autoRenew": autoRenew}
	if grace != nil {
		out["graceUntil"] = grace.UTC().Format(time.RFC3339)
	}
	return out, nil
}

// iapUserByToken은 계정 연결 값의 주인을 찾는다. 없거나 UUID 모양이 아니면 0이다.
func iapUserByToken(ctx context.Context, q dbtx, token string) (int64, error) {
	if !iapIsUUID(token) {
		return 0, nil
	}
	var user int64
	err := q.QueryRow(ctx, "SELECT user_id FROM iap_account_tokens WHERE token=$1::uuid", token).Scan(&user)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return user, err
}

// iapRefreshSubscription은 구독 줄의 상태만 스토어의 답으로 고친다. 주인은 바꾸지 않는다. 줄이 없으면 false다.
// 바뀐 것이 없어도 updated_at은 고친다(대조 작업이 방금 확인한 줄을 다시 고르지 않게).
func iapRefreshSubscription(ctx context.Context, q dbtx, s iapSubscription) (bool, error) {
	var grace *time.Time
	if !s.GraceUntil.IsZero() {
		grace = &s.GraceUntil
	}
	tag, err := q.Exec(ctx, `UPDATE iap_subscriptions SET product_id=$3, plan_id=$4, env=$5, state=$6, expires_at=$7, grace_until=$8,
			auto_renew=$9, latest_transaction_id=nullif($10,''), updated_at=now()
		WHERE route=$1 AND original_id=$2`, string(s.Route), s.OriginalID, s.ProductID, s.PlanID, string(s.Env), string(s.State), s.ExpiresAt, grace, s.AutoRenew, s.LatestTxnID)
	return tag.RowsAffected() == 1, err
}

// iapTouchSubscription은 스토어가 그 구독을 더 알려 주지 않을 때(구글은 만료 60일 뒤) 권한 없음으로 확정한다.
// paid였던 줄이면 같은 SQL 문에서 만료 고지(T8)도 쓴다.
func iapTouchSubscription(ctx context.Context, q dbtx, route iap.Route, originalID string) error {
	_, err := q.Exec(ctx, `WITH old AS (
			SELECT user_id, state, product_id, env, expires_at FROM iap_subscriptions WHERE route=$1 AND original_id=$2 FOR UPDATE
		), u AS (
			UPDATE iap_subscriptions SET state=CASE WHEN state='paid' THEN 'inactive' ELSE state END, updated_at=now() WHERE route=$1 AND original_id=$2
		)
		INSERT INTO iap_notices (user_id, kind, template, params, env, dedupe_key)
		SELECT old.user_id, 'expired', 'T8',
			jsonb_build_object('route', $1::text, 'productId', old.product_id, 'kind', 'subscription',
				'expiresAt', to_char(old.expires_at AT TIME ZONE 'UTC', `+iapStampSQL+`)),
			old.env, 'expired:' || $1::text || ':' || $2::text || ':' || to_char(old.expires_at AT TIME ZONE 'UTC', `+iapStampSQL+`)
		FROM old WHERE old.state='paid' AND old.user_id IS NOT NULL
		ON CONFLICT (user_id, dedupe_key) DO NOTHING`, string(route), originalID)
	return err
}

// iapEndLinked는 새 구독이 대신한 옛 줄기를 끝낸다(구글 요금제 변경·만료 전 재가입). 안 끝내면 한 구매로 두 줄이 권한을 준다.
func iapEndLinked(ctx context.Context, q dbtx, route iap.Route, linkedID, newID string) error {
	if linkedID == "" || linkedID == newID {
		return nil
	}
	_, err := q.Exec(ctx, "UPDATE iap_subscriptions SET state='inactive', auto_renew=false, updated_at=now() WHERE route=$1 AND original_id=$2 AND state='paid'", string(route), linkedID)
	return err
}

// iapSyncPurchaseState는 원장에 있는 거래의 환불 상태를 스토어의 답에 맞춘다. 줄을 지우지 않는다.
// 환불되면 revoked로, 환불이 되돌려지면 다시 paid로 고친다. 바뀐 줄이 있으면 true다.
func iapSyncPurchaseState(ctx context.Context, q dbtx, route iap.Route, key string, state iap.State, revokedAt time.Time) (bool, error) {
	switch state {
	case iap.StateRevoked:
		at := revokedAt
		if at.IsZero() {
			at = time.Now().UTC()
		}
		return iapRevokePurchase(ctx, q, route, key, at)
	case iap.StatePaid:
		// 환불 되돌림은 애플에만 적용한다. 애플은 거래마다 환불 여부를 알려 준다.
		// 구글 조회는 "지금 유효한가"만 알려 줘서, 환불 알림으로 표시한 줄을 다음 조회가 되살려 버린다.
		if route != iap.RouteApple {
			return false, nil
		}
		tag, err := q.Exec(ctx, "UPDATE iap_purchases SET state='paid', revoked_at=NULL, updated_at=now() WHERE route=$1 AND transaction_id=$2 AND state='revoked'", string(route), key)
		return tag.RowsAffected() == 1, err
	}
	return false, nil
}

// iapNoticeRow는 처리할 알림 한 건이다.
type iapNoticeRow struct {
	Route      iap.Route
	ID         string
	Kind       iap.Kind // 다시 물어볼 대상의 종류. 없으면 빈 값
	TargetID   string
	OriginalID string
	OrderID    string
	Type       string // 스토어가 준 알림 종류. "voided/"로 시작하면 구글의 환불·취소 알림
}

// iapPendingNotifications는 아직 처리하지 못한 알림을 오래된 것부터 고른다.
// 실패한 것은 시도할수록 간격을 늘린다(1분, 2분, 4분 … 최대 약 17시간). 8일이 지난 것은 더 시도하지 않는다.
func iapPendingNotifications(ctx context.Context, q dbtx, limit int) ([]iapNoticeRow, error) {
	rows, err := q.Query(ctx, `SELECT route, notification_id, coalesce(target_kind,''), coalesce(target_id,''), coalesce(original_id,''), coalesce(order_id,''), kind
		FROM iap_notifications
		WHERE result IN ('received','failed') AND received_at > now() - interval '8 days'
		  AND (processed_at IS NULL OR processed_at < now() - interval '1 minute' * power(2, least(attempts, 10)))
		ORDER BY received_at LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []iapNoticeRow
	for rows.Next() {
		var n iapNoticeRow
		if err = rows.Scan(&n.Route, &n.ID, &n.Kind, &n.TargetID, &n.OriginalID, &n.OrderID, &n.Type); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// iapYearlessToRefund는 서버가 환불할 칸 없는 선반 거래를 준다(구글 권고: 받을 수 없는 구매는 자동 환불에 맡기지 않는다, 2026-11-26 결정).
//   - 연도를 모르는 선반: 2일 기다린다. 앱이 연도와 함께 다시 내면 칸을 받는다(그러면 shelf_year가 채워져 빠진다)
//   - 주인 없는 선반(결제한 계정이 탈퇴, user_id NULL): 제출 때 이미 환불을 시도했으니 기다리지 않고 다시 한다
//
// 3일이 지나면 구글이 이미 자동 환불했으니 뺀다. 20번 넘게 실패한 거래도 빼고 운영자가 본다
func iapYearlessToRefund(ctx context.Context, q dbtx, routes []string, limit int) ([]iapOverCapRow, error) {
	rows, err := q.Query(ctx, `SELECT route, transaction_id FROM iap_purchases
		WHERE kind='product' AND shelf_year IS NULL AND NOT over_cap AND confirmed_at IS NULL AND state='paid'
		  AND refund_requested_at IS NULL AND refund_attempts < 20 AND route = ANY($1)
		  AND (created_at < now() - interval '2 days' OR user_id IS NULL) AND created_at > now() - interval '3 days'
		ORDER BY created_at LIMIT $2`, routes, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []iapOverCapRow
	for rows.Next() {
		var r iapOverCapRow
		var route string
		if err = rows.Scan(&route, &r.Key); err != nil {
			return nil, err
		}
		r.Route = iap.Route(route)
		out = append(out, r)
	}
	return out, rows.Err()
}

// iapUnconfirmed는 지급했는데 스토어 확인을 마치지 못한 거래다. 구글은 3일 안에 확인하지 않으면 자동 환불한다.
type iapUnconfirmed struct {
	Route      iap.Route
	Key        string
	OriginalID string
	ProductID  string
	Kind       iap.Kind
}

// iapUnconfirmedPurchases는 스토어 확인을 못 마친 거래를 고른다(정기 대조 1단계).
// 연도를 모르는 선반은 뺀다. 제출·알림 경로처럼 일부러 소비하지 않은 거래다(연도와 함께 다시 내면 shelf_year가 채워져 그때 대상이 된다).
// 여기서 소비하면 구글의 3일 자동 환불이 사라지고 앱도 다시 낼 수 없어, 돈은 받고 칸은 없는 채로 굳는다
func iapUnconfirmedPurchases(ctx context.Context, q dbtx, limit int) ([]iapUnconfirmed, error) {
	rows, err := q.Query(ctx, `SELECT route, transaction_id, original_id, product_id, kind FROM iap_purchases
		WHERE confirmed_at IS NULL AND state='paid' AND created_at < now() - interval '1 minute' AND created_at > now() - interval '4 days'
		  AND NOT (kind = 'product' AND shelf_year IS NULL)
		ORDER BY created_at LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []iapUnconfirmed
	for rows.Next() {
		var u iapUnconfirmed
		if err = rows.Scan(&u.Route, &u.Key, &u.OriginalID, &u.ProductID, &u.Kind); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// iapDueSubscriptions는 스토어에 다시 물어볼 구독을 고른다(애플이 권하는 "갱신 시점 재확인").
//   - 유효한데 만료(유예 중이면 유예 끝)가 5분 안으로 다가왔거나 지난 것. 갱신됐는지 확인한다. 10분에 한 번
//   - 권한이 없지만 만료된 지 60일이 안 된 것. 결제 재시도로 되살아났는지 확인한다. 하루에 한 번
func iapDueSubscriptions(ctx context.Context, q dbtx, limit int) ([][2]string, error) {
	rows, err := q.Query(ctx, `SELECT route, original_id FROM iap_subscriptions
		WHERE (state='paid' AND coalesce(grace_until, expires_at) < now() + interval '5 minutes' AND updated_at < now() - interval '10 minutes')
		   OR (state='inactive' AND expires_at > now() - interval '60 days' AND updated_at < now() - interval '24 hours')
		ORDER BY updated_at LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out [][2]string
	for rows.Next() {
		var route, original string
		if err = rows.Scan(&route, &original); err != nil {
			return nil, err
		}
		out = append(out, [2]string{route, original})
	}
	return out, rows.Err()
}

// iapProductList는 지금 파는 상품이다. 앱이 이 목록의 상품 ID로 스토어에 가격을 묻는다. 가격은 여기에 없다(D22).
func iapProductList(ctx context.Context, q dbtx) ([]map[string]any, error) {
	rows, err := q.Query(ctx, "SELECT route, product_id, kind, coalesce(entitlement,''), coalesce(shelves,0) FROM iap_products WHERE active ORDER BY route, kind, product_id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var route, id, kind, entitlement string
		var shelves int
		if err = rows.Scan(&route, &id, &kind, &entitlement, &shelves); err != nil {
			return nil, err
		}
		p := map[string]any{"route": route, "productId": id, "kind": kind}
		if kind == "subscription" {
			p["entitlement"] = entitlement
		} else {
			p["shelves"] = shelves
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// iapLockLine은 구독 1건 하나를 다루는 동안 다른 요청·작업이 같은 줄기를 다루지 못하게 한다(트랜잭션이 끝나면 풀린다).
// 줄이 아직 없을 때는 SELECT ... FOR UPDATE가 아무것도 잠그지 못한다. 그 틈에 제출과 알림 처리가 동시에 "줄 없음"을 보고
// 서로의 결과를 덮어쓰는 것을 막는다.
func iapLockLine(ctx context.Context, tx pgx.Tx, route iap.Route, originalID string) error {
	_, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", "iap:"+string(route)+":"+originalID)
	return err
}

// iapBumpSubscription은 "방금 확인했다"고만 남긴다. 처리하지 않기로 한 줄(받지 않는 거래, 조회 실패)이
// 대조 작업의 맨 앞에 매번 다시 뽑혀 다른 구독의 차례를 막지 않게 한다.
func iapBumpSubscription(ctx context.Context, q dbtx, route iap.Route, originalID string) error {
	_, err := q.Exec(ctx, "UPDATE iap_subscriptions SET updated_at=now() WHERE route=$1 AND original_id=$2", string(route), originalID)
	return err
}

// iapReservation은 선반 결제 중 예약 하나다.
type iapReservation struct {
	ID        string
	ExpiresAt time.Time
}

// iapReserveShelf는 그 해 책장에 shelves칸 결제 중 예약을 잡는다. paid는 그 해에 이미 산 칸 수다.
// 산 칸 + 살아 있는 예약 칸 + 이번 칸이 iapPaidShelfMax를 넘으면 잡지 않고, 가장 먼저 끝나는 예약까지 남은 시간(wait)을 준다.
// 부르는 쪽이 유저 줄을 잠근 트랜잭션 안에서 부른다(두 기기가 동시에 잡지 못하게). 시각은 DB 시계다(D23).
func iapReserveShelf(ctx context.Context, tx pgx.Tx, user int64, year, shelves, paid int) (r iapReservation, wait time.Duration, err error) {
	// 끝난 예약은 지운다. 남아 있어도 세지 않지만 테이블이 쌓이지 않게
	if _, err = tx.Exec(ctx, "DELETE FROM iap_shelf_reservations WHERE user_id=$1 AND expires_at <= now()", user); err != nil {
		return
	}
	var held int
	var waitSecs float64
	if err = tx.QueryRow(ctx, `SELECT coalesce(sum(shelves),0)::int, coalesce(extract(epoch FROM min(expires_at) - now()),0)::float8
		FROM iap_shelf_reservations WHERE user_id=$1 AND year=$2 AND expires_at > now()`, user, year).Scan(&held, &waitSecs); err != nil {
		return
	}
	if paid+held+shelves > iapPaidShelfMax {
		wait = time.Duration(waitSecs * float64(time.Second))
		if wait < time.Second {
			wait = time.Second
		}
		return
	}
	err = tx.QueryRow(ctx, `INSERT INTO iap_shelf_reservations(id, user_id, year, shelves, expires_at)
		VALUES($1,$2,$3,$4, now() + make_interval(secs => $5)) RETURNING id::text, expires_at`,
		uuid.NewString(), user, year, shelves, iapShelfHold.Seconds()).Scan(&r.ID, &r.ExpiresAt)
	return
}

// iapReleaseReservation은 이 유저의 예약 하나를 푼다. 없거나 남의 예약이거나 UUID 모양이 아니면 아무 일도 하지 않는다.
func iapReleaseReservation(ctx context.Context, q dbtx, user int64, id string) error {
	_, err := q.Exec(ctx, "DELETE FROM iap_shelf_reservations WHERE user_id=$1 AND id::text=lower($2)", user, id)
	return err
}

// iapReleaseOldestReservation은 그 해 책장의 살아 있는 예약 중 가장 먼저 잡은 것 하나를 푼다.
// 어느 예약의 결제인지 모를 때 쓴다(스토어 알림으로 지급될 때, 앱이 예약 번호를 보내지 않았을 때).
func iapReleaseOldestReservation(ctx context.Context, q dbtx, user int64, year int) error {
	_, err := q.Exec(ctx, `DELETE FROM iap_shelf_reservations WHERE id = (
		SELECT id FROM iap_shelf_reservations WHERE user_id=$1 AND year=$2 AND expires_at > now()
		ORDER BY created_at, id LIMIT 1)`, user, year)
	return err
}

// iapTokenOwner는 계정 연결 값(구독용이든 연도용이든)을 발급받은 유저다. 모르는 값이면 0이다
func iapTokenOwner(ctx context.Context, q dbtx, token string) (int64, error) {
	if _, err := uuid.Parse(token); err != nil {
		return 0, nil
	}
	var user int64
	err := q.QueryRow(ctx, "SELECT user_id FROM iap_account_tokens WHERE token=$1::uuid", token).Scan(&user)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return user, err
}

// iapNullTime은 0 시각을 NULL로 넘긴다
func iapNullTime(t time.Time) *time.Time {
	if t.IsZero() {
		return nil
	}
	return &t
}

// iapLockSubscription은 구독 1건(경로, 원 거래 ID)을 트랜잭션 끝까지 잠근다. 줄이 아직 없을 때도 잠기므로
// 두 계정이 같은 새 구독을 동시에 내도 하나씩 처리된다(FOR UPDATE는 없는 줄을 잠그지 못한다)
func iapLockSubscription(ctx context.Context, tx pgx.Tx, route iap.Route, originalID string) error {
	_, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1 || '/' || $2, 0))", string(route), originalID)
	return err
}
