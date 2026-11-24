// 책 그림(지금 앱 ui/BookVisual.tsx의 앞면 자세): 실제 판형(가로×세로 mm) 비율의 앞면을 둘레 여백(BOOK_PAD 4DU)과 함께 폭 width에 맞춘다.
// 밑에 옅은 종이색 판과 닿는 그림자, 위에 옅은 광택과 밝은 테두리. 표지 사진이 있으면 그 사진, 없으면 책 색 대체 표지.
// (책장과 같은 3D 몸통·빛을 쓰는 앞면 렌더러는 따로 옮긴다: 지금은 크기·자리·그림자를 앱과 같게 맞춘 앞면)
library;

import 'package:flutter/material.dart';

import '../domain/geometry.dart';
import '../domain/library.dart';
import '../scene_config/skin.dart' show skinPlank;
import 'kit.dart';
import 'theme.dart';

const _bookPad = 4.0; // 캔버스 여백(DU): 갈피·가장자리가 잘리지 않게
const _estimated = (widthMm: 128.0, heightMm: 188.0); // 판형을 모를 때(지금 앱 ESTIMATED_SIZE)

/// 폭 width로 그렸을 때 표지 자리(여백 edge 안쪽의 폭·높이)
/// uniform: 판형과 상관없이 같은 크기(추정 판형 128×188 비율)로 — 내 책 격자·목록처럼 나란히 놓을 때(표지는 그 틀에 맞춰 잘린다).
/// 2026-11-16 사용자 '책들 크기가 동일하지 않아서 높낮이가 다 다른데'
({double edge, double w, double h}) coverRect(num? widthMm, num? heightMm, double width, {bool uniform = false}) {
  final known = !uniform && widthMm != null && heightMm != null;
  final fw = mm((known ? widthMm : _estimated.widthMm).toDouble()), fh = mm((known ? heightMm : _estimated.heightMm).toDouble());
  final scale = width / (fw + _bookPad * 2);
  return (edge: _bookPad * scale, w: fw * scale, h: fh * scale);
}

/// 책장에 꽂힌 책 표시(내 책 격자 · 책장에 꽂기 시트): 표지 밑에 선반 판 한 토막. 표지가 판 윗면에 서 있고(표지 아래 끝 = 윗면 가운데),
/// 판은 표지보다 양옆으로 표지 폭의 7% 길다. 색은 지금 책장 선반 색(skinPlank): 앞면은 그 색, 윗면은 밝게, 아래로 옅은 그늘.
/// 2026-11-25 사용자 '책장에 있다는 표시 원 안에 책장 아이콘 넣지 말고 사진처럼 넣은 책 밑에 선반 디자인'(전에는 표지 오른쪽 아래 흰 원 + 책장 그림)
({double ext, double top, double front, double shadow}) _plankOf(double coverW) =>
    (ext: coverW * 0.07, top: coverW * 0.06, front: coverW * 0.055, shadow: coverW * 0.05);

/// 표지 칸(coverRect) 밑에 까는 선반 판(Stack 안, 표지 그림보다 먼저 = 뒤에. 화면 읽기는 칸 이름이 맡는다)
Widget shelfPlankUnder(({double edge, double w, double h}) r) {
  final p = _plankOf(r.w);
  return Positioned(
    left: r.edge - p.ext,
    top: r.edge + r.h - p.top / 2,
    width: r.w + p.ext * 2,
    height: p.top + p.front + p.shadow,
    child: ShelfPlank(top: p.top, front: p.front, shadow: p.shadow),
  );
}

/// 선반 판 한 토막(윗면 top · 앞면 front · 아래 그늘 shadow 높이). 꾸밈 그림이라 누르기 · 화면 읽기에서 빠진다
class ShelfPlank extends StatelessWidget {
  const ShelfPlank({super.key, required this.top, required this.front, required this.shadow});
  final double top, front, shadow;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: ExcludeSemantics(child: CustomPaint(painter: _PlankPainter(Color(0xFF000000 | skinPlank.color), top, front, shadow))));
}

/// 선반 판(그늘까지)이 책 그림 칸(BookVisual) 아래로 나가는 길이: 아래 글자와의 틈을 이만큼 더 둔다(판이 없는 칸도 같은 줄에 맞게 함께)
double shelfPlankBelow(({double edge, double w, double h}) r) {
  final p = _plankOf(r.w);
  return (p.top / 2 + p.front + p.shadow - r.edge).clamp(0, double.infinity).toDouble();
}

class _PlankPainter extends CustomPainter {
  _PlankPainter(this.color, this.top, this.front, this.shadow);
  final Color color;
  final double top, front, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = Radius.circular(front * 0.35);
    // 판 밑 그늘(바닥에 닿는 옅은 번짐)
    canvas.drawRRect(
      RRect.fromLTRBR(front * 0.4, top + front * 0.4, w - front * 0.4, top + front + shadow * 0.4, r),
      Paint()
        ..color = const Color(0x2E573F28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow * 0.45),
    );
    // 앞면: 선반 색, 아래로 조금 어둡게
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(0, top * 0.5, w, top + front, bottomLeft: r, bottomRight: r),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, Color.lerp(color, const Color(0xFF3B2A1C), 0.1)!],
        ).createShader(Rect.fromLTRB(0, top, w, top + front)),
    );
    // 윗면: 밝게(위에서 빛), 앞 모서리에 아주 옅은 밝은 줄
    canvas.drawRRect(RRect.fromLTRBAndCorners(0, 0, w, top, topLeft: r, topRight: r), Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.45)!);
    canvas.drawRect(Rect.fromLTRB(0, top - 0.6, w, top), Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.65)!);
  }

  @override
  bool shouldRepaint(_PlankPainter old) => old.color != color || old.top != top || old.front != front || old.shadow != shadow;
}

class BookVisual extends StatelessWidget {
  const BookVisual({super.key, required this.lib, required this.id, required this.width, this.uniform = false});
  final Library lib;
  final String id;
  final double width;

  /// 모든 책을 같은 크기 틀로(coverRect uniform)
  final bool uniform;

  @override
  Widget build(BuildContext context) {
    final b = lib.books[id];
    final e = b == null ? null : lib.editions[b.editionId];
    if (b == null || e == null) return const SizedBox.shrink();
    final r = coverRect(e.widthMm, e.heightMm, width, uniform: uniform);
    final radius = width * 0.025;
    final color = themeColorOf(lib, id);
    return Semantics(
      label: '${e.title} 표지',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: r.h + r.edge * 2,
        child: Stack(children: [
          // 밑판: 종이색 + 바닥에 닿는 그림자
          Positioned(
            left: r.edge + 1,
            right: (r.edge - width * 0.018).clamp(0, double.infinity),
            top: r.edge + 3,
            bottom: r.edge,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE8D8C0),
                borderRadius: BorderRadius.circular(radius),
                border: const Border(right: BorderSide(color: Color(0xFFF7ECDB))),
                boxShadow: [
                  cssShadow(const Color.fromRGBO(124, 85, 48, 0.19), 1, width * 0.043, width * 0.072),
                  cssShadow(const Color.fromRGBO(87, 63, 40, 0.18), 0, 1, 1.2),
                ],
              ),
            ),
          ),
          Positioned(
            left: r.edge,
            top: r.edge,
            width: r.w,
            height: r.h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(fit: StackFit.expand, children: [
                RealCover(uri: e.coverUri, title: e.title, color: color, width: r.w, ratio: r.w / r.h),
                // 옅은 광택(왼쪽 위 밝게, 오른쪽 아래 아주 조금 어둡게)과 밝은 테두리
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x0BFFFFFF), Color(0x00FFFFFF), Color(0x06271A11)],
                        stops: [0, 0.42, 1],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: const Color(0x3BFFFAEC), width: 0.65),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
