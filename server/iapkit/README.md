# iapkit (서버 쪽 결제 키트)

앱 안 결제(Apple App Store, Google Play)를 처리하는 서버 패키지다. 책장 한켠에서 떼어 냈고, 다른 앱에도 같은 방식으로 붙인다.

- 앱 쪽 짝: [`app/packages/iap_kit`](../../app/packages/iap_kit/README.md)
- 법·고지 체크리스트: [`LEGAL.md`](LEGAL.md)
- 결정 기록(책장 한켠에서 내린 것): `docs/adr/0001-iap-server-go.md`(서버·라이브러리), `0002-iap-design.md`(설계 D1~D23), `0003-iap-compliance.md`(법규 L1~L23)
- 운영 설정(스토어 콘솔·알림 주소·키): `docs/guides/iap-store-setup.md`

## 하는 일

| 일 | 어디 |
|---|---|
| 구매 확인: 앱이 낸 증거로 스토어에 다시 물어 지급 | `purchase.go` `POST /iap/purchases` |
| 원장: 거래 1건 1줄, 지우지 않음. 권한은 저장하지 않고 원장에서 계산 | `store.go`, `migrations/001_iap.sql` |
| 한 번 사는 상품의 대상(결제 의도)·상한(결제 중 예약) | `purchase.go` `POST /iap/intent` |
| 스토어 알림 받기(애플 App Store Server Notifications v2, 구글 RTDN Pub/Sub) | `notify.go` |
| 정기 대조: 밀린 알림, 확인 못 한 거래, 스토어 목록으로 빠진 환불 메우기, 넘김 환불 | `notify.go` `StartWorker` |
| 결제 고지 기록(알림함): 결제 완료, 실패, 만료, 환불, 갱신 예정, 넘김 | `notices.go` |
| 구매 내역, 사업자 정보, 운영자 통계 | `history.go` |
| 스토어 API 호출(서명 확인, 조회, 확인·소비, 환불) | `iap/` 하위 패키지 |

## 붙이는 법

### 1. 요구 사항

- Go: 이 저장소의 `go.mod` 판(1.27). `net/http`의 메서드 경로 패턴(`"POST /iap/purchases"`)을 쓴다
- PostgreSQL: CI는 14로 시험한다. `hashtextextended`를 쓰므로 11 이상
- 앱 DB에 `users (id BIGINT PRIMARY KEY)` 테이블. 키트 테이블이 이 테이블을 가리키고, 유저 단위 잠금에 `SELECT id FROM users WHERE id=$1 FOR NO KEY UPDATE`를 쓴다(FK를 가진 다른 테이블의 쓰기는 막지 않음)
- 키트가 쓰는 테이블 이름은 모두 `iap_`로 시작하고, 마이그레이션 이력은 `iapkit_schema_history`에 따로 남는다. 앱 테이블과 이름이 겹치면 안 된다

### 2. 코드

```go
import "github.com/yuntyu01/chaekjang-hankyeon/server/iapkit"

// 앱 마이그레이션(users 테이블 포함) 뒤에
if err := iapkit.Migrate(ctx, db); err != nil { ... }

kit := iapkit.New(db, iapkit.StoresFromEnv(), myRules, iapkit.SandboxFromEnv())
kit.Auth = func(w http.ResponseWriter, r *http.Request) (int64, bool) {
    user, err := myAuth(r)              // 앱의 로그인 확인
    if err != nil {
        myWriteError(w, err)            // 응답은 앱이 쓴다
        return 0, false
    }
    return user, true
}
kit.Admin = myAdminCheck                // 없으면 운영자 경로는 404

mux := http.NewServeMux()
kit.Routes(mux)                         // 결제가 꺼져 있으면 아무것도 붙지 않는다
kit.StartWorker(ctx)                    // 고루틴을 직접 띄워 1분마다 정기 대조한다(go를 붙이지 않는다, 한 번만 부른다). 결제가 꺼져 있으면 바로 돌아온다
```

책장 한켠의 실제 연결: `server/internal/server/iap.go`(규칙·인증 연결), `server/internal/server/migrate.go`(마지막 줄에서 `iapkit.Migrate`)

### 3. 앱 규칙(Rules)

키트는 앱의 말(선반, 연도, 코인)을 모른다. 앱마다 다른 것은 `Rules`로 받는다.

| 필드 | 뜻 | 책장 한켠 | 대상이 없는 앱 |
|---|---|---|---|
| `TargetRequired` | 한 번 사는 상품이 어느 대상에 붙는지 정해져야 지급하는가 | `true` | `false` |
| `ValidTarget` | 앱이 보낸 대상 문자열이 맞는지(64자 이하는 키트가 먼저 본다) | 2000~9999 연도, `"02026"` 거절 | `nil` |
| `Cap` | 대상 하나에서 돈 내고 살 수 있는 수량의 최대. 0이면 상한 없음 | 3(연도 책장마다 선반 3칸) | 0 |
| `Hold` | 결제 중 예약이 상한을 잡는 시간. 0이면 5분 | 5분 | 상한이 없으면 쓰지 않음 |
| `Keep` | 결제 의도(어느 대상에 얼마를 사려 했는지)를 기억하는 시간. 0이면 8일(애플 알림 재전송 약 6.5일, 구글 Pub/Sub 보관 7일보다 길게) | 0(8일) | 쓰지 않음 |
| `Messages` | 오류 문구(문구 키 → 문장). 없는 키는 `DefaultMessages` | 선반 말로 바꾼 8개 | 비워 둠 |

- 대상(target): 한 번 사는 상품이 붙는 자리. 문자열이고 뜻은 앱이 정한다. 대상이 없는 앱은 `''`
- 수량(units): 상품 하나가 대상에 더하는 양. `iap_products.units`
- 권한(entitlement): 구독이 주는 이름. `iap_products.entitlement`. 지금 유효한 구독이 주는 이름만 `entitlements`에 나온다

대상은 스토어에 싣지 않는다. 계정 연결 값(애플 `appAccountToken`, 구글 `obfuscatedAccountId`)은 계정마다 하나이고, 어느 대상의 구매인지는 서버에 남긴 결제 의도로 찾는다(D1, D7, 2026-11-27 개정)

1. 앱이 제출에 붙인 결제 의도 번호(`reservation`). 이 유저의 것이고 결제보다 먼저 남긴 것만
2. 결제 전 72시간 안에 남긴 의도(보관 시간 `Keep` 안) 중 수량이 같은 것들, 없으면 전부를 본다. 그 대상이 하나로 모이면 가장 새것을 쓰고, 갈리면(두 기기에서 다른 대상을 동시에 결제) 모른다고 둔다. 스토어 알림이 먼저 온 경우도 이 길로 찾는다. 알림이 정한 대상은 뒤에 바꾸지 않으므로 추측하지 않고 앱 제출을 기다린다
3. 앱이 보낸 `target`(앱 밖에서 산 구매 등)

- 왜 스토어에 싣지 않나: 애플은 한 계정의 모든 구매에 같은 `appAccountToken`을 쓰라고 권하고(WWDC25 세션 249), 구매마다 새 값을 넣었는데 첫 값이 돌아왔다는 보고가 있다(애플 포럼 800411). 구글은 이 값을 계정 식별자로 보고 사기 탐지에 쓴다
- 왜 며칠 기억하나: 결제가 늦게 끝나거나(구글 현금 결제 대기, 애플 보호자 승인) 서버가 내려가 알림이 늦게 와도(애플은 약 6.5일까지 다시 보내고, 구글 Pub/Sub은 7일 보관) 알림만으로 대상을 찾으려고

DB 값의 뜻(`iap_purchases.target`)

| 값 | 뜻 |
|---|---|
| `NULL` | 대상을 모름(거래만 기록, 지급하지 않음, 2일 뒤 환불) |
| `''` | 대상이 없는 앱의 상품 |
| `'2026'` 등 | 그 대상 |

### 4. 상품 넣기

상품은 코드가 아니라 테이블에 둔다(D21). 운영자가 SQL로 넣는다. 가격은 두지 않는다(스토어가 정한다, D22).

```sql
-- 구독: 권한 이름을 준다
INSERT INTO iap_products (route, product_id, kind, entitlement) VALUES ('apple', 'pro_monthly', 'subscription', 'pro');
-- 한 번 사는 상품: 수량을 준다. consume=false면 구글에서 소비하지 않는다(다시 살 수 없는 상품)
INSERT INTO iap_products (route, product_id, kind, units) VALUES ('google', 'coins_100', 'product', 100);
-- 구독 요금제 주기(갱신 예정 고지에 쓴다. 구글은 base plan ID, 애플은 빈 값)
INSERT INTO iap_plans (route, product_id, plan_id, period) VALUES ('google', 'pro', 'yearly', 'year');
```

### 5. 환경 변수

| 이름 | 뜻 |
|---|---|
| `IAP_ENABLED` | `1`이면 켠다. 꺼져 있으면 경로도 정기 처리도 없다(`StoresFromEnv`가 nil) |
| `IAP_APPLE_KEY_P8`, `IAP_APPLE_KEY_ID`, `IAP_APPLE_ISSUER_ID`, `IAP_APPLE_BUNDLE_ID` | App Store Server API 키. 넷 다 있어야 애플 경로가 생긴다 |
| `IAP_GOOGLE_KEY_JSON`, `IAP_GOOGLE_PACKAGE` | Google Play Developer API 서비스 계정 키와 패키지 이름 |
| `IAP_GOOGLE_PUSH_AUDIENCE`, `IAP_GOOGLE_PUSH_EMAIL` | 구글 알림(Pub/Sub 푸시)의 OIDC 토큰 확인 값. 없으면 구글 알림 경로를 열지 않는다 |
| `IAP_ALLOW_SANDBOX` | `1`이면 샌드박스 거래에도 지급(TestFlight, 심사). 매출 집계에서는 빠진다 |
| `IAP_SELLER_JSON` | 앱에 보일 사업자 정보 JSON(`name, owner, address, phone, email, bizNo, saleNo, host`). 공개 저장소에 적지 않는다 |
| `IAP_RENEWAL_NOTICE_DAYS` | 연 구독 갱신 예정 고지를 며칠 전에 쓸지(2~60, 기본 14) |

키 값은 저장소·이슈·PR에 적지 않는다. 배포 환경에만 둔다.

## API

모든 응답은 JSON이고 오류는 `{"error":{"code","message"}}`다. 로그인이 필요한 경로는 `Kit.Auth`가 확인한다.

| 경로 | 하는 일 |
|---|---|
| `GET /iap/me` | 지금 상태: `entitlements`, `unitsByTarget`, `capPerTarget`, `subscription`, `accountToken`(계정 연결 값), `products`, `routes`, `seller`, `unreadNotices` |
| `POST /iap/intent` | 한 번 사는 상품의 결제를 시작하기 직전. 결제 의도를 남기고 계정 연결 값을 준다. 요청 `{target, units}`, 응답 `{token, target, units(이미 산 수량), reservation?, expiresAt?}`. 대상도 상한도 없는 앱은 `reservation`이 없다 |
| `POST /iap/intent/release` | 결제 의도 지우기(결제 취소·실패). 결제 대기에는 부르지 않는다. 요청 `{reservation}`. 언제나 204 |
| `POST /iap/purchases` | 구매 제출. 요청 `{route, productId, proof, restore, target?, reservation?}`, 응답 `{status: granted\|already\|inactive, target?, overCap?, autoRefund?, ...상태}` 또는 202 |
| `GET /iap/purchases` | 구매 내역(L17) |
| `GET /iap/notices`, `POST /iap/notices/read` | 결제 고지 알림함(L8, L11) |
| `POST /iap/notifications/apple` | 애플 알림 수신(스토어가 부른다) |
| `POST /iap/notifications/google` | 구글 알림 수신(Pub/Sub 푸시) |
| `GET /admin/iap/stats` | 운영자 통계(`Kit.Admin`) |

요청·응답의 자세한 규칙은 각 핸들러 위 주석에 있다(`purchase.go`의 `iapSubmit`, `iapTargetTokenFor`).

### 오류 코드와 앱이 거래를 끝낼지

| 상태 | 코드 | 거래를 끝내나 | 뜻 |
|---|---|---|---|
| 200 | | 끝냄 | 지급했거나 전에 지급함 |
| 202 | | 안 끝냄 | 결제 대기(구글) |
| 404 | `iap_purchase_not_found` | 안 끝냄 | 스토어에 아직 없음 |
| 409 | `iap_purchase_refunded` | 끝냄 | 환불된 거래 |
| 409 | `iap_other_account` | 끝냄 | 다른 계정의 구매(한 번 사는 상품은 결제한 계정에 넣은 뒤 이 코드) |
| 409 | `iap_owner_gone` | 끝냄 | 결제한 계정이 탈퇴함 |
| 409 | `iap_cap_full` | (결제 전) | 상한까지 샀거나 남은 수량보다 많음 |
| 409 | `iap_target_busy` | (결제 전) | 다른 기기가 그 대상을 결제 중. `retryAfter`초 뒤 |
| 422 | `iap_purchase_rejected`, `iap_sandbox_not_allowed` | 끝냄 | 받지 않는 거래 |
| 422 | `iap_bad_proof`, `iap_unknown_product` | 안 끝냄 | 증거를 확인 못 함, 상품 테이블에 없음 |
| 422 | `iap_target_missing` | 안 끝냄 | 대상을 모름. 대상을 붙여 다시 낸다 |
| 429 | `iap_too_many` | 안 끝냄 | 유저당 1분 제출 횟수 넘음 |
| 503 | `iap_store_unavailable` | 안 끝냄 | 스토어 조회 실패, 스토어가 한도(429)에 걸려 쉬는 중 |
| 503 | `iap_busy` | 안 끝냄 | DB 잠금을 5초 넘게 기다림(결제 트랜잭션의 `lock_timeout`), 문장이 10초를 넘김, 교착(40P01) |

같은 응답 코드에 상황마다 다른 문구를 주려고 문구 키를 따로 둔다.

| 문구 키(`Rules.Messages`) | 응답 코드 |
|---|---|
| `iap_cap_full`, `iap_cap_too_many` | `iap_cap_full` |
| `iap_target_busy` | `iap_target_busy` |
| `iap_target_missing` | `iap_target_missing` |
| `iap_granted_owner` | `iap_other_account` |
| `iap_owner_refunded`, `iap_owner_later`, `iap_owner_apple` | `iap_owner_gone` |

## 테이블

| 테이블 | 담는 것 |
|---|---|
| `iap_products` | 파는 상품과 주는 것(권한 이름 또는 수량) |
| `iap_plans` | 구독 요금제의 결제 주기 |
| `iap_account_tokens` | 스토어에 넘기는 계정 연결 값(유저 번호를 밖에 내보내지 않는다, D7). 계정마다 하나(2026-11-27 전에 대상마다 준 값도 그 유저의 값으로 남는다) |
| `iap_reservations` | 결제 의도(`keep_until`까지)와 결제 중 예약(`expires_at`까지). 원장이 아니라 지워도 된다 |
| `iap_purchases` | 거래 원장. 계정을 지워도 남는다(`ON DELETE SET NULL`, 5년 보존 L13) |
| `iap_subscriptions` | 구독 1건의 지금 상태 |
| `iap_notifications` | 받은 스토어 알림 원문 |
| `iap_notices` | 보낸 결제 고지(L11) |

## 정기 대조(StartWorker)

1분마다 돌고, 스토어 알림이 오면 바로 깨어난다. 서버가 여러 대면 advisory lock(`iapkit.sweep`)을 잡은 한 대만 돈다. 나머지는 그 회차를 건너뛴다.

1. 스토어 확인(acknowledge·consume)을 못 마친 거래를 다시 확인한다. 구글은 3일 안에 확인하지 않으면 환불한다
2. 스토어 목록(애플 알림 이력, 구글 무효 구매 30일)으로 빠진 알림과 환불을 메운다(6시간에 한 번, 실패하면 15분 뒤 다시)
3. 밀린 알림을 처리한다
4. 상한을 넘게 산 거래 중 환불 요청을 못 마친 것을 다시 요청한다(구글)
5. 대상을 끝내 모르는 거래(2일 뒤)와 주인 없는 거래를 환불한다
6. 연 구독의 갱신 예정 고지를 쓴다(6시간에 한 번)

한 바퀴는 2분이 기준이다. 단계마다 마감 시각(`iapSweepStages`, 시작부터 30·60·80·95·115초)이 있어 느린 스토어가 앞 단계를 붙잡아도 뒤 단계가 돈다. 마감에 걸린 건은 다음 바퀴에 이어서 한다. 마감은 새 일을 시작하지 않게만 하고, 이미 시작한 환불 요청·스토어 확인과 그 기록은 끝까지 한다(최대 15초 넘김).

스토어가 한도 초과(429, 구글은 403의 한도 사유도)로 답하면 그 경로는 `Retry-After`까지 부르지 않는다(`iap.RateLimitError`, `iap.Rester`). 쉬는 동안 건너뛴 건과 처리 도중 한도에 걸린 건은 시도 횟수를 쓰지 않는다. 요약 로그의 `resting`은 건너뛴 건, `cut`은 마감에 걸린 단계 수다.

사람이 봐야 하는 일은 `iap alert:`로 시작하는 로그를 한 시간에 한 번 남긴다. 로그 기반 경보를 이 문자열에 건다.

| 경보 | 조건 | 할 일 |
|---|---|---|
| 구글 구매 미확인 | 확인 못 한 구글 구매가 48시간을 넘김(72시간이면 구글이 환불) | 구글 API 상태·키를 본다 |
| 환불 포기 | 주지 않은 거래의 환불 요청이 20번 실패했거나 주문 ID가 없음(`refundsGaveUp`) | 콘솔에서 직접 환불한다 |
| 알림 포기 | 8일 동안 처리하지 못한 알림(`notificationsGaveUp30Days`) | 원인을 고치고 다시 처리한다 |

## 시험

```sh
# 일회용 PostgreSQL이 필요하다. 키트 시험은 그 안에 스키마를 새로 만들어 users 테이블 하나만 두고 돈다
TEST_DATABASE_URL=postgres://... go test -race ./iapkit/...
```

- `rules_test.go`: 대상이 없는 앱 규칙(`Rules{}`, `Rules{Cap: 3}`)으로 사고, 넘기고, 환불한다
- `purchase_test.go`의 `covebookIAPRules`: 책장 한켠과 같은 값으로 연도·상한을 시험한다
- `iap/`: 스토어 API는 가짜(`fake.go`)로 시험한다

## 하지 않는 것

- 화면과 문구 전체. 앱이 만든다(LEGAL.md의 앱 체크리스트)
- 로그인. `Kit.Auth`로 앱의 인증을 받는다
- 가격 저장과 계산. 스토어가 정한다
- 세무 장부. 원장은 결제 사실의 기록이고 세무 장부를 대신하지 않는다(L22)
- 계정 삭제. 앱이 `users` 줄을 지우면 원장은 주인만 비운 채 남는다
