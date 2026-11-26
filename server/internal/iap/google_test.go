package iap

import (
	"context"
	"encoding/base64"
	"errors"
	"net/url"
	"strings"
	"testing"

	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/googleapi"
)

type fakeGoogleAPI struct {
	sub   *androidpublisher.SubscriptionPurchaseV2
	prod  *androidpublisher.ProductPurchaseV2
	err   error
	calls *[]string // 확인·소비 호출 기록
}

func (f fakeGoogleAPI) AcknowledgeSubscription(_ context.Context, pkg, id, token string, _ *androidpublisher.SubscriptionPurchasesAcknowledgeRequest) error {
	*f.calls = append(*f.calls, "ack-sub "+pkg+" "+id+" "+token)
	return f.err
}
func (f fakeGoogleAPI) AcknowledgeProduct(_ context.Context, pkg, id, token, _ string) error {
	*f.calls = append(*f.calls, "ack-product "+pkg+" "+id+" "+token)
	return f.err
}
func (f fakeGoogleAPI) ConsumeProduct(_ context.Context, pkg, id, token string) error {
	*f.calls = append(*f.calls, "consume "+pkg+" "+id+" "+token)
	return f.err
}
func (f fakeGoogleAPI) Refund(_ context.Context, pkg, order string) error {
	*f.calls = append(*f.calls, "refund "+pkg+" "+order)
	return f.err
}

func (f fakeGoogleAPI) VerifySubscriptionV2(context.Context, string, string) (*androidpublisher.SubscriptionPurchaseV2, error) {
	return f.sub, f.err
}
func (f fakeGoogleAPI) VerifyProductV2(context.Context, string, string) (*androidpublisher.ProductPurchaseV2, error) {
	return f.prod, f.err
}

func TestGoogleSubscription(t *testing.T) {
	g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{sub: &androidpublisher.SubscriptionPurchaseV2{
		SubscriptionState: "SUBSCRIPTION_STATE_ACTIVE", StartTime: "2026-11-18T03:00:00.5Z", RegionCode: "KR",
		ExternalAccountIdentifiers: &androidpublisher.ExternalAccountIdentifiers{ObfuscatedExternalAccountId: "u-1"},
		TestPurchase:               &androidpublisher.TestPurchase{},
		LineItems: []*androidpublisher.SubscriptionPurchaseLineItem{{
			ProductId: "plus", ExpiryTime: "2026-12-18T12:00:00+09:00", LatestSuccessfulOrderId: "GPA.1",
			OfferDetails: &androidpublisher.OfferDetails{BasePlanId: "monthly"},
		}},
	}}}
	p, err := g.Lookup(context.Background(), Ref{Kind: KindSubscription, ID: "tok"})
	if err != nil {
		t.Fatal(err)
	}
	if p.Route != RouteGoogle || p.TransactionID != "GPA.1" || p.OriginalTransactionID != "tok" || p.BundleID != "app.covebook" {
		t.Fatalf("식별 값이 다름: %+v", p)
	}
	if p.ProductID != "plus" || p.PlanID != "monthly" || p.AccountToken != "u-1" || p.Country != "KR" {
		t.Fatalf("상품·계정 값이 다름: %+v", p)
	}
	if p.State != StatePaid || p.Env != EnvSandbox || p.Acknowledged {
		t.Fatalf("상태·환경이 다름: %+v", p)
	}
	// 다른 시간대로 와도 UTC로 맞춘다
	if got := p.ExpiresAt.Format("2006-01-02T15:04:05Z07:00"); got != "2026-12-18T03:00:00Z" {
		t.Fatalf("만료 시각: %s", got)
	}
	if p.PriceMilli != 0 || p.Currency != "" {
		t.Fatalf("구글 조회에는 금액이 없다: %+v", p)
	}
}

func TestGoogleSubscriptionStates(t *testing.T) {
	for state, want := range map[string]State{
		"SUBSCRIPTION_STATE_ACTIVE":                    StatePaid,
		"SUBSCRIPTION_STATE_IN_GRACE_PERIOD":           StatePaid,
		"SUBSCRIPTION_STATE_CANCELED":                  StatePaid,
		"SUBSCRIPTION_STATE_PENDING":                   StatePending,
		"SUBSCRIPTION_STATE_ON_HOLD":                   StateInactive,
		"SUBSCRIPTION_STATE_PAUSED":                    StateInactive,
		"SUBSCRIPTION_STATE_EXPIRED":                   StateInactive,
		"SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED": StateInactive,
		"SUBSCRIPTION_STATE_UNSPECIFIED":               StateInactive,
		"나중에 생긴 상태":                                    StateInactive,
		"":                                             StateInactive,
	} {
		if got := subscriptionState(state); got != want {
			t.Errorf("%q: 기대 %s, 실제 %s", state, want, got)
		}
	}
}

func TestGoogleProduct(t *testing.T) {
	prod := func(state string) *androidpublisher.ProductPurchaseV2 {
		return &androidpublisher.ProductPurchaseV2{
			OrderId: "GPA.2", ObfuscatedExternalAccountId: "u-1", RegionCode: "KR", PurchaseCompletionTime: "2026-11-18T03:00:00Z",
			PurchaseStateContext: &androidpublisher.PurchaseStateContext{PurchaseState: state},
			ProductLineItem:      []*androidpublisher.ProductLineItem{{ProductId: "shelf.1"}},
		}
	}
	for state, want := range map[string]State{"PURCHASED": StatePaid, "PENDING": StatePending, "CANCELLED": StateRevoked, "PURCHASE_STATE_UNSPECIFIED": StateInactive} {
		g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{prod: prod(state)}}
		p, err := g.Lookup(context.Background(), Ref{Kind: KindProduct, ID: "tok"})
		if err != nil {
			t.Fatal(err)
		}
		if p.State != want || p.ProductID != "shelf.1" || p.TransactionID != "GPA.2" || p.Env != EnvProduction {
			t.Errorf("%s: %+v", state, p)
		}
	}
	// 상태 정보가 통째로 없으면 지급하지 않는 쪽
	noState := prod("")
	noState.PurchaseStateContext = nil
	p, _ := (&Google{api: fakeGoogleAPI{prod: noState}}).Lookup(context.Background(), Ref{Kind: KindProduct, ID: "tok"})
	if p.State != StateInactive {
		t.Fatalf("상태가 없는데 %s", p.State)
	}
}

func TestGoogleErrors(t *testing.T) {
	ctx := context.Background()
	for _, code := range []int{404, 410} {
		_, err := (&Google{api: fakeGoogleAPI{err: &googleapi.Error{Code: code}}}).Lookup(ctx, Ref{Kind: KindProduct, ID: "x"})
		if !errors.Is(err, ErrNotFound) {
			t.Fatalf("%d가 ErrNotFound가 아님: %v", code, err)
		}
	}
	// 권한 오류·장애는 "없는 거래"가 아니다
	_, err := (&Google{api: fakeGoogleAPI{err: &googleapi.Error{Code: 503}}}).Lookup(ctx, Ref{Kind: KindSubscription, ID: "x"})
	if err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("장애가 없는 거래로 처리됨: %v", err)
	}
	// 종류를 안 알려 주면 조회하지 않는다
	if _, err := (&Google{api: fakeGoogleAPI{}}).Lookup(ctx, Ref{ID: "x"}); err == nil {
		t.Fatal("종류 없이 조회됨")
	}
	// 항목 수가 예상과 다르면 멈춘다
	_, err = (&Google{api: fakeGoogleAPI{sub: &androidpublisher.SubscriptionPurchaseV2{}}}).Lookup(ctx, Ref{Kind: KindSubscription, ID: "x"})
	if err == nil {
		t.Fatal("항목이 없는 구독이 통과됨")
	}
}

func TestGoogleSubscriptionStatus(t *testing.T) {
	sub := func(state string, autoRenew bool) *androidpublisher.SubscriptionPurchaseV2 {
		return &androidpublisher.SubscriptionPurchaseV2{SubscriptionState: state, StartTime: "2026-11-18T03:00:00Z",
			LineItems: []*androidpublisher.SubscriptionPurchaseLineItem{{ProductId: "plus", ExpiryTime: "2026-12-18T03:00:00Z",
				AutoRenewingPlan: &androidpublisher.AutoRenewingPlan{AutoRenewEnabled: autoRenew}}}}
	}
	ctx := context.Background()
	// 이미 확인된 구독은 그렇게 표시된다
	acked := sub("SUBSCRIPTION_STATE_ACTIVE", true)
	acked.AcknowledgementState = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"
	if p, _ := (&Google{api: fakeGoogleAPI{sub: acked}}).Subscription(ctx, "tok"); !p.Acknowledged {
		t.Fatal("확인된 구독이 미확인으로 나옴")
	}
	// 유예 중: 구글이 늘려 준 만료 시각이 유예의 끝이다
	p, err := (&Google{api: fakeGoogleAPI{sub: sub("SUBSCRIPTION_STATE_IN_GRACE_PERIOD", true)}}).Subscription(ctx, "tok")
	if err != nil || p.State != StatePaid || !p.AutoRenew || !p.GraceUntil.Equal(p.ExpiresAt) || p.OriginalTransactionID != "tok" {
		t.Fatalf("유예: %+v %v", p, err)
	}
	// 해지 예약: 자동 갱신 꺼짐, 유예 아님
	p, _ = (&Google{api: fakeGoogleAPI{sub: sub("SUBSCRIPTION_STATE_CANCELED", false)}}).Subscription(ctx, "tok")
	if p.State != StatePaid || p.AutoRenew || !p.GraceUntil.IsZero() {
		t.Fatalf("해지 예약: %+v", p)
	}
}

func TestGoogleConfirm(t *testing.T) {
	ctx := context.Background()
	var calls []string
	g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{calls: &calls}}
	for _, c := range []struct {
		ref     Ref
		consume bool
		want    string
	}{
		{Ref{Kind: KindSubscription, ID: "t1"}, false, "ack-sub app.covebook p t1"},
		{Ref{Kind: KindProduct, ID: "t2"}, true, "consume app.covebook p t2"},
		{Ref{Kind: KindProduct, ID: "t3"}, false, "ack-product app.covebook p t3"},
	} {
		calls = nil
		if err := g.Confirm(ctx, c.ref, "p", c.consume); err != nil || len(calls) != 1 || calls[0] != c.want {
			t.Errorf("%+v: %v %v", c, calls, err)
		}
	}
	// 구독을 소비하라는 것, 종류가 없는 것은 스토어를 부르지 않고 거절한다
	calls = nil
	if err := g.Confirm(ctx, Ref{Kind: KindSubscription, ID: "t"}, "p", true); err == nil || len(calls) != 0 {
		t.Fatal("구독 소비가 통과", calls)
	}
	if err := g.Confirm(ctx, Ref{ID: "t"}, "p", false); err == nil || len(calls) != 0 {
		t.Fatal("종류 없는 확인이 통과", calls)
	}
	// 스토어가 실패하면 오류를 돌려준다(부르는 쪽이 다시 시도한다)
	g = &Google{packageName: "app.covebook", api: fakeGoogleAPI{calls: &calls, err: &googleapi.Error{Code: 503}}}
	if err := g.Confirm(ctx, Ref{Kind: KindProduct, ID: "t"}, "p", true); err == nil {
		t.Fatal("실패가 숨겨짐")
	}
}

func googlePush(messageID, inner string) []byte {
	return []byte(`{"message":{"data":"` + base64.StdEncoding.EncodeToString([]byte(inner)) + `","messageId":"` + messageID + `"},"subscription":"projects/x/subscriptions/y"}`)
}

func TestGoogleParseNotice(t *testing.T) {
	g := &Google{packageName: "app.covebook"}
	n, err := g.ParseNotice(googlePush("m-1", `{"version":"1.0","packageName":"app.covebook","eventTimeMillis":"1800000000000","subscriptionNotification":{"version":"1.0","notificationType":2,"purchaseToken":"tok"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if n.Route != RouteGoogle || n.ID != "m-1" || n.Type != "subscription/2" || n.SentAt.IsZero() || n.Test || n.Voided {
		t.Fatalf("구독 알림: %+v", n)
	}
	if *n.Target != (Ref{Kind: KindSubscription, ID: "tok"}) || n.OriginalID != "tok" {
		t.Fatalf("대상: %+v", n.Target)
	}
	n, err = g.ParseNotice(googlePush("m-2", `{"packageName":"app.covebook","oneTimeProductNotification":{"notificationType":1,"purchaseToken":"tok2","sku":"shelf"}}`))
	if err != nil || n.Type != "product/1" || *n.Target != (Ref{Kind: KindProduct, ID: "tok2"}) || n.OriginalID != "" {
		t.Fatalf("상품 알림: %+v %v", n, err)
	}
	// 환불: 구독이면 구독 1건로, 한 번 사는 상품이면 상품으로
	n, err = g.ParseNotice(googlePush("m-3", `{"packageName":"app.covebook","voidedPurchaseNotification":{"purchaseToken":"tok3","orderId":"GPA.1","productType":1,"refundType":1}}`))
	if err != nil || !n.Voided || n.OrderID != "GPA.1" || *n.Target != (Ref{Kind: KindSubscription, ID: "tok3"}) || n.OriginalID != "tok3" {
		t.Fatalf("구독 환불: %+v %v", n, err)
	}
	n, _ = g.ParseNotice(googlePush("m-4", `{"packageName":"app.covebook","voidedPurchaseNotification":{"purchaseToken":"tok4","orderId":"GPA.2","productType":2,"refundType":1}}`))
	if !n.Voided || *n.Target != (Ref{Kind: KindProduct, ID: "tok4"}) || n.OriginalID != "" {
		t.Fatalf("상품 환불: %+v", n)
	}
	// 연결 확인 알림, 차지백 검토, 모르는 종류: 오류가 아니다. 다시 물어볼 대상이 없을 뿐이다
	if n, err = g.ParseNotice(googlePush("m-5", `{"packageName":"app.covebook","testNotification":{"version":"1.0"}}`)); err != nil || !n.Test || n.Target != nil {
		t.Fatalf("테스트 알림: %+v %v", n, err)
	}
	if n, err = g.ParseNotice(googlePush("m-6", `{"packageName":"app.covebook","pendingRefundReviewNotification":{"orderId":"GPA.3"}}`)); err != nil || n.Type != "refund-review" || n.OrderID != "GPA.3" {
		t.Fatalf("환불 검토: %+v %v", n, err)
	}
	if n, err = g.ParseNotice(googlePush("m-7", `{"packageName":"app.covebook","나중에생긴알림":{}}`)); err != nil || n.Type != "unknown" || n.Target != nil {
		t.Fatalf("모르는 종류: %+v %v", n, err)
	}
	// 다른 앱의 알림과 틀린 본문은 받지 않는다
	if _, err = g.ParseNotice(googlePush("m-8", `{"packageName":"com.other","subscriptionNotification":{"notificationType":2,"purchaseToken":"t"}}`)); !errors.Is(err, ErrWrongApp) {
		t.Fatalf("다른 앱: %v", err)
	}
	for _, body := range []string{``, `{}`, `{"message":{"data":"e30="}}`, `{"message":{"data":"@@@","messageId":"m"}}`, `{"message":{"data":"bm90IGpzb24=","messageId":"m"}}`} {
		if _, err := g.ParseNotice([]byte(body)); err == nil {
			t.Errorf("본문 %q가 통과", body)
		}
	}
}

func TestGoogleVerify(t *testing.T) {
	g := &Google{packageName: "app.covebook"}
	if ref, err := g.Verify(KindProduct, "tok"); err != nil || ref != (Ref{Kind: KindProduct, ID: "tok"}) {
		t.Fatalf("%+v %v", ref, err)
	}
	if _, err := g.Verify(KindProduct, ""); !errors.Is(err, ErrBadProof) {
		t.Fatalf("빈 토큰: %v", err)
	}
}

// 통신 오류 메시지에 구매 토큰이 남지 않는다. 구글 API 주소에는 토큰이 들어 있고 토큰은 구매 증거다.
func TestGoogleErrorsHideToken(t *testing.T) {
	const token = "secret-purchase-token"
	netErr := &url.Error{Op: "Get", URL: "https://androidpublisher.googleapis.com/x/tokens/" + token, Err: errors.New("context deadline exceeded")}
	ctx := context.Background()
	var calls []string
	g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{err: netErr, calls: &calls}}
	_, lookupErr := g.Lookup(ctx, Ref{Kind: KindSubscription, ID: token})
	_, productErr := g.Lookup(ctx, Ref{Kind: KindProduct, ID: token})
	confirmErr := g.Confirm(ctx, Ref{Kind: KindProduct, ID: token}, "shelf", true)
	for name, err := range map[string]error{"구독 조회": lookupErr, "상품 조회": productErr, "확인": confirmErr} {
		if err == nil || strings.Contains(err.Error(), token) {
			t.Errorf("%s 오류에 토큰이 남음: %v", name, err)
		}
		if err != nil && !strings.Contains(err.Error(), "deadline") {
			t.Errorf("%s 오류에서 원인이 사라짐: %v", name, err)
		}
	}
}

func TestGoogleRefund(t *testing.T) {
	var calls []string
	g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{calls: &calls}}
	if err := g.Refund(context.Background(), "GPA.1"); err != nil || len(calls) != 1 || calls[0] != "refund app.covebook GPA.1" {
		t.Fatalf("환불 요청: %v %v", calls, err)
	}
	// 주문 ID가 없으면(프로모션 코드 구매) 부르지 않는다
	if err := g.Refund(context.Background(), ""); err == nil || len(calls) != 1 {
		t.Fatalf("주문 ID 없으면 오류: %v %v", calls, err)
	}
}

// 요금제 변경을 다음 결제일로 미루면 항목이 2개 온다. 만료가 늦은 새 요금제를 쓴다(이슈 #33)
func TestGoogleSubscriptionDeferredChange(t *testing.T) {
	g := &Google{packageName: "app.covebook", api: fakeGoogleAPI{sub: &androidpublisher.SubscriptionPurchaseV2{
		SubscriptionState: "SUBSCRIPTION_STATE_ACTIVE", StartTime: "2026-11-18T03:00:00Z",
		LineItems: []*androidpublisher.SubscriptionPurchaseLineItem{
			{ProductId: "plus", ExpiryTime: "2026-12-18T03:00:00Z", LatestSuccessfulOrderId: "GPA.1",
				OfferDetails: &androidpublisher.OfferDetails{BasePlanId: "monthly"}, AutoRenewingPlan: &androidpublisher.AutoRenewingPlan{AutoRenewEnabled: false}},
			{ProductId: "plus", ExpiryTime: "2027-12-18T03:00:00Z", LatestSuccessfulOrderId: "GPA.2",
				OfferDetails: &androidpublisher.OfferDetails{BasePlanId: "yearly"}, AutoRenewingPlan: &androidpublisher.AutoRenewingPlan{AutoRenewEnabled: true}},
		},
	}}}
	p, err := g.Lookup(context.Background(), Ref{Kind: KindSubscription, ID: "tok"})
	if err != nil {
		t.Fatalf("항목 2개를 받지 못함: %v", err)
	}
	if p.PlanID != "yearly" || !p.AutoRenew || p.ExpiresAt.Year() != 2027 || p.TransactionID != "GPA.2" {
		t.Fatalf("새 요금제를 고르지 않음: %+v", p)
	}
}
