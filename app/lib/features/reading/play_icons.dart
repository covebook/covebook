// 재생·일시정지 그림: Lucide(ISC) play · pause 모양을 채워 그린다(2026-11-18 사용자: 화면 속 아이콘은 Lucide 한 벌.
// 그전에는 Tabler player-play-filled · player-pause-filled). 크기·색은 쓰는 곳에서 정한다
library;

import 'package:flutter/widgets.dart';

import '../bookmark/bookmark_paper.dart';

// Lucide play(24칸, lucide-static 1.75.0)
final _tri = svgPath('M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z');

/// 재생 삼각형(Lucide 모양을 채우고 같은 굵기 테두리로 둥근 모서리까지). 눈으로 가운데 보이게 오른쪽으로 조금
class PlayIcon extends StatelessWidget {
  const PlayIcon({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: size * 0.04),
        child: CustomPaint(size: Size.square(size), painter: _Tri(color)),
      );
}

class _Tri extends CustomPainter {
  _Tri(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(_tri, Paint()..color = color);
    canvas.drawPath(_tri, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_Tri old) => old.color != color;
}

/// 일시정지: 두 막대(Lucide pause: 폭 5 · 둥글기 1에 선 굵기 2를 더한 모양이라 둥글기는 폭의 약 2/7)
class PauseIcon extends StatelessWidget {
  const PauseIcon({super.key, required this.height, required this.width, required this.gap, required this.color});
  final double height, width, gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar() => Container(width: width, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(width * 2 / 7)));
    return Row(mainAxisSize: MainAxisSize.min, children: [bar(), SizedBox(width: gap), bar()]);
  }
}
