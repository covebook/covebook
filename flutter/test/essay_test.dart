// 긴 감상(기록 > 감상, 2026-11-16): 모델·저장 행·백업 호환·동기화 변환, 기록 탭 거르기
import 'dart:convert';

import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/library_json.dart';
import 'package:chaekjang/domain/sync.dart';
import 'package:chaekjang/features/record/record_tab.dart' show MarkKind, essayShown, markConditions, markShown;
import 'package:chaekjang/store/backup.dart' show countsOf, validateBackup;
import 'package:chaekjang/store/library_read.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';
const t2 = '2026-11-16T02:00:00.000Z';
const t3 = '2026-11-16T03:00:00.000Z';

Essay essay({String id = 'es1', String book = 'bk1', String? title, String body = '첫 줄\n둘째 줄', String at = t1}) =>
    Essay(id: id, myBookId: book, title: title, body: body, createdAt: t1, updatedAt: at);

Library lib({Map<String, Essay>? essays}) => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '데미안', authors: const ['헤르만 헤세'], source: 'photo', createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.read, createdAt: t1, updatedAt: t1, rating: 4.5, note: '한 줄 감상')},
      sessions: {'s1': Session(id: 's1', startedAt: t1, endedAt: t1, durationMs: 60000, createdAt: t1, updatedAt: t1, myBookId: 'bk1', memo: '세션 메모')},
      bookmarks: {'m1': Bookmark(id: 'm1', myBookId: 'bk1', text: '새는 알에서 나오려고 투쟁한다', memo: '갈피 메모', createdAt: t1, updatedAt: t1)},
      essays: essays ?? {'es1': essay(title: '알을 깨는 일', body: '길게 쓴 감상\n\n둘째 문단')},
    );

Map<String, Object?> backupOf(Library l) => {
      'app': 'chaekjang',
      'format': 1,
      'exportedAt': t1,
      'library': jsonDecode(jsonEncode(libraryToJson(l))),
      'layout': '{"version":2,"shelves":[],"placements":[],"drawer":[]}',
      'view': null,
      'settings': {},
      'images': {},
      'bookcases': [],
    };

void main() {
  group('모델', () {
    test('제목은 고를 수 있다: 비우면 없음, 앞뒤 빈칸은 뗀다', () {
      final e = essay();
      expect(e.edit(title: '  ', body: '본문', updated: t2).title, isNull);
      final x = e.edit(title: ' 제목 ', body: '본문', updated: t2);
      expect([x.title, x.body, x.createdAt, x.updatedAt, x.myBookId], ['제목', '본문', t1, t2, 'bk1']);
      expect(e.toJson().containsKey('title'), isFalse);
    });

    test('목록 제목·미리보기: 제목이 없으면 본문 첫 줄이 제목 자리에', () {
      expect(essayHeadline(essay(title: '제목')), '제목');
      expect(essayPreview(essay(title: '제목', body: '한 줄\n\n두 줄')), '한 줄 두 줄');
      expect(essayHeadline(essay(body: '\n\n첫 줄\n둘째 줄\n셋째 줄')), '첫 줄');
      expect(essayPreview(essay(body: '\n\n첫 줄\n둘째 줄\n셋째 줄')), '둘째 줄 셋째 줄');
      // 긴 첫 줄은 제목 자리에서 줄이고 미리보기에 첫 줄부터
      final long = '가' * 50;
      expect(essayHeadline(essay(body: long)), '${'가' * 40}…');
      expect(essayPreview(essay(body: long)), long);
      expect(essayPreview(essay(body: '짧은 한 줄')), '');
      // 그림 글자를 반으로 가르지 않는다
      expect(essayHeadline(essay(body: '😀' * 41)), '${'😀' * 40}…');
    });

    test('서재 copy는 감상을 지킨다', () {
      final l = lib().copy(bookmarks: const {});
      expect(l.essays.keys, ['es1']);
    });
  });

  group('저장(재실행 뒤에도 남는 행)', () {
    test('감상 → 행 → 감상이 같다', () {
      for (final e in [essay(title: '제목'), essay(id: 'es2', body: '제목 없는 감상')]) {
        final v = valuesOf(LibKind.essays, e);
        final row = {for (final (i, c) in libColumns[LibKind.essays]!.indexed) c: v[i]};
        expect(jsonEncode(essayOf(row).toJson()), jsonEncode(e.toJson()));
      }
      expect(libTable[LibKind.essays], 'essays');
    });

    test('행으로 서재를 읽을 때 감상 표가 없으면(앱을 처음 고친 뒤) 빈 감상', () {
      final rows = <String, List<Map<String, Object?>>>{
        'essays': [
          {'id': 'es1', 'my_book_id': 'bk1', 'title': null, 'body': '본문', 'created_at': t1, 'updated_at': t2},
        ],
      };
      expect(libraryFromRows(rows).essays['es1']?.body, '본문');
      expect(libraryFromRows(const {}).essays, isEmpty);
    });
  });

  group('백업 호환', () {
    test('감상이 있는 서재 JSON 왕복: 별점·한 줄 감상·갈피 메모·세션 메모와 따로', () {
      final j = jsonDecode(jsonEncode(libraryToJson(lib()))) as Map<String, Object?>;
      final back = libraryFromJson(j);
      expect(back.essays['es1']!.title, '알을 깨는 일');
      expect(back.essays['es1']!.body, '길게 쓴 감상\n\n둘째 문단');
      expect([back.books['bk1']!.rating, back.books['bk1']!.note, back.bookmarks['m1']!.memo, back.sessions['s1']!.memo], [4.5, '한 줄 감상', '갈피 메모', '세션 메모']);
      expect(jsonEncode(libraryToJson(back)), jsonEncode(libraryToJson(lib())));
    });

    test('감상이 없는 예전 백업도 그대로 읽고 검사를 통과한다', () {
      final old = backupOf(lib(essays: const {}));
      expect((old['library']! as Map).containsKey('essays'), isFalse, reason: '감상이 없으면 예전 모양 그대로 쓴다');
      expect(validateBackup(old), isNull);
      expect(libraryFromJson((old['library']! as Map).cast<String, Object?>()).essays, isEmpty);
      expect(countsOf(old).essays, 0);
      expect(countsOf(old).bookmarks, 1);
    });

    test('감상이 든 백업: 검사 통과·개수, 틀린 감상은 이유를 알린다', () {
      final b = backupOf(lib(essays: {'es1': essay(), 'es2': essay(id: 'es2', title: '두 번째')}));
      expect(validateBackup(b), isNull);
      expect(countsOf(b).essays, 2);
      final orphan = jsonDecode(jsonEncode(b)) as Map<String, Object?>;
      ((orphan['library']! as Map)['essays'] as Map)['es1']['myBookId'] = 'nope';
      expect(validateBackup(orphan), '감상 정보가 올바르지 않아요.');
      final noBody = jsonDecode(jsonEncode(b)) as Map<String, Object?>;
      ((noBody['library']! as Map)['essays'] as Map)['es2'].remove('body');
      expect(validateBackup(noBody), '감상 정보가 올바르지 않아요.');
      final badId = jsonDecode(jsonEncode(b)) as Map<String, Object?>;
      ((badId['library']! as Map)['essays'] as Map)['es2']['id'] = 'other';
      expect(validateBackup(badId), isNotNull);
    });
  });

  group('동기화 변환', () {
    test('올리기: 감상 변경은 essays 묶음으로(제목 없으면 빼고)', () {
      final l = lib(essays: {'es1': essay(), 'es2': essay(id: 'es2', title: '제목', at: t2)});
      final r = buildPush(l, {dirtyKey(LibKind.essays, 'es1'): (deleted: false, at: t1), dirtyKey(LibKind.essays, 'gone'): (deleted: true, at: t3)}, 'file:///x/');
      expect(r.count, 2);
      expect(r.body['essays'], [
        {'id': 'es1', 'myBookId': 'bk1', 'body': '첫 줄\n둘째 줄', 'createdAt': t1, 'updatedAt': t1},
        {'id': 'gone', 'deleted': true, 'updatedAt': t3},
      ]);
      expect(fullDirty(l).keys.where((k) => k.startsWith('essays:')).toSet(), {'essays:es1', 'essays:es2'});
      final w = essayToWire(l.essays['es2']!);
      expect(jsonEncode(essayFromWire(w).toJson()), jsonEncode(l.essays['es2']!.toJson()));
    });

    test('감상을 모르는 서버(재배포 전): 감상은 빼고 보내고 올릴 표시는 남긴다', () {
      final body = {'books': <Wire>[{'id': 'bk1'}], 'essays': <Wire>[{'id': 'es1'}]};
      expect(withoutEssays(body).keys, ['books']);
      final pending = {'books:bk1': 1, 'essays:es1': 2, 'bookmarks:essays:x': 3};
      expect(ackableWithoutEssays(pending).keys, ['books:bk1', 'bookmarks:essays:x']);
      expect(serverKnowsEssays({'rev': 1, 'books': []}), isFalse);
      expect(serverKnowsEssays({'rev': 1, 'books': [], 'essays': []}), isTrue);
    });

    test('받기: 더 새것이 이기고, 지운 것은 지운다. essays가 없는 응답(예전 서버)은 감상을 건드리지 않는다', () {
      final l = lib(essays: {'es1': essay(at: t2), 'es2': essay(id: 'es2', at: t1)});
      Map<String, Object?> pull(List<Wire>? essays) => {'rev': 2, 'more': false, 'books': [], 'bookmarks': [], 'essays': ?essays};
      final old = mergeRemote(l, pull(null), 'file:///x/');
      expect(old.lib.essays.keys.toSet(), {'es1', 'es2'});
      expect(old.writes, isEmpty);
      final m = mergeRemote(
        l,
        pull([
          {'id': 'es1', 'myBookId': 'bk1', 'body': '서버의 낡은 값', 'createdAt': t1, 'updatedAt': t1},
          {'id': 'es2', 'myBookId': 'bk1', 'title': '다른 기기에서', 'body': '고친 본문', 'createdAt': t1, 'updatedAt': t3},
          {'id': 'es3', 'myBookId': 'bk1', 'body': '새 감상', 'createdAt': t3, 'updatedAt': t3},
        ]),
        'file:///x/',
      );
      expect(m.lib.essays['es1']!.body, '첫 줄\n둘째 줄');
      expect([m.lib.essays['es2']!.title, m.lib.essays['es2']!.body], ['다른 기기에서', '고친 본문']);
      expect(m.lib.essays['es3']!.body, '새 감상');
      expect(m.writes.map((w) => w.id).toSet(), {'es2', 'es3'});
      final d = mergeRemote(l, pull([{'id': 'es2', 'deleted': true, 'updatedAt': t3}]), 'file:///x/');
      expect(d.lib.essays.keys, ['es1']);
      expect(d.erases, [(kind: LibKind.essays, id: 'es2')]);
    });
  });

  group('기록 탭 거르기', () {
    final text = Bookmark(id: 'a', myBookId: 'bk1', text: '문장', memo: '메모', createdAt: t1, updatedAt: t1, savedAt: t2);
    final photo = Bookmark(id: 'b', myBookId: 'bk2', text: '', photoUri: 'file:///p.jpg', createdAt: t1, updatedAt: t1);

    test('갈피: 책·유형·아껴둔·검색어가 함께 걸린다', () {
      expect(markShown(text), isTrue);
      expect(markShown(photo, kind: MarkKind.photo), isTrue);
      expect(markShown(text, kind: MarkKind.photo), isFalse);
      expect(markShown(photo, kind: MarkKind.text), isFalse);
      expect(markShown(text, savedOnly: true), isTrue);
      expect(markShown(photo, savedOnly: true), isFalse);
      expect(markShown(text, book: 'bk2'), isFalse);
      expect(markShown(text, book: 'bk1', kind: MarkKind.text, savedOnly: true, q: '메모'), isTrue);
      expect(markShown(text, savedOnly: true, q: '없는 말'), isFalse);
    });

    test('갈피 조건 줄: 걸린 것만(기본이면 없음)', () {
      expect(markConditions(), isEmpty);
      expect(markConditions(bookTitle: '데미안', kind: MarkKind.photo), ['데미안', '사진 갈피']);
      expect(markConditions(savedOnly: true), ['아껴둔 갈피']);
    });

    test('감상: 책·검색어(제목·본문·책 제목·지은이)', () {
      final l = lib();
      final e = l.essays['es1']!;
      expect(essayShown(l, e), isTrue);
      expect(essayShown(l, e, book: 'bk2'), isFalse);
      for (final q in ['알을', '둘째 문단', '데미안', '헤세']) {
        expect(essayShown(l, e, q: q), isTrue, reason: q);
      }
      expect(essayShown(l, e, q: '없는 말'), isFalse);
    });
  });
}
