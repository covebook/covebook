// 내 책(지금 앱 app/books.tsx 전체 책, 2026-11-05 사용자 시안 → 2026-11-16 메뉴 개편으로 하단 둘째 탭): 등록한 모든 책을 보고 관리하는 곳
// (책장에 놓인 책도, 책장에 없는 책도 여기 있다). 책장은 그중 골라 놓고 꾸미는 곳.
// 탭: 맨 위 밑줄 글자 탭(읽기 상태), 둘째 줄 '책 N권'과 검색·보기 전환·필터·추가(2026-11-24 사용자 6단계: 왼쪽 위 '내 책' 제목 줄 · '선택' 글자 단추를 뺐다).
// 검색을 켜면 맨 위 한 줄에 검색칸. 정렬과 '책장에 없는 책'·완독한 해·숨긴 책은 필터 시트에,
// 조건이 걸렸을 때만 그 조건과 해제 줄을 보인다. 다른 화면에서 여는 내 책(openAllBooks)도 이 탭으로 온다.
// 책을 꾹 누르면 어떤 책이든 고르는 상태가 되고(둘째 줄이 'N권 선택' · '취소') 아래에 '삭제'와 '진열'(진열은 고른 책 중 책장에 없는 책만 센다: 책장에 있는 책 제한은
// 책장에 꽂기에만). 고른 책이 모두 연도 책장에 있으면 '삭제' 대신 '숨기기'(숨긴 책은 필터 › 숨긴 책 보기에서 되돌린다)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_nav.dart' show AppNav;
import '../../app/app_shell.dart' show tabBarHidden;
import '../../domain/geometry.dart' show mm;
import '../../domain/layout.dart' show placementOf;
import '../../domain/library.dart';
import '../../domain/types.dart' show Book;
import '../../services/cover_colors.dart' show shelfRefresh;
import '../../store/library_model.dart';
import '../../store/library_store.dart' show archivedBookIds, archivedYears;
import '../../store/mini_timer_store.dart' show miniTimerSpace;
import '../../store/placement_store.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/book_visual.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/bookmark_detail_screen.dart' show openBookmark;
import 'add_book_screen.dart' show openAddBook;
import 'all_books.dart';
import 'book_screen.dart' show openBook;
import 'book_widgets.dart' show confirmRemoveBooks, removeBooks, removedText, unhideBook, unhiddenText;
import 'labels.dart' show bookStatuses, dateShort, statusLabel;
import 'place_books.dart';

const _cellMin = 80.0; // 격자 칸 최소 폭: 휴대폰은 3칸, 넓은 화면은 칸을 늘린다(96 → 80, 2026-11-24 사용자 7단계)
const _gap = 14.0; // 격자 칸 사이(가로)

/// 보기 방식은 앱을 켜 둔 동안 기억한다
var _lastGrid = true;

/// 내 책 열기(offShelf: 책장에 없는 책만): 하단 '내 책' 탭으로 간다(2026-11-16 메뉴 개편: 전체 책은 독립 탭이 됐다). 밀어 넣은 화면은 모두 닫는다
Future<void> openAllBooks(BuildContext context, {bool offShelf = false}) async {
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  AppNav.instance.goBooks(offShelf: offShelf);
}

/// 하단 '내 책' 탭(뒤로 없음, 제목·검색·추가 머리줄, 탭 바 높이만큼 아래를 비운다). 밀어 넣는 화면으로 여는 곳은 없다(2026-11-19: 쓰지 않는 갈래를 지웠다)
class AllBooksScreen extends StatefulWidget {
  const AllBooksScreen({super.key});

  @override
  State<AllBooksScreen> createState() => _AllBooksScreenState();
}

class _AllBooksScreenState extends State<AllBooksScreen> {
  String _q = '';
  ReadStatus? _status;
  bool _offShelfOnly = false;
  AllBooksSort _sort = AllBooksSort.recent;
  int? _year;
  bool _grid = _lastGrid;
  bool _selecting = false;

  /// 탭 머리줄의 검색 칸(닫으면 검색어도 지운다. 탭을 오가도 그대로 남는다)
  bool _searching = false;
  final List<String> _picked = [];
  Set<String> _archived = const {};

  /// 삭제 · 진열하는 동안 아래 단추 줄은 누른 때 모습 그대로 두고 누른 단추만 돌린다
  /// (2026-11-20 에뮬: 한 권씩 지워지는 사이 '2권 삭제' → '1권 삭제' → 흐린 '삭제', 진열은 '고른 책은 모두 책장에 있어요'가 잠깐 보였다)
  ({_FooterNow now, String kind})? _working;

  /// 다른 화면이 내 책 탭으로 보내며 '책장에 없는 책만'을 걸었으면 받는다(AppNav.goBooks)
  void _nav() {
    final nav = AppNav.instance;
    if (!nav.booksOffShelf) return;
    nav.booksOffShelf = false;
    if (mounted) setState(() => _offShelfOnly = true);
  }

  @override
  void initState() {
    super.initState();
    LibraryModel.instance.addListener(_changed);
    shelfRefresh.addListener(_changed);
    AppNav.instance.addListener(_nav);
    _nav();
    Future.wait([LibraryModel.instance.load(), PlacementStore.instance.ensure(), archivedBookIds().then((a) => _archived = a)]).then((_) => _changed());
  }

  @override
  void dispose() {
    AppNav.instance.removeListener(_nav);
    if (_selecting) tabBarHidden.value = false;
    LibraryModel.instance.removeListener(_changed);
    shelfRefresh.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toggle(String id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));

  /// 고르는 동안 탭 바를 숨긴다(아래 삭제·진열 버튼이 탭 바에 가리지 않게. 기기 뒤로는 이 화면이 받아 고르기만 끝낸다: 앱 틀은 탭 바가 숨으면 뒤로를 넘긴다)
  void _setSelecting(bool on) {
    _selecting = on;
    tabBarHidden.value = on;
  }

  void _stopSelecting() => setState(() {
        _setSelecting(false);
        _picked.clear();
      });

  /// 고르기 시작('선택' 또는 책을 꾹 누름). 처음 고른 책이 있으면 그 책부터
  void _startManage([String? id]) => setState(() {
        _setSelecting(true);
        _picked
          ..clear()
          ..addAll([?id]);
      });

  /// 진열 결과는 토스트(2026-11-19 공통 규칙: 머리 아래 5초 안내 줄이었다. 여러 권이라 되돌리기는 없다).
  /// 못 놓은 책이 있으면 까닭까지(2026-11-15 QA: 꽉 찬 책장에서 진열을 누르면 아무 말 없이 끝났다). 한 권도 못 놓고 책장이 꽉 찼으면 할 일을 확인창으로
  Future<void> _placeNow(_FooterNow now) async {
    final ids = now.chosen;
    final r = await _hold('place', now, () => placeWithChoice(context, ids));
    if (!mounted) return;
    _stopSelecting();
    final why = r.full ? '책장이 꽉 차서' : '자리가 없어';
    if (r.placed == 0 && r.full) {
      appAlert(context, '책장이 꽉 차서 진열하지 못했어요', keptNote(full: true));
      return;
    }
    _toastAfterFrame(r.placed > 0
        ? (r.kept > 0 ? '${r.placed}권을 책장에 진열했어요. ${r.kept}권은 $why 보관해 두었어요.' : '${r.placed}권을 책장에 진열했어요.')
        : '진열할 자리가 없어 보관해 두었어요.');
  }

  /// 결과 토스트는 고르기를 끝낸 화면이 한 번 그려진 다음에 띄운다(2026-11-20 QA: 고르기 삭제 · 진열 뒤 토스트가 보이지 않았다).
  /// 지우거나 놓은 책 때문에 책장 탭(뒤에 숨어 있어도)이 같은 프레임에 책장을 다시 만들고 굽는다. 그 프레임에서 토스트를 만들면
  /// 토스트의 3초가 그 무거운 프레임 동안 흘러 화면에 그려지기 전에 걷혔다(되돌리기가 있는 5초 토스트는 남아 보였다)
  Future<void> _toastAfterFrame(String text) async {
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) showToast(context, text);
  }

  /// 삭제 · 숨기기(확인은 책 정보와 같은 시트). 결과는 토스트, 실패하면 확인창
  Future<void> _remove(_FooterNow now) async {
    final r = await confirmRemoveBooks(context, now.picked);
    if (r == null || !mounted) return;
    try {
      await _hold('remove', now, () => removeBooks(r));
    } catch (e) {
      if (mounted) appAlert(context, '삭제하지 못했어요', errorText(e));
      return;
    }
    if (!mounted) return;
    _stopSelecting();
    _toastAfterFrame(removedText(r));
  }

  /// [act]가 끝날 때까지 아래 단추 줄을 누른 때 모습([now])으로 붙든다([_working])
  Future<T> _hold<T>(String kind, _FooterNow now, Future<T> Function() act) async {
    setState(() => _working = (now: now, kind: kind));
    try {
      return await act();
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  /// 줄 이름 · 고르는 줄 셋째 줄: 상태 | 소장본 | 책장
  String _subOf(Library lib, AllBooksRow r, Map<String, String> copyOf) => [?statusLabel[lib.books[r.book.id]?.status], ?copyOf[r.book.id], if (r.onShelf) '책장'].join(metaSep);

  // 2026-11-19 build(약 255줄)를 머리 · 빈 화면 · 격자 · 목록 · 머리줄 오른쪽 · 아래 단추로 나눴다(화면은 그대로)
  @override
  Widget build(BuildContext context) {
    final lib = LibraryModel.instance.lib;
    final place = PlacementStore.instance;
    final layout = place.layout;
    // 탭 첫 화면이라 불러오는 동안에도 뒤로 없이 '내 책' 머리(뒤로 꺾쇠와 빈 위 줄이 잠깐 보였다)
    if (layout == null) return const Screen(back: false, title: '내 책', hideTitle: true, children: [Loading()]);
    final rows = listAllBooks(lib, place.books, layout, q: _q, status: _status, offShelfOnly: _offShelfOnly, sort: _sort, year: _year);
    final shown = shownBooks(lib).map((b) => b.id).toList();
    final total = shown.length;
    final years = {for (final id in shown) ?finishedYear(lib, id)}.toList()..sort((a, b) => b - a);
    final offCount = shown.where(layout.drawer.contains).length;
    final hiddenCount = LibraryModel.instance.hiddenBooks.length;
    final pickedBooks = [for (final id in _picked) if (lib.books[id] != null) id];
    // 진열할 책: 고른 책 중 책장에 없는 책(그사이 놓인 책도 뺀다). 책장에 있는 책 제한은 진열에만(삭제·숨기기는 고른 책 모두)
    final chosen = [for (final id in pickedBooks) if (placementOf(layout, id) == null) id];
    final kept = pickedBooks.where(_archived.contains).length;
    final hideOnly = kept > 0 && kept == pickedBooks.length;
    // 필터 시트에서 건 조건: 걸렸을 때만 숫자 아래에 이름과 해제(2026-11-15 QA: '전체' 탭인데 '책 3권'이라 전체가 3권으로 읽혔다)
    final conditions = filterConditions(offShelfOnly: _offShelfOnly, year: _year, sort: _sort);
    // 같은 판을 두 권 넣었으면(별도 소장본) 몇 번째 소장본인지(넣은 차례)
    final copyOf = copyLabels(lib);
    final header = _header(rows, conditions, () => _openFilter(years, offCount, hiddenCount));
    // 아래 탭 바(와 독서 중이면 작은 타이머) 높이만큼 비운다. 고르는 중에는 탭 바가 숨고 아래 버튼 줄이 있다
    final bottomPad = !_selecting ? TabBarStyle.contentPad + (ReadingStore.instance.active != null ? miniTimerSpace : 0) : Space.section;

    return PopScope(
      // 고르는 중에 기기 뒤로를 누르면 화면을 떠나지 않고 고르기만 끝낸다
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _stopSelecting();
      },
      child: Screen(
        scroll: false,
        // 왼쪽 위 제목 줄은 없다(하단바에 이름, 2026-11-24 사용자 6단계): 맨 위가 읽기 상태 탭, 둘째 줄이 '책 N권'과 검색 · 보기 전환 · 필터 · ＋
        // (고르는 중에는 둘째 줄이 'N권 선택'과 빨간 '취소'). 제목은 화면 읽기 머리로만
        back: false,
        hideTitle: true,
        title: _selecting ? _selectedTitle((_working?.now.picked ?? pickedBooks).length) : '내 책',
        // 검색 중: 맨 위 한 줄에 검색칸(끄면 사라진다). 닫기는 칸 왼쪽 ← 화살표(오른쪽 '취소' 글자 없음, 2026-11-20 사용자 · 11-21 내 책 검색 시안)
        headerField: !_selecting && _searching
            ? SearchField(
                value: _q,
                onChange: (v) => setState(() => _q = v),
                autofocus: true,
                placeholder: total > 0 ? '책 $total권에서 찾기' : '제목, 저자 검색',
                label: '내 책에서 찾기',
                onBack: () => setState(() {
                  _q = '';
                  _searching = false;
                }),
              )
            : null,
        footer: _selecting ? _selectFooter(_working?.now ?? (picked: pickedBooks, chosen: chosen, hideOnly: hideOnly), busy: _working?.kind) : null,
        children: [
          // 스크롤 칸은 화면 폭(Bleed), 좌우 여백은 목록 안쪽: 표지 모서리에 걸친 고르는 원 · 책장 배지가 오른쪽 줄에서 잘렸다(2026-11-21 촬영 확인)
          Expanded(
            child: Bleed(
              child: LayoutBuilder(builder: (_, box) {
                final pad = EdgeInsets.fromLTRB(Space.page, 0, Space.page, bottomPad);
                if (rows.isEmpty) return ListView(padding: pad, children: [header, _empty(total)]);
                return _grid ? _gridView(box.maxWidth - Space.page * 2, lib, rows, header, pad, copyOf) : _listView(lib, rows, header, pad, copyOf);
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 고르는 중 아래 단추 두 개: 삭제(또는 숨기기) · 진열. 단추 이름은 'N권 삭제'(다른 화면 'N권 추가'와 같은 어순).
  /// 고른 책이 모두 책장에 있어 진열이 꺼지면 까닭을 단추 바로 위에(2026-11-19 공통 규칙: 꺼진 까닭이 보이지 않았다)
  Widget _selectFooter(_FooterNow now, {String? busy}) {
    final (:picked, :chosen, :hideOnly) = now;
    final verb = hideOnly ? '숨기기' : '삭제';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (picked.isNotEmpty && chosen.isEmpty) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: NoticeText(picked.length == 1 ? '고른 책은 이미 책장에 있어요.' : '고른 책은 모두 책장에 있어요.')),
      Row(children: [
        Expanded(
          child: Btn(
            size: 'xlarge',
            kind: hideOnly ? 'secondary' : 'danger',
            label: picked.isNotEmpty ? '${picked.length}권 $verb' : verb,
            disabled: picked.isEmpty || (busy != null && busy != 'remove'),
            busy: busy == 'remove',
            onPress: () => _remove(now),
          ),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Btn(
            size: 'xlarge',
            label: chosen.isNotEmpty ? '${chosen.length}권 진열' : '진열',
            disabled: chosen.isEmpty || (busy != null && busy != 'place'),
            busy: busy == 'place',
            onPress: () => _placeNow(now),
          ),
        ),
      ]),
    ]);
  }

  /// 목록 머리: 맨 위 읽기 상태 탭, 둘째 줄 '책 N권'과 검색 · 보기 바꾸기 · 필터 · ＋(고르는 중에는 'N권 선택'과 '취소'), 건 조건 줄, 안내 한 줄.
  /// '선택' 글자 단추는 없다(책을 길게 눌러 고른다, 2026-11-24 사용자 6단계)
  Widget _header(List<AllBooksRow> rows, List<String> conditions, VoidCallback onFilter) => Padding(
        padding: EdgeInsets.only(bottom: rows.isEmpty ? 0 : (_grid ? Space.m : Space.xs)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 읽기 상태 탭은 고르는 중에도 그대로(바꿔도 고른 책은 유지). 맨 위 줄이라 위 여백 없이(다섯 탭 첫 줄 높이가 같게)
          Tabs<ReadStatus?>(
            items: [(id: null, label: '전체'), for (final s in bookStatuses) (id: s, label: statusLabel[s]!)],
            value: _status,
            onChange: (v) => setState(() => _status = v),
          ),
          // 고르는 중: 둘째 줄 'N권 선택' · 오른쪽 빨간 '취소'(2026-11-20 사용자: 왼쪽 말고 오른쪽에, 빨간색으로), 아래 공용 안내 글.
          // 검색 중에 고르기를 시작하면 검색칸이 사라져도 그 검색어로 걸러진 목록이라 함께 알린다
          if (_selecting) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Space.hit),
                child: Row(children: [
                  // 삭제 · 진열하는 동안은 누른 때 수 그대로(한 권씩 지워지며 '2권 선택' → '1권 선택' → '책 선택'으로 바뀌어 보였다)
                  Expanded(child: Text(_selectedTitle((_working?.now.picked ?? [for (final id in _picked) if (LibraryModel.instance.lib.books[id] != null) id]).length), style: AppType.rowStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Transform.translate(offset: const Offset(8, 0), child: TextLink(label: '취소', danger: true, onPress: _stopSelecting)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.xs, bottom: Space.s),
              child: NoticeText(_q.trim().isNotEmpty ? '‘${_q.trim()}’에 맞는 책에서 삭제하거나 진열할 책을 골라 주세요.' : '삭제하거나 진열할 책을 골라 주세요.', center: true),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              // 왼쪽 '책 N권'(지금 검색·필터 결과), 오른쪽 선택 · 보기 전환 · 필터(지금 앱: 마지막 아이콘 marginRight −10, Flutter TextLink는 안쪽 여백 8이 이미 있다)
              child: Row(children: [
                Expanded(child: Text('책 ${rows.length}권', style: AppType.sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Transform.translate(
                  offset: const Offset(10, 0),
                  // 나란한 아이콘은 IconRow(가운데 사이 40, 2026-11-26 사용자 '아이콘 같은 라인에 있으면 사이 간격이 큰 거 같아': 48이었다)
                  child: IconRow(children: [
                    // 검색(검색 중에는 맨 위 검색칸이 있어 없다) · 보기 전환 · 필터 · ＋(머리줄 아이콘과 같은 공용 HeadIcon 회색)
                    if (!_searching) IconBtn(label: '내 책 검색', onPress: () => setState(() => _searching = true), child: const HeadIcon('Search')),
                    // 보기 바꾸기 단추 하나: 지금 격자면 목록 아이콘, 목록이면 격자 아이콘(누르면 그 보기로).
                    // 지금 보기 아이콘까지 두 개 두면 '이미 격자인데 격자 표시가 왜 있냐'(2026-11-19 사용자). 색은 옅은 회색(2026-11-18)
                    IconBtn(
                      label: _grid ? '목록으로 보기' : '표지 격자로 보기',
                      onPress: () => setState(() => _lastGrid = _grid = !_grid),
                      child: HeadIcon(_grid ? 'ListIcon' : 'LayoutGrid'),
                    ),
                    FilterIcon(active: conditions.isNotEmpty, onPress: onFilter),
                    IconBtn(label: '책 추가', onPress: () => openAddBook(context), child: const HeadIcon('Plus')),
                  ]),
                ),
              ]),
            ),
            if (conditions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(children: [
                  Expanded(child: MetaText(conditions.join(metaSep), style: AppType.sub.copyWith(color: AppColors.ink), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Transform.translate(
                    offset: const Offset(8, 0),
                    child: TextLink(label: '조건 지우기', soft: true, onPress: () => setState(() {
                      _offShelfOnly = false;
                      _year = null;
                      _sort = AllBooksSort.recent;
                    })),
                  ),
                ]),
              ),
          ],
        ]),
      );

  /// 책이 없거나 조건에 맞는 책이 없을 때(docs/design/DESIGN.md 11장 표: 검색 0건은 다른 낱말 + 직접 만들 길 '책 추가', 거르기 0건은 '조건 지우기')
  Widget _empty(int total) {
    final q = _q.trim();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xxl),
      child: total == 0
          ? Empty(title: '아직 등록한 책이 없어요', action: '책 추가', onAction: () => openAddBook(context))
          : q.isNotEmpty
              ? Empty(title: '‘$q’에 맞는 책이 없어요', action: '책 추가', onAction: () => openAddBook(context, q: q))
              : Empty(
                  title: '조건에 맞는 책이 없어요',
                  action: '조건 지우기',
                  actionKind: 'secondary',
                  // 읽기 상태 · 책장에 없는 책 · 완독한 해를 모두 푼다(정렬은 거르기가 아니라 그대로)
                  onAction: () => setState(() {
                    _status = null;
                    _offShelfOnly = false;
                    _year = null;
                  }),
                ),
    );
  }

  /// 표지 격자(칸 폭은 화면에 맞춰 3칸 이상)
  Widget _gridView(double width, Library lib, List<AllBooksRow> rows, Widget header, EdgeInsets pad, Map<String, String> copyOf) {
    final cols = math.max(3, ((width + _gap) / (_cellMin + _gap)).floor());
    final cellW = (width - _gap * (cols - 1)) / cols;
    final lines = (rows.length + cols - 1) ~/ cols;
    return ListView.builder(
      padding: pad,
      itemCount: lines + 1,
      itemBuilder: (_, i) {
        if (i == 0) return header;
        final line = rows.skip((i - 1) * cols).take(cols).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.xl),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (k, r) in line.indexed) ...[
              if (k > 0) const SizedBox(width: _gap),
              _GridCell(
                lib: lib,
                book: r.book,
                width: cellW,
                sub: r.book.author ?? '',
                tail: copyOf[r.book.id] ?? '',
                shelf: r.onShelf,
                label: [r.book.title, ?r.book.author, _subOf(lib, r, copyOf)].where((t) => t.isNotEmpty).join(', '),
                state: !_selecting
                    ? _CellState.normal
                    : _picked.contains(r.book.id)
                        ? _CellState.picked
                        : _CellState.free,
                onPress: !_selecting ? () => openBook(context, r.book.id) : () => _toggle(r.book.id),
                onLongPress: () {
                  if (!_selecting) _startManage(r.book.id);
                },
              ),
            ],
          ]),
        );
      },
    );
  }

  /// 목록(공용 책 줄 BookRow 크게). 줄 사이 선 없이 여백만(2026-11-17 내 책 목록 시안)
  Widget _listView(Library lib, List<AllBooksRow> rows, Widget header, EdgeInsets pad, Map<String, String> copyOf) {
    final memos = memosByBook(lib);
    return ListView.builder(
      padding: pad,
      itemCount: rows.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return header;
        final r = rows[i - 1];
        final id = r.book.id;
        if (_selecting) {
          // 고르는 중: 제목 · 저자 · 상태 | 소장본 | 책장, 오른쪽 고르는 원(목록 줄과 같은 크기라 고르기를 시작해도 줄이 그대로)
          final on = _picked.contains(id);
          final sub = _subOf(lib, r, copyOf);
          return BookRow(
            size: BookRowSize.large,
            cover: _thumb(lib, id),
            title: r.book.title,
            meta: r.book.author,
            third: sub,
            trailing: RadioMark(on: on),
            onPress: () => _toggle(id),
            checked: on,
            label: [r.book.title, ?r.book.author, sub].where((t) => t.isNotEmpty).join(', '),
          );
        }
        final b = lib.books[id];
        // 시안: 제목 · 저자·상태 · 한 줄 감상 두 줄, 메모가 있으면 메모 단추
        return _BookListRow(
          lib: lib,
          book: r.book,
          // 2026-11-17 사용자 시안: 저자 · 상태(읽기 전은 쓰지 않는다)만. 소장본 구분은 남긴다
          sub: [?r.book.author, if (b != null && b.status != ReadStatus.want) statusLabel[b.status]!, ?copyOf[id]].join(metaSep),
          note: b?.note,
          memos: memos[id] ?? const [],
          onPress: () => openBook(context, id),
          onLongPress: () => _startManage(id),
        );
      },
    );
  }

  String _selectedTitle(int n) => n > 0 ? '$n권 선택' : '책 선택';

  // 2026-11-17 사용자 시안(갈피 필터와 같은 모양): 정렬 두 칸 · 책장에 없는 책만(권수) · 완독한 해 · 숨긴 책 · 적용. 고른 것은 '적용'을 눌러야 걸린다
  void _openFilter(List<int> years, int offCount, int hiddenCount) {
    var sort = _sort;
    var off = _offShelfOnly;
    var year = _year;
    showSheet<void>(
      context,
      title: '필터',
      scroll: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const SheetLabel('정렬'),
          Row(children: [
            for (final (i, k) in AllBooksSort.values.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s),
              Expanded(child: ChoiceBox(label: sortLabel[k]!, on: sort == k, onPress: () => set(() => sort = k))),
            ],
          ]),
          const SizedBox(height: Space.l),
          // 공용 FilterToggleRow(줄 어디를 눌러도 켜고 끔, 화면 읽기 한 번)
          FilterToggleRow(label: '책장에 없는 책만', count: '$offCount권', value: off, onChange: (v) => set(() => off = v)),
          if (years.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            const SheetLabel('완독한 해'),
            Wrap(spacing: Space.s, runSpacing: Space.m, children: [
              for (final y in years)
                SizedBox(width: 96, child: ChoiceBox(label: '$y년', on: year == y, onPress: () => set(() => year = year == y ? null : y))),
            ]),
          ],
          if (hiddenCount > 0) ...[
            const SizedBox(height: Space.m),
            ListItem(
              label: '숨긴 책 보기',
              sub: ['$hiddenCount권', '연도 책장에 남아 있는 책'].join(metaSep),
              chevron: true,
              // 시트에서 고르던 조건은 버리지 않고 걸어 둔 뒤 넘어간다(말없이 버려졌다)
              onPress: () {
                Navigator.pop(ctx);
                setState(() {
                  _sort = sort;
                  _offShelfOnly = off;
                  _year = year;
                });
                _openHidden();
              },
            ),
          ],
          const SizedBox(height: Space.l),
          // 시트 안 단추는 xlarge(2026-11-19 공통 규칙)
          Btn(label: '적용', size: 'xlarge', onPress: () {
            Navigator.pop(ctx);
            setState(() {
              _sort = sort;
              _offShelfOnly = off;
              _year = year;
            });
          }),
          const SizedBox(height: Space.s),
        ]);
      }),
    );
  }

  /// 숨긴 책: 다시 보이게 하면 갈피·기록과 함께 돌아오고 책장에는 '책장에 없는 책'으로 들어간다
  Future<void> _openHidden() async {
    final model = LibraryModel.instance;
    final years = await archivedYears(model.hiddenBooks.map((b) => b.id));
    if (!mounted) return;
    // 다시 보이게 하는 중인 책(두 번 눌리지 않게)
    final busy = <String>{};
    await showSheet<void>(
      context,
      title: '숨긴 책',
      description: '연도 책장에 남아 있어 삭제하는 대신 숨긴 책이에요. 다시 보이게 하면 갈피, 기록과 함께 돌아와요.',
      scroll: true,
      maxHeight: 0.8,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => ListenableBuilder(
        listenable: model,
        builder: (ctx, _) {
          final lib = model.lib;
          final books = model.hiddenBooks;
          if (books.isEmpty) return const EmptyLine('숨긴 책이 없어요');
          // 숨긴 책 한 줄은 공용 책 줄 BookRow 작게(2026-11-19 공통 규칙: 제목 17 · 메타 15 · 표지 44였다)
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final b in books)
              BookRow(
                cover: ExcludeSemantics(child: BookVisual(lib: lib, id: b.id, width: BookRow.coverWidth(BookRowSize.small))),
                title: lib.editions[b.editionId]?.title ?? '제목 없음',
                meta: [?lib.editions[b.editionId]?.authors.firstOrNull, if (years[b.id]?.isNotEmpty ?? false) '${years[b.id]!.join(', ')}년 책장'].join(metaSep),
                trailing: Btn(
                  label: '다시 보이기',
                  kind: 'secondary',
                  size: 'medium',
                  busy: busy.contains(b.id),
                  onPress: () async {
                    final title = lib.editions[b.editionId]?.title ?? '책';
                    final last = books.length <= 1;
                    setSheet(() => busy.add(b.id));
                    try {
                      await unhideBook(b.id);
                    } catch (e) {
                      if (ctx.mounted) setSheet(() => busy.remove(b.id));
                      if (mounted) appAlert(context, '다시 보이게 하지 못했어요', errorText(e));
                      return;
                    }
                    if (ctx.mounted) setSheet(() => busy.remove(b.id));
                    if (!mounted) return;
                    // 토스트는 시트 위에도 보인다(머리 아래 안내 줄은 시트에 가려 보이지 않았다)
                    showToast(context, unhiddenText(title));
                    if (last && ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
          ]);
        },
      )),
    );
  }
}

enum _CellState { normal, free, picked }

/// 격자 한 칸(줄이 아니라 칸이라 BookRow가 아니다): 표지 + 제목·저자 한 줄씩. 고르는 중: 표지 오른쪽 위 모서리에 고르는 원, 고른 책은 테마색 테두리.
/// 책장에 꽂힌 책은 표지 오른쪽 아래 책장 배지(고르는 중이 아닐 때)
class _GridCell extends StatelessWidget {
  const _GridCell({required this.lib, required this.book, required this.width, required this.sub, this.tail = '', this.shelf = false, required this.label, required this.state, this.onPress, this.onLongPress});
  final Library lib;
  final Book book;
  final double width;

  /// 제목 아래 한 줄: 저자(길면 줄인다) · 뒤 표시(소장본 · 책장, 늘 보인다)
  final String sub;
  final String tail;

  /// 책장에 꽂혀 있음: 표지 오른쪽 아래 책장 배지(2026-11-18 사용자 그림)
  final bool shelf;
  final String label;
  final _CellState state;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final e = lib.editions[lib.books[book.id]?.editionId];
    final r = coverRect(e?.widthMm, e?.heightMm, width, uniform: true);
    return Semantics(
      button: true,
      // 여러 권 고르는 중에는 '선택됨/선택 안 됨'(checked), 꾹 누르기(고르기 시작)도 화면 읽기에서 쓸 수 있게
      checked: state == _CellState.normal ? null : state == _CellState.picked,
      label: label,
      onTap: onPress,
      onLongPress: state == _CellState.normal ? onLongPress : null,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Pressable(
          onPress: onPress,
          child: SizedBox(
            width: width,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(clipBehavior: Clip.none, children: [
                // 책장 표시: 표지 밑 선반 판(표지보다 먼저 = 뒤에, 2026-11-25 사용자. 전에는 오른쪽 아래 흰 원 + 책장 그림)
                if (shelf) shelfPlankUnder(r),
                BookVisual(lib: lib, id: book.id, width: width, uniform: true),
                if (state == _CellState.picked)
                  Positioned(
                    left: r.edge - 2,
                    top: r.edge - 2,
                    width: r.w + 4,
                    height: r.h + 4,
                    child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: AppColors.accent, width: 2), borderRadius: BorderRadius.circular(5))),
                  ),
                // 공용 고르는 원(24)은 표지 오른쪽 위 모서리에 걸친다: 원 가운데가 모서리 쪽(2026-11-20 사용자 '체크표시 원을 좀 더 오른쪽으로 해서 모서리로'), 걸침 0.7
                if (state != _CellState.normal)
                  Positioned(
                    left: r.edge + r.w - ControlSize.radio * 0.7,
                    top: r.edge - ControlSize.radio * 0.3,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x1F191F28), offset: Offset(0, 1), blurRadius: 4)]),
                      child: RadioMark(on: state == _CellState.picked),
                    ),
                  ),
              ]),
              // 판이 있든 없든 같은 틈(한 줄 제목이 나란히): 판 몫만큼 더
              Padding(
                padding: EdgeInsets.only(top: Space.s + shelfPlankBelow(r)),
                child: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookGridTitle),
              ),
              // 저자가 길어도 '| 책장' 같은 뒤 표시는 잘리지 않게 저자만 줄인다(2026-11-16 QA 현우 F14: 'Antoine de Saint…'에서 책장 표시가 사라졌다)
              if (sub.isNotEmpty || tail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: LayoutBuilder(
                    builder: (context, box) => Row(children: [
                      if (sub.isNotEmpty) Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookGridAuthor)),
                      if (tail.isNotEmpty)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: box.maxWidth),
                          child: MetaText('${sub.isNotEmpty ? metaSep : ''}$tail', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: AppType.bookGridAuthor),
                        ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 목록 줄 표지(BookRow 크게 80 칸 가운데): 지금 앱 StandaloneBook 앞면 배율 0.42(설계 단위 → dp). 판형과 상관없이 모든 책을 같은 크기로(격자와 같은 규칙).
/// 표지 높이 (mm(188) + 여백 8) × 0.74 ≈ 112는 글 묶음 최대 높이(제목 한 줄 26 + 2 + 저자·상태 23 + 2 + 한줄평 두 줄 42 = 95, BookRow 글자)보다 커서
/// 한줄평이 0 · 1 · 2줄이어도 줄 높이가 같다(112 + 위아래 12 × 2 = 136. 2026-11-17 사용자 댓글 '줄 간격 같게'. 예전 직접 그린 줄은 글 묶음 109 · 줄 140)
Widget _thumb(Library lib, String id) => Center(child: ExcludeSemantics(child: BookVisual(lib: lib, id: id, width: (mm(128) + 8) * 0.74, uniform: true)));

/// 목록 한 줄(시안, 공용 책 줄 BookRow 크게): 표지 + 제목 한 줄 + 저자·상태 + 한줄평 두 줄(셋째 줄). 메모가 있으면 오른쪽 메모 단추를 눌러 작은 상자로 본다.
/// 화면 읽기: 줄은 안쪽 글로 한 번 읽고, 메모 단추는 따로 읽는다(줄 이름으로 덮으면 메모 단추가 빠진다)
class _BookListRow extends StatelessWidget {
  const _BookListRow({required this.lib, required this.book, required this.sub, required this.note, required this.memos, required this.onPress, required this.onLongPress});
  final Library lib;
  final Book book;
  final String sub;
  final String? note;
  final List<BookMemo> memos;
  final VoidCallback onPress, onLongPress;

  // 꾹 누르기는 공용 책 줄의 onLongPress(화면 읽기에도 꾹 누르기가 생긴다, 2026-11-19 공통 규칙: 바깥 GestureDetector였다)
  @override
  Widget build(BuildContext context) => BookRow(
          size: BookRowSize.large,
          // 글 묶음 · 메모 단추는 큰 표지 높이의 세로 가운데(2026-11-20 사용자: 글씨가 작아져 위에 맞추면 아래가 남는다.
          // 썸네일 줄이기 · 한줄평 3줄보다 가운데 정렬: 한줄평 0 · 1 · 2줄 어느 줄이든 위아래가 고르고 표지는 그대로)
          cover: _thumb(lib, book.id),
          title: book.title,
          titleLines: 1,
          meta: sub,
          third: note,
          // 메모 단추는 제목 줄 오른쪽 끝(한줄평이 줄 폭을 다 쓰게, 2026-11-20 사용자)
          titleTrailing: memos.isEmpty
              ? null
              : Builder(
                  builder: (ctx) => IconBtn(
                    label: '메모 ${memos.length}개 보기',
                    onPress: () => _showMemos(ctx, book.id, memos),
                    child: const LucideIcon('StickyNote', size: IconSize.small, color: AppColors.icon),
                  ),
                ),
          onPress: onPress,
          onLongPress: onLongPress,
        );
}

/// 메모 작은 상자: 아이콘 옆에서 뜬다(화면 아래쪽 아이콘이면 위로). 최근 메모 다섯 개, 누르면 그 갈피(독서 기록은 책 정보)로
Future<void> _showMemos(BuildContext iconContext, String bookId, List<BookMemo> memos) {
  final box = iconContext.findRenderObject()! as RenderBox;
  final at = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.sizeOf(iconContext);
  final below = at.center.dy < screen.height * 0.6;
  const boxW = 268.0, edge = 16.0, arrow = 12.0;
  final right = math.max(edge, screen.width - at.right);
  final arrowRight = math.max(10.0, screen.width - at.center.dx - right - arrow / 2);
  final rest = memos.length - 5;
  return showGeneralDialog<void>(
    context: iconContext,
    barrierDismissible: true,
    barrierLabel: '메모 닫기',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final t = Curves.easeOutCubic.transform(anim.value);
      void open(VoidCallback go) {
        Navigator.pop(ctx);
        go();
      }

      return Stack(children: [
        Positioned(
          right: right,
          top: below ? at.bottom + 2 : null,
          bottom: below ? null : screen.height - at.top + 2,
          width: boxW,
          child: Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.9 + 0.1 * t,
              alignment: below ? Alignment.topRight : Alignment.bottomRight,
              child: Material(
                color: Colors.transparent,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    right: arrowRight,
                    top: below ? -arrow / 2 + 1 : null,
                    bottom: below ? null : -arrow / 2 + 1,
                    child: Transform.rotate(angle: math.pi / 4, child: Container(width: arrow, height: arrow, color: AppColors.bg)),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(Shape.card), boxShadow: [cssShadow(const Color(0x2E191F28), 0, 6, 20)]),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        for (final m in memos.take(5))
                          Semantics(
                            button: true,
                            label: '${m.text}, ${dateShort(m.at)} ${m.bookmark ? '갈피' : '독서 기록'}. 눌러서 열기',
                            excludeSemantics: true,
                            child: Pressable(
                              onPress: () => open(() => m.bookmark ? openBookmark(iconContext, m.id) : openBook(iconContext, bookId)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: Space.s),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(m.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.sub.copyWith(color: AppColors.ink)),
                                  Padding(padding: const EdgeInsets.only(top: 3), child: MetaText([dateShort(m.at), m.bookmark ? '갈피' : '독서 기록'].join(metaSep), style: AppType.caption)),
                                ]),
                              ),
                            ),
                          ),
                        if (rest > 0)
                          Semantics(
                            button: true,
                            label: '그 밖에 메모 $rest개, 책 정보에서 모두 보기',
                            excludeSemantics: true,
                            onTap: () => open(() => openBook(iconContext, bookId)),
                            child: Pressable(
                              onPress: () => open(() => openBook(iconContext, bookId)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: Space.s),
                                child: MetaText(['그 밖에 $rest개', '책 정보에서 모두 보기'].join(metaSep), style: AppType.caption),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    },
  );
}

/// 고르기 아래 단추 줄이 그리는 것: 고른 책 · 그중 진열할 책(책장에 없는 책) · 고른 책이 모두 보관한 책이라 숨기기만 되는지
typedef _FooterNow = ({List<String> picked, List<String> chosen, bool hideOnly});
