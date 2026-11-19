// 구독 결제 화면. 문구는 docs/legal/notice-templates.md T1을 따른다.
// - 상품, 가격, 결제 주기, 갱신 조건, 해지 방법을 결제 버튼 바로 위에 본문과 같은 크기로 적는다(ADR-0003).
// - 요금제를 미리 골라 두지 않는다. 고르기 전에는 버튼이 눌리지 않는다(다크패턴 규제: 특정 옵션의 사전 선택 금지).
// - 가격은 스토어가 준 현지 가격 문자열 그대로. 월로 나눈 값이나 할인율을 앱이 계산해 적지 않는다.
// - 이미 구독 중인 계정에는 구독 버튼 대신 구독 중임을 알린다(ADR-0002 D16: 두 스토어에서 겹쳐 결제하지 않게).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/iap.dart';
import '../../store/entitlement_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../settings/settings_screen.dart' show privacyUrl;
import '../settings/terms.dart' show showTermsSheet;
import 'notice.dart' show showPurchaseDone;
import 'subscription_screen.dart' show openSubscription, showRefundSheet, storeName;

Future<void> openPlans(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/me/plans'), builder: (_) => const PlanScreen()));

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _e = EntitlementStore.instance;
  final _iap = IapService.instance;

  /// 고른 요금제. 처음에는 아무것도 고르지 않은 상태다
  IapPlan? _picked;

  /// 이 화면을 열었을 때 이미 구독 중이었는지(여기서 결제가 끝난 순간을 알아보려고)
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    // late 초기화는 처음 읽을 때 계산돼서, 결제가 끝난 뒤의 값이 들어간다. 여기서 바로 적는다
    _wasActive = _e.subscription?.active ?? false;
    _e.addListener(_changed);
    _iap.addListener(_changed);
    if (_iap.plans.isEmpty) _iap.refresh();
  }

  @override
  void dispose() {
    _e.removeListener(_changed);
    _iap.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // 이 화면에서 결제가 끝났다: 결제 완료를 알린다(T3)
    final sub = _e.subscription;
    if (!_wasActive && sub != null && sub.active && _iap.lastResult == IapResult.granted) {
      _wasActive = true;
      showPurchaseDone(context, sub, price: _picked?.price);
    }
  }

  IapProduct? _productOf(IapPlan plan) => _e.products.where((p) => p.kind == 'subscription' && p.productId == plan.details.id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final sub = _e.subscription;
    final store = storeName(iapRoute);
    Widget line(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: WordText(t, style: AppType.sub));
    final links = ListGroup(children: [
      ListItem(label: '이용약관', chevron: true, onPress: () => showTermsSheet(context)),
      ListItem(label: '환불 안내', chevron: true, onPress: () => showRefundSheet(context, iapRoute)),
      ListItem(label: '개인정보 처리방침', chevron: true, onPress: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
    ]);
    if (sub != null && sub.active) {
      return Screen(title: '책장 한켠 플러스', children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.s, bottom: Space.item),
          child: WordText(sub.route == iapRoute ? '지금 구독하고 있어요.' : '${storeName(sub.route)}에서 구독하고 있는 계정이에요. 이 기기에서도 그대로 쓸 수 있어요.', style: AppType.body),
        ),
        Btn(label: '구독 관리', kind: 'secondary', size: 'l', onPress: () => openSubscription(context)),
      ]);
    }
    final plans = _iap.plans;
    if (plans.isEmpty && _iap.loading) {
      return const Screen(title: '책장 한켠 플러스', children: [Padding(padding: EdgeInsets.only(top: Space.section), child: Loading())]);
    }
    if (plans.isEmpty) {
      return Screen(title: '책장 한켠 플러스', children: [
        Padding(padding: const EdgeInsets.only(top: Space.s, bottom: Space.item), child: WordText('지금은 구독할 수 없어요. 잠시 뒤 다시 시도해 주세요.', style: AppType.body)),
        const SectionBand(inset: true),
        links,
      ]);
    }
    final p = _picked;
    final failed = _iap.lastResult == IapResult.retryLater || _iap.lastResult == IapResult.rejected ? _iap.lastMessage : null;
    return Screen(title: '책장 한켠 플러스', children: [
      Padding(
        padding: const EdgeInsets.only(top: Space.s, bottom: Space.item),
        child: WordText('유료 벽지와 선반 색을 쓸 수 있어요. 책을 기록하고 진열하는 기능은 구독하지 않아도 그대로 쓸 수 있어요.', style: AppType.body),
      ),
      for (final plan in plans)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: Choice(label: plan.name, sub: '${plan.price} / ${plan.periodLabel}', selected: identical(plan, p), onPress: _iap.busy ? () {} : () => setState(() => _picked = plan)),
        ),
      const SizedBox(height: Space.item),
      // 고른 상품과 가격, 조건을 버튼 바로 위에(본문과 같은 크기)
      if (p != null) ...[
        MetaText('책장 한켠 플러스 ${p.name}$metaSep${p.price} / ${p.periodLabel}', style: AppType.rowStrong),
        const SizedBox(height: Space.s),
        line('${p.periodLabel} 자동으로 결제됩니다.'),
        line('다음 결제일 24시간 전까지 해지하지 않으면 같은 금액으로 갱신됩니다.'),
        line('해지는 $store 계정의 구독 관리에서 할 수 있습니다. 앱의 내 정보에 있는 구독 관리에서도 바로 갈 수 있습니다.'),
        line('해지해도 이미 결제한 기간이 끝날 때까지 이용할 수 있습니다.'),
        line('환불은 $store의 환불 절차를 따릅니다.'),
      ] else
        line('요금제를 고르면 결제 조건을 보여 드려요.'),
      if (failed != null) Padding(padding: const EdgeInsets.only(top: 4), child: WordText(failed, style: AppType.sub.copyWith(color: AppColors.danger))),
      // 결제 대기(편의점 결제, 보호자 승인 등): 실패가 아니라 기다리는 중이라고 알린다
      if (_iap.lastResult == IapResult.pending && _iap.lastMessage != null) Padding(padding: const EdgeInsets.only(top: 4), child: WordText(_iap.lastMessage!, style: AppType.body)),
      Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Btn(
          label: _iap.busy ? '결제 확인 중' : '구독하기',
          size: 'l',
          busy: _iap.busy,
          disabled: _iap.busy || p == null,
          onPress: () {
            final product = p == null ? null : _productOf(p);
            if (product != null) _iap.buy(product, plan: p);
          },
        ),
      ),
      const SizedBox(height: Space.section),
      const SectionBand(inset: true),
      links,
    ]);
  }
}
