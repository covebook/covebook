// 내 책 고르기(2026-11-20 QA): 여러 권을 골라 삭제 · 진열하면 결과 토스트가 뜬다(아무 알림 없이 끝났다)
import 'dart:io';

import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/geometry.dart' show realDimensions;
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/book/all_books_screen.dart';
import 'package:chaekjang/services/cover_colors.dart' show shelfRefresh;
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/library_store.dart' show saveLayout;
import 'package:chaekjang/store/placement_store.dart';
import 'package:chaekjang/ui/feedback.dart' show showToast;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory, databaseFactorySqflitePlugin;

const t1 = '2026-11-10T01:00:00.000Z';

Library lib() => Library(
      editions: {
        'e1': Edition(id: 'e1', title: '소년이 온다', authors: const ['한강'], source: 'photo', createdAt: t1, updatedAt: t1),
        'e2': Edition(id: 'e2', title: '모순', authors: const ['양귀자'], source: 'photo', createdAt: t1, updatedAt: '2026-11-11T01:00:00.000Z'),
      },
      books: {
        'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.read, createdAt: t1, updatedAt: t1),
        'b2': MyBook(id: 'b2', editionId: 'e2', status: ReadStatus.want, createdAt: '2026-11-11T01:00:00.000Z', updatedAt: '2026-11-11T01:00:00.000Z'),
      },
    );

Book shelfBook(String id, String title) => Book(id: id, title: title, dims: realDimensions(128, 188, 250, null));

/// 글자(낱말 이음표 U+2060을 뺀 글이 같은 것): WordText는 낱말 사이에 이음표를 넣는다
Finder plain(String s) => find.byWidgetPredicate((w) {
      final t = w is RichText ? w.text.toPlainText() : null;
      return t != null && t.replaceAll('⁠', '') == s;
    });

/// 기기 DB(sqflite) 대신: 연도 책장 찾기 같은 읽기는 빈 결과. 서재 · 배치 쓰기는 시험용 쓰기로 바꿔 끼운다
void fakeDb() {
  databaseFactory = databaseFactorySqflitePlugin;
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => Directory.systemTemp.path);
  m.setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (c) async {
    final sql = ((c.arguments as Map?)?['sql'] as String?) ?? '';
    return switch (c.method) {
      'openDatabase' => 1,
      'query' => sql.contains('user_version') ? {'columns': ['user_version'], 'rows': [[10]]} : {'columns': <String>[], 'rows': <List<Object?>>[]},
      _ => null,
    };
  });
}

Future<void> open(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(home: AllBooksScreen()));
  await t.pumpAndSettle();
}

Future<void> pick(WidgetTester t, String title) async {
  await t.tap(find.text('선택'));
  await t.pumpAndSettle();
  await t.tap(find.text(title).first);
  await t.pumpAndSettle();
}

void main() {
  final m = LibraryModel.instance, p = PlacementStore.instance;
  setUpAll(fakeDb);
  tearDown(() {
    m.writeChanges = applyLocalChanges;
    p.writeLayout = saveLayout;
  });

  void use() {
    m.useForTest(lib());
    m.writeChanges = (_) async {};
    p.writeLayout = (_, _) async {};
    p.books = {'b1': shelfBook('b1', '소년이 온다'), 'b2': shelfBook('b2', '모순')};
    p.layout = const ShelfLayout([Shelf('s1', 0)], [], ['b1', 'b2']);
  }

  testWidgets('골라 삭제하면 고르기가 끝나고 결과 토스트', (t) async {
    use();
    await open(t);
    await pick(t, '모순');
    await t.tap(find.text('1권 삭제'));
    await t.pumpAndSettle();
    // 확인 시트의 삭제 단추
    await t.tap(find.text('삭제').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(plain('1권을 삭제했어요.'), findsOneWidget);
    expect(m.lib.books.containsKey('b2'), isFalse);
    expect(find.text('1권 삭제'), findsNothing, reason: '고르기가 끝났다');
    final at = t.getRect(find.ancestor(of: plain('1권을 삭제했어요.'), matching: find.byType(DecoratedBox)).first);
    await t.pumpAndSettle(const Duration(seconds: 4));
    expect(plain('1권을 삭제했어요.'), findsNothing, reason: '토스트는 잠시 뒤 걷힌다');
    // 고르기 아래 단추 줄이 사라진 뒤 자리(탭 바 위): 단추 줄이 있던 높이에 뜨지 않는다
    showToast(t.element(find.byType(AllBooksScreen)), '기준');
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final base = t.getRect(find.ancestor(of: plain('기준'), matching: find.byType(DecoratedBox)).first);
    expect(at.bottom, closeTo(base.bottom, 0.5));
    await t.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('토스트는 책장을 다시 그리는 프레임 다음에 만든다(같은 프레임이면 무거운 다시 그리기 동안 3초가 흘렀다)', (t) async {
    use();
    await open(t);
    await pick(t, '모순');
    var refreshed = 0;
    void onRefresh() => refreshed++;
    shelfRefresh.addListener(onRefresh);
    addTearDown(() => shelfRefresh.removeListener(onRefresh));
    await t.tap(find.text('1권 진열'));
    await t.pump();
    expect(refreshed, 1, reason: '진열로 책장 다시 그리기를 알렸다');
    expect(find.text('1권 진열'), findsNothing, reason: '고르기가 끝난 화면을 그렸다');
    expect(plain('1권을 책장에 진열했어요.'), findsNothing, reason: '그 프레임에는 아직 토스트가 없다');
    await t.pump();
    expect(plain('1권을 책장에 진열했어요.'), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('골라 진열하면 결과 토스트', (t) async {
    use();
    await open(t);
    await pick(t, '모순');
    await t.tap(find.text('1권 진열'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(plain('1권을 책장에 진열했어요.'), findsOneWidget);
    expect(placementOf(p.layout!, 'b2'), isNotNull);
    await t.pumpAndSettle(const Duration(seconds: 4));
  });
}
