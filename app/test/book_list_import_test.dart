import 'dart:convert';

import 'package:chaekjang/domain/book_list_import.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/book/book_match.dart';
import 'package:chaekjang/services/book_search.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

BookCandidate _c(String title, {String? isbn, List<String> authors = const [], String? publisher, String? publishedAt}) =>
    BookCandidate(key: 'k:$title:$isbn', title: title, authors: authors, sourceName: 'YES24', isbn13: isbn, publisher: publisher, publishedAt: publishedAt);

void main() {
  group('ISBN', () {
    test('13자리는 검사 숫자가 맞을 때만, 10자리는 978을 붙여 13자리로', () {
      expect(isbn13Of('9788936434120'), '9788936434120');
      expect(isbn13Of('978-89-364-3412-0'), '9788936434120');
      expect(isbn13Of('ISBN 9788936434120'), '9788936434120');
      expect(isbn13Of('="9781984822178"'), '9781984822178'); // 굿리즈 내보내기 모양
      expect(isbn13Of('9788936434121'), isNull); // 검사 숫자 틀림
      expect(isbn13Of('8801234567893'), isNull); // 책(978·979)이 아닌 바코드
      expect(isbn13Of('8936434128'), '9788936434120');
      expect(isbn13Of('1984'), isNull);
      expect(isbn13Of(''), isNull);
    });
  });

  group('목록 표 읽기', () {
    test('한국어 머리 이름: 제목·저자·출판사·ISBN·상태', () {
      final p = parseTable([
        ['번호', '책 제목', '지은이', '출판사', 'ISBN', '읽기 상태'],
        ['1', '소년이 온다', '한강', '창비', '9788936434120', '다 읽음'],
        ['2', '데미안', '헤르만 헤세', '민음사', '', '읽고 싶은 책'],
        ['', '', '', '', '', ''],
        ['3', '작별하지 않는다', '한강', '문학동네', '', '읽는 중'],
      ]);
      expect(p.error, isNull);
      expect(p.columns, {'isbn': 'ISBN', 'title': '책 제목', 'author': '지은이', 'publisher': '출판사', 'status': '읽기 상태'});
      expect(p.rows.length, 3);
      expect(p.rows[0].isbn, '9788936434120');
      expect(p.rows[0].query, '9788936434120');
      expect(p.rows[0].status, ReadStatus.read);
      expect(p.rows[1].query, '데미안 헤르만 헤세');
      expect(p.rows[1].status, ReadStatus.want);
      expect(p.rows[2].status, ReadStatus.reading);
      expect(p.rows[2].line, 5);
    });

    test('영어 머리(굿리즈 모양)와 같은 ISBN 거르기', () {
      final p = parseTable([
        ['Book Id', 'Title', 'Author', 'ISBN13', 'Exclusive Shelf'],
        ['1', 'Normal People', 'Sally Rooney', '="9781984822178"', 'read'],
        ['2', 'Normal People', 'Sally Rooney', '="9781984822178"', 'to-read'],
        ['3', 'Klara and the Sun', 'Kazuo Ishiguro', '=""', 'currently-reading'],
      ]);
      expect(p.rows.length, 2);
      expect(p.duplicates, 1);
      expect(p.rows[0].status, ReadStatus.read);
      expect(p.rows[1].isbn, isNull);
      expect(p.rows[1].status, ReadStatus.reading);
    });

    test('머리줄이 없으면 내용으로 ISBN·제목 열을 짐작한다', () {
      final p = parseTable([
        ['9788936434120', '소년이 온다'],
        ['9788937460449', '데미안'],
      ]);
      expect(p.rows.map((r) => r.isbn), ['9788936434120', '9788937460449']);
      expect(p.rows.map((r) => r.title), ['소년이 온다', '데미안']);
    });

    test('CSV(UTF-8 BOM·따옴표·쉼표)와 TSV, 읽지 못하는 글자', () {
      final csv = utf8.encode('﻿제목,저자\n"채식주의자, 개정판",한강\n아몬드,손원평\n');
      final p = parseBookList(csv, 'list.csv');
      expect(p.rows.map((r) => r.title), ['채식주의자, 개정판', '아몬드']);
      final tsv = utf8.encode('title\tauthor\nIntermezzo\tSally Rooney\n');
      expect(parseBookList(tsv, 'list.tsv').rows.single.author, 'Sally Rooney');
      // EUC-KR 같은 UTF-8이 아닌 파일
      expect(parseBookList([0xC1, 0xA6, 0xB8, 0xF1, 0x0A], 'old.csv').error, 'encoding');
      expect(parseBookList(utf8.encode('x'), 'list.pdf').error, 'format');
      expect(parseBookList(utf8.encode('제목\n\n'), 'empty.csv').error, 'empty');
    });

    test('엑셀(.xlsx): 숫자로 저장된 ISBN도 소수점 없이', () {
      final x = Excel.createExcel();
      final sheet = x.getDefaultSheet()!;
      x.appendRow(sheet, [TextCellValue('도서명'), TextCellValue('저자'), TextCellValue('ISBN')]);
      x.appendRow(sheet, [TextCellValue('소년이 온다'), TextCellValue('한강'), IntCellValue(9788936434120)]);
      x.appendRow(sheet, [TextCellValue('데미안'), TextCellValue('헤르만 헤세'), DoubleCellValue(9788937460449)]);
      final p = parseBookList(x.encode()!, '내 책.xlsx');
      expect(p.error, isNull);
      expect(p.rows.map((r) => r.isbn), ['9788936434120', '9788937460449']);
      expect(p.rows.map((r) => r.title), ['소년이 온다', '데미안']);
    });
  });

  group('검색 결과 고르기', () {
    test('ISBN 줄은 같은 ISBN만(결과가 한 권뿐이면 그 책)', () {
      const row = ImportRow(line: 2, isbn: '9788936434120');
      final a = _c('다른 책', isbn: '9788937460449'), b = _c('소년이 온다', isbn: '9788936434120');
      expect(matchCandidate(row, [a, b]), b);
      expect(matchCandidate(row, [a]), a);
      expect(matchCandidate(row, [a, _c('또 다른 책', isbn: '9788932917245')]), isNull);
    });

    test('제목 줄은 제목이 같거나 겹치는 책 중 저자·출판사가 맞는 쪽', () {
      const row = ImportRow(line: 3, title: '데미안', author: '헤르만 헤세', publisher: '민음사');
      final other = _c('데미안', authors: ['Hermann Hesse'], publisher: '문학동네');
      final right = _c('데미안 (세계문학전집 44)', authors: ['헤르만 헤세'], publisher: '민음사');
      expect(matchCandidate(row, [other, right]), right);
      expect(matchCandidate(const ImportRow(line: 4, title: '없는 책'), [other]), isNull);
    });

    test('내 서재에 있는 책: ISBN이 같거나, ISBN이 없으면 제목·첫 저자가 같은 책(숨긴 책은 빼고)', () {
      final lib = Library();
      const t = '2026-11-15T00:00:00Z';
      lib.editions['e1'] = Edition(id: 'e1', title: '소년이 온다', authors: const ['한강'], source: 'search', createdAt: t, updatedAt: t, isbn13: '9788936434120');
      lib.books['b1'] = MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.want, createdAt: t, updatedAt: t);
      lib.editions['e2'] = Edition(id: 'e2', title: '데미안', authors: const ['헤르만 헤세'], source: 'manual', createdAt: t, updatedAt: t);
      lib.books['b2'] = MyBook(id: 'b2', editionId: 'e2', status: ReadStatus.want, createdAt: t, updatedAt: t, hiddenAt: t);
      expect(ownedBookId(lib, _c('소년이 온다', isbn: '9788936434120')), 'b1');
      expect(ownedBookId(lib, _c('소년이 온다', isbn: '9788954651134')), isNull); // 다른 판
      expect(ownedBookId(lib, _c('소년이 온다', authors: ['한강'])), 'b1');
      expect(ownedBookId(lib, _c('데미안', authors: ['헤르만 헤세'])), isNull); // 숨긴 책
    });

    test('결과 줄 출판사 · 연도', () {
      expect(publisherLine(_c('a', publisher: '창비', publishedAt: '2014-05-19')), '창비 | 2014');
      expect(publisherLine(_c('a', publishedAt: '2014')), '2014');
      expect(publisherLine(_c('a')), isNull);
    });
  });
}
