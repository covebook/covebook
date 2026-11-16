# 홈 화면 위젯 — 책장 한켠 (2026-11-16, a7c27f7)

## 한눈에

| 플랫폼 | 상태 | 위치 |
|---|---|---|
| Android | 있음. 세 가지(나의 책장 · 벽 없이 · 투명), AppWidget(RemoteViews), Glance 아님 | `android/app/src/main/kotlin/app/covebook/shelfwidget/` · `res/layout/shelf_widget*.xml` · `res/xml/shelf_widget*_info.xml` |
| iOS | **없음**. `ios/`에는 Runner뿐이고 WidgetKit 익스텐션이 없다 | — |
| (참고) 지금 앱 RN | Android 같은 세 가지(이 Flutter 위젯의 원본) | `../app/modules/shelf-widget/android/` |

## Android 위젯

### 종류와 크기

세 위젯 모두 같은 크기 규칙을 씁니다.

| 항목 | 값 |
|---|---|
| 기본 칸 | 4×2(`targetCellWidth` 4, `targetCellHeight` 2) |
| 최소 크기 | 250×110dp |
| 늘리기 | 가로·세로 다(`resizeMode` horizontal\|vertical). 최소 110×100dp |
| 보이는 단 수 | 위젯 가로를 늘 꽉 채우고, 높이에 들어가는 만큼 책장 칸을 위에서부터 1~4단 이어 붙인다. 8%까지 넘치면 위쪽을 잘라 맞춘다 |
| 갱신 | 주기 갱신 없음(`updatePeriodMillis` 0). 앱이 책장을 그릴 때 칸마다 떠 둔 그림을 넘긴다(`ShelfWidgetChannel` → `ShelfWidgetProvider`) |

| 위젯 | 이름 | 모양 |
|---|---|---|
| `shelf_widget_info` | 나의 책장 | 책장 구멍(틀 포함)이 위젯을 채우고, 남는 자리는 벽 색 카드 |
| `shelf_widget_niche_info` | 나의 책장(벽 없이) | 구멍 가장자리가 곧 위젯 경계(바깥 평평한 벽 없음) |
| `shelf_widget_cut_info` | 나의 책장(투명) | 선반 판과 책만(벽·틀 투명). 앱이 넘긴 모양으로 오려 낸 PNG |

### 그리는 방식

- 위젯 전체가 그림 한 장(`ImageView` 하나, 뿌리 id `@android:id/background`)입니다. 책장·책·글자는 앱 Flutter 화면을 떠 둔 PNG라 앱 글꼴·색이 그대로 들어갑니다.
- 위젯이 직접 정하는 것은 다음 셋뿐입니다(`ShelfWidgetRenderer.kt`).
  - **카드 바탕**: 그림 맨 위 가운데 화소(= 책장 벽 색). 그림이 없을 때는 `CARD` rgb(246,244,242) = `#F6F4F2`.
  - **모서리**: Android 12+는 `system_app_widget_background_radius`, 그 아래는 위젯 폭의 4.8%.
  - **빈 상태 글자** '앱을 열면 책장이 보여요.'. 색 `HINT` rgb(150,140,135) = `#968C87`, 크기 위젯 폭의 4.5%, 글꼴은 시스템 기본(Roboto/Noto Sans).

### 플랫폼 제약(디자인할 때 넣어야 할 것)

- RemoteViews라 쓸 수 있는 뷰가 정해져 있습니다(ImageView·TextView·FrameLayout 등). 커스텀 그림·그림자·흐림은 비트맵으로 그려 넘겨야 합니다.
- 앱 글꼴(Pretendard 등)은 TextView에서 바로 못 씁니다. 비트맵에 그리거나 시스템 글꼴을 씁니다.
- 위젯 그림 메모리 한도: 그림 폭 1000px 상한(`MAX_W`).
- 모서리는 런처가 시스템 반지름으로 깎습니다(뿌리 id가 background).
- 눌림·애니메이션이 없습니다. 누르면 앱을 엽니다.
- 다크 모드 대응이 없습니다(앱도 라이트 하나).

## iOS 위젯(만든다면)

- WidgetKit + SwiftUI 익스텐션을 새로 만들어야 합니다. 크기는 small 2×2 · medium 4×2 · large 4×4.
- 앱 그룹 컨테이너로 Android처럼 떠 둔 책장 그림을 넘기면 SwiftUI는 `Image` 하나만 그리면 됩니다. 그러면 색·글꼴 어긋남이 생길 자리가 없습니다.
- SwiftUI 위젯은 스크롤·영상·실시간 애니메이션이 안 되고, 보이는 갱신은 타임라인 단위입니다.
