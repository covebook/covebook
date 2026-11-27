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
import '../../services/iap.dart';
import '../../store/entitlement_store.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
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

/// 고지 글(고지 문구 T3, T7~T10, T15). 고지 데이터·알림함 읽기·띄울 것 고르기는 결제 키트(IapNotice, fetchIapNotices, iapNoticeToShow)에 있다
extension CovebookNoticeText on IapNotice {
  /// 갱신 예정(T4)의 결제 예정 금액: 서버는 금액을 주지 않아 스토어가 준 지금 가격을 쓴다. 가려낼 수 없으면 null(금액 줄을 뺀다)
  String? get _price {
    final sub = EntitlementStore.instance.subscription;
    if (sub == null || sub.productId != productId) return null;
    final plan = [for (final p in IapService.instance.plans) if (p.details.id == productId && p.period == '${params['period'] ?? ''}') p];
    return plan.length == 1 ? plan.first.price : iapPriceOf(IapService.instance, sub);
  }

  /// 제목과 본문(고지 문구 T3, T7~T10). 모르는 종류는 null(새 종류를 아는 앱 버전이 나오기 전까지 보이지 않는다)
  (String, String)? get text {
    const name = '책장 한켠 플러스';
    final store = route.isEmpty ? '결제한 스토어' : storeName(route);
    final grace = date('graceUntil'), expires = date('expiresAt');
    // 서버 키트는 선반·연도를 모른다: 수량(units)이 칸 수, 대상(target)이 연도 책장이다
    final shelves = units;
    final year = int.tryParse(target);
    final bookcase = year == null ? '' : '$year년 책장의 ';
    final revoked = date('revokedAt');
    final when = revoked == null ? '' : '환불일은 ${iapDate(revoked)}입니다. ';
    final paid = createdAt; // 결제 완료 고지는 서버가 거래를 원장에 넣을 때 쓴다(T3의 결제일)
    return switch (kind) {
      'payment_failed' => ('$name 결제가 이뤄지지 않았습니다', '${grace == null ? '' : '${iapDate(grace)}까지는 계속 이용할 수 있습니다. '}$store 계정의 결제 수단을 확인해 주세요. 그때까지 결제되지 않으면 구독이 끝납니다.'),
      'expired' => ('$name 구독이 끝났습니다', '만든 책장과 기록은 그대로 있습니다. 유료 벽지와 선반 색은 기본 모양으로 보이고, 고른 설정은 저장돼 있습니다.'),
      'subscription_refunded' => ('$name 결제가 환불 처리됐습니다', '$when구독이 종료됐습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.'),
      // 어느 해 책장인지 몰라 칸을 열지 않은 결제를 서버가 환불했다(opened=false). 잠글 선반이 없다
      'product_refunded' when params['opened'] == false => ('추가 선반 결제가 환불 처리됐습니다', '$when어느 해 책장의 선반인지 확인하지 못해 선반을 열지 않고 환불했습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.'),
      'product_refunded' => ('추가 선반 결제가 환불 처리됐습니다', '$when${bookcase.isEmpty ? '해당 ' : bookcase}선반이 잠겼습니다. 꽂혀 있던 책은 내 책에 보관했습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.'),
      'renewal_upcoming' => expires == null
          ? null
          : ('$name가 ${iapDate(expires)}에 갱신됩니다', '${_price == null ? '' : '결제 예정 금액은 $_price입니다. '}$store에 등록한 결제 수단으로 결제됩니다. 계속 이용하려면 할 일이 없습니다. 갱신을 원하지 않으면 ${iapDate(expires.subtract(const Duration(days: 1)))}까지 내 정보 › 구독 관리에서 해지할 수 있습니다.'),
      'cancel_scheduled' => ('$name의 자동 갱신이 꺼졌습니다', '${expires == null ? '' : '${iapDate(expires)}까지 이용할 수 있습니다. '}이후에는 결제되지 않습니다.'),
      // 두 기기에서 함께 사서 그 해 유료 칸(3칸)을 넘었다: 칸을 열지 않고 돌려준다(고지 문구 T15, ADR-0002 D1)
      'product_over_cap' => (
          '추가 선반이 열리지 않았습니다',
          '${year == null ? '이 책장은' : '$year년 책장은'} 다른 기기에서 먼저 결제해 유료 선반 3칸이 모두 열려 있었습니다. '
              '${shelves > 0 ? '이번 결제(선반 $shelves칸)는' : '이번 결제는'} '
              '${route == 'apple' ? 'Apple에 환불을 요청해 돌려받을 수 있습니다. Apple의 문제 신고 페이지에서 이 구매를 골라 환불을 요청해 주세요.' : params['autoRefund'] == true ? '자동으로 환불했습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.' : '환불해 드립니다. 처리되면 $store에서 확인할 수 있습니다.'}'
        ),
      'purchase_done' => params['kind'] == 'product'
          ? ('추가 선반 결제가 완료됐습니다', '${shelves > 0 ? '$bookcase선반 $shelves칸을 더 열 수 있습니다.' : '$bookcase선반을 더 열 수 있습니다.'} $kIapContractNote')
          : ('$name 결제가 완료됐습니다', '${paid == null ? '' : '결제일은 ${iapDate(paid)}입니다. '}${expires == null ? '' : '다음 결제일은 ${iapDate(expires)}입니다. '}해지는 내 정보의 구독 관리에서 할 수 있습니다. $kIapContractNote'),
      _ => null,
    };
  }
}

/// 서버에서 상태를 받은 뒤 부른다. 기준은 서버 알림함이다: 안 읽은 중요한 고지를 하나 띄우고 읽음으로 남긴다(띄운 것만. 나머지는 알림함에 안 읽음으로 남는다).
/// 서버가 알림함을 주지 않으면 기기에 남긴 지난번 상태와 견주는 예전 방식으로 알린다
Future<void> checkIapNotice(BuildContext context) async {
  final e = EntitlementStore.instance;
  if (!iapOn || !e.loaded) return;
  final List<IapNotice>? list;
  try {
    list = await fetchIapNotices();
  } on IapNoticesUnavailable {
    return; // 기기 기준 상태(iapSeenKey)도 그대로 둬, 다음에 같은 변화를 놓치지 않는다
  }
  final now = IapSnapshot.of(e);
  final seen = IapSnapshot.parse(await KvStore.get(iapSeenKey));
  await KvStore.set(iapSeenKey, now.encode());
  if (list != null) {
    final n = iapNoticeToShow(list, known: (n) => n.text != null);
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
        IapNoticeKind.shelfRefunded => 'product_refunded',
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
  // 결제 실패만 할 일이 있다: 결제 수단 확인을 주 버튼으로, 미루기('나중에')는 아래 글자 버튼으로
  if (n.kind == 'payment_failed' && n.route.isNotEmpty) {
    return appAlert(context, title, message, [
      AlertButton('${storeName(n.route)}에서 결제 수단 확인하기', onPress: () => launchUrl(storeManageUrl(n.route, n.productId), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
      const AlertButton('나중에', style: AlertStyle.cancel),
    ], true, true);
  }
  // 애플은 개발자가 환불할 수 없다: 사용자가 애플 문제 신고 페이지에서 요청한다
  if (n.kind == 'product_over_cap' && n.route == 'apple') {
    return appAlert(context, title, message, [
      AlertButton('Apple에 환불 요청하기', onPress: () => launchUrl(appleRefundUrl, mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
      const AlertButton('나중에', style: AlertStyle.cancel),
    ], true, true);
  }
  return appAlert(context, title, message);
}

/// 애플 구매 환불 요청 페이지(문제 신고)
final appleRefundUrl = Uri.parse('https://reportaproblem.apple.com');

/// 결제 완료(T3): 결제한 화면에서 바로 알린다. price: 스토어가 준 가격 문자열(모르면 줄을 내지 않는다)
/// 결제 완료 고지(T3 v2)가 계약 내용 서면(전자상거래법 제13조 제2항)을 겸하도록 판매자 정보와 철회·환불 기준이 있는 곳을 알린다
const kIapContractNote = '판매자 정보와 청약철회·환불 기준은 내 정보의 사업자 정보와 이용약관에 있습니다.';

/// 미성년자 취소 고지(전자상거래법 제13조 제3항: 계약을 맺을 때 미성년자에게 알린다). 연령을 확인하지 않으니 모든 구매 화면에 둔다. 약관과 같은 문장
const kIapMinorNote = '미성년자가 법정대리인의 동의 없이 결제한 경우 미성년자 본인이나 법정대리인이 결제를 취소할 수 있습니다.';

Future<void> showPurchaseDone(BuildContext context, IapSubscription sub, {String? price}) => appAlert(
      context,
      '결제가 완료됐습니다',
      ['책장 한켠 플러스', if (price != null) '결제 금액 $price', '결제일 ${iapDate(DateTime.now())}', '다음 결제일 ${iapDate(sub.expiresAt)}', '해지는 내 정보의 구독 관리에서 할 수 있습니다.', kIapContractNote].join('\n'),
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
