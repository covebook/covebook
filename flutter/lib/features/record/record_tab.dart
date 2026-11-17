// 기록 탭(2026-11-16 메뉴 구조 개편): 머리줄 '기록'과 검색·추가(고른 글자 탭에 맞게), 왼쪽 글자 탭 '갈피 | 감상'.
// 갈피: 예전 갈피 탭 그대로 옮김. 탭 아래 한 줄은 '갈피 N개'와 아껴둔 갈피 켜고 끄기·필터. 책·유형(문장·사진)은 필터 시트에,
// 걸렸을 때만 '데미안 · 사진 갈피'처럼 조건과 해제를 보인다(기본 조건 칩 줄은 없앴다). 갈피 보드는 필터 시트 '보기'에서.
// 감상: 긴 감상(essay_screens.dart) 목록. '감상 N편'과 필터(책). 표지·책 제목·지은이·미리보기·쓴 날을 상자 없이 줄로
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_nav.dart';
import '../../domain/library.dart';
import '../../store/library_model.dart';
import '../../store/mini_timer_store.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/labels.dart';
import '../bookmark/board_screen.dart' show openBookmarkBoard;
import '../bookmark/bookmark_card.dart';
import '../bookmark/bookmark_detail_screen.dart';
import '../bookmark/bookmark_empty.dart';
import '../bookmark/mark_text.dart' show isPhotoMark;
import '../bookmark/new_bookmark_screen.dart';
import '../stats/stats_widgets.dart' show LinkedCover;
import 'essay_screens.dart';

enum MarkKind { all, text, photo }

const markKindLabel = {MarkKind.all: '모든 유형', MarkKind.text: '문장 갈피', MarkKind.photo: '사진 갈피'};
const _sections = [(id: RecordSection.marks, label: '갈피'), (id: RecordSection.essays, label: '감상')];

/// 갈피 거르기(책·유형·아껴둔·검색어). 모두 함께 건다
bool markShown(Bookmark m, {String? book, MarkKind kind = MarkKind.all, bool savedOnly = false, String q = ''}) {
  final t = q.trim();
  return (book == null || m.myBookId == book) &&
      (!savedOnly || m.savedAt != null) &&
      // 글이 있는 갈피는 사진을 함께 두어도 문장 갈피(카드와 같은 규칙 isPhotoMark, 2026-11-16 QA 은서 F11)
      (kind != MarkKind.photo || isPhotoMark(m.text, m.photoUri)) &&
      (kind != MarkKind.text || !isPhotoMark(m.text, m.photoUri)) &&
      (t.isEmpty || m.text.contains(t) || (m.memo ?? '').contains(t));
}

/// 갈피 조건 줄(걸린 것만): 책 이름 · 유형 · 아껴둔. 아무것도 안 걸렸으면 빈 목록(줄을 보이지 않는다)
List<String> markConditions({String? bookTitle, MarkKind kind = MarkKind.all, bool savedOnly = false}) => [
      ?bookTitle,
      if (kind != MarkKind.all) markKindLabel[kind]!,
      if (savedOnly) '아껴둔 갈피',
    ];

/// 감상 거르기(책·검색어: 제목·본문·책 제목·지은이)
bool essayShown(Library lib, Essay e, {String? book, String q = ''}) {
  if (book != null && e.myBookId != book) return false;
  final t = q.trim();
  if (t.isEmpty) return true;
  final ed = lib.editions[lib.books[e.myBookId]?.editionId ?? ''];
  return (e.title ?? '').contains(t) || e.body.contains(t) || (ed?.title.contains(t) ?? false) || (ed?.authors.any((a) => a.contains(t)) ?? false);
}

class RecordTab extends StatefulWidget {
  const RecordTab({super.key, this.initialBook, this.initialSection});

  /// 갈피를 이 책만 걸러 연다
  final String? initialBook;
  final RecordSection? initialSection;

  @override
  State<RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<RecordTab> {
  final _model = LibraryModel.instance;
  RecordSection _section = RecordSection.marks;

  // 글자 탭마다 따로 둔다(갈피↔감상을 오가도 검색어·조건이 그대로)
  final _q = {RecordSection.marks: '', RecordSection.essays: ''};
  final _searching = <RecordSection>{};
  String? _markBook;
  MarkKind _kind = MarkKind.all;
  bool _savedOnly = false;
  String? _essayBook;

  @override
  void initState() {
    super.initState();
    final nav = AppNav.instance;
    _markBook = nav.bookmarkBook ?? widget.initialBook;
    _section = nav.recordSection ?? widget.initialSection ?? RecordSection.marks;
    nav.bookmarkBook = null;
    nav.recordSection = null;
    nav.addListener(_nav);
    _model.addListener(_changed);
    ReadingStore.instance.addListener(_changed);
    _model.load();
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    ReadingStore.instance.removeListener(_changed);
    AppNav.instance.removeListener(_nav);
    super.dispose();
  }

  // 보드 '목록 보기'(그 책 갈피만)·다른 화면에서 갈피/감상으로 보낼 때
  void _nav() {
    final nav = AppNav.instance;
    final book = nav.bookmarkBook, section = nav.recordSection;
    if ((book == null && section == null) || !mounted) return;
    nav.bookmarkBook = null;
    nav.recordSection = null;
    setState(() {
      if (book != null) {
        _markBook = book;
        _section = RecordSection.marks;
      }
      if (section != null) _section = section;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Library get _lib => _model.lib;

  String _titleOf(String bookId) => _lib.editions[_lib.books[bookId]?.editionId ?? '']?.title ?? '제목 없음';

  /// 책 있는 갈피(최근 순)
  List<Bookmark> get _marks {
    final list = [for (final m in _lib.bookmarks.values) if (_lib.books[m.myBookId] != null) m];
    // 지금 앱 sort는 안정 정렬
    final indexed = [for (final (i, m) in list.indexed) (i, m)]..sort((a, b) {
        final c = b.$2.createdAt.compareTo(a.$2.createdAt);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [for (final x in indexed) x.$2];
  }

  /// 기록이 있는 책(수와 함께, 최근 기록 순: 목록이 이미 최근 순)
  List<({String id, int count, String title})> _booksOf(Iterable<String> bookIds) {
    final n = <String, int>{};
    for (final id in bookIds) {
      n[id] = (n[id] ?? 0) + 1;
    }
    return [for (final e in n.entries) (id: e.key, count: e.value, title: _titleOf(e.key))];
  }

  void _toggleSaved(String id) {
    _model.toggleSaved(id).catchError((_) {
      if (mounted) appAlert(context, '갈피 표시를 저장하지 못했어요', '잠시 후 다시 눌러 주세요.');
    });
  }

  // ── 필터 시트 ──

  // 갈피 필터(2026-11-17 사용자 시안, 높이·여백은 시안보다 조금 넉넉히): 책 한 줄(모든 책 ›) · 유형 세 칸 · 아껴둔 갈피만 · 적용.
  // 고른 것은 '적용'을 눌러야 걸린다. 갈피 보드는 머리줄 격자 아이콘으로 옮겼다
  Future<void> _openMarkFilter() {
    var book = _markBook;
    var kind = _kind;
    var saved = _savedOnly;
    return showSheet<void>(
      context,
      title: '필터',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          // 책: 왼쪽 '책', 오른쪽 고른 책 이름 ›
          Semantics(
            button: true,
            label: '책, ${book == null ? '모든 책' : _titleOf(book!)}',
            excludeSemantics: true,
            onTap: () => _openMarkBooks(board: false, current: book, onPick: (id) => set(() => book = id)),
            child: Pressable(
              onPress: () => _openMarkBooks(board: false, current: book, onPick: (id) => set(() => book = id)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(children: [
                  Text('책', style: AppType.rowStrong),
                  const SizedBox(width: Space.l),
                  Expanded(child: Text(book == null ? '모든 책' : _titleOf(book!), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub)),
                  const SizedBox(width: 4),
                  const LucideIcon('ChevronRight', size: 20, color: AppColors.inkSoft),
                ]),
              ),
            ),
          ),
          Container(height: 1 / MediaQuery.devicePixelRatioOf(ctx), color: AppColors.line),
          const SizedBox(height: Space.l + 4),
          const SheetLabel('유형'),
          Row(children: [
            for (final (i, k) in MarkKind.values.indexed) ...[
              if (i > 0) const SizedBox(width: Space.s),
              Expanded(child: ChoiceBox(label: k == MarkKind.all ? '전체' : markKindLabel[k]!, on: kind == k, onPress: () => set(() => kind = k))),
            ],
          ]),
          const SizedBox(height: Space.l),
          // 아껴둔 갈피만(예전 머리줄 아이콘)
          FilterToggleRow(label: '아껴둔 갈피만', value: saved, onChange: (v) => set(() => saved = v)),
          const SizedBox(height: Space.l),
          Btn(label: '적용', onPress: () {
            Navigator.pop(ctx);
            setState(() {
              _markBook = book;
              _kind = kind;
              _savedOnly = saved;
            });
          }),
          const SizedBox(height: Space.s),
        ]),
      ),
    );
  }

  void _openBoard() {
    final books = _booksOf(_marks.map((m) => m.myBookId));
    final only = _markBook ?? (books.length == 1 ? books.first.id : null);
    if (only != null) {
      openBookmarkBoard(context, only);
    } else {
      _openMarkBooks(board: true);
    }
  }

  Future<void> _openMarkBooks({required bool board, String? current, ValueChanged<String?>? onPick}) {
    final all = _marks;
    return _openBookChoice(
      title: board ? '보드로 볼 책' : '책 선택',
      books: _booksOf(all.map((m) => m.myBookId)),
      unit: (n) => '갈피 $n개',
      allSub: board ? null : '갈피 ${all.length}개',
      current: board ? null : (onPick != null ? current : _markBook),
      searchLabel: '갈피를 볼 책 찾기',
      onPick: (id) {
        if (board) {
          if (id != null) openBookmarkBoard(context, id);
        } else if (onPick != null) {
          onPick(id);
        } else {
          setState(() => _markBook = id);
        }
      },
    );
  }

  Future<void> _openEssayFilter() {
    final all = _model.essaysOf();
    return showSheet<void>(
      context,
      title: '필터',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        FilterGroup(title: '책', first: true, children: [
          FilterOption(
            label: _essayBook == null ? '모든 책' : _titleOf(_essayBook!),
            chevron: true,
            onPress: () {
              Navigator.pop(ctx);
              _openBookChoice(
                title: '책 선택',
                books: _booksOf(all.map((e) => e.myBookId)),
                unit: (n) => '감상 $n편',
                allSub: '감상 ${all.length}편',
                current: _essayBook,
                searchLabel: '감상을 볼 책 찾기',
                onPick: (id) => setState(() => _essayBook = id),
              );
            },
          ),
        ]),
      ]),
    );
  }

  /// 책 선택 시트: 내 책 검색(많을 때) · '모든 책'(allSub가 있을 때) · 표지·이름·수·체크
  Future<void> _openBookChoice({
    required String title,
    required List<({String id, int count, String title})> books,
    required String Function(int) unit,
    required String? allSub,
    required String? current,
    required String searchLabel,
    required ValueChanged<String?> onPick,
  }) {
    var bookQ = '';
    return showSheet<void>(
      context,
      title: title,
      scroll: true,
      maxHeight: 0.8,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final shown = books.where((x) => bookQ.trim().isEmpty || x.title.contains(bookQ.trim()));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (books.length > 5)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.tight),
                child: SearchField(value: bookQ, onChange: (v) => set(() => bookQ = v), placeholder: '내 책 검색', label: searchLabel),
              ),
            if (allSub != null)
              _BookChoice(
                label: '모든 책',
                sub: allSub,
                on: current == null,
                onPress: () {
                  Navigator.pop(ctx);
                  onPick(null);
                },
              ),
            for (final x in shown)
              _BookChoice(
                label: x.title,
                sub: unit(x.count),
                on: current == x.id,
                cover: LinkedCover(lib: _lib, id: x.id, width: 40),
                onPress: () {
                  Navigator.pop(ctx);
                  onPick(x.id);
                },
              ),
          ]);
        },
      ),
    );
  }

  // ── 화면 ──

  @override
  Widget build(BuildContext context) {
    if (!_model.loaded) return const Screen(title: '기록', back: false, scroll: false, children: []);
    final section = _section;
    final marks = section == RecordSection.marks;
    final searching = _searching.contains(section);
    final what = marks ? '갈피' : '감상';
    return Screen(
      title: '기록',
      back: false,
      scroll: false,
      right: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(
          label: searching ? '$what 검색 닫기' : '$what 검색',
          onPress: () => setState(() {
            if (searching) {
              _q[section] = '';
              _searching.remove(section);
            } else {
              _searching.add(section);
            }
          }),
          child: LucideIcon(searching ? 'X' : 'Search'),
        ),
        const SizedBox(width: 4),
        marks
            ? IconBtn(label: '갈피 추가', onPress: () => openNewBookmark(context, book: _markBook, photoOnly: _kind == MarkKind.photo), child: const LucideIcon('Plus'))
            : IconBtn(label: '감상 쓰기', onPress: () => openNewEssay(context, book: _essayBook), child: const LucideIcon('Plus')),
      ]),
      children: [
        if (searching)
          Padding(
            padding: const EdgeInsets.only(top: Space.tight, bottom: Space.item),
            child: SearchField(
              key: ValueKey(section),
              value: _q[section]!,
              onChange: (v) => setState(() => _q[section] = v),
              autofocus: true,
              placeholder: marks ? '문장·메모에서 찾기' : '감상·책 제목에서 찾기',
              label: '$what 검색어',
            ),
          ),
        // 갈피 | 감상: 같은 크기 글자, 고른 것만 진하게 + 짧고 얇은 밑줄(회색 상자 없이 왼쪽 정렬)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Tabs<RecordSection>(items: _sections, value: section, onChange: (v) => setState(() => _section = v), gap: Space.xl),
          ),
        ),
        ...marks ? _marksBody(context) : _essaysBody(context),
      ],
    );
  }

  double get _bottomPad => TabBarStyle.contentPad + (ReadingStore.instance.active != null ? miniTimerSpace : 0);

  /// 개수 줄(왼쪽 'N개', 오른쪽 아이콘들) + 걸렸을 때만 조건 줄
  List<Widget> _countRows(String count, List<Widget> icons, List<String> conditions, VoidCallback clear) => [
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(children: [
            Expanded(child: Text(count, style: AppType.sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
            // 마지막 아이콘 오른쪽 여백을 머리줄 아이콘과 맞춘다(내 책 탭과 같게)
            Transform.translate(offset: const Offset(10, 0), child: Row(mainAxisSize: MainAxisSize.min, children: icons)),
          ]),
        ),
        if (conditions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Row(children: [
              Expanded(child: Text(conditions.join(' · '), style: AppType.sub.copyWith(color: AppColors.ink), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Transform.translate(offset: const Offset(8, 0), child: TextLink(label: '조건 해제', soft: true, onPress: clear)),
            ]),
          ),
      ];

  List<Widget> _marksBody(BuildContext context) {
    final all = _marks;
    if (all.isEmpty) return [Expanded(child: BookmarkEmpty(onAdd: () => openNewBookmark(context)))];
    final q = _q[RecordSection.marks]!.trim();
    final list = [for (final m in all) if (markShown(m, book: _markBook, kind: _kind, savedOnly: _savedOnly, q: q)) m];
    final conditions = markConditions(bookTitle: _markBook == null ? null : _titleOf(_markBook!), kind: _kind, savedOnly: _savedOnly);
    final plain = _savedOnly && q.isEmpty && _markBook == null && _kind == MarkKind.all;
    final emptyTitle = plain ? '아껴둔 갈피가 없어요' : _kind == MarkKind.photo && q.isEmpty ? '사진 갈피가 없어요' : '맞는 갈피가 없어요';
    final emptyBody = plain
        ? '갈피 오른쪽 아래의 표시를 눌러 모아 보세요.'
        : _kind == MarkKind.photo && q.isEmpty
            ? '페이지를 찍어 그대로 붙여 두세요.'
            : q.isNotEmpty
                ? '다른 낱말로 찾아보세요.'
                : '조건을 풀거나 다른 책·유형을 골라 보세요.';
    final cardW = math.min(MediaQuery.sizeOf(context).width - Space.page * 2, contentMax);
    final bottomPad = _bottomPad;
    return [
      ..._countRows(
        '갈피 ${list.length}개',
        [
          // 갈피 보드(책 한 권의 갈피를 넓은 보드에): 격자 아이콘(2026-11-17 시안). 아껴둔 갈피만은 필터 안으로 옮겼다
          IconBtn(label: '갈피 보드로 보기', onPress: _openBoard, child: const LucideIcon('LayoutGrid', size: 22)),
          FilterIcon(active: _markBook != null || _kind != MarkKind.all || _savedOnly, onPress: _openMarkFilter),
        ],
        conditions,
        () => setState(() {
          _markBook = null;
          _kind = MarkKind.all;
          _savedOnly = false;
        }),
      ),
      Expanded(
        child: OverflowBox(
          // 목록은 화면 좌우 여백 밖까지(카드 그림자·뒤 종이가 잘리지 않게)
          maxWidth: cardW + Space.page * 2,
          child: list.isEmpty
              ? ListView(padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, bottomPad), children: [Empty(title: emptyTitle, body: emptyBody)])
              : ListView.builder(
                  // 글자 탭마다 따로 스크롤 자리를 기억한다
                  key: const PageStorageKey('record-marks'),
                  padding: EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, bottomPad),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final b = _lib.books[m.myBookId]!;
                    final e = _lib.editions[b.editionId];
                    if (e == null) return const SizedBox.shrink();
                    return BookmarkCard(
                      key: ValueKey(m.id),
                      compact: true,
                      width: cardW,
                      seed: m.id,
                      onOpen: () => openBookmark(context, m.id),
                      saved: m.savedAt != null,
                      onToggleSaved: () => _toggleSaved(m.id),
                      data: BookmarkCardData(
                        text: m.text,
                        title: e.title,
                        author: e.authors.join(', '),
                        page: m.page,
                        date: ymd(m.createdAt),
                        color: ribbonOf(_lib, b.id),
                        coverUri: e.coverUri,
                        bookId: b.id,
                        bookColor: themeColorOf(_lib, b.id),
                        photoUri: m.photoUri,
                        photoRatio: m.photoRatio,
                      ),
                    );
                  },
                ),
        ),
      ),
    ];
  }

  List<Widget> _essaysBody(BuildContext context) {
    final all = _model.essaysOf();
    final bottomPad = _bottomPad;
    if (all.isEmpty) {
      return [
        Expanded(
          child: ListView(padding: EdgeInsets.only(bottom: bottomPad), children: [
            // 여기는 긴 감상만 모인다: 한 줄 감상·별점이 어디 있는지 알린다(2026-11-16 QA 영숙 F16: 한 줄 감상을 썼는데 비어 있어 사라진 줄 알았다).
            // 안내 글은 한 칸, '감상 쓰기' 단추는 따로(묶음 전체가 단추로 '…감상 쓰기 / 감상 쓰기'까지 한꺼번에 읽혔다, 영숙 F9)
            Semantics(
              container: true,
              child: Empty(
                title: '아직 쓴 감상이 없어요',
                body: keepAll('책을 읽고 든 생각을 길게 남기는 곳이에요.\n별점과 한줄평은 책 정보 › 평가에 있어요.'),
                action: '감상 쓰기',
                onAction: () => openNewEssay(context),
              ),
            ),
          ]),
        ),
      ];
    }
    // 고른 책의 감상을 다 지웠으면 거르기를 푼다(빈 조건만 남지 않게)
    final book = _essayBook != null && _lib.books[_essayBook] != null ? _essayBook : null;
    final q = _q[RecordSection.essays]!.trim();
    final list = [for (final e in all) if (essayShown(_lib, e, book: book, q: q)) e];
    return [
      ..._countRows(
        '감상 ${list.length}편',
        [FilterIcon(active: book != null, onPress: _openEssayFilter)],
        [if (book != null) _titleOf(book)],
        () => setState(() => _essayBook = null),
      ),
      Expanded(
        child: list.isEmpty
            ? ListView(padding: EdgeInsets.only(bottom: bottomPad), children: [
                Empty(title: '맞는 감상이 없어요', body: q.isNotEmpty ? '다른 낱말로 찾아보세요.' : '조건을 풀거나 다른 책을 골라 보세요.'),
              ])
            : ListView.separated(
                key: const PageStorageKey('record-essays'),
                padding: EdgeInsets.only(bottom: bottomPad),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: list.length,
                separatorBuilder: (_, _) => const AppDivider(),
                itemBuilder: (context, i) => EssayRow(key: ValueKey(list[i].id), lib: _lib, essay: list[i]),
              ),
      ),
    ];
  }
}

/// 책 선택 줄: 표지 · 이름(고르면 굵게) · 수 · 고르는 원
class _BookChoice extends StatelessWidget {
  const _BookChoice({required this.label, required this.sub, required this.on, required this.onPress, this.cover});
  final String label, sub;
  final bool on;
  final VoidCallback onPress;
  final Widget? cover;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: '$label, $sub',
        onTap: onPress,
        excludeSemantics: true,
        child: Pressable(
          onPress: onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                if (cover != null) ...[SizedBox(width: 40, child: Center(child: IgnorePointer(child: cover))), const SizedBox(width: 14)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row.copyWith(fontFamily: on ? AppType.label.fontFamily : null)),
                    Text(sub, style: AppType.caption),
                  ]),
                ),
                const SizedBox(width: 14),
                RadioMark(on: on),
              ]),
            ),
          ),
        ),
      );
}
