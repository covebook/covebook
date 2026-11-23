// 기록 탭(2026-11-16 메뉴 구조 개편): 맨 위 글자 탭 '갈피 | 감상'과 그 줄 오른쪽 검색 · 추가(고른 글자 탭에 맞게). 왼쪽 위 제목 '기록'은 없다(2026-11-24 사용자 6단계, 하단바에 이름).
// 검색을 켜면 맨 위 한 줄에 검색칸이 나타나고 끄면 사라진다.
// 갈피: 예전 갈피 탭 그대로 옮김. 탭 아래 한 줄은 '갈피 N개'와 아껴둔 갈피 켜고 끄기·필터. 책·유형(문장·사진)은 필터 시트에,
// 걸렸을 때만 '데미안 | 사진 갈피'처럼 조건과 '조건 지우기'를 보인다(기본 조건 칩 줄은 없앴다). 갈피 보드는 개수 줄 격자 아이콘에서.
// 감상: 긴 감상(essay_screens.dart) 목록. '감상 N편'과 필터(책). 표지·책 제목·지은이·미리보기·쓴 날을 상자 없이 줄로
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/qa_probe.dart';
import '../../app/app_nav.dart';
import '../../domain/library.dart';
import '../../store/library_model.dart';
import '../../store/mini_timer_store.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/feedback.dart' show errorText;
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/board_screen.dart' show openBookmarkBoard;
import '../bookmark/book_picker.dart' show pickBook;
import '../bookmark/bookmark_card.dart';
import '../bookmark/bookmark_detail_screen.dart';
import '../bookmark/bookmark_empty.dart';
import '../bookmark/mark_text.dart' show isPhotoMark;
import '../bookmark/new_bookmark_screen.dart';
import 'essay_screens.dart';

enum MarkKind { all, text, photo }

// 유형 이름(필터 칸 · 조건 줄). all은 필터 칸 '전체'(읽지 않던 '모든 유형'을 칸 이름으로, 2026-11-19)
const markKindLabel = {MarkKind.all: '전체', MarkKind.text: '문장 갈피', MarkKind.photo: '사진 갈피'};
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

  /// 오래된 순(기본은 최신순). 갈피 · 감상 따로(2026-11-18 사용자 '필터가 책밖에 없어? 최신순 오래된순 이런 거는?')
  bool _marksOld = false, _essaysOld = false;

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

  /// 기록이 있는 책과 그 수(최근 기록 순: 목록이 이미 최근 순, 맵은 넣은 순서를 지킨다)
  Map<String, int> _booksOf(Iterable<String> bookIds) {
    final n = <String, int>{};
    for (final id in bookIds) {
      n[id] = (n[id] ?? 0) + 1;
    }
    return n;
  }

  void _toggleSaved(String id) {
    _model.toggleSaved(id).catchError((Object e) {
      // 공통 규칙: 실패 본문은 errorText(예외 원문은 로그로)
      if (mounted) appAlert(context, '갈피 표시를 저장하지 못했어요', errorText(e));
    });
  }

  // ── 필터 시트 ──

  /// 필터 시트(갈피 · 감상이 같은 모양 · 같은 동작, 2026-11-19 공통 규칙): 책 한 줄(모든 책 ›) · 그 밖 조건 · 적용.
  /// 책은 필터 시트 위에 겹쳐 고르고, 고른 것은 '적용'을 눌러야 걸린다(2026-11-17 사용자 시안. 감상 필터는 고르면 바로 걸렸다)
  Future<void> _openFilter({
    required String? book,
    required bool old,
    required void Function(String? current, ValueChanged<String?> onPick) chooseBook,
    List<Widget> Function(StateSetter set)? more,
    required void Function(String? book, bool old) onApply,
  }) {
    var picked = book;
    var oldFirst = old;
    return showSheet<void>(
      context,
      title: '필터',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          // 공통 규칙: '이름 … 값 ›' 줄은 ListItem(직접 만든 줄이었다)
          // 정렬(내 책 필터와 같은 두 칸)
          const SheetLabel('정렬'),
          Row(children: [
            Expanded(child: ChoiceBox(label: '최신순', on: !oldFirst, onPress: () => set(() => oldFirst = false))),
            const SizedBox(width: Space.s),
            Expanded(child: ChoiceBox(label: '오래된순', on: oldFirst, onPress: () => set(() => oldFirst = true))),
          ]),
          const SizedBox(height: Space.l),
          ListItem(label: '책', value: picked == null ? '모든 책' : _titleOf(picked!), chevron: true, onPress: () => chooseBook(picked, (id) => set(() => picked = id))),
          const Hairline(),
          const SizedBox(height: Space.l),
          ...?more?.call(set),
          Btn(
            label: '적용',
            size: 'xlarge',
            onPress: () {
              Navigator.pop(ctx);
              onApply(picked, oldFirst);
            },
          ),
          const SizedBox(height: Space.s),
        ]),
      ),
    );
  }

  // 갈피 필터(2026-11-17 사용자 시안, 높이·여백은 시안보다 조금 넉넉히): 책 한 줄(모든 책 ›) · 유형 세 칸 · 아껴둔 갈피만 · 적용.
  // 갈피 보드는 머리줄 격자 아이콘으로 옮겼다
  Future<void> _openMarkFilter() {
    var kind = _kind;
    var saved = _savedOnly;
    return _openFilter(
      book: _markBook,
      old: _marksOld,
      chooseBook: (current, onPick) => _pickMarkBook(_marks, current: current, onPick: onPick),
      more: (set) => [
        const SheetLabel('유형'),
        Row(children: [
          for (final (i, k) in MarkKind.values.indexed) ...[
            if (i > 0) const SizedBox(width: Space.s),
            Expanded(child: ChoiceBox(label: markKindLabel[k]!, on: kind == k, onPress: () => set(() => kind = k))),
          ],
        ]),
        const SizedBox(height: Space.l),
        // 아껴둔 갈피만(예전 머리줄 아이콘)
        FilterToggleRow(label: '아껴둔 갈피만', value: saved, onChange: (v) => set(() => saved = v)),
        const SizedBox(height: Space.l),
      ],
      onApply: (book, old) => setState(() {
        _markBook = book;
        _kind = kind;
        _savedOnly = saved;
        _marksOld = old;
      }),
    );
  }

  void _openBoard() {
    final marks = _marks;
    final books = _booksOf(marks.map((m) => m.myBookId));
    final only = _markBook ?? (books.length == 1 ? books.keys.first : null);
    if (only != null) {
      openBookmarkBoard(context, only);
    } else {
      _pickMarkBook(marks, board: true, onPick: (id) {
        if (id != null) openBookmarkBoard(context, id);
      });
    }
  }

  /// 갈피가 있는 책 고르기(필터의 책 줄 · 보드로 볼 책). 보드는 '모든 책' 줄 없이
  Future<void> _pickMarkBook(List<Bookmark> marks, {bool board = false, String? current, required ValueChanged<String?> onPick}) => _chooseBook(
        description: board ? '갈피 보드로 볼 책을 골라요.' : null,
        books: _booksOf(marks.map((m) => m.myBookId)),
        unit: (n) => '갈피 $n개',
        allSub: board ? null : '갈피 ${marks.length}개',
        current: current,
        onPick: onPick,
      );

  // 감상 필터: 갈피 필터와 같은 시트(고를 것이 책뿐이라 책 줄 + 적용)
  Future<void> _openEssayFilter() {
    final all = _model.essaysOf();
    return _openFilter(
      book: _essayBook,
      old: _essaysOld,
      chooseBook: (current, onPick) => _chooseBook(
        books: _booksOf(all.map((e) => e.myBookId)),
        unit: (n) => '감상 $n편',
        allSub: '감상 ${all.length}편',
        current: current,
        onPick: onPick,
      ),
      onApply: (book, old) => setState(() {
        _essayBook = book;
        _essaysOld = old;
      }),
    );
  }

  /// 책 고르기: 앱 공통 책 고르기 시트(book_picker pickBook, 2026-11-19 공통 규칙: 기록 탭 · 통계 · 갈피 남기기가 따로 만들었다).
  /// 책 줄 둘째 줄은 그 책의 갈피 · 감상 수, allSub가 있으면 맨 위 '모든 책'(고르면 null)
  Future<void> _chooseBook({
    String? description,
    required Map<String, int> books,
    required String Function(int) unit,
    required String? allSub,
    required String? current,
    required ValueChanged<String?> onPick,
  }) async {
    final r = await pickBook(
      context,
      _lib,
      books: books.keys.toList(),
      meta: (id) => unit(books[id] ?? 0),
      all: allSub != null,
      allSub: allSub,
      current: (id: current),
      description: description,
    );
    if (r.picked) onPick(r.id);
  }

  // ── 화면 ──

  @override
  Widget build(BuildContext context) {
    // 공통 규칙 11장: 화면 전체를 불러오는 중은 가운데 원(빈 몸통이었다)
    if (!_model.loaded) return const Screen(title: '기록', back: false, scroll: false, hideTitle: true, children: [Loading()]);
    final section = _section;
    final marks = section == RecordSection.marks;
    final searching = _searching.contains(section);
    final what = marks ? '갈피' : '감상';
    // 왼쪽 위 제목 '기록'은 없다(하단바에 이름, 2026-11-24 사용자 6단계): 맨 위가 '갈피 | 감상' 줄, 그 오른쪽에 검색 · ＋
    final icons = Row(mainAxisSize: MainAxisSize.min, children: [
      // 공통 규칙: 머리줄 아이콘은 HeadIcon(회색, 2026-11-19)
      IconBtn(label: '$what 검색', onPress: () => setState(() => _searching.add(section)), child: const HeadIcon('Search')),
      const SizedBox(width: headIconGap),
      marks
          ? IconBtn(label: '갈피 추가', onPress: () => openNewBookmark(context, book: _markBook, photoOnly: _kind == MarkKind.photo), child: const HeadIcon('Plus'))
          : IconBtn(label: '감상 쓰기', onPress: () => openNewEssay(context, book: _essayBook), child: const HeadIcon('Plus')),
    ]);
    return qaProbe('records', Screen(
      title: '기록',
      back: false,
      scroll: false,
      hideTitle: true,
      // 검색 중: 맨 위 한 줄에 검색칸(끄면 사라진다), 닫기는 칸 왼쪽 ← (내 책 검색과 같은 모양, 2026-11-20 사용자 · 11-21 내 책 검색 시안)
      headerField: searching
          ? SearchField(
              key: ValueKey(section),
              value: _q[section]!,
              onChange: (v) => setState(() => _q[section] = v),
              autofocus: true,
              placeholder: marks ? '문장, 메모에서 찾기' : '감상, 책 제목에서 찾기',
              label: '$what 검색어',
              onBack: () => setState(() {
                _q[section] = '';
                _searching.remove(section);
              }),
            )
          : null,
      children: [
        // 갈피 | 감상: 같은 크기 글자, 고른 것만 진하게 + 짧고 얇은 밑줄(회색 상자 없이 왼쪽 정렬). 오른쪽 끝 검색 · ＋(검색 중에는 없다)
        Row(children: [
          Tabs<RecordSection>(items: _sections, value: section, onChange: (v) => setState(() => _section = v), gap: Space.xl),
          const Spacer(),
          // 마지막 아이콘 오른쪽 여백을 개수 줄 아이콘과 맞춘다
          if (!searching) Transform.translate(offset: const Offset(10, 0), child: icons),
        ]),
        ...marks ? _marksBody(context) : _essaysBody(context),
      ],
    ));
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
              Expanded(child: MetaText(conditions.join(metaSep), style: AppType.sub.copyWith(color: AppColors.ink), maxLines: 2, overflow: TextOverflow.ellipsis)),
              // 공통 규칙 11·13장: 조건을 푸는 말은 '조건 지우기' 하나(빈 화면 단추와 같은 말, '조건 해제'였다)
              Transform.translate(offset: const Offset(8, 0), child: TextLink(label: '조건 지우기', soft: true, onPress: clear)),
            ]),
          ),
      ];

  List<Widget> _marksBody(BuildContext context) {
    final all = _marks;
    if (all.isEmpty) return [Expanded(child: BookmarkEmpty(onAdd: () => openNewBookmark(context)))];
    final q = _q[RecordSection.marks]!.trim();
    final shown = [for (final m in all) if (markShown(m, book: _markBook, kind: _kind, savedOnly: _savedOnly, q: q)) m];
    final list = _marksOld ? shown.reversed.toList() : shown;
    final conditions = [
      if (_marksOld) '오래된순',
      ...markConditions(bookTitle: _markBook == null ? null : _titleOf(_markBook!), kind: _kind, savedOnly: _savedOnly),
    ];
    void clear() => setState(() {
          _markBook = null;
          _kind = MarkKind.all;
          _savedOnly = false;
          _marksOld = false;
        });
    final plain = _savedOnly && q.isEmpty && _markBook == null && _kind == MarkKind.all;
    // 공통 규칙 11장: 검색 0건은 "‘검색어’에 맞는 …" + 다른 낱말 안내, 거르기 0건은 '조건에 맞는 …' + '조건 지우기'
    final emptyTitle = q.isNotEmpty
        ? '‘$q’에 맞는 갈피가 없어요'
        : plain
            ? '아껴둔 갈피가 없어요'
            : _kind == MarkKind.photo
                ? '사진 갈피가 없어요'
                : '조건에 맞는 갈피가 없어요';
    // 본문은 단추 없이 할 일을 알려야 할 때만(DESIGN 11장): 검색 0건은 바로 위 검색칸이 할 일
    final emptyBody = q.isNotEmpty
        ? null
        : plain
            ? '갈피 오른쪽 아래의 표시를 눌러 모아 보세요.'
            : _kind == MarkKind.photo
                ? '페이지를 찍어 그대로 붙여 두세요.'
                : null;
    final cardW = math.min(MediaQuery.sizeOf(context).width - Space.page * 2, contentMax);
    final bottomPad = _bottomPad;
    return [
      ..._countRows(
        '갈피 ${list.length}개',
        [
          // 갈피 보드(책 한 권의 갈피를 넓은 보드에): 격자 아이콘(2026-11-17 시안). 아껴둔 갈피만은 필터 안으로 옮겼다
          // 공통 규칙: 아이콘은 머리줄과 같은 회색 HeadIcon, 사이 headIconGap(2026-11-19. 격자만 검었고 사이가 0이었다)
          IconBtn(label: '갈피 보드로 보기', onPress: _openBoard, child: const HeadIcon('LayoutGrid')),
          const SizedBox(width: headIconGap),
          FilterIcon(active: _markBook != null || _kind != MarkKind.all || _savedOnly || _marksOld, onPress: _openMarkFilter),
        ],
        conditions,
        clear,
      ),
      Expanded(
        child: OverflowBox(
          // 목록은 화면 좌우 여백 밖까지(카드 그림자·뒤 종이가 잘리지 않게)
          maxWidth: cardW + Space.page * 2,
          child: list.isEmpty
              ? ListView(padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, bottomPad), children: [
                  Empty(title: emptyTitle, body: emptyBody, action: q.isEmpty ? '조건 지우기' : null, actionKind: 'secondary', onAction: clear),
                ])
              : ListView.builder(
                  // 글자 탭마다 따로 스크롤 자리를 기억한다
                  key: const PageStorageKey('record-marks'),
                  padding: EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, bottomPad),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    // 카드 값은 상세와 같은 cardData(목록 날짜는 dateShort)
                    final data = cardData(_lib, m, short: true);
                    if (data == null) return const SizedBox.shrink();
                    return qaProbe('markcard', BookmarkCard(
                      key: ValueKey(m.id),
                      compact: true,
                      width: cardW,
                      seed: m.id,
                      onOpen: () => openBookmark(context, m.id),
                      saved: m.savedAt != null,
                      onToggleSaved: () => _toggleSaved(m.id),
                      data: data,
                    ));
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
    final shown = [for (final e in all) if (essayShown(_lib, e, book: book, q: q)) e];
    final list = _essaysOld ? shown.reversed.toList() : shown;
    void clear() => setState(() {
          _essayBook = null;
          _essaysOld = false;
        });
    return [
      ..._countRows(
        '감상 ${list.length}편',
        [FilterIcon(active: book != null || _essaysOld, onPress: _openEssayFilter)],
        [if (_essaysOld) '오래된순', if (book != null) _titleOf(book)],
        clear,
      ),
      Expanded(
        child: list.isEmpty
            ? ListView(padding: EdgeInsets.only(bottom: bottomPad), children: [
                // 공통 규칙 11장: 검색 0건 · 거르기 0건(갈피와 같은 말)
                q.isNotEmpty
                    ? Empty(title: '‘$q’에 맞는 감상이 없어요')
                    : Empty(title: '조건에 맞는 감상이 없어요', action: '조건 지우기', actionKind: 'secondary', onAction: clear),
              ])
            // 목록 줄 사이에 선을 긋지 않는다(다른 책 목록과 같게, 0.5 선이었다)
            : ListView.builder(
                key: const PageStorageKey('record-essays'),
                padding: EdgeInsets.only(bottom: bottomPad),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: list.length,
                itemBuilder: (context, i) => EssayRow(key: ValueKey(list[i].id), lib: _lib, essay: list[i]),
              ),
      ),
    ];
  }
}
