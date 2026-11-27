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
}
