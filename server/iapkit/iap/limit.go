package iap

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/awa/go-iap/appstore/api"
	"google.golang.org/api/googleapi"
)

// RateLimitError는 스토어가 요청 한도를 넘었다고 답했거나(429), 그 뒤 쉬는 중이라 부르지 않은 것이다.
// Until까지는 같은 경로의 스토어 API를 부르지 않는다. 애플 한도는 시간 단위로 세므로 바로 다시 두드리면 더 늦게 풀린다.
type RateLimitError struct {
	Route Route
	Until time.Time
	Err   error // 스토어가 준 원래 오류. 쉬는 중이라 부르지 않았으면 nil
}

func (e *RateLimitError) Error() string {
	if e.Err == nil {
		return fmt.Sprintf("%s: store rate limited until %s (not called)", e.Route, e.Until.UTC().Format(time.RFC3339))
	}
	return fmt.Sprintf("%s: store rate limited until %s: %v", e.Route, e.Until.UTC().Format(time.RFC3339), e.Err)
}

func (e *RateLimitError) Unwrap() error { return e.Err }

// RestingUntil은 한도에 걸려 쉬는 스토어가 언제까지 쉬는지 알려 준다. 정기 대조가 이 경로의 건을 건너뛰는 데 쓴다.
// Apple, Google, Fake가 구현한다.
type Rester interface {
	RestingUntil() time.Time
}

// ListRester는 목록 조회(애플 알림 이력, 구글 무효 구매 목록)의 쉬는 시각을 따로 알려 준다.
// 목록 조회의 한도는 구매 한 건 조회와 따로 센다. 애플은 API마다 한도가 따로 있다(Identifying rate limits).
// 목록 조회가 한도에 걸려도 결제 제출(구매 조회·확인)은 막지 않는다. 그 반대도 같다
type ListRester interface {
	ListRestingUntil() time.Time
}

// 한도에 걸렸는데 다시 부를 시각을 모르면 기다리는 시간. 쉬는 시간의 상한
const (
	limitDefaultRest = time.Minute
	limitMaxRest     = time.Hour
)

// limiter는 스토어 클라이언트 하나의 "언제까지 쉬나"를 기억한다. 0 값으로 쓴다.
type limiter struct {
	mu    sync.Mutex
	until time.Time
}

// check는 쉬는 중이면 부르지 말라는 오류를 준다.
func (l *limiter) check(route Route) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if time.Now().Before(l.until) {
		return &RateLimitError{Route: route, Until: l.until}
	}
	return nil
}

// note는 스토어 오류가 한도 초과면 쉴 시각을 적고 RateLimitError로 감싸 돌려준다. 아니면 그대로 돌려준다.
func (l *limiter) note(route Route, err error) error {
	if err == nil {
		return nil
	}
	at, ok := rateLimitedUntil(err, time.Now())
	if !ok {
		return err
	}
	l.mu.Lock()
	if at.After(l.until) {
		l.until = at
	}
	at = l.until
	l.mu.Unlock()
	return &RateLimitError{Route: route, Until: at, Err: err}
}

// IsRateLimit은 스토어가 한도에 걸렸거나 쉬는 중이라 실패한 것인지 본다.
// 이런 실패는 그 건의 잘못이 아니라서, 부르는 쪽은 시도 횟수를 쓰지 않는다.
func IsRateLimit(err error) bool {
	var rl *RateLimitError
	return errors.As(err, &rl)
}

func isRateLimit(err error) bool { return IsRateLimit(err) }

// googleLimitReasons는 구글 API가 403으로 주는 한도 초과 사유다(일부 API는 429 대신 403을 쓴다)
var googleLimitReasons = map[string]bool{"rateLimitExceeded": true, "userRateLimitExceeded": true, "quotaExceeded": true}

func (l *limiter) restingUntil() time.Time {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.until
}

// rateLimitedUntil은 오류가 한도 초과인지 보고, 그렇다면 다시 부를 시각을 준다.
//   - 애플: 오류 코드 4290000. 본문이 없는 429도 있다(라이브러리의 StatusCode)
//   - 구글: HTTP 429. Retry-After 헤더(초)가 있으면 쓴다. 403에 한도 사유(rateLimitExceeded 등)가 붙은 것도 같다
func rateLimitedUntil(err error, now time.Time) (time.Time, bool) {
	var ae *api.Error
	if errors.As(err, &ae) && ae.ErrorCode() == 4290000 {
		return retryAt(ae.RetryAfter(), now), true
	}
	var ge *googleapi.Error
	if errors.As(err, &ge) && ge.Code == http.StatusTooManyRequests {
		v, _ := strconv.ParseInt(ge.Header.Get("Retry-After"), 10, 64)
		return retryAt(v, now), true
	}
	if ge != nil && ge.Code == http.StatusForbidden {
		for _, item := range ge.Errors {
			if googleLimitReasons[item.Reason] {
				return retryAt(0, now), true
			}
		}
	}
	var withStatus interface{ StatusCode() int }
	if errors.As(err, &withStatus) && withStatus.StatusCode() == http.StatusTooManyRequests {
		return retryAt(0, now), true
	}
	return time.Time{}, false
}

// retryAt은 Retry-After 값을 시각으로 바꾼다.
// 애플 문서는 "UNIX 시각, 밀리초"라 하고, 라이브러리 주석은 "초"라 하고, 구글(HTTP 표준)은 "몇 초 뒤"다. 크기로 가린다:
// 10^12보다 크면 밀리초 시각, 10^9보다 크면 초 시각, 그보다 작으면 몇 초 뒤. 0이나 음수는 모름(1분).
// 너무 먼 값(1시간 넘게)은 1시간으로 줄인다. 잘못된 헤더 하나로 결제가 하루 멈추지 않게
func retryAt(v int64, now time.Time) time.Time {
	var at time.Time
	switch {
	case v > 1e12:
		at = time.UnixMilli(v)
	case v > 1e9:
		at = time.Unix(v, 0)
	case v > 0:
		at = now.Add(time.Duration(v) * time.Second)
	default:
		at = now.Add(limitDefaultRest)
	}
	if !at.After(now) {
		at = now.Add(time.Second)
	}
	if at.Sub(now) > limitMaxRest {
		at = now.Add(limitMaxRest)
	}
	return at
}
