// 책 정보에서 읽기 상태를 완독으로 바꾸면 '평가' 칸으로 넘어간다(2026-11-23 사용자 E단계). 다른 상태로 바꾸면 그대로 '내 기록'
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/book/book_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';

Future<void> _openMine(WidgetTester t) async {
  final m = LibraryModel.instance;
  m.useForTest(Library(
    editions: {'ed1': Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 216, createdAt: t1, updatedAt: t1)},
    books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1)},
  ));
  m.writeChanges = (_) async {};
  addTearDown(() => m.writeChanges = applyLocalChanges);
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: BookScreen(id: 'bk1', onRead: (_) {})));
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(find.text('내 기록'));
  await t.pumpAndSettle();
}

Future<void> _pick(WidgetTester t, String status) async {
  await t.tap(find.bySemanticsLabel(RegExp('^읽기 상태')));
  await t.pumpAndSettle();
  await t.tap(find.text(status).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('완독으로 바꾸면 평가 칸(별점 · 한줄평)이 보인다', (t) async {
    await _openMine(t);
    expect(find.text('한줄평'), findsNothing);
    await _pick(t, '완독');
    expect(LibraryModel.instance.lib.books['bk1']!.status, ReadStatus.read);
    expect(find.text('한줄평'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('보류로 바꾸면 내 기록 칸 그대로', (t) async {
    await _openMine(t);
    await _pick(t, '보류');
    expect(LibraryModel.instance.lib.books['bk1']!.status, ReadStatus.paused);
    expect(find.text('한줄평'), findsNothing);
    expect(find.text('독서 기록'), findsOneWidget);
  });

  testWidgets('5단계: 현재 쪽을 마지막 쪽(216)으로 고쳐 완독이 되면 평가 칸으로', (t) async {
    await _openMine(t);
    await t.tap(find.bySemanticsLabel(RegExp('^현재 쪽')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '216');
    await t.pump(const Duration(milliseconds: 700));
    await t.pumpAndSettle();
    expect(LibraryModel.instance.lib.books['bk1']!.status, ReadStatus.read);
    expect(find.text('한줄평'), findsOneWidget, reason: '평가 칸');
  });

  testWidgets('5단계: 마지막 쪽 전이면 내 기록 칸 그대로', (t) async {
    await _openMine(t);
    await t.tap(find.bySemanticsLabel(RegExp('^현재 쪽')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, '100');
    await t.pump(const Duration(milliseconds: 700));
    await t.pumpAndSettle();
    expect(LibraryModel.instance.lib.books['bk1']!.status, ReadStatus.reading);
    expect(find.text('한줄평'), findsNothing);
  });
}

