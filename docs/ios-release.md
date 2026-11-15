# Apple 로그인 · TestFlight 내부 테스트

이 구성은 앱스토어 공개 심사나 외부 테스트를 제출하지 않는다. `main` 변경 → 서명 빌드 → App Store Connect의 TestFlight 업로드까지 자동화한다. App Store Connect에서 **내부 그룹**을 만들고 자동 배포를 켜면 초대한 내부 사용자만 설치할 수 있다. 공개 링크는 만들지 않는다.

## 현재 연결 상태

2026-11-14 Apple Developer 활성화와 Team ID `8R7ZQBT9G2`를 확인했다. 앱 ID의 Sign in with Apple, Services ID `app.covebook.signin`, 아래 도메인·Return URL 등록을 완료했다. 2026-11-15 App Store Connect에 책장 한켠(Apple ID `6835054912`)을 생성하고 자동 배포를 켠 Internal 테스트 그룹을 등록했다. 2026-11-15 로그인 키를 발급하고 KoDeploy Covebook 앱에 Apple 환경변수 5개를 저장한 뒤 서버 재배포를 완료했다. 운영 `/auth/providers`에서 `apple: true`를 확인했다. KoDeploy 소스 주소도 `covebook/covebook`으로 갱신했다. App Store Connect API 접근권한 승인을 받았고 Developer 역할 업로드 키와 배포 인증서·프로파일을 발급해 GitHub Secrets 6개를 저장했다. 첫 서명 빌드와 업로드가 성공했고, TestFlight 내부 그룹에서 `0.1.0 (1794741859)`의 `Testing` 상태를 확인했다. 내부 테스터는 소유자 본인 1명이며 `IOS_RELEASE=true`로 자동 업로드를 활성화했다. 첫 성공 실행: https://github.com/covebook/covebook/actions/runs/43708736750 . 실기기 로그인 확인은 남아 있다. 코드·설정 테스트와 실기기/Apple 실연동 검증은 별개다.

## Apple 로그인

앱의 시스템 인증 브라우저에서 Apple을 열고, 서버의 HTTPS 콜백이 `form_post` 응답을 받는다. 서버는 일회용 state·nonce와 Apple 공개키로 서명·issuer·audience·만료를 검증한다. 비공개 이메일도 지원하며, 이메일이 같다는 이유로 기존 계정을 자동 합치지 않는다.

Apple Developer에서 앱 ID에 **Sign in with Apple**을 켜고, 앱과 연결된 **Services ID**를 만든다. 아래 서버 도메인과 Return URL을 등록한다. `APPLE_CLIENT_ID`에는 앱 Bundle ID가 아닌 **Services ID**를 넣는다. Apple 로그인용 키와 App Store Connect 업로드용 키는 서로 다른 키다.

서버 환경 변수(앱·GitHub 소스에 넣지 않음):

| 변수 | 값 |
|---|---|
| `APPLE_CLIENT_ID` | `app.covebook.signin` |
| `APPLE_TEAM_ID` | `8R7ZQBT9G2` |
| `APPLE_KEY_ID` | Sign in with Apple 키 ID |
| `APPLE_PRIVATE_KEY` | 해당 `.p8` PEM 본문. 실제 줄바꿈 또는 `\n` 허용 |
| `APPLE_TOKEN_ENCRYPTION_KEY` | 무작위 32바이트의 Base64 (`openssl rand -base64 32`) |

갱신 토큰은 AES-256-GCM으로 암호화해 DB에 보관하고 앱에 주지 않는다. 암호화 키는 백업에 포함하되 코드·로그에 남기지 않는다. 기존 토큰을 다시 암호화하지 않고 키만 교체하면 탈퇴 시 토큰을 복호화할 수 없으므로 키를 보존해야 한다.

회원 탈퇴는 기존 삭제 저널로 세션을 차단한 뒤 Apple `/auth/revoke`를 호출하고 데이터를 지운다. Apple 오류가 나면 기존 삭제 작업자가 재시도한다. 키가 빠졌거나 잘못된 설정이면 `/auth/providers`의 Apple 기능은 꺼지고 버튼도 숨겨진다.

## 배포 순서

1. Apple Developer 활성화 확인 → 앱 ID/Services ID/Apple 로그인 키 등록.
2. 서버 변수 설정 → DB 마이그레이션과 서버 재배포. GitHub push만으로 서버가 자동 재배포되는 것은 아니다.
3. App Store Connect 앱 생성 → 내부 TestFlight 그룹/사용자와 수출 규정 정보 설정.
4. 아래 서명·업로드 값을 GitHub Actions secrets/variables에 저장. 비밀 키를 이슈·코멘트·문서에 붙이지 않는다.
5. Actions의 `iOS: private TestFlight`를 `main`에서 수동 실행해 첫 빌드/업로드를 확인.
6. 실제 기기에서 Apple 로그인(이메일 공유/가리기), 재로그인, 취소, 계정 삭제와 기존 로그인 회귀 확인.
7. 저장소 변수 `IOS_RELEASE=true`를 설정하면 이후 앱 변경을 자동 업로드한다. 끄려면 `false`로 변경한다.

업로드 성공 후에도 Apple의 처리/수출 규정 확인에 따라 TestFlight 설치까지 시간이 걸릴 수 있다. 코드 서명·Apple 로그인 실연동·실제 업로드는 계정과 자격 증명이 준비된 뒤 검증해야 한다.

## Covebook 설정

- iOS 앱: **`flutter/`**, Bundle ID **`app.covebook`**. 기존 `app/` React Native/Android 배포 파이프라인과 분리되어 있다.
- 서버 도메인: `covebook.kodeploy.com`
- Return URL: **`https://covebook.kodeploy.com/auth/apple/callback`**
- 앱 복귀: `chaekjang://auth/apple`; 기기 계정에 묶인 일회용 claim 티켓을 사용한다.
- `V18__apple_login.sql` 마이그레이션이 Apple 로그인 상태·티켓·암호화 갱신 토큰을 추가한다.
- Flutter 3.47.6 / Dart 3.13.5, macOS 26 runner와 Xcode 26.6, Fastlane으로 빌드한다. 참조 fixture의 날짜 기준에 맞춰 테스트 단계는 `TZ=Asia/Seoul`에서 실행한다.

| GitHub 변수 | 용도 |
|---|---|
| `APPLE_TEAM_ID` | Apple Team ID |
| `IOS_RELEASE` | 첫 수동 성공 후 `true` |

| GitHub secret | 용도 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API 키 ID |
| `ASC_ISSUER_ID` | API 키 발급자 UUID |
| `ASC_PRIVATE_KEY` | 업로드용 `.p8` PEM 본문 |
| `IOS_DISTRIBUTION_P12` | 개인 키를 포함한 Apple Distribution 인증서 `.p12`의 Base64 |
| `IOS_DISTRIBUTION_PASSWORD` | `.p12` 내보내기 비밀번호 |
| `IOS_PROVISION_PROFILE` | `app.covebook` App Store 프로파일 `.mobileprovision`의 Base64 |

Apple 로그인 capability를 켠 **App Store 배포 프로파일**이 필요하다. Development/Ad Hoc/다른 앱의 프로파일은 preflight에서 거절한다. `.p12`의 인증서와 프로파일의 인증서가 일치해야 한다. CI는 임시 keychain에 인증서를 설치하고 실행 후 삭제한다. 빌드 파일을 공개 GitHub Release에 올리지 않는다. 앱은 `SYNC_URL=https://covebook.kodeploy.com`으로 빌드한다.

TestFlight 업로드만 수행하고 외부 배포와 공개 앱 심사는 제출하지 않는다. 내부 그룹에서 자동 배포를 켜야 테스트 사용자에게 새 빌드가 보인다.

## 구현 검증 (2026-11-14)

Flutter 정적 분석과 테스트 642개 통과. 두 서버 모두 임시 PostgreSQL 16에서 전체 Go 테스트 통과. Apple state/최종 코드 재사용 거절, 잘못된 서명·audience·nonce·만료 거절, 계정 매핑·탈퇴 시 토큰 철회를 모의 Apple 응답으로 확인했다. GitHub workflow는 actionlint 검사를 통과했다. 2026-11-15 GitHub macOS runner에서 정적 분석·전체 Flutter 테스트, 실제 Apple 서명 빌드·TestFlight 업로드·Apple 빌드 처리까지 통과했다. 실제 기기에서 로그인·로그인 취소·이메일 가리기·회원 탈퇴를 확인하는 단계는 남아 있다.
