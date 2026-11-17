// 재생·일시정지 그림: Tabler 아이콘(MIT) player-play-filled · player-pause-filled 모양(2026-11-18 사용자 '내가 말한 라이브러리 썼나':
// 화면 속 아이콘은 Tabler 한 벌). 크기·색은 쓰는 곳에서 정한다
library;

import 'package:flutter/widgets.dart';

import '../bookmark/bookmark_paper.dart';

// Tabler player-play-filled(24칸)
final _tri = svgPath('M6 4v16a1 1 0 0 0 1.524 .852l13 -8a1 1 0 0 0 0 -1.704l-13 -8a1 1 0 0 0 -1.524 .852z');

/// 재생 삼각형(Tabler 채운 모양). 눈으로 가운데 보이게 오른쪽으로 조금
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
  }

  @override
  bool shouldRepaint(_Tri old) => old.color != color;
}

/// 일시정지: 두 막대(Tabler player-pause-filled처럼 모서리 둥글기는 폭의 1/3)
class PauseIcon extends StatelessWidget {
  const PauseIcon({super.key, required this.height, required this.width, required this.gap, required this.color});
  final double height, width, gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar() => Container(width: width, height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(width / 3)));
    return Row(mainAxisSize: MainAxisSize.min, children: [bar(), SizedBox(width: gap), bar()]);
  }
}
