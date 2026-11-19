// 결제로 가진 것(구독 권한, 구매한 선반 칸 수)과 구독 상태. 기준은 서버(/iap/me)이고 여기는 사본이다(ADR-0002 D3).
// 서버에 닿지 못해도 지난번 값을 보여 주려고 기기에 남겨 둔다. 날짜는 스토어가 준 값을 그대로 쓰고 앱에서 더하지 않는다.
// 결제 화면은 빌드 플래그로 꺼 둔다(--dart-define=IAP=true일 때만 켜짐, AGENTS.md)
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/kv_store.dart';

/// 결제 기능을 켠 빌드인지. 기본은 꺼짐
const iapOn = bool.fromEnvironment('IAP');

const _cacheKey = 'iap-status:v1';

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
  const IapProduct({required this.route, required this.productId, required this.kind, this.shelves = 0});
  final String route, productId;

  /// subscription 또는 product(한 번 사는 상품)
  final String kind;

  /// 한 번 사는 상품이 주는 선반 칸 수
  final int shelves;

  static IapProduct? from(Object? j) {
    if (j is! Map || j['productId'] is! String) return null;
    return IapProduct(route: '${j['route']}', productId: j['productId'] as String, kind: '${j['kind']}', shelves: (j['shelves'] as num?)?.toInt() ?? 0);
  }
}

class EntitlementStore extends ChangeNotifier {
  EntitlementStore._();
  static final instance = EntitlementStore._();

  /// 구독 권한(유료 꾸미기)
  bool plus = false;

  /// 구매한 선반 칸 수
  int shelves = 0;
  IapSubscription? subscription;

  /// 스토어에 넘기는 계정 연결 값(서버가 유저마다 발급한 UUID)
  String accountToken = '';

  /// 서버가 알려 준, 지금 파는 상품
  List<IapProduct> products = const [];

  /// 서버가 받는 결제 경로(apple, google)
  List<String> routes = const [];

  /// 사업자 정보(서버 설정에서 온다. 공개 저장소라 앱에 적지 않는다). 키: name, owner, address, phone, email, bizNo, saleNo
  Map<String, String> seller = const {};

  /// 서버에서 한 번이라도 받았는지
  bool loaded = false;

  /// 기기에 남긴 지난번 값을 읽는다(서버에 닿기 전 화면에 쓴다)
  Future<void> restore() async {
    final raw = await KvStore.get(_cacheKey);
    if (raw == null) return;
    try {
      apply(jsonDecode(raw) as Map<String, dynamic>, save: false);
    } catch (_) {
      // 사본이 깨졌으면 서버 값으로 다시 채운다
    }
  }

  /// 서버 응답(/iap/me, /iap/purchases)을 반영한다. 응답에 없는 칸은 그대로 둔다
  void apply(Map<String, dynamic> j, {bool save = true}) {
    if (j['plus'] is bool) plus = j['plus'] as bool;
    if (j['shelves'] is num) shelves = (j['shelves'] as num).toInt();
    if (j.containsKey('subscription')) subscription = IapSubscription.from(j['subscription']);
    if (j['accountToken'] is String) accountToken = j['accountToken'] as String;
    if (j['products'] is List) products = [for (final p in j['products'] as List) ?IapProduct.from(p)];
    if (j['seller'] is Map) seller = {for (final e in (j['seller'] as Map).entries) if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}'.trim()};
    if (j['routes'] is List) routes = [for (final r in j['routes'] as List) '$r'];
    loaded = true;
    if (save) {
      KvStore.set(
        _cacheKey,
        jsonEncode({
          'plus': plus,
          'shelves': shelves,
          if (j.containsKey('subscription')) 'subscription': j['subscription'],
          if (seller.isNotEmpty) 'seller': seller,
        }),
      ).catchError((_) {});
    }
    notifyListeners();
  }

  /// 로그아웃·계정 전환 때 비운다
  Future<void> clear() async {
    plus = false;
    shelves = 0;
    subscription = null;
    accountToken = '';
    products = const [];
    loaded = false;
    await KvStore.remove(_cacheKey).catchError((_) {});
    notifyListeners();
  }
}
