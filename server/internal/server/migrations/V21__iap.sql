-- 인앱결제(ADR-0002). 거래 원장, 구독 상태, 받은 알림, 파는 상품, 계정 연결 값.
-- 규칙
--  * 권한은 저장하지 않는다. plus 여부와 선반 칸 수는 아래 표에서 계산한다(D5).
--  * 결제 경로(route)는 문자열 값이다('apple', 'google'). 새 경로가 생겨도 표를 고치지 않게 CHECK를 두지 않는다(D19).
--  * 거래·구독은 계정을 지워도 남긴다(거래 기록 보존, ADR-0003). 그래서 user_id는 ON DELETE SET NULL이다.
--    다른 표는 CASCADE로 지워지지만 이 두 표는 유저 연결만 끊긴다.
--  * 시각은 전부 UTC(TIMESTAMPTZ). 만료 판단은 서버 시계로 한다(D23).
--  * 금액은 통화 1단위 = 1000인 정수(D20). 구글 구매 조회에는 금액이 없어 NULL이다.

-- 스토어에 넘기는 계정 연결 값(애플 appAccountToken, 구글 obfuscatedAccountId). 유저 번호를 밖에 내보내지 않는다(D7).
-- 유저 하나에 여러 개일 수 있다: 애플은 첫 구매 때 값이 굳어 계정을 옮겨도 그대로 오기 때문에, 옮길 때 값도 함께 옮긴다(D8).
CREATE TABLE iap_account_tokens (
    token      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX iap_account_tokens_user_idx ON iap_account_tokens (user_id, created_at);

-- 파는 상품. "어떤 상품이 무엇을 주는가"를 코드가 아니라 여기에 둔다(D21). 가격은 두지 않는다(스토어가 정한다, D22).
CREATE TABLE iap_products (
    route       TEXT NOT NULL,
    product_id  TEXT NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('subscription', 'product')),
    entitlement TEXT,              -- 구독이 주는 권한('plus')
    shelves     INT,               -- 한 번 사는 상품이 주는 선반 칸 수
    active      BOOLEAN NOT NULL DEFAULT true,  -- 새로 팔지 않게 된 상품은 false. 이미 산 것은 그대로 인정한다
    PRIMARY KEY (route, product_id),
    CHECK ((kind = 'subscription' AND entitlement IS NOT NULL AND shelves IS NULL)
        OR (kind = 'product' AND shelves > 0 AND entitlement IS NULL))
);

-- 거래 원장: 스토어가 확인해 준 거래 1건. 줄을 지우지 않는다. 환불은 state와 revoked_at으로 남긴다.
-- (route, transaction_id)가 유일해서 같은 거래를 두 번 제출해도 한 번만 들어간다(D6).
CREATE TABLE iap_purchases (
    id             BIGSERIAL PRIMARY KEY,
    route          TEXT   NOT NULL,
    transaction_id TEXT   NOT NULL,   -- 애플: 거래 ID. 구글: 주문 ID(없으면 구매 토큰)
    original_id    TEXT   NOT NULL,   -- 구독 줄기를 묶는 값. 애플: 원 거래 ID. 구글: 구매 토큰
    user_id        BIGINT REFERENCES users(id) ON DELETE SET NULL,
    account_token  UUID,              -- 스토어가 돌려준 계정 연결 값. 없는 구매도 있다
    product_id     TEXT   NOT NULL,
    kind           TEXT   NOT NULL CHECK (kind IN ('subscription', 'product')),
    env            TEXT   NOT NULL CHECK (env IN ('production', 'sandbox')),  -- 샌드박스도 받되 매출 집계에서 뺀다(D15)
    state          TEXT   NOT NULL CHECK (state IN ('paid', 'revoked')),
    purchased_at   TIMESTAMPTZ NOT NULL,
    revoked_at     TIMESTAMPTZ,
    currency       TEXT CHECK (currency ~ '^[A-Z]{3}$'),
    price_milli    BIGINT,
    country        TEXT,              -- 스토어가 준 코드 그대로(애플 storefront, 구글 regionCode)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (route, transaction_id)
);
CREATE INDEX iap_purchases_user_idx ON iap_purchases (user_id, kind);
CREATE INDEX iap_purchases_original_idx ON iap_purchases (route, original_id);

-- 구독 한 줄기의 지금 상태. 갱신될 때마다 거래 줄은 늘고 이 줄은 고쳐진다.
-- user_id는 "구매 복원"을 누른 계정으로 바뀔 수 있다. 한 번에 한 계정만 가진다(D8).
CREATE TABLE iap_subscriptions (
    id                    BIGSERIAL PRIMARY KEY,
    route                 TEXT   NOT NULL,
    original_id           TEXT   NOT NULL,
    user_id               BIGINT REFERENCES users(id) ON DELETE SET NULL,
    product_id            TEXT   NOT NULL,
    plan_id               TEXT   NOT NULL DEFAULT '',  -- 구글 요금제(base plan). 애플은 상품 ID가 요금제라 빈 값
    env                   TEXT   NOT NULL CHECK (env IN ('production', 'sandbox')),
    state                 TEXT   NOT NULL CHECK (state IN ('paid', 'inactive', 'revoked')),
    expires_at            TIMESTAMPTZ NOT NULL,
    grace_until           TIMESTAMPTZ,       -- 결제 실패 유예가 끝나는 시각. 유예 중이 아니면 NULL(D11)
    auto_renew            BOOLEAN NOT NULL,  -- false면 해지 예약. 만료일까지는 유효하다(D12)
    latest_transaction_id TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (route, original_id)
);
CREATE INDEX iap_subscriptions_user_idx ON iap_subscriptions (user_id);

-- 스토어가 보낸 알림 1건. 원문을 남긴다(분쟁과 버그 추적). (route, notification_id)가 유일해서 다시 와도 한 번만 처리한다(D6).
CREATE TABLE iap_notifications (
    id              BIGSERIAL PRIMARY KEY,
    route           TEXT NOT NULL,
    notification_id TEXT NOT NULL,   -- 애플: notificationUUID. 구글: Pub/Sub messageId
    kind            TEXT NOT NULL,   -- 스토어가 준 종류 값 그대로
    payload         TEXT NOT NULL,
    result          TEXT NOT NULL DEFAULT 'received' CHECK (result IN ('received', 'processed', 'ignored', 'failed')),
    error           TEXT,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at    TIMESTAMPTZ,
    UNIQUE (route, notification_id)
);
CREATE INDEX iap_notifications_pending_idx ON iap_notifications (received_at) WHERE result IN ('received', 'failed');
