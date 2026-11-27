package iapkit

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/jackc/pgx/v5"
	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit/iap"
)

// 스토어 알림 수신과 정기 대조. 근거: docs/reports/2026-11-19-iap-pitfalls.md 3-4장, 3-5장, 8-2장(T4, T5)
//
// 받을 때: 서명·인증 확인 → 원문을 DB에 저장(알림 ID 유일) → 바로 200. 처리는 뒤에서 한다.
//   - 애플 엔지니어: 응답은 몇 초 안에, 처리는 수신과 분리하라. 이미 받은 알림에도 200을 주라.
//   - DB에 먼저 저장하는 이유: 애플 재시도는 1시간 뒤부터라 응답한 뒤에 잃으면 되찾기 어렵다.
// 처리할 때: 알림 내용으로 상태를 정하지 않는다. "이 거래를 다시 물어보라"는 신호로만 쓰고 스토어의 답으로 덮어쓴다.
//   - 그래서 알림이 겹치거나 순서가 바뀌어도 결과가 같다.
// 대조: 알림은 빠질 수 있다. 만료가 다가온 구독, 확인을 못 마친 거래, 처리에 실패한 알림을 주기적으로 다시 본다.

// iapNoticeParser는 알림 본문을 풀 수 있는 스토어다(iap.Apple, iap.Google).
type iapNoticeParser interface {
	ParseNotice(body []byte) (iap.Notice, error)
}

func (s *Kit) routeIAPNotify(m *http.ServeMux) {
	if _, ok := s.IAP[iap.RouteApple].(iapNoticeParser); ok {
		m.HandleFunc("POST /iap/notifications/apple", wrap(s.iapNotify(iap.RouteApple)))
	}
	// 구글 알림은 보낸 쪽이 구글인지 확인할 설정이 있을 때만 받는다. 없으면 경로를 열지 않는다.
	if _, ok := s.IAP[iap.RouteGoogle].(iapNoticeParser); ok && s.iapPushAuth != nil {
		m.HandleFunc("POST /iap/notifications/google", wrap(s.iapNotify(iap.RouteGoogle)))
	}
}

// iapGooglePushAuth는 구글 Pub/Sub 푸시 요청의 인증 토큰을 확인하는 함수를 만든다. 설정이 없으면 nil이다.
//   - IAP_GOOGLE_PUSH_AUDIENCE: Pub/Sub 구독에 적은 대상(audience)
//   - IAP_GOOGLE_PUSH_EMAIL: 푸시에 쓰는 서비스 계정 이메일
//
// 구글이 서명한 토큰인지, 대상이 우리인지, 그 서비스 계정이 보낸 것인지 본다.
func (s *Kit) iapGooglePushAuth() func(ctx context.Context, header string) error {
	audience, email := strings.TrimSpace(os.Getenv("IAP_GOOGLE_PUSH_AUDIENCE")), strings.TrimSpace(os.Getenv("IAP_GOOGLE_PUSH_EMAIL"))
	if audience == "" || email == "" {
		return nil
	}
	keys := oidc.NewRemoteKeySet(oidc.ClientContext(context.Background(), s.HTTP), "https://www.googleapis.com/oauth2/v3/certs")
	verifier := oidc.NewVerifier("https://accounts.google.com", keys, &oidc.Config{ClientID: audience, SupportedSigningAlgs: []string{"RS256"}})
	return func(ctx context.Context, header string) error {
		raw, ok := strings.CutPrefix(header, "Bearer ")
		if !ok || raw == "" {
			return errors.New("no bearer token")
		}
		token, err := verifier.Verify(ctx, raw)
		if err != nil {
			return err
		}
		var claims struct {
			Email    string `json:"email"`
			Verified bool   `json:"email_verified"`
		}
		if err = token.Claims(&claims); err != nil {
			return err
		}
		if !claims.Verified || !strings.EqualFold(claims.Email, email) {
			return errors.New("unexpected sender")
		}
		return nil
	}
}

func (s *Kit) iapNotify(route iap.Route) handler {
	return func(w http.ResponseWriter, r *http.Request) error {
		ctx := r.Context()
		if route == iap.RouteGoogle {
			if err := s.iapPushAuth(ctx, r.Header.Get("Authorization")); err != nil {
				log.Printf("iap notification rejected: route=%s reason=auth", route)
				return unauthorized
			}
		}
		body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
		if err != nil {
			return bad
		}
		n, err := s.IAP[route].(iapNoticeParser).ParseNotice(body)
		switch {
		case err == nil:
		case errors.Is(err, iap.ErrWrongApp):
			// 다른 앱의 알림. 다시 받아도 같으니 받았다고 답하고 버린다.
			log.Printf("iap notification ignored: route=%s reason=other app", route)
			w.WriteHeader(http.StatusOK)
			return nil
		case errors.Is(err, iap.ErrBadNotice):
			log.Printf("iap notification malformed: route=%s", route)
			if route == iap.RouteGoogle {
				// Pub/Sub은 2xx가 아니면 계속 다시 보낸다. 풀 수 없는 것은 다시 받아도 못 푼다.
				w.WriteHeader(http.StatusOK)
				return nil
			}
			return bad
		default:
			// 서명 확인 실패. 위조일 수도 있고 우리 쪽 문제일 수도 있다. 5xx로 답해 스토어가 다시 보내게 한다.
			log.Printf("iap notification verify failed: route=%s err=%v", route, err)
			return apiError{500, "iap_notification_unverified", "알림을 확인하지 못했어요"}
		}
		inserted, err := iapRecordNotification(ctx, s.DB, n, string(body))
		if err != nil {
			return err // 저장하지 못했으면 스토어가 다시 보내게 한다
		}
		if inserted && n.Test {
			if err = iapFinishNotification(ctx, s.DB, route, n.ID, "ignored", "연결 확인용 알림"); err != nil {
				return err
			}
		}
		if inserted && !n.Test {
			s.iapWakeUp()
		}
		// 이미 받은 알림에도 200. 5xx를 주면 애플이 재시도를 처음부터 다시 한다.
		w.WriteHeader(http.StatusOK)
		return nil
	}
}

func (s *Kit) iapWakeUp() {
	select {
	case s.iapWake <- struct{}{}:
	default:
	}
}

// StartIAPWorker는 알림 처리와 대조를 뒤에서 돌린다. 1분마다, 그리고 새 알림이 오면 바로 돈다.
// 서버가 여러 대여도 한 번에 한 곳만 돌게 DB 자문 락을 잡는다.
func (s *Kit) StartIAPWorker(ctx context.Context) {
	if len(s.IAP) == 0 {
		return
	}
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			s.iapSweepSafely(ctx)
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			case <-s.iapWake:
			}
		}
	}()
}

// iapSweepSafely는 한 번 돌리되, 그 안에서 패닉이 나도 서버 전체가 죽지 않게 한다.
// 고루틴의 패닉은 잡지 않으면 프로세스를 내린다. 스토어가 보낸 예상 밖의 값 하나로 서버가 죽으면 안 된다.
func (s *Kit) iapSweepSafely(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("iap sweep panic: %v", r)
		}
	}()
	jobCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	if err := s.iapSweepLocked(jobCtx); err != nil && ctx.Err() == nil {
		log.Printf("iap sweep failed: %v", err)
	}
}

// iapSweepLock은 정기 대조를 한 서버에서만 돌리는 잠금의 이름이다. 숫자 대신 이름에서 키를 만들어(hashtextextended)
// 키트를 붙인 앱이 쓰는 다른 advisory lock 숫자와 겹치지 않게 한다.
const iapSweepLock = "iapkit.sweep"

func (s *Kit) iapSweepLocked(ctx context.Context) error {
	conn, err := s.DB.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	var got bool
	if err = conn.QueryRow(ctx, "SELECT pg_try_advisory_lock(hashtextextended($1, 0))", iapSweepLock).Scan(&got); err != nil || !got {
		return err // 다른 곳에서 돌고 있으면 이번에는 건너뛴다
	}
	defer conn.Exec(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock(hashtextextended($1, 0))", iapSweepLock)
	res, err := s.iapSweep(ctx)
	s.iapLogSweep(ctx, res)
	return err
}

// iapSweepResult는 한 번 돌면서 한 일이다. 숫자가 계속 크면 알림이 안 오고 있다는 신호다(이슈 #39).
type iapSweepResult struct {
	Notices, NoticesFailed, Confirmed, Refreshed int
	Backfilled, Voided                           int // 스토어의 목록으로 메운 알림, 반영한 환불
	Renewals                                     int // 새로 쓴 갱신 예정 고지
	Refunds                                      int // 주지 않은 거래(상한 넘김, 대상 모름, 주인 없음)의 환불을 요청해 성공한 수(구글)
	Resting                                      int // 스토어가 한도(429)에 걸려 쉬는 중이라 이번에 건너뛴 건
	Cut                                          int // 단계 마감 시각이 지나 이번 바퀴에 못 한 단계 수
}

// 대조 한 바퀴(2분) 안에서 단계마다 끝나야 하는 시각(시작부터). 앞 단계가 느린 스토어에 묶여도 뒤 단계가 돌 시간을 남긴다.
// 마감은 누적이라 앞 단계가 빨리 끝나면 남은 시간을 뒤 단계가 쓴다. 기한이 있는 일(구글 확인 3일)에 가장 많이 준다.
// 마감에 걸린 건은 다음 바퀴(1분 뒤)에 이어서 한다. 모두 다시 해도 되는 일이다
var iapSweepStages = struct {
	confirm, catchUp, notices, refunds, subscriptions time.Duration
}{
	confirm:       30 * time.Second,
	catchUp:       60 * time.Second,
	notices:       80 * time.Second,
	refunds:       95 * time.Second,
	subscriptions: 115 * time.Second, // 남은 5초는 DB만 쓰는 갱신 예정 고지
}

// iapSweep은 밀린 일을 한 번 처리한다: 스토어 확인 재시도, 빠진 알림·환불 메우기, 알림 처리, 만료가 다가온 구독 재확인.
// 순서: 기한이 있는 것(구글 확인 3일)을 가장 먼저 한다. 한 단계가 실패해도 다음 단계는 돈다.
func (s *Kit) iapSweep(jobCtx context.Context) (iapSweepResult, error) {
	var res iapSweepResult
	var firstErr error
	keep := func(err error) {
		if err != nil && firstErr == nil && jobCtx.Err() == nil {
			firstErr = err
		}
	}
	start := time.Now()
	// stage는 단계의 마감 시각까지 쓰는 ctx를 준다. 마감이 지난 단계는 건너뛴다(ok=false)
	stage := func(until time.Duration) (context.Context, context.CancelFunc, bool) {
		c, cancel := context.WithDeadline(jobCtx, start.Add(until))
		if c.Err() != nil {
			res.Cut++
			return c, cancel, false
		}
		return c, cancel, true
	}
	// over는 단계 도중 마감이 지났는지 본다. 지났으면 남은 건은 다음 바퀴로 넘긴다
	over := func(c context.Context) bool {
		if c.Err() != nil {
			res.Cut++
			return true
		}
		return false
	}
	// resting은 그 경로의 스토어가 한도에 걸려 쉬는 중인지 본다. 쉬는 중이면 부르지 않고 건너뛴다(시도 횟수도 쓰지 않는다)
	resting := func(route iap.Route) bool {
		if r, ok := s.IAP[route].(iap.Rester); ok && time.Now().Before(r.RestingUntil()) {
			res.Resting++
			return true
		}
		return false
	}

	// 1. 스토어 확인을 못 마친 거래
	ctx, cancel, ok := stage(iapSweepStages.confirm)
	var unconfirmed []iapUnconfirmed
	if ok {
		var err error
		unconfirmed, err = iapUnconfirmedPurchases(ctx, s.DB, 100)
		keep(err)
	}
	for _, u := range unconfirmed {
		if over(ctx) {
			break
		}
		if resting(u.Route) {
			continue
		}
		iapSafely("confirm", func() {
			store := s.IAP[u.Route]
			if store == nil {
				return
			}
			ref, consume := iap.Ref{Kind: u.Kind, ID: u.OriginalID}, false
			if u.Kind == iap.KindProduct {
				if p, e := iapFindProduct(ctx, s.DB, u.Route, u.ProductID); e == nil {
					consume = p.Consume
				}
			}
			// 시작한 확인은 단계 마감과 상관없이 끝까지 한다(iapConfirmAfter). 구글에는 적용됐는데 응답 전에 끊기면
			// 원장에는 미확인으로 남아 이미 소비한 구매에 다시 소비를 요청하게 된다
			e := iapConfirmAfter(ctx, store, ref, u.ProductID, consume)
			if e != nil && !iap.IsRateLimit(e) && iapAlreadyConfirmed(ctx, store, ref, consume) {
				// 앞선 확인이 구글에는 적용됐는데 원장 기록만 실패한 경우다. 다시 요청하면 구글이 400(invalidPurchaseState)을 주니
				// 스토어 상태를 보고 확인을 마친 것으로 적는다. 안 그러면 4일 동안 매 바퀴 다시 부르고 미확인 경보가 거짓으로 울린다
				e = nil
			}
			if e != nil {
				log.Printf("iap confirm retry failed: route=%s product=%s err=%v", u.Route, u.ProductID, e)
				return
			}
			// 스토어 확인은 됐다. 단계 마감에 기록이 끊기지 않게 한다
			if e = iapMarkConfirmed(context.WithoutCancel(ctx), s.DB, u.Route, u.Key); e != nil {
				keep(e)
				return
			}
			res.Confirmed++
		})
	}
	cancel()

	// 2. 스토어의 목록으로 빠진 알림과 환불을 메운다(6시간에 한 번). 넣은 알림은 바로 아래에서 처리된다
	if ctx, cancel, ok = stage(iapSweepStages.catchUp); ok {
		s.iapCatchUp(ctx, &res)
	}
	cancel()
	// 3. 밀린 알림
	ctx, cancel, ok = stage(iapSweepStages.notices)
	var notices []iapNoticeRow
	if ok {
		var err error
		notices, err = iapPendingNotifications(ctx, s.DB, 100)
		keep(err)
	}
	for _, n := range notices {
		if over(ctx) {
			break
		}
		if resting(n.Route) {
			continue
		}
		result, note := s.iapProcessNoticeSafely(ctx, n)
		if ctx.Err() != nil && result == "failed" {
			// 마감 때문에 끊긴 것은 알림의 실패가 아니다. 시도 횟수를 쓰지 않고 다음 바퀴에 다시 한다
			res.Cut++
			break
		}
		if result == "failed" && resting(n.Route) {
			// 처리 도중 스토어가 한도에 걸렸다. 이 알림의 실패가 아니니 시도 횟수를 쓰지 않는다
			continue
		}
		if result == "failed" {
			res.NoticesFailed++
			log.Printf("iap notification failed (will retry): route=%s id=%s err=%s", n.Route, n.ID, note)
		} else {
			res.Notices++
		}
		// 처리 결과는 마감과 상관없이 남긴다. 처리하고도 못 적으면 다음 바퀴에 같은 알림을 또 처리한다
		keep(iapFinishNotification(jobCtx, s.DB, n.Route, n.ID, result, note))
	}
	cancel()

	// 4. 상한을 넘게 산 거래 중 환불 요청을 못 마친 것(구글). 처음 요청은 제출·알림 처리에서 한다
	var refunders []string
	for route, store := range s.IAP {
		if _, ok := store.(iap.Refunder); ok && !resting(route) {
			refunders = append(refunders, string(route))
		}
	}
	ctx, cancel, ok = stage(iapSweepStages.refunds)
	var overCap, ungranted []iapOverCapRow
	if ok && len(refunders) > 0 {
		var err error
		overCap, err = iapOverCapToRefund(ctx, s.DB, refunders, 50)
		keep(err)
		ungranted, err = iapUngrantedToRefund(ctx, s.DB, refunders, 50)
		keep(err)
	}
	for _, o := range overCap {
		if over(ctx) {
			break
		}
		if resting(o.Route) {
			continue // 앞 건에서 한도에 걸렸다. 남은 건은 시도 횟수를 쓰지 않고 다음에 한다
		}
		iapSafely("over cap refund", func() {
			store := s.IAP[o.Route]
			if _, ok := store.(iap.Refunder); !ok {
				return
			}
			// 주문 ID는 원장에 두지 않는다. 구매 토큰으로 다시 물어 받는다
			storeCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
			p, e := store.Lookup(storeCtx, iap.Ref{Kind: iap.KindProduct, ID: o.Key})
			cancel()
			if e != nil {
				log.Printf("iap over cap refund retry: lookup failed route=%s err=%v", o.Route, e)
				if iap.IsRateLimit(e) || ctx.Err() != nil {
					return // 한도·단계 마감은 이 거래의 실패가 아니다
				}
				keep(iapNoteRefundAttempt(ctx, s.DB, o.Route, o.Key, false))
				return
			}
			if s.iapRefundOverCap(ctx, store, o.Key, p.TransactionID) {
				res.Refunds++
			}
		})
	}
	// 대상을 끝내 모르는 거래(2일 뒤)와 주인 없는 거래. 앱이 대상과 함께 다시 낼 시간을 준 뒤 구글 3일 자동 환불보다 먼저 한다.
	// 환불하는 순간 앱이 대상을 붙여 내 받았어도, 구글 환불 알림(voided)이 와서 회수한다
	for _, o := range ungranted {
		if over(ctx) {
			break
		}
		if resting(o.Route) {
			continue
		}
		iapSafely("ungranted refund", func() {
			store := s.IAP[o.Route]
			storeCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
			p, e := store.Lookup(storeCtx, iap.Ref{Kind: iap.KindProduct, ID: o.Key})
			cancel()
			if e != nil {
				log.Printf("iap ungranted refund: lookup failed route=%s err=%v", o.Route, e)
				return
			}
			if s.iapRefundPurchase(ctx, store, o.Key, p.TransactionID) {
				res.Refunds++
			}
		})
	}

	cancel()

	// 5. 만료가 다가왔거나 지난 구독
	ctx, cancel, ok = stage(iapSweepStages.subscriptions)
	var due [][2]string
	if ok {
		var err error
		due, err = iapDueSubscriptions(ctx, s.DB, 200)
		keep(err)
	}
	for _, d := range due {
		if over(ctx) {
			break
		}
		route, original := iap.Route(d[0]), d[1]
		if resting(route) {
			continue // 미루지 않는다(bump). 쉬는 동안 순서를 흐트러뜨릴 이유가 없다
		}
		if iapSafely("subscription", func() {
			store := s.IAP[route]
			if store == nil {
				// 꺼진 경로의 줄이 매번 맨 앞에 뽑히지 않게 한다
				keep(iapBumpSubscription(ctx, s.DB, route, original))
				return
			}
			if _, e := s.iapSyncSubscription(ctx, store, original); e != nil {
				if ctx.Err() != nil {
					return // 마감에 끊긴 것. 다음 바퀴에 같은 순서로 다시 한다
				}
				log.Printf("iap subscription refresh failed: route=%s err=%v", route, e)
				keep(iapBumpSubscription(ctx, s.DB, route, original))
				return
			}
			res.Refreshed++
		}) {
			// 패닉 난 구독이 다음 바퀴에도 맨 앞에 뽑혀 뒤의 구독을 막지 않게 뒤로 보낸다
			keep(iapBumpSubscription(jobCtx, s.DB, route, original))
		}
	}
	cancel()

	// 6. 곧 갱신될 연 구독에 갱신 예정 고지(T4). 5에서 만료일을 새로 받은 뒤에 본다. 6시간에 한 번. DB만 쓰고 남은 시간을 다 쓴다
	if now := time.Now().UTC(); jobCtx.Err() == nil && s.iapRenewalDue(now) {
		n, e := iapNoteRenewals(jobCtx, s.DB, now, iapRenewalNoticeDays())
		keep(e)
		res.Renewals = n
	}
	return res, firstErr
}

// iapSafely는 대조의 한 건을 돌리고, 패닉을 그 건의 실패로 가둔다(패닉이면 true).
// 대조 전체의 recover(iapSweepSafely)만 있으면 패닉 난 한 건이 그 바퀴의 뒤 단계를 다 끊고, 다음 바퀴에도 맨 앞에 뽑혀 같은 일이 반복된다
func iapSafely(what string, fn func()) (panicked bool) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("iap sweep panic: step=%s panic=%v", what, r)
			panicked = true
		}
	}()
	fn()
	return false
}

// iapProcessNoticeSafely는 알림 한 건의 패닉을 그 알림의 실패로 가둔다.
// 대조 전체의 recover(iapSweepSafely)만 있으면, 패닉 난 알림은 실패로 기록되지 않아 시도 횟수가 오르지 않고
// 다음 바퀴에도 맨 앞에 뽑혀 뒤의 알림과 4단계(만료 구독 재조회)를 매번 막는다. 실패로 남기면 다른 실패처럼 간격을 두고 다시 시도한다
func (s *Kit) iapProcessNoticeSafely(ctx context.Context, n iapNoticeRow) (result, note string) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("iap notification panic: route=%s id=%s panic=%v", n.Route, n.ID, r)
			result, note = "failed", fmt.Sprintf("처리 중 패닉: %v", r)
		}
	}()
	return s.iapProcessNotice(ctx, n)
}

// iapProcessNotice는 알림 한 건을 처리하고 결과(processed, ignored, failed)와 메모를 돌려준다.
func (s *Kit) iapProcessNotice(ctx context.Context, n iapNoticeRow) (result, note string) {
	store := s.IAP[n.Route]
	if store == nil {
		return "failed", "그 경로의 스토어가 꺼져 있음"
	}
	if n.TargetID == "" {
		return "ignored", "다시 물어볼 거래가 없는 알림"
	}
	var notes []string
	// 구글의 환불·취소 알림: 인증을 통과한 구글의 알림이 곧 환불의 근거다. 조회 결과로 판단하지 않는다.
	// (구글 구매 조회가 환불된 구매를 환불 상태로 돌려준다는 보장이 없고, 오래된 토큰은 조회되지 않는다)
	voided := strings.HasPrefix(n.Type, "voided/")
	if voided && n.Route == iap.RouteGoogle {
		now := time.Now().UTC()
		// 한 번 사는 상품은 구매 토큰이, 구독의 갱신 거래는 주문 ID가 원장의 키다
		keys := []string{}
		for _, key := range []string{n.TargetID, n.OrderID} {
			if key == "" {
				continue
			}
			keys = append(keys, key)
			if _, _, err := s.iapApplyPurchaseState(ctx, n.Route, key, iap.StateRevoked, now); err != nil {
				return "failed", err.Error()
			}
		}
		// 한 번 사는 상품이 원장에 아직 없으면(앱이 제출하기 전에 환불됨) 끝내지 않고 다시 시도한다.
		// 여기서 끝내면 환불 사실이 남지 않아, 늦게 온 제출이 조회만 믿고 칸을 연다(구글 조회는 환불을 보장하지 않음)
		if n.Kind != iap.KindSubscription {
			var known bool
			if err := s.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM iap_purchases WHERE route=$1 AND transaction_id = ANY($2))`, string(n.Route), keys).Scan(&known); err != nil {
				return "failed", err.Error()
			}
			if !known {
				return "failed", "원장에 아직 없는 거래의 환불(제출 전 환불). 제출되면 다음 재시도에서 회수"
			}
		}
		notes = append(notes, "환불 알림 반영")
		// 구독이면 구독 상태도 스토어의 답으로 맞춘다. 한 번 사는 상품은 여기서 끝낸다(조회가 되살리지 않게)
		if n.Kind != iap.KindSubscription || n.OriginalID == "" {
			return "processed", strings.Join(notes, "; ")
		}
		m, err := s.iapSyncSubscription(ctx, store, n.OriginalID)
		if err != nil {
			return "failed", err.Error()
		}
		return "processed", strings.Join(append(notes, m), "; ")
	}
	if n.Kind == iap.KindSubscription && n.OriginalID != "" {
		m, err := s.iapSyncSubscription(ctx, store, n.OriginalID)
		if err != nil {
			return "failed", err.Error()
		}
		notes = append(notes, m)
	}
	m, err := s.iapSyncPurchase(ctx, store, iap.Ref{Kind: n.Kind, ID: n.TargetID})
	if err != nil {
		return "failed", err.Error()
	}
	notes = append(notes, m)
	return "processed", strings.Join(notes, "; ")
}

// iapBasics는 알림·대조로 알게 된 거래가 우리 앱의 아는 상품인지, 받아도 되는 환경인지 본다. 계정과 상태는 보지 않는다.
func (s *Kit) iapBasics(ctx context.Context, store iap.Store, p iap.Purchase) error {
	products, err := iapProductSet(ctx, s.DB, store.Route())
	if err != nil {
		return err
	}
	p.State = iap.StatePaid
	return iap.Check(p, iap.Expect{BundleID: store.AppID(), Products: products, AccountTokens: []string{strings.ToLower(p.AccountToken)}, AllowSandbox: s.IAPSandbox})
}

// iapSyncSubscription은 구독 1건을 스토어에 다시 묻고 우리 테이블을 그 답으로 맞춘다.
//   - 줄이 있으면 상태만 고친다. 주인은 그대로다(주인은 우리 테이블이 정한다. 스토어의 계정 연결 값은 옮긴 뒤에도 옛 값이다).
//   - 줄이 없으면(앱이 제출하기 전에 알림이 먼저 옴, 앱 밖 구매) 계정 연결 값으로 주인을 찾아 만든다. 못 찾으면 만들지 않는다.
func (s *Kit) iapSyncSubscription(ctx context.Context, store iap.Store, originalID string) (string, error) {
	route := store.Route()
	storeCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
	defer cancel()
	cur, err := store.Subscription(storeCtx, originalID)
	if errors.Is(err, iap.ErrNotFound) {
		return "스토어에 없는 구독", iapTouchSubscription(ctx, s.DB, route, originalID)
	}
	if err != nil {
		return "", fmt.Errorf("구독 조회: %w", err)
	}
	if err = s.iapBasics(ctx, store, cur); err != nil {
		if errors.Is(err, iap.ErrWrongApp) || errors.Is(err, iap.ErrUnknownProduct) || errors.Is(err, iap.ErrSandbox) {
			// 받지 않는 거래(샌드박스 스위치가 꺼짐 등)도 "확인했다"고 남긴다. 안 그러면 대조 작업이 이 줄만 되풀이한다
			return "받지 않는 거래: " + err.Error(), iapBumpSubscription(ctx, s.DB, route, originalID)
		}
		return "", err
	}
	sub := iapSubscription{Route: route, OriginalID: cur.OriginalTransactionID, ProductID: cur.ProductID, PlanID: cur.PlanID, Env: cur.Env,
		State: cur.State, ExpiresAt: cur.ExpiresAt, GraceUntil: cur.GraceUntil, AutoRenew: cur.AutoRenew, LatestTxnID: cur.TransactionID}
	if cur.State == iap.StatePending {
		return "결제 대기", iapBumpSubscription(ctx, s.DB, route, originalID)
	}

	tx, err := iapBegin(ctx, s.DB)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	// 같은 줄기를 다루는 제출과 순서를 맞춘다. 줄이 없을 때 둘이 동시에 "없음"을 보면 알림이 제출한 사람의 구독을 덮어쓸 수 있다
	if err = iapLockLine(ctx, tx, route, sub.OriginalID); err != nil {
		return "", err
	}
	owner, err := iapSubscriptionOwner(ctx, tx, route, sub.OriginalID)
	if err != nil {
		return "", err
	}
	note, granted, user := "상태 갱신", false, owner.user
	if owner.found {
		// 고치기 전의 값을 읽어 두고, 고친 뒤 달라진 것(유예 시작, 만료, 해지 접수, 환불)을 고지로 남긴다
		before, e := iapSubBeforeOf(ctx, tx, route, sub.OriginalID)
		if e != nil {
			return "", e
		}
		if _, err = iapRefreshSubscription(ctx, tx, sub); err != nil {
			return "", err
		}
		if err = iapNoteSubscriptionChange(ctx, tx, user, before, sub, time.Now()); err != nil {
			return "", err
		}
	} else {
		// 주인 찾기: 계정 연결 값, 없으면 이 구독이 대신한 옛 줄기의 주인.
		if user, err = iapUserByToken(ctx, tx, cur.AccountToken); err != nil {
			return "", err
		}
		if user == 0 && cur.LinkedID != "" {
			linked, e := iapSubscriptionOwner(ctx, tx, route, cur.LinkedID)
			if e != nil {
				return "", e
			}
			user = linked.user
		}
		if user == 0 {
			return "주인을 모르는 구독. 앱이 제출하면 연결됨", tx.Commit(ctx)
		}
		if _, err = iapUpsertSubscription(ctx, tx, user, sub); err != nil {
			return "", err
		}
		// 알림만으로 새로 지급한 구독도 결제 완료를 알린다(T3). 뒤에 앱이 같은 거래를 제출하면 "전에 지급한 것"이라 다시 알리지 않는다
		if cur.State == iap.StatePaid {
			if err = iapNotePurchaseDone(ctx, tx, user, iap.KindSubscription, cur, iapGrant{}); err != nil {
				return "", err
			}
		}
		note, granted = "알림으로 새 구독 연결", true
	}
	if err = iapEndLinked(ctx, tx, route, cur.LinkedID, sub.OriginalID); err != nil {
		return "", err
	}
	// 가장 최근 거래를 원장에 남긴다(갱신 거래). 주인을 아는 경우에만.
	key := iapTransactionKey(iap.KindSubscription, cur)
	if user != 0 && cur.State == iap.StatePaid {
		inserted, e := iapRecordPurchase(ctx, tx, user, iap.KindSubscription, cur, s.IAPRules.TargetRequired)
		if e != nil {
			return "", e
		}
		// 주인이 있던 구독에 처음 보는 결제 거래: 갱신(또는 요금제 변경) 결제다. 결제 완료를 알린다(T3, ADR-0003 L7 "구매·갱신 직후").
		// 고지의 유일 키가 거래 단위라, 같은 거래를 제출 경로가 먼저 알렸어도 한 줄이다
		if inserted && owner.found {
			if err = iapNotePurchaseDone(ctx, tx, user, iap.KindSubscription, cur, iapGrant{}); err != nil {
				return "", err
			}
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	// 알림만으로 지급한 새 구독은 여기서 스토어 확인을 한다(앱이 꺼져 있어도 3일 기한을 지키게).
	if granted && cur.State == iap.StatePaid && !cur.Acknowledged {
		if e := iapConfirmAfter(ctx, store, iap.Ref{Kind: iap.KindSubscription, ID: sub.OriginalID}, cur.ProductID, false); e != nil {
			log.Printf("iap confirm failed (will retry): route=%s err=%v", route, e)
		} else if e = iapMarkConfirmed(context.WithoutCancel(ctx), s.DB, route, key); e != nil {
			log.Printf("iap confirm not recorded: route=%s err=%v", route, e)
		}
	}
	return note, nil
}

// iapApplyPurchaseState는 스토어가 알려 준 거래 상태(환불, 애플의 환불 되돌림)를 원장에 반영한다. 바뀐 줄이 있으면 changed다.
// 환불·되돌림은 상한(대상마다 N칸)의 개수를 바꾸는 쓰기라서, 제출·상한 판정과 같은 유저 줄 잠금(iapLockUser)을 잡은
// 트랜잭션 안에서 한다. 잠금 없이 하면 동시에 도는 제출이 바뀌기 전 개수를 세서 판정한다(2026-11-28 조사, 우아한형제들 WMS의 취소 경로 사례).
// 되돌림(revoked→paid)이면 상한을 다시 판정한다. 환불된 동안 같은 대상을 또 샀으면 되돌린 거래가 넘은 거래가 되고(overCap),
// 넘김 고지(T15)를 쓴다. 애플은 개발자가 환불할 수 없어 고지가 "애플에 환불을 요청해 주세요"를 안내한다
func (s *Kit) iapApplyPurchaseState(ctx context.Context, route iap.Route, key string, state iap.State, revokedAt time.Time) (changed, overCap bool, err error) {
	tx, err := iapBegin(ctx, s.DB)
	if err != nil {
		return false, false, err
	}
	defer tx.Rollback(ctx)
	// 잠글 유저를 먼저 읽는다. 한 번 사는 상품은 주인이 바뀌지 않는다(D8). 주인이 없는 줄(탈퇴)은 셀 상한이 없어 잠그지 않는다
	var user *int64
	var kind string
	err = tx.QueryRow(ctx, "SELECT user_id, kind FROM iap_purchases WHERE route=$1 AND transaction_id=$2", string(route), key).Scan(&user, &kind)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, false, nil // 원장에 없는 거래(다른 환경, 지급 전 환불). 부르는 쪽이 따로 다룬다
	}
	if err != nil {
		return false, false, err
	}
	if user != nil {
		if err = iapLockUser(ctx, tx, *user); err != nil {
			return false, false, err
		}
	}
	if changed, err = iapSyncPurchaseState(ctx, tx, route, key, state, revokedAt); err != nil {
		return false, false, err
	}
	if changed && state == iap.StatePaid && kind == string(iap.KindProduct) && user != nil {
		if overCap, err = iapSettleCap(ctx, tx, *user, route, key, s.IAPSandbox, s.IAPRules.Cap); err != nil {
			return false, false, err
		}
		if overCap {
			if err = iapNoteOverCapRow(ctx, tx, *user, route, key); err != nil {
				return false, false, err
			}
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return false, false, err
	}
	if overCap {
		log.Printf("iap over cap after refund reversal: route=%s user=%d", route, *user)
	}
	return changed, overCap, nil
}

// iapSyncPurchase는 거래 하나를 스토어에 다시 묻고 원장의 환불 상태를 맞춘다.
// 한 번 사는 상품이 원장에 없으면(앱이 제출하기 전에 알림이 먼저 옴) 계정 연결 값으로 주인을 찾아 지급한다.
func (s *Kit) iapSyncPurchase(ctx context.Context, store iap.Store, ref iap.Ref) (string, error) {
	route := store.Route()
	storeCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
	defer cancel()
	p, err := store.Lookup(storeCtx, ref)
	if errors.Is(err, iap.ErrNotFound) {
		return "스토어에 없는 거래", nil
	}
	if err != nil {
		return "", fmt.Errorf("거래 조회: %w", err)
	}
	key := iapTransactionKey(ref.Kind, p)
	changed, reversedOverCap, err := s.iapApplyPurchaseState(ctx, route, key, p.State, p.RevokedAt)
	if err != nil {
		return "", err
	}
	if changed {
		if p.State == iap.StateRevoked {
			return "환불 반영", nil
		}
		if reversedOverCap {
			return "환불 되돌림 반영(그사이 같은 대상을 또 사서 상한 넘음: 되돌린 거래는 주지 않음)", nil
		}
		return "환불 되돌림 반영", nil
	}
	if ref.Kind != iap.KindProduct || p.State != iap.StatePaid {
		return "거래 상태 변화 없음", nil
	}
	owner, err := iapPurchaseOwner(ctx, s.DB, route, key)
	if err != nil {
		return "", err
	}
	if owner.found {
		return "이미 원장에 있음", nil
	}
	if err = s.iapBasics(ctx, store, p); err != nil {
		if errors.Is(err, iap.ErrWrongApp) || errors.Is(err, iap.ErrUnknownProduct) || errors.Is(err, iap.ErrSandbox) {
			return "받지 않는 거래: " + err.Error(), nil
		}
		return "", err
	}
	user, err := iapUserByToken(ctx, s.DB, p.AccountToken)
	if err != nil {
		return "", err
	}
	if user == 0 {
		return "주인을 모르는 구매. 앱이 제출하면 연결됨", nil
	}
	product, err := iapFindProduct(ctx, s.DB, route, p.ProductID)
	if err != nil {
		return "", err
	}
	// 원장, 상한 넘김 판정, 결제 중 예약 풀기, 고지(T3 또는 넘김)를 한 트랜잭션에 쓴다(앱보다 알림이 먼저 온 경우)
	tx, err := iapBegin(ctx, s.DB)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	// 유저 줄을 잠근다. 같은 유저의 제출과 차례로 결제 의도를 보고 지운다
	if err = iapLockUser(ctx, tx, user); err != nil {
		return "", err
	}
	inserted, err := iapRecordPurchase(ctx, tx, user, iap.KindProduct, p, s.IAPRules.TargetRequired)
	if err != nil {
		return "", err
	}
	// 어느 대상의 구매인지는 결제 의도로 찾는다(D1). 결제가 늦게 끝나도 의도는 며칠 남아 있다(Rules.Keep).
	// 대상을 모르면 주지 않았으니 결제 완료도 알리지 않는다
	intentID, intentTarget, intentKnown, err := iapIntentTarget(ctx, tx, user, "", product.Units, p.PurchasedAt)
	if err != nil {
		return "", err
	}
	target, known, filled, err := iapSetTarget(ctx, tx, route, key, intentTarget)
	if err != nil {
		return "", err
	}
	if intentKnown && (inserted || filled) {
		if err = iapReleaseReservation(ctx, tx, user, intentID); err != nil {
			return "", err
		}
	}
	overCap := false
	if inserted && known {
		if overCap, err = iapSettleCap(ctx, tx, user, route, key, s.IAPSandbox, s.IAPRules.Cap); err != nil {
			return "", err
		}
		if err = iapNoteProductGrant(ctx, tx, user, p, iapGrant{Units: product.Units, Target: target, OverCap: overCap}); err != nil {
			return "", err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	// 대상을 모르면 소비하지 않는다. 앱이 대상과 함께 내면 그때 소비하고, 끝내 안 내면 서버가 2일 뒤 환불한다(제출 경로와 같다)
	if inserted && known && !p.Acknowledged {
		if e := iapConfirmAfter(ctx, store, ref, p.ProductID, product.Consume); e != nil {
			log.Printf("iap confirm failed (will retry): route=%s err=%v", route, e)
		} else if e = iapMarkConfirmed(context.WithoutCancel(ctx), s.DB, route, key); e != nil {
			log.Printf("iap confirm not recorded: route=%s err=%v", route, e)
		}
	}
	if !known {
		return "대상을 모르는 구매 기록. 앱이 대상과 함께 제출하면 그 대상에 줌", nil
	}
	if overCap {
		log.Printf("iap over cap: route=%s user=%d target=%s", route, user, target)
		if s.iapRefundOverCap(ctx, store, key, p.TransactionID) {
			return fmt.Sprintf("알림으로 새 구매 기록(대상 %q, 상한 넘음: 주지 않고 환불 요청)", target), nil
		}
		return fmt.Sprintf("알림으로 새 구매 기록(대상 %q, 상한 넘음: 주지 않음, 환불은 사용자 요청 또는 다시 시도)", target), nil
	}
	return fmt.Sprintf("알림으로 새 구매 지급(대상 %q)", target), nil
}

// iapConfirmAfter는 DB 커밋 뒤의 스토어 확인이다. 앞의 조회와 제한 시간을 나눠 쓰지 않게 새로 준다
// iapAlreadyConfirmed는 스토어에 다시 물어 이 거래가 이미 확인(소비)됐는지 본다. 조회에 실패하면 false다.
// 소비해야 하는 구글 상품은 소비까지 됐어야 한다. 확인만 되고 소비 안 된 구매를 끝난 것으로 적으면
// 재시도가 멈추고, 그 상품을 다시 살 수 없게 된다
func iapAlreadyConfirmed(ctx context.Context, store iap.Store, ref iap.Ref, consume bool) bool {
	c, cancel := context.WithTimeout(context.WithoutCancel(ctx), iapStoreTimeout)
	defer cancel()
	p, err := store.Lookup(c, ref)
	if err != nil {
		return false
	}
	if consume && store.Route() == iap.RouteGoogle {
		return p.Consumed
	}
	return p.Acknowledged
}

func iapConfirmAfter(ctx context.Context, store iap.Store, ref iap.Ref, productID string, consume bool) error {
	c, cancel := context.WithTimeout(context.WithoutCancel(ctx), iapStoreTimeout)
	defer cancel()
	return store.Confirm(c, ref, productID, consume)
}

// iapSyncRevoked는 제출에서 스토어가 환불이라고 답한 거래를 알림 처리와 같은 길로 반영한다.
// 요청이 끊겨도 끝까지 하도록 취소를 떼어 낸다(안의 스토어 조회는 각자 제한 시간을 둔다)
func (s *Kit) iapSyncRevoked(ctx context.Context, store iap.Store, kind iap.Kind, ref iap.Ref, originalID string) {
	c := context.WithoutCancel(ctx)
	var note string
	var err error
	if kind == iap.KindSubscription {
		note, err = s.iapSyncSubscription(c, store, originalID)
	} else {
		note, err = s.iapSyncPurchase(c, store, ref)
	}
	if err != nil {
		log.Printf("iap revoked on submit not synced (sweep will retry): route=%s err=%v", store.Route(), err)
		return
	}
	log.Printf("iap revoked on submit: route=%s %s", store.Route(), note)
}
