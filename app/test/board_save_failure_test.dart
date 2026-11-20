// 갈피 보드(2026-11-20 QA): 카드를 옮겼는데 저장하지 못하면 앞 자리로 돌아가고 다른 저장 실패처럼 확인창을 띄운다.
// 화면에서는 옮겨진 채 아무 알림이 없다가 앱을 다시 켜면 앞 자리로 돌아와 있었다
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/bookmark/board_card.dart';
import 'package:chaekjang/features/bookmark/board_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-10T01:00:00.000Z';

Library lib() => Library(
      editions: {'e1': Edition(id: 'e1', title: '모순', authors: const ['양귀자'], source: 'photo', createdAt: t1, updatedAt: t1)},
      books: {'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1)},
      bookmarks: {'m1': Bookmark(id: 'm1', myBookId: 'b1', text: '삶은 누구에게나 한 번뿐이다', createdAt: t1, updatedAt: t1)},
    );

Future<void> open(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(home: BookmarkBoardScreen(first: 'b1')));
  // 처음 그린 뒤 마지막 보던 곳(기기 저장, 시험에는 없다)을 읽고 보인다
  await t.pumpAndSettle();
}

/// 카드를 꾹 눌러 들고 by만큼 옮겨 놓는다
Future<void> drag(WidgetTester t, Offset by) async {
  final g = await t.startGesture(t.getCenter(find.byType(BoardCard)));
  await t.pump(const Duration(milliseconds: 400));
  for (var i = 1; i <= 5; i++) {
    await g.moveBy(by / 5);
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  final m = LibraryModel.instance;
  tearDown(() => m.writeChanges = applyLocalChanges);

  testWidgets('저장하지 못하면 카드가 앞 자리로 돌아가고 확인창이 뜬다', (t) async {
    m.writeChanges = (_) async => throw StateError('기기에 쓰지 못했어요');
    // 위젯 시험의 시계 안에서 서재를 넣는다(저장 차례가 이 시험의 시계로 돈다)
    m.useForTest(lib());
    await open(t);
    final before = t.getCenter(find.byType(BoardCard));
    await drag(t, const Offset(80, 120));
    expect(find.text('갈피 자리를 저장하지 못했어요'), findsOneWidget);
    expect(m.lib.bookmarks['m1']!.boardX, isNull);
    expect(t.getCenter(find.byType(BoardCard)), before);
    await t.tap(find.text('확인'));
    await t.pumpAndSettle();
    expect(find.text('갈피 자리를 저장하지 못했어요'), findsNothing);
  });

  testWidgets('저장되면 옮긴 자리에 남고 확인창은 없다', (t) async {
    m.writeChanges = (_) async {};
    // 위젯 시험의 시계 안에서 서재를 넣는다(저장 차례가 이 시험의 시계로 돈다)
    m.useForTest(lib());
    await open(t);
    final before = t.getCenter(find.byType(BoardCard));
    await drag(t, const Offset(80, 120));
    expect(find.text('갈피 자리를 저장하지 못했어요'), findsNothing);
    expect(m.lib.bookmarks['m1']!.boardX, isNotNull);
    expect(t.getCenter(find.byType(BoardCard)), isNot(before));
  });
}
