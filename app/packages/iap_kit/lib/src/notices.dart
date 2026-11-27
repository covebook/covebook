// 결제 고지(서버 알림함 GET /iap/notices), 구매 내역(GET /iap/purchases), 연 구독 갱신 전 알림 시각.
// 법이 요구하는 것(거래 고지 L7·L11, 구매 내역 L17, 갱신 전 고지 L9)이라 어느 앱이든 데이터와 판단이 같다. 키트가 맡는다.
// 글(고지 문구 템플릿)과 화면, 기기 알림 플러그인은 앱이 만든다. 앱은 확장으로 글을 붙인다(책장 한켠: features/iap/notice.dart).
library;

import 'entitlements.dart';
import 'kit.dart';

/// 고지 한 건(서버 iap_notices 한 줄). 서버는 종류와 문구에 넣을 값(params)만 준다
class IapNotice {
  const IapNotice({required this.kind, this.id = 0, this.createdAt, this.readAt, this.params = const {}});
  final int id;

  /// payment_failed, expired, subscription_refunded, product_refunded, product_over_cap,
  /// renewal_upcoming, cancel_scheduled, purchase_done. 모르는 종류도 받아 둔다(앱이 글을 모르면 보이지 않는다)
  final String kind;
  final DateTime? createdAt, readAt;
  final Map<String, dynamic> params;

  static IapNotice? from(Object? j) {
    if (j is! Map || j['kind'] is! String) return null;
    return IapNotice(
      id: (j['id'] as num?)?.toInt() ?? 0,
      kind: j['kind'] as String,
      createdAt: DateTime.tryParse('${j['createdAt']}'),
      readAt: DateTime.tryParse('${j['readAt']}'),
      params: j['params'] is Map ? Map<String, dynamic>.from(j['params'] as Map) : const {},
    );
  }

  bool get unread => readAt == null;
  String get route => '${params['route'] ?? ''}';
  String get productId => '${params['productId'] ?? ''}';

  /// 한 번 사는 상품의 대상과 수량(구독 고지에는 없다)
  String get target => '${params['target'] ?? ''}';
  int get units => (params['units'] as num?)?.toInt() ?? 0;

  /// params의 시각(graceUntil, expiresAt, revokedAt). 없거나 깨졌으면 null
  DateTime? date(String key) => DateTime.tryParse('${params[key]}');

  /// 앱을 열었을 때 창으로도 한 번 띄우는 종류인지(꼭 읽어야 하는 것). 나머지는 알림함에만 둔다
  bool get important => iapImportantNotices.contains(kind);
}

/// 창으로 한 번 띄우는 종류: 이용이 끊기거나(실패, 만료), 돈이 돌아가거나(환불, 넘김) 할 일이 있는 것
const iapImportantNotices = {'payment_failed', 'expired', 'subscription_refunded', 'product_refunded', 'product_over_cap'};

/// 알림함을 받지 못했다(통신 오류, 서버 오류). 이때는 아무것도 띄우지 않고 다음에 다시 본다.
/// 기기 기준으로 대신 띄우면 다음 실행에 같은 일이 알림함에서 안 읽음으로 다시 떠 두 번 보인다
class IapNoticesUnavailable implements Exception {
  const IapNoticesUnavailable();
}

/// 서버 알림함을 읽는다.
/// - 로그인하지 않았거나 서버가 없는 빌드(IapSignedOut), 알림함이 없는 예전 서버(404): null. 앱은 기기 기준으로 알릴 수 있다
/// - 그 밖의 실패: IapNoticesUnavailable
Future<List<IapNotice>?> fetchIapNotices() async {
  try {
    final res = await IapKit.call('GET', '/iap/notices');
    if (res is! Map || res['notices'] is! List) return null;
    return [for (final j in res['notices'] as List) ?IapNotice.from(j)];
  } on IapSignedOut {
    return null;
  } on IapApiError catch (e) {
    if (e.status == 404) return null;
    throw const IapNoticesUnavailable();
  } catch (_) {
    throw const IapNoticesUnavailable();
  }
}

/// 읽음으로 표시한다. ids가 없으면 전부. 실패해도 넘어간다(다음에 다시 안 읽음으로 보일 뿐이다)
Future<void> markIapNoticesRead([List<int>? ids]) async {
  try {
    final res = await IapKit.call('POST', '/iap/notices/read', ids == null ? {'all': true} : {'ids': ids});
    if (res is Map && res['unread'] is num) EntitlementStore.instance.setUnread((res['unread'] as num).toInt());
  } catch (_) {}
}

/// 앱을 열었을 때 창으로 띄울 고지: 안 읽은 중요한 것 가운데 가장 새것 하나. 한 번에 여러 창을 쌓지 않는다.
/// 띄운 것만 읽음으로 남기고(markIapNoticesRead([n.id])) 나머지는 알림함에 안 읽음으로 둔다. 닫은 고지는 다시 띄우지 않는다(다크패턴 규제).
/// known: 앱이 글을 만들 수 있는 고지인지. 글이 없는 고지(새 종류, 값이 빠진 것)를 고르면 빈 창이 뜬다
IapNotice? iapNoticeToShow(List<IapNotice> list, {bool Function(IapNotice n)? known}) {
  final unread = [for (final n in list) if (n.unread && n.important && (known?.call(n) ?? true)) n];
  if (unread.isEmpty) return null;
  unread.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  return unread.first;
}

/// 구매 내역 한 줄(서버 원장). 날짜는 스토어가 준 시각 그대로. 금액은 서버가 가진 줄에만 있다(구글은 구매 조회에 금액을 주지 않는다)
class IapHistoryItem {
  const IapHistoryItem({required this.route, required this.productId, required this.kind, required this.state, required this.purchasedAt, this.revokedAt, this.units = 0, this.target = '', this.currency, this.priceMilli});

  /// apple, google
  final String route, productId;

  /// subscription, product
  final String kind;

  /// paid, revoked
  final String state;
  final DateTime purchasedAt;
  final DateTime? revokedAt;
  final int units;
  final String target;
  final String? currency;

  /// 통화 1단위 = 1000인 정수(서버 D20)
  final int? priceMilli;

  static IapHistoryItem? from(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['purchasedAt']}');
    if (at == null) return null;
    return IapHistoryItem(
      route: '${j['route'] ?? ''}',
      productId: '${j['productId'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      state: '${j['state'] ?? ''}',
      purchasedAt: at,
      revokedAt: DateTime.tryParse('${j['revokedAt']}'),
      units: (j['units'] as num?)?.toInt() ?? 0,
      target: '${j['target'] ?? ''}',
      currency: j['currency'] as String?,
      priceMilli: (j['priceMilli'] as num?)?.toInt(),
    );
  }

  bool get refunded => state == 'revoked';

  /// 금액: 서버가 가진 값을 통화 코드와 함께 그대로(환율·세금 계산을 하지 않는다). 없으면 null
  String? get price {
    final c = currency, m = priceMilli;
    if (c == null || m == null) return null;
    final whole = m ~/ 1000, frac = m % 1000;
    final digits = '$whole'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return frac == 0 ? '$digits $c' : '$digits.${'$frac'.padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')} $c';
  }
}

/// 구매 내역을 서버에서 읽는다. 실패하면 던진다(로그인하지 않음, 통신 실패, 서버 오류)
Future<List<IapHistoryItem>> fetchIapPurchases() async {
  final res = await IapKit.call('GET', '/iap/purchases');
  final list = res is Map && res['purchases'] is List ? res['purchases'] as List : const [];
  return [for (final j in list) ?IapHistoryItem.from(j)];
}

/// 연 구독 갱신 며칠 전에 알리나(L12 한국 기본값, 서버 IAP_RENEWAL_NOTICE_DAYS 기본값과 같다)
const iapRenewalNoticeDays = 14;

/// 연 구독 갱신 전 기기 알림을 걸 시각(기기 시각 그날 hour시). 걸지 않아야 하면 null.
/// - 대상: 연 구독, 이용 중, 자동 갱신 켜짐, 결제 실패 유예가 아님. 월 구독은 보내지 않는다(L9)
/// - 결제일까지 하루도 안 남았으면 알려도 해지할 틈이 없어 null
/// 알림을 거는 일(플러그인, 권한)은 앱이 한다. 서버도 같은 때 알림함에 renewal_upcoming을 쌓는다(기준은 알림함)
DateTime? renewalReminderAt(IapSubscription? sub, DateTime now, {int days = iapRenewalNoticeDays, int hour = 10}) {
  if (sub == null || !sub.active || !sub.autoRenew || sub.period != 'year') return null;
  final grace = sub.graceUntil;
  if (grace != null && grace.isAfter(sub.expiresAt)) return null;
  final day = sub.expiresAt.toLocal().subtract(Duration(days: days));
  final at = DateTime(day.year, day.month, day.day, hour);
  if (!at.isAfter(now) || sub.expiresAt.difference(at) < const Duration(days: 1)) return null;
  return at;
}
