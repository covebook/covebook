// 책장에 꽂기(2026-11-24 사용자 시안): 홈 '+' 시트에서 책장에 없는 책을 끌어 원하는 자리에 꽂는다(placeFromDrawer).
// 시트는 책장에 없는 책이 앞, 책장에 있는 책은 끝 + 표지 밑 선반 판(2026-11-25). '목록 보기'는 책 추가 화면. 책을 끌 때 아래 빼기 자리(RemoveZone: 흰 빛 + 검은 X, 2026-11-24)에 놓으면 책장에서 뺀다
import 'dart:ui' as ui;

import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/home/decorate_panel.dart' show RemoveZone;
import 'package:chaekjang/features/home/place_sheet.dart';
import 'package:chaekjang/ui/book_visual.dart' show BookVisual, ShelfPlank, coverRect;
import 'package:chaekjang/ui/kit.dart' show LucideIcon, Space;
import 'package:chaekjang/ui/theme.dart' show AppColors;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Book _b(String id, double t) => Book(id: id, title: id, dims: BookDims(220, t, 140));
const t1 = '2026-11-16T05:00:00.000Z', t2 = '2026-11-20T05:00:00.000Z';

void main() {
  group('placeFromDrawer: 책장에 없는 책을 놓을 자리에', () {
    final books = {'a': _b('a', 30), 'b': _b('b', 30), 'n': _b('n', 30)};
    final l = ShelfLayout(
      [const Shelf('s1', 0), const Shelf('s2', 1)],
      [BookPlacement(bookId: 'a', shelfId: 's1', order: 0, pos: 0), BookPlacement(bookId: 'b', shelfId: 's1', order: 1, pos: 40)],
      const ['n'],
    );
    final detached = ShelfLayout(l.shelves, l.placements, const []);

    test('빈 선반 가운데에 놓으면 그 선반에 세워 꽂히고 서랍에서 빠진다', () {
      final t = findDropTarget(detached, books, 's2', 200, Pose.upright, 30);
      final r = placeFromDrawer(l, books, 'n', t);
      expect(r.ok, isTrue, reason: r.reason);
      final p = placementOf(r.layout!, 'n')!;
      expect(p.shelfId, 's2');
      expect(p.pose, Pose.upright);
      expect(r.layout!.drawer, isNot(contains('n')));
      expect(checkSpace(r.layout!, books), isNull);
    });

    test('책 사이에 놓으면 그 차례로(다른 책은 그대로 그 선반에)', () {
      final t = findDropTarget(detached, books, 's1', 35, Pose.upright, 30);
      final r = placeFromDrawer(l, books, 'n', t);
      expect(r.ok, isTrue, reason: r.reason);
      final order = [for (final it in shelfItems(r.layout!, 's1')) it.bookIds.first];
      expect(order, containsAllInOrder(['a', 'b']));
      expect(order, contains('n'));
      expect(placementOf(r.layout!, 'a')!.shelfId, 's1');
    });

    test('이미 책장에 있는 책이면 옮기기와 같다', () {
      final t = findDropTarget(detached, books, 's2', 200, Pose.upright, 30);
      final r = placeFromDrawer(l, books, 'a', t);
      expect(r.ok, isTrue);
      expect(placementOf(r.layout!, 'a')!.shelfId, 's2');
    });
  });

  group('시트', () {
    Library lib() => Library(
          editions: {
            for (final (id, title) in const [('e1', '가호'), ('e2', '싯다르타'), ('e3', '데미안')])
              id: Edition(id: id, title: title, authors: const ['작가'], source: 'photo', createdAt: t1, updatedAt: t1),
          },
          books: {
            'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1),
            'b2': MyBook(id: 'b2', editionId: 'e2', status: ReadStatus.want, createdAt: t2, updatedAt: t2),
            'b3': MyBook(id: 'b3', editionId: 'e3', status: ReadStatus.read, createdAt: t2, updatedAt: t2),
          },
        );

    test('책장에 없는 책이 앞(최근 넣은 책부터), 책장에 있는 책은 끝', () {
      final items = placeItems(lib(), const ['b1', 'b2', 'b3'], (id) => id == 'b3');
      expect([for (final i in items) i.id], ['b2', 'b1', 'b3']);
      expect([for (final i in items) i.onShelf], [false, false, true]);
    });

    test('시트를 연 동안 꽂은 책은 맨 오른쪽 끝(꽂은 차례)', () {
      final items = placeItems(lib(), const ['b1', 'b2', 'b3'], (id) => id != 'b1', placedNow: const ['b2']);
      expect([for (final i in items) i.id], ['b1', 'b3', 'b2']);
    });

    Future<({List<String> events})> pumpSheet(WidgetTester t, {double scale = 1}) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final events = <String>[];
      final l = lib();
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlaceSheet(
                lib: l,
                items: placeItems(l, const ['b1', 'b2', 'b3'], (id) => id == 'b3'),
                hidden: false,
                onDragStart: (id, g, ui.Image img, s) {
                  events.add('start:$id');
                  img.dispose();
                },
                onDragMove: (_) => events.add('move'),
                onDragEnd: () => events.add('end'),
                onDragCancel: () => events.add('cancel'),
                onList: () => events.add('list'),
                onClose: () => events.add('close'),
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      return (events: events);
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('제목 \'책장에 꽂기\' · 오른쪽 \'목록 보기\', 책장에 있는 책은 끝 + 책장 표시, 글자 ×$scale', (t) async {
        final r = await pumpSheet(t, scale: scale);
        expect(find.text('책장에 꽂기'), findsOneWidget);
        expect(find.text('새 책 찾기'), findsNothing);
        await t.tap(find.text('목록 보기'));
        expect(r.events, ['list']);
        expect(find.bySemanticsLabel('데미안, 책장에 있어요'), findsOneWidget);
        expect(find.bySemanticsLabel('싯다르타, 위로 끌어 책장에 꽂기'), findsOneWidget);
        // 책장 표시는 표지 밑 선반 판(2026-11-25 사용자 '원 안 책장 아이콘 말고 책 밑에 선반 디자인'): 책장에 있는 책에만 하나, 흰 원 배지는 없다
        final plank = find.byType(ShelfPlank);
        expect(plank, findsOneWidget);
        expect(find.byWidgetPredicate((w) => w is Container && (w.decoration as BoxDecoration?)?.shape == BoxShape.circle), findsNothing);
        final bv = t.getRect(find.descendant(of: find.bySemanticsLabel('데미안, 책장에 있어요'), matching: find.byType(BookVisual)));
        final cr = coverRect(null, null, bv.width, uniform: true);
        final cover = Rect.fromLTWH(bv.left + cr.edge, bv.top + cr.edge, cr.w, cr.h);
        final p = t.getRect(plank);
        expect(p.left, lessThan(cover.left), reason: '판이 표지보다 양옆으로 길다');
        expect(p.right, greaterThan(cover.right));
        expect(p.top, lessThan(cover.bottom), reason: '표지가 판 윗면에 서 있다');
        expect(p.bottom, greaterThan(cover.bottom));
        // 판이 없는 책과 제목 줄 높이가 같다
        expect(t.getRect(find.text('데미안').last).top, closeTo(t.getRect(find.text('가호').last).top, 0.01));
        // 책장에 있는 책(데미안)이 맨 오른쪽
        final x = {for (final s in ['가호', '싯다르타', '데미안']) s: t.getCenter(find.text(s).last).dx};
        expect(x['싯다르타']!, lessThan(x['가호']!));
        expect(x['가호']!, lessThan(x['데미안']!));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('표지를 위로 끌면 들고(손가락을 따라) 놓으면 끝. 책장에 있는 책은 들지 않는다', (t) async {
      final r = await pumpSheet(t);
      await t.drag(find.bySemanticsLabel('싯다르타, 위로 끌어 책장에 꽂기'), const Offset(0, -200));
      await t.pump();
      expect(r.events.first, 'start:b2');
      expect(r.events, contains('move'));
      expect(r.events.last, 'end');
      r.events.clear();
      await t.drag(find.bySemanticsLabel('데미안, 책장에 있어요'), const Offset(0, -200));
      await t.pump();
      expect(r.events, isEmpty);
    });

    testWidgets('손잡이 칸 16(막대는 위 끝에서 8), 바로 아래 제목 줄: 시트가 전(24)보다 8 낮다(2026-11-25 사용자)', (t) async {
      await pumpSheet(t);
      final handle = find.bySemanticsLabel('책장에 꽂기 닫기');
      final h = t.getRect(handle);
      expect(h.height, Space.l);
      final bar = find.descendant(of: handle, matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 38));
      expect(t.getRect(bar).top - h.top, closeTo(Space.s, 0.01));
      final row = find.ancestor(of: find.text('책장에 꽂기'), matching: find.byType(Row)).first;
      expect(t.getRect(row).top, closeTo(h.bottom, 0.01));
      // 제목 줄 ~ 표지 8(16이었다): 표지 밑 판 몫이 붙어도 시트가 전보다 낮다
      final cover = find.descendant(of: find.bySemanticsLabel('데미안, 책장에 있어요'), matching: find.byType(BookVisual));
      expect(t.getRect(cover).top - t.getRect(row).bottom, closeTo(Space.s, 0.01));
    });

    testWidgets('손잡이를 누르면 닫는다', (t) async {
      final r = await pumpSheet(t);
      await t.tap(find.bySemanticsLabel('책장에 꽂기 닫기'));
      expect(r.events, ['close']);
    });
  });

  testWidgets('빼기 자리: 흰 빛 + 검은 X(2026-11-24 사용자 \'흰색 그라데이션에 검은색 x\'), 책이 위에 오면 커진다', (t) async {
    Future<double> scaleOf(bool active) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 300, child: RemoveZone(active: active, centerFromBottom: 100)))));
      await t.pumpAndSettle();
      return t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    }

    expect(await scaleOf(false), 1);
    expect(t.widget<LucideIcon>(find.byType(LucideIcon)).color, AppColors.icon, reason: '회색 X(같은 날 사용자 \'검은 거 말고 회색\')');
    // 안쪽 빛은 흰색(가운데 흰색 → 투명)
    final glow = t.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).map((c) => (c.decoration! as BoxDecoration).gradient! as RadialGradient).toList();
    expect(glow.last.colors.first.toARGB32() | 0xFF000000, AppColors.white.toARGB32());
    expect(glow.last.colors.last.a, 0);
    expect(await scaleOf(true), greaterThan(1));
  });
}
