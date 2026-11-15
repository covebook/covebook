// 전체 책 목록 거르기·정렬과 삭제 문구가 지금 앱(features/book/all-books.ts) 규칙대로인지 본다
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/book/all_books.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t0 = '2026-01-01T00:00:00.000Z';
  Edition ed(String id, String title, List<String> authors) => Edition(id: id, title: title, authors: authors, source: 'manual', createdAt: t0, updatedAt: t0);
  MyBook mb(String id, ReadStatus st, String created, {String? hidden}) =>
      MyBook(id: id, editionId: 'e$id', status: st, createdAt: created, updatedAt: created, hiddenAt: hidden);
  final lib = Library(
    editions: {'ea': ed('ea', '나무', ['김가']), 'eb': ed('eb', '가방', ['박나']), 'ec': ed('ec', '다리', ['이다']), 'ed': ed('ed', '숨김', ['최라'])},
    books: {
      'a': mb('a', ReadStatus.reading, '2026-03-01T00:00:00.000Z'),
      'b': mb('b', ReadStatus.read, '2026-05-01T00:00:00.000Z'),
      'c': mb('c', ReadStatus.read, '2026-05-01T00:00:00.000Z'),
      'd': mb('d', ReadStatus.want, '2026-06-01T00:00:00.000Z', hidden: '2026-07-01T00:00:00.000Z'),
    },
  );
  final books = {
    for (final (id, title, author) in [('a', '나무', '김가'), ('b', '가방', '박나'), ('c', '다리', '이다'), ('d', '숨김', '최라')]) id: Book(id: id, title: title, author: author),
  };
  final layout = ShelfLayout([Shelf('s1', 0)], [BookPlacement(bookId: 'a', shelfId: 's1', order: 0, pose: Pose.upright, tilt: 0)], ['b']);
  List<String> ids(List<AllBooksRow> r) => [for (final x in r) x.book.id];

  test('숨긴 책은 빠지고, 최근순은 등록 늦은 순 → 같으면 제목순', () {
    expect(ids(listAllBooks(lib, books, layout)), ['b', 'c', 'a']);
  });
  test('제목순', () {
    expect(ids(listAllBooks(lib, books, layout, sort: AllBooksSort.title)), ['b', 'a', 'c']);
  });
  test('읽기 상태·책장에 없는 책·검색(제목 또는 저자)', () {
    expect(ids(listAllBooks(lib, books, layout, status: ReadStatus.read)), ['b', 'c']);
    expect(ids(listAllBooks(lib, books, layout, offShelfOnly: true)), ['b', 'c']);
    expect(ids(listAllBooks(lib, books, layout, q: ' 박나 ')), ['b']);
    expect(listAllBooks(lib, books, layout).firstWhere((r) => r.book.id == 'a').onShelf, isTrue);
  });
  test('삭제 문구: 0개인 것은 빼고 한 줄에 한 문장', () {
    expect(deleteNote((rounds: 2, marks: 3, essays: 0, sessions: 1)), '갈피 3개와 읽은 기록 2회도 지워져요.\n독서 시간은 통계에 남아요.\n되돌릴 수 없어요.');
    expect(deleteNote((rounds: 1, marks: 0, essays: 0, sessions: 0)), '읽은 기록 1회도 지워져요.\n되돌릴 수 없어요.');
    expect(deleteNote((rounds: 0, marks: 0, essays: 0, sessions: 0)), '되돌릴 수 없어요.');
    // 긴 감상도 책과 함께 지워진다(2026-11-16 기록 > 감상). 조사는 받침대로
    expect(deleteNote((rounds: 1, marks: 0, essays: 3, sessions: 0)), '감상 3편과 읽은 기록 1회도 지워져요.\n되돌릴 수 없어요.');
    expect(deleteNote((rounds: 1, marks: 2, essays: 1, sessions: 0)), '갈피 2개, 감상 1편과 읽은 기록 1회도 지워져요.\n되돌릴 수 없어요.');
  });

  test('내 책 필터 조건 줄: 기본(모든 책·최근순)이면 비고, 건 조건만 이름으로', () {
    expect(filterConditions(), isEmpty);
    expect(filterConditions(offShelfOnly: true, year: 2025, sort: AllBooksSort.title), ['책장에 없는 책', '2025년 완독', '제목순']);
    expect(filterConditions(sort: AllBooksSort.recent, year: 2024), ['2024년 완독']);
  });

  test('내 책 개수는 검색·상태·필터를 모두 적용한 결과 수와 같다', () {
    final r = listAllBooks(lib, books, layout, q: '다', status: ReadStatus.read, offShelfOnly: true);
    // c(다리, 완독)는 책장 서랍에도 없고 배치에도 없어 책장에 없는 책. b(가방)는 '다'가 없다
    expect(ids(r), ['c']);
  });
}

