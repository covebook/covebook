package server

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
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
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

func (s *Server) routeIAPNotify(m *http.ServeMux) {
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
func (s *Server) iapGooglePushAuth() func(ctx context.Context, header string) error {
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

func (s *Server) iapNotify(route iap.Route) handler {
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

func (s *Server) iapWakeUp() {
	select {
	case s.iapWake <- struct{}{}:
	default:
	}
}

// StartIAPWorker는 알림 처리와 대조를 뒤에서 돌린다. 1분마다, 그리고 새 알림이 오면 바로 돈다.
// 서버가 여러 대여도 한 번에 한 곳만 돌게 DB 자문 락을 잡는다.
func (s *Server) StartIAPWorker(ctx context.Context) {
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
func (s *Server) iapSweepSafely(ctx context.Context) {
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

const iapSweepLockKey = 987614003 // migrate.go가 987614002를 쓴다

func (s *Server) iapSweepLocked(ctx context.Context) error {
	conn, err := s.DB.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	var got bool
	if err = conn.QueryRow(ctx, "SELECT pg_try_advisory_lock($1)", iapSweepLockKey).Scan(&got); err != nil || !got {
		return err // 다른 곳에서 돌고 있으면 이번에는 건너뛴다
	}
	defer conn.Exec(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", iapSweepLockKey)
	res, err := s.iapSweep(ctx)
	s.iapLogSweep(ctx, res)
	return err
}

// iapSweepResult는 한 번 돌면서 한 일이다. 숫자가 계속 크면 알림이 안 오고 있다는 신호다(이슈 #39).
type iapSweepResult struct {
	Notices, NoticesFailed, Confirmed, Refreshed int
	Backfilled, Voided                           int // 스토어의 목록으로 메운 알림, 반영한 환불
}

// iapSweep은 밀린 일을 한 번 처리한다: 스토어 확인 재시도, 빠진 알림·환불 메우기, 알림 처리, 만료가 다가온 구독 재확인.
// 순서: 기한이 있는 것(구글 확인 3일)을 가장 먼저 한다. 한 단계가 실패해도 다음 단계는 돈다.
func (s *Server) iapSweep(ctx context.Context) (iapSweepResult, error) {
	var res iapSweepResult
	var firstErr error
	keep := func(err error) {
		if err != nil && firstErr == nil {
			firstErr = err
		}
	}

	// 1. 스토어 확인을 못 마친 거래
	unconfirmed, err := iapUnconfirmedPurchases(ctx, s.DB, 100)
	keep(err)
	for _, u := range unconfirmed {
		store := s.IAP[u.Route]
		if store == nil {
			continue
		}
		ref, consume := iap.Ref{Kind: u.Kind, ID: u.OriginalID}, false
		if u.Kind == iap.KindProduct {
			if p, e := iapFindProduct(ctx, s.DB, u.Route, u.ProductID); e == nil {
				consume = p.Consume
			}
		}
		storeCtx, cancel := context.WithTimeout(ctx, iapStoreTimeout)
		e := store.Confirm(storeCtx, ref, u.ProductID, consume)
		cancel()
		if e != nil {
			log.Printf("iap confirm retry failed: route=%s product=%s err=%v", u.Route, u.ProductID, e)
			continue
		}
		if e = iapMarkConfirmed(ctx, s.DB, u.Route, u.Key); e != nil {
			keep(e)
			continue
		}
		res.Confirmed++
	}

	// 2. 스토어의 목록으로 빠진 알림과 환불을 메운다(6시간에 한 번). 넣은 알림은 바로 아래에서 처리된다
	s.iapCatchUp(ctx, &res)

	// 3. 밀린 알림
	notices, err := iapPendingNotifications(ctx, s.DB, 100)
	keep(err)
	for _, n := range notices {
		result, note := s.iapProcessNotice(ctx, n)
		if result == "failed" {
			res.NoticesFailed++
			log.Printf("iap notification failed (will retry): route=%s id=%s err=%s", n.Route, n.ID, note)
		} else {
			res.Notices++
		}
		keep(iapFinishNotification(ctx, s.DB, n.Route, n.ID, result, note))
	}

	// 4. 만료가 다가왔거나 지난 구독
	due, err := iapDueSubscriptions(ctx, s.DB, 200)
	keep(err)
	for _, d := range due {
		route, original := iap.Route(d[0]), d[1]
		store := s.IAP[route]
		if store == nil {
			// 꺼진 경로의 줄이 매번 맨 앞에 뽑히지 않게 한다
			keep(iapBumpSubscription(ctx, s.DB, route, original))
			continue
		}
		if _, e := s.iapSyncSubscription(ctx, store, original); e != nil {
			log.Printf("iap subscription refresh failed: route=%s err=%v", route, e)
			keep(iapBumpSubscription(ctx, s.DB, route, original))
			continue
		}
		res.Refreshed++
	}
	return res, firstErr
}

// iapProcessNotice는 알림 한 건을 처리하고 결과(processed, ignored, failed)와 메모를 돌려준다.
func (s *Server) iapProcessNotice(ctx context.Context, n iapNoticeRow) (result, note string) {
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
		for _, key := range []string{n.TargetID, n.OrderID} {
			if key == "" {
				continue
			}
			if _, err := iapRevokePurchase(ctx, s.DB, n.Route, key, now); err != nil {
				return "failed", err.Error()
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
func (s *Server) iapBasics(ctx context.Context, store iap.Store, p iap.Purchase) error {
	products, err := iapProductSet(ctx, s.DB, store.Route())
	if err != nil {
		return err
	}
	p.State = iap.StatePaid
	return iap.Check(p, iap.Expect{BundleID: store.AppID(), Products: products, AccountTokens: []string{strings.ToLower(p.AccountToken)}, AllowSandbox: s.IAPSandbox})
}

// iapSyncSubscription은 구독 줄기를 스토어에 다시 묻고 우리 표를 그 답으로 맞춘다.
//   - 줄이 있으면 상태만 고친다. 주인은 그대로다(주인은 우리 표가 정한다. 스토어의 계정 연결 값은 옮긴 뒤에도 옛 값이다).
//   - 줄이 없으면(앱이 제출하기 전에 알림이 먼저 옴, 앱 밖 구매) 계정 연결 값으로 주인을 찾아 만든다. 못 찾으면 만들지 않는다.
func (s *Server) iapSyncSubscription(ctx context.Context, store iap.Store, originalID string) (string, error) {
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

	tx, err := s.DB.Begin(ctx)
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
			if err = iapNotePurchaseDone(ctx, tx, user, iap.KindSubscription, cur, 0); err != nil {
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
		if _, err = iapRecordPurchase(ctx, tx, user, iap.KindSubscription, cur); err != nil {
			return "", err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	// 알림만으로 지급한 새 구독은 여기서 스토어 확인을 한다(앱이 꺼져 있어도 3일 기한을 지키게).
	if granted && cur.State == iap.StatePaid && !cur.Acknowledged {
		if e := store.Confirm(storeCtx, iap.Ref{Kind: iap.KindSubscription, ID: sub.OriginalID}, cur.ProductID, false); e != nil {
			log.Printf("iap confirm failed (will retry): route=%s err=%v", route, e)
		} else if e = iapMarkConfirmed(ctx, s.DB, route, key); e != nil {
			log.Printf("iap confirm not recorded: route=%s err=%v", route, e)
		}
	}
	return note, nil
}

// iapSyncPurchase는 거래 하나를 스토어에 다시 묻고 원장의 환불 상태를 맞춘다.
// 한 번 사는 상품이 원장에 없으면(앱이 제출하기 전에 알림이 먼저 옴) 계정 연결 값으로 주인을 찾아 지급한다.
func (s *Server) iapSyncPurchase(ctx context.Context, store iap.Store, ref iap.Ref) (string, error) {
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
	changed, err := iapSyncPurchaseState(ctx, s.DB, route, key, p.State, p.RevokedAt)
	if err != nil {
		return "", err
	}
	if changed {
		if p.State == iap.StateRevoked {
			return "환불 반영", nil
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
	// 원장과 결제 완료 고지(T3)를 한 트랜잭션에 쓴다
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	inserted, err := iapRecordPurchase(ctx, tx, user, iap.KindProduct, p)
	if err != nil {
		return "", err
	}
	if inserted {
		if err = iapNotePurchaseDone(ctx, tx, user, iap.KindProduct, p, product.Shelves); err != nil {
			return "", err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	if inserted && !p.Acknowledged {
		if e := store.Confirm(storeCtx, ref, p.ProductID, product.Consume); e != nil {
			log.Printf("iap confirm failed (will retry): route=%s err=%v", route, e)
		} else if e = iapMarkConfirmed(ctx, s.DB, route, key); e != nil {
			log.Printf("iap confirm not recorded: route=%s err=%v", route, e)
		}
	}
	return "알림으로 새 구매 지급", nil
}
