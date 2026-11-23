-- 구독 요금제의 결제 주기(월, 연). 갱신 예정 고지(T4, 연 구독만, ADR-0003 L9)와 앱의 기기 예약 알림에 쓴다.
-- 스토어 응답에는 주기가 없다(애플 거래 정보, 구글 subscriptionsv2 모두). 그래서 상품 테이블처럼 운영자가 채운다(D21). 가격은 두지 않는다(D22).
--  * 애플은 상품 ID가 요금제라 plan_id가 빈 값이다. 구글은 base plan ID다(한 구독 상품에 월·연 요금제가 함께 있다).
--  * 줄이 없는 요금제는 주기를 모르는 것으로 본다: 갱신 예정 고지를 보내지 않고, /iap/me에 period를 넣지 않는다.
CREATE TABLE iap_plans (
    route      TEXT NOT NULL,
    product_id TEXT NOT NULL,
    plan_id    TEXT NOT NULL DEFAULT '',
    period     TEXT NOT NULL CHECK (period IN ('month', 'year')),
    PRIMARY KEY (route, product_id, plan_id),
    FOREIGN KEY (route, product_id) REFERENCES iap_products (route, product_id)
);
