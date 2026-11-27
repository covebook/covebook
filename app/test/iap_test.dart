// 결제: 거래를 끝내도 되는 때, 선반 칸 수 계산, 서버 응답 반영, 구독 관리 화면과 선반 구매 시트.
// IAP_SHOTS=1로 돌리면 화면을 docs/screenshots/2026-11-19-iap/ 에 PNG로 남긴다(PR에 붙이는 그림).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart' show closeShelvesBeyond;
import 'package:chaekjang/domain/types.dart' show BookPlacement, Shelf;
import 'package:chaekjang/features/home/locked_rows.dart';
import 'package:chaekjang/features/iap/consent_screen.dart';
import 'package:chaekjang/features/iap/notice.dart';
import 'package:chaekjang/features/iap/notices_screen.dart';
import 'package:chaekjang/features/iap/plan_screen.dart';
import 'package:chaekjang/features/iap/purchase_history_screen.dart';
import 'package:chaekjang/features/iap/seller_sheet.dart';
import 'package:chaekjang/features/iap/shelf_purchase_sheet.dart';
import 'package:chaekjang/features/iap/subscription_screen.dart';
import 'package:chaekjang/features/iap/withdraw_notice.dart';
import 'package:chaekjang/services/iap.dart';
import 'package:chaekjang/services/renewal_reminder.dart';
import 'package:chaekjang/features/book/place_books.dart' show enforceShelfLimit;
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

/// 확인창의 글은 낱말 단위 줄바꿈 처리로 글자 사이에 보이지 않는 문자가 들어간다. 화면 읽기 이름으로 찾는다
Finder _says(String text) => find.bySemanticsLabel(RegExp(RegExp.escape(text)));

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(key: _root, child: MaterialApp(debugShowCheckedModeBanner: false, home: home)));
  await t.pumpAndSettle();
}

/// 스토어에서 받아 오기가 끝났는데 가격이 없는 상태를 흉내 낸다.
/// 실제 refresh는 기기 저장소를 읽어 가짜 시계 안에서 끝나지 않는다(앞 시험이 연 연결을 기다리다 멈춘다).
/// 그래서 loading을 켠 채 화면을 열어 refresh를 건너뛰게 하고, 여기서 끄고 화면에 알린다
Future<void> _refreshEndsEmpty(WidgetTester t) async {
  await t.pump();
  IapService.instance.loading = false;
  EntitlementStore.instance.apply({'products': const []}, save: false);
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
    ..entitlements = const {}
    ..unitsByTarget = const {}
    ..subscription = null
    ..products = const []
    ..seller = const {}
    ..accountToken = '';
  IapService.instance
    ..details = const {}
    ..plans = const []
    ..loading = false
    ..busy = false
    ..lastResult = null
    ..lastMessage = null;
}

void main() {
  setUpAll(_fonts);
  setUp(_reset);
  _resetAfterLogout();

  test('거래를 끝내도 되는 때: 지급됐거나, 다시 내도 결과가 같을 때만', () {
    expect(iapShouldFinish(status: 200), isTrue);
    expect(iapShouldFinish(status: 409, code: 'iap_purchase_refunded'), isTrue);
    expect(iapShouldFinish(status: 409, code: 'iap_other_account'), isTrue);
    expect(iapShouldFinish(status: 422, code: 'iap_purchase_rejected'), isTrue);
    expect(iapShouldFinish(status: 422, code: 'iap_sandbox_not_allowed'), isTrue);
    // 연도를 모르는 선반 거래: 서버가 소비하지 않고 돌려준다(연도와 함께 다시 내면 칸을 준다). 우리 상품 테이블에 없는 상품: 우리 설정 문제
    expect(iapShouldFinish(status: 422, code: 'iap_target_missing'), isFalse);
    expect(iapShouldFinish(status: 422, code: 'iap_unknown_product'), isFalse);
    // 다시 낼 수 있어야 하는 것: 결제 대기, 스토어 확인 실패, 요청 많음, 서버 오류, 없는 거래, 증거 확인 실패
    for (final (status, code) in [(202, ''), (503, 'iap_store_unavailable'), (429, 'iap_too_many'), (500, 'internal_error'), (404, 'iap_purchase_not_found'), (422, 'iap_bad_proof'), (401, 'unauthorized')]) {
      expect(iapShouldFinish(status: status, code: code), isFalse, reason: '$status $code');
    }
  });

  test('선반 칸 수: 무료 3칸 + 구매한 칸, 여섯 칸까지', () {
    expect(allowedShelfSlots(), 3);
    expect(allowedShelfSlots(1), 4);
    expect(allowedShelfSlots(3), 6);
    expect(allowedShelfSlots(9), 6); // 구매 기록이 더 많아도 여섯 칸을 넘지 않는다
    expect(openableShelfCount(1), 2);
    expect(openableShelfCount(3), 0);
    expect(openableShelfCount(3, 2), 2);
    expect(openableShelfCount(5, 2), 0);
    // 환불로 구매한 칸이 줄어 지금 선반이 더 많아도 음수가 되지 않는다
    expect(openableShelfCount(5, 0), 0);
    expect(purchasableShelfCount(), 3);
    expect(purchasableShelfCount(2), 1);
    expect(purchasableShelfCount(3), 0);
  });

  test('서버 응답 반영: 있는 칸만 바꾸고, 날짜는 받은 값 그대로', () {
    final e = EntitlementStore.instance;
    e.apply({
      'entitlements': ['plus'],
      'unitsByTarget': {'${liveShelfYear()}': 2, '2025': 1, 'x': 3, '2024': 0},
      'accountToken': 'a-token',
      'routes': ['apple', 'google'],
      'products': [
        {'route': 'apple', 'productId': 'shelf', 'kind': 'product', 'units': 1},
        {'route': 'apple', 'productId': 'plus', 'kind': 'subscription', 'entitlement': 'plus'},
        '깨진 줄',
      ],
      'subscription': {'route': 'apple', 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    expect((e.plus, e.shelves, e.accountToken, e.products.length), (true, 2, 'a-token', 2));
    // 연도 책장마다 따로: 0칸은 버리고, 연도가 아닌 대상('x')은 칸 계산에서 빠진다
    expect(e.shelvesByYear, {liveShelfYear(): 2, 2025: 1});
    expect((e.shelvesFor(2025), e.shelvesFor(2023), e.shelvesTotal, e.unitsFor('x')), (1, 0, 3, 3));
    expect(e.subscription!.expiresAt, DateTime.utc(2027, 1, 18, 3));
    expect(e.subscription!.statusLabel, '이용 중');
    // 구매 응답에는 계정 연결 값과 상품 목록이 없다. 그대로 남아야 한다
    e.apply({'status': 'granted', 'entitlements': <String>[], 'unitsByTarget': {'${liveShelfYear()}': 3}, 'subscription': null}, save: false);
    expect((e.plus, e.shelves, e.accountToken, e.products.length, e.subscription), (false, 3, 'a-token', 2, null));
    expect(e.shelvesFor(2025), 0); // 받은 표로 통째로 바꾼다
    // 키트는 대상을 문자열로 둔다. 연도가 아닌 대상은 책장 한켠의 칸 계산에서 빠진다
    e.apply({'unitsByTarget': {'x': 1}}, save: false);
    expect((e.unitsFor('x'), e.shelvesTotal), (1, 0));
    expect(e.shelvesByYear, isEmpty); // 레코드 안의 Map은 내용으로 비교되지 않아 따로 본다
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
      'entitlements': ['plus'],
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
      'entitlements': ['plus'],
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
      'entitlements': ['plus'],
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
    expect(find.text('요금제 보기'), findsOneWidget);
    await _shot(t, '4-subscription-none');
  });

  testWidgets('선반 구매 시트: 상품·가격이 버튼 위에 있고 고지 문구가 있다', (t) async {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'products': [
        {'route': iapRoute, 'productId': 'shelf', 'kind': 'product', 'units': 1},
      ],
    }, save: false);
    IapService.instance.details = {'shelf': _detail('shelf', '추가 선반', '스토어 가격')};
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    // 상품과 가격은 옅은 세로줄로 나눈다(가운데 점을 쓰지 않는 앱 규칙). 화면 읽기는 쉼표로 읽는다
    final head = find.bySemanticsLabel('${liveShelfYear()}년 책장, 추가 선반 1칸, 스토어 가격');
    expect(head, findsOneWidget);
    expect(find.text('한 번 결제하면 이 책장에서 계속 쓸 수 있습니다.'), findsOneWidget);
    expect(find.text('구매한 선반은 로그인한 계정에 기록되어 기기를 바꿔도 유지됩니다.'), findsOneWidget);
    expect(find.textContaining('환불 절차를 따릅니다'), findsOneWidget);
    expect(find.text(kIapMinorNote), findsOneWidget); // 미성년자 취소 고지(전자상거래법 제13조 제3항)
    expect(find.text('구매하기'), findsOneWidget);
    // 가격이 버튼보다 위에 있다
    expect(t.getTopLeft(head).dy, lessThan(t.getTopLeft(find.text('구매하기')).dy));
    expect(find.textContaining('·'), findsNothing);
    await _shot(t, '5-shelf-purchase');
  });

  testWidgets('선반 구매 시트: 스토어에서 가격을 못 받았으면 살 수 없다고 알린다', (t) async {
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showShelfPurchase(ctx))))));
    IapService.instance.loading = true;
    await t.tap(find.text('열기'));
    await _refreshEndsEmpty(t);
    expect(find.textContaining('지금은 선반을 구매할 수 없어요'), findsOneWidget);
    expect(find.text('구매하기'), findsNothing);
  });

  test('결제 주기: 월·연만 읽는다', () {
    expect(iapPeriodOf('P1M'), 'month');
    expect(iapPeriodOf('P1Y'), 'year');
    expect(iapPeriodOf('P1W'), '');
    expect(iapPlanOf(_detail('plus', '플러스', '스토어 가격')), isNull); // 스토어별 타입이 아니면 요금제로 보지 않는다
  });

  test('환불로 줄어든 칸: 그 아래 선반을 닫고 책은 보관으로, 무료 세 칸은 그대로', () {
    const shelves = [Shelf('s1', 0), Shelf('s2', 1), Shelf('s3', 2), Shelf('s4', 3), Shelf('s5', 4)];
    BookPlacement at(String book, String shelf) => BookPlacement(bookId: book, shelfId: shelf, order: 0, pos: 0);
    final l = ShelfLayout(shelves, [at('a', 's1'), at('b', 's3'), at('c', 's4'), at('d', 's5')], const ['z']);
    // 두 칸을 샀다가 둘 다 환불됐다: 넷째, 다섯째 선반이 닫힌다
    final next = closeShelvesBeyond(l, 3)!;
    expect([for (final s in next.shelves) s.id], ['s1', 's2', 's3']);
    expect([for (final p in next.placements) (p.bookId, p.shelfId)], [('a', 's1'), ('b', 's3')]);
    expect(next.drawer, containsAll(['c', 'd', 'z']));
    // 한 칸만 환불: 다섯째만 닫힌다
    final one = closeShelvesBeyond(l, 4)!;
    expect([for (final s in one.shelves) s.id], ['s1', 's2', 's3', 's4']);
    expect(one.drawer, containsAll(['d', 'z']));
    expect(one.drawer.contains('c'), isFalse);
    // 닫을 것이 없으면 건드리지 않는다
    expect(closeShelvesBeyond(l, 5), isNull);
    expect(closeShelvesBeyond(next, 3), isNull);
  });

  void plans() {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'products': [
        {'route': iapRoute, 'productId': 'plus', 'kind': 'subscription'},
      ],
    }, save: false);
    IapService.instance.plans = [
      IapPlan(details: _detail('plus', '플러스', '월 스토어 가격'), period: 'month'),
      IapPlan(details: _detail('plus', '플러스', '연 스토어 가격'), period: 'year'),
    ];
  }

  testWidgets('구독 결제 화면: 요금제를 미리 골라 두지 않고, 고르기 전에는 결제할 수 없다', (t) async {
    plans();
    await _pump(t, const PlanScreen());
    expect(find.bySemanticsLabel('월간, 월 스토어 가격 / 매월'), findsOneWidget);
    expect(find.bySemanticsLabel('연간, 연 스토어 가격 / 매년'), findsOneWidget);
    // 아무것도 골라져 있지 않다
    expect(t.widgetList<Choice>(find.byType(Choice)).every((c) => !c.selected), isTrue);
    expect(find.textContaining('자동으로 결제됩니다'), findsNothing);
    expect(t.widget<Btn>(find.widgetWithText(Btn, '구독하기')).disabled, isTrue);
    await _shot(t, '6-plans-none-picked');
  });

  testWidgets('구독 결제 화면: 고르면 가격·주기·갱신·해지 조건이 버튼 위에 나온다', (t) async {
    plans();
    await _pump(t, const PlanScreen());
    await t.tap(find.bySemanticsLabel('연간, 연 스토어 가격 / 매년'));
    await t.pumpAndSettle();
    final head = find.bySemanticsLabel('책장 한켠 플러스 연간, 연 스토어 가격 / 매년');
    expect(head, findsOneWidget);
    for (final text in ['매년 자동으로 결제됩니다.', '24시간 전까지 해지하지 않으면', '구독 관리에서 할 수 있습니다', '이미 결제한 기간이 끝날 때까지', '환불 절차를 따릅니다', kIapMinorNote]) {
      expect(find.textContaining(text), findsOneWidget, reason: text);
    }
    final button = find.widgetWithText(Btn, '구독하기');
    expect(t.widget<Btn>(button).disabled, isFalse);
    // 조건이 버튼보다 위에 있다
    expect(t.getTopLeft(head).dy, lessThan(t.getTopLeft(button).dy));
    expect(t.getTopLeft(find.textContaining('환불 절차를 따릅니다')).dy, lessThan(t.getTopLeft(button).dy));
    expect(find.textContaining('·'), findsNothing);
    await _shot(t, '7-plans-picked');
  });

  testWidgets('구독 결제 화면: 이미 구독 중이면 구독 버튼이 없다', (t) async {
    plans();
    EntitlementStore.instance.apply({
      'entitlements': ['plus'],
      'subscription': {'route': iapRoute == 'apple' ? 'google' : 'apple', 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    await _pump(t, const PlanScreen());
    expect(find.text('구독하기'), findsNothing);
    expect(find.textContaining('에서 구독하고 있는 계정이에요'), findsOneWidget);
    expect(find.text('구독 관리'), findsOneWidget);
    await _shot(t, '8-plans-already');
  });

  testWidgets('구독 결제 화면: 스토어에서 요금제를 못 받았으면 구독할 수 없다고 알린다', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    IapService.instance.loading = true;
    await t.pumpWidget(const MaterialApp(home: PlanScreen()));
    await _refreshEndsEmpty(t);
    expect(find.textContaining('지금은 구독할 수 없어요'), findsOneWidget);
    expect(find.text('구독하기'), findsNothing);
  });

  test('구매 내역 한 줄: 서버 값 그대로, 금액은 있을 때만', () {
    final a = IapHistoryItem.from({'route': 'apple', 'productId': 'shelf', 'kind': 'product', 'state': 'paid', 'purchasedAt': '2026-11-19T03:00:00Z', 'units': 1, 'currency': 'USD', 'priceMilli': 1234500})!;
    expect((a.name, a.stateLabel, a.price), ('추가 선반 1칸', '결제 완료', '1,234.5 USD'));
    final b = IapHistoryItem.from({'route': 'google', 'productId': 'plus', 'kind': 'subscription', 'state': 'revoked', 'purchasedAt': '2026-11-19T03:00:00Z', 'revokedAt': '2026-11-20T03:00:00Z'})!;
    expect((b.name, b.stateLabel, b.price), ('책장 한켠 플러스', '환불됨', null));
    expect(b.line, contains('환불일'));
    expect(IapHistoryItem.from({'purchasedAt': '날짜가 아님'}), isNull);
  });

  testWidgets('구매 내역: 결제일·상품·상태를 보여 주고 복사할 수 있다', (t) async {
    await _pump(
      t,
      PurchaseHistoryScreen(items: [
        IapHistoryItem(route: iapRoute, productId: 'plus', kind: 'subscription', state: 'paid', purchasedAt: DateTime.utc(2026, 12, 18, 3)),
        IapHistoryItem(route: iapRoute, productId: 'plus', kind: 'subscription', state: 'paid', purchasedAt: DateTime.utc(2026, 11, 18, 3)),
        IapHistoryItem(route: iapRoute, productId: 'shelf', kind: 'product', state: 'revoked', purchasedAt: DateTime.utc(2026, 11, 10, 3), revokedAt: DateTime.utc(2026, 11, 12, 3), shelves: 1),
      ]),
    );
    expect(find.text('책장 한켠 플러스'), findsNWidgets(2));
    expect(find.text('추가 선반 1칸'), findsOneWidget);
    expect(find.text('환불됨'), findsOneWidget);
    expect(find.text('환불일 2026년 11월 12일'), findsOneWidget);
    expect(find.text('내역 복사'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    await _shot(t, '9-purchase-history');
  });

  testWidgets('구매 내역: 없으면 없다고 알린다', (t) async {
    await _pump(t, const PurchaseHistoryScreen(items: []));
    expect(find.text('구매한 것이 없어요.'), findsOneWidget);
    expect(find.text('내역 복사'), findsNothing);
  });

  testWidgets('사업자 정보: 서버가 준 항목만 정해진 순서로', (t) async {
    expect(hasSellerInfo, isFalse);
    // 시험용 가짜 값(실제 사업자 정보는 저장소에 적지 않는다)
    EntitlementStore.instance.apply({
      'seller': {'name': '시험 상호', 'owner': '홍길동', 'address': '시험시 시험구 시험로 1', 'phone': '000-0000-0000', 'email': 'test@example.com', 'bizNo': '000-00-00000', 'saleNo': '제0000-시험-0000호', 'host': '시험 호스팅', 'memo': ''},
    }, save: false);
    expect(hasSellerInfo, isTrue);
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showSellerSheet(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    for (final label in ['상호', '대표자', '주소', '전화번호', '전자우편', '사업자등록번호', '통신판매업 신고번호', '호스팅서비스 제공자']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('시험 상호'), findsOneWidget);
    await _shot(t, '10-seller');
  });

  testWidgets('탈퇴 안내: 구독이 해지되지 않는다고 알리고, 탈퇴를 막지 않는다', (t) async {
    final sub = IapSubscription(route: iapRoute, productId: 'plus', state: 'paid', active: true, autoRenew: true, expiresAt: DateTime.utc(2027, 1, 18));
    var continued = 0;
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showWithdrawNotice(ctx, sub, onContinue: () => continued++))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(_says('구독은 자동으로 해지되지 않습니다'), findsOneWidget);
    expect(find.textContaining('에서 해지하기'), findsOneWidget);
    await _shot(t, '11-withdraw-notice');
    await t.tap(find.text('탈퇴 계속'));
    await t.pumpAndSettle();
    expect(continued, 1);
    expect(find.text('탈퇴 계속'), findsNothing);
  });

  test('상태 변화 알림: 지난번과 달라진 것만, 처음 보는 계정은 알리지 않는다', () {
    const none = IapSnapshot(plus: false, shelves: 0);
    const plus = IapSnapshot(plus: true, shelves: 0);
    expect(iapNoticeFor(null, plus), isNull);
    expect(iapNoticeFor(plus, plus), isNull);
    expect(iapNoticeFor(none, plus), isNull); // 새로 구독한 것은 결제한 화면에서 알린다
    expect(iapNoticeFor(plus, none, subState: 'inactive'), IapNoticeKind.expired);
    expect(iapNoticeFor(plus, none, subState: 'revoked'), IapNoticeKind.subscriptionRefunded);
    expect(iapNoticeFor(const IapSnapshot(plus: false, shelves: 2), const IapSnapshot(plus: false, shelves: 1)), IapNoticeKind.shelfRefunded);
    // 결제 실패 유예: 같은 유예는 한 번만
    const grace = IapSnapshot(plus: true, shelves: 0, grace: '2027-02-03T03:00:00.000Z');
    expect(iapNoticeFor(plus, grace), IapNoticeKind.paymentFailed);
    expect(iapNoticeFor(grace, grace), isNull);
    // 남겼다가 다시 읽어도 같다. 깨진 값은 없는 것으로 본다
    final back = IapSnapshot.parse(grace.encode())!;
    expect((back.plus, back.shelves, back.grace), (true, 0, grace.grace));
    expect(IapSnapshot.parse('깨짐'), isNull);
  });

  final noticeSub = IapSubscription(route: iapRoute, productId: 'plus', state: 'paid', active: true, autoRenew: true, expiresAt: DateTime.utc(2027, 1, 18, 3), graceUntil: DateTime.utc(2027, 2, 3, 3));
  for (final (kind, shot, texts) in [
    (IapNoticeKind.paymentFailed, '13-notice-payment-failed', ['결제가 이뤄지지 않았습니다', '2027년 2월 3일까지는 계속 이용할 수 있습니다.', '결제 수단 확인하기', '나중에']),
    (IapNoticeKind.expired, '14-notice-expired', ['구독이 끝났습니다', '만든 책장과 기록은 그대로 있습니다.', '확인']),
    (IapNoticeKind.subscriptionRefunded, '15-notice-subscription-refunded', ['환불 처리됐습니다', '구독이 종료됐습니다.', '확인']),
    (IapNoticeKind.shelfRefunded, '16-notice-shelf-refunded', ['추가 선반 결제가 환불 처리됐습니다', '꽂혀 있던 책은 내 책에 보관했습니다.', '확인']),
  ]) {
    testWidgets('상태 변화 알림 화면: ${kind.name}', (t) async {
      await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showIapNotice(ctx, iapNoticeOf(kind, noticeSub)))))));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      for (final text in texts) {
        expect(_says(text), findsWidgets, reason: text);
      }
      // 거래 고지에 권유 문장을 넣지 않는다
      expect(_says('다시 구독'), findsNothing);
      expect(_says('·'), findsNothing);
      await _shot(t, shot);
      // 아래 시트가 아니라 가운데 창이다
      final box = t.getRect(_says(texts.first).first);
      expect(box.center.dy, lessThan(t.view.physicalSize.height / t.view.devicePixelRatio * 0.6));
      await t.tap(find.text(texts.last));
      await t.pumpAndSettle();
      expect(_says(texts.first), findsNothing);
    });
  }

  test('기기에 남긴 권한(plus)은 스토어가 준 만료(유예 포함)까지만 믿는다', () {
    final now = DateTime.utc(2026, 11, 26, 12);
    IapSubscription? sub(String expires, [String? grace]) => IapSubscription.from({'expiresAt': expires, 'graceUntil': grace});
    expect(iapCachedEntitlementsValid(subscription: sub('2026-11-27T00:00:00Z'), now: now), isTrue);
    expect(iapCachedEntitlementsValid(subscription: sub('2026-11-26T00:00:00Z'), now: now), isFalse);
    expect(iapCachedEntitlementsValid(subscription: sub('2026-11-26T00:00:00Z', '2026-12-10T00:00:00Z'), now: now), isTrue, reason: '유예 중');
    expect(iapCachedEntitlementsValid(subscription: null, now: now), isTrue, reason: '구독 정보가 없는 옛 사본');
  });

  group('알림함', () {
    IapNotice n(int id, String kind, String at, {bool read = false, Map<String, dynamic> params = const {}}) => IapNotice.from({
          'id': id,
          'kind': kind,
          'template': 'T',
          'createdAt': at,
          if (read) 'readAt': at,
          'params': params,
        })!;
    final list = [
      n(6, 'renewal_upcoming', '2027-02-15T01:00:00Z', read: true, params: {'route': iapRoute, 'productId': 'plus', 'expiresAt': '2027-03-01T00:00:00Z', 'period': 'year'}),
      n(5, 'payment_failed', '2027-01-18T03:00:00Z', params: {'route': iapRoute, 'productId': 'plus', 'graceUntil': '2027-02-03T03:00:00Z'}),
      n(4, 'cancel_scheduled', '2027-01-10T03:00:00Z', read: true, params: {'route': iapRoute, 'expiresAt': '2027-01-18T03:00:00Z'}),
      n(3, 'product_refunded', '2027-01-05T03:00:00Z', read: true, params: {'route': iapRoute}),
      n(2, 'purchase_done', '2026-12-18T03:00:00Z', read: true, params: {'kind': 'subscription', 'expiresAt': '2027-01-18T03:00:00Z'}),
      n(1, 'purchase_done', '2026-12-01T03:00:00Z', read: true, params: {'kind': 'product', 'units': 1}),
    ];

    test('서버 고지를 읽는다. 모르는 종류와 깨진 줄은 보이지 않는다', () {
      expect(IapNotice.from({'id': 1}), isNull);
      expect(IapNotice.from('깨짐'), isNull);
      expect(n(9, 'future_kind', '2027-01-01T00:00:00Z').text, isNull);
      expect(list[1].unread, isTrue);
      expect(list[2].unread, isFalse);
      expect(list[2].text!.$1, contains('자동 갱신이 꺼졌습니다'));
      expect(list[2].text!.$2, contains('2027년 1월 18일까지 이용할 수 있습니다'));
      expect(list[5].text!.$2, '선반 1칸을 더 열 수 있습니다. $kIapContractNote');
      // 구독 결제 완료(T3)에는 결제일이 있다(고지가 쓰인 날)
      expect(list[4].text!.$2, contains('결제일은 2026년 12월'));
      expect(list[3].text!.$2, contains('선반이 잠겼습니다'));
      // 칸을 연 적 없는 선반의 환불: 잠겼다고 하지 않는다
      final unopened = n(7, 'product_refunded', '2027-01-06T03:00:00Z', params: {'route': iapRoute, 'opened': false}).text!.$2;
      expect(unopened, contains('선반을 열지 않고 환불했습니다'));
      expect(unopened, isNot(contains('잠겼습니다')));
      // 고지에 금액은 넣지 않는다(서버가 주지 않고, 금액은 결제한 스토어가 정한다)
      for (final x in list) {
        expect(x.text!.$2.contains(RegExp(r'\d\s*원')), isFalse, reason: x.kind);
      }
    });

    test('앱을 열 때 띄우는 것은 안 읽은 중요한 고지 하나(가장 새것)', () {
      expect(iapNoticeToShow(list)!.id, 5);
      expect(iapNoticeToShow([list[0], ...list.skip(2)]), isNull); // 다 읽었으면 없다
      // 해지 접수·결제 완료는 알림함에만 둔다
      expect(iapNoticeToShow([n(7, 'cancel_scheduled', '2027-01-20T00:00:00Z'), n(8, 'purchase_done', '2027-01-21T00:00:00Z')]), isNull);
      final two = [n(10, 'expired', '2027-01-01T00:00:00Z'), n(11, 'product_refunded', '2027-01-02T00:00:00Z')];
      expect(iapNoticeToShow(two)!.id, 11);
    });

    testWidgets('알림 화면: 새 알림 표시, 날짜, 권유 문장 없음', (t) async {
      await _pump(t, NoticesScreen(items: list));
      expect(_says('새 알림'), findsOneWidget);
      expect(_says('결제가 이뤄지지 않았습니다'), findsWidgets);
      expect(_says('자동 갱신이 꺼졌습니다'), findsWidgets);
      expect(_says('2027년 1월 18일'), findsWidgets);
      expect(_says('다시 구독'), findsNothing);
      await _shot(t, '21-notices');
    });

    testWidgets('알림 화면: 받은 알림이 없을 때', (t) async {
      await _pump(t, const NoticesScreen(items: []));
      expect(_says('받은 알림이 없어요'), findsOneWidget);
      await _shot(t, '22-notices-empty');
    });
  });

  group('갱신 전 알림(L9, T4)', () {
    IapSubscription sub({String period = 'year', bool autoRenew = true, bool active = true, DateTime? grace}) => IapSubscription(
          route: iapRoute,
          productId: 'plus',
          state: 'paid',
          active: active,
          autoRenew: autoRenew,
          expiresAt: DateTime(2027, 3, 1, 9),
          graceUntil: grace,
          period: period,
        );
    final now = DateTime(2027, 1, 20);

    test('연 구독·자동 갱신·이용 중일 때만, 결제일 14일 전 오전 10시', () {
      expect(renewalReminderAt(sub(), now), DateTime(2027, 2, 15, 10));
      expect(renewalReminderAt(sub(period: 'month'), now), isNull); // 월 구독은 보내지 않는다
      expect(renewalReminderAt(sub(period: ''), now), isNull); // 주기를 모르면 보내지 않는다
      expect(renewalReminderAt(sub(autoRenew: false), now), isNull); // 해지 예약
      expect(renewalReminderAt(sub(active: false), now), isNull);
      expect(renewalReminderAt(sub(grace: DateTime(2027, 3, 10)), now), isNull); // 결제 실패 유예 중
      expect(renewalReminderAt(sub(), DateTime(2027, 2, 16)), isNull); // 이미 지났다
      expect(renewalReminderAt(null, now), isNull);
    });

    test('알림 글: 갱신일, 금액(알 때만), 하루 전까지 해지할 수 있다는 안내. 권유 문장 없음', () {
      final (title, body) = renewalReminderText(sub(), price: '스토어 가격');
      expect(title, '책장 한켠 플러스가 2027년 3월 1일에 갱신됩니다');
      expect(body, contains('결제 예정 금액은 스토어 가격입니다.'));
      expect(body, contains('2027년 2월 28일까지 내 정보 › 구독 관리에서 해지할 수 있습니다.'));
      expect(renewalReminderText(sub()).$2, isNot(contains('결제 예정 금액')));
    });

    test('알림함의 갱신 예정 고지: 창으로 띄우지 않고 알림함에만', () {
      final n = IapNotice.from({
        'id': 30,
        'kind': 'renewal_upcoming',
        'createdAt': '2027-02-15T01:00:00Z',
        'params': {'route': iapRoute, 'productId': 'plus', 'expiresAt': '2027-03-01T00:00:00Z', 'period': 'year'},
      })!;
      expect(n.text!.$1, contains('갱신됩니다'));
      expect(n.text!.$2, contains('구독 관리에서 해지할 수 있습니다'));
      expect(n.important, isFalse);
      expect(iapNoticeToShow([n]), isNull);
    });
  });

  testWidgets('결제 완료: 결제한 화면에서 금액, 다음 결제일, 해지하는 곳을 알린다', (t) async {
    plans();
    await _pump(t, const PlanScreen());
    await t.tap(find.bySemanticsLabel('월간, 월 스토어 가격 / 매월'));
    await t.pumpAndSettle();
    // 서버가 지급했다고 답한 순간
    IapService.instance.lastResult = IapResult.granted;
    EntitlementStore.instance.apply({
      'entitlements': ['plus'],
      'subscription': {'route': iapRoute, 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    await t.pumpAndSettle();
    expect(_says('결제가 완료됐습니다'), findsOneWidget);
    expect(_says('결제 금액 월 스토어 가격'), findsOneWidget);
    expect(_says('다음 결제일 2027년 1월 18일'), findsOneWidget);
    expect(_says('해지는 내 정보의 구독 관리에서'), findsOneWidget);
    await _shot(t, '12-purchase-done');
  });

  testWidgets('결제 대기: 실패가 아니라 기다리는 중이라고 알리고 버튼을 잠그지 않는다', (t) async {
    plans();
    IapService.instance
      ..lastResult = IapResult.pending
      ..lastMessage = '결제가 끝나면 자동으로 반영돼요. 이 화면을 닫아도 돼요.';
    await _pump(t, const PlanScreen());
    await t.tap(find.bySemanticsLabel('월간, 월 스토어 가격 / 매월'));
    await t.pumpAndSettle();
    expect(find.textContaining('결제가 끝나면 자동으로 반영돼요'), findsOneWidget);
    expect(t.widget<Btn>(find.widgetWithText(Btn, '구독하기')).disabled, isFalse);
    await _shot(t, '17-plans-pending');
  });

  testWidgets('이전 작업의 결과: 화면을 새로 열면 지난 오류 문구는 보이지 않는다', (t) async {
    plans();
    IapService.instance
      ..lastResult = IapResult.retryLater
      ..lastMessage = '지난번 결제를 시작하지 못했어요.';
    await _pump(t, const PlanScreen());
    expect(find.textContaining('지난번 결제를 시작하지 못했어요'), findsNothing);
    expect(IapService.instance.lastResult, isNull);
  });

  testWidgets('불러오는 중: 요금제를 받는 동안은 구독할 수 없다고 하지 않는다', (t) async {
    IapService.instance.loading = true;
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: PlanScreen()));
    await t.pump();
    expect(find.byType(Loading), findsOneWidget);
    expect(find.textContaining('지금은 구독할 수 없어요'), findsNothing);
  });

  test('선반 상품: 그 해에 산 칸과 합쳐 3칸을 넘는 상품은 팔지 않는다(3칸 묶음은 산 칸이 없는 해에만)', () {
    const one = IapProduct(route: 'apple', productId: 'shelf1', kind: 'product', units: 1);
    const three = IapProduct(route: 'apple', productId: 'shelf3', kind: 'product', units: 3);
    const plus = IapProduct(route: 'apple', productId: 'plus', kind: 'subscription');
    List<int> offers(int paid) => [for (final p in shelfOffers(const [three, plus, one], paid: paid)) p.shelves];
    expect(offers(0), [1, 3]);
    expect(offers(1), [1]);
    expect(offers(2), [1]);
    expect(offers(3), isEmpty);
  });

  testWidgets('선반 구매 시트: 상품이 여럿이면 고르게 하고, 미리 골라 두지 않는다', (t) async {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'unitsByTarget': {'2025': 3}, // 지난해 책장에 산 칸은 올해 책장과 상관없다
      'products': [
        {'route': iapRoute, 'productId': 'shelf3', 'kind': 'product', 'units': 3},
        {'route': iapRoute, 'productId': 'shelf1', 'kind': 'product', 'units': 1},
      ],
    }, save: false);
    IapService.instance.details = {'shelf1': _detail('shelf1', '추가 선반', '한 칸 스토어 가격'), 'shelf3': _detail('shelf3', '추가 선반', '세 칸 스토어 가격')};
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(t.widgetList<Choice>(find.byType(Choice)).map((c) => (c.label, c.selected)), [('추가 선반 1칸', false), ('추가 선반 3칸', false)]);
    expect(t.widget<Btn>(find.widgetWithText(Btn, '구매하기')).disabled, isTrue);
    final y = liveShelfYear();
    expect(find.textContaining('$y년 책장에 선반을 엽니다'), findsOneWidget);
    expect(find.textContaining('로그인하지 않고'), findsNothing);
    await t.tap(find.bySemanticsLabel('추가 선반 3칸, 세 칸 스토어 가격'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('$y년 책장, 추가 선반 3칸, 세 칸 스토어 가격'), findsOneWidget); // 버튼 위의 연도·상품·가격 줄
    expect(find.textContaining('$y년 책장에 선반 3칸을 엽니다. 다른 해의 책장에는 열리지 않습니다.'), findsOneWidget);
    expect(t.widget<Btn>(find.widgetWithText(Btn, '구매하기')).disabled, isFalse);
    await _shot(t, '18-shelf-purchase-options');
  });

  testWidgets('선반 구매 시트: 구매가 끝나 칸이 늘면 닫히고, 샀다고 알려 준다', (t) async {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'unitsByTarget': {'${liveShelfYear()}': 1},
      'products': [
        {'route': iapRoute, 'productId': 'shelf', 'kind': 'product', 'units': 1},
      ],
    }, save: false);
    IapService.instance.details = {'shelf': _detail('shelf', '추가 선반', '스토어 가격')};
    bool? bought;
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () async => bought = await showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('구매하기'), findsOneWidget);
    EntitlementStore.instance.apply({'status': 'granted', 'unitsByTarget': {'${liveShelfYear()}': 2}}, save: false);
    await t.pumpAndSettle();
    expect(find.text('구매하기'), findsNothing);
    expect(bought, isTrue);
  });

  test('구독 관리의 결제 금액: 구글은 요금제 ID로 찾고, 가려낼 수 없으면 보이지 않는다', () {
    final iap = IapService.instance;
    IapSubscription sub(String plan) => IapSubscription(route: 'google', productId: 'plus', planId: plan, state: 'paid', active: true, autoRenew: true, expiresAt: DateTime.utc(2027, 1, 18));
    iap.plans = [
      IapPlan(details: _detail('plus', '플러스', '월 가격'), period: 'month', planId: 'monthly'),
      IapPlan(details: _detail('plus', '플러스', '연 가격'), period: 'year', planId: 'yearly'),
    ];
    iap.details = {'plus': _detail('plus', '플러스', '월 가격')};
    expect(iapPriceOf(iap, sub('yearly')), '연 가격');
    expect(iapPriceOf(iap, sub('monthly')), '월 가격');
    expect(iapPriceOf(iap, sub('없는 요금제')), isNull);
    expect(iapPriceOf(iap, sub('')), isNull); // 요금제를 모르는데 후보가 둘이면 고르지 않는다
    // 애플: 상품 ID가 곧 요금제
    iap.plans = [IapPlan(details: _detail('plus', '플러스', '월 가격'), period: 'month')];
    expect(iapPriceOf(iap, sub('')), '월 가격');
    iap.plans = const [];
    expect(iapPriceOf(iap, sub('')), '월 가격');
  });

  for (final (name, shot, accept, open) in [
    (
      '가격 변경 동의',
      '19-consent-price-change',
      '바뀐 가격에 동의',
      (BuildContext ctx) => openPriceChangeConsent(ctx, product: '책장 한켠 플러스', period: '매월', oldPrice: '지금 스토어 가격', newPrice: '새 스토어 가격', effectiveAt: DateTime.utc(2027, 3, 1, 3), expiresAt: DateTime.utc(2027, 3, 18, 3)),
    ),
    (
      '유료 전환 동의',
      '20-consent-trial',
      '유료 전환에 동의',
      (BuildContext ctx) => openTrialConversionConsent(ctx, convertAt: DateTime.utc(2027, 1, 25, 3), price: '스토어 가격', period: '매월'),
    ),
  ]) {
    testWidgets('$name: 동의와 거절이 같은 크기·같은 모양이고, 답을 그대로 돌려준다', (t) async {
      final answers = <bool?>[];
      await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () async => answers.add(await open(ctx)))))));
      Future<void> show() async {
        await t.tap(find.text('열기'));
        await t.pumpAndSettle();
      }

      await show();
      final no = find.widgetWithText(Btn, '동의하지 않음'), yes = find.widgetWithText(Btn, accept);
      expect(t.getSize(no), t.getSize(yes));
      expect(t.widget<Btn>(no).kind, t.widget<Btn>(yes).kind);
      expect(t.getTopLeft(no).dy, t.getTopLeft(yes).dy);
      expect(find.textContaining('동의로 봅니다'), findsNothing);
      // 줄 값이 잘리지 않는다
      for (final v in t.widgetList<ListItem>(find.byType(ListItem))) {
        expect(find.text(v.value!), findsOneWidget);
        expect(v.value!.length, lessThan(22), reason: v.value);
      }
      expect(find.textContaining('·'), findsNothing);
      await _shot(t, shot);
      await t.tap(no);
      await t.pumpAndSettle();
      await show();
      await t.tap(yes);
      await t.pumpAndSettle();
      // 답하지 않고 뒤로 가면 답이 없는 것이다(거절로도 동의로도 치지 않는다)
      await show();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(answers, [false, true, null]);
    });
  }

  test('연도 책장 표시: 선반 환불·구매 고지와 구매 내역에 해가 보인다', () {
    IapNotice n(String kind, Map<String, dynamic> params) =>
        IapNotice.from({'id': 1, 'kind': kind, 'createdAt': '2026-11-19T03:00:00Z', 'params': {'route': 'apple', ...params}})!;
    expect(n('product_refunded', {'target': '2026', 'revokedAt': '2026-11-19T03:00:00Z'}).text!.$2, contains('2026년 책장의 선반이 잠겼습니다'));
    expect(n('product_refunded', {}).text!.$2, contains('해당 선반이 잠겼습니다'));
    expect(n('purchase_done', {'kind': 'product', 'units': 3, 'target': '2027'}).text!.$2, '2027년 책장의 선반 3칸을 더 열 수 있습니다. $kIapContractNote');
    final h = IapHistoryItem.from({'route': 'apple', 'productId': 'shelf3', 'kind': 'product', 'state': 'paid', 'purchasedAt': '2026-11-19T03:00:00Z', 'units': 3, 'target': '2026'})!;
    expect(h.name, '2026년 책장 추가 선반 3칸');
    // 해가 바뀌어 올해 칸이 0이 돼도 상태 비교는 모든 해의 합이라 환불로 보지 않는다
    final e = EntitlementStore.instance..apply({'unitsByTarget': {'${liveShelfYear() - 1}': 2}}, save: false);
    expect((e.shelves, IapSnapshot.of(e).shelves), (0, 2));
  });

  test('넘은 선반 결제 고지: 구글은 자동 환불, 애플은 환불 요청 안내', () {
    IapNotice n(String route, {bool auto = false}) => IapNotice.from({
          'id': 9,
          'kind': 'product_over_cap',
          'createdAt': '2026-11-19T03:00:00Z',
          'params': {'route': route, 'productId': 'shelf3', 'target': '2026', 'units': 3, 'autoRefund': auto},
        })!;
    final g = n('google', auto: true);
    expect(g.important, isTrue);
    expect(g.text!.$1, '추가 선반이 열리지 않았습니다');
    expect(g.text!.$2, '2026년 책장은 다른 기기에서 먼저 결제해 유료 선반 3칸이 모두 열려 있었습니다. 이번 결제(선반 3칸)는 자동으로 환불했습니다. 환불 금액과 시기는 Google Play에서 확인할 수 있습니다.');
    expect(n('google').text!.$2, endsWith('이번 결제(선반 3칸)는 환불해 드립니다. 처리되면 Google Play에서 확인할 수 있습니다.'));
    expect(n('apple').text!.$2, endsWith('Apple의 문제 신고 페이지에서 이 구매를 골라 환불을 요청해 주세요.'));
  });

  testWidgets('넘은 선반 결제 창(애플): 환불 요청 단추와 나중에', (t) async {
    final n = IapNotice.from({
      'id': 9,
      'kind': 'product_over_cap',
      'createdAt': '2026-11-19T03:00:00Z',
      'params': {'route': 'apple', 'productId': 'shelf1', 'target': '2026', 'units': 1},
    })!;
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showIapNotice(ctx, n))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(_says('추가 선반이 열리지 않았습니다'), findsWidgets);
    expect(_says('Apple에 환불 요청하기'), findsWidgets);
    expect(_says('나중에'), findsWidgets);
    await _shot(t, '26-notice-shelf-over-cap');
    await t.tap(find.text('나중에'));
    await t.pumpAndSettle();
    expect(_says('추가 선반이 열리지 않았습니다'), findsNothing);
  });
}

void _resetAfterLogout() {
  test('로그아웃 초기화: 앞 계정의 서버 상태 표시를 지워, 새 계정 상태를 받기 전에는 선반을 닫지 않는다', () async {
    final s = IapService.instance
      ..synced = true
      ..details = {'shelf': _detail('shelf', '추가 선반', '스토어 가격')}
      ..plans = [IapPlan(details: _detail('plus', '플러스', '월 스토어 가격'), period: 'month')]
      ..busy = true
      ..lastResult = IapResult.granted
      ..lastMessage = '앞 계정의 결과';
    s.loading = true; // 앞 계정의 refresh가 아직 도는 중
    s.reset();
    // 새 계정의 refresh가 막히지 않게 푼다(앞 계정의 응답은 세대 번호가 달라 버린다)
    expect(s.loading, isFalse);
    expect(s.synced, isFalse);
    expect(s.details, isEmpty);
    expect(s.plans, isEmpty);
    expect(s.busy, isFalse);
    expect(s.lastResult, isNull);
    expect(s.lastMessage, isNull);
    // synced가 false면 칸 수가 비어 있어도 선반을 닫지 않는다
    expect(await enforceShelfLimit(), 0);
  }, skip: !iapOn);
}
