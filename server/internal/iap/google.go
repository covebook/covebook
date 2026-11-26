package iap

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/awa/go-iap/playstore"
	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/googleapi"
)

// googleAPI는 go-iap의 구글 클라이언트에서 우리가 쓰는 메서드만 고른 것이다.
type googleAPI interface {
	VerifySubscriptionV2(ctx context.Context, packageName, token string) (*androidpublisher.SubscriptionPurchaseV2, error)
	VerifyProductV2(ctx context.Context, packageName, token string) (*androidpublisher.ProductPurchaseV2, error)
	AcknowledgeSubscription(ctx context.Context, packageName, subscriptionID, token string, req *androidpublisher.SubscriptionPurchasesAcknowledgeRequest) error
	AcknowledgeProduct(ctx context.Context, packageName, productID, token, developerPayload string) error
	ConsumeProduct(ctx context.Context, packageName, productID, token string) error
	Refund(ctx context.Context, packageName, orderID string) error
	GetOrder(ctx context.Context, packageName, orderID string) (*androidpublisher.Order, error)
}

// googleOrderTimeout은 금액을 받으려는 주문 조회(orders.get)의 제한 시간이다. 금액은 없어도 되므로 구매 조회보다 짧게 둔다
const googleOrderTimeout = 3 * time.Second

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

func (g *Google) Route() Route  { return RouteGoogle }
func (g *Google) AppID() string { return g.packageName }

// Refund는 주문을 환불한다(orders.refund). go-iap는 revoke 인자를 주지 않는다.
// 선반은 소비(consume)하는 상품이라 스토어 쪽에서 거둘 권한이 없고, 칸은 우리 서버가 주지 않았으므로 상관없다.
func (g *Google) Refund(ctx context.Context, orderID string) error {
	if orderID == "" {
		return errors.New("google: 주문 ID가 없는 구매는 환불할 수 없다")
	}
	if err := g.api.Refund(ctx, g.packageName, orderID); err != nil {
		return fmt.Errorf("google 환불 %s: %w", orderID, err)
	}
	return nil
}

const googleAcknowledged = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"

// Verify는 구매 토큰을 그대로 조회 대상으로 쓴다. 토큰이 비밀 값이라 따로 확인할 서명이 없다.
func (g *Google) Verify(kind Kind, proof string) (Ref, error) {
	if proof == "" {
		return Ref{}, fmt.Errorf("google: %w", ErrBadProof)
	}
	return Ref{Kind: kind, ID: proof}, nil
}

// Lookup은 구매 토큰으로 묻는다. 구독과 한 번 사는 상품은 조회 주소가 달라 ref.Kind로 가른다.
func (g *Google) Lookup(ctx context.Context, ref Ref) (Purchase, error) {
	switch ref.Kind {
	case KindSubscription:
		s, err := g.api.VerifySubscriptionV2(ctx, g.packageName, ref.ID)
		if err != nil {
			return Purchase{}, googleErr(err)
		}
		p, err := g.fromSubscription(ref.ID, s)
		if err == nil {
			g.fillPrice(ctx, &p)
		}
		return p, err
	case KindProduct:
		r, err := g.api.VerifyProductV2(ctx, g.packageName, ref.ID)
		if err != nil {
			return Purchase{}, googleErr(err)
		}
		p, err := g.fromProduct(ref.ID, r)
		if err == nil {
			g.fillPrice(ctx, &p)
		}
		return p, err
	}
	return Purchase{}, fmt.Errorf("google: 모르는 상품 종류 %q", ref.Kind)
}

// fillPrice는 주문 조회(orders.get, 2025-05 출시)로 실제 결제 금액을 채운다(2026-11-26 결정, ADR-0003 L17).
// 구매 조회(purchases.*v2)에는 금액이 없다. total은 세금과 할인을 반영해 구매자가 낸 금액이다.
// 지급 판단에는 쓰지 않으므로 실패해도 구매는 그대로 돌려준다. 결제가 끝난 거래만, 주문 ID가 있을 때만 묻는다(프로모션 코드 구매는 주문 ID가 없다).
// 서비스 계정에 "재무 데이터 보기" 권한이 없으면 403이 온다. 금액이 계속 비면 이 로그를 본다
func (g *Google) fillPrice(ctx context.Context, p *Purchase) {
	if p.State != StatePaid || p.TransactionID == "" {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, googleOrderTimeout)
	defer cancel()
	o, err := g.api.GetOrder(ctx, g.packageName, p.TransactionID)
	if err != nil {
		log.Printf("google order price unavailable: product=%s err=%v", p.ProductID, err)
		return
	}
	if o == nil || o.Total == nil || o.Total.CurrencyCode == "" {
		return
	}
	p.Currency = o.Total.CurrencyCode
	p.PriceMilli = o.Total.Units*1000 + o.Total.Nanos/1_000_000
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
	// 보통 항목은 1개다. 요금제 변경을 다음 결제일로 미루면(DEFERRED) 옛 요금제(자동 갱신 꺼짐)와 새 요금제가 함께 온다.
	// 만료가 가장 늦은 항목을 지금 구독으로 본다. 둘 다 같은 plus라 권한은 같고, 만료·요금제·자동 갱신 표시만 새 것을 따른다
	if len(s.LineItems) == 0 {
		return Purchase{}, errors.New("google 구독: 항목이 없음")
	}
	item, latest := s.LineItems[0], time.Time{}
	for _, it := range s.LineItems {
		if t, err := rfcTime(it.ExpiryTime); err == nil && t.After(latest) {
			item, latest = it, t
		}
	}
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
		Acknowledged:          s.AcknowledgementState == googleAcknowledged,
		Env:                   EnvProduction,
		PurchasedAt:           started,
		ExpiresAt:             expires,
		Country:               Country(s.RegionCode),
	}
	if item.OfferDetails != nil {
		p.PlanID = item.OfferDetails.BasePlanId
	}
	if item.AutoRenewingPlan != nil {
		p.AutoRenew = item.AutoRenewingPlan.AutoRenewEnabled
	}
	// 구글은 유예 중에 만료 시각을 유예가 끝나는 때까지 늘려 준다. 그 값이 곧 유예의 끝이다.
	if s.SubscriptionState == "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" {
		p.GraceUntil = expires
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
		Acknowledged:          r.AcknowledgementState == googleAcknowledged,
		Env:                   EnvProduction,
		PurchasedAt:           bought,
		Country:               Country(r.RegionCode),
	}
	if d := r.ProductLineItem[0].ProductOfferDetails; d != nil {
		p.Quantity = int(d.Quantity)
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

// Subscription은 구매 토큰으로 구독의 지금 상태를 묻는다. 구글은 Lookup과 같은 조회다.
func (g *Google) Subscription(ctx context.Context, originalID string) (Purchase, error) {
	return g.Lookup(ctx, Ref{Kind: KindSubscription, ID: originalID})
}

// Confirm은 구글에 지급을 마쳤다고 알린다. 3일 안에 하지 않으면 구글이 자동으로 환불한다.
// 이미 확인한 구매에 다시 불러도 되도록 부르는 쪽이 재시도한다. 결제 대기 구매에는 부르지 않는다.
func (g *Google) Confirm(ctx context.Context, ref Ref, productID string, consume bool) error {
	var err error
	switch {
	case ref.Kind == KindSubscription && !consume:
		err = g.api.AcknowledgeSubscription(ctx, g.packageName, productID, ref.ID, &androidpublisher.SubscriptionPurchasesAcknowledgeRequest{})
	case ref.Kind == KindProduct && consume:
		err = g.api.ConsumeProduct(ctx, g.packageName, productID, ref.ID)
	case ref.Kind == KindProduct:
		err = g.api.AcknowledgeProduct(ctx, g.packageName, productID, ref.ID, "")
	default:
		return fmt.Errorf("google 확인: 종류 %q, 소비 %v는 맞지 않는 조합", ref.Kind, consume)
	}
	if err != nil {
		return fmt.Errorf("google 확인 %s: %w", productID, err)
	}
	return nil
}

// ParseNotice는 구글 실시간 알림(Pub/Sub 푸시)의 본문을 푼다.
// 보낸 쪽이 구글인지(푸시 요청의 인증 토큰)는 요청을 받는 쪽에서 먼저 확인한다. 여기서는 우리 앱의 알림인지만 본다.
// 구글 알림에는 상태가 없고 구매 토큰만 있다.
func (g *Google) ParseNotice(body []byte) (Notice, error) {
	var push struct {
		Message struct {
			Data      string `json:"data"`
			MessageID string `json:"messageId"`
		} `json:"message"`
	}
	if err := json.Unmarshal(body, &push); err != nil || push.Message.MessageID == "" {
		return Notice{}, errors.New("google 알림: 본문 형식이 다름")
	}
	raw, err := base64.StdEncoding.DecodeString(push.Message.Data)
	if err != nil {
		return Notice{}, errors.New("google 알림: data를 풀 수 없음")
	}
	var d playstore.DeveloperNotificationV2
	if err = json.Unmarshal(raw, &d); err != nil {
		return Notice{}, errors.New("google 알림: 내용 형식이 다름")
	}
	n := Notice{Route: RouteGoogle, ID: push.Message.MessageID}
	if ms, e := strconv.ParseInt(d.EventTimeMillis, 10, 64); e == nil {
		n.SentAt = msTime(ms)
	}
	if d.TestNotification != nil {
		n.Type, n.Test = "test", true
		return n, nil
	}
	if d.PackageName != g.packageName {
		return Notice{}, fmt.Errorf("google 알림 %s: %w", n.ID, ErrWrongApp)
	}
	switch {
	case d.SubscriptionNotification != nil:
		s := d.SubscriptionNotification
		n.Type = "subscription/" + strconv.Itoa(int(s.NotificationType))
		n.Target = &Ref{Kind: KindSubscription, ID: s.PurchaseToken}
		n.OriginalID = s.PurchaseToken
	case d.OneTimeProductNotification != nil:
		o := d.OneTimeProductNotification
		n.Type = "product/" + strconv.Itoa(int(o.NotificationType))
		n.Target = &Ref{Kind: KindProduct, ID: o.PurchaseToken}
	case d.VoidedPurchaseNotification != nil:
		v := d.VoidedPurchaseNotification
		n.Type, n.Voided, n.OrderID = "voided/"+strconv.Itoa(int(v.ProductType)), true, v.OrderID
		kind := KindProduct
		if v.ProductType == playstore.VoidedPurchaseProductTypeSubscription {
			kind, n.OriginalID = KindSubscription, v.PurchaseToken
		}
		n.Target = &Ref{Kind: kind, ID: v.PurchaseToken}
	case d.PendingRefundReviewNotification != nil:
		n.Type, n.OrderID = "refund-review", d.PendingRefundReviewNotification.OrderID
	default:
		n.Type = "unknown" // 모르는 종류도 버리지 않는다. 받는 쪽이 원문을 저장한다
	}
	return n, nil
}
