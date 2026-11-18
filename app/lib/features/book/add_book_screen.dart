// 책 추가(지금 앱 app/book/add.tsx): 책 찾기(검색·직접 입력) → 책·판본 확인 → 추가하고 책장에 놓기(기본) 또는 보관만 하기.
// 저장한 뒤 다시 묻지 않는다. 자리가 모자랄 때만 새 선반 열기 / 보관만 하기를 고른다(place_books). 보관만 한 책도 전체 책에 있다.
// 검색 결과·표지·쪽수가 없어도 직접 입력과 기본 장정으로 끝낼 수 있다. 추정 크기를 확인된 정보처럼 저장하지 않는다.
// 2026-11-15 페르소나 QA·사용자 '다 넣어': '책 확인'에서 뒤로·'한 권 더 추가' 뒤에도 검색어와 결과가 남는다(_FindMemory),
// 검색 결과에서 여러 권 고르기 → 한 번에 추가, 결과 줄에 출판사·연도와 '내 서재에 있음', 바코드 연속 스캔·목록 파일 가져오기 입구
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/library.dart';
import '../../services/book_search.dart';
import '../../store/files.dart' show keepImage;
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/alert.dart';
import '../../ui/book_visual.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../home/home_screen.dart' show showBookOnShelf;
import 'all_books_screen.dart' show openAllBooks;
import 'barcode_scan_screen.dart' show openBarcodeScan;
import 'binding_editor.dart';
import 'book_match.dart';
import 'book_screen.dart' show BookScreen;
import 'book_widgets.dart';
import 'labels.dart' show bookStatuses, statusLabel;
import 'bulk_add.dart';
import 'import_list_screen.dart' show openImportList;
import 'place_books.dart';

/// 책 추가 열기. q: 바로 검색, title: 직접 입력 확인 단계로. pick: 책 고르기에서 '새 책 등록'으로 왔다(추가한 책 id를 돌려준다)
Future<String?> openAddBook(BuildContext context, {String? q, String? title, bool pick = false}) => Navigator.of(context, rootNavigator: true)
    .push<String>(MaterialPageRoute(settings: const RouteSettings(name: '/book/add'), builder: (_) => AddBookScreen(q: q, title: title, pick: pick)));

class _Draft {
  _Draft(this.source);
  String title = '', authors = '', publisher = '', publishedAt = '', isbn = '', pages = '', width = '', height = '';
  String? coverUri, coverSource, category, seriesTitle, sourceName, link, productId;
  final String source; // manual · search · photo
  ReadStatus status = ReadStatus.want;
}

/// 찾기 단계에서 남겨 두는 것: 확인 단계로 갔다 돌아와도·'한 권 더 추가' 뒤에도 검색어와 결과가 그대로(2026-11-15 QA 정우 F2·민혁 F4).
/// 여러 권 고르기에서 고른 책은 검색어를 바꿔도 남는다(여러 번 찾아 모아서 한 번에 추가)
class _FindMemory {
  String q = '';
  List<BookCandidate>? items;
  String? provider, err;
  List<BookCandidate> popular = const [];
  bool multi = false;
  final picked = <String, BookCandidate>{};
}

class AddBookScreen extends StatefulWidget {
  const AddBookScreen({super.key, this.q, this.title, this.pick = false});
  final String? q, title;
  final bool pick;

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  late String _step = widget.title != null ? 'confirm' : 'find'; // find · confirm · binding
  // 장정 직접 고르기: 추천 장정 계산값과 고르는 장정
  BookArtParams? _art;
  BindingDraft? _binding;
  late _Draft _draft = _Draft('manual')..title = widget.title ?? '';
  String? _notice;
  bool _saving = false, _more = false;
  final _find = _FindMemory();

  /// 판형(가로·세로 mm): 둘 다 있을 때만
  ({int widthMm, int heightMm})? get _size {
    final w = numOf(_draft.width), h = numOf(_draft.height);
    return w != null && h != null ? (widthMm: math.min(w, h), heightMm: math.max(w, h)) : null;
  }

  void _toConfirm(_Draft d, [String? msg]) => setState(() {
        _draft = d;
        _notice = msg;
        _step = 'confirm';
      });

  /// 고르면 그 판본의 상세(쪽수·판형·ISBN)를 읽어 채운다(없으면 비워 둔 채로 확인 단계로)
  Future<void> _fromCandidate(BookCandidate picked) async {
    setState(() => _notice = '판본 정보를 확인하는 중…');
    final c = await candidateDetails(picked);
    if (!mounted) return;
    final d = _Draft('search')
      ..title = c.title
      ..authors = c.authors.join(', ')
      ..publisher = c.publisher ?? ''
      ..publishedAt = c.publishedAt ?? ''
      ..isbn = c.isbn13 ?? ''
      ..pages = c.pageCount?.toString() ?? ''
      ..width = c.size?.widthMm.toString() ?? ''
      ..height = c.size?.heightMm.toString() ?? ''
      ..coverUri = c.coverUrl
      ..coverSource = c.coverUrl != null ? 'api' : null
      ..category = c.category
      ..seriesTitle = c.seriesTitle
      ..sourceName = c.sourceName
      ..link = c.link
      ..productId = c.productId;
    final missing = [if (c.pageCount == null) '쪽수', if (c.size == null) '판형'];
    _toConfirm(d, missing.isEmpty ? null : '${c.sourceName} 판본 기록에 ${missing.join(', ')} 정보가 없어요. 알면 적고, 모르면 비워 두세요(장정은 흔한 크기로 만들고 ‘확인 전’으로 표시해요).');
  }

  /// 같은 ISBN이 이미 서재에 있으면: 기존 책 보기 / 별도 소장본으로 추가. 다시 읽기는 재등록이 아니라 기존 책에서
  void _confirmDuplicate(VoidCallback go) {
    final code = cleanIsbn(_draft.isbn);
    final lib = LibraryModel.instance.lib;
    final dup = code.isEmpty ? null : lib.books.values.where((b) => b.hiddenAt == null && lib.editions[b.editionId]?.isbn13 == code).firstOrNull;
    if (dup == null) return go();
    appAlert(context, '이미 내 서재에 있는 책이에요',
        '같은 ISBN의 책이 있어요. 다시 읽으려면 그 책에서 ‘다시 읽기’를 하면 지난 기록이 그대로 이어져요. 같은 책을 한 권 더 가지고 있다면 별도 소장본으로 추가할 수 있어요.', [
      const AlertButton('취소', style: AlertStyle.cancel),
      AlertButton('기존 책 보기', onPress: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book'), builder: (_) => BookScreen(id: dup.id)))),
      AlertButton('별도 소장본으로 추가', onPress: go),
    ]);
  }

  /// 추천 장정 계산(여러 권 추가와 같은 식, bulk_add recommendedArt): 표지는 색 추출에만 쓰고 결과 장정만 저장한다. 책등 사진 비율도 먼저 잰다
  Future<BookArtParams> _prepareArt() {
    final d = _draft;
    return recommendedArt(
      title: d.title,
      isbn: d.isbn,
      publisher: d.publisher,
      publishedAt: d.publishedAt,
      pageCount: numOf(d.pages),
      size: _size,
      category: d.category,
      seriesTitle: d.seriesTitle,
      coverUri: d.coverUri,
      apiCover: d.coverSource == 'api',
    );
  }

  /// 등록 완료: shelf(기본)는 바로 책장에 놓고, keep은 책장에 없는 책으로 보관만 한다
  Future<void> _add({bool keep = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final picked = _step == 'binding' ? _binding : null;
      final art = picked != null && _art != null ? _art! : await _prepareArt();
      final d = _draft;
      var coverUri = d.coverUri;
      if (coverUri != null && d.coverSource == 'photo') coverUri = await keepImage(coverUri, 'cover');
      final isbn = cleanIsbn(d.isbn);
      final id = await LibraryModel.instance.addBook(
        title: d.title.trim(),
        authors: [for (final a in d.authors.split(',')) if (a.trim().isNotEmpty) a.trim()],
        publisher: d.publisher.trim().isEmpty ? null : d.publisher.trim(),
        publishedAt: d.publishedAt.trim().isEmpty ? null : d.publishedAt.trim(),
        isbn13: isbn.isEmpty ? null : isbn,
        pageCount: numOf(d.pages),
        widthMm: _size?.widthMm,
        heightMm: _size?.heightMm,
        category: d.category,
        seriesTitle: d.seriesTitle,
        art: art,
        coverUri: coverUri,
        coverSource: coverUri != null ? d.coverSource : null,
        source: d.source,
        sourceName: d.sourceName,
        link: d.link,
        productId: d.productId,
        status: d.status,
        binding: picked,
      );
      // 책장 쪽 책 목록에 새 책을 넣고 놓는다
      await PlacementStore.instance.reload();
      if (!mounted) return;
      String placed;
      if (keep) {
        await PlacementStore.instance.addToDrawer(id);
        placed = 'kept';
      } else {
        final r = await placeWithChoice(context, [id]);
        placed = r.placed > 0 ? 'shelf' : (r.full ? 'full' : 'kept');
      }
      if (mounted) await _showDone(id, placed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 추가 완료(결과만 알린다. 다시 묻지 않는다): 밑에서 올라오는 시트. 닫으면 책 추가를 부른 화면으로
  Future<void> _showDone(String id, String placed) async {
    final lib = LibraryModel.instance.lib;
    final nav = Navigator.of(context);
    String? next;
    await showSheet<void>(
      context,
      title: '추가했어요',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (lib.books[id] != null) SizedBox(width: 88, child: BookVisual(lib: lib, id: id, width: 88)),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_draft.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
              if (_draft.authors.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(_draft.authors, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub)),
              Padding(
                padding: const EdgeInsets.only(top: Space.m),
                child: Text(placed == 'shelf' ? '책장에 진열했어요' : keptTitle(full: placed == 'full'), style: AppType.button.copyWith(color: AppColors.accent)),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(placed == 'shelf' ? '꾸미기에서 자리와 자세를 바꿀 수 있어요.' : keptNote(full: placed == 'full'), style: AppType.caption),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: Space.xl),
        // 시트 안 단추는 l(2026-11-19 공통 규칙: 확인 시트는 l, 결과 시트는 m이었다)
        if (widget.pick)
          Btn(label: '이 책으로 계속 쓰기', size: 'l', onPress: () => Navigator.pop(ctx))
        else ...[
          if (placed == 'shelf')
            Btn(label: '책장에서 보기', size: 'l', onPress: () {
              next = 'shelf';
              Navigator.pop(ctx);
            })
          else
            Btn(label: '내 책 보기', size: 'l', onPress: () {
              next = 'books';
              Navigator.pop(ctx);
            }),
          const SizedBox(height: Space.s),
          Btn(label: '책 정보 보기', kind: 'secondary', size: 'l', onPress: () {
            next = 'book';
            Navigator.pop(ctx);
          }),
          SubAction(label: '한 권 더 추가', onPress: () {
            next = 'again';
            Navigator.pop(ctx);
          }),
        ],
      ]),
    );
    if (!mounted) return;
    switch (next) {
      case 'shelf':
        showBookOnShelf(nav.context, id);
      case 'books':
        nav.pop(id);
        if (nav.context.mounted) openAllBooks(nav.context, offShelf: true);
      case 'book':
        nav.pushReplacement(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book'), builder: (_) => BookScreen(id: id)));
      case 'again':
        // 책을 다 넣고 '한 권 더 추가'면 빈 검색 칸으로 새로 찾는다(2026-11-16 QA 은서 F16: 앞 검색어(ISBN) 뒤에 이어 쳐 엉뚱한 결과가 나왔다).
        // 검색어를 남기는 것은 결과에서 책 확인으로 갔다 뒤로 돌아올 때다(2026-11-15 QA 정우 F2·민혁 F4)
        setState(() {
          _find
            ..q = ''
            ..items = null
            ..provider = null
            ..err = null;
          _step = 'find';
          _draft = _Draft('manual');
          _notice = null;
          _art = null;
          _binding = null;
          _more = false;
        });
      default:
        // 닫으면 책 추가를 부른 화면으로(이미 추가했으니 확인 화면에 머물지 않는다)
        nav.pop(id);
    }
  }

  /// 장정 직접 고르기: 추천 장정을 계산해 두고 미리보기 단계로
  Future<void> _toBinding() async {
    setState(() => _saving = true);
    try {
      final art = await _prepareArt();
      if (!mounted) return;
      setState(() {
        _art = art;
        _binding = BindingDraft.of(art);
        _step = 'binding';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 'binding' && _art != null && _binding != null) {
      // 뒤로 가면 책 확인으로(고른 장정은 버린다)
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_saving) setState(() => _step = 'confirm');
        },
        child: Screen(
          title: '장정 미리보기',
          footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Btn(label: '추가하고 책장에 진열', busy: _saving, onPress: () => _add()),
            SubAction(label: '보관만 하기', disabled: _saving, onPress: () => _add(keep: true)),
          ]),
          children: [
            BindingEditor(
              title: _draft.title,
              author: _draft.authors,
              size: _size,
              pages: numOf(_draft.pages),
              value: _binding!,
              recommended: BindingDraft.of(_art!),
              realCover: _draft.coverUri,
              onChange: (v) => setState(() => _binding = v),
            ),
          ],
        ),
      );
    }
    if (_step == 'find') {
      return _FindStep(
        memory: _find,
        initial: widget.q,
        notice: _notice,
        pick: widget.pick,
        onPick: _fromCandidate,
        onManual: (q) => _toConfirm(_Draft('manual')..title = q),
        onAddMany: _addMany,
      );
    }
    final d = _draft;
    final ready = d.title.trim().isNotEmpty && !_saving;
    // 찾기에서 왔으면 뒤로 키·뒤로 화살표는 검색 결과로(2026-11-15 QA 민혁 F4: 책장까지 나가 검색어가 사라졌다). 직접 입력으로 바로 연 확인은 그대로 닫힌다
    return PopScope(
      canPop: widget.title != null,
      onPopInvokedWithResult: (didPop, _) {
        // 확인 단계 안내(판본 쪽수·판형 없음 등)는 그 책 이야기라 검색으로 돌아가면 지운다(2026-11-18: 검색 화면에 남아 있었다)
        if (!didPop && !_saving) {
          setState(() {
            _step = 'find';
            _notice = null;
          });
        }
      },
      child: _confirm(d, ready),
    );
  }

  /// 여러 권 고르기에서 고른 책을 한 번에 추가(추천 장정, 진열 규칙은 한 권 추가와 같다). 결과 시트에서 '계속 추가'면 찾기 단계에 남는다
  Future<void> _addMany(List<BookCandidate> picks) async {
    if (_saving || picks.isEmpty) return;
    setState(() => _saving = true);
    final r = await addBooks(context, [for (final c in picks) (book: c, status: ReadStatus.want)]);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _find
        ..picked.clear()
        ..multi = false;
    });
    final next = await showBulkDone(context, r);
    if (mounted) goAfterBulk(context, next);
  }

  Widget _confirm(_Draft d, bool ready) {
    return Screen(
      title: '책 확인',
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 주요 행동: 추천 장정으로 바로 추가(책장에 놓기). 장정은 고르고 싶을 때만(보조)
        Btn(label: '추천 장정으로 추가', disabled: !ready, busy: _saving, onPress: () => _confirmDuplicate(() => _add())),
        SubAction(label: '장정 직접 고르기', disabled: !ready, onPress: () => _confirmDuplicate(_toBinding)),
      ]),
      children: [
        if (_notice != null) Padding(padding: const EdgeInsets.only(top: Space.m, bottom: Space.l), child: _Notice(_notice!)),
        _coverBlock(d),
        Field(label: '제목 (필수)', value: d.title, onChange: (t) => setState(() => d.title = t), placeholder: '책 제목'),
        Field(label: '저자 (선택)', value: d.authors, onChange: (t) => setState(() => d.authors = t), placeholder: '여러 명은 쉼표로'),
        Field(label: '전체 쪽수 (선택)', value: d.pages, onChange: (t) => setState(() => d.pages = t), placeholder: '쪽수 입력', number: true),
        // 접는 줄은 목록 가져오기 안내와 같은 부품(2026-11-19 공통 규칙)
        Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: FoldRow(
            title: '추가 정보',
            note: ['출판사', 'ISBN', '판형', '읽기 상태'].join(metaSep),
            open: _more,
            onToggle: () => setState(() => _more = !_more),
            child: Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Field(label: '출판사', value: d.publisher, onChange: (t) => setState(() => d.publisher = t)),
                Field(label: 'ISBN', value: d.isbn, onChange: (t) => setState(() => d.isbn = t), number: true),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Field(label: '판형 가로(mm)', value: d.width, onChange: (t) => setState(() => d.width = t), number: true)),
                  const SizedBox(width: Space.m),
                  Expanded(child: Field(label: '판형 세로(mm)', value: d.height, onChange: (t) => setState(() => d.height = t), number: true)),
                ]),
                Text('쪽수, 판형을 모르면 비워 두세요. 책장에는 흔한 크기로 보이고, 상세에는 ‘확인 전’으로 표시돼요.', style: AppType.sub),
                const H2('읽기 상태'),
                Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                  for (final s in bookStatuses) AppChip(label: statusLabel[s]!, on: d.status == s, onPress: () => setState(() => d.status = s)),
                ]),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  /// 표지 가운데 + 표지 단추, 아래 제공처 한 줄(시안). 표지 단추는 책 정보 수정과 같은 이름 · 모양(2026-11-19 공통 규칙: 회색 상자 안 글자 단추였다)
  Widget _coverBlock(_Draft d) {
    final link = d.link;
    void openLink() => launchUrl(Uri.parse(link!), mode: LaunchMode.externalApplication);
    return Padding(
      padding: const EdgeInsets.only(top: Space.s, bottom: Space.l),
      child: Column(children: [
        _shadowed(RealCover(uri: d.coverUri, title: d.title.isEmpty ? '표지' : d.title, width: 120)),
        Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: CoverPhotoButton(
            hasCover: d.coverUri != null,
            onPicked: (uri) => setState(() => d
              ..coverUri = uri
              ..coverSource = 'photo'),
            onDenied: (msg) => setState(() => _notice = msg),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(child: WordText(d.coverUri != null ? (d.coverSource == 'photo' ? '내가 찍은 사진' : '${d.sourceName ?? '도서 정보'} 제공') : '표지가 없어요', style: AppType.caption)),
            // 원문 보기는 밑줄 없는 글자 단추(2026-11-19 공통 규칙). 화면 읽기 이름은 '○○에서 원문 보기' 그대로
            if (link != null && d.coverSource != 'photo') ...[
              const MetaBar(),
              Semantics(
                link: true,
                label: '${d.sourceName ?? '판매처'}에서 원문 보기',
                excludeSemantics: true,
                onTap: openLink,
                child: TextLink(label: '원문 보기', soft: true, start: true, onPress: openLink),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// 표지 그림자(책 확인 표지 · 검색 결과 표지): 모서리 3 · 옅은 그림자
Widget _shadowed(Widget cover) => DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), boxShadow: [cssShadow(const Color(0x1A000000), 0, 2, 4)]),
      child: cover,
    );

/// 책 추가 첫 화면(2026-11-01 사용자): 검색창 → 결과 → 추가가 전부. 직접 입력은 결과 아래·결과 없음·검색 실패 때의 작은 '직접 등록'으로만.
/// 상태는 부모의 _FindMemory에 둔다(확인 단계에 갔다 와도 그대로). '여러 권 고르기'(전체 책 '책장에 진열'과 같은 모양: 머리줄 '취소',
/// 줄 오른쪽 동그라미 체크, 아래 'N권 추가', 기기 뒤로는 고르기만 끝낸다). 이미 서재에 있는 책은 고르지 않는다(한 권 추가에서 별도 소장본으로)
class _FindStep extends StatefulWidget {
  const _FindStep({
    required this.memory,
    required this.initial,
    required this.notice,
    required this.pick,
    required this.onPick,
    required this.onManual,
    required this.onAddMany,
  });
  final _FindMemory memory;
  final String? initial, notice;
  final bool pick;
  final ValueChanged<BookCandidate> onPick;
  final ValueChanged<String> onManual;
  final ValueChanged<List<BookCandidate>> onAddMany;

  @override
  State<_FindStep> createState() => _FindStepState();
}

class _FindStepState extends State<_FindStep> {
  _FindMemory get _m => widget.memory;
  bool _busy = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null && _m.items == null && _m.q.isEmpty) {
      _m.q = widget.initial!;
      _search(widget.initial!);
    }
    if (_m.popular.isEmpty) {
      popularBooks().then((list) {
        if (mounted) setState(() => _m.popular = list);
      });
    }
  }

  Future<void> _search([String? text]) async {
    final t = (text ?? _m.q).trim();
    if (t.isEmpty) return;
    final run = ++_run;
    setState(() {
      _busy = true;
      _m.err = null;
    });
    final r = await searchBooks(t);
    // 늦게 온 결과로 새 검색 화면을 덮지 않는다
    if (!mounted || run != _run) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _m.items = r.items;
        _m.provider = r.provider;
      } else {
        _m.err = r.message;
        _m.items = null;
      }
    });
  }

  void _toggle(BookCandidate c) => setState(() {
        if (_m.picked.remove(c.key) == null) _m.picked[c.key] = c;
      });

  void _endMulti() => setState(() {
        _m.multi = false;
        _m.picked.clear();
      });

  /// 결과 머리 오른쪽 '여러 권 고르기'(책 고르기에서 새 책 등록으로 왔을 때는 한 권만)
  String? get _multiLink => widget.pick || _m.multi ? null : '여러 권 고르기';

  Widget _row(BookCandidate c, Library lib) {
    final owned = ownedBookId(lib, c) != null;
    return _ResultRow(
      c: c,
      owned: owned,
      multi: _m.multi,
      picked: _m.picked.containsKey(c.key),
      onPick: _m.multi ? (owned ? null : _toggle) : widget.onPick,
    );
  }

  // 목록 머리(많이 찾는 책 · 검색 결과): 공용 구역 머리(구역 제목 19 · 개수 · 제목 아래 출처 · 오른쪽 '여러 권 고르기', 2026-11-19 공통 규칙: 제목이 21이었다)
  Widget _section(String title, {String? count, String? source}) =>
      SectionHead(title: title, count: count, note: source, link: _multiLink, linkLabel: _multiLink, onLink: () => setState(() => _m.multi = true));

  @override
  Widget build(BuildContext context) {
    final items = _m.items;
    final q = _m.q;
    final lib = LibraryModel.instance.lib;
    final n = _m.picked.length;
    return PopScope(
      canPop: !_m.multi,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endMulti();
      },
      // 2026-11-17 사용자 시안: 뒤로 옆 '책 추가' 제목 + 오른쪽 '목록 가져오기', 그 아래 검색칸(오른쪽 끝 바코드), '많이 찾는 책' 줄은 제목·저자와 +
      child: Screen(
        headerField: Semantics(header: true, child: Text(_m.multi ? (n == 0 ? '여러 권 고르기' : '$n권 고름') : '책 추가', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle)),
        // 고르기를 끝내는 '취소'는 본문색(2026-11-19 공통 규칙)
        left: _m.multi ? TextLink(label: '취소', ink: true, onPress: _endMulti) : null,
        // 엑셀·CSV 목록으로 여러 권(책 고르기에서 왔을 때는 한 권만 고르므로 없음)
        right: widget.pick || _m.multi ? null : TextLink(label: '목록 가져오기', soft: true, onPress: () => openImportList(context)),
        footer: _m.multi ? Btn(label: n == 0 ? '추가할 책을 고르세요' : '$n권 추가', disabled: n == 0, onPress: () => widget.onAddMany(_m.picked.values.toList())) : null,
        children: [
          SearchField(
            value: q,
            onChange: (t) => setState(() {
              _m.q = t;
              if (t.isEmpty) {
                _run++;
                _busy = false;
                _m.items = null;
                _m.err = null;
              }
            }),
            onSubmit: () => _search(),
            busy: _busy,
            // 큰 글씨에서는 짧게(2026-11-16 QA 영숙 F3). 화면 읽기 이름은 그대로
            placeholder: _big(context) ? '제목, 저자' : '책 제목, 저자로 검색',
            label: '제목이나 저자로 찾기',
            // 바코드로 여러 권 찾기: 검색칸 오른쪽 끝(책 고르기에서 왔을 때·여러 권 고르는 중에는 없음)
            // 칸 안 아이콘은 돋보기와 같은 22(24였다)
            trailing: widget.pick || _m.multi ? null : IconBtn(label: '바코드로 찾기', onPress: () => openBarcodeScan(context), child: const LucideIcon('ScanBarcode', color: AppColors.inkSoft)),
          ),
          if (widget.notice != null) Padding(padding: const EdgeInsets.only(top: Space.s), child: _Notice(widget.notice!)),
          if (_busy && items == null) const Loading(label: '책을 찾는 중이에요'),
          if (_m.err != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Notice(_m.err!, error: true),
                const SizedBox(height: Space.s),
                Btn(label: '다시 시도', kind: 'secondary', size: 's', onPress: () => _search()),
                _ManualLink(onPress: () => widget.onManual(q)),
              ]),
            ),
          if (items != null && items.isEmpty && !_busy)
            Empty(title: '‘${q.trim()}’에 맞는 책이 없어요', body: '제목이나 저자 이름을 짧게 줄여 찾거나, 직접 등록할 수 있어요.', action: '직접 등록', actionKind: 'secondary', onAction: () => widget.onManual(q)),
          // 검색 전: 많이 찾는 책(YES24 베스트셀러 순서 그대로). 출처 표시는 늘 보인다(YES24 약관)
          if (q.trim().isEmpty && items == null && !_busy && _m.err == null && _m.popular.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _section('많이 찾는 책', source: 'YES24 베스트셀러'),
                const SizedBox(height: Space.s),
                for (final c in _m.popular) _row(c, lib),
              ]),
            ),
          if (items != null && items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // 결과 머리는 '많이 찾는 책'과 같은 모양: 제목 아래 출처(YES24 약관), 오른쪽 '여러 권 고르기'
                // (2026-11-19 사용자: 한 줄에 '|'로 붙여 쓰지 말 것)
                _section('검색 결과', count: '${items.length}권', source: _m.provider == null ? null : '${_m.provider} 제공'),
                const SizedBox(height: Space.s),
                for (final c in items) _row(c, lib),
                if (!_m.multi) _ManualLink(onPress: () => widget.onManual(q)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// 글자를 키운 화면(1.3배부터)
bool _big(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) >= 13;

/// 검색 결과·인기 책 한 줄(공용 책 줄 BookRow 보통, 2026-11-19 공통 규칙): 표지 · 제목 · 저자, 오른쪽 '추가'.
/// 출판사 · 연도(판 구분, 2026-11-15 QA 지민 F12·정우 F7)는 화면 읽기 이름에만 둔다(2026-11-17 사용자 시안: 제목 밑에 저자만).
/// 이미 서재에 있는 책은 '내 서재에 있음'(체크). 여러 권 고르기에서는 '추가' 대신 고르는 원(서재에 있는 책은 흐린 원, 고를 수 없음)
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.c, required this.onPick, this.owned = false, this.multi = false, this.picked = false});
  final BookCandidate c;
  final bool owned, multi, picked;
  final ValueChanged<BookCandidate>? onPick;

  /// 오른쪽 그림(22)의 오른쪽 끝을 내용 오른쪽 끝(검색칸 끝)에 맞춘다: 누르는 칸 48 가운데 22라 남는 만큼 밀어 둔다
  static const _iconNudge = (Space.hit - 22) / 2;

  @override
  Widget build(BuildContext context) {
    final pub = publisherLine(c);
    final tap = onPick == null ? null : () => onPick!(c);
    final action = multi ? (owned ? '내 서재에 있음' : (picked ? '고름' : '고르기')) : '추가';
    const size = BookRowSize.medium;
    return BookRow(
      size: size,
      cover: Opacity(
        opacity: multi && owned ? disabledOpacity : 1,
        child: _shadowed(RealCover(uri: c.coverUrl, title: c.title, width: BookRow.coverWidth(size), ratio: 0.72)),
      ),
      title: c.title,
      meta: c.authors.isEmpty ? null : c.authors.join(', '),
      trailing: multi
          ? RadioMark(on: picked, dim: owned)
          // 오른쪽 + (이미 서재에 있는 책은 체크: 눌러도 별도 소장본으로 넣을지 묻는다). 시안처럼 작고 옅은 회색
          : Transform.translate(
              offset: const Offset(_iconNudge, 0),
              child: SizedBox.square(
                dimension: Space.hit,
                child: Center(child: owned ? const AddedMark() : const LucideIcon('Plus', color: AppColors.inkSoft)),
              ),
            ),
      onPress: tap,
      selected: multi && picked,
      // 여러 권 고르기에서는 서재에 있는 책의 행동 이름이 '내 서재에 있음'이라 두 번 읽지 않는다(2026-11-18)
      label: [c.title, if (c.authors.isNotEmpty) c.authors.join(', '), ?pub, if (owned && action != '내 서재에 있음') '내 서재에 있음', action].join(', '),
    );
  }
}

/// 검색으로 못 찾았을 때만 쓰는 보조 경로(누르는 자리 48, 화면 읽기로도 누를 수 있게)
class _ManualLink extends StatelessWidget {
  const _ManualLink({required this.onPress});
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '원하는 책이 없나요? 직접 등록',
        excludeSemantics: true,
        onTap: onPress,
        child: Center(
          child: Pressable(
            onPress: onPress,
            child: Container(
              constraints: const BoxConstraints(minHeight: Space.hit),
              margin: const EdgeInsets.only(top: Space.l),
              alignment: Alignment.center,
              child: Text.rich(TextSpan(text: '원하는 책이 없나요? ', style: AppType.sub, children: [
                TextSpan(text: '직접 등록', style: AppType.sub.strong.copyWith(color: AppColors.accent)),
              ])),
            ),
          ),
        ),
      );
}

/// 안내 글(상자 없이: 흰 화면 안 회색 상자를 두지 않는다, 2026-11-19 공통 규칙). 안내는 sub, 오류는 sub 빨강
class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: WordText(text, style: error ? AppType.sub.copyWith(color: AppColors.danger) : AppType.sub),
      );
}
