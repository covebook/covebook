-- 결제 고지(앱 안 알림함, ADR-0003 L8·L11). 유저에게 알린 것을 한 줄씩 남긴다. 알림함이 고지의 기준이고 푸시·이메일은 보조다.
-- 규칙
--  * 문구를 저장하지 않는다. 어떤 문구(template, 버전)에 어떤 값(params)을 넣었는지만 남긴다. 문구는 docs/legal/notice-templates.md에 있다.
--  * params에는 화면이 문구를 채울 값만 둔다. 금액은 두지 않는다(스토어가 정한다, ADR-0002 D22).
--  * (user_id, dedupe_key)가 유일해서 같은 일을 두 번 알리지 않는다. 같은 스토어 알림을 다시 처리해도 한 줄이다.
--  * 상태를 바꾸는 같은 트랜잭션(또는 같은 SQL 문)에서 쓴다. 상태만 바뀌고 고지가 빠지는 일이 없게.
--  * 계정을 지우면 함께 지운다(거래 기록은 iap_purchases에 따로 남는다).
CREATE TABLE iap_notices (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind             TEXT   NOT NULL,   -- purchase_done, payment_failed, expired, cancel_scheduled, subscription_refunded, shelf_refunded
    template         TEXT   NOT NULL,   -- 고지 문구 번호: T3, T7, T8, T9, T10
    template_version INT    NOT NULL DEFAULT 1,
    params           JSONB  NOT NULL DEFAULT '{}',
    env              TEXT   NOT NULL DEFAULT 'production' CHECK (env IN ('production', 'sandbox')),  -- 샌드박스 거래의 고지는 스위치가 꺼지면 보이지 않는다(D15)
    dedupe_key       TEXT   NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at          TIMESTAMPTZ,
    UNIQUE (user_id, dedupe_key)
);
CREATE INDEX iap_notices_user_idx ON iap_notices (user_id, created_at DESC);
