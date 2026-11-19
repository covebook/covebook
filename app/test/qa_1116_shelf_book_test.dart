// 2026-11-16 페르소나 QA 2차(책장·책·읽기·백업): 뺀 책 제자리 진열, 백업 파일 이름·시각, 삭제 문구의 남는 시간, 꾸미기 조작부(큰 글씨·순서 단추)
import 'package:chaekjang/domain/geometry.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/book/all_books.dart';
import 'package:chaekjang/features/home/decorate_panel.dart';
import 'package:chaekjang/scene_config/skin.dart';
import 'package:chaekjang/scene_config/spine_look.dart';
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
    expect(deleteNote(n), '독서 시간 2분은 책 없이 읽기 기록으로 통계에 남아요.\n되돌릴 수 없어요.');
  });

  group('꾸미기(영숙 F7, 2026-11-19 사용자 시안: 위 탭 · 아래 칸)', () {
    Widget host(Widget child, {double scale = 1}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(360, 640), textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: child)),
          ),
        );
    Widget panel({double scale = 1}) => host(
          DecoratePanel(
            title: '작별하지 않는다',
            pose: Pose.upright,
            lean: 0,
            canLean: (left: true, right: true),
            msg: null,
            spin: 0,
            spinMax: 30,
            spinRange: null,
            depth: (lo: -20.0, hi: 20.0, z: 0.0, back: 20.0),
            onPose: (_) {},
            onLean: (_) {},
            onSpin: (_) {},
            onDepth: (_) {},
          ),
          scale: scale,
        );

    testWidgets('맨 위 줄: 책 배치·선반·벽지 탭과 되돌리기·완료, 탭을 누르면 바뀐다', (tester) async {
      final tabs = <DecorateTab>[];
      var done = 0;
      await tester.pumpWidget(host(DecorateBar(tab: DecorateTab.books, onTab: tabs.add, canUndo: false, onUndo: () {}, onDone: () => done++)));
      expect(tester.takeException(), isNull);
      for (final t in ['책 배치', '선반', '벽지', '되돌리기', '완료']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      // 탭 글자와 완료 글자가 같은 줄 높이(밑줄 몫 때문에 탭 글자가 떠 보이지 않게)
      expect((tester.getCenter(find.text('책 배치')).dy - tester.getCenter(find.text('완료')).dy).abs(), lessThan(4));
      await tester.tap(find.text('벽지'));
      await tester.tap(find.text('완료'));
      expect(tabs, [DecorateTab.wall]);
      expect(done, 1);
    });

    testWidgets('책 고르기 전: 떠 있는 안내와 책 측면 고르기, 2배 글자에서도 넘치지 않는다', (tester) async {
      final picked = <SpineLook>[];
      await tester.pumpWidget(host(DecorateHint(msg: null, spine: SpineLook.color, onSpine: picked.add), scale: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('책을 누르거나 끌어보세요'), findsOneWidget);
      expect(find.text('책등'), findsNothing);
      await tester.tap(find.text('실물 측면'));
      expect(picked, [SpineLook.photo]);
    });

    testWidgets('선반 탭은 선반·벽(틀), 벽지 탭은 벽지만. 고르면 그 조합을 넘긴다', (tester) async {
      final picked = <SkinChoice>[];
      await tester.pumpWidget(host(SkinSheet(tab: DecorateTab.shelf, choice: defaultSkin, onPick: picked.add)));
      expect(tester.takeException(), isNull);
      expect(find.text('선반'), findsOneWidget);
      expect(find.text('벽'), findsOneWidget);
      expect(find.text('벽지'), findsNothing);
      await tester.tap(find.text(plankSkins['walnut']!.name));
      expect(picked.single, defaultSkin.copyWith(plank: 'walnut'));
      await tester.pumpWidget(host(SkinSheet(tab: DecorateTab.wall, choice: defaultSkin, onPick: picked.add)));
      expect(find.text('벽지'), findsOneWidget);
      expect(find.text('선반'), findsNothing);
    });

    testWidgets('고른 책: 순서 줄·자리 표시 없이 앞뒤·기대기, 2배 글자에서 라벨이 넘치지 않는다', (tester) async {
      await tester.pumpWidget(panel(scale: 2));
      expect(tester.takeException(), isNull);
      expect(find.text(keepAll('작별하지 않는다')), findsOneWidget);
      expect(find.text('책등'), findsOneWidget);
      expect(find.text('앞뒤'), findsOneWidget);
      expect(find.text('기대기'), findsOneWidget);
      expect(find.text('순서'), findsNothing);
      expect(find.textContaining('번째 선반'), findsNothing);
      expect(find.bySemanticsLabel('왼쪽으로 한 칸 옮기기'), findsNothing);
    });
  });
}
