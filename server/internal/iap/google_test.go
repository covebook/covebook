package iap

import (
	"context"
	"errors"
	"testing"

	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/googleapi"
)

type fakeGoogleAPI struct {
	sub  *androidpublisher.SubscriptionPurchaseV2
	prod *androidpublisher.ProductPurchaseV2
	err  error
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
	if p.State != StatePaid || p.Env != EnvSandbox {
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
