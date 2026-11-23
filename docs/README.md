# 문서 색인

## 폴더

| 폴더 | 담는 것 | 파일 이름 |
|---|---|---|
| `adr/` | 기술 결정 기록 | `번호-주제.md` |
| `spec/` | 구현 지시서, 계획, 구조 설명 | 주제 이름 |
| `design/` | 디자인 기준과 자산 규격. 시안 그림은 `design/mockups/`, 지난 기준·조사는 `design/history/` | 주제 이름 |
| `release/` | 배포와 로그인 설정 방법 | 주제 이름 |
| `legal/` | 약관·개인정보 처리방침 초안, 결제 고지 문구 | `주제-draft-날짜.md` |
| `templates/` | 문서 양식 (ADR, 보고서) | |
| `guides/` | 배우면서 쓰는 노트 (Go, 결제 서버) | 주제 이름 |
| `reports/` | 날짜별 작업 보고 | `날짜-주제.md` |
| `qa/` | 페르소나 QA 기준과 시험 자료 | |
| `screenshots/` | 보고서가 가리키는 캡처·영상 | `날짜-주제/` 폴더 |

- 새 보고서: `reports/YYYY-MM-DD-주제.md`
- 그 보고서의 캡처: `screenshots/YYYY-MM-DD-주제/`
- 새 결정 기록: `adr/다음 번호-주제.md`. 양식은 `templates/adr.md`
- 보고서 양식: `templates/report.md`
- 문서 최상위에는 이 색인만 둠

## 지금 기준이 되는 문서

- 디자인: [`design/DESIGN.md`](design/DESIGN.md)(화면 규칙·역할·예외·어디를 고치나), [`design/assets.md`](design/assets.md)
- 지시서: [`spec/HOME_BRIEF.md`](spec/HOME_BRIEF.md)(홈), [`spec/SPEC.md`](spec/SPEC.md)(홈 외), [`spec/BOOKSHELF_ASSET_BRIEF.md`](spec/BOOKSHELF_ASSET_BRIEF.md)(선반·배경 자산)
- DB 구조: [`spec/erd.md`](spec/erd.md)(지금은 결제 표 8개와 이유)
- 결제 용어: [`guides/iap-glossary.md`](guides/iap-glossary.md)
- 결제 세팅(애플·구글 콘솔, 서버 환경 변수): [`guides/iap-store-setup.md`](guides/iap-store-setup.md)
- 구조: [`spec/bookshelf-architecture.md`](spec/bookshelf-architecture.md)(옛 RN 앱 기록), 앱 폴더 안내 [`../app/README.md`](../app/README.md)
- 계획: [`spec/PLAN-2026-11-flow.md`](spec/PLAN-2026-11-flow.md)
- 배포: [`release/android-release.md`](release/android-release.md), [`release/ios-release.md`](release/ios-release.md)
- 로그인 설정: [`release/social-login.md`](release/social-login.md)
- 약관 초안: [`legal/terms-draft-2026-11-18.md`](legal/terms-draft-2026-11-18.md), [`legal/privacy-draft-2026-11-16.md`](legal/privacy-draft-2026-11-16.md)
- 결제 고지 문구: [`legal/notice-templates.md`](legal/notice-templates.md)
- 문서 양식: [`templates/`](templates/README.md)
- QA: [`qa/PERSONA_QA.md`](qa/PERSONA_QA.md)

## 결정 기록

| 번호 | 결정 | 상태 |
|---|---|---|
| 0001 | [인앱결제 서버 검증을 기존 Go 서버에서 go-iap으로 구현](adr/0001-iap-server-go.md) | 제안 |
| 0002 | [인앱결제 설계 결정 (상품 유형, 장부, 계정 연결, 실패 처리, 해외 확장)](adr/0002-iap-design.md) | 제안 |
| 0003 | [결제 법규 대응 (고지, 동의, 해지, 기록)](adr/0003-iap-compliance.md) | 제안 |

## 보고서

| 날짜 | 문서 |
|---|---|
| 2026-11-19 | [인앱결제·구독에서 신경 쓸 것 (조사 종합, 정할 것과 답이 있는 것, 미확인 17건)](reports/2026-11-19-iap-pitfalls.md) |
| 2026-11-18 | [인앱결제 종합 보고 (상품, 법규, 만들 것, 설계, 진행 방식)](reports/2026-11-18-iap-briefing.md) |
| 2026-11-18 | [법규 때문에 만들어야 하는 기능 (알림, 화면, 기록)](reports/2026-11-18-compliance-features.md) |
| 2026-11-16 | [페르소나 QA 2차 — 2026-11-16](reports/2026-11-16-persona-qa.md) |
| 2026-11-15 | [2026-11-15 페르소나 QA 보고](reports/2026-11-15-persona-qa.md) |
| 2026-10-26 | [2026-10-26 물리 개편 보고](reports/2026-10-26-physics.md) |
| 2026-10-26 | [2026-10-26 디자인 통일 보고](reports/2026-10-26-design.md) |
| 2026-10-05 | [2026-10-05 사진 갈피 + 재장정(앱 장정) 구현 보고](reports/2026-10-05-photo-bookmark-rebinding.md) |
| 2026-10-05 | [2026-10-05 백엔드·동기화 기록](reports/2026-10-05-backend-sync.md) |
| 2026-10-02 | [시안 재현: 표지·조판·책 몸체·머리글 (2026-10-02)](reports/2026-10-02-design-reproduction.md) |
| 2026-10-01 | [이동 표시 오류 마무리와 새 책 디자인 (2026-10-01)](reports/2026-10-01-move-fix-book-design.md) |
| 2026-10-01 | [홈 3D 구조 정리 - 단계별 결과 (2026-10-01)](reports/2026-10-01-home-3d.md) |
| 2026-10-01 | [홈 3D 구조 정리 - 진단과 기준 측정 (2026-10-01)](reports/2026-10-01-home-3d-diagnosis.md) |
| 2026-09-30 | [안정화와 갈피 문학잡지형](reports/2026-09-30-stability-bookmark.md) |
| 2026-09-30 | [책 구조(표지·속지·책등) 확정 결과](reports/2026-09-30-book-structure.md) |
| 2026-09-30 | [책장 한켠 — 전체 화면과 핵심 흐름 1차 구현](reports/2026-09-30-app-core.md) |
| 2026-09-27 | [2026-09-27 상태 기록](reports/2026-09-27-status.md) |
| 2026-09-27 | [홈 화면 시안 대조 및 수정 (2026-09-27)](reports/2026-09-27-home-visual-review.md) |

## 옛 React Native 앱 시기의 문서

- 2026-11-13: Flutter로 이전 시작
- 2026-11-18: React Native 앱(`app/`) 삭제 (마지막 커밋 `4f9e1d9`)
- 2026-11-13 이전 보고서와 `spec/` 지시서의 `app/...` 경로: 그 앱 기준
- `screenshots/2026-09-27-home/`: 2026-09-27~10-02에 번호만 붙여 모아 둔 캡처
