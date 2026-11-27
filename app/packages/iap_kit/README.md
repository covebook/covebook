# iap_kit (앱 쪽 결제 키트)

앱 안 결제(App Store, Google Play)의 앱 쪽 코드다. 서버 키트 `server/iapkit`와 짝으로 쓴다.

- 서버 키트 설명, API, 테이블: [`server/iapkit/README.md`](../../../server/iapkit/README.md)
- 법·고지 체크리스트: [`server/iapkit/LEGAL.md`](../../../server/iapkit/LEGAL.md)
- 결정 기록(책장 한켠): `docs/adr/0002-iap-design.md`

## 키트가 하는 것과 앱이 할 것

| 키트 | 앱 |
|---|---|
| 스토어 결제 창 열기, 구매 스트림 듣기 | 결제 화면, 구독 관리, 구매 내역, 알림함 같은 화면 전부 |
| 구매 증거를 서버에 내고, 서버 답을 보고 거래를 끝낼지 정하기(`iapShouldFinish`) | 화면 문구(고지 문구 T1~T15). 고지·내역 한 줄의 글은 확장으로 붙인다 |
| 고지 읽기·읽음 표시, 창으로 띄울 고지 하나 고르기, 구매 내역 읽기, 연 구독 갱신 전 알림 시각(아래 "고지와 구매 내역") | 기기 알림 걸기(`flutter_local_notifications` 같은 플러그인, 권한 묻기) |
| 안드로이드: 확인하지 못한 구매를 앱이 앞으로 올 때 다시 내기 | 권한을 쓰는 곳(유료 꾸미기를 켜고 끄기 등) |
| iOS: 끝내지 않은 거래가 새 결제를 막을 때 꺼내서 다시 내기 | 서버 호출 함수, 기기 저장소, 결제 켜기 플래그 |
| 결제 상태 사본(`EntitlementStore`)을 기기에 남기고, 만료가 지난 구독의 권한은 끄기 | 앱 말로 읽는 확장(책장 한켠: `plus`, `shelvesFor(year)`) |
| 한 번 사는 상품의 결제 의도(`POST /iap/intent`)와 지우기. 결제 대기에는 지우지 않고, 고른 대상과 의도 번호를 기기에 남겨 앱을 다시 켜도 그 거래에 붙인다 | |

## 붙이는 법

1. `pubspec.yaml`

   ```yaml
   dependencies:
     iap_kit:
       path: packages/iap_kit
   ```

2. 앱을 켤 때 한 번 `IapKit.configure`를 부른다(`main`, `runApp` 전)

   ```dart
   IapKit.configure(
     enabled: const bool.fromEnvironment('IAP'),       // 결제 화면을 켠 빌드인지
     api: (method, path, [body]) async {               // 로그인 토큰을 붙여 서버를 부른다
       final token = await readLoginToken();
       if (token == null) throw const IapSignedOut();  // 알림함은 이때 null(기기 기준으로 알릴 수 있다)
       try {
         return await myApi(method, path, token, body);
       } on MyApiError catch (e) {
         throw IapApiError(e.status, e.code, e.message); // 서버 오류 {"error":{"code","message"}}
       }
     },
     storage: IapStorage(get: kv.get, set: kv.set, remove: kv.remove),
     defaultTarget: () => '',                          // 대상이 있는 앱만 바꾼다(책장 한켠: 올해 연도)
     messages: const {'over_cap': '...'},              // 바꿀 문구만
   );
   ```

3. 로그인한 뒤 첫 화면에서 `IapService.instance.start()`, 로그아웃할 때 `IapService.instance.reset()`과 `EntitlementStore.instance.clear()`
4. 서버 상품 테이블(`iap_products`)에 넣은 상품을 스토어 콘솔에도 같은 ID로 만든다

책장 한켠의 실제 연결: `app/lib/services/iap.dart`(configure), `app/lib/store/entitlement_store.dart`(앱 말 확장)

## 상태 읽기

- `EntitlementStore.instance`
  - `has('plus')`: 구독 권한이 있는지. 권한 이름은 서버 `iap_products.entitlement`
  - `unitsFor(target)`: 그 대상에서 산 수량. 대상이 없는 앱은 `unitsFor('')`
  - `capPerTarget`: 대상 하나의 상한(서버 규칙). 0이면 없음
  - `subscription`: 구독 상태(`statusLabel`은 T11 표시)
  - `products`, `seller`, `unreadNotices`
- `IapService.instance`
  - `plans`: 구독 요금제(월간, 연간). 할인·체험 제안은 뺀다
  - `details`: 스토어가 준 상품과 가격 문자열
  - `busy`, `loading`, `lastResult`, `lastMessage`

`ChangeNotifier`라서 `ListenableBuilder`나 `addListener`로 다시 그린다.

## 사기

```dart
// 구독: 고른 요금제
await IapService.instance.buy(product, plan: plan);
// 한 번 사는 상품: 대상이 있으면 대상을 준다
await IapService.instance.buy(product, target: '2026');
```

- 결과는 `lastResult`와 `lastMessage`로 온다. `buy`는 결제 창을 띄우기까지만 기다린다
- 한 번 사는 상품은 서버에서 그 대상의 계정 연결 값을 받아 스토어에 넘긴다. 앱이 결제 중 꺼지거나 스토어 알림으로 와도 서버가 대상을 잃지 않는다
- 상한에 닿았거나(`iap_cap_full`) 다른 기기가 결제 중이면(`iap_target_busy`) 결제 창을 띄우지 않는다. 문구는 서버 규칙의 문구를 그대로 보인다

## 고지와 구매 내역

거래 고지(L7, L11), 구매 내역(L17), 갱신 전 고지(L9)는 법이 요구한다. 앱마다 다시 짜다 빠뜨리지 않게 데이터와 판단은 키트가 맡는다.

| 이름 | 하는 일 |
|---|---|
| `fetchIapNotices()` | 알림함(`GET /iap/notices`). 로그인 안 함(`IapSignedOut`)·예전 서버(404)는 null, 그 밖의 실패는 `IapNoticesUnavailable` |
| `markIapNoticesRead([ids])` | 읽음 표시. 서버가 준 안 읽은 수를 `EntitlementStore.unreadNotices`에 반영 |
| `iapNoticeToShow(list, known:)` | 앱을 열 때 창으로 띄울 것 하나: 안 읽은 중요한 고지(`iapImportantNotices`) 가운데 가장 새것. 띄운 것만 읽음으로 남긴다. 닫은 고지를 다시 띄우지 않는다(다크패턴 규제) |
| `IapNotice` | 종류(`kind`)와 값(`params`, `units`, `target`, `date('expiresAt')`). 글은 없다 |
| `fetchIapPurchases()`, `IapHistoryItem` | 구매 내역(`GET /iap/purchases`). 금액은 통화 코드와 함께 그대로(`price`) |
| `renewalReminderAt(sub, now, days:, hour:)` | 연 구독 갱신 전 기기 알림을 걸 시각. 월 구독, 해지 예약, 결제 실패 유예면 null. 기본 14일 전(`iapRenewalNoticeDays`, 서버 `IAP_RENEWAL_NOTICE_DAYS`와 맞춘다) |

글은 앱이 확장으로 붙인다. 서버 키트의 "종류와 값은 서버, 글은 앱"과 같은 나눔이다.

```dart
extension MyNoticeText on IapNotice {
  (String, String)? get text => switch (kind) {
        'expired' => ('구독이 끝났습니다', '...'),
        _ => null, // 모르는 종류는 보이지 않는다
      };
}

final list = await fetchIapNotices();
final n = list == null ? null : iapNoticeToShow(list, known: (n) => n.text != null);
if (n != null) {
  await markIapNoticesRead([n.id]);
  showMyDialog(n.text!);
}
```

책장 한켠: `app/lib/features/iap/notice.dart`(고지 글, 창), `notices_screen.dart`(알림함), `purchase_history_screen.dart`(내역 글), `app/lib/services/renewal_reminder.dart`(기기 알림)

## 문구

키트가 직접 보이는 문구는 `defaultMessages`에 있고 `configure(messages:)`로 바꾼다.

| 키 | 언제 |
|---|---|
| `start_failed` | 결제 창을 띄우지 못함 |
| `pending` | 결제 대기(편의점 결제, 보호자 승인) |
| `checking` | 서버가 202(결제 확인 중) |
| `not_paid` | 스토어 오류 |
| `submit_failed` | 서버에 닿지 못함 |
| `restored`, `nothing_to_restore`, `restore_failed` | 구매 복원 |
| `expired` | 만료된 구독을 냄 |
| `over_cap` | 다른 기기에서 먼저 상한까지 사서 이번 결제가 반영되지 않음(T15) |
| `unfinished_cleared`, `unfinished_left` | iOS 끝내지 않은 지난 거래 |

서버가 문구를 정하는 오류(상한, 대상 모름, 결제한 계정 탈퇴 등)는 서버 `Rules.Messages`에서 바꾼다.

## 시험

```sh
cd app/packages/iap_kit && flutter analyze && flutter test
```

- 책장 한켠 없이, 대상이 없는 앱 기준으로 돈다. 서버는 `configure(api:)`에 가짜 함수를 넣어 흉내 낸다
- 안드로이드 CI(`android-flutter-play.yml`)가 앱 시험 뒤에 이 패키지의 분석·시험도 돈다. 앱의 `flutter test`는 path 의존 패키지의 시험을 돌지 않는다
- 화면 시험은 앱에 있다(`app/test/iap_test.dart`)

## 하지 않는 것

- 화면을 그리지 않는다. 결제 화면의 법적 표시(가격, 주기, 해지 방법)는 앱 화면 책임이다(LEGAL.md)
- 안드로이드 확인(acknowledge·consume)을 하지 않는다. 서버가 한다. 서버가 거절한 구매를 앱이 확인해 버리지 않게
- 가격을 계산하지 않는다. 스토어가 준 문자열만 보인다
