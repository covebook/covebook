// 선반 구매 시트(잠긴 선반을 눌렀는데 쓸 수 있는 칸을 다 연 경우). 문구는 docs/legal/notice-templates.md T2를 따른다.
// 가격은 스토어가 준 현지 가격 문자열을 그대로 보여 준다(앱에 가격을 적지 않는다, ADR-0002 D22).
// 옵션을 미리 골라 두지 않고, 닫으면 다시 띄우지 않는다(다크패턴 규제).
library;

import 'package:flutter/material.dart';

import '../../services/iap.dart';
import '../../store/entitlement_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'subscription_screen.dart' show storeName;

/// 이 기기의 스토어에서 살 수 있는 선반 상품(칸 수가 적은 것부터). 가격을 받지 못한 상품은 뺀다
List<IapProduct> shelfProducts() {
  final iap = IapService.instance;
  final list = [
    for (final p in EntitlementStore.instance.products)
      if (p.kind == 'product' && p.route == iapRoute && p.shelves > 0 && iap.details.containsKey(p.productId)) p,
  ]..sort((a, b) => a.shelves.compareTo(b.shelves));
  return list;
}

/// 선반 구매 시트를 연다. 구매가 끝나 칸이 늘었으면 true
Future<bool> showShelfPurchase(BuildContext context) async {
  final before = EntitlementStore.instance.shelves;
  await showSheet<void>(context, title: '선반 더 열기', builder: (ctx) => const _ShelfPurchase());
  return EntitlementStore.instance.shelves > before;
}

class _ShelfPurchase extends StatefulWidget {
  const _ShelfPurchase();

  @override
  State<_ShelfPurchase> createState() => _ShelfPurchaseState();
}

class _ShelfPurchaseState extends State<_ShelfPurchase> {
  final _iap = IapService.instance;
  final _e = EntitlementStore.instance;
  late final int _before = _e.shelves;

  @override
  void initState() {
    super.initState();
    _iap.addListener(_changed);
    _e.addListener(_changed);
    if (_iap.details.isEmpty) _iap.refresh();
  }

  @override
  void dispose() {
    _iap.removeListener(_changed);
    _e.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // 구매가 끝나 칸이 늘었으면 닫는다
    if (_e.shelves > _before) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final products = shelfProducts();
    final store = storeName(iapRoute);
    if (products.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        WordText('지금은 선반을 구매할 수 없어요. 잠시 뒤 다시 시도해 주세요.', style: AppType.body),
        Padding(padding: const EdgeInsets.only(top: Space.item), child: Btn(label: '확인', size: 'l', onPress: () => Navigator.pop(context))),
      ]);
    }
    final p = products.first;
    final price = _iap.details[p.productId]!.price;
    final failed = _iap.lastResult == IapResult.retryLater || _iap.lastResult == IapResult.rejected ? _iap.lastMessage : null;
    // 가운데 점을 쓰지 않는다(앱 규칙, 2026-11-18): 줄마다 문장 하나
    Widget line(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: WordText(t, style: AppType.sub));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // 상품과 가격을 버튼 바로 위에, 같은 크기의 글자로
      MetaText('추가 선반 ${p.shelves}칸$metaSep$price', style: AppType.rowStrong),
      const SizedBox(height: Space.s),
      line('한 번 결제하면 계속 쓸 수 있습니다.'),
      line('구매한 선반은 계정에 기록됩니다. 로그인해 두면 기기를 바꿔도 유지됩니다.'),
      line('환불은 $store의 환불 절차를 따릅니다.'),
      if (failed != null) Padding(padding: const EdgeInsets.only(top: 4), child: WordText(failed, style: AppType.sub.copyWith(color: AppColors.danger))),
      Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Btn(label: _iap.busy ? '결제 확인 중' : '구매하기', size: 'l', busy: _iap.busy, disabled: _iap.busy, onPress: () => _iap.buy(p)),
      ),
    ]);
  }
}
