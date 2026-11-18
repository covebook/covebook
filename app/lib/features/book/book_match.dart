// 검색 결과 고르기·내 서재에 있는지(순수 계산, 시험용). 목록 가져오기·바코드·검색 결과 줄이 같이 쓴다
library;

import '../../domain/book_list_import.dart' show ImportRow, isbn13Of;
import '../../domain/library.dart' show Library;
import '../../services/book_search.dart' show BookCandidate;

/// 제목 비교용: 괄호 속 부제·띄어쓰기·문장 부호를 뺀 소문자
String normTitle(String s) => s.toLowerCase().replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '').replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

String _normName(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');

/// 같은 책으로 볼 서재 책 id(숨긴 책은 빼고): ISBN이 같거나, ISBN이 없으면 제목·첫 저자가 같은 책
String? ownedBookId(Library lib, BookCandidate c) {
  final code = c.isbn13 == null ? null : isbn13Of(c.isbn13!);
  final title = normTitle(c.title);
  final author = c.authors.isEmpty ? '' : _normName(c.authors.first);
  for (final b in lib.books.values) {
    if (b.hiddenAt != null) continue;
    final e = lib.editions[b.editionId];
    if (e == null) continue;
    if (code != null) {
      if (e.isbn13 != null && isbn13Of(e.isbn13!) == code) return b.id;
      continue;
    }
    if (title.isNotEmpty && normTitle(e.title) == title && (author.isEmpty || (e.authors.isNotEmpty && _normName(e.authors.first) == author))) return b.id;
  }
  return null;
}

/// 가져오기 한 줄에 맞는 검색 결과: ISBN이 있으면 같은 ISBN(검색 결과가 한 권뿐이면 그 책), 없으면 제목이 같거나 겹치는 책 중 저자·출판사가 맞는 쪽
BookCandidate? matchCandidate(ImportRow row, List<BookCandidate> items) {
  if (items.isEmpty) return null;
  if (row.isbn != null) {
    for (final c in items) {
      if (c.isbn13 != null && isbn13Of(c.isbn13!) == row.isbn) return c;
    }
    return items.length == 1 ? items.first : null;
  }
  final t = normTitle(row.title);
  if (t.isEmpty) return null;
  final a = _normName(row.author);
  final p = _normName(row.publisher);
  BookCandidate? best;
  var bestScore = 0;
  for (final c in items) {
    final ct = normTitle(c.title);
    var score = ct == t ? 3 : (ct.isNotEmpty && (ct.contains(t) || t.contains(ct)) ? 2 : 0);
    if (score == 0) continue;
    if (a.isNotEmpty && c.authors.any((x) => _normName(x).contains(a) || a.contains(_normName(x)))) score += 2;
    if (p.isNotEmpty && c.publisher != null && _normName(c.publisher!).contains(p)) score += 1;
    if (score > bestScore) (best, bestScore) = (c, score);
  }
  return best;
}

/// 결과 줄의 출판사 · 연도(둘 다 없으면 null)
String? publisherLine(BookCandidate c) {
  final year = RegExp(r'\d{4}').firstMatch(c.publishedAt ?? '')?.group(0);
  final parts = [if (c.publisher != null && c.publisher!.trim().isNotEmpty) c.publisher!.trim(), ?year];
  return parts.isEmpty ? null : parts.join(' · ');
}
