// Package iapkit은 앱 안 결제(애플 App Store, 구글 Play)의 서버 쪽이다. 구매 확인, 원장, 스토어 알림, 정기 대조, 환불, 결제 고지를 맡는다.
// 앱마다 다른 것(무엇을 파는지, 한 번 사는 상품이 붙는 대상과 상한, 오류 문구)은 Rules로 받는다.
// 붙이는 법과 경계는 README.md에 있다. 결정 기록: docs/adr/0001, 0002(책장 한켠 저장소).
package iapkit

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit/iap"
)

// Kit은 결제 서버 하나다. New로 만들고 Routes로 경로를 붙이고 StartWorker로 정기 처리를 돌린다.
type Kit struct {
	DB         *pgxpool.Pool
	IAP        map[iap.Route]iap.Store // 결제 경로. 비어 있으면 결제 API가 없다
	IAPSandbox bool                    // 샌드박스 거래에도 지급할지 (IAP_ALLOW_SANDBOX)
	IAPRules   Rules                   // 앱마다 다른 결제 규칙(대상·상한·문구)
	// Auth는 요청의 로그인한 유저 번호를 준다. 앱의 인증을 그대로 쓴다. ok가 false면 Auth가 이미 오류 응답을 썼다
	Auth func(w http.ResponseWriter, r *http.Request) (user int64, ok bool)
	// Admin은 운영자 요청인지 본다(GET /admin/iap/stats). nil이거나 false면 없는 경로처럼 404다
	Admin func(r *http.Request) bool
	// HTTP는 구글 알림 인증서를 받을 때 쓴다
	HTTP *http.Client

	iapMu        sync.Mutex
	iapHits      map[int64]iapHit
	iapRenewalAt time.Time                                             // 갱신 예정 고지를 마지막으로 찾은 때
	iapCatchUpAt map[iap.Route]time.Time                               // 경로마다 스토어 목록으로 메우기를 마지막으로 돌린 때
	iapLoggedAt  time.Time                                             // 대조 요약 로그를 마지막으로 남긴 때
	iapWake      chan struct{}                                         // 새 알림이 오면 처리 작업을 깨운다
	iapPushAuth  func(ctx context.Context, authorization string) error // 구글 알림 요청의 인증 확인. 없으면 구글 알림을 받지 않는다
}

// New는 결제 서버를 만든다. stores가 비어 있으면 결제를 끈 것이다(경로도 정기 처리도 없다).
// 구글 경로가 있으면 구글 알림 요청의 인증 설정(IAP_GOOGLE_PUSH_AUDIENCE, IAP_GOOGLE_PUSH_EMAIL)을 환경 변수에서 읽는다.
func New(db *pgxpool.Pool, stores map[iap.Route]iap.Store, rules Rules, sandbox bool) *Kit {
	k := &Kit{DB: db, IAP: stores, IAPRules: rules, IAPSandbox: sandbox, HTTP: &http.Client{Timeout: 8 * time.Second}, iapWake: make(chan struct{}, 1)}
	if stores[iap.RouteGoogle] != nil {
		k.iapPushAuth = k.iapGooglePushAuth()
	}
	return k
}

// Enabled는 결제 경로가 하나라도 켜져 있는지다.
func (s *Kit) Enabled() bool { return s != nil && len(s.IAP) > 0 }

// Routes는 결제 API와 스토어 알림 주소를 붙인다. 결제가 꺼져 있으면 아무것도 붙이지 않는다.
func (s *Kit) Routes(m *http.ServeMux) {
	if !s.Enabled() {
		return
	}
	s.routeIAP(m)
	s.routeIAPNotify(m)
}

// StartWorker는 정기 대조(알림 처리 재시도, 스토어 확인, 환불, 갱신 고지)를 돌린다. 결제가 꺼져 있으면 아무 일도 하지 않는다.
func (s *Kit) StartWorker(ctx context.Context) {
	if !s.Enabled() {
		return
	}
	s.StartIAPWorker(ctx)
}

// user는 요청의 유저다. 앱의 Auth가 응답을 썼으면 errAnswered를 돌려 wrap이 더 쓰지 않게 한다.
func (s *Kit) user(w http.ResponseWriter, r *http.Request) (int64, error) {
	if s.Auth == nil {
		return 0, unauthorized
	}
	u, ok := s.Auth(w, r)
	if !ok {
		return 0, errAnswered
	}
	return u, nil
}

// adminOK는 운영자 요청인지다.
func (s *Kit) adminOK(r *http.Request) bool { return s.Admin != nil && s.Admin(r) }

// --- HTTP 도우미. 오류 응답 모양은 {"error":{"code","message"}}다(책장 한켠 서버와 같다).

type apiError struct {
	status        int
	code, message string
}

func (e apiError) Error() string { return e.message }

var (
	bad          = apiError{400, "bad_request", "요청 형식이 올바르지 않아요"}
	unauthorized = apiError{401, "unauthorized", "로그인이 필요해요"}
	notFound     = apiError{404, "not_found", "찾을 수 없어요"}
	// errAnswered는 Auth가 이미 응답을 썼다는 뜻이다
	errAnswered = errors.New("iapkit: response already written")
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, err error) {
	if errors.Is(err, errAnswered) {
		return
	}
	var ae apiError
	if !errors.As(err, &ae) {
		var pe *pgconn.PgError
		switch {
		case errors.As(err, &pe) && (strings.HasPrefix(pe.Code, "23") || strings.HasPrefix(pe.Code, "22")):
			ae = bad
		case errors.Is(err, pgx.ErrNoRows):
			ae = notFound
		case iapDBBusy(err):
			// 잠금을 기다리다 끊김(iapBegin의 제한 시간). 5xx라 앱은 거래를 끝내지 않고 다시 낸다
			log.Printf("iap request busy: %v", err)
			ae = apiError{503, "iap_busy", "잠시 뒤 다시 시도해 주세요"}
		default:
			log.Printf("iap request failed: %v", err)
			ae = apiError{500, "internal_error", "서버 오류가 발생했어요"}
		}
	}
	writeJSON(w, ae.status, map[string]any{"error": map[string]string{"code": ae.code, "message": ae.message}})
}

type handler func(http.ResponseWriter, *http.Request) error

func wrap(h handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			fail(w, err)
		}
	}
}

func decode(r *http.Request, v any) error {
	if err := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20)).Decode(v); err != nil {
		return bad
	}
	return nil
}
