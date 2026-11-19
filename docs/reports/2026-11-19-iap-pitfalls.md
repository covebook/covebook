# 인앱결제·구독에서 신경 써야 할 것 (조사 종합)

- 작성일: 2026-11-19
- 조사 범위: 애플·구글 공식 문서, 결제 대행사 엔지니어링 블로그, 애플 개발자 포럼, 중국어권 기술 블로그(掘金, 博客园, 腾讯云, 阿里云), 한국어 블로그·Q&A·세무사 글
- 읽는 사람: 범수, 정환
- 관련 문서: [ADR-0001](../adr/0001-iap-server-go.md), [ADR-0002](../adr/0002-iap-design.md), [ADR-0003](../adr/0003-iap-compliance.md), [학습 노트](../guides/iap-go-notes.md)
- 작업 목록: 마일스톤 "인앱결제 1차". 이 문서의 장마다 대응하는 이슈는 10장
- 주의: 세무·법률 내용은 공개 자료로 조사한 것. 출시 전 전문가 확인 필요

## 0. 확인 수준 표기

| 표기 | 뜻 |
|---|---|
| 공식 | 애플·구글·PG 공식 문서 원문을 읽음 |
| 대행사 | 결제 대행사·기업 기술 블로그 |
| 포럼 | 개발자 포럼 사례. 애플 엔지니어 답변이면 따로 적음 |
| 커뮤니티 | 개인 블로그, Q&A |
| 전문가 | 세무사·회계사 글 |
| 추정 | 문서에 없고 규칙에서 미루어 본 것 |
| 미확인 | 근거를 못 찾음 |

- 구글 공식 문서는 요약 도구를 거쳐 읽음. 사고와 직결되는 숫자(3일, 60일, 64자)는 구현 전에 원문을 다시 열어 봄
- 애플 문서는 주소 뒤에 `.md`를 붙이면 본문이 읽힘 (일반 주소는 본문이 안 읽힘)
- 못 찾은 것: 한국 기업의 인앱결제 사고 회고, 디시인사이드·OKKY의 관련 글, 중국 대기업의 인앱결제 서버 회고 (网易云音乐, 37手游 두 편만 있음)

## 1. 한 장 요약

- 원칙 다섯
  1. 지급 근거는 서버가 스토어에 직접 물어 받은 답뿐. 앱이 보낸 값과 알림 본문은 "다시 물어보라"는 신호
  2. 중복 방지의 마지막 방어선은 DB 유일 키. 락은 보조
  3. 시간 초과는 실패가 아니라 "결과 모름". 미확정 상태로 두고 나중에 확정
  4. 알림은 늦고, 겹치고, 순서가 바뀌고, 빠짐. 정기 대조 작업이 마지막 방어선
  5. 날짜와 금액을 서버가 계산하지 않음. 스토어가 준 만료 시각을 쓰고, 매출은 정산 보고서 기준
- 지금 설계에서 고쳐야 할 것: 2장 (6건)
- 정해야 하는 것: 8장. 16건을 항목마다 근거를 찾아 판정함. 추가 선반을 소모성으로 둔 결정(ADR-0002 D1)을 다시 봐야 한다는 것이 가장 큰 발견
- 실측으로만 알 수 있는 것: 9장 (17건)

## 2. 지금 설계·코드에서 고칠 것

| # | 지금 | 조사 결과 | 조치 |
|---|---|---|---|
| 1 | ADR-0002 D7·D8: 애플 계정 연결 값은 "첫 구매 때 굳음" | 애플 문서에 그런 문장 없음. 포럼 관측이 엇갈림. 2025-06에 값을 나중에 넣거나 바꾸는 API(Set App Account Token)가 생김 | ADR 서술 정정. 구독 이전에 이 API를 쓸지 결정 (5-2) |
| 2 | V21 초안: 구글 거래 유일 키가 "주문 ID, 없으면 구매 토큰" | 구글 공식: 주문 ID를 기본 키로 쓰지 말 것. 프로모션 코드 구매와 결제 대기 구매는 주문 ID가 없음 | 일회성 상품은 구매 토큰, 구독 갱신은 주문 ID로 나눔 (4-3) |
| 3 | ADR-0002 D15: 샌드박스 거래를 운영 서버에서 받음 | 网易云音乐 사고: 심사 빌드의 샌드박스 결제로 결제 안 한 계정이 운영 권한을 받음 | 받는 범위와 환경 판정 방법을 다시 정함 (6-1) |
| 4 | `google.go`: 구독 상태만 보고 "결제됨" 판단 | 구글: 만료 시각이 지나도 상태가 ACTIVE일 수 있고(무음 유예 최소 1일), 해지 예약은 만료 시각까지만 유효 | 상태와 만료 시각을 함께 보는 규칙을 #10에서 확정 (3-3) |
| 5 | 서버: DB 쿼리·락 제한 시간 없음, 연결 풀 기본값. 애플 호출 30초, 구글 10초 | 알림은 몇 초 안에 응답해야 함. 스토어 호출은 트랜잭션 밖 | 시간 제한 값을 정함 (3-2) |
| 6 | 학습 노트: `storefront` 형식 미확인 | 애플 `storefront`는 ISO 3166-1 alpha-3, 구글 `regionCode`는 alpha-2 (공식) | 노트 정정. 국가 칸에 두 형식이 섞임을 명시 |

## 3. 서버 신뢰성

### 3-1. 결과를 모르는 조회 (UNKNOWN)

- 사실
  - 스토어 조회가 시간 초과나 5xx면 거래가 진짜인지 모르는 상태 (추정이 아니라 정의)
  - 애플 Get Transaction Info가 운영에서 간헐적으로 시간 초과·`5000001`을 낸다는 보고 (포럼). 재시도 간격의 공식 권고 없음
  - 애플 재시도 대상 오류: `GeneralInternalRetryableError`(5000001), `OriginalTransactionIdNotFoundRetryableError`(4040006), `AccountNotFoundRetryableError`(4040002), `AppNotFoundRetryableError`, 429 (공식)
  - 재시도하면 안 되는 것: `TransactionIdNotFoundError`(4040010). 환경과 번들 ID를 확인할 대상. 애플은 "해결 못 하면 열어 주지 말라"고 함 (공식)
  - 우리 코드: `iap.ErrNotFound`와 그 밖의 오류를 이미 구분함 (`server/internal/iap/apple.go`)
- 서버가 할 일
  - "없는 거래"는 거절. 통신 실패는 미확정으로 두고 앱에 "확인 중" 응답
  - 앱은 거래를 끝내지 않음. 스토어가 다시 전달하므로 다음 제출에서 확정됨
  - 미확정 건은 대조 작업이 다시 조회 (3-5)
- 선택지 (8장 T1)
  - 지급 보류: 안전. 스토어 장애 동안 결제한 사람이 못 씀
  - 임시 지급 뒤 사후 검증: 경험이 좋음. 위조·환불 거래에 잠깐 열림
  - 앱이 보낸 서명된 거래(JWS)를 서버가 오프라인으로 서명 검증해 임시 지급: 위조 위험은 낮음. 환불 반영이 늦고, 구글에는 같은 수단이 없음 (추정)
- 출처: [애플 오류 코드](https://developer.apple.com/documentation/appstoreserverapi/error-codes), [애플 포럼 840598](https://developer.apple.com/forums/thread/840598), [超时不是失败而是未知](https://feinterview.poetries.top/ai-monitor/news/idempotency)

### 3-2. 시간 제한 값

- 사실
  - 애플 알림: 제한 시간 숫자는 문서에 없음. 애플 엔지니어 답: "몇 초 이내, 가능하면 1초 미만. 처리는 수신과 분리" (포럼)
  - 구글 알림(Pub/Sub 푸시): 응답 기한 기본 10초, 10~600초로 설정 가능 (공식)
  - PG 문서의 권장 읽기 제한 시간은 60초(포트원). 우리와 다른 상황: PG는 승인 요청, 우리는 조회 요청
  - 중국어권 예: 검증 요청 10초, 앱 쪽 10~15초 안에 오류 표시. 없으면 심사에서 "무한 로딩"으로 반려 (커뮤니티)
  - 우리 서버: 애플 클라이언트 30초(라이브러리 기본), 구글 10초, 다른 외부 호출 8초. DB 쿼리·락 제한 없음
- 정할 값 (8장 T2)

| 값 | 짧으면 | 길면 |
|---|---|---|
| 스토어 조회 제한 시간 | "결과 모름"이 늘어남 | 요청이 연결을 오래 붙잡음. 앱이 오래 기다림 |
| 조회 재시도 횟수 | 일시 장애에 약함 | 스토어 장애 때 호출이 몰림. 호출 한도 소모 |
| DB 쿼리 제한 시간 | 정상 쿼리가 끊길 수 있음 | 느린 쿼리가 풀을 차지 |
| DB 락 대기 제한 | 동시 요청이 실패로 끝남 | 한 요청이 멈추면 뒤가 줄줄이 멈춤 |
| 앱의 "확인 중" 표시 시점 | 정상 결제도 불안하게 보임 | 멈춘 것처럼 보임 |

- 원칙: 스토어 호출은 DB 트랜잭션 밖. 트랜잭션은 "원장에 넣고 커밋"만 (학습 노트 6장)
- 출처: [애플 포럼 779594](https://developer.apple.com/forums/thread/779594), [Pub/Sub 푸시](https://docs.cloud.google.com/pubsub/docs/push), [포트원 REST v2](https://developers.portone.io/api/rest-v2), [심사 2.1 반려 사례](https://blog.wenhaofree.com/posts/technology/app-store-guideline-2-1-subscription-loading-fix/)

### 3-3. 만료 직후의 틈

- 사실
  - 애플: 갱신 과정은 만료 10일 전부터 점검하고 만료 전 24시간 동안 갱신을 시도 (공식). "갱신 시도 전에 만료돼 짧은 공백이 생길 수 있고 운영에서도 가능" (공식, 샌드박스 문서)
  - 구글: 유예를 0일로 둬도 최소 1일의 무음 유예가 있고 그동안 상태는 ACTIVE (공식). 갱신 반영이 만료 뒤 몇 분~몇 시간 늦을 수 있음 (대행사). 상한은 문서에 없음
  - 구글 공식: 만료 시각이 아니라 알림을 받은 시점에 재조회하라고 함
  - 만료 뒤 버퍼를 몇 분으로 둘지에 대한 공식 답과 업계 수치는 없음. 같은 질문의 애플 포럼 글은 답글 0 (미확인)
- 서버가 할 일
  - 만료 시각이 지났다는 이유만으로 끊지 않음. 먼저 스토어에 한 번 재조회
  - 유예 기간은 따로 저장한 값으로 판단 (V21의 `grace_until`)
- 선택지 (8장 T3)
  - 정확히 끊기: 단순. 결제에 성공한 사람이 잠깐 막힘
  - 고정 버퍼: 쉬움. 근거 수치가 없고 해지한 사람이 그만큼 더 씀. 대행사 예는 "만료 후 6시간 미만이고 자동 갱신이 켜져 있으면 유지"
  - 만료가 지난 사람만 접근 시점에 재조회(짧은 캐시): 가장 정확. 호출이 늘고, 조회가 실패할 때의 대책이 필요
- 출처: [애플 구독 결제 처리](https://developer.apple.com/documentation/storekit/handling-subscriptions-billing), [구글 구독 수명 주기](https://developer.android.com/google/play/billing/lifecycle/subscriptions), [RevenueCat 갱신 지연](https://www.revenuecat.com/docs/customers/google-play-renewal-extensions), [애플 포럼 828530](https://developer.apple.com/forums/thread/828530)

### 3-4. 알림 수신

- 사실: 애플
  - 재시도: 첫 시도 실패 시 5번 더. 직전 시도로부터 1, 12, 24, 48, 72시간 뒤. 운영에서만. 샌드박스는 1번 (공식)
  - 성공 응답은 HTTP 200~206 (공식). 400을 주니 재시도가 멈췄다는 보고가 있어 4xx 동작은 믿을 수 없음 (포럼)
  - 재시도는 같은 `notificationUUID`. 이미 처리한 알림이 다시 와도 200. 500을 주면 재시도를 처음부터 다시 돎 (포럼, 애플 엔지니어)
  - 순서 보장 문구 없음. 해지 알림이 최초 구매 알림보다 2~35초 먼저 온 사례. 같은 거래에 식별자가 다른 갱신 알림 2건이 98ms 간격으로 온 사례 (포럼)
  - `CONSUMPTION_REQUEST`는 환불 요청이 열려 있는 동안 새 식별자로 다시 옴 (포럼, 애플 엔지니어)
  - 해지 알림(`DID_CHANGE_RENEWAL_STATUS`)은 사용자 해지뿐 아니라 시스템이 갱신을 끌 때도 옴 (포럼)
  - 알림 주소: HTTPS, TLS 1.2 이상, 포트 443 또는 1024 이상. 보내는 쪽 대역 `17.0.0.0/8`. 테스트 알림 요청 API 있음 (공식)
- 사실: 구글
  - 알림에는 상태가 없고 구매 토큰만 있음. 반드시 재조회 (공식)
  - 한 번 이상 전달, 순서 보장 없음. `messageId`로 중복 제거 (공식)
  - 푸시 인증: `Authorization` 헤더의 JWT. 서명, 발급자, 대상(`aud`), 이메일(푸시용 서비스 계정) 확인. 토큰은 최대 1시간 된 것일 수 있음 (공식)
  - 일회성 상품 알림은 Play Console에서 "구독과 일회성 상품 모든 알림"을 골라야 옴 (공식)
  - 환불은 `voidedPurchaseNotification`. 차지백 검토 요청(`pendingRefundReviewNotification`)은 24시간 안에 응답 (공식)
  - 메시지 보관 기본 7일. 구독자 활동이 없으면 31일 뒤 Pub/Sub 구독이 만료됨 (공식)
- 서버가 할 일
  1. 서명·인증 확인
  2. 원문을 DB에 저장 (알림 ID 유일 키, V21의 `iap_notifications`)
  3. 바로 200 응답
  4. 처리는 뒤에서: 스토어 재조회 → 결과를 그대로 덮어씀. 알림 종류로 상태를 추측하지 않음
  5. 모르는 종류의 알림, 모르는 구독의 알림도 버리지 않고 저장
- 선택지 (8장 T4)
  - 받자마자 200 주고 뒤에서 처리: 응답 기한을 지킴. 뒤 처리가 실패하면 스토어는 재시도하지 않으니 우리 큐가 책임짐
  - 처리 끝난 뒤 200: 실패하면 스토어가 다시 보내 줌. 스토어 API가 느리면 재전송이 몰림
  - 원문을 DB에 넣고 200, 처리는 DB에 남은 "미처리" 줄을 작업이 가져감: 둘의 단점을 줄임. 구현이 늘어남
- 출처: [애플 알림 응답](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications), [애플 포럼 756151](https://developer.apple.com/forums/thread/756151), [777254](https://developer.apple.com/forums/thread/777254), [738323](https://developer.apple.com/forums/thread/738323), [819050](https://developer.apple.com/forums/thread/819050), [구글 RTDN](https://developer.android.com/google/play/billing/rtdn-reference), [Pub/Sub 푸시 인증](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions), [37手游 WWDC22 정리](https://cloud.tencent.com/developer/article/2045275)

### 3-5. 정기 대조 작업

- 사실
  - 알림이 통째로 안 온 사례, 전부 시간 초과로 기록된 사례가 있음 (포럼). 애플 문서도 "서버가 멈췄으면 API로 복구하라"고 함 (공식)
  - 애플: 알림 이력 조회는 운영 180일, 샌드박스 30일, 20건씩, 실패한 것만 고르는 옵션 있음. 이력은 "그때의 상태"라서 현재 상태는 구독 상태 조회로 확인 (공식)
  - 구글: 알림 유실 복구 전용 API 없음. 수단은 토큰 재조회와 무효 구매 목록 API(최근 30일, 하루 6000건). 구매 토큰은 구독 만료 60일 뒤부터 조회 불가 (공식)
  - 애플 유예 종료 알림을 놓치면 계정이 계속 활성으로 남음
  - 闲鱼: 손실은 "발견까지 걸리는 시간"에 비례. 지표는 대조 범위와 발견 시간 (대행사)
  - 인프런 답변: 보정 배치는 기본. 방어 로직이 도는 횟수가 정상 건수에 가까우면 구조 문제 (커뮤니티)
- 대조 대상
  - 만료가 임박했거나 지난 구독
  - 한동안 알림이 없는 활성 구독
  - 미확정으로 남은 조회 (3-1)
  - 처리 실패로 남은 알림
  - 구글: 지급했는데 확인(acknowledge)이 안 된 구매 (4-1)
  - 애플: 실패한 알림 이력. 구글: 무효 구매 목록
- 선택지 (8장 T5)
  - 주기: 짧으면 호출이 늘고 길면 발견이 늦음. ADR-0002 D4는 하루 1번. 미확인 구매는 3일 기한이 있어 더 자주 봐야 함
  - 전부 재조회 vs 골라서 재조회: 애플 권고는 갱신 시점에 맞춘 재확인. 전부 재조회를 권하는 출처는 없음 (8-2 T5)
  - 어디서 돌릴지: KoDeploy가 정기 작업을 지원하는지 미확인 (9장 U15). 안 되면 서버 안에서 타이머로
- 출처: [애플 알림 이력](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history), [구글 무효 구매](https://developers.google.com/android-publisher/voided-purchases), [闲鱼 资损防控](https://juejin.cn/post/7012456069586747422), [인프런 질문](https://www.inflearn.com/community/questions/1707023)

### 3-6. 중복과 멱등

- 사실
  - 앱 제출, 알림, 스토어의 재전달이 같은 거래로 겹쳐 옴. 순서는 정해져 있지 않음
  - 중복 요청에 오류를 주면 앱이 거래를 끝내지 못해 계속 다시 보냄. "이미 처리됨"을 성공으로 답해야 함 (커뮤니티, 博客园)
  - 영수증 해시가 아니라 거래 ID로 거름. "조회 후 삽입"은 동시 요청에 약함 (커뮤니티)
  - 분산 락의 문제: 만료 시간, 장애 조치 때 무력화, 락 단위를 잘못 잡으면 무의미 (대행사, 阿里云)
  - 상태를 바꿀 때는 `WHERE`에 원래 상태를 넣는 조건부 `UPDATE`
- 우리 상태: V21 초안이 유일 키 + `ON CONFLICT DO NOTHING`으로 구현. 동시 10건 테스트 통과. 환불은 `WHERE state='paid'` 조건부 `UPDATE`
- 남은 일: #10에서 "이미 처리된 거래"의 응답 모양을 성공으로 정함
- 출처: [博客园 XingxueLiao](https://www.cnblogs.com/xingxueliao/p/8493678.html), [博客园 Mr.陳](https://www.cnblogs.com/chglog/p/15347753.html), [阿里云 幂等](https://developer.aliyun.com/article/1676393)

### 3-7. 호출 한도

- 애플: 대부분 초당 50건(거래 조회, 구독 상태 조회, 알림 이력). 계정 연결 값 설정은 초당 20건. 샌드박스는 10%. 초과 시 429와 `Retry-After` (공식). `Retry-After` 단위는 출처마다 다름 (9장 U2)
- 구글: 묶음별 분당 3000건. 무효 구매 목록은 하루 6000건, 30초에 30건 (공식)
- 우리 규모에서는 한도가 병목이 아님. 알림마다 재조회해도 됨. 다만 429·5xx에는 간격을 늘려 재시도

### 3-8. 관측과 알람

- 볼 지표 (중국어권 글과 조사 종합)
  - 알림 처리 성공률, 처리 실패로 남은 알림 수
  - 미확정으로 남은 조회 수와 가장 오래된 것의 나이
  - 구글: 지급 뒤 확인이 안 된 구매 수 (3일 기한)
  - 대조 작업이 고친 건수 (0에 가까워야 정상)
  - 운영 서버가 받은 샌드박스 거래 수
  - 계정 연결 값이 없거나 달라서 거절한 건수
  - 환불 건수와 계정별 환불 횟수
- 주의: 로그에 스토어 키, 서명된 거래 원문 전체를 남기지 않음. 알림 원문은 DB에만
- 미정: 알람을 어디로 보낼지 (8장 T16)
- 출처: [支付超时 全链路方案](https://cloud.tencent.com/developer/article/2581350)

## 4. 스토어별 규칙

### 4-1. 구글: 확인(acknowledge) 3일 규칙

- 사실 (전부 공식)
  - 구매를 3일 안에 처리하지 않으면 자동 환불되고 권한이 회수됨. 신규 구독, 재가입, 요금제 변경(새 토큰이 생기는 경우)은 확인 필요. 갱신은 불필요
  - 한 번 사는 상품은 소비(consume)가 확인을 겸함. 안 하면 다시 살 때 "이미 보유" 오류
  - 소비 API는 상품 ID와 토큰이 둘 다 필요
  - 결제 대기 구매는 확인하지 않음. 3일은 결제가 끝난 때부터
  - 기존 구독이 미확인이면 요금제 변경과 재구독이 막힘
  - 거절한 구매는 3일 만료에 맡기지 말고 직접 환불. 구독은 `subscriptionsv2.revoke`, 일회성은 `orders.refund`(`revoke=true`). 그 토큰에는 확인·소비를 호출하지 않음
  - 테스터는 3분(문서 다른 곳은 5분) 안에 확인하지 않으면 환불
- 서버가 할 일
  - 서버가 확인함. 순서는 DB 커밋 뒤 확인 (ADR-0002 D10과 같음)
  - 확인이 실패하면 다시 시도. "지급했는데 미확인"인 줄을 대조 작업이 주기적으로 봄
- 선택지 (8장 T6)
  - DB 커밋 뒤 확인: 확인이 실패해도 재시도로 복구. 중복 지급은 유일 키가 막음
  - 확인 뒤 커밋: 커밋이 실패하면 지급 없이 확인된 구매가 남아 복구가 어려움
  - 추가 선반을 "소비"할지 "확인"만 할지: 소비하면 같은 상품을 다시 살 수 있음(ADR-0002 D1의 전제). 확인만 하면 한 번만 살 수 있음
- 출처: [구글 결제 통합](https://developer.android.com/google/play/billing/integrate), [보안](https://developer.android.com/google/play/billing/security), [테스트](https://developer.android.com/google/play/billing/test)

### 4-2. 구글: 구독 상태와 권한

| 상태 | 권한 | 비고 |
|---|---|---|
| ACTIVE | 줌 | 무음 유예 중에도 이 상태 |
| IN_GRACE_PERIOD | 줌 | |
| CANCELED | 만료 시각까지 줌 | 해지 알림에서 바로 회수하는 것이 가장 흔한 버그. 정책 위반 소지 |
| ON_HOLD | 안 줌 | 만료 시각은 과거. 복구되면 갱신일이 복구일로 바뀜 |
| PAUSED | 안 줌 | 현재 주기가 끝난 뒤 시작 |
| EXPIRED | 안 줌 | |
| PENDING | 안 줌 | 결제 대기 |
| PENDING_PURCHASE_CANCELED | 안 줌 | |
| 모르는 값 | 안 줌 | 로그를 남김 |

- 우리 코드: 위 표와 같음 (`server/internal/iap/google.go`). 해지 예약의 만료 시각 비교는 권한 계산 SQL이 함
- 유예: 기본 켜짐. 일수 선택지는 출처마다 다름(대행사). 보류: 기본 "60일 - 유예 일수" (공식), 최대 30일이라는 글도 있음 (대행사)
- 만료 시각은 `lineItems[].expiryTime`을 씀
- 출처: [구글 구독 수명 주기](https://developer.android.com/google/play/billing/lifecycle/subscriptions), [RevenueCat 상태 기계](https://www.revenuecat.com/guides/google-play-billing/the-subscription-state-machine)

### 4-3. 구글: 토큰과 주문 ID

- 사실
  - 구매 토큰은 전역 유일. 구글 공식: "주문 ID를 중복 확인이나 기본 키로 쓰지 말 것"
  - 프로모션 코드 구매, 결제 대기 구매는 주문 ID가 없음 (공식)
  - 구독은 갱신마다 주문 ID가 새로 생기고 토큰은 그대로. 최신 주문 ID는 `latestSuccessfulOrderId` (`latestOrderId`는 2027-08-31 종료) (공식)
  - 업그레이드, 다운그레이드, 만료 전 재가입은 새 토큰이 나오고 옛 토큰은 무효. 새 구독에 `linkedPurchaseToken`으로 옛 토큰이 적혀 있음. 안 끊으면 한 구매로 여러 사람이 권한을 가짐 (공식)
  - 예약된 변경(DEFERRED)은 한 구독에 항목이 둘. "새 토큰이 이긴다"는 단순 규칙은 틀릴 수 있음 (대행사)
  - 구매 토큰은 구독 만료 60일 뒤부터 조회 불가 (공식)
- 서버가 할 일
  - 유일 키: 일회성 상품은 토큰, 구독 갱신 거래는 주문 ID. 구독 줄기는 토큰
  - 새 토큰에 `linkedPurchaseToken`이 있으면 같은 트랜잭션에서 옛 줄기를 끝냄
  - 우리 코드는 구독 항목이 1개가 아니면 멈춤 (`google.go`). 예약 변경에서 항목이 2개가 되므로 요금제 변경을 지원하려면 고쳐야 함
- 출처: [구글 보안](https://developer.android.com/google/play/billing/security), [RevenueCat 구글 예외 사례](https://www.revenuecat.com/blog/engineering/google-play-edge-cases), [API 지원 종료](https://developer.android.com/google/play/billing/play-developer-apis-deprecations)

### 4-4. 애플: 결제 실패와 상태

- 상태 값: 1 활성, 2 만료, 3 결제 재시도, 4 유예, 5 취소·환불. 권한은 1과 4만 (공식)
- 결제 재시도는 최대 60일. 횟수와 간격은 비공개
- 유예 기간: 3, 16, 28일 중 선택(주 구독은 최대 6일). 결제 오류 시점에 배정되면 못 바꿈. "모든 갱신" 또는 "유료에서 유료로 갱신할 때만" (공식)
- 알림 흐름: 갱신 실패(유예면 `GRACE_PERIOD`) → 유예 종료 → 복구되면 갱신(`BILLING_RECOVERY`) → 60일 실패면 만료(`BILLING_RETRY`)
- 복구 날짜: 유예 안에 복구하면 갱신일 유지. 유예 뒤 복구하면 복구일이 새 결제일. 구글도 같음(유예 복구는 유지, 보류 복구는 변경) (공식)
- 유예 중 거래의 만료 시각은 과거 값 그대로. 유예의 끝은 갱신 정보의 `gracePeriodExpiresDate`
- 알림과 실제 상태가 어긋난 보고가 있음 (포럼). 상태는 구독 상태 조회로 확정
- 결제 수단 수정 안내 주소: `https://apps.apple.com/account/billing`
- 선택지 (8장 T7): 유예 일수. 길면 결제 복구가 늘고, 복구 못 하면 그 기간은 무료로 쓴 것
- 출처: [애플 비자발적 이탈 줄이기](https://developer.apple.com/documentation/storekit/reducing-involuntary-subscriber-churn), [유예 기간 켜기](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions/)

### 4-5. 구독 변경 (월↔연)

- 애플 (공식)
  - 업그레이드는 즉시. 이전 구독의 남은 금액은 환불되고 업그레이드 날짜가 새 갱신일
  - 다운그레이드와 기간이 다른 교차 변경은 다음 갱신일에 적용
  - `isUpgraded`가 참인 거래는 무시하고 더 높은 등급의 다른 거래로 권한을 판단
  - 원 거래 ID는 같은 구독 그룹 안에서는 갱신·재구독·변경에도 유지 (포럼, 애플 엔지니어). 드물게 바뀐 보고가 있음
  - 업그레이드 때 이전 거래에 환불 알림이 올 수 있음. 그것으로 권한 전체를 끊으면 안 됨
- 구글 (공식)
  - 교체 방식 5가지. 같은 구독 상품 안에서 자동 갱신 요금제끼리 옮길 때는 `CHARGE_FULL_PRICE`와 `WITHOUT_PRORATION`만 유효. 다른 방식은 구매 실패. 우리(구독 1개에 월·연)가 여기에 해당
  - 요금제 변경 때 기존 계정 연결 값을 다시 넘겨야 함
  - 교체 방식은 앱이 지정. 서버는 허용 범위만 정함
- 선택지 (8장 T8)
  - 출시 때 앱 안에서 요금제 변경을 지원할지: 지원하면 위 규칙을 다 구현. 안 하면 "해지 뒤 다시 가입"을 안내. 다만 애플은 설정 앱에서 사용자가 직접 바꿀 수 있어 서버는 어차피 받아야 함
  - 구글 월→연: 즉시 전액 청구(이해하기 쉬움) vs 다음 갱신 때 청구
- 출처: [애플 구독 정보](https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information), [구글 구독](https://developer.android.com/google/play/billing/subscriptions), [애플 포럼 732932](https://developer.apple.com/forums/thread/732932)

### 4-6. 환불

- 애플 (공식)
  - `REFUND`(모든 상품 유형), `REFUND_DECLINED`, `REFUND_REVERSED`(환불이 되돌려짐. 회수했던 권한을 복원)
  - 부분 환불 칸(2025-12 추가): `revocationType`, `revocationPercentage`
  - `CONSUMPTION_REQUEST`: 고객이 환불을 요청하면 옴. 고객이 동의한 경우에만 12시간 안에 사용 정보를 보냄. 동의 없이 보내면 400. 동의는 명시적이어야 하고 추적 허용 팝업으로 받으면 안 됨. 앱 개인정보 라벨에 공개 필요
  - 반복 환불 계정을 식별하고 조치하는 것은 개발자 책임
- 구글 (공식)
  - 환불과 권한 회수는 별개. `orders.refund`는 `revoke=true`여야 회수됨. 구독은 최신 주문일 때만 회수되므로 `subscriptionsv2.revoke`를 권장
  - 무효 구매 목록: 최근 30일. 환불 주체(사용자, 개발자, 구글)와 사유(차지백 등)가 나옴
  - 소비한 상품의 환불 처리는 개발자 몫. 공식 제안은 잔액을 음수로, 활동 제한, 단계적 제재
- 환불 문의: 스토어가 환불을 처리하고 개발사는 직접 못 함. 개발사와 스토어 사이에서 사용자가 오가는 사례가 반복됨 (커뮤니티)
- 중국 사례: 환불 뒤 재화가 남는 것이 환불 대행 산업의 수익원이었음. 대응은 환불 이력으로 경고→제한→정지. 정상 사용자가 걸리는 것이 난점 (커뮤니티, 2016~2018)
- 선택지 (8장 T9)
  - 환불된 선반: ADR-0002 D13은 "잠금, 꽂힌 책은 유지". 잠긴 선반의 책을 옮기게 할지는 #6에서 미정 → 2026-11-19 정환: 책을 빼 내 책에 보관하고 그 칸을 잠금(D13 변경)
  - 환불 요청 때 사용 정보를 보낼지: 보내려면 동의 수집과 개인정보 라벨 변경. 안 보내면 구현 없음. 응답이 없으면 환불이 승인되는 경향이라는 글이 있음 (대행사, 한 회사 사례)
  - 반복 환불 계정: 아무 조치 없음 / 구매 제한. 제한하려면 약관에 적어야 함
- 출처: [애플 환불 알림 처리](https://developer.apple.com/documentation/storekit/handling-refund-notifications), [사용 정보 보내기](https://developer.apple.com/documentation/appstoreserverapi/send-consumption-information), [구글 구매 관리](https://developer.android.com/google/play/billing/manage-purchases), [환불 대행 산업](https://www.baijing.cn/article/3324)

### 4-7. 가격 변경

- 애플 (공식): 동의가 필요한 인상은 ① 동의를 요구하는 지역 ② 50% 초과이면서 일정 금액 초과 ③ 12개월 안에 인상 이력. 응답이 없으면 주기 끝에 만료. 적용된 인상은 되돌릴 수 없음
- 구글 (공식): 기존 구독자는 기본으로 옛 가격에 남음. 동의형 인상은 동의하지 않으면 해당 갱신 때 자동 해지. 한국은 무료 체험·도입가 뒤 가격이 오르면 별도 동의(step-up)가 필요하고 동의하지 않으면 자동 해지
- 한국 법: 증액·유료 전환 전 30일 이내 별도 동의 (ADR-0003 L5)
- 영향: 출시 뒤 가격을 올리기 어려움. 첫 가격을 신중하게 (#6)

### 4-8. 라이브러리와 API의 지원 종료

- 구글 결제 라이브러리(PBL): 버전마다 2년. 7은 2026-11-01에 연장까지 끝남. 8은 2027-08-31, 9는 2028-08-31 (공식)
- Flutter `in_app_purchase_android` 0.5.5가 PBL 9.1.0 (pub.dev 변경 기록)
- 구글 서버 API: `subscriptions.get` 등 2027-08-31 종료. 우리는 처음부터 v2 사용
- 애플: 권장 도메인이 2026-05-05부터 `api.storekit.apple.com`. 옛 도메인도 지원. `go-iap` v1.59.1은 새 주소를 씀 (소스 확인)
- 애플 2026 신규: 12개월 약정 월 구독, 복수 좌석. 안 써도 모르는 값이 올 수 있어 해석을 관대하게

## 5. 계정과 구매의 연결

### 5-1. 앱을 거치지 않은 구매

- 사실 (공식)
  - 애플: 오퍼 코드 사용, App Store에서 직접 한 구독은 계정 연결 값이 없음
  - 구글: Play 스토어에서 직접 재구독하면 값이 없음. 구독 정보의 `outOfAppPurchaseContext`에 만료된 옛 토큰과 옛 값이 있고, 서버가 이것으로 사용자를 찾아 확인해야 함 (3일 기한)
  - 이런 구매가 늘고 있음 (스토어 추천, 보상)
- 서버가 할 일
  - 값이 없는 거래도 정상 입력으로 받음. "주인 미확인"으로 두고, 앱이 로그인 상태에서 그 거래를 제출하면 연결
  - 구글은 기한 안에 확인하지 않으면 환불되므로 주인을 못 찾아도 확인은 해야 하는지 정해야 함
- 선택지 (8장 T10)
  - 값이 없는 거래를 제출한 로그인 사용자에게 지급: 편함. 남의 거래 ID를 아는 사람이 가져갈 수 있음
  - 거절하고 "구매 복원"에서만 연결: 안전. 복원 경로를 따로 만들어야 함
  - 근거 조사 결과: 업계 기본은 첫 번째(제출한 사용자에게 연결). 두 번째는 보수적 선택 (8-2 T10)
  - `Check` 함수(범수가 구현)의 "빈 값" 결정이 이 선택

### 5-2. 계정 연결 값

- 애플 (공식): 2025-06에 Set App Account Token API 추가. 원 거래 ID로 호출하고, 현재와 이후 갱신에 적용. 가족 공유 거래는 불가
- "첫 구매 때 굳는다"는 문장은 애플 문서에 없음. 포럼 관측은 엇갈림 (2023: 처음 값 유지, 2026: 교차 변경 때 바뀜) (미확인, 9장 U5)
- 애플 권장: 계정 하나의 모든 구매에 같은 값 (대행사, WWDC25 요약)
- 구글: 최대 64자. 개인정보를 넣으면 구매 차단 (공식). 우리는 무작위 UUID라 해당 없음
- 값이 기대와 다르면 믿지 말고 경고를 남김. 원인은 보통 같은 스토어 계정으로 다른 앱 계정에 로그인한 것
- V21 초안의 "유저 하나에 값 여러 개" 구조는 어느 쪽이든 안전
- 선택지 (8장 T11): 구독을 다른 계정으로 옮길 때(ADR-0002 D8) 애플에 새 값을 써넣을지. 넣으면 이후 알림이 새 계정을 가리킴. 안 넣으면 옛 값이 계속 와서 우리 표로 풀어야 함

### 5-3. 기기 계정으로 산 뒤 로그인

- **결정됨 (2026-11-19 정환)**: 로그인 필수, 오프라인 계정 없음(ADR-0002 D9). 구매가 늘 로그인 계정에 묶여 이 문제가 생기지 않음. 남은 일은 기존 기기 계정 사용자를 로그인 계정으로 옮기는 것(로그인 작업)

- 사실: 우리 서버의 계정 전환은 데이터를 합치지 않고 "이전 계정" 관계만 기록 (`server/internal/server/google.go`의 `recordSwitch`)
- 문제: 비로그인으로 산 구매(ADR-0002 D9)가 옛 기기 계정에 남음
- 선택지 (8장 T12)
  - 전환할 때 구매와 계정 연결 값을 새 계정으로 옮김: 단순. 로그아웃 뒤 기기 계정으로 돌아가면 구매가 없음
  - 권한 계산에서 이전 계정을 같이 봄: 옮기지 않음. 계산이 복잡해지고 계정 삭제와 엮임
  - 비로그인 구매를 막음: D9를 뒤집음. 애플 심사가 로그인 강제를 문제 삼을 수 있음
- 중국어권 글: 같은 스토어 계정으로 여러 앱 계정에 로그인해 "다른 계정에 들어간" 구매가 누락 신고의 단골 원인. 결제 중에는 계정 전환을 막음 (커뮤니티)

### 5-4. 가족 공유

- 한번 켜면 끌 수 없음 (공식). 켜면 가족 구성원마다 거래가 따로 생기고 회수 알림(`REVOKE`)을 처리해야 함
- 제안: 켜지 않음. 켜지 않아도 `inAppOwnershipType`은 확인하고 모르는 값은 지급하지 않음

## 6. 환경과 시험

### 6-1. 샌드박스 거래

- 사실
  - TestFlight와 심사는 샌드박스로 결제 (공식: TestFlight. 포럼: 심사)
  - 서버가 샌드박스 거래를 처리하지 못하면 심사에서 "무한 로딩"으로 반려 (커뮤니티)
  - 반대 사고: 운영 서버가 샌드박스 거래에 운영 권한을 줌 (网易云音乐)
  - 애플 문서 절차: 환경을 모르면 운영에 먼저 묻고 "거래 없음"이면 샌드박스에 물음. 같은 오류 문서는 "해결 못 하면 열어 주지 말라"고도 함. 이 폴백이 안전한지에 애플은 답하지 않음 (포럼)
  - 앱이 서명된 거래(JWS)를 같이 보내면 서버가 환경을 알 수 있음
  - 구글: 테스트 구매는 `testPurchase` 칸으로 표시. 라이선스 테스터가 아니면 테스트 트랙에서도 실제 청구
- 우리 상태: `go-iap`의 폴백 클라이언트 사용. 환경을 `iap_purchases.env`에 저장
- 선택지 (8장 T13)
  - 운영에서 샌드박스 거래를 거부: 안전. 심사 반려 위험
  - 받되 일반 사용자와 같은 권한: 지금 설계(D15). 샌드박스 계정을 가진 사람(TestFlight 참가자)이 무료로 씀
  - 받되 허용 목록의 계정만: 심사 계정을 미리 알 수 없음
  - 받되 기한을 둠: 시험은 되고 누출은 제한. 구현이 늘어남
- 출처: [云音乐 IAP 实践](https://juejin.cn/post/7233948883045941303), [애플 거래 없음 오류](https://developer.apple.com/documentation/appstoreserverapi/transactionidnotfounderror), [애플 포럼 848630](https://developer.apple.com/forums/thread/848630)

### 6-2. 시험 환경의 시간

| | 애플 샌드박스 | 구글 라이선스 테스터 |
|---|---|---|
| 1개월 구독 | 5분 (설정으로 3분~1시간) | 5분 |
| 1년 구독 | 1시간 | 30분 |
| 갱신 횟수 | 최초 구매 뒤 최대 12번 | 최대 6번 |
| 유예 | 5분 | 5분 |
| 결제 재시도·보류 | 10분 | 10분 |
| 알림 재시도 | 없음 (1번만) | |

- 구글 Play Billing Lab: 유예·보류 상태로 바로 전환, 앱 밖 구매 시험 가능
- 샌드박스 알림은 한 번만 오므로 대조 작업으로 누락을 확인
- 샌드박스에서 환불을 시험할 수 있는지는 글마다 다름 (9장 U9)

### 6-3. 앱 쪽 누락 방지

- 지급 확인 응답을 받은 뒤에만 거래를 끝냄(`completePurchase`). ADR-0002 D10
- 끝내지 않은 거래는 앱 시작 때 다시 전달됨. 서버에 다시 제출. Flutter `in_app_purchase`에서 소모성 상품이 "복원됨"으로 오는 사례 (포럼)
- 구매 버튼 연타 방지. 결제 중에는 계정 전환을 막음
- 서버 응답이 늦을 때의 제한 시간과 오류 표시. 없으면 심사 반려
- 영구 실패(진짜 무효 거래)는 끝내서 무한 재시도를 막음
- 사용자가 직접 "구매 복원"을 누를 수 있는 입구. 심사 필수
- 구글: 서버가 확인했으면 앱의 확인을 생략 (커뮤니티, gee6809)

## 7. 날짜, 금액, 장부

### 7-1. "한 달"의 기준

| | 애플 | 구글 |
|---|---|---|
| 규칙 | 최초 구매 날짜와 같은 날. 그 날짜가 없는 달은 말일, 이후 원래 날짜로 복귀 | 29~31일이 2월을 지나면 28일로 옮겨지고 계속 28일. 3/31 시작은 4/30, 이후 30일 |
| 예 | 1/30 → 2/28 → 3/30 | 1/31 → 2/28 → 3/28 |
| 확인 | 공식 (1/30 예). 1/31과 연 구독 2/29는 추정 | 공식 |

- 서버는 다음 결제일을 계산하지 않음. 스토어가 준 만료 시각만 저장하고 표시 (애플 문서도 "구매일+기간으로 계산하지 말라")
- 같은 날 가입해도 스토어에 따라 결제일이 달라짐. 고지 문구의 `{다음 결제일}`은 스토어 값
- 시각은 UTC로 저장하고 화면에서만 한국 시간으로. 애플 설정 앱의 만료일과 하루 어긋난다는 보고가 있음 (포럼, 9장 U8)
- PG 정기결제의 말일·윤년 처리를 다룬 한국어 글은 못 찾음. 토스페이먼츠 예제는 매월 1일 고정 (대행사)
- 선택지 (8장 T14): 화면의 날짜를 기기 시간대로 보일지 한국 시간으로 고정할지. 해외 판매 때 달라짐

### 7-2. 금액

- 애플 `price`: 통화 단위의 1000배 정수(3300원 = 3300000). 구매일의 설정 가격에 할인 반영 (공식). 애플 원문: 매출 정산에 쓰지 말고 App Store Connect 보고서를 기준으로
- 구글: 구매 조회에 실제 결제 금액이 없음. `orders.get`의 `total`(할인·세금 반영), `tax`를 따로 조회. 갱신마다 주문 ID가 새로 생김 (공식)
- 스토어 가격이 매출이 아닌 이유
  - 소비자가 낸 부가세가 들어 있음 (11,000원 = 10,000원 + 1,000원)
  - 스토어 수수료가 빠짐
  - 환불과 조정이 다음 달 보고서로 넘어감
  - 외화 판매는 입금일 환율로 바뀜
- 선택지 (8장 T15): 구글 금액을 주문 조회로 실시간 저장할지, 정산 보고서로만 볼지

### 7-3. 정산

| | 애플 | 구글 |
|---|---|---|
| 지급 시점 | 회계월 마지막 날 기준 45일 이내, 통화별 월 1회 | 그달 주문을 다음 달 15일쯤 |
| 최소 지급액 | 한국 은행 원화 계좌 1달러 | 현지 통화 1달러 (한국 적용은 미확인) |
| 보고서 | 재무 보고서. 회계월 첫 금요일부터 | 수익 보고서. 보통 다음 달 5일 |
| 수수료 증빙 | 사업자등록번호가 검증되면 매월 전자세금계산서. 검증 전에는 현금영수증 | 사업자등록번호를 입력하지 않으면 수수료에 10% 별도 청구 (커뮤니티) |

- 전부 공식 (표시한 것 제외)
- 사업자등록번호는 최대한 일찍 입력. 애플은 세금 정보를 안 내면 지급이 늦어짐
- 구글은 2026-10부터 보고서의 수수료 설명 값이 바뀜. 값을 글자 그대로 비교하는 자동화는 깨질 수 있음

### 7-4. 세무 (전문가 확인 필요)

- 다수 의견
  - 한국 소비자 매출은 개발자가 부가세 10%를 신고. 해외 소비자 매출은 영세율 (전문가)
  - 매출은 수수료를 빼기 전 총액으로 신고하고 수수료는 비용 또는 매입 (전문가 다수). 순액으로 신고하면 매출 과소 신고라는 경고
- 엇갈리는 것
  - 11,000원 판매의 매출이 10,000원인지 11,000원인지 (세무사 5명 중 3대 2)
  - 애플 입금이 외화인지 원화인지
  - 간이과세 기준 금액, 통신판매업 신고 면제 기준
  - 사업자등록 전 정산분의 처리
- 연 구독: 받은 돈을 선수수익으로 잡고 기간에 걸쳐 인식하는 것이 회계 원칙. 가입 즉시 매출로 잡았다가 투자 실사에서 지적받은 사례 (전문가). 소규모 개인사업자의 소득세 신고에서 어디까지 해야 하는지는 미확인
- 기록 보존: 계약·청약철회 5년, 대금 결제·공급 5년, 분쟁 처리 3년 (법령 미러 사이트로 확인. 원문 대조 필요)
- 세무사에게 물을 질문
  1. 한국 소비자 인앱결제의 부가세를 우리가 신고·납부하는지, 신고 매출은 부가세 포함 총액인지
  2. 일반과세와 간이과세에 따라 신고, 영세율, 매입세액 공제가 어떻게 다른지
  3. 해외 소비자 판매분의 영세율과 소명 서류
  4. 스토어 수수료는 매입인지 비용인지. 애플 전자세금계산서로 공제되는지, 구글은 어떤 증빙을 받는지
  5. 사업자등록 전에 생긴 매출과 수수료
  6. 연 구독의 수입 시기. 월별로 나눠야 하는지. 환불 때 수정 방법
  7. 업종코드와 복식부기 의무 기준
  8. 소비자 결제에 현금영수증·세금계산서 발행 의무가 있는지
  9. 통신판매업 신고 필요 여부와 시기, 구매안전서비스 확인증
  10. 환율 차이와 송금 수수료, 입금 보고서와 장부의 대조 방법
  11. 증빙·장부 보존 기간
  12. 법인 전환 때 스토어 계정과 정산 관계

### 7-5. 원장에 남길 것

- 지금 V21: 거래 ID, 경로, 상품, 종류, 유저, 계정 연결 값, 환경, 상태, 구매 시각, 환불 시각, 통화, 금액, 국가
- 조사에서 추가로 권하는 것
  - 공급가액과 부가세를 나눈 값
  - 스토어 수수료, 정산 순액, 정산 월, 입금 환율 (보고서에서)
  - 상태 변경 이력
  - 스토어 응답 원문 (감사용)
- 회계 글의 원칙: 줄을 지우거나 고치지 않고 더함. 환불은 반대 줄을 더함. 소규모는 불변 원장 + 반대 기장만으로 충분 (커뮤니티, 掘金)
- 지금 V21은 환불을 같은 줄의 상태 변경으로 남김. 반대 줄 방식으로 바꿀지 정해야 함 (8장 T15)

## 8. 정해야 하는 것과 이미 답이 있는 것 (근거 확인본)

- 2026-11-19에 세 번 고침
  1. 처음: 16건 모두 "정답 없음"
  2. 재검토: 내 판단으로 "답 있음" 4건을 가려냄
  3. 근거 조사: 항목마다 공식 문서, 스토어 엔지니어 답변, 결제 대행사의 기본 동작을 찾아 확정. 2번의 판정 중 T1, T3, T5, T6, T7, T10, T11이 틀리거나 부족했음
- 판정 기준
  - 답 있음: 공식 문서나 스토어 엔지니어의 답이 있거나, 여러 출처가 같은 답을 권하고 반대 출처가 없음
  - 선택: 출처가 갈리거나 공식 답이 없음. 이때는 대행사(RevenueCat, Adapty)의 기본값을 "업계 기본"으로 적음
- 못 찾은 것: 실제 숫자(대조 주기, 제한 시간)를 공개한 기업 기술 블로그. 국내외 모두 못 엶

### 8-1. 판정표

| # | 문제 | 판정 | 답 또는 업계 기본 | 확신 |
|---|---|---|---|---|
| T1 | 스토어 조회가 실패할 때 지급 | 상품에 따라 갈림 | 소모성·구글은 보류가 답. 애플 구독은 선택 (보류 / 서명 확인 뒤 임시 지급) | 중 |
| T2 | 시간 제한 값 | 원칙은 답, 숫자는 선택 | 외부 호출은 트랜잭션 밖. 숫자는 8-3의 참고값에서 시작 | 중 |
| T3 | 만료 직후의 틈 | 재조회는 답, 버퍼는 선택 | 끊기 전에 재조회. 유예 중이면 유지. 업계 기본은 버퍼 없음, 선택적으로 6시간 | 중 |
| T4 | 알림 응답 시점 | 답 있음 | 저장하고 바로 2xx, 처리는 뒤에서 | 상 |
| T5 | 대조 작업 | 있어야 함은 답, 주기는 선택 | 애플 권고는 갱신 시점 재확인과 장애 뒤 이력 조회. 전부 재조회를 권하는 곳은 없음 | 중 |
| T6 | 구글 확인 | 답 있음. D1과 충돌 | 서버가, 지급 직후. 한 번 사면 영구인 상품은 비소모성으로 등록하고 소비하지 않음 | 상 |
| T7 | 유예·보류 설정 | 켜는 것은 합의, 일수는 취향 | 애플 16일·모든 갱신, 구글 유예 7 또는 14일 + 보류 30일 | 중 |
| T8 | 월↔연 변경 UI | 선택 | 최소 구성은 UI 없이 스토어 구독 관리 링크. 애플 쪽 변경은 서버가 반드시 처리 | 중 |
| T9 | 환불 대응 | 회수는 답, 나머지 선택 | 사용 정보 전송은 대행사마다 기본값이 다름. 동의 없이는 보낼 수 없음 | 중 |
| T10 | 계정 연결 값이 없거나 다른 구매 | 다른 값은 답, 빈 값은 선택 | 다르면 거절. 비면 업계 기본은 제출한 사용자에게 연결 | 상 / 하 |
| T11 | 애플에 새 값 써넣기 | 의무 아님. 조건 있음 | 안 써도 됨. 대신 알림을 원 거래 ID로 현재 주인에게 연결해야 함 | 중 |
| T12 | 익명 구매 뒤 로그인 | 선택 | 업계 기본은 로그인 계정으로 따라가고 한 번에 한 계정 | 중 |
| T13 | 샌드박스 거래 | 선택 | 받을 수 있어야 함까지만 정해짐. RevenueCat 기본은 전부 지급 | 상 |
| T14 | 날짜 표시 시간대 | 취향 | 권고 없음. 흔한 것은 기기 시간대에 날짜만 | 하 |
| T15 | 금액과 장부 | 매출 기준은 답, 나머지 선택 | 매출은 스토어 정산 보고서. 환불은 반대 줄이 일반 권고 | 상 / 중 |
| T16 | 관측과 알람 | 선택 | 최소 항목은 검증 오류 급증과 알림 미수신 | 하 |

### 8-2. 항목별 근거

**T1. 스토어 조회가 실패할 때**

- 소모성 상품과 구글은 보류
  - 구글: 서버에서 확인한 뒤 지급. "Don't grant entitlement when the purchase state is PENDING." ([구글 보안](https://developer.android.com/google/play/billing/security))
  - RevenueCat도 1회성 구매는 임시 지급을 지원하지 않음 ([Offline Entitlements](https://www.revenuecat.com/blog/engineering/introducing-offline-entitlements.md))
  - 보류에도 시한이 있음: 구글은 3일 안에 확인하지 못하면 자동 환불
- 애플 구독은 선택
  - 애플은 서명 확인만으로 충분하다고 함: "There's no need to call our server to verify the signed transaction info." ([WWDC21 10174](https://developer.apple.com/videos/play/wwdc2021/10174/)). 다만 장애 상황을 직접 다룬 문장은 아님
  - RevenueCat은 2020년 애플 장애(약 5시간, 실패한 구매 50만 건 이상) 때 "temporarily unlock access for anyone who posts a receipt" 뒤 재처리. 교훈으로 "build a fallback receipt validation path for when Apple returns 500 errors" ([사후 분석](https://www.revenuecat.com/blog/engineering/post-mortem-2020-01-24-app-store-outage))
  - 서명은 그 시점의 사실만 보증. 환불·만료 같은 현재 상태는 모름 (추론)
- 공통: 끝내지 않은 거래는 앱 시작 때 다시 옴. "the updates listener receives them once, immediately after the app launches." ([애플 Transaction.updates](https://developer.apple.com/documentation/storekit/transaction/updates.md))
- 우리 선택지: 애플 구독도 보류로 시작(단순). 스토어 장애로 문의가 생기면 서명 확인 임시 지급을 추가

**T2. 시간 제한 값**

- 원칙: "Ideally, a transaction should only contain database statements." ([GitLab 트랜잭션 지침](https://docs.gitlab.com/ee/development/database/transaction_guidelines.html))
- 숫자는 8-3

**T3. 만료 직후의 틈**

- 재조회: "Call the purchases.subscriptionsv2.get() method at the RTDN time instead of the expiry time to get a more accurate status of the subscription." ([구글 구독 수명 주기](https://developer.android.com/google/play/billing/lifecycle/subscriptions))
- 구글은 유예 0일이어도 "Play will wait a minimum of 1 day to ensure sufficient time for payment retries" (같은 문서)
- 애플 직원: "you could allow a short offline allowance based on the last verified expiration date" ([포럼 840705](https://developer.apple.com/forums/thread/840705))
- RevenueCat의 기본은 버퍼 없음: "At the planned renewal time, entitlements go empty." 갱신은 "can land minutes or hours after the previous expiryTime", 지연은 "often under ~24 hours". 선택 사항으로 만료가 "less than six hours ago"이면 "treat the customer as renewal pending rather than fully churned" ([RevenueCat 구글 갱신 지연](https://www.revenuecat.com/docs/customers/google-play-renewal-extensions.md))
- 스토어에 유예를 켜 둔 것만으로는 이 틈이 메워지지 않음: "A configured store grace period doesn't keep entitlements active the moment a billing period ends." ([RevenueCat 유예](https://www.revenuecat.com/docs/subscription-guidance/how-grace-periods-work.md))

**T4. 알림 응답 시점**

- 애플 엔지니어: "It should only be a few seconds at most, or at best under a second. We recommend all of the logic around processing the notification be done asynchronously from receiving the notification" ([포럼 779594](https://developer.apple.com/forums/thread/779594))
- 애플 엔지니어: "we recommend to respond with 200 even if you believe it is a duplicate" ([포럼 756151](https://developer.apple.com/forums/thread/756151))
- Stripe: "Quickly returns a successful status code (2xx) before any complex logic that might cause a timeout." ([Stripe 웹훅](https://docs.stripe.com/webhooks))
- Adyen: "Store the event in a queue or database. Acknowledge the webhook with a response status code 202. Subsequently, process the event asynchronously." ([Adyen](https://www.adyen.com/knowledge-hub/webhooks-accept-2xx))
- GitHub는 10초, Shopify는 전체 5초, RevenueCat 웹훅은 "respond quickly and defer processing"
- 처리 뒤에 응답하라는 공식 문서는 못 찾음
- DB에 먼저 저장해야 하는 이유: 애플 재시도는 1시간 뒤부터. "If your server is down long enough to miss the final retry attempt from the App Store server, that notification is lost." ([WWDC22 10007](https://developer.apple.com/videos/play/wwdc2022/10007/))
- 구글만 예외: Pub/Sub이 메시지를 7일 보관하고 바로 재시도하므로 "처리 뒤 응답"도 가능. 평균 응답이 1초를 넘으면 전달이 느려짐 ([Pub/Sub 푸시](https://docs.cloud.google.com/pubsub/docs/push))

**T5. 대조 작업**

- 애플: "You can additionally schedule a job to call our subscription status API to check the status of your subscription at its renewal time as a fail-over mechanism." ([WWDC21 10174](https://developer.apple.com/videos/play/wwdc2021/10174/))
- 애플: "If your server misses notifications due to an outage, you can always get up-to-date transaction information by calling App Store Server API endpoints" ([알림 응답 문서](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications.md))
- Shopify: "Your app shouldn't rely on receiving data from Shopify webhooks." ([Shopify 웹훅 모범 사례](https://shopify.dev/docs/apps/build/webhooks/best-practices))
- 구글은 반대로 잦은 조회를 경고: 알림을 쓰면 폴링이 필요 없고 비효율적 사용은 한도 제한으로 이어짐 ([구글 준비 문서](https://developer.android.com/google/play/billing/getting-ready))
- 주기를 정하는 창: 애플 재시도 누적 약 157시간, 애플 알림 이력 180일, 구글 토큰 만료 후 60일, 구글 무효 구매 30일
- 정정: 3-5장의 "규모가 작을 때는 전부 재조회가 단순"은 근거 없음. 만료가 가까운 구독만 보는 것이 애플의 권고

**T6. 구글 확인**

- **결정됨 (2026-11-19 정환)**: 선반은 연도 책장마다(ADR-0002 D1). 사는 횟수에 끝이 없어 소모성 유지. 비소모성 여러 개 안은 쓸 수 없음. 서버가 지급 직후 확인(소비)하는 부분은 그대로

- 서버가: "server side APIs provide additional protection against issues like poor network connectivity and malicious activity." ([구글 보안](https://developer.android.com/google/play/billing/security))
- 지급 직후: "You should acknowledge the purchase immediately after granting entitlement." (같은 문서). "DB 커밋 뒤"라고 쓴 문장은 없음. 지급 기록이 먼저라는 뜻으로 읽은 것
- 영구 상품은 소비하지 않음: "Google removed the ability to query consumed one-time purchases" ([RevenueCat 알려진 문제](https://www.revenuecat.com/docs/known-store-issues/play-billing-library/restore-consumable-purchases-bc8.md)). RevenueCat은 비소모성으로 표시한 상품을 "will never consume"
- **ADR-0002 D1과 충돌**: D1은 추가 선반을 소모성으로 정함(같은 상품을 여러 번 사기 위해). 소비하면 스토어 복원이 안 되고 서버 기록만 남음. 비로그인 구매(D9)에서 앱을 지우면 되찾을 길이 없는 약점이 여기서 나옴
  - 대안: 선반을 비소모성 상품 여러 개로 등록(첫째 칸, 둘째 칸, 셋째 칸). 스토어가 복원해 줌. 상품이 늘고 "몇 번째를 살 차례인지" 로직이 필요
  - "최대 3칸"이 계정 전체면 이 대안이 가능. 연도 책장마다면 개수가 정해지지 않아 소모성밖에 안 됨
  - #6에서 선반 범위와 함께 다시 정함 → 2026-11-19 연도 책장마다로 정해져 소모성 유지

**T7. 유예·보류 설정**

- 애플: 3, 16, 28일. 앱 단위 설정. "모든 갱신"은 무료 도입 기간에도 적용 ([애플 유예 설정](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions))
- Adapty: "Enable grace period with an appropriate duration (16 or 28 days for most apps)", "Most apps benefit from All Renewals." ([Adapty](https://adapty.io/blog/how-to-handle-apple-billing-grace-period/)). 근거 수치(15~20% 더 회수)는 출처 표시 없음
- RevenueCat: "For most apps, enabling both grace period (7 or 14 days) and account hold (30 days) is the right choice." ([RevenueCat 구글 가이드](https://www.revenuecat.com/guides/google-play-billing/payment-recovery-grace-period-and-account-hold))
- 구글 수치로 소개된 것: 보류를 더하면 결제 실패 회수 35% 증가, 비자발적 이탈 8% 감소 ([RevenueCat](https://www.revenuecat.com/blog/growth/google-play-billing-error-churn-how-to-fix))
- 구글은 유예·보류·일시중지가 모두 기본으로 켜져 있음. 일시중지를 끄라고 권하는 글은 못 찾음
- 유예를 켜지 말라는 글은 못 찾음

**T8. 월↔연 변경**

- 애플은 사용자가 설정 앱에서 바꿀 수 있고 `DID_CHANGE_RENEWAL_PREF`가 옴. 서버가 처리해야 함 ([애플 알림 유형](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype.md))
- 심사 지침 3.1.2(b): "Users should have a seamless upgrade/downgrade experience and should not be able to inadvertently subscribe to multiple variations of the same thing." 앱 안에 변경 화면이 있어야 한다는 문장은 없음
- 구글: "Your app should include a link on a settings or preferences screen that allows users to manage their subscriptions" ([구글 구독](https://developer.android.com/google/play/billing/subscriptions))
- 구글에서 토큰 잇기를 무시하면 "would then appear to have two active subscriptions when they should have one." ([RevenueCat](https://www.revenuecat.com/guides/google-play-billing/subscription-upgrades-downgrades-and-plan-changes))
- 미확인: Play 스토어의 구독 관리 화면에서 사용자가 월→연을 직접 바꿀 수 있는지
- 이중 가입: 애플은 같은 구독 그룹이면 하나만 활성이라 구조적으로 막힘. 구글은 서버가 막아야 함

**T9. 환불 대응**

- 회수: 애플은 `REFUND`, 되돌려지면 `REFUND_REVERSED`. 구글은 "When a purchase is voided, you can claw back unused items as if they were never purchased." ([구글 보안](https://developer.android.com/google/play/billing/security))
- 사용 정보 전송의 규칙: "If the customer provided consent, respond by calling this API ... If not, don't respond to the CONSUMPTION_REQUEST notification." 12시간 안. 동의는 선택 해제 방식이 아니라 명시 동의 ([애플](https://developer.apple.com/documentation/appstoreserverapi/send-consumption-information.md))
- 환불 선호는 참고 사항: "Your refund preference is one of a variety of factors that the App Store uses to inform its refund decisions." ([애플](https://developer.apple.com/documentation/appstoreserverapi/refundpreference.md))
- 대행사 기본값이 다름

| | RevenueCat | Adapty |
|---|---|---|
| 기본 동작 | 응답 안 함 | 첫 요청은 거절 선호, 이후는 승인 |
| 내세우는 효과 | 환불률 3% → 1.9% (자사 앱 하나, 15일) | 4% → 2.3% (자체 수치) |

- 응답이 의무라는 문장은 없음. 응답하라는 근거는 모두 대행사 자료
- 반복 환불: 구글이 단계적 조치를 예시. "Consider taking less drastic actions for first-time offenders, such as displaying in-app warnings." 횟수 기준은 없음
- 한국 전자상거래법과 스토어 환불의 관계를 다룬 글은 못 찾음 (전문가 확인)

**T10. 계정 연결 값이 없거나 다른 구매**

- 다르면 거절: "If you configured the billing flow with obfuscatedAccountId or obfuscatedProfileId, check that the purchase mapping matches the expected user account in your system." ([구글 보안](https://developer.android.com/google/play/billing/security)). 애플 쪽에는 같은 요구가 없음
- 비는 경우는 정상 구매일 수 있음: "customers can also purchase in-app products outside of your app, for example, by redeeming an offer code in the App Store. In that case, the original transaction doesn't include an app account token." ([애플](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token.md))
- 애플 엔지니어: "There's no reliable way to distinguish between transaction made inside the app vs outside of the app" ([포럼 757600](https://developer.apple.com/forums/thread/757600))
- 업계 기본: 거래를 제출한 사용자에게 연결 (RevenueCat의 Transfer)
- 정정: 5-1장에서 "거절하고 복원에서만 연결"을 안전한 쪽으로 권했지만 이것은 업계 기본이 아닌 보수적 선택. 값이 없는 구매가 얼마나 흔한지 수치는 없음

**T11. 애플에 새 값 써넣기**

- 용도: "set or reset the appAccountToken associated with the transaction you specify in the originalTransactionId parameter." ([애플](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token.md)). 계정 소유가 바뀔 때의 불일치를 고치는 데 쓸 수 있음 ([WWDC25 249](https://nonstrict.eu/wwdcindex/wwdc2025/249/))
- 써야 한다는 문서는 없음
- 조건: 안 쓰면 알림의 값이 옛 계정을 가리킴. 알림을 처리할 때 값이 아니라 원 거래 ID로 현재 주인을 찾아야 함. V21의 `iap_subscriptions`가 원 거래 ID마다 현재 유저를 가짐
- 복원 때 구독을 옮기는 것(ADR-0002 D8)은 RevenueCat 기본과 같음: "The default behavior is to transfer purchases between identified App User IDs if needed." ([RevenueCat 복원 동작](https://www.revenuecat.com/docs/projects/restore-behavior))

**T12. 익명 구매 뒤 로그인**

- **결정됨 (2026-11-19 정환)**: 익명 구매 자체를 두지 않음. 로그인 필수(ADR-0002 D9)

- RevenueCat: 로그인하면 익명 ID를 계정 ID에 묶어 합침. 로그아웃하면 새 익명 ID ([RevenueCat 고객 식별](https://www.revenuecat.com/docs/customers/identifying-customers))
- Adapty: 옮기기 방식은 "limits purchase access to 1 customer ID at a time"이고 "works best for applications that allow purchases with or without authentication." ([Adapty](https://adapty.io/docs/sharing-paid-access-between-user-accounts))
- 심사 지침 5.1.1(v): "If your app doesn't include significant account-based features, let people use it without a login."
- 반대 쪽: 구매 전 로그인을 강제하면 단순해짐. RevenueCat의 "원래 주인 유지" 방식은 "only allowed for apps that require every customer to create an account before purchasing"
- 소모성 상품 전용 규칙은 못 찾음

**T13. 샌드박스 거래**

- 받을 수 있어야 함: 심사팀 회신으로 인용된 문장 "your server needs to be able to handle a production-signed app getting its receipts from Apple's test environment." ([포럼 93773](https://developer.apple.com/forums/thread/93773)). 공식 문서가 아니라 개발자가 옮긴 것
- RevenueCat 기본값: "Anybody (default)"는 "All non-production purchases ... will grant access to entitlements". 다른 옵션은 허용 목록, 전부 끔. 기본값은 "recommended for early development or internal QA testing." ([RevenueCat 샌드박스 접근](https://www.revenuecat.com/docs/projects/sandbox-access.md))
- 网易云音乐: "会导致一批没有真实支付的账号兑现线上权益". 대응은 "需要对这部分票据验证完成的权益发放进行限制，行为可追溯", "非审核期间关闭正式环境的沙盒校验" ([云音乐](https://juejin.cn/post/7233948883045941303))
- 구글은 `testPurchase` 칸으로 구분. 서버가 어떻게 하라는 문장은 없음

**T14. 날짜 표시**

- 애플·구글·대행사 문서에 표시 시간대를 정한 문장 없음
- 애플 설정 앱과 하루 어긋난다는 질문에 답이 없음 ([포럼 800332](https://developer.apple.com/forums/thread/800332))

**T15. 금액과 장부**

- 애플: "Important: For financial and accounting purposes, use the App Store Connect reporting tools." ([애플 price](https://developer.apple.com/documentation/appstoreserverapi/price.md))
- RevenueCat: "Rely on Apple's financial reports for accurate payout data, financial reporting, and all accounting use cases." ([RevenueCat 보고서 대조](https://www.revenuecat.com/docs/dashboard-and-metrics/reconciling-with-financial-reports))
- 구글 쪽의 같은 취지 문장은 공식 문서에서 못 찾음. 주문 조회의 `total`은 "The final amount paid by the customer, taking into account discounts and taxes"
- 환불 기록: Stripe는 환불을 별도 항목으로 남김 ([Stripe 잔액 거래 유형](https://docs.stripe.com/reports/balance-transaction-types)). "it's more accurate to store immutable transactions and always compute balances from those transactions." ([Modern Treasury](https://www.moderntreasury.com/journal/accounting-for-developers-part-i))
- 소규모 서비스에 반대 줄이 꼭 필요하다는 근거도, 과하다는 근거도 못 찾음

**T16. 관측과 알람**

- RevenueCat 사후 분석: "We should have been notified as soon as our receipt endpoint had elevated 500s." "The data was there in our monitoring, but it wasn't set up to notify anyone." ([사후 분석](https://www.revenuecat.com/blog/engineering/post-mortem-2020-01-24-app-store-outage))
- 일치하는 임계값은 없음. 공식 문서와 사고 사례가 함께 가리키는 최소 항목은 검증 오류 급증과 알림 미수신

### 8-3. 시간 제한 참고값

| 항목 | 값 | 누가 쓰는가 |
|---|---|---|
| 스토어 API 요청 제한 시간 | 30초 | 애플 공식 서버 라이브러리(Python, Java, Swift) 기본값. `go-iap`도 30초 |
| 앱 쪽 제한 시간 | 2초, 5초, 15초, 30초 (경우에 따라) | RevenueCat iOS SDK |
| 앱 쪽 재시도 간격 | 0, 0.75, 3초 | RevenueCat iOS SDK |
| DB 쿼리 / 락 대기 / 유휴 트랜잭션 | 10초 / 5초 / 1분 | 블로그 예시 (OneUptime) |
| 위 세 값 | 전부 15초 | GitLab.com |
| 연결 풀 기본 크기 | 4와 CPU 수 중 큰 값 | `pgx` |
| 연결 풀 크기 공식 | 코어 수 × 2 + 디스크 수, 이후 조정 | PostgreSQL 위키 |
| 재시도 | 최대 2회, 간격을 늘리며, 멱등 키와 함께 | Stripe 예시 |
| 알림 응답 | 몇 초 이내 (애플), 10초 (구글 기본, GitHub, Adyen), 5초 (Shopify) | |

- 앱이 서버 응답을 기다리는 시간의 공식 권장값은 없음

### 8-4. 누가 무엇을 정하나

- 그대로 구현: T4, T5(있어야 함), T6(서버가 지급 직후), T10(다른 값 거절), T15(매출은 정산 보고서), T3(재조회, 유예 중 유지)
- 정환과 정할 것
  - T6에서 나온 것: 추가 선반을 소모성으로 둘지 비소모성 여러 개로 바꿀지. 선반 범위(#6)와 함께 → 소모성 유지(2026-11-19)
  - T12: 익명 구매를 로그인 계정으로 옮길지. 업계 기본은 옮김 → 로그인 필수로 문제 자체가 없어짐(2026-11-19)
  - T13: 샌드박스 범위
  - T9: 환불 요청에 응답할지, 반복 환불 조치
  - T8: 월↔연 변경 화면
  - T7: 유예 일수. 권고값에서 시작
- 범수가 정하고 기록할 것: T1(애플 구독), T2 숫자, T3 버퍼, T5 주기, T10(빈 값), T11, T14, T15(반대 줄), T16
- 난이도 기준: 상은 틀리면 돈·권한 사고로 이어지고 되돌리기 어려움. 중은 고칠 수 있지만 재작업이 큼. 하는 설정값이라 나중에 바꿀 수 있음

## 9. 실측으로만 알 수 있는 것 (unknown)

| # | 모르는 것 | 확인 방법 |
|---|---|---|
| U1 | 애플 알림에 4xx로 답하면 재시도가 멈추는지 | 문서와 포럼이 다름. 4xx를 쓰지 않는 것으로 회피 |
| U2 | 애플 429의 `Retry-After` 단위 | 샌드박스에서 일부러 한도를 넘겨 응답 확인 |
| U3 | 재시도된 애플 알림의 `signedDate`가 원래 값인지 | 샌드박스는 재시도가 없음. 운영에서 관측 |
| U4 | 애플 1/31 시작 월 구독, 2/29 시작 연 구독의 다음 결제일 | 계산하지 않으므로 영향 없음. 관측만 |
| U5 | 애플 계정 연결 값이 갱신·교차 변경에서 유지되는지 | 샌드박스에서 값을 바꿔 가며 구매 |
| U6 | 소모성 거래가 애플 거래 내역 조회에 나오는지 | 샌드박스에서 구매 뒤 조회 (ADR-0002 부록 B) |
| U7 | 만료 뒤 갱신 알림이 실제로 얼마나 늦는지 | 운영에서 지연 분포를 기록. T3의 근거 |
| U8 | 애플 설정 앱의 만료일과 API 값이 하루 어긋나는지 | 샌드박스에서 비교 |
| U9 | 샌드박스에서 환불과 환불 알림을 시험할 수 있는지 | 직접 시험 |
| U10 | 구글 알림의 순서가 실제로 바뀌는지 | 재조회로 덮어쓰므로 영향 없음. 관측만 |
| U11 | `go-iap`이 쓰는 애플 도메인 | 확인함 (2026-11-19). v1.59.1은 새 도메인 `api.storekit.apple.com`을 씀 |
| U12 | 한국에서 구글 결제 대기(PENDING)가 실제로 나오는 결제 수단 | 테스트 카드 "느린 카드"로 흐름만 확인. 실제 발생은 운영 관측 |
| U13 | 이미 확인한 구글 토큰을 다시 확인·소비하면 어떤 오류가 나는지 | 테스트 구매로 확인 |
| U14 | 구글 서비스 계정 권한이 반영되는 데 걸리는 시간 (24시간~며칠) | 일찍 만들어 두고 기록 |
| U15 | KoDeploy에서 정기 작업을 돌릴 수 있는지 | KoDeploy 문서·문의 |
| U16 | KoDeploy가 알림 주소 요건(포트, TLS 1.2, 응답 시간)을 만족하는지, 서버가 잠들지 않는지 | 테스트 알림 요청으로 확인 |
| U17 | 법규: "갱신 14일 전 개별 통지" 조항의 실재, 스토어 결제에서 통신판매업자 여부 | 전문가 확인 (ADR-0003 7장) |

## 10. 이슈 대응

- 이 문서에서 나온 작업은 마일스톤 "인앱결제 1차"에 이슈로 올림. 상위 이슈가 있는 것은 GitHub 하위 이슈로 연결함
- 라벨: `트레이드오프`(정답이 없어 선택 필요), `미확인`(실측·전문가 확인), `난이도-상/중/하`

| 이슈 | 내용 | 근거 장 | 종류 | 상위 이슈 |
|---|---|---|---|---|
| #22 | 스토어 조회가 실패할 때(결과 모름)의 지급 정책 | 3-1장, T1 | 트레이드오프, 난이도-상 | #10 |
| #23 | 시간 제한 값 정하기 (스토어 조회, 재시도, DB, 앱 대기) | 3-2장, T2 | 트레이드오프, 난이도-중 | 없음 |
| #24 | 만료 직후 갱신 결과가 안 온 틈에 권한을 유지할지 | 3-3장, T3 | 트레이드오프, 난이도-상 | #14 |
| #25 | 알림 수신 구조: 저장하고 바로 응답, 처리는 뒤에서 | 3-4장, T4 | 트레이드오프, 난이도-중 | #11 |
| #26 | 정기 대조 작업: 빠진 알림과 미확정 건을 스토어와 맞춤 | 3-5장, T5 | 트레이드오프, 난이도-중 | 없음 |
| #27 | 구글 확인(acknowledge·consume) 3일 규칙과 재시도 | 4-1장, T6 | 트레이드오프, 난이도-중 | #10 |
| #28 | 구글 거래 유일 키와 토큰 잇기(linkedPurchaseToken) | 4-3장 | 난이도-중 | #8 |
| #29 | 계정 연결 값이 없거나 다른 구매를 누구에게 줄지 | 5-1장, 5-2장, T10, T11 | 트레이드오프, 난이도-상 | #10 |
| #30 | 기기 계정으로 산 뒤 로그인하면 구매를 어디에 둘지 (2026-11-19 로그인 필수로 정리) | 5-3장, T12 | 트레이드오프, 난이도-상 | #6 |
| #31 | 운영 서버가 샌드박스 거래를 어디까지 받을지 (D15 재검토) | 6-1장, T13 | 트레이드오프, 난이도-상 | #15 |
| #32 | 환불 대응: 회수, 복원, 환불 요청 응답, 반복 환불 | 4-6장, T9 | 트레이드오프, 난이도-상 | #14 |
| #33 | 구독 변경(월↔연): 스토어 규칙과 출시 때 지원 범위 | 4-5장, T8 | 트레이드오프, 난이도-중 | #13 |
| #34 | 결제 실패 대응 설정: 유예, 보류, 일시중지 | 4-2장, 4-4장, T7 | 트레이드오프, 난이도-하 | #7 |
| #35 | "한 달"과 날짜 표시: 서버는 계산하지 않음 | 7-1장, T14 | 트레이드오프, 난이도-하 | #6 |
| #36 | 스토어에서 되돌릴 수 없는 설정 점검 | 4-7장, 5-4장 | 난이도-하 | #7 |
| #37 | 금액과 장부: 무엇을 어디까지 남길지 | 7-2장, 7-5장, T15 | 트레이드오프, 난이도-중 | #8 |
| #38 | 세무·신고 확인: 세무사에게 물을 것 | 7-3장, 7-4장 | 미확인, 난이도-중 | #7 |
| #39 | 관측과 알람: 무엇을 재고 언제 울릴지 | 3-8장, T16 | 트레이드오프, 난이도-하 | 없음 |
| #40 | 앱 쪽 누락 방지: 거래 끝내기, 재제출, 대기 화면 | 6-3장, 3-6장 | 난이도-중 | #13 |
| #41 | 실측으로 확인할 것 목록 (unknown) | 9장 | 미확인, 난이도-중 | #15 |
| #42 | 라이브러리와 스토어 API의 지원 종료 일정 | 4-8장 | 난이도-하 | 없음 |

## 11. 중국어권·국내 글에서 반복되는 교훈

1. 서버가 스토어에 직접 확인한 거래만 지급 근거
2. 최종 방어선은 거래 ID 유일 키. 락은 보조
3. 중복 요청에는 "이미 처리됨" 성공 응답
4. 지급 뒤에만 거래를 끝냄. 끝내지 않은 거래는 앱 시작 때 다시 제출
5. 알림, 앱 제출, 서버 정기 조회를 함께 씀
6. 정기 대조가 마지막 방어선. 발견까지 걸리는 시간이 손실을 좌우
7. 시간 초과는 실패가 아니라 미확정. 알림은 기록하고 바로 응답
8. 샌드박스는 받되 권한이 운영으로 새지 않게
9. 계정 연결 값이 비거나 틀릴 때의 경로를 미리 만듦
10. 외부 호출은 DB 트랜잭션 밖에서
11. 환불은 스토어가 처리. 앱 안에 환불 신청 경로를 안내
12. 구독 화면에 가격·기간·약관·복원 버튼. 해지 경로를 숨기지 않음

## 12. 읽은 글 (주요)

- 애플 공식
  - [구독 결제 처리](https://developer.apple.com/documentation/storekit/handling-subscriptions-billing)
  - [알림에 응답하기](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications)
  - [알림 이력 조회](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history)
  - [비자발적 이탈 줄이기](https://developer.apple.com/documentation/storekit/reducing-involuntary-subscriber-churn)
  - [환불 알림 처리](https://developer.apple.com/documentation/storekit/handling-refund-notifications)
  - [계정 연결 값 설정](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token)
  - [호출 한도](https://developer.apple.com/documentation/appstoreserverapi/identifying-rate-limits)
  - [구독 정보(갱신일 규칙)](https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information)
  - [구독 가격 관리](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/)
  - [샌드박스 계정 설정](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/)
  - [지급 정보](https://developer.apple.com/kr/help/app-store-connect/reference/reporting/payment-information/), [세금 문서](https://developer.apple.com/kr/help/app-store-connect/manage-tax-information/manage-invoices-and-other-tax-documents/)
- 구글 공식
  - [결제 통합](https://developer.android.com/google/play/billing/integrate), [보안](https://developer.android.com/google/play/billing/security)
  - [구독 수명 주기](https://developer.android.com/google/play/billing/lifecycle/subscriptions), [구독 변경](https://developer.android.com/google/play/billing/subscriptions)
  - [알림 참조](https://developer.android.com/google/play/billing/rtdn-reference), [가격 변경](https://developer.android.com/google/play/billing/price-changes)
  - [테스트](https://developer.android.com/google/play/billing/test), [지원 종료 일정](https://developer.android.com/google/play/billing/deprecation-faq)
  - [무효 구매](https://developers.google.com/android-publisher/voided-purchases), [한도](https://developers.google.com/android-publisher/quotas), [주문](https://developers.google.com/android-publisher/api-ref/rest/v3/orders)
  - [Pub/Sub 푸시](https://docs.cloud.google.com/pubsub/docs/push), [푸시 인증](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions)
  - [지급](https://support.google.com/googleplay/android-developer/answer/137997?hl=ko), [수익 보고서](https://support.google.com/googleplay/android-developer/answer/6135870?hl=ko)
- 대행사·기업 블로그
  - [RevenueCat 구글 상태 기계](https://www.revenuecat.com/guides/google-play-billing/the-subscription-state-machine), [구글 예외 사례](https://www.revenuecat.com/blog/engineering/google-play-edge-cases), [갱신 지연](https://www.revenuecat.com/docs/customers/google-play-renewal-extensions)
  - [토스페이먼츠 멱등성](https://www.tosspayments.com/blog/articles/dev-1), [포트원 웹훅](https://developers.portone.io/opi/ko/integration/webhook/readme-v2)
- 중국어권
  - [云音乐 IAP 实践总结](https://juejin.cn/post/7233948883045941303), [37手游 WWDC22 IAP](https://cloud.tencent.com/developer/article/2045275)
  - [苹果支付为什么容易丢单](https://www.cnblogs.com/ricklz/p/17993800), [内购的防范与优化](https://www.cnblogs.com/chglog/p/15347753.html), [服务端二次验证](https://www.cnblogs.com/xingxueliao/p/8493678.html)
  - [V2 接口 入门](https://juejin.cn/post/7381375087205728267), [防掉单 WWDC21](https://juejin.cn/post/6974733392260644895)
  - [闲鱼 资损防控](https://juejin.cn/post/7012456069586747422), [账务系统设计](https://juejin.cn/post/7409850315204542483), [支付超时 全链路方案](https://cloud.tencent.com/developer/article/2581350)
- 한국어
  - [구글 인앱결제 서버 구현 (velog)](https://velog.io/@puar12/Android-인앱결제-Server-구현-결제영수증-검증-포함-환불-처리), [Flutter + 서버 검증 (gee6809)](https://gee6809.github.io/posts/play_store_in_app_purchase)
  - [외부 호출과 트랜잭션 (dev-gallery)](https://dev-gallery.tistory.com/81), [인프런 결제 보정 질문](https://www.inflearn.com/community/questions/1707023), [인프런 트랜잭션 질문](https://www.inflearn.com/community/questions/1686639)
  - [앱 개발자 세금 (Taxwatch)](https://www.taxwatch.co.kr/article/tax/2022/05/16/0002), [인앱결제 세무 Q&A (taxly)](https://taxly.kr/qna/140313-인앱결제-관련-회계-세무-처리-문의), [구독 매출 인식 (브런치)](https://brunch.co.kr/@f9d461d3eab642e/99)
