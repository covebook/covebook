-- 연결된 로그인마다 공급자가 확인해 준 이메일(선택, 계정 화면에 '어느 계정인지' 보여 주는 용도. 회원탈퇴 때 행과 함께 지워진다)
ALTER TABLE auth_identities ADD COLUMN email TEXT;
-- Apple 갱신 토큰을 받은 클라이언트: NULL은 웹(Services ID), 값이 있으면 그 클라이언트(앱 안 로그인은 번들 ID)로 연결을 끊는다
ALTER TABLE apple_tokens ADD COLUMN client_id TEXT;
