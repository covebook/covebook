# 작업 규칙 (사람·AI 에이전트 공통)

## Git: 무조건 main (결제의 일부 변경만 예외)
- 브랜치를 따로 만들지 않는다. 실험·점검도 main에서 한다(`git checkout -b`, `git worktree add`로 다른 브랜치 만들기 금지).
- 단계가 끝날 때마다(코드나 문서가 바뀐 단계) 그 단계에서 바꾼 파일만 골라 main에 커밋하고 바로 push한다.
- 다른 사람이 먼저 push했으면 `git pull --rebase origin main`으로 받아 합친 뒤 push한다. 강제 push 금지.
- 같은 작업 폴더를 여러 세션이 함께 쓸 수 있다. `git add -A`·`git add .` 대신 내가 바꾼 파일만 add한다. 남의 미커밋 변경은 건드리지 않는다.
- 커밋 메시지는 짧은 한국어로 쓴다. `Co-Authored-By` 같은 AI 흔적은 넣지 않는다.
- 커밋하지 않는 것: `server/.env`, `server/.gradle`·`server/bin`·`server/build`·`server/data`.
- 앱은 Flutter(`app/`)다. main push에 `app/**` 변경이 있으면 iOS TestFlight CI(`.github/workflows/ios-testflight.yml`)가 돈다. 결과를 확인한다.
- main push에 `app/**` 변경이 있으면 안드로이드 Play 배포(`.github/workflows/android-flutter-play.yml`)도 자동으로 돌아 비공개 테스트(alpha)에 올라간다. 결과를 확인한다. 버전 이름은 `app/pubspec.yaml`의 `version`.
- 서버(`server/**`) 변경은 push만으로 운영에 반영되지 않는다. KoDeploy에서 재배포해야 한다.

## 화면 디자인
- 사용자에게 보이는 화면이나 동작을 추가·수정하기 전에 `docs/design/DESIGN.md`의 관련 항목을 먼저 읽고 기존 공통 부품과 규칙을 적용한다. 빈 상태, 로딩, 오류, 버튼 동작, 화면 이동·복귀, 사용자에게 표시되는 문구도 포함한다. 공통 규칙을 새로 만들거나 변경하면 같은 작업에서 문서와 구현을 함께 갱신한다.
- 규칙·역할·예외와 '무엇을 바꿀 때 어디를 고치나'는 `docs/design/DESIGN.md` 하나에 있다.
- 값은 Flutter에서 한 번만 정의한다: 글꼴·크기·줄 높이·색은 `app/lib/ui/theme.dart`, 간격·모서리·조작부·아이콘·표지 크기와 공용 부품은 `app/lib/ui/kit.dart`. 화면 파일에 크기·색 숫자를 새로 쓰지 않는다.
- 시안 토큰(`app/design-system/tokens.json`·`web/`)은 손으로 고치지 않는다. 값을 바꿨으면 `cd app && DESIGN_TOKENS_UPDATE=1 flutter test test/design_tokens_test.dart`로 다시 만들고 함께 커밋한다(안 하면 `flutter test`가 실패한다).

## 결제(인앱결제) 작업: 돈과 DB가 걸린 변경만 PR
- 위 "무조건 main"의 예외다. 아래 변경은 main에 바로 올리지 않고 브랜치와 PR로 한다. 다른 사람이 확인한 뒤 머지하고, 머지 뒤 브랜치를 지운다.
  - DB 마이그레이션
  - 지급 판단(구매 검증, 권한 지급·회수)
  - 스토어 알림 수신
- 그 밖의 결제 작업은 main에 바로 올린다: 문서, 학습 노트, 약관·고지 문구, 서버에서 아직 불리지 않는 코드.
- 작업 목록은 마일스톤 "인앱결제 1차"의 이슈로 관리한다.
- 결제 화면은 빌드 플래그로 꺼 둔 채 머지한다(main push마다 TestFlight가 돌기 때문).
- 마이그레이션 번호는 머지 직전에 main과 맞춘다.
- 가격, 사업자 정보, 스토어 키는 저장소·이슈·PR에 적지 않는다(공개 저장소).
- 결정 기록은 `docs/adr/`에 있다: `0001-iap-server-go.md`(서버·라이브러리), `0002-iap-design.md`(설계), `0003-iap-compliance.md`(법규 대응).
- 결제 화면과 알림 문구는 `docs/legal/notice-templates.md`를 따른다. 해지·탈퇴 경로를 숨기거나, 옵션을 미리 선택해 두거나, 거절한 사람에게 같은 팝업을 다시 띄우지 않는다(전자상거래법 다크패턴 규제).
