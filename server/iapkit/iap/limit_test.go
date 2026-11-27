package iap

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/awa/go-iap/appstore/api"
	"github.com/awa/go-iap/playstore"
	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/googleapi"
)

// 다시 부를 시각: 애플·구글이 주는 여러 모양의 Retry-After를 시각으로 바꾸고, 너무 먼 값은 1시간으로 줄인다
func TestRetryAt(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	cases := []struct {
		name string
		v    int64
		want time.Duration // now부터
	}{
		{"모름", 0, time.Minute},
		{"몇 초 뒤", 30, 30 * time.Second},
		{"초 시각", now.Unix() + 120, 2 * time.Minute},
		{"밀리초 시각", now.Add(90 * time.Second).UnixMilli(), 90 * time.Second},
		{"너무 멂", now.Add(48 * time.Hour).UnixMilli(), time.Hour},
		{"이미 지남", now.Add(-time.Minute).UnixMilli(), time.Second},
	}
	for _, c := range cases {
		if got := retryAt(c.v, now).Sub(now); got != c.want {
			t.Errorf("%s: %v, 기대 %v", c.name, got, c.want)
		}
	}
}

func TestRateLimitedUntil(t *testing.T) {
	now := time.Now()
	h := http.Header{}
	h.Set("Retry-After", "45")
	cases := []struct {
		name string
		err  error
		ok   bool
		rest time.Duration
	}{
		{"애플 4290000", fmt.Errorf("감쌈: %w", api.RateLimitExceededError), true, time.Minute},
		{"구글 429 + Retry-After", &googleapi.Error{Code: 429, Header: h}, true, 45 * time.Second},
		{"구글 429만", &googleapi.Error{Code: 429}, true, time.Minute},
		{"구글 503", &googleapi.Error{Code: 503}, false, 0},
		{"구글 403 한도 사유", &googleapi.Error{Code: 403, Errors: []googleapi.ErrorItem{{Reason: "quotaExceeded"}}}, true, time.Minute},
		{"구글 403 권한", &googleapi.Error{Code: 403, Errors: []googleapi.ErrorItem{{Reason: "forbidden"}}}, false, 0},
		{"애플 다른 오류", api.TransactionIdNotFoundError, false, 0},
		{"통신 오류", errors.New("timeout"), false, 0},
	}
	for _, c := range cases {
		at, ok := rateLimitedUntil(c.err, now)
		if ok != c.ok {
			t.Errorf("%s: 한도 판정 %v, 기대 %v", c.name, ok, c.ok)
			continue
		}
		if ok && at.Sub(now) != c.rest {
			t.Errorf("%s: 쉬는 시간 %v, 기대 %v", c.name, at.Sub(now), c.rest)
		}
	}
}

// 구글이 429를 주면 그 뒤로는 쉬는 시간이 끝날 때까지 API를 부르지 않는다
func TestGoogleRestsAfterRateLimit(t *testing.T) {
	ctx := context.Background()
	h := http.Header{}
	h.Set("Retry-After", "60")
	calls := 0
	g := &Google{api: countingGoogleAPI{fakeGoogleAPI: fakeGoogleAPI{err: &googleapi.Error{Code: 429, Header: h}}, n: &calls}}

	_, err := g.Lookup(ctx, Ref{Kind: KindProduct, ID: "x"})
	var rl *RateLimitError
	if !errors.As(err, &rl) || rl.Err == nil {
		t.Fatalf("429인데 한도 오류가 아님: %v", err)
	}
	if errors.Is(err, ErrNotFound) {
		t.Fatal("한도 초과를 '없음'으로 봄")
	}
	if until := g.RestingUntil(); time.Until(until) < 50*time.Second {
		t.Fatalf("쉬는 시각이 짧음: %v", time.Until(until))
	}
	for _, call := range []func() error{
		func() error { _, e := g.Lookup(ctx, Ref{Kind: KindSubscription, ID: "y"}); return e },
		func() error { return g.Confirm(ctx, Ref{Kind: KindProduct, ID: "x"}, "p", false) },
		func() error { return g.Refund(ctx, "GPA.1") },
	} {
		if e := call(); !errors.As(e, &rl) || rl.Err != nil {
			t.Fatalf("쉬는 중인데 부름(또는 다른 오류): %v", e)
		}
	}
	if calls != 1 {
		t.Fatalf("API 호출 %d번, 기대 1번", calls)
	}
	// 목록 조회는 한도를 따로 센다. 구매 조회가 쉬어도 목록은 부르고, 목록이 429를 맞으면 그때부터 목록만 쉰다
	if _, e := g.Voided(ctx, time.Now().Add(-time.Hour)); !errors.As(e, &rl) || rl.Err == nil || calls != 2 {
		t.Fatalf("목록 조회가 구매 조회의 쉬기에 막힘: %v, 호출 %d번", e, calls)
	}
	if _, e := g.Voided(ctx, time.Now().Add(-time.Hour)); !errors.As(e, &rl) || rl.Err != nil || calls != 2 {
		t.Fatalf("목록이 429를 맞았는데 다시 부름: %v, 호출 %d번", e, calls)
	}
	if time.Until(g.ListRestingUntil()) < 50*time.Second {
		t.Fatalf("목록 쉬는 시각이 짧음: %v", time.Until(g.ListRestingUntil()))
	}
}

// countingGoogleAPI는 구매 조회 횟수를 센다
type countingGoogleAPI struct {
	fakeGoogleAPI
	n *int
}

func (c countingGoogleAPI) VerifyProductV2(ctx context.Context, pkg, token string) (*androidpublisher.ProductPurchaseV2, error) {
	*c.n++
	return c.fakeGoogleAPI.VerifyProductV2(ctx, pkg, token)
}

func (c countingGoogleAPI) VoidedPurchases(ctx context.Context, pkg string, start, end, max int64, token string, skip int64, kind playstore.VoidedPurchaseType) (*androidpublisher.VoidedPurchasesListResponse, error) {
	*c.n++
	return c.fakeGoogleAPI.VoidedPurchases(ctx, pkg, start, end, max, token, skip, kind)
}
