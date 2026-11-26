// 선반 구매 시트(잠긴 선반을 눌렀는데 쓸 수 있는 칸을 다 연 경우). 문구는 docs/legal/notice-templates.md T2를 따른다.
// 가격은 스토어가 준 현지 가격 문자열을 그대로 보여 준다(앱에 가격을 적지 않는다, ADR-0002 D22).
// 옵션을 미리 골라 두지 않고, 닫으면 다시 띄우지 않는다(다크패턴 규제).
library;

import 'package:flutter/material.dart';

import '../../services/iap.dart';
import '../../store/entitlement_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'notice.dart' show kIapMinorNote;
import 'subscription_screen.dart' show storeName;

/// 그 해 책장에서 살 수 있는 선반 상품(칸 수가 적은 것부터). 이미 산 칸과 합쳐 유료 칸 최대(3칸)를 넘는 상품은 뺀다.
/// 그래서 3칸 묶음은 그 해에 산 칸이 없을 때만 보인다(ADR-0002 D1)
List<IapProduct> shelfOffers(Iterable<IapProduct> products, {required int paid}) => [
      for (final p in products)
        if (p.kind == 'product' && p.shelves > 0 && paid + p.shelves <= paidShelfMax) p,
    ]..sort((a, b) => a.shelves.compareTo(b.shelves));

/// 이 기기의 스토어에서 그 해 책장에 살 수 있는 선반 상품. 가격을 받지 못한 상품은 뺀다
List<IapProduct> shelfProducts(int year) {
  final iap = IapService.instance;
  final e = EntitlementStore.instance;
  return shelfOffers([for (final p in e.products) if (p.route == iapRoute && iap.details.containsKey(p.productId)) p], paid: e.shelvesFor(year));
}

/// 선반 구매 시트를 연다(year: 칸을 열 연도 책장, 없으면 지금 책장). 구매가 끝나 칸이 늘었으면 true
Future<bool> showShelfPurchase(BuildContext context, {int? year}) async {
  final y = year ?? liveShelfYear();
  final before = EntitlementStore.instance.shelvesFor(y);
  await showSheet<void>(context, title: '선반 더 열기', builder: (ctx) => _ShelfPurchase(year: y));
  return EntitlementStore.instance.shelvesFor(y) > before;
}

class _ShelfPurchase extends StatefulWidget {
  const _ShelfPurchase({required this.year});
  final int year;

  @override
  State<_ShelfPurchase> createState() => _ShelfPurchaseState();
}

class _ShelfPurchaseState extends State<_ShelfPurchase> {
  final _iap = IapService.instance;
  final _e = EntitlementStore.instance;
  int _before = 0;

  /// 상품이 여럿일 때 고른 것. 미리 골라 두지 않는다
  IapProduct? _picked;

  @override
  void initState() {
    super.initState();
    // late 초기화는 처음 읽을 때 계산된다(구매가 끝난 뒤의 값이 들어가 시트가 닫히지 않았다). 여기서 바로 적는다
    _before = _e.shelvesFor(widget.year);
    _iap.addListener(_changed);
    _e.addListener(_changed);
    _iap.clearResult(); // 이전 작업의 오류 문구가 처음부터 보이지 않게
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
    if (_e.shelvesFor(widget.year) > _before) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final year = widget.year;
    final products = shelfProducts(year);
    final store = storeName(iapRoute);
    if (products.isEmpty && _iap.loading) return const Padding(padding: EdgeInsets.symmetric(vertical: Space.item), child: Loading());
    if (products.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        WordText('지금은 선반을 구매할 수 없어요. 잠시 뒤 다시 시도해 주세요.', style: AppType.body),
        Padding(padding: const EdgeInsets.only(top: Space.item), child: Btn(label: '확인', size: 'l', onPress: () => Navigator.pop(context))),
      ]);
    }
    // 상품이 하나면 그것, 여럿이면 고른 것(고르기 전에는 살 수 없다)
    // 목록이 새 객체로 바뀌어도 고른 것을 잃지 않게 상품 ID로 다시 찾는다
    final p = products.length == 1 ? products.first : products.where((o) => o.productId == _picked?.productId).firstOrNull;
    final price = p == null ? null : _iap.details[p.productId]!.price;
    final failed = _iap.lastResult == IapResult.retryLater || _iap.lastResult == IapResult.rejected ? _iap.lastMessage : null;
    // 가운데 점을 쓰지 않는다(앱 규칙, 2026-11-18): 줄마다 문장 하나
    // 결제 조건은 본문과 같은 크기로 적는다(작은 글씨로 숨기지 않는다, 고지 문구 T1)
    Widget line(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: WordText(t, style: AppType.body));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (products.length > 1)
        for (final o in products)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Choice(label: '추가 선반 ${o.shelves}칸', sub: _iap.details[o.productId]!.price, selected: identical(o, p), onPress: _iap.busy ? () {} : () => setState(() => _picked = o)),
          ),
      // 상품과 가격을 버튼 바로 위에, 같은 크기의 글자로
      if (p != null) MetaText('$year년 책장$metaSep추가 선반 ${p.shelves}칸$metaSep$price', style: AppType.rowStrong),
      const SizedBox(height: Space.s),
      line(p == null ? '$year년 책장에 선반을 엽니다. 다른 해의 책장에는 열리지 않습니다.' : '$year년 책장에 선반 ${p.shelves}칸을 엽니다. 다른 해의 책장에는 열리지 않습니다.'),
      line('한 번 결제하면 이 책장에서 계속 쓸 수 있습니다.'),
      line('구매한 선반은 로그인한 계정에 기록되어 기기를 바꿔도 유지됩니다.'),
      // 청약철회 제한 표시(전자상거래법 제17조 제6항, T2 v4). 시험 사용은 잠긴 선반 미리보기(locked_rows)
      line('결제하면 바로 선반이 열려 청약철회가 제한됩니다. 환불은 $store의 환불 절차를 따릅니다.'),
      line(kIapMinorNote),
      if (failed != null) Padding(padding: const EdgeInsets.only(top: 4), child: WordText(failed, style: AppType.sub.copyWith(color: AppColors.danger))),
      if (_iap.lastResult == IapResult.pending && _iap.lastMessage != null) Padding(padding: const EdgeInsets.only(top: 4), child: WordText(_iap.lastMessage!, style: AppType.body)),
      Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Btn(label: _iap.busy ? '결제 확인 중' : '구매하기', size: 'l', busy: _iap.busy, disabled: _iap.busy || p == null, onPress: () {
          if (p != null) _iap.buy(p, year: year);
        }),
      ),
    ]);
  }
}
