package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 결제 고지(앱 안 알림함, ADR-0003 L8·L11·L18).
//
// 고지는 "상태가 바뀐 순간"에 한 번 쓴다. 그래서 고칠 줄의 이전 값을 먼저 읽고(FOR UPDATE) 새 값과 견준다.
// 스토어 알림은 같은 것이 여러 번 오고 대조 작업도 같은 줄을 다시 보므로, 유일 키(user_id, dedupe_key)로 한 번만 남긴다.
// 문구는 저장하지 않는다. 문구 번호와 채울 값만 남기고, 앱이 docs/legal/notice-templates.md의 문구로 보여 준다.

const (
	noticePurchaseDone    = "purchase_done"         // T3 결제 완료
	noticePaymentFailed   = "payment_failed"        // T7 결제 실패(유예 시작)
	noticeExpired         = "expired"               // T8 구독 만료
	noticeCancelScheduled = "cancel_scheduled"      // T10 해지 접수(자동 갱신 꺼짐)
	noticeSubRefunded     = "subscription_refunded" // T9 환불(구독)
	noticeShelfRefunded   = "shelf_refunded"        // T9 환불(선반)
	noticeRenewalUpcoming = "renewal_upcoming"      // T4 갱신 예정(연 구독)
)

var iapNoticeTemplate = map[string]string{
	noticePurchaseDone: "T3", noticePaymentFailed: "T7", noticeExpired: "T8",
	noticeCancelScheduled: "T10", noticeSubRefunded: "T9", noticeShelfRefunded: "T9",
	noticeRenewalUpcoming: "T4",
}

// iapStamp는 고지의 값과 유일 키에 쓰는 시각 표기다(UTC, 초 단위). SQL 쪽 표기(iapStampSQL)와 같아야 같은 일이 한 줄로 모인다.
func iapStamp(t time.Time) string { return t.UTC().Format(time.RFC3339) }

const iapStampSQL = `'YYYY-MM-DD"T"HH24:MI:SS"Z"'`

// iapWriteNotice는 고지 한 줄을 쓴다. 같은 일(dedupe)이 이미 있으면 아무것도 하지 않는다. 주인이 없으면 쓰지 않는다.
func iapWriteNotice(ctx context.Context, q dbtx, user int64, kind string, env iap.Env, dedupe string, params map[string]any) error {
	if user == 0 {
		return nil
	}
	raw, err := json.Marshal(params)
	if err != nil {
		return err
	}
	if env == "" {
		env = iap.EnvProduction
	}
	_, err = q.Exec(ctx, `INSERT INTO iap_notices (user_id, kind, template, params, env, dedupe_key)
		VALUES ($1,$2,$3,$4::jsonb,$5,$6) ON CONFLICT (user_id, dedupe_key) DO NOTHING`,
		user, kind, iapNoticeTemplate[kind], string(raw), string(env), dedupe)
	return err
}

// iapNotePurchaseDone은 새로 지급한 구매를 알린다(T3). 거래 키가 유일 키라 같은 거래는 한 번만 알린다.
func iapNotePurchaseDone(ctx context.Context, q dbtx, user int64, kind iap.Kind, p iap.Purchase, shelves int) error {
	params := map[string]any{"route": string(p.Route), "productId": p.ProductID, "kind": string(kind)}
	if kind == iap.KindSubscription {
		params["expiresAt"] = iapStamp(p.ExpiresAt)
	} else {
		params["shelves"] = shelves
	}
	return iapWriteNotice(ctx, q, user, noticePurchaseDone, p.Env, "purchase_done:"+string(p.Route)+":"+iapTransactionKey(kind, p), params)
}

// iapSubBefore는 구독 줄을 고치기 전의 값이다. 고지는 이 값과 새 값이 달라진 순간에만 쓴다.
type iapSubBefore struct {
	found     bool
	user      int64 // 주인이 없으면 0
	state     iap.State
	grace     time.Time // 유예 중이 아니었으면 zero
	autoRenew bool
}

// iapSubBeforeOf는 구독 줄의 지금 값을 읽고 잠근다. 같은 트랜잭션에서 줄을 고친 뒤 iapNoteSubscriptionChange에 넘긴다.
func iapSubBeforeOf(ctx context.Context, tx pgx.Tx, route iap.Route, originalID string) (iapSubBefore, error) {
	var (
		b     iapSubBefore
		user  *int64
		grace *time.Time
	)
	err := tx.QueryRow(ctx, "SELECT user_id, state, grace_until, auto_renew FROM iap_subscriptions WHERE route=$1 AND original_id=$2 FOR UPDATE",
		string(route), originalID).Scan(&user, &b.state, &grace, &b.autoRenew)
	if errors.Is(err, pgx.ErrNoRows) {
		return iapSubBefore{}, nil
	}
	if err != nil {
		return b, err
	}
	b.found = true
	if user != nil {
		b.user = *user
	}
	if grace != nil {
		b.grace = *grace
	}
	return b, nil
}

// iapNoteSubscriptionChange는 구독 줄이 before에서 s로 바뀌면서 유저에게 알릴 일이 생겼는지 보고 고지를 쓴다.
// 주인이 그대로인 줄에만 쓴다(새로 생긴 줄, 다른 계정으로 옮겨진 줄은 "바뀐 것"이 아니다).
//   - 환불(T9): revoked가 됐다
//   - 만료(T8): paid였는데 inactive가 됐다. 방금 환불을 알린 구독이면 만료는 따로 알리지 않는다
//   - 결제 실패(T7): 유예가 새로 시작됐다(유예 종료 시각이 전과 다르다)
//   - 해지 접수(T10): 자동 갱신이 켜져 있다가 꺼졌고 아직 이용 기간이 남았다
func iapNoteSubscriptionChange(ctx context.Context, q dbtx, user int64, before iapSubBefore, s iapSubscription, now time.Time) error {
	if !before.found || before.user == 0 || before.user != user {
		return nil
	}
	line := string(s.Route) + ":" + s.OriginalID
	base := map[string]any{"route": string(s.Route), "productId": s.ProductID, "kind": string(iap.KindSubscription)}
	with := func(k string, v any) map[string]any {
		m := map[string]any{k: v}
		for bk, bv := range base {
			m[bk] = bv
		}
		return m
	}
	switch {
	case s.State == iap.StateRevoked && before.state != iap.StateRevoked:
		return iapWriteNotice(ctx, q, user, noticeSubRefunded, s.Env, "subscription_refunded:"+line, with("revokedAt", iapStamp(now)))
	case s.State == iap.StateInactive && before.state == iap.StatePaid:
		var refunded bool
		if err := q.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM iap_notices WHERE user_id=$1 AND dedupe_key=$2 AND created_at > now() - interval '1 day')",
			user, "subscription_refunded:"+line).Scan(&refunded); err != nil || refunded {
			return err
		}
		return iapWriteNotice(ctx, q, user, noticeExpired, s.Env, "expired:"+line+":"+iapStamp(s.ExpiresAt), with("expiresAt", iapStamp(s.ExpiresAt)))
	case s.State != iap.StatePaid:
		return nil
	}
	if !s.GraceUntil.IsZero() && s.GraceUntil.After(now) && !s.GraceUntil.Equal(before.grace) {
		m := with("graceUntil", iapStamp(s.GraceUntil))
		m["expiresAt"] = iapStamp(s.ExpiresAt)
		if err := iapWriteNotice(ctx, q, user, noticePaymentFailed, s.Env, "payment_failed:"+line+":"+iapStamp(s.GraceUntil), m); err != nil {
			return err
		}
	}
	if before.state == iap.StatePaid && before.autoRenew && !s.AutoRenew && s.ExpiresAt.After(now) {
		return iapWriteNotice(ctx, q, user, noticeCancelScheduled, s.Env, "cancel_scheduled:"+line+":"+iapStamp(s.ExpiresAt), with("expiresAt", iapStamp(s.ExpiresAt)))
	}
	return nil
}

// iapUnreadNotices는 아직 읽지 않은 고지 수다. 샌드박스 거래의 고지는 스위치가 켜졌을 때만 센다.
func iapUnreadNotices(ctx context.Context, q dbtx, user int64, allowSandbox bool) (n int, err error) {
	err = q.QueryRow(ctx, "SELECT count(*)::int FROM iap_notices WHERE user_id=$1 AND read_at IS NULL AND ($2 OR env='production')", user, allowSandbox).Scan(&n)
	return
}

// iapNotices는 내 고지 목록이다(알림함). 최신순 100건.
//
// 응답: {"notices":[{"id":1,"kind":"payment_failed","template":"T7","templateVersion":1,"createdAt":"...","readAt":"...(읽은 것만)","params":{...}}]}
func (s *Server) iapNotices(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
	if err != nil {
		return err
	}
	rows, err := s.DB.Query(r.Context(), `SELECT id, kind, template, template_version, params, created_at, read_at FROM iap_notices
		WHERE user_id=$1 AND ($2 OR env='production') ORDER BY created_at DESC, id DESC LIMIT 100`, user, s.IAPSandbox)
	if err != nil {
		return err
	}
	defer rows.Close()
	list := []map[string]any{}
	for rows.Next() {
		var (
			id             int64
			kind, template string
			version        int
			raw            []byte
			created        time.Time
			read           *time.Time
			params         map[string]any
		)
		if err = rows.Scan(&id, &kind, &template, &version, &raw, &created, &read); err != nil {
			return err
		}
		if err = json.Unmarshal(raw, &params); err != nil || params == nil {
			params = map[string]any{}
		}
		item := map[string]any{"id": id, "kind": kind, "template": template, "templateVersion": version, "createdAt": iapStamp(created), "params": params}
		if read != nil {
			item["readAt"] = iapStamp(*read)
		}
		list = append(list, item)
	}
	if err = rows.Err(); err != nil {
		return err
	}
	writeJSON(w, 200, map[string]any{"notices": list})
	return nil
}

// iapNoticesRead는 고지를 읽음으로 표시한다. 요청: {"ids":[1,2]} 또는 {"all":true}. 응답: {"unread":n}
// 내 것이 아닌 번호는 조용히 지나친다(남의 고지가 있는지 알려 주지 않는다). 이미 읽은 것의 읽은 시각은 바꾸지 않는다.
func (s *Server) iapNoticesRead(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
	if err != nil {
		return err
	}
	var body struct {
		IDs []int64 `json:"ids"`
		All bool    `json:"all"`
	}
	if err = decode(r, &body); err != nil {
		return err
	}
	if len(body.IDs) > 500 {
		return bad
	}
	ctx := r.Context()
	if body.All {
		_, err = s.DB.Exec(ctx, "UPDATE iap_notices SET read_at=now() WHERE user_id=$1 AND read_at IS NULL", user)
	} else if len(body.IDs) > 0 {
		_, err = s.DB.Exec(ctx, "UPDATE iap_notices SET read_at=now() WHERE user_id=$1 AND read_at IS NULL AND id = ANY($2)", user, body.IDs)
	}
	if err != nil {
		return err
	}
	unread, err := iapUnreadNotices(ctx, s.DB, user, s.IAPSandbox)
	if err != nil {
		return err
	}
	writeJSON(w, 200, map[string]any{"unread": unread})
	return nil
}

// iapNoticeCounts는 최근 30일에 쓴 고지 수를 종류별로 센다(운영 숫자). 샌드박스는 뺀다.
func iapNoticeCounts(ctx context.Context, q dbtx) (map[string]int, error) {
	rows, err := q.Query(ctx, "SELECT kind, count(*)::int FROM iap_notices WHERE env='production' AND created_at > now() - interval '30 days' GROUP BY kind")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var (
			kind string
			n    int
		)
		if err = rows.Scan(&kind, &n); err != nil {
			return nil, err
		}
		out[kind] = n
	}
	return out, rows.Err()
}

// iapRenewalEvery는 갱신 예정 고지를 찾는 간격이다. 하루에 한 번이면 충분하지만, 한 회차가 실패했을 때 하루를 기다리지 않게 6시간으로 둔다.
// 같은 갱신은 유일 키로 한 번만 쓰이므로 자주 돌아도 결과는 같다.
const iapRenewalEvery = 6 * time.Hour

// iapRenewalNoticeDays는 갱신일 며칠 전부터 알릴지다(ADR-0003 L9·L12, 한국 기본 14일). IAP_RENEWAL_NOTICE_DAYS로 바꾼다.
func iapRenewalNoticeDays() int {
	if n, err := strconv.Atoi(os.Getenv("IAP_RENEWAL_NOTICE_DAYS")); err == nil && n > 0 && n <= 60 {
		return n
	}
	return 14
}

// iapRenewalDue는 갱신 예정 고지를 지금 찾을 차례인지 보고, 차례면 찾은 것으로 적는다(서버 한 대의 메모리로 센다).
func (s *Server) iapRenewalDue(now time.Time) bool {
	s.iapMu.Lock()
	defer s.iapMu.Unlock()
	if !s.iapRenewalAt.IsZero() && now.Sub(s.iapRenewalAt) < iapRenewalEvery {
		return false
	}
	s.iapRenewalAt = now
	return true
}

// iapNoteRenewals는 곧 갱신될 연 구독에 갱신 예정 고지(T4)를 쓴다. 쓴 줄 수를 돌려준다.
// 대상: 주인이 있고, 이용 중(paid)이고, 자동 갱신이 켜져 있고, 만료일(다음 결제일)이 앞으로 days일 안이고, 요금제 주기가 연인 구독.
// 월 구독은 보내지 않는다(L9). 주기를 모르는 요금제(iap_plans에 줄이 없음)도 보내지 않는다.
// 유일 키에 만료일이 들어 있어서 갱신될 때마다 한 번씩 쓰인다. 해지했다가 다시 켜도 같은 갱신이면 다시 쓰지 않는다.
func iapNoteRenewals(ctx context.Context, q dbtx, now time.Time, days int) (int, error) {
	tag, err := q.Exec(ctx, `INSERT INTO iap_notices (user_id, kind, template, params, env, dedupe_key)
		SELECT s.user_id, $1, 'T4',
			jsonb_build_object('route', s.route, 'productId', s.product_id, 'period', 'year',
				'expiresAt', to_char(s.expires_at AT TIME ZONE 'UTC', `+iapStampSQL+`)),
			s.env,
			$1 || ':' || s.route || ':' || s.original_id || ':' || to_char(s.expires_at AT TIME ZONE 'UTC', `+iapStampSQL+`)
		FROM iap_subscriptions s
		JOIN iap_plans pl ON pl.route=s.route AND pl.product_id=s.product_id AND pl.plan_id=s.plan_id AND pl.period='year'
		WHERE s.user_id IS NOT NULL AND s.state='paid' AND s.auto_renew AND s.grace_until IS NULL
			AND s.expires_at > $2 AND s.expires_at <= $2 + make_interval(days => $3)
		ON CONFLICT (user_id, dedupe_key) DO NOTHING`, noticeRenewalUpcoming, now, days)
	if err != nil {
		return 0, err
	}
	return int(tag.RowsAffected()), nil
}
