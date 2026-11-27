// 독서 기록 수정 규칙(옛 앱(RN) domain/session-edit.ts·library.ts updateSessionIn)
// (옛 앱 시험을 옮겨 온 것이다. 지금은 이 Flutter 코드의 규칙 시험이다)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/session_edit.dart';
import 'package:flutter_test/flutter_test.dart';

String local(int y, int m, int d, int h, int mi, [int s = 0]) => DateTime(y, m, d, h, mi, s).toUtc().toIso8601String();

Session session({String? book = 'a', String? round = 'r-a'}) => Session(
      id: 's1',
      myBookId: book,
      roundId: round,
      // 20:00:10 시작, 20:40:10 끝, 실제 독서 25분 30초(일시정지 14분 30초)
      startedAt: local(2026, 11, 3, 20, 0, 10),
      endedAt: local(2026, 11, 3, 20, 40, 10),
      durationMs: 25 * 60000 + 30000,
      createdAt: local(2026, 11, 3, 20, 40, 10),
      updatedAt: local(2026, 11, 3, 20, 40, 10),
      memo: '메모',
    );

void main() {
  test('화면 값: 현지 날짜·시각, 분은 반올림(1분 이상)', () {
    final f = sessionFormOf(session());
    expect([f.day, f.time, f.minutes, f.memo, f.pages], ['2026-11-03', '20:00', '26', '메모', '']);
  });

  test('메모만 고치면 시각·초 단위 시간은 그대로', () {
    final s = session(), f = sessionFormOf(s);
    final p = sessionEditPatch(s, f, (bookId: f.bookId, day: f.day, time: f.time, minutes: f.minutes, startPage: f.startPage, pages: f.pages, memo: ' 새 메모 '))!;
    expect(p, {'memo': '새 메모'});
  });

  test('시각을 옮기면 시작·끝을 같은 만큼(초 단위 그대로), 고친 칸이 틀리면 저장 막기', () {
    final s = session(), f = sessionFormOf(s);
    final p = sessionEditPatch(s, f, (bookId: f.bookId, day: f.day, time: '21:30', minutes: f.minutes, startPage: '', pages: '', memo: f.memo))!;
    expect(p['startedAt'], local(2026, 11, 3, 21, 30, 10));
    expect(p['endedAt'], local(2026, 11, 3, 22, 10, 10));
    expect(sessionEditPatch(s, f, (bookId: f.bookId, day: '2026-1-3', time: f.time, minutes: f.minutes, startPage: '', pages: '', memo: f.memo)), isNull);
    expect(sessionEditPatch(s, f, (bookId: f.bookId, day: f.day, time: f.time, minutes: '0', startPage: '', pages: '', memo: f.memo)), isNull);
  });

  test('독서 시간을 늘리면 끝은 시작 + 새 시간이 기존 끝보다 늦을 때만 늦춘다', () {
    final s = session(), f = sessionFormOf(s);
    final longer = sessionEditPatch(s, f, (bookId: f.bookId, day: f.day, time: f.time, minutes: '60', startPage: '', pages: '', memo: f.memo))!;
    expect(longer['durationMs'], 3600000);
    expect(longer['endedAt'], local(2026, 11, 3, 21, 0, 10));
    final shorter = sessionEditPatch(s, f, (bookId: f.bookId, day: f.day, time: f.time, minutes: '10', startPage: '', pages: '', memo: f.memo))!;
    expect(shorter.containsKey('endedAt'), isFalse);
  });

  test('책 연결을 끊거나 바꾸면 회차도 그 책 것으로(없으면 비움), 지우면 갈피는 연결만 비운다', () {
    final lib = Library();
    for (final id in ['a', 'b']) {
      lib.books[id] = MyBook(id: id, editionId: 'e', status: ReadStatus.reading, createdAt: '', updatedAt: '');
    }
    lib.rounds['r-b'] = Round(id: 'r-b', myBookId: 'b', index: 1, createdAt: '', updatedAt: '', startedAt: '2026-11-01');
    lib.sessions['s1'] = session();
    lib.bookmarks['m1'] = Bookmark(id: 'm1', myBookId: 'a', text: '문장', createdAt: '', updatedAt: '', sessionId: 's1');
    final moved = updateSessionIn(lib, 's1', {'myBookId': 'b'}, 'now');
    expect([moved.sessions['s1']!.myBookId, moved.sessions['s1']!.roundId], ['b', 'r-b']);
    final cut = updateSessionIn(lib, 's1', {'myBookId': null}, 'now');
    expect([cut.sessions['s1']!.myBookId, cut.sessions['s1']!.roundId], [null, null]);
    expect(identical(updateSessionIn(lib, 's1', {'memo': '메모'}, 'now'), lib), isTrue); // 바뀐 것 없음
    final gone = deleteSessionIn(lib, 's1', 'now');
    expect(gone.sessions.containsKey('s1'), isFalse);
    expect(gone.bookmarks['m1']!.sessionId, isNull);
    expect(gone.bookmarks['m1']!.text, '문장');
  });

  group('읽기 상태 · 현재 쪽 규칙(2026-11-24 1단계): 기록 수정 · 삭제', () {
    Session rec(String id, {num? start, num? pages, String round = 'r1', int day = 3}) => Session(
          id: id,
          myBookId: 'a',
          roundId: round,
          startedAt: local(2026, 11, day, 20, 0),
          endedAt: local(2026, 11, day, 21, 0),
          durationMs: 3600000,
          createdAt: '',
          updatedAt: '',
          startPage: start,
          pagesRead: pages,
        );
    Library make({num? current = 120, ReadStatus status = ReadStatus.reading}) {
      final lib = Library();
      lib.editions['e'] = Edition(id: 'e', title: '책', authors: const [], source: 'photo', pageCount: 200, createdAt: '', updatedAt: '');
      lib.books['a'] = MyBook(id: 'a', editionId: 'e', status: status, currentPage: current, createdAt: '', updatedAt: '');
      lib.rounds['r1'] = Round(id: 'r1', myBookId: 'a', index: 1, createdAt: '', updatedAt: '', startedAt: '2026-11-01');
      lib.sessions['s1'] = rec('s1', start: 50, pages: 80, day: 1);
      lib.sessions['s2'] = rec('s2', start: 80, pages: 120, day: 2);
      return lib;
    }

    test('규칙 3: 현재 쪽이 그 기록의 도달한 쪽이면, 도달한 쪽을 고친 뒤 같은 회차 남은 기록 중 가장 큰 쪽으로', () {
      expect(updateSessionIn(make(), 's2', {'pagesRead': 100}, 'now').books['a']!.currentPage, 100);
      expect(updateSessionIn(make(), 's2', {'pagesRead': 60}, 'now').books['a']!.currentPage, 80, reason: '다른 기록(80)이 더 크다');
      expect(updateSessionIn(make(), 's2', {'pagesRead': 150}, 'now').books['a']!.currentPage, 150);
    });

    test('규칙 3: 기록을 지우면 남은 기록의 가장 큰 쪽, 남은 게 없으면 그 기록의 시작 쪽, 그것도 없으면 비운다', () {
      expect(deleteSessionIn(make(), 's2', 'now').books['a']!.currentPage, 80);
      final only = make()..sessions.remove('s1');
      expect(deleteSessionIn(only, 's2', 'now').books['a']!.currentPage, 80, reason: '그 기록의 시작 쪽');
      final noStart = make()
        ..sessions.remove('s1')
        ..sessions['s2'] = rec('s2', pages: 120, day: 2);
      expect(deleteSessionIn(noStart, 's2', 'now').books['a']!.currentPage, isNull);
    });

    test('규칙 3: 다른 회차 기록은 세지 않는다', () {
      final lib = make()
        ..rounds['r0'] = Round(id: 'r0', myBookId: 'a', index: 0, createdAt: '', updatedAt: '', startedAt: '2026-10-01', finishedAt: '2026-10-20')
        ..sessions['old'] = rec('old', pages: 190, round: 'r0', day: 1);
      expect(deleteSessionIn(lib, 's2', 'now').books['a']!.currentPage, 80);
    });

    test('규칙 3: 현재 쪽이 기록과 다르면(직접 적은 쪽) 고치거나 지워도 그대로', () {
      expect(updateSessionIn(make(current: 130), 's2', {'pagesRead': 100}, 'now').books['a']!.currentPage, 130);
      expect(deleteSessionIn(make(current: 130), 's2', 'now').books['a']!.currentPage, 130);
    });

    test('규칙 1: 도달한 쪽을 마지막 쪽으로 고치면 완독, 완독일은 그 기록을 시작한 날', () {
      final out = updateSessionIn(make(), 's2', {'pagesRead': 200}, 'now');
      expect(out.books['a']!.status, ReadStatus.read);
      expect(out.rounds['r1']!.finishedAt, '2026-11-02');
    });

    test('규칙 4: 완독은 되돌리지 않는다(기록을 지우거나 쪽을 낮춰도 완독)', () {
      final done = updateSessionIn(make(), 's2', {'pagesRead': 200}, 'now');
      final lowered = updateSessionIn(done, 's2', {'pagesRead': 120}, 'now');
      expect(lowered.books['a']!.status, ReadStatus.read);
      expect(lowered.books['a']!.currentPage, 120);
      final gone = deleteSessionIn(done, 's2', 'now');
      expect(gone.books['a']!.status, ReadStatus.read);
      expect(gone.books['a']!.currentPage, 80);
    });
  });
}

