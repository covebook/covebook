# 공통 위젯 — 책장 한켠 Flutter (2026-11-16, a7c27f7)

색·글자·간격 값은 `tokens.json`에 있습니다. 공통 위젯은 대부분 `lib/ui/kit.dart`에 있습니다. 새 화면은 이 위젯과 `AppColors`·`AppType`만 씁니다.

## 기본 조작

| 위젯 | 위치 | 하는 일 | 변형 | 상태 |
|---|---|---|---|---|
| `Btn` | lib/ui/kit.dart:332 | 버튼 | `kind`: primary(갈색 채움·흰 글자, 화면에 하나) · secondary(흰 바탕+회색 선) · danger(흰 바탕+선, 빨간 글자) · ghost(바탕·선 없이 글자만). `size`: l 52 · m 48 · s 40(2026-11-18 시안에 맞춰 낮춤, 누르는 자리는 48 이상). `icon` 앞 아이콘 | `disabled`(회색), `busy`(돌림 표시, 누르기 막음) |
| `IconBtn` | kit.dart | 아이콘 단추(누르는 자리 48) | `circle`(둥근 바탕) | `disabled` |
| `TextLink` | kit.dart:1551 | 글자 버튼(밑줄 없음) | 기본 굵은 갈색 = 이어서 할 일, `soft` 회색 = 조심스러운 일, `start` 왼쪽 정렬 | `disabled` |
| `Pressable` | kit.dart:57 | 바탕 없는 누를 것(글자·아이콘·목록 줄) | `pressedOpacity`(기본 0.55) | `disabled` |
| `AppChip` | kit.dart:448 | 칩(옅은 회색 알약) | `color`면 앞에 색 점 | `on`(갈색 채움·흰 글자) |
| `Toggle` | kit.dart:1589 | 스위치 50×30, 손잡이 24(직접 그림) | — | `value` 켬/끔 |
| `RadioMark` | kit.dart:1038 | 고르는 원 22(빈 원 / 갈색 원+흰 체크) | `size` | `on` |
| `Choice` | kit.dart:1230 | 고르는 블록(분위기·목표 시간), 모서리 14 | `compact`, `sub`, `child`(그림 칸) | `selected`(갈색 테두리+체크) |
| `Stars` | kit.dart:1657 | 별점 1~5(같은 별 다시 누르면 지움) | `size`, `color` | `onChange` 없으면 보기 전용 |
| `AppSlider` | kit.dart:1324 | 막대 조절(소리 크기) | `night`(어두운 장면 위 크림색) | `dim`(값은 두고 회색), 끄는 중 `onChange`, 뗄 때 `onCommit` |

## 입력

| 위젯 | 위치 | 하는 일 | 변형 | 상태 |
|---|---|---|---|---|
| `Field` | kit.dart:1422 | 입력칸(회색 바탕, 누르면 갈색 테두리). 이름 위, 단위는 칸 안 오른쪽 | `multiline`, `number`, `unit`, `minHeight`, `placeholder` | `hint`(아래 도움말), `error`(빨간 글자) |
| `SelectField` | kit.dart:1507 | 고르는 칸(누르면 시트·화면) | `sub` | `disabled` |
| `SearchField` | kit.dart:1094 | 검색창(돋보기·지우기) | `placeholder`, `autofocus` | `busy` |
| `DateField` / `showDatePickerSheet()` | kit.dart:1696 / 1717 | 날짜 칸 → 한 달 달력 시트 | `min`·`max`(고를 수 없는 날 흐림), `clearable` | `disabled` |
| `TimeField` | kit.dart:1824 | 시각 칸 → 시·분 돌림 목록 시트 | — | — |
| `showMinutesSheet()` | kit.dart:1892 | 걸리는 시간(0~5시간·5분 단위) | `initial` | 0분은 5분으로 |

## 목록·구획

| 위젯 | 위치 | 하는 일 | 변형 | 상태 |
|---|---|---|---|---|
| `Screen` | kit.dart:104 | 화면 틀(머리줄·뒤로·내용·아래 고정 단추) | 큰 왼쪽 제목 / `back: false` / `footer` | — |
| `H2` | kit.dart:319 | 구역 제목 | `first`(위 여백 없음) | — |
| `ListItem` | kit.dart | 목록 한 줄(이름·설명·값·꺾쇠). **모든 목록 줄 높이 50**(위아래 12, 설명 있으면 14) | `icon`, `right`, `chevron`, `danger` | `selected` |
| `SectionHead` | kit.dart | 한 화면 안 구역 머리줄: 제목(section 19) · 옆 회색 개수('감상 1개') · 오른쪽 글자 단추(sub 16, 화살표 선택). 높이 30 | 책 정보 평가·내 기록 | — |
| `OutlineBox` | kit.dart | 테두리 상자(흰 바탕 · line · 둥근 12 · 안쪽 18/14) | 읽은 기간 카드, 통계 평균 카드 | — |
| `ListGroup` | kit.dart:778 | 목록 묶음(줄 사이 선 없음) | `title`(작은 회색) | — |
| `SectionBand` | kit.dart:794 | 묶음 사이 화면 끝까지 1dp 선 | — | — |
| `AppDivider` | kit.dart:862 | 구분선 | — | — |
| `Bleed` | kit.dart:813 | 내용 폭 밖으로 넓혀 화면 끝까지 | `by` | — |
| `PullUp` | kit.dart:1200 | 음수 위 여백(위로 당겨 그림) | `dy` | — |
| `Empty` | kit.dart:498 | 빈 화면(제목·설명·행동 하나) | `actionKind` | — |
| `Loading` | kit.dart:525 | 불러오는 중 | `label` | — |
| `BrandFooter` | kit.dart:1638 | 맨 아래 '— 책장 한켠' | — | — |

## 탭·거르기

| 위젯 | 위치 | 하는 일 | 쓰는 곳 | 상태 |
|---|---|---|---|---|
| `Tabs` | kit.dart:923 | 밑줄 글자 탭(고른 칸만 굵게 + 짧은 갈색 밑줄 3) | 내 책 상태, 기록 갈피/감상, 커뮤니티(`fill`) | `fill`: 칸을 똑같이 나눔 + 아래 얇은 선 |
| `Segmented` | kit.dart:675 | 회색 칸(높이 44) 안 고른 칸만 흰 바탕 | 책 상세 3탭, 통계 캘린더/분석, 갈피 공유 모양 | — |
| `FilterIcon` | kit.dart:989 | 필터 아이콘 → 필터 시트 | 내 책, 기록 | `active`(갈색 점) |
| `FilterButton` | kit.dart:723 | 거르기 단추(회색 알약 / `plain` 글자+꺾쇠) | 통계 '모든 책 ˅' | `active`(갈색) |
| `FilterGroup` | kit.dart:1015 | 필터 시트 묶음(진한 이름, 위 선) | 필터 시트 | `first` |
| `FilterOption` | kit.dart:1058 | 필터 줄(오른쪽 `RadioMark`) | 필터 시트 | `selected`, `chevron`(다른 시트로), `right`(스위치 등) |
| `SheetLabel` | kit.dart | 시트 안 묶음 이름('정렬' · '유형', rowStrong 18, 아래 12) | 내 책·갈피 필터 | — |
| `ChoiceBox` | kit.dart | 고르는 칸(테두리 상자 48, 고르면 진한 테두리 + 모서리 체크) | 갈피 유형, 내 책 정렬, 완독한 해 | `on` |
| `FilterToggleRow` | kit.dart | 켜고 끄는 줄(굵은 이름 + 회색 개수 + 스위치, 줄 어디를 눌러도) | 책장에 없는 책만, 아껴둔 갈피만 | `value` |

> 같은 '안쪽 메뉴'에 `Tabs`와 `Segmented` 두 모양이 섞여 있습니다(drift.md 7).

## 시트·확인창

| 위젯 | 위치 | 하는 일 | 변형 | 상태 |
|---|---|---|---|---|
| `showSheet()` | kit.dart:870 | 아래 시트(모서리 20, 손잡이, 제목·설명) | `scroll`, `maxHeight`(화면 비율), `fit`, 폭 상한 560 | 뒤 막 `scrim` |
| `appAlert()` · `AlertButton` | lib/ui/alert.dart:21 · :13 | 확인창(모서리 18) | 버튼 `AlertStyle`: normal · cancel · destructive. `stacked`(세로 쌓기) | `cancelable` |

## 아이콘·그림

| 위젯 | 위치 | 하는 일 | 변형 |
|---|---|---|---|
| `LucideIcon` | kit.dart:36 | 선 아이콘(lucide, 기본 22·굵기 1.6). 이름은 `lib/gen/lucide.g.dart`에 있는 것만(없으면 X로 보임) | `size`, `color`, `stroke`, `fill` |
| 하단 탭 아이콘 | lib/ui/tab_icons.dart | 책장·내 책·읽기·기록(갈피)·통계(달력) SVG, 굵기 2.4 | 안 고름 = 회색 윤곽, 고름 = 검정으로 속이 참 |
| 책장 머리 아이콘 | assets/header/*.png · home_screen.dart `_Header`(:1636) | 꾸미기·추가·프로필(회색 점토 입체 그림, 1x·2x·3x) | 프로필은 `tool/gen_profile_icon.py`로 생성 |
| `RealCover` | kit.dart:549 | 실제 표지(없으면 책 색 대체 표지, 명조 제목) | `ratio`(기본 0.68) |
| `CoverImage` · `LinkedCover` | lib/features/stats/stats_widgets.dart:21 · :60 | 표지 그림(크기별 주소 차례로) · 책 id로 표지 | `radius` |
| `BookVisual` | lib/ui/book_visual.dart:26 | 앞에서 본 책(판형 비율 + 밑판·그림자·광택) | `uniform`(모든 책을 같은 128×188 틀로) |
| `StandaloneBook` · `RotatableBook` | lib/ui/standalone_book.dart:106 · :144 | 선반 밖 3D 책 한 권 · 돌려 보는 책 | `pose`, `initialSpin` |
| `EngravedYear` | lib/ui/engraved_year.dart:26 | 새긴 듯한 연도 글자(책장 머리 '2026') | `header` |

## 기능 위젯(화면 여러 곳에서 다시 씀)

| 위젯 | 위치 | 하는 일 | 변형 · 상태 |
|---|---|---|---|
| `BookmarkCard` | lib/features/bookmark/bookmark_card.dart:83 | 갈피 카드(종이·테이프·뒷종이·표지 출처) | `compact`(목록), `showMemo`, `saved`·`onToggleSaved`(아껴두기). 사진 갈피면 `PhotoPlate` |
| `BookmarkPaper` · `BookmarkTape` | bookmark_paper.dart:112 · bookmark_tape.dart:122 | 종이 결 · 테이프 그림 | `kind`(흰 종이/색 종이), `seed` |
| `BoardCard` | lib/features/bookmark/board_card.dart:27 | 갈피 보드 위 카드 | 기울기·테이프 자리 |
| `EssayRow` | lib/features/record/essay_screens.dart:36 | 긴 감상 목록 줄(표지 높이 = 글 묶음 높이) | `showBook`(책 상세 안에서는 표지 없이) |
| `MiniTimer` | lib/features/reading/mini_timer.dart:32 | 모든 화면 위 작은 독서 타이머 | 접힘(시간 동그라미) / 펼침(책·일시정지·시간) |
| 하단 탭 바 | lib/app/app_shell.dart | 흰 알약 5칸(아이콘만, 접근성 이름은 메뉴명) | 상세 화면에서는 숨김 |
| `PickMark` | lib/features/book/barcode_scan_screen.dart:240 | 여러 권 고르기 원 | `on` |

## 지켜 온 규칙(문서·메모에서)

- 흰 화면 안에 회색 상자를 두지 않는다(입력칸은 예외). 글자 버튼에 밑줄을 긋지 않는다.
- 주요 버튼(갈색 채움)은 화면에 하나.
- 아이콘·글자 버튼의 눌림은 투명도 0.55로 통일한다.
- 누르는 자리는 48dp 이상(`Space.hit`, 2026-11-16 QA).
- **글자 크기·여백·글씨체·단추 크기는 화면에서 직접 쓰지 않는다**(2026-11-18 사용자: 항목에 따라 다른 곳과 통일해서 관리). 글자는 `AppType` 역할(title 26 · pageTitle 23 · heading 21 · section 19 · row 18 · body 17 · sub/label/labelStrong/bodySmall/buttonSmall 16 · caption 15 · micro 13, 숫자는 display 48 · timer 64 · clock 36 · figure 24, 명조는 quote · reading), 간격은 `Space`(구역 사이 `block` 48 · 촘촘한 줄 `dense` 32), 둥글기는 `Shape`(카드 12), 단추는 `Btn` 크기 l 52 · m 48 · s 40. 시안에 맞추려면 그 역할 값을 바꾸거나 공통 부품을 고친다. 예외는 그린 표지·공유 그림·새긴 해·자동 맞춤 제목뿐.

## 로그인 단추 (`_BrandButton`, features/settings/backup_screen.dart)

- 백업 및 복원 › 동기화 아래 '계정 연결'에 카카오·Apple·Google을 같은 틀로 쌓는다: 높이 54, 모서리 `Shape.button`(10), 가운데 로고 22 + 글자 16 Bold, 단추 사이 8.
- 순서는 카카오 · Google · Apple. 색은 각 회사 규칙: 카카오 `#FEE500` 바탕·검은 말풍선·글자 85% 검정 / Google 옅은 회색 `#F2F2F2` 바탕·선 없음·네 색 G·글자 `#1F1F1F`(Neutral) / Apple 검정 바탕·흰 로고·흰 글자.
- 문구는 'OO로 계속하기'로 맞춘다(Google 영어 그림 단추는 2026-11-16에 뺐다).
- 연결된 계정은 위 목록에 '… 계정 연결됨' 줄로 보이고 그 단추는 사라진다. '서버 계정 삭제'는 단추들 아래 따로 둔다.

## 아이콘

- 화면 안 선 아이콘은 모두 Lucide(ISC, lucide-static 1.75.0) 한 벌: `LucideIcon(이름)`, 24칸 기준 선 굵기 1.8(`stroke`로 바꾼다). 표는 `tool/gen_icons.py`가 `tool/lucide_icons/`에서 `lib/gen/lucide.g.dart`로 만든다. 새 아이콘은 표(NAMES)와 SVG를 더한다. 재생·일시정지는 Lucide play·pause를 채운 모양(`play_icons.dart`). 2026-11-17~18 잠깐 Tabler였다.
- 예외: 하단 탭 아이콘(`tab_icons.dart`), 책장 머리 입체 아이콘(그림), 재생·일시정지 채운 모양(`PlayIcon`·`PauseIcon`), Apple 로고.
- 목록 오른쪽 끝 +는 22·옅은 회색(`inkSoft`)이고 그림 오른쪽 끝을 내용 오른쪽 끝에 맞춘다(누르는 칸 48).
