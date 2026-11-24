// 책 그림(지금 앱 ui/BookVisual.tsx의 앞면 자세): 실제 판형(가로×세로 mm) 비율의 앞면을 둘레 여백(BOOK_PAD 4DU)과 함께 폭 width에 맞춘다.
// 밑에 옅은 종이색 판과 닿는 그림자, 위에 옅은 광택과 밝은 테두리. 표지 사진이 있으면 그 사진, 없으면 책 색 대체 표지.
// (책장과 같은 3D 몸통·빛을 쓰는 앞면 렌더러는 따로 옮긴다: 지금은 크기·자리·그림자를 앱과 같게 맞춘 앞면)
library;

import 'package:flutter/material.dart';

import '../domain/geometry.dart';
import '../domain/library.dart';
import 'kit.dart';
import 'tab_icons.dart' show shelfIcon;
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

/// 책장에 꽂힌 책 표시: 흰 동그라미 30 안 진한 책장 그림(하단 '책장' 탭 그림) + 옅은 그림자, 표지 오른쪽 아래 모서리에 0.7만큼 걸친다.
/// 내 책 격자 · 책장에 꽂기 시트가 같이 쓴다(2026-11-24 사용자 '내 책 목록에 아이콘 있잖아': 꽂기 시트에 작은 회색 그림을 따로 그렸었다)
const shelfBadgeSize = 30.0;

/// 표지 칸(coverRect) 위에 얹는 책장 표시(Stack 안, 화면 읽기는 칸 이름이 맡는다)
Widget shelfBadgeOn(({double edge, double w, double h}) r) => Positioned(
      left: r.edge + r.w - shelfBadgeSize * 0.7,
      top: r.edge + r.h - shelfBadgeSize * 0.7,
      child: ExcludeSemantics(
        child: Container(
          width: shelfBadgeSize,
          height: shelfBadgeSize,
          decoration: const BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x1F191F28), offset: Offset(0, 1), blurRadius: 4)],
          ),
          child: Center(child: shelfIcon(AppColors.ink, size: shelfBadgeSize * 0.6)),
        ),
      ),
    );

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
