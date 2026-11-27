# 책장 한켠 앱 (Flutter)

```bash
flutter pub get
flutter run                          # 서버 붙여 쓰기: --dart-define=SYNC_URL=…
flutter analyze --no-fatal-infos     # 경로에 한글이 있어 분석 서버가 멈추면: dart analyze
flutter test                         # 디자인 토큰 · 옛 앱과 견줌 시험 포함
```

| 폴더 | 담는 것 |
|---|---|
| `lib/domain/` | 서재 값 · 규칙 · 3D 구조 · 빛 계산(화면과 상관없는 순수 계산) |
| `lib/scene_config/` | 빛 · 카메라 · 스킨 값 |
| `lib/db/`, `lib/store/` | 기기 DB와 서재 읽기 · 쓰기 |
| `lib/services/` | 서버 동기화 · 도서 검색 · 사진 등 바깥 연동 |
| `lib/features/` | 화면 |
| `lib/ui/` | 디자인 값(`theme.dart` · `kit.dart`)과 공용 부품, 책장 그리기 |
| `lib/gen/` | 만든 코드(손으로 고치지 않음, `tool/README.md`) |
| `shaders/` | 빛 셰이더(`tool/gen_shaders.sh`가 만든다) |
| `design-system/` | 시안용 디자인 토큰(`test/design_tokens_test.dart`가 만든다) |
| `tool/` | 셰이더 · 견줌 자료 · 아이콘 만드는 도구([설명](tool/README.md)) |

- 화면 디자인 규칙과 '어디를 고치나': [`docs/design/DESIGN.md`](../docs/design/DESIGN.md)
- 작업 규칙(커밋 · 배포): [`AGENTS.md`](../AGENTS.md)
- 코드 주석의 **"지금 앱"·"RN"·"옛 앱"은 이식 당시의 React Native 앱**(2026-11-18에 지움, 마지막 커밋 `4f9e1d9`, 그때 경로 `app/src/…`)을 가리킨다. 지금 `app/`은 이 Flutter 앱이다.
- 셰이더 생성기와 견줌 자료(`tool/gen_shaders.sh`, `tool/dump_*.test.ts`)는 아직 그 옛 코드를 커밋에서 꺼내 쓴다. 빛을 바꿀 때만 돌린다([`tool/README.md`](tool/README.md)).

---

# 이식 기록 (2026-11-13 시작)

옛 앱(React Native + Skia, 당시 `app/`)을 Flutter(당시 `flutter/`, 11-18부터 `app/`)로 옮겼다. 아래는 이식 당시 기록이라 "지금 앱"은 옛 RN 앱이다.

## 왜 옮기나 (11-13 측정 기준, 에뮬 x86_64)

| | 지금(RN) |
|---|---|
| 새로 설치 첫 실행 → 책장 보임 | 21.0초 |
| 다시 켜기 | 18.4초 (굽기는 전부 캐시) |
| 그중 셰이더 컴파일 | 약 15초 ※ 에뮬은 셰이더 디스크 캐시가 없어 매번 컴파일. 실기기 값은 미측정 |
| 책 끌기 | 프레임 92% 지연 |
| QA APK(x86_64) | 114MB (lib 47.7 · res 37.5 · dex 20.9) |

- **셰이더를 빌드할 때 미리 컴파일한다**(impellerc). 지금은 첫 그리기 때 기기에서 컴파일돼 UI 스레드를 막았다.
- **그리기가 UI 스레드 밖**이라 GPU가 오래 걸려도 '응답 없음'이 뜨지 않는다.
- **그리기 엔진이 한 벌**이다(지금은 RN + Skia를 따로 넣어 약 30MB).
- **실행 환경이 하나**다(지금은 JS · 워클릿 · Skia 셋으로 나뉘어 그 경계에서 버그가 났다).

안 바뀌는 것: GPU가 빛을 굽는 계산량. 그래서 **S23에서 한 줄 굽기를 재는 관문**을 지나야 전체 이식을 계속한다.

## 전후 비교 (11-13, 같은 에뮬레이터 x86_64, 같은 양의 굽기)

RN = 지금 앱(c0751c2, QA 측정 빌드) · Flutter = 이 폴더. 줄 6개, 면 110개. 셰이더 식·값은 두 앱이 같다.

| 재는 것 | RN | Flutter |
|---|---|---|
| **줄 6개 굽기(데운 뒤)** | 3.4초 | **0.7~1.0초** |
| **첫 그리기 GPU 준비** | 약 15초 | **4.3~5.8초** |
| 새로 설치 첫 실행 굽기 | 3.4초 | 5~9초(위 GPU 준비 포함) |
| 다시 켜기 굽기 | 0초(디스크 캐시) | **0초(디스크 캐시)** |
| 다시 켜서 책장이 뜰 때까지 | 18.4초 | **5.9초** |
| 구운 값 | — | **같다**(평균·표본 화소가 소수점까지 일치) |
| 앱 크기 | 114MB | 18MB(그림·글꼴·글자 인식이 아직 없어 비교 불가) |

측정 함정: Flutter의 이름 uniform API(`getUniformVec4Array`)는 부를 때마다 슬롯 객체를 **배열 길이의 제곱만큼** 만든다
(`box[160]` 한 번에 160×640개). 면마다 부르면 굽기가 6배 느려진다. 자리 번호(`shaderIndex`)를 프로그램마다 한 번 구해 두고
`setFloat`으로 넣는다(`lib/ui/bake.dart` ShaderSlots). 시간은 그림을 1×1로 한 번 읽어 GPU가 끝난 뒤 잰다(`settle`).

**에뮬레이터는 OpenGL로 돌고 S23은 Vulkan으로 돈다.** 첫 그리기 GPU 준비가 가장 달라질 수 있는 부분이라, 결정은 S23 수치로 한다.

## 옮기는 순서

1. 뼈대 · 상수(`scene_config`, `domain` 상수)
2. 셰이더 생성기(`tool/gen_shaders.sh` → `shaders/*.frag`), 빛 격자 · 굽기부터
3. 굽기 파이프라인(`lib/ui/scene_light.dart`) + 줄 하나 그리기
4. **관문: S23에서 한 줄 굽기 측정.** 지금 앱보다 낫거나 같으면 계속
5. 화면 · 저장소 · 동기화 · 위젯

규칙: 계산과 겉모습은 **먼저 그대로 옮기고**, 개선은 그다음에 한다(차이가 났을 때 이식 실수인지 의도한 변경인지 가릴 수 있게).

## 지금 앱과 다르게 가는 것

- **셰이더 소스는 빌드할 때 만든다.** 지금은 켤 때마다 문자열로 만들어 컴파일했다.
  `bash tool/gen_shaders.sh` → `shaders/*.frag`(저장소에 함께 둔다) → `flutter build`가 미리 컴파일.
- **SkSL → GLSL**: `float2/3/4`→`vec2/3/4`, `half`→`float`, 진입점은 `out vec4 fragColor; void main()`,
  화면 좌표는 `FlutterFragCoord()`, 자식 그림은 `sampler2D` + `texture()`.

## 값의 기준

빛 값은 **커밋된 값**(당시 `git show HEAD:app/src/scene-config/lighting.ts`, 지금은 `git show 4f9e1d9:app/src/scene-config/lighting.ts`)으로 옮긴다.
다른 세션이 11-10부터 미커밋으로 들고 있는 빛 조정(창빛 0.22→0.5 등)은 그 작업이 끝나 커밋되면 그때 반영한다.
