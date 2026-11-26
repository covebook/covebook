// 독서 끝내고 저장하기(지금 앱 store/finish-reading.ts): 기록이 디스크에 저장되기 전에는 복구용 초안을 지우지 않는다. 다시 해도 같은 세션 id
library;

import 'dart:async';

import '../domain/library.dart' show today;
import '../services/ambient.dart';
import '../domain/reading.dart';
import 'library_model.dart';
import 'reading_store.dart';
import 'settings_store.dart';

/// startPage: 이번 독서를 시작한 쪽, pagesRead: 도달한 쪽. 둘 다 있을 때만 화면이 분량을 센다
Future<void> saveFinishedReading(FinishDraft draft, {num? startPage, num? pagesRead, String? memo}) async {
  if (draft.myBookId == null) _markNoBookDay(today(DateTime.parse(draft.startedAt)));
  await LibraryModel.instance.addSession(SessionInput(
    id: draft.id,
    myBookId: draft.myBookId,
    startedAt: draft.startedAt,
    endedAt: draft.endedAt,
    durationMs: draft.durationMs,
    startPage: startPage,
    pagesRead: pagesRead,
    memo: memo,
  ));
  await ReadingStore.instance.clearPending();
}

/// 쪽 칸 글자를 쪽 수로(숫자만 남겨 0보다 클 때만). 독서 끝 화면과 묻지 않고 저장하는 길이 같은 규칙을 쓴다
int? pageOf(String? v) {
  final n = int.tryParse((v ?? '').replaceAll(RegExp(r'[^\d]'), ''));
  return v != null && v.trim().isNotEmpty && n != null && n > 0 ? n : null;
}

/// 적어 둔 그대로 저장(묻지 않고 거기까지 기록, 2026-11-26 사용자 '화면 나가면 그냥 거기까지 기록하고 (팝업이나 그렇게 떠서 하는 거면 그냥 기록하고)').
/// 칸 글자를 넘기지 않으면 초안에 남은 것(쪽 · 메모, 시작 쪽은 그 책의 지금 쪽)을 쓴다. 독서 끝 화면이 저장 단추에서 막는 쪽
/// (전체 쪽수보다 큼 · 시작 쪽보다 앞)은 빼고 시간과 메모는 남긴다. 1초가 안 되는 기록은 남길 것이 없어 버린다(false). 저장하면 true
Future<bool> saveDraftAsIs(FinishDraft draft, {String? startPage, String? pages, String? memo}) async {
  if (draft.durationMs < 1000) {
    await ReadingStore.instance.clearPending();
    return false;
  }
  final model = LibraryModel.instance;
  await model.load();
  final n = draft.notes;
  final book = draft.myBookId == null ? null : model.lib.books[draft.myBookId];
  final total = book == null ? null : model.lib.editions[book.editionId]?.pageCount;
  final max = total != null && total > 0 ? total : null;
  var sp = book == null ? null : pageOf(startPage ?? n?.startPage ?? draft.startPage?.toString());
  var ep = book == null ? null : pageOf(pages ?? n?.pages);
  if (sp != null && max != null && sp > max) sp = null;
  if (ep != null && ((max != null && ep > max) || (sp != null && ep < sp))) ep = null;
  final m = (memo ?? n?.memo ?? '').trim();
  await saveFinishedReading(draft, startPage: sp, pagesRead: ep, memo: m.isEmpty ? null : m);
  return true;
}

/// 앱을 다시 켰을 때 남아 있던 독서를 묻지 않고 거기까지 기록한다(2026-11-26 사용자 '멈춰 둔 독서가 있어요 이런 거 그냥 기록해').
/// 전에는 창 셋이 물었다: 저장하지 않은 독서 기록이 있어요 · 멈춰 둔 독서가 있어요 · 지난 독서가 중간에 멈췄어요.
/// - 끝내고 저장하지 않은 초안: 적어 둔 쪽 · 메모 그대로
/// - 멈춰 둔 독서(켤 때 일시정지였던 것, 1분 미만은 ReadingStore.load가 지운다): 멈춘 때까지
/// - 앱이 꺼져 멈춘 독서: 마지막으로 확인된 때까지(1분 미만 꺼졌던 것은 읽던 중이라 그 시간도 넣는다, askGapMs)
/// 저장한 기록을 돌려준다. 저장하지 못하면 예외(그 기록은 저장 전 초안으로 읽기 탭에 남고 다음에 켤 때 다시 저장한다)
Future<List<FinishDraft>> settleLeftoverReading() async {
  final rs = ReadingStore.instance;
  final saved = <FinishDraft>[];
  final p = rs.pending;
  if (p != null && rs.pendingRestored) {
    rs.ackPendingRestored();
    if (await saveDraftAsIs(p)) saved.add(p);
  }
  // 초안이 남아 있으면(지금 독서 끝 화면에서 적는 중 등) 진행 중 독서를 끝내지 않는다: 끝내면 그 초안을 덮는다
  if (rs.pending != null || rs.active == null) return saved;
  final it = rs.interrupted;
  FinishDraft? d;
  if (it != null) {
    d = rs.finishInterrupted(includeGap: it.gapMs < askGapMs);
  } else if (rs.stale) {
    rs.clearStale();
    d = rs.finish(rs.active!.lastBeat);
  }
  if (d != null && await saveDraftAsIs(d)) saved.add(d);
  return saved;
}

/// 독서 일시정지: 타이머와 함께 소리도 멈춘다. 켜 둔 소리 설정은 그대로라 이어 읽으면 다시 난다
/// (2026-11-21 사용자 '타이머 멈출 때 소리도 같이 멈추게'). 일시정지 단추(장면 · 작은 타이머)가 모두 이것을 쓴다
void pauseReading() {
  ReadingStore.instance.pause();
  Ambient.instance.hold();
}

/// 이어 읽을 때 켜 둔 소리도 다시(소리를 꺼 둔 사람은 그대로 조용하다)
void _resumeSound() => unawaited(Ambient.instance.resumeIfWanted().catchError((Object _) {}));

/// 멈춰 둔 독서를 이어 읽기. 시작한 날이 오늘이 아니면 지난 몫은 그날(멈춘 때 끝난) 기록으로 저장하고 같은 책으로 오늘 새로 시작한다
/// (2026-11-19 타이머 점검 B1: 어제 멈춘 독서를 오늘 이어 읽으면 오늘 읽은 시간까지 어제 기록이 되고 읽기 탭은 00:00이었다).
/// 이어 읽기 단추(장면 · 작은 타이머 · 읽기 시작 · 멈춰 둔 독서 창)가 모두 이것을 쓴다.
/// 지난 몫을 저장하지 못하면 그 예외를 돌려준다(부른 화면이 알린다: 실패는 조용히 끝나지 않는다, docs/design/DESIGN.md 11장). 아니면 null
Future<Object?> resumeReading() async {
  final rs = ReadingStore.instance;
  final a = rs.active;
  if (a == null || a.runningSince != null) return null;
  if (today(DateTime.parse(a.startedAt)) == today()) {
    rs.resume();
    _resumeSound();
    return null;
  }
  final draft = rs.finish(a.lastBeat);
  try {
    if (draft != null && draft.durationMs >= 1000) {
      await saveFinishedReading(draft, startPage: draft.startPage);
    } else {
      await rs.clearPending();
    }
  } catch (e) {
    // 저장하지 못하면 지난 몫은 저장 전 초안으로 남는다(다음 '읽기 시작'이 독서 끝 화면으로 간다). 새로 시작하지 않는다
    return e;
  }
  final page = a.myBookId == null ? null : LibraryModel.instance.lib.books[a.myBookId]?.currentPage;
  rs.start(a.myBookId, page);
  _resumeSound();
  return null;
}

/// 다른 책 읽기: 지금까지의 독서를 그 책(또는 책 없음)의 기록으로 저장하고, 새 책으로 타이머를 새로 시작한다
Future<String?> saveAndStartOther(String? nextBookId) async {
  final rs = ReadingStore.instance;
  final draft = rs.finish();
  if (draft == null) return null;
  if (draft.durationMs >= 1000) {
    await saveFinishedReading(draft, startPage: draft.startPage);
  } else {
    await rs.clearPending();
  }
  final page = nextBookId == null ? null : LibraryModel.instance.lib.books[nextBookId]?.currentPage;
  rs.start(nextBookId, page);
  return draft.id;
}

/// 직접 추가한 독서 기록 저장(2026-11-23 사용자: 타이머를 켜지 않고 읽은 사람도 기록을 쉽게): 타이머 저장과 같은 길
/// (addSession: 책이 있으면 회차를 확보하고 읽기 전 → 읽는 중, 도달한 쪽은 현재 쪽을 앞으로만). 책 없이 오늘 읽은 기록이면
/// 타이머처럼 읽기 탭에 '책 없이 읽기' 줄을 띄운다(지난 날 기록은 오늘 줄과 상관없어 남기지 않는다). 새 기록 id를 돌려준다
Future<String> saveManualReading(SessionInput input) async {
  final day = today(DateTime.parse(input.startedAt));
  if (input.myBookId == null && day == today()) _markNoBookDay(day);
  return LibraryModel.instance.addSession(input);
}

/// 책 없이 읽어 저장한 날(설정 noBookDay)을 남긴다. 읽기 탭은 그날만 오늘 책 없는 시간으로 '책 없이 읽기' 줄을 띄운다:
/// 책을 지워 책 연결이 빈 독서 시간만으로는 줄이 생기지 않게(2026-11-16 QA 현우 F4)
void _markNoBookDay(String day) {
  final s = SettingsStore.instance;
  if (s.loaded && s.noBookDay == day) return;
  s.load().then((_) {
    if (s.noBookDay != day) s.set({'noBookDay': day});
  });
}
