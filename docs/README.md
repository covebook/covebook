# 문서 색인

## 폴더

| 폴더 | 담는 것 | 파일 이름 |
|---|---|---|
| `spec/` | 구현 지시서, 계획, 구조 설명 | 주제 이름 |
| `design/` | 디자인 기준과 자산 규격. 시안 그림은 `design/mockups/` | 주제 이름 |
| `release/` | 배포와 로그인 설정 방법 | 주제 이름 |
| `legal/` | 약관·개인정보 처리방침 초안 | `주제-draft-날짜.md` |
| `reports/` | 날짜별 작업 보고 | `날짜-주제.md` |
| `qa/` | 페르소나 QA 기준과 시험 자료 | |
| `screenshots/` | 보고서가 가리키는 캡처·영상 | `날짜-주제/` 폴더 |

- 새 보고서는 `reports/YYYY-MM-DD-주제.md`, 그 캡처는 `screenshots/YYYY-MM-DD-주제/`에 둔다
- 문서 최상위에는 이 색인만 둔다

## 지금 기준이 되는 문서

- 디자인: [`design/DESIGN.md`](design/DESIGN.md), [`design/assets.md`](design/assets.md)
- 지시서: [`spec/HOME_BRIEF.md`](spec/HOME_BRIEF.md)(홈), [`spec/SPEC.md`](spec/SPEC.md)(홈 외), [`spec/BOOKSHELF_ASSET_BRIEF.md`](spec/BOOKSHELF_ASSET_BRIEF.md)(선반·배경 자산)
- 구조: [`spec/bookshelf-architecture.md`](spec/bookshelf-architecture.md)
- 계획: [`spec/PLAN-2026-11-flow.md`](spec/PLAN-2026-11-flow.md)
- 배포: [`release/android-release.md`](release/android-release.md), [`release/ios-release.md`](release/ios-release.md)
- 로그인 설정: [`release/social-login.md`](release/social-login.md)
- 약관 초안: [`legal/terms-draft-2026-11-18.md`](legal/terms-draft-2026-11-18.md), [`legal/privacy-draft-2026-11-16.md`](legal/privacy-draft-2026-11-16.md)
- QA: [`qa/PERSONA_QA.md`](qa/PERSONA_QA.md)

## 보고서

| 날짜 | 문서 |
|---|---|
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

- 앱은 2026-11-13부터 Flutter로 옮겼고, React Native 앱(`app/`)은 2026-11-18에 지웠다(마지막 커밋 `4f9e1d9`)
- 2026-11-13 이전 보고서와 `spec/`의 지시서에 나오는 `app/...` 경로는 그 앱 기준이다
- `screenshots/2026-09-27-home/`은 2026-09-27~10-02에 번호만 붙여 모아 둔 캡처다
