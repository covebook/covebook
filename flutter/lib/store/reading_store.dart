// 진행 중 독서(타이머) 상태(지금 앱 store/reading-store.ts): 시각만 저장하고 경과는 계산한다.
// 달리는 동안 5초마다, 그리고 백그라운드로 갈 때 '마지막 확인 시각'을 저장한다 → 강제 종료 뒤 다시 켜면 그 시각까지만 센다(domain/reading recoverOnLoad).
// 저장본은 지금 앱과 같은 키(reading-state:v2, {version:2, active, pending})라 앱을 바꿔 깔아도 이어진다
library;

import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

import '../db/kv_store.dart';
import '../domain/reading.dart';

const _stateKey = 'reading-state:v2';
const _oldKey = 'active-reading:v1';
const _oldPendingKey = 'finished-reading:v1';
const _beatMs = 5000;

/// 통화 등으로 소리가 이만큼 넘게 끊겼을 때만 그 시간을 넣을지 묻는다(짧은 알림음·안내 음성은 그대로 센다)
const _askSpanMs = 30000;

num _now() => DateTime.now().millisecondsSinceEpoch;

class ReadingStore extends ChangeNotifier with WidgetsBindingObserver {
  ReadingStore._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = ReadingStore._();

  Active? active;
  Interrupted? interrupted;
  FinishDraft? pending;
  bool pendingRestored = false;
  bool loaded = false;
  String? error;
  Timer? _beat;
  Future<void> _writeTail = Future.value();
  Future<void>? _loading;

  /// 통화 등으로 소리가 끊긴 동안(읽는 중이었을 때): 끝나면 넣을지 묻는다(앱 틀이 창을 띄운다)
  ({num start, num end})? spanGap;
  num? _spanStart;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;

  bool get running => active?.runningSince != null;
  num get elapsed => active == null ? 0 : elapsedMs(active!, _now());

  // 한 키에 함께 기록한다(끝낼 때 진행 기록 삭제와 초안 생성 사이에 빈 상태가 없다)
  Future<void> _persist(Active? a, FinishDraft? p) {
    final value = jsonEncode({'version': 2, 'active': a?.toJson(), 'pending': p?.toJson()});
    final w = _writeTail.then((_) => KvStore.set(_stateKey, value));
    _writeTail = w.catchError((_) {});
    return w;
  }

  void _save() {
    _persist(active, pending).then((_) {
      if (error != null) {
        error = null;
        notifyListeners();
      }
    }, onError: (Object e) {
      error = '$e';
      notifyListeners();
    });
  }

  void _tick() {
    final a = active;
    if (a == null || a.runningSince == null) return;
    active = a.copyWith(lastBeat: _now());
    _save(); // 화면은 다시 그리지 않는다(경과는 화면이 스스로 계산)
  }

  void _startBeat() => _beat ??= Timer.periodic(const Duration(milliseconds: _beatMs), (_) => _tick());
  void _stopBeat() {
    _beat?.cancel();
    _beat = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _tick(); // 백그라운드로 갈 때 마지막 확인 시각을 남긴다
  }

  Future<void> load() => _loading ??= () async {
        final raw = await KvStore.get(_stateKey);
        Active? a;
        FinishDraft? p;
        if (raw != null) {
          final saved = (jsonDecode(raw) as Map).cast<String, Object?>();
          if (saved['version'] != 2 || !saved.containsKey('active') || !saved.containsKey('pending')) throw StateError('독서 기록을 읽지 못했어요');
          a = saved['active'] == null ? null : Active.fromJson((saved['active']! as Map).cast());
          p = saved['pending'] == null ? null : FinishDraft.fromJson((saved['pending']! as Map).cast());
        } else {
          final oa = await KvStore.get(_oldKey), op = await KvStore.get(_oldPendingKey);
          a = oa == null ? null : Active.fromJson((jsonDecode(oa) as Map).cast());
          p = op == null ? null : FinishDraft.fromJson((jsonDecode(op) as Map).cast());
          if (a != null && p != null && a.id == p.id) a = null;
        }
        final r = recoverOnLoad(a, _now());
        await _persist(r.active, p);
        active = r.active;
        interrupted = r.interrupted;
        pending = p;
        pendingRestored = p != null;
        loaded = true;
        error = null;
        notifyListeners();
      }();

  /// startPage: 그 책의 지금 쪽(알 때만, 이번 독서의 시작 쪽 기본값)
  void start(String? myBookId, [num? startPage]) {
    final t = _now();
    active = Active(id: newId('ss'), myBookId: myBookId, startedAt: isoOf(t), accumulatedMs: 0, runningSince: t, lastBeat: t, startPage: myBookId != null ? startPage : null);
    interrupted = null;
    spanGap = null;
    _spanStart = null;
    notifyListeners();
    _save();
    _startBeat();
  }

  void pause() {
    final a = active;
    if (a == null || a.runningSince == null) return;
    final t = _now();
    active = a.copyWith(accumulatedMs: elapsedMs(a, t), runningSince: null, lastBeat: t);
    notifyListeners();
    _save();
    _stopBeat();
  }

  void resume() {
    final a = active;
    if (a == null || a.runningSince != null) return;
    final t = _now();
    active = a.copyWith(runningSince: t, lastBeat: t, interruptedAt: null);
    interrupted = null;
    notifyListeners();
    _save();
    _startBeat();
  }

  /// 이 기록의 연결 책 정정. 시작 쪽은 그 책의 현재 쪽으로(없으면 비움)
  void setBook(String? myBookId, [num? startPage]) {
    final a = active;
    if (a == null) return;
    active = a.copyWith(myBookId: myBookId, startPage: myBookId != null ? startPage : null);
    notifyListeners();
    _save();
  }

  /// 복구 창에서 이어 읽기: 꺼져 있던 시간을 넣거나 뺀다(사용자 결정 2026-11-15 '물어보기')
  void resumeInterrupted({required bool includeGap}) {
    final it = interrupted;
    if (it == null || active == null) return resume();
    final t = _now();
    active = resumeInterruptedActive(it, includeGap: includeGap, now: t);
    interrupted = null;
    notifyListeners();
    _save();
    _startBeat();
  }

  /// 복구 창에서 끝내기: 넣으면 지금 끝낸 것으로(꺼진 시간 포함), 빼면 마지막 확인 시각에 끝낸 것으로
  FinishDraft? finishInterrupted({required bool includeGap}) {
    final it = interrupted;
    if (it == null || active == null) return finish();
    if (!includeGap) return finish(it.lastBeat);
    active = resumeInterruptedActive(it, includeGap: true, now: _now());
    return finish();
  }

  /// 오디오가 끊겼다 이어지는 것(통화·다른 앱 소리)을 지켜본다. 앱을 켤 때 한 번
  Future<void> watchInterruptions() async {
    if (_interruptions != null) return;
    try {
      final session = await AudioSession.instance;
      _interruptions = session.interruptionEventStream.listen(_interruption);
    } catch (_) {
      // 오디오 세션을 못 얻는 기기(시험 등)는 통화 시간을 묻지 않는다
    }
  }

  void _interruption(AudioInterruptionEvent e) {
    if (e.type == AudioInterruptionType.duck) return;
    final t = _now();
    if (e.begin) {
      if (running) _spanStart = t;
      return;
    }
    final start = _spanStart;
    _spanStart = null;
    if (start == null || active == null || t - start < _askSpanMs) return;
    spanGap = (start: start, end: t);
    notifyListeners();
  }

  /// 통화 등으로 끊긴 동안을 넣을지 답하기(넣으면 그대로 둔다)
  void answerSpan({required bool include}) {
    final g = spanGap;
    spanGap = null;
    final a = active;
    if (g != null && a != null && !include) {
      active = excludeSpan(a, g.end - g.start, _now());
      _save();
    }
    notifyListeners();
  }

  /// 복구 창을 닫기(일시정지로 둠. 표시는 남겨 다음 실행에서 다시 묻는다)
  /// 진행 중 독서와 저장 전 초안을 모두 버린다(로그아웃으로 기기 기록을 지울 때)
  Future<void> discardAll() async {
    _stopBeat();
    active = null;
    interrupted = null;
    pending = null;
    pendingRestored = false;
    spanGap = null;
    _spanStart = null;
    notifyListeners();
    await _persist(null, null);
  }

  void dismissInterrupted() {
    interrupted = null;
    notifyListeners();
  }

  /// 끝내기: 초안을 만들어 저장하고 진행 중 상태를 지운다(저장·버리기는 종료 화면이 정한다)
  FinishDraft? finish([num? endAt]) {
    final a = active;
    if (a == null) return null;
    _stopBeat();
    final p = wholeSeconds(finishActive(a, _now(), endAt));
    active = null;
    interrupted = null;
    spanGap = null;
    _spanStart = null;
    pending = p;
    pendingRestored = false;
    notifyListeners();
    _save();
    return p;
  }

  /// 끝낸 기록의 책 바꾸기(적던 시작 쪽은 지운다: 새 책의 지금 쪽이 기본값)
  void setPendingBook(String? myBookId, [num? startPage]) {
    final p = pending;
    if (p == null) return;
    final n = p.notes;
    pending = FinishDraft(
      id: p.id,
      startedAt: p.startedAt,
      endedAt: p.endedAt,
      durationMs: p.durationMs,
      myBookId: myBookId,
      startPage: myBookId != null ? startPage : null,
      notes: n == null ? null : FinishNotes(pages: n.pages, memo: n.memo),
    );
    notifyListeners();
    _save();
  }

  /// 종료 화면에 적는 중인 값(쪽수·메모)을 초안에 함께 둔다(앱이 꺼져도 복구)
  void setPendingNotes({String? startPage, String? pages, String? memo}) {
    final p = pending;
    if (p == null) return;
    final n = p.notes;
    pending = FinishDraft(
      id: p.id,
      startedAt: p.startedAt,
      endedAt: p.endedAt,
      durationMs: p.durationMs,
      myBookId: p.myBookId,
      startPage: p.startPage,
      notes: FinishNotes(startPage: startPage ?? n?.startPage, pages: pages ?? n?.pages, memo: memo ?? n?.memo),
    );
    _save();
  }

  Future<void> clearPending() async {
    final p = pending;
    try {
      await _persist(active, null);
      if (identical(pending, p)) {
        pending = null;
        pendingRestored = false;
        error = null;
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
      notifyListeners();
      rethrow;
    }
  }

  void ackPendingRestored() {
    pendingRestored = false;
    notifyListeners();
  }
}
