# 2026-10-05 백엔드·동기화 기록

> 저장소 README에 있던 기록을 2026-11-18에 옮겼다. 당시 앱은 React Native(`app/`)였고 그 폴더는 지웠다(마지막 커밋 `4f9e1d9`). 아래의 `app/...` 경로는 그 커밋 기준이다.

- **구조:** 앱은 로컬 우선(오프라인 동작)이고, `EXPO_PUBLIC_API_URL`이 있는 빌드에서만 서버와 동기화한다(`app/src/services/sync.ts`, 순수 규칙은 `domain/sync.ts`).
- **스키마(Flyway V2):** 판본(`editions`+`edition_authors`)·내 책·장정·회차·세션·갈피·파일을 앱 모델 그대로 정규화. 사용자 표는 `(user_id, id)` 복합 키 + 같은 사용자 안 복합 외래키. 공유 카탈로그 `books`는 저자를 `book_authors`로 분리. V8에서 책장 배치 JSON을 `shelves`·`shelf_placements` 표로 나누고 `books`의 계산 열(키·두께 분류, 기본 모티프)을 뺐다(`server/README.md`).
- **API:** `POST /auth/device`(기기 계정·토큰), `GET /me`, `POST /sync/push`, `GET /sync/pull?since=`, `PUT|GET /files/{id}`(사진), 기존 `/books/search`·`/books/{isbn13}`.
- **충돌·삭제:** `updatedAt`이 더 새로운 쪽이 이김, 삭제는 `deleted_at` 표시로 전달. 한 번 올리기는 한 트랜잭션.
- **미구현:** 소셜 로그인 검증(표 `auth_identities`만 준비), 요청 제한, 고아 파일 정리, 배포(HTTPS) — 보고서 `docs/reports/2026-10-05-photo-bookmark-rebinding.md` 참고.
