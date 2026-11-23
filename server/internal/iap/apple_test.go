package iap

import (
	"context"
	"errors"
	"net/url"
	"testing"
	"time"

	"github.com/awa/go-iap/appstore"
	"github.com/awa/go-iap/appstore/api"
)

// fakeAppleAPI는 go-iap 클라이언트 자리에 끼우는 가짜다.
type fakeAppleAPI struct {
	tx       *api.JWSTransaction
	lookup   error
	parseErr error
	status   *api.StatusResponse
	renewal  *api.JWSRenewalInfoDecodedPayload
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
func (f fakeAppleAPI) GetALLSubscriptionStatuses(context.Context, string, *url.Values) (*api.StatusResponse, error) {
	return f.status, f.lookup
}
func (f fakeAppleAPI) ParseJWSEncodeString(string) (interface{}, error) {
	if f.renewal == nil {
		return nil, f.parseErr
	}
	return f.renewal, f.parseErr
}

func TestAppleLookup(t *testing.T) {
	a := &Apple{api: fakeAppleAPI{tx: &api.JWSTransaction{
		TransactionID: "200", OriginalTransactionId: "100", BundleID: "app.covebook", ProductID: "plus.monthly",
		AppAccountToken: "u-1", Environment: api.Sandbox, PurchaseDate: 1_800_000_000_000, Price: 12990, Currency: "USD", Storefront: "USA",
	}}}
	p, err := a.Lookup(context.Background(), Ref{Kind: KindSubscription, ID: "200"})
	if err != nil {
		t.Fatal(err)
	}
	if p.Route != RouteApple || p.TransactionID != "200" || p.OriginalTransactionID != "100" || p.AccountToken != "u-1" {
		t.Fatalf("식별 값이 다름: %+v", p)
	}
	if p.Env != EnvSandbox || p.PriceMilli != 12990 || p.Currency != "USD" || p.Country != "US" {
		t.Fatalf("환경·금액이 다름: %+v", p)
	}
	if !p.PurchasedAt.Equal(time.UnixMilli(1_800_000_000_000)) || p.PurchasedAt.Location() != time.UTC {
		t.Fatalf("구매 시각이 UTC가 아님: %v", p.PurchasedAt)
	}
	if !p.ExpiresAt.IsZero() || p.State != StatePaid {
		t.Fatalf("없는 시각은 zero여야 함: %+v", p)
	}
}

func TestAppleRevoked(t *testing.T) {
	a := &Apple{api: fakeAppleAPI{tx: &api.JWSTransaction{TransactionID: "1", RevocationDate: 1_800_000_000_000}}}
	p, err := a.Lookup(context.Background(), Ref{ID: "1"})
	if err != nil || p.State != StateRevoked || p.RevokedAt.IsZero() {
		t.Fatalf("환불된 거래가 구분되지 않음: %+v %v", p, err)
	}
}

func TestAppleLookupErrors(t *testing.T) {
	ctx := context.Background()
	// 스토어에 없는 거래는 ErrNotFound로 구분된다
	_, err := (&Apple{api: fakeAppleAPI{lookup: api.TransactionIdNotFoundError}}).Lookup(ctx, Ref{ID: "1"})
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("ErrNotFound가 아님: %v", err)
	}
	// 통신 실패는 ErrNotFound가 아니다(다시 시도할 수 있어야 한다)
	_, err = (&Apple{api: fakeAppleAPI{lookup: errors.New("timeout")}}).Lookup(ctx, Ref{ID: "1"})
	if err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("통신 실패가 없는 거래로 처리됨: %v", err)
	}
	// 서명 확인 실패는 거래를 돌려주지 않는다
	p, err := (&Apple{api: fakeAppleAPI{tx: &api.JWSTransaction{TransactionID: "1"}, parseErr: errors.New("bad signature")}}).Lookup(ctx, Ref{ID: "1"})
	if err == nil || p.TransactionID != "" {
		t.Fatalf("서명 실패인데 거래가 나옴: %+v %v", p, err)
	}
}

func appleStatusResponse(original string, status api.AutoRenewSubscriptionStatus) *api.StatusResponse {
	return &api.StatusResponse{Data: []api.SubscriptionGroupIdentifierItem{{LastTransactions: []api.LastTransactionsItem{
		{OriginalTransactionId: "다른 줄기", Status: api.SubscriptionExpired, SignedTransactionInfo: "x", SignedRenewalInfo: "x"},
		{OriginalTransactionId: original, Status: status, SignedTransactionInfo: "t", SignedRenewalInfo: "r"},
	}}}}
}

func TestAppleSubscription(t *testing.T) {
	ctx := context.Background()
	tx := &api.JWSTransaction{TransactionID: "300", OriginalTransactionId: "100", ProductID: "plus.monthly", ExpiresDate: 1_800_000_000_000, Environment: api.Production}
	for _, c := range []struct {
		name   string
		status api.AutoRenewSubscriptionStatus
		want   State
	}{
		{"활성", api.SubscriptionActive, StatePaid},
		{"유예", api.SubscriptionGracePeriod, StatePaid},
		{"결제 재시도는 권한 없음", api.SubscriptionRetryPeriod, StateInactive},
		{"만료", api.SubscriptionExpired, StateInactive},
		{"환불·취소", api.SubscriptionRevoked, StateRevoked},
		{"모르는 값", 99, StateInactive},
	} {
		a := &Apple{api: fakeAppleAPI{tx: tx, status: appleStatusResponse("100", c.status),
			renewal: &api.JWSRenewalInfoDecodedPayload{AutoRenewStatus: api.AutoRenewStatusOn, GracePeriodExpiresDate: 1_800_000_600_000}}}
		p, err := a.Subscription(ctx, "100")
		if err != nil {
			t.Fatal(c.name, err)
		}
		if p.State != c.want || p.TransactionID != "300" || !p.AutoRenew || p.GraceUntil.IsZero() || p.Env != EnvProduction {
			t.Errorf("%s: %+v", c.name, p)
		}
	}
	// 해지 예약: 자동 갱신이 꺼졌어도 활성이면 권한은 그대로다. 유예가 없으면 GraceUntil은 zero
	a := &Apple{api: fakeAppleAPI{tx: tx, status: appleStatusResponse("100", api.SubscriptionActive), renewal: &api.JWSRenewalInfoDecodedPayload{AutoRenewStatus: api.AutoRenewStatusOff}}}
	if p, err := a.Subscription(ctx, "100"); err != nil || p.State != StatePaid || p.AutoRenew || !p.GraceUntil.IsZero() {
		t.Fatalf("해지 예약: %+v %v", p, err)
	}
	// 환불된 거래는 상태 값이 활성이어도 환불로 본다
	revoked := *tx
	revoked.RevocationDate = 1_800_000_000_000
	a = &Apple{api: fakeAppleAPI{tx: &revoked, status: appleStatusResponse("100", api.SubscriptionActive), renewal: &api.JWSRenewalInfoDecodedPayload{}}}
	if p, _ := a.Subscription(ctx, "100"); p.State != StateRevoked {
		t.Fatalf("환불된 거래: %s", p.State)
	}
	// 답에 그 줄기가 없으면, 그리고 스토어가 없다고 하면 ErrNotFound
	a = &Apple{api: fakeAppleAPI{tx: tx, status: appleStatusResponse("다른 것", api.SubscriptionActive), renewal: &api.JWSRenewalInfoDecodedPayload{}}}
	if _, err := a.Subscription(ctx, "100"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("줄기 없음: %v", err)
	}
	a = &Apple{api: fakeAppleAPI{lookup: api.OriginalTransactionIdNotFoundError}}
	if _, err := a.Subscription(ctx, "100"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("스토어에 없음: %v", err)
	}
	// 통신 실패와 서명 실패는 ErrNotFound가 아니다
	a = &Apple{api: fakeAppleAPI{lookup: errors.New("timeout")}}
	if _, err := a.Subscription(ctx, "100"); err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("통신 실패: %v", err)
	}
	a = &Apple{api: fakeAppleAPI{tx: tx, status: appleStatusResponse("100", api.SubscriptionActive), parseErr: errors.New("bad signature")}}
	if p, err := a.Subscription(ctx, "100"); err == nil || p.TransactionID != "" {
		t.Fatalf("서명 실패인데 답이 나옴: %+v %v", p, err)
	}
}

func TestAppleParseNotice(t *testing.T) {
	// 서명 확인을 가짜로 바꿔 알림 내용을 직접 넣는다. 실제 서명 확인은 라이브러리가 한다
	notice := func(p appstore.SubscriptionNotificationV2DecodedPayload, tx *api.JWSTransaction, verifyErr error) (Notice, error) {
		a := &Apple{bundleID: "app.covebook", api: fakeAppleAPI{tx: tx},
			verifyNotice: func(_ string, into *appstore.SubscriptionNotificationV2DecodedPayload) error {
				*into = p
				return verifyErr
			}}
		return a.ParseNotice([]byte(`{"signedPayload":"aaa.bbb.ccc"}`))
	}
	data := appstore.SubscriptionNotificationV2Data{BundleID: "app.covebook", Environment: "Production", SignedTransactionInfo: "signed"}
	sub := &api.JWSTransaction{TransactionID: "300", OriginalTransactionId: "100", Type: api.AutoRenewable}

	n, err := notice(appstore.SubscriptionNotificationV2DecodedPayload{NotificationType: "DID_RENEW", Subtype: "BILLING_RECOVERY", NotificationUUID: "u-1", SignedDate: 1_800_000_000_000, Data: data}, sub, nil)
	if err != nil {
		t.Fatal(err)
	}
	if n.Route != RouteApple || n.ID != "u-1" || n.Type != "DID_RENEW/BILLING_RECOVERY" || n.Env != EnvProduction || n.Test || n.SentAt.IsZero() {
		t.Fatalf("알림: %+v", n)
	}
	if n.Target == nil || *n.Target != (Ref{Kind: KindSubscription, ID: "300"}) || n.OriginalID != "100" {
		t.Fatalf("대상: %+v %s", n.Target, n.OriginalID)
	}
	// 한 번 사는 상품의 알림(환불 등)은 구독 1건가 없다
	n, err = notice(appstore.SubscriptionNotificationV2DecodedPayload{NotificationType: "REFUND", NotificationUUID: "u-2", Data: data}, &api.JWSTransaction{TransactionID: "400", Type: api.Consumable}, nil)
	if err != nil || *n.Target != (Ref{Kind: KindProduct, ID: "400"}) || n.OriginalID != "" || n.Type != "REFUND" {
		t.Fatalf("상품 알림: %+v %v", n, err)
	}
	// 샌드박스, 연결 확인 알림
	sandbox := data
	sandbox.Environment, sandbox.SignedTransactionInfo = "Sandbox", ""
	n, err = notice(appstore.SubscriptionNotificationV2DecodedPayload{NotificationType: "TEST", NotificationUUID: "u-3", Data: sandbox}, nil, nil)
	if err != nil || !n.Test || n.Env != EnvSandbox || n.Target != nil {
		t.Fatalf("테스트 알림: %+v %v", n, err)
	}
	// 묶음 알림은 summary에 번들 ID가 있다
	n, err = notice(appstore.SubscriptionNotificationV2DecodedPayload{NotificationType: "RENEWAL_EXTENSION", Subtype: "SUMMARY", NotificationUUID: "u-4",
		Summary: appstore.SubscriptionNotificationV2Summary{BundleID: "app.covebook", Environment: "Production"}}, nil, nil)
	if err != nil || n.Target != nil || n.Env != EnvProduction {
		t.Fatalf("묶음 알림: %+v %v", n, err)
	}
	// 다른 앱의 알림, 서명 실패, 알림 ID 없음은 받지 않는다
	other := data
	other.BundleID = "com.other"
	if _, err = notice(appstore.SubscriptionNotificationV2DecodedPayload{NotificationUUID: "u-5", Data: other}, sub, nil); !errors.Is(err, ErrWrongApp) {
		t.Fatalf("다른 앱: %v", err)
	}
	if _, err = notice(appstore.SubscriptionNotificationV2DecodedPayload{NotificationUUID: "u-6", Data: data}, sub, errors.New("bad signature")); err == nil {
		t.Fatal("서명 실패인데 통과")
	}
	if _, err = notice(appstore.SubscriptionNotificationV2DecodedPayload{Data: data}, sub, nil); err == nil {
		t.Fatal("알림 ID 없이 통과")
	}
	// 본문이 틀리면 서명 확인까지 가지 않는다
	a := &Apple{bundleID: "app.covebook", verifyNotice: func(string, *appstore.SubscriptionNotificationV2DecodedPayload) error {
		t.Fatal("틀린 본문인데 서명 확인을 부름")
		return nil
	}}
	for _, body := range []string{``, `{}`, `{"signedPayload":""}`, `not json`} {
		if _, err := a.ParseNotice([]byte(body)); err == nil {
			t.Errorf("본문 %q가 통과", body)
		}
	}
	// 애플은 확인(acknowledge)이 필요 없다
	if err := a.Confirm(context.Background(), Ref{}, "", false); err != nil {
		t.Fatal(err)
	}
}

func TestAppleVerify(t *testing.T) {
	a := &Apple{bundleID: "app.covebook", api: fakeAppleAPI{tx: &api.JWSTransaction{TransactionID: "200", BundleID: "app.covebook"}}}
	ref, err := a.Verify(KindSubscription, "서명된 거래")
	if err != nil || ref != (Ref{Kind: KindSubscription, ID: "200"}) {
		t.Fatalf("정상: %+v %v", ref, err)
	}
	// 서명이 틀리면 거래 ID를 돌려주지 않는다
	a = &Apple{bundleID: "app.covebook", api: fakeAppleAPI{tx: &api.JWSTransaction{TransactionID: "200", BundleID: "app.covebook"}, parseErr: errors.New("bad signature")}}
	if ref, err = a.Verify(KindProduct, "위조"); !errors.Is(err, ErrBadProof) || ref.ID != "" {
		t.Fatalf("서명 실패: %+v %v", ref, err)
	}
	// 서명은 맞지만 다른 앱의 거래
	a = &Apple{bundleID: "app.covebook", api: fakeAppleAPI{tx: &api.JWSTransaction{TransactionID: "200", BundleID: "com.other"}}}
	if _, err = a.Verify(KindProduct, "남의 앱"); !errors.Is(err, ErrWrongApp) {
		t.Fatalf("다른 앱: %v", err)
	}
	// 거래 ID가 없는 내용
	a = &Apple{bundleID: "app.covebook", api: fakeAppleAPI{tx: &api.JWSTransaction{BundleID: "app.covebook"}}}
	if _, err = a.Verify(KindProduct, "빈 거래"); !errors.Is(err, ErrBadProof) {
		t.Fatalf("거래 ID 없음: %v", err)
	}
}
