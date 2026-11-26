// 타이머를 켜면 책 정보가 바로 바뀐다(2026-11-19 사용자 '타이머 읽었는데 바로 기록이 안 돼'):
// 재는 중인 책은 '읽는 중'으로 보이고 내 기록 맨 위에 '지금 읽는 중' 줄, 아래 단추는 '이어서 읽기'.
// 회차 · 상태는 기록을 저장할 때 생긴다(시작만 하고 버리면 남지 않게, 타이머 점검 B3·B4)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/reading.dart';
import 'package:chaekjang/features/book/book_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/reading_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 216, createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.want, createdAt: t1, updatedAt: t1)},
    );

/// 글자(낱말 이음표를 뺀 글)에 그 말이 들어 있는 것
Finder plainHas(String s) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().replaceAll('⁠', '').contains(s));

void main() {
  test('기록을 저장하면 회차가 생기고 읽기 전이면 읽는 중', () {
    final r = sessionRound(lib(), 'bk1', '2026-11-19', t1);
    expect(r.lib.books['bk1']!.status, ReadStatus.reading);
    expect(r.lib.rounds.length, 1);
    final s = addSessionTo(r.lib, const SessionInput(myBookId: 'bk1', startedAt: '2026-11-19T01:00:00.000Z', endedAt: '2026-11-19T01:10:00.000Z', durationMs: 600000), t1);
    expect(s.lib.rounds.length, 1);
    expect(s.lib.sessions.values.single.roundId, r.roundId);
  });

  testWidgets('재는 중인 책: 내 기록 맨 위 지금 읽는 중 줄, 단추는 이어서 읽기', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    final m = LibraryModel.instance;
    m.lib = lib();
    m.loaded = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    ReadingStore.instance.active = Active(id: 'ss1', myBookId: 'bk1', startedAt: DateTime.now().toUtc().toIso8601String(), accumulatedMs: 0, runningSince: now, lastBeat: now);
    addTearDown(() => ReadingStore.instance.active = null);
    await t.pumpWidget(MaterialApp(home: BookScreen(id: 'bk1', onRead: (_) {})));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('이어서 읽기'), findsWidgets);
    await t.tap(find.text('내 기록'));
    await t.pump(const Duration(milliseconds: 300));
    expect(plainHas('지금 읽는 중 | '), findsOneWidget);
    expect(plainHas('기록을 저장하면 1회차가 생겨요'), findsOneWidget);
    expect(find.text('읽는 중'), findsWidgets);
    expect(find.text('타이머로 읽으면 여기에 쌓여요'), findsNothing);
    ReadingStore.instance.active = null;
    await t.pumpWidget(const SizedBox());
  });

  test('읽기 전으로 되돌린 책(회차가 남음)도 기록을 저장하면 읽는 중(점검 B5)', () {
    final r = sessionRound(lib(), 'bk1', '2026-11-19', t1);
    final back = r.lib.copy(books: {...r.lib.books, 'bk1': r.lib.books['bk1']!.copyWith(status: ReadStatus.want, updatedAt: t1)});
    final s = addSessionTo(back, const SessionInput(myBookId: 'bk1', startedAt: '2026-11-19T01:00:00.000Z', endedAt: '2026-11-19T01:10:00.000Z', durationMs: 600000), t1);
    expect(s.lib.books['bk1']!.status, ReadStatus.reading);
    expect(s.lib.rounds.length, 1);
  });

  group('읽기 상태 · 현재 쪽 규칙(2026-11-24 1단계): 타이머 저장 · 현재 쪽 고치기', () {
    // 기기 현지 날짜 기준 그날 저녁 9시(UTC로 바꿔 적는다)
    String at(int d, [int h = 21]) => DateTime(2026, 11, d, h).toUtc().toIso8601String();
    SessionInput input(num? pages, {int day = 19}) => SessionInput(myBookId: 'bk1', startedAt: at(day), endedAt: at(day, 22), durationMs: 3600000, pagesRead: pages);

    test('규칙 1: 도달한 쪽이 전체 쪽수(216) 이상이면 완독, 완독일은 그 기록을 시작한 날', () {
      final r = addSessionTo(lib(), input(216, day: 19), at(23));
      final b = r.lib.books['bk1']!;
      expect(b.status, ReadStatus.read);
      expect(b.currentPage, 216);
      expect(r.lib.rounds.values.single.finishedAt, '2026-11-19');
    });

    test('규칙 1: 마지막 쪽 전이면 읽는 중 그대로, 쪽수를 모르는 판본은 완독으로 바꾸지 않는다', () {
      expect(addSessionTo(lib(), input(215), at(23)).lib.books['bk1']!.status, ReadStatus.reading);
      final noCount = lib()..editions['ed1'] = Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', createdAt: t1, updatedAt: t1);
      expect(addSessionTo(noCount, input(999), at(23)).lib.books['bk1']!.status, ReadStatus.reading);
      final zero = lib()..editions['ed1'] = Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 0, createdAt: t1, updatedAt: t1);
      expect(addSessionTo(zero, input(999), at(23)).lib.books['bk1']!.status, ReadStatus.reading);
    });

    test('규칙 1: 이미 완독이면 그대로(완독일도 그대로)', () {
      final done = addSessionTo(lib(), input(216, day: 18), at(23)).lib;
      final again = addSessionTo(done, input(216, day: 20), at(23)).lib;
      expect(again.books['bk1']!.status, ReadStatus.read);
      expect([for (final r in again.rounds.values) r.finishedAt], ['2026-11-18']);
    });

    test('규칙 2: 현재 쪽을 마지막 쪽 이상으로 고치면 완독(완독일 오늘), 낮춰도 완독은 그대로(규칙 4)', () {
      final reading = addSessionTo(lib(), input(100), at(23)).lib;
      final now = DateTime.now().toUtc().toIso8601String();
      final done = setCurrentPageIn(reading, 'bk1', 216, now);
      expect(done.books['bk1']!.status, ReadStatus.read);
      expect(done.rounds.values.single.finishedAt, today());
      final lower = setCurrentPageIn(done, 'bk1', 50, now);
      expect(lower.books['bk1']!.status, ReadStatus.read);
      expect(lower.books['bk1']!.currentPage, 50);
      expect(setCurrentPageIn(reading, 'bk1', 200, now).books['bk1']!.status, ReadStatus.reading);
    });
  });
}

