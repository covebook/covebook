# 책장 한켠 — 쓰는 법(먼저 읽기)

이 디자인 시스템은 **토큰 전용**입니다. 앱은 Flutter라 `window.ChaekjangDS`에 컴포넌트가 없습니다(0개). 화면은 직접 HTML/JSX로 짓되 색·글자·간격·모서리·그림자·크기는 `--ck-*` 변수와 `.ck-type-*` class만 씁니다. 숫자 색·크기를 새로 적지 않습니다. 화면 글은 한국어, 바탕은 흰색 하나(다크 없음)입니다.

값은 모두 Flutter 앱(`app/lib/ui/theme.dart`·`kit.dart`)에서 만들어집니다(`app/test/design_tokens_test.dart`). 어떤 역할을 언제 쓰는지는 `guidelines/DESIGN.md`(앱 디자인 기준)에 있습니다. 이 글에는 숫자를 적지 않습니다: 숫자는 `styles.css`가 원본입니다.

## 준비
`styles.css` 하나를 링크합니다(토큰 + 글꼴 + 역할 글자 class + `html, body` 바탕). 감쌀 공급자(provider)는 없습니다.

## 글자
- 글자는 역할 class로: `<p class="ck-type-sub">`. class가 글꼴·크기·줄 높이·색·숫자 폭을 한꺼번에 맞춥니다. 변수만 쓸 때는 `font: var(--ck-type-<역할>)`에 색을 따로 줍니다.
- 화면 틀: `title`(탭 첫 화면 큰 제목) · `nav-title`(밀어 넣은 화면 위 줄) · `heading`(시트·창 제목) · `section`(구역 제목) · `count`(구역 제목 옆 개수).
- 줄과 글: `row`(목록 줄 이름) · `row-strong` · `body` · `sub`(보조) · `caption`(작은 보조) · `micro`.
- 책: `book-title`(책 한 줄) · `book-author`(작가 줄) · `book-note`(한줄평 셋째 줄) · `review`(평가 탭 한줄평) · `book-head-title`(책 정보 머리) · `book-feature-title`(읽기 탭 큰 카드) · `book-card-title`(독서 끝 연결된 책) · `book-grid-title`·`book-grid-author`(내 책 격자).
- 기록: `record-day`('11월 17일') · `record-range`('오후 9:05-9:30') · `record-duration`('38분').
- 단추: `button`(보통·큰 단추) · `button-small`(작은 단추) · `link`(글자 단추).
- 숫자: `display` · `figure` · `clock` · `timer` · `score` · `wheel`.
- 갈피 문장·감상 본문은 `quote` · `reading`(명조).

## 색·간격·모서리
- 색: `--ck-ink`(본문) · `--ck-ink-soft`(보조, 머리줄 아이콘·꺾쇠) · `--ck-ink-faint` · `--ck-bg` · `--ck-surface`(옅은 회색 면) · `--ck-input` · `--ck-line` · `--ck-section-line` · `--ck-track` · `--ck-meta-bar`(정보 사이 세로줄) · `--ck-accent`(갈색, 주요 단추·고른 것에만) · `--ck-accent-pressed` · `--ck-on-accent` · `--ck-danger` · `--ck-star` · `--ck-scrim`. 어두운 읽기 장면 위: `--ck-night-*`.
- 간격: `--ck-space-page`(화면 좌우) · `--ck-space-xs`·`s`·`m`·`l`·`xl`·`xxl` · `--ck-space-block`(한 화면 구역 사이) · `--ck-space-dense`(촘촘한 기록 줄) · `--ck-touch`(누르는 자리 최소).
- 모서리: `--ck-radius-button` · `input` · `card` · `choice` · `segmented`(전환 칸 바깥) · `segment`(고른 칸) · `sheet` · `dialog` · `tag` · `pill` · `cover`.
- 그림자: `--ck-shadow-float` · `--ck-shadow-tab-bar` · `--ck-shadow-segmented-thumb` · `--ck-shadow-bookmark-card`.

## 부품 만드는 법(Flutter `kit.dart`와 같은 치수)
| 부품 | 만드는 법 |
|---|---|
| 주요 단추 | 높이 `--ck-btn-l`(화면 아래 주요·시트 안) · `--ck-btn-m`(카드·창 안) · `--ck-btn-s`(줄 안), `--ck-radius-button`, 바탕 `--ck-accent`, 글자 `.ck-type-button` + `--ck-on-accent`. 한 화면에 하나 |
| 보조 단추 | 흰 바탕, 1px `--ck-line` 테두리, 글자 `--ck-ink`(삭제는 `--ck-danger`) |
| 글자 단추 | `.ck-type-link`, 밑줄 없음. 화면을 끝내는 '취소'·'완료'는 `--ck-ink`, 다른 곳으로 가는 보조는 `--ck-ink-soft` |
| 머리줄 아이콘 | lucide 선 아이콘 `--ck-icon`, 굵기 `--ck-icon-stroke`, 색 `--ck-ink-soft`, 누르는 자리 `--ck-touch` |
| 목록 줄 | 이름 `.ck-type-row`, 값 `.ck-type-sub`, 줄 사이 선 없음, 다른 화면으로 넘어가는 줄만 오른쪽 꺾쇠 `--ck-icon-chevron` `--ck-ink-soft` |
| 책 한 줄 | 표지 폭 `--ck-cover-row`(고르기·기록) · `--ck-cover-result`(검색 결과·감상) · `--ck-cover-list`(내 책 목록), 표지와 글 사이 `--ck-space-l`, 제목 `.ck-type-book-title`, 작가 `.ck-type-book-author`, 셋째 줄 `.ck-type-book-note` |
| 입력칸 | 높이 `--ck-field`, 바탕 `--ck-input`, 테두리 없음, `--ck-radius-input`, 누르면 1px `--ck-accent` 테두리 |
| 검색칸 | 높이 `--ck-search`, 바탕 `--ck-input` |
| 전환 칸 | 회색 칸 `--ck-segmented-height` `--ck-surface` `--ck-radius-segmented`, 고른 칸 높이 `--ck-segment` 흰 바탕 `--ck-radius-segment` + `--ck-shadow-segmented-thumb` |
| 안쪽 탭(내 책·기록) | 글자만, 고른 탭 `--ck-ink` 굵게 + 갈색 밑줄 |
| 고르는 원 | `--ck-radio`: 안 고름 = 옅은 테두리 빈 원, 고름 = `--ck-accent` 원 + 흰 체크 |
| 스위치 | `--ck-toggle-width`×`--ck-toggle-height`, 손잡이 `--ck-toggle-knob`, 켜면 `--ck-accent` |
| 아래 시트 | 흰 바탕, 위 모서리 `--ck-radius-sheet`, 뒤 막 `--ck-scrim`, 위 가운데 `--ck-track` 손잡이, 제목 `.ck-type-heading`. '닫기' 단추 없음 |
| 확인창 | `--ck-radius-dialog` |
| 하단 탭 바 | 양옆 `--ck-tabbar-side`, 높이 `--ck-tabbar-height` 흰 알약 + `--ck-shadow-tab-bar`, 아이콘 `--ck-icon-tab-bar`. 5칸: 책장·내 책·읽기·기록·통계. 고른 칸 `--ck-tab-ink` 채움, 나머지 `--ck-tab-ink-soft` |

## 규칙
- 흰 화면 안에 회색 상자를 두지 않습니다(입력칸·전환 칸만 예외). 상자가 꼭 필요하면 1px `--ck-line` 테두리 상자.
- 누르는 자리는 `--ck-touch` 이상. 눌림은 투명도 `--ck-press-opacity`, 꺼짐은 `--ck-disabled-opacity`.
- 위 줄·아래 단추는 내용과 함께 스크롤합니다(고정 막대 없음).

```html
<section style="padding: 0 var(--ck-space-page)">
  <h1 class="ck-type-title">내 책</h1>
  <p class="ck-type-caption">책 5권</p>
  <button class="ck-type-button" style="width:100%; height: var(--ck-btn-l); border:0; border-radius: var(--ck-radius-button);
    background: var(--ck-accent); color: var(--ck-on-accent)">책 추가</button>
</section>
```
