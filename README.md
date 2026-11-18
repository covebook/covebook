# 책장 한켠

- 읽은 책을 모아 직접 배치해 꾸미는 책장 앱
- 화면명: "나의 책장"


- 앱: `app/` (Flutter, Android·iOS)
- 서버: `server/` (Go, PostgreSQL)
- 문서: `docs/` ([색인](docs/README.md))
- 작업 규칙: [`AGENTS.md`](AGENTS.md)

## 실행

```bash
cd flutter
flutter pub get
flutter run
flutter test

cd server
go test ./...                     # PostgreSQL 통합 시험은 별도 테스트 DB 필요
DATABASE_URL='postgres://user:pass@localhost:5432/chaekjang?sslmode=disable' go run ./cmd/server # 기본 포트 8080
```

- Flutter 버전: 배포 워크플로와 맞춤 (`.github/workflows/android-flutter-play.yml`의 `flutter-version`)
- 서버 설정·검증 방법: [`server/README.md`](server/README.md)
- 서버 운영 반영: KoDeploy에서 손으로 재배포

## 구조

| 경로 | 역할 |
|---|---|
| `app/lib/domain/` | 책·자리 값, 3D 구조, 빛·그림자 계산 |
| `app/lib/scene_config/` | 빛·카메라·스킨 값 |
| `app/lib/db/`, `app/lib/store/` | 기기 DB와 서재 읽기·쓰기 |
| `app/lib/services/` | 서버 동기화 등 바깥 연동 |
| `app/lib/features/` | 화면(홈, 책, 갈피, 읽기, 기록, 통계, 공유, 설정, 계정 등) |
| `app/lib/ui/`, `app/lib/app/` | 공통 부품, 앱 뼈대와 탭 이동 |
| `app/design-system/` | 디자인 시스템 문서 |
| `server/internal/server/` | 계정, 동기화, 파일, 도서 API와 DB 마이그레이션 |
| `server/internal/llm/` | Gemini·GPT 키 관리 게이트웨이 |
| `server/internal/appleauth/` | Apple 로그인 검증 |

## 배포

| 대상 | 방법 | 문서 |
|---|---|---|
| Android (Play) | Actions에서 "CD: Android Flutter AAB"를 손으로 실행 | [`docs/release/android-release.md`](docs/release/android-release.md) |
| iOS (TestFlight) | main에 `app/**` 변경이 푸시되면 자동 실행 | [`docs/release/ios-release.md`](docs/release/ios-release.md) |
| 서버 | KoDeploy에서 손으로 재배포 | [`server/README.md`](server/README.md) |

## 옛 React Native 앱

- 2026-11-13: Flutter로 이전 시작
- 2026-11-18: React Native 앱(`app/`)을 저장소에서 삭제
- 코드가 남아 있는 마지막 커밋: `4f9e1d9` (`git show 4f9e1d9:app/package.json`으로 꺼내 볼 수 있음)
- 셰이더 생성기(`app/tool/gen_shaders.sh`): 아직 그 코드를 씀. 그 커밋에서 꺼내 실행
- 2026-11-13 이전 보고서(`docs/reports/`)의 `app/...` 경로: 그 앱 기준
- 이 README에 있던 과거 기록: [`2026-09-27 상태`](docs/reports/2026-09-27-status.md), [`2026-10-05 백엔드·동기화`](docs/reports/2026-10-05-backend-sync.md)
