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
import 'package:flutter/rendering.dart';
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
    Widget panel({double scale = 1, ValueChanged<SpineLook>? onSpine, VoidCallback? onBinding}) => host(
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
            spine: SpineLook.color,
            onSpine: onSpine ?? (_) {},
            onBinding: onBinding ?? () {},
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

    testWidgets('책 고르기 전: 떠 있는 안내 하나(책 옆면은 책을 고른 뒤 디자인에), 2배 글자에서도 넘치지 않는다', (tester) async {
      await tester.pumpWidget(host(const DecorateHint(msg: null), scale: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('책을 하나 골라 주세요'), findsOneWidget);
      expect(find.text('책등'), findsNothing);
      expect(find.text('측면'), findsNothing);
    });

    testWidgets('고른 책: 위치, 각도 | 디자인 전환 칸, 디자인에서 책 옆면(단색 | 측면 | 겹무늬) · 이 책 꾸미기(2026-11-23 이름)', (tester) async {
      final picked = <SpineLook>[];
      var binding = 0;
      await tester.pumpWidget(panel(onSpine: picked.add, onBinding: () => binding++));
      expect(find.text('위치, 각도'), findsOneWidget);
      expect(find.text('측면'), findsNothing);
      await tester.tap(find.text('디자인'));
      await tester.pump();
      expect(find.text('앞뒤'), findsNothing);
      expect(find.text('책 옆면'), findsOneWidget);
      expect(find.textContaining('모든 책'), findsNothing, reason: '고른 책에만 걸려 적용 범위 글이 없다');
      for (final o in ['단색', '측면', '겹무늬']) {
        expect(find.text(o), findsOneWidget, reason: o);
      }
      await tester.tap(find.text('측면'));
      expect(picked, [SpineLook.photo]);
      expect(find.text('그림, 색상, 재질'), findsOneWidget);
      await tester.tap(find.text('이 책 꾸미기'));
      expect(binding, 1);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.15, 1.3, 2.0]) {
      testWidgets('글씨 $scale배 360 폭: 전환 칸 \'위치, 각도\'가 칸 안에 다 보이고, 이 책 꾸미기 줄은 이름 · 설명(오른쪽)이 한 줄', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(panel(scale: scale));
        // 고른 칸(굵게)일 때 글자 폭이 칸 안쪽(양옆 4)보다 좁다
        final cell = find.ancestor(of: find.text('위치, 각도'), matching: find.byType(Container)).first;
        final text = tester.renderObject<RenderParagraph>(find.text('위치, 각도'));
        expect(text.didExceedMaxLines, isFalse);
        // 1.3배까지는 한 줄로 다 들어간다(2배는 두 줄로 접힌다)
        if (scale <= 1.3) expect(text.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(tester.getSize(cell).width - 8));
        // 제목이 오른쪽 칸 때문에 세 글자도 안 남지 않는다(1배: 같은 줄, 조금 키운 글씨 · 큰 글씨: 다른 줄)
        final title = find.text(keepAll('작별하지 않는다'));
        expect(tester.getSize(title).width, greaterThan(22 * scale * 3 - 1));
        if (scale == 1.0) expect((tester.getCenter(title).dy - tester.getCenter(find.text('위치, 각도')).dy).abs(), lessThan(4), reason: '기본 글씨는 같은 줄');
        await tester.tap(find.text('디자인'));
        await tester.pump();
        // 이름 · 설명 둘 다 한 줄, 설명은 같은 줄 오른쪽(2026-11-24 사용자 '왼쪽 사진처럼 우측에 있게 하고 한 줄로': 이름 아래였다).
        // 이름은 다 보이고, 칸이 모자라면 설명 끝이 '…'
        // (시험 글꼴은 글자마다 1em이라 실제 글꼴보다 넓다: 실제 360dp 1.3배 화면은 에뮬 사진으로 본다)
        final name = tester.renderObject<RenderParagraph>(find.text('이 책 꾸미기'));
        if (scale <= 1.3) expect(name.didExceedMaxLines, isFalse, reason: '이름은 잘리지 않는다');
        expect(tester.getSize(find.text('이 책 꾸미기')).height, lessThan(25.5 * scale * 1.5));
        expect(tester.getSize(find.text('그림, 색상, 재질')).height, lessThan(22.5 * scale * 1.5));
        expect((tester.getCenter(find.text('그림, 색상, 재질')).dy - tester.getCenter(find.text('이 책 꾸미기')).dy).abs(), lessThan(2), reason: '같은 줄');
        expect(tester.getRect(find.text('그림, 색상, 재질')).left, greaterThan(tester.getRect(find.text('이 책 꾸미기')).right));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('선반 탭은 선반·벽(틀), 벽지 탭은 벽지만. 고르면 그 조합을 넘긴다', (tester) async {
      final picked = <SkinChoice>[];
      await tester.pumpWidget(host(SkinSheet(tab: DecorateTab.shelf, choice: defaultSkin, onPick: picked.add)));
      expect(tester.takeException(), isNull);
      expect(find.text('선반'), findsOneWidget);
      expect(find.text('벽'), findsOneWidget);
      expect(find.text('벽지'), findsNothing);
      // 선반 · 벽 둘 다 '호두나무'(묶음 이름이 '벽'이라 '호두나무 벽'으로 쓰지 않는다): 위가 선반
      await tester.tap(find.text(plankSkins['walnut']!.name).first);
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
