// 세운 책 돌리기(2026-11-26 사용자 '정면이랑 측면을 세우기로 통일'): 0° 책등이 앞(책등 자세) ~ 90° 표지가 앞(표지 자세 돌림 0).
// 그 사이는 표지 자세를 책등 쪽(+)으로 (90 − 각) 돌린 것. 물리 규칙(겹치지 않음 · 선반 안)은 엔진 그대로
import 'dart:convert';
import 'dart:io';

import 'package:chaekjang/domain/book3.dart';
import 'package:chaekjang/domain/book3_physics.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/domain/vec3.dart';
import 'package:flutter_test/flutter_test.dart';

import 'edit_matches_app_test.dart' show layoutOf, d;

Book _b(String id, double t) => Book(id: id, title: id, dims: BookDims(220, t, 140));

void main() {
  final books = {'a': _b('a', 30), 'b': _b('b', 30), 'c': _b('c', 30)};
  final l = ShelfLayout(
    [const Shelf('s1', 0)],
    [
      BookPlacement(bookId: 'a', shelfId: 's1', order: 0, pos: 0),
      BookPlacement(bookId: 'b', shelfId: 's1', order: 1, pos: 200),
      BookPlacement(bookId: 'c', shelfId: 's1', order: 2, pos: 450),
    ],
    const [],
  );

  test('돌림 +90 표지 자세는 책등이 앞(보는 쪽 −z)을 본다: 책등 자세와 같은 방향', () {
    final dims = Dims(30, 220, 140);
    final b = frontBook3('x', dims, 0, 0, 0, 90);
    // 책등 면 가운데(책 좌표 z = 0 면)와 앞마구리 면 가운데(z = w): 책등 쪽이 더 앞(작은 z)
    final spine = toWorld(b, Vec3(dims.t / 2, dims.h / 2, 0));
    final fore = toWorld(b, Vec3(dims.t / 2, dims.h / 2, dims.w));
    expect(spine.z, lessThan(fore.z - dims.w + 0.01));
    expect(frontSpinOfTurn(0), 90);
    expect(frontSpinOfTurn(90), 0);
    expect(standTurnOf(60), 30);
  });

  test('책등 자세에서 30° 돌리면 표지 자세 돌림 60, 겹치지 않고 선반 안. 90°면 표지가 앞, 0°면 다시 책등 자세', () {
    final r = setStandTurn(l, books, 'b', 30);
    expect(r.ok, isTrue, reason: r.reason);
    final p = placementOf(r.layout!, 'b')!;
    expect(p.pose, Pose.front);
    final fs = frontStateOf(r.layout!, books, 'b')!;
    expect(standTurnOf(fs.state.spin), closeTo(30, 0.6));
    expect(checkSpace(r.layout!, books), isNull);
    final full = setStandTurn(r.layout!, books, 'b', 90);
    expect(full.ok, isTrue, reason: full.reason);
    expect(frontStateOf(full.layout!, books, 'b')!.state.spin.abs(), lessThan(0.01));
    final back = setStandTurn(full.layout!, books, 'b', 0);
    expect(back.ok, isTrue, reason: back.reason);
    expect(placementOf(back.layout!, 'b')!.pose, Pose.upright);
    expect(checkSpace(back.layout!, books), isNull);
    expect(setStandTurn(back.layout!, books, 'b', 0).reason, 'no-change');
  });

  test('옆 책과 붙어 표지를 앞으로 다 돌릴 자리가 없어도 닿는 데까지는 돌아간다(겹치지 않게)', () {
    final tight = ShelfLayout(
      [const Shelf('s1', 0)],
      [
        for (var i = 0; i < 3; i++) BookPlacement(bookId: 'abc'[i], shelfId: 's1', order: i, pos: i * 31.0),
      ],
      const [],
    );
    final r = setStandTurn(tight, books, 'b', 60);
    if (r.ok) {
      expect(checkSpace(r.layout!, books), isNull);
      final p = placementOf(r.layout!, 'b')!;
      expect(p.pose, Pose.front);
      final turn = standTurnOf(frontStateOf(r.layout!, books, 'b')!.state.spin);
      expect(turn, inInclusiveRange(0.75, 60.6));
    } else {
      expect(r.reason, 'no-space');
    }
  });

  test('지금 앱 편집 사례의 모든 세운 책: 20° 돌리면 겹치지 않고, 0°로 되돌리면 책등 자세', () {
    final json = jsonDecode(File('test/fixtures/edit_cases.json').readAsStringSync()) as Map<String, dynamic>;
    var turned = 0;
    for (final c in (json['cases'] as List).cast<Map<String, dynamic>>()) {
      final BookMap bs = {
        for (final b in (c['books'] as List).cast<Map<String, dynamic>>())
          b['id'] as String: Book(id: b['id'] as String, title: b['title'] as String, dims: BookDims(d(b['dims']['height'])!, d(b['dims']['thickness'])!, d(b['dims']['coverWidth'])!)),
      };
      for (final s in (c['steps'] as List).cast<Map<String, dynamic>>()) {
        final layout = layoutOf(s['before'] as Map<String, dynamic>);
        for (final p in layout.placements) {
          if (p.pose != Pose.upright || p.stackId != null || boxOf(layout, bs, p.bookId) == null) continue;
          final r = setStandTurn(layout, bs, p.bookId, 20);
          if (!r.ok) {
            expect(r.reason, 'no-space', reason: '${c['name']} ${p.bookId}');
            continue;
          }
          expect(checkSpace(r.layout!, bs), isNull, reason: '${c['name']} ${p.bookId}');
          final turn = standTurnOf(frontStateOf(r.layout!, bs, p.bookId)!.state.spin);
          expect(turn, inInclusiveRange(0.75, 20.6), reason: '${c['name']} ${p.bookId}');
          final back = setStandTurn(r.layout!, bs, p.bookId, 0);
          expect(back.ok, isTrue, reason: '${c['name']} ${p.bookId} ${back.reason}');
          expect(placementOf(back.layout!, p.bookId)!.pose, Pose.upright);
          turned++;
        }
      }
    }
    expect(turned, greaterThan(5));
  });
}
