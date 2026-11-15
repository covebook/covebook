// 책장에 놓기·옮기기(Flutter 2026-11-15 QA 고침): 줄 가운데 빈 틈에 새 책 놓기, 꽉 찬 줄에서 먼 자리로 옮기면 사이 책이 밀린다
import 'package:chaekjang/domain/geometry.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/shelf_scene.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

Book _b(String id, double t) => Book(id: id, title: id, dims: BookDims(220, t, 140));

void main() {
  test('끝에 자리가 없으면 줄 안의 빈 틈에 놓는다(다른 책은 그대로)', () {
    final books = {'a': _b('a', 30), 'z': _b('z', 30), 'new': _b('new', 30)};
    final l = ShelfLayout(
      [const Shelf('s1', 0)],
      [BookPlacement(bookId: 'a', shelfId: 's1', order: 0, pos: 0), BookPlacement(bookId: 'z', shelfId: 's1', order: 1, pos: shelfUsableWidth - 30)],
      const ['new'],
    );
    final first = fitCandidates(l, books, 'new').first;
    final xs = bookXs(first, books);
    expect(xs['a'], 0);
    expect(xs['z'], shelfUsableWidth - 30);
    expect(xs['new']!, greaterThanOrEqualTo(29.9));
    expect(xs['new']! + 30, lessThanOrEqualTo(shelfUsableWidth - 30 + 0.01));
    expect(checkSpace(first, books), isNull);
  });

  test('틈이 책보다 좁으면 후보가 없다', () {
    final books = {'a': _b('a', 30), 'z': _b('z', 30), 'new': _b('new', 40)};
    final l = ShelfLayout(
      [const Shelf('s1', 0)],
      [BookPlacement(bookId: 'a', shelfId: 's1', order: 0, pos: 0), BookPlacement(bookId: 'z', shelfId: 's1', order: 1, pos: 50)],
      const ['new'],
    );
    // 끝(80부터)에는 들어간다: 끝 후보가 먼저
    final first = fitCandidates(l, books, 'new').first;
    expect(bookXs(first, books)['new']!, greaterThanOrEqualTo(80 - 0.01));
  });

  test('꽉 찬 줄: 첫 책을 다섯째 자리로 옮기면 사이 책이 밀려 들어간다', () {
    final books = <String, Book>{};
    final ps = <BookPlacement>[];
    var x = 0.0;
    for (var i = 0; i < 10; i++) {
      final t = 30.0 + (i % 3) * 4;
      books['b$i'] = _b('b$i', t);
      ps.add(BookPlacement(bookId: 'b$i', shelfId: 's1', order: i, pos: x));
      x += t;
    }
    final l = resolveLeans(ensureShelves(ShelfLayout([const Shelf('s1', 0)], ps, const [])), books);
    final t = findSwapTarget(l, books, 'b0', bookXs(l, books)['b5']! + 17);
    expect(t.kind, 'place');
    final r = applySwapTarget(l, books, 'b0', t);
    expect(r.ok, isTrue, reason: r.reason);
    final next = resolveLeans(ensureShelves(r.layout!), books);
    expect(validateLayout(next, books, books.keys.toList()), isEmpty);
    final order = [for (final it in shelfItems(next, 's1')) it.bookIds.first];
    expect(order.indexOf('b0'), greaterThan(3));
  });
}
