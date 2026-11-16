# 책장 한켠 — 쓰는 법(먼저 읽기)

이 디자인 시스템은 **토큰 전용**입니다. 앱은 Flutter라 `window.ChaekjangDS`에 컴포넌트가 없습니다(0개). 화면은 직접 HTML/JSX로 짓되 색·글자·간격·모서리·그림자는 아래 `--ck-*` 변수만 씁니다. 숫자 색·크기를 새로 적지 않습니다. 화면 글은 한국어, 바탕은 흰색 하나(다크 없음)입니다.

## 준비
`styles.css` 하나를 링크합니다(토큰 + 글꼴 + `html, body` 바탕). 감쌀 공급자(provider)는 없습니다.

## 쓰는 방식 — CSS 변수
- 색: `--ck-ink`(본문 #191F28) · `--ck-ink-soft`(보조) · `--ck-ink-faint` · `--ck-bg` · `--ck-surface`(옅은 회색 면) · `--ck-input` · `--ck-line` · `--ck-section-line` · `--ck-track` · `--ck-accent`(갈색, 주요 버튼·선택에만) · `--ck-accent-pressed` · `--ck-on-accent` · `--ck-danger` · `--ck-star` · `--ck-scrim`. 어두운 읽기 장면 위: `--ck-night-ink` · `--ck-night-ink-soft` · `--ck-night-line`.
- 글자: `font: var(--ck-type-title)` 26/34 Bold · `--ck-type-heading` 21/29 · `--ck-type-section` 19/27 · `--ck-type-row` 18/26 · `--ck-type-row-strong` · `--ck-type-body` 17/27 · `--ck-type-sub` 16/23(색 `--ck-ink-soft`) · `--ck-type-caption` 15/21(색 `--ck-ink-soft`) · `--ck-type-button` 17/24 SemiBold · `--ck-type-label` 16/22 Medium. 갈피 문장·감상 본문은 `font-family: var(--ck-font-reading)`(명조).
- 간격: `--ck-space-page`(화면 좌우 24) · `--ck-space-xs` 4 · `--ck-space-s` 8 · `--ck-space-m` 12 · `--ck-space-l` 16 · `--ck-space-xl` 28 · `--ck-space-xxl` 40 · `--ck-space-row` 56 · `--ck-touch` 44.
- 모서리: `--ck-radius-button` 10 · `--ck-radius-input` 10 · `--ck-radius-choice` 14 · `--ck-radius-sheet` 20 · `--ck-radius-dialog` 18 · `--ck-radius-chip`(알약) · `--ck-radius-tag` 6. 그림자: `--ck-shadow-float` · `--ck-shadow-tab-bar` · `--ck-shadow-bookmark-card`.

## 부품 만드는 법(Flutter `lib/ui/kit.dart`와 같은 치수)
| 부품 | 만드는 법 |
|---|---|
| 주요 버튼 | 높이 `--ck-btn-m`(54, 큰 것 `--ck-btn-l` 60, 작은 것 `--ck-btn-s` 44), 폭 가득, `--ck-radius-button`, 바탕 `--ck-accent`, 글자 `--ck-on-accent` `--ck-type-button`. 화면에 하나만 |
| 보조 버튼 | 흰 바탕, 1px `--ck-line` 테두리, 글자 `--ck-ink`(삭제는 `--ck-danger`) |
| 글자 버튼 | 밑줄 없이 굵은 `--ck-accent`(조심스러운 일은 `--ck-ink-soft`) |
| 칩 | `--ck-surface` 알약, 고르면 `--ck-accent` 채움 + `--ck-on-accent` |
| 안쪽 탭 | 글자만, 고른 탭 `--ck-ink` 굵게 + 글자 폭 갈색 밑줄 3px. 회색 상자 탭은 쓰지 않음 |
| 목록 줄 | 최소 높이 `--ck-space-row`, 줄 사이 선 없음, 오른쪽 꺾쇠 `--ck-ink-faint` |
| 입력칸 | 바탕 `--ck-input`, 테두리 없음, `--ck-radius-input`, 누르면 1px `--ck-accent` 테두리, 이름은 위 `--ck-type-label` |
| 고르는 원 | `--ck-radio` 22: 안 고름 = 1.5px `--ck-line` 빈 원, 고름 = `--ck-accent` 원 + 흰 체크 |
| 스위치 | `--ck-toggle-width`×`--ck-toggle-height`, 손잡이 `--ck-toggle-knob`, 켜면 `--ck-accent` |
| 아래 시트 | 흰 바탕, 위 모서리 `--ck-radius-sheet`, 뒤 막 `--ck-scrim`, 위 가운데 36×4 `--ck-track` 손잡이, 제목 `--ck-type-heading` |
| 확인창 | `--ck-radius-dialog`, 버튼은 세로로 쌓기 |
| 하단 탭 바 | 양옆 `--ck-tabbar-side`, 높이 `--ck-tabbar-height` 흰 알약 + `--ck-shadow-tab-bar`. 아이콘만 5칸: 책장·내 책·읽기·기록·통계. 고른 칸 `--ck-tab-ink` 채움, 나머지 `--ck-tab-ink-soft` 윤곽 |
| 갈피 카드 | 흰 종이 `--ck-radius-bookmark-card` + `--ck-shadow-bookmark-card`, 문장은 `--ck-font-reading`, 위 오른쪽에 반투명 종이 테이프 |

## 규칙
- 흰 화면 안에 회색 상자를 두지 않습니다(입력칸만 예외). 묶음은 여백과 `--ck-section-line` 띠로 나눕니다.
- 화면 제목은 왼쪽 `--ck-type-title`, 화면 좌우 여백 `--ck-space-page`.
- 누르는 자리는 `--ck-touch` 이상. 눌림은 투명도 `--ck-press-opacity`.
- 아이콘은 lucide 선 아이콘(굵기 1.6, 22px).
- 자세한 위젯 목록은 `guidelines/components.md`, 피해야 할 어긋남은 `guidelines/drift.md`.

```html
<section style="padding: 0 var(--ck-space-page)">
  <h1 style="font: var(--ck-type-title); color: var(--ck-ink)">내 책</h1>
  <p style="font: var(--ck-type-caption); color: var(--ck-ink-soft)">책 5권</p>
  <button style="width:100%; height: var(--ck-btn-m); border:0; border-radius: var(--ck-radius-button);
    background: var(--ck-accent); color: var(--ck-on-accent); font: var(--ck-type-button)">책 추가</button>
</section>
```
