# Go 서버

기존 HTTP API와 PostgreSQL 스키마를 유지하는 Go 서버다. KoDeploy의 기존 빌드 경로 `server/`와 Dockerfile을 사용하며, 기본 포트는 8080이고 `PORT` 환경변수로 변경할 수 있다. `server/**`가 바뀐 main push는 시험을 통과하면 KoDeploy에 자동 배포된다(`.github/workflows/kodeploy-server.yml`). PR에서는 시험만 돈다.

## 실행

Go 1.27 이상과 PostgreSQL이 필요하다. `DATABASE_URL`과 기타 환경변수는 `.env.example`을 참고한다.
KoDeploy에서 제공하는 `postgresql+psycopg2://` 접두사는 서버 시작 시 `postgresql://`로 변환한다. 접속 정보와 SSL 설정은 그대로 유지한다.

```sh
cd server
DATABASE_URL='postgres://user:pass@localhost:5432/chaekjang?sslmode=disable' go run ./cmd/server
```

Docker 이미지: `docker build -t chaekjang-go server`. 운영에서는 사진을 영구 보존할 수 있도록 S3 호환 저장소의 `S3_BUCKET`, `S3_ENDPOINT`, `S3_REGION`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`를 설정한다. 로컬 파일 저장은 `FILE_DIR`을 사용한다. 헬스 체크는 `GET /healthz`다.

## 데이터베이스

- 기존 Flyway 데이터베이스는 V1~V7의 성공 이력이 있어야 실행되며, Go 서버는 해당 마이그레이션을 다시 실행하지 않는다. V5인 DB는 `internal/server/migrations`의 V6·V7을 Flyway 도구로 먼저 적용해야 한다.
- V8부터는 Go 서버의 마이그레이션이다. Flyway V7 DB와 Go가 만든 DB 모두에 시작할 때 트랜잭션으로 적용하고 `go_schema_history`에 기록한다. 기존 Flyway의 이력 테이블을 위조하지 않는다.
- 되돌리기: 서버는 DB에 코드보다 새 마이그레이션이 있으면 시작하지 않는다(`internal/server/migrate.go`, `iapkit/migrate.go`). 그래서 마이그레이션이 들어간 커밋 뒤에는 옛 커밋을 다시 배포해 되돌릴 수 없다(서버 전체가 뜨지 않는다). 되돌릴 때는 코드만 되돌리는 커밋을 새로 push하고, 스키마는 그대로 두거나 앞으로 가는 마이그레이션으로 고친다
- 새 데이터베이스에는 V1부터 모두 적용한다. 버전은 파일 이름의 `V<번호>__`로 정하며 1부터 빠짐없이 이어져야 한다.
- V8(`normalized_layout`): 책장 배치 JSON(`shelf_layouts.layout`)을 `shelves`·`shelf_placements` 표로 옮기고, `books`의 키·두께 분류와 기본 모티프 열을 지운다(판형·쪽수·ISBN으로 계산). 되돌릴 수 없으니 운영 DB는 백업한 뒤 재배포한다.
- 알 수 없는 이력을 가진 기존 스키마에는 적용하지 않는다. 실제 데이터 전환 전에 백업과 별도 환경에서의 검증이 필요하다.

## 커뮤니티 스위치

커뮤니티 API는 `COMMUNITY_ENABLED=1`일 때만 등록된다(운영자 `/admin/reports` 포함). 비우면 `/healthz`의 `community`가 false이고 앱은 커뮤니티 화면을 숨긴다. 표의 글은 지우지 않으므로 값을 켜고 재배포하면 앱 업데이트 없이 그대로 열린다. 계정 삭제는 스위치와 상관없이 커뮤니티 데이터까지 지운다.

## 결제 스위치

결제는 `server/iapkit`(서버 키트)이 맡고, 이 서버는 `internal/server/iap.go`에서 키트를 붙인다. API, 환경 변수, 오류 코드, 정기 대조, 경보는 [`iapkit/README.md`](iapkit/README.md)에 있다. 여기에는 이 앱에만 해당하는 것만 적는다.

- 스위치: `IAP_ENABLED=1`이고 스토어 키(`IAP_APPLE_*`, `IAP_GOOGLE_*`)가 있을 때만 결제 경로가 붙는다. 꺼져 있으면 `/healthz`의 `iap`가 false다
- 스토어 설정은 스토어마다 따로 본다. 한쪽이 틀리면 그쪽만 꺼지고 나머지는 켜진다. 틀린 설정과 구글 알림 인증 누락은 `iap alert:` 로그와 `/admin/iap/stats`의 `configProblems`로 나온다
- 규칙(`covebookIAPRules`): 대상은 연도 책장(`"2026"`), 대상마다 돈을 내고 여는 칸은 최대 3칸이다(ADR-0002 D1)
- 샌드박스(TestFlight, 심사) 구매는 `IAP_ALLOW_SANDBOX=1`일 때만 지급한다(ADR-0002 D15)
- 사업자 정보는 `IAP_SELLER_JSON`으로 넣고 `/iap/me`의 `seller`로 나간다. 값은 저장소에 적지 않는다
- 결정 기록: `../docs/adr/0002-iap-design.md`(설계), `../docs/adr/0003-iap-compliance.md`(법규)

## 검증과 남은 작업

`go test ./...`로 일반 시험을 실행하고, **전용 테스트 DB**를 준비한 뒤 `TEST_DATABASE_URL=postgres://... go test ./...`로 PostgreSQL 통합 시험을 실행한다. Flyway V7 DB를 V8로 올리는 시험은 빈 DB를 하나 더 만들어 `TEST_EMPTY_DATABASE_URL`로 넘긴다. 이 시험은 계정과 데이터를 생성하므로 실제 데이터베이스를 지정하지 않는다.

기기 계정, Google·카카오 로그인, 계정 삭제, 도서 검색·상세, 파일, 동기화 API를 구현했다. 도서 검색·ISBN 조회는 YES24 기준이다: `YES24_API_KEY`로 YES24를 부르고(쪽수·판형 mm·분류·시리즈·책 소개, 2026-10-31 실제 키로 확인), 키가 없으면 개발용 가짜 목록을 쓴다(`internal/server/yes24.go`). 종이책만 쓰되 외국 도서(외서·직수입양서·직수입일서, 관리 분류 '외국도서')도 넣고, 한글이 없는 검색어는 외국 도서 칸(`category=FOREIGN`) 100건을 함께 받아 전체 검색 앞 3건 뒤를 제목·저자가 맞는 순으로 다시 줄 세운다(한글 검색어는 국내 도서 먼저). `/healthz`의 `books`가 `yes24`인지로 확인한다. `KAKAO_REST_KEY`는 이제 카카오 로그인(`KAKAO_LOGIN_REST_KEY`가 없을 때)에만 쓴다. 계정 삭제 저널은 R2에 남으며 서버 시작 전 재적용한다. Google·카카오와 객체 저장소의 실서비스 자격 증명은 시험하지 않았다. LLM 키 순환 게이트웨이는 이전했지만 기존 서버처럼 외부 API 엔드포인트에는 연결되어 있지 않다. 실제 서비스 교체 전 외부 연동과 양 서버의 응답 및 부하를 추가 검증해야 한다. 로그인 설정과 삭제·복원 주의사항은 `../docs/release/social-login.md`를 참고한다.
