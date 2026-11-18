// 책장 배치 저장소(지금 앱 store/placement-store.ts의 확정·되돌리기): 편집 엔진(domain/layout_engine)이 만든 배치를 받아
// 기대기 정리(받침 잃은 책은 기대거나 눕거나 다시 선다. 옆 벽이 있어 선반 밖으로 떨어지지 않는다) → 구조·공간 검증 → 저장(바뀐 행만) → 책장 다시 굽기.
// 되돌리기는 바로 앞 한 번. 배치는 홈이 책장을 그리려고 읽은 서재를 그대로 받는다(adopt: 따로 DB를 다시 읽지 않는다)
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/layout.dart';
import '../domain/layout_engine.dart';
import '../domain/placed.dart' show jsRound;
import '../domain/types.dart' show BookPlacement;
import '../domain/shelf_scene.dart';
import '../services/cover_colors.dart' show shelfRefresh;
import 'library_store.dart';

class PlacementStore {
  PlacementStore._();
  static final instance = PlacementStore._();

  ShelfLayout? layout;
  BookMap books = {};
  ShelfLayout? _undo;

  /// 책장에서 뺀 책이 있던 자리(뺄 때 배치와 그 선반에서의 차례). '책장에 진열'로 되돌리면 그 자리부터 본다(앱을 끄면 잊는다).
  /// 2026-11-16 QA 현우 F12: 빼고 나서 다시 진열하면 선반 맨 끝으로 갔다
  final _spots = <String, ({BookPlacement was, int index})>{};

  /// 마지막으로 뺄 때 자리로 되돌린 책
  String? lastRestored;

  /// 뺄 때 자리를 기억하고 있는지
  bool hadSpot(String bookId) => _spots.containsKey(bookId);

  bool get canUndo => _undo != null;

  /// 홈이 읽은 서재(책 크기·배치)를 받는다
  void adopt(Library lib) {
    books = {for (final b in lib.books) b.id: b};
    layout = lib.layout;
  }

  /// 서재를 다시 읽는다(숨긴 책을 되돌린 뒤·책 정보나 장정을 고친 뒤처럼 책이 바뀌었을 때). 홈 책장도 다시 그린다.
  /// 책 크기(판형·쪽수)가 바뀐 책이 선반에 있으면 그 틈을 지키며 새 크기로 맞추고, 안 들어가면 끝 책을 책장에서 뺀다(지금 앱 syncBooks). 뺀 책 수
  Future<int> reload() async {
    final before = books, l = layout;
    adopt(await loadLibrary());
    if (l == null) return 0;
    final resized = l.placements.any((p) {
      final a = before[p.bookId]?.dims, b = books[p.bookId]?.dims;
      return a != null && b != null && (a.height != b.height || a.thickness != b.thickness || a.coverWidth != b.coverWidth);
    });
    if (!resized) {
      shelfRefresh.value++;
      return 0;
    }
    final fit = fitToShelf(keepGaps(l, before, books), books);
    final next = resolveLeans(fit.layout, books);
    _undo = null;
    layout = l;
    await _write(next);
    return fit.moved.length;
  }

  /// 아직 받은 게 없을 때만 읽는다
  Future<void> ensure() async {
    if (layout == null) adopt(await loadLibrary());
  }

  /// 배치에 없는 책은 서랍 끝에(지금 앱 commit과 같다)
  ShelfLayout _withMissing(ShelfLayout l) {
    final placed = {for (final p in l.placements) p.bookId, ...l.drawer};
    final missing = [for (final id in books.keys) if (!placed.contains(id)) id];
    return missing.isEmpty ? l : ShelfLayout(l.shelves, l.placements, [...l.drawer, ...missing]);
  }

  Future<void> _write(ShelfLayout next) async {
    final prev = layout!;
    layout = next;
    await saveLayout(prev, next);
    shelfRefresh.value++;
  }

  /// 확정: 기대기 결과(최종 각·상대)와 넘어진 책까지 풀어 검증한 뒤 저장. 안 되면 false
  Future<bool> commit(ShelfLayout input) async {
    final cur = layout;
    if (cur == null) return false;
    final next = resolveLeans(ensureShelves(_withMissing(input)), books);
    final errors = validateLayout(next, books, books.keys.toList());
    if (errors.isNotEmpty) {
      debugPrint('[layout] 확정 거절 $errors');
      return false;
    }
    _undo = cur;
    await _write(next);
    return true;
  }

  // ---------- 책장에 놓기·빼기(지금 앱 placement-store addToShelf·fromDrawer·addToDrawer·toDrawer·addShelf) ----------

  /// 책장에 놓기는 다른 책을 건드리지 않는다(2026-10-31 지시): 선반마다 맨 끝 후보를 기대기까지 풀어 보고,
  /// 다른 책의 선반·자세·자리·깊이·쌓기·기대기가 모두 그대로인 첫 후보만 쓴다
  static double? _r2(double? v) => v == null ? null : jsRound(v * 100) / 100;
  static String _spot(BookPlacement p) =>
      jsonEncode([p.shelfId, p.pose.index, p.tilt, _r2(p.pos), _r2(p.depth), _r2(p.spin), _r2(p.pitch), p.stackId, p.stackOrder, _r2(p.leanAngle), p.leanOn]);

  static String _place(BookPlacement p) => jsonEncode([p.shelfId, p.pose.index, _r2(p.pos), _r2(p.depth), _r2(p.spin), _r2(p.pitch), p.stackId, p.stackOrder]);

  /// lean: 기대기(기운 각·기댄 책)까지 같아야 하는지
  bool _undisturbed(ShelfLayout next, String shelfId, {bool lean = true}) {
    final after = {for (final p in resolveLeans(ensureShelves(next), books, shelfId).placements) p.bookId: p};
    final key = lean ? _spot : _place;
    return layout!.placements.every((p) {
      final q = after[p.bookId];
      return q != null && key(q) == key(p);
    });
  }

  /// 책장에 놓기(서랍에 있든 처음이든). 뺀 책이면 뺄 때 자리부터, 그다음 선반마다 끝, 줄 안의 빈 틈(fitCandidates). 놓았으면 true, 자리가 없으면 false
  Future<bool> placeOnShelf(String bookId) async {
    final l = layout;
    if (l == null || placementOf(l, bookId) != null) return l != null;
    final spot = _spots.remove(bookId);
    if (spot != null) {
      final next = reinsertAt(l, books, spot.was, spot.index);
      // 다른 책은 자리·자세·깊이가 그대로일 때만(기대기는 뺄 때처럼 다시 풀린다: 이 책에 기대 있던 옆 책은 다시 기댄다)
      if (next != null && _undisturbed(next, spot.was.shelfId, lean: false) && await commit(next)) {
        lastRestored = bookId;
        return true;
      }
    }
    lastRestored = null;
    for (final next in fitCandidates(l, books, bookId)) {
      if (_undisturbed(next, placementOf(next, bookId)!.shelfId)) return commit(next);
    }
    return false;
  }

  /// 책장에 없는 책으로 둔다(이미 어디든 있으면 그대로)
  Future<bool> addToDrawer(String bookId) async {
    final l = layout;
    if (l == null) return false;
    if (l.drawer.contains(bookId) || placementOf(l, bookId) != null) return true;
    return commit(normalize(ShelfLayout(l.shelves, l.placements, [bookId, ...l.drawer])));
  }

  /// 책장에서 빼기(책은 전체 책에 남는다). 있던 자리를 기억해 다시 진열할 때 그 자리로 돌린다
  Future<bool> toDrawer(String bookId) async {
    final l = layout;
    final r = l == null ? null : moveToDrawer(l, bookId, books);
    final p = l == null ? null : placementOf(l, bookId);
    if (r == null || !r.ok || !await commit(r.layout!)) return false;
    if (p != null) {
      final index = shelfItems(l!, p.shelfId).indexWhere((it) => it.bookIds.contains(bookId));
      _spots[bookId] = (was: p, index: index);
    }
    return true;
  }

  /// 선반 한 칸 더 열기(맨 끝에 빈 선반)
  Future<bool> addShelf() async {
    final l = layout;
    return l != null && await commit(addShelfTo(l, 'shelf-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'));
  }

  /// 지우거나 숨긴 책을 배치에서 뺀다(지금 앱 syncBooks: 서재에 없는 책은 배치에서 빠진다)
  Future<void> forget(Iterable<String> ids) async {
    final l = layout;
    final gone = ids.toSet();
    if (l == null || gone.isEmpty) return;
    books = {for (final e in books.entries) if (!gone.contains(e.key)) e.key: e.value};
    _spots.removeWhere((id, _) => gone.contains(id));
    final next = resolveLeans(
        normalize(ShelfLayout(l.shelves, [for (final p in l.placements) if (!gone.contains(p.bookId)) p], [for (final id in l.drawer) if (!gone.contains(id)) id])), books);
    _undo = null;
    await _write(next);
  }

  Future<bool> undo() async {
    final prev = _undo;
    if (prev == null || layout == null) return false;
    _undo = null;
    // 빼기를 되돌려 책장에 다시 선 책은 기억한 자리가 필요 없다
    _spots.removeWhere((id, _) => placementOf(prev, id) != null);
    await _write(_withMissing(prev));
    return true;
  }
}

/// 편집 실패 까닭 → 알림 글(지금 앱 ko.fail)
const editFailText = {
  'no-space': '공간이 부족해요. 다른 자리로 옮겨 주세요.',
  'unsupported': '아래 책 위에 다 올라가지 않아요. 더 큰 책 위에 쌓아 주세요.',
  'spin-only-lying': '눕힌 책만 돌릴 수 있어요.',
  'stack-full': '쌓기는 3권까지예요.',
  'not-stackable': '눕힌 책끼리만 쌓을 수 있어요.',
  'tilt-only-spine': '세운 책만 기울일 수 있어요.',
  'cannot-lean': '이 책은 두꺼워서 기울여 기댈 수 없어요.',
  'shelf-not-empty': '책이 있는 선반은 지울 수 없어요.',
  'outside': '책장 안에 놓아 주세요.',
};
