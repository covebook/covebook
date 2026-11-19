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
import '../../store/entitlement_store.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'subscription_screen.dart' show iapDate, storeManageUrl, storeName;

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
    return IapSnapshot(plus: e.plus, shelves: e.shelves, grace: inGrace ? g.toUtc().toIso8601String() : '');
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

/// 서버에서 상태를 받은 뒤 부른다. 알릴 것이 있으면 한 번 띄우고, 본 상태를 남긴다
Future<void> checkIapNotice(BuildContext context) async {
  final e = EntitlementStore.instance;
  if (!iapOn || !e.loaded) return;
  final now = IapSnapshot.of(e);
  final seen = IapSnapshot.parse(await KvStore.get(iapSeenKey));
  final kind = iapNoticeFor(seen, now, subState: e.subscription?.state ?? '');
  await KvStore.set(iapSeenKey, now.encode());
  if (kind != null && context.mounted) await showIapNotice(context, kind, e.subscription);
}

/// 가운데 확인창으로 알린다(꼭 읽어야 하는 알림이고, 뒤 화면과 관계가 없다. 아래 시트는 뒤 화면을 보며 고르는 일에 쓴다)
Future<void> showIapNotice(BuildContext context, IapNoticeKind kind, IapSubscription? sub) {
  final store = storeName(sub?.route ?? '');
  const name = '책장 한켠 플러스';
  final grace = sub?.graceUntil;
  final (title, message) = switch (kind) {
    IapNoticeKind.paymentFailed => ('$name 결제가 이뤄지지 않았습니다', '${grace == null ? '' : '${iapDate(grace)}까지는 계속 이용할 수 있습니다. '}그때까지 결제되지 않으면 구독이 끝납니다.'),
    IapNoticeKind.expired => ('$name 구독이 끝났습니다', '만든 책장과 기록은 그대로 있습니다. 유료 벽지와 선반 색은 기본 모양으로 보이고, 고른 설정은 저장돼 있습니다.'),
    IapNoticeKind.subscriptionRefunded => ('$name 결제가 환불 처리됐습니다', '구독이 종료됐습니다. 환불 금액과 시기는 $store에서 확인할 수 있습니다.'),
    IapNoticeKind.shelfRefunded => ('추가 선반 결제가 환불 처리됐습니다', '해당 선반이 잠겼습니다. 꽂혀 있던 책은 내 책에 보관했습니다. 환불 금액과 시기는 결제한 스토어에서 확인할 수 있습니다.'),
  };
  // 결제 실패만 할 일이 있다: 결제 수단 확인을 주 버튼으로, 닫기는 아래 글자 버튼으로
  if (kind == IapNoticeKind.paymentFailed && sub != null) {
    return appAlert(context, title, message, [
      AlertButton('$store에서 결제 수단 확인하기', onPress: () => launchUrl(storeManageUrl(sub.route, sub.productId), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
      const AlertButton('닫기', style: AlertStyle.cancel),
    ], true, true);
  }
  return appAlert(context, title, message);
}

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
