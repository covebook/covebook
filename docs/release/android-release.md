# 책장 한켠 안드로이드 릴리스 (Play Store)

앱을 AAB로 빌드해 Google Play Console에 올리는 파이프라인.

- 워크플로: `.github/workflows/android-flutter-play.yml` (Actions 이름 "CD: Android Flutter AAB")
- 앱 id: `app.covebook` (`flutter/android/app/build.gradle.kts`의 `applicationId`. 스토어 등록 후에는 바꿀 수 없다)
- 빌드 대상: `flutter/`
- 옛 React Native 앱(`app/`)과 그 워크플로(`android-playstore-deploy.yml`)는 2026-11-18에 지웠다(마지막 커밋 `4f9e1d9`). 앱 id와 업로드 키가 같아서 Flutter 빌드가 같은 앱의 업데이트로 올라간다.

## 1. 한 번만 하는 준비

### 1-1. 업로드 키스토어

키스토어를 잃으면 같은 앱의 업데이트를 못 올린다. 파일과 비밀번호는 따로 안전하게 보관한다.

```bash
keytool -genkeypair -v -keystore chaekjang-upload.jks -alias chaekjang-upload \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w 0 chaekjang-upload.jks > chaekjang-upload.jks.base64
```

### 1-2. Play Console

1. 앱을 만들고 패키지명을 앱 id(`app.covebook`)와 같게 한다.
2. **첫 AAB는 콘솔에서 손으로 한 번 올려야 한다.** Play API는 이미 트랙이 있는 앱에만 올릴 수 있다. 아래 "드라이런"으로 받은 AAB를 올린다.
3. GitHub의 `PLAY_SERVICE_ACCOUNT_JSON`에 들어 있는 실제 서비스 계정을 Play Console 사용자 및 권한에 등록한다. 현재 Covebook 전용 계정은 `covebook-play-deploy@gen-lang-client-0332508820.iam.gserviceaccount.com`이다. `app.covebook`에만 앱 정보 보기·앱 품질 정보 보기(자동 포함)·앱을 테스트 트랙으로 출시 권한을 부여한다. 계정 전체·관리자·재무·프로덕션 권한은 자동 Alpha 업로드에 부여하지 않는다.

### 1-3. GitHub Secrets

저장소 Settings > Secrets and variables > Actions.

| 종류 | 이름 | 값 |
| --- | --- | --- |
| Secret | `KEYSTORE_BASE64` | `chaekjang-upload.jks.base64` 내용 |
| Secret | `KEYSTORE_PASSWORD` | 키스토어 비밀번호 |
| Secret | `KEY_ALIAS` | `chaekjang-upload` |
| Secret | `KEY_PASSWORD` | 키 비밀번호 |
| Secret | `PLAY_SERVICE_ACCOUNT_JSON` | 서비스 계정 JSON 전체 (드라이런이면 불필요) |
| Variable | `ANDROID_VERSION_CODE_OFFSET` | 선택. 이미 올린 빌드가 있을 때 versionCode 바닥을 올리는 정수 |

업로드를 요청한 실행은 AAB 빌드 전에 실제 서비스 계정과 Play 앱 접근 권한을 확인한다(`.github/scripts/check_play_access.py`). 검사용 임시 edit를 만들고 Alpha 트랙을 조회한 뒤 폐기하며 출시를 업로드하거나 commit하지 않는다. 키 JSON·비밀키·인증 토큰은 출력하지 않는다.
서버 주소는 워크플로에 적혀 있다(`--dart-define=SYNC_URL=https://covebook.kodeploy.com`). 바꾸려면 워크플로를 고친다. 앱 배포와 별도로 운영 서버에도 호환되는 동기화 코드를 배포해야 한다. 동기화 응답의 `syncEpoch`가 2 이상이 아니면 앱은 기록을 기기에 보관하고 서버 업데이트를 안내한다.

## 2. 배포하는 법

자동으로 돌지 않는다. main에서 손으로만 돌린다: Actions > "CD: Android Flutter AAB" > Run workflow.

| 입력 | 뜻 | 기본값 |
| --- | --- | --- |
| `track` | 올릴 테스트 트랙. `alpha`, `internal`, `beta` 중 하나 | `alpha` |
| `version_name` | 버전 이름(예: `0.2.0`) | `0.2.0` |
| `dry_run` | 켜면 AAB만 만들어 아티팩트로 남기고 Play 업로드는 건너뛴다 | 꺼짐 |

- 이 전용 서비스 계정은 프로덕션 출시 권한이 없다. 정식 출시는 Play Console에서 한다.
- versionCode는 2025-01-01부터의 분 단위 시각이라 겹치지 않는다. 한 번에 하나만 돈다.

## 3. 빌드가 하는 일

Play 권한 사전 검사(업로드할 때만) → 버전 정하기 → 키스토어 복원 → `flutter build appbundle --release` → AAB 아티팩트 저장 → Play 업로드(업로드할 때만) → 서명 파일 지우기.

- Flutter 버전은 워크플로에 고정돼 있다(3.47.6).
- `.github/scripts/test_check_play_access.py`(권한 검사 단위 테스트)는 옛 워크플로에서만 돌았다. 지금은 CI에서 돌지 않으므로 검사 스크립트를 고치면 손으로 돌린다: `python -m unittest discover -s .github/scripts -p 'test_check_play_access.py' -v`

## 4. 2026-10-27 업로드 복구 기록 (옛 React Native 워크플로)

아래는 지운 워크플로에서 있었던 일이다. `recover_existing_run` 같은 입력은 지금 워크플로에 없다. Play 권한 설정 경위를 남겨 둔다.

- main의 `d9aedd5` 실행 `40422698144`는 AAB 빌드·타입 검사를 통과했으나 실제 서비스 계정이 Play Console에 미등록되어 업로드 단계에서 권한 오류가 났다. 키가 GitHub에 존재하는지 확인하는 것만으로는 이 오류를 발견할 수 없었다.
- 계정의 비밀값을 바꾸지 않고 Covebook에만 테스트 출시 권한을 등록한 뒤, 실행 `40439933188`에서 기존 `chaekjang-956153-aab`를 재사용해 Alpha 업로드를 완료했다. 재빌드·버전 변경은 하지 않았다. Play 심사·게시 여부는 Console에서 별도로 확인한다.
- 이 사건의 재전송 입력 `recover_existing_run=40422698144`는 해당 main 커밋·아티팩트·SHA-256만 허용하며 트랙은 Alpha로 고정된다. 실행하려면 `dry_run=false`가 필요하다. 이미 복구한 버전을 다시 올리지 않는다. 다른 실행에 재사용하려면 소스·AAB·버전·서명을 확인하고 제한값을 코드 리뷰로 갱신한다.
- 권한 오류·트랙 조회 오류·임시 edit 정리 실패·다른 서비스 계정·Alpha 트랙 누락을 검사하는 단위 테스트가 있다. 실제 Store 서명본의 기기 설치·전체 기능 사용까지 검증했다는 뜻은 아니다.
