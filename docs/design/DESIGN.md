# 책장 한켠 디자인 기준

앱 화면(Flutter, `app/`)의 디자인 규칙을 모은 문서 하나다. 기준은 **지금 실행되는 Flutter 앱의 모양과 동작**이다.

- 값의 원본은 코드다. 글꼴·크기·줄 높이·색은 `app/lib/ui/theme.dart`, 간격·모서리·조작부 크기·아이콘·표지 크기와 공용 부품은 `app/lib/ui/kit.dart`에 한 번만 정의한다.
- 이 문서는 **언제 무엇을 쓰는지와 어디서 고치는지**를 적는다. 표의 숫자는 코드에서 옮겨 적은 것이고, `app/test/design_tokens_test.dart`가 코드와 같은지 검사한다.
- 시안(HTML·Claude Design)용 값 `app/design-system/tokens.json`·`app/design-system/web/`은 같은 시험이 Flutter 값에서 만든다. 손으로 고치지 않는다.
- 책장 3D 장면(벽·판·책·빛)의 색과 재질은 이 문서 밖이다(`app/lib/gen/`, `app/tool/gen_shaders.sh`).
- 지난 기준(React Native 앱 시절 2026-10~11-18)과 조사 기록은 [`history/`](history/)에 있다.

## 0. 무엇을 바꿀 때 어디를 고치나

| 바꾸려는 것 | 고칠 곳 | 그다음 |
|---|---|---|
| **규칙**(어떤 항목에 어떤 역할·부품을 쓰나, 예외) | 이 문서 | 규칙에 맞게 화면 코드를 고친다 |
| **공통 값**(한 역할의 크기·색·간격) | `theme.dart`의 `TypeSpecs`·`AppColors`, `kit.dart`의 `Space`·`Shape`·`ControlSize`·`IconSize`·`CoverSize` | `cd app && DESIGN_TOKENS_UPDATE=1 flutter test test/design_tokens_test.dart`로 시안 토큰을 다시 만들고, 이 문서 표의 숫자도 고친다(안 고치면 시험이 실패한다) |
| **공용 부품 모양**(단추·줄·시트의 생김새) | `kit.dart`의 그 위젯 | 그 부품을 쓰는 모든 화면이 함께 바뀐다 |
| **한 화면 배치만**(순서·정렬·묶음 사이) | 그 화면 파일(`app/lib/features/…`)의 Row·Column·Padding | 간격은 `Space` 이름으로 쓴다. 새 숫자가 필요하면 새 역할을 만들거나 9장 예외에 적는다 |

값이 우연히 같아도 역할이 다르면 이름을 따로 둔다. 예: 책 한 줄 제목 `AppType.bookTitle`과 굵은 줄 이름 `AppType.rowStrong`은 지금 둘 다 18/26 SemiBold지만, 책 제목만 키울 수 있게 따로 있다.

## 1. 원칙

- 책이 주인공이다. 화면 바탕은 흰색 하나, 글자는 먹색(`ink`), 강조는 차분한 갈색(`accent`) 하나. 카드와 그림자는 아끼고 여백으로 나눈다. 입체·빛·재질은 책장 장면에만 쓴다.
- 흰 화면 안에 회색 상자를 두지 않는다(토스식, 2026-11-01). 입력칸·전환 칸만 예외. 상자가 꼭 필요하면 테두리 상자 `OutlineBox`.
- 같은 종류 항목은 같은 공용 부품과 같은 역할 값을 쓴다(2026-11-18 사용자 '버튼·글씨 크기·여백·글씨체는 항목에 따라 통일해서 관리'). 화면 파일에 크기·색·여백 숫자를 직접 쓰지 않는다.
- 역할 글자에 덧칠하는 것은 색(`ink`·`inkSoft`·`inkFaint`·`accent`·`danger`·`onAccent`), 숫자 폭 고정 `.tnum`, 고른 칸만 굵게 `.strong` 셋뿐이다. 다른 굵기·크기가 필요하면 역할을 새로 만든다.
- 위 줄·아래 단추는 내용과 함께 스크롤한다(2026-11-19 사용자 '고정 다 없애'). 책 정보 전환 칸만 위에 붙어 남는다.
- 다크 테마는 없다. 어두운 읽기 장면 위 글자·조작부만 `NightColors`.
- 글자 크기는 기기 글자 크기 설정을 따른다. 큰 글씨에서도 잘리지 않게 줄 높이는 최소값으로 두고 칸은 글자만큼 늘어난다.

## 2. 글자 (`theme.dart` `TypeSpecs` → 화면에서는 `AppType.이름`)

굵기: 보통 = Pretendard Regular, Medium, SemiBold, Bold. 명조 = Noto Serif KR. 크기/줄 높이는 dp.
앱은 글자 크기와 줄 높이를 화소 단위로 올려 그린다(`rnPx`, 옛 RN 앱과 같은 줄 높이). 시안 CSS는 dp 그대로.

### 2-1. 화면 틀

| 역할 | 크기/줄 | 굵기 | 색 | 언제 |
|---|---|---|---|---|
| `AppType.hero` | 32/40 | Bold | ink | 화면에 하나뿐인 큰 이름(로그인 '책장 한켠') |
| `AppType.title` | 26/34 | Bold | ink | 탭 첫 화면 왼쪽 큰 제목 `Screen(back: false, title:)` |
| `AppType.pageTitle` | 23/30 | Bold | ink | 머리줄 왼쪽 큰 제목(책 추가·꾸미기) |
| `AppType.navTitle` | 18/25 | SemiBold | ink | 밀어 넣은 화면 위 줄 가운데 제목 `NavBar` |
| `AppType.heading` | 21/29 | SemiBold | ink | 시트·확인창 제목, 큰 카드 제목 |
| `AppType.section` | 19/27 | SemiBold | ink | 구역 제목 `SectionHead` |
| `AppType.count` | 16/23 | Medium | inkSoft | 구역 제목 옆 개수('갈피  3') |

### 2-2. 줄과 글

| 역할 | 크기/줄 | 굵기 | 색 | 언제 |
|---|---|---|---|---|
| `AppType.row` | 18/26 | 보통 | ink | 목록 줄 이름(설정·메뉴·이름+값) `ListItem` |
| `AppType.rowStrong` | 18/26 | SemiBold | ink | 굵은 줄 이름(시트 안 묶음 이름 `SheetLabel`) |
| `AppType.body` | 17/27 | 보통 | ink | 본문 |
| `AppType.sub` | 16/23 | 보통 | inkSoft | 보조 글(값·설명·출처·안내). 오류는 `danger`로 색만 |
| `AppType.caption` | 15/21 | 보통 | inkSoft | 작은 보조 글(묶음 이름 `ListGroup`·메타) |
| `AppType.bodySmall` | 16/22 | 보통 | ink | 작은 본문(체크 이름·날짜 칸·짧은 글) |
| `AppType.label` | 16/22 | Medium | ink | 작은 이름(칩·고르는 칸) |
| `AppType.labelStrong` | 16/22 | SemiBold | ink | 굵은 작은 이름(카드 제목·닉네임·필터 칸) |
| `AppType.micro` | 13/18 | 보통 | inkSoft | 아주 작은 표시(그래프 눈금·배지), 숫자 폭 고정 |
| `AppType.quote` | 16/27 | 명조 | ink | 갈피 문장 |
| `AppType.reading` | 17/30 | 명조 | ink | 감상 등 긴 글 본문 |
| `AppType.input` | 16/— | 보통 | ink | 입력창 글자(줄 높이는 플랫폼 기본) |

### 2-3. 단추 글자

| 역할 | 크기/줄 | 굵기 | 색 | 언제 |
|---|---|---|---|---|
| `AppType.button` | 17/24 | SemiBold | (단추가 정함) | 보통·큰 단추 `Btn` m·l |
| `AppType.buttonSmall` | 16/22 | SemiBold | (단추가 정함) | 작은 단추 `Btn` s |
| `AppType.link` | 16/23 | SemiBold | accent | 글자 단추 `TextLink`(색만 바꿔 쓴다: 5장) |
| `AppType.loginLink` | 15/21 | Medium | inkSoft | 로그인 화면 아래 작은 글자 단추 |

### 2-4. 숫자 (모두 숫자 폭 고정)

| 역할 | 크기/줄 | 굵기 | 색 | 언제 |
|---|---|---|---|---|
| `AppType.timer` | 64/72 | 보통 | ink | 읽기 장면 시간 |
| `AppType.display` | 48/58 | Bold | ink | 아주 큰 숫자(통계 '이번 달 읽은 시간'). 단위는 `AppType.displayUnit` |
| `AppType.displayUnit` | 22/30 | Medium | ink | 위 숫자의 단위 |
| `AppType.clock` | 36/44 | 보통 | ink | 큰 시간(독서 끝·접은 읽기 장면) |
| `AppType.score` | 36/44 | Bold | ink | 큰 점수(독자 평점 평균) |
| `AppType.figure` | 24/32 | Bold | ink | 숫자 값(통계 읽은 날·독서 횟수·쪽수) `StatNumber` |
| `AppType.wheel` | 19/27 | 보통 | inkSoft | 돌려 고르는 숫자(분·시각 시트). 고른 값은 `.strong` + ink |

## 3. 책: 제목·작가·한줄평·표지

### 3-1. 글자 역할

| 역할 | 크기/줄 | 굵기 | 색 | 언제 |
|---|---|---|---|---|
| `AppType.bookTitle` | 18/26 | SemiBold | ink | **책 제목 기본.** 책 한 줄 `BookRow`(고르기·검색 결과·내 책 목록·기록 줄), 책 확인, 시트 머리 |
| `AppType.bookHeadTitle` | 23/30 | Bold | ink | 책 정보 머리(표지 아래 가운데) |
| `AppType.bookFeatureTitle` | 21/29 | SemiBold | ink | 읽기 탭 '최근 읽던 책' 큰 카드 |
| `AppType.bookSavedTitle` | 19/27 | SemiBold | ink | 저장했어요 창(사용자 시안) |
| `AppType.bookGridTitle` | 15/21 | 보통 | ink | 내 책 격자 표지 아래 |
| `AppType.bookAuthor` | 16/23 | 보통 | inkSoft | **작가 줄 기본.** 책 줄 둘째 줄('작가 \| 출판사', '작가 \| 상태'), 책 정보 머리 작가 |
| `AppType.bookGridAuthor` | 13/18 | 보통 | inkSoft | 내 책 격자 둘째 줄 |
| `AppType.bookNote` | 15/21 | 보통 | inkSoft | 한줄평 · 책 줄 셋째 줄(한줄평·미리보기·진행) |
| `AppType.review` | 17/27 | 보통 | ink | 한줄평 · 평가 탭 본문. 비었을 때 안내는 `AppType.sub` |

- 작가 글자는 `authorLine(authors)` 하나로 만든다(여러 작가는 쉼표: '클레어 키건, 홍한별', `app/lib/domain/library.dart`).
- 제목은 줄 수만 정한다: 책 줄 작게 1줄, 보통·크게 2줄, 넘치면 말줄임. 책 정보 머리는 줄 수 제한 없음.
- 책 없이 읽은 기록의 이름은 '책 없이 읽기', 표지 자리는 회색 칸 `NoBookCover`.

### 3-2. 책 한 줄 `BookRow`

표지 + 16(`Space.l`) + (제목 `bookTitle`, 둘째 줄 `bookAuthor`를 `MetaText`로, 셋째 줄 `bookNote`) + 오른쪽 자리. 위아래 12(`dense`면 4).

| 크기 | 표지 폭 | 쓰는 곳 |
|---|---|---|
| `CoverSize.row` | 40 | 작게: 책 고르기·여러 권 선택·바코드·가져오기·읽기 목록·통계 기록 |
| `CoverSize.result` | 64 | 보통: 검색 결과·감상 목록 |
| `CoverSize.list` | 80 | 크게: 내 책 목록(글 위쪽 맞춤) |

### 3-3. 그 밖의 표지 크기(폭, 높이는 책 비율)

| 이름 | 폭 | 쓰는 곳 |
|---|---|---|
| `CoverSize.head` | 140 | 책 정보 머리 |
| `CoverSize.feature` | 120 | 읽기 탭 '최근 읽던 책' |
| `CoverSize.confirm` | 120 | 책 확인(추가 전) |
| `CoverSize.edit` | 96 | 책 정보 수정 |
| `CoverSize.added` | 88 | '추가했어요' 시트 |
| `CoverSize.saved` | 72 | 저장했어요 창(2026-11-18 사용자 '썸네일 좀 더 크게') |
| `CoverSize.place` | 68 | 책장에 꽂기 |
| `CoverSize.sheet` | 56 | 숨기기·삭제 확인 시트 |
| `CoverSize.post` | 36 | 함께 읽기 글 안 |
| `CoverSize.swatch` | 22 | 장정 고르기 칸 안 |
| `CoverSize.ratio` | 0.68 | 대체 표지·책 없이 읽기 칸의 가로:세로 |

내 책 격자 표지는 책장 장면 크기(mm)에서 계산한다(`all_books_screen.dart` `_thumb`). 표지 모서리는 `Shape.cover` 3.

## 4. 날짜·시간

글자 모양은 함수 하나씩만 쓴다. 화면에서 날짜·시각을 직접 조립하지 않는다.

| 쓰임 | 모양 | 함수 |
|---|---|---|
| 목록·카드 날짜 | '11월 15일', 올해가 아니면 '2025년 11월 15일' | `dateShort` (`features/book/labels.dart`) |
| 상세·날짜 칸 | '2026년 11월 15일' | `dateLong` |
| 날짜 머리(요일까지) | '10월 31일 토요일' | `dayTitle` (`features/stats/chart_data.dart`) |
| 시각 하나 | '오후 9:05' | `timeLabel` |
| 시간대 | '오후 9:05-9:30'(오전·오후가 같으면 한 번, 짧은 '-') | `timeRange` |
| 재는 중인 시간 | '00:45', 한 시간 넘으면 '1:02:03' | `clock` (`domain/reading.dart`) |
| 지난 시간 | '38분', '1시간 30분', 1분 미만은 '1분 미만' | `formatDuration` (`domain/library.dart`) |
| 지난 시간(초까지 필요할 때) | 1분 미만은 '45초', 그 밖은 분까지 | `formatDurationShort` |

독서 기록 줄(책 정보 '독서 기록')은 날짜로 묶는다: 날짜 머리 `AppType.recordDay` 18/26, 그 아래 시간대 `AppType.recordRange` 16/23 회색, 오른쪽 읽은 시간 `AppType.recordDuration` 18/26(숫자 폭 고정). 줄 높이 최소 `Space.dense`.

| 역할 | 크기/줄 | 굵기 | 색 | 언제 |
|---|---|---|---|---|
| `AppType.recordDay` | 18/26 | 보통 | ink | 기록 묶음 날짜 머리('11월 17일') |
| `AppType.recordRange` | 16/23 | 보통 | inkSoft | 기록 시간대('오후 9:05-9:30') |
| `AppType.recordDuration` | 18/26 | 보통 | ink | 기록 한 줄 읽은 시간('38분') |

- 정보 사이는 옅은 세로줄 `metaSep`(' \| ', 색 `metaBar`). 그릴 때는 늘 `MetaText`(화면 읽기는 쉼표로 읽는다).
- 개수는 '갈피 N개', '책 N권' 어순.

## 5. 단추 (`kit.dart` `Btn`·`TextLink`)

### 5-1. 우선순위

| 우선 | 부품 | 모양 | 언제 |
|---|---|---|---|
| 1 | `Btn` primary | 갈색 채움, 흰 글자 | 그 화면에서 가장 중요한 한 가지(저장·이어서 읽기). **한 화면에 하나** |
| 2 | `Btn` secondary | 흰 바탕, `line` 테두리, 먹색 글자 | primary 옆 덜 중요한 일(갈피 남기기), 혼자 있는 보조 일 |
| 2 | `Btn` danger | secondary 모양, `danger` 글자 | 지우기처럼 되돌리기 어려운 일(확인창 거친 뒤) |
| 3 | `Btn` ghost | 바탕 없음 | 어두운 읽기 장면 위 보조 |
| 4 | `TextLink` | 글자만, 밑줄 없음, 누르는 자리 48 | 머리줄 '취소'·'완료'(ink), 다른 곳으로 가는 보조·구역 링크(soft, 회색), 그 밖 갈색 |

- 둘을 나란히 둘 때는 왼쪽 secondary, 오른쪽 primary.
- 저장 단추 이름은 '○○ 저장'. 고치기·지우기는 '수정'·'삭제'.
- 확인창은 `appAlert` 하나. 시트에는 '닫기' 단추를 두지 않는다(밖 누르기·내려 닫기).
- 쓰던 글이 있는 화면은 나갈 때 묻는다(갈피 남기기·갈피 수정·감상 쓰기·감상 수정, `form_parts.dart`).
- 결제 화면·알림 문구는 [`../legal/notice-templates.md`](../legal/notice-templates.md)를 따른다(해지 경로 숨기기·미리 선택·거절한 사람에게 같은 팝업 다시 띄우기 금지).

### 5-2. 크기

| 이름 | 보이는 높이 | 언제 |
|---|---|---|
| `ControlSize.buttonL` | 52 | 화면 아래 주요 단추, 시트 안 단추(`Btn(size: 'l')`) |
| `ControlSize.buttonM` | 48 | 카드·창 안 단추(기본, 읽기 탭 '이어서 읽기') |
| `ControlSize.buttonS` | 40 | 줄 안 작은 단추 |

모서리 `Shape.button` 10. 꺼진 단추는 primary는 `line` 바탕 + `inkFaint` 글자, 그 밖은 투명도 `disabledOpacity` 0.4. 눌림: primary는 `accentPressed`, secondary는 `input` 바탕, 글자·아이콘 단추는 투명도 `pressOpacity` 0.55.

## 6. 아이콘·누르는 자리

| 이름 | 값 | 언제 |
|---|---|---|
| `IconSize.base` | 22 | 머리줄·줄 안 아이콘(lucide 선 아이콘) |
| `IconSize.stroke` | 1.6 | 선 아이콘 굵기 |
| `IconSize.chevron` | 20 | 줄 끝 꺾쇠 `Chevron`(inkSoft) |
| `IconSize.back` | 28 | 뒤로 꺾쇠(`NavBar`) |
| `IconSize.mark` | 20 | 이미 넣음 체크 `AddedMark`(accent) |
| `IconSize.markStroke` | 2 | 위 체크 굵기 |
| `IconSize.checkStroke` | 3 | 고른 원·정보 넣기 네모 안 흰 체크 굵기 |
| `Space.hit` | 48 | 누르는 자리 최소(아이콘·글자 단추·작은 단추 모두) |

- 머리줄 아이콘은 `HeadIcon`: 22, 굵기 1.6, **회색 inkSoft**, 아이콘 사이 4(`headIconGap`).
- 줄 끝 꺾쇠는 **다른 화면이나 시트로 넘어가는 줄에만**. 메뉴 시트(⋯) 안 줄에는 없다.
- 하단 탭 아이콘은 직접 그린 그림(23, `TabBarStyle.icon`): 고른 칸 채움(`tabInk`), 나머지 윤곽(`tabInkSoft`)과 글자.
- 겉모양이 48보다 작아도 누르는 자리는 위아래 빈 자리까지 48로 넓힌다(작은 단추·전환 칸·스위치).

## 7. 화면 틀·줄·고르기

| 항목 | 규칙 | 부품 |
|---|---|---|
| 탭 첫 화면 머리 | 왼쪽 `title`, 위 16·아래 12·좌우 24(`TabHeader`) | `Screen(back: false, title:)` |
| 밀어 넣은 화면 머리 | 가운데 `navTitle`, 줄 높이 60, 뒤로 꺾쇠 28 | `NavBar` |
| 구역 제목 | `section`, 오른쪽 개수 `count`, 오른쪽 링크는 회색 `TextLink` + 꺾쇠, 아래 설명 한 줄 `sub` | `SectionHead(note:)` |
| 구역 사이 | `Space.block` 48 | — |
| 설정형 묶음 이름 | `caption` 회색, 아래 4 | `ListGroup(title:)` |
| 시트 안 묶음 이름 | `rowStrong`, 아래 12 | `SheetLabel` |
| 설정·메뉴 줄 | 이름 `row`, 값 `sub`, 보이는 높이 50 | `ListItem` |
| 켜고 끄는 줄 | `ListItem`과 같은 글자, 줄 전체가 스위치 | `ListItem(right: Toggle)`·`FilterToggleRow` |
| 하나 고르기 시트 줄 | 고르면 진한 굵은 글자, 아니면 회색, 오른쪽 고르는 원 | `FilterOption` |
| 고르는 원 | `ControlSize.radio` 22, 고르면 갈색 채움 + 흰 체크, 이미 있는 것은 흐린 채움 | `RadioMark` |
| 상자형 고르기 | 테두리 상자 + 모서리 체크 `ControlSize.choiceBadge` 24 | `ChoiceBox` |
| 정보 넣기 네모 | `ControlSize.checkSquare` 22 + 흰 체크 | `CheckSquare` |
| 전환 칸 | 회색 칸 44, 고른 칸 `ControlSize.segment` 38 흰 바탕 | `Segmented` |
| 안쪽 탭(내 책·기록) | 글자만, 고른 탭 굵게 + 갈색 밑줄 | `Tabs` |
| 스위치 | `ControlSize.toggleWidth` 50 × `ControlSize.toggleHeight` 30, 손잡이 24 | `Toggle` |
| 입력칸 | 높이 `ControlSize.field` 56(여러 줄 110), `input` 바탕, 테두리 없음 | `Field`·`SelectField`·`DateField`·`TimeField` |
| 검색칸 | 높이 `ControlSize.search` 48 | `SearchField` |
| 필터 단추 | 높이 `ControlSize.filter` 40, 알약 | `FilterButton` |
| 구분선 | 1 물리 화소 | `Hairline` |

### 7-1. 간격 (`kit.dart` `Space`)

| 이름 | 값 | 언제 |
|---|---|---|
| `Space.page` | 24 | 화면 좌우 여백 |
| `Space.section` | 40 | 큰 묶음 사이(시트·설정 화면 안 큰 묶음) |
| `Space.block` | 48 | 한 화면 안 구역 사이(책 정보 독서 기록·읽은 기간·갈피) |
| `Space.group` | 28 | 같은 구역 안 무리 사이 |
| `Space.item` | 12 | 줄·항목 사이 |
| `Space.tight` | 8 | 붙어 있는 것 사이 |
| `Space.dense` | 32 | 촘촘한 정보 줄 최소 높이(독서 기록 줄) |
| `Space.xs` | 4 | 아주 좁은 간격(아이콘 사이·제목 아래 작가) |
| `Space.s` | 8 | 좁은 간격 |
| `Space.m` | 12 | 보통 간격 |
| `Space.l` | 16 | 표지와 글 사이, 넓은 간격 |
| `Space.xl` | 28 | 아주 넓은 간격 |
| `Space.xxl` | 40 | 가장 넓은 간격 |
| `Space.touch` | 44 | 아이콘 칸의 겉폭(머리줄·검색칸 안). 누르는 자리는 `Space.hit` |

### 7-2. 모서리 (`kit.dart` `Shape`)

| 이름 | 값 | 언제 |
|---|---|---|
| `Shape.button` | 10 | 단추 |
| `Shape.input` | 10 | 입력칸·검색칸 |
| `Shape.card` | 12 | 테두리 상자(읽은 기간 카드·통계 평균 카드) |
| `Shape.choice` | 14 | 고르는 큰 칸 `Choice` |
| `Shape.segmented` | 12 | 전환 칸 바깥 |
| `Shape.segment` | 9 | 전환 칸 고른 칸 |
| `Shape.sheet` | 20 | 아래 시트 위 모서리 |
| `Shape.dialog` | 18 | 확인창 |
| `Shape.tag` | 6 | 작은 표시·정보 넣기 네모 |
| `Shape.filterPill` | 20 | 필터 단추 |
| `Shape.cover` | 3 | 표지 |

## 8. 색 (`theme.dart` `AppColors`)

`AppColors.all`에 이름·값·쓰임이 함께 있다(시안 토큰도 여기서 만든다). 자주 헷갈리는 것만:

- 글자는 `ink`(본문) · `inkSoft`(보조, 머리줄 아이콘·꺾쇠도) · `inkFaint`(흐린 글자·빈 칸 안내). 회색 글자를 새로 만들지 않는다.
- `accent` 갈색은 주요 단추·고른 것·글자 단추에만. 넓은 면에 칠하지 않는다.
- `surface`는 옅은 회색 면(칩·전환 칸·표지 자리), `input`은 입력칸 바탕. 값이 같아도 따로 쓴다.
- `danger`는 삭제·오류 글자에만.
- 장면 위(어두운 그림)는 `NightColors`.

## 9. 예외 (사용자가 따로 정한 것, 지울 때는 사용자에게 묻는다)

- 읽기 탭 '내 읽기 목록' +: 26·선 2(2026-11-18 시안).
- 책 정보 '내 기록'의 '9회, 총 41분': 세로줄 대신 쉼표(2026-11-18 시안).
- 계정 및 동기화 상태 글: `heading` 21(2026-11-18).
- 저장했어요 창: 표지 72, 제목·작가는 표지 위 끝, 'N분 기록했어요'는 표지 아래 끝(사용자 시안).
- 읽기 목록 줄은 촘촘하게(`BookRow(dense: true)`, 시안).
- 로그인 화면 단추는 사용자 시안 그대로(`app/lib/ui/brand_button.dart`, 2026-11-19 '전처럼').
- 공유 그림(책 카드·갈피 카드·종이·테이프·서명)의 글자·색·여백 숫자: 옛 앱 화소 값 그대로(시안 99% 맞춤). 파일 맨 위에 적어 둔다: `board_card.dart`, `bookmark_card.dart`, `photo_plate.dart`, `bookmark_detail_screen.dart`, `features/share/share_scene.dart`, `features/share/mark_scene.dart`. 화면 코드의 `fontSize:` 숫자는 `design_tokens_test.dart` 예외 목록의 파일에만 허용한다(새로 넣으면 시험이 실패한다).
- 책장 홈(`features/home`)의 장면 위 조작부는 다른 세션이 다듬는 중이라 이 규칙을 아직 다 맞추지 않았다.

### 9-1. 결정 대기

- 검색칸 높이: 11-18 '검색창 두께 좀 줄이고'로 44를 넣었지만 안쪽 검색 아이콘 칸(48)이 높이를 정해 실제로는 48로 그려진다. 지금 화면 그대로 48로 적었다. 44로 줄일지 사용자에게 묻는다.
