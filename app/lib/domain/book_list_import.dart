// 책 목록 파일 가져오기(2026-11-15 사용자 'CSV·엑셀 가져오기 다 넣어', 페르소나 QA 장서가 F2 '400권을 한 권씩'):
// CSV·TSV·엑셀(.xlsx) 파일을 읽어 머리줄에서 ISBN·제목·저자·출판사·읽기 상태 열을 찾고, 줄마다 찾을 검색어를 만든다.
// 북적북적·엑셀 독서 기록처럼 머리 이름이 제각각이라 이름을 넓게 맞춘다(한국어·영어). 머리줄이 없으면 내용으로 ISBN·제목 열을 짐작한다.
// 화면·검색과 떨어진 순수 계산(시험용). ISBN 검사는 바코드 스캔도 같이 쓴다
library;

import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'library.dart' show ReadStatus;

/// ISBN 정규화: 13자리(978·979, 검사 숫자 맞음)는 그대로, 10자리(검사 숫자 맞음)는 978을 붙여 13자리로. 아니면 null
String? isbn13Of(String raw) {
  // 하이픈·띄어쓰기·'ISBN' 글자·굿리즈식 ="978…" 따옴표를 뗀다
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
  if (RegExp(r'^\d{13}$').hasMatch(s)) {
    if (!s.startsWith('978') && !s.startsWith('979')) return null;
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(s[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - sum % 10) % 10 == int.parse(s[12]) ? s : null;
  }
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(s)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final d = s[i] == 'X' ? 10 : int.parse(s[i]);
      sum += d * (10 - i);
    }
    if (sum % 11 != 0) return null;
    final body = '978${s.substring(0, 9)}';
    var t = 0;
    for (var i = 0; i < 12; i++) {
      t += int.parse(body[i]) * (i.isEven ? 1 : 3);
    }
    return '$body${(10 - t % 10) % 10}';
  }
  return null;
}

/// 파일 한 줄(가져올 책 하나)
class ImportRow {
  const ImportRow({required this.line, this.isbn, this.title = '', this.author = '', this.publisher = '', this.status});

  /// 파일에서 몇째 줄인지(사람이 보는 1부터)
  final int line;
  final String? isbn;
  final String title, author, publisher;
  final ReadStatus? status;

  /// 검색어: ISBN이 있으면 그것만(판이 정확하다), 없으면 제목 + 저자
  String get query => isbn ?? [title, author].where((s) => s.isNotEmpty).join(' ');

  /// 목록에 보일 이름
  String get label => title.isNotEmpty ? (author.isNotEmpty ? '$title · $author' : title) : (isbn ?? '');
}

/// 읽은 결과: 줄들 + 찾은 열(머리 이름, 없으면 null) + 실패 사유(encoding · empty · format)
class ImportParse {
  const ImportParse({this.rows = const [], this.columns = const {}, this.duplicates = 0, this.error});
  final List<ImportRow> rows;
  final Map<String, String> columns;

  /// 같은 ISBN이 두 번 이상 나와 뺀 줄 수
  final int duplicates;
  final String? error;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_\-.()\[\]/·:]'), '');

// 머리 이름(정규화한 값에 들어 있으면 그 열). 앞쪽이 더 확실한 이름
const _isbnNames = ['isbn13', 'isbn', '국제표준도서번호', '바코드'];
const _titleNames = ['책제목', '도서제목', '도서명', '책이름', '제목', '서명', 'booktitle', 'title', '책'];
// 'author'가 'authors'보다 먼저: 굿리즈의 'Additional Authors'보다 앞 열 'Author'를 잡는다
const _authorNames = ['저자', '지은이', '작가', '글쓴이', 'author', 'writer'];
const _publisherNames = ['출판사', '펴낸곳', '발행처', 'publisher'];
const _statusNames = ['읽기상태', '독서상태', '상태', 'status', 'shelf', 'exclusiveshelf'];

int? _find(List<String> head, List<String> names, Set<int> taken) {
  for (final n in names) {
    for (var i = 0; i < head.length; i++) {
      if (taken.contains(i)) continue;
      final h = _norm(head[i]);
      // '책'처럼 짧은 이름은 같을 때만(‘책 정보 링크’ 같은 열을 제목으로 잡지 않게)
      if (n.length <= 2 ? h == n : h.contains(n)) return i;
    }
  }
  return null;
}

/// 읽기 상태 글자 → 상태(모르면 null: 가져올 때 '읽고 싶은'으로)
ReadStatus? statusOf(String s) {
  final t = _norm(s);
  if (t.isEmpty) return null;
  // 'reading'·'to-read'가 'read'에 걸리지 않게 읽는 중·읽고 싶은을 먼저
  if (RegExp('읽는중|읽고있|reading|current').hasMatch(t)) return ReadStatus.reading;
  if (RegExp('읽고싶|찜|want|toread|wish').hasMatch(t)) return ReadStatus.want;
  if (RegExp('멈춤|중단|쉬는|보류|paused|abandon|dnf').hasMatch(t)) return ReadStatus.paused;
  if (RegExp(r'다읽|읽었|읽음|완독|^read$|finished|done').hasMatch(t)) return ReadStatus.read;
  return null;
}

/// 엑셀 칸 → 글자. 숫자로 저장된 ISBN(9788936434120.0)은 소수점 없이
String _cell(Data? d) {
  final v = d?.value;
  return switch (v) {
    null => '',
    IntCellValue(:final value) => '$value',
    DoubleCellValue(:final value) => value == value.roundToDouble() && value.abs() < 1e15 ? value.toStringAsFixed(0) : '$value',
    TextCellValue() => v.value.toString(),
    _ => v.toString(),
  }
      .trim();
}

/// 파일 내용(바이트)과 이름으로 표를 읽는다. CSV는 UTF-8(엑셀 'CSV UTF-8')·UTF-16만 읽는다(EUC-KR이면 encoding 오류)
List<List<String>>? readTable(List<int> bytes, String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  if (ext == 'xlsx' || ext == 'xlsm') {
    final book = Excel.decodeBytes(bytes);
    for (final sheet in book.tables.values) {
      final rows = [for (final r in sheet.rows) r.map(_cell).toList()];
      if (rows.any((r) => r.any((c) => c.isNotEmpty))) return rows;
    }
    return const [];
  }
  String text;
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    text = String.fromCharCodes([for (var i = 2; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8)]);
  } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    text = String.fromCharCodes([for (var i = 2; i + 1 < bytes.length; i += 2) (bytes[i] << 8) | bytes[i + 1]]);
  } else {
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
  if (text.startsWith('﻿')) text = text.substring(1);
  final table = Csv(fieldDelimiter: ext == 'tsv' ? '\t' : ',', autoDetect: ext != 'tsv').decode(text);
  return [for (final r in table) r.map((c) => '${c ?? ''}'.trim()).toList()];
}

/// 표 → 가져올 줄들
ImportParse parseTable(List<List<String>> table) {
  final rows = [for (final r in table) if (r.any((c) => c.isNotEmpty)) r];
  if (rows.isEmpty) return const ImportParse(error: 'empty');
  // 머리줄: 앞 다섯 줄 중 제목·ISBN 머리 이름이 처음 나오는 줄
  var headAt = -1;
  int? ci, ct, ca, cp, cs;
  for (var r = 0; r < rows.length && r < 5; r++) {
    final taken = <int>{};
    final i = _find(rows[r], _isbnNames, taken);
    if (i != null) taken.add(i);
    final t = _find(rows[r], _titleNames, taken);
    if (i == null && t == null) continue;
    if (t != null) taken.add(t);
    final a = _find(rows[r], _authorNames, taken);
    if (a != null) taken.add(a);
    final p = _find(rows[r], _publisherNames, taken);
    if (p != null) taken.add(p);
    final s = _find(rows[r], _statusNames, taken);
    headAt = r;
    (ci, ct, ca, cp, cs) = (i, t, a, p, s);
    break;
  }
  final columns = <String, String>{};
  if (headAt < 0) {
    // 머리줄이 없으면 내용으로: 칸 대부분이 ISBN인 열 = ISBN, 그 밖에 글자가 가장 많은 열 = 제목
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    for (var c = 0; c < width; c++) {
      final cells = [for (final r in rows) if (c < r.length && r[c].isNotEmpty) r[c]];
      if (cells.isNotEmpty && cells.where((x) => isbn13Of(x) != null).length >= cells.length * 0.6) {
        ci = c;
        break;
      }
    }
    var best = 0;
    for (var c = 0; c < width; c++) {
      if (c == ci) continue;
      final n = [for (final r in rows) if (c < r.length && r[c].isNotEmpty && isbn13Of(r[c]) == null && double.tryParse(r[c]) == null) 1].length;
      if (n > best) (best, ct) = (n, c);
    }
    if (ci == null && ct == null) return const ImportParse(error: 'format');
  } else {
    final h = rows[headAt];
    if (ci != null) columns['isbn'] = h[ci];
    if (ct != null) columns['title'] = h[ct];
    if (ca != null) columns['author'] = h[ca];
    if (cp != null) columns['publisher'] = h[cp];
    if (cs != null) columns['status'] = h[cs];
  }
  String at(List<String> r, int? c) => c != null && c < r.length ? r[c] : '';
  final out = <ImportRow>[];
  final seen = <String>{};
  var dup = 0;
  for (var r = headAt + 1; r < rows.length; r++) {
    final row = rows[r];
    final isbn = isbn13Of(at(row, ci));
    final title = at(row, ct);
    if (isbn == null && title.isEmpty) continue;
    if (isbn != null && !seen.add(isbn)) {
      dup++;
      continue;
    }
    out.add(ImportRow(
      line: table.indexOf(row) + 1,
      isbn: isbn,
      title: title,
      author: at(row, ca),
      publisher: at(row, cp),
      status: statusOf(at(row, cs)),
    ));
  }
  return ImportParse(rows: out, columns: columns, duplicates: dup, error: out.isEmpty ? 'empty' : null);
}

/// 파일 바이트 → 가져올 줄들(읽지 못하면 error: encoding · empty · format)
ImportParse parseBookList(List<int> bytes, String fileName) {
  final ext = fileName.toLowerCase().split('.').last;
  if (!const ['csv', 'tsv', 'txt', 'xlsx', 'xlsm'].contains(ext)) return const ImportParse(error: 'format');
  List<List<String>>? table;
  try {
    table = readTable(bytes, fileName);
  } catch (_) {
    return const ImportParse(error: 'format');
  }
  if (table == null) return const ImportParse(error: 'encoding');
  return parseTable(table);
}
