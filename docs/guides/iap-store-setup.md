# 결제 세팅과 출시 점검

- 결제를 켜기까지 할 일을 한 문서에 모음: 먼저 정할 것, 콘솔에서 만들 것, 서버·앱 설정, 시험, 켜는 날. 정환이 직접 하거나 Claude Code에 넘길 때 쓴다
- 처음 보는 말은 [`iap-glossary.md`](iap-glossary.md). 결정의 이유는 ADR-0001~0003
- 화면 번호(결제 1~26)는 `docs/screenshots/2026-11-19-iap/`(앱 PR #45 브랜치)의 그림 번호
- **값은 여기에도, 저장소·이슈·PR에도 적지 않는다**(공개 저장소). 키·가격·사업자 정보는 콘솔과 KoDeploy 환경 변수에만 둔다
- 표시
  - [사람]: 계정 주인이 콘솔에 로그인해 직접 한다. 계약·은행·세금·키 발급은 대신할 수 없다
  - [Claude]: Claude Code가 저장소에서 할 수 있다
- 확인 날짜 2026-11-23. 콘솔 메뉴 이름은 자주 바뀐다. 이름이 다르면 비슷한 메뉴를 찾는다

## 0. 한눈에

| 순서 | 할 일 | 누가 | 걸리는 시간 |
|---|---|---|---|
| 1 | 사업자등록, 통신판매업 신고, 세무사 상담 | 사람 | 며칠~몇 주 |
| 2 | 애플 유료 앱 계약·은행·세금, 구글 결제 프로필 | 사람 | 계약 승인에 며칠 |
| 3 | 수수료 15% 신청(애플 소규모 사업자, 구글 계정 그룹) | 사람 | 몇 분 |
| 4 | 구글 서버용 서비스 계정 만들고 Play Console에 초대 | 사람 | 권한 반영에 하루 이상 걸릴 수 있어 **일찍** |
| 5 | 앱 PR #45 머지(결제는 플래그로 꺼진 채) → Play 비공개 테스트에 올라감 | Claude | 구글 상품을 만들려면 결제 라이브러리가 든 빌드가 먼저 있어야 함 |
| 6 | 상품 4개씩 만들기(구독 월·연, 선반 1칸·3칸) | 사람 | |
| 7 | 서버 알림 주소, 키 발급 | 사람 | |
| 8 | 서버 PR 머지 → KoDeploy 환경 변수 → 재배포 → DB 상품 줄 | 사람(KoDeploy) + Claude | |
| 9 | 샌드박스 시험 | 사람 + Claude | 6장 |
| 10 | 켜는 날: 심사 제출, 첫 주 점검 | 사람 + Claude | 9장 |
| 0 | KoDeploy 확인: 서버가 잠드는지, 한 대인지, 백업, Cloudflare | 사람 | 8장. 결과에 따라 다른 일이 바뀌니 먼저 |

- 정환이 Claude Code에 넘길 값: 7장 표
- 양쪽에 같은 이름을 쓴다: 상품 ID, 요금제 ID

## 0-1. 사이트별로 등록할 것

| 사이트 | 결제 때문에 등록할 것 | 장 |
|---|---|---|
| 애플 개발자 사이트 `developer.apple.com/account` | 새 약관이 뜨면 동의(안 하면 App Store Connect가 막힘). 앱 ID `app.covebook`에 In-App Purchase가 켜져 있는지 확인(기본으로 켜져 있음). **그 밖에는 없음** | 2-8 |
| App Store Connect `appstoreconnect.apple.com` | 유료 앱 계약·은행·세금, 구독 그룹과 상품 4개, 서버 알림 주소, 인앱결제 키, 샌드박스 테스터, 앱 개인정보, 심사 메모 | 2-1~2-8 |
| 애플 소규모 사업자 프로그램 페이지 | 수수료 15% 신청 | 2-2 |
| Play Console `play.google.com/console` | 결제 프로필, 계정 그룹(15%), 상품, 서비스 계정 초대, 실시간 알림 주제 이름, 라이선스 테스터, 데이터 보안 | 3-1~3-7 |
| Google Cloud 콘솔 `console.cloud.google.com` | API 2개 사용 설정, 서버용 서비스 계정과 JSON 키, Pub/Sub 주제·푸시 구독 | 3-5, 3-6 |
| KoDeploy | 환경 변수, 재배포, 서버 상태 확인 | 4, 7, 8 |

- 휴대폰 푸시 알림 등록은 **필요 없다**
  - 우리 앱은 서버가 휴대폰으로 보내는 원격 푸시를 쓰지 않는다. 그래서 애플 APNs 키·푸시 인증서, 구글 FCM(Firebase) 등록이 필요 없다
  - 연 구독 갱신 전 알림은 앱이 기기 안에 예약하는 로컬 알림이다(`flutter_local_notifications`). 아이폰은 앱이 권한을 묻고 안드로이드는 `POST_NOTIFICATIONS` 권한이 이미 매니페스트에 있다. 대략적 예약(`inexactAllowWhileIdle`)이라 Play에 신고할 정확한 알람 권한도 없다
- 이 문서의 "서버 알림·실시간 알림"은 **스토어가 우리 서버로 보내는 웹훅**이다. 휴대폰 푸시와 다르다(2-5, 3-6)
- 나중에 원격 푸시를 넣으면 그때 APNs 키(애플 개발자 사이트 → Keys)와 Firebase 프로젝트가 생긴다. 결제와는 따로 정한다

## 0-2. 먼저 정할 것

- [x] 추가 선반 범위: 연도 책장마다, 책장 6칸 중 3칸 무료, 1칸·3칸 묶음 (2026-11-19 정환, ADR-0002 D1)
- [x] 로그인 필수, 오프라인 계정 없음 (2026-11-19 정환, ADR-0002 D9)
- [x] 상품 종류: 구독 월·연은 자동 갱신 구독, 선반 1칸·3칸은 소모성 (2026-11-23 정환)
- [ ] 구독이 여는 것: 유료 벽지·선반 색 목록 (정환)
- [x] 정책 이슈: 샌드박스 #31, 월↔연 #33, 유예 #34 등 (2026-11-26 범수, ADR-0002 3장 끝 표). 아래 설정값에 반영
- [ ] 앱 시작 로그인, 기존 기기 계정 사용자 옮기기 (정환)
- [x] 책장 5칸 → 6칸 (main d161e16)
- [ ] 청약철회 제한을 적용할지, 적용하면 구매 화면(T1·T2) 문구 (약관 초안의 확인 필요 항목)
- [ ] 문의 처리 기한(약관 초안은 3영업일)
- [ ] 개인정보 국외 이전 해당 여부 (처리방침 초안의 확인 필요 항목)

## 1. 사업·세무·약관 [사람]

- 사업자등록
  - 개인사업자로 시작할 수 있다. 일반과세·간이과세 중 무엇으로 할지는 세무사에게 묻는다
  - 업종코드도 세무사와 정한다
- 통신판매업 신고
  - 스토어 결제에서 개발사가 신고 대상인지 자료가 엇갈린다. 우리는 대상으로 보고 준비한다(ADR-0003)
  - 구매안전서비스 이용확인증이 필요한지, 간이과세자 면제가 되는지 확인한다
- 세무사에게 물을 것 12개: `docs/reports/2026-11-19-iap-pitfalls.md` 7-4장
  - 특히 한국 소비자 결제의 부가세, 스토어 수수료 증빙, 연 구독 매출 시기
- 앱에 보일 사업자 정보(상호, 대표자, 주소, 전화, 전자우편, 사업자등록번호, 통신판매업 신고번호)
  - 법으로 앱에 보여야 한다(ADR-0003 L14, 결제 10 화면)
  - 저장소에 적지 않고 KoDeploy의 `IAP_SELLER_JSON`에 넣는다(7장)
- 약관과 처리방침: 결제를 켜기 30일 전
  - [ ] 약관 유료 조항 확정 (`docs/legal/terms-draft-2026-11-18.md`의 "유료 서비스 조항")
  - [ ] 바뀐 약관을 앱에 공지. 회원에게 불리할 수 있는 변경이라 시행 30일 전 (약관 제3조)
  - [ ] 처리방침 결제 부분 확정 (`docs/legal/privacy-draft-2026-11-16.md`의 "결제 부분"). 웹 전문 반영은 결제를 켜는 날
  - [ ] 통신판매업 신고, 사업자 정보 확정 (앱에 보일 값은 서버 환경 변수로)

## 2. 애플 (App Store Connect)

- 계정 역할
  - **Account Holder**만 할 수 있는 것: 계약 동의, 소규모 사업자 프로그램 신청
  - Admin 이상: 인앱결제 키 발급
- 번들 ID: `app.covebook`. Team ID와 앱은 `docs/release/ios-release.md`에 있다

### 2-1. 계약·은행·세금 [사람]

- App Store Connect → 비즈니스(Business) → **유료 앱 계약(Paid Apps Agreement)** 동의
  - 계약이 "활성"이 아니면 샌드박스에서도 상품이 안 불러와진다. 가장 먼저 한다
- 은행 계좌: 원화 계좌 가능. 은행의 SWIFT 코드가 필요하다
- 세금 양식: 미국 세금 양식(개인은 W-8BEN, 사업자는 W-8BEN-E)
- 한국 사업자등록번호 입력
  - 검증되면 애플 수수료 전자세금계산서가 매달 나온다
  - 세금 정보가 없으면 지급이 늦어진다

### 2-2. 수수료 15% [사람]

- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) 신청
  - Account Holder가 신청한다
  - 수수료 대상이 연 100만 달러 이하이면 30% 대신 15%
  - 신청하지 않으면 구독 첫해와 선반 구매가 30%다

### 2-3. 판매 나라 [사람]

- 한국 먼저 간다. 앱의 판매 나라(Pricing and Availability)를 정한다
- EU에 팔려면 디지털서비스법 **판매자(trader) 신고**가 필요하다. 신고하면 주소·전화가 EU 스토어에 공개된다
  - 신고 전까지는 판매 나라에서 EU를 뺀다

### 2-4. 상품 만들기 [사람]

- 상품 ID 제안. **한 번 만들면 바꿀 수 없고, 지운 ID는 다시 못 쓴다**. 구글과 같은 ID를 쓴다
- 상품 종류(구독 월·연 = 자동 갱신 구독, 선반 1칸·3칸 = 소모성)는 2026-11-23 정환 확인

| 상품 | 종류 | 상품 ID(제안) |
|---|---|---|
| plus 월간 | 자동 갱신 구독 | `app.covebook.plus.monthly` |
| plus 연간 | 자동 갱신 구독 | `app.covebook.plus.yearly` |
| 추가 선반 1칸 | 소모성(Consumable) | `app.covebook.shelf.1` |
| 추가 선반 3칸 묶음 | 소모성(Consumable) | `app.covebook.shelf.3` |

- 구독
  - 구독(Subscriptions) → 구독 그룹 하나(예: plus) → 그 안에 월간·연간
    - 월간과 연간은 **같은 등급(level)**으로 둔다. 기간이 다른 같은 등급끼리 바꾸면 다음 갱신일부터 바뀌어, 구글 설정과 같아진다(#33). 그룹과 등급은 나중에 바꾸기 어렵다
  - 결제 실패 유예(Billing Grace Period): 켠다. **28일**, 대상은 모든 구독자(#34). 서버는 유예를 이미 처리한다(`grace_until`)
  - 가족 공유(Family Sharing): **켜지 않는다**. 켜면 다시 끌 수 없다. 가족 구성원의 구매에는 계정 연결 값이 없어 누구 것인지 가리기 어렵다
  - 무료 체험·할인 제안: 만들지 않는다(ADR-0002 D14)
- 선반: 앱 내 구입(In-App Purchases) → 소모성 2개
- 상품마다 넣을 것
  - 표시 이름과 설명(한국어)
  - 가격: 한국 가격을 정하면 다른 나라는 애플이 자동으로 맞춘다. 가격은 저장소에 적지 않는다
  - 심사용 스크린샷: 결제 화면 그림. `docs/screenshots/2026-11-19-iap/`의 5·6번을 쓸 수 있다
  - 심사 메모: 결제 화면 가는 길
- 첫 인앱 상품은 **앱 새 버전과 함께 심사에 제출**한다. 상품만 따로 낼 수 없다

### 2-5. 서버 알림 [사람]

- 앱 정보(App Information) → App Store Server Notifications
  - 운영(Production) 주소: `https://covebook.kodeploy.com/iap/notifications/apple`
  - 샌드박스(Sandbox) 주소: 같은 주소
  - 버전: **Version 2**
- 저장한 다음 "테스트 알림 보내기"는 서버를 켠 뒤(8장) 한다

### 2-6. 키 [사람]

- 사용자 및 액세스(Users and Access) → 통합(Integrations) → **인앱 구입(In-App Purchase)** 키 → 만들기
- 받는 것 세 개 → 7장 표
  - `.p8` 파일: **한 번만 내려받을 수 있다**. 잃어버리면 새로 만든다
  - 키 ID
  - 발급자(Issuer) ID
- 로그인 키(Sign in with Apple), 앱 업로드 키(App Store Connect API)와 다른 키다. 섞지 않는다
- 앱 전용 공유 암호(App-Specific Shared Secret)는 필요 없다. 옛 영수증 검증 방식용이다

### 2-7. 샌드박스 테스터 [사람]

- 사용자 및 액세스 → 샌드박스(Sandbox) → 테스트 계정 만들기
  - 실제 Apple ID로 쓰지 않은 이메일을 쓴다
- 아이폰: 설정 → App Store → 샌드박스 계정에 로그인
- 샌드박스는 갱신이 빠르다(연 구독이 1시간마다). 6장 참고

### 2-8. 앱 정보와 심사 [사람 + Claude]

- 앱 개인정보(App Privacy): "구매 항목 › 구매 내역" 추가 [사람]
- 이용약관 링크 (심사 지침 3.1.2: 구독 앱은 앱 안과 스토어 설명 둘 다에 약관·처리방침 링크가 있어야 함)
  - 앱 안: 요금제 화면(결제 6)에 둘 다 있음
  - 스토어 설명: 처리방침은 `https://covebook.kodeploy.com/privacy`. **약관 웹 주소는 아직 없다**
  - 할 일 [Claude]: 서버에 `/terms` 페이지를 만든다(`server/internal/server/site/`, 처리방침과 같은 방식). 아니면 애플 표준 약관(EULA)을 쓴다
- 심사 메모 [사람]: 로그인이 필수라 심사용 계정이 필요하다. 소셜 로그인만 있어 방법을 정해야 한다
  - 로그인 강제는 반려 사례가 있다(ADR-0002 부록 A). 심사 메모에 "기록 동기화 때문에 계정이 필요하다"는 이유를 적는다
- 애플 개발자 사이트 [사람]
  - Certificates, Identifiers & Profiles → Identifiers → `app.covebook` → In-App Purchase가 켜져 있는지 본다. 기본으로 켜져 있어 프로파일을 새로 받을 필요는 보통 없다
  - 첫 TestFlight 빌드에서 상품이 불러와지는지 보고 최종 확인
  - Push Notifications는 켜지 않아도 된다(0-1)

## 3. 구글 (Play Console + Google Cloud)

- 패키지 이름: `app.covebook`. Play Console의 앱과 지금 배포용 서비스 계정은 `docs/release/android-release.md`에 있다

### 3-1. 결제 프로필 [사람]

- Play Console → 설정 → **결제 프로필(Payments profile)**: 판매자 정보, 은행 계좌, 세금 정보
- 한국 사업자등록번호 입력
  - 넣지 않으면 수수료에 부가세 10%가 따로 붙는다는 보고가 있다(커뮤니티)

### 3-2. 수수료 15% [사람]

- Play Console → 설정 → 계정 그룹 만들기 → [15% 수수료 등급](https://support.google.com/googleplay/android-developer/answer/10632485) 신청
  - 결제 프로필이 먼저 있어야 한다
  - 7월 1일 뒤에 신청하면 신청한 날부터 15%다
- 자동 갱신 구독은 처음부터 15%다

### 3-3. 빌드 먼저 [Claude]

- 구글은 결제 라이브러리가 든 빌드가 테스트 트랙에 있어야 상품을 만들 수 있다
  - 지금 main 빌드에는 결제 라이브러리가 없다. 앱 PR #45에 있다
- 순서
  1. PR #45를 main에 머지한다. 결제 화면은 `--dart-define=IAP=true`가 없으면 꺼져 있어 사용자에게 보이지 않는다
  2. main push로 Play 비공개 테스트(alpha)에 자동으로 올라간다(`.github/workflows/android-flutter-play.yml`). 결과를 확인한다
  3. 그 뒤 3-4를 한다

### 3-4. 상품 만들기 [사람]

- 상품 ID는 애플과 같게(2-4 표)
- 구독: 수익 창출(Monetize with Play) → 제품 → 구독
  - 구독 상품 **하나**(`app.covebook.plus`)에 기본 요금제(base plan) 둘
    - 월간: 요금제 ID `monthly`, 자동 갱신, 1개월
    - 연간: 요금제 ID `yearly`, 자동 갱신, 1년
  - 요금제 ID는 서버 `iap_plans` 테이블에 그대로 넣는다(4장)
  - 유예 기간 **30일**, 계정 보류 **30일**(둘을 합쳐 60일). 일시중지(pause)는 끈다(#34)
  - 요금제 변경 청구: 앱에 변경 화면이 없어 앱이 고르는 교체 방식은 없다. 콘솔에 기본값 설정이 보이면 **다음 결제일에 청구**로 둔다(#33)
  - 제안(무료 체험, 할인): 만들지 않는다
- 선반: 수익 창출 → 제품 → **일회성 상품**
  - `app.covebook.shelf.1`, `app.covebook.shelf.3`
  - 여러 번 사는 상품이다. 서버가 구매 뒤 소비(consume)한다(`iap_products.consume`)
  - **수량 구매(multi-quantity)는 켜지 않는다**(기본 꺼짐). 서버는 1개 값만 칸으로 바꾸므로 2개 이상 산 구매는 받지 않고 소비하지 않는다(구글이 3일 뒤 환불)
- 가격은 저장소에 적지 않는다

### 3-5. 서버용 서비스 계정 [사람]

- **배포용(`covebook-play-deploy`)과 따로 만든다**. 배포용은 테스트 출시 권한만 있고 서버용은 주문 권한만 갖게 나눈다
- Google Cloud 콘솔
  1. 프로젝트에서 **Google Play Android Developer API** 사용 설정
  2. IAM → 서비스 계정 만들기(예: `covebook-iap-server`)
  3. 키 → JSON 키 만들기 → 내려받음 → 7장 표
- Play Console → 사용자 및 권한 → 위 서비스 계정 이메일 초대
  - 앱 `app.covebook`에만
  - 권한: **재무 데이터 보기**, **주문 및 구독 관리**
- 권한이 서버에 반영되는 데 하루 이상 걸릴 수 있다. 그동안 서버는 권한 오류를 낸다. **가장 먼저 만들어 둔다**

### 3-6. 실시간 알림(RTDN) [사람]

- Google Cloud 콘솔
  1. **Cloud Pub/Sub API** 사용 설정
  2. Pub/Sub → 주제 만들기(예: `play-rtdn`)
  3. 그 주제 → 권한 → 주 구성원 추가: `google-play-developer-notifications@system.gserviceaccount.com`, 역할 **Pub/Sub 게시자**
     - 구글 Play가 이 계정으로 알림을 넣는다([공식](https://developer.android.com/google/play/billing/getting-ready))
  4. 그 주제에 구독 만들기
     - 전송 유형: **푸시**
     - 엔드포인트: `https://covebook.kodeploy.com/iap/notifications/google`
     - **인증 사용**: 서비스 계정 하나를 고른다(3-5의 계정이어도 됨). 이 이메일이 `IAP_GOOGLE_PUSH_EMAIL`
     - 대상(audience): 엔드포인트 주소를 그대로 적는다. 이 값이 `IAP_GOOGLE_PUSH_AUDIENCE`
     - 오래된 프로젝트는 Pub/Sub 서비스 에이전트에 "서비스 계정 토큰 생성자" 역할이 필요할 수 있다. 저장할 때 화면이 알려 준다
- 위 1~4는 명령으로도 된다. 정환이 `gcloud auth login`으로 로그인하면 Claude Code가 돌릴 수 있다 [Claude]
  - 3-5의 서비스 계정 만들기도 함께 한다. **JSON 키 만들기는 빼 두었다.** 키 파일이 Claude 작업 폴더에 남지 않게 정환이 콘솔에서 만들어 KoDeploy에 바로 넣는다
  - Play Console 초대(3-5)와 아래 Play Console 칸은 명령으로 못 한다

```sh
PROJECT=<프로젝트 ID>           # Google Cloud 프로젝트 ID
URL=https://covebook.kodeploy.com/iap/notifications/google
SA=covebook-iap-server@$PROJECT.iam.gserviceaccount.com
gcloud config set project "$PROJECT"
gcloud services enable pubsub.googleapis.com androidpublisher.googleapis.com
gcloud iam service-accounts create covebook-iap-server --display-name="covebook IAP server"
gcloud pubsub topics create play-rtdn
gcloud pubsub topics add-iam-policy-binding play-rtdn \
  --member=serviceAccount:google-play-developer-notifications@system.gserviceaccount.com \
  --role=roles/pubsub.publisher
gcloud pubsub subscriptions create play-rtdn-push --topic=play-rtdn \
  --push-endpoint="$URL" --push-auth-service-account="$SA" --push-auth-token-audience="$URL"
# 확인: 구독의 엔드포인트·인증 값
gcloud pubsub subscriptions describe play-rtdn-push --format='value(pushConfig)'
```

  - 이렇게 하면 `IAP_GOOGLE_PUSH_AUDIENCE`는 `$URL`, `IAP_GOOGLE_PUSH_EMAIL`은 `$SA`다
- Play Console → 수익 창출 설정 → **실시간 개발자 알림**
  - 주제 이름: `projects/<프로젝트 ID>/topics/play-rtdn`
  - 알림 종류를 고르는 칸이 있으면 구독, 일회성 상품, 무효 구매를 모두 고른다
  - "테스트 알림 보내기"는 서버를 켠 뒤(8장). 서버 로그에서 받은 것을 확인한다
- 서버는 두 값(`AUDIENCE`, `EMAIL`)이 없으면 구글 알림 주소를 열지 않는다

### 3-7. 테스터와 앱 정보 [사람]

- Play Console → 설정 → **라이선스 테스트**: 시험할 구글 계정 이메일
  - 그 계정을 비공개 테스트 트랙 테스터에도 넣고 Play 스토어에서 설치해야 한다
- 앱 콘텐츠 → 데이터 보안: "금융 정보 › 구매 기록" 추가

## 4. 서버 [Claude + 사람]

- PR 머지 [Claude, 사람이 머지를 요청한 뒤]
  - 순서: #21 → #43·#44 → #46 → #47 → #48
  - 머지 직전 마이그레이션 번호(V21~V23)를 main과 맞춘다
- KoDeploy 환경 변수 [사람]: 7장 표의 값을 넣는다
- KoDeploy 재배포 [사람]. push만으로는 반영되지 않는다
- 확인 [Claude]: `/healthz`의 `iap`가 true
- [ ] 보관 기간이 지난 결제 기록 삭제 작업 (아직 없음. 처리방침 초안의 5년·3년). 탈퇴한 계정의 결제 고지도 `user_id`가 NULL인 채 남는다(#47)
- [ ] `GET /admin/iap/stats`로 숫자가 나오는지
- [ ] 선반 숫자: `shelfOverCap`(3칸을 넘은 거래), `shelfOverCapRefunded`(구글 자동 환불 요청), `shelfOverCapApple`(애플, 사용자 환불 요청 안내), `shelfNoYear`(연도를 모르는 거래). 0이 아니면 거래를 확인
- DB 상품 줄 [Claude, 운영 DB 접속은 사람이 연다]

```sql
-- 상품이 주는 것. 가격은 넣지 않는다
INSERT INTO iap_products(route, product_id, kind, entitlement, shelves, consume) VALUES
  ('apple',  'app.covebook.plus.monthly', 'subscription', 'plus', NULL, false),
  ('apple',  'app.covebook.plus.yearly',  'subscription', 'plus', NULL, false),
  ('apple',  'app.covebook.shelf.1', 'product', NULL, 1, true),
  ('apple',  'app.covebook.shelf.3', 'product', NULL, 3, true),
  ('google', 'app.covebook.plus',    'subscription', 'plus', NULL, false),
  ('google', 'app.covebook.shelf.1', 'product', NULL, 1, true),
  ('google', 'app.covebook.shelf.3', 'product', NULL, 3, true);
-- 구독 주기(#48). 애플은 상품 ID가 곧 요금제라 plan_id가 빈 값
INSERT INTO iap_plans(route, product_id, plan_id, period) VALUES
  ('apple',  'app.covebook.plus.monthly', '', 'month'),
  ('apple',  'app.covebook.plus.yearly',  '', 'year'),
  ('google', 'app.covebook.plus', 'monthly', 'month'),
  ('google', 'app.covebook.plus', 'yearly',  'year');
```

- 위 칸 이름은 PR 브랜치 기준이다. 넣기 전에 머지된 마이그레이션과 맞춘다
- 상품 ID를 제안과 다르게 만들었으면 실제 ID로 바꿔 넣는다
- `iap_plans` 줄이 없으면 서버가 주기를 몰라 연 구독 갱신 예정 고지와 앱의 갱신 전 알림이 나가지 않는다
- 할 일 [Claude]: 웹 약관 페이지 `/terms`(2-8)

## 5. 앱 [Claude]

- PR #45 머지는 3-3에서 이미 함
- 상품 ID는 앱에 적혀 있지 않다. 앱이 서버(`/iap/me`)에서 받으므로 4장 DB 줄만 맞으면 앱은 고칠 것이 없다
- 심사 제출 빌드와 TestFlight·Play 워크플로에는 켜는 날 `--dart-define=IAP=true`를 넣는다(9장)

## 6. 시험

- 먼저 볼 것
  - 애플: 상품이 불러와지는지(안 되면 유료 앱 계약, 상품 상태, 번들 ID를 의심)
  - 구글: 서비스 계정 권한 오류가 사라졌는지, 테스트 알림이 서버에 오는지
- 앱: `--dart-define=IAP=true` 빌드, 서버: `IAP_ALLOW_SANDBOX=1`
- 각 줄에서 화면과 서버 둘 다 확인. 서버는 `iap sweep:` 로그와 `/admin/iap/stats`

| 할 일 | 떠야 하는 화면 | 서버에서 볼 것 |
|---|---|---|
| 요금제 화면 열기 | 결제 6 (미리 고른 것 없음) | |
| 월간 고르고 구독 | 결제 7 → 결제 12 결제 완료 | 거래 줄, 구독 줄, `purchase_done` 고지 |
| (첫 구매 직후) 계정 연결 값 확인 | | 거래 줄의 `account_token`이 **비어 있지 않은지**. 애플은 UUID 모양이 아닌 값을 오류 없이 버린다. Flutter에서 비어 오는 사례가 보고됨(2026-11-26 조사) |
| 결제 대기(구글 느린 카드) | 결제 17 | 대기 뒤 지급 |
| 구독 관리 | 결제 1 | |
| 스토어에서 해지 | 결제 2, 알림함에 해지 접수 | `auto_renew=false`, `cancel_scheduled` 고지 |
| 결제 실패(샌드박스 갱신 실패) | 결제 3, 앱 열 때 결제 13 창 | `grace_until`, `payment_failed` 고지 |
| 만료 | 앱 열 때 결제 14 창 | `state=inactive`, `expired` 고지 |
| 연간 구독 결제 직후 | 결제 12 뒤 알림 권한을 한 번 묻는다(거절해도 알림함에 남음) | `/iap/me`의 `subscription.period=year` |
| 연간 구독, 갱신 14일 전 | 기기 예약 알림(오전 10시), 알림함 갱신 예정 | `renewal_upcoming` 고지. 애플 샌드박스는 연 구독이 1시간마다 갱신돼 고지가 하루 최대 4줄 쌓일 수 있다 |
| 구독 환불 | 앱 열 때 결제 15 창 | `state=revoked`, `subscription_refunded` 고지 |
| 추가 선반 1칸 구매 | 결제 5 → 그 해 책장만 칸이 늘고 시트 닫힘 | 거래 줄과 연도, 확인(acknowledge·consume) 시각 |
| 2026년 1칸을 산 뒤 바로 2027년 책장에서 1칸 | 2027년 책장에 열림 | 두 거래의 `shelf_year`가 2026, 2027. 로그 `iap shelf year from reservation`이 나오면 애플이 앞의 계정 연결 값을 돌려준 것이고 예약 연도로 바로잡은 것(포럼 보고, erd.md 3.7) |
| 추가 선반 3칸 묶음 | 산 칸이 없는 해에만 보임, 결제 18 | 칸 수 3, 다른 해 책장은 그대로 |
| 지난해 책장으로 넘겨 보기 | 지난해 책장의 칸 수는 그 해에 산 만큼 | |
| 한 기기에서 선반 결제창을 띄운 채 다른 기기에서 같은 해 선반 구매 | 뒤 기기는 "다른 기기에서 결제하고 있어요" | 예약 줄, 409 `iap_shelf_busy` |
| 결제창을 취소 | 다른 기기에서 바로 살 수 있음 | 예약이 풀림 |
| 예약이 끝난 뒤 늦게 결제돼 3칸 초과 | 3칸까지만 열림, 결제 26 창 | 구글은 자동 환불 요청 시각, 애플은 `shelf_over_cap` 고지(autoRefund=false) |
| 선반 결제 직후 앱을 강제 종료하고 다시 켬(안드로이드) | 칸이 열림 | 앱이 켜질 때 다시 낸 제출과 확인 시각. 안 열리면 3일 뒤 구글이 환불하니 꼭 볼 것 |
| 계정 A로 선반 결제 직후 앱을 끄고 계정 B로 로그인해 켬 | B에는 "결제한 다른 계정에 선반을 넣었어요", A로 돌아가면 칸이 있음 | 거래 줄의 `user_id`가 A, 로그 `iap shelf for other account` |
| 추가 선반 환불 | 앱 열 때 결제 16 창, 그 칸의 책이 내 책으로, 칸이 잠긴 모양 | `shelf_refunded` 고지 |
| 구매 복원(다른 회원 계정) | 구독이 새 계정으로 옮겨짐 | 구독 줄 `user_id` 변경 |
| 다른 기기 같은 계정 | 같은 상태, 알림 창은 한 기기에서만 한 번 | |
| 구매 내역 | 결제 9 | `GET /iap/purchases` |
| 사업자 정보 | 결제 10 | `IAP_SELLER_JSON` |
| 구독 중 회원탈퇴 | 결제 11 안내 → 탈퇴 | 결제 기록 줄이 남고 `user_id`가 NULL |
| 알림함 | 결제 23 점 → 결제 24 → 결제 21 | 읽음 처리 뒤 `unreadNotices=0` |
| 서버를 잠시 끄고 구매 | 앱이 나중에 다시 보내 지급 | 끝내지 않은 거래가 다음 실행에 다시 옴 |

## 7. Claude Code에 넘길 값 (저장소에 적지 말 것)

- 정환이 콘솔에서 받아 **KoDeploy 환경 변수에 직접** 넣는다. 채팅·저장소·이슈에 붙여 넣지 않는다

| 환경 변수 | 어디서 | 2·3장 |
|---|---|---|
| `IAP_APPLE_KEY_P8` | 인앱 구입 키 `.p8` 파일 내용 (여러 줄이 안 되면 base64) | 2-6 |
| `IAP_APPLE_KEY_ID` | 같은 키의 키 ID | 2-6 |
| `IAP_APPLE_ISSUER_ID` | 같은 화면의 발급자 ID | 2-6 |
| `IAP_APPLE_BUNDLE_ID` | `app.covebook` | |
| `IAP_GOOGLE_KEY_JSON` | 서버용 서비스 계정 JSON 키 내용 | 3-5 |
| `IAP_GOOGLE_PACKAGE` | `app.covebook` | |
| `IAP_GOOGLE_PUSH_AUDIENCE` | 푸시 구독의 대상 값 | 3-6 |
| `IAP_GOOGLE_PUSH_EMAIL` | 푸시 구독 인증에 고른 서비스 계정 이메일 | 3-6 |
| `IAP_SELLER_JSON` | 사업자 정보 JSON(`name`, `owner`, `address`, `phone`, `email`, `bizNo`, `saleNo`) | 1 |
| `IAP_ENABLED` | `1` | |
| `IAP_ALLOW_SANDBOX` | `1` (계속 켜 둔다. 앱을 고칠 때마다 심사·TestFlight 결제가 샌드박스로 온다. #31 결정) | |
| `IAP_RENEWAL_NOTICE_DAYS` | 연 구독 갱신 예정 고지를 며칠 전에. 비우면 14 | |
| `ADMIN_TOKEN` | 운영 숫자 조회용(`GET /admin/iap/stats`). 운영에 아직 없다(2026-11-23 확인). 긴 무작위 값을 새로 만들어 넣는다(`openssl rand -hex 32`) | |

- 애플 키 넷은 다 넣거나 다 비운다. 구글은 `AUDIENCE`·`EMAIL`이 없으면 구글 알림 주소가 닫힌다
- `IAP_ALLOW_SANDBOX`를 끄면 전에 준 샌드박스 권한도 사라진다

- Claude Code에 알려 줄 것은 값이 아니라 "넣었다"와 실제로 만든 상품 ID·요금제 ID뿐이다

## 8. 서버 호스팅(KoDeploy) 확인

- 우리 서버는 KoDeploy에 있고(`https://covebook.kodeploy.com`) 앞에 Cloudflare가 있다. 애플·구글 알림은 이 주소로 오는 웹훅이다
- 2026-11-23에 밖에서 확인한 것

| 확인할 것 | 결과 | 왜 중요한가 |
|---|---|---|
| HTTPS, TLS 1.2 이상 | 통과. TLS 1.2·1.3 되고 1.1은 거절. Let's Encrypt 인증서(2027-01-20까지, 자동 갱신으로 보임) | 애플 알림 주소의 조건 |
| 응답 속도 | `/healthz` 0.36초 | 알림에 몇 초 안에 답해야 함 |
| 브라우저가 아닌 POST | **일부 막힘.** 프로그램 이름(User-Agent)이 `Java/1.7`·`Java/1.8`이면 Cloudflare가 403(오류 1010)으로 막음. `Java/17`, `Go-http-client`, `curl`, 구글 이름 등은 서버까지 닿음 | 애플·구글이 어떤 이름으로 보내는지는 확인 안 됨. 막히면 알림이 하나도 안 옴 |
| 서버가 잠드는가 | 밖에서 알 수 없음. **KoDeploy에서 확인** [사람] | 정기 대조(1분마다)가 서버 안에서 돈다. 잠들면 알림 처리, 구글 3일 확인 기한, 갱신 고지가 멈춤 |
| 서버가 한 대인가 | 밖에서 알 수 없음. KoDeploy에서 확인 [사람] | 제출 횟수 제한(1분 30번)이 서버 메모리 기준. 여러 대면 느슨해짐. 정기 대조는 DB 잠금으로 한 곳만 돌아 괜찮음 |
| DB 백업 | KoDeploy에서 확인 [사람] | 결제 기록 5년 보관 |
| Cloudflare 설정을 누가 바꿀 수 있나 | `kodeploy.com`은 KoDeploy 쪽 도메인으로 보임. 우리가 못 바꿀 수 있음 [사람] | 아래 "막히면" |

- 알림이 막히는지 보는 법 (서버 PR 머지와 키 설정 뒤)
  - 애플: App Store Connect의 테스트 알림, 또는 App Store Server API의 "테스트 알림 요청"
  - 구글: Play Console의 "테스트 알림 보내기"
  - 서버 로그에 받은 기록이 없고 스토어 쪽에 실패가 남으면 Cloudflare를 의심한다
- 막히면
  - Cloudflare에서 `/iap/notifications/*` 경로를 보안 검사(브라우저 무결성 검사, 봇 차단)에서 빼는 규칙을 만든다. Cloudflare를 가진 쪽(KoDeploy 운영자)에게 부탁해야 할 수 있다
  - 그게 안 되면 우리가 가진 도메인을 KoDeploy 서버에 연결해 알림 주소로 쓴다. 알림 주소는 콘솔에서 언제든 바꿀 수 있다

## 9. 켜는 날

- [ ] 처리방침 웹 전문 반영 (서버 재배포)
- [ ] 앱 `IAP=true`로 빌드하는 설정을 CI에 반영 (TestFlight·Play 워크플로)
- [ ] 심사 제출. `IAP_ALLOW_SANDBOX=1`은 심사가 끝나도 그대로 둔다(#31)
- [ ] 첫 주는 매일 `/admin/iap/stats`: 대기·실패 알림, 확인 못 한 구매(`oldestUnconfirmedSeconds`가 86400을 넘으면 본다. 구글은 3일에 환불), 샌드박스 거래 수

## 출처

- 애플: [Small Business Program](https://developer.apple.com/app-store/small-business-program/), [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications), [In-App Purchase 키](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests)
- 구글: [결제 준비(Getting ready)](https://developer.android.com/google/play/billing/getting-ready), [15% 수수료와 계정 그룹](https://support.google.com/googleplay/android-developer/answer/10632485), [일회성 상품 만들기](https://support.google.com/googleplay/android-developer/answer/1153481), [실시간 개발자 알림](https://developer.android.com/google/play/billing/realtime_developer_notifications)
- 세무·사업자: `docs/reports/2026-11-19-iap-pitfalls.md` 7장, ADR-0003
