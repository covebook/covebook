// 구독 관리(내 정보 > 구독 관리). 문구는 docs/legal/notice-templates.md T11을 따른다.
// 법이 요구하는 것(ADR-0003): 설정 첫 화면에서 한 번에 닿는다. 해지 버튼을 누르면 스토어 구독 관리로 바로 간다.
// 해지 앞에 설문, 혜택 재안내, 재확인 팝업을 두지 않는다. 날짜는 스토어가 준 값을 그대로 보여 준다(앱에서 더하지 않는다).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/iap.dart';
import '../../store/entitlement_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../settings/terms.dart' show showTermsSheet;
import 'plan_screen.dart' show openPlans;

Future<void> openSubscription(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/me/subscription'), builder: (_) => const SubscriptionScreen()));

/// 결제한 스토어의 이름
String storeName(String route) => route == 'apple' ? 'App Store' : 'Google Play';

/// 스토어의 구독 관리 화면 주소. 해지는 스토어에서 한다
Uri storeManageUrl(String route, String productId) => route == 'apple'
    ? Uri.parse('https://apps.apple.com/account/subscriptions')
    : Uri.parse('https://play.google.com/store/account/subscriptions?package=app.covebook&sku=${Uri.encodeQueryComponent(productId)}');

/// 스토어의 환불 신청 주소
Uri storeRefundUrl(String route) => route == 'apple' ? Uri.parse('https://reportaproblem.apple.com') : Uri.parse('https://play.google.com/store/account/orderhistory');

/// 구독 중인 요금제의 스토어 가격. 요금제를 가려낼 수 없으면 null(틀린 금액을 보이느니 보이지 않는다)
String? iapPriceOf(IapService iap, IapSubscription sub) {
  final plans = [for (final p in iap.plans) if (p.details.id == sub.productId) p];
  if (plans.isEmpty) return sub.planId.isEmpty ? iap.details[sub.productId]?.price : null;
  if (sub.planId.isEmpty) return plans.length == 1 ? plans.first.price : null;
  return plans.where((p) => p.planId == sub.planId).firstOrNull?.price;
}

/// 날짜 표시: 기기 시간대의 날짜만. 스토어가 준 시각을 그대로 옮긴다
String iapDate(DateTime t) {
  final d = t.toLocal();
  return '${d.year}년 ${d.month}월 ${d.day}일';
}

/// 환불 안내 시트(구독 관리, 결제 화면이 같이 쓴다)
Future<void> showRefundSheet(BuildContext context, String route) => showSheet<void>(
      context,
      title: '환불 안내',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        WordText('환불은 ${storeName(route)}의 환불 절차를 따릅니다. 결제와 환불은 ${storeName(route)}가 처리해서, 앱에서 바로 환불해 드릴 수 없어요.', style: AppType.body),
        const SizedBox(height: Space.item),
        WordText('환불이 처리되면 구독이 종료되고, 구매한 선반은 잠겨요. 그 선반에 꽂아 둔 책은 내 책에 보관되고 기록은 그대로 있어요.', style: AppType.body),
        Padding(
          padding: const EdgeInsets.only(top: Space.item),
          child: Btn(label: '${storeName(route)}에서 환불 신청하기', kind: 'secondary', onPress: () => launchUrl(storeRefundUrl(route), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
        ),
      ]),
    );

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _e = EntitlementStore.instance;
  final _iap = IapService.instance;

  @override
  void initState() {
    super.initState();
    _e.addListener(_changed);
    _iap.addListener(_changed);
    _iap.refresh();
  }

  @override
  void dispose() {
    _e.removeListener(_changed);
    _iap.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {});

  Future<void> _restore() async {
    await _iap.restorePurchases();
    if (!mounted) return;
    final m = _iap.lastMessage;
    if (m != null) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 3), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final sub = _e.subscription;
    final route = sub?.route ?? iapRoute;
    final store = storeName(route);
    // 구글은 구독 상품 하나에 요금제가 여럿이다. 상품 ID로 찾으면 다른 요금제의 가격이 나올 수 있어 요금제 ID로 찾는다
    final price = sub == null ? null : iapPriceOf(_iap, sub);
    final grace = sub?.graceUntil;
    final inGrace = sub != null && sub.active && grace != null && grace.isAfter(sub.expiresAt);
    return Screen(
      title: '구독 관리',
      children: [
        if (sub == null || !sub.active)
          Padding(
            padding: const EdgeInsets.only(top: Space.s, bottom: Space.item),
            child: WordText(sub == null ? '구독하고 있지 않아요.' : '구독이 끝났어요. 만든 책장과 기록은 그대로 있어요.', style: AppType.body),
          )
        else ...[
          ListGroup(children: [
            ListItem(label: '요금제', value: _iap.details[sub.productId]?.title ?? '책장 한켠 플러스'),
            ListItem(label: '상태', value: sub.statusLabel),
            // 자동 갱신이면 다음 결제일, 해지 예약이면 이용이 끝나는 날, 결제 실패 유예 중이면 유예가 끝나는 날. 스토어가 준 날짜 그대로
            ListItem(label: inGrace ? '이용 가능 기한' : sub.autoRenew ? '다음 결제일' : '이용 종료일', value: iapDate(inGrace ? grace : sub.expiresAt)),
            if (sub.autoRenew && !inGrace && price != null) ListItem(label: '결제 금액', value: price),
          ]),
          if (inGrace)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: WordText('결제가 이뤄지지 않았어요. ${iapDate(grace)}까지는 계속 이용할 수 있어요. $store 계정의 결제 수단을 확인해 주세요.', style: AppType.sub),
            )
          else if (!sub.autoRenew)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: WordText('자동 갱신이 꺼져 있어요. ${iapDate(sub.expiresAt)}까지 이용할 수 있고, 이후에는 결제되지 않아요.', style: AppType.sub),
            ),
          // 다른 스토어에서 구독한 계정(D16): 해지는 결제한 스토어에서 한다
          if (route != iapRoute)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: WordText('$store에서 구독한 계정이에요. 해지와 결제 수단 변경은 $store에서 할 수 있어요.', style: AppType.sub),
            ),
          const SizedBox(height: Space.section),
          // 누르면 스토어 구독 관리로 바로 간다. 사이에 아무것도 두지 않는다
          Btn(label: '$store에서 해지하기', kind: 'secondary', size: 'l', onPress: () => _open(storeManageUrl(route, sub.productId))),
          const SizedBox(height: Space.s),
        ],
        // 구독하지 않은 계정: 요금제 화면으로 가는 길 하나(구독을 권하는 문장은 두지 않는다)
        if (sub == null || !sub.active) ...[
          Btn(label: '요금제 보기', kind: 'secondary', size: 'l', onPress: () => openPlans(context)),
          const SizedBox(height: Space.s),
        ],
        Btn(label: '구매 복원', kind: 'secondary', size: 'l', busy: _iap.busy, onPress: _restore),
        const SizedBox(height: Space.section),
        const SectionBand(inset: true),
        ListGroup(children: [
          ListItem(label: '환불 안내', chevron: true, onPress: () => showRefundSheet(context, route)),
          ListItem(label: '이용약관', chevron: true, onPress: () => showTermsSheet(context)),
        ]),
      ],
    );
  }
}
