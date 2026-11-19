// 공통 UI 규칙(docs/design/DESIGN.md 10~14장)을 실제 화면에서: 찾을 수 없음과 돌아가기 · 숨긴 책 안내 ·
// 고치는 화면 나가기 확인 · 독서 기록 수정 쪽 칸 오류 · 책 고르기 시트 하나
import 'dart:io';

import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/book/book_screen.dart';
import 'package:chaekjang/features/book/edit_book_screen.dart';
import 'package:chaekjang/features/bookmark/book_picker.dart';
import 'package:chaekjang/features/stats/session_edit_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/placement_store.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-10T01:00:00.000Z';

Edition _ed(String id, String title, {int? pages}) => Edition(id: id, title: title, authors: const ['작가'], source: 'photo', pageCount: pages, createdAt: t1, updatedAt: t1);
MyBook _bk(String id, String ed, {String? hiddenAt}) => MyBook(id: id, editionId: ed, status: ReadStatus.reading, hiddenAt: hiddenAt, createdAt: t1, updatedAt: t1);

Library _lib({int extra = 0}) => Library(
      editions: {
        'e1': _ed('e1', '작별하지 않는다', pages: 332),
        'e2': _ed('e2', '데미안', pages: 248),
        for (var i = 0; i < extra; i++) 'x$i': _ed('x$i', '책 $i'),
      },
      books: {
        'b1': _bk('b1', 'e1'),
        'b2': _bk('b2', 'e2', hiddenAt: t1),
        for (var i = 0; i < extra; i++) 'y$i': _bk('y$i', 'x$i'),
      },
      sessions: {
        's1': Session(id: 's1', myBookId: 'b1', startedAt: '2026-11-17T11:00:00.000Z', endedAt: '2026-11-17T11:38:00.000Z', durationMs: 38 * 60000, startPage: 10, pagesRead: 30, createdAt: t1, updatedAt: t1),
      },
    );

void _use(Library l) {
  final m = LibraryModel.instance;
  m.lib = l;
  m.loaded = true;
  PlacementStore.instance.layout = const ShelfLayout([], []);
  PlacementStore.instance.books = {};
}

/// 첫 화면 위에 [screen]을 밀어 넣는다(돌아가기 · 나가기 확인을 보려고)
Future<void> _push(WidgetTester t, Widget screen) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen)), child: const Text('열기'))))),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => Directory.systemTemp.path);
    // 화면이 켤 때 부르는 서재 읽기(기기 DB)는 시험에 없다: 한 번 실패를 받아 두면 화면이 다시 불러도 같은 결과를 돌려받아 조용하다
    await LibraryModel.instance.load().catchError((_) {});
  });

  group('찾을 수 없음과 돌아가기(9 · 10장)', () {
    testWidgets('없는 책: 찾을 수 없음 + 돌아가기를 누르면 이전 화면', (t) async {
      _use(_lib());
      await _push(t, BookScreen(id: 'nope', onRead: (_) {}));
      expect(find.text('책을 찾을 수 없어요'), findsOneWidget);
      await t.tap(find.text('돌아가기'));
      await t.pumpAndSettle();
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('없는 독서 기록도 같은 틀', (t) async {
      _use(_lib());
      await _push(t, const SessionEditScreen(id: 'nope'));
      expect(find.text('기록을 찾을 수 없어요'), findsOneWidget);
      await t.tap(find.text('돌아가기'));
      await t.pumpAndSettle();
      expect(find.text('열기'), findsOneWidget);
    });
  });

  testWidgets('숨긴 책을 책 정보로 열면 안내 한 줄', (t) async {
    _use(_lib());
    await _push(t, BookScreen(id: 'b2', onRead: (_) {}));
    expect(find.text('숨긴 책이라 내 책 목록에는 보이지 않아요.'), findsOneWidget);
    // 메뉴('다시 보이기')는 기기 DB(연도 책장)를 읽어 화면 시험 밖: 에뮬에서 확인
  });

  group('고치는 화면 나가기 확인(12장)', () {
    testWidgets('책 정보 수정: 고치고 뒤로 가면 묻고, 계속 수정이면 머문다', (t) async {
      _use(_lib());
      await _push(t, const EditBookScreen(id: 'b1'));
      await t.enterText(find.widgetWithText(TextField, '작별하지 않는다'), '작별하지 않는다 (개정판)');
      await t.pump();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('고친 내용을 버릴까요?'), findsOneWidget);
      await t.tap(find.text('계속 수정'));
      await t.pumpAndSettle();
      expect(find.text('열기'), findsNothing);
    });

    testWidgets('독서 기록 수정: 고치지 않았으면 묻지 않고 돌아간다', (t) async {
      _use(_lib());
      await _push(t, const SessionEditScreen(id: 's1'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('고친 내용을 버릴까요?'), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('독서 기록 수정: 쪽 칸 오류면 저장 단추는 켜져 있고, 눌러도 저장하지 않고 화면에 남는다', (t) async {
      _use(_lib());
      await _push(t, const SessionEditScreen(id: 's1'));
      await t.enterText(find.widgetWithText(TextField, '30'), '999');
      await t.pumpAndSettle();
      final save = find.widgetWithText(Btn, '기록 저장');
      expect(t.widget<Btn>(save).disabled, isFalse);
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.text('기록 저장'), findsOneWidget);
      expect(LibraryModel.instance.lib.sessions['s1']!.pagesRead, 30);
    });
  });

  group('책 고르기 시트 하나(13장)', () {
    Future<({bool picked, String? id})?> open(WidgetTester t, Library l, {String? current, bool all = false}) async {
      _use(l);
      ({bool picked, String? id})? got;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () async => got = await pickBook(c, l, current: (id: current), all: all), child: const Text('고르기')))),
        ),
      ));
      await t.tap(find.text('고르기'));
      await t.pumpAndSettle();
      return got;
    }

    testWidgets('제목 책 고르기, 지금 고른 책은 고르는 원이 켜져 있고 모든 책은 맨 위 줄', (t) async {
      await open(t, _lib(), current: 'b1', all: true);
      expect(find.text('책 고르기'), findsOneWidget);
      expect(find.text('모든 책'), findsOneWidget);
      final on = t.widgetList<RadioMark>(find.byType(RadioMark)).where((r) => r.on).length;
      expect(on, 1);
      expect(find.byType(SearchField), findsNothing, reason: '책이 적으면 검색칸 없음');
    });

    testWidgets('책이 6권부터 검색칸, 0건이면 안내', (t) async {
      await open(t, _lib(extra: 6));
      expect(find.byType(SearchField), findsOneWidget);
      await t.enterText(find.descendant(of: find.byType(SearchField), matching: find.byType(EditableText)), '없는책제목');
      await t.pumpAndSettle();
      expect(find.textContaining('없는책제목'), findsWidgets);
      expect(find.textContaining('맞는 책이 없어요'), findsOneWidget);
    });
  });
}
