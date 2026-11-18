# 작업 규칙 (사람·AI 에이전트 공통)

## Git: 무조건 main (결제 작업만 예외)
- 브랜치를 따로 만들지 않는다. 실험·점검도 main에서 한다(`git checkout -b`, `git worktree add`로 다른 브랜치 만들기 금지).
- 단계가 끝날 때마다(코드나 문서가 바뀐 단계) 그 단계에서 바꾼 파일만 골라 main에 커밋하고 바로 push한다.
- 다른 사람이 먼저 push했으면 `git pull --rebase origin main`으로 받아 합친 뒤 push한다. 강제 push 금지.
- 같은 작업 폴더를 여러 세션이 함께 쓸 수 있다. `git add -A`·`git add .` 대신 내가 바꾼 파일만 add한다. 남의 미커밋 변경은 건드리지 않는다.
- 커밋 메시지는 짧은 한국어로 쓴다. `Co-Authored-By` 같은 AI 흔적은 넣지 않는다.
- 커밋하지 않는 것: `server/.env`, `server/.gradle`·`server/bin`·`server/build`·`server/data`.
- 앱은 Flutter(`flutter/`)다. main push에 `flutter/**` 변경이 있으면 iOS TestFlight CI(`.github/workflows/ios-testflight.yml`)가 돈다. 결과를 확인한다.
- 안드로이드 Play 배포(`.github/workflows/android-flutter-play.yml`)는 자동으로 돌지 않는다. Actions에서 손으로 돌린다.
- 서버(`server/**`) 변경은 push만으로 운영에 반영되지 않는다. KoDeploy에서 재배포해야 한다.

## 결제(인앱결제) 작업은 이슈·PR로
- 위 "무조건 main"의 예외다. 결제 관련 변경은 main에 바로 올리지 않는다.
- 마일스톤 "인앱결제 1차"의 이슈 하나에 브랜치 하나, PR 하나로 한다. 브랜치는 짧게 가져가고 머지 뒤 지운다.
- 다른 사람이 PR을 확인한 뒤 머지한다. DB 마이그레이션, 스토어 키, 지급 판단이 걸린 변경은 특히 그렇다.
- 결제 화면은 빌드 플래그로 꺼 둔 채 머지한다(main push마다 TestFlight가 돌기 때문).
- 마이그레이션 번호는 머지 직전에 main과 맞춘다.
- 가격, 사업자 정보, 스토어 키는 저장소·이슈·PR에 적지 않는다(공개 저장소).
- 결정 기록은 `docs/adr/`에 있다: `0001-iap-server-go.md`, `0002-iap-design.md`.
