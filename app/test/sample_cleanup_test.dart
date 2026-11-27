// 예전 앱이 빈 서재에 깔던 예시 책장 자리 치우기(2026-11-25 예시 책장 삭제, domain/sample_cleanup)
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/sample_cleanup.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 예전 설치: 세 칸에 예시 책 여섯 권(하나는 서랍)
  final sample = ShelfLayout(
    const [Shelf('s1', 0), Shelf('s2', 1), Shelf('s3', 2)],
    [
      for (var i = 1; i <= 5; i++) BookPlacement(bookId: 'home-reference-b0$i', shelfId: 's${(i - 1) % 3 + 1}', order: i, pos: 0),
    ],
    const ['home-reference-b06'],
  );

  test('예시 책 id', () {
    expect(isSampleBookId('home-reference-b01'), isTrue);
    expect(isSampleBookId('home-reference-b17-2'), isTrue);
    expect(isSampleBookId('home-reference-b1'), isFalse);
    expect(isSampleBookId('b-1234'), isFalse);
  });

  test('예시 자리만 있으면 빈 선반 세 칸이 남는다', () {
    final fresh = withoutSamples(sample, isSampleBookId)!;
    expect(fresh.placements, isEmpty);
    expect(fresh.drawer, isEmpty);
    expect(fresh.shelves.length, 3);
  });

  test('내 책이 꽂힌 선반은 위로 모으고 빈 선반은 세 칸까지', () {
    final mine = ShelfLayout(
      [...sample.shelves, const Shelf('mine-4', 3), const Shelf('mine-5', 4)],
      [...sample.placements, const BookPlacement(bookId: 'me1', shelfId: 'mine-4', order: 0, pos: 0), const BookPlacement(bookId: 'me2', shelfId: 'mine-5', order: 0, pos: 0)],
      const ['home-reference-b06', 'me3'],
    );
    final cleaned = withoutSamples(mine, isSampleBookId)!;
    expect([for (final s in sortedShelves(cleaned)) s.id].take(2), ['mine-4', 'mine-5']);
    expect(cleaned.shelves.length, 3);
    expect([for (final p in cleaned.placements) p.bookId], ['me1', 'me2']);
    expect(cleaned.drawer, ['me3']);
    // 치울 예시가 없으면 그대로
    expect(withoutSamples(cleaned, isSampleBookId), isNull);
  });
}
