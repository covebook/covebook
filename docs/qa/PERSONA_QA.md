# 페르소나 QA 공통 규칙

페르소나 에이전트(`.claude/agents/qa-*.md`)가 시작할 때 이 문서를 먼저 읽는다.
실행은 `/persona-qa`(`.claude/commands/persona-qa.md`)가 맡는다.

## 0. 목적

정해진 시험 대본을 도는 것이 아니다. 성격이 다른 사용자가 되어 책장 한켠을 **그 사람처럼** 써 보고,
그 사람이 겪을 문제(크래시·기록 손실·헷갈림·느림·안 보임)를 찾는다.
행동은 페르소나처럼, 관찰과 기록은 QA처럼 한다.

## 1. 대상과 안전 규칙 (반드시 지킴)

- 대상 앱: `PKG=app.covebook.qa`(시험 설치). 실행 명령이 다른 값을 넘기면 그 값을 쓴다.
- **사용자 실제 앱 `app.covebook`·`com.chaekjang.app`에는 아무것도 하지 않는다.** 실행·`pm clear`·삭제·데이터 접근 모두 금지.
  `pm clear`·`am force-stop`·`uninstall`은 항상 `$PKG`에만 쓴다.
- 모든 adb 명령에 `-s $SERIAL`을 붙인다. 여러 에뮬이 동시에 돌 수 있다.
- 코드는 고치지 않는다. 원인을 짐작하면 '추정'이라고 적는다.
- 실제 결제·실제 소셜 로그인·실제 SNS 게시는 하지 않는다. 공유 시트가 열리는 데까지만 본다.
- 바꾼 기기 설정은 끝날 때 반드시 되돌린다(7절 원복 목록).
- 해 보지 못한 것은 '시험 못 함'과 이유로 적는다. 결과를 지어내지 않는다.

## 2. 화면 읽기

1. 먼저 화면 구조를 본다. 글자와 버튼 위치를 싸게 얻는다.
   ```bash
   adb -s $SERIAL shell uiautomator dump /sdcard/ui.xml >/dev/null && adb -s $SERIAL pull /sdcard/ui.xml "$RUN/ui.xml" >/dev/null
   grep -o 'text="[^"]*"\|content-desc="[^"]*"\|bounds="[^"]*"' "$RUN/ui.xml"
   ```
   - 3D 책장은 캔버스라 그림은 안 잡히지만, **책마다 보이지 않는 접근성 칸**(content-desc에 책 제목)이 있어서 책 위치를 bounds로 얻을 수 있다.
   - bounds `[x1,y1][x2,y2]`의 가운데를 누른다.
2. 그림이 중요할 때만 스크린샷을 찍어 Read로 본다(장정·카드·잘림·겹침 확인, 캔버스 안).
   ```bash
   adb -s $SERIAL exec-out screencap -p > "$RUN/shots/NN-설명.png"
   ```
   파일 이름은 순번 + 짧은 설명. 발견마다 증거 스크린샷을 남긴다.

## 3. 조작

| 하고 싶은 것 | 명령 |
|---|---|
| 누르기 | `adb -s $SERIAL shell input tap X Y` |
| 길게 누르기 | `adb -s $SERIAL shell input swipe X Y X Y 900` |
| 끌기(길게 눌러 옮기기) | `adb -s $SERIAL shell input draganddrop X1 Y1 X2 Y2 2500` · 안 되면 `input motionevent DOWN X1 Y1; sleep 1; input motionevent MOVE ...; input motionevent UP X2 Y2` |
| 스크롤 | `adb -s $SERIAL shell input swipe 540 1700 540 700 300` |
| 뒤로 · 홈 | `adb -s $SERIAL shell input keyevent KEYCODE_BACK` · `KEYCODE_HOME` |
| 영어·숫자 입력 | `adb -s $SERIAL shell input text 'Normal%sPeople'`(%s = 띄어쓰기) |
| 한글 입력 | ADBKeyBoard로 보낸다(아래) |
| 앱 켜기 | `adb -s $SERIAL shell monkey -p $PKG -c android.intent.category.LAUNCHER 1` |
| 앱 강제 종료 | `adb -s $SERIAL shell am force-stop $PKG` |
| 새로 설치한 상태로 | `adb -s $SERIAL shell pm clear $PKG` |

한글(입력칸을 먼저 누른 뒤):
```bash
adb -s $SERIAL shell am broadcast -a ADB_INPUT_B64 --es msg "$(printf '%s' '데미안' | base64)"
# 안 되면: adb -s $SERIAL shell am broadcast -a ADB_INPUT_TEXT --es msg '데미안'
```

- 두 손가락 동작(연도 책장 모아 보기)은 adb로 못 한다. '시험 못 함'으로 적는다.
- ADBKeyBoard가 켜져 있으면 화면 키보드가 안 뜬다. "키보드가 입력칸을 가리는지"를 볼 때만
  `adb -s $SERIAL shell ime reset`으로 기본 키보드로 바꾸고, 끝나면 다시 `ime set com.android.adbkeyboard/.AdbIME`.
- 바코드 스캔·실제 책 촬영은 에뮬 카메라로 하기 어렵다. 해 보고 안 되면 '실기기 필요'로 적는다.

## 4. 환경 바꾸기 (페르소나가 시킬 때만)

| 상황 | 켜기 | 되돌리기 |
|---|---|---|
| 인터넷 끊김 | `shell svc wifi disable; shell svc data disable` | `enable` |
| 전화가 옴 | `emu gsm call 01012345678` (받기 `emu gsm accept 01012345678`) | `emu gsm cancel 01012345678` |
| 화면 끄기·켜기 | `shell input keyevent KEYCODE_POWER` · `KEYCODE_WAKEUP` 후 `shell wm dismiss-keyguard` | — |
| 잠자기(Doze) | `shell dumpsys deviceidle force-idle` | `shell dumpsys deviceidle unforce` |
| 글자 크게 | `shell settings put system font_scale 1.5` | `1.0` |
| 작은 화면(360×640dp) | `shell wm size 720x1280; shell wm density 320` | `shell wm size reset; shell wm density reset` |
| 동작 줄이기 | `shell settings put global window_animation_scale 0`(transition·animator도) | 셋 다 `1` |

(모두 `adb -s $SERIAL` 뒤에 붙인다.)

## 5. 크래시·성능 감시

- 시작할 때 `adb -s $SERIAL logcat -c`.
- 목표 하나가 끝날 때마다 확인:
  ```bash
  adb -s $SERIAL shell pidof $PKG || echo "앱 프로세스 없음"
  adb -s $SERIAL logcat -d -b crash | tail -40
  adb -s $SERIAL logcat -d | grep -E "FATAL EXCEPTION|ANR in|ReactNativeJS.*(Error|Warning)|already has a parent|E/flutter" | tail -20
  ```
  잡힌 줄은 발견의 증거로 그대로 붙인다.
- 끌기·스크롤 매끄러움: 동작 전 `shell dumpsys gfxinfo $PKG reset`, 동작 뒤 `shell dumpsys gfxinfo $PKG | grep -E "Total frames|Janky frames|90th|99th"`.
- 시간 재기: 동작 직전·직후 `date +%s.%N`. 화면이 바뀔 때까지 재려면 1초 간격으로 화면 구조나 스크린샷을 확인한다.

## 6. 페르소나로 움직이는 법

- 그 사람이 읽지 않을 안내문은 읽지 않은 채로 행동한다. 다만 무엇을 건너뛰었는지는 적는다.
- 길이 안 보이면 그 사람이 할 법한 행동(아무거나 누르기, 뒤로 가기, 포기)을 한다. **헷갈린 것 자체가 발견이다.**
- 같은 곳에서 세 번 막히면 '막힘'으로 적고 다음 목표로 넘어간다.
- 한도: 조작 약 100번, 스크린샷 약 40장. 넘을 것 같으면 남은 목표를 '시간 부족'으로 적고 마친다.

## 7. 끝내기

1. 바꾼 설정 원복: 인터넷, 글자 크기, 화면 크기·밀도, 동작 배율, Doze, 키보드(`ime set com.android.adbkeyboard/.AdbIME`으로 처음 상태). 각각 확인 명령으로 되돌아갔는지 본다.
2. `$RUN/report.md`를 아래 형식으로 쓴다.

```markdown
# <페르소나 이름> — <날짜> · 빌드 <versionName> (<git 짧은 해시>)

## 한 줄 평 (페르소나 말투)
"…"

## 계속 쓸까?
쓴다 / 고민 / 지운다 — 이유 한두 줄

## 발견
### F1. <한 줄 제목>
- 심각도: 치명(크래시·기록 손실) / 높음(핵심 흐름 막힘) / 보통(우회 가능) / 낮음(다듬기)
- 종류: 크래시 · 데이터 · 기능 · 헷갈림 · 성능 · 접근성 · 문구
- 재현: 1) … 2) … 3) …
- 기대 / 실제: … / …
- 증거: shots/07-…png, 로그 줄
- 재현 횟수: 3번 중 3번
- 이 사람에게 미치는 영향: …

## 잘된 것
- …

## 시험 못 함
- <항목> — <이유>

## 원복 확인
- 글자 크기 1.0 ✅ …
```
