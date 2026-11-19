// 알림(내 정보 > 알림): 결제 고지가 쌓이는 알림함(ADR-0003 L8: 앱 안 알림함이 고지의 기준. 앱을 열면 반드시 볼 수 있어야 한다).
// 창으로 한 번 뜨고 사라지는 안내와 달리, 닫은 뒤에도 다시 볼 수 있다. 서버에 보낸 기록이 남는다(L11).
// 거래 고지만 둔다. 혜택 홍보나 권유를 넣지 않는다. 화면을 열면 전부 읽음으로 표시한다.
library;

import 'package:flutter/material.dart';

import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'notice.dart';
import 'subscription_screen.dart' show iapDate, openSubscription;

Future<void> openNotices(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/me/notices'), builder: (_) => const NoticesScreen()));

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key, this.items});

  /// 시험에서 서버 없이 넣는 목록
  final List<IapNotice>? items;

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  List<IapNotice>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    if (_items == null) _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final list = await fetchIapNotices();
    if (!mounted) return;
    setState(() {
      _items = list;
      _failed = list == null;
    });
    // 목록을 본 것으로 친다. 이 화면에는 방금까지 안 읽었던 표시를 그대로 둔다(무엇이 새것인지 보이게)
    if (list != null && list.any((n) => n.unread)) markIapNoticesRead();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items == null ? null : [for (final n in _items!) if (n.text != null) n];
    return Screen(title: '알림', children: [
      if (items == null && !_failed)
        const Padding(padding: EdgeInsets.only(top: Space.section), child: Loading())
      else if (items == null) ...[
        Padding(padding: const EdgeInsets.only(top: Space.s, bottom: Space.item), child: WordText('알림을 불러오지 못했어요.', style: AppType.body)),
        Btn(label: '다시 시도', kind: 'secondary', size: 'l', onPress: _load),
      ] else if (items.isEmpty)
        Padding(padding: const EdgeInsets.only(top: Space.s, bottom: Space.item), child: WordText('받은 알림이 없어요.', style: AppType.body))
      else
        for (final n in items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Semantics(
              container: true,
              label: [if (n.unread) '새 알림', n.text!.$1, n.text!.$2, if (n.createdAt != null) iapDate(n.createdAt!)].join(', '),
              excludeSemantics: true,
              child: OutlineBox(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: WordText(n.text!.$1, style: AppType.rowStrong)),
                    // 안 읽은 고지: 작은 점
                    if (n.unread) Padding(padding: const EdgeInsets.only(left: 8, top: 7), child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle))),
                  ]),
                  const SizedBox(height: 4),
                  WordText(n.text!.$2, style: AppType.body.copyWith(color: AppColors.inkSoft)),
                  if (n.createdAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: WordText(iapDate(n.createdAt!), style: AppType.caption)),
                ]),
              ),
            ),
          ),
      const SizedBox(height: Space.item),
      WordText('결제와 구독에 관한 안내가 여기에 남아요.', style: AppType.sub),
      TextLink(label: '구독 관리 열기', start: true, onPress: () => openSubscription(context)),
    ]);
  }
}
