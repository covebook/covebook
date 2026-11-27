// 결제 키트 시험: 책장 한켠 없이, 대상이 없는 앱(계정 전체에 붙는 상품)으로 돈다.
import 'package:flutter_test/flutter_test.dart';
import 'package:iap_kit/iap_kit.dart';

void main() {
  setUp(() async {
    await EntitlementStore.instance.clear();
    IapKit.messages = const {};
  });

  test('서버 응답 반영: 권한 이름과 대상별 수량을 그대로, 대상이 없는 앱은 키가 빈 문자열', () {
    final e = EntitlementStore.instance;
    e.apply({
      'entitlements': ['pro', 3, 'ad_free'],
      'unitsByTarget': {'': 5, 'zero': 0},
      'capPerTarget': 0,
      'products': [
        {'route': 'google', 'productId': 'coins10', 'kind': 'product', 'units': 10},
        {'route': 'google', 'productId': 'pro', 'kind': 'subscription', 'entitlement': 'pro'},
      ],
    }, save: false);
    expect(e.entitlements, {'pro', 'ad_free'}); // 문자열이 아닌 값은 버린다
    expect((e.has('pro'), e.has('plus'), e.unitsFor(''), e.unitsTotal, e.capPerTarget), (true, false, 5, 5, 0));
    expect(e.unitsByTarget.containsKey('zero'), isFalse, reason: '0은 버린다');
    expect(e.products.first.units, 10);
    // 구매 응답에는 상품 목록이 없다. 있는 칸만 바꾼다
    e.apply({'status': 'granted', 'unitsByTarget': {'': 15}}, save: false);
    expect((e.unitsFor(''), e.products.length, e.has('pro')), (15, 2, true));
  });

  test('기기 사본: 저장했다가 다시 읽고, 만료가 지난 구독의 권한은 서버 확인 전까지 끈다', () async {
    final e = EntitlementStore.instance;
    e.apply({
      'entitlements': ['pro'],
      'unitsByTarget': {'': 2},
      'subscription': {'route': 'google', 'productId': 'pro', 'state': 'paid', 'active': true, 'autoRenew': true, 'expiresAt': '2000-01-01T00:00:00Z'},
    });
    await Future<void>.delayed(Duration.zero); // 저장은 기다리지 않고 돈다
    e
      ..entitlements = const {}
      ..unitsByTarget = const {};
    await e.restore();
    expect(e.unitsFor(''), 2);
    expect(e.has('pro'), isFalse, reason: '2000년에 끝난 구독');
  });

  test('오프라인: 서버에 닿지 못하면 만료가 지난 권한을 끄고, 서버 값이 있으면 기기 시계로 끄지 않는다', () {
    final e = EntitlementStore.instance;
    final sub = {'route': 'google', 'productId': 'pro', 'state': 'paid', 'active': true, 'autoRenew': true};
    // 앱을 켠 뒤 만료일이 지났고 서버에 닿지 못했다
    e.apply({'entitlements': ['pro'], 'subscription': {...sub, 'expiresAt': '2000-01-01T00:00:00Z'}}, save: false);
    expect(e.has('pro'), isTrue, reason: '서버가 준 값은 그대로 쓴다');
    e.expireIfStale();
    expect(e.has('pro'), isFalse);
    // 아직 남은 구독은 그대로
    e.apply({'entitlements': ['pro'], 'subscription': {...sub, 'expiresAt': '2999-01-01T00:00:00Z'}}, save: false);
    e.expireIfStale();
    expect(e.has('pro'), isTrue);
  });

  test('거래를 끝내도 되는 때', () {
    expect(iapShouldFinish(status: 200), isTrue);
    expect(iapShouldFinish(status: 409, code: 'iap_cap_full'), isTrue);
    expect(iapShouldFinish(status: 422, code: 'iap_target_missing'), isFalse, reason: '대상을 붙여 다시 낸다');
    expect(iapShouldFinish(status: 422, code: 'iap_bad_proof'), isFalse);
    expect(iapShouldFinish(status: 503), isFalse);
  });

  test('문구: 앱이 바꾼 것을 먼저, 없으면 키트 기본 문구', () {
    expect(IapKit.text('restored'), defaultMessages['restored']);
    IapKit.messages = const {'restored': 'Restored.'};
    expect(IapKit.text('restored'), 'Restored.');
    expect(IapKit.text('pending'), defaultMessages['pending']);
  });

  group('고지·구매 내역·갱신 시각', () {
    // 서버 응답을 흉내 낸다. 길마다 돌려줄 것(값이나 던질 것)
    void serve(Map<String, Object? Function(Object? body)> routes) => IapKit.configure(
          enabled: true,
          storage: IapKit.storage,
          api: (method, path, [body]) async {
            final f = routes['$method $path'];
            if (f == null) throw const IapApiError(404, 'not_found', '');
            return f(body);
          },
        );
    IapNotice n(int id, String kind, String at, {bool read = false}) =>
        IapNotice.from({'id': id, 'kind': kind, 'createdAt': at, if (read) 'readAt': at, 'params': {'route': 'google', 'units': 2, 'target': 'x'}})!;

    test('알림함 읽기: 로그인 안 함과 예전 서버(404)는 null, 그 밖의 실패는 IapNoticesUnavailable', () async {
      serve({'GET /iap/notices': (_) => {'notices': [{'id': 1, 'kind': 'expired'}, {'id': 2}, '깨짐']}});
      final list = (await fetchIapNotices())!;
      expect([for (final x in list) x.id], [1], reason: '종류가 없거나 깨진 줄은 버린다');
      serve({'GET /iap/notices': (_) => throw const IapSignedOut()});
      expect(await fetchIapNotices(), isNull);
      serve({});
      expect(await fetchIapNotices(), isNull);
      serve({'GET /iap/notices': (_) => throw const IapApiError(503, 'iap_unavailable', '')});
      expect(fetchIapNotices(), throwsA(isA<IapNoticesUnavailable>()));
      serve({'GET /iap/notices': (_) => throw StateError('통신 실패')});
      expect(fetchIapNotices(), throwsA(isA<IapNoticesUnavailable>()));
    });

    test('읽음 표시: 서버가 준 안 읽은 수를 반영하고, 실패는 넘어간다', () async {
      Object? sent;
      serve({'POST /iap/notices/read': (b) => {'unread': (sent = b) == null ? 0 : 3}});
      await markIapNoticesRead([7]);
      // 레코드로 묶으면 Map은 같은 객체인지만 본다. 따로 견준다
      expect(sent, {'ids': [7]});
      expect(EntitlementStore.instance.unreadNotices, 3);
      await markIapNoticesRead();
      expect(sent, {'all': true});
      serve({});
      await markIapNoticesRead(); // 던지지 않는다
    });

    test('띄울 고지: 안 읽은 중요한 것 가운데 가장 새것 하나, 앱이 글을 모르는 것은 뺀다', () {
      final list = [
        n(1, 'expired', '2027-01-01T00:00:00Z', read: true),
        n(2, 'payment_failed', '2027-01-02T00:00:00Z'),
        n(3, 'product_over_cap', '2027-01-03T00:00:00Z'),
        n(4, 'cancel_scheduled', '2027-01-04T00:00:00Z'), // 알림함에만
        n(5, 'something_new', '2027-01-05T00:00:00Z'),
      ];
      expect(iapNoticeToShow(list)!.id, 3);
      expect(iapNoticeToShow(list, known: (x) => x.kind != 'product_over_cap')!.id, 2);
      expect(iapNoticeToShow([list[0], list[3], list[4]]), isNull);
      expect((list[2].units, list[2].target, list[2].route, list[2].important, list[3].important), (2, 'x', 'google', true, false));
    });

    test('구매 내역: 날짜가 없는 줄은 버리고, 금액은 통화 코드와 함께 그대로', () async {
      serve({
        'GET /iap/purchases': (_) => {
              'purchases': [
                {'route': 'apple', 'productId': 'coins', 'kind': 'product', 'state': 'paid', 'purchasedAt': '2026-11-19T03:00:00Z', 'units': 10, 'currency': 'USD', 'priceMilli': 1234500},
                {'route': 'google', 'productId': 'pro', 'kind': 'subscription', 'state': 'revoked', 'purchasedAt': '2026-11-19T03:00:00Z', 'revokedAt': '2026-11-20T03:00:00Z', 'currency': 'KRW', 'priceMilli': 3300000},
                {'purchasedAt': '날짜가 아님'},
              ],
            },
      });
      final items = await fetchIapPurchases();
      expect(items.length, 2);
      expect((items[0].price, items[0].units, items[0].target, items[0].refunded), ('1,234.5 USD', 10, '', false));
      expect((items[1].price, items[1].refunded, items[1].revokedAt), ('3,300 KRW', true, DateTime.utc(2026, 11, 20, 3)));
      serve({});
      expect(fetchIapPurchases(), throwsA(isA<IapApiError>()));
    });

    test('갱신 전 알림 시각: 연 구독만, 며칠 전인지는 바꿀 수 있다', () {
      IapSubscription sub({String period = 'year', bool autoRenew = true}) =>
          IapSubscription(route: 'google', productId: 'pro', state: 'paid', active: true, autoRenew: autoRenew, expiresAt: DateTime(2027, 3, 1, 9), period: period);
      final now = DateTime(2027, 1, 1);
      expect(renewalReminderAt(sub(), now), DateTime(2027, 2, 15, 10));
      expect(renewalReminderAt(sub(), now, days: 30, hour: 9), DateTime(2027, 1, 30, 9));
      expect(renewalReminderAt(sub(period: 'month'), now), isNull);
      expect(renewalReminderAt(sub(autoRenew: false), now), isNull);
      expect(renewalReminderAt(sub(), now, days: 0), isNull, reason: '결제일까지 하루도 안 남으면 해지할 틈이 없다');
    });
  });
}
