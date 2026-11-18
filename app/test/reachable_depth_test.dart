// 앞뒤 막대 범위(2026-11-18 사용자: 책 앞에 두면 뒤 책 때문에 못 가는데 막대는 벽만 보고 범위를 보였다).
// 지금 앱 편집 사례(edit_cases.json)의 모든 배치·모든 책에서: 갈 수 있는 범위는 벽 범위 안이고, 그 끝으로 옮기면 정확히 그 자리에 간다
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'edit_matches_app_test.dart' show layoutOf, d;

void main() {
  test('갈 수 있는 앞뒤 범위 ⊆ 벽 범위, 끝으로 옮기면 그 끝에 닿는다', () {
    final json = jsonDecode(File('test/fixtures/edit_cases.json').readAsStringSync()) as Map<String, dynamic>;
    var checked = 0, narrower = 0;
    for (final c in (json['cases'] as List).cast<Map<String, dynamic>>()) {
      final BookMap books = {
        for (final b in (c['books'] as List).cast<Map<String, dynamic>>())
          b['id'] as String: Book(id: b['id'] as String, title: b['title'] as String, dims: BookDims(d(b['dims']['height'])!, d(b['dims']['thickness'])!, d(b['dims']['coverWidth'])!)),
      };
      for (final s in (c['steps'] as List).cast<Map<String, dynamic>>()) {
        final layout = layoutOf(s['before'] as Map<String, dynamic>);
        for (final p in layout.placements) {
          if (boxOf(layout, books, p.bookId) == null) continue;
          final wall = depthRange(layout, books, p.bookId);
          final r = reachableDepth(layout, books, p.bookId);
          // 지금 자리가 벽 범위 밖(앞으로 조금 나온 책)이면 범위는 지금 자리까지 넓다
          expect(r.lo, greaterThanOrEqualTo(math.min(wall.lo, wall.z) - 0.01), reason: '${c['name']} ${p.bookId} lo');
          expect(r.hi, lessThanOrEqualTo(math.max(wall.hi, wall.z) + 0.01), reason: '${c['name']} ${p.bookId} hi');
          expect(r.z, inInclusiveRange(r.lo - 0.01, r.hi + 0.01));
          expect(r.back, wall.hi);
          if (r.lo > wall.lo + 0.5 || r.hi < wall.hi - 0.5) narrower++;
          // 끝으로 옮겨도 그 범위를 넘지 않는다(막대가 보인 범위 = 실제로 가는 범위).
          // 벽에 젖혀 기댄 표지 책은 상자 z와 바닥 자리 값이 달라 따로(기존 동작)
          final tipped = p.pose == Pose.front && (frontStateOf(layout, books, p.bookId)?.state.pitch ?? 0) > 0;
          if (!tipped) {
            for (final end in [r.lo, r.hi]) {
              if ((end - r.z).abs() < 0.01) continue;
              final e = setDepth(layout, books, p.bookId, end);
              if (!e.ok) continue;
              expect(boxOf(e.layout!, books, p.bookId)!.z, inInclusiveRange(r.lo - 0.05, r.hi + 0.05), reason: '${c['name']} ${p.bookId} → $end');
            }
          }
          checked++;
        }
      }
    }
    expect(checked, greaterThan(20));
    // 옆·뒤 책 때문에 벽 범위보다 좁아진 경우가 사례 안에 실제로 있다
    expect(narrower, greaterThan(0));
  });
}
