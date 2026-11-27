// 동의 요청 화면: 가격 변경(T5), 유료 전환(T6). 문구는 docs/legal/notice-templates.md를 따른다.
// 아직 어디에서도 열지 않는다(미리 만든 화면). 쓰려면 서버가 "누구에게 언제 물어야 하는지"와 답을 기록하는 길이 먼저 있어야 한다.
// 지켜야 하는 것(ADR-0003, 전자상거래법 다크패턴 규제):
// - 동의와 거절을 명시적으로 받는다. "거부하지 않으면 동의로 봅니다"를 쓰지 않는다. 답하지 않고 닫으면 답이 없는 것이다(null)
// - 거절 버튼을 동의 버튼과 같은 크기, 같은 모양으로 둔다(한쪽을 강조하지 않는다). 어느 쪽도 미리 골라 두지 않는다
// - 거절한 사람에게 다시 띄우지 않는다. 다시 띄울지 말지는 부르는 쪽이 답을 기록해서 지킨다
// - 혜택 홍보나 할인 권유를 넣지 않는다
library;

import 'package:flutter/material.dart';

import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'subscription_screen.dart' show iapDate;

/// 가격 변경 동의(T5). true = 동의, false = 동의하지 않음, null = 답하지 않고 닫음.
/// 가격은 스토어가 준 현지 가격 문자열 그대로. period: '매월' 또는 '매년'
Future<bool?> openPriceChangeConsent(
  BuildContext context, {
  required String product,
  required String period,
  required String oldPrice,
  required String newPrice,
  required DateTime effectiveAt,
  required DateTime expiresAt,
}) =>
    _open(
      context,
      ConsentScreen(
        title: '가격 변경 안내',
        headline: '$product의 가격이 바뀝니다',
        rows: [('지금 가격', '$oldPrice / $period'), ('바뀌는 가격', '$newPrice / $period'), ('적용일', iapDate(effectiveAt))],
        // 적용일 줄은 날짜만 적는다(길면 잘린다). 조건은 아래 문장으로
        notes: ['바뀐 가격은 ${iapDate(effectiveAt)} 이후 첫 결제부터 적용됩니다.', '동의하지 않으면 ${iapDate(expiresAt)}에 구독이 끝나고 더 이상 결제되지 않습니다.', '동의한 뒤에도 내 정보의 구독 관리에서 언제든 해지할 수 있습니다.'],
        acceptLabel: '바뀐 가격에 동의',
      ),
    );

/// 유료 전환 동의(T6). 무료 체험이나 할인을 도입했을 때만 쓴다
Future<bool?> openTrialConversionConsent(BuildContext context, {required DateTime convertAt, required String price, required String period}) => _open(
      context,
      ConsentScreen(
        title: '유료 전환 안내',
        headline: '무료 체험이 ${iapDate(convertAt)}에 끝납니다',
        rows: [('결제 시작일', iapDate(convertAt)), ('결제 금액', '$price / $period')],
        notes: ['동의하지 않으면 ${iapDate(convertAt)}에 체험이 끝나고 결제되지 않습니다.', '동의한 뒤에도 내 정보의 구독 관리에서 언제든 해지할 수 있습니다.'],
        acceptLabel: '유료 전환에 동의',
      ),
    );

Future<bool?> _open(BuildContext context, ConsentScreen screen) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<bool>(settings: const RouteSettings(name: '/me/consent'), builder: (_) => screen));

class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key, required this.title, required this.headline, required this.rows, required this.notes, required this.acceptLabel});
  final String title, headline, acceptLabel;
  final List<(String, String)> rows;
  final List<String> notes;

  @override
  Widget build(BuildContext context) => Screen(title: title, children: [
        Padding(padding: const EdgeInsets.only(top: Space.s, bottom: Space.item), child: WordText(headline, style: AppType.heading)),
        ListGroup(children: [for (final (label, value) in rows) ListItem(label: label, value: value)]),
        const SizedBox(height: Space.item),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: WordText(n, style: AppType.body)),
        const SizedBox(height: Space.item),
        // 두 버튼은 같은 크기, 같은 모양(한쪽을 강조하지 않는다). 높이도 같게 맞춘다
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: Btn(label: '동의하지 않음', kind: 'secondary', size: 'l', onPress: () => Navigator.pop(context, false))),
            const SizedBox(width: Space.s),
            Expanded(child: Btn(label: acceptLabel, kind: 'secondary', size: 'l', onPress: () => Navigator.pop(context, true))),
          ]),
        ),
      ]);
}
