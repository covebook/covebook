// 4단계(2026-11-24 사용자): 읽기를 끝내면 시작한 자리로. 책 화면 · 책 시트 · 책 공유에서 읽기를 시작하면 화면을 닫거나 탭을 바꾸지 않고 그 위에
// 장면(또는 독서 끝)을 연다(읽기 탭 목록에서는 그 책이 맨 앞). 독서 끝에서 저장 · 버리기를 하면 독서 끝만 닫혀 시작한 화면으로 돌아오고,
// '저장했어요' 창 · '독서 기록을 버렸어요' 토스트는 그 화면 위에 뜬다. 읽기 탭에서 시작하면 그대로 읽기 탭
import 'package:chaekjang/app/app_nav.dart';
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/reading.dart';
import 'package:chaekjang/features/reading/finish_screen.dart';
import 'package:chaekjang/features/reading/start_book.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/reading_store.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb, plain;

const t1 = '2026-11-16T01:00:00.000Z';


Future<void> _setUp(WidgetTester t) async {
  final m = LibraryModel.instance;
  m.useForTest(Library(
    editions: {'ed1': Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 216, createdAt: t1, updatedAt: t1)},
    books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1)},
  ));
  m.writeChanges = (_) async {};
  addTearDown(() => m.writeChanges = applyLocalChanges);
  final r = ReadingStore.instance;
  // 기기 저장소 읽기는 시험 시계로 돈다: 끝날 때까지 밀어 준 뒤 초안을 넣는다(읽기가 늦게 끝나면 초안을 덮어쓴다)
  // 앞 시험에서 이미 읽었으면 그대로(앞 시험 시계에 묶인 Future라 기다릴 수 없다)
  var done = r.loaded;
  if (!done) r.load().then((_) => done = true, onError: (Object _) => done = true);
  for (var i = 0; i < 100 && !done; i++) {
    await t.pump(const Duration(milliseconds: 20));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  expect(done, isTrue);
  final now = DateTime.now();
  r.pending = FinishDraft(
    id: 'ss_return',
    myBookId: 'bk1',
    startedAt: now.subtract(const Duration(minutes: 10)).toUtc().toIso8601String(),
    endedAt: now.toUtc().toIso8601String(),
    durationMs: 600000,
  );
  addTearDown(() => r.pending = null);
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

/// 탭 화면 위에 밀어 넣은 '책 화면'(읽기 시작 단추)
Future<void> _pumpBookPage(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (c) => TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/book'),
            builder: (c2) => Scaffold(body: Column(children: [const Text('책 화면'), TextButton(onPressed: () => startReadingBook(c2, 'bk1'), child: const Text('이어서 읽기'))])),
          )),
          child: const Text('탭 화면'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('탭 화면'));
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

void main() {
  setUpAll(fakeDb);

  // 읽기 저장소는 앱에 하나라 시험 시계가 바뀌면(시험을 나누면) 처음 읽기를 기다릴 수 없다: 한 시험 안에서 차례로 본다
  testWidgets('책 화면에서 시작하면 화면 · 탭 그대로 그 위에 독서 끝. 버리면 책 화면 + 토스트, 저장하면 책 화면 + 저장했어요 창. 읽기 탭에서 연 독서 끝은 읽기 탭으로', (t) async {
    await _setUp(t);
    await _pumpBookPage(t);
    final tab = AppNav.instance.tab;
    const settle = Duration(seconds: 5);

    // 1) 버리기: 책 화면으로 돌아와 토스트(한 번만 닫힌다: 탭 화면까지 가지 않는다)
    await t.tap(find.text('이어서 읽기'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    expect(find.byType(FinishScreen), findsOneWidget, reason: '저장 전 기록이 있으면 독서 끝부터');
    expect(AppNav.instance.tab, tab, reason: '탭을 바꾸지 않는다');
    expect(AppNav.instance.readBook, 'bk1', reason: '읽기 탭 목록에서는 그 책이 맨 앞');
    AppNav.instance.readBook = null;
    await t.ensureVisible(find.text('이 기록 버리기'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    await t.tap(find.text('이 기록 버리기'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    await t.tap(find.text('버리기').last);
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    expect(find.byType(FinishScreen), findsNothing);
    expect(find.text('책 화면'), findsOneWidget, reason: '시작한 화면으로 돌아온다');
    // '독서 기록을 버렸어요' 토스트는 기기 저장소를 비운 뒤라(시험 시계에서는 끝나지 않는다) 에뮬레이터에서 본다. 초안은 비워졌다
    for (var i = 0; i < 20 && ReadingStore.instance.pending != null; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(ReadingStore.instance.pending, isNull);
    expect(AppNav.instance.tab, tab);
    await t.pump(const Duration(seconds: 4));

    // 2) 저장: 책 화면으로 돌아와 저장했어요 창
    final r = ReadingStore.instance;
    final now = DateTime.now();
    r.pending = FinishDraft(id: 'ss_return', myBookId: 'bk1', startedAt: now.subtract(const Duration(minutes: 10)).toUtc().toIso8601String(), endedAt: now.toUtc().toIso8601String(), durationMs: 600000);
    await t.tap(find.text('이어서 읽기'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    expect(find.byType(FinishScreen), findsOneWidget);
    await t.tap(find.text('개인 기록 저장'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    expect(find.byType(FinishScreen), findsNothing);
    expect(find.text('책 화면'), findsOneWidget);
    expect(find.textContaining('기록했어요'), findsOneWidget, reason: '저장했어요 창은 돌아온 화면 위에');
    expect(LibraryModel.instance.lib.sessions.containsKey('ss_return'), isTrue, reason: '내 기록 칸에 보일 기록이 저장됐다');
    expect(AppNav.instance.tab, tab);
    await t.tap(find.text('확인'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);

    // 3) 읽기 탭에서 연 독서 끝(맨 아래 화면 위)은 저장하면 그 맨 아래 화면으로
    r.pending = FinishDraft(id: 'ss_tab', myBookId: 'bk1', startedAt: now.subtract(const Duration(minutes: 5)).toUtc().toIso8601String(), endedAt: now.toUtc().toIso8601String(), durationMs: 300000);
    Navigator.of(t.element(find.text('책 화면'))).pop();
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    unawaited(openFinish(t.element(find.text('탭 화면')), root: true));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    await t.tap(find.text('개인 기록 저장'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    expect(find.text('탭 화면'), findsOneWidget);
    expect(find.textContaining('기록했어요'), findsOneWidget);
    await t.tap(find.text('확인'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);

    // 4) 뒤로 나가면 묻지 않고 적은 데까지 저장(2026-11-26 사용자 '화면 나가면 그냥 거기까지 기록하고'): 막힌 쪽(전체 216쪽보다 큼)은 빼고 시작 쪽 · 메모는 남긴다
    r.pending = FinishDraft(
      id: 'ss_back',
      myBookId: 'bk1',
      startedAt: now.subtract(const Duration(minutes: 3)).toUtc().toIso8601String(),
      endedAt: now.toUtc().toIso8601String(),
      durationMs: 180000,
      notes: const FinishNotes(startPage: '10', pages: '999', memo: ' 좋았다 '),
    );
    unawaited(openFinish(t.element(find.text('탭 화면')), root: true));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, settle);
    expect(find.byType(FinishScreen), findsOneWidget);
    await t.binding.handlePopRoute();
    // 토스트는 지나간 화면 시간으로 걷힌다(3초): 다 가라앉히지 않고 화면이 닫힐 만큼만 민다
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('나갈까요'), findsNothing, reason: '묻지 않는다');
    expect(find.byType(FinishScreen), findsNothing);
    expect(find.text('탭 화면'), findsOneWidget);
    final s = LibraryModel.instance.lib.sessions['ss_back'];
    expect(s, isNotNull, reason: '뒤로 나가도 기록된다');
    expect(s!.startPage, 10);
    expect(s.pagesRead, isNull, reason: '전체 쪽수보다 큰 쪽은 뺀다');
    expect(s.memo, '좋았다');
    expect(r.pending, isNull);
    expect(plain('‘소년이 온다’ 3분을 기록했어요.'), findsOneWidget, reason: '돌아온 화면에서 토스트');
    await t.pump(const Duration(seconds: 4));
  });
}
