// 2026-11-16 페르소나 QA 2차(책장·책·읽기·백업): 뺀 책 제자리 진열, 백업 파일 이름·시각, 삭제 문구의 남는 시간, 꾸미기 조작부(큰 글씨·순서 단추)
import 'package:chaekjang/domain/geometry.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/book/all_books.dart';
import 'package:chaekjang/features/home/decorate_panel.dart';
import 'package:chaekjang/store/backup.dart' show backupFileName, backupTimeLabel;
import 'package:chaekjang/ui/keep_all.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Book _b(String id, double t) => Book(id: id, title: id, dims: BookDims(220, t, 140));

const t1 = '2026-11-16T05:00:00.000Z';

void main() {
  group('뺀 책을 다시 진열하면 뺄 때 자리로(현우 F12)', () {
    final books = {'a': _b('a', 30), 'b': _b('b', 30), 'c': _b('c', 30)};
    final l = ShelfLayout(
      [const Shelf('s1', 0)],
      [
        BookPlacement(bookId: 'a', shelfId: 's1', order: 0, pos: 0),
        BookPlacement(bookId: 'b', shelfId: 's1', order: 1, pos: 40),
        BookPlacement(bookId: 'c', shelfId: 's1', order: 2, pos: 90),
      ],
      const [],
    );

    test('맨 왼쪽 책을 빼고 되돌리면 맨 왼쪽 같은 가로 자리', () {
      final was = placementOf(l, 'a')!;
      final out = moveToDrawer(l, 'a', books).layout!;
      final back = reinsertAt(out, books, was, 0);
      expect(back, isNotNull);
      expect([for (final it in shelfItems(back!, 's1')) it.bookIds.first], ['a', 'b', 'c']);
      final xs = bookXs(back, books);
      expect(xs['a'], 0);
      expect(xs['b'], 40);
      expect(xs['c'], 90);
      expect(back.drawer, isNot(contains('a')));
      expect(checkSpace(back, books), isNull);
    });

    test('가운데 책도 그 차례로', () {
      final was = placementOf(l, 'b')!;
      final back = reinsertAt(moveToDrawer(l, 'b', books).layout!, books, was, 1);
      expect([for (final it in shelfItems(back!, 's1')) it.bookIds.first], ['a', 'b', 'c']);
      expect(bookXs(back, books)['b'], 40);
    });

    test('선반이 없어졌으면 null(부르는 쪽이 빈 자리로 놓는다)', () {
      final was = placementOf(l, 'a')!;
      final out = moveToDrawer(l, 'a', books).layout!;
      final noShelf = ShelfLayout([const Shelf('s2', 0)], const [], out.drawer);
      expect(reinsertAt(noShelf, books, was, 0), isNull);
    });

    test('순서 단추: 한 칸 오른쪽으로, 끝에서는 바뀌지 않는다', () {
      final r = moveBy(l, books, 'a', 1);
      expect(r.ok, isTrue, reason: r.reason);
      expect([for (final it in shelfItems(r.layout!, 's1')) it.bookIds.first], ['b', 'a', 'c']);
      expect(moveBy(l, books, 'c', 1).ok, isFalse);
      expect(shelfUsableWidth, greaterThan(120));
    });
  });

  group('백업 파일 이름·시각은 기기 시각(현우 F6)', () {
    test('파일 이름은 현지 시각', () {
      final local = DateTime.parse(t1).toLocal();
      String p2(int n) => n.toString().padLeft(2, '0');
      expect(backupFileName(t1), 'chaekjang-backup-${local.year}-${p2(local.month)}-${p2(local.day)}-${p2(local.hour)}-${p2(local.minute)}-00.json');
    });

    test('복원 확인에 시각까지, 올해가 아니면 해도', () {
      final local = DateTime.parse(t1).toLocal();
      final hm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      expect(backupTimeLabel(t1, now: DateTime(local.year, 12, 1)), '${local.month}월 ${local.day}일 $hm');
      expect(backupTimeLabel(t1, now: DateTime(local.year + 1, 1, 1)), '${local.year}년 ${local.month}월 ${local.day}일 $hm');
      expect(backupTimeLabel('x'), '');
    });
  });

  test('삭제 요약: 남는 독서 시간 합(현우 F4)', () {
    final lib = Library(
      editions: {'e1': Edition(id: 'e1', title: '가호', authors: const [], source: 'manual', createdAt: t1, updatedAt: t1)},
      books: {'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1)},
      rounds: const {},
      sessions: {
        's1': Session(id: 's1', startedAt: t1, endedAt: t1, durationMs: 100000, createdAt: t1, updatedAt: t1, myBookId: 'b1'),
        's2': Session(id: 's2', startedAt: t1, endedAt: t1, durationMs: 37000, createdAt: t1, updatedAt: t1, myBookId: 'b1'),
        's3': Session(id: 's3', startedAt: t1, endedAt: t1, durationMs: 999000, createdAt: t1, updatedAt: t1),
      },
      bookmarks: const {},
      bindings: const {},
    );
    final n = deleteSummary(lib, ['b1']);
    expect(n.sessions, 2);
    expect(n.ms, 137000);
    expect(deleteNote(n), '독서 시간 2분은 책 없이 읽은 시간으로 통계에 남아요.\n되돌릴 수 없어요.');
  });

  group('꾸미기 조작부(영숙 F7, 2026-11-18 순서 줄·안내 뺌)', () {
    Widget panel({String? title, double scale = 1, VoidCallback? onSkin}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 640), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: DecoratePanel(
                  title: title,
                  pose: title == null ? null : Pose.upright,
                  lean: 0,
                  canLean: (left: true, right: true),
                  msg: null,
                  spin: 0,
                  spinMax: 30,
                  spinRange: null,
                  depth: title == null ? null : (lo: -20.0, hi: 20.0, z: 0.0, back: 20.0),
                  canUndo: false,
                  onPose: (_) {},
                  onLean: (_) {},
                  onSpin: (_) {},
                  onDepth: (_) {},
                  onUndo: () {},
                  onDone: () {},
                  onSkin: onSkin ?? () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('처음(책 고르기 전): 안내 한 줄과 선반·벽지 단추만, 흐린 자세 탭 없음, 2배 글자에서도 넘치지 않는다', (tester) async {
      var skin = 0;
      await tester.pumpWidget(panel(scale: 2, onSkin: () => skin++));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('끌어'), findsNothing);
      expect(find.textContaining(keepAll('꾸밀')), findsOneWidget);
      expect(find.text('책등'), findsNothing);
      expect(find.text('앞뒤'), findsNothing);
      await tester.tap(find.text('선반, 벽지 바꾸기'));
      expect(skin, 1);
    });

    testWidgets('고른 책: 선반·벽지는 제목 줄의 작은 글자 단추', (tester) async {
      await tester.pumpWidget(panel(title: '작별하지 않는다'));
      expect(find.text('선반, 벽지 바꾸기'), findsNothing);
      expect(find.text('선반, 벽지'), findsOneWidget);
      expect(find.text('책등'), findsOneWidget);
    });

    testWidgets('고른 책: 순서 줄·자리 표시 없이 앞뒤·기대기, 2배 글자에서 라벨이 넘치지 않는다', (tester) async {
      await tester.pumpWidget(panel(title: '작별하지 않는다', scale: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('앞뒤'), findsOneWidget);
      expect(find.text('기대기'), findsOneWidget);
      expect(find.text('순서'), findsNothing);
      expect(find.textContaining('번째 선반'), findsNothing);
      expect(find.bySemanticsLabel('왼쪽으로 한 칸 옮기기'), findsNothing);
    });

    testWidgets('1배 글자: 제목과 단추가 한 줄', (tester) async {
      await tester.pumpWidget(panel(title: '작별하지 않는다'));
      expect(tester.takeException(), isNull);
      final title = tester.getCenter(find.text(keepAll('작별하지 않는다')));
      final done = tester.getCenter(find.text('완료'));
      expect((title.dy - done.dy).abs(), lessThan(12));
    });
  });
}
