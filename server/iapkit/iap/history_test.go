package iap

import (
	"context"
	"errors"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/awa/go-iap/appstore"
	"github.com/awa/go-iap/appstore/api"
	"google.golang.org/api/androidpublisher/v3"
)

func TestAppleNoticeHistory(t *testing.T) {
	var since int64
	// 서명된 본문마다 다른 알림이 풀리게 한다. "other"는 다른 앱, "broken"은 서명 실패다
	a := &Apple{bundleID: "app.covebook",
		api: fakeAppleAPI{since: &since, tx: &api.JWSTransaction{TransactionID: "300", OriginalTransactionId: "100", Type: api.AutoRenewable},
			history: []api.NotificationHistoryResponseItem{{SignedPayload: "u-1"}, {SignedPayload: "other"}, {SignedPayload: "broken"}, {SignedPayload: "u-2"}}},
		verifyNotice: func(signed string, into *appstore.SubscriptionNotificationV2DecodedPayload) error {
			if signed == "broken" {
				return errors.New("bad signature")
			}
			bundle := "app.covebook"
			if signed == "other" {
				bundle = "com.other"
			}
			*into = appstore.SubscriptionNotificationV2DecodedPayload{NotificationType: "DID_RENEW", NotificationUUID: signed,
				Data: appstore.SubscriptionNotificationV2Data{BundleID: bundle, Environment: "Production", SignedTransactionInfo: "signed"}}
			return nil
		}}
	got, skipped, err := a.NoticeHistory(context.Background(), time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	// 다른 앱의 알림은 조용히 빼고, 풀지 못한 것은 건수로 알린다
	if len(got) != 2 || skipped != 1 || got[0].Notice.ID != "u-1" || got[1].Notice.ID != "u-2" {
		t.Fatalf("이력: %+v skipped=%d", got, skipped)
	}
	if got[0].Notice.OriginalID != "100" || got[0].Payload != `{"signedPayload":"u-1"}` {
		t.Fatalf("알림 내용: %+v", got[0])
	}
	// 수신 경로가 받는 본문과 같은 모양이라 다시 풀 수 있다
	if n, err := a.ParseNotice([]byte(got[1].Payload)); err != nil || n.ID != "u-2" {
		t.Fatalf("다시 풀기: %+v %v", n, err)
	}
	// 애플 이력은 180일까지다. 더 옛날을 물어도 180일로 줄인다
	if _, _, err = a.NoticeHistory(context.Background(), time.Now().Add(-400*24*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if age := time.Since(time.UnixMilli(since)); age > 181*24*time.Hour || age < 179*24*time.Hour {
		t.Fatalf("시작 시각이 180일이 아님: %v", age)
	}
	// 조회 실패는 오류로 올린다
	a.api = fakeAppleAPI{lookup: errors.New("timeout")}
	if _, _, err = a.NoticeHistory(context.Background(), time.Now()); err == nil {
		t.Fatal("조회 실패인데 통과")
	}
}

func TestGoogleVoided(t *testing.T) {
	g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{voided: map[string]*androidpublisher.VoidedPurchasesListResponse{
		"": {VoidedPurchases: []*androidpublisher.VoidedPurchase{{PurchaseToken: "tok-1", OrderId: "GPA.1", VoidedTimeMillis: 1_800_000_000_000}, nil, {OrderId: "토큰 없음"}},
			TokenPagination: &androidpublisher.TokenPagination{NextPageToken: "p2"}},
		"p2": {VoidedPurchases: []*androidpublisher.VoidedPurchase{{PurchaseToken: "tok-2", OrderId: "GPA.2"}}},
	}}}
	got, err := g.Voided(context.Background(), time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Token != "tok-1" || got[0].OrderID != "GPA.1" || got[0].VoidedAt.IsZero() || got[1].Token != "tok-2" || !got[1].VoidedAt.IsZero() {
		t.Fatalf("무효 구매: %+v", got)
	}
	// 오류에 구매 토큰이 든 주소가 남지 않는다
	g.api = fakeGoogleAPI{err: &url.Error{Op: "Get", URL: "https://androidpublisher.googleapis.com/x?token=secret-token", Err: errors.New("context deadline exceeded")}}
	if _, err = g.Voided(context.Background(), time.Now()); err == nil || strings.Contains(err.Error(), "secret-token") {
		t.Fatalf("오류: %v", err)
	}
}
