// 읽기(지금 앱 domain/reading-list.ts·library.ts addSessionTo·sessionRound·newId, store/reading-store.ts 순수 규칙, BookPicker recentBookIds를 옮긴 것).
// 같은지는 test/reading_matches_app_test.dart(tool/dump_reading.test.ts가 지금 앱 함수로 뽑은 값)
library;

import 'dart:math' as math;

import 'library.dart';

export 'josa.dart';

// ---------- 읽기 탭 목록 ----------

/// 오늘(기기 날짜, 세션 시작 시각 기준) 저장된 독서 시간: 전체·책마다·책 없이. 지금 재는 시간은 화면이 더한다
class TodayRead {
  const TodayRead(this.total, this.byBook, this.noBook);
  final num total;
  final Map<String, num> byBook;
  final num noBook;
}

TodayRead todayRead(Library lib, String day) {
  final byBook = <String, num>{};
  num total = 0, noBook = 0;
  for (final s in lib.sessions.values) {
    if (sessionDay(s) != day) continue;
    total += s.durationMs;
    if (s.myBookId != null && lib.books[s.myBookId] != null) {
      byBook[s.myBookId!] = (byBook[s.myBookId!] ?? 0) + s.durationMs;
    } else {
      noBook += s.durationMs;
    }
  }
  return TodayRead(total, byBook, noBook);
}

/// 책 없이 읽기 줄을 추가해 둔 표시(설정 readList)
const noBook = '~none';

int _cmp(String a, String b) => a.compareTo(b);

/// 줄에 오르는 책: 넘겨받은 책 → 지금 재는 책 → 마지막으로 읽은 때가 가까운 책 → 읽기 시작한(바뀐) 때가 가까운 책 → 추가해 둔 책(추가한 순서)
List<String> readListIds(Library lib, {required String day, String? activeId, String? focusId, List<String> added = const []}) {
  bool shown(String? id) => id != null && lib.books[id] != null && lib.books[id]!.hiddenAt == null;
  final last = <String, String>{};
  for (final s in lib.sessions.values) {
    if (s.myBookId != null && _cmp(last[s.myBookId!] ?? '', s.startedAt) < 0) last[s.myBookId!] = s.startedAt;
  }
  final todayBy = todayRead(lib, day).byBook;
  final rest = [for (final (i, b) in lib.books.values.indexed) if (shown(b.id) && (b.status == ReadStatus.reading || todayBy.containsKey(b.id))) (i, b)]
    ..sort((x, y) {
      var c = _cmp(last[y.$2.id] ?? '', last[x.$2.id] ?? '');
      if (c == 0) c = _cmp(y.$2.updatedAt, x.$2.updatedAt);
      return c != 0 ? c : x.$1.compareTo(y.$1); // 지금 앱 sort는 안정 정렬
    });
  final out = <String>{};
  for (final id in [focusId, activeId]) {
    if (shown(id)) out.add(id!);
  }
  out.addAll(rest.map((x) => x.$2.id));
  out.addAll(added.where(shown));
  return out.toList();
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// 시간 글자: 공부 타이머처럼 늘 '시:분:초'(0:00:00)
String hms(num ms) {
  final t = math.max(0, (ms / 1000).floor());
  return '${t ~/ 3600}:${_p2((t % 3600) ~/ 60)}:${_p2(t % 60)}';
}

/// 경과 시계: 한 시간이 안 되면 '분:초'
String clock(num ms) {
  final t = (ms / 1000).floor();
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  return h > 0 ? '$h:${_p2(m)}:${_p2(s)}' : '${_p2(m)}:${_p2(s)}';
}

/// 책 고르기 차례: 최근 읽은 책(읽는 중인데 기록이 없으면 바뀐 때)
List<String> recentBookIds(Library lib) {
  final last = <String, String>{};
  for (final s in lib.sessions.values) {
    if (s.myBookId != null && lib.books[s.myBookId] != null && _cmp(last[s.myBookId!] ?? '', s.startedAt) < 0) last[s.myBookId!] = s.startedAt;
  }
  for (final b in lib.books.values) {
    if (b.status == ReadStatus.reading && !last.containsKey(b.id)) last[b.id] = b.updatedAt;
  }
  final e = [for (final (i, x) in last.entries.indexed) (i, x)]
    ..sort((a, b) {
      final c = _cmp(b.$2.value, a.$2.value);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final x in e) x.$2.key];
}

// ---------- 새 id·독서 저장 ----------

final _rnd = math.Random();

/// 지금 앱 newId: `${prefix}_${Date.now() 36진수}${무작위 6자}`
String newId(String prefix) {
  final r = StringBuffer();
  while (r.length < 6) {
    r.write(_rnd.nextInt(36).toRadixString(36));
  }
  return '${prefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$r';
}

/// 기록을 저장할 때 그 책의 회차 확보: 있으면 마지막 회차, 없으면 1회차를 열고 읽기 전이면 읽는 중으로
({Library lib, String? roundId}) sessionRound(Library lib, String myBookId, String day, String now, {String Function()? roundId}) {
  final book = lib.books[myBookId];
  if (book == null) return (lib: lib, roundId: null);
  final last = currentRound(lib, myBookId);
  if (last != null) {
    // 읽기 전으로 되돌린 책(회차는 남아 있음)도 기록을 저장하면 읽는 중(2026-11-19 타이머 점검 B5: 계속 '읽기 전'이었다)
    if (book.status != ReadStatus.want) return (lib: lib, roundId: last.id);
    return (lib: lib.copy(books: {...lib.books, myBookId: book.copyWith(status: ReadStatus.reading, updatedAt: now)}), roundId: last.id);
  }
  final id = (roundId ?? () => newId('rd'))();
  final r = Round(id: id, myBookId: myBookId, index: 1, startedAt: day, createdAt: now, updatedAt: now, paused: book.status == ReadStatus.paused);
  final status = book.status == ReadStatus.want ? ReadStatus.reading : book.status;
  return (
    lib: lib.copy(rounds: {...lib.rounds, id: r}, books: {...lib.books, myBookId: book.copyWith(status: status, updatedAt: now)}),
    roundId: id,
  );
}

class SessionInput {
  const SessionInput({required this.startedAt, required this.endedAt, required this.durationMs, this.id, this.myBookId, this.startPage, this.pagesRead, this.memo});
  final String? id, myBookId, memo;
  final String startedAt, endedAt;
  final num durationMs;
  final num? startPage, pagesRead;
}

/// 독서 기록 저장: 같은 id(타이머 id)로 다시 저장해도 하나로 남는다. 책이 있으면 회차를 먼저 확보해 연결하고,
/// 적은 쪽수는 현재 쪽수를 앞으로만 옮기고, 마지막 쪽이면 완독으로(finishIfLastPage). 책 없이 시간만도 저장한다.
/// 타이머 저장 · 읽은 시간 직접 추가가 같이 쓴다
({Library lib, String id}) addSessionTo(Library lib, SessionInput input, String now, {String Function()? sessionId, String Function()? roundId}) {
  final prev = input.id == null ? null : lib.sessions[input.id];
  var next = lib;
  String? rid;
  final linked = input.myBookId != null && lib.books[input.myBookId] != null;
  if (linked) {
    final r = sessionRound(lib, input.myBookId!, today(DateTime.parse(input.startedAt)), now, roundId: roundId);
    next = r.lib;
    rid = r.roundId;
  }
  final id = input.id ?? (sessionId ?? () => newId('ss'))();
  final s = Session(
    id: id,
    startedAt: input.startedAt,
    endedAt: input.endedAt,
    durationMs: input.durationMs,
    createdAt: prev?.createdAt ?? now,
    updatedAt: now,
    myBookId: linked ? input.myBookId : null,
    roundId: rid,
    startPage: input.startPage,
    pagesRead: input.pagesRead,
    memo: input.memo,
  );
  next = next.copy(sessions: {...next.sessions, id: s});
  final b = s.myBookId == null ? null : next.books[s.myBookId];
  if (b != null && input.pagesRead != null && input.pagesRead != 0) {
    next = next.copy(books: {...next.books, b.id: b.copyWith(currentPage: math.max(b.currentPage ?? 0, input.pagesRead!), updatedAt: now)});
    // 적은 쪽이 마지막 쪽이면 완독(완독일은 그 기록을 시작한 날)
    next = finishIfLastPage(next, b.id, input.pagesRead, today(DateTime.parse(input.startedAt)), now, roundId: roundId);
  }
  return (lib: next, id: id);
}

// ---------- 진행 중 독서(타이머) ----------

/// 진행 중 독서: 시각(벽시계)만 저장하고 경과는 계산한다. JSON 모양은 지금 앱 저장본과 같다
class Active {
  const Active({required this.id, required this.startedAt, required this.accumulatedMs, required this.runningSince, required this.lastBeat, this.myBookId, this.interruptedAt, this.startPage});
  final String id;
  final String? myBookId;
  final String startedAt;
  final num accumulatedMs;
  final num? runningSince;
  final num lastBeat;
  final num? interruptedAt;
  final num? startPage;

  static const _keep = Object();
  Active copyWith({Object? myBookId = _keep, num? accumulatedMs, Object? runningSince = _keep, num? lastBeat, Object? interruptedAt = _keep, Object? startPage = _keep}) => Active(
        id: id,
        startedAt: startedAt,
        myBookId: identical(myBookId, _keep) ? this.myBookId : myBookId as String?,
        accumulatedMs: accumulatedMs ?? this.accumulatedMs,
        runningSince: identical(runningSince, _keep) ? this.runningSince : runningSince as num?,
        lastBeat: lastBeat ?? this.lastBeat,
        interruptedAt: identical(interruptedAt, _keep) ? this.interruptedAt : interruptedAt as num?,
        startPage: identical(startPage, _keep) ? this.startPage : startPage as num?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'myBookId': ?myBookId,
        'startedAt': startedAt,
        'accumulatedMs': accumulatedMs,
        'runningSince': runningSince,
        'lastBeat': lastBeat,
        'interruptedAt': ?interruptedAt,
        'startPage': ?startPage,
      };

  static Active fromJson(Map<String, Object?> j) => Active(
        id: j['id']! as String,
        myBookId: j['myBookId'] as String?,
        startedAt: j['startedAt']! as String,
        accumulatedMs: j['accumulatedMs']! as num,
        runningSince: j['runningSince'] as num?,
        lastBeat: j['lastBeat']! as num,
        interruptedAt: j['interruptedAt'] as num?,
        startPage: j['startPage'] as num?,
      );
}

/// 강제 종료 뒤 복구: 마지막 확인 시각까지 센 시간과 그 뒤 지난 시간(gapMs = 다시 연 시각 − 마지막 확인 시각)
class Interrupted {
  const Interrupted(this.active, this.countedMs, this.lastBeat, this.gapMs);
  final Active active;
  final num countedMs, lastBeat, gapMs;

  /// 앱을 다시 연 시각(꺼져 있던 시간의 끝)
  num get reopenAt => lastBeat + gapMs;
}

/// 꺼져 있던 시간을 물을 만큼 길었는지(1분 미만은 묻지 않고 넣는다: 사용자가 읽고 있었을 가능성이 크고 묻는 것이 더 번거롭다)
const askGapMs = 60000;

/// 복구 창에서 고른 대로 이어 읽기: 꺼져 있던 시간을 넣으면 마지막 확인 시각부터, 빼면 다시 연 시각부터 잰다.
/// 어느 쪽이든 안내창이 떠 있던 동안(다시 연 뒤)은 읽은 시간에 들어간다(2026-11-15 QA: 창이 떠 있던 54초가 빠졌다)
Active resumeInterruptedActive(Interrupted it, {required bool includeGap, required num now}) =>
    it.active.copyWith(runningSince: includeGap ? it.lastBeat : it.reopenAt, lastBeat: now, interruptedAt: null);

/// 저장하는 독서 시간은 초 단위로 내린다(읽기 탭 시계(내림)와 기록 화면(초 반올림)이 1초씩 달랐다, 2026-11-15 QA)
FinishDraft wholeSeconds(FinishDraft p) => FinishDraft(
      id: p.id,
      startedAt: p.startedAt,
      endedAt: p.endedAt,
      durationMs: (p.durationMs ~/ 1000) * 1000,
      myBookId: p.myBookId,
      startPage: p.startPage,
      notes: p.notes,
    );

// 조사 고르기(josa · withJosa)는 domain/josa.dart로 옮겼다(따옴표 · 영문 끝 글자까지, 2026-11-20). 이 파일을 가져오는 곳이 그대로 쓰도록 다시 내보낸다

/// 종료 화면에 적는 중인 값(입력 그대로의 글자)
class FinishNotes {
  const FinishNotes({this.startPage, this.pages, this.memo});
  final String? startPage, pages, memo;
  Map<String, Object?> toJson() => {'startPage': ?startPage, 'pages': ?pages, 'memo': ?memo};
  static FinishNotes fromJson(Map<String, Object?> j) => FinishNotes(startPage: j['startPage'] as String?, pages: j['pages'] as String?, memo: j['memo'] as String?);
}

/// 끝낸 뒤 종료 화면이 저장·버리기를 정할 값(id = 타이머 id = 저장할 세션 id)
class FinishDraft {
  const FinishDraft({required this.id, required this.startedAt, required this.endedAt, required this.durationMs, this.myBookId, this.startPage, this.notes});
  final String id, startedAt, endedAt;
  final String? myBookId;
  final num durationMs;
  final num? startPage;
  final FinishNotes? notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'myBookId': ?myBookId,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'durationMs': durationMs,
        'startPage': ?startPage,
        if (notes != null) 'notes': notes!.toJson(),
      };

  static FinishDraft fromJson(Map<String, Object?> j) => FinishDraft(
        id: j['id']! as String,
        myBookId: j['myBookId'] as String?,
        startedAt: j['startedAt']! as String,
        endedAt: j['endedAt']! as String,
        durationMs: j['durationMs']! as num,
        startPage: j['startPage'] as num?,
        notes: j['notes'] == null ? null : FinishNotes.fromJson((j['notes']! as Map).cast<String, Object?>()),
      );
}

num elapsedMs(Active a, num now) => a.accumulatedMs + (a.runningSince != null ? math.max(0, now - a.runningSince!) : 0);

/// 저장본을 다시 읽을 때: 달리는 상태로 남아 있으면 앱이 꺼진 것 → 마지막 확인 시각까지만 세고 일시정지로
({Active? active, Interrupted? interrupted}) recoverOnLoad(Active? saved, num now) {
  if (saved == null) return (active: null, interrupted: null);
  if (saved.runningSince != null) {
    final lastBeat = math.max(saved.runningSince!, saved.lastBeat);
    final counted = saved.accumulatedMs + (lastBeat - saved.runningSince!);
    final active = saved.copyWith(accumulatedMs: counted, runningSince: null, lastBeat: lastBeat, interruptedAt: lastBeat);
    return (active: active, interrupted: Interrupted(active, counted, lastBeat, math.max(0, now - lastBeat)));
  }
  if (saved.interruptedAt != null) {
    return (active: saved, interrupted: Interrupted(saved, saved.accumulatedMs, saved.interruptedAt!, math.max(0, now - saved.interruptedAt!)));
  }
  return (active: saved, interrupted: null);
}

String isoOf(num ms) => DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true).toIso8601String();

/// 끝내기: endAt을 주면 그 시각에 끝낸 것으로(달리는 중일 때만 의미가 있다)
FinishDraft finishActive(Active a, num now, [num? endAt]) {
  final t = endAt ?? now;
  final running = a.runningSince != null;
  final duration = running ? a.accumulatedMs + math.max(0, t - a.runningSince!) : a.accumulatedMs;
  final end = running ? t : (a.interruptedAt ?? math.max(a.lastBeat, DateTime.parse(a.startedAt).millisecondsSinceEpoch));
  return FinishDraft(id: a.id, myBookId: a.myBookId, startedAt: a.startedAt, endedAt: isoOf(end), durationMs: duration, startPage: a.startPage);
}

// ---------- 읽기 상태·다시 읽기(지금 앱 domain/library.ts applyStatus·rereadRound) ----------

/// 상태 변경 규칙. 상태는 사용자가 정하고, 자동으로는 적은 쪽이 마지막 쪽일 때만 완독으로 바꾼다(finishIfLastPage. 타이머 시간으로는 판정하지 않는다,
/// 완독은 자동으로 되돌리지 않는다). day는 기기 현지 날짜.
/// 같은 상태면 그대로. 읽는 중·보류로: 열린 회차를 이어 가거나(보류 해제/설정) 없으면 새 회차(완독 뒤면 다시 읽기, 진도 0쪽부터).
/// 완독으로: 열린 회차를 닫고(완독일 오늘), 회차가 없으면 만들고 바로 닫는다. 읽기 전으로: 날짜 없는 빈 열린 회차만 지운다
Library applyStatus(Library lib, String myBookId, ReadStatus status, String now, {String? day, String Function()? roundId}) {
  final book = lib.books[myBookId];
  if (book == null || book.status == status) return lib;
  final d = day ?? today(DateTime.parse(now));
  final rounds = {...lib.rounds};
  final last = currentRound(lib, myBookId);
  final open = last != null && last.finishedAt == null ? last : null;
  Round make() => Round(id: (roundId ?? () => newId('rd'))(), myBookId: myBookId, index: (last?.index ?? 0) + 1, startedAt: d, createdAt: now, updatedAt: now);
  Object? page = book.currentPage;
  if (status == ReadStatus.reading || status == ReadStatus.paused) {
    final paused = status == ReadStatus.paused;
    if (open != null) {
      rounds[open.id] = open.copyWith(paused: paused, startedAt: open.startedAt ?? d, updatedAt: now);
    } else {
      final r = make();
      rounds[r.id] = paused ? r.copyWith(paused: true, updatedAt: now) : r;
      if (last != null) page = null; // 다시 읽기: 진도는 0쪽부터
    }
  } else if (status == ReadStatus.read) {
    if (open != null) {
      rounds[open.id] = open.copyWith(paused: false, finishedAt: d, updatedAt: now);
    } else if (last == null) {
      final r = make();
      rounds[r.id] = r.copyWith(finishedAt: d, updatedAt: now);
    }
  } else if (open != null && open.startedAt == null && open.finishedAt == null) {
    rounds.remove(open.id);
  }
  return lib.copy(rounds: rounds, books: {...lib.books, myBookId: book.patch(status: status, currentPage: page, updatedAt: now)});
}

// ---------- 읽기 상태 · 현재 쪽 규칙(한 곳, 2026-11-24 사용자 1단계) ----------
// 들어오는 길(타이머 저장 · 읽은 시간 직접 추가 · 기록 수정 · 기록 삭제 · 현재 쪽 고치기)이 모두 아래를 거친다.
//  1. 책에 연결된 기록을 저장할 때 도달한 쪽이 판본 전체 쪽수(있고 0보다 클 때만) 이상이면 완독(완독일은 그 기록을 시작한 날). 이미 완독이면 그대로
//  2. 현재 쪽을 직접 고쳐 전체 쪽수 이상이 되면 같은 완독(완독일은 오늘)
//  3. 기록의 도달한 쪽을 고치거나 기록을 지우면, 책의 현재 쪽이 그 기록의 예전 도달한 쪽과 같았을 때만 같은 회차에 남은 기록의 도달한 쪽 중 가장 큰 값으로
//     (없으면 그 기록의 시작 쪽, 그것도 없으면 비움). 사용자가 직접 적은 다른 값은 그대로
//  4. 완독은 자동으로 되돌리지 않는다(기록을 지우거나 쪽을 낮춰도 상태는 그대로)

/// 판본 전체 쪽수(값이 있고 0보다 클 때만)
num? bookPageCount(Library lib, String myBookId) {
  final b = lib.books[myBookId];
  final n = b == null ? null : lib.editions[b.editionId]?.pageCount;
  return n != null && n > 0 ? n : null;
}

/// 규칙 1·2: 적은 쪽이 마지막 쪽 이상이면 완독(applyStatus, 완독일 day). 이미 완독이거나 쪽수를 모르면 그대로
Library finishIfLastPage(Library lib, String myBookId, num? page, String day, String now, {String Function()? roundId}) {
  final b = lib.books[myBookId];
  final count = bookPageCount(lib, myBookId);
  if (b == null || b.status == ReadStatus.read || page == null || count == null || page < count) return lib;
  return applyStatus(lib, myBookId, ReadStatus.read, now, day: day, roundId: roundId);
}

/// 규칙 2: 현재 쪽 직접 고치기(null이면 비운다). 마지막 쪽 이상이면 완독(완독일 오늘)
Library setCurrentPageIn(Library lib, String myBookId, num? page, String now) {
  final b = lib.books[myBookId];
  if (b == null) return lib;
  final next = lib.copy(books: {...lib.books, myBookId: b.patch(currentPage: page, updatedAt: now)});
  return finishIfLastPage(next, myBookId, page, today(DateTime.parse(now)), now);
}

/// 규칙 3: 기록 하나([before], 고치거나 지우기 전)가 바뀐 뒤 그 책의 현재 쪽을 맞춘다. [lib]은 바뀐 뒤 서재
Library syncPageAfterSessionChange(Library lib, Session before, String now) {
  final id = before.myBookId, old = before.pagesRead;
  final b = id == null ? null : lib.books[id];
  if (b == null || old == null || old == 0 || b.currentPage != old) return lib;
  num? best;
  for (final s in lib.sessions.values) {
    if (s.myBookId != id || s.roundId != before.roundId) continue;
    final p = s.pagesRead;
    if (p != null && p != 0 && (best == null || p > best)) best = p;
  }
  final page = best ?? (before.startPage != null && before.startPage != 0 ? before.startPage : null);
  if (page == b.currentPage) return lib;
  return lib.copy(books: {...lib.books, id!: b.patch(currentPage: page, updatedAt: now)});
}

/// 다시 읽기(명시적): 지난 회차는 그대로 두고 새 회차를 연다(진도 0쪽부터). 열린 회차가 있으면 그대로
Library rereadRound(Library lib, String myBookId, String now, {String? day, String Function()? roundId}) {
  final book = lib.books[myBookId];
  if (book == null) return lib;
  final last = currentRound(lib, myBookId);
  if (last != null && last.finishedAt == null) return lib;
  final d = day ?? today(DateTime.parse(now));
  final r = Round(id: (roundId ?? () => newId('rd'))(), myBookId: myBookId, index: (last?.index ?? 0) + 1, startedAt: d, createdAt: now, updatedAt: now);
  return lib.copy(rounds: {...lib.rounds, r.id: r}, books: {...lib.books, myBookId: book.patch(status: ReadStatus.reading, currentPage: null, updatedAt: now)});
}
