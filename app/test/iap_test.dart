// 결제: 거래를 끝내도 되는 때, 선반 칸 수 계산, 서버 응답 반영, 구독 관리 화면과 선반 구매 시트.
// IAP_SHOTS=1로 돌리면 화면을 docs/screenshots/2026-11-19-iap/ 에 PNG로 남긴다(PR에 붙이는 그림).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chaekjang/features/home/locked_rows.dart';
import 'package:chaekjang/features/iap/shelf_purchase_sheet.dart';
import 'package:chaekjang/features/iap/subscription_screen.dart';
import 'package:chaekjang/services/iap.dart';
import 'package:chaekjang/store/entitlement_store.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

final _shots = Platform.environment['IAP_SHOTS'] == '1';
const _shotDir = '../docs/screenshots/2026-11-19-iap';

Future<void> _fonts() async {
  for (final (family, file) in [
    ('PretendardRegular', 'Pretendard-Regular.otf'),
    ('PretendardMedium', 'Pretendard-Medium.otf'),
    ('PretendardSemiBold', 'Pretendard-SemiBold.otf'),
    ('PretendardBold', 'Pretendard-Bold.otf'),
  ]) {
    final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync())));
    await l.load();
  }
}

final _root = GlobalKey();

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(key: _root, child: MaterialApp(debugShowCheckedModeBanner: false, home: home)));
  await t.pumpAndSettle();
}

Future<void> _shot(WidgetTester t, String name) async {
  if (!_shots) return;
  await t.runAsync(() async {
    final boundary = _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.625);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_shotDir).createSync(recursive: true);
    File('$_shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

ProductDetails _detail(String id, String title, String price) =>
    ProductDetails(id: id, title: title, description: '', price: price, rawPrice: 0, currencyCode: 'KRW');

void _reset() {
  final e = EntitlementStore.instance;
  e
    ..plus = false
    ..shelves = 0
    ..subscription = null
    ..products = const []
    ..accountToken = '';
  IapService.instance
    ..details = const {}
    ..busy = false
    ..lastResult = null
    ..lastMessage = null;
}

void main() {
  setUpAll(_fonts);
  setUp(_reset);

  test('거래를 끝내도 되는 때: 지급됐거나, 다시 내도 결과가 같을 때만', () {
    expect(iapShouldFinish(status: 200), isTrue);
    expect(iapShouldFinish(status: 409, code: 'iap_purchase_refunded'), isTrue);
    expect(iapShouldFinish(status: 409, code: 'iap_other_account'), isTrue);
    expect(iapShouldFinish(status: 422, code: 'iap_purchase_rejected'), isTrue);
    expect(iapShouldFinish(status: 422, code: 'iap_sandbox_not_allowed'), isTrue);
    // 다시 낼 수 있어야 하는 것: 결제 대기, 스토어 확인 실패, 요청 많음, 서버 오류, 없는 거래, 증거 확인 실패
    for (final (status, code) in [(202, ''), (503, 'iap_store_unavailable'), (429, 'iap_too_many'), (500, 'internal_error'), (404, 'iap_purchase_not_found'), (422, 'iap_bad_proof'), (401, 'unauthorized')]) {
      expect(iapShouldFinish(status: status, code: code), isFalse, reason: '$status $code');
    }
  });

  test('선반 칸 수: 무료 3칸 + 구매한 칸, 다섯 칸까지', () {
    expect(allowedShelfSlots(), 3);
    expect(allowedShelfSlots(1), 4);
    expect(allowedShelfSlots(2), 5);
    expect(allowedShelfSlots(9), 5); // 구매 기록이 더 많아도 다섯 칸을 넘지 않는다
    expect(openableShelfCount(1), 2);
    expect(openableShelfCount(3), 0);
    expect(openableShelfCount(3, 2), 2);
    expect(openableShelfCount(5, 2), 0);
    // 환불로 구매한 칸이 줄어 지금 선반이 더 많아도 음수가 되지 않는다
    expect(openableShelfCount(5, 0), 0);
    expect(purchasableShelfCount(), 2);
    expect(purchasableShelfCount(2), 0);
  });

  test('서버 응답 반영: 있는 칸만 바꾸고, 날짜는 받은 값 그대로', () {
    final e = EntitlementStore.instance;
    e.apply({
      'plus': true,
      'shelves': 2,
      'accountToken': 'a-token',
      'routes': ['apple', 'google'],
      'products': [
        {'route': 'apple', 'productId': 'shelf', 'kind': 'product', 'shelves': 1},
        {'route': 'apple', 'productId': 'plus', 'kind': 'subscription', 'entitlement': 'plus'},
        '깨진 줄',
      ],
      'subscription': {'route': 'apple', 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    expect((e.plus, e.shelves, e.accountToken, e.products.length), (true, 2, 'a-token', 2));
    expect(e.subscription!.expiresAt, DateTime.utc(2027, 1, 18, 3));
    expect(e.subscription!.statusLabel, '이용 중');
    // 구매 응답에는 계정 연결 값과 상품 목록이 없다. 그대로 남아야 한다
    e.apply({'status': 'granted', 'plus': false, 'shelves': 3, 'subscription': null}, save: false);
    expect((e.plus, e.shelves, e.accountToken, e.products.length, e.subscription), (false, 3, 'a-token', 2, null));
  });

  test('구독 상태 표시: 이용 중, 해지 예약, 결제 확인 필요, 끝남', () {
    IapSubscription sub({bool active = true, bool autoRenew = true, DateTime? grace}) =>
        IapSubscription(route: 'apple', productId: 'plus', state: 'paid', active: active, autoRenew: autoRenew, expiresAt: DateTime.utc(2027, 1, 18), graceUntil: grace);
    expect(sub().statusLabel, '이용 중');
    expect(sub(autoRenew: false).statusLabel, '해지 예약');
    expect(sub(grace: DateTime.utc(2027, 2, 3)).statusLabel, '결제 확인 필요');
    expect(sub(active: false).statusLabel, '이용하고 있지 않아요');
    expect(IapSubscription.from({'expiresAt': '날짜가 아님'}), isNull);
  });

  test('스토어 주소: 해지는 스토어 구독 관리로 바로 간다', () {
    expect(storeManageUrl('apple', 'plus').toString(), 'https://apps.apple.com/account/subscriptions');
    expect(storeManageUrl('google', 'plus monthly').toString(), contains('sku=plus+monthly'));
    expect(storeName('apple'), 'App Store');
    expect(storeName('google'), 'Google Play');
  });

  testWidgets('구독 관리: 이용 중', (t) async {
    EntitlementStore.instance.apply({
      'plus': true,
      'subscription': {'route': iapRoute, 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    IapService.instance.details = {'plus': _detail('plus', '책장 한켠 플러스 (월)', '스토어 가격')};
    await _pump(t, const SubscriptionScreen());
    expect(find.text('이용 중'), findsOneWidget);
    expect(find.text('다음 결제일'), findsOneWidget);
    expect(find.text('2027년 1월 18일'), findsOneWidget);
    expect(find.text('스토어 가격'), findsOneWidget);
    // 해지 버튼이 화면에 바로 보이고, 구매 복원이 있다
    expect(find.textContaining('에서 해지하기'), findsOneWidget);
    expect(find.text('구매 복원'), findsOneWidget);
    expect(find.text('환불 안내'), findsOneWidget);
    await _shot(t, '1-subscription-active');
  });

  testWidgets('구독 관리: 해지 예약은 끝나는 날을 알리고 결제 금액을 보이지 않는다', (t) async {
    EntitlementStore.instance.apply({
      'plus': true,
      'subscription': {'route': iapRoute, 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': false, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    IapService.instance.details = {'plus': _detail('plus', '책장 한켠 플러스 (월)', '스토어 가격')};
    await _pump(t, const SubscriptionScreen());
    expect(find.text('해지 예약'), findsOneWidget);
    expect(find.text('이용 종료일'), findsOneWidget);
    expect(find.text('결제 금액'), findsNothing);
    expect(find.textContaining('이후에는 결제되지 않아요'), findsOneWidget);
    await _shot(t, '2-subscription-cancelled');
  });

  testWidgets('구독 관리: 결제 실패 유예 중이면 유예가 끝나는 날과 결제 수단 확인을 알린다', (t) async {
    EntitlementStore.instance.apply({
      'plus': true,
      'subscription': {
        'route': iapRoute, 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true,
        'expiresAt': '2027-01-18T03:00:00Z', 'graceUntil': '2027-02-03T03:00:00Z',
      },
    }, save: false);
    await _pump(t, const SubscriptionScreen());
    expect(find.text('결제 확인 필요'), findsOneWidget);
    // 유예가 끝나는 날을 '다음 결제일'이라고 부르지 않는다
    expect(find.text('이용 가능 기한'), findsOneWidget);
    expect(find.text('다음 결제일'), findsNothing);
    expect(find.textContaining('2027년 2월 3일까지는 계속 이용할 수 있어요'), findsOneWidget);
    await _shot(t, '3-subscription-grace');
  });

  testWidgets('구독 관리: 구독이 없어도 구매 복원과 환불 안내가 있다', (t) async {
    await _pump(t, const SubscriptionScreen());
    expect(find.text('구독하고 있지 않아요.'), findsOneWidget);
    expect(find.textContaining('에서 해지하기'), findsNothing);
    expect(find.text('구매 복원'), findsOneWidget);
    await _shot(t, '4-subscription-none');
  });

  testWidgets('선반 구매 시트: 상품·가격이 버튼 위에 있고 고지 문구가 있다', (t) async {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'products': [
        {'route': iapRoute, 'productId': 'shelf', 'kind': 'product', 'shelves': 1},
      ],
    }, save: false);
    IapService.instance.details = {'shelf': _detail('shelf', '추가 선반', '스토어 가격')};
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    // 상품과 가격은 옅은 세로줄로 나눈다(가운데 점을 쓰지 않는 앱 규칙). 화면 읽기는 쉼표로 읽는다
    final head = find.bySemanticsLabel('추가 선반 1칸, 스토어 가격');
    expect(head, findsOneWidget);
    expect(find.text('한 번 결제하면 계속 쓸 수 있습니다.'), findsOneWidget);
    expect(find.textContaining('환불 절차를 따릅니다'), findsOneWidget);
    expect(find.text('구매하기'), findsOneWidget);
    // 가격이 버튼보다 위에 있다
    expect(t.getTopLeft(head).dy, lessThan(t.getTopLeft(find.text('구매하기')).dy));
    expect(find.textContaining('·'), findsNothing);
    await _shot(t, '5-shelf-purchase');
  });

  testWidgets('선반 구매 시트: 스토어에서 가격을 못 받았으면 살 수 없다고 알린다', (t) async {
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.textContaining('지금은 선반을 구매할 수 없어요'), findsOneWidget);
    expect(find.text('구매하기'), findsNothing);
  });
}
