# /design-sync 메모 — 책장 한켠 (Flutter)

- 앱이 Flutter라 웹 컴포넌트 번들이 없다. **토큰 전용 디자인 시스템**으로 올린다(컴포넌트 0개, 사용자 2026-11-16 'flutter 기준으로').
- 원본은 Flutter: `lib/ui/theme.dart`·`lib/ui/kit.dart` → `design-system/tokens.json`(손으로 뽑음) → `python3 tool/gen_design_css.py` → `design-system/web/`(styles.css · fonts.css · package.json · index.js). web/ 아래는 손으로 고치지 않는다.
- 빌드(flutter/에서):
  `python3 tool/gen_design_css.py && node .ds-sync/package-build.mjs --config .design-sync/config.json --node-modules ./.ds-sync/node_modules --entry ./design-system/web/index.js --out ./ds-bundle && node .ds-sync/package-validate.mjs ./ds-bundle`
- 변환기 의존: `.ds-sync/`에 esbuild · ts-morph · @types/react · react@18.3.1 · react-dom@18.3.1(묶음 _vendor용) · playwright@1.63.0(~/.cache/ms-playwright의 chromium-1243에 맞춤, 브라우저는 다시 받지 않음).
- 글꼴 묶음에는 실제로 넣은 글꼴만 적는다. 'Apple SD Gothic Neo' 같은 대체 글꼴 이름을 넣으면 `[FONT_MISSING]`이 난다.
- 지침(guidelines/)은 `design-system/components.md` · `drift.md` · `platform-widgets.md`를 빌드 때 복사한다.

## 업로드 기록
- 2026-11-16 첫 업로드: 프로젝트 '책장 한켠 Design System'(https://claude.ai/design/p/7efa6dab-30aa-404a-979a-f79e3c798a9b), 부품 0 · 파일 22개(글꼴 8, 지침 4, styles.css·_ds_bundle.*·README·_vendor). package-validate 통과.
- 로그인: 원격 조작(Remote Control)에서는 /design-login이 안 된다. 본 PC 터미널에서 /design-login 뒤 /design-sync.
- 다시 올리기: 위 빌드 명령 → validate → 프로젝트의 `_ds_sync.json`을 받아 `.design-sync/.cache/remote-sync.json`에 두고 resync 드라이버로 비교, 바뀐 파일만 올린다. 부품이 없으니 그림 검증(캡처·채점)은 없다.

## Re-sync risks
- `tokens.json`은 theme.dart에서 손으로 뽑았다. theme.dart를 바꾸고 tokens.json을 안 고치면 조용히 어긋난다. 동기화 전에 둘을 대조한다.
- conventions.md의 '부품 만드는 법' 표는 kit.dart 위젯 치수(버튼 높이·모서리·칩·탭 밑줄 등)를 옮긴 것이다. 위젯을 바꾸면 표도 고친다.
- 화면 사진(아티팩트·zip)은 묶음에 넣지 않았다. 디자인 에이전트는 사진을 보지 못한다.
- 기록 시점: 2026-11-16, 커밋 8372bb8 이후. 같은 날 `--ck-touch`를 44→48로(QA 고침 Space.hit 48, tokens.json `iconButtonTouch`·`hit`).
