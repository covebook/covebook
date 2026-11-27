// 첫 책 꽂기 안내 겹(2026-11-27 사용자 시안): 고른 책을 들고 책장으로 돌아와 '책장에 꽂기' 시트가 열리면
// 화면 전체에 반투명 차콜(약 45%)을 깔고 그 책 표지 자리만 원래 밝기로 비운다(책장 · 선반 결은 뒤로 비친다).
// 표지 위 빈 벽에 흰 글 두 줄 '눌러서 꽂거나 / 원하는 칸으로 끌어 보세요'와 가는 흰 곡선 화살표 하나가 표지 오른쪽 위 모서리를 가리킨다.
// 글은 선반 판 띠와 시트를 피해 표지에 가장 가까운 빈 벽에 둔다(작은 화면에서도 표지 · 선반을 가리지 않게).
// 누르기는 모두 아래로 지나간다: 표지를 누르거나 끄는 것은 시트가 그대로 받는다(끌기를 시작하면 홈이 이 겹을 바로 걷는다)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// 안내 글(두 줄 고정: 줄을 넘치면 글자만 줄인다)
const firstBookCoachText = '눌러서 꽂거나\n원하는 칸으로 끌어 보세요';

/// 글 · 화살표 자리(화면 좌표): 시험이 자리 규칙을 따로 본다
@visibleForTesting
({Rect text, Offset from, Offset control, Offset to}) coachLayout({
  required Size screen,
  required Rect target,
  required Size text,
  required double top,
  required double floor,
  List<({double top, double bottom})> blocked = const [],
}) {
  // 빈 벽 구간: [top, floor]에서 선반 판 띠를 뺀 것(위에서부터)
  final free = <({double top, double bottom})>[];
  var y = top;
  for (final b in [...blocked]..sort((a, c) => a.top.compareTo(c.top))) {
    if (b.bottom <= y || b.top >= floor) continue;
    if (b.top > y) free.add((top: y, bottom: math.min(b.top, floor)));
    y = math.max(y, b.bottom);
  }
  if (y < floor) free.add((top: y, bottom: floor));
  // 표지에 가장 가까운(가장 아래) 구간 중 글이 위아래 여백까지 들어가는 곳. 없으면 가장 넓은 곳
  final need = text.height + Space.l * 2;
  final fits = [for (final f in free) if (f.bottom - f.top >= need) f];
  final pick = fits.isNotEmpty
      ? fits.last
      : free.isEmpty
          ? (top: top, bottom: floor)
          : free.reduce((a, c) => (c.bottom - c.top) > (a.bottom - a.top) ? c : a);
  // 글 아래 끝은 그 구간 아래에서 16 위(판 바로 위 벽), 구간이 좁으면 구간 가운데
  final textTop = pick.bottom - pick.top >= need ? pick.bottom - Space.l - text.height : (pick.top + pick.bottom - text.height) / 2;
  // 가로: 표지 오른쪽으로 비켜(시안: 글 왼쪽이 표지 오른쪽보다 40쯤 오른쪽) 화면 안에
  final left = (target.right + Space.xxl).clamp(Space.page, math.max(Space.page, screen.width - Space.page - text.width)).toDouble();
  final box = Rect.fromLTWH(left, textTop, text.width, text.height);
  // 화살표: 글 왼쪽 아래에서 시작해 표지 오른쪽 위 모서리 바로 바깥을 가리킨다. 오른쪽 아래로 불룩한 곡선(시안)
  final from = Offset(box.left + Space.s, box.bottom + Space.s);
  final to = Offset(target.right + Space.s, target.top - Space.s);
  final control = Offset(math.max(from.dx, to.dx) + Space.l, to.dy - (to.dy - from.dy) * 0.35);
  return (text: box, from: from, control: control, to: to);
}

class FirstBookCoach extends StatelessWidget {
  const FirstBookCoach({super.key, required this.target, required this.top, required this.floor, this.blocked = const []});

  /// 비울 표지 자리(화면 좌표)
  final Rect target;

  /// 글을 둘 수 있는 위 끝(머리줄 아래)과 아래 끝(시트 위 끝)
  final double top, floor;

  /// 선반 판 띠(화면 y 범위): 글이 가리지 않는다
  final List<({double top, double bottom})> blocked;

  /// 표지 둘레로 더 비우는 폭 · 모서리(시안: 표지 둘레 흰 테)
  static const holePad = Space.s, holeRadius = Shape.button;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final style = AppType.section.copyWith(color: AppColors.white);
    final scaler = MediaQuery.textScalerOf(context);
    final maxW = screen.width - Space.page * 2;
    final tp = TextPainter(text: TextSpan(text: firstBookCoachText, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
    // 두 줄 고정: 화면 폭을 넘으면 글자만 줄인다(FittedBox와 같은 비율)
    final shrink = tp.width > maxW ? maxW / tp.width : 1.0;
    final size = Size(tp.width * shrink, tp.height * shrink);
    tp.dispose();
    final l = coachLayout(screen: screen, target: target, text: size, top: top, floor: floor, blocked: blocked);
    final hole = RRect.fromRectAndRadius(target.inflate(holePad), const Radius.circular(holeRadius));
    return IgnorePointer(
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _CoachPainter(hole: hole, from: l.from, control: l.control, to: l.to))),
        Positioned.fromRect(
          rect: l.text,
          child: Semantics(
            liveRegion: true,
            label: firstBookCoachText.replaceAll('\n', ' '),
            excludeSemantics: true,
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: Text(firstBookCoachText, softWrap: false, style: style)),
          ),
        ),
      ]),
    );
  }
}

class _CoachPainter extends CustomPainter {
  _CoachPainter({required this.hole, required this.from, required this.control, required this.to});
  final RRect hole;
  final Offset from, control, to;

  /// 화살표 선 굵기 · 촉 길이 · 촉 벌림
  static const _stroke = 2.0, _head = 10.0, _spread = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(scrim, Paint()..color = AppColors.coachScrim);
    final line = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy), line);
    // 촉: 끝에서 곡선 방향 반대로 두 획
    final d = to - control;
    final back = d.distance == 0 ? const Offset(0, -1) : -d / d.distance;
    Offset turn(Offset v, double a) => Offset(v.dx * math.cos(a) - v.dy * math.sin(a), v.dx * math.sin(a) + v.dy * math.cos(a));
    canvas.drawPath(Path()
      ..moveTo(to.dx + turn(back, _spread).dx * _head, to.dy + turn(back, _spread).dy * _head)
      ..lineTo(to.dx, to.dy)
      ..lineTo(to.dx + turn(back, -_spread).dx * _head, to.dy + turn(back, -_spread).dy * _head), line);
  }

  @override
  bool shouldRepaint(_CoachPainter old) => old.hole != hole || old.from != from || old.control != control || old.to != to;
}
