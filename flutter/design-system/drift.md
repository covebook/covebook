# 어긋남(drift) — 테마를 안 거친 색·글자 크기, 플랫폼끼리 다른 색 (2026-11-16, a7c27f7)

`lib/` 아래(생성 코드 `lib/gen/`과 `lib/ui/theme.dart` 제외)를 셌습니다.
- 색 리터럴(`Color(0x…)` · `Color.fromRGBO` · `Color.fromARGB`) 127곳 / 29파일
- `fontSize:` 숫자 69곳 / 23파일

책장 3D 장면(벽·판·책 빛)은 빛 모델이 생성하는 값이라 제외했습니다. 갈피 종이·공유 그림처럼 '물건의 색'은 따로 표시했습니다.

## 1. 플랫폼끼리 다른 색 (Flutter ↔ Android 위젯 Kotlin)

| 쓰임 | Flutter | Android 위젯 | 차이 |
|---|---|---|---|
| 빈 상태 글자 | `AppColors.inkSoft` `#646F7E`(푸른 회색) | `HINT` `#968C87`(따뜻한 회색, `ShelfWidgetRenderer.kt:27`) | 색온도가 반대, 밝기도 다름 |
| 그림 없을 때 카드 바탕 | `AppColors.surface` `#F2F4F6`(푸른 기) | `CARD` `#F6F4F2`(`ShelfWidgetRenderer.kt:28`) | RGB 순서가 뒤집힌 값(따뜻한 기) |
| 빈 상태 글꼴 | Pretendard | 시스템 기본 | 다름 |
| 빈 상태 글자 크기 | 글자 위계(15~18) | 위젯 폭의 4.5% | 위계 밖 |

평소 위젯은 앱이 떠 둔 그림이라 어긋나지 않습니다. 어긋나는 것은 그림이 없을 때(설치 직후·앱을 아직 안 열었을 때)뿐입니다. iOS 위젯은 없어 비교할 것이 없습니다.

## 2. 토큰과 같은 값을 다시 적은 곳

| 곳 | 값 | 쓸 토큰 |
|---|---|---|
| bookmark_empty.dart:37 | `0xFFE5E8EB` | `AppColors.line` |
| backup_screen.dart:224 | `0xFF000000` · `0xFFFFFFFF` | `AppColors.tabInk` · `AppColors.white` |
| barcode_scan_screen.dart:135, bookmark_card.dart:17, photo_plate.dart:83·111, home_screen.dart:1478·1519 | `0xFFFFFFFF` | `AppColors.white`(바탕이면 `bg`) |

## 3. 토큰과 거의 같은 값(실수로 갈라진 듯한 것)

| 곳 | 값 | 가까운 토큰 | 차(RGB 합) |
|---|---|---|---|
| bookmark_detail_screen.dart:245 | `#68524A` | `accent` `#6C534A` | 5 |
| book_share_screen.dart:24 | `#F3F2F1` | `surface` `#F2F4F6` | 8(따뜻한 쪽) |
| home_screen.dart:1711 | `#F4F3F2` | `surface` `#F2F4F6` | 7(따뜻한 쪽) |
| startup.dart(시작 점) | `#7C6253` · `#DBCDC1` | `accent` · `track` | 지금 앱 시작 그림에 맞춘 값(의도) |

## 4. 토큰이 없어 화면마다 적은 색 묶음

| 묶음 | 값 | 곳 | 제안 토큰 |
|---|---|---|---|
| 갈피·감상 본문 글자(따뜻한 먹색) | `#292725` · `#34302C` · `#38332D` | bookmark_card.dart, photo_plate.dart | `readingInk`(하나로) |
| 종이 카드 그림자 | rgba(60,50,45, 0.05·0.06·0.28) | bookmark_card.dart, board_card.dart | `shadow.paper` |
| 갈피 뒷종이 테두리 | rgba(108,83,74, 0.16) | bookmark_card.dart | `paperEdge` |
| 떠 있는 것 그림자 | `#14191F28`(ink 8%) 4곳 · `#1F000000` · `#1A000000` · `#14000000` | kit.dart, mark_share_sheet.dart, binding_editor.dart, book_share_screen.dart | `shadow.float`·`shadow.thumb`로 모으기 |
| 장면 위 흰 겹 | `#E6FFFFFF` · `#33FFFFFF` · `#0AFFFFFF` · `#0FFFFFFF` | reading_screen.dart, home_screen.dart | night 묶음에 넣기 |
| 장정 편집 그림 색 | `#94765B` · `#89705A` · `#EEECE9` · `#ECE9E4` | binding_editor.dart | 장정 재질 표(물건 색, UI 토큰 아님) |
| 공유 그림 글자 | `#1B1B1B` 등 7색(share_scene.dart `_ink`) · mark_scene.dart 13곳 | share_scene.dart, mark_scene.dart | 시안 그림 화소에 맞춘 값(의도, 공유 그림 전용 묶음으로) |

## 5. 글자 크기를 숫자로 적은 곳

글자 위계(`AppType`)는 15 · 16 · 17 · 18 · 19 · 21 · 26입니다. 이 밖의 크기가 꽤 많습니다.

| 크기 | 곳 수 | 비고 |
|---|---|---|
| 12 · 13 · 13.5 · 14 | 20 | 위계에 없는 작은 글자(배지·메타·달력 숫자 등) |
| 15.5 · 16.5 | 2 | 반 단계(지금 앱 값을 옮긴 곳) |
| 20 · 23 · 24 | 8 | 위계 사이 |
| 32 · 34 · 36 · 48 · 56 | 7 | 숫자 큰 표시(타이머·통계·장면 시계) |
| 15 · 16 · 17 · 18 · 19 | 32 | 위계와 같은 크기를 숫자로 다시 적음(`AppType.copyWith(fontSize:)` 포함) |

많은 파일: kit.dart 10, community_widgets.dart 7, stats_widgets.dart 6, book_screen.dart 5, decorate_panel.dart 5, book_sheet.dart 4, essay_screens.dart 4(11-16 감상 줄 14·17 — 이번에 넣은 것), all_books_screen.dart 3, read_list.dart 3, reading_screen.dart 3.

제안
- 위계에 `meta`(14/20)와 `micro`(12/16)를 넣습니다.
- 큰 숫자 표시는 `display`(36/44 · 48/56)로 둡니다.
- 나머지는 이 위계로 옮깁니다.

## 6. 날짜 쓰는 법이 화면마다 다름

| 화면 | 쓰는 법 |
|---|---|
| 읽기 | `11. 15 (일)` |
| 통계 | `11월 15일 일요일` |
| 감상·갈피 상세 | `2026.11.15` |
| 갈피 카드 | `11월 15일` |

날짜 형식 함수 하나로 모으길 제안합니다.

## 7. 같은 역할, 다른 모양

| 역할 | 모양 A | 모양 B |
|---|---|---|
| 화면 안쪽 메뉴 | `Tabs` 밑줄 글자(내 책·기록) | `Segmented` 회색 칸(책 상세·통계) |
| 상세 화면 머리줄 | 큰 왼쪽 제목(갈피 남기기·감상 고치기·내 정보) | 가운데 작은 제목(갈피·책 공유) / 뒤로 옆 작은 제목(갈피 보드) |
| 같은 일의 말 | '진열'(여러 권 선택) | '책장에 꽂기'(추가 화면) · '책장에서 빼기'(책 시트) |
| 스토어 입구와 제목 | '선반·벽지'(꾸미기 안 입구) | '스토어'(열리는 화면 제목) |

## 다음에 하면 좋은 것

- `tokens.json`을 원본으로 두고 스크립트로 상수 파일을 만듭니다: Dart `lib/ui/theme.g.dart`, Kotlin `ShelfWidgetColors.kt`, 나중에 Swift까지. 그러면 1번 같은 어긋남이 다시 생기지 않습니다.
- 디자인 반영 때는 새 색·글자 크기를 숫자로 적지 않고 `AppColors`·`AppType`와 공통 위젯만 씁니다. 없는 것은 먼저 토큰·위젯으로 만들고 `components.md`를 고칩니다.
