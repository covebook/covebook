// 결제로 가진 것(구독이 주는 권한, 대상마다 산 수량)과 구독 상태. 기준은 서버(/iap/me)이고 여기는 사본이다(ADR-0002 D3).
// 서버에 닿지 못해도 지난번 값을 보여 주려고 기기에 남겨 둔다. 날짜는 스토어가 준 값을 그대로 쓰고 앱에서 더하지 않는다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'kit.dart';

const _cacheKey = 'iap-status:v2';

class IapSubscription {
  const IapSubscription({
    required this.route,
    required this.productId,
    required this.state,
    required this.active,
    required this.autoRenew,
    required this.expiresAt,
    this.planId = '',
    this.graceUntil,
    this.period = '',
  });

  /// 결제한 곳: apple, google
  final String route;
  final String productId, planId;

  /// 서버가 스토어에서 받은 상태: paid, inactive, revoked
  final String state;

  /// 지금 권한이 있는지(만료 전이거나 결제 실패 유예 중)
  final bool active;

  /// 자동 갱신이 켜져 있는지. 꺼져 있으면 해지 예약
  final bool autoRenew;

  /// 스토어가 준 만료 시각. 자동 갱신이면 다음 결제일
  final DateTime expiresAt;

  /// 결제 실패 유예가 끝나는 시각(유예 중일 때만)
  final DateTime? graceUntil;

  /// 결제 주기: month, year. 서버가 모르면 빈 값(요금제 주기 테이블 iap_plans에 줄이 없을 때)
  final String period;

  static IapSubscription? from(Object? j) {
    if (j is! Map) return null;
    final expires = DateTime.tryParse('${j['expiresAt']}');
    if (expires == null) return null;
    return IapSubscription(
      route: '${j['route'] ?? ''}',
      productId: '${j['productId'] ?? ''}',
      planId: '${j['planId'] ?? ''}',
      state: '${j['state'] ?? ''}',
      active: j['active'] == true,
      autoRenew: j['autoRenew'] == true,
      expiresAt: expires,
      graceUntil: DateTime.tryParse('${j['graceUntil']}'),
      period: '${j['period'] ?? ''}',
    );
  }

  /// 화면에 보일 상태(고지 문구 T11: 이용 중 / 해지 예약 / 결제 확인 필요)
  String get statusLabel {
    if (!active) return '이용하고 있지 않아요';
    final grace = graceUntil;
    if (grace != null && grace.isAfter(expiresAt)) return '결제 확인 필요';
    return autoRenew ? '이용 중' : '해지 예약';
  }
}

class IapProduct {
  const IapProduct({required this.route, required this.productId, required this.kind, this.units = 0});
  final String route, productId;

  /// subscription 또는 product(한 번 사는 상품)
  final String kind;

  /// 한 번 사는 상품이 대상에 더하는 수량(책장 한켠: 선반 칸 수)
  final int units;

  static IapProduct? from(Object? j) {
    if (j is! Map || j['productId'] is! String) return null;
    return IapProduct(route: '${j['route']}', productId: j['productId'] as String, kind: '${j['kind']}', units: (j['units'] as num?)?.toInt() ?? 0);
  }
}

/// 기기에 남긴 권한을 서버에 닿기 전까지 믿어도 되는지(ADR-0002 3장 끝 표, 오프라인 캐시).
/// 권한은 구독에서만 온다. 스토어가 준 만료 시각(유예 중이면 유예 끝)까지만 믿는다. 그 뒤 갱신됐는지는 서버만 안다.
/// 구독 정보가 없는 사본은 그대로 둔다(서버에 닿으면 바로 고쳐진다)
bool iapCachedEntitlementsValid({required IapSubscription? subscription, required DateTime now}) {
  if (subscription == null) return true;
  final grace = subscription.graceUntil;
  final until = grace != null && grace.isAfter(subscription.expiresAt) ? grace : subscription.expiresAt;
  return now.isBefore(until);
}

class EntitlementStore extends ChangeNotifier {
  EntitlementStore._();
  static final instance = EntitlementStore._();

  /// 구독이 주는 권한 이름(서버 /iap/me의 entitlements). 책장 한켠은 'plus'
  Set<String> entitlements = const {};

  bool has(String entitlement) => entitlements.contains(entitlement);

  /// 대상마다 산 수량(서버 /iap/me의 unitsByTarget). 산 것이 있는 대상만 들어 있다. 대상이 없는 앱은 키가 ''다
  Map<String, int> unitsByTarget = const {};

  int unitsFor(String target) => unitsByTarget[target] ?? 0;

  /// 모든 대상에서 산 수량의 합(환불이면 줄어든다)
  int get unitsTotal => unitsByTarget.values.fold(0, (a, b) => a + b);

  /// 대상 하나에서 살 수 있는 수량의 최대(서버 규칙). 0이면 상한이 없다
  int capPerTarget = 0;

  IapSubscription? subscription;

  /// 스토어에 넘기는 계정 연결 값(서버가 유저마다 발급한 UUID). 구독에 쓴다
  String accountToken = '';

  /// 서버가 알려 준, 지금 파는 상품
  List<IapProduct> products = const [];

  /// 서버가 받는 결제 경로(apple, google)
  List<String> routes = const [];

  /// 사업자 정보(서버 설정에서 온다. 공개 저장소라 앱에 적지 않는다). 키: name, owner, address, phone, email, bizNo, saleNo
  Map<String, String> seller = const {};

  /// 알림함의 안 읽은 고지 수(서버 값)
  int unreadNotices = 0;

  /// 서버에서 한 번이라도 받았는지
  bool loaded = false;

  /// 기기에 남긴 지난번 값을 읽는다(서버에 닿기 전 화면에 쓴다)
  Future<void> restore() async {
    final raw = await IapKit.storage.get(_cacheKey);
    if (raw == null) return;
    try {
      apply(jsonDecode(raw) as Map<String, dynamic>, save: false);
      // 만료가 지난 사본의 권한은 서버 확인 전까지 끈다(오프라인에서 끝없이 쓰지 않게)
      if (entitlements.isNotEmpty && !iapCachedEntitlementsValid(subscription: subscription, now: DateTime.now())) {
        entitlements = const {};
        notifyListeners();
      }
    } catch (_) {
      // 사본이 깨졌으면 서버 값으로 다시 채운다
    }
  }

  /// 서버 응답(/iap/me, /iap/purchases)을 반영한다. 응답에 없는 칸은 그대로 둔다
  void apply(Map<String, dynamic> j, {bool save = true}) {
    if (j['entitlements'] is List) entitlements = {for (final e in j['entitlements'] as List) if (e is String) e};
    if (j['unitsByTarget'] is Map) {
      unitsByTarget = {
        for (final e in (j['unitsByTarget'] as Map).entries)
          if (e.value is num && (e.value as num) > 0) '${e.key}': (e.value as num).toInt(),
      };
    }
    if (j['capPerTarget'] is num) capPerTarget = (j['capPerTarget'] as num).toInt();
    if (j.containsKey('subscription')) subscription = IapSubscription.from(j['subscription']);
    if (j['accountToken'] is String) accountToken = j['accountToken'] as String;
    if (j['products'] is List) products = [for (final p in j['products'] as List) ?IapProduct.from(p)];
    if (j['seller'] is Map) seller = {for (final e in (j['seller'] as Map).entries) if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}'.trim()};
    if (j['unreadNotices'] is num) unreadNotices = (j['unreadNotices'] as num).toInt();
    if (j['routes'] is List) routes = [for (final r in j['routes'] as List) '$r'];
    loaded = true;
    if (save) {
      IapKit.storage
          .set(
            _cacheKey,
            jsonEncode({
              'entitlements': entitlements.toList(),
              'unitsByTarget': unitsByTarget,
              'capPerTarget': capPerTarget,
              if (j.containsKey('subscription')) 'subscription': j['subscription'],
              if (seller.isNotEmpty) 'seller': seller,
            }),
          )
          .catchError((_) {});
    }
    notifyListeners();
  }

  void setUnread(int n) {
    if (unreadNotices == n) return;
    unreadNotices = n;
    notifyListeners();
  }

  /// 로그아웃·계정 전환 때 비운다
  Future<void> clear() async {
    entitlements = const {};
    unitsByTarget = const {};
    capPerTarget = 0;
    subscription = null;
    accountToken = '';
    unreadNotices = 0;
    products = const [];
    loaded = false;
    await IapKit.storage.remove(_cacheKey).catchError((_) {});
    notifyListeners();
  }
}
