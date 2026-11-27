// 책장 화면 바탕은 벽지 색(2026-11-25 사용자 '벽지 색 바꾸려면 위에 끊기지 말고 책장 화면 흰색을 다 바꿔, 다른 곳은 그렇다고 바꾸지 말고'):
// 바탕 색은 지금 벽지 색, 맨 윗줄 벽은 그리는 면 위 끝(머리줄 뒤)부터 · 맨 아랫줄 벽은 아래 끝(하단바 뒤)까지 늘려 같은 벽으로 잇는다
import 'dart:ui';

import 'package:chaekjang/domain/shelf_row.dart';
import 'package:chaekjang/features/home/home_screen.dart';
import 'package:chaekjang/scene_config/skin.dart';
import 'package:chaekjang/ui/scene.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => setSkin(defaultSkin));

  test('바탕 색 = 벽지 색: 흰 벽이면 일반 화면 바탕과 같은 흰색, 세이지 · 종이 · 크림은 그 색', () {
    expect(shelfWallColor, AppColors.bg);
    for (final (wall, hex) in [('sage', 0xFFE3E8DD), ('paper', 0xFFF6F4EE), ('cream', 0xFFF5EEE1)]) {
      expect(setSkin(defaultSkin.copyWith(wall: wall)), isTrue);
      expect(shelfWallColor, Color(hex), reason: wall);
    }
    expect(AppColors.bg, const Color(0xFFFFFFFF), reason: '다른 화면 바탕은 그대로 흰색');
  });

  test('맨 윗줄은 그리는 면 위 끝부터, 맨 아랫줄은 아래 끝까지 그린다(가운데 줄은 제 자리만)', () {
    final rows = [buildRow([], 300, top: true), buildRow([], 300), buildRow([], 300, last: true)];
    final p = ShelfPainter(rows: rows, atlases: const [], rowSpots: const [], spaces: const [], keys: const [], contentTop: 120, viewport: 800);
    const size = Size(360, 1600);
    expect(p.bandOf({0}, size).$1, 0);
    expect(p.bandOf({2}, size).$2, size.height);
    final mid = p.bandOf({1}, size);
    expect(mid.$1, greaterThan(p.bandOf({0}, size).$1));
    expect(mid.$2, lessThan(size.height));
    // 상태 표시줄 칸 띠: 맨 윗줄 벽만 그리는 같은 그림(벽만 그리는지가 다르면 다시 그린다)
    final strip = ShelfPainter(rows: rows, atlases: const [], rowSpots: const [], spaces: const [], keys: const [], contentTop: 120, viewport: 800, only: const {0}, wallOnly: true);
    expect(strip.shouldRepaint(ShelfPainter(rows: rows, atlases: const [], rowSpots: const [], spaces: const [], keys: const [], contentTop: 120, viewport: 800, only: const {0})), isTrue);
    expect(strip.bandOf({0}, const Size(360, 24)).$1, 0, reason: '띠 높이(상태 표시줄)만 그려도 위 끝부터');
  });
}
