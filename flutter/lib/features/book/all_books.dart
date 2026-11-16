// 전체 책 목록(지금 앱 features/book/all-books.ts): 등록한 모든 책(책장에 놓인 책 + 책장에 없는 책)을 검색·읽기 상태·책장에 없는 책·완독한 해로
// 거르고 정렬한다. 책 정보는 서재 한 곳에만 있고, 책장 배치는 같은 책 ID로 따로 본다. 숨긴 책(연도 책장에 남긴 책)은 목록에 없다
library;

import '../../domain/title_layout.dart' show compareKoTitle;
import '../../domain/layout.dart';
import '../../domain/layout_engine.dart' show BookMap;
import '../../domain/library.dart';
import '../../domain/reading.dart' show withJosa;
import '../../domain/types.dart';

enum AllBooksSort { recent, title }

const sortLabel = {AllBooksSort.recent: '최근순', AllBooksSort.title: '제목순'};

typedef AllBooksRow = ({Book book, bool onShelf});

/// 필터 시트에서 건 조건 이름(걸린 것만). 기본(모든 책·최근순)이면 빈 목록: 조건 줄을 보이지 않는다(2026-11-16 메뉴 개편 지시)
List<String> filterConditions({bool offShelfOnly = false, int? year, AllBooksSort sort = AllBooksSort.recent}) => [
      if (offShelfOnly) '책장에 없는 책',
      if (year != null) '$year년 완독',
      if (sort != AllBooksSort.recent) sortLabel[sort]!,
    ];

/// 화면에 보이는 책(숨긴 책 빼고)
Iterable<MyBook> shownBooks(Library lib) => lib.books.values.where((b) => b.hiddenAt == null);

List<AllBooksRow> listAllBooks(Library lib, BookMap books, ShelfLayout layout,
    {String q = '', ReadStatus? status, bool offShelfOnly = false, AllBooksSort sort = AllBooksSort.recent, int? year}) {
  final t = q.trim().toLowerCase();
  final rows = <AllBooksRow>[];
  for (final b in shownBooks(lib)) {
    final book = books[b.id];
    if (book == null) continue;
    final onShelf = placementOf(layout, b.id) != null;
    if (offShelfOnly && onShelf) continue;
    if (status != null && b.status != status) continue;
    if (year != null && finishedYear(lib, b.id) != year) continue;
    if (t.isNotEmpty && !'${book.title} ${book.author ?? ''}'.toLowerCase().contains(t)) continue;
    rows.add((book: book, onShelf: onShelf));
  }
  if (sort == AllBooksSort.title) {
    rows.sort((a, b) => compareKoTitle(a.book.title, b.book.title));
  } else {
    rows.sort((a, b) {
      final c = lib.books[b.book.id]!.createdAt.compareTo(lib.books[a.book.id]!.createdAt);
      return c != 0 ? c : compareKoTitle(a.book.title, b.book.title);
    });
  }
  return rows;
}

/// 책마다 남긴 메모(독서 기록·갈피의 메모, 최근 순)
typedef BookMemo = ({String id, String text, String at, bool bookmark});

Map<String, List<BookMemo>> memosByBook(Library lib) {
  final out = <String, List<BookMemo>>{};
  void add(String? bookId, BookMemo m) {
    if (bookId == null || m.text.isEmpty) return;
    (out[bookId] ??= []).add(m);
  }

  for (final s in lib.sessions.values) {
    add(s.myBookId, (id: s.id, text: s.memo?.trim() ?? '', at: sessionDay(s), bookmark: false));
  }
  for (final m in lib.bookmarks.values) {
    add(m.myBookId, (id: m.id, text: m.memo?.trim() ?? '', at: m.createdAt, bookmark: true));
  }
  for (final list in out.values) {
    list.sort((a, b) => b.at.compareTo(a.at));
  }
  return out;
}

typedef DeleteSummary = ({int rounds, int marks, int essays, int sessions, num ms});

/// 책을 지우면 함께 지워지는 것(갈피·긴 감상·독서 회차)과 남는 것(독서 시간 ms: 책 연결만 비워 통계에 남는다)
DeleteSummary deleteSummary(Library lib, Iterable<String> ids) {
  final set = ids.toSet();
  final sessions = [for (final s in lib.sessions.values) if (s.myBookId != null && set.contains(s.myBookId)) s];
  return (
    rounds: set.fold(0, (a, id) => a + roundsOf(lib, id).length),
    marks: set.fold(0, (a, id) => a + bookmarksOf(lib, id).length),
    essays: lib.essays.values.where((e) => set.contains(e.myBookId)).length,
    sessions: sessions.length,
    ms: sessions.fold<num>(0, (a, s) => a + s.durationMs),
  );
}

/// 받침이 있으면 '과', 없으면 '와'(갈피 2개와 · 감상 1편과)
String _wa(String word) {
  final c = word.isEmpty ? 0 : word.codeUnitAt(word.length - 1);
  return c >= 0xAC00 && c <= 0xD7A3 && (c - 0xAC00) % 28 != 0 ? '과' : '와';
}

/// 삭제 확인 문구: 한 줄에 한 문장(함께 지워지는 것 → 남는 것 → 되돌릴 수 없음). 0개인 것은 뺀다.
/// 남는 독서 시간은 얼마가 어떻게 남는지 쓴다(2026-11-16 QA 현우 F4: '읽은 기록 1회도 지워져요'와 '독서 시간은 통계에 남아요'가 함께 나와
/// 무엇이 남는지 헷갈렸다). 지워지는 회차는 '독서 회차'로(백업 숫자와 같은 말)
String deleteNote(DeleteSummary n) {
  final parts = [if (n.marks > 0) '갈피 ${n.marks}개', if (n.essays > 0) '감상 ${n.essays}편', if (n.rounds > 0) '독서 회차 ${n.rounds}회'];
  final gone = parts.length <= 1 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')}${_wa(parts[parts.length - 2])} ${parts.last}';
  final kept = n.ms >= 60000 ? formatDuration(n.ms) : formatDurationPrecise(n.ms);
  return [
    if (gone.isNotEmpty) '$gone도 지워져요.',
    if (n.sessions > 0) '독서 시간 ${withJosa(kept, '은', '는')} 책 없이 읽은 시간으로 통계에 남아요.',
    '되돌릴 수 없어요.',
  ].join('\n');
}

/// 같은 판(판본)을 두 권 이상 넣은 책: 책 id → '소장본 N'(넣은 차례). 한 권뿐인 판은 없다(2026-11-15 QA: 별도 소장본 두 권이 목록에서 같아 보였다)
Map<String, String> copyLabels(Library lib) {
  final byEdition = <String, List<MyBook>>{};
  for (final b in shownBooks(lib)) {
    (byEdition[b.editionId] ??= []).add(b);
  }
  final out = <String, String>{};
  for (final list in byEdition.values) {
    if (list.length < 2) continue;
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final (i, b) in list.indexed) {
      out[b.id] = '소장본 ${i + 1}';
    }
  }
  return out;
}
