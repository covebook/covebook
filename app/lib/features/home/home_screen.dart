// 홈 화면(책장 탭): 서재를 읽어 줄마다 굽고(담아 둔 그림이 있으면 그대로) 실제 책장을 그린다. 지금 앱 features/home/HomeScreen을 옮기는 중.
// 머리줄·하단바 덮개·책장 그림까지. 측정: 켤 때마다 logcat에 [flbake] 줄마다·[fltotal] 합, 제목을 길게 누르면 다시 굽는다
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, Ticker;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;

import '../../services/qa_probe.dart';
import '../../services/cover_colors.dart';
import '../../ui/kit.dart' show Btn, PullUp, Space, showSheet;
import 'locked_rows.dart';
import '../../store/entitlement_store.dart';
import '../book/place_books.dart' show lockedShelfIds;
import '../iap/shelf_purchase_sheet.dart' show showShelfPurchase;
import 'refunded_shelf_mark.dart';
import 'book_sheet.dart';
import '../settings/settings_screen.dart' show openProfile;
import '../store/store_screen.dart' show openStore;
import 'decorate_panel.dart';
import 'year_pager.dart';
import '../../domain/bookcase.dart' show Bookcase;
import '../../store/bookcase_store.dart';
import '../../app/app_shell.dart' show tabBarHidden;
import '../../app/app_nav.dart' show AppNav, AppTab;
import '../../app/startup.dart' show shelfReady;
import '../../domain/geometry.dart' show maxFrontSpin, maxSpin;
import '../../domain/layout.dart' show ShelfLayout, placementOf, shelfItems, sortedShelves;
import '../../domain/book3_physics.dart' show fromPlaced;
import '../../domain/geometry.dart' show shelfUsableWidth;
import '../../domain/layout_engine.dart';
import '../../domain/types.dart' show Book, Pose, tiltToward;
import '../../domain/shelf_scene.dart' show computeShelf, resolveLeans;
import '../../domain/vec3.dart' show C3, Vec3;
import '../../domain/book3.dart' show corners, toWorld;
import '../../domain/front_pose.dart' show FrontState;
import '../../domain/placed.dart' show jsRound;
import '../../store/mini_timer_store.dart' show MiniTimerPlace;
import '../../store/placement_store.dart';

import '../../domain/camera.dart';
import '../../domain/place_books.dart';
import '../../domain/shelf_row.dart';
import '../../services/cover_cache.dart';
import '../../store/files.dart' show imageDir;
import '../../store/library_store.dart';
import '../../store/library_model.dart';
import '../../domain/library.dart' as dl show Library;
import '../../store/first_shelf.dart';
import '../../ui/artwork_images.dart' show loadArtworkImages;
import '../../ui/bake.dart';
import '../../ui/bake_cache.dart';
import '../../ui/book_key.dart';
import '../../ui/cover_photo.dart';
import '../../scene_config/spine_look.dart';
import '../../scene_config/skin.dart' show skinChoice;
import '../../domain/ribbon_design.dart' show ribbonDesign;
import '../../services/shelf_widget.dart';
import 'row_tween.dart';
import '../../store/settings_store.dart' show SettingsStore;
import '../../ui/glyph_metrics.dart';
import '../../ui/metrics.dart';
import '../../ui/outline.dart';
import '../../ui/plane_key.dart';
import '../../ui/ribbons.dart';
import '../../ui/row_bake.dart';
import '../../ui/scene.dart';
import '../../ui/theme.dart';
import '../../ui/a11y_text.dart';
import '../book/add_book_screen.dart' show openAddBook;

/// 앱이 깨어난 때(main이 채운다). 켜고 책장이 다 될 때까지를 잰다
DateTime bootAt = DateTime.now();

class RowRun {
  RowRun(this.items, this.w, this.h, this.gridMs, this.bakeMs);
  final int items;
  final int w;
  final int h;
  final int gridMs;
  final int bakeMs;
  int get total => gridMs + bakeMs;
}

class Run {
  Run(this.rows, this.loadMs, this.sinceBoot);
  final List<RowRun> rows;
  final int loadMs;
  final int sinceBoot;
  int get bakeTotal => rows.fold(0, (t, r) => t + r.total);
  int get gridTotal => rows.fold(0, (t, r) => t + r.gridMs);
}

/// 창빛 그림자 그림의 배율(설계 단위 → 그림 칸). 지금 앱은 화면 배율을 쓴다

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _scroll = ScrollController();

  // ---------- 지난 연도 책장(지금 앱 YearPager) ----------
  final _pagerKey = GlobalKey<YearPagerState>();
  List<Bookcase> _bookcases = BookcaseStore.instance.bookcases;
  bool _pinching = false;
  void _bookcasesChanged() {
    if (mounted) setState(() => _bookcases = BookcaseStore.instance.bookcases);
  }

  // ---------- 누르기·꾸미기(책장 편집) ----------
  /// 마지막으로 그린 책장 기하(누른 책 찾기용): 줄 자리·화면 배율·머리글 아래 끝·잠긴 칸 시작
  ({ShelfMetrics m, List<RowGeom> geo, double contentTop, int lockedFrom})? _geom;
  bool _decorating = false;

  /// 꾸미는 동안은 머리글(제목·연도·버튼)을 빼고 책장을 위로 붙여 넓게 쓴다(되돌리기·완료는 조작부 제목 줄, 지금 앱 bare).
  /// 꾹 눌러 끌며 꾸미기를 시작했으면 놓은 뒤에 뺀다(끄는 도중 손가락 아래 책장이 밀리지 않게)
  bool _bare = false;
  String? _editId;
  String? _editMsg;
  ({
    String title,
    Pose pose,
    int lean,
    ({bool left, bool right}) canLean,
    double spin,
    double spinMax,
    ({double lo, double hi})? spinRange,
    ({double lo, double hi, double z, double back}) depth,
    ({bool left, bool right}) canMove,
    String place,
  })? _panel;

  /// 정보 시트를 연 책(시트가 열린 동안 윤곽 빛)
  String? _popId;

  /// 보여 달라는 책(막 넣은 책은 책장을 새로 굽는 동안 아직 줄에 없다: 굽기가 끝난 뒤 다시 찾는다)
  String? _pendingFocus;

  void _focusBook() {
    final id = focusBookOnShelf.value;
    if (id == null) return;
    focusBookOnShelf.value = null;
    _pendingFocus = id;
    _tryFocus();
  }

  /// 그 책이 있는 줄이 화면 가운데쯤 오게 넘기고 2.5초 윤곽을 빛낸다(2026-11-15 QA: 책을 넣고 '책장에서 보기'를 눌러도 맨 위에 머물렀다)
  void _tryFocus() {
    final id = _pendingFocus, g = _geom, c = _case;
    if (id == null || g == null || c == null) return;
    // 지난 책장을 보고 있었으면 지금 책장으로
    _pagerKey.currentState?.goTo(0);
    final i = [for (var k = 0; k < c.rows.length; k++) if (c.rows[k].books.any((b) => b.id == id)) k].firstOrNull;
    if (i == null || i >= g.geo.length) {
      // 굽는 중이거나 다시 구울 차례면 끝난 뒤 다시 찾는다(_run 끝). 아니면 책장에 없는 책이다
      if (!_busy && !_again && !_rebuild) _pendingFocus = null;
      return;
    }
    _pendingFocus = null;
    if (_scroll.hasClients) {
      final r = g.geo[i];
      final p = _scroll.position;
      final target = (g.contentTop + r.top + r.height / 2 - p.viewportDimension / 2).clamp(0.0, p.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
    setState(() => _popId = id);
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _popId == id) setState(() => _popId = null);
    });
  }

  /// 그린 책(잠긴 칸 빼고)마다 화면 윤곽(콘텐츠 좌표)과 가장 앞 깊이. 줄마다 그릴 때와 같은 카메라·변환
  Iterable<({String id, ui.Path path, double z})> _outlines([String? only]) sync* {
    final g = _geom, c = _case;
    if (g == null || c == null) return;
    final cam = Cam(viewPitchMin);
    for (var i = 0; i < g.lockedFrom && i < g.geo.length && i < c.rows.length; i++) {
      final px = Affine(g.m.scale, g.m.originX + sideMargin * g.m.scale, g.contentTop + g.geo[i].baseline);
      for (final b in c.rows[i].books) {
        if (only != null && b.id != only) continue;
        yield (id: b.id, path: bookOutline(cam, px, b), z: corners(b).map((v) => v.z).reduce(math.min));
      }
    }
  }

  /// 누른 점 아래의 책: 윤곽 안에 든 것 중 가장 앞(깊이 작은) 책
  String? _hitBook(Offset p) {
    String? best;
    var bestZ = double.infinity;
    for (final o in _outlines()) {
      if (o.z < bestZ && o.path.contains(p)) {
        bestZ = o.z;
        best = o.id;
      }
    }
    return best;
  }

  ui.Path? _outlineOf(String? id) => id == null ? null : _outlines(id).firstOrNull?.path;

  Future<void> _onTap(Offset p) => _tapBook(_hitBook(p));

  /// 책 누르기(화면 읽기의 책 칸도 같다): 꾸미는 중이면 고르기, 아니면 책 정보 시트
  Future<void> _tapBook(String? id) async {
    if (_decorating) {
      setState(() {
        _drag = null;
        _editId = id;
        _editMsg = null;
      });
      _computePanel();
      return;
    }
    if (id == null) return;
    setState(() => _popId = id);
    await showBookSheet(context, id);
    if (mounted) setState(() => _popId = null);
  }

  /// 책장 책마다 화면 읽기 칸(책장은 그림이라 책이 화면 구조에 잡히지 않았다, 2026-11-15 QA): 윤곽 상자 자리에 제목·저자.
  /// 책장 그림·자리가 그대로면 지난번 것을 쓴다
  /// 화면 읽기 차례는 위 선반부터, 한 선반 안에서는 왼쪽 책부터(2026-11-16 QA 영숙 F11: 오른쪽 책을 먼저 읽었다)
  ({Object key, List<({String id, Rect rect, String label})> list})? _semCache;
  List<({String id, Rect rect, String label})> _bookSemantics() {
    final g = _geom, c = _case;
    if (g == null || c == null) return const [];
    final key = (c, _libBooks, g.contentTop, g.m.scale, g.m.originX, g.geo.length, g.lockedFrom);
    final hit = _semCache;
    if (hit != null && hit.key == key) return hit.list;
    final byId = {for (final b in _libBooks) b.id: b};
    final rowOf = {for (var i = 0; i < c.rows.length; i++) for (final b in c.rows[i].books) b.id: i};
    final list = [
      for (final o in _outlines())
        if (byId[o.id] case final b?) (id: o.id, rect: o.path.getBounds(), label: a11yLabel([b.title, ?b.author].join(', '))),
    ]..sort((a, b) {
        final r = (rowOf[a.id] ?? 0).compareTo(rowOf[b.id] ?? 0);
        return r != 0 ? r : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    _semCache = (key: key, list: list);
    return list;
  }

  Future<void> _enterDecorate([String? id]) async {
    await PlacementStore.instance.ensure();
    if (!mounted) return;
    setState(() {
      _decorating = true;
      _editId = id;
      _editMsg = null;
    });
    tabBarHidden.value = true;
    MiniTimerPlace.instance.setHidden(true);
    _computePanel();
  }

  void _exitDecorate() {
    _clearPreview();
    setState(() {
      _drag = null;
      _decorating = false;
      _editId = null;
      _panel = null;
      _editMsg = null;
    });
    tabBarHidden.value = false;
    MiniTimerPlace.instance.setHidden(false);
  }

  /// 고른 책의 조작부 값(자세·기대기 가능 방향·회전 범위·앞뒤 범위)
  void _computePanel() {
    final s = PlacementStore.instance, l = s.layout, id = _editId;
    final p = l == null || id == null ? null : placementOf(l, id);
    if (l == null || id == null || p == null) {
      setState(() => _panel = null);
      return;
    }
    // 기울이면 실제로 기대는지(닿을 곳이 없으면 바로 선다). 그 선반만 풀어 본다
    bool can(int d) {
      if (p.pose != Pose.upright) return false;
      if (p.tilt.sign == d) return true;
      final r = setTilt(l, s.books, id, tiltToward(d));
      return r.ok && (placementOf(resolveLeans(r.layout!, s.books, p.shelfId), id)?.tilt ?? 0) != 0;
    }

    final fs = p.pose == Pose.front ? frontStateOf(l, s.books, id) : null;
    // 순서 단추(왼쪽·오른쪽 한 칸)와 지금 자리: 몇 번째 선반의 왼쪽에서 몇 번째(쌓인 책은 더미째 센다)
    final items = shelfItems(l, p.shelfId);
    final at = items.indexWhere((it) => it.bookIds.contains(id));
    final shelfNo = sortedShelves(l).indexWhere((x) => x.id == p.shelfId) + 1;
    setState(() => _panel = (
          title: s.books[id]?.title ?? '',
          pose: p.pose == Pose.front && (p.pitch ?? 0) >= 89.95 ? Pose.horizontal : p.pose,
          lean: p.tilt.sign,
          canLean: (left: can(-1), right: can(1)),
          spin: fs?.state.spin ?? p.spin ?? 0,
          spinMax: p.pose == Pose.front ? maxFrontSpin : maxSpin,
          spinRange: spinRangeOf(l, s.books, id),
          depth: reachableDepth(l, s.books, id),
          canMove: (left: at > 0 || p.stackId != null, right: (at >= 0 && at < items.length - 1) || p.stackId != null),
          place: '$shelfNo번째 선반 | 왼쪽에서 ${at + 1}번째 / ${items.length}',
        ));
  }

  /// 편집 결과 확정(실패면 까닭을 조작부에, 성공 알림은 note)
  Future<bool> _apply(EditResult r, [String? note]) async {
    if (!r.ok) {
      setState(() => _editMsg = r.reason == 'no-change' ? null : editFailText[r.reason] ?? editFailText['outside']);
      return false;
    }
    final ok = await PlacementStore.instance.commit(r.layout!);
    if (!mounted) return ok;
    setState(() => _editMsg = ok ? note : editFailText['no-space']);
    _computePanel();
    return ok;
  }

  /// 고른 책에 편집 한 번(배치·책이 있을 때만)
  void _edit(EditResult Function(ShelfLayout l, BookMap books, String id) op) {
    final s = PlacementStore.instance, l = s.layout, id = _editId;
    if (l == null || id == null) return;
    _apply(op(l, s.books, id));
  }

  void _editPose(Pose pose) {
    if (_panel?.pose != pose) _edit((l, b, id) => setPose(l, b, id, pose));
  }

  void _editLean(int d) {
    if (_panel?.lean != d) _edit((l, b, id) => setTilt(l, b, id, tiltToward(d)));
  }

  void _editSpin(double deg) => _edit((l, b, id) {
        if (placementOf(l, id)?.pose != Pose.front) return setSpin(l, b, id, deg);
        final fs = frontStateOf(l, b, id);
        final r = fs == null ? null : frontSpin(l, b, id, fs.state, fs.qx, deg);
        return r == null ? const EditResult.fail('no-space') : EditResult.ok(r.layout);
      });

  void _editDepth(double z) => _edit((l, b, id) => setDepth(l, b, id, z));

  /// 고른 책을 같은 선반에서 한 칸 옮기기(2026-11-16 QA 영숙 F8: 끌기 말고는 순서를 바꿀 길이 없어 화면 읽기 사용자는 못 바꿨다)
  void _editMove(int d) => _edit((l, b, id) => moveBy(l, b, id, d));

  // ---------- 끌어 옮기기(지금 앱 HomeScreen beginDrag·endDrag, useShelfDragPreview) ----------
  /// 잡은 책: 잡은 곳(콘텐츠 좌표)·잡은 항목 가운데와 폭(설계 단위)·윤곽·끄는 책을 뺀 배치(끌기 한 번에 한 번만 계산)
  ({String id, String shelfId, Offset start, double centerDU, double widthDU, ui.Path path, ShelfLayout detached})? _drag;
  Offset _dragNow = Offset.zero;
  bool _dragOk = true;

  void _beginDrag(Offset at) {
    final id = _hitBook(at);
    final path = _outlineOf(id);
    final s = PlacementStore.instance, l = s.layout;
    final p = l == null || id == null ? null : placementOf(l, id);
    if (l == null || p == null || path == null) return;
    // 잡은 항목(더미의 받침이면 더미 전체)의 곧은 3D 상자: 가운데와 폭
    final item = shelfItems(l, p.shelfId).where((it) => it.bookIds.contains(id)).firstOrNull;
    final bx = boxOf(l, s.books, id!);
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final c in bx == null ? const <Vec3>[] : corners(fromPlaced(bx))) {
      lo = math.min(lo, c.x);
      hi = math.max(hi, c.x);
    }
    setState(() {
      _decorating = true;
      _editId = id;
      _editMsg = null;
      _frozen = true; // 끄는 책은 굳힌 책장 그림에서 떠 온다
      _dragNow = at;
      _dragOk = true;
      _drag = (
        id: id,
        shelfId: p.shelfId,
        start: at,
        centerDU: (lo + hi) / 2,
        widthDU: item != null ? itemWidth(item, l, s.books) : hi - lo,
        path: path,
        detached: detach(l, id, s.books),
      );
    });
    tabBarHidden.value = true;
    // 꾸미는 동안 작은 타이머는 숨긴다: 조작부의 위치 mm·회전 값을 가렸다(2026-11-16 QA 현우 F9)
    MiniTimerPlace.instance.setHidden(true);
    _computePanel();
    _dragTarget = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_drag?.id == id) _showPreview(l, {p.shelfId}, hide: id, key: 'lifted');
    });
  }

  /// 손가락 자리의 놓을 자리(늘 확정 배치에서 계산: 같은 줄이면 바꿔 놓기, 다른 줄이면 끄는 책을 뺀 배치에서 놓을 자리).
  /// key가 같으면 놓은 배치도 같다(손가락이 움직여도 자리가 그대로면 다시 계산하지 않는다)
  ({String key, String? shelfId, EditResult Function() run}) _targetAt(Offset at) {
    final d = _drag, g = _geom, s = PlacementStore.instance, l = s.layout;
    if (d == null || g == null || l == null) return (key: 'none', shelfId: null, run: () => const EditResult.fail('no-change'));
    final shelves = sortedShelves(l);
    final cy = at.dy - g.contentTop;
    final index = g.geo.isEmpty || cy < g.geo.first.top ? -1 : g.geo.indexWhere((r) => cy >= r.top && cy < r.top + r.height);
    final centerDU = d.centerDU + (at.dx - d.start.dx) / g.m.scale;
    final withinX = centerDU > -sideMargin && centerDU < shelfUsableWidth + sideMargin;
    if (!withinX || index < 0 || index >= shelves.length) return (key: 'outside', shelfId: null, run: () => const EditResult.fail('outside'));
    final shelfId = shelves[index].id;
    // 환불로 잠긴 선반에는 다른 선반의 책을 새로 꽂지 못한다(그 선반 안에서 자리를 바꾸거나 밖으로 빼는 것은 된다, D13)
    if (shelfId != d.shelfId && lockedShelfIds().contains(shelfId)) return (key: 'locked:$shelfId', shelfId: null, run: () => const EditResult.fail('shelf-locked'));
    if (shelfId == d.shelfId) {
      final t = findSwapTarget(l, s.books, d.id, centerDU);
      return (key: 'same:${t.kind}:${t.itemKey}:${t.index}:${t.x}:${t.dx}', shelfId: shelfId, run: () => applySwapTarget(l, s.books, d.id, t));
    }
    final t = findDropTarget(d.detached, s.books, shelfId, centerDU, placementOf(l, d.id)!.pose, d.widthDU);
    return (key: 'other:$shelfId:${t.kind}:${t.itemKey}:${t.index}:${t.x}', shelfId: shelfId, run: () => moveBook(l, s.books, d.id, t));
  }

  /// 마지막으로 본 놓을 자리와 그 결과
  ({String key, EditResult result})? _dragTarget;

  EditResult _dropAt(Offset at) {
    final t = _targetAt(at);
    final last = _dragTarget;
    if (last != null && last.key == t.key) return last.result;
    final r = t.run();
    _dragTarget = (key: t.key, result: r);
    // 미리 보기: 놓을 수 있으면 그 배치(기대기까지 그 줄에서 풀어 둔다: 놓는 순간 각도가 튀지 않게), 아니면 확정 배치에서 든 책만 빠진다
    final d = _drag!, l = PlacementStore.instance.layout!, books = PlacementStore.instance.books;
    if (r.ok && t.shelfId != null) {
      final src = t.shelfId == d.shelfId ? r.layout! : resolveLeans(r.layout!, books, d.shelfId);
      _showPreview(resolveLeans(src, books, t.shelfId), {d.shelfId, t.shelfId!}, hide: d.id, key: t.key);
    } else {
      _showPreview(l, {d.shelfId}, hide: d.id, key: 'lifted');
    }
    return r;
  }

  // 가장자리 자동 스크롤(지금 앱 autoScroll: 끄는 동안만, 화면 위아래 72 안이면 한 틀에 최대 14씩). 스크롤하면서도 손가락 자리로 놓을 자리를 다시 본다
  final _viewportKey = GlobalKey();
  Offset? _dragGlobal;
  Timer? _autoScroll;

  void _autoScrollTick() {
    final g = _dragGlobal, box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (_drag == null || g == null || box == null || !_scroll.hasClients) return;
    const edge = 72.0, speed = 14.0;
    final y = box.globalToLocal(g).dy, h = box.size.height;
    final delta = y < edge ? -speed * math.min(1, (edge - y) / edge) : y > h - edge ? speed * math.min(1, (y - (h - edge)) / edge) : 0.0;
    if (delta == 0) return;
    final p = _scroll.position;
    final next = (p.pixels + delta).clamp(0.0, p.maxScrollExtent);
    if (next == p.pixels) return;
    _scroll.jumpTo(next);
    final local = box.globalToLocal(g);
    _moveDrag(Offset(local.dx, local.dy + next));
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragGlobal = null;
  }

  void _moveDrag(Offset at) {
    if (_drag == null) return;
    final r = _dropAt(at);
    setState(() {
      _dragNow = at;
      _dragOk = r.ok || r.reason == 'no-change';
    });
  }

  Future<void> _endDrag() async {
    _stopAutoScroll();
    final d = _drag;
    if (d == null) return;
    final r = _dropAt(_dragNow);
    setState(() => _drag = null);
    _dragTarget = null;
    // 성공은 알리지 않는다(바뀐 책장이 보이고, 바로 위에 되돌리기)
    if (!await _apply(r)) {
      _clearPreview();
      return;
    }
    // 놓은 책은 바로 보이게: 확정 배치로 미리 보기를 바꿔 그린다(끄는 동안의 미리 보기는 든 책을 뺀 줄이라, 새로 굽기가 끝날 때까지 빈칸이었다.
    // 2026-11-15 QA 6.6초). 빛은 지난 그림에서 면 이름으로 옮겨 쓰고, 새로 구운 그림이 오면 바뀐다(_run 끝에서 미리 보기를 걷는다)
    final l = PlacementStore.instance.layout;
    final to = l == null ? null : placementOf(l, d.id)?.shelfId;
    if (mounted && l != null && to != null) _showPreview(l, {d.shelfId, to}, key: 'dropped:${DateTime.now().microsecondsSinceEpoch}', bake: false);
  }

  // ---------- 미리 보기(끄는 동안 바뀐 선반만 그 배치로 그린다, 지금 앱 previewShelf) ----------
  /// 선반 차례 → 미리 보는 줄. 바로는 지난 그림의 빛(면 이름으로 자리를 옮겨 쓴다)으로, 잠시 뒤 그 배치로 구운 그림으로
  Map<int, _PreviewRow> _previewRows = const {};
  String? _previewKey;
  Timer? _previewBake;

  /// 그릴 줄 목록(미리 보는 줄을 끼운 것). 미리 보기가 바뀔 때만 새로 만든다(손가락이 움직일 때마다 책장을 다시 그리지 않게)
  ({List<RowCase> rows, List<ui.Image> atlases, List<List<Spot>> spots, List<({PlaneKey wall, PlaneKey floor})> keys, List<Map<String, BookKey>> bookKeys})? _shown;

  /// bake: 잠시 뒤 그 배치로 구워 빛(빠진 책 그늘 등)을 바로잡는다. 책을 끄는 동안은 손가락이 0.7초 머물 때만 굽는다: 굽기는 GPU를 몇 초씩 써서
  /// 자리를 지날 때마다 구우면 끄는 손이 끊겼다(2026-11-15 QA: 미리 보기 굽기 0.1~5초, 8초 동안 화면 22장). 그사이 빛은 지난 그림에서 면 이름으로 옮겨 쓴다
  void _showPreview(ShelfLayout l, Set<String> shelfIds, {String? hide, required String key, bool bake = true}) {
    final c = _case, s = PlacementStore.instance, committed = s.layout;
    if (c == null || committed == null || key == _previewKey) return;
    final shelves = sortedShelves(committed);
    final next = <int, _PreviewRow>{};
    for (final id in shelfIds) {
      final i = shelves.indexWhere((x) => x.id == id);
      if (i < 0 || i >= _rowSpots.length) continue;
      final bodies = [for (final f in computeShelf(l, s.books, id)) if (f.bookId != hide) fromPlaced(f.box)];
      final old = c.rows[i], oldSpots = _rowSpots[i];
      final row = rowFromBooks(bodies, _libBooks, rowSpace, top: old.top, last: old.last)..tabLoss = old.tabLoss;
      final spots = [
        for (final it in row.items)
          switch (old.indexOf(it.key)) { final k when k >= 0 && k < oldSpots.length => oldSpots[k], _ => oldSpots.first },
      ];
      next[i] = _PreviewRow(row, spots);
    }
    _previewKey = key;
    _setPreviewRows(next);
    _previewBake?.cancel();
    if (bake) _previewBake = Timer(Duration(milliseconds: _drag != null ? 700 : 150), () => _bakePreview(key));
  }

  Future<void> _bakePreview(String key) async {
    final grid = _gridSlots, bake = _bakeSlots;
    if (grid == null || bake == null) return;
    for (final e in Map.of(_previewRows).entries) {
      if (e.value.atlas != null) continue;
      // 차례를 기다리는 동안 손가락이 다른 자리로 가면 굽지 않는다
      final b = await bakeRow(grid, bake, BakeCase([e.value.row]), e.value.row, persist: false, tag: ' preview', wanted: () => mounted && _previewKey == key);
      if (b == null) return;
      if (!mounted || _previewKey != key) {
        b.image.dispose();
        return;
      }
      _setPreviewRows({..._previewRows, e.key: _PreviewRow(e.value.row, b.at, b.image, b.keys, b.bookKeys)});
    }
  }

  void _setPreviewRows(Map<int, _PreviewRow> next) {
    for (final e in _previewRows.entries) {
      if (!identical(next[e.key]?.atlas, e.value.atlas)) e.value.atlas?.dispose();
    }
    final c = _case;
    setState(() {
      _previewRows = next;
      _shown = next.isEmpty || c == null
          ? null
          : (
              rows: [for (var i = 0; i < c.rows.length; i++) next[i]?.row ?? c.rows[i]],
              atlases: [for (var i = 0; i < _atlases.length; i++) next[i]?.atlas ?? _atlases[i]],
              spots: [for (var i = 0; i < _rowSpots.length; i++) next[i]?.spots ?? _rowSpots[i]],
              keys: [for (var i = 0; i < _keys.length; i++) next[i]?.keys ?? _keys[i]],
              bookKeys: [for (var i = 0; i < _bookKeys.length; i++) next[i]?.bookKeys ?? _bookKeys[i]],
            );
    });
  }

  void _clearPreview() {
    _previewBake?.cancel();
    _previewKey = null;
    if (_previewRows.isNotEmpty) _setPreviewRows(const {});
  }

  // ---------- 표지 책 머리 손잡이(지금 앱 HeadHandle·onHandle): 위아래로 끌면 뒤로 젖히기, 좌우로 끌면 돌리기 ----------
  static const _tiltPerDu = 0.35; // 머리를 1DU 밀면 0.35° 젖힘(20°에 약 57DU)
  static const _spinPerDu = 0.9; // 좌우 1DU에 0.9°
  static const _handleHit = 48.0;
  static const _handleLiftDu = 7.0; // 머리보다 이만큼 위(3D 세로)에 손잡이

  ({String id, String shelfId, double qx, FrontState start})? _head;
  FrontState? _headCur;
  ShelfLayout? _headLast;
  bool? _headTilt; // 끄는 방향(조금 움직인 뒤 한 번 정한다): true 젖히기, false 돌리기
  ({double d, double a}) _headBase = (d: 0, a: 0);
  Offset _headDrag = Offset.zero, _headOff = Offset.zero;
  bool _headStepQueued = false;

  /// 손잡이 자리(콘텐츠 좌표): 고른 표지 책 머리 앞 가운데 바로 위
  Offset? _handlePoint() {
    final id = _editId, g = _geom, c = _case, l = PlacementStore.instance.layout;
    if (!_decorating || _drag != null || id == null || g == null || c == null || l == null || placementOf(l, id)?.pose != Pose.front) return null;
    final cam = Cam(viewPitchMin);
    for (var i = 0; i < g.lockedFrom && i < g.geo.length && i < c.rows.length; i++) {
      for (final b in c.rows[i].books) {
        if (b.id != id) continue;
        final head = toWorld(b, Vec3(b.dims.t, b.dims.h, b.dims.w / 2));
        return toPx(cam, Affine(g.m.scale, g.m.originX + sideMargin * g.m.scale, g.contentTop + g.geo[i].baseline), Vec3(head.x, head.y + _handleLiftDu, head.z));
      }
    }
    return null;
  }

  int? _headPointer;

  bool _headBegin() {
    final s = PlacementStore.instance, l = s.layout, id = _editId;
    final f = l == null || id == null ? null : frontStateOf(l, s.books, id);
    final shelfId = l == null || id == null ? null : placementOf(l, id)?.shelfId;
    if (f == null || shelfId == null) return false;
    setState(() {
      _head = (id: id!, shelfId: shelfId, qx: f.qx, start: f.state);
      _headCur = f.state;
      _headLast = null;
      _headTilt = null;
      _headDrag = Offset.zero;
      _headOff = Offset.zero;
      _editMsg = null;
    });
    return true;
  }

  void _headMove(Offset d) {
    _headDrag += d;
    if (_headStepQueued) return;
    _headStepQueued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) => _headStep());
  }

  /// 끈 거리 → 원하는 각도 → 실제로 되는 각도(옆 책·벽에 막히면 거기까지). 그 줄은 미리 보기로 바로 그린다
  void _headStep() {
    _headStepQueued = false;
    final h = _head, g = _geom, s = PlacementStore.instance, l = s.layout, cur = _headCur;
    if (h == null || g == null || l == null || cur == null) return;
    if (_headTilt == null) {
      if (_headDrag.distance < 4) return;
      _headTilt = _headDrag.dy.abs() >= _headDrag.dx.abs();
      _headBase = (d: 0, a: _headTilt! ? h.start.pitch : h.start.spin);
    }
    final tilt = _headTilt!;
    final gain = tilt ? _tiltPerDu : _spinPerDu;
    final d = (tilt ? -_headDrag.dy : _headDrag.dx) / g.m.scale; // 잡은 지점에서 축 방향으로 끈 거리(DU, 위·오른쪽이 +)
    final want = _headBase.a + (d - _headBase.d) * gain;
    final r = tilt ? frontTilt(l, s.books, h.id, cur, h.qx, want) : frontSpin(l, s.books, h.id, cur, h.qx, want);
    if (r == null) return;
    final got = tilt ? r.state.pitch : r.state.spin;
    // 돌리기는 0 근처에서 살짝 붙는다(frontSpin): 그만큼은 막힌 것이 아니다
    final aim = !tilt && want.abs() < 0.8 ? 0.0 : want;
    if ((got - aim).abs() > 0.05) _headBase = (d: d, a: got);
    _headCur = r.state;
    _headLast = r.layout;
    _showPreview(r.layout, {h.shelfId}, key: 'head:${r.state.pitch}:${r.state.spin}:${r.state.depth}');
    final off = (got - (tilt ? h.start.pitch : h.start.spin)) / gain * g.m.scale;
    setState(() => _headOff = tilt ? Offset(0, -off) : Offset(off, 0));
  }

  /// 놓으면: 받침을 잃은 표지 책은 무게중심에 따라 넘어져 벽·책·바닥에서 멈춘 자세로 저장한다(끄는 동안 마지막 배치에서)
  Future<void> _headEnd() async {
    if (_headStepQueued) _headStep();
    final h = _head, last = _headLast, cur = _headCur, s = PlacementStore.instance;
    setState(() {
      _head = null;
      _headOff = Offset.zero;
    });
    if (h == null || last == null || cur == null) {
      _clearPreview();
      return;
    }
    final fin = frontRelease(last, s.books, h.id, cur, h.qx);
    if (!await _apply(fin != null ? EditResult.ok(fin) : const EditResult.fail('no-space'))) _clearPreview();
  }

  void _headCancel() {
    setState(() {
      _head = null;
      _headOff = Offset.zero;
    });
    _clearPreview();
  }

  /// 표지 책 뒤로 젖힌 각도 글자(조작부). 끄는 동안만 '젖혔어요', 가만히 있을 때는 지금 상태와 바꾸는 법
  /// (2026-11-15 QA: 표지로 세우자마자 끌지도 않았는데 '머리를 끌어 뒤로 12° 젖혔어요'가 나왔다. 표지 책은 처음에 벽에 기대 젖혀 선다)
  String? get _anglesText {
    final s = PlacementStore.instance, l = s.layout, id = _editId;
    final pitch = _head != null ? _headCur?.pitch : (l == null || id == null ? null : frontStateOf(l, s.books, id)?.state.pitch);
    if (pitch == null) return null;
    final deg = jsRound(pitch).toInt();
    if (_head != null) return '뒤로 $deg° 젖혔어요';
    return pitch >= 0.5 ? '뒤로 $deg° 젖혀 있어요. 책 머리를 위아래로 끌면 바꿀 수 있어요.' : '책 머리를 위아래로 끌면 뒤로 젖힐 수 있어요.';
  }

  Future<void> _undo() async {
    await PlacementStore.instance.undo();
    if (!mounted) return;
    setState(() => _editMsg = null);
    _computePanel();
  }

  /// 지난 책장이 없는데 옆으로 밀었다: 언제 생기는지 알린다(10초에 한 번만)
  DateTime? _pastHintAt;
  void _noPastShelf(DragEndDetails d) {
    if (d.primaryVelocity == null || d.primaryVelocity!.abs() < 400) return;
    final now = DateTime.now();
    if (_pastHintAt != null && now.difference(_pastHintAt!).inSeconds < 10) return;
    _pastHintAt = now;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('해가 바뀌면 올해 책장이 지난 책장으로 남아요. 그때부터 옆으로 넘겨 볼 수 있어요.'),
      duration: Duration(seconds: 3),
      persist: false, // 정한 시간 뒤 꼭 사라지게(2026-11-16 QA 현우 F1)
    ));
  }

  /// 책장 그림(입력이 같으면 다시 쓰고, 바뀌면 다시 그린다)
  ui.Image? _shelfImage;

  /// 책장 그림이 마지막으로 바뀐 때: 연달아 바뀌는 동안(손잡이로 젖히기·앞뒤 막대처럼 매 프레임 바뀔 때)은 굳히지 않고 그대로 그리다가
  /// 멈추면 굳힌다(매 프레임 굳히면 그대로 그리는 것보다 무겁다)
  DateTime _shelfChangedAt = DateTime(0);
  Timer? _settleFreeze;

  /// 끄는 동안 굳힌 그림 위에 덧놓는 바뀐 줄 띠 그림(위 끝 · 어떤 줄 · 무엇으로 그렸는지)
  ui.Image? _overlay;
  double _overlayTop = 0;
  String? _overlayKey;
  Object? _shelfKey;
  bool _frozen = false;
  Timer? _freezeTimer;

  // ---------- 책 옮겨 가기(지금 앱 planner의 밀림·미리 보기 움직임, MOTION_MS 230, row_tween.dart) ----------
  static const _tweenMs = 230;
  final _tween = RowTween();
  double _tweenT = 1;
  Ticker? _tweenTicker;
  bool get _tweening => _tweenT < 1 && _tween.active;

  bool get _reduceMotion {
    final m = SettingsStore.instance.reduceMotion;
    return m == 'on' || (m == 'system' && MediaQuery.disableAnimationsOf(context));
  }

  /// 그릴 줄: 그릴 줄 목록이 바뀌면(미리 보기·새로 굽기) 지금 보이던 자세에서 움직임을 시작하고, 움직이는 동안은 섞은 자세의 줄
  List<RowCase> _moving(List<RowCase> target) {
    if (_tween.retarget(target, animate: !_reduceMotion)) {
      _tweenTicker ??= createTicker((elapsed) {
        if (!mounted) return;
        setState(() => _tweenT = math.min(1.0, elapsed.inMilliseconds / _tweenMs));
        if (_tweenT >= 1) _tweenTicker!.stop();
      });
      _tweenTicker!.stop();
      _tweenT = _tween.active ? 0 : 1;
      if (_tween.active) _tweenTicker!.start();
    }
    return _tween.at(Curves.easeOutCubic.transform(_tweenT));
  }

  /// 홈 화면 위젯 칸 넘기기: 책장 그림을 새로 굳히고 2초 동안 그대로면(표지 사진이 하나씩 올 때마다 다시 굳힌다) 넘긴다
  Timer? _widgetTimer;
  void _scheduleWidget() {
    _widgetTimer?.cancel();
    _widgetTimer = Timer(const Duration(seconds: 2), _sendWidget);
  }

  Future<void> _sendWidget() async {
    if (!mounted || _decorating || _drag != null || _shown != null || _head != null) return;
    final img = _shelfImage;
    if (img == null) return;
    final copy = img.clone();
    try {
      await sendShelfWidget(copy, MediaQuery.devicePixelRatioOf(context), _widgetRows(), AppColors.bg);
    } finally {
      copy.dispose();
    }
  }

  /// 위젯에 넘길 칸(잠긴 칸 빼고 위에서 네 칸): 자를 범위, 열쇠(칸 자리·책 자리·그림에 영향 주는 책 값·스킨·책 측면·표지 사진이 왔는지),
  /// 투명 위젯용 모양(책 윤곽·갈피 띠·선반 판 윤곽, 지금 앱 shelfCutShapes)
  List<WidgetRow> _widgetRows() {
    final g = _geom, c = _case;
    if (g == null || c == null) return const [];
    final cam = Cam(viewPitchMin);
    final s = g.m.scale;
    final n = [widgetRowsMax, g.lockedFrom, g.geo.length, c.rows.length].reduce(math.min);
    String f(double v) => v.toStringAsFixed(2);
    return [
      for (var i = 0; i < n; i++)
        () {
          final r = g.geo[i], row = c.rows[i];
          final px = Affine(s, g.m.originX + sideMargin * s, g.contentTop + r.baseline);
          final books = <List<double>>[], ribbons = <List<double>>[];
          final sig = StringBuffer('$i|${r.top.round()}|${r.height.round()}|${(s * 1000).round()}|${g.m.originX.round()}|${skinChoice.key}|${spineLook.value.name}');
          for (var j = 0; j < row.books.length; j++) {
            final b = row.books[j];
            final look = j < row.looks.length ? row.looks[j] : null;
            sig.write('|${b.id},${f(b.t.x)},${f(b.t.y)},${f(b.t.z)},${f(b.roll)},${f(b.yaw)},${f(b.spin)},${f(b.pitch)},${f(b.dims.t)},${f(b.dims.h)},${f(b.dims.w)}');
            if (look != null) {
              sig.write(',${look.title},${look.tone},${look.ink},${look.ribbons},${look.ribbon},${look.material},${look.artwork},${look.coverUri},${_photos.containsKey(look.coverUri)}');
            }
            final pts = bookOutlinePoints(cam, px, b);
            if (pts.length < 3) continue;
            books.add([for (final p in pts) ...[p.dx, p.dy]]);
            if (look != null && look.ribbons > 0) {
              final out = ribbonDesign(b.id, look.ribbons).map((t) => t.out).reduce(math.max);
              final up = (out + 3) * s;
              final xs = pts.map((p) => p.dx), ys = pts.map((p) => p.dy);
              final minX = xs.reduce(math.min), maxX = xs.reduce(math.max), minY = ys.reduce(math.min);
              ribbons.add([minX, minY - up, maxX - minX, up + 2 * s]);
            }
          }
          final board = plankShape((v) => toPx(cam, px, v), s).outline;
          return WidgetRow(
            key: widgetHash(sig.toString()),
            top: i == 0 ? g.contentTop : g.contentTop + r.top,
            bottom: g.contentTop + r.top + r.height,
            rel: i == 0 ? 0 : r.top,
            books: books,
            ribbons: ribbons,
            boards: [
              [for (final p in board) ...[p.dx, p.dy]],
            ],
          );
        }(),
    ];
  }

  /// 시작 사진(files/home_snapshot.png): 굳힌 책장 그림을 저장해 두고 다음에 켤 때 먼저 보인다
  ui.Image? _snap;
  static Future<File> _snapFile() => homeSnapshotFile();

  Future<void> _loadSnap() async {
    try {
      final f = await _snapFile();
      if (!f.existsSync()) return;
      final img = await decodeImageInLine(await f.readAsBytes());
      if (img == null) return;
      if (!mounted || _atlases.length > 1) {
        img.dispose();
        return;
      }
      setState(() => _snap = img);
      // ignore: avoid_print
      print('[flsnap] 시작 사진 ${img.width}x${img.height}');
    } catch (_) {
      // 없거나 깨졌으면 그냥 진짜 책장을 기다린다
    }
  }

  Future<void> _saveSnap(ui.Image img) async {
    try {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await (await _snapFile()).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } catch (_) {
      // 다음에 굳힐 때 다시 저장한다
    }
  }

  Widget _shelfLayer(ShelfPainter painter, Size size, double dpr) {
    final w = (size.width * dpr).ceil(), h = (size.height * dpr).ceil();
    // 셰이더가 아직 안 올라왔거나 그림이 너무 크면(텍스처 한도) 그대로 그린다
    // 켤 때는 화면에 보이는 만큼만 바로 그린다(한 장으로 굳히면 안 보이는 아래 줄까지 그려 책장이 1초쯤 늦게 뜬다).
    // 가만히 있게 되면(6초 뒤) 또는 밀기 시작하면 그림으로 굳힌다
    _freezeTimer ??= Timer(const Duration(seconds: 6), () {
      if (mounted && !_frozen) setState(() => _frozen = true);
    });
    // 끄는 동안(미리 보기): 들기 전 굳힌 그림 위에, 바뀐 줄과 그 아래 줄(겹치는 띠를 같은 순서로 덮으려고)만 그 띠 크기 그림으로 굳혀 덧놓는다.
    // 놓을 자리가 바뀔 때만 다시 굳히고 프레임마다는 그림 두 장만 옮긴다.
    // 2026-11-18 측정(에뮬레이터, 책 끌 때 프레임마다 GPU): 책장 전체를 셰이더로 다시 그리기 400~500ms → 바뀐 두 줄만 다시 그리기 160~350ms.
    // 미리 보기마다 책장 전체를 새로 굳히기는 0.9~2.7초로 더 무거웠다. 끄는 책은 들기 전 굳힌 그림에서 떠 온다
    final frozen = _shelfImage;
    if (_shown != null && frozen != null && _previewRows.isNotEmpty && ShelfPainter.ready) {
      final only = {for (final i in _previewRows.keys) ...[i, i + 1]};
      // 책들이 새 자리로 미끄러지는 동안(약 0.25초)은 그 두 줄만 그대로 그리고, 멈추면 굳힌다
      if (_tweening) {
        return Stack(fit: StackFit.expand, children: [
          RawImage(image: frozen, width: size.width, height: size.height, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill),
          CustomPaint(painter: painter.onlyRows(only)),
        ]);
      }
      final band = painter.bandOf(only, size);
      // 바뀌었는지: 어느 줄 · 미리 보기(_shown은 미리 보기가 바뀔 때만 새로 만든다) · 줄 빛 그림
      final okey = '${(only.toList()..sort()).join(',')}|${identityHashCode(_shown)}|${identityHashCode(painter.atlases)}|${painter.look}';
      final changed = _overlay == null || _overlayKey != okey;
      if (changed && band.$2 > band.$1) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec)
          ..scale(dpr)
          ..translate(0, -band.$1);
        painter.onlyRows(only).paint(canvas, size);
        final pic = rec.endRecording();
        final old = _overlay;
        _overlay = pic.toImageSync(w, ((band.$2 - band.$1) * dpr).ceil());
        _overlayTop = band.$1;
        _overlayKey = okey;
        pic.dispose();
        if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      final ov = _overlay;
      return Stack(fit: StackFit.expand, children: [
        RawImage(image: frozen, width: size.width, height: size.height, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill),
        if (ov != null)
          Positioned(
            left: 0,
            top: _overlayTop,
            width: size.width,
            height: ov.height / dpr,
            child: RawImage(image: ov, width: size.width, height: ov.height / dpr, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill),
          ),
      ]);
    }
    if (_overlay != null) {
      final o = _overlay!;
      _overlay = null;
      _overlayKey = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => o.dispose());
    }
    if (_shown != null || _tweening || !_frozen || !ShelfPainter.ready || h > 8192 || w > 8192) return CustomPaint(painter: painter);
    final key = (
      _runs.length,
      painter.look,
      painter.rows,
      painter.atlases,
      painter.rowSpots,
      painter.photos,
      painter.bookKeys,
      painter.keys,
      painter.contentTop,
      painter.bottomInset,
      painter.viewport,
      painter.frostedFrom,
      w,
      h,
    );
    if (_shelfImage == null || _shelfKey != key) {
      final now = DateTime.now();
      final rapid = _shelfImage != null && now.difference(_shelfChangedAt) < const Duration(milliseconds: 250);
      _shelfChangedAt = now;
      if (rapid) {
        _settleFreeze?.cancel();
        _settleFreeze = Timer(const Duration(milliseconds: 300), () {
          if (mounted) setState(() {});
        });
        return CustomPaint(painter: painter);
      }
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(dpr);
      painter.paint(canvas, size);
      final pic = rec.endRecording();
      final old = _shelfImage;
      _shelfImage = pic.toImageSync(w, h);
      _shelfKey = key;
      pic.dispose();
      final saved = _shelfImage!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _saveSnap(saved));
      _scheduleWidget();
      // 시작 사진은 진짜 책장이 떴으니 놓는다
      final s0 = _snap;
      if (s0 != null) {
        _snap = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => s0.dispose());
      }
      // 앞 장은 이번 화면이 다 그려진 뒤 놓는다
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return RawImage(image: _shelfImage, width: size.width, height: size.height, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill);
  }

  final List<Run> _runs = [];
  final List<ui.Image> _atlases = [];
  final List<List<Spot>> _rowSpots = [];
  final List<double> _spaces = [];
  final List<({PlaneKey wall, PlaneKey floor})> _keys = [];
  String _state = '준비 중…';

  /// 줄마다 책이 받는 창빛 그림자(책 id → 면 칸 그림)
  List<Map<String, BookKey>> _bookKeys = const [];

  /// 지금 책장의 책 정보(줄을 다시 만들 때)
  List<Book> _libBooks = const [];

  /// 지난 굽기의 줄별 결과(굽기 열쇠 → 그림·그림자 열쇠·갈피 손실). 다음 굽기에서 바뀌지 않은 줄은 그대로 쓴다
  Map<String, _RowDone> _rowDone = {};

  /// 받아 온 표지 사진(주소 → 그림). 받는 대로 다시 그린다(그 전까지는 코드로 그린 장정)
  Map<String, CoverPhoto> _photos = const {};
  bool _busy = false;

  /// 줄 가운데 맨 끝 몇 줄이 잠긴 칸인지
  int _lockedCount = 0;
  BakeCase? _case;
  ShaderSlots? _gridSlots;
  ShaderSlots? _bakeSlots;

  @override
  void initState() {
    super.initState();
    shelfRefresh.addListener(_refresh);
    spineLook.addListener(_spineLookChanged);
    focusBookOnShelf.addListener(_focusBook);
    LibraryModel.instance.addListener(_libraryChanged);
    BookcaseStore.instance.addListener(_bookcasesChanged);
    // 구매·환불로 쓸 수 있는 선반 칸이 바뀌면 환불된 선반 표시를 다시 그린다
    if (iapOn) EntitlementStore.instance.addListener(_entitlementChanged);
    if (!BookcaseStore.instance.loaded) BookcaseStore.instance.load();
    _loadSnap();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    WidgetsBinding.instance.addObserver(this);
  }

  /// 앱이 앞으로 오면 받지 못한 표지를 다시 받아 본다. 뒤로 가면 다시 받기를 멈춘다
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryCovers(reset: true);
    } else if (state == AppLifecycleState.paused) {
      _coverRetry?.cancel();
      _coverRetry = null;
    }
  }

  /// 받지 못한 표지(인터넷 없이 복원·추가한 책은 코드로 그린 표지로 그렸다)를 앱이 앞으로 올 때와 잠시 뒤마다(30초부터 10분까지 늘려 가며) 다시 받는다.
  /// 받는 대로 책장을 다시 그린다(2026-11-16 QA 현우 F2: 인터넷이 돌아와도 앱을 다시 켜야 표지가 돌아왔다)
  Timer? _coverRetry;
  int _coverTries = 0;

  void _retryCovers({bool reset = false}) {
    if (reset) _coverTries = 0;
    _coverRetry?.cancel();
    _coverRetry = null;
    if (!mounted) return;
    final missing = [for (final b in _libBooks) if (b.coverArtUri case final u? when !_photos.containsKey(u)) u];
    if (missing.isEmpty) return;
    _loadCovers(missing);
    _coverRetry = Timer(Duration(seconds: math.min(600, 30 << math.min(_coverTries, 5))), _retryCovers);
    _coverTries++;
  }

  /// 서재(갈피·장정·책 정보)가 바뀌면 책장 모습도 바뀔 수 있다: 책장에 보이는 값만 모은 열쇠가 바뀌었을 때만 다시 만든다
  /// (2026-11-15 QA: 갈피를 남겨도 책을 하나 더 넣기 전까지 갈피 탭이 안 보였다). 바뀌지 않은 줄의 구운 그림은 그대로 쓴다
  String? _lookSig;
  void _libraryChanged() {
    final model = LibraryModel.instance;
    if (!model.loaded) return;
    final sig = shelfLookSignature(model.lib);
    final changed = _lookSig != null && sig != _lookSig;
    _lookSig = sig;
    // DB에 다 쓴 뒤 읽는다(서재 모델은 먼저 바뀌고 쓰기는 뒤따른다)
    if (changed) model.flushPending().then((_) => _refresh());
  }

  // 표지 색·두께·갈피 색이 새로 맞춰졌다: 줄을 서재에서 다시 만들어 굽는다(굽는 중이면 끝난 뒤)
  bool _again = false;
  void _refresh() {
    if (!mounted) return;
    if (_busy) {
      _again = true;
      return;
    }
    _rebuild = true;
    _run();
  }

  /// 다음 굽기에서 줄을 서재로부터 새로 만든다(그동안 화면은 지난 줄·그림 그대로: 둘은 굽기가 끝날 때 함께 바꾼다)
  bool _rebuild = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _state = '굽는 중…';
    });
    final t0 = DateTime.now();
    // 셰이더는 빌드할 때 미리 컴파일돼 있다(impellerc). 여기서는 읽어 올리기만 한다
    // 서재(SQLite)에서 책과 자리를 읽어 줄을 만든다. 비어 있으면 보기 책을 넣는다
    await prepareFirstShelf();
    final lib = await loadLibrary();
    PlacementStore.instance.adopt(lib);
    _loadCovers([for (final b in lib.books) ?b.coverArtUri]);
    // 못 받은 표지는 잠시 뒤 다시(앞서 걸어 둔 다시 받기가 있으면 그대로)
    _coverRetry ??= Timer(const Duration(seconds: 30), _retryCovers);
    final shelves = placeShelves(lib);
    // 마지막 선반 아래 잠긴 칸(다섯 칸까지): 흐린 예시 책
    final locked = [for (var i = 0; i < lockedShelfCount(shelves.length); i++) await lockedRow(i)];
    final lockedCount = locked.length;
    final rebuild = _rebuild;
    _rebuild = false;
    final c = _case != null && !rebuild ? _case! : BakeCase([
      for (var i = 0; i < shelves.length; i++) rowFromBooks(shelves[i], lib.books, rowSpace, top: i == 0, last: i == shelves.length - 1 && locked.isEmpty),
      for (var i = 0; i < locked.length; i++) rowFromBooks(locked[i].bodies, locked[i].books, rowSpace, last: i == locked.length - 1),
      probeRow(),
    ]);
    await ShelfPainter.load();
    final gridSlots = _gridSlots ??= ShaderSlots(await ui.FragmentProgram.fromAsset('shaders/grid.frag'), gridUniformNames);
    final bakeSlots = _bakeSlots ??= ShaderSlots(await ui.FragmentProgram.fromAsset('shaders/bake.frag'), bakeUniformNames);
    final loadMs = DateTime.now().difference(t0).inMilliseconds;

    await loadBakeCache();
    final rows = <RowRun>[];
    final images = <ui.Image>[];
    final spots = <List<Spot>>[];
    final spaces = <double>[];
    final keys = <({PlaneKey wall, PlaneKey floor})>[];
    final bookKeys = <Map<String, BookKey>>[];
    final done = <String, _RowDone>{};
    for (var ri = 0; ri < c.rows.length; ri++) {
      final r = c.rows[ri];
      final probe = ri == c.rows.length - 1; // 맨 뒤는 값 확인용(시간에 넣지 않는다)
      final key = bakeKey(r);
      // 지난번과 같은 줄(책을 옮긴 줄 말고는 다 그렇다): 구운 그림·그림자 열쇠·갈피 손실을 그대로 쓴다(다시 읽거나 굽지 않는다)
      final kept = probe ? null : _rowDone[key] ?? done[key];
      if (kept != null) {
        r.tabLoss = kept.tabLoss;
        done[key] = kept;
        images.add(kept.image.clone());
        spots.add(kept.at);
        spaces.add(r.space);
        keys.add(kept.keys);
        bookKeys.add(kept.bookKeys);
        rows.add(RowRun(r.items.length, kept.image.width, kept.image.height, 0, 0));
        continue;
      }
      // 같은 값으로 구워 담아 둔 그림이 있으면 굽지 않는다(row_bake)
      final b = (await bakeRow(gridSlots, bakeSlots, c, r, probe: probe, stamp: true))!;
      images.add(b.image);
      if (probe) continue;
      final row = _RowDone(b.image.clone(), b.at, b.keys, b.bookKeys, r.tabLoss);
      done[key] = row;
      spots.add(b.at);
      spaces.add(r.space);
      keys.add(b.keys);
      bookKeys.add(b.bookKeys);
      rows.add(RowRun(r.items.length, b.image.width, b.image.height, b.gridMs, b.bakeMs));
    }
    final run = Run(rows, loadMs, DateTime.now().difference(bootAt).inMilliseconds);
    // ignore: avoid_print
    print('[fltotal] rows ${rows.length} bake ${run.bakeTotal}ms (grid ${run.gridTotal}) load ${run.loadMs}ms sinceBoot ${run.sinceBoot}ms');
    // 첫 책장을 다 그렸다: 앱 틀의 시작 그림 덮개를 걷는다(app/startup.dart)
    shelfReady.value = true;

    if (!mounted) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    setState(() {
      _case = c;
      _lockedCount = lockedCount;
      for (final i in _atlases) {
        i.dispose();
      }
      _atlases
        ..clear()
        ..addAll(images);
      _rowSpots
        ..clear()
        ..addAll(spots);
      _spaces
        ..clear()
        ..addAll(spaces);
      _keys
        ..clear()
        ..addAll(keys);
      _bookKeys = bookKeys;
      for (final e in _rowDone.entries) {
        if (!identical(done[e.key], e.value)) e.value.image.dispose();
      }
      _rowDone = done;
      _runs.add(run);
      _libBooks = lib.books;
      _state = '${_runs.length}번째';
      _busy = false;
    });
    // 새 그림이 나왔으니 미리 보기는 걷는다(미리 보는 줄은 지난 그림의 자리를 쓰고 있었다). 끄는 중이면 다음 손가락 움직임에 다시 만든다
    _dragTarget = null;
    _clearPreview();
    if (_again) {
      _again = false;
      _refresh();
    }
    // 보여 달라던 책이 이번 굽기로 줄에 들어왔으면 그리로(줄 자리는 다음 화면을 그릴 때 정해진다)
    if (_pendingFocus != null) WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocus());
  }

  /// 환불로 잠긴 선반이 시작하는 줄 번호. 없으면 줄 수보다 큰 값(결제가 꺼졌거나 서버 상태를 아직 못 받았으면 잠그지 않는다)
  void _entitlementChanged() {
    if (mounted) setState(() {});
  }

  int _refundedFrom() {
    final e = EntitlementStore.instance;
    return iapOn && e.loaded ? allowedShelfSlots(e.shelves) : 1 << 30;
  }

  // 환불된 선반 안내: 무엇이 되고 안 되는지 알리고, 다시 살 수 있으면 구매 시트로 가는 길을 둔다(권유 문장은 넣지 않는다)
  void _openRefunded() => showSheet<void>(
        context,
        title: '환불된 선반',
        description: '결제가 환불돼 잠긴 선반이에요.\n꽂힌 책은 그대로 있고, 빼거나 이 선반 안에서 옮길 수 있어요. 새로 꽂을 수는 없어요.',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: Btn(label: '확인', size: 'l', onPress: () => Navigator.pop(ctx))),
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Btn(
              label: '선반 구매 보기',
              kind: 'secondary',
              size: 'l',
              onPress: () {
                Navigator.pop(ctx);
                showShelfPurchase(context);
              },
            ),
          ),
        ]),
      );

  // 잠긴 선반 시트(지금 앱 LockedShelfSheet): 세 칸까지는 바로 열고, 그 위는 유료 예정이라 준비 중으로 알린다(2026-11-15 사용자 결정).
  // '무료로'는 쓰지 않는다(QA: 곧 돈 받겠다는 뜻으로 읽혔다). 남은 칸 수를 알린다
  void _openLocked() {
    final shelves = PlacementStore.instance.layout?.shelves.length ?? _rowSpots.length - _lockedCount;
    // 결제를 켠 빌드는 구매한 칸만큼 더 열 수 있다. 꺼진 빌드는 지금처럼 무료 칸까지
    final paid = iapOn ? EntitlementStore.instance.shelves : 0;
    final free = openableShelfCount(shelves, paid);
    if (free == 0 && iapOn && purchasableShelfCount(paid) > 0) {
      // 쓸 수 있는 칸을 다 열었고 살 수 있는 칸이 남았다: 구매 시트. 사고 나면 이어서 선반을 연다
      showShelfPurchase(context).then((bought) {
        if (bought && mounted) _openLocked();
      });
      return;
    }
    if (free == 0) {
      showSheet<void>(
        context,
        title: '선반 더 열기',
        description: iapOn
            ? '선반 $shelfSlots칸을 모두 열었어요.\n책장에 없는 책은 내 책에 그대로 보관돼요.'
            : '선반은 $freeShelfSlots칸까지 쓸 수 있어요. 더 여는 기능은 준비하고 있어요.\n책장에 없는 책은 내 책에 그대로 보관돼요.',
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Btn(label: '확인', size: 'l', onPress: () => Navigator.pop(ctx)),
        ),
      );
      return;
    }
    showSheet<void>(
      context,
      title: '선반 한 칸 더 열기',
      description: '책을 더 진열할 수 있는 선반이 한 칸 늘어나요. 앞으로 $free칸 더 열 수 있어요.',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Btn(
          label: '선반 열기',
          size: 'l',
          onPress: () async {
            Navigator.pop(ctx);
            final ok = await PlacementStore.instance.addShelf();
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(ok ? '선반을 열었어요.' : '지금은 바꿀 수 없어요.'), duration: const Duration(seconds: 2), persist: false));
          },
        ),
      ),
    );
  }

  /// 책등 모양(스토어)이 바뀌었다: 표지 사진을 그 모양으로 다시 준비한다(실물 측면이면 책등 사진도 받는다). 오는 대로 바꿔 그린다
  void _spineLookChanged() {
    if (mounted) _loadCovers([for (final b in _libBooks) ?b.coverArtUri], again: true);
  }

  /// 표지 사진을 받는다(기기에 있으면 바로). 하나 올 때마다 다시 그린다
  bool _pruned = false;
  void _loadCovers(List<String> uris, {bool again = false}) {
    if (!_pruned) {
      _pruned = true;
      pruneCoverCache();
    }
    final t0 = DateTime.now();
    var left = uris.toSet().length;
    for (final uri in uris.toSet()) {
      if (!again && _photos.containsKey(uri)) {
        left--;
        continue;
      }
      loadCoverPhoto(uri).then((photo) {
        if (photo != null && mounted) setState(() => _photos = {..._photos, uri: photo});
        if (--left == 0) debugPrint('[flcover] ${uris.length} covers ${DateTime.now().difference(t0).inMilliseconds}ms got ${_photos.length}');
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _shelfImage?.dispose();
    _overlay?.dispose();
    _settleFreeze?.cancel();
    _snap?.dispose();
    _freezeTimer?.cancel();
    _widgetTimer?.cancel();
    _tweenTicker?.dispose();
    _autoScroll?.cancel();
    _coverRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    shelfRefresh.removeListener(_refresh);
    spineLook.removeListener(_spineLookChanged);
    focusBookOnShelf.removeListener(_focusBook);
    LibraryModel.instance.removeListener(_libraryChanged);
    BookcaseStore.instance.removeListener(_bookcasesChanged);
    if (iapOn) EntitlementStore.instance.removeListener(_entitlementChanged);
    if (_decorating) MiniTimerPlace.instance.setHidden(false);
    for (final i in _atlases) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => qaProbe('home', _qaBuild(context));

  Widget _qaBuild(BuildContext context) {
    final r = _runs.isEmpty ? null : _runs.last;
    final pad = MediaQuery.paddingOf(context);
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    Widget header([double opacity = 1]) => Opacity(
      opacity: opacity,
      child: MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scale),
      child: _Header(
        year: DateTime.now().year,
        // 측정 메뉴: 제목을 길게 누르면 다시 굽고 시간을 알린다(지금 앱 측정 번들의 책장 메뉴 자리)
        onLongPress: _busy ? null : _run,
        onDecorate: () => _enterDecorate(),
        icons: !_decorating,
        status: r == null ? _state : '굽기 ${r.bakeTotal}ms | 켠 뒤 ${r.sinceBoot}ms',
      ),
    ),
    );
    final ready = _atlases.length > 1 && _rowSpots.length == _spaces.length;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final snap = _snap;
    // 지금 책장 쪽(머리글 불투명도: 모아 보기로 줄이면 사라진다)
    // 지금 앱: 스크롤 영역은 상태 표시줄 아래부터(위로 올라간 책은 상태 표시줄 밑에서 잘린다)
    Widget shelfPage(double headerOpacity) => ClipRect(
                clipper: _BelowTop(pad.top),
                child: LayoutBuilder(
                  builder: (context, box) {
                    if (!_decorating) {
                      _bare = false;
                    } else if (_drag == null) {
                      _bare = true;
                    }
                    final contentTop = pad.top + (_bare ? 0 : homeHeaderHeight);
                    final bottomInset = navigationShelfReserve + pad.bottom;
                    final m = makeMetrics(box.maxWidth);
                    final n = _rowSpots.length;
                    final geo = computeRows(n, m.scale, viewportHeight: box.maxHeight - contentTop, bottomInset: bottomInset, real: n - _lockedCount);
                    // 잠긴 칸까지 다 보이게 세로로 넘긴다(머리줄도 함께, 지금 앱 홈 스크롤)
                    final last = geo.isEmpty ? null : geo.last;
                    // 끝 여백(지금 앱 contentEnd): 판 그늘 몫과 하단바 블록 + 덮개 0.6 중 큰 것
                    final tail = math.max((shelfCastExtent + 8) * m.scale, pad.bottom + TabBarStyle.gap + TabBarStyle.height + TabBarStyle.fade * 0.6);
                    // 꾸미는 동안은 아래 조작부 뒤에 숨는 줄도 위로 밀어 볼 수 있게 끝 여백을 늘린다(순서 단추가 생겨 약 360, 큰 글씨면 화면의 62%까지)
                    final panelH = largeText(context) ? MediaQuery.sizeOf(context).height * 0.62 : 360.0;
                    final height = math.max(box.maxHeight, last == null ? 0.0 : contentTop + last.top + last.height + tail + (_decorating ? panelH : 0));
                    final lockedFrom = n - _lockedCount;
                    _geom = (m: m, geo: geo, contentTop: contentTop, lockedFrom: lockedFrom);
                    return NotificationListener<ScrollStartNotification>(
                      onNotification: (_) {
                        if (!_frozen) setState(() => _frozen = true);
                        return false;
                      },
                      child: SingleChildScrollView(
                        key: _viewportKey,
                        controller: _scroll,
                        physics: _head != null || _pinching ? const NeverScrollableScrollPhysics() : null,
                        child: SizedBox(
                          width: box.maxWidth,
                          height: height,
                          child: Stack(
                            children: [
                              // 책장은 화면 밀도 크기의 그림 한 장으로 한 번 그려 두고 밀 때는 옮기기만 한다(지금 앱 줄 캔버스와 같은 생각).
                              // 그대로 두면 밀 때마다 빛 셰이더를 모두 다시 돌려 에뮬에서 16fps였다. 셰이더 좌표는 그리는 면 기준이라 결과 화소는 같다
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: _shelfLayer(
                                    ShelfPainter(
                                      rows: _moving(_shown?.rows ?? _case!.rows),
                                      atlases: _shown?.atlases ?? _atlases,
                                      rowSpots: _shown?.spots ?? _rowSpots,
                                      spaces: _spaces,
                                      photos: _photos,
                                      bookKeys: _shown?.bookKeys ?? _bookKeys,
                                      keys: _shown?.keys ?? _keys,
                                      contentTop: contentTop,
                                      bottomInset: bottomInset,
                                      viewport: box.maxHeight,
                                      frostedFrom: lockedFrom,
                                      look: '${skinChoice.key}|${spineLook.value.name}',
                                    ),
                                    Size(box.maxWidth, height),
                                    MediaQuery.devicePixelRatioOf(context),
                                  ),
                                ),
                              ),
                              // 고른 책 윤곽 빛(지금 앱 SelectGlow): 바깥으로 흰 얇은 선과 좁은 그림자 번짐, 책 면은 덮지 않고 바닥 면 아래로 새지 않는다
                              // 겹쳐 그리는 것은 있다 없다 하므로 키를 단다(없으면 아래 누르기 층이 새로 만들어져 끌던 손가락이 끊긴다)
                              if (_drag == null ? _outlineOf(_decorating ? _editId : _popId) : null case final path?)
                                Positioned.fill(key: const ValueKey('glow'), child: IgnorePointer(child: CustomPaint(painter: GlowPainter(path, _geom!.m.scale)))),
                              // 끄는 책: 잡은 책 윤곽이 손가락을 따라간다(놓을 수 없는 자리면 붉게)
                              if (_drag case final d?)
                                Positioned.fill(
                                  key: const ValueKey('drag'),
                                  child: IgnorePointer(
                                    child: CustomPaint(painter: _DragPainter(d.path, _dragNow - d.start, _geom!.m.scale, _dragOk, _shelfImage, MediaQuery.devicePixelRatioOf(context))),
                                  ),
                                ),
                              // 누르기: 책 정보 시트(꾸미는 중이면 고르기), 꾹 누르기: 꾸미기
                              Positioned.fill(
                                key: const ValueKey('touch'),
                                child: RawGestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  // 화면 읽기에는 이름 없는 화면 전체 칸으로 잡혔다(2026-11-16 QA 영숙 F10): 책 누르기는 아래 책 칸이, 옮기기는 꾸미기 조작부가 맡는다
                                  excludeFromSemantics: true,
                                  gestures: {
                                    TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                                      TapGestureRecognizer.new,
                                      (g) => g.onTapUp = (e) => _onTap(e.localPosition),
                                    ),
                                    // 꾹 눌러(지금 앱 motion.longPress 350ms) 책을 집으면 꾸미기가 시작되고 손가락을 따라 옮긴다(놓으면 그 자리로)
                                    LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                                      () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 350)),
                                      (g) => g
                                        ..onLongPressStart = ((e) {
                                          _beginDrag(e.localPosition);
                                          _dragGlobal = e.globalPosition;
                                          _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
                                        })
                                        ..onLongPressMoveUpdate = ((e) {
                                          _dragGlobal = e.globalPosition;
                                          _moveDrag(e.localPosition);
                                        })
                                        ..onLongPressEnd = ((_) => _endDrag())
                                        ..onLongPressCancel = (() {
                                          _stopAutoScroll();
                                          setState(() => _drag = null);
                                          _dragTarget = null;
                                          _clearPreview();
                                        }),
                                    ),
                                  },
                                ),
                              ),
                              // 화면 읽기용 책 칸(누르기는 아래 누르기 층이 받는다: 이 칸은 손가락을 가로채지 않는다)
                              if (_drag == null && _head == null)
                                for (final (i, b) in _bookSemantics().indexed)
                                  Positioned.fromRect(
                                    key: ValueKey('sem:${b.id}'),
                                    rect: b.rect,
                                    child: Semantics(
                                      container: true,
                                      sortKey: OrdinalSortKey(1.0 + i),
                                      button: true,
                                      selected: _decorating && _editId == b.id,
                                      label: b.label,
                                      onTap: () => _tapBook(b.id),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                              // 표지 책 머리 손잡이: 보이는 점은 작게, 잡는 칸은 넓게. 끄는 동안 손가락을 따라 실제로 된 각도만큼 옮겨 가고, 제자리와 가는 선으로 잇는다
                              if (_handlePoint() case final hp?) ...[
                                if (_headOff.distance >= 2)
                                  Positioned.fill(key: const ValueKey('tether'), child: IgnorePointer(child: CustomPaint(painter: _TetherPainter(hp, hp + _headOff)))),
                                Positioned(
                                  key: const ValueKey('handle'),
                                  left: hp.dx + _headOff.dx - _handleHit / 2,
                                  top: hp.dy + _headOff.dy - _handleHit / 2,
                                  width: _handleHit,
                                  height: _handleHit,
                                  child: Semantics(
                                    container: true,
                                    sortKey: const OrdinalSortKey(50000),
                                    label: '머리 손잡이: 위아래로 끌면 뒤로 젖히기, 좌우로 끌면 돌리기',
                                    // 닿는 순간 잡는다(지금 앱 manualActivation): 손가락 이벤트를 바로 받고, 잡는 동안은 스크롤을 끈다(스크롤 끌기가 손잡이를 가로채지 않게)
                                    child: Listener(
                                      behavior: HitTestBehavior.opaque,
                                      onPointerDown: (e) {
                                        if (_headPointer == null && _headBegin()) _headPointer = e.pointer;
                                      },
                                      onPointerMove: (e) {
                                        if (e.pointer == _headPointer) _headMove(e.delta);
                                      },
                                      onPointerUp: (e) {
                                        if (e.pointer != _headPointer) return;
                                        _headPointer = null;
                                        _headEnd();
                                      },
                                      onPointerCancel: (e) {
                                        if (e.pointer != _headPointer) return;
                                        _headPointer = null;
                                        _headCancel();
                                      },
                                      child: Center(child: _Knob(scale: _geom!.m.scale)),
                                    ),
                                  ),
                                ),
                              ],
                              // 머리줄(책장과 함께 스크롤: 지금 앱 2026-11-04 '상단 라인은 고정이 아니야'): 왼쪽 '나의 책장'과 그 밑 해, 오른쪽 스토어·꾸미기·전체 책·더하기
                              // 자식 목록 자리는 그대로 둔다(있다 없다 하면 뒤의 누르기 층이 새로 만들어져 끌던 손가락이 끊긴다)
                              // 화면 읽기는 머리줄('나의 책장'·꾸미기·책 추가·내 정보)을 책보다 먼저 읽는다(2026-11-16 QA 영숙 F11: '내 정보'가 책 뒤로 밀렸다)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: pad.top,
                                child: _bare
                                    ? const SizedBox.shrink()
                                    : Semantics(container: true, explicitChildNodes: true, sortKey: const OrdinalSortKey(0), child: header(headerOpacity)),
                              ),
                              // 환불로 잠긴 선반(D13): 책은 그대로 두고 표시만 얹는다. 표시를 누르면 안내, 책은 그대로 눌린다
                              for (var i = _refundedFrom(); i < lockedFrom && i < geo.length; i++)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: contentTop + geo[i].top,
                                  height: geo[i].height,
                                  child: RefundedShelfMark(onTap: _openRefunded),
                                ),
                              // 잠긴 칸: 가운데 자물쇠, 누르면 선반 한 칸 더 열기
                              for (var i = lockedFrom; i < n && i < geo.length; i++)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: contentTop + geo[i].top,
                                  height: geo[i].height,
                                  child: Semantics(
                                    container: true,
                                    sortKey: OrdinalSortKey(100000.0 + i),
                                    button: true,
                                    label: '잠긴 선반, 눌러서 열기',
                                    onTap: _openLocked,
                                    excludeSemantics: true,
                                    child: _Pressable(
                                      onTap: _openLocked,
                                      child: const Center(child: LockIcon()),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
    // 꾸미는 중 기기 뒤로 = 꾸미기 끝내기(끄던 책은 제자리로). 앱 껍데기는 꾸미는 동안(탭 바가 숨은 동안) 뒤로를 홈에 맡긴다(2026-11-15 QA 민혁 F2)
    return PopScope(
      canPop: !_decorating,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_decorating) return;
        if (_drag != null) {
          _stopAutoScroll();
          setState(() => _drag = null);
          _dragTarget = null;
        }
        _exitDecorate();
      },
      child: ColoredBox(
      color: AppColors.bg,
      child: Stack(
        children: [
          // 시작 사진(지금 앱 LoadingScreen 스냅샷): 진짜 책장이 준비될 때까지 지난번에 굳힌 책장 그림을 먼저 보인다
          if (!ready && snap != null && snap.width == (MediaQuery.sizeOf(context).width * dpr).ceil()) ...[
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: RawImage(image: snap, width: snap.width / dpr, height: snap.height / dpr, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill),
              ),
            ),
            Positioned(left: 0, right: 0, top: pad.top, child: header()),
          ],
          // 책장(머리글 아래부터, 맨 윗줄 벽은 머리글 뒤까지). 지금 앱 홈 화면과 같은 구도
          if (ready)
            Positioned.fill(
              // 지난 연도 책장이 있으면 옆으로 넘기고 두 손가락으로 모아 본다(지금 앱 YearPager)
              child: _bookcases.isEmpty
                  // 지난 책장이 아직 없을 때 옆으로 밀면 짧게 알린다(2026-11-15 QA: 밀어도 아무 반응이 없었다). 꾸미는 중에는 책 끌기와 겹치지 않게 듣지 않는다
                  ? GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      excludeFromSemantics: true, // 알림만 띄우는 밀기: 화면 읽기에 이름 없는 전체 칸을 만들지 않는다(영숙 F10)
                      onHorizontalDragEnd: _decorating ? null : _noPastShelf,
                      child: shelfPage(1),
                    )
                  : YearPager(
                      key: _pagerKey,
                      bookcases: _bookcases,
                      blocked: _decorating || _drag != null || _head != null,
                      onPinch: (v) => setState(() => _pinching = v),
                      current: shelfPage,
                    ),
            ),
          // 화면 위 끝 덮개(HeaderVeil)는 뺐다: 내리면 위가 뿌옇게 덮였다(2026-11-18 사용자 '상단 블러는 없애'). 하단바 쪽 덮개만 남긴다
          // 하단바 쪽 덮개: 책장이 하단바 뒤로 들어갈 때 벽 색으로 서서히 덮는다(지금 앱 TabBarFade)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: pad.bottom + TabBarStyle.gap + TabBarStyle.height + TabBarStyle.fade,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment(0, -1 + 2 * TabBarStyle.fade / (pad.bottom + TabBarStyle.gap + TabBarStyle.height + TabBarStyle.fade)),
                    colors: [for (final a in _fadeStops) Color.fromRGBO(255, 255, 255, a.$2)],
                    stops: [for (final a in _fadeStops) a.$1],
                  ),
                ),
              ),
            ),
          ),
          if (_decorating)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratePanel(
                bookKey: _editId,
                title: _panel?.title,
                pose: _panel?.pose,
                lean: _panel?.lean ?? 0,
                canLean: _panel?.canLean ?? (left: false, right: false),
                msg: _editMsg,
                angles: _anglesText,
                spin: _panel?.spin ?? 0,
                spinMax: _panel?.spinMax ?? maxSpin,
                spinRange: _panel?.spinRange,
                depth: _panel?.depth,
                canUndo: PlacementStore.instance.canUndo,
                onPose: _editPose,
                onLean: _editLean,
                onSpin: _editSpin,
                onDepth: _editDepth,
                onUndo: _undo,
                onDone: _exitDecorate,
                onSkin: () => openStore(context),
                onMove: _editMove,
                canMove: _panel?.canMove ?? (left: false, right: false),
                place: _panel?.place,
              ),
            ),
        ],
      ),
      ),
    );
  }
}


/// top 아래만 보이게 자른다(상태 표시줄 밑부터)
class _BelowTop extends CustomClipper<Rect> {
  const _BelowTop(this.top);
  final double top;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);
  @override
  bool shouldReclip(_BelowTop old) => old.top != top;
}

class GlowPainter extends CustomPainter {
  GlowPainter(this.path, this.scale);
  final ui.Path path;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final b = path.getBounds();
    canvas.save();
    // 책 면은 덮지 않는다(선의 바깥 절반만), 받치는 면 아래로는 새지 않는다
    canvas.clipPath(ui.Path.combine(ui.PathOperation.difference, ui.Path()..addRect(Rect.fromLTRB(-4000, b.bottom - 4000, 8000, b.bottom)), path));
    canvas.drawPath(path, Paint()
      ..color = const Color(0x521F2533) // rgba(31,37,51,0.32)
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, 3.2 * scale));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlowPainter old) => old.path != path || old.scale != scale;
}

/// 끄는 책: 굳힌 책장 그림(든 순간의 모습)에서 그 책 모양만 떠서 손가락을 따라 옮긴다(아래 그늘, 둘레 흰 선). 제자리는 그 줄에서 책을 빼고 다시 그린다.
/// 놓을 수 없는 자리면 붉게 덮는다. 굳힌 그림이 없으면 흰 윤곽만
class _DragPainter extends CustomPainter {
  _DragPainter(this.path, this.delta, this.scale, this.ok, this.image, this.dpr);
  final ui.Path path;
  final Offset delta;
  final double scale;
  final bool ok;
  final ui.Image? image;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final moved = path.shift(delta);
    canvas.drawPath(moved.shift(Offset(0, 4 * scale)), Paint()
      ..color = const Color(0x521F2533)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * scale));
    final img = image;
    canvas.save();
    canvas.clipPath(moved);
    if (img != null) {
      canvas.translate(delta.dx, delta.dy);
      canvas.scale(1 / dpr);
      canvas.drawImage(img, Offset.zero, Paint()..filterQuality = FilterQuality.low);
    } else {
      canvas.drawPath(moved, Paint()..color = const Color(0x66FFFFFF));
    }
    canvas.restore();
    if (!ok) canvas.drawPath(moved, Paint()..color = const Color(0x40D9534F));
    canvas.drawPath(moved, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_DragPainter old) => old.delta != delta || old.ok != ok || old.image != image || old.path != path;
}

/// 손잡이 점(지금 앱 knob: 옅은 종이색 원, 나무색 테두리·가운데 점, 옅은 그림자)
class _Knob extends StatelessWidget {
  const _Knob({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
        width: 16 * scale,
        height: 16 * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xF2FFFCF6),
          border: Border.all(color: const Color(0x8CA07858)),
          boxShadow: const [BoxShadow(color: Color(0x2E3B3330), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Center(
          child: Container(width: 5 * scale, height: 5 * scale, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xCCA06E46))),
        ),
      );
}

/// 머리 위 제자리와 손잡이를 잇는 가는 선(무엇을 젖히거나 돌리는지 보이게)
class _TetherPainter extends CustomPainter {
  _TetherPainter(this.from, this.to);
  final Offset from, to;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(from, to, Paint()
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..color = const Color(0x8CA07858));

  @override
  bool shouldRepaint(_TetherPainter old) => old.from != from || old.to != to;
}

class _PreviewRow {
  _PreviewRow(this.row, this.spots, [this.atlas, this.keys, this.bookKeys]);
  final RowCase row;
  final List<Spot> spots;

  /// 그 배치로 구운 그림(없으면 지난 그림을 쓴다). 이 미리 보기 것: 걷을 때 버린다
  final ui.Image? atlas;
  final ({PlaneKey wall, PlaneKey floor})? keys;
  final Map<String, BookKey>? bookKeys;
}

class _RowDone {
  _RowDone(this.image, this.at, this.keys, this.bookKeys, this.tabLoss);
  final ui.Image image;
  final List<Spot> at;
  final ({PlaneKey wall, PlaneKey floor}) keys;
  final Map<String, BookKey> bookKeys;
  final Map<String, C3> tabLoss;
}

/// 책장에서 이 책을 보여 달라(책 정보 '책장에서 보기', 지금 앱 uiBus.focusBook): 홈이 그 줄로 넘기고 잠깐 윤곽을 빛낸다
final focusBookOnShelf = ValueNotifier<String?>(null);

/// 책장에서 이 책 보기: 홈(첫 화면)까지 닫고 그 책 줄로 넘긴다(책 정보 '책장에서 보기'·책 추가 결과 '책장에서 보기'가 같이 쓴다)
void showBookOnShelf(BuildContext context, String id) {
  focusBookOnShelf.value = id;
  Navigator.of(context).popUntil((r) => r.isFirst);
  // 다른 탭(읽기·갈피 등)에서 책을 넣었어도 책장 탭으로
  AppNav.instance.goTab(AppTab.shelf);
}

/// 책장에 보이는 서재 값만 모은 열쇠(장정·판본은 고친 때, 갈피 수·갈피 색·숨김). 이것이 바뀌면 홈이 줄을 다시 만든다
String shelfLookSignature(dl.Library lib) {
  final marks = <String, int>{};
  for (final m in lib.bookmarks.values) {
    marks[m.myBookId] = (marks[m.myBookId] ?? 0) + 1;
  }
  final b = StringBuffer();
  for (final x in lib.books.values) {
    final d = x.bindingId == null ? null : lib.bindings[x.bindingId];
    b.write('${x.id}|${x.hiddenAt}|${x.ribbonColor}|${x.bindingId}|${lib.editions[x.editionId]?.updatedAt}|${d?.updatedAt}|${marks[x.id] ?? 0};');
  }
  return b.toString();
}

/// 시작 사진 파일(굳힌 책장 그림, 다음에 켤 때 먼저 보인다)
Future<File> homeSnapshotFile() async => File('${(await imageDir()).parent.path}/home_snapshot.png');

/// 시작 사진을 버린다(스킨처럼 책장 모습이 바뀌었을 때: 다음에 켤 때 옛 모습이 먼저 뜨지 않게)
Future<void> dropHomeSnapshot() async {
  try {
    final f = await homeSnapshotFile();
    if (f.existsSync()) f.deleteSync();
  } catch (_) {
    // 못 지워도 다음 굳히기 때 덮어쓴다
  }
}

/// 하단바 덮개 농도(끝이 부드러운 곡선)
const _fadeStops = [(0.0, 0.0), (0.2, 0.05), (0.4, 0.2), (0.6, 0.48), (0.8, 0.8), (1.0, 1.0)];

/// 머리줄 높이(지금 앱은 배치에서 잰다): 위 16 + 제목 줄 34 − 2 + 해 줄 23 + 아래 4. 글자 줄은 지금 앱처럼 화소로 올린 높이(rnPx)
/// (2026-11-10 사용자 '책장 좀 더 높이', '2026이랑 나의 책장 사이 간격 줄이고': 아래 여백 12 → 4, 해 위 4 → −2)
const _headerBottom = 4.0;
double get homeHeaderHeight => TabHeader.paddingTop + rnPx(34) - 2 + rnPx(23) + _headerBottom;

/// 책장 줄 배치에서 하단바 몫(지금 앱 navigation.shelfReserve)
const navigationShelfReserve = 78.0;

/// 책장 머리 아이콘 그림 크기(지난 책장 공유 아이콘도 같이 쓴다)
const headerArtSize = 37.0;

// 2026-11-18 사용자: 점토 아이콘으로 바꾸고 크게(그림 31 → 37). 이어 '너무 우측에 몰려 있다, 간격 띄워 잘 배치':
// 아이콘 가운데 사이 40 → 52(그림 사이 빈 곳 3 → 15), 맨 끝 아이콘 가운데는 화면 끝에서 24.3 → 36
// (그림 몸통 오른쪽 끝이 제목 왼쪽 여백 24와 거울처럼 맞는다. 점토 그림은 그림자 몫이 있어 몸통 폭이 그림의 약 80%)
const _headerArt = headerArtSize;
const _headerPitch = 52.0;
const _headerLastCenter = 36.0;

class _Header extends StatelessWidget {
  const _Header({required this.year, required this.status, this.onLongPress, this.onDecorate, this.icons = true});
  final int year;
  final String status;
  final VoidCallback? onLongPress;
  final VoidCallback? onDecorate;

  /// 꾸미는 동안은 오른쪽 아이콘을 숨긴다(지금 앱 editing ? null)
  final bool icons;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 머리줄 아래 여백 4, 해는 제목 바로 밑(−2dp, 지금 앱 11-10 조정). 굵기는 보통(2026-11-15 사용자 '두께는 전이 나은 느낌').
      // 오른쪽은 아이콘 누르는 칸이 그림 칸보다 양옆으로 넓은 만큼(_HeaderIcons.slop) 덜 비운다: 그림 자리는 그대로
      padding: EdgeInsets.fromLTRB(TabHeader.paddingH, TabHeader.paddingTop, _headerLastCenter - Space.hit / 2, _headerBottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // '나의 책장'과 해를 한 이름으로 읽는다(2026-11-16 QA 영숙 F9: 두 줄로 따로 읽혔다). 길게 누르기는 측정 메뉴라 화면 읽기에서 뺀다
            child: Semantics(
              container: true,
              header: true,
              label: '나의 책장, $year',
              excludeSemantics: true,
              child: GestureDetector(
                excludeFromSemantics: true,
                onLongPress: onLongPress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('나의 책장', style: AppType.title, maxLines: 1),
                    PullUp(
                      dy: 2,
                      child: Tooltip(
                        message: status,
                        child: Text('$year', style: AppType.sub, maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 꾸미기 · 추가 · 프로필(2026-11-16 메뉴 구조 개편: 전체 책은 하단 '내 책' 탭과 겹쳐 빼고, 스토어(선반·벽지)는 꾸미기 안에서 연다)
          if (icons)
            Padding(
              padding: const EdgeInsets.only(top: 2.5 - _HeaderIcons.slopY),
              child: _HeaderIcons(items: [
                ('decorate', '꾸미기', onDecorate),
                ('add', '책 추가', () => openAddBook(context)),
                ('profile', '내 정보', () => openProfile(context)),
              ]),
            )
          else
            const Padding(padding: EdgeInsets.only(top: 2.5), child: SizedBox(height: 44)),
        ],
      ),
    );
  }
}

/// 머리 아이콘 줄: 아이콘마다 누르는 칸 48×48(Space.hit, 2026-11-16 QA 영숙 F12), 가운데 사이 _headerPitch.
/// 칸 사이 빈 곳은 가까운 아이콘이 받는다. 화면 읽기 칸도 48×48
class _HeaderIcons extends StatefulWidget {
  const _HeaderIcons({required this.items});
  final List<(String, String, VoidCallback?)> items;

  /// 머리줄 높이(44) 밖으로 넓힌 누르는 자리(위아래)
  static const slopY = (Space.hit - 44) / 2;

  @override
  State<_HeaderIcons> createState() => _HeaderIconsState();
}

class _HeaderIconsState extends State<_HeaderIcons> {
  int? _down;

  int _at(double x) => ((x - Space.hit / 2) / _headerPitch).round().clamp(0, widget.items.length - 1);

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return SizedBox(
      width: _headerPitch * (n - 1) + Space.hit,
      height: Space.hit,
      child: Stack(children: [
        for (final (i, it) in widget.items.indexed) ...[
          Positioned(
            left: i * _headerPitch,
            top: 0,
            width: Space.hit,
            height: Space.hit,
            child: Opacity(
              opacity: _down == i ? pressOpacity : 1,
              // 그림 역할을 빼야 화면 읽기가 '이미지'가 아니라 단추로 읽는다(2026-11-16 QA 영숙 F11)
              child: Center(child: Image.asset('assets/header/${it.$1}.png', width: _headerArt, height: _headerArt, excludeFromSemantics: true)),
            ),
          ),
          Positioned(
            left: i * _headerPitch,
            top: 0,
            width: Space.hit,
            height: Space.hit,
            child: Semantics(container: true, button: true, label: it.$2, onTap: it.$3, child: const SizedBox.expand()),
          ),
        ],
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: (e) => setState(() => _down = _at(e.localPosition.dx)),
            onTapCancel: () => setState(() => _down = null),
            onTapUp: (e) {
              final i = _at(e.localPosition.dx);
              setState(() => _down = null);
              widget.items[i].$3?.call();
            },
          ),
        ),
      ]),
    );
  }
}

/// 눌리는 동안 옅어지는 단추(지금 앱 press 0.55)
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap,
    child: Opacity(opacity: _down ? pressOpacity : 1, child: widget.child),
  );
}

/// 구운 줄들을 실제 책장처럼 쌓아 그린다(지금은 뒷벽만, ui/scene). 줄마다 카메라가 따로다
class ShelfPainter extends CustomPainter {
  ShelfPainter({
    required this.rows,
    required this.atlases,
    required this.rowSpots,
    required this.spaces,
    required this.keys,
    this.photos = const {},
    this.bookKeys = const [],
    this.contentTop = 78,
    this.bottomInset = 0,
    this.viewport,
    this.frostedFrom = 1 << 30,
    this.look = '',
    this.only,
  });

  /// 이 차례 줄만 그린다(null이면 모두). 끄는 동안 굳힌 그림 위에 바뀐 줄만 덧그릴 때
  final Set<int>? only;

  /// 그 줄들이 그리는 세로 띠(그리는 면 px, paint와 같은 줄 자리 계산)
  (double, double) bandOf(Set<int> which, Size size) {
    final m = makeMetrics(size.width);
    final geo = computeRows(rows.length, m.scale, viewportHeight: (viewport ?? size.height) - contentTop, bottomInset: bottomInset, real: math.min(rows.length, frostedFrom));
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final i in which) {
      if (i < 0 || i >= geo.length) continue;
      final r = geo[i];
      lo = math.min(lo, contentTop + math.max(0.0, r.top - headDu * m.scale));
      hi = math.max(hi, contentTop + r.top + r.height + shelfCastExtent * m.scale);
    }
    if (lo > hi) return (0, 0);
    return (lo.floorToDouble(), math.min(size.height, hi.ceilToDouble()));
  }

  ShelfPainter onlyRows(Set<int> rows) => ShelfPainter(
        rows: this.rows,
        atlases: atlases,
        rowSpots: rowSpots,
        spaces: spaces,
        keys: keys,
        photos: photos,
        bookKeys: bookKeys,
        contentTop: contentTop,
        bottomInset: bottomInset,
        viewport: viewport,
        frostedFrom: frostedFrom,
        look: look,
        only: rows,
      );

  /// 스킨·책 측면(그릴 때 셰이더 값으로 읽는다): 바뀌면 굽기를 기다리지 않고 지난 그림 위에 새 색으로 바로 다시 그린다
  /// (2026-11-15 QA: 선반·벽지 적용하기 뒤 2~4초 옛 모습이었다. 새로 구운 빛은 끝나는 대로 바뀐다)
  final String look;

  /// 줄 자리를 정하는 화면 높이(스크롤해도 줄 자리는 화면 기준, 지금 앱 computeRows)
  final double? viewport;

  /// 이 차례부터는 잠긴 칸(책을 흐리게)
  final int frostedFrom;

  /// 콘텐츠(책장 줄) 위 끝과 아래 하단바 몫(화면 px)
  final double contentTop;
  final double bottomInset;
  final Map<String, CoverPhoto> photos;
  final List<Map<String, BookKey>> bookKeys;
  final List<RowCase> rows;
  final List<ui.Image> atlases;
  final List<List<Spot>> rowSpots;
  final List<double> spaces;
  final List<({PlaneKey wall, PlaneKey floor})> keys;

  static ShaderSlots? _lit;
  static ShaderSlots? _book;
  static ShaderSlots? _tab;
  static GlyphMetrics? _glyphs;

  /// 책 셰이더·제목 글꼴(선반 밖에서 한 권만 그릴 때도 쓴다)
  static ShaderSlots? get bookSlots => _book;
  static GlyphMetrics? get glyphs => _glyphs;

  /// 그리기 셰이더가 다 올라왔는지(그림으로 굳히기 전에 본다)
  static bool get ready => _lit != null && _book != null && _tab != null && _glyphs != null;

  /// 그리기 셰이더는 한 번만 올린다(미리 컴파일돼 있다)
  static Future<void> load() async {
    _lit ??= ShaderSlots(await ui.FragmentProgram.fromAsset('shaders/lit.frag'), litUniformNames);
    _book ??= ShaderSlots(await ui.FragmentProgram.fromAsset('shaders/book.frag'), bookUniformNames);
    _tab ??= ShaderSlots(await ui.FragmentProgram.fromAsset('shaders/tab.frag'), tabUniformNames);
    _glyphs ??= await GlyphMetrics.load(titleFontAsset);
    // 기본 정면 장정 그림(고른 책의 앞표지)
    await loadArtworkImages();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lit = _lit;
    final book = _book;
    if (lit == null || book == null) return;
    final m = makeMetrics(size.width);
    final cam = Cam(viewPitchMin);
    // 머리글 아래가 콘텐츠 위 끝(지금 앱 홈 스크롤 영역)
    final contentY = contentTop;
    final geo = computeRows(rows.length, m.scale, viewportHeight: (viewport ?? size.height) - contentY, bottomInset: bottomInset, real: math.min(rows.length, frostedFrom));
    Affine pxOf(RowGeom r) => Affine(m.scale, m.originX + sideMargin * m.scale, contentY + r.baseline);
    for (var i = 0; i < rowSpots.length && i < atlases.length && i < geo.length; i++) {
      final r = geo[i];
      if (only != null && !only!.contains(i)) continue;
      final px = pxOf(r);
      // 줄 캔버스(지금 앱 RowCanvas): 칸 위로 맨 윗줄 벽 끝까지, 아래로 판 밑 벽까지. 윗선반 판 윤곽 안은 비운다(그 판이 보인다)
      final y0 = math.max(0.0, r.top - headDu * m.scale);
      final y1 = r.top + r.height + shelfCastExtent * m.scale;
      canvas.save();
      final area = Path()..addRect(Rect.fromLTRB(0, contentY + y0, size.width, contentY + y1));
      final up = i > 0 ? plankOutlinePath((v) => toPx(cam, pxOf(geo[i - 1]), v), m.scale) : null;
      canvas.clipPath(up == null ? area : Path.combine(PathOperation.difference, area, up));
      drawRow(
        canvas,
        lit,
        book,
        cam,
        px,
        rows[i],
        rowSpots[i],
        atlases[i],
        r.space,
        keys[i],
        glyphs: _glyphs,
        photos: photos,
        tab: _tab,
        bookKeys: i < bookKeys.length ? bookKeys[i] : const {},
        frosted: i >= frostedFrom,
      );
      canvas.restore();
      if (contentY + y0 > size.height) break;
    }
  }

  @override
  bool shouldRepaint(ShelfPainter old) =>
      old.atlases != atlases ||
      old.photos != photos ||
      old.bookKeys != bookKeys ||
      old.contentTop != contentTop ||
      old.bottomInset != bottomInset ||
      old.viewport != viewport ||
      old.frostedFrom != frostedFrom ||
      old.look != look ||
      !setEquals(old.only, only);
}
