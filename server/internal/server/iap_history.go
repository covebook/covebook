package server

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 구매 내역, 사업자 정보, 빠진 알림 메우기, 밀린 일의 숫자.

// iapPurchases는 내 구매 내역을 최신순으로 준다(ADR-0003 L17). 원장의 줄 그대로이고 환불된 줄도 보인다.
// 금액은 스토어가 알려 준 거래에만 있다(구글 구매 조회에는 금액이 없다).
//
// 응답: {"purchases":[{"route","productId","kind","state":"paid|revoked","purchasedAt","revokedAt","shelves","year","overCap","currency","priceMilli"}]}
// 추가 선반은 shelves(상품이 주는 칸 수)와 year(칸이 열린 연도 책장)를 준다. 연도를 모르는 거래는 year가 없다.
// 그 해 3칸을 넘게 사서 칸을 주지 않은 거래는 "overCap":true다(환불 대상).
func (s *Server) iapPurchases(w http.ResponseWriter, r *http.Request) error {
	user, err := s.user(r)
	if err != nil {
		return err
	}
	ctx := r.Context()
	rows, err := s.DB.Query(ctx, `SELECT b.route, b.product_id, b.kind, b.state, b.purchased_at, b.revoked_at, coalesce(p.shelves,0), coalesce(b.currency,''), b.price_milli, b.shelf_year, b.over_cap
		FROM iap_purchases b LEFT JOIN iap_products p ON p.route=b.route AND p.product_id=b.product_id
		WHERE b.user_id=$1 AND ($2 OR b.env='production')
		ORDER BY b.purchased_at DESC, b.id DESC LIMIT 200`, user, s.IAPSandbox)
	if err != nil {
		return err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var route, product, kind, state, currency string
		var purchased time.Time
		var revoked *time.Time
		var shelves int
		var price *int64
		var year *int
		var overCap bool
		if err = rows.Scan(&route, &product, &kind, &state, &purchased, &revoked, &shelves, &currency, &price, &year, &overCap); err != nil {
			return err
		}
		item := map[string]any{"route": route, "productId": product, "kind": kind, "state": state, "purchasedAt": purchased.UTC().Format(time.RFC3339)}
		if revoked != nil {
			item["revokedAt"] = revoked.UTC().Format(time.RFC3339)
		}
		if kind == string(iap.KindProduct) && shelves > 0 {
			item["shelves"] = shelves
			if year != nil {
				item["year"] = *year
			}
			if overCap {
				item["overCap"] = true
			}
		}
		if currency != "" && price != nil {
			item["currency"], item["priceMilli"] = currency, *price
		}
		out = append(out, item)
	}
	if err = rows.Err(); err != nil {
		return err
	}
	writeJSON(w, 200, map[string]any{"purchases": out})
	return nil
}

// iapSellerKeys는 앱에 보여 줄 사업자 정보의 칸이다(ADR-0003 L14): 상호, 대표자, 주소, 전화, 전자우편, 사업자등록번호, 통신판매업 신고번호.
var iapSellerKeys = []string{"name", "owner", "address", "phone", "email", "bizNo", "saleNo"}

// iapSeller는 환경 변수 IAP_SELLER_JSON(JSON 객체)에서 사업자 정보를 읽는다. 저장소가 공개라 값을 코드에 적지 않는다.
// 없거나 깨졌으면 nil이다. 아는 칸의 글자 값만 내보낸다.
func iapSeller() map[string]string {
	raw := os.Getenv("IAP_SELLER_JSON")
	if raw == "" {
		return nil
	}
	var in map[string]any
	if err := json.Unmarshal([]byte(raw), &in); err != nil {
		log.Printf("iap seller info ignored: IAP_SELLER_JSON is not a JSON object")
		return nil
	}
	out := map[string]string{}
	for _, k := range iapSellerKeys {
		if v, ok := in[k].(string); ok && v != "" {
			out[k] = v
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// iapCatchUpEvery는 스토어의 목록(애플 알림 이력, 구글 무효 구매)을 받아 빈 곳을 메우는 간격이다.
// 서버 한 대의 메모리로 센다. 서버를 다시 켜면 바로 한 번 돈다. 여러 대면 각자 돌지만 같은 것을 다시 넣어도 결과가 같다.
const iapCatchUpEvery = 6 * time.Hour

// iapCatchUpDue는 이 경로의 메우기를 지금 돌릴 차례인지 보고, 차례면 돌린 것으로 적는다.
func (s *Server) iapCatchUpDue(route iap.Route, now time.Time) bool {
	s.iapMu.Lock()
	defer s.iapMu.Unlock()
	if last, ok := s.iapCatchUpAt[route]; ok && now.Sub(last) < iapCatchUpEvery {
		return false
	}
	if s.iapCatchUpAt == nil {
		s.iapCatchUpAt = map[iap.Route]time.Time{} // nil 맵에는 쓸 수 없다
	}
	s.iapCatchUpAt[route] = now
	return true
}

// iapCatchUpSince는 어디서부터 다시 받을지 정한다.
//   - 기본은 7일 전: 애플의 재시도가 약 6.5일에 걸쳐 있어, 그 안에 못 받은 것은 이력으로만 되찾는다.
//   - 마지막으로 알림을 받은 지 오래됐으면(서버가 오래 죽어 있었으면) 그 하루 전부터.
//   - 30일보다 멀리 가지 않는다(구글 무효 구매 목록의 한도).
func iapCatchUpSince(ctx context.Context, q dbtx, route iap.Route, now time.Time) time.Time {
	since := now.Add(-7 * 24 * time.Hour)
	var last *time.Time
	if err := q.QueryRow(ctx, "SELECT max(received_at) FROM iap_notifications WHERE route=$1", string(route)).Scan(&last); err == nil && last != nil {
		if t := last.Add(-24 * time.Hour); t.Before(since) {
			since = t
		}
	}
	if floor := now.Add(-30 * 24 * time.Hour); since.Before(floor) {
		since = floor
	}
	return since
}

// iapCatchUp은 스토어가 가진 목록으로 빠진 것을 메운다. 실패해도 다른 대조는 계속 돈다.
//   - 알림 이력: 우리가 못 받은 알림을 알림 표에 넣는다. 처리는 이어지는 알림 처리 단계가 한다. 이미 받은 것은 유일 키가 거른다.
//   - 무효 구매 목록: 환불을 원장에 반영한다. 환불 알림이 빠졌을 때의 대비다.
func (s *Server) iapCatchUp(ctx context.Context, res *iapSweepResult) {
	now := time.Now().UTC()
	for route, store := range s.IAP {
		history, hasHistory := store.(iap.NoticeHistory)
		voided, hasVoided := store.(iap.VoidedLister)
		if (!hasHistory && !hasVoided) || !s.iapCatchUpDue(route, now) {
			continue
		}
		since := iapCatchUpSince(ctx, s.DB, route, now)
		if hasHistory {
			storeCtx, cancel := context.WithTimeout(ctx, 2*iapStoreTimeout)
			past, skipped, err := history.NoticeHistory(storeCtx, since)
			cancel()
			if err != nil {
				log.Printf("iap notification history failed: route=%s err=%v", route, err)
			}
			if skipped > 0 {
				log.Printf("iap notification history: route=%s unreadable=%d", route, skipped)
			}
			for _, p := range past {
				inserted, err := iapRecordNotification(ctx, s.DB, p.Notice, p.Payload)
				if err != nil {
					log.Printf("iap notification history save failed: route=%s err=%v", route, err)
					break
				}
				if !inserted {
					continue
				}
				res.Backfilled++
				if p.Notice.Test {
					_ = iapFinishNotification(ctx, s.DB, route, p.Notice.ID, "ignored", "연결 확인용 알림")
				}
			}
		}
		if hasVoided {
			storeCtx, cancel := context.WithTimeout(ctx, 2*iapStoreTimeout)
			list, err := voided.Voided(storeCtx, since)
			cancel()
			if err != nil {
				log.Printf("iap voided list failed: route=%s err=%v", route, err)
			}
			for _, v := range list {
				if s.iapApplyVoided(ctx, store, v, now) {
					res.Voided++
				}
			}
		}
	}
	if res.Backfilled > 0 || res.Voided > 0 {
		log.Printf("iap catch-up: backfilled_notifications=%d voided_purchases=%d", res.Backfilled, res.Voided)
	}
}

// iapApplyVoided는 스토어가 환불했다고 알려 준 구매 한 건을 원장에 반영한다. 새로 바뀐 줄이 있으면 true다.
// 목록에는 구독인지 한 번 사는 상품인지가 없다. 한 번 사는 상품은 구매 토큰이, 구독의 갱신 거래는 주문 ID가 원장의 키라서 둘 다 찾는다.
// 우리 원장에 없는 구매(다른 서버 환경, 지급 전에 환불)는 바뀌는 줄이 없어 그냥 지나간다.
func (s *Server) iapApplyVoided(ctx context.Context, store iap.Store, v iap.VoidedPurchase, now time.Time) bool {
	at := v.VoidedAt
	if at.IsZero() {
		at = now
	}
	changed := false
	for _, key := range []string{v.Token, v.OrderID} {
		if key == "" {
			continue
		}
		c, err := iapRevokePurchase(ctx, s.DB, store.Route(), key, at)
		if err != nil {
			log.Printf("iap voided apply failed: route=%s err=%v", store.Route(), err)
			return changed
		}
		changed = changed || c
	}
	if !changed {
		return false
	}
	// 구독의 거래였으면 구독 상태도 스토어의 답으로 맞춘다
	var isSub bool
	if err := s.DB.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM iap_subscriptions WHERE route=$1 AND original_id=$2)", string(store.Route()), v.Token).Scan(&isSub); err == nil && isSub {
		if _, err = s.iapSyncSubscription(ctx, store, v.Token); err != nil {
			log.Printf("iap voided subscription refresh failed: route=%s err=%v", store.Route(), err)
		}
	}
	return true
}

// iapBacklog는 밀린 일의 숫자다(이슈 #39). 계속 크면 알림이 안 오거나 스토어 조회가 실패하고 있다는 신호다.
type iapBacklog struct {
	PendingNotices       int   `json:"pendingNotifications"`   // 받았지만 아직 처리하지 않은 알림
	FailedNotices        int   `json:"failedNotifications"`    // 처리에 실패해 다시 시도할 알림
	Unconfirmed          int   `json:"unconfirmedPurchases"`   // 지급했는데 스토어 확인을 못 마친 구매(구글은 3일 안에 해야 한다)
	OldestPendingSecs    int64 `json:"oldestPendingSeconds"`   // 가장 오래 기다린 알림의 나이
	Subscriptions        int   `json:"activeSubscriptions"`    // 지금 유효한 구독 줄기(운영 환경)
	RevokedPurchases     int   `json:"revokedPurchases30Days"` // 최근 30일에 환불된 거래
	ShelfOverCap         int   `json:"shelfOverCap"`           // 한 연도 책장에서 3칸을 넘게 사서 칸을 주지 않은 거래 중 돈이 아직 돌아가지 않은 것(운영 환경). 애플 거래와 구글 환불 요청 실패(D1)
	ShelfOverCapRefunded int   `json:"shelfOverCapRefunded"`   // 넘게 산 구글 거래 중 서버가 환불을 요청한 것(운영 환경)
	ShelfOverCapApple    int   `json:"shelfOverCapApple"`      // 넘게 산 애플 거래 중 아직 환불되지 않은 것(운영 환경). 개발자가 환불할 수 없어 사용자가 애플에 요청해야 한다
	ShelfNoYear          int   `json:"shelfNoYear"`            // 어느 해 책장인지 모르는 선반 거래(운영 환경, 환불 안 됨). 칸을 주지 않았다. 문의를 받거나 환불할 대상
}

func iapBacklogNow(ctx context.Context, q dbtx) (b iapBacklog, err error) {
	err = q.QueryRow(ctx, `SELECT
		(SELECT count(*) FROM iap_notifications WHERE result='received'),
		(SELECT count(*) FROM iap_notifications WHERE result='failed' AND received_at > now() - interval '8 days'),
		(SELECT count(*) FROM iap_purchases WHERE confirmed_at IS NULL AND state='paid'),
		coalesce((SELECT extract(epoch FROM now() - min(received_at)) FROM iap_notifications
			WHERE result IN ('received','failed') AND received_at > now() - interval '8 days'), 0)::bigint,
		(SELECT count(*) FROM iap_subscriptions WHERE state='paid' AND env='production' AND coalesce(grace_until, expires_at) > now()),
		(SELECT count(*) FROM iap_purchases WHERE state='revoked' AND revoked_at > now() - interval '30 days'),
		(SELECT count(*) FROM iap_purchases WHERE over_cap AND state='paid' AND env='production' AND refund_requested_at IS NULL),
		(SELECT count(*) FROM iap_purchases WHERE over_cap AND env='production' AND refund_requested_at IS NOT NULL),
		(SELECT count(*) FROM iap_purchases WHERE over_cap AND state='paid' AND env='production' AND route='apple'),
		(SELECT count(*) FROM iap_purchases WHERE kind='product' AND state='paid' AND env='production' AND shelf_year IS NULL)`).
		Scan(&b.PendingNotices, &b.FailedNotices, &b.Unconfirmed, &b.OldestPendingSecs, &b.Subscriptions, &b.RevokedPurchases,
			&b.ShelfOverCap, &b.ShelfOverCapRefunded, &b.ShelfOverCapApple, &b.ShelfNoYear)
	return
}

// iapLogSweep은 한 번 돈 결과와 밀린 일을 한 줄로 남긴다. 한 일도 밀린 일도 없으면 한 시간에 한 번만 남긴다.
func (s *Server) iapLogSweep(ctx context.Context, res iapSweepResult) {
	b, err := iapBacklogNow(ctx, s.DB)
	if err != nil {
		log.Printf("iap backlog query failed: %v", err)
		return
	}
	quiet := res == iapSweepResult{} && b.PendingNotices == 0 && b.FailedNotices == 0 && b.Unconfirmed == 0
	now := time.Now()
	s.iapMu.Lock()
	skip := quiet && now.Sub(s.iapLoggedAt) < time.Hour
	if !skip {
		s.iapLoggedAt = now
	}
	s.iapMu.Unlock()
	if skip {
		return
	}
	log.Printf("iap sweep: notices=%d notices_failed=%d confirmed=%d refreshed=%d backfilled=%d voided=%d refunds=%d | backlog: pending=%d failed=%d unconfirmed=%d oldest_pending=%ds shelf_over_cap=%d shelf_over_cap_apple=%d shelf_no_year=%d",
		res.Notices, res.NoticesFailed, res.Confirmed, res.Refreshed, res.Backfilled, res.Voided, res.Refunds,
		b.PendingNotices, b.FailedNotices, b.Unconfirmed, b.OldestPendingSecs, b.ShelfOverCap, b.ShelfOverCapApple, b.ShelfNoYear)
}

// iapAdminStats는 밀린 일의 숫자를 준다. 운영자 토큰이 없으면 없는 경로처럼 답한다(community.go의 adminOK와 같은 방식).
func (s *Server) iapAdminStats(w http.ResponseWriter, r *http.Request) error {
	if !adminOK(r) {
		return notFound
	}
	b, err := iapBacklogNow(r.Context(), s.DB)
	if err != nil {
		return err
	}
	writeJSON(w, 200, b)
	return nil
}
