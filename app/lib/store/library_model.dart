// 서재 한 벌을 화면들이 함께 본다(지금 앱 store/library-store.ts의 읽기·고치기 일부).
// 고치면 화면은 바로 바뀌고, 항목 행과 동기화 대기 기록은 한 트랜잭션으로 차례대로 저장한다(누른 순서대로)
library;

import 'package:flutter/foundation.dart';

import '../db/library_write.dart';
import '../domain/binding_draft.dart';
import '../domain/color.dart';
import '../domain/cover_url.dart';
import '../domain/library.dart';
import '../domain/reading.dart';
import '../domain/session_edit.dart';
import 'library_read.dart';
import 'first_shelf.dart';

const Object _keep = Object();

class LibraryModel extends ChangeNotifier {
  LibraryModel._();
  static final instance = LibraryModel._();

  /// 화면이 보는 서재(저장 중인 고치기까지 들어 있다)
  Library get lib => _lib;

  /// 서재를 통째로 바꾼다(기기에서 읽은 값 · 시험): 기기에 있는 값으로 본다
  set lib(Library l) => _lib = _saved = l;
  Library _lib = Library();

  /// 기기 DB에 있는 서재(저장이 끝난 고치기까지). 저장이 실패하면 그 고치기의 항목을 이 값으로 되돌린다
  Library _saved = Library();
  bool loaded = false;
  Object? error;
  Future<void>? _loading;
  Future<void> _writes = Future.value();

  /// 서재 변경을 기기에 쓴다(시험에서 성공 · 실패를 바꿔 끼운다)
  @visibleForTesting
  Future<void> Function(List<LocalChange> changes) writeChanges = applyLocalChanges;

  // 예시 서재(빈 서재에만 넣는다)를 다 넣은 뒤에 읽는다
  Future<void> load() => _loading ??= prepareFirstShelf().then((_) => loadFullLibrary()).then((l) {
        lib = l;
        loaded = true;
        notifyListeners();
      });

  /// 시험: 기기 DB 없이 이 서재를 읽은 것으로(책 추가 · 갈피 남기기처럼 먼저 읽기를 기다리는 고치기도 바로 한다)
  @visibleForTesting
  void useForTest(Library l) {
    lib = l;
    loaded = true;
    error = null;
    // 저장 차례도 새로(위젯 시험은 시험 안에서 불러야 저장이 그 시험의 시계로 돈다)
    _loading = Future.value();
    _writes = Future.value();
  }

  /// 다시 읽기(다른 곳에서 DB를 바꾼 뒤)
  Future<void> reload() {
    _loading = null;
    return load();
  }

  /// 화면은 바로 바꾸고 저장은 차례대로. 저장하지 못하면(트랜잭션이라 DB는 그대로) 화면도 DB 값으로 되돌린 뒤 던진다
  /// (2026-11-20 QA: 지우기가 실패해 '삭제하지 못했어요'가 떠도 화면에서는 책 · 독서 기록 · 갈피가 사라져 있다가 앱을 다시 켜면 돌아왔다)
  Future<void> _commit(Library next, List<LocalChange> changes) {
    _lib = next;
    notifyListeners();
    final w = _writes.catchError((_) {}).then((_) => writeChanges(changes));
    _writes = w.then((_) {
      error = null;
      _saved = _applied(_saved, changes);
    }, onError: (Object e) {
      error = e;
      _lib = _restored(_lib, _saved, changes);
      notifyListeners();
      throw e;
    });
    return _writes;
  }

  /// 진행 중인 저장이 끝날 때까지(동기화가 DB를 읽기 전에)
  Future<void> flushPending() => _writes.catchError((_) {});

  /// 서버에서 받은 변경을 지금 서재에 얹는다(올릴 변경으로 표시하지 않는다, 지금 앱 applyRemote).
  /// 합친 뒤 저장 사이에 바뀐 다른 항목을 잃지 않게, 받은 항목만 지금 서재에 덮어쓴다
  Future<void> applyRemote(List<({LibKind kind, Object item, String id})> writes, List<({LibKind kind, String id})> erases) async {
    if (writes.isEmpty && erases.isEmpty) return;
    final ed = {...lib.editions}, bk = {...lib.books}, rd = {...lib.rounds}, ss = {...lib.sessions}, bm = {...lib.bookmarks}, bd = {...lib.bindings}, es = {...lib.essays};
    Map<String, Object> table(LibKind k) => switch (k) {
          LibKind.editions => ed,
          LibKind.books => bk,
          LibKind.rounds => rd,
          LibKind.sessions => ss,
          LibKind.bookmarks => bm,
          LibKind.bindings => bd,
          LibKind.essays => es,
        };
    for (final w in writes) {
      table(w.kind)[w.id] = w.item;
    }
    for (final e in erases) {
      table(e.kind).remove(e.id);
    }
    _lib = Library(editions: ed, books: bk, rounds: rd, sessions: ss, bookmarks: bm, bindings: bd, essays: es);
    notifyListeners();
    final changes = [
      for (final w in writes) LocalChange.put(w.kind, w.id, w.item, ''),
      for (final e in erases) LocalChange.delete(e.kind, e.id, ''),
    ];
    final done = _writes.catchError((_) {}).then((_) => applyRemoteChanges(changes)).then((_) {
      _saved = _applied(_saved, changes);
    }, onError: (Object e) {
      // 받은 항목을 쓰지 못했으면 화면도 DB 값으로(다음 동기화가 다시 받는다)
      _lib = _restored(_lib, _saved, changes);
      notifyListeners();
      throw e;
    });
    _writes = done.catchError((_) {});
    await done;
  }

  Library _withBookmarks(Map<String, Bookmark> bookmarks) =>
      lib.copy(bookmarks: bookmarks);

  /// 아껴둔 갈피(아껴둔 순서)
  List<String> get savedIds => ([for (final m in lib.bookmarks.values) if (m.savedAt != null) m]..sort((a, b) => a.savedAt!.compareTo(b.savedAt!))).map((m) => m.id).toList();

  /// 바뀐 항목만 골라 저장할 변경으로(지금 앱 commit의 비교와 같다: 같은 객체면 그대로)
  List<LocalChange> _diff(Library next, String at) {
    final out = <LocalChange>[];
    void kind<T extends Object>(LibKind k, Map<String, T> a, Map<String, T> b, String Function(T) updated) {
      for (final e in b.entries) {
        if (!identical(a[e.key], e.value)) out.add(LocalChange.put(k, e.key, e.value, updated(e.value)));
      }
      for (final id in a.keys) {
        if (!b.containsKey(id)) out.add(LocalChange.delete(k, id, at));
      }
    }

    kind<Edition>(LibKind.editions, lib.editions, next.editions, (x) => x.updatedAt);
    kind<MyBook>(LibKind.books, lib.books, next.books, (x) => x.updatedAt);
    kind<Round>(LibKind.rounds, lib.rounds, next.rounds, (x) => x.updatedAt);
    kind<Session>(LibKind.sessions, lib.sessions, next.sessions, (x) => x.updatedAt);
    kind<Bookmark>(LibKind.bookmarks, lib.bookmarks, next.bookmarks, (x) => x.updatedAt);
    kind<Binding>(LibKind.bindings, lib.bindings, next.bindings, (x) => x.updatedAt);
    kind<Essay>(LibKind.essays, lib.essays, next.essays, (x) => x.updatedAt);
    return out;
  }

  /// 새 서재로 바꾸고 바뀐 항목을 저장한다
  Future<void> commitLib(Library next) {
    final changes = _diff(next, nowIso());
    if (changes.isEmpty) return Future.value();
    return _commit(next, changes);
  }

  /// 독서 기록 저장(회차 확보·쪽 옮기기 포함). 같은 id로 다시 저장해도 하나.
  /// 서재를 다 읽은 뒤에 계산한다(읽기 전이면 책이 없는 것으로 보여 책 연결이 빠진다)
  Future<String> addSession(SessionInput input) async {
    await load();
    final r = addSessionTo(lib, input, nowIso());
    await commitLib(r.lib);
    return r.id;
  }

  /// 책 고치기(별점·한 줄 감상·현재 쪽·갈피 색). null을 주면 비운다
  Future<void> updateBook(String id, {Object? rating = _keep, Object? note = _keep, Object? currentPage = _keep, Object? ribbonColor = _keep}) {
    final b = lib.books[id];
    if (b == null) return Future.value();
    final next = b.patch(rating: rating, note: note, currentPage: currentPage, ribbonColor: ribbonColor, updatedAt: nowIso());
    return commitLib(lib.copy(books: {...lib.books, id: next}));
  }

  /// 읽기 상태 바꾸기(같은 상태면 그대로)
  Future<void> setStatus(String id, ReadStatus status) => commitLib(applyStatus(lib, id, status, nowIso()));

  /// 다시 읽기: 지난 회차는 그대로 두고 새 회차(진도 0쪽부터)
  Future<void> reread(String id) => commitLib(rereadRound(lib, id, nowIso()));

  /// 회차 날짜 고치기(null을 주면 비운다)
  Future<void> updateRound(String roundId, {Object? startedAt = _keep, Object? finishedAt = _keep}) {
    final r = lib.rounds[roundId];
    if (r == null) return Future.value();
    return commitLib(lib.copy(rounds: {...lib.rounds, roundId: r.copyWith(startedAt: startedAt, finishedAt: finishedAt, updatedAt: nowIso())}));
  }

  /// 책 추가(지금 앱 addBook): 판본 + 내 책 + 장정(고른 장정, 없으면 추천 장정 그대로) + 읽기 상태에 맞는 회차. 새 책 id를 돌려준다(저장까지 기다린다)
  Future<String> addBook({
    required String title,
    required List<String> authors,
    required String source,
    required ReadStatus status,
    BookArtParams? art,
    String? publisher,
    String? publishedAt,
    String? isbn13,
    num? pageCount,
    num? widthMm,
    num? heightMm,
    String? category,
    String? seriesTitle,
    String? coverUri,
    String? coverSource,
    String? sourceName,
    String? link,
    String? productId,
    BindingDraft? binding,
  }) async {
    await load();
    final t = nowIso();
    final e = Edition(
      id: newId('ed'),
      title: title,
      authors: authors,
      source: source,
      createdAt: t,
      updatedAt: t,
      isbn13: isbn13,
      publisher: publisher,
      publishedAt: publishedAt,
      pageCount: pageCount,
      widthMm: widthMm,
      heightMm: heightMm,
      coverUri: coverUri,
      coverSource: coverSource,
      category: category,
      seriesTitle: seriesTitle,
      sourceName: sourceName,
      productId: productId,
      link: link,
      art: art,
    );
    final id = newId('bk');
    final bd = _bindingOf(
        id,
        binding ??
            BindingDraft(spineColor: art?.baseColor ?? '#8F6E55', motif: art?.motifId ?? 'none', inkColor: art?.inkColor, accentColor: art?.accentColor, layout: art?.layoutVariant),
        null,
        t);
    final b = MyBook(id: id, editionId: e.id, status: ReadStatus.want, bindingId: bd.id, createdAt: t, updatedAt: t);
    var next = lib.copy(editions: {...lib.editions, e.id: e}, books: {...lib.books, id: b}, bindings: {...lib.bindings, bd.id: bd});
    if (status != ReadStatus.want) next = applyStatus(next, id, status, t);
    await commitLib(next);
    return id;
  }
  /// 책 꾸미기 저장(지금 앱 setBinding + 갈피 색): 장정(binding, 고쳤을 때만. 그 책의 장정을 고른 값으로, 없으면 새로. 재질·표지 그림이 비면 예전 값도 지운다)과
  /// 갈피 색(ribbonColor, 바꿨을 때만, null = 표지에서 고른 색)을 한 번에(한 트랜잭션)
  Future<void> setBookLook(String myBookId, {BindingDraft? binding, Object? ribbonColor = _keep}) {
    var b = lib.books[myBookId];
    if (b == null) return Future.value();
    final t = nowIso();
    var bindings = lib.bindings;
    if (binding != null) {
      final bd = _bindingOf(myBookId, binding, b.bindingId == null ? null : lib.bindings[b.bindingId], t);
      bindings = {...bindings, bd.id: bd};
      b = b.patch(bindingId: bd.id, updatedAt: t);
    }
    if (!identical(ribbonColor, _keep)) b = b.patch(ribbonColor: ribbonColor, updatedAt: t);
    return commitLib(lib.copy(bindings: bindings, books: {...lib.books, myBookId: b}));
  }


  Binding _bindingOf(String myBookId, BindingDraft v, Binding? old, String t) => Binding(
        id: old?.id ?? newId('bd'),
        myBookId: myBookId,
        spineColor: v.spineColor,
        motif: v.motif,
        source: v.source,
        status: old?.status ?? 'ready',
        seed: v.seed,
        createdAt: old?.createdAt ?? t,
        updatedAt: t,
        inkColor: v.inkColor ?? old?.inkColor,
        accentColor: v.accentColor ?? old?.accentColor,
        layout: v.layout ?? old?.layout,
        material: v.material,
        coverArtUri: old?.coverArtUri,
        coverArtId: v.coverArtId,
        spineArtUri: old?.spineArtUri,
      );

  /// 책 정보 고치기(지금 앱 updateEdition): 판본 값을 통째로 바꾼다(비운 값은 '확인 전')
  Future<void> updateEdition(String editionId, {required String title, required List<String> authors, String? publisher, String? publishedAt, String? isbn13, num? pageCount, num? widthMm, num? heightMm, String? coverUri, String? coverSource}) {
    final e = lib.editions[editionId];
    if (e == null) return Future.value();
    final next = Edition(
      id: e.id,
      title: title,
      authors: authors,
      source: e.source,
      createdAt: e.createdAt,
      updatedAt: nowIso(),
      isbn13: isbn13,
      publisher: publisher,
      publishedAt: publishedAt,
      pageCount: pageCount,
      widthMm: widthMm,
      heightMm: heightMm,
      coverUri: coverUri,
      coverSource: coverSource,
      category: e.category,
      seriesTitle: e.seriesTitle,
      sourceName: e.sourceName,
      productId: e.productId,
      link: e.link,
      art: e.art,
    );
    return commitLib(lib.copy(editions: {...lib.editions, editionId: next}));
  }

  /// 갈피 남기기(지금 앱 addBookmark): 새 id를 돌려준다. 저장이 끝날 때까지 기다린다(실패하면 던진다: 화면은 적은 내용을 그대로 둔다)
  Future<String> addBookmark({required String myBookId, required String text, num? page, String? memo, String? photoUri, num? photoRatio, String? sessionId, num? boardX, num? boardY, num? boardRot}) async {
    await load();
    final t = nowIso();
    final m = Bookmark(
      id: newId('bm'),
      myBookId: myBookId,
      text: text,
      createdAt: t,
      updatedAt: t,
      page: page,
      memo: memo,
      photoUri: photoUri,
      photoRatio: photoRatio,
      sessionId: sessionId,
      boardX: boardX,
      boardY: boardY,
      boardRot: boardRot,
    );
    await _commit(_withBookmarks({...lib.bookmarks, m.id: m}), [LocalChange.put(LibKind.bookmarks, m.id, m, t)]);
    return m.id;
  }

  /// 갈피 고치기
  /// 보드에서 갈피 한 장을 옮기거나 폭을 바꿨다(지금 앱 updateBoard). 아직 자동 자리인 다른 갈피는 지금 자리를 함께 적어 둔다
  /// (그 갈피들이 이 갈피의 칸을 이어받아 밀려 오지 않게). 함께 적는 갈피는 1ms 앞선 때로 적어 '나중에 만진 갈피가 위' 순서를 지킨다
  Future<void> updateBoard(List<({String id, double x, double y, double rot})> spots, String id, {required double x, required double y, required double rot, double? w}) {
    final m = lib.bookmarks[id];
    if (m == null) return Future.value();
    final t = nowIso();
    final before = DateTime.parse(t).subtract(const Duration(milliseconds: 1)).toUtc().toIso8601String();
    final bookmarks = {...lib.bookmarks};
    for (final s in spots) {
      final o = bookmarks[s.id];
      if (o != null && s.id != id && o.boardX == null) bookmarks[s.id] = o.withBoard(s.x, s.y, s.rot, before);
    }
    bookmarks[id] = m.withBoard(x, y, rot, t, w: w);
    return commitLib(lib.copy(bookmarks: bookmarks));
  }

  /// 독서 기록 고치기(지금 앱 updateSession): 준 필드만
  Future<void> updateSession(String id, SessionPatch patch) => commitLib(updateSessionIn(lib, id, patch, nowIso()));

  /// 독서 기록 지우기(연결된 갈피는 연결만 비운다)
  Future<void> deleteSession(String id) => commitLib(deleteSessionIn(lib, id, nowIso()));

  Future<void> updateBookmark(String id, {required String text, Object? page = _keep, Object? memo = _keep, Object? photoUri = _keep, Object? photoRatio = _keep}) {
    final m = lib.bookmarks[id];
    if (m == null) return Future.value();
    final next = m.edit(text: text, page: page, memo: memo, photoUri: photoUri, photoRatio: photoRatio, updated: nowIso());
    return commitLib(lib.copy(bookmarks: {...lib.bookmarks, id: next}));
  }

  // ---------- 긴 감상(2026-11-16 기록 > 감상, Flutter만) ----------

  /// 책의 긴 감상(최근에 쓴 순). bookId가 없으면 모든 책(갈피 목록처럼 책이 있는 것만, 숨긴 책 것도 남긴다)
  List<Essay> essaysOf([String? bookId]) {
    final list = [
      for (final e in lib.essays.values)
        if ((bookId == null || e.myBookId == bookId) && lib.books[e.myBookId] != null) e,
    ]..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  /// 긴 감상 쓰기: 새 id를 돌려준다. 저장이 끝날 때까지 기다린다(실패하면 던진다: 화면은 쓴 글을 그대로 둔다)
  Future<String> addEssay({required String myBookId, String? title, required String body}) async {
    await load();
    final t = nowIso();
    final e = Essay(id: newId('es'), myBookId: myBookId, title: (title ?? '').trim().isEmpty ? null : title!.trim(), body: body, createdAt: t, updatedAt: t);
    await _commit(lib.copy(essays: {...lib.essays, e.id: e}), [LocalChange.put(LibKind.essays, e.id, e, t)]);
    return e.id;
  }

  /// 긴 감상 고치기(제목을 비우면 제목 없이)
  Future<void> updateEssay(String id, {String? title, required String body}) {
    final e = lib.essays[id];
    if (e == null) return Future.value();
    final t = nowIso();
    final next = e.edit(title: title, body: body, updated: t);
    return _commit(lib.copy(essays: {...lib.essays, id: next}), [LocalChange.put(LibKind.essays, id, next, t)]);
  }

  /// 긴 감상 지우기
  Future<void> deleteEssay(String id) {
    if (!lib.essays.containsKey(id)) return Future.value();
    final t = nowIso();
    return _commit(lib.copy(essays: {...lib.essays}..remove(id)), [LocalChange.delete(LibKind.essays, id, t)]);
  }

  /// 갈피 지우기
  Future<void> deleteBookmark(String id) {
    if (!lib.bookmarks.containsKey(id)) return Future.value();
    return commitLib(lib.copy(bookmarks: {...lib.bookmarks}..remove(id)));
  }

  // ---------- 책 지우기·숨기기(지금 앱 library-store deleteBook·unhideBook·hiddenBooks) ----------

  /// 숨긴 책(연도 책장에 있어 지우는 대신 숨긴 책), 숨긴 순서
  List<MyBook> get hiddenBooks => [for (final b in lib.books.values) if (b.hiddenAt != null) b]..sort((a, b) => a.hiddenAt!.compareTo(b.hiddenAt!));

  /// 책 지우기. 연도 책장(archived)에 있는 책은 지우지 않고 숨긴다(장정·회차·갈피·독서 기록 연결이 그대로 남는다).
  /// 지우면 장정·회차·갈피·긴 감상도 지우고, 독서 기록은 책 연결만 비워 통계에 남긴다. 같은 판본을 쓰는 책이 없으면 판본도 지운다
  Future<void> deleteBook(String id, {required bool archived}) {
    final b = lib.books[id];
    if (b == null) return Future.value();
    final t = nowIso();
    if (archived) return commitLib(lib.copy(books: {...lib.books, id: b.patch(hiddenAt: t, updatedAt: t)}));
    final books = {...lib.books}..remove(id);
    final editions = {...lib.editions};
    if (!books.values.any((o) => o.editionId == b.editionId)) editions.remove(b.editionId);
    final rounds = {...lib.rounds}..removeWhere((_, r) => r.myBookId == id);
    final bookmarks = {...lib.bookmarks}..removeWhere((_, m) => m.myBookId == id);
    final bindings = {...lib.bindings}..removeWhere((_, x) => x.myBookId == id);
    final essays = {...lib.essays}..removeWhere((_, x) => x.myBookId == id);
    final sessions = {
      for (final e in lib.sessions.entries)
        e.key: e.value.myBookId != id
            ? e.value
            : Session(
                id: e.value.id,
                startedAt: e.value.startedAt,
                endedAt: e.value.endedAt,
                durationMs: e.value.durationMs,
                createdAt: e.value.createdAt,
                updatedAt: t,
                startPage: e.value.startPage,
                pagesRead: e.value.pagesRead,
                memo: e.value.memo,
              ),
    };
    return commitLib(Library(editions: editions, books: books, rounds: rounds, sessions: sessions, bookmarks: bookmarks, bindings: bindings, essays: essays));
  }

  /// 숨긴 책을 다시 보이게(숨긴 때만 지운다). 책장 자리는 부르는 쪽이 '책장에 없는 책'으로 넣는다
  Future<void> unhideBook(String id) {
    final b = lib.books[id];
    if (b == null || b.hiddenAt == null) return Future.value();
    return commitLib(lib.copy(books: {...lib.books, id: b.patch(hiddenAt: null, updatedAt: nowIso())}));
  }

  /// 갈피 아껴두기 켜고 끄기
  Future<void> toggleSaved(String id) {
    final m = lib.bookmarks[id];
    if (m == null) return Future.value();
    final t = nowIso();
    final next = m.withSaved(m.savedAt != null ? null : t, t);
    return _commit(_withBookmarks({...lib.bookmarks, id: next}), [LocalChange.put(LibKind.bookmarks, id, next, t)]);
  }
}

/// 저장이 끝난 변경을 얹은 서재(기기 DB에 있는 값을 따라간다)
Library _applied(Library base, List<LocalChange> changes) {
  Map<String, T> on<T extends Object>(LibKind k, Map<String, T> m) {
    Map<String, T>? out;
    for (final c in changes) {
      if (c.kind != k) continue;
      out ??= {...m};
      if (c.deleted) {
        out.remove(c.id);
      } else {
        out[c.id] = c.item! as T;
      }
    }
    return out ?? m;
  }

  return Library(
    editions: on(LibKind.editions, base.editions),
    books: on(LibKind.books, base.books),
    rounds: on(LibKind.rounds, base.rounds),
    sessions: on(LibKind.sessions, base.sessions),
    bookmarks: on(LibKind.bookmarks, base.bookmarks),
    bindings: on(LibKind.bindings, base.bindings),
    essays: on(LibKind.essays, base.essays),
  );
}

/// 저장하지 못한 변경을 되돌린 서재: 그 변경이 넣은(지운) 그대로인 항목만 기기 DB 값(saved)으로 돌린다.
/// 그사이 다른 고치기가 다시 바꾼 항목은 그대로 둔다(그 고치기의 저장이 항목을 통째로 쓴다)
Library _restored(Library cur, Library saved, List<LocalChange> changes) {
  Map<String, T> on<T extends Object>(LibKind k, Map<String, T> now, Map<String, T> was) {
    Map<String, T>? out;
    for (final c in changes) {
      if (c.kind != k) continue;
      final v = now[c.id];
      if (c.deleted ? v != null : !identical(v, c.item)) continue;
      out ??= {...now};
      final old = was[c.id];
      if (old == null) {
        out.remove(c.id);
      } else {
        out[c.id] = old;
      }
    }
    return out ?? now;
  }

  return Library(
    editions: on(LibKind.editions, cur.editions, saved.editions),
    books: on(LibKind.books, cur.books, saved.books),
    rounds: on(LibKind.rounds, cur.rounds, saved.rounds),
    sessions: on(LibKind.sessions, cur.sessions, saved.sessions),
    bookmarks: on(LibKind.bookmarks, cur.bookmarks, saved.bookmarks),
    bindings: on(LibKind.bindings, cur.bindings, saved.bindings),
    essays: on(LibKind.essays, cur.essays, saved.essays),
  );
}

/// 책장 책의 갈피 색(지금 앱 toShelfBook art.ribbon): 고른 색 → 표지에서 뽑은 색 → 무채색이 아닌 책 색
String? ribbonOf(Library lib, String myBookId) {
  final b = lib.books[myBookId];
  if (b == null) return null;
  final picked = b.ribbonColor;
  if (picked != null && picked.isNotEmpty) return picked;
  final accent = coverAccentOf(lib.editions[b.editionId]?.coverUri);
  if (accent != null && accent.isNotEmpty) return accent;
  final theme = themeColorOf(lib, myBookId);
  return isNeutralColor(theme) ? null : theme;
}
