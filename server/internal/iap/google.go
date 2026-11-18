package iap

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/awa/go-iap/playstore"
	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/googleapi"
)

// googleAPI는 go-iap의 구글 클라이언트에서 우리가 쓰는 메서드만 고른 것이다.
type googleAPI interface {
	VerifySubscriptionV2(ctx context.Context, packageName, token string) (*androidpublisher.SubscriptionPurchaseV2, error)
	VerifyProductV2(ctx context.Context, packageName, token string) (*androidpublisher.ProductPurchaseV2, error)
}

type Google struct {
	api         googleAPI
	packageName string
}

// NewGoogle은 서비스 계정 키(JSON)로 클라이언트를 만든다.
// 만드는 순간 구글에서 접근 토큰을 한 번 받아 오므로, 키가 틀리거나 통신이 안 되면 여기서 실패한다.
func NewGoogle(serviceAccountJSON []byte, packageName string) (*Google, error) {
	c, err := playstore.New(serviceAccountJSON)
	if err != nil {
		return nil, fmt.Errorf("google 클라이언트: %w", err)
	}
	return &Google{api: c, packageName: packageName}, nil
}

func (g *Google) Route() Route { return RouteGoogle }

// Lookup은 구매 토큰으로 묻는다. 구독과 한 번 사는 상품은 조회 주소가 달라 ref.Kind로 가른다.
func (g *Google) Lookup(ctx context.Context, ref Ref) (Purchase, error) {
	switch ref.Kind {
	case KindSubscription:
		s, err := g.api.VerifySubscriptionV2(ctx, g.packageName, ref.ID)
		if err != nil {
			return Purchase{}, googleErr(err)
		}
		return g.fromSubscription(ref.ID, s)
	case KindProduct:
		p, err := g.api.VerifyProductV2(ctx, g.packageName, ref.ID)
		if err != nil {
			return Purchase{}, googleErr(err)
		}
		return g.fromProduct(ref.ID, p)
	}
	return Purchase{}, fmt.Errorf("google: 모르는 상품 종류 %q", ref.Kind)
}

// googleErr는 "그런 구매 없음"(404, 410)을 ErrNotFound로 바꾼다. 나머지는 통신·권한 문제로 둔다.
func googleErr(err error) error {
	var ge *googleapi.Error
	if errors.As(err, &ge) && (ge.Code == http.StatusNotFound || ge.Code == http.StatusGone) {
		return fmt.Errorf("google: %w", ErrNotFound)
	}
	return fmt.Errorf("google 구매 조회: %w", err)
}

func (g *Google) fromSubscription(token string, s *androidpublisher.SubscriptionPurchaseV2) (Purchase, error) {
	// 우리 구독은 상품 1개라 항목도 1개다. 다르면 설정이 바뀐 것이니 지급하지 않고 멈춘다.
	if len(s.LineItems) != 1 {
		return Purchase{}, fmt.Errorf("google 구독: 항목이 %d개", len(s.LineItems))
	}
	item := s.LineItems[0]
	started, err := rfcTime(s.StartTime)
	if err != nil {
		return Purchase{}, fmt.Errorf("google 구독 시작 시각: %w", err)
	}
	expires, err := rfcTime(item.ExpiryTime)
	if err != nil {
		return Purchase{}, fmt.Errorf("google 구독 만료 시각: %w", err)
	}
	p := Purchase{
		Route:                 RouteGoogle,
		TransactionID:         item.LatestSuccessfulOrderId,
		OriginalTransactionID: token,
		BundleID:              g.packageName, // 응답에 패키지 이름이 없다. 우리 패키지로 물어서 받은 답이다
		ProductID:             item.ProductId,
		State:                 subscriptionState(s.SubscriptionState),
		Env:                   EnvProduction,
		PurchasedAt:           started,
		ExpiresAt:             expires,
		Country:               s.RegionCode,
	}
	if item.OfferDetails != nil {
		p.PlanID = item.OfferDetails.BasePlanId
	}
	if s.ExternalAccountIdentifiers != nil {
		p.AccountToken = s.ExternalAccountIdentifiers.ObfuscatedExternalAccountId
	}
	if s.TestPurchase != nil {
		p.Env = EnvSandbox
	}
	return p, nil
}

func (g *Google) fromProduct(token string, r *androidpublisher.ProductPurchaseV2) (Purchase, error) {
	if len(r.ProductLineItem) != 1 {
		return Purchase{}, fmt.Errorf("google 상품: 항목이 %d개", len(r.ProductLineItem))
	}
	bought, err := rfcTime(r.PurchaseCompletionTime)
	if err != nil {
		return Purchase{}, fmt.Errorf("google 구매 시각: %w", err)
	}
	state := StateInactive
	if r.PurchaseStateContext != nil {
		switch r.PurchaseStateContext.PurchaseState {
		case "PURCHASED":
			state = StatePaid
		case "PENDING":
			state = StatePending
		case "CANCELLED":
			state = StateRevoked
		}
	}
	p := Purchase{
		Route:                 RouteGoogle,
		TransactionID:         r.OrderId,
		OriginalTransactionID: token,
		BundleID:              g.packageName,
		ProductID:             r.ProductLineItem[0].ProductId,
		AccountToken:          r.ObfuscatedExternalAccountId,
		State:                 state,
		Env:                   EnvProduction,
		PurchasedAt:           bought,
		Country:               r.RegionCode,
	}
	if r.TestPurchaseContext != nil {
		p.Env = EnvSandbox
	}
	return p, nil
}

// subscriptionState는 구글의 구독 상태를 지급 판단용 상태로 줄인다.
// 해지했지만 기간이 남은 구독(CANCELED)은 만료일까지 유효하다(ADR-0002 D12).
// 유예 기간은 유지한다(D11). 모르는 값은 권한 없음으로 둔다.
func subscriptionState(s string) State {
	switch s {
	case "SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_CANCELED":
		return StatePaid
	case "SUBSCRIPTION_STATE_PENDING":
		return StatePending
	}
	return StateInactive
}

// rfcTime은 구글의 RFC 3339 시각 문자열을 UTC로 바꾼다. 빈 문자열은 "없음"이다.
func rfcTime(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}, err
	}
	return t.UTC(), nil
}
