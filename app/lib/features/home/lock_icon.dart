// 잠긴 선반의 자물쇠 그림
library;

import 'package:flutter/material.dart';

/// 자물쇠(지금 앱 TabIcons LockIcon 32×40, 색 #3F4347·구멍 #F4F3F2). 아직 안 연 선반과 환불로 닫힌 선반이 같은 모양이다
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
