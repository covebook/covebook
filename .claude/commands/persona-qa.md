---
description: 성격이 다른 가상 사용자(페르소나)들이 에뮬레이터에서 책장 한켠을 써 보고 QA 보고서를 낸다
argument-hint: "[core|all|페르소나 이름...] [pkg=app.covebook.qa]"
---

# /persona-qa

인자: `$ARGUMENTS`

## 페르소나

| 짧은 이름 | 에이전트 | 묶음 |
|---|---|---|
| bookstagrammer | qa-bookstagrammer | core |
| collector | qa-collector | core |
| night-reader | qa-night-reader | core |
| button-masher | qa-button-masher | core |
| transcriber | qa-transcriber | more |
| data-worrier | qa-data-worrier | more |
| large-text | qa-large-text | more |

- 인자가 없으면 `core` 4명. `all`이면 7명. 이름을 주면 그 사람들만.
- `pkg=`가 있으면 그 패키지, 없으면 `app.covebook.qa`.

## 1. 준비 점검 (하나라도 안 되면 멈추고 사람에게 할 일을 알려 준다)

1. `docs/qa/PERSONA_QA.md`를 읽는다. 안전 규칙(실제 앱 `app.covebook`·`com.chaekjang.app`은 건드리지 않음)을 이 실행 전체에 적용한다.
2. `adb devices`로 켜진 에뮬을 찾는다. 없으면 멈춘다.
3. 각 에뮬에 `$PKG`가 깔려 있는지 본다(`adb -s S shell pm list packages | grep -x "package:$PKG"`).
   없으면 멈추고 알린다: "실제 앱과 다른 패키지 이름의 시험 빌드가 필요하다. 실제 앱에 돌리면 `pm clear`로 내 서재가 지워진다."
4. ADBKeyBoard(`com.android.adbkeyboard`)가 있으면 `ime enable`·`ime set com.android.adbkeyboard/.AdbIME`.
   없으면 사람에게 설치를 부탁하되(github.com/senzhk/ADBKeyBoard), 기다리지 말고 영어·숫자 입력만으로 진행하고 보고서에 '한글 입력 없이 진행'이라고 적는다.
5. 빌드 정보: `adb -s S shell dumpsys package $PKG | grep versionName`, `git rev-parse --short HEAD`.
6. `.gitignore`에 `.qa-runs/`가 없으면 추가한다.
7. `docs/qa/fixtures/`에 사진이 없으면 transcriber가 합성 사진을 쓴다는 것만 알린다(멈추지 않음).

## 2. 실행

- 결과 폴더: `RUN_ROOT=.qa-runs/<YYYY-MM-DD-HHMM>`, 페르소나마다 `$RUN_ROOT/<짧은 이름>/`(안에 `shots/`).
- **에뮬이 1대면 한 명씩 차례로** 돌린다(같은 화면을 동시에 만지면 결과가 섞인다). 순서는 표 순서, button-masher는 묶음의 마지막.
- 에뮬이 여러 대면 대수만큼 동시에, 페르소나마다 다른 SERIAL을 준다.
- 각 페르소나 에이전트에게 이렇게 넘긴다:

  ```
  SERIAL=<serial> PKG=<pkg> RUN=<결과 폴더 절대 경로>
  빌드: <versionName> (<git 해시>), 기기: <에뮬 이름·해상도>
  docs/qa/PERSONA_QA.md와 네 페르소나 파일대로 시험하고 $RUN/report.md를 써라.
  ```
- 한 페르소나가 끝나면 그 사람이 바꾼 설정이 원복됐는지(`font_scale`, `wm size`, `wm density`, 동작 배율 셋, wifi·data, deviceidle) 확인하고 다음 사람을 시작한다.

## 3. 합친 보고서

모든 `report.md`를 읽고 `docs/REPORT-<YYYY-MM-DD>-persona-qa.md`를 쓴다. 이 저장소의 다른 REPORT 문서처럼 짧은 한국어로.

1. **머리**: 날짜, 빌드, 기기, 돌린 페르소나, 걸린 시간. 원복 실패가 있으면 맨 위에 경고.
2. **요약 표**: 페르소나 | 계속 쓸까 | 치명 | 높음 | 보통 | 낮음.
3. **고칠 것 (최대 10개)**: 같은 문제를 여러 사람이 겪었으면 하나로 묶고 "N명이 겪음". 순서는 심각도 → 겪은 사람 수 → 핵심 흐름(첫 실행·책 추가·책장·읽기·갈피)인지. 각 항목에 재현 단계 요약과 증거 경로.
4. **헷갈린 곳**: 크래시는 아니지만 사람들이 막히거나 잘못 이해한 곳. 페르소나의 말을 그대로.
5. **잘된 것**.
6. **실기기에서 확인할 것**: 각 보고서의 '시험 못 함'을 모아 중복 없이.
7. **페르소나 한 줄 평** 모음.

증거 중 고칠 것 상위 항목의 스크린샷만 `docs/screenshots/persona-qa-<YYYY-MM-DD>/`로 복사해 보고서에서 가리킨다. 나머지는 `.qa-runs/`에 둔다.

## 4. 마무리

- 코드는 고치지 않는다.
- 커밋은 AGENTS.md 규칙대로 하되, 합친 보고서와 복사한 스크린샷, `.gitignore` 변경만. `.qa-runs/`는 커밋하지 않는다.
- 사람에게는 요약 표, 고칠 것 상위 5개, 보고서 경로만 짧게 알린다.
