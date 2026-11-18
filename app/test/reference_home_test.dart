// 새 서재 예시 책장(지금 앱 home-reference): 18권·자리 18개·그림 표지 3권, 갈피 보이는 책, 배치 JSON이 읽힌다
import 'dart:convert';
import 'dart:io';

import 'package:chaekjang/domain/book_look.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/domain/layout_json.dart';
import 'package:chaekjang/domain/reference_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('예시 책장 읽기', () {
    final h = referenceHomeOf(jsonDecode(File('assets/reference_home.json').readAsStringSync()) as Map<String, Object?>);
    expect(h.books.length, 18);
    final l = layoutFromJson(h.layoutJson)!;
    expect(l.placements.length, 18);
    expect(l.shelves.length, 3);
    expect(l.placements.every((p) => h.books.containsKey(p.bookId)), isTrue);
    final pictures = [for (final b in h.books.values) if (b.reference != null) b.title];
    expect(pictures, containsAll(['느린 계절', '여름의 숲', '우리가 빛의 속도로 갈 수 없다면']));
    for (final k in ['night', 'forest', 'sunset']) {
      expect(File('assets/reference/$k.png').existsSync(), isTrue);
    }
    // 그림 표지는 그림 책 빛(회색 반사율)으로 — 지금 앱은 책 색에 물들었다(Flutter에서만 고친다)
    final night = h.books.values.firstWhere((b) => b.reference == 'night');
    expect(lookOf(night).picture, isTrue);
    expect(lookOf(h.books['home-reference-b02']!).ribbons, 2);
    expect(lookOf(h.books['home-reference-b02']!).material, 'linen');
  });

  test('내 책이 생기면 예시 책을 전부 치운다(2026-11-15 사용자 결정)', () {
    final h = referenceHomeOf(jsonDecode(File('assets/reference_home.json').readAsStringSync()) as Map<String, Object?>);
    final sample = layoutFromJson(h.layoutJson)!;
    bool isSample(String id) => h.books.containsKey(id);
    // 첫 책: 예시 자리만 있으면 빈 선반 세 칸이 남는다
    final fresh = withoutSamples(sample, isSample)!;
    expect(fresh.placements, isEmpty);
    expect(fresh.shelves.length, 3);
    // 예시 세 칸 아래 내 책이 꽂힌 넷째·다섯째 칸(예전 설치): 내 책 선반을 위로 모으고 빈 선반은 세 칸까지
    final mine = ShelfLayout(
      [...sample.shelves, const Shelf('mine-4', 3), const Shelf('mine-5', 4)],
      [...sample.placements, const BookPlacement(bookId: 'me1', shelfId: 'mine-4', order: 0, pos: 0), const BookPlacement(bookId: 'me2', shelfId: 'mine-5', order: 0, pos: 0)],
      const [],
    );
    final cleaned = withoutSamples(mine, isSample)!;
    expect([for (final s in sortedShelves(cleaned)) s.id].take(2), ['mine-4', 'mine-5']);
    expect(cleaned.shelves.length, 3);
    expect([for (final p in cleaned.placements) p.bookId], ['me1', 'me2']);
    // 치울 예시가 없으면 그대로
    expect(withoutSamples(cleaned, isSample), isNull);
  });
}
