# app/tool — 만드는 도구

손으로 고치지 않는 파일(셰이더·견줌 자료·아이콘·그림)을 만드는 도구다. 앱 빌드(`flutter build`)는 이 도구를 돌리지 않는다. 만든 결과를 저장소에 함께 커밋한다.

## 옛 React Native 앱 코드를 쓰는 것

옛 앱은 2026-11-18에 저장소에서 지웠다(마지막 커밋 `4f9e1d9`, 그때 경로 `app/src/…`). 빛 모델과 그 견줌 자료는 아직 그 코드에서 만든다.

| 파일 | 하는 일 | 만드는 것 |
|---|---|---|
| `gen_shaders.sh` | 옛 커밋의 `app/`을 임시 폴더에 풀고 `rn_light.patch`를 덧댄 뒤, jest로 아래 `dump_*.test.ts`를 돌리고 SkSL을 GLSL로 바꾼 뒤(`sksl_to_glsl.dart`) 낱개 uniform을 vec4 배열 하나로 묶는다(`pack_uniforms.dart`) | `shaders/{grid,bake,lit,book,tab}.frag`, `lib/gen/*`(묶은 자리 표 `packed_uniforms.g.dart` 포함), `assets/bake_case.json`, `test/fixtures/*.json` |
| `rn_light.patch` | Flutter로 옮긴 뒤 고친 빛(조명·스킨 모양·빛 모델·맞추기 값)을 옛 앱 파일에 덧대는 패치 | — |
| `dump_*.test.ts` | 옛 앱 함수 결과를 뽑는 jest 파일(빛 · 배치 · 읽기 · 갈피 · 장정 · 편집 · 잠긴 선반 · QA 예시 · 참고 책장 · DB 구조) | `test/fixtures/*.json`. Flutter 쪽 `test/*_matches_app_test.dart`가 이것과 견준다 |
| `pixcheck.test.ts` | 같은 굽기 입력을 옛 셰이더로 CPU(CanvasKit)에서 구워 자국을 찍는다. 앱 로그 `[flpix]`와 견주어 두 쪽 빛 계산이 같은지 본다 | 콘솔 출력만(손으로 돌림) |

**언제 돌리나**: 빛 식·빛 값·셰이더를 바꿀 때만. 화면 UI만 바꿀 때는 필요 없다.

**바꾸는 법**
1. 저장소 뿌리에서 옛 앱을 두 벌 푼다: `git archive 4f9e1d9 app | tar -x -C <원본>`, 같은 명령으로 `<사본>`. 사본에만 지금 패치를 덧댄다: `cd <사본> && patch -p1 < <저장소>/app/tool/rn_light.patch`.
2. 사본의 빛 파일(`app/src/scene-config/lighting.ts`·`skin.ts`, `app/src/ui/scene-light-sksl.ts`, `app/src/domain/light-model.ts` 등)을 고친다.
3. `<원본>`과 `<사본>`의 차이로 `rn_light.patch`를 다시 만든다(`diff -ru`, 경로는 `a/app/src/…`·`b/app/src/…`). 새 패치가 `<원본>`에 그대로 덧대지는지 `patch -p1 --dry-run`으로 본다.
4. `cd app && bash tool/gen_shaders.sh` (node 22: `NODE_BIN`, Flutter: `FLUTTER_BIN`. 옛 앱 node_modules를 받아 둔 곳이 있으면 `RN_NODE_MODULES=<폴더>`, 없으면 임시 폴더에 `npm ci`).
5. `flutter test`로 견줌 시험을 돌리고, 바뀐 `shaders/`·`lib/gen/`·`assets/bake_case.json`·`test/fixtures/`를 함께 커밋한다.

`bake.frag`가 바뀌면 `lib/gen/bake_shader_hash.g.dart`(굽기 캐시 열쇠)도 바뀌어 기기마다 다음 실행 때 한 번 다시 굽는다. 머리 주석만 바뀌어도 그렇다.

**대체 경로(남은 일)**: `dump_*`가 견주는 함수(배치 · 읽기 · 갈피 · 장정 · 편집 등)는 이미 Dart로 옮겨져 있다(`lib/domain/`, 굽기 · 그리기는 `lib/ui/bake.dart`·`row_bake.dart`·`scene.dart`). 옛 코드에 남은 것은 셰이더 원문을 짜는 생성기(`scene-light-sksl.ts`)와 빛 맞추기 값 계산(`light-model.ts`·`light-calibration.generated.ts` → `lib/gen/`)뿐이다. 이 둘을 Dart로 옮기면 `gen_shaders.sh`·`rn_light.patch`·`dump_*.test.ts`·`pixcheck.test.ts`와 node 의존을 지울 수 있다. 그때 `test/fixtures/*.json`은 지금 값 그대로 고정 자료로 남긴다(Flutter 시험이 계속 견준다). 그전까지는 빛을 바꿀 때만 위 순서로 돌린다.

## Flutter·Python만 쓰는 것

| 파일 | 하는 일 |
|---|---|
| `sksl_to_glsl.dart` | SkSL → Flutter GLSL(`gen_shaders.sh`가 부른다) |
| `pack_uniforms.dart` | 셰이더의 낱개 uniform을 `uniform vec4 uP[N]` 하나로 묶고 자리 표(`lib/gen/packed_uniforms.g.dart`)를 쓴다(`gen_shaders.sh`가 부른다). 아이폰 Impeller Metal은 uniform마다 버퍼 칸 하나를 쓰고 칸은 31개(0~30)까지라, 48칸을 쓰던 벽·판(lit)·책(book) 셰이더가 아이폰에서 만들어지지 않았다(2026-11-25). 이미 묶인 파일은 그대로 둔다 |
| `gen_icons.py`, `gen_ios_icons.py`, `app_icon/` | 앱 아이콘(Android · iOS) |
| `gen_header_clay_icons.py`, `header_art/` | 머리글 입체 아이콘 그림 |
| `make_login_shelf.py`, `login_art/` | 로그인 화면 책장 그림 |
| `soften_share_shelf_shadow.py` | 공유 그림 선반 그림자 다듬기 |
| `lucide_icons/` | 쓰는 lucide 아이콘 원본 SVG(ISC 라이선스) |
| `qa/rn-backup.json` | 옛 앱에서 내보낸 백업 파일(옛 백업 복원 QA용) |

디자인 토큰(시안용 `design-system/tokens.json`·`web/`)은 여기 없다. `test/design_tokens_test.dart`가 만든다(`docs/design/DESIGN.md` 0장).
