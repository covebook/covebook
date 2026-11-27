package iap

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/awa/go-iap/appstore"
	"github.com/awa/go-iap/appstore/api"
	"github.com/golang-jwt/jwt/v5"
)

// appleAPI는 go-iap 클라이언트에서 우리가 쓰는 메서드만 고른 것이다.
// 시험에서는 이것만 가진 가짜를 끼운다.
type appleAPI interface {
	GetTransactionInfo(ctx context.Context, transactionID string) (*api.TransactionInfoResponse, error)
	ParseSignedTransaction(signed string) (*api.JWSTransaction, error)
	GetALLSubscriptionStatuses(ctx context.Context, originalTransactionID string, query *url.Values) (*api.StatusResponse, error)
	GetAllNotificationHistory(ctx context.Context, body api.NotificationHistoryRequest, duration time.Duration) ([]api.NotificationHistoryResponseItem, error)
}

// AppleConfig는 App Store Server API 키다. 값은 환경변수에서 읽고 저장소에 적지 않는다.
type AppleConfig struct {
	KeyP8    []byte // .p8 파일 내용
	KeyID    string
	IssuerID string
	BundleID string
}

type Apple struct {
	api      appleAPI
	bundleID string
	// parseRenewal은 서명된 갱신 정보의 서명과 인증서 사슬을 확인하고 내용을 푼다. 시험에서는 가짜로 바꾼다.
	parseRenewal func(signed string) (*api.JWSRenewalInfoDecodedPayload, error)
	// verifyNotice는 알림의 서명과 인증서 사슬을 확인하고 내용을 푼다. 시험에서는 가짜로 바꾼다.
	verifyNotice func(signed string, into *appstore.SubscriptionNotificationV2DecodedPayload) error
	lim          limiter // 한도(429)에 걸리면 Retry-After까지 부르지 않는다. 거래 조회용
	listLim      limiter // 알림 이력 조회용. 따로 센다(ListRester)
}

// RestingUntil은 한도에 걸려 언제까지 쉬는지 준다(Rester).
func (a *Apple) RestingUntil() time.Time { return a.lim.restingUntil() }

// ListRestingUntil은 알림 이력 조회가 언제까지 쉬는지 준다(ListRester).
func (a *Apple) ListRestingUntil() time.Time { return a.listLim.restingUntil() }

// NewApple은 운영에 먼저 묻고, 없으면 샌드박스에 묻는 클라이언트를 만든다.
// 심사와 TestFlight 구매가 샌드박스 거래라서 필요하다(ADR-0002 D15).
func NewApple(c AppleConfig) *Apple {
	verifier := appstore.New()
	return &Apple{
		api: api.NewStoreClientWithSandboxFallback(&api.StoreConfig{
			KeyContent: c.KeyP8,
			KeyID:      c.KeyID,
			Issuer:     c.IssuerID,
			BundleID:   c.BundleID,
		}),
		bundleID:     c.BundleID,
		parseRenewal: parseAppleRenewal,
		verifyNotice: func(signed string, into *appstore.SubscriptionNotificationV2DecodedPayload) error {
			return verifier.ParseNotificationV2WithClaim(signed, into)
		},
	}
}

func (a *Apple) Route() Route  { return RouteApple }
func (a *Apple) AppID() string { return a.bundleID }

// Verify는 앱이 낸 서명된 거래(JWS)의 서명과 인증서 사슬을 확인하고 거래 ID를 꺼낸다.
// 여기서 꺼낸 값으로 지급하지 않는다. 지급 근거는 이 ID로 스토어에 다시 물어 받은 답이다.
func (a *Apple) Verify(kind Kind, proof string) (Ref, error) {
	t, err := a.api.ParseSignedTransaction(proof)
	if err != nil || t == nil || t.TransactionID == "" {
		return Ref{}, fmt.Errorf("apple: %w", ErrBadProof)
	}
	if t.BundleID != a.bundleID {
		return Ref{}, fmt.Errorf("apple: %w", ErrWrongApp)
	}
	return Ref{Kind: kind, ID: t.TransactionID}, nil
}

// Lookup은 거래 ID로 묻는다. 애플은 종류와 상관없이 같은 주소라 ref.Kind는 쓰지 않는다.
func (a *Apple) Lookup(ctx context.Context, ref Ref) (Purchase, error) {
	transactionID := ref.ID
	if err := a.lim.check(RouteApple); err != nil {
		return Purchase{}, err
	}
	rsp, err := a.api.GetTransactionInfo(ctx, transactionID)
	if err != nil {
		if rl := a.lim.note(RouteApple, err); isRateLimit(rl) {
			return Purchase{}, rl
		}
		if errors.Is(err, api.TransactionIdNotFoundError) {
			return Purchase{}, fmt.Errorf("apple %s: %w", transactionID, ErrNotFound)
		}
		return Purchase{}, fmt.Errorf("apple 거래 조회 %s: %w", transactionID, err)
	}
	// 응답 본문도 애플이 서명한 문자열이다. 서명·인증서 검증은 라이브러리가 한다(ADR-0001 결정 9).
	t, err := a.api.ParseSignedTransaction(rsp.SignedTransactionInfo)
	if err != nil {
		return Purchase{}, fmt.Errorf("apple 서명 확인 %s: %w", transactionID, err)
	}
	return fromApple(t), nil
}

func fromApple(t *api.JWSTransaction) Purchase {
	env := EnvProduction
	if t.Environment != api.Production {
		env = EnvSandbox // 모르는 값은 매출에서 빠지는 쪽으로 둔다
	}
	state := StatePaid
	if t.RevocationDate != 0 {
		state = StateRevoked
	}
	return Purchase{
		Route:                 RouteApple,
		State:                 state,
		Acknowledged:          true,
		TransactionID:         t.TransactionID,
		OriginalTransactionID: t.OriginalTransactionId,
		BundleID:              t.BundleID,
		ProductID:             t.ProductID,
		AccountToken:          t.AppAccountToken,
		Env:                   env,
		PurchasedAt:           msTime(t.PurchaseDate),
		ExpiresAt:             msTime(t.ExpiresDate),
		RevokedAt:             msTime(t.RevocationDate),
		Currency:              t.Currency,
		PriceMilli:            t.Price, // 애플은 이미 x1000 값으로 준다
		Country:               Country(t.Storefront),
	}
}

// msTime은 애플의 밀리초 시각을 UTC로 바꾼다. 0은 "없음"이다.
func msTime(ms int64) time.Time {
	if ms == 0 {
		return time.Time{}
	}
	return time.UnixMilli(ms).UTC()
}

// Subscription은 원 거래 ID로 구독의 지금 상태를 묻는다.
// 애플의 답에는 그 구독 그룹의 줄기들이 들어 있다. 물어본 원 거래 ID의 줄기를 고른다.
func (a *Apple) Subscription(ctx context.Context, originalID string) (Purchase, error) {
	if err := a.lim.check(RouteApple); err != nil {
		return Purchase{}, err
	}
	rsp, err := a.api.GetALLSubscriptionStatuses(ctx, originalID, nil)
	if err != nil {
		if rl := a.lim.note(RouteApple, err); isRateLimit(rl) {
			return Purchase{}, rl
		}
		if errors.Is(err, api.TransactionIdNotFoundError) || errors.Is(err, api.OriginalTransactionIdNotFoundError) {
			return Purchase{}, fmt.Errorf("apple 구독 %s: %w", originalID, ErrNotFound)
		}
		return Purchase{}, fmt.Errorf("apple 구독 상태 조회 %s: %w", originalID, err)
	}
	for _, group := range rsp.Data {
		for _, item := range group.LastTransactions {
			if item.OriginalTransactionId != originalID {
				continue
			}
			t, err := a.api.ParseSignedTransaction(item.SignedTransactionInfo)
			if err != nil {
				return Purchase{}, fmt.Errorf("apple 서명 확인 %s: %w", originalID, err)
			}
			p := fromApple(t)
			p.State = appleStatus(item.Status, p.State)
			r, err := a.parseRenewal(item.SignedRenewalInfo)
			if err != nil {
				return Purchase{}, fmt.Errorf("apple 갱신 정보 서명 확인 %s: %w", originalID, err)
			}
			p.AutoRenew = r.AutoRenewStatus == api.AutoRenewStatusOn
			p.GraceUntil = msTime(r.GracePeriodExpiresDate)
			return p, nil
		}
	}
	return Purchase{}, fmt.Errorf("apple 구독 %s: 답에 그 줄기가 없음: %w", originalID, ErrNotFound)
}

// parseAppleRenewal은 서명된 갱신 정보(JWS)를 확인하고 푼다.
// 라이브러리의 ParseJWSEncodeString을 쓰지 않는 이유: 본문에 특정 글자가 있는지로 종류를 추측하고,
// 점(.)이 없는 문자열에서는 패닉한다. 여기서는 형식을 먼저 보고, 거래와 같은 인증서 사슬 확인을 거친다.
func parseAppleRenewal(signed string) (*api.JWSRenewalInfoDecodedPayload, error) {
	if strings.Count(signed, ".") != 2 {
		return nil, errors.New("서명된 값의 형식이 다름")
	}
	key, err := (&appstore.Cert{}).ExtractPublicKeyFromToken(signed)
	if err != nil {
		return nil, err
	}
	var r api.JWSRenewalInfoDecodedPayload
	if _, err = jwt.ParseWithClaims(signed, &r, func(*jwt.Token) (interface{}, error) { return key, nil }); err != nil {
		return nil, err
	}
	return &r, nil
}

// appleStatus는 애플의 구독 상태 값을 지급 판단용 상태로 줄인다. 1 활성과 4 유예만 권한이 있다.
// 3 결제 재시도와 2 만료는 권한이 없고, 5는 환불·취소다. 모르는 값은 권한 없음으로 둔다.
func appleStatus(status api.AutoRenewSubscriptionStatus, fromTransaction State) State {
	if fromTransaction == StateRevoked {
		return StateRevoked
	}
	switch status {
	case api.SubscriptionActive, api.SubscriptionGracePeriod:
		return StatePaid
	case api.SubscriptionRevoked:
		return StateRevoked
	}
	return StateInactive
}

// Confirm은 애플에서는 할 일이 없다. 앱이 지급 응답을 받은 뒤 거래를 끝낸다(ADR-0002 D10).
func (a *Apple) Confirm(context.Context, Ref, string, bool) error { return nil }

// ParseNotice는 애플 서버 알림(V2)의 본문을 확인하고 푼다.
// 서명·인증서 확인은 라이브러리가 한다. 우리 앱의 알림인지(번들 ID)는 여기서 본다.
func (a *Apple) ParseNotice(body []byte) (Notice, error) {
	var envelope struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := json.Unmarshal(body, &envelope); err != nil || envelope.SignedPayload == "" {
		return Notice{}, fmt.Errorf("apple 알림 본문: %w", ErrBadNotice)
	}
	var payload appstore.SubscriptionNotificationV2DecodedPayload
	if err := a.verifyNotice(envelope.SignedPayload, &payload); err != nil {
		return Notice{}, fmt.Errorf("apple 알림 서명 확인: %w", err)
	}
	if payload.NotificationUUID == "" {
		return Notice{}, fmt.Errorf("apple 알림 ID 없음: %w", ErrBadNotice)
	}
	kind := string(payload.NotificationType)
	if payload.Subtype != "" {
		kind += "/" + string(payload.Subtype)
	}
	n := Notice{Route: RouteApple, ID: payload.NotificationUUID, Type: kind, SentAt: msTime(payload.SignedDate), Test: payload.NotificationType == "TEST"}
	bundle, environment := payload.Data.BundleID, payload.Data.Environment
	if bundle == "" { // 묶음 알림(갱신일 일괄 연장 등)은 data 대신 summary에 있다
		bundle, environment = payload.Summary.BundleID, payload.Summary.Environment
	}
	if bundle != a.bundleID {
		return Notice{}, fmt.Errorf("apple 알림 %s: %w", n.ID, ErrWrongApp)
	}
	n.Env = EnvSandbox
	if strings.EqualFold(environment, string(api.Production)) {
		n.Env = EnvProduction
	}
	if signed := string(payload.Data.SignedTransactionInfo); signed != "" {
		t, err := a.api.ParseSignedTransaction(signed)
		if err != nil {
			return Notice{}, fmt.Errorf("apple 알림 %s 거래 서명 확인: %w", n.ID, err)
		}
		ref := Ref{Kind: KindProduct, ID: t.TransactionID}
		if t.Type == api.AutoRenewable {
			ref.Kind = KindSubscription
			n.OriginalID = t.OriginalTransactionId
		}
		n.Target = &ref
	}
	return n, nil
}
