package iap

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/awa/go-iap/appstore/api"
)

// appleAPI는 go-iap 클라이언트에서 우리가 쓰는 메서드만 고른 것이다.
// 시험에서는 이 둘만 가진 가짜를 끼운다.
type appleAPI interface {
	GetTransactionInfo(ctx context.Context, transactionID string) (*api.TransactionInfoResponse, error)
	ParseSignedTransaction(signed string) (*api.JWSTransaction, error)
}

// AppleConfig는 App Store Server API 키다. 값은 환경변수에서 읽고 저장소에 적지 않는다.
type AppleConfig struct {
	KeyP8    []byte // .p8 파일 내용
	KeyID    string
	IssuerID string
	BundleID string
}

type Apple struct{ api appleAPI }

// NewApple은 운영에 먼저 묻고, 없으면 샌드박스에 묻는 클라이언트를 만든다.
// 심사와 TestFlight 구매가 샌드박스 거래라서 필요하다(ADR-0002 D15).
func NewApple(c AppleConfig) *Apple {
	return &Apple{api: api.NewStoreClientWithSandboxFallback(&api.StoreConfig{
		KeyContent: c.KeyP8,
		KeyID:      c.KeyID,
		Issuer:     c.IssuerID,
		BundleID:   c.BundleID,
	})}
}

func (a *Apple) Route() Route { return RouteApple }

func (a *Apple) LookupTransaction(ctx context.Context, transactionID string) (Purchase, error) {
	rsp, err := a.api.GetTransactionInfo(ctx, transactionID)
	if err != nil {
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
	return Purchase{
		Route:                 RouteApple,
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
		Country:               t.Storefront,
	}
}

// msTime은 애플의 밀리초 시각을 UTC로 바꾼다. 0은 "없음"이다.
func msTime(ms int64) time.Time {
	if ms == 0 {
		return time.Time{}
	}
	return time.UnixMilli(ms).UTC()
}
