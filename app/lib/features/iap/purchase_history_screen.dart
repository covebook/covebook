// 구매 내역(내 정보 > 구매 내역, ADR-0003 L17). 유저가 자기 결제 기록을 앱에서 보고 따로 남길 수 있게 한다.
// 기준은 서버 원장(GET /iap/purchases)이다. 날짜는 스토어가 준 시각 그대로. 금액은 서버가 가진 줄에만 있다
// (구글은 구매 조회에 금액을 주지 않는다). 없으면 스토어 주문 내역에서 보라고 안내한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../db/kv_store.dart';
import '../../services/iap.dart';
import '../../services/sync.dart' show api, syncTokenKey;
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'subscription_screen.dart' show iapDate, storeName, storeRefundUrl;

Future<void> openPurchaseHistory(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/me/purchases'), builder: (_) => const PurchaseHistoryScreen()));

class IapHistoryItem {
  const IapHistoryItem({required this.route, required this.productId, required this.kind, required this.state, required this.purchasedAt, this.revokedAt, this.shelves = 0, this.year, this.currency, this.priceMilli});
  final String route, productId, kind, state;
  final DateTime purchasedAt;
  final DateTime? revokedAt;
  final int shelves;

  /// 추가 선반을 연 연도 책장(서버가 주지 않으면 null)
  final int? year;
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
      shelves: (j['shelves'] as num?)?.toInt() ?? 0,
      year: (j['year'] as num?)?.toInt(),
      currency: j['currency'] as String?,
      priceMilli: (j['priceMilli'] as num?)?.toInt(),
    );
  }

  bool get refunded => state == 'revoked';
  String get name => kind == 'subscription' ? '책장 한켠 플러스' : year == null ? '추가 선반 $shelves칸' : '$year년 책장 추가 선반 $shelves칸';
  String get stateLabel => refunded ? '환불됨' : '결제 완료';

  /// 금액: 서버가 가진 값을 통화 코드와 함께 그대로(환율·세금 계산을 하지 않는다). 없으면 null
  String? get price {
    final c = currency, m = priceMilli;
    if (c == null || m == null) return null;
    final whole = m ~/ 1000, frac = m % 1000;
    final digits = '$whole'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return frac == 0 ? '$digits $c' : '$digits.${'$frac'.padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')} $c';
  }

  /// 따로 남길 때의 한 줄
  String get line => [iapDate(purchasedAt), name, ?price, storeName(route), stateLabel, if (revokedAt != null) '환불일 ${iapDate(revokedAt!)}'].join(', ');
}

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key, this.items});

  /// 시험에서 서버 없이 넣는 목록
  final List<IapHistoryItem>? items;

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  List<IapHistoryItem>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    if (_items == null) _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final token = await KvStore.get(syncTokenKey);
      if (token == null) throw StateError('로그인이 필요해요');
      final res = await api('GET', '/iap/purchases', token);
      final list = res is Map<String, dynamic> && res['purchases'] is List ? res['purchases'] as List : const [];
      if (mounted) setState(() => _items = [for (final j in list) ?IapHistoryItem.from(j)]);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _copy(List<IapHistoryItem> items) async {
    await Clipboard.setData(ClipboardData(text: ['책장 한켠 구매 내역', for (final i in items) i.line].join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('구매 내역을 복사했어요.'), duration: Duration(seconds: 3), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final store = storeName(iapRoute);
    return Screen(title: '구매 내역', children: [
      if (items == null && !_failed)
        const Padding(padding: EdgeInsets.only(top: Space.section), child: Loading())
      else if (items == null) ...[
        Padding(padding: const EdgeInsets.only(top: Space.s, bottom: Space.item), child: WordText('구매 내역을 불러오지 못했어요.', style: AppType.body)),
        Btn(label: '다시 시도', kind: 'secondary', size: 'l', onPress: _load),
      ] else if (items.isEmpty)
        Padding(padding: const EdgeInsets.only(top: Space.s, bottom: Space.item), child: WordText('구매한 것이 없어요.', style: AppType.body))
      else ...[
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: OutlineBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: WordText(i.name, style: AppType.rowStrong)),
                  WordText(i.stateLabel, style: AppType.sub.copyWith(color: i.refunded ? AppColors.danger : AppColors.inkSoft)),
                ]),
                const SizedBox(height: 4),
                MetaText([iapDate(i.purchasedAt), storeName(i.route), ?i.price].join(metaSep), style: AppType.sub),
                if (i.revokedAt != null) WordText('환불일 ${iapDate(i.revokedAt!)}', style: AppType.sub),
              ]),
            ),
          ),
        const SizedBox(height: Space.s),
        Btn(label: '내역 복사', kind: 'secondary', size: 'l', onPress: () => _copy(items)),
      ],
      const SizedBox(height: Space.item),
      WordText('영수증과 결제 금액은 $store 주문 내역에서도 볼 수 있어요.', style: AppType.sub),
      TextLink(label: '$store 주문 내역 열기', start: true, onPress: () => launchUrl(storeRefundUrl(iapRoute), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
    ]);
  }
}
