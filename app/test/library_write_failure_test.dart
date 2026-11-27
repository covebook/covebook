// 저장 실패(2026-11-20 QA: 쓰기를 일부러 실패시키는 점검): 기기에 쓰지 못한 고치기는 화면 서재에서도 되돌린다.
// 지우기가 실패해 '삭제하지 못했어요'가 떠도 책 · 독서 기록 · 갈피 · 감상이 화면에서 사라져 있다가 앱을 다시 켜면 돌아왔다
import 'dart:async';

import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/library_store.dart' show saveLayout;
import 'package:chaekjang/store/placement_store.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-10T01:00:00.000Z';

Library lib() => Library(
      editions: {'e1': Edition(id: 'e1', title: '소년이 온다', authors: const ['한강'], source: 'photo', createdAt: t1, updatedAt: t1)},
      books: {'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.reading, bindingId: 'd1', createdAt: t1, updatedAt: t1)},
      bindings: {'d1': Binding(id: 'd1', myBookId: 'b1', spineColor: '#4E4C33', motif: 'none', source: 'auto', status: 'ready', seed: 0, createdAt: t1, updatedAt: t1)},
      rounds: {'r1': Round(id: 'r1', myBookId: 'b1', index: 1, startedAt: '2026-11-10', createdAt: t1, updatedAt: t1)},
      sessions: {
        's1': Session(id: 's1', myBookId: 'b1', roundId: 'r1', startedAt: t1, endedAt: '2026-11-10T01:30:00.000Z', durationMs: 1800000, startPage: 1, pagesRead: 20, createdAt: t1, updatedAt: t1),
      },
      bookmarks: {
        'm1': Bookmark(id: 'm1', myBookId: 'b1', text: '첫 갈피', createdAt: t1, updatedAt: t1),
        'm2': Bookmark(id: 'm2', myBookId: 'b1', text: '둘째 갈피', createdAt: t1, updatedAt: t1),
      },
      essays: {'x1': Essay(id: 'x1', myBookId: 'b1', body: '긴 감상', createdAt: t1, updatedAt: t1)},
    );

Future<void> fail(List<LocalChange> _) async => throw StateError('기기에 쓰지 못했어요');
Future<void> ok(List<LocalChange> _) async {}

void main() {
  final m = LibraryModel.instance;
  var notified = 0;
  void count() => notified++;

  setUp(() {
    m.useForTest(lib());
    m.writeChanges = fail;
    notified = 0;
    m.addListener(count);
  });
  tearDown(() {
    m.removeListener(count);
    m.writeChanges = applyLocalChanges;
  });

  group('지우기가 실패하면 화면 서재도 그대로', () {
    test('책 삭제: 판본 · 장정 · 회차 · 갈피 · 감상이 돌아오고 독서 기록의 책 연결도 그대로', () async {
      final before = m.lib;
      await expectLater(m.deleteBook('b1', archived: false), throwsStateError);
      for (final (now, was) in [
        (m.lib.books, before.books),
        (m.lib.editions, before.editions),
        (m.lib.bindings, before.bindings),
        (m.lib.rounds, before.rounds),
        (m.lib.sessions, before.sessions),
        (m.lib.bookmarks, before.bookmarks),
        (m.lib.essays, before.essays),
      ]) {
        expect(now.keys, unorderedEquals(was.keys));
        for (final id in was.keys) {
          expect(identical(now[id], was[id]), isTrue, reason: id);
        }
      }
      expect(m.lib.sessions['s1']!.myBookId, 'b1');
      expect(notified, 2, reason: '지울 때 한 번, 되돌릴 때 한 번 알린다');
      expect(m.error, isA<StateError>());
    });

    test('책 숨기기도 숨긴 때가 비워진 채로 돌아온다', () async {
      await expectLater(m.deleteBook('b1', archived: true), throwsStateError);
      expect(m.lib.books['b1']!.hiddenAt, isNull);
    });

    test('독서 기록 삭제', () async {
      await expectLater(m.deleteSession('s1'), throwsStateError);
      expect(m.lib.sessions['s1'], isNotNull);
    });

    test('갈피 삭제: 갈피 수가 줄지 않는다', () async {
      await expectLater(m.deleteBookmark('m1'), throwsStateError);
      expect(m.lib.bookmarks.keys, unorderedEquals(['m1', 'm2']));
    });

    test('감상 삭제', () async {
      await expectLater(m.deleteEssay('x1'), throwsStateError);
      expect(m.essaysOf('b1').map((e) => e.id), ['x1']);
    });
  });

  group('다른 쓰기도 같은 길', () {
    test('새 갈피 · 새 감상은 빠지고, 고친 값은 앞 값으로', () async {
      await expectLater(m.addBookmark(myBookId: 'b1', text: '새 갈피'), throwsStateError);
      expect(m.lib.bookmarks.length, 2);
      await expectLater(m.addEssay(myBookId: 'b1', body: '새 감상'), throwsStateError);
      expect(m.lib.essays.length, 1);
      await expectLater(m.updateBook('b1', rating: 5), throwsStateError);
      expect(m.lib.books['b1']!.rating, isNull);
      await expectLater(m.toggleSaved('m1'), throwsStateError);
      expect(m.lib.bookmarks['m1']!.savedAt, isNull);
    });

    test('보드 자리 저장 실패: 옮긴 갈피와 함께 적은 갈피 모두 앞 자리(자동 자리)로', () async {
      await expectLater(
        m.updateBoard([(id: 'm1', x: 10, y: 20, rot: 1), (id: 'm2', x: 300, y: 20, rot: -1)], 'm1', x: 500, y: 600, rot: 1),
        throwsStateError,
      );
      expect(m.lib.bookmarks['m1']!.boardX, isNull);
      expect(m.lib.bookmarks['m2']!.boardX, isNull);
    });

    test('먼저 저장된 고치기는 남기고 실패한 고치기만 되돌린다', () async {
      m.writeChanges = ok;
      await m.deleteBookmark('m1');
      m.writeChanges = fail;
      await expectLater(m.deleteBookmark('m2'), throwsStateError);
      expect(m.lib.bookmarks.keys, ['m2'], reason: 'm1은 기기에서 지워졌고 m2는 지우지 못했다');
    });

    test('차례를 기다리던 다음 고치기가 성공하면 그 고치기는 화면에 남는다', () async {
      final first = Completer<void>();
      var calls = 0;
      m.writeChanges = (_) {
        calls++;
        return calls == 1 ? first.future : Future.value();
      };
      final a = m.deleteBookmark('m1');
      final b = m.updateBook('b1', rating: 4);
      expect(m.lib.bookmarks.containsKey('m1'), isFalse);
      first.completeError(StateError('기기에 쓰지 못했어요'));
      await expectLater(a, throwsStateError);
      await b;
      expect(m.lib.bookmarks.containsKey('m1'), isTrue);
      expect(m.lib.books['b1']!.rating, 4);
    });

    test('실패한 고치기 위에 다시 고친 것도 실패하면 기기 값으로(앞 실패 값이 남지 않는다)', () async {
      final first = Completer<void>();
      var calls = 0;
      m.writeChanges = (_) {
        calls++;
        return calls == 1 ? first.future : Future<void>.error(StateError('또 실패'));
      };
      final a = m.updateBook('b1', rating: 3);
      final b = m.updateBook('b1', note: '다시 고침');
      first.completeError(StateError('기기에 쓰지 못했어요'));
      await expectLater(a, throwsStateError);
      expect(m.lib.books['b1']!.note, '다시 고침', reason: '뒤 고치기가 아직 저장 중');
      await expectLater(b, throwsStateError);
      expect(m.lib.books['b1']!.rating, isNull);
      expect(m.lib.books['b1']!.note, isNull);
    });

    test('서버에서 받은 항목을 쓰지 못하면 화면에서도 빠진다', () async {
      final mark = Bookmark(id: 'm9', myBookId: 'b1', text: '받은 갈피', createdAt: t1, updatedAt: t1);
      // 시험에는 기기 DB가 없어 받은 항목 쓰기가 실패한다
      await expectLater(m.applyRemote([(kind: LibKind.bookmarks, item: mark, id: 'm9')], [(kind: LibKind.bookmarks, id: 'm1')]), throwsA(anything));
      expect(m.lib.bookmarks.keys, unorderedEquals(['m1', 'm2']));
    });
  });

  group('책장 배치 저장 실패', () {
    final p = PlacementStore.instance;
    const before = ShelfLayout([Shelf('s1', 0)], []);
    tearDown(() => p.writeLayout = saveLayout);

    test('화면 배치가 앞 배치로 돌아오고 되돌리기도 그대로', () async {
      p.layout = before;
      p.books = {};
      p.writeLayout = (_, _) async => throw StateError('기기에 쓰지 못했어요');
      await expectLater(p.commit(const ShelfLayout([Shelf('s1', 0), Shelf('s2', 1)], [])), throwsStateError);
      expect(identical(p.layout, before), isTrue);
      expect(p.canUndo, isFalse);
    });
  });
}
