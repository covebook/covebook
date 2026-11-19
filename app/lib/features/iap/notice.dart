// 결제 상태가 바뀐 것을 앱을 열었을 때 한 번 알린다: 결제 실패(T7), 구독 만료(T8), 환불 처리(T9).
// - 지난번에 본 상태를 기기에 남겨 두고 서버가 준 지금 상태와 견준다. 같은 일을 두 번 알리지 않는다
//   (닫은 사람에게 같은 창을 다시 띄우지 않는다, 다크패턴 규제).
// - 거래 고지라 혜택 홍보나 다시 구독하라는 권유를 넣지 않는다(notice-templates 쓰는 규칙).
// - 결제 완료(T3)는 결제한 화면에서 바로 알린다(showPurchaseDone).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../db/kv_store.dart';
import '../../services/sync.dart' show api, syncTokenKey;
import '../../store/entitlement_store.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../services/iap.dart' show IapService;
import 'subscription_screen.dart' show iapDate, iapPriceOf, storeManageUrl, storeName;

enum IapNoticeKind { paymentFailed, expired, subscriptionRefunded, shelfRefunded }

/// 알림을 정할 때 견주는 값
class IapSnapshot {
  const IapSnapshot({required this.plus, required this.shelves, this.grace = ''});
  final bool plus;
  final int shelves;

  /// 결제 실패 유예가 끝나는 시각(유예 중일 때만). 같은 유예를 두 번 알리지 않으려고 둔다
  final String grace;

  static IapSnapshot of(EntitlementStore e) {
    final sub = e.subscription, g = sub?.graceUntil;
    final inGrace = sub != null && sub.active && g != null && g.isAfter(sub.expiresAt);
    // 모든 해의 합: 해가 바뀌어 올해 칸이 0이 돼도 환불로 보지 않는다
    return IapSnapshot(plus: e.plus, shelves: e.shelvesTotal, grace: inGrace ? g.toUtc().toIso8601String() : '');
  }

  static IapSnapshot? parse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return IapSnapshot(plus: j['plus'] == true, shelves: (j['shelves'] as num?)?.toInt() ?? 0, grace: '${j['grace'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({'plus': plus, 'shelves': shelves, 'grace': grace});
}

/// 지난번에 본 상태(seen)와 지금(now)을 견줘 알릴 것을 정한다. 처음 보는 계정(seen 없음)은 알리지 않는다.
/// subState: 지금 구독 줄의 상태(서버 값: paid, inactive, revoked)
IapNoticeKind? iapNoticeFor(IapSnapshot? seen, IapSnapshot now, {String subState = ''}) {
  if (seen == null) return null;
  if (now.shelves < seen.shelves) return IapNoticeKind.shelfRefunded;
  if (seen.plus && !now.plus) return subState == 'revoked' ? IapNoticeKind.subscriptionRefunded : IapNoticeKind.expired;
  if (now.grace.isNotEmpty && now.grace != seen.grace) return IapNoticeKind.paymentFailed;
  return null;
}

/// 고지 한 건(서버의 알림함 한 줄, ADR-0003 L8·L11). 서버가 종류와 문구에 넣을 값을 주고, 글은 앱이 고지 문구 템플릿대로 만든다
class IapNotice {
  const IapNotice({required this.kind, this.id = 0, this.createdAt, this.readAt, this.params = const {}});
  final int id;

  /// payment_failed, expired, subscription_refunded, shelf_refunded, cancel_scheduled, purchase_done
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

  /// 갱신 예정(T4)의 결제 예정 금액: 서버는 금액을 주지 않아 스토어가 준 지금 가격을 쓴다. 가려낼 수 없으면 null(금액 줄을 뺀다)
  String? get _price {
    final sub = EntitlementStore.instance.subscription;
    if (sub == null || sub.productId != productId) return null;
    final plan = [for (final p in IapService.instance.plans) if (p.details.id == productId && p.period == '${params['period'] ?? ''}') p];
    return plan.length == 1 ? plan.first.price : iapPriceOf(IapService.instance, sub);
  }
  String get route => '${params['route'] ?? ''}';
  String get productId => '${params['productId'] ?? ''}';
  DateTime? _date(String key) => DateTime.tryParse('${params[key]}');

  /// 앱을 열었을 때 창으로도 한 번 띄우는 종류(꼭 읽어야 하는 것). 나머지는 알림함에만 둔다
  bool get important => const {'payment_failed', 'expired', 'subscription_refunded', 'shelf_refunded', 'shelf_over_cap'}.contains(kind);

  /// 제목과 본문(고지 문구 T3, T7~T10). 모르는 종류는 null(새 종류를 아는 앱 버전이 나오기 전까지 보이지 않는다)
  (String, String)? get text {
    const name = '책장 한켠 플러스';
    final store = route.isEmpty ? '결제한 스토어' : storeName(route);
    final grace = _date('graceUntil'), expires = _date('expiresAt');
    final shelves = (params['shelves'] as num?)?.toInt() ?? 0;
    final year = (params['year'] as num?)?.toInt();
    final bookcase = year == null ? '' : '$year년 책장의 ';
    final revoked = _date('revokedAt');
    final when = revoked == null ? '' : '환불일은 ${iapDate(revoked)}입니다. ';
    return switch (kind) {
      'payment_failed' => ('$name 결제가 이뤄지지 않았습니다', '${grace == null ? '' : '${iapDate(grace)}까지는 계속 이용할 수 있습니다. '}$store 계정의 결제 수단을 확인해 주세요. 그때까지 결제되지 않으면 구독이 끝납니다.'),
      'expired' => ('$name 구독이 끝났습니다', '만든 책장과 기록은 그대로 있습니다. 유료 벽지와 선반 색은 기본 모양으로 보이고, 고른 설정은 저장돼 있습니다.'),
      'subscription_refunded' => ('$name 결제가 환불 처리됐습니다', '$when구독이 종료됐습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.'),
      'shelf_refunded' => ('추가 선반 결제가 환불 처리됐습니다', '$when${bookcase.isEmpty ? '해당 ' : bookcase}선반이 잠겼습니다. 꽂혀 있던 책은 내 책에 보관했습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.'),
      'renewal_upcoming' => expires == null
          ? null
          : ('$name가 ${iapDate(expires)}에 갱신됩니다', '${_price == null ? '' : '결제 예정 금액은 $_price입니다. '}계속 이용하려면 할 일이 없습니다. 갱신을 원하지 않으면 ${iapDate(expires.subtract(const Duration(days: 1)))}까지 내 정보 › 구독 관리에서 해지할 수 있습니다.'),
      'cancel_scheduled' => ('$name의 자동 갱신이 꺼졌습니다', '${expires == null ? '' : '${iapDate(expires)}까지 이용할 수 있습니다. '}이후에는 결제되지 않습니다.'),
      // 두 기기에서 함께 사서 그 해 유료 칸(3칸)을 넘었다: 칸을 열지 않고 돌려준다(고지 문구 T15, ADR-0002 D1)
      'shelf_over_cap' => (
          '추가 선반이 열리지 않았습니다',
          '${year == null ? '이 책장은' : '$year년 책장은'} 다른 기기에서 먼저 결제해 유료 선반 3칸이 모두 열려 있었습니다. '
              '${shelves > 0 ? '이번 결제(선반 $shelves칸)는' : '이번 결제는'} '
              '${route == 'apple' ? 'Apple에 환불을 요청해 돌려받을 수 있습니다. Apple의 문제 신고 페이지에서 이 구매를 골라 환불을 요청해 주세요.' : params['autoRefund'] == true ? '자동으로 환불했습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.' : '환불해 드립니다. 처리되면 $store에서 확인할 수 있습니다.'}'
        ),
      'purchase_done' => params['kind'] == 'product'
          ? ('추가 선반 결제가 완료됐습니다', shelves > 0 ? '$bookcase선반 $shelves칸을 더 열 수 있습니다.' : '$bookcase선반을 더 열 수 있습니다.')
          : ('$name 결제가 완료됐습니다', '${expires == null ? '' : '다음 결제일은 ${iapDate(expires)}입니다. '}해지는 내 정보의 구독 관리에서 할 수 있습니다.'),
      _ => null,
    };
  }
}

/// 서버 알림함을 읽는다. 서버가 아직 알림함을 주지 않으면(예전 서버) null
Future<List<IapNotice>?> fetchIapNotices() async {
  final token = await KvStore.get(syncTokenKey);
  if (token == null) return null;
  try {
    final res = await api('GET', '/iap/notices', token);
    if (res is! Map<String, dynamic> || res['notices'] is! List) return null;
    return [for (final j in res['notices'] as List) ?IapNotice.from(j)];
  } catch (_) {
    return null;
  }
}

/// 읽음으로 표시한다. ids가 없으면 전부. 실패해도 넘어간다(다음에 다시 안 읽음으로 보일 뿐이다)
Future<void> markIapNoticesRead([List<int>? ids]) async {
  final token = await KvStore.get(syncTokenKey);
  if (token == null) return;
  try {
    final res = await api('POST', '/iap/notices/read', token, ids == null ? {'all': true} : {'ids': ids});
    if (res is Map<String, dynamic> && res['unread'] is num) EntitlementStore.instance.setUnread((res['unread'] as num).toInt());
  } catch (_) {}
}

/// 앱을 열었을 때 창으로 띄울 고지: 안 읽은 중요한 것 가운데 가장 새것 하나. 한 번에 여러 창을 쌓지 않는다
IapNotice? iapNoticeToShow(List<IapNotice> list) {
  final unread = [for (final n in list) if (n.unread && n.important && n.text != null) n];
  if (unread.isEmpty) return null;
  unread.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  return unread.first;
}

/// 서버에서 상태를 받은 뒤 부른다. 기준은 서버 알림함이다: 안 읽은 중요한 고지를 하나 띄우고 읽음으로 남긴다(띄운 것만. 나머지는 알림함에 안 읽음으로 남는다).
/// 서버가 알림함을 주지 않으면 기기에 남긴 지난번 상태와 견주는 예전 방식으로 알린다
Future<void> checkIapNotice(BuildContext context) async {
  final e = EntitlementStore.instance;
  if (!iapOn || !e.loaded) return;
  final list = await fetchIapNotices();
  final now = IapSnapshot.of(e);
  final seen = IapSnapshot.parse(await KvStore.get(iapSeenKey));
  await KvStore.set(iapSeenKey, now.encode());
  if (list != null) {
    final n = iapNoticeToShow(list);
    if (n == null || !context.mounted) return;
    await markIapNoticesRead([n.id]);
    if (context.mounted) await showIapNotice(context, n);
    return;
  }
  final kind = iapNoticeFor(seen, now, subState: e.subscription?.state ?? '');
  if (kind != null && context.mounted) await showIapNotice(context, iapNoticeOf(kind, e.subscription));
}

/// 기기에서 알아낸 변화를 고지 모양으로(서버 알림함이 없을 때)
IapNotice iapNoticeOf(IapNoticeKind kind, IapSubscription? sub) => IapNotice(
      kind: switch (kind) {
        IapNoticeKind.paymentFailed => 'payment_failed',
        IapNoticeKind.expired => 'expired',
        IapNoticeKind.subscriptionRefunded => 'subscription_refunded',
        IapNoticeKind.shelfRefunded => 'shelf_refunded',
      },
      params: {
        if (sub != null && kind != IapNoticeKind.shelfRefunded) ...{
          'route': sub.route,
          'productId': sub.productId,
          'expiresAt': sub.expiresAt.toIso8601String(),
          if (sub.graceUntil != null) 'graceUntil': sub.graceUntil!.toIso8601String(),
        },
      },
    );

/// 가운데 확인창으로 알린다(꼭 읽어야 하는 알림이고, 뒤 화면과 관계가 없다. 아래 시트는 뒤 화면을 보며 고르는 일에 쓴다)
Future<void> showIapNotice(BuildContext context, IapNotice n) async {
  final text = n.text;
  if (text == null) return;
  final (title, message) = text;
  // 결제 실패만 할 일이 있다: 결제 수단 확인을 주 버튼으로, 닫기는 아래 글자 버튼으로
  if (n.kind == 'payment_failed' && n.route.isNotEmpty) {
    return appAlert(context, title, message, [
      AlertButton('${storeName(n.route)}에서 결제 수단 확인하기', onPress: () => launchUrl(storeManageUrl(n.route, n.productId), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
      const AlertButton('닫기', style: AlertStyle.cancel),
    ], true, true);
  }
  // 애플은 개발자가 환불할 수 없다: 사용자가 애플 문제 신고 페이지에서 요청한다
  if (n.kind == 'shelf_over_cap' && n.route == 'apple') {
    return appAlert(context, title, message, [
      AlertButton('Apple에 환불 요청하기', onPress: () => launchUrl(appleRefundUrl, mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
      const AlertButton('닫기', style: AlertStyle.cancel),
    ], true, true);
  }
  return appAlert(context, title, message);
}

/// 애플 구매 환불 요청 페이지(문제 신고)
final appleRefundUrl = Uri.parse('https://reportaproblem.apple.com');

/// 결제 완료(T3): 결제한 화면에서 바로 알린다. price: 스토어가 준 가격 문자열(모르면 줄을 내지 않는다)
Future<void> showPurchaseDone(BuildContext context, IapSubscription sub, {String? price}) => appAlert(
      context,
      '결제가 완료됐습니다',
      ['책장 한켠 플러스', if (price != null) '결제 금액 $price', '다음 결제일 ${iapDate(sub.expiresAt)}', '해지는 내 정보의 구독 관리에서 할 수 있습니다.'].join('\n'),
      null,
      true,
      false,
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        child: const Center(child: LucideIcon('Check', size: 24, color: AppColors.onAccent, stroke: 3)),
      ),
    );
