# 결제 서버 학습 노트 (Java 개발자가 Go로)

- 시작일: 2026-11-18
- 읽는 사람: Java·Spring은 알고 Go는 처음인 사람
- 쓰는 법: 결제 이슈를 하나 끝낼 때마다 그때 필요했던 것을 장으로 추가. 맨 아래 "진행 기록"에 날짜와 이슈 번호를 남김
- 결정 기록: [ADR-0001](../adr/0001-iap-server-go.md), [ADR-0002](../adr/0002-iap-design.md)
- 확인 수준: 코드 인용은 이 저장소와 `go-iap` v1.59.1 소스를 직접 읽은 것. 외부 사실은 10장에 출처와 확인 여부를 적음

## 0. 지금 어디까지

| 이슈 | 내용 | 상태 |
|---|---|---|
| #9 | `go-iap` 도입, 결제 경로 인터페이스 | 진행 중. 애플 거래 조회까지 |
| #8 | 테이블 (V21~) | #6 결정 대기 |
| #10 | 구매 검증 API | 시작 전 |

- 내가 직접 채울 곳: `server/internal/iap/check.go`의 `Check` (7장)

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
- 인터페이스가 두 겹
  - 안쪽 `appleAPI`: 라이브러리를 가림. `apple.go` 안에서만 보임
  - 바깥 `Store`: 애플·구글을 가림. 서버의 다른 코드는 이것만 봄
- "구현했는지" 컴파일 때 확인하는 관용구 (`fake.go`)

```go
var _ Store = (*Apple)(nil)
```

- 라이브러리 타입을 밖으로 내보내지 않음. `fromApple`이 `api.JWSTransaction`을 우리 타입 `Purchase`로 바꿈
  - 라이브러리를 바꾸거나 구글을 붙여도 나머지 코드는 그대로

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

## 7. 내가 채울 것: `Check`

- 위치: `server/internal/iap/check.go`
- 역할: 스토어가 "진짜 거래"라고 확인해 준 뒤, 그 거래가 **이 요청**에 지급해도 되는 것인지 봄. 라이브러리의 서명 검증 뒤에 두는 두 번째 방어선 (ADR-0001 결정 9)
- 막는 것

| 검사 | 막는 상황 |
|---|---|
| 번들 ID | 다른 앱에서 산 진짜 거래를 우리 서버에 제출 |
| 상품 ID | 우리가 팔지 않는 상품, 오타 |
| 환불 여부 | 이미 환불받은 거래를 다시 제출 |
| 계정 값 | 남의 거래 ID를 자기 계정으로 제출 |

- 정할 것 1: 거래의 `AccountToken`이 비어 있을 때
  - 막기: 안전함. 다만 앱을 거치지 않은 구매는 이 값이 없음 (App Store에서 직접 한 구독, 프로모션 코드 등). 그런 구매자가 지급을 못 받음
  - 통과: 편함. 다만 남의 거래 ID를 알면 자기 계정에 붙일 수 있음. 거래 ID 유일 키가 "한 번만"은 막아 주지만 "누구에게"는 못 막음
  - 절충: `Check`에서는 막고, 빈 값 거래는 따로 "복원" 경로에서만 받음 (#13). 이렇게 하려면 오류를 하나 더 만들어 구분해야 함
- 정할 것 2: 여러 개가 동시에 틀렸을 때 순서
  - 로그에 남는 오류가 원인 파악에 쓰임. 가장 근본적인 것(다른 앱)부터 보는 것이 보통
- 확인 방법
  - `go test -v -run TestCheck ./internal/iap`
  - 지금은 "먼저 채운다"로 건너뜀. 채우면 표의 경우들이 돎
  - `check_test.go`의 표에 빈 `AccountToken` 경우를 한 줄 추가
- 쓸 문법
  - `if p.BundleID != want.BundleID { return ErrWrongApp }`
  - 맵 조회: `want.Products[p.ProductID]`는 없으면 `false`
  - `p.Revoked()`

## 8. 테스트 쓰는 법

- 파일 이름이 `_test.go`로 끝나고 함수가 `TestXxx(t *testing.T)`면 테스트. 프레임워크 없음
- 실패 알림: `t.Fatalf("...")`. 단정문 라이브러리를 쓰지 않고 `if`로 비교
- 표 형식 테스트 (`check_test.go`): 경우를 구조체 목록으로 늘어놓고 `t.Run(이름, ...)`으로 돌림. JUnit의 `@ParameterizedTest`
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
- 구글 (`playstore` 패키지): `New(jsonKey)`, `VerifySubscriptionV2`, `VerifyProductV2`, `AcknowledgeSubscription`, `AcknowledgeProduct`, `ConsumeProduct`. 구현은 다음 단계

## 10. 출처와 확인 수준

| 내용 | 출처 | 확인 |
|---|---|---|
| `go-iap` 함수와 동작 | v1.59.1 소스 (`appstore/api/store.go`, `store_fallback.go`, `model.go`) | 직접 읽음 |
| `pgx`의 `Rollback` 동작 | `go doc github.com/jackc/pgx/v5 Tx.Rollback` | 직접 읽음 |
| 애플 `price`가 1000배 단위 | [애플 문서 price](https://developer.apple.com/documentation/appstoreserverapi/price), [개발자 포럼](https://developer.apple.com/forums/thread/767978) | 검색 결과 요약으로 확인. 원문 페이지는 직접 못 엶 |
| `storefront` 코드 형식, `appAccountToken` 형식 | [애플 문서 JWSTransactionDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload) | 미확인. 샌드박스에서 실제 값으로 확인 (#15) |
| 인터페이스는 쓰는 쪽 패키지에 | [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) | 검색 결과 요약으로 확인 |
| `defer` 위치 실수 | [DEV 글](https://dev.to/mark_saward/go-footguns-go-defer-and-rust-drop-17af) | 검색 결과 요약으로 확인 |

- 더 읽을 것
  - [A Tour of Go](https://go.dev/tour/): 문법 전체. 반나절
  - [Effective Go](https://go.dev/doc/effective_go): 관용적인 쓰기
  - [Executing transactions](https://go.dev/doc/database/execute-transactions): 표준 라이브러리 기준 트랜잭션. 이 서버는 `pgx`지만 모양이 같음
  - [Working with Errors in Go 1.13](https://go.dev/blog/go1.13-errors): `%w`, `errors.Is`, `errors.As`

## 진행 기록

| 날짜 | 이슈 | 한 것 | 배운 것 |
|---|---|---|---|
| 2026-11-18 | #9 | `go-iap` v1.59.1 추가, `iap` 패키지(`Store`, 애플 거래 조회, 가짜), `Check` 자리 | 1~9장 |
