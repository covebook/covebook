// 결제: 거래를 끝내도 되는 때, 선반 칸 수 계산, 서버 응답 반영, 구독 관리 화면과 선반 구매 시트.
// IAP_SHOTS=1로 돌리면 화면을 docs/screenshots/2026-11-19-iap/ 에 PNG로 남긴다(PR에 붙이는 그림).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chaekjang/features/home/locked_rows.dart';
import 'package:chaekjang/features/iap/notice.dart';
import 'package:chaekjang/features/iap/plan_screen.dart';
import 'package:chaekjang/features/iap/purchase_history_screen.dart';
import 'package:chaekjang/features/iap/seller_sheet.dart';
import 'package:chaekjang/features/iap/shelf_purchase_sheet.dart';
import 'package:chaekjang/features/iap/subscription_screen.dart';
import 'package:chaekjang/features/iap/withdraw_notice.dart';
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

/// 확인창의 글은 낱말 단위 줄바꿈 처리로 글자 사이에 보이지 않는 문자가 들어간다. 화면 읽기 이름으로 찾는다
Finder _says(String text) => find.bySemanticsLabel(RegExp(RegExp.escape(text)));

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
    expect(find.text('요금제 보기'), findsOneWidget);
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

  test('결제 주기: 월·연만 읽는다', () {
    expect(iapPeriodOf('P1M'), 'month');
    expect(iapPeriodOf('P1Y'), 'year');
    expect(iapPeriodOf('P1W'), '');
    expect(iapPlanOf(_detail('plus', '플러스', '스토어 가격')), isNull); // 스토어별 타입이 아니면 요금제로 보지 않는다
  });

  test('환불로 잠긴 선반: 쓸 수 있는 칸 아래의 선반', () {
    // 두 칸을 샀다가 환불돼 구매한 칸이 0이 됐다: 넷째, 다섯째 선반이 잠긴다
    expect([for (var i = 0; i < 5; i++) shelfLockedAt(i, 0)], [false, false, false, true, true]);
    expect([for (var i = 0; i < 5; i++) shelfLockedAt(i, 1)], [false, false, false, false, true]);
    expect(shelfLockedAt(4, 2), isFalse);
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
    for (final text in ['매년 자동으로 결제됩니다.', '24시간 전까지 해지하지 않으면', '구독 관리에서 할 수 있습니다', '이미 결제한 기간이 끝날 때까지', '환불 절차를 따릅니다']) {
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
      'plus': true,
      'subscription': {'route': iapRoute == 'apple' ? 'google' : 'apple', 'productId': 'plus', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2027-01-18T03:00:00Z'},
    }, save: false);
    await _pump(t, const PlanScreen());
    expect(find.text('구독하기'), findsNothing);
    expect(find.textContaining('에서 구독하고 있는 계정이에요'), findsOneWidget);
    expect(find.text('구독 관리'), findsOneWidget);
    await _shot(t, '8-plans-already');
  });

  testWidgets('구독 결제 화면: 스토어에서 요금제를 못 받았으면 구독할 수 없다고 알린다', (t) async {
    await _pump(t, const PlanScreen());
    expect(find.textContaining('지금은 구독할 수 없어요'), findsOneWidget);
    expect(find.text('구독하기'), findsNothing);
  });

  test('구매 내역 한 줄: 서버 값 그대로, 금액은 있을 때만', () {
    final a = IapHistoryItem.from({'route': 'apple', 'productId': 'shelf', 'kind': 'product', 'state': 'paid', 'purchasedAt': '2026-11-19T03:00:00Z', 'shelves': 1, 'currency': 'USD', 'priceMilli': 1234500})!;
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
      'seller': {'name': '시험 상호', 'owner': '홍길동', 'address': '시험시 시험구 시험로 1', 'phone': '000-0000-0000', 'email': 'test@example.com', 'bizNo': '000-00-00000', 'saleNo': '제0000-시험-0000호', 'memo': ''},
    }, save: false);
    expect(hasSellerInfo, isTrue);
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showSellerSheet(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    for (final label in ['상호', '대표자', '주소', '전화번호', '전자우편', '사업자등록번호', '통신판매업 신고번호']) {
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
    (IapNoticeKind.paymentFailed, '13-notice-payment-failed', ['결제가 이뤄지지 않았습니다', '2027년 2월 3일까지는 계속 이용할 수 있습니다.', '결제 수단 확인하기', '닫기']),
    (IapNoticeKind.expired, '14-notice-expired', ['구독이 끝났습니다', '만든 책장과 기록은 그대로 있습니다.', '확인']),
    (IapNoticeKind.subscriptionRefunded, '15-notice-subscription-refunded', ['환불 처리됐습니다', '구독이 종료됐습니다.', '확인']),
    (IapNoticeKind.shelfRefunded, '16-notice-shelf-refunded', ['추가 선반 결제가 환불 처리됐습니다', '꽂힌 책은 그대로 있습니다.', '확인']),
  ]) {
    testWidgets('상태 변화 알림 화면: ${kind.name}', (t) async {
      await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showIapNotice(ctx, kind, noticeSub))))));
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

  testWidgets('결제 완료: 결제한 화면에서 금액, 다음 결제일, 해지하는 곳을 알린다', (t) async {
    plans();
    await _pump(t, const PlanScreen());
    await t.tap(find.bySemanticsLabel('월간, 월 스토어 가격 / 매월'));
    await t.pumpAndSettle();
    // 서버가 지급했다고 답한 순간
    IapService.instance.lastResult = IapResult.granted;
    EntitlementStore.instance.apply({
      'plus': true,
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

  testWidgets('선반 구매 시트: 상품이 여럿이면 고르게 하고, 미리 골라 두지 않는다', (t) async {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'products': [
        {'route': iapRoute, 'productId': 'shelf2', 'kind': 'product', 'shelves': 2},
        {'route': iapRoute, 'productId': 'shelf1', 'kind': 'product', 'shelves': 1},
      ],
    }, save: false);
    IapService.instance.details = {'shelf1': _detail('shelf1', '추가 선반', '한 칸 스토어 가격'), 'shelf2': _detail('shelf2', '추가 선반', '두 칸 스토어 가격')};
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () => showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(t.widgetList<Choice>(find.byType(Choice)).map((c) => (c.label, c.selected)), [('추가 선반 1칸', false), ('추가 선반 2칸', false)]);
    expect(t.widget<Btn>(find.widgetWithText(Btn, '구매하기')).disabled, isTrue);
    await t.tap(find.bySemanticsLabel('추가 선반 2칸, 두 칸 스토어 가격'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('추가 선반 2칸, 두 칸 스토어 가격'), findsNWidgets(2)); // 고른 칸과, 버튼 위의 상품·가격 줄
    expect(t.widget<Btn>(find.widgetWithText(Btn, '구매하기')).disabled, isFalse);
    await _shot(t, '18-shelf-purchase-options');
  });

  testWidgets('선반 구매 시트: 구매가 끝나 칸이 늘면 닫히고, 샀다고 알려 준다', (t) async {
    EntitlementStore.instance.apply({
      'accountToken': 'a-token',
      'shelves': 0,
      'products': [
        {'route': iapRoute, 'productId': 'shelf', 'kind': 'product', 'shelves': 1},
      ],
    }, save: false);
    IapService.instance.details = {'shelf': _detail('shelf', '추가 선반', '스토어 가격')};
    bool? bought;
    await _pump(t, Scaffold(body: Builder(builder: (ctx) => Center(child: Btn(label: '열기', onPress: () async => bought = await showShelfPurchase(ctx))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('구매하기'), findsOneWidget);
    EntitlementStore.instance.apply({'status': 'granted', 'shelves': 1}, save: false);
    await t.pumpAndSettle();
    expect(find.text('구매하기'), findsNothing);
    expect(bought, isTrue);
  });
}
