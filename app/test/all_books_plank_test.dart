// 내 책 격자의 책장 표시(2026-11-25 사용자 '책장에 있다는 표시 원 안에 책장 아이콘 넣지 말고 사진처럼 넣은 책 밑에 선반 디자인'):
// 책장에 꽂힌 책만 표지 밑에 선반 판, 흰 원 배지는 없다. 판이 있든 없든 제목 줄은 나란히
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/library_store.dart' show saveLayout;
import 'package:chaekjang/store/placement_store.dart';
import 'package:chaekjang/ui/book_visual.dart' show BookVisual, ShelfPlank, coverRect;
import 'package:chaekjang/ui/theme.dart' show AppType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb, lib, open, shelfBook;

/// 격자 칸 제목(표지 그림 안 제목 글자와 구별)
Finder gridTitle(String s) => find.byWidgetPredicate((w) => w is Text && w.data == s && w.style?.fontSize == AppType.bookGridTitle.fontSize);

void main() {
  final m = LibraryModel.instance, p = PlacementStore.instance;
  setUpAll(fakeDb);
  tearDown(() {
    m.writeChanges = applyLocalChanges;
    p.writeLayout = saveLayout;
  });

  testWidgets('책장에 있는 책(소년이 온다)만 표지 밑 선반 판, 판은 표지보다 양옆으로 길고 표지가 윗면에 선다, 제목 줄은 나란히', (t) async {
    m.useForTest(lib());
    m.writeChanges = (_) async {};
    p.writeLayout = (_, _) async {};
    p.books = {'b1': shelfBook('b1', '소년이 온다'), 'b2': shelfBook('b2', '모순')};
    p.layout = ShelfLayout([Shelf('s1', 0)], [BookPlacement(bookId: 'b1', shelfId: 's1', order: 0, pose: Pose.upright, tilt: 0)], ['b2']);
    await open(t);
    if (find.bySemanticsLabel('표지 격자로 보기').evaluate().isNotEmpty) {
      await t.tap(find.bySemanticsLabel('표지 격자로 보기'));
      await t.pumpAndSettle();
    }
    final plank = find.byType(ShelfPlank);
    expect(plank, findsOneWidget);
    final cell = find.ancestor(of: plank, matching: find.byType(Stack)).first;
    expect(find.descendant(of: cell, matching: find.byWidgetPredicate((w) => w is Container && (w.decoration as BoxDecoration?)?.shape == BoxShape.circle)), findsNothing,
        reason: '흰 원 배지 없음');
    final bv = t.getRect(cell);
    final visual = t.getRect(find.descendant(of: cell, matching: find.byType(BookVisual)));
    final cr = coverRect(null, null, visual.width, uniform: true);
    final cover = Rect.fromLTWH(visual.left + cr.edge, visual.top + cr.edge, cr.w, cr.h);
    final r = t.getRect(plank);
    expect(r.left, lessThan(cover.left));
    expect(r.right, greaterThan(cover.right));
    expect(r.top, lessThan(cover.bottom));
    expect(r.bottom, greaterThan(cover.bottom));
    expect(bv.width, greaterThan(0));
    expect(t.getRect(gridTitle('소년이 온다')).top, closeTo(t.getRect(gridTitle('모순')).top, 0.01), reason: '판이 없는 책과 제목 줄이 나란히');
    expect(t.getRect(gridTitle('소년이 온다')).top, greaterThan(r.bottom), reason: '판(그늘까지) 아래에 제목');
  });
}
