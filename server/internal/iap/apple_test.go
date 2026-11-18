package iap

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/awa/go-iap/appstore/api"
)

// fakeAppleAPI는 go-iap 클라이언트 자리에 끼우는 가짜다.
type fakeAppleAPI struct {
	tx       *api.JWSTransaction
	lookup   error
	parseErr error
}

func (f fakeAppleAPI) GetTransactionInfo(context.Context, string) (*api.TransactionInfoResponse, error) {
	if f.lookup != nil {
		return nil, f.lookup
	}
	return &api.TransactionInfoResponse{SignedTransactionInfo: "signed"}, nil
}
func (f fakeAppleAPI) ParseSignedTransaction(string) (*api.JWSTransaction, error) {
	return f.tx, f.parseErr
}

func TestAppleLookup(t *testing.T) {
	a := &Apple{api: fakeAppleAPI{tx: &api.JWSTransaction{
		TransactionID: "200", OriginalTransactionId: "100", BundleID: "app.covebook", ProductID: "plus.monthly",
		AppAccountToken: "u-1", Environment: api.Sandbox, PurchaseDate: 1_800_000_000_000, Price: 12990, Currency: "USD", Storefront: "USA",
	}}}
	p, err := a.LookupTransaction(context.Background(), "200")
	if err != nil {
		t.Fatal(err)
	}
	if p.Route != RouteApple || p.TransactionID != "200" || p.OriginalTransactionID != "100" || p.AccountToken != "u-1" {
		t.Fatalf("식별 값이 다름: %+v", p)
	}
	if p.Env != EnvSandbox || p.PriceMilli != 12990 || p.Currency != "USD" || p.Country != "USA" {
		t.Fatalf("환경·금액이 다름: %+v", p)
	}
	if !p.PurchasedAt.Equal(time.UnixMilli(1_800_000_000_000)) || p.PurchasedAt.Location() != time.UTC {
		t.Fatalf("구매 시각이 UTC가 아님: %v", p.PurchasedAt)
	}
	if !p.ExpiresAt.IsZero() || p.Revoked() {
		t.Fatalf("없는 시각은 zero여야 함: %+v", p)
	}
}

func TestAppleLookupErrors(t *testing.T) {
	ctx := context.Background()
	// 스토어에 없는 거래는 ErrNotFound로 구분된다
	_, err := (&Apple{api: fakeAppleAPI{lookup: api.TransactionIdNotFoundError}}).LookupTransaction(ctx, "1")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("ErrNotFound가 아님: %v", err)
	}
	// 통신 실패는 ErrNotFound가 아니다(다시 시도할 수 있어야 한다)
	_, err = (&Apple{api: fakeAppleAPI{lookup: errors.New("timeout")}}).LookupTransaction(ctx, "1")
	if err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("통신 실패가 없는 거래로 처리됨: %v", err)
	}
	// 서명 확인 실패는 거래를 돌려주지 않는다
	p, err := (&Apple{api: fakeAppleAPI{tx: &api.JWSTransaction{TransactionID: "1"}, parseErr: errors.New("bad signature")}}).LookupTransaction(ctx, "1")
	if err == nil || p.TransactionID != "" {
		t.Fatalf("서명 실패인데 거래가 나옴: %+v %v", p, err)
	}
}
