// 독서 끝내고 저장하기(지금 앱 store/finish-reading.ts): 기록이 디스크에 저장되기 전에는 복구용 초안을 지우지 않는다. 다시 해도 같은 세션 id
library;

import '../domain/library.dart' show today;
import '../domain/reading.dart';
import 'library_model.dart';
import 'reading_store.dart';
import 'settings_store.dart';

/// startPage: 이번 독서를 시작한 쪽, pagesRead: 도달한 쪽. 둘 다 있을 때만 화면이 분량을 센다
Future<void> saveFinishedReading(FinishDraft draft, {num? startPage, num? pagesRead, String? memo}) async {
  if (draft.myBookId == null) _markNoBookDay(draft);
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

/// 책 없이 읽어 저장한 날(설정 noBookDay)을 남긴다. 읽기 탭은 그날만 오늘 책 없는 시간으로 '책 없이 읽기' 줄을 띄운다:
/// 책을 지워 책 연결이 빈 독서 시간만으로는 줄이 생기지 않게(2026-11-16 QA 현우 F4)
void _markNoBookDay(FinishDraft draft) {
  final day = today(DateTime.parse(draft.startedAt));
  final s = SettingsStore.instance;
  if (s.loaded && s.noBookDay == day) return;
  s.load().then((_) {
    if (s.noBookDay != day) s.set({'noBookDay': day});
  });
}
