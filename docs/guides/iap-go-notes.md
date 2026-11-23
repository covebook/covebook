# 결제 서버 학습 노트 (Java 개발자가 Go로)

- 시작일: 2026-11-18
- 읽는 사람: Java·Spring은 알고 Go는 처음인 사람
- 쓰는 법: 결제 이슈를 하나 끝낼 때마다 그때 필요했던 것을 장으로 추가. 맨 아래 "진행 기록"에 날짜와 이슈 번호를 남김
- 결정 기록: [ADR-0001](../adr/0001-iap-server-go.md), [ADR-0002](../adr/0002-iap-design.md)
- 확인 수준: 코드 인용은 이 저장소와 `go-iap` v1.59.1 소스를 직접 읽은 것. 외부 사실은 10장에 출처와 확인 여부를 적음

## 0. 지금 어디까지

| 이슈 | 내용 | 상태 | 어디에 |
|---|---|---|---|
| #9 | `go-iap` 도입, 결제 경로 인터페이스 | 끝. main에 있음 | `server/internal/iap/` |
| #8 | 테이블 (V21) | PR #21 | `migrations/V21__iap.sql`, `iap_store.go` |
| #10 | 구매 검증 API | PR #43 (#21 위에) | `iap.go` |
| #11, #12, #26 | 스토어 알림 수신, 정기 대조 | PR #44 (#43 위에) | `iap_notify.go` |
| #13 이후 | 앱 화면 | 시작 전 | |

- PR은 #21 → #43 → #44 순서로 쌓여 있음. 아래 것부터 머지
- 읽는 순서: 이 노트 10장(요청 하나가 지나가는 길) → PR #43의 `iap.go` → PR #44의 `iap_notify.go`
- `Check`는 PR #43에 구현해 넣음 (커밋 하나로 따로). 직접 다시 써 보려면 그 커밋만 되돌림

## 1. 매일 쓰는 명령

| 하고 싶은 것 | 명령 (`server/`에서) | Java로 치면 |
|---|---|---|
| 전체 테스트 | `go test ./...` | `./gradlew test` |
| 한 패키지만, 자세히 | `go test -v ./internal/iap` | |
| 테스트 하나만 | `go test -run TestCheck ./internal/iap` | |
| 정적 검사 | `go vet ./...` | |
| 줄 맞춤 | `gofmt -w internal/iap` | 포매터. 팀 설정 없이 하나뿐 |
| 서버 실행 | `DATABASE_URL=... go run ./cmd/server` | `bootRun` |
| 의존성 추가 | `go get 모듈@버전` 뒤 `go mod tidy` | `build.gradle` 수정 |
| 문서 보기 | `go doc 패키지 이름` | Javadoc |

- `./...`은 "이 폴더 아래 모든 패키지"
- DB 통합 테스트는 `TEST_DATABASE_URL`이 있을 때만 돎. 없으면 건너뜀. 실제 DB를 넣지 않음
- 버릴 DB를 로컬에 띄워 돌리는 법 (Homebrew의 PostgreSQL 기준)

```sh
initdb -D /tmp/pgtest -U test --auth=trust
pg_ctl -D /tmp/pgtest -o "-p 55432" -w start
psql -h 127.0.0.1 -p 55432 -U test -d postgres -c "CREATE DATABASE iaptest"
TEST_DATABASE_URL='postgres://test@127.0.0.1:55432/iaptest?sslmode=disable' go test ./...
pg_ctl -D /tmp/pgtest stop
```

- 주의: `TestCommunity`는 같은 DB에서 두 번째 실행하면 실패함 (고정된 이름을 씀). 다시 돌릴 때는 DB를 지우고 새로 만듦
- `-count=1`: 캐시된 결과를 쓰지 않고 다시 실행. DB 테스트에 붙임
- `go.mod`가 Java의 `build.gradle`, `go.sum`이 의존성 잠금 파일. 둘 다 커밋

## 2. Java와 다른 것 한눈에

| Java·Spring | Go (이 서버) |
|---|---|
| 클래스, 상속 | `struct`와 메서드. 상속 없음 |
| `implements` 선언 | 선언 없음. 메서드가 맞으면 구현 (4장) |
| `public` / `private` | 이름 첫 글자. 대문자면 패키지 밖에 공개, 소문자면 패키지 안에서만 |
| 예외 `throw` / `try-catch` | 함수가 `error`를 값으로 돌려줌 (3장) |
| `null` | `nil`. 값 타입(`struct`, `string`, `int`)은 `nil`이 없고 "zero 값"이 있음 |
| `@Transactional` | `Begin` / `Commit` / `Rollback`을 직접 (6장) |
| JPA | SQL을 직접 씀 (`pgx`) |
| DI 컨테이너 | 없음. 생성할 때 필드에 넣어 줌 |
| Mockito | 작은 인터페이스 + 손으로 쓴 가짜 (4장) |
| `Optional<T>` | 값과 `bool` 또는 값과 `error`를 같이 돌려줌 |

- zero 값: 선언만 하고 값을 안 넣으면 `string`은 `""`, 숫자는 `0`, `time.Time`은 `IsZero()`가 참인 값
  - `Purchase.ExpiresAt`이 "없음"일 때 `null` 대신 zero 값을 씀 (`server/internal/iap/iap.go`)
- 패키지 = 폴더. 한 폴더의 `.go` 파일은 전부 같은 패키지라 서로 소문자 이름도 보임
- `internal/` 아래 패키지는 이 모듈 밖에서 가져다 쓸 수 없음. 컴파일러가 막음

## 3. 오류 처리

- 예외가 없음. 실패할 수 있는 함수는 마지막 반환값이 `error`

```go
p, err := store.LookupTransaction(ctx, id)
if err != nil {
    return err
}
```

- 확인을 빼먹으면 컴파일은 되고, 실패한 채로 다음 줄이 실행됨. Java에서 가장 다른 점
- 감싸기: `fmt.Errorf("apple 거래 조회 %s: %w", id, err)`. `%w`가 원래 오류를 안에 넣어 둠. Java의 `new XException("...", cause)`
- 구분하기: `errors.Is(err, iap.ErrNotFound)`. 여러 번 감싸도 안쪽까지 찾아봄. `catch (NotFoundException e)` 자리
- 미리 만들어 둔 오류 값: `var ErrNotFound = errors.New("...")`. 이름은 `Err`로 시작
- 이 저장소의 예
  - `server/internal/iap/apple.go`: "스토어에 없는 거래"와 "통신 실패"를 다른 오류로 돌려줌
  - 이유: 없는 거래는 거절, 통신 실패는 다시 시도. 둘을 섞으면 스토어가 잠깐 느릴 때 정상 구매를 거절하게 됨
- HTTP 핸들러 쪽: `apiError`를 만들어 `fail(w, err)`로 응답 (`server/internal/server/server.go`)

## 4. 인터페이스와 가짜

- Go 인터페이스는 메서드 목록일 뿐이고, 구현하는 쪽이 "구현한다"고 적지 않음
- 그래서 **쓰는 쪽**이 필요한 메서드만 골라 인터페이스를 선언함. Go 코드 리뷰 지침도 같은 말 (10장)
- 이 저장소의 예 (`server/internal/iap/apple.go`)

```go
type appleAPI interface {
    GetTransactionInfo(ctx context.Context, transactionID string) (*api.TransactionInfoResponse, error)
    ParseSignedTransaction(signed string) (*api.JWSTransaction, error)
}
```

  - `go-iap` 클라이언트는 메서드가 30개쯤이지만 우리는 둘만 씀
  - 테스트는 이 둘만 가진 `fakeAppleAPI`를 끼움 (`apple_test.go`). 네트워크 없이 돎
- 인터페이스를 한 번 고쳤음 (2026-11-18)
  - 처음: `LookupTransaction(거래ID)`. 애플만 보고 만든 모양
  - 구글을 붙이니 안 맞음. 구글은 거래 ID가 아니라 구매 토큰으로 묻고, 구독과 한 번 사는 상품의 조회 주소가 다름
  - 지금: `Lookup(ctx, Ref{Kind, ID})`
  - 배운 것: 구현이 하나일 때 만든 인터페이스는 그 구현의 모양을 닮음. 두 번째 구현이 생길 때 고치는 것이 정상
- 인터페이스가 두 겹
  - 안쪽 `appleAPI`: 라이브러리를 가림. `apple.go` 안에서만 보임
  - 바깥 `Store`: 애플·구글을 가림. 서버의 다른 코드는 이것만 봄
- "구현했는지" 컴파일 때 확인하는 관용구 (`fake.go`)

```go
var _ Store = (*Apple)(nil)
```

- 라이브러리 타입을 밖으로 내보내지 않음. `fromApple`이 `api.JWSTransaction`을 우리 타입 `Purchase`로 바꿈
  - 라이브러리를 바꾸거나 구글을 붙여도 나머지 코드는 그대로

### 4-1. 이번에 쓴 문법

| 문법 | 예 | 뜻 |
|---|---|---|
| `errors.As` | `var ge *googleapi.Error; errors.As(err, &ge)` | 감싼 오류 속에서 그 **타입**을 찾아 꺼냄. `catch (GoogleException e)`로 받아 `e.getCode()`를 보는 것 |
| `switch` | `switch ref.Kind { case KindSubscription: ... }` | `break`가 필요 없음. 맞는 `case` 하나만 실행 |
| 맵 | `map[string]bool`, `m[k]` | 없는 키는 zero 값(`false`, `""`, `0`). 있는지까지 보려면 `v, ok := m[k]` |
| 슬라이스 | `[]string`, `append(s, x)`, `len(s)` | `ArrayList` |
| 함수를 인자로 | `FromEnv(getenv func(string) string)` | 실제로는 `os.Getenv`, 테스트에서는 가짜 환경을 넘김 |
| 포인터와 `nil` 확인 | `if s.TestPurchase != nil` | 스토어 응답의 선택 칸은 포인터. 확인 없이 `.`으로 들어가면 죽음(Java의 NPE) |

- 모르는 값은 안전한 쪽으로: `subscriptionState`는 아는 상태만 "결제됨"으로 보고 나머지는 전부 "권한 없음" (`google.go`). 구글이 상태를 새로 추가해도 공짜 지급이 안 됨

## 5. `context`

- 함수 첫 인자로 넘기는 `ctx context.Context`. 요청 하나의 "취소 신호와 시간 제한"
- 클라이언트가 연결을 끊으면 `r.Context()`가 취소되고, 그 `ctx`를 받은 DB 쿼리와 HTTP 호출이 같이 멈춤
- Java에는 딱 맞는 것이 없음. 스레드 인터럽트와 요청 범위 값을 합친 것에 가까움
- 규칙: 받은 `ctx`를 아래 함수에 그대로 넘김. 구조체 필드에 저장하지 않음
- 주의: 지급 트랜잭션은 요청이 끊겨도 끝까지 가야 하는지 #10에서 정해야 함. 정하면 여기에 추가

## 6. 트랜잭션

- 이 서버의 모양 (`server/internal/server/server.go:147`)

```go
tx, err := s.DB.Begin(ctx)
if err != nil {
    return err
}
defer tx.Rollback(ctx)

if _, err = tx.Exec(ctx, `INSERT ...`, a, b); err != nil {
    return err              // 여기서 나가면 defer가 롤백
}
return tx.Commit(ctx)
```

- `defer`: 함수가 끝날 때 실행. Java의 `finally`
- 커밋 뒤의 `Rollback`은 아무 일도 안 함. `pgx` 문서: 이미 닫힌 트랜잭션이면 `ErrTxClosed`를 돌려줄 뿐이라 `defer tx.Rollback()`이 안전하다고 적혀 있음 (`go doc github.com/jackc/pgx/v5 Tx.Rollback`으로 확인)
- `defer`는 `Begin`의 오류 확인 **뒤**에 둠. 앞에 두면 `Begin`이 실패했을 때 `nil`에 대고 롤백을 부름
- 자주 틀리는 것

| 실수 | 결과 |
|---|---|
| 트랜잭션 안에서 `tx.Exec` 대신 `s.DB.Exec` | 컴파일·실행 다 되는데 그 쿼리만 트랜잭션 밖에서 따로 커밋됨 |
| `err` 확인 누락 | 실패한 쿼리 뒤의 쿼리가 계속 실행됨 |
| 트랜잭션 안에서 외부 HTTP 호출 | 그동안 DB 연결과 락을 쥐고 있음 |

- Spring은 트랜잭션을 스레드에 묶어 줘서 어디서 쿼리를 불러도 같은 트랜잭션. Go는 `tx` 변수를 직접 들고 다님
- 행 잠금: `SELECT ... FOR UPDATE` (`server/internal/server/sync.go:123`). `@Lock(PESSIMISTIC_WRITE)` 자리
- 중복 방지: 유일 키 + `INSERT ... ON CONFLICT DO NOTHING` (`server/internal/server/native.go:32`)
  - "먼저 조회하고 없으면 넣기"는 같은 요청이 동시에 두 번 오면 둘 다 "없음"을 봄
  - DB의 유일 키에 맡기고, 실제로 들어간 행 수로 판단
- 결제에서 쓸 순서 (#10에서 구현)
  1. 트랜잭션 밖: 스토어에 조회, `Check`
  2. 짧은 트랜잭션: 거래 기록 `INSERT ... ON CONFLICT DO NOTHING` → 들어갔을 때만 권한 지급 → 커밋
  3. 커밋 뒤: 스토어에 확인(acknowledge) (ADR-0002 D10)

### 6-1. 결제 테이블에서 쓴 것 (V21, `server/internal/server/iap_store.go`)

| 하고 싶은 것 | 쓴 방법 | Java·JPA로 치면 |
|---|---|---|
| 같은 거래를 두 번 넣지 않기 | `INSERT ... ON CONFLICT (route, transaction_id) DO NOTHING` 뒤 `tag.RowsAffected() == 1` | `save` 전에 `existsBy...`를 하는 대신 유일 키에 맡김 |
| 있으면 고치고 없으면 넣기 | `ON CONFLICT (...) DO UPDATE SET x = EXCLUDED.x` | `merge` |
| 동시에 두 개 생기지 않게 | `SELECT id FROM users WHERE id=$1 FOR UPDATE`로 유저 줄을 먼저 잠금 | `@Lock(PESSIMISTIC_WRITE)` |
| 트랜잭션 안팎 어디서나 부를 함수 | `dbtx` 인터페이스 (`Exec`, `Query`, `QueryRow`)를 인자로 받음. 풀과 `tx`가 둘 다 맞음 | `EntityManager`를 받는 것 |
| 빈 값을 NULL로 | SQL에서 `nullif($1, '')` | |
| NULL일 수 있는 칸 읽기 | 포인터로 받음: `var owner *int64` | `Long` (박싱 타입) |
| 계정을 지워도 기록은 남기기 | 외래 키를 `ON DELETE SET NULL` | `@OnDelete` 없이 연관만 끊기 |

- 권한은 저장하지 않고 계산 (ADR-0002 D5): `iapEntitlements`가 구독 테이블과 거래 테이블에서 매번 셈. 원장과 "가진 것"이 어긋날 수 없음
- 만료 판단은 SQL의 `now()` (DB 서버 시계). 앱 서버가 여러 대여도 기준이 하나
- 동시성은 테스트로 확인: 같은 거래를 고루틴 10개가 동시에 넣고 "처음 들어갔다"는 답이 1번인지 봄 (`iap_store_test.go`)
  - 고루틴: `go func() { ... }()`. 가벼운 스레드. `sync.WaitGroup`으로 끝나기를 기다림 (`CountDownLatch` 자리)

## 7. 내가 채울 것: `Check`

- 위치: `server/internal/iap/check.go`
- 역할: 스토어가 "진짜 거래"라고 확인해 준 뒤, 그 거래가 **이 요청**에 지급해도 되는 것인지 봄. 라이브러리의 서명 검증 뒤에 두는 두 번째 방어선 (ADR-0001 결정 9)
- 막는 것

| 검사 | 막는 상황 |
|---|---|
| 번들 ID | 다른 앱에서 산 진짜 거래를 우리 서버에 제출 |
| 상품 ID | 우리가 팔지 않는 상품, 오타 |
| 상태 (`State`) | 환불받은 거래를 다시 제출, 결제 대기 중인 거래(구글 편의점 결제 등)에 미리 지급 |
| 계정 값 | 남의 거래 ID를 자기 계정으로 제출 |

- 정할 것 1: 거래의 `AccountToken`이 비어 있을 때
  - 막기: 안전함. 다만 앱을 거치지 않은 구매는 이 값이 없음 (App Store에서 직접 한 구독, 프로모션 코드 등). 그런 구매자가 지급을 못 받음
  - 통과: 편함. 다만 남의 거래 ID를 알면 자기 계정에 붙일 수 있음. 거래 ID 유일 키가 "한 번만"은 막아 주지만 "누구에게"는 못 막음
  - 절충: `Check`에서는 막고, 빈 값 거래는 따로 "복원" 경로에서만 받음 (#13). 이렇게 하려면 오류를 하나 더 만들어 구분해야 함
- 정할 것 2: 여러 개가 동시에 틀렸을 때 순서
  - 로그에 남는 오류가 원인 파악에 쓰임. 가장 근본적인 것(다른 앱)부터 보는 것이 보통
- 확인 방법
  - `go test -v -run TestCheck ./internal/iap`
  - 지금은 "먼저 채운다"로 건너뜀. 채우면 테이블의 경우들이 돎
  - `check_test.go`의 테이블에 빈 `AccountToken` 경우를 한 줄 추가
- 쓸 문법
  - `if p.BundleID != want.BundleID { return ErrWrongApp }`
  - 맵 조회: `want.Products[p.ProductID]`는 없으면 `false`
  - `p.State != StatePaid`. 환불(`StateRevoked`)만 `ErrRevoked`, 나머지는 `ErrNotPaid`

## 8. 테스트 쓰는 법

- 파일 이름이 `_test.go`로 끝나고 함수가 `TestXxx(t *testing.T)`면 테스트. 프레임워크 없음
- 실패 알림: `t.Fatalf("...")`. 단정문 라이브러리를 쓰지 않고 `if`로 비교
- 테이블 주도 테스트(table-driven test, `check_test.go`): 경우를 구조체 목록으로 늘어놓고 `t.Run(이름, ...)`으로 돌림. JUnit의 `@ParameterizedTest`
- 가짜: 인터페이스를 구현한 작은 구조체를 손으로 씀 (`fake.go`, `apple_test.go`)
- 다른 패키지에서 결제를 테스트할 때는 `iap.Fake`에 거래를 넣어 두고 씀

## 9. `go-iap`에서 실제로 쓰는 것

- 버전: v1.59.1. 이 아래로 내리지 않음 (서명 검증 보완이 여기 들어감, ADR-0001 부록 C)
- 애플 (`github.com/awa/go-iap/appstore/api`)

| 함수 | 하는 일 |
|---|---|
| `NewStoreClientWithSandboxFallback(cfg)` | 운영에 먼저 묻고, "거래 없음"이나 401이면 샌드박스에 다시 물음 |
| `GetTransactionInfo(ctx, 거래ID)` | 거래 조회. 응답은 서명된 문자열 하나 |
| `ParseSignedTransaction(문자열)` | 서명·인증서를 확인하고 `JWSTransaction`으로 풂 |
| `TransactionIdNotFoundError` | "그 거래 없음" 오류 값. `errors.Is`로 비교 |

- 받은 값에서 쓰는 칸: `TransactionID`, `OriginalTransactionId`, `BundleID`, `ProductID`, `AppAccountToken`, `Environment`, `PurchaseDate`, `ExpiresDate`, `RevocationDate`, `Price`, `Currency`, `Storefront`
- `Price`는 통화 단위의 1000배 정수. 12990이면 12.99. 64비트 정수로 저장
- 시각은 밀리초. `time.UnixMilli(ms).UTC()`로 바꿈 (ADR-0002 D23)
- 설정 값 4개: `.p8` 키 내용, 키 ID, 발급자 ID, 번들 ID. 환경변수로만 넣고 저장소·이슈·PR에 적지 않음
- 구글 (`github.com/awa/go-iap/playstore`, 안쪽은 구글 공식 `androidpublisher` 클라이언트)

| 함수 | 하는 일 |
|---|---|
| `New(서비스계정JSON)` | 클라이언트 생성. 만들 때 구글에서 접근 토큰을 한 번 받아 옴 (키가 틀리면 여기서 실패) |
| `VerifySubscriptionV2(ctx, 패키지, 토큰)` | 구독 조회 |
| `VerifyProductV2(ctx, 패키지, 토큰)` | 한 번 사는 상품 조회 |
| `AcknowledgeSubscription`, `AcknowledgeProduct`, `ConsumeProduct` | 확인·소비. #10에서 붙임 |

- 애플과 다른 점 (라이브러리와 구글 클라이언트 타입 정의를 읽어 확인)

| 항목 | 애플 | 구글 |
|---|---|---|
| 무엇으로 묻나 | 거래 ID | 구매 토큰 |
| 구독·일회성 상품 | 같은 주소 | 주소가 다름. 종류를 알려 줘야 함 |
| 응답의 금액·통화 | 있음 (1000배 정수) | 없음. 주문 조회 API가 따로 있음 |
| 계정 연결 값 | `appAccountToken` | `obfuscatedExternalAccountId` |
| 시각 형식 | 밀리초 숫자 | RFC 3339 문자열 |
| 국가 코드 | `storefront` (세 글자, ISO 3166-1 alpha-3) | `regionCode` (두 글자, alpha-2). 국가 칸에 두 형식이 섞여 들어감 |
| 시험 구매 표시 | `environment`가 Sandbox | `testPurchase` 칸이 있음 |
| 요금제 | 상품 ID가 곧 요금제 | 구독 1개 아래 요금제(`basePlanId`) |
| 결제 대기 상태 | 없음 | 있음 (`PENDING`). 지급하면 안 됨 |
| "없는 거래" | `TransactionIdNotFoundError` | HTTP 404, 410 |

- 구글 구독 상태 → 우리 상태: 이용 중·유예 기간·해지 예약은 "결제됨", 결제 대기는 "대기", 보류·일시정지·만료·모르는 값은 "권한 없음"

### 9-0. `Store`가 하는 일 네 가지

| 메서드 | 언제 부르나 | 애플 | 구글 |
|---|---|---|---|
| `Lookup(ref)` | 앱이 거래를 제출했을 때 | 거래 조회 | 구독 조회 또는 상품 조회 |
| `Subscription(원 거래 ID)` | 알림을 받았을 때, 정기 대조에서 | 구독 상태 조회. 상태 값 1·4만 권한 있음 | `Lookup`과 같은 조회 |
| `Confirm(ref, 상품 ID, 소비 여부)` | DB 커밋 뒤 | 할 일 없음 (앱이 거래를 끝냄) | 확인 또는 소비. 3일 안에 안 하면 자동 환불 |
| `ParseNotice(본문)` | 스토어 알림을 받았을 때 | 서명 확인 뒤 알림 ID와 다시 물어볼 거래를 꺼냄 | 알림 ID와 구매 토큰을 꺼냄 |

- 알림에서 꺼내는 것은 "무엇을 다시 물어볼지"뿐. 상태는 `Lookup`·`Subscription`의 답으로 정함 ([조사 종합 3-4장](../reports/2026-11-19-iap-pitfalls.md))
- `ParseNotice`는 인터페이스에 넣지 않음. 애플과 구글의 본문 모양이 달라 받는 쪽이 각각 부름
- 애플 알림의 서명 확인은 `Apple` 구조체의 함수 칸(`verifyNotice`)에 들어 있음. 테스트는 이 칸을 가짜로 바꿔 끼움. 인터페이스를 따로 만들지 않고 함수 하나를 바꿔 끼우는 방법

### 9-1. 스토어 키 넣는 법

- 환경변수 6개. 이름은 `server/.env.example`에 있음. 값은 KoDeploy 환경에만 넣음
- 한 스토어의 값이 전부 비면 그 스토어는 꺼짐. 일부만 있으면 서버가 오류를 냄 (`config.go`의 `FromEnv`)
- 키 내용은 그대로 넣거나 base64로 넣음. 여러 줄 값을 못 넣는 환경 때문
- 오류 메시지에는 빠진 변수 **이름**만 나옴. 값은 로그에 남기지 않음

## 10. 출처와 확인 수준

| 내용 | 출처 | 확인 |
|---|---|---|
| `go-iap` 함수와 동작 | v1.59.1 소스 (`appstore/api/store.go`, `store_fallback.go`, `model.go`) | 직접 읽음 |
| `pgx`의 `Rollback` 동작 | `go doc github.com/jackc/pgx/v5 Tx.Rollback` | 직접 읽음 |
| 애플 `price`가 1000배 단위 | [애플 문서 price](https://developer.apple.com/documentation/appstoreserverapi/price), [개발자 포럼](https://developer.apple.com/forums/thread/767978) | 원문 확인. 3300원이면 3300000 |
| `storefront` 코드 형식 | [애플 문서 storefront](https://developer.apple.com/documentation/appstoreserverapi/storefront) | 원문 확인. ISO 3166-1 alpha-3 |
| `appAccountToken`이 갱신·변경에서 유지되는지 | 애플 포럼 | 관측이 엇갈림. 샌드박스에서 확인 (이슈 #41) |
| 인터페이스는 쓰는 쪽 패키지에 | [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) | 원문 확인. "Go interfaces generally belong in the package that uses values of the interface type, not the package that implements those values." |
| 오류를 `_`로 버리지 않음 | 같은 문서 Handle Errors 절 | 원문 확인. "Do not discard errors using `_` variables." |
| 커밋 뒤 `defer` 롤백은 아무 일도 안 함 | [Executing transactions](https://go.dev/doc/database/execute-transactions) | 원문 확인. "If the transaction succeeds, it will be committed before the function exits, making the deferred rollback call a no-op." |
| `%w`와 `errors.Is` | [Working with Errors in Go 1.13](https://go.dev/blog/go1.13-errors) | 원문 확인. 감싼 오류의 사슬 전체를 따라가며 비교함 |
| `defer` 위치 실수 | [DEV 글](https://dev.to/mark_saward/go-footguns-go-defer-and-rust-drop-17af) | 검색 결과 요약으로 확인 |

- 애플 문서 읽는 법: 문서 주소 뒤에 `.md`를 붙이면 본문이 읽힘. 일반 주소는 도구로 열면 제목만 나옴
- 결제에서 신경 쓸 것 전체: [조사 종합](../reports/2026-11-19-iap-pitfalls.md)
- 더 읽을 것
  - [A Tour of Go](https://go.dev/tour/): 문법 전체. 반나절
  - [Effective Go](https://go.dev/doc/effective_go): 관용적인 쓰기
  - [Executing transactions](https://go.dev/doc/database/execute-transactions): 표준 라이브러리 기준 트랜잭션. 이 서버는 `pgx`지만 모양이 같음
  - [Working with Errors in Go 1.13](https://go.dev/blog/go1.13-errors): `%w`, `errors.Is`, `errors.As`

## 10. 요청 하나가 지나가는 길 (PR #43, #44)

### 10-1. 구매 제출 `POST /iap/purchases` (`iap.go`의 `iapSubmit`)

| 단계 | 하는 일 | DB 트랜잭션 | 실패하면 |
|---|---|---|---|
| 1 | 우리 상품 테이블에서 종류를 찾음 | 없음 | 422 |
| 2 | 구매 증거 확인(애플은 서명) 뒤 스토어에 조회 | **없음** | 없는 거래 404, 조회 실패 503 |
| 3 | `iap.Check`로 지급해도 되는지 봄 | 없음 | 409, 422, 결제 대기는 202 |
| 4 | 유저 줄 잠금 → 주인 확인 → 원장에 넣기 → 커밋 | 짧게 | 롤백 |
| 5 | 스토어 확인(구글) | 없음 | 지급은 유지, 나중에 다시 시도 |

- 2단계가 트랜잭션 밖인 이유: 스토어가 15초 걸리면 그동안 DB 연결과 락을 쥐고 있게 됨. 6장의 "외부 호출은 트랜잭션 밖"
- 4단계가 유저 줄을 잠그는 이유: 같은 유저의 요청 두 개가 동시에 주인 확인을 하지 않게
- 5단계가 커밋 뒤인 이유: 확인을 먼저 하고 커밋이 실패하면 "지급 없이 확인된 구매"가 남아 되돌릴 수 없음. 반대 순서는 다시 시도하면 됨
- 조회 실패(503)를 실패로 치지 않음: 결과를 모르는 것. 앱이 거래를 끝내지 않으면 스토어가 다시 전달

### 10-2. 알림 `POST /iap/notifications/...` (`iap_notify.go`)

1. 받기 (`iapNotify`): 확인 → 원문을 DB에 저장 → 바로 200
2. 뒤에서 처리 (`iapSweep`): 저장된 알림을 꺼내 스토어에 다시 묻고 우리 테이블을 그 답으로 덮어씀
- 알림 내용으로 상태를 정하지 않음. 알림은 "이 거래를 다시 물어보라"는 신호. 그래서 겹치거나 순서가 바뀌어도 결과가 같음
- 구독 줄의 주인은 알림이 바꾸지 못함. 주인은 우리 테이블이 정함

### 10-3. 여기서 새로 쓴 Go 문법

| 문법 | 어디 | 뜻 | Java로 치면 |
|---|---|---|---|
| 고루틴 `go func() { ... }()` | `StartIAPWorker` | 뒤에서 따로 도는 가벼운 스레드 | `ExecutorService.submit` |
| 채널 `chan struct{}` | `iapWake` | 고루틴끼리 신호를 주고받는 통로 | `BlockingQueue` |
| `select { case <-a: case <-b: }` | 작업 루프 | 여러 채널 중 먼저 오는 것을 기다림. "1분이 지났거나, 새 알림이 왔거나, 서버가 꺼지거나" | 없음. 가장 Go다운 문법 |
| `select { case ch <- v: default: }` | `iapWakeUp` | 받을 쪽이 바쁘면 기다리지 않고 넘어감 | `queue.offer` |
| `context.WithTimeout` + `defer cancel()` | 스토어 호출 | 이 호출은 15초까지만. `cancel`을 안 부르면 타이머가 샘 | `Future.get(timeout)` |
| 함수를 돌려주는 함수 | `iapNotify(route)`, `iapGooglePushAuth()` | 설정을 품은 함수를 만들어 줌(클로저) | 람다를 반환하는 메서드 |
| 타입 단언 `v, ok := x.(T)` | `s.IAP[route].(iapNoticeParser)` | 인터페이스 값이 다른 인터페이스도 구현하는지 확인 | `instanceof` 뒤 캐스팅 |
| `sync.Mutex` | `iapAllow` | 여러 고루틴이 같은 맵을 만질 때 잠금 | `synchronized` |
| `map[K]V`를 고루틴에서 쓸 때 | 같은 곳 | 잠금 없이 동시에 쓰면 프로그램이 죽음. `go test -race`가 잡아 줌 | `HashMap`의 동시 수정 |
| DB 자문 락 `pg_try_advisory_lock` | `iapSweepLocked` | 서버가 여러 대여도 한 곳만 돌게 | `@SchedulerLock` (ShedLock) |

### 10-4. 이번에 실제로 겪은 것 (기억해 둘 실수)

- **SQL의 NULL**: `만료 지남 OR 유예_끝 > now()`에서 유예 끝이 NULL이면 결과가 `false`가 아니라 `NULL`. `WHERE`에서는 거짓처럼 동작하지만, 그 값을 참·거짓 변수로 읽으면 실패함. 만료 직후의 구독자 전원이 500을 받을 뻔했음. `coalesce(식, false)`로 고침
  - 찾은 방법: "만료됐을 때"를 시험하는 테스트를 쓰다가. 정상 경로 테스트만 있었으면 못 찾음
- **ID는 증거가 아님**: 처음에는 애플 거래 ID(숫자)만 받았음. 숫자는 추측할 수 있어서 남의 구독을 복원으로 가져갈 수 있었음. 스토어가 서명한 거래를 받도록 고침. "이 값을 아는 것이 주인이라는 증거가 되는가"를 물어야 함
- **공유 DB에서의 테스트**: "이번에 처리한 건수가 3이어야 한다"는 테스트는 다른 테스트가 남긴 데이터 때문에 실패함. 내가 만든 줄을 ID로 찾아 확인해야 함
- **코드 맞춤(`gofmt`)이 줄을 바꿈**: 구조체 칸의 주석 위치가 정렬되면서 줄 모양이 달라짐. 저장할 때마다 `gofmt -w`를 돌리는 것이 관례

### 10-5. 코드 리뷰에서 배운 것 (PR #44)

- **비밀 값이 오류 문장에 실려 로그로 감**: 구글 API 주소에는 구매 토큰이 들어 있고, Go의 통신 오류(`*url.Error`)는 요청 주소를 통째로 문장에 넣음. 그 오류를 `log.Printf("%v", err)`로 찍거나 알림 테이블의 `error` 칸에 적으면 토큰이 남음. 구매 토큰은 그 자체가 구매 증거라, 남이 보면 구독을 복원으로 가져갈 수 있음
  - 고친 것: `scrubURL`이 `errors.As`로 `*url.Error`를 꺼내 주소를 빼고 원인만 남김(`internal/iap/google.go`)
  - 기억할 것: 오류는 "문장"이 아니라 "값"이라 안에 무엇이 들었는지 모른 채 찍게 됨. 밖에서 받은 오류를 로그·DB에 남기기 전에 비밀이 실리는지 봄
  - Java로 치면: 예외 메시지에 요청 URL이 든 `HttpClientErrorException`을 그대로 로깅한 것
- **줄이 없으면 `FOR UPDATE`는 아무것도 잠그지 못함**: 구독 1건을 처음 만들 때, 앱의 제출과 스토어 알림이 동시에 오면 둘 다 `SELECT ... FOR UPDATE`에서 "줄 없음"을 받고 그냥 지나감. 잠글 줄이 없기 때문. 그 뒤 둘 다 넣으려 해서 한쪽이 주인을 덮어쓸 수 있었음
  - 고친 것: `iapLockLine`이 `pg_advisory_xact_lock(hashtextextended('경로:원거래ID', 0))`로 "아직 없는 줄"의 이름에 락을 검. 트랜잭션이 끝나면 자동으로 풀림
  - Java로 치면: JPA `PESSIMISTIC_WRITE`도 똑같이 못 막음. 없는 엔티티는 잠글 수 없어서 보통 유일 키 + 재시도나 이름 붙인 락을 씀
- **고루틴의 패닉은 프로세스를 내림**: HTTP 요청을 처리하는 고루틴의 패닉은 `net/http`가 잡아 주지만, 내가 `go func()`로 띄운 고루틴은 아무도 잡지 않음. 대조 작업에서 패닉이 한 번 나면 서버 전체가 죽음. 스토어가 보낸 예상 밖의 값(점이 없는 서명 문자열에서 라이브러리가 패닉) 하나로 생길 수 있었음
  - 고친 것: `iapSweepSafely`의 `defer func() { if r := recover(); r != nil { ... } }()`. 그리고 패닉하는 라이브러리 함수 대신 형식을 먼저 보는 `parseAppleRenewal`
  - Java로 치면: 스레드 풀의 작업에서 예외가 나면 그 작업만 죽고 JVM은 살아 있음. Go는 반대라 뒤에서 도는 고루틴마다 `recover`를 직접 둠

### 10-6. Java와 달라서 불편했던 것 (이 코드에서 실제로 겪은 것만)

| 겪은 것 | 어디서 | Java였다면 | 여기서 한 것 |
|---|---|---|---|
| 선언적 트랜잭션이 없음 | `iapSubmit`, `iapSyncSubscription` | `@Transactional` 하나 | `Begin` → `defer tx.Rollback(ctx)` → 끝에 `Commit`. 번거롭지만 "스토어 호출은 트랜잭션 밖"이 코드에 그대로 보임. `@Transactional` 메서드 안에서 외부 API를 부르는 실수가 구조적으로 눈에 띔 |
| 오류를 줄마다 확인 | 전부 | 예외가 알아서 올라감 | `if err != nil { return err }`가 함수의 절반. 대신 "여기서 실패하면 어떻게 되나"를 줄마다 정하게 됨(확인 실패는 지급 유지, 조회 실패는 503) |
| 오류 종류를 값으로 구분 | `iapStoreError`, `googleErr` | `catch (NotFoundException e)` | `errors.Is(err, iap.ErrNotFound)`, `errors.As(err, &ge)`. `%w`로 감싸는 것을 잊으면 `errors.Is`가 못 찾음. 컴파일러가 알려 주지 않음 |
| nil 맵에 쓰면 패닉 | `iapAllow`, `iapCatchUpDue` | `new HashMap<>()`을 잊으면 NPE | 읽기는 되고 쓰기만 패닉이라 테스트가 읽기만 하면 못 잡음. 쓰기 전에 `if m == nil { m = map[..]..{} }` |
| 제로값이 "없음"과 구분되지 않음 | `Purchase.RevokedAt`, `PriceMilli` | `Optional`, `null` | `time.Time{}`은 `IsZero()`로, 금액은 DB에서 `*int64`로 받아 "0원"과 "모름"을 가름. 구글은 금액을 안 줘서 실제로 필요했음 |
| 인터페이스를 암시적으로 구현 | `iap.Store`, `iap.NoticeHistory` | `implements`를 적음 | 메서드 하나를 빼먹어도 쓰는 곳까지 가야 오류가 남. `var _ Store = (*Apple)(nil)` 한 줄로 컴파일 때 확인. 대신 "애플만 가진 기능"을 선택 인터페이스로 두고 `store.(iap.NoticeHistory)`로 물어볼 수 있어 편함 |
| 고루틴 패닉 | `StartIAPWorker` | 스레드 하나만 죽음 | 위 10-5 |
| `gofmt`가 줄을 바꿈 | 구조체, 테이블 모양 코드 | 포매터가 선택 | 칸 맞춤이 바뀌면 안 고친 줄까지 diff에 나옴. 저장할 때마다 `gofmt -w`를 돌려 한 번에 맞춤 |
| 스트림이 없음 | `/iap/me`의 상품 거르기, 내역 만들기 | `stream().filter().map().toList()` | `for` + `append`. 줄은 늘지만 중간에 오류를 돌려주기 쉬움 |
| 행을 객체로 바꿔 주는 것이 없음 | `iap_store.go` 전체 | JPA 엔티티, `RowMapper` | `rows.Scan(&a, &b, ...)`을 SELECT 순서와 손으로 맞춤. 순서가 틀려도 타입이 같으면 컴파일도 실행도 됨. DB를 쓰는 테스트로만 잡음 |
| JSON 응답을 `map[string]any`로 | `/iap/me` | DTO 클래스 | 빠르지만 `p["route"].(string)` 같은 단언이 생김. 값이 다른 타입이면 패닉. 밖에 계약으로 내보내는 것은 구조체가 안전함(`iapBacklog`는 구조체로 함) |

- 한계라고 느낀 것은 없었음. 결제 서버에 필요한 것(HTTP, DB 트랜잭션, 서명 검증, 뒤에서 도는 작업)은 표준 라이브러리와 `pgx`, `go-iap`로 다 됨
- 불편은 "프레임워크가 해 주던 것을 손으로 한다"에 모여 있음. 돈이 걸린 코드에서는 그 덕에 트랜잭션 경계와 실패 처리가 숨지 않아 오히려 검토하기 쉬웠음

### 10-7. 빠진 알림 메우기와 구매 내역 (PR #46)

- **선택 인터페이스**: 알림 이력은 애플만, 무효 구매 목록은 구글만 줌. `Store`에 넣으면 없는 쪽이 빈 메서드를 가져야 함. 따로 작은 인터페이스(`iap.NoticeHistory`, `iap.VoidedLister`)를 두고 쓰는 쪽이 `h, ok := store.(iap.NoticeHistory)`로 물어봄
- **메우기는 "넣기만" 함**: 이력에서 받은 알림을 알림 테이블에 넣을 뿐이고, 처리는 원래 있던 알림 처리 단계가 함. 이미 받은 알림은 유일 키가 거름. 새 경로를 만들지 않아 지급 판단이 한 곳에 남음
- **주기를 어디에 기억하나**: "마지막으로 돌린 때"를 서버 메모리에 둠. 서버를 다시 켜면 한 번 더 돌지만 결과가 같아서 괜찮음. 같은 일을 다시 해도 결과가 같게 만들어 두면 이런 것을 DB에 적지 않아도 됨
- **공개 저장소와 설정 값**: 사업자 정보는 코드에 적지 못해 환경 변수 `IAP_SELLER_JSON`에서 읽음. 아는 칸의 글자 값만 내보냄(환경 변수에 실수로 넣은 다른 값이 앱으로 나가지 않게)

### 10-8. 알림함: 상태가 "바뀐 순간"을 잡기 (고지, V22)

- **문제**: 스토어 알림은 "지금 상태"만 알려 줌. 같은 알림이 여러 번 오고 대조 작업도 같은 줄을 다시 봄. 그런데 유저에게는 "결제가 실패했다"를 한 번만 알려야 함
- **UPDATE만 해서는 바뀌었는지 모름**: `UPDATE ... SET state='inactive'`는 원래 inactive였어도 성공함. 바뀐 순간을 알려면 고치기 전의 값을 같이 읽어야 함
- **읽는 법 두 가지**
  - 먼저 읽고 잠그기: `SELECT ... FOR UPDATE`로 이전 값을 읽고(`iapSubBeforeOf`), 같은 트랜잭션에서 고친 뒤 Go에서 견줌(`iapNoteSubscriptionChange`). 조건이 여러 개일 때(유예 시작, 해지 접수, 만료) 읽기 쉬움
  - 한 문장으로: `WITH r AS (UPDATE ... WHERE state='paid' RETURNING ...) INSERT INTO iap_notices SELECT ... FROM r`. `WHERE state='paid'`가 "바뀌는 줄만" 고르고, `RETURNING`이 고친 줄을 다음 문장에 넘김(`iapRevokePurchase`). 트랜잭션을 따로 열지 않아도 상태와 고지가 함께 쓰임
- **그래도 유일 키를 둠**: `UNIQUE (user_id, dedupe_key)` + `ON CONFLICT DO NOTHING`. 비교가 틀리거나 다른 경로(환불 알림과 구독 조회)가 같은 일을 각자 알아채도 한 줄. 키에 "어느 일인지"를 넣음(예: `payment_failed:apple:<구독>:<유예 종료 시각>`). 다음 달의 결제 실패는 시각이 달라 새 줄이 됨
- **같은 값을 Go와 SQL 양쪽에서 만들 때**: 시각 표기가 다르면 유일 키가 어긋남. `iapStamp`(Go)와 `iapStampSQL`(to_char 형식)을 나란히 두고 초 단위 UTC로 맞춤
- **문구는 저장하지 않음**: 문구 번호(T7)와 버전, 채울 값만 저장. 문구를 고치면 버전을 올림. 분쟁 때 "어떤 문구를 언제 보여 줬나"를 답할 수 있음
- **Java였다면**: JPA의 `@PreUpdate`나 Hibernate 이벤트로 이전 값을 받았을 자리. 여기서는 직접 읽어야 해서 번거롭지만, 어느 SQL이 언제 잠그는지가 코드에 그대로 보임

### 10-9. 갱신 예정 고지: "상태가 바뀌지 않았는데" 알리기 (T4, V23)

- **10-8과 다른 점**: 앞의 고지는 상태가 바뀐 순간에 씀. 갱신 예정은 아무것도 바뀌지 않음. "만료일이 14일 안으로 들어왔다"는 시간이 흘러서 생기는 일이라, 알림이 아니라 정기 대조가 찾아야 함
- **한 문장으로 찾고 쓰기**: `INSERT INTO iap_notices SELECT ... FROM iap_subscriptions JOIN iap_plans ... WHERE expires_at <= now + 14일 ON CONFLICT DO NOTHING`. 대상 고르기와 쓰기가 한 SQL이라 Go로 줄을 가져와 돌 필요가 없음(`iapNoteRenewals`)
- **유일 키에 만료일을 넣음**: `renewal_upcoming:<경로>:<구독>:<만료일>`. 몇 번을 돌아도 같은 갱신은 한 줄, 1년 뒤 갱신은 만료일이 달라 새 줄
- **스토어는 주기를 알려 주지 않음**: 애플 거래 정보에도, 구글 구독 조회에도 "월인지 연인지"가 없음. 상품 테이블처럼 운영자가 채우는 테이블(`iap_plans`)를 둠. 구글은 한 상품에 월·연 요금제가 함께 있어서 열쇠가 (경로, 상품, 요금제)
- **자주 돌 필요가 없는 일**: 1분마다 도는 대조 안에 있지만 6시간에 한 번만 함(`iapRenewalDue`, 10-7의 메우기와 같은 방식). 결과가 같아서 서버를 다시 켜면 한 번 더 돌아도 괜찮음
- **환경 변수 숫자 읽기**: `strconv.Atoi(os.Getenv(...))`가 실패하거나 범위 밖이면 기본값 14. Java의 `Integer.parseInt`는 예외를 던지지만 Go는 `err`를 돌려주니 if 하나로 기본값 처리

### 10-10. 추가 선반을 연도 책장마다: 스토어가 모르는 값을 거래에 붙이기 (D1, V21)

- **문제**: 2026-11-19 결정으로 선반은 연도 책장마다 따로 삼(책장 6칸 중 3칸 무료, 유료는 해마다 최대 3칸). 그런데 스토어 거래에는 "몇 년 책장"이 없음. 앱이 제출할 때 연도를 같이 보내면 될 것 같지만, 앱이 결제 중 꺼지거나 스토어 알림이 먼저 오면 연도가 사라짐
- **풀이: 계정 연결 값을 연도마다 따로 발급**: 스토어는 결제 때 넘긴 값(애플 `appAccountToken`, 구글 `obfuscatedAccountId`)을 거래에 그대로 붙여 돌려줌. 그래서 값을 "계정 × 연도"마다 하나씩 만들고(`iap_account_tokens.year`), 돌아온 값으로 연도를 찾음. 구독용 값은 `year`가 NULL인 줄
  - 앱 흐름: `POST /iap/shelf-token {"year":2026}` → 받은 값을 결제에 넘김 → 제출
  - 이미 다 연 해(3칸)에는 409 `iap_shelf_full`을 줘서 결제창이 뜨기 전에 막음
- **연도는 거래 줄에 복사해 둠**: `iap_purchases.shelf_year`. 넣는 SQL 안에서 `(SELECT year FROM iap_account_tokens WHERE token=...)`로 채움. 탈퇴하면 값 테이블은 CASCADE로 지워지지만 거래 원장은 남으니, 연도도 원장에 있어야 함
- **연도 하나에 값 하나: 부분 유일 색인**: `CREATE UNIQUE INDEX ... (user_id, year) WHERE year IS NOT NULL`. 구독용 값(NULL)은 이 색인에 안 걸림. 만들 때 `INSERT ... ON CONFLICT (user_id, year) WHERE year IS NOT NULL DO NOTHING` 뒤 다시 읽음. 부분 색인을 `ON CONFLICT`로 쓰려면 같은 `WHERE`를 적어야 PostgreSQL이 그 색인을 찾음
  - Java·JPA로 치면 `@Table(uniqueConstraints=...)`로는 조건부 유일을 못 적음. DDL을 직접 써야 하는 자리
- **3칸 상한은 읽을 때 자름**: `least(sum(p.shelves), 3)`(`iapEntitlements`). 두 기기에서 동시에 사면 넘을 수 있는데, 저장할 때 막으려면 잠금이 늘어남. 원장은 사실대로 두고 읽을 때 자르면 환불이 들어와도 다시 계산할 게 없음(D5와 같은 생각). 상한은 `iapPaidShelfMax` 한 곳
  - 넘은 거래는 제출 응답의 `overCap`, 결제 완료 고지의 `overCap`, `/admin/iap/stats`의 `shelfOverCap`으로 보임. 환불은 운영자가 함
  - **10-11에서 바뀜**: 넘은 거래는 통째로 칸을 주지 않고(`over_cap`) 자동 환불. 결제 전 예약도 더함
- **넘은 거래 세기: 윈도 함수**: `sum(shelves) OVER (PARTITION BY user_id, shelf_year ORDER BY purchased_at, id)`로 "그 거래까지 산 칸"을 구하고 3을 넘는 줄을 셈. Java로 하면 줄을 다 가져와 누적합을 돌렸을 일을 SQL 한 문장으로 함(10-11에서 `over_cap` 칸을 세는 것으로 바뀜)
- **연도를 모르는 거래**: 앱 밖에서 산 구매(프로모션 코드)는 계정 연결 값이 비어 있음. 이때만 제출 본문의 `year`를 씀. 값이 연도를 알면 본문은 무시함(값이 결제 때의 뜻이라). 둘 다 없으면 거래는 기록하고(돈은 받았으니) 칸은 주지 않고 422 `iap_shelf_year_missing`. 같은 거래를 연도와 함께 다시 내면 그때 채우고 결제 완료를 알림(`iapSetShelfYear`가 "이번에 채웠는지"를 돌려줌)
- **고치기 전 값과 고친 값을 한 문장에서**: `WITH old AS (SELECT ... FOR UPDATE) UPDATE ... FROM old RETURNING b.shelf_year, old.shelf_year IS NULL`. CTE의 `old`는 고치기 전 값이라 "채웠는지"를 바로 앎(10-8의 `RETURNING`과 같은 수법)
- **Java와 다른 점: JSON의 숫자 키**: Go의 `map[int]int`를 `encoding/json`으로 내보내면 키가 문자열이 됨(`{"2026":3}`). JSON 객체 키는 문자열뿐이라 그렇고, Jackson의 `Map<Integer,Integer>`도 같음. 앱은 키를 문자열로 읽음

### 10-11. 두 기기에서 동시에 살 때: 결제 전 예약 + 결제 뒤 자동 환불 (D1)

- **문제**: 태블릿에서 결제창을 띄워 둔 채 휴대폰에서도 사면, 두 기기 모두 "산 칸 0"을 보고 결제가 시작됨. 둘 다 3칸 묶음이면 6칸. 10-10의 409는 계정 연결 값을 받는 순간에만 보므로 못 막음
- **두 겹으로 지킴**
  - **결제 전: 예약**(`iap_shelf_reservations`). `POST /iap/shelf-token {"year":2026,"shelves":3}`이 값을 주면서 "이 해 책장 3칸 결제 중"을 5분(`iapShelfHold`) 잡음. 산 칸 + 살아 있는 예약 칸 + 이번 칸 > 3이면 409 `iap_shelf_busy`와 `retryAfter`(가장 먼저 끝나는 예약까지 남은 초)
    - 결제가 끝나면 제출(`reservation`)이 풀고, 취소하면 앱이 `POST /iap/shelf-token/release`로 풂. 앱이 꺼지면 `expires_at`이 지나 저절로 무시됨(지우는 일은 다음 예약 때)
    - 예약 번호를 모르는 지급(스토어 알림이 먼저 옴, 옛 앱)은 그 해의 가장 오래된 예약 하나를 풂
  - **결제 뒤: 넘은 거래는 칸을 주지 않고 환불**(`iap_purchases.over_cap`). 예약이 끝난 뒤 결제가 끝나는 등 예약을 지나친 경우를 받음
- **왜 예약만으로 안 되나**: 예약은 "앱이 약속을 지킨다"는 가정 위에 있음. 5분을 넘긴 결제(구글 결제 대기, 느린 카드), 예약을 안 부르는 옛 앱, 앱 밖 구매는 예약을 지나침. 돈이 걸린 상한은 마지막에 서버가 원장으로 한 번 더 지켜야 함
- **왜 "읽을 때 자르기"만으로 안 되나**: 10-10은 넘어도 3칸까지는 열어 줬음. 그런데 넘은 거래를 환불하면 그 거래의 칸도 빠져야 함. 3칸 묶음 일부만 인정하면 "환불은 통째, 칸은 일부"가 되어 셈이 꼬임. 그래서 넘은 거래는 통째로 넘은 것으로 보고(`iapSettleShelf`), 칸 수에서 뺌. `least(sum, 3)`은 마지막 안전장치로 남김
- **한 번 넘은 거래는 되돌리지 않음**: 앞선 거래가 나중에 환불돼 자리가 생겨도 `over_cap`을 false로 돌리지 않음. 이미 환불을 요청한 거래에 칸을 주면 돈과 칸을 둘 다 주게 됨. SQL에서 `SET over_cap = me.over_cap OR (...)`로 true에서 false로 가는 길을 막음
- **유저 줄 잠금으로 줄 세우기**: 예약과 판정 둘 다 `SELECT ... FROM users WHERE id=$1 FOR UPDATE` 뒤에 셈. 같은 유저의 두 요청이 차례로 보게 됨. Java의 `synchronized(user)`를 DB에서 하는 셈이고, 서버가 여러 대여도 통함
- **환불: 구글만 서버가 할 수 있음**: Play Developer API `orders.refund`(`iap.Refunder`). 애플은 개발자가 환불하는 API가 없어 고지로 "애플에 환불 요청"을 안내(`autoRefund=false`)
  - 소비(consume)를 먼저 하고 환불함. 구글은 3일 안에 확인하지 않으면 어차피 환불하지만, 그때는 사용자에게 알릴 길이 없음
  - 실패하면 `refund_attempts`를 올리고 정기 처리(4단계)가 다시 요청. 주문 ID는 원장에 두지 않고 구매 토큰으로 다시 조회해 받음
  - 다시 시도 목록은 환불할 수 있는 경로만 물음(`route = ANY($1)`). 애플의 넘은 거래가 목록 50줄을 차지해 구글 거래가 밀리는 일을 막음
- **Go: 선택 기능은 작은 인터페이스로**: `Store`에 `Refund`를 넣지 않고 `Refunder`를 따로 둠. 쓰는 곳에서 `rf, ok := store.(iap.Refunder)`로 물어봄(타입 단언). Java로 치면 `if (store instanceof Refunder rf)`. 애플 구현이 "지원 안 함" 오류를 돌려주는 빈 메서드를 갖지 않아도 됨
  - 시험 가짜도 `FakeRefunder{*Fake}`로 따로 둠. 구조체 포함(embedding)이라 `Fake`의 메서드를 그대로 가지면서 `Refund`만 더함. 애플 가짜가 환불을 흉내 내지 않게

## 진행 기록

| 날짜 | 이슈 | 한 것 | 배운 것 |
|---|---|---|---|
| 2026-11-18 | #9 | `go-iap` v1.59.1 추가, `iap` 패키지(`Store`, 애플 거래 조회, 가짜), `Check` 자리 | 1~9장 |
| 2026-11-19 | #9 | 구독 상태 조회, 구글 확인·소비, 애플·구글 알림 해석 | 9-0 |
| 2026-11-19 | 조사 | 애플·구글·중국어권·국내 자료 조사, 이슈 #22~#42 | [조사 종합](../reports/2026-11-19-iap-pitfalls.md) |
| 2026-11-19 | #10 | 구매 검증 API, `Check`, 보안 수정(서명된 거래, 샌드박스 스위치, 제출 제한) | 10-1, 10-4 |
| 2026-11-19 | #11, #12, #26 | 알림 수신, 뒤에서 도는 처리·대조 작업 | 10-2, 10-3 |
| 2026-11-19 | #8 | V21 마이그레이션(테이블 5개), 저장소 함수와 DB 테스트 | 1장 로컬 DB, 6-1 |
| 2026-11-18 | #9 | 구글 거래 조회, 인터페이스를 `Lookup(Ref)`로 고침, 상태 값 `State`, 환경변수 읽기 | 4장 고친 기록, 4-1, 9장 구글 비교, 9-1 |
| 2026-11-19 | #26, #39, L14, L17 | 구매 내역, 사업자 정보, 애플 알림 이력·구글 무효 구매 목록으로 메우기, 밀린 일 숫자 | 10-5, 10-6, 10-7 |
| 2026-11-19 | L8, L11, L18 | 알림함: 고지 테이블(V22), 바뀐 순간에 한 번 쓰기, 목록·읽음 API | 10-8 |
| 2026-11-19 | L9, L11 | 고지 기록 탈퇴 뒤 보존, 갱신 예정 고지(V23 `iap_plans`), `/iap/me`의 `period` | 10-9 |
| 2026-11-19 | #6, D1 | 추가 선반 연도 책장마다(유료 최대 3칸): 연도별 계정 연결 값, `shelf_year`, `POST /iap/shelf-token`, `shelvesByYear`, 넘은 거래 세기 | 10-10 |
| 2026-11-19 | D1 | 두 기기 동시 구매: 결제 중 예약 5분, 넘은 거래는 칸을 주지 않고 자동 환불(구글), 넘김 고지 | 10-11 |
