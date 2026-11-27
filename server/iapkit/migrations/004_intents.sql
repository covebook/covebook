-- 결제 의도(2026-11-27, D1 개정)
-- 대상은 스토어에 싣지 않고 우리 서버에 남긴다. 계정 연결 값은 계정마다 하나로 돌아간다(D7)
--   - 애플은 한 계정의 모든 구매에 같은 appAccountToken을 쓰라고 권한다(WWDC25 세션 249)
--   - 구매마다 새 값을 넣었는데 첫 값이 돌아왔다는 보고가 있다(애플 포럼 800411, 샌드박스)
--   - 구글은 obfuscatedAccountId를 "구매자의 앱 계정"으로 보고 사기 탐지에 쓴다
--
-- iap_reservations 한 줄이 두 가지 일을 한다
--   - 결제 중 예약: expires_at까지(몇 분) 그 대상의 수량을 잡아 두 기기가 상한을 넘게 사지 못하게 한다
--   - 결제 의도: keep_until까지(며칠) "이 유저가 이 대상에 이 수량을 사려 했다"를 기억한다.
--     결제가 늦게 끝나도(구글 현금 결제 대기, 애플 보호자 승인) 알림만으로 대상을 찾는다
ALTER TABLE iap_reservations ADD COLUMN keep_until TIMESTAMPTZ;
UPDATE iap_reservations SET keep_until = expires_at;
ALTER TABLE iap_reservations ALTER COLUMN keep_until SET NOT NULL;
-- 상한을 세는 일은 몇 분짜리 예약만 본다. 대상은 결제 시각 앞의 의도 중 같은 수량을 찾는다
DROP INDEX iap_reservations_user_idx;
CREATE INDEX iap_reservations_user_idx ON iap_reservations (user_id, units, created_at);

-- 대상마다 따로 주던 계정 연결 값을 그만 쓴다. 이미 준 값은 지우지 않는다(그 유저의 값이라 주인 찾기에는 계속 쓴다)
DROP INDEX iap_account_tokens_target_idx;
ALTER TABLE iap_account_tokens DROP COLUMN target;
