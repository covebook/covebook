// 환불로 잠긴 선반의 표시(ADR-0002 D13). 꽂힌 책은 그대로 보이고, 책을 누르거나 빼는 것을 막지 않는다(표시만 누를 수 있다).
// 모양 두 가지를 둔다. 어느 쪽을 쓸지는 refundedLook 한 줄로 정한다.
//  A안: 아직 안 연 선반과 같은 자물쇠를 선반 가운데에. 앱에 이미 있는 모양이라 새로 배울 것이 없다. 자물쇠가 책 한두 권을 가린다
//  B안: 선반을 옅게 덮고 오른쪽 위에 작은 자물쇠와 '환불된 선반' 글자표. 책을 가리지 않고 왜 잠겼는지 글로 보인다
library;

import 'package:flutter/material.dart';

import '../../ui/kit.dart';
import '../../ui/theme.dart';

enum RefundedLook { a, b }

/// 지금 쓰는 모양
const refundedLook = RefundedLook.a;

class RefundedShelfMark extends StatelessWidget {
  const RefundedShelfMark({super.key, required this.onTap, this.look = refundedLook});
  final VoidCallback onTap;
  final RefundedLook look;

  @override
  Widget build(BuildContext context) {
    Widget tap(Widget child) => Semantics(
          container: true,
          button: true,
          label: '환불된 선반, 눌러서 안내 보기',
          onTap: onTap,
          excludeSemantics: true,
          child: Pressable(onPress: onTap, child: child),
        );
    if (look == RefundedLook.a) {
      // 자물쇠만 누를 수 있다. 나머지 자리는 아래의 책이 그대로 눌린다
      return Center(child: tap(const Padding(padding: EdgeInsets.all(8), child: LockIcon())));
    }
    return Stack(children: [
      // 옅은 덮개: 누르기를 가로채지 않는다
      Positioned.fill(child: IgnorePointer(child: ColoredBox(color: AppColors.bg.withValues(alpha: 0.5)))),
      Positioned(
        top: 8,
        right: 12,
        child: tap(Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const LockIcon(scale: 0.4),
            const SizedBox(width: 6),
            Text('환불된 선반', style: AppType.caption.copyWith(color: AppColors.ink)),
          ]),
        )),
      ),
    ]);
  }
}

/// 자물쇠(지금 앱 TabIcons LockIcon 32×40, 색 #3F4347·구멍 #F4F3F2). 아직 안 연 선반과 환불된 선반이 같이 쓴다
class LockIcon extends StatelessWidget {
  const LockIcon({super.key, this.scale = 1});
  final double scale;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(32 * scale, 40 * scale), painter: _LockPainter(scale));
}

class _LockPainter extends CustomPainter {
  _LockPainter(this.scale);
  final double scale;
  static const _ink = Color(0xFF3F4347), _hole = Color(0xFFF4F3F2);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final shackle = Path()
      ..moveTo(8.5, 19)
      ..lineTo(8.5, 11.5)
      ..arcToPoint(const Offset(23.5, 11.5), radius: const Radius.circular(7.5))
      ..lineTo(23.5, 19);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(2.5, 16.5, 27, 22), const Radius.circular(5.5)), Paint()..color = _ink);
    canvas.drawCircle(const Offset(16, 25.5), 3.1, Paint()..color = _hole);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14.5, 25.5, 3, 6.5), const Radius.circular(1.5)), Paint()..color = _hole);
  }

  @override
  bool shouldRepaint(_LockPainter old) => old.scale != scale;
}
