// 홈 화면(책장 탭): 서재를 읽어 줄마다 굽고(담아 둔 그림이 있으면 그대로) 실제 책장을 그린다. 지금 앱 features/home/HomeScreen을 옮기는 중.
// 머리줄·하단바 덮개·책장 그림까지. 측정: 켤 때마다 logcat에 [flbake] 줄마다·[fltotal] 합, 제목을 길게 누르면 다시 굽는다
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, Ticker;
import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction, OrdinalSortKey, SemanticsService;

import '../../services/qa_probe.dart';
import '../../services/cover_colors.dart';
import '../../ui/alert.dart' show appAlert;
import '../../ui/feedback.dart' show errorText, showToast;
import '../../ui/kit.dart' show Btn, Pressable, PullUp, Space, showSheet;
import 'locked_rows.dart';
import 'book_sheet.dart';
import '../settings/settings_screen.dart' show openProfile;
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
import '../../domain/book3.dart' show Book3, corners, toWorld;
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
import '../../scene_config/skin.dart' show SkinChoice, setSkin, skinChoice;
import '../../store/skin_store.dart' show saveSkin;
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
import '../book/binding_screen.dart' show openBindingEditor;

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

  /// 꾸미기 탭(2026-11-19 사용자 시안: 맨 위 '책 배치 | 선반 | 벽지', 머리줄 자리를 같은 높이로 덮어 책장이 밀리지 않는다)
  DecorateTab _decoTab = DecorateTab.books;

  /// 이번 꾸미기의 되돌리기 차례: 배치 편집(_placeUndo 표시, 되돌리기는 PlacementStore가) · 바꾸기 전 스킨 · 바꾸기 전 책 측면
  final List<Object> _decoUndo = [];
  static const _placeUndo = 'place';

  /// 이번 꾸미기에서 스킨·책 측면을 바꿨다: 마칠 때 빛을 새로 굽는다(고르는 동안은 그리는 값만 바꿔 바로 보인다)
  bool _skinChanged = false;
  String? _editId;
  String? _editMsg;
  ({
    String title,
    Pose pose,
    int lean,
    ({bool left, bool right}) canLean,
    double? leanDeg,
    double? frontPitch,
    double spin,
    double spinMax,
    ({double lo, double hi})? spinRange,
    ({double lo, double hi, double z, double back}) depth,
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

  Future<void> _onTap(Offset p) async {
    // 꾸미는 중 책을 잡았던 손가락: 고르기·놓기는 잡기가 이미 했다
    if (_eatTap) {
      _eatTap = false;
      return;
    }
    await _tapBook(_hitBook(p));
  }

  // ---------- 꾸미는 중 닿자마자 잡기(2026-11-18 사용자: 꾹 누르지 않아도 책에 닿아 끌면 바로 옮기기) ----------
  /// 책에 닿은 손가락(잡은 자리·책). 잡는 동안 스크롤을 끈다(physics)
  ({int pointer, Offset down, String id})? _grab;

  /// 이 손가락의 누르기(TapGestureRecognizer)는 버린다
  bool _eatTap = false;

  /// 꾹 눌러 시작한 끌기(꾸미기 밖에서 책을 꾹 눌러 꾸미기를 시작할 때)
  bool _lpDrag = false;

  /// 이만큼 움직이면 옮기기 시작(스크롤을 꺼 두어 누르기 판정 거리 18보다 작게 잡는다)
  static const _grabSlop = 6.0;

  void _grabDown(PointerDownEvent e) {
    _eatTap = false;
    // 선반·벽지 탭에서는 책을 잡지 않는다(어디를 밀어도 스크롤, 책을 누르면 책 배치 탭으로)
    if (!_decorating || _decoTab != DecorateTab.books || _grab != null || _drag != null || _head != null || _pinching) return;
    final id = _hitBook(e.localPosition);
    if (id == null) return;
    setState(() => _grab = (pointer: e.pointer, down: e.localPosition, id: id));
  }

  void _grabMove(PointerMoveEvent e) {
    final g = _grab;
    if (g == null || e.pointer != g.pointer || _lpDrag) return;
    if (_drag == null) {
      if ((e.localPosition - g.down).distance < _grabSlop) return;
      _beginDrag(g.down);
      if (_drag == null) return;
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
    }
    _dragGlobal = e.position;
    _moveDrag(e.localPosition);
  }

  void _grabUp(PointerUpEvent e) {
    final g = _grab;
    if (g == null || e.pointer != g.pointer) return;
    setState(() => _grab = null);
    _eatTap = true;
    if (_lpDrag) return;
    if (_drag != null) {
      _endDrag();
    } else {
      _tapBook(g.id);
    }
  }

  void _grabCancel(PointerCancelEvent e) {
    final g = _grab;
    if (g == null || e.pointer != g.pointer) return;
    setState(() => _grab = null);
    if (!_lpDrag && _drag != null) _cancelDrag();
  }

  /// 끌기 그만(제자리로)
  void _cancelDrag() {
    _stopAutoScroll();
    _stats?.cancel();
    _stats = null;
    setState(() => _drag = null);
    _dropDragSprite();
    _dragTarget = null;
    _clearPreview();
  }

  /// 책 누르기(화면 읽기의 책 칸도 같다): 꾸미는 중이면 고르기, 아니면 책 정보 시트
  Future<void> _tapBook(String? id) async {
    if (_decorating) {
      // 선반·벽지 탭에서 책을 누르면 책 배치 탭으로(빈 곳을 누르면 그 탭 그대로)
      if (id == null && _decoTab != DecorateTab.books) return;
      setState(() {
        _drag = null;
        _decoTab = DecorateTab.books;
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

  /// 꾸미는 중 책 칸의 읽기 동작: 같은 선반에서 왼쪽·오른쪽으로 한 칸(끌기를 못 하는 화면 읽기 사용자도 순서를 바꾼다, 2026-11-16 QA 영숙 F8).
  /// 조작부의 '순서' 줄은 뺐다(2026-11-18 사용자): 옮긴 뒤 새 자리를 소리로 알린다
  static const _moveLeft = CustomSemanticsAction(label: '왼쪽으로 한 칸 옮기기');
  static const _moveRight = CustomSemanticsAction(label: '오른쪽으로 한 칸 옮기기');

  Future<void> _moveByA11y(String id, int d) async {
    final s = PlacementStore.instance, l = s.layout;
    if (l == null) return;
    if (_editId != id) setState(() => _editId = id);
    final r = moveBy(l, s.books, id, d);
    final view = View.of(context);
    final ok = r.ok && await _apply(r);
    if (!mounted) return;
    final now = PlacementStore.instance.layout;
    final p = now == null ? null : placementOf(now, id);
    var text = d < 0 ? '더 왼쪽으로 옮길 수 없어요' : '더 오른쪽으로 옮길 수 없어요';
    if (ok && now != null && p != null) {
      final at = shelfItems(now, p.shelfId).indexWhere((it) => it.bookIds.contains(id));
      final shelfNo = sortedShelves(now).indexWhere((x) => x.id == p.shelfId) + 1;
      text = '$shelfNo번째 선반, 왼쪽에서 ${at + 1}번째';
    }
    SemanticsService.sendAnnouncement(view, text, TextDirection.ltr);
  }

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
      _startDecorate();
      _editId = id;
      _editMsg = null;
    });
    tabBarHidden.value = true;
    MiniTimerPlace.instance.setHidden(true);
    _computePanel();
  }

  /// 꾸미기 시작(꾸미기 단추, 또는 꾹 눌러 끌기)
  void _startDecorate() {
    if (_decorating) return;
    _decorating = true;
    _decoTab = DecorateTab.books;
    _decoUndo.clear();
    _skinChanged = false;
  }

  void _exitDecorate() {
    _clearPreview();
    // 고른 스킨·책 측면으로 빛을 다시 굽고 시작 사진을 버린다(지난 '선반, 벽지' 화면의 적용하기와 같다)
    if (_skinChanged) {
      _skinChanged = false;
      dropHomeSnapshot();
      shelfRefresh.value++;
    }
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
    setState(() => _panel = (
          title: s.books[id]?.title ?? '',
          pose: p.pose == Pose.front && (p.pitch ?? 0) >= 89.95 ? Pose.horizontal : p.pose,
          lean: p.tilt.sign,
          canLean: (left: can(-1), right: can(1)),
          leanDeg: p.leanAngle?.abs(),
          frontPitch: fs?.state.pitch,
          spin: fs?.state.spin ?? p.spin ?? 0,
          spinMax: p.pose == Pose.front ? maxFrontSpin : maxSpin,
          spinRange: spinRangeOf(l, s.books, id),
          depth: reachableDepth(l, s.books, id),
        ));
  }

  /// 편집 결과 확정(실패면 까닭을 조작부에, 성공 알림은 note)
  Future<bool> _apply(EditResult r, [String? note]) async {
    if (!r.ok) {
      setState(() => _editMsg = r.reason == 'no-change' ? null : editFailText[r.reason] ?? editFailText['outside']);
      return false;
    }
    final bool ok;
    try {
      ok = await PlacementStore.instance.commit(r.layout!);
    } catch (e) {
      // 기기에 쓰지 못하면 배치는 앞으로 돌아가고(PlacementStore) 까닭을 알린다(2026-11-20: 알림 없이 처리 안 된 오류로 끝났다)
      if (mounted) {
        _computePanel();
        appAlert(context, '배치를 저장하지 못했어요', errorText(e));
      }
      return false;
    }
    if (ok && _decorating) _decoUndo.add(_placeUndo);
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

  /// 표지 책 기대기: 바로 | 뒤로(뒤 벽에 기대기)
  void _editFrontLean(bool back) => _edit((l, b, id) => setFrontLean(l, b, id, back));

  void _editSpin(double deg) => _edit((l, b, id) {
        if (placementOf(l, id)?.pose != Pose.front) return setSpin(l, b, id, deg);
        final fs = frontStateOf(l, b, id);
        final r = fs == null ? null : frontSpin(l, b, id, fs.state, fs.qx, deg);
        return r == null ? const EditResult.fail('no-space') : EditResult.ok(r.layout);
      });

  void _editDepth(double z) => _edit((l, b, id) => setDepth(l, b, id, z));

  // ---------- 끌어 옮기기(지금 앱 HomeScreen beginDrag·endDrag, useShelfDragPreview) ----------
  /// 잡은 책: 잡은 곳(콘텐츠 좌표)·잡은 항목 가운데와 폭(설계 단위)·윤곽·끄는 책을 뺀 배치(끌기 한 번에 한 번만 계산)
  ({String id, String shelfId, Offset start, double centerDU, double widthDU, ui.Path path, ShelfLayout detached})? _drag;
  Offset _dragNow = Offset.zero;
  bool _dragOk = true;

  /// 끄는 책 그림(아래 그늘·책 모양을 들 때 한 번 굳힌다): 프레임마다는 옮겨 놓기만 한다
  /// (전에는 프레임마다 그늘을 흐리고 책장 그림 전체를 책 윤곽으로 잘라 그렸다)
  ({ui.Image image, Rect rect})? _dragSprite;

  void _makeDragSprite(ui.Path path) {
    _dropDragSprite();
    final img = _shelfImage, g = _geom;
    if (img == null || g == null) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scale = g.m.scale;
    final b = path.getBounds();
    // 그늘 흐림(시그마 약 6·scale의 3배)과 아래로 4·scale 내린 몫
    final pad = 6 * scale * 3 + 4 * scale;
    final r = Rect.fromLTRB(b.left - pad, b.top - pad, b.right + pad, b.bottom + pad);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)
      ..scale(dpr)
      ..translate(-r.left, -r.top);
    _DragPainter.paintBook(canvas, path, scale, img, dpr);
    final pic = rec.endRecording();
    _dragSprite = (image: pic.toImageSync((r.width * dpr).ceil(), (r.height * dpr).ceil()), rect: r);
    pic.dispose();
  }

  void _dropDragSprite() {
    final old = _dragSprite?.image;
    _dragSprite = null;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

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
      _startDecorate();
      _decoTab = DecorateTab.books;
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
    _makeDragSprite(path);
    tabBarHidden.value = true;
    // 꾸미는 동안 작은 타이머는 숨긴다: 조작부의 위치 mm·회전 값을 가렸다(2026-11-16 QA 현우 F9)
    MiniTimerPlace.instance.setHidden(true);
    _computePanel();
    _dragTarget = null;
    _dropCache.clear();
    _rowCache.clear();
    if (qaFrames) _stats = _DragStats();
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
    if (shelfId == d.shelfId) {
      final t = findSwapTarget(l, s.books, d.id, centerDU);
      return (key: 'same:${t.kind}:${t.itemKey}:${t.index}:${t.x}:${t.dx}', shelfId: shelfId, run: () => applySwapTarget(l, s.books, d.id, t));
    }
    final t = findDropTarget(d.detached, s.books, shelfId, centerDU, placementOf(l, d.id)!.pose, d.widthDU);
    return (key: 'other:$shelfId:${t.kind}:${t.itemKey}:${t.index}:${t.x}', shelfId: shelfId, run: () => moveBook(l, s.books, d.id, t));
  }

  /// 마지막으로 본 놓을 자리와 그 결과
  ({String key, EditResult result})? _dragTarget;

  /// 이번 끌기에서 계산한 놓을 자리(열쇠 → 결과·기대기까지 푼 미리 보기 배치)와 만든 미리 보기 줄(줄 차례·모습 열쇠 → 줄)
  final Map<String, ({EditResult result, ShelfLayout shown})> _dropCache = {};
  final Map<String, _PreviewRow> _rowCache = {};

  EditResult _dropAt(Offset at) {
    _stats?.steps++;
    final t = qaTime('drag.target', () => _targetAt(at));
    final last = _dragTarget;
    if (last != null && last.key == t.key) return last.result;
    _stats?.targets++;
    final d = _drag!, l = PlacementStore.instance.layout!, books = PlacementStore.instance.books;
    // 같은 끌기에서 본 자리면 계산해 둔 것을 쓴다(손가락이 오가면 같은 자리를 다시 지난다)
    final hit = _dropCache[t.key];
    if (hit != null) _stats?.cacheHits++;
    final r = hit?.result ?? qaTime<EditResult>('drag.run', t.run);
    _dragTarget = (key: t.key, result: r);
    // 미리 보기: 놓을 수 있으면 그 배치(기대기까지 그 줄에서 풀어 둔다: 놓는 순간 각도가 튀지 않게), 아니면 확정 배치에서 든 책만 빠진다
    if (r.ok && t.shelfId != null) {
      final shown = hit?.shown ??
          qaTime<ShelfLayout>('drag.lean', () {
            final src = t.shelfId == d.shelfId ? r.layout! : resolveLeans(r.layout!, books, d.shelfId);
            return resolveLeans(src, books, t.shelfId);
          });
      if (hit == null) {
        if (_dropCache.length >= 256) _dropCache.clear();
        _dropCache[t.key] = (result: r, shown: shown);
      }
      qaTime('drag.preview', () => _showPreview(shown, {d.shelfId, t.shelfId!}, hide: d.id, key: t.key));
    } else {
      qaTime('drag.preview', () => _showPreview(l, {d.shelfId}, hide: d.id, key: 'lifted'));
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

  /// 손가락 움직임은 프레임마다 한 번만 놓을 자리를 본다(터치는 프레임보다 자주 온다: 그때마다 배치를 풀면 한 프레임에 여러 번 계산했다)
  bool _dragStepQueued = false;

  /// 시험 빌드 전용 끌기 기록
  _DragStats? _stats;

  void _moveDrag(Offset at) {
    if (_drag == null) return;
    _stats?.moves++;
    // 굽기는 손가락이 쉴 때만(움직이는 동안 미뤄 둔다)
    if (at != _dragNow && (_previewBake?.isActive ?? false)) _schedulePreviewBake(_previewKey);
    _dragNow = at;
    if (_dragStepQueued) return;
    _dragStepQueued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) => _dragStep());
  }

  void _dragStep() {
    _dragStepQueued = false;
    if (_drag == null || !mounted) return;
    final r = _dropAt(_dragNow);
    setState(() => _dragOk = r.ok || r.reason == 'no-change');
  }

  Future<void> _endDrag() async {
    _stopAutoScroll();
    final d = _drag;
    if (d == null) return;
    final r = _dropAt(_dragNow);
    setState(() => _drag = null);
    _dropDragSprite();
    _dragTarget = null;
    _stats?.finish();
    _stats = null;
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
      final sig = _bodiesSig(bodies);
      // 보이는 모습이 그대로면(같은 선반에서 빈 곳으로 끌면 놓을 자리 열쇠는 0.5DU마다 바뀌지만 다른 책은 그대로다) 줄을 다시 만들지 않는다.
      // 확정 배치와 같은 줄은 미리 보기에서 뺀다(굳힌 그림 그대로)
      final had = _previewRows[i];
      if (had != null && had.sig == sig) {
        next[i] = had;
        continue;
      }
      if (i < c.rows.length && sig == _bodiesSig(c.rows[i].books)) continue;
      // 이번 끌기에서 같은 모습으로 만든 줄이 있으면 그대로(같은 줄 그림이라 다시 그릴 곳도 없다)
      final cached = _rowCache['$i|$sig'];
      if (cached != null) {
        next[i] = cached;
        continue;
      }
      final old = c.rows[i], oldSpots = _rowSpots[i];
      final row = rowFromBooks(bodies, _libBooks, rowSpace, top: old.top, last: old.last)..tabLoss = old.tabLoss;
      final spots = [
        for (final it in row.items)
          switch (old.indexOf(it.key)) { final k when k >= 0 && k < oldSpots.length => oldSpots[k], _ => oldSpots.first },
      ];
      next[i] = _PreviewRow(row, spots, sig);
      if (_rowCache.length >= 64) _rowCache.clear();
      _rowCache['$i|$sig'] = next[i]!;
    }
    if (next.length == _previewRows.length && next.entries.every((e) => identical(_previewRows[e.key], e.value))) {
      // 바뀐 것이 없다: 그림도 굽기 차례도 그대로
      if (next.isEmpty) _previewKey = key;
      return;
    }
    _stats?.previews++;
    _previewKey = key;
    _setPreviewRows(next);
    _previewBake?.cancel();
    if (bake && next.isNotEmpty) _schedulePreviewBake(key);
  }

  /// 미리 보는 줄 굽기 예약: 끄는 동안은 손가락이 0.7초 쉴 때(움직이면 다시 미룬다), 놓은 뒤·손잡이는 0.15초 뒤
  void _schedulePreviewBake(String? key) {
    _previewBake?.cancel();
    if (key == null) return;
    _previewBake = Timer(Duration(milliseconds: _drag != null ? 700 : 150), () {
      _stats?.bakes++;
      _bakePreview(key);
    });
  }

  /// 줄 책들의 보이는 모습 열쇠(자리·자세, 0.01 단위)
  static String _bodiesSig(List<Book3> bodies) {
    final b = StringBuffer();
    String f(double v) => (v * 100).round().toString();
    for (final x in bodies) {
      b.write('${x.id},${f(x.t.x)},${f(x.t.y)},${f(x.t.z)},${f(x.roll)},${f(x.yaw)},${f(x.spin)},${f(x.pitch)};');
    }
    return b.toString();
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
      _setPreviewRows({..._previewRows, e.key: _PreviewRow(e.value.row, b.at, e.value.sig, b.image, b.keys, b.bookKeys)});
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

  /// 표지 책 뒤로 젖힌 각도 글자(조작부). 끄는 동안만 '젖혔어요', 가만히 있을 때는 지금 각도만
  /// (2026-11-15 QA: 표지로 세우자마자 끌지도 않았는데 '머리를 끌어 뒤로 12° 젖혔어요'가 나왔다. 표지 책은 처음에 벽에 기대 젖혀 선다).
  /// 바꾸는 법 안내('책 머리를 위아래로 끌면…')는 뺐다(2026-11-18 사용자: 젖힌 각도만 남기기). 머리 손잡이 점이 보이고 화면 읽기 이름에 있다
  String? get _anglesText {
    final s = PlacementStore.instance, l = s.layout, id = _editId;
    final pitch = _head != null ? _headCur?.pitch : (l == null || id == null ? null : frontStateOf(l, s.books, id)?.state.pitch);
    if (pitch == null) return null;
    final deg = jsRound(pitch).toInt();
    if (_head != null) return '뒤로 $deg° 젖혔어요';
    // 바로 세웠으면 '뒤로 0°' 대신(기대기 '바로'와 같은 말)
    return deg == 0 ? '똑바로 서 있어요' : '뒤로 $deg° 젖혀 있어요';
  }

  bool get _canUndo => _decoUndo.isNotEmpty || PlacementStore.instance.canUndo;

  /// 되돌리기: 이번 꾸미기에서 마지막에 바꾼 것(배치·스킨·책 측면)부터 한 번에 하나씩, 여러 번(배치는 PlacementStore가 30번까지 쌓는다,
  /// 2026-11-21 사용자 '되돌리기 1번밖에 안 되는 게 좀 별론데'). 이번에 바꾼 것이 없으면 지난 배치 편집
  Future<void> _undo() async {
    final last = _decoUndo.isEmpty ? _placeUndo : _decoUndo.removeLast();
    switch (last) {
      case SkinChoice prev:
        _applySkin(prev);
      case SpineLook prev:
        _applySpine(prev);
      default:
        await PlacementStore.instance.undo();
    }
    if (!mounted) return;
    setState(() => _editMsg = null);
    _computePanel();
  }

  /// 선반·벽지 고르기: 책장에 바로 보이고(그리는 값) 바로 저장한다. 빛은 꾸미기를 마칠 때 다시 굽는다
  void _pickSkin(SkinChoice next) {
    final prev = skinChoice;
    if (next == prev || !_applySkin(next)) return;
    _decoUndo.add(prev);
  }

  bool _applySkin(SkinChoice c) {
    if (!setSkin(c)) return false;
    saveSkin(c);
    _skinChanged = true;
    setState(() {});
    return true;
  }

  /// 책 측면 고르기(책 배치 탭): 표지 사진을 그 모양으로 다시 준비해 바로 바꿔 그린다(_spineLookChanged)
  void _pickSpine(SpineLook next) {
    final prev = spineLook.value;
    if (next == prev) return;
    _applySpine(next);
    _decoUndo.add(prev);
  }

  void _applySpine(SpineLook v) {
    spineLook.value = v;
    saveSpineLook(v);
    _skinChanged = true;
    setState(() {});
  }

  /// 꾸미기 아래 칸: 책 배치는 고른 책 조작부(고르기 전에는 안내 하나), 선반·벽지는 고르기 칸
  Widget _decoBottom() {
    if (_decoTab != DecorateTab.books) return SkinSheet(tab: _decoTab, choice: skinChoice, onPick: _pickSkin);
    final p = _panel;
    if (p == null) return DecorateHint(msg: _editMsg);
    final id = _editId;
    return DecoratePanel(
      bookKey: _editId,
      title: p.title,
      pose: p.pose,
      lean: p.lean,
      canLean: p.canLean,
      msg: _editMsg,
      angles: _anglesText,
      spin: p.spin,
      spinMax: p.spinMax,
      spinRange: p.spinRange,
      depth: p.depth,
      onPose: _editPose,
      onLean: _editLean,
      leanDeg: p.leanDeg,
      frontBack: p.frontPitch == null ? null : p.frontPitch! > 0.5,
      onFrontLean: _editFrontLean,
      onSpin: _editSpin,
      onDepth: _editDepth,
      spine: spineLook.value,
      onSpine: _pickSpine,
      onBinding: () {
        if (id != null) openBindingEditor(context, id);
      },
    );
  }

  /// 탭 바꾸기: 선반·벽지 탭에서는 고른 책을 놓는다(아래 칸이 그 탭 것으로 바뀐다)
  void _setDecoTab(DecorateTab t) {
    if (t == _decoTab) return;
    setState(() {
      _decoTab = t;
      if (t != DecorateTab.books) {
        _editId = null;
        _panel = null;
        _editMsg = null;
      }
    });
  }

  /// 지난 책장이 없는데 옆으로 밀었다: 언제 생기는지 알린다(10초에 한 번만)
  DateTime? _pastHintAt;
  void _noPastShelf(DragEndDetails d) {
    if (d.primaryVelocity == null || d.primaryVelocity!.abs() < 400) return;
    final now = DateTime.now();
    if (_pastHintAt != null && now.difference(_pastHintAt!).inSeconds < 10) return;
    _pastHintAt = now;
    showToast(context, '해가 바뀌면 올해 책장이 지난 책장으로 남아요. 그때부터 옆으로 넘겨 볼 수 있어요.');
  }

  /// 책장 그림(입력이 같으면 다시 쓰고, 바뀌면 다시 그린다)
  ui.Image? _shelfImage;

  /// 책장 그림이 마지막으로 바뀐 때: 연달아 바뀌는 동안(손잡이로 젖히기·앞뒤 막대처럼 매 프레임 바뀔 때)은 굳히지 않고 그대로 그리다가
  /// 멈추면 굳힌다(매 프레임 굳히면 그대로 그리는 것보다 무겁다)
  DateTime _shelfChangedAt = DateTime(0);
  Timer? _settleFreeze;

  /// 끄는 동안 굳힌 그림 위에 덧놓는 바뀐 줄 띠 그림(위 끝 · 어떤 줄 · 무엇으로 그렸는지)
  ui.Image? _overlay;
  Object? _overlayKey;

  /// 띠 그림의 화소 위·아래 끝과 그때 그린 값(다음 띠는 이 그림을 바탕으로 바뀐 곳만 다시 그린다)
  int _overlayTopPx = 0, _overlayBottomPx = 0;
  ShelfPainter? _overlayPainter;
  Set<int> _overlayPreviews = const {};

  /// 굳힌 책장 그림을 그린 값(끄는 동안 바탕: 이것과 다른 곳만 다시 그린다)
  ShelfPainter? _frozenPainter;

  /// 줄마다 보이는 모습 열쇠(굽기 열쇠 + 책 그림 재료). 굳힌 그림 때의 것과 견주어 바뀐 줄만 다시 굳힌다
  List<String> _rowSigs = const [];
  List<String> _frozenSigs = const [];
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

  /// 굳힌 그림 위에 띠로 덧그릴 줄: 미리 보는 줄. 미리 보기 없이 책이 미끄러지는 동안(놓기를 그만둬 제자리로 돌아갈 때, 조작부로 기대기·자세를 바꾼 뒤)은
  /// 굳힌 그림과 모습이 다른 줄(그 밖의 줄은 굳힌 그림 그대로라 책장 전체를 셰이더로 다시 그리지 않는다. 2026-11-19 측정(에뮬): 그 0.23초 동안 프레임마다 0.3~0.45초)
  Set<int> _overlayRows(ShelfPainter p) {
    if (_shown != null) return _previewRows.keys.toSet();
    final c = _case;
    if (!_tweening || c == null || _frozenPainter == null || _frozenSigs.length != _rowSigs.length) return const {};
    return {
      for (var i = 0; i < _rowSigs.length; i++)
        if (_rowSigs[i] != _frozenSigs[i]) i,
      for (var i = 0; i < p.rows.length && i < c.rows.length; i++)
        if (!identical(p.rows[i], c.rows[i])) i,
    };
  }

  /// 시작 사진은 굳힌 그림이 3초 그대로일 때 저장한다(PNG로 읽어 내기가 무겁다: 책을 옮겨 놓자마자 하면 끊겼다).
  /// 꾸미는 동안은 머리글 없이 위로 붙은 책장이라 저장하지 않는다(꾸미기를 마치면 다시 굳히며 저장한다)
  Timer? _snapTimer;
  void _scheduleSnap() {
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(seconds: 3), () {
      final img = _shelfImage;
      if (!mounted || img == null || _decorating || _drag != null) return;
      _saveSnap(img);
    });
  }

  /// 굳힌 그림을 그린 뒤 바뀐 줄(줄 차례). 줄 수·자리·스킨·표지 사진처럼 모두가 바뀌었거나 절반 넘게 바뀌었으면 null(전체를 다시 그린다)
  List<int>? _changedRows(ShelfPainter p, ui.Image? old, int w, int h) {
    final f = _frozenPainter;
    if (old == null || old.width != w || old.height != h || f == null) return null;
    if (f.look != p.look ||
        !identical(f.photos, p.photos) ||
        f.rows.length != p.rows.length ||
        f.contentTop != p.contentTop ||
        f.bottomInset != p.bottomInset ||
        f.viewport != p.viewport ||
        f.frostedFrom != p.frostedFrom ||
        _frozenSigs.length != _rowSigs.length ||
        _rowSigs.length != p.rows.length) {
      return null;
    }
    final changed = [for (var i = 0; i < _rowSigs.length; i++) if (_rowSigs[i] != _frozenSigs[i]) i];
    return changed.length * 2 > _rowSigs.length ? null : changed;
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
    // 2026-11-19: 띠도 바뀐 곳만 다시 그린다. 같은 선반 빈 곳으로 끌면 0.5DU마다 띠 전체(두 줄)를 셰이더로 다시 굳혀 끄는 손이 드르륵 끊겼다.
    // 바탕(지난 띠 그림 또는 굳힌 책장 그림)과 자세가 다른 책 둘레의 세로 기둥만 그 위에 다시 그리고, 미끄러지는 동안도 그 기둥만 그대로 그린다
    final previews = frozen == null || !ShelfPainter.ready ? const <int>{} : _overlayRows(painter);
    if (frozen != null && previews.isNotEmpty) {
      final only = {for (final i in previews) ...[i, i + 1]};
      final band = painter.bandOf(only, size);
      final topPx = (band.$1 * dpr).floor(), bottomPx = math.min(h, (band.$2 * dpr).ceil());
      final top = topPx / dpr, bandH = (bottomPx - topPx) / dpr;
      final ov = _overlay;
      final onOverlay = ov != null && _overlayTopPx == topPx && _overlayBottomPx == bottomPx && ov.width == w && _overlayPainter != null && setEquals(_overlayPreviews, previews);
      // 기록용: 줄 하나 높이(다시 그린 넓이를 줄 수로)
      final rowH = qaFrames && _geom != null && _geom!.geo.isNotEmpty ? _geom!.geo.first.height : 1.0;
      final base = onOverlay ? _overlayPainter : (frozen.width == w ? _frozenPainter : null);
      final rows = painter.onlyRows(only);
      Widget frozenImage() => RawImage(image: frozen, width: size.width, height: size.height, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill);
      Widget bandImage(ui.Image img) => Positioned(
            left: 0,
            top: top,
            width: size.width,
            height: img.height / dpr,
            child: RawImage(image: img, width: size.width, height: img.height / dpr, scale: dpr, filterQuality: FilterQuality.none, fit: BoxFit.fill),
          );
      // 띠 그림은 지난 띠 그림(없거나 다른 띠면 굳힌 책장 그림)을 바탕으로, 그것과 자세가 다른 책 둘레만 다시 그려 고쳐 간다.
      // 미끄러지는 동안(약 0.25초)도 프레임마다 그 프레임에 움직인 책 둘레만 다시 그린다(처음 바탕과 견주면 밀린 책이 쌓여 다시 그릴 곳이 커졌다)
      final okey = ((only.toList()..sort()).join(','), topPx, bottomPx, identityHashCode(painter.rows), identityHashCode(painter.atlases), painter.look, identityHashCode(painter.photos));
      if (_tweening) _stats?.tweenFrames++;
      if ((ov == null || !onOverlay || _overlayKey != okey) && bottomPx > topPx) {
        final rects = qaTime('drag.rects', () => rows.dirtyRects(previews, base, size));
        if (onOverlay && rects.isEmpty) {
          _overlayKey = okey;
          _overlayPainter = painter.snapshot();
        } else {
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec)
            ..scale(dpr)
            ..translate(0, -top);
          // 바탕을 화소 그대로 옮기고(띠 위 끝은 화소 경계라 1:1) 바뀐 곳만 다시 그린다
          final src = onOverlay ? ov : frozen;
          canvas.drawImageRect(src, Rect.fromLTWH(0, onOverlay ? 0 : topPx.toDouble(), w.toDouble(), (bottomPx - topPx).toDouble()), Rect.fromLTWH(0, top, w / dpr, bandH),
              Paint()..filterQuality = FilterQuality.none);
          if (rects.isNotEmpty) _RectsPainter(rows, rects).paint(canvas, size);
          final pic = rec.endRecording();
          _overlay = pic.toImageSync(w, bottomPx - topPx);
          _overlayTopPx = topPx;
          _overlayBottomPx = bottomPx;
          _overlayKey = okey;
          _overlayPainter = painter.snapshot();
          _overlayPreviews = previews;
          pic.dispose();
          _stats?.band(rects, size.width, rowH);
          if (ov != null) WidgetsBinding.instance.addPostFrameCallback((_) => ov.dispose());
        }
      }
      final now = _overlay;
      return Stack(fit: StackFit.expand, children: [frozenImage(), if (now != null) bandImage(now)]);
    }
    if (_overlay != null) {
      final o = _overlay!;
      _overlay = null;
      _overlayKey = null;
      _overlayPainter = null;
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
      final canvas = Canvas(rec);
      final old = _shelfImage;
      // 줄 자리·모습이 그대로인 줄은 지난 그림을 그대로 옮기고 바뀐 줄만 다시 그린다(책을 옮겨 놓은 뒤 두세 줄만 바뀐다: 전에는 놓을 때마다 책장 전체를 다시 그렸다).
      // 2026-11-19 에뮬에서 부분·전체 굳히기 화면이 화소까지 같았다(차이 최대 7/255)
      final changed = _changedRows(painter, old, w, h);
      if (changed != null) {
        canvas.drawImage(old!, Offset.zero, Paint()..filterQuality = FilterQuality.none);
        canvas.scale(dpr);
        // 이 줄들이 그리는 높이 안은 그 줄과 바로 아래 줄을 차례대로 그리면 전체를 그린 것과 같다(ShelfPainter.dirtyRects)
        final rects = painter.dirtyRects(changed.toSet(), null, size);
        if (rects.isNotEmpty) _RectsPainter(painter.onlyRows({for (final i in changed) ...[i, i + 1]}), rects).paint(canvas, size);
      } else {
        canvas.scale(dpr);
        painter.paint(canvas, size);
      }
      final pic = rec.endRecording();
      _shelfImage = pic.toImageSync(w, h);
      _shelfKey = key;
      _frozenPainter = painter.snapshot();
      _frozenSigs = List.of(_rowSigs);
      pic.dispose();
      if (qaFrames) {
        // ignore: avoid_print
        print('[flfreeze] ${changed == null ? 'all' : 'rows $changed'}');
      }
      _scheduleSnap();
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
    // 마지막 선반 아래 잠긴 칸(여섯 칸까지): 흐린 예시 책. 예시 줄은 세 줄을 돌려 쓴다
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
    final sigs = <String>[];
    for (var ri = 0; ri < c.rows.length; ri++) {
      final r = c.rows[ri];
      final probe = ri == c.rows.length - 1; // 맨 뒤는 값 확인용(시간에 넣지 않는다)
      final key = bakeKey(r);
      sigs.add('$key|${_looksSig(r)}');
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
      _rowSigs = sigs;
      _runs.add(run);
      _libBooks = lib.books;
      _state = '${_runs.length}번째';
      _busy = false;
    });
    // 새 그림이 나왔으니 미리 보기는 걷는다(미리 보는 줄은 지난 그림의 자리를 쓰고 있었다). 끄는 중이면 다음 손가락 움직임에 다시 만든다
    _dragTarget = null;
    _dropCache.clear();
    _rowCache.clear();
    _clearPreview();
    if (_again) {
      _again = false;
      _refresh();
    }
    // 보여 달라던 책이 이번 굽기로 줄에 들어왔으면 그리로(줄 자리는 다음 화면을 그릴 때 정해진다)
    if (_pendingFocus != null) WidgetsBinding.instance.addPostFrameCallback((_) => _tryFocus());
  }

  // 잠긴 선반 시트(지금 앱 LockedShelfSheet): 세 칸까지는 바로 열고, 그 위는 유료 예정이라 준비 중으로 알린다(2026-11-15 사용자 결정).
  // '무료로'는 쓰지 않는다(QA: 곧 돈 받겠다는 뜻으로 읽혔다). 남은 칸 수를 알린다
  void _openLocked() {
    final shelves = PlacementStore.instance.layout?.shelves.length ?? _rowSpots.length - _lockedCount;
    final free = openableShelfCount(shelves);
    if (free == 0) {
      // 다음 행동이 없는 안내라 시트 대신 확인창(DESIGN 5-1). 문구는 그대로(결제 고지 기준 확인 필요)
      appAlert(context, '선반 더 열기', '선반은 $freeShelfSlots칸까지 쓸 수 있어요. 더 여는 기능은 준비하고 있어요.\n책장에 없는 책은 내 책에 그대로 보관돼요.');
      return;
    }
    showSheet<void>(
      context,
      title: '선반 한 칸 더 열기',
      description: '책을 더 진열할 수 있는 선반이 한 칸 늘어나요. 앞으로 $free칸 더 열 수 있어요.',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Btn(
          label: '선반 열기',
          size: 'xlarge',
          onPress: () async {
            Navigator.pop(ctx);
            Object? err;
            var ok = false;
            try {
              ok = await PlacementStore.instance.addShelf();
            } catch (e) {
              err = e;
            }
            if (!mounted) return;
            if (ok) {
              showToast(context, '선반을 열었어요.');
            } else {
              appAlert(context, '선반을 열지 못했어요', err == null ? '잠시 뒤 다시 시도해 주세요.' : errorText(err));
            }
          },
        ),
      ),
    );
  }

  /// 책등 모양(꾸미기 '책 측면')이 바뀌었다: 표지 사진을 그 모양으로 다시 준비한다(실물 측면이면 책등 사진도 받는다). 오는 대로 바꿔 그린다
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
    _snapTimer?.cancel();
    _dragSprite?.image.dispose();
    _tweenTicker?.dispose();
    _autoScroll?.cancel();
    _coverRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    shelfRefresh.removeListener(_refresh);
    spineLook.removeListener(_spineLookChanged);
    focusBookOnShelf.removeListener(_focusBook);
    LibraryModel.instance.removeListener(_libraryChanged);
    BookcaseStore.instance.removeListener(_bookcasesChanged);
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
        // 측정 메뉴: 제목을 길게 누르면 다시 굽고 시간을 알린다(지금 앱 측정 번들의 책장 메뉴 자리). 시험 빌드(QA_FRAMES)에서만
        onLongPress: !qaFrames || _busy ? null : _run,
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
                    // 꾸미는 동안 머리줄 자리는 꾸미기 맨 위 줄(같은 높이)이 덮는다: 책장 자리는 그대로
                    final contentTop = pad.top + homeHeaderHeight;
                    final bottomInset = navigationShelfReserve + pad.bottom;
                    final m = makeMetrics(box.maxWidth);
                    final n = _rowSpots.length;
                    final geo = computeRows(n, m.scale, viewportHeight: box.maxHeight - contentTop, bottomInset: bottomInset, real: n - _lockedCount);
                    // 잠긴 칸까지 다 보이게 세로로 넘긴다(머리줄도 함께, 지금 앱 홈 스크롤)
                    final last = geo.isEmpty ? null : geo.last;
                    // 끝 여백(지금 앱 contentEnd): 판 그늘 몫과 하단바 블록 + 덮개 0.6 중 큰 것
                    final tail = math.max((shelfCastExtent + 8) * m.scale, pad.bottom + TabBarStyle.gap + TabBarStyle.height + TabBarStyle.fade * 0.6);
                    // 꾸미는 동안은 아래 조작부 뒤에 숨는 줄도 위로 밀어 볼 수 있게 끝 여백을 늘린다(책을 고른 조작부 약 330에 여유를 둬 360, 큰 글씨면 화면의 62%까지)
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
                        physics: _head != null || _grab != null || _pinching ? const NeverScrollableScrollPhysics() : null,
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
                                    child: CustomPaint(painter: _DragPainter(d.path, _dragNow - d.start, _geom!.m.scale, _dragOk, _shelfImage, MediaQuery.devicePixelRatioOf(context), _dragSprite)),
                                  ),
                                ),
                              // 누르기: 책 정보 시트(꾸미는 중이면 고르기), 꾹 누르기: 꾸미기
                              Positioned.fill(
                                key: const ValueKey('touch'),
                                // 꾸미는 중에는 책에 닿는 순간 잡는다(머리 손잡이처럼 Listener, 잡는 동안 스크롤을 끈다): 움직이면 바로 옮기고, 그대로 떼면 고르기
                                child: Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: _grabDown,
                                  onPointerMove: _grabMove,
                                  onPointerUp: _grabUp,
                                  onPointerCancel: _grabCancel,
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
                                          // 꾸미는 중 책에 닿은 손가락은 잡기가 맡는다
                                          if (_grab != null) return;
                                          _beginDrag(e.localPosition);
                                          if (_drag == null) return;
                                          _lpDrag = true;
                                          _dragGlobal = e.globalPosition;
                                          _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
                                        })
                                        ..onLongPressMoveUpdate = ((e) {
                                          if (!_lpDrag) return;
                                          _dragGlobal = e.globalPosition;
                                          _moveDrag(e.localPosition);
                                        })
                                        ..onLongPressEnd = ((_) {
                                          if (!_lpDrag) return;
                                          _lpDrag = false;
                                          _endDrag();
                                        })
                                        ..onLongPressCancel = (() {
                                          if (!_lpDrag) return;
                                          _lpDrag = false;
                                          _cancelDrag();
                                        }),
                                    ),
                                  },
                                ),
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
                                      customSemanticsActions: _decorating
                                          ? {_moveLeft: () => _moveByA11y(b.id, -1), _moveRight: () => _moveByA11y(b.id, 1)}
                                          : null,
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
                              // 머리줄(책장과 함께 스크롤: 지금 앱 2026-11-04 '상단 라인은 고정이 아니야'): 왼쪽 '나의 책장'과 그 밑 해, 오른쪽 꾸미기·책 추가·내 정보
                              // 자식 목록 자리는 그대로 둔다(있다 없다 하면 뒤의 누르기 층이 새로 만들어져 끌던 손가락이 끊긴다)
                              // 화면 읽기는 머리줄('나의 책장'·꾸미기·책 추가·내 정보)을 책보다 먼저 읽는다(2026-11-16 QA 영숙 F11: '내 정보'가 책 뒤로 밀렸다)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: pad.top,
                                child: _decorating
                                    ? const SizedBox.shrink()
                                    : Semantics(container: true, explicitChildNodes: true, sortKey: const OrdinalSortKey(0), child: header(headerOpacity)),
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
                                    child: Pressable(
                                      onPress: _openLocked,
                                      child: const Center(child: _LockIcon()),
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
    // 꾸미는 동안은 책장을 조금 위로(꾸미기 맨 위 줄이 머리줄보다 낮다: 줄과 책장 사이가 넓었다, 2026-11-20 사용자 '밑에 책장 조금 위로 올려').
    // 배치(줄 높이 · 굽기)는 그대로 두고 그린 자리만 옮긴다(누르기 · 끌기도 같이 옮겨진다)
    Widget liftedPage(double headerOpacity) => TweenAnimationBuilder<double>(
          tween: Tween(end: _decorating ? homeHeaderHeight - decoBarHeight : 0),
          duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (_, dy, child) => Transform.translate(offset: Offset(0, -dy), child: child),
          child: shelfPage(headerOpacity),
        );
    // 꾸미는 중 기기 뒤로 = 꾸미기 끝내기(끄던 책은 제자리로). 앱 껍데기는 꾸미는 동안(탭 바가 숨은 동안) 뒤로를 홈에 맡긴다(2026-11-15 QA 민혁 F2)
    return PopScope(
      canPop: !_decorating,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_decorating) return;
        _grab = null;
        _lpDrag = false;
        if (_drag != null) _cancelDrag();
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
                      child: liftedPage(1),
                    )
                  : YearPager(
                      key: _pagerKey,
                      bookcases: _bookcases,
                      blocked: _decorating || _drag != null || _head != null,
                      onPinch: (v) => setState(() => _pinching = v),
                      current: liftedPage,
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
          if (_decorating) ...[
            // 맨 위 줄: 머리줄 자리(같은 높이, 흰 바탕으로 덮어 밀린 책장이 비치지 않게)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: pad.top + decoBarHeight,
              child: ColoredBox(
                color: AppColors.bg,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(TabHeader.paddingH, pad.top, TabHeader.paddingH, 0),
                  child: Align(child: DecorateBar(tab: _decoTab, onTab: _setDecoTab, canUndo: _canUndo, onUndo: _undo, onDone: _exitDecorate)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _decoBottom(),
            ),
          ],
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
  _DragPainter(this.path, this.delta, this.scale, this.ok, this.image, this.dpr, [this.sprite]);
  final ui.Path path;
  final Offset delta;
  final double scale;
  final bool ok;
  final ui.Image? image;
  final double dpr;

  /// 들 때 굳힌 그늘·책 모양(있으면 옮겨 놓기만 한다)
  final ({ui.Image image, Rect rect})? sprite;

  /// 그늘과 책 모양(제자리 좌표): 굳힌 책장 그림에서 윤곽만 떠 온다. 굳힌 그림이 없으면 흰 윤곽만
  static void paintBook(Canvas canvas, ui.Path path, double scale, ui.Image? image, double dpr) {
    canvas.drawPath(path.shift(Offset(0, 4 * scale)), Paint()
      ..color = const Color(0x521F2533)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * scale));
    canvas.save();
    canvas.clipPath(path);
    if (image != null) {
      canvas.scale(1 / dpr);
      canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.low);
    } else {
      canvas.drawPath(path, Paint()..color = const Color(0x66FFFFFF));
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final moved = path.shift(delta);
    final sp = sprite;
    if (sp != null) {
      canvas.drawImageRect(sp.image, Rect.fromLTWH(0, 0, sp.image.width.toDouble(), sp.image.height.toDouble()), sp.rect.shift(delta), Paint()..filterQuality = FilterQuality.none);
    } else {
      canvas.save();
      canvas.translate(delta.dx, delta.dy);
      paintBook(canvas, path, scale, image, dpr);
      canvas.restore();
    }
    if (!ok) canvas.drawPath(moved, Paint()..color = const Color(0x40D9534F));
    canvas.drawPath(moved, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_DragPainter old) => old.delta != delta || old.ok != ok || old.image != image || old.path != path || !identical(old.sprite?.image, sprite?.image);
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
  _PreviewRow(this.row, this.spots, this.sig, [this.atlas, this.keys, this.bookKeys]);
  final RowCase row;
  final List<Spot> spots;

  /// 책들의 보이는 모습 열쇠(같으면 다시 만들지 않는다)
  final String sig;

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

/// 줄 책들의 그림 재료 열쇠(제목·색·갈피·재질·표지 사진 주소). 굽기 열쇠에 들지 않는 책 모습
String _looksSig(RowCase r) => [
      for (final l in r.looks) '${l.title}|${l.face}|${l.tone}|${l.ink}|${l.titleTop}|${l.coverUri}|${l.ribbons}|${l.ribbon}|${l.material}|${l.artwork}|${l.reference}|${l.plainCover}',
    ].join(';');

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

/// 머리줄 높이(지금 앱은 배치에서 잰다) = 위 여백(TDS Top upperGap 24) + 제목 줄(title) − 2 + 해 줄(Top 부제 secondary) + 아래 4(홈만: 바로 아래가 책장 벽).
/// 줄 높이는 글자 역할에서 읽고, 지금 앱처럼 화소로 올린다(rnPx). 숫자를 따로 두면 글자 위계를 바꿀 때 어긋난다
/// (2026-11-10 사용자 '책장 좀 더 높이', '2026이랑 나의 책장 사이 간격 줄이고': 아래 여백 12 → 4, 해 위 4 → −2)
const _headerBottom = 4.0;
double get homeHeaderHeight => TabHeader.paddingTop + rnPx(TypeSpecs.title.line) - 2 + rnPx(TypeSpecs.secondary.line) + _headerBottom;

/// 꾸미기 맨 위 줄 높이: 낮은 전환 칸(누르는 자리 48) + 위아래 4. 머리줄보다 낮아 꾸미는 동안 책장이 그만큼 위로 온다(liftedPage)
const decoBarHeight = Space.hit + Space.xs * 2;

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
                    // 굽기 시간 툴팁은 측정용이라 시험 빌드(QA_FRAMES)에서만: 출시 빌드 사용자에게 개발 숫자를 보이지 않는다
                    PullUp(
                      dy: 2,
                      child: qaFrames
                          // 해는 제목 아래 부제(TDS Top.SubtitleParagraph size 15: t6 regular grey700)
                          ? Tooltip(message: status, child: Text('$year', style: AppType.secondary, maxLines: 1))
                          : Text('$year', style: AppType.secondary, maxLines: 1),
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
            const Padding(padding: EdgeInsets.only(top: 2.5), child: SizedBox(height: Space.touch)),
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
  static const slopY = (Space.hit - Space.touch) / 2;

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

/// 잠긴 칸 자물쇠(지금 앱 TabIcons LockIcon 32×40, 색 #3F4347·구멍 #F4F3F2)
class _LockIcon extends StatelessWidget {
  const _LockIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(32, 40), painter: _LockPainter());
}

class _LockPainter extends CustomPainter {
  static const _ink = Color(0xFF3F4347), _hole = Color(0xFFF4F3F2);

  @override
  void paint(Canvas canvas, Size size) {
    final shackle = Path()
      ..moveTo(8.5, 19)
      ..lineTo(8.5, 11.5)
      ..arcToPoint(const Offset(23.5, 11.5), radius: const Radius.circular(7.5))
      ..lineTo(23.5, 19);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(2.5, 16.5, 27, 22), const Radius.circular(5.5)), Paint()..color = _ink);
    canvas.drawCircle(const Offset(16, 25.5), 3.1, Paint()..color = _hole);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14.5, 25.5, 3, 6.5), const Radius.circular(1.5)), Paint()..color = _hole);
  }

  @override
  bool shouldRepaint(_LockPainter old) => false;
}

/// 바뀐 기둥 둘레 여유(설계 단위): 갈피 탭·윤곽 빛·둥근 모서리 몫
const _dirtyPad = 8.0;

/// 바탕 그림 위 몇 네모(rects)만 줄들을 그린다(끄는 동안 띠의 바뀐 곳)
class _RectsPainter extends CustomPainter {
  _RectsPainter(this.rows, this.rects);
  final ShelfPainter rows;
  final List<Rect> rects;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    canvas.save();
    if (rects.length == 1) {
      canvas.clipRect(rects.single);
    } else {
      final clip = Path();
      for (final r in rects) {
        clip.addRect(r);
      }
      canvas.clipPath(clip);
    }
    rows.paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RectsPainter old) => !identical(old.rows.rows, rows.rows) || !listEquals(old.rects, rects) || rows.shouldRepaint(old.rows);
}

/// 시험 빌드 전용: 끌기 한 번의 기록([fldrag], 놓고 1.5초 뒤 프레임 시간까지)
class _DragStats {
  _DragStats() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }
  final _t0 = DateTime.now();
  int moves = 0, steps = 0, targets = 0, previews = 0, bakes = 0, tweenFrames = 0, cacheHits = 0;
  int _bands = 0;
  double _bandCover = 0;
  int _frames = 0, _slow = 0, _janky = 0, _worstBuild = 0, _worstRaster = 0, _rasterSum = 0;
  bool _open = true;

  /// 다시 그린 넓이(줄 하나 전체 = 1)
  static double _rowsCovered(List<Rect> rects, double width, double rowH) => rects.fold(0.0, (t, r) => t + r.width * r.height) / (width * rowH);

  void band(List<Rect> rects, double width, double rowH) {
    _bands++;
    _bandCover += _rowsCovered(rects, width, rowH);
  }

  void _onTimings(List<ui.FrameTiming> ts) {
    if (!_open) return;
    for (final t in ts) {
      _frames++;
      final b = t.buildDuration.inMilliseconds, r = t.rasterDuration.inMilliseconds;
      _rasterSum += r;
      if (b > _worstBuild) _worstBuild = b;
      if (r > _worstRaster) _worstRaster = r;
      if (t.totalSpan.inMilliseconds > 20) _slow++;
      if (math.max(b, r) > 32) _janky++;
    }
  }

  /// 놓았다: 프레임 시간은 묶어서 늦게 오니 1.5초 더 모은 뒤 찍는다
  void finish() {
    final ms = DateTime.now().difference(_t0).inMilliseconds;
    String pct(double v, int n) => n == 0 ? '-' : '${(v / n).toStringAsFixed(2)}줄';
    Timer(const Duration(milliseconds: 1500), () {
      _open = false;
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      // ignore: avoid_print
      print('[fldrag] ${ms}ms moves $moves steps $steps targets $targets previews $previews '
          'tween $tweenFrames bands $_bands(${pct(_bandCover, _bands)}) cache $cacheHits bakes $bakes | '
          'frames $_frames slow>20 $_slow janky>32 $_janky worstBuild ${_worstBuild}ms worstRaster ${_worstRaster}ms avgRaster ${_frames == 0 ? 0 : (_rasterSum / _frames).toStringAsFixed(1)}ms');
    });
  }

  void cancel() {
    _open = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }
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

  /// 지금 값을 그대로 적어 둔다(목록은 복사: 줄 빛 그림 목록은 굽기가 끝나면 그 자리에서 바뀐다). 바탕 그림이 무엇으로 그려졌는지 견줄 때
  ShelfPainter snapshot() => ShelfPainter(
        rows: List.of(rows),
        atlases: List.of(atlases),
        rowSpots: rowSpots,
        spaces: spaces,
        keys: List.of(keys),
        photos: photos,
        bookKeys: List.of(bookKeys),
        contentTop: contentTop,
        bottomInset: bottomInset,
        viewport: viewport,
        frostedFrom: frostedFrom,
        look: look,
        only: only,
      );

  /// base 값으로 그린 바탕 그림과 이 값으로 그린 그림이 다른 곳(그리는 면 px 네모들, rows 줄만 본다).
  /// 네모는 그 줄이 그리는 높이(머리 위 headDu ~ 판 밑 그늘) × 가로 구간: 자세가 다르거나 있고 없는 책은 그 윤곽(옛 자리·새 자리) 둘레 _dirtyPad,
  /// 줄 빛 그림·창빛 그림자·표지 사진·스킨이 다르면 폭 전체. base가 없으면 줄마다 폭 전체.
  /// 이 네모 안은 그 줄과 바로 아래 줄을 차례대로 그리면 책장 전체를 그린 것과 같다(위 줄은 판 윤곽만 들어오는데 그 줄이 비워 둔다)
  List<Rect> dirtyRects(Set<int> which, ShelfPainter? base, Size size) {
    final m = makeMetrics(size.width);
    final cam = Cam(viewPitchMin);
    final geo = computeRows(rows.length, m.scale, viewportHeight: (viewport ?? size.height) - contentTop, bottomInset: bottomInset, real: math.min(rows.length, frostedFrom));
    final whole = base == null ||
        base.look != look ||
        !identical(base.photos, photos) ||
        base.rows.length != rows.length ||
        base.contentTop != contentTop ||
        base.bottomInset != bottomInset ||
        base.viewport != viewport ||
        base.frostedFrom != frostedFrom;
    T? at<T>(List<T> l, int i) => i < l.length ? l[i] : null;
    final pad = _dirtyPad * m.scale;
    final out = <Rect>[];
    for (final i in which.toList()..sort()) {
      if (i < 0 || i >= geo.length || i >= rows.length) continue;
      final r = geo[i];
      final y0 = contentTop + math.max(0.0, r.top - headDu * m.scale), y1 = math.min(size.height, contentTop + r.top + r.height + shelfCastExtent * m.scale);
      if (y1 <= y0) continue;
      if (whole || !identical(at(base.atlases, i), at(atlases, i)) || at(base.keys, i) != at(keys, i) || !identical(at(base.bookKeys, i), at(bookKeys, i))) {
        out.add(Rect.fromLTRB(0, y0, size.width, y1));
        continue;
      }
      final px = Affine(m.scale, m.originX + sideMargin * m.scale, contentTop + r.baseline);
      final spans = <(double, double)>[];
      void add(Book3 b) {
        final o = bookOutline(cam, px, b).getBounds();
        spans.add((o.left - pad, o.right + pad));
      }

      final was = {for (final b in base.rows[i].books) b.id: b};
      final now = {for (final b in rows[i].books) b.id: b};
      for (final e in was.entries) {
        final n = now[e.key];
        if (n != null && !RowTween.moved(e.value, n)) continue;
        add(e.value);
        if (n != null) add(n);
      }
      for (final e in now.entries) {
        if (!was.containsKey(e.key)) add(e.value);
      }
      // 겹치는 구간은 합친다
      spans.sort((a, b) => a.$1.compareTo(b.$1));
      final merged = <(double, double)>[];
      for (final (lo, hi) in spans) {
        final l = math.max(0.0, lo), h = math.min(size.width, hi);
        if (h <= l) continue;
        if (merged.isNotEmpty && l <= merged.last.$2) {
          merged[merged.length - 1] = (merged.last.$1, math.max(merged.last.$2, h));
        } else {
          merged.add((l, h));
        }
      }
      for (final (l, h) in merged) {
        out.add(Rect.fromLTRB(l, y0, h, y1));
      }
    }
    return out;
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

  /// 갈피 탭 셰이더(책 꾸미기 › 갈피 미리보기 책도 쓴다)
  static ShaderSlots? get tabSlots => _tab;
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
      // 줄 목록이 바뀌면(책이 미끄러지는 동안 프레임마다) 다시 그린다. 2026-11-19 전에는 보지 않아 미끄러지는 0.23초 동안 첫 장면에 멈춰 있다가 끝에 튀었다
      !identical(old.rows, rows) ||
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
