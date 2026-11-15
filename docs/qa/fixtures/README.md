# 페르소나 QA 시험 사진

transcriber(필사러)와 collector(장서가)가 쓴다. 파일 이름은 영어로 한다(에뮬 사진 목록에 안 뜨는 일을 줄이려고).
글자 인식용 사진은 **같은 이름의 `.txt`에 정답 글**을 함께 둔다. 정답이 있어야 틀린 글자 수를 셀 수 있다.

| 파일 | 내용 | 정답 |
|---|---|---|
| `prose-ko.jpg` | 한국 소설 한 페이지, 밝은 곳에서 정면 | `prose-ko.txt` |
| `poem-ko.jpg` | 연 구분이 있는 시 한 편 | `poem-ko.txt`(줄바꿈·빈 줄 그대로) |
| `blurry-ko.jpg` | 살짝 흔들린 산문 페이지 | `blurry-ko.txt` |
| `tilted-ko.jpg` | 20°쯤 기울어지고 손가락 그림자가 진 페이지 | `tilted-ko.txt` |
| `english.jpg` | 영어 원서 한 페이지 | `english.txt` |
| `cover-1.jpg` ~ `cover-3.jpg` | 책 표지 정면 사진(표지 사진으로 책 찾기) | 없음(제목은 파일 옆 `cover-N.title`) |

- 산문과 시 두 장만이라도 실제 사진이면 좋다. 나머지는 없으면 에이전트가 `app/assets/fonts/NotoSerifKR-Regular.otf`로 합성 사진을 만든다(보고서에 '합성'으로 표시).
- 사진은 긴 변 2000px 이하로 줄여서 둔다.
- 사진이 크면 커밋하지 말고 `.gitignore`에 `docs/qa/fixtures/*.jpg`를 넣어도 된다.
