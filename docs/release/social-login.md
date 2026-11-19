# Optional Google and Kakao login

> 앞 영어 절(서버 쪽 브라우저 로그인·탈퇴·복원)은 React Native 앱 시절에 썼다. 서버 내용은 그대로 맞다. 앱은 2026-11-18부터 Flutter이고, 로그인은 앱 안 SDK(카카오·Apple·Google, `/auth/{공급자}/native`, 커밋 694411a·5bd05bb)를 먼저 쓰고 안 되면 이 브라우저 흐름으로 돌아간다. 앱 쪽 시험은 아래 Verification.

The server authenticates provider identities. No provider secret belongs in the app, Git, public policies or logs. The existing book search key is separate from `KAKAO_LOGIN_REST_KEY`.

| Provider | Server variables | Fixed provider redirect |
|---|---|---|
| Google | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | `https://covebook.kodeploy.com/auth/google/callback` |
| Kakao | `KAKAO_LOGIN_REST_KEY`, `KAKAO_CLIENT_SECRET`, `KAKAO_ADMIN_KEY`, `KAKAO_APP_ID` | `https://covebook.kodeploy.com/auth/kakao/callback` |

Set `PUBLIC_BASE_URL=https://covebook.kodeploy.com`. Use a Google **Web application** OAuth client, scopes `openid profile`; email is not collected. Kakao requests only the member identifier and optional nickname. Neither provider's profile pictures or access/refresh tokens are persisted. Google signature, issuer, audience, expiry, nonce and authorized party are checked using official JWKS. Matching email/name never links accounts.

The app starts login with its authenticated device token and `accountLifecycle: "1"`. Only `chaekjang://auth/google` or `chaekjang://auth/kakao` is accepted for app return; development shells without the app's URL scheme cannot use this production flow. The HTTPS callback consumes the provider state, and an opaque single-use ticket is claimed using the starting device's token. Google tickets expire after two minutes; provider state after ten minutes. Expired login rows are removed when a login is started. A device with an existing provider link cannot silently switch into a different linked account. Anonymous predecessor copies are tracked and erased with their target account.

Kakao Login remains disabled until its Admin key and app id are configured. The Admin key is used solely for authenticating the unlink webhook and disconnecting accounts that were deleted in Covebook. Configure GET or POST `https://covebook.kodeploy.com/auth/kakao/unlink` as the Kakao **unlink webhook**. Both its `Authorization: KakaoAK ...` header and `app_id` are checked. A verified unlink removes the Kakao identity only; the Covebook account and reading records remain until the user explicitly requests account deletion.

## Account deletion and restore

`DELETE /me` requires the account's bearer token and `{ "confirmation": "DELETE" }`. The client pauses sync before requesting deletion. A minimal deletion intent, including a hash of the requesting token for idempotent retries, is durably stored outside the SQL database in the existing private FileStore (`_account-deletions/`). Tokens are revoked after the journal is saved. Background work deletes account rows and cascaded records, queues physical file removal and Kakao unlink, and retries failures. Logs use fixed messages without provider identifiers, keys or record contents. Kakao unlink jobs retain only the identifier needed for retries; jobs that remain after seven days raise an operator alert and continue retrying until resolved.

Deletion intents include account creation time to prevent deleting a new account that happens to reuse a numeric id. They remain for less than 30 days after DB deletion, and are reapplied **before web service startup** after a DB restore. Restore the database while retaining the newer independent private file store. Do not roll that journal back with a database snapshot. A restore older than the journal retention requires a separate audit; no host backup expiry has been verified by this code alone.

Local books/photos are intentionally retained after server deletion. A 401 response persistently pauses sync, including after restart; it never creates a replacement device account automatically. An explicit confirmation in Settings can create a new cloud account and upload local records again. A failed deletion request preserves its retry credential and remains paused. Existing old clients are required to update before starting a social login.

The file deletion queue retries physical removal, including unregistered objects in the user's storage prefix. A persistent failure requires operator intervention; a timer alone does not guarantee a seven-day deletion deadline. Host/proxy log retention and hosting backup retention are separate configuration and must be verified before publishing a concrete guarantee. R2 credentials require list, read, write and delete access to the private bucket and deletion journal. Do not roll back this journal with an older database backup.

## Rollout

- In Google Cloud Console, use a Web application OAuth client and register `https://covebook.kodeploy.com/auth/google/callback` as an authorized redirect URI. Set `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `PUBLIC_BASE_URL` on the server only.
- Apply migrations V6 and V7 using Flyway on existing Flyway-managed databases before starting the Go server. Go-managed databases apply V6 and V7 themselves; never point tests at the production database.
- Deploy the server before enabling the app feature. `/auth/providers` reports which providers are configured; missing credentials keep the corresponding button hidden. The production OAuth flow requires an installed build of the app.
- Older app versions can automatically recreate a device account after a token is revoked. Update all devices before requesting deletion; records retained on an old device can otherwise be uploaded again as a new account.

## Verification

Run `go test ./...` in `server`, setting `TEST_DATABASE_URL` to a disposable PostgreSQL database for integration tests, and `flutter analyze --no-fatal-infos` plus `flutter test test/sync_test.dart test/login_gate_test.dart` in `app` (the old React Native `sync-account-lifecycle` test was removed with that app on 2026-11-18). Integration tests use isolated PostgreSQL, fake providers and temporary storage. Tests cover JWT rejection, ticket/state replay, authenticated deletion, immediate session rejection, physical file removal, predecessor deletion, restore reapplication, forged webhook rejection and sync pause persistence. Provider registration and real installed-app sign-in are separate checks.

Google button artwork is the unmodified approved light button. Sources: [Google OIDC](https://developers.google.com/identity/openid-connect/openid-connect), [Kakao REST](https://developers.kakao.com/docs/ko/kakaologin/rest-api), [Kakao callbacks](https://developers.kakao.com/docs/ko/kakaologin/callback).


## 로그인 필수 (2026-11-16, Flutter)

- 서버가 있는 빌드(`SYNC_URL`)는 카카오·Apple·Google 중 하나로 로그인해야 책장이 열린다(`features/auth/login_screen.dart`의 `AuthGate`). 서버 없는 시험 빌드는 지금처럼 바로 쓴다.
- 로그인은 기존 연결 흐름 그대로다: 기기 계정을 만들고(`/auth/device`) 소셜 계정을 붙인다. 이미 있는 계정이면 그 계정으로 바뀌고(`switched`) 서버 기록을 받아 온다. 로그인 전에는 동기화하지 않는다.
- 예시 책장 자리는 시각을 `1970-01-01`로 두고 올리지 않는다(`exampleLayoutAt`). 배치는 '더 나중에 고친 쪽'이 이기므로, 새 폰에서 받기 전에 깔린 예시 자리가 진짜 책장을 덮지 않게 했다.
- 로그아웃(백업 및 복원): 올리지 못한 변경을 먼저 올려 보고 남으면 알린다. 그다음 이 폰의 서재 DB·진행 중 독서·사진·받은 표지·책장 시작 사진·토큰을 지우고 로그인 화면으로 간다(`store/local_reset.dart`). 기기 설정(진동·움직임·스킨·책 측면)은 남긴다.
- 서버 계정 삭제도 이 폰의 기록을 지우고 로그인 화면으로 간다.
- App Store 심사 5.1.1(v): 계정이 꼭 필요하지 않은 기능에 로그인을 강제하면 반려될 수 있다. 동기화·커뮤니티가 계정 기능이라는 설명을 심사 메모에 준비한다.
- 남은 것: 실제 소셜 로그인으로 처음 로그인·다른 폰 로그인·로그아웃·재로그인을 실기기에서 확인. 안드로이드 홈 위젯은 로그아웃 뒤에도 마지막 책장 그림이 남는다(다시 로그인하면 바뀐다).

## Apple 로그인

Apple 서버 검증·토큰 철회와 TestFlight 구성은 [ios-release.md](ios-release.md)를 참고한다.
