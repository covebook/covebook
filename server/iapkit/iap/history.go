package iap

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/awa/go-iap/appstore/api"
	"github.com/awa/go-iap/playstore"
)

// 알림은 빠질 수 있다. 스토어가 "보냈던 것"과 "환불한 것"의 목록을 따로 주므로 주기적으로 받아 빈 곳을 메운다.
// 모든 스토어가 가진 기능이 아니라서 Store에 넣지 않고 선택 인터페이스로 둔다.
// 받는 쪽은 `h, ok := store.(iap.NoticeHistory)`로 있는지 물어본다(Java의 instanceof 자리).

// PastNotice는 스토어가 전에 보낸 알림 한 건이다. Payload는 알림 수신 경로가 받는 본문과 같은 모양이다.
type PastNotice struct {
	Notice  Notice
	Payload string
}

// NoticeHistory는 보냈던 알림을 다시 내줄 수 있는 스토어다(애플 Get Notification History).
type NoticeHistory interface {
	// NoticeHistory는 since부터 지금까지 스토어가 보낸 알림을 돌려준다. skipped는 풀지 못해 건너뛴 건수다.
	NoticeHistory(ctx context.Context, since time.Time) (notices []PastNotice, skipped int, err error)
}

// VoidedPurchase는 스토어가 환불·취소한 구매 한 건이다.
type VoidedPurchase struct {
	Token    string // 구매 토큰
	OrderID  string
	VoidedAt time.Time
}

// VoidedLister는 환불·취소된 구매 목록을 내줄 수 있는 스토어다(구글 Voided Purchases API).
type VoidedLister interface {
	Voided(ctx context.Context, since time.Time) ([]VoidedPurchase, error)
}

var (
	_ NoticeHistory = (*Apple)(nil)
	_ VoidedLister  = (*Google)(nil)
	_ NoticeHistory = (*Fake)(nil)
	_ VoidedLister  = (*Fake)(nil)
)

// appleHistoryPause는 이력의 쪽과 쪽 사이에 쉬는 시간이다(애플 한도: 엔드포인트당 초당 50회).
const appleHistoryPause = 100 * time.Millisecond

// NoticeHistory는 애플이 since 이후에 보낸 알림을 받는다. 우리가 받았든 못 받았든 전부 들어 있다.
// 운영 환경의 이력만 본다(라이브러리의 대체 클라이언트가 이력은 운영에만 묻는다). 샌드박스 알림은 메우지 않는다.
// 애플이 주는 이력은 최근 180일까지다.
func (a *Apple) NoticeHistory(ctx context.Context, since time.Time) ([]PastNotice, int, error) {
	now := time.Now()
	if limit := now.Add(-180 * 24 * time.Hour); since.Before(limit) {
		since = limit
	}
	items, err := a.api.GetAllNotificationHistory(ctx, api.NotificationHistoryRequest{StartDate: since.UnixMilli(), EndDate: now.UnixMilli()}, appleHistoryPause)
	if err != nil {
		return nil, 0, fmt.Errorf("apple 알림 이력 조회: %w", err)
	}
	var out []PastNotice
	skipped := 0
	for _, item := range items {
		// 수신 경로가 받는 본문과 같은 모양으로 만들어 같은 해석 함수를 거친다(서명·번들 확인 포함)
		body, _ := json.Marshal(map[string]string{"signedPayload": item.SignedPayload})
		n, err := a.ParseNotice(body)
		if err != nil {
			if !errors.Is(err, ErrWrongApp) {
				skipped++
			}
			continue
		}
		out = append(out, PastNotice{Notice: n, Payload: string(body)})
	}
	return out, skipped, nil
}

// googleVoidedPages는 한 번에 넘길 쪽 수의 상한이다(한 쪽에 최대 1000건). 넘은 쪽은 이번에 받지 않는다. 다음 대조도 같은 시작 시각부터 처음 쪽을 다시 받으므로 이어지지 않는다(6시간 동안 1000건×상한을 넘는 환불이 올 때만 문제다).
const googleVoidedPages = 20

// Voided는 구글이 since 이후에 환불·취소한 구매(구독 포함)를 받는다. 구글이 주는 목록은 최근 30일까지다.
// 목록에는 구독인지 한 번 사는 상품인지가 없다. 받는 쪽이 구매 토큰과 주문 ID 둘 다로 원장을 찾는다.
func (g *Google) Voided(ctx context.Context, since time.Time) ([]VoidedPurchase, error) {
	now := time.Now()
	if limit := now.Add(-30*24*time.Hour + time.Hour); since.Before(limit) {
		since = limit
	}
	var out []VoidedPurchase
	token := ""
	for page := 0; page < googleVoidedPages; page++ {
		rsp, err := g.api.VoidedPurchases(ctx, g.packageName, since.UnixMilli(), now.UnixMilli(), 1000, token, 0, playstore.VoidedPurchaseTypeWithSubscription)
		if err != nil {
			return nil, fmt.Errorf("google 무효 구매 목록: %w", googleErr(err))
		}
		for _, v := range rsp.VoidedPurchases {
			if v == nil || v.PurchaseToken == "" {
				continue
			}
			out = append(out, VoidedPurchase{Token: v.PurchaseToken, OrderID: v.OrderId, VoidedAt: msTime(v.VoidedTimeMillis)})
		}
		if rsp.TokenPagination == nil || rsp.TokenPagination.NextPageToken == "" {
			break
		}
		token = rsp.TokenPagination.NextPageToken
	}
	return out, nil
}

// NoticeHistory는 History에 넣어 둔 알림을 돌려준다(시험용).
func (f *Fake) NoticeHistory(context.Context, time.Time) ([]PastNotice, int, error) {
	if f.Err != nil {
		return nil, 0, f.Err
	}
	out := make([]PastNotice, 0, len(f.History))
	for _, n := range f.History {
		n.Route = f.R
		body, _ := json.Marshal(n)
		out = append(out, PastNotice{Notice: n, Payload: string(body)})
	}
	return out, 0, nil
}

// Voided는 VoidedList에 넣어 둔 목록을 돌려준다(시험용).
func (f *Fake) Voided(context.Context, time.Time) ([]VoidedPurchase, error) {
	if f.Err != nil {
		return nil, f.Err
	}
	return f.VoidedList, nil
}
