// 책 정보(지금 앱 app/book/[id]/index.tsx): 표지 위 가운데 전환 칸 [내 기록 | 평가 | 책 정보], 열면 내 기록(2026-11-24). 이어서 읽기와 갈피 남기기는 아래에 늘 보인다.
// 책 꾸미기는 책 정보 칸 줄, 책 공유는 머리줄 아이콘(⋯ 메뉴에서는 뺐다)
// 날짜·쪽수·별점은 모두 선택 입력. 완독은 사용자가 정하거나, 적은 쪽(기록의 도달한 쪽 · 현재 쪽)이 마지막 쪽일 때만 자동으로 바뀐다(타이머 시간으로는 판정하지 않고, 자동으로 되돌리지 않는다. domain/reading.dart 읽기 상태 · 현재 쪽 규칙).
// 완독한 책을 '읽는 중'·'보류'로 바꾸면 새 회차(다시 읽기)라 먼저 묻는다. 상태를 완독으로 바꾸면 평가 칸으로 넘긴다(2026-11-23). 현재 쪽을 마지막 쪽으로 고쳐 완독이 돼도 평가 칸으로(2026-11-24)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:url_launcher/url_launcher.dart';

import '../../domain/layout.dart' show placementOf;
import '../../domain/library.dart';
import '../../store/library_model.dart';
import '../../store/library_store.dart' show archivedYears;
import '../../store/placement_store.dart';
import '../../ui/alert.dart';
import '../../ui/book_visual.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/board_screen.dart' show openBookmarkBoard;
import '../bookmark/bookmark_detail_screen.dart' show openBookmark;
import '../bookmark/new_bookmark_screen.dart';
import '../bookmark/photo_plate.dart' show BookmarkPhoto;
import '../community/book_reviews.dart';
import '../home/home_screen.dart' show showBookOnShelf;
import '../../domain/reading.dart' show clock;
import '../../store/reading_store.dart';
import '../reading/reading_screen.dart' show ElapsedTicker;
import '../reading/start_book.dart' show startReadingBook;
import '../record/essay_screens.dart' show EssayRow, openNewEssay;
import '../stats/chart_data.dart' show timeLabel, timeRange;
import '../stats/session_edit_screen.dart' show openSessionAdd, openSessionEdit;
import '../stats/stats_screen.dart';
import 'binding_screen.dart' show openBindingEditor;
import 'book_share_screen.dart' show openBookShare;
import 'book_widgets.dart' show confirmRemoveBooks, removeBooks, removedText, unhideBook, unhiddenText;
import 'edit_book_screen.dart' show openEditBook;
import 'labels.dart';
import 'place_books.dart' show keptNote, keptTitle, placeWithChoice;

// 내 기록이 먼저(2026-11-24 사용자 2단계: [책 정보 | 평가 | 내 기록]이었고 열면 책 정보였다)
const _views = [('mine', '내 기록'), ('rate', '평가'), ('info', '책 정보')];

/// 책 정보 화면 열기
Future<void> openBook(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book'), builder: (_) => BookScreen(id: id)));

/// 책 정보 화면
class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.id, this.onRead});
  final String id;

  /// '읽기 시작·이어서 읽기'를 대신할 동작(시험용). 없으면 그 책으로 독서를 시작하고 읽기 화면을 연다(start_book)
  final void Function(String id)? onRead;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  final _model = LibraryModel.instance;
  String _tab = 'mine';
  bool _pageEdit = false;
  bool _noteEdit = false; // 평가 탭 한줄평을 고치는 중
  bool _roundEdit = false; // 내 기록 탭 읽은 기간 날짜를 고치는 중
  Timer? _noteTimer;
  Timer? _pageTimer;
  final _note = TextEditingController();
  final _page = TextEditingController();
  bool _noteLoaded = false;

  /// 지우고 닫는 중: 화면이 닫히는 동안 지운 책 대신 마지막으로 보던 책을 그린다
  /// (2026-11-20 QA: 삭제 직후 닫히는 동안 '책을 찾을 수 없어요'가 잠깐 비쳤다)
  bool _leaving = false;
  MyBook? _lastBook;
  Edition? _lastEdition;
  BookReviewsState? _reviews; // 같은 판본(ISBN-13)의 공개 후기. 판본 ISBN을 고치면 새로 받는다
  String? _reviewsIsbn;

  /// 고른 탭 내용(책 정보·평가·내 기록) 자리
  final _paneKey = GlobalKey();

  BookReviewsState _reviewsOf(String? isbn13) {
    final r = _reviews;
    if (r != null && _reviewsIsbn == isbn13) return r;
    r?.dispose();
    _reviewsIsbn = isbn13;
    return _reviews = BookReviewsState(isbn13)..addListener(_changed);
  }

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    // 이 책을 재는 중이면 '지금 읽는 중' 줄과 단추가 바로 바뀌게
    ReadingStore.instance.addListener(_changed);
    _model.load();
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    ReadingStore.instance.removeListener(_changed);
    // 화면을 떠나도 적던 한 줄 감상 · 현재 쪽은 남긴다
    if (_noteTimer?.isActive ?? false) {
      _noteTimer!.cancel();
      _saveNote();
    }
    if (_pageTimer?.isActive ?? false) {
      _pageTimer!.cancel();
      _savePage();
    }
    _note.dispose();
    _page.dispose();
    _reviews?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String get id => widget.id;

  /// 책 공유: 비어 있는 항목을 눌러 돌아오면 그것을 적는 탭으로(평가 · 내 기록)
  Future<void> _share() async {
    final tab = await openBookShare(context, id);
    if (mounted && tab != null) _chooseTab(tab);
  }

  /// 탭을 바꾸면 그 내용 첫머리가 보이게 넘긴다(2026-11-16 QA 영숙 F5: 큰 글씨·작은 화면에서는 큰 표지가 화면을 채워 '평가'를 눌러도
  /// 바뀐 게 안 보였다). 첫머리가 이미 화면 위쪽에 보이면 그대로 둔다
  void _chooseTab(String v) {
    setState(() => _tab = v);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _paneKey.currentContext;
      final box = ctx?.findRenderObject();
      final pos = ctx == null ? null : Scrollable.maybeOf(ctx)?.position;
      final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
      if (!mounted || box == null || pos == null || viewport == null) return;
      final reveal = viewport.getOffsetToReveal(box, 0).offset;
      final shownAt = reveal - pos.pixels; // 내용 첫머리가 화면(스크롤 칸) 위에서 얼마나 아래에 있는지
      if (shownAt >= 0 && shownAt < pos.viewportDimension * 0.6) return;
      final target = (reveal - Space.xl).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        pos.jumpTo(target);
      } else {
        pos.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });
  }

  void _saveNote() {
    final t = _note.text.trim();
    _model.updateBook(id, note: t.isEmpty ? null : t);
  }

  /// 현재 쪽 저장(0 · 빈 값은 없음). 한줄평처럼 적는 대로 잠깐 뒤 저장한다(2026-11-19 공통 규칙 12장: 한 칸짜리 값은 바로 저장. 키보드 '완료'를 눌러야만 저장됐다)
  /// 마지막 쪽을 적어 완독이 되면(읽기 상태 · 현재 쪽 규칙) 상태를 완독으로 바꿀 때처럼 평가 칸으로(2026-11-24 사용자 5단계)
  void _savePage() {
    final n = num.tryParse(_page.text.trim());
    final next = n != null && n > 0 ? n.round() : null;
    if (next == _model.lib.books[id]?.currentPage) return;
    final wasRead = _model.lib.books[id]?.status == ReadStatus.read;
    _model.updateBook(id, currentPage: next).then((_) {
      if (mounted && !wasRead && _model.lib.books[id]?.status == ReadStatus.read) _chooseTab('rate');
    }, onError: (Object _) {});
  }

  void _chooseStatus(MyBook b, Round? last, ReadStatus s) {
    if (s == b.status) return;
    if ((s == ReadStatus.reading || s == ReadStatus.paused) && last?.finishedAt != null) {
      return _askReread(last!, () async {
        if (s == ReadStatus.paused) await _model.setStatus(id, ReadStatus.paused);
      });
    }
    _model.setStatus(id, s);
    // 완독으로 바꾸면 평가 칸으로(별점 · 한줄평을 바로 남기게, 2026-11-23 사용자)
    if (s == ReadStatus.read) _chooseTab('rate');
  }

  /// 다시 읽기 확인(완독한 책을 읽는 중 · 보류로 바꿀 때와 '다시 읽기' 단추가 같은 창): 새 회차를 만든 뒤 then
  void _askReread(Round last, Future<void> Function() then) {
    appAlert(context, '다시 읽기를 시작할까요?', '${last.index + 1}회차가 생기고 진도는 0쪽부터예요. 지난 회차의 완독일, 독서 기록, 갈피는 그대로 남아요.', [
      const AlertButton('취소', style: AlertStyle.cancel),
      AlertButton('다시 읽기', onPress: () async {
        await _model.reread(id);
        await then();
      }),
    ]);
  }

  /// 책 메뉴(지금 앱): 정보 수정·책장에서 보기·책장에서 빼기/진열·숨기기/삭제.
  /// 책 공유는 머리줄 아이콘, 책 꾸미기는 책 정보 칸 줄에 있어 메뉴에서 뺐다(2026-11-24 사용자 2단계).
  /// 숨긴 책(연도 책장에만 남은 책, 갈피 상세에서 들어올 수 있다)은 진열 · 숨기기 대신 '다시 보이기'(내 책 › 숨긴 책과 같은 일)
  Future<void> _menu() async {
    final place = PlacementStore.instance;
    await place.ensure();
    final years = (await archivedYears([id]))[id] ?? const <int>[];
    if (!mounted) return;
    final onShelf = place.layout != null && placementOf(place.layout!, id) != null;
    final hidden = _model.lib.books[id]?.hiddenAt != null;
    showSheet<void>(
      context,
      builder: (ctx) => ListGroup(children: [
        ListItem(label: '책 정보 수정', onPress: () {
          Navigator.pop(ctx);
          openEditBook(context, id);
        }),
        // 책을 옮기지 않고 책장에서 그 책을 비춰 보인다(2026-11-16 QA 영숙 F8: '이동'이라 자리를 옮기는 줄 알았다)
        if (onShelf)
          ListItem(label: '책장에서 보기', onPress: () {
            Navigator.pop(ctx);
            showBookOnShelf(context, id);
          }),
        // 책장에서 빼기는 배치만 푼다(책 정보·장정·독서 기록·갈피 그대로). 삭제(빨간 글자)는 책 데이터 자체를 지운다
        // 결과는 홈 책 시트와 같은 토스트 + 되돌리기(2026-11-19 공통 규칙: 확인창이었고 되돌릴 수 없었다)
        if (onShelf)
          ListItem(label: '책장에서 빼기', sub: '기록은 그대로, 내 책에 남아요', onPress: () async {
            Navigator.pop(ctx);
            final ok = await place.toDrawer(id);
            if (!mounted) return;
            if (!ok) {
              appAlert(context, '책장에서 빼지 못했어요', '잠시 뒤 다시 시도해 주세요.');
              return;
            }
            showToast(context, '책장에서 뺐어요. 내 책에 그대로 있어요.', action: '되돌리기', onAction: () => place.undo());
          })
        else if (!hidden)
          ListItem(label: '책장에 진열', onPress: () async {
            Navigator.pop(ctx);
            // 뺐던 책은 뺄 때 자리로 돌아간다(placement_store). 진열했는지·어디인지 토스트로 알린다(2026-11-16 QA 현우 F12: 화면이 그대로라 됐는지 몰랐다).
            // 한 권 진열은 바로 앞 배치 하나라 되돌릴 수 있다. 못 놓았으면(책장이 꽉 참 · 보관만 하기) 까닭과 할 일을 확인창으로
            final back = place.hadSpot(id);
            final r = await placeWithChoice(context, [id]);
            if (!mounted) return;
            if (r.placed > 0) {
              final spot = back && place.lastRestored == id;
              showToast(context, spot ? '뺄 때 있던 자리에 다시 진열했어요.' : '책장 빈 자리에 진열했어요.', action: '되돌리기', onAction: () => place.undo());
            } else if (r.kept > 0) {
              appAlert(context, keptTitle(full: r.full), keptNote(full: r.full));
            }
          }),
        if (hidden)
          ListItem(label: '다시 보이기', sub: '내 책 목록에 다시 보여요', onPress: () {
            Navigator.pop(ctx);
            _unhide();
          })
        else if (years.isNotEmpty)
          ListItem(label: '책 숨기기', sub: '${years.join(', ')}년 책장에는 남아요', onPress: () {
            Navigator.pop(ctx);
            _remove();
          })
        else
          ListItem(label: '책 삭제', sub: '갈피, 감상, 독서 회차까지 지워요', danger: true, onPress: () {
            Navigator.pop(ctx);
            _remove();
          }),
      ]),
    );
  }

  /// 숨긴 책 다시 보이기(내 책 › 숨긴 책과 같은 함수). 화면은 그대로 두고 토스트로 알린다
  Future<void> _unhide() async {
    final title = _model.lib.editions[_model.lib.books[id]?.editionId]?.title ?? '책';
    try {
      await unhideBook(id);
    } catch (e) {
      if (mounted) appAlert(context, '다시 보이게 하지 못했어요', errorText(e));
      return;
    }
    if (mounted) showToast(context, unhiddenText(title));
  }

  /// 책 삭제 · 숨기기(연도 책장에 있는 책은 지우지 않고 숨긴다, 2026-11-06 사용자 '삭제 말고 숨기기로'). 확인은 내 책 여러 권과 같은 시트(confirmRemoveBooks).
  /// 보고 있던 책이 사라지니 화면을 닫고 토스트로 알린다(2026-11-19 공통 규칙: 알림 없이 닫혔다). 탭 첫 화면까지 닫는다: 이 화면 아래에 지운 책의 갈피 · 감상이 열려 있을 수 있다
  Future<void> _remove() async {
    final title = _model.lib.editions[_model.lib.books[id]?.editionId]?.title;
    final r = await confirmRemoveBooks(context, [id]);
    if (r == null || !mounted) return;
    final nav = Navigator.of(context);
    _leaving = true;
    try {
      await removeBooks(r);
    } catch (e) {
      _leaving = false;
      if (mounted) appAlert(context, r.hidden.isNotEmpty ? '숨기지 못했어요' : '삭제하지 못했어요', errorText(e));
      return;
    }
    if (!mounted) return;
    showToast(context, removedText(r, title: title));
    nav.popUntil((route) => route.isFirst);
  }

  // 2026-11-19 build(약 400줄)를 책 정보 · 평가 · 내 기록 칸과 그 안 구역, 아래 단추로 나눴다(화면은 그대로)
  @override
  Widget build(BuildContext context) {
    final lib = _model.lib;
    final b0 = lib.books[id];
    final e0 = b0 == null ? null : lib.editions[b0.editionId];
    // 지우고 닫는 중이면 마지막으로 보던 책(_leaving)
    final b = b0 ?? (_leaving ? _lastBook : null);
    final e = e0 ?? (_leaving ? _lastEdition : null);
    if (b0 != null && e0 != null) {
      _lastBook = b0;
      _lastEdition = e0;
    }
    if (!_model.loaded) return const Screen(children: [Loading()]);
    if (b == null || e == null) {
      // 찾을 수 없음(docs/design/DESIGN.md 9장): 이유 + 나가는 단추 하나(뒤로와 같다. '책장으로'라 했지만 실제로는 이전 화면이었다)
      return Screen(title: '책 정보', children: [Empty(title: '책을 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop())]);
    }
    if (!_noteLoaded) {
      _note.text = b.note ?? '';
      _noteLoaded = true;
    }
    final rounds = roundsOf(lib, id);
    final last = rounds.isEmpty ? null : rounds.last;
    final reviews = _reviewsOf(e.isbn13);

    return Screen(
      // 머리줄 아이콘은 공용 HeadIcon(회색 · 사이 4, 2026-11-19 공통 규칙: 여기만 진한 색이었다)
      right: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(label: '책 공유', onPress: _share, child: const HeadIcon('Share')),
        const SizedBox(width: headIconGap),
        IconBtn(label: '더 보기', onPress: _menu, child: const HeadIcon('MoreHorizontal')),
      ]),
      footer: _footer(b, last),
      // 전환 칸은 위 줄 아래에 고정(스크롤하면 위 줄에 가려 잘렸다, 2026-11-18 사용자 '천장이 가리는 거 없애, 천장 고정')
      pinned: Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: SizedBox(width: 300, child: Segmented<String>(items: _views, value: _tab, onChange: _chooseTab)),
      ),
      children: [
        // 표지와 제목·지은이
        // 2026-11-17 시안에 맞춰 표지·간격을 줄였다(표지 170 → 140, 제목 24 → 22)
        Padding(
          padding: const EdgeInsets.only(top: Space.l + Space.s),
          child: Column(children: [
            BookVisual(lib: lib, id: id, width: CoverSize.head),
            // 위 줄에 제목이 없는 화면이라 책 제목을 화면 읽기 머리로(docs/design/DESIGN.md 15장)
            Padding(
              padding: const EdgeInsets.only(top: Space.l),
              child: Semantics(header: true, child: Text(e.title, textAlign: TextAlign.center, style: AppType.bookHeadTitle)),
            ),
            if (e.authors.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(authorLine(e.authors), textAlign: TextAlign.center, style: AppType.bookHeadAuthor)),
            // 숨긴 책이면 그렇다고 한 줄(메뉴에 '다시 보이기')
            if (b.hiddenAt != null) const NoticeText('숨긴 책이라 내 책 목록에는 보이지 않아요.', center: true),
            ReaderRating(data: reviews.data),
          ]),
        ),
        Padding(
          key: _paneKey,
          padding: const EdgeInsets.only(top: Space.l),
          child: switch (_tab) { 'rate' => _ratePane(lib, b, e, reviews), 'mine' => _minePane(lib, b, e, rounds), _ => _infoPane(lib, b, e) },
        ),
      ],
    );
  }

  /// 아래 두 단추: 갈피 남기기 · 읽기 시작(이어서 읽기 · 다시 읽기). 하나가 두 줄이 되면 높이를 맞춘다
  Widget _footer(MyBook b, Round? last) {
    // 이 책을 지금 재는 중이면 늘 '이어서 읽기'(장면으로 돌아간다)
    final live = ReadingStore.instance.active?.myBookId == b.id;
    final readLabel = live || b.status == ReadStatus.reading || b.status == ReadStatus.paused
        ? '이어서 읽기'
        : b.status == ReadStatus.read
            ? '다시 읽기'
            : '읽기 시작';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: Btn(label: '갈피 남기기', kind: 'secondary', size: 'xlarge', onPress: () => openNewBookmark(context, book: widget.id))),
        const SizedBox(width: Space.s),
        Expanded(
          child: Btn(
            label: readLabel,
            size: 'xlarge',
            // 그 책으로 바로 독서를 시작하고 읽기 화면을 연다(2026-11-16 QA 영숙 F2: 읽기 탭 목록에 올리기만 하고 시계가 가지 않았다)
            // 완독한 책의 '다시 읽기'는 새 회차를 먼저 묻는다(지난 회차에 이어 붙지 않게)
            // 완독한 책의 '다시 읽기' 확인은 읽기 시작 한 곳(confirmReread)이 묻는다. 재는 중이면 묻지 않고 장면으로(점검 B7)
            onPress: () => widget.onRead != null ? widget.onRead!(id) : unawaited(startReadingBook(context, id)),
          ),
        ),
      ]),
    );
  }

  /// 책 정보 칸: 출판 · ISBN · 쪽수 · 판형 · 도서 정보 · 책 꾸미기 · 판매처(책 꾸미기 줄은 2026-11-24 사용자 2단계: ⋯ 메뉴에 있었다. 갈피 색은 책 꾸미기 › 갈피)
  Widget _infoPane(Library lib, MyBook b, Edition e) {
    final pub = [?e.publisher, if (e.publishedAt != null && e.publishedAt!.length >= 4) e.publishedAt!.substring(0, 4)].where((x) => x.isNotEmpty).join(metaSep);
    final sized = e.widthMm != null && e.heightMm != null;
    return ListGroup(children: [
      ListItem(label: '출판', value: pub.isEmpty ? '미입력' : pub),
      ListItem(label: 'ISBN', value: e.isbn13 ?? '미입력'),
      ListItem(label: '쪽수', value: e.pageCount != null ? '${e.pageCount}쪽' : '미입력'),
      // 비어 있는 서지 값은 모두 '미입력'(2026-11-19 공통 규칙: 판형만 '확인 전'이었다)
      ListItem(label: '판형', value: sized ? '${e.widthMm}×${e.heightMm}mm' : '미입력', sub: sized ? null : '책장에는 기본 크기로 표시해요'),
      ListItem(label: '도서 정보', value: e.source == 'search' ? e.sourceName ?? '검색' : e.source == 'photo' ? '사진으로 추가' : '직접 입력'),
      ListItem(label: '책 꾸미기', chevron: true, onPress: () => openBindingEditor(context, id)),
      // 판매 페이지는 맨 아래(YES24 약관: 출처와 상품 링크를 함께 보인다). 앱 밖으로 나가는 줄도 꺾쇠, 열지 못하면 확인창(docs/design/DESIGN.md 10장)
      if (e.link != null) ListItem(label: '${e.sourceName ?? '판매처'}에서 보기', chevron: true, onPress: () => _openLink(e.link!)),
    ]);
  }

  Future<void> _openLink(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[link] $e');
    }
    if (!ok && mounted) appAlert(context, '페이지를 열지 못했어요', '잠시 뒤 다시 시도해 주세요.');
  }

  void _endNote() {
    _noteTimer?.cancel();
    _saveNote();
    FocusScope.of(context).unfocus();
    setState(() => _noteEdit = false);
  }

  /// 줄 안 입력칸(한줄평 · 현재 쪽): 입력 바탕 · 모서리 · 안쪽 좌우 16 위아래 12 · 높이 ControlSize.field(Field와 같다) · 갈색 커서 · 화면 읽기 이름을 한 곳에서
  /// (2026-11-19 공통 규칙: 쪽수 칸만 커서 색과 이름이 없었다)
  Widget _inlineInput({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextAlign textAlign = TextAlign.start,
    int? maxLength,
    int? maxLines = 1,
    ValueChanged<String>? onChanged,
    VoidCallback? onEditingComplete,
    ValueChanged<String>? onSubmitted,
  }) =>
      Container(
        constraints: const BoxConstraints(minHeight: ControlSize.field),
        decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(Shape.input)),
        child: Semantics(
          label: label,
          textField: true,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: maxLength,
            minLines: 1,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textAlign: textAlign,
            textInputAction: TextInputAction.done,
            style: AppType.input,
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              isCollapsed: true,
              counterText: '',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
              hintText: hint,
              hintStyle: AppType.input.copyWith(color: AppColors.inkFaint),
            ),
            onChanged: onChanged,
            onEditingComplete: onEditingComplete,
            onSubmitted: onSubmitted,
          ),
        ),
      );

  // 평가 칸(2026-11-17 사용자 시안): 별은 표지·제목·저자 아래 가운데, 그 아래 '한줄평'(오른쪽 수정)과 '감상 N'(오른쪽 쓰기).
  // 한줄평은 회색 상자 없이 글만 두고 '수정'을 누르면 그 자리에서 고친다. 별점·한줄평은 나만 본다. 구역 머리줄은 공용 SectionHead
  Widget _ratePane(Library lib, MyBook b, Edition e, BookReviewsState reviews) {
    final note = (b.note ?? '').trim();
    final essays = _model.essaysOf(id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Semantics(label: '내 별점, 나만 봐요', child: Stars(value: b.rating, onChange: (v) => _model.updateBook(id, rating: v)))),
      // 별점 아래 28 → 16(2026-11-24 사용자: 한줄평 제목 줄 48 안 빈 자리까지 더하면 별과 제목이 멀었다)
      const SizedBox(height: Space.l),
      SectionHead(
        title: '한줄평',
        link: _noteEdit ? '완료' : (note.isEmpty ? '쓰기' : '수정'),
        onLink: () {
          if (_noteEdit) {
            _endNote();
          } else {
            _note.text = b.note ?? '';
            setState(() => _noteEdit = true);
          }
        },
      ),
      if (_noteEdit)
        // 여러 줄로 다 보인다(2026-11-16 QA 영숙 F15). 줄바꿈은 넣지 않고 완료로 닫는다.
        // 적는 대로 잠깐 뒤 저장한다(입력 중에 칸을 바꾸거나 화면을 떠나도 남게)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: _inlineInput(
            label: '한줄평',
            controller: _note,
            hint: '이 책은 나에게…',
            maxLength: 140,
            maxLines: null,
            onChanged: (_) {
              _noteTimer?.cancel();
              _noteTimer = Timer(const Duration(milliseconds: 600), _saveNote);
            },
            onEditingComplete: _endNote,
          ),
        )
      // 비어 있으면 안내 없이 머리 '쓰기'만(DESIGN 11장: 구역 머리에 할 일이 보이면 빈 줄을 두지 않는다)
      else if (note.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText(note, style: AppType.review)),
      const SizedBox(height: Space.block),
      // 감상(기록 › 감상과 같은 데이터, 이 책 것만)
      SectionHead(title: '감상', count: essays.isEmpty ? null : '${essays.length}개', link: '쓰기', onLink: () => openNewEssay(context, book: id)),
      // 비어 있으면 머리 '쓰기'만(DESIGN 11장)
      if (essays.isNotEmpty)
        for (final (i, x) in essays.indexed) ...[if (i > 0) const AppDivider(), EssayRow(key: ValueKey(x.id), lib: lib, essay: x, showBook: false, compact: true)],
      if (reviews.available) ...[
        const SectionBand(),
        Padding(padding: const EdgeInsets.only(top: Space.xl), child: ReviewsPane(title: e.title, myRating: b.rating, state: reviews)),
      ],
    ]);
  }

  void _pickStatus(MyBook b, Round? last) => showSheet<void>(
        context,
        title: '읽기 상태',
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final st in bookStatuses)
            FilterOption(
              label: statusLabel[st]!,
              selected: b.status == st,
              onPress: () {
                Navigator.of(ctx).pop();
                _chooseStatus(b, last, st);
              },
            ),
        ]),
      );

  /// 쪽수 숫자를 누르면 칸을 열고, 다시 누르면 적던 값을 저장하고 닫는다(버려졌다)
  void _togglePage(MyBook b) {
    if (_pageEdit) return _endPage();
    setState(() {
      _pageEdit = true;
      _page.text = b.currentPage != null && b.currentPage != 0 ? '${b.currentPage}' : '';
    });
  }

  void _endPage() {
    _pageTimer?.cancel();
    _savePage();
    FocusScope.of(context).unfocus();
    setState(() => _pageEdit = false);
  }

  // 내 기록 칸(2026-11-17 사용자 시안): 위에 읽기 상태(누르면 고르는 시트)와 쪽수, 진행 막대와 %,
  // 그 아래 최근 독서 기록(날짜·시간대·걸린 시간, 전체 보기는 통계). 읽은 기간(회차)과 남긴 갈피는 그 아래 그대로
  Widget _minePane(Library lib, MyBook b, Edition e, List<Round> rounds) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ..._progress(b, e, rounds.isEmpty ? null : rounds.last),
        const SizedBox(height: Space.block),
        ..._sessions(lib),
        const SizedBox(height: Space.block),
        ..._rounds(rounds),
        const SizedBox(height: Space.block),
        ..._marks(lib),
      ]);

  /// 읽기 상태 · 현재 쪽 · 진행 막대(전체 쪽수를 모르면 한 줄 안내) · 쪽수 고치기 칸
  List<Widget> _progress(MyBook b, Edition e, Round? last) {
    final pc = e.pageCount;
    final cur = b.currentPage ?? 0;
    final pct = pc != null && pc > 0 ? ((cur / pc).clamp(0.0, 1.0) * 100).round() : null;
    void pick() => _pickStatus(b, last);
    void toggle() => _togglePage(b);
    // 지금 이 책을 재는 중이면 '읽기 전'이어도 '읽는 중'으로 보인다(기록을 저장하면 그대로 읽는 중이 된다. 시작만 하고 버리면 원래대로)
    final shown = ReadingStore.instance.active?.myBookId == b.id && b.status == ReadStatus.want ? ReadStatus.reading : b.status;
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Semantics(
          button: true,
          label: '읽기 상태 ${statusLabel[shown]}, 바꾸기',
          onTap: pick,
          excludeSemantics: true,
          child: Pressable(
            onPress: pick,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Space.hit),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(statusLabel[shown]!, style: AppType.rowStrong.copyWith(color: AppColors.accent)),
                const SizedBox(width: Space.xs),
                const LucideIcon('ChevronDown', size: 20, color: AppColors.accent, stroke: 2),
              ]),
            ),
          ),
        ),
        const SizedBox(width: Space.m),
        Expanded(
          child: Semantics(
            button: true,
            label: '현재 쪽 $cur${pc != null ? ' / $pc쪽' : '쪽'}, 눌러서 수정',
            onTap: toggle,
            excludeSemantics: true,
            child: Pressable(
              onPress: toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Space.hit),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text.rich(TextSpan(
                    text: '$cur',
                    style: AppType.figure,
                    children: [TextSpan(text: pc != null ? ' / $pc쪽' : '쪽', style: AppType.body.copyWith(color: AppColors.inkSoft))],
                  )),
                ),
              ),
            ),
          ),
        ),
      ]),
      // 쪽수 진행 막대와 오른쪽 %(2026-11-18 사용자 시안: '% 바 옆에'). 전체 쪽수를 모르면 막대 대신 한 줄 안내
      Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: pc != null && pc > 0
            ? Row(children: [
                Expanded(child: ProgressBar(value: (cur / pc).toDouble(), soft: true)),
                const SizedBox(width: Space.m),
                // '100%'가 들어갈 폭으로 고정: 진행이 늘어 자릿수가 바뀌어도 막대 길이가 그대로(2026-11-18 사용자 '100% 기준으로')
                Stack(alignment: Alignment.centerRight, children: [
                  Opacity(opacity: 0, child: Text('100%', style: AppType.caption.tnum)),
                  Text('$pct%', style: AppType.caption.tnum),
                ]),
              ])
            : Text('전체 쪽수 미입력', style: AppType.caption),
      ),
      if (_pageEdit)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: _inlineInput(
            label: '현재 쪽',
            controller: _page,
            hint: '읽은 쪽수',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            // 적는 대로 잠깐 뒤 저장(한줄평과 같은 방식). 키보드 '완료'는 저장하고 닫는다
            onChanged: (_) {
              _pageTimer?.cancel();
              _pageTimer = Timer(const Duration(milliseconds: 600), _savePage);
            },
            onSubmitted: (_) => _endPage(),
          ),
        ),
    ];
  }

  /// 최근 독서 기록: 날짜 · 시간대 · 걸린 시간(누르면 고치기), 전체는 통계에서
  List<Widget> _sessions(Library lib) {
    final recent = lib.sessions.values.where((x) => x.myBookId == id).toList()..sort((a, c) => c.startedAt.compareTo(a.startedAt));
    final readMs = bookReadMs(lib, id);
    final done = completions(lib, id);
    // 지금 재는 독서(저장 전): 맨 위에 '지금 읽는 중 · 시작 시각부터' + 흐르는 시간. 누르면 읽기 장면으로(2026-11-19 사용자 '타이머 읽었는데 바로 기록이 안 돼')
    final act = ReadingStore.instance.active;
    final live = act != null && act.myBookId == id ? act : null;
    return [
      // 머리 오른쪽 '추가'(타이머 없이 읽은 시간을 이 책으로, 2026-11-23 사용자) · '전체 보기'(기록이 있을 때)
      SectionHead(
        title: '독서 기록',
        extra: '추가',
        onExtra: () => openSessionAdd(context, bookId: id),
        link: recent.isNotEmpty ? '전체 보기' : null,
        chevron: true,
        linkLabel: '독서 기록 전체 보기',
        onLink: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsScreen(tab: false, initialBook: id))),
      ),
      // 횟수·총 시간은 '독서 기록' 아래 한 줄(2026-11-18 사용자 시안: '9회, 총 41분' — 쉼표는 사용자 예외)
      if (recent.isNotEmpty || readMs > 0)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text([if (recent.isNotEmpty) '${recent.length}회', '총 ${formatDuration(readMs)}', if (done > 0) '완독 $done회'].join(', '), style: AppType.sub),
        ),
      if (live != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Semantics(
            button: true,
            label: '지금 읽는 중, ${timeLabel(DateTime.parse(live.startedAt))}부터, 읽기 화면으로',
            excludeSemantics: true,
            onTap: () => startReadingBook(context, id),
            child: Pressable(
              onPress: () => startReadingBook(context, id),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Space.dense),
                child: Row(children: [
                  Expanded(child: MetaText(['지금 읽는 중', '${timeLabel(DateTime.parse(live.startedAt))}부터'].join(metaSep), style: AppType.sub)),
                  ElapsedTicker(running: live.runningSince != null, builder: (ms) => Text(clock(ms), style: AppType.row.tnum)),
                ]),
              ),
            ),
          ),
        ),
      if (recent.isEmpty && live == null)
        const EmptyLine('타이머로 읽으면 여기에 쌓여요')
      else
        // 같은 날짜는 묶고(날짜 한 줄 아래 시간대는 연하게, 읽은 시간은 오른쪽에 진하게), 구분선 없이 날짜 사이 여백으로(2026-11-17 시안). 최근 5개
        for (final g in _byDay(recent.take(5).toList()))
          Padding(
            // 머리–첫 날짜 8 → 12(2026-11-18 사용자 '줄 위치가 좀 더 밑으로': 시안은 머리와 첫 날짜 사이가 더 넓다)
            padding: const EdgeInsets.only(top: Space.m),
            // 그날 기록이 하나면 날짜 · 시간대 두 줄을 한 줄로 누르고, 읽은 시간은 두 줄 세로 가운데(DESIGN 7장 '두 줄 줄의 오른쪽 값',
            // 2026-11-20 사용자 '20분 같은 시간은 11월 9일이랑 그 밑에 오후 라인 중앙'). 여럿이면 날짜 아래 시간대 줄마다 오른쪽에
            child: g.items.length == 1
                ? Semantics(
                    button: true,
                    label: '${g.day}, ${timeRange(g.items.first.startedAt, g.items.first.endedAt)}, ${formatDuration(g.items.first.durationMs)}, 수정',
                    excludeSemantics: true,
                    onTap: () => openSessionEdit(context, g.items.first.id),
                    child: Pressable(
                      onPress: () => openSessionEdit(context, g.items.first.id),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.day, style: AppType.recordDay),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: Space.dense),
                              child: Align(alignment: Alignment.centerLeft, child: Text(timeRange(g.items.first.startedAt, g.items.first.endedAt), style: AppType.recordRange)),
                            ),
                          ]),
                        ),
                        Text(formatDuration(g.items.first.durationMs), style: AppType.recordDuration),
                      ]),
                    ),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(header: true, child: Text(g.day, style: AppType.recordDay)),
              for (final x in g.items)
                Semantics(
                  button: true,
                  label: '${g.day}, ${timeRange(x.startedAt, x.endedAt)}, ${formatDuration(x.durationMs)}, 수정',
                  excludeSemantics: true,
                  onTap: () => openSessionEdit(context, x.id),
                  child: Pressable(
                    onPress: () => openSessionEdit(context, x.id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: Space.dense),
                      child: Row(children: [
                        // 다른 화면 기록 줄과 같은 역할(시간대 recordRange 13 · 읽은 시간 recordDuration 15, 2026-11-24 구역 제목 17보다 한 단계 작게)
                        Expanded(child: Text(timeRange(x.startedAt, x.endedAt), style: AppType.recordRange)),
                        // 읽은 시간은 위 날짜('11월 17일')와 같은 글자(2026-11-18 사용자 '20분 글씨체 너무 두껍다')
                        Text(formatDuration(x.durationMs), style: AppType.recordDuration),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
    ];
  }

  /// 읽은 기간(회차, 2026-11-17 사용자 시안): 테두리 카드에 'N회차'·상태, 시작일·완독일. 오른쪽 '수정'을 누르면 그 자리에서 날짜를 고른다
  List<Widget> _rounds(List<Round> rounds) => [
        SectionHead(title: '읽은 기간', link: rounds.isEmpty ? null : (_roundEdit ? '완료' : '수정'), onLink: () => setState(() => _roundEdit = !_roundEdit)),
        if (rounds.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: Space.s), child: Column(children: [
            for (final r in rounds)
              _roundEdit
                  ? _RoundCard(key: ValueKey('${r.id}|${r.startedAt}|${r.finishedAt}'), round: r, onSave: (s, f) => _model.updateRound(r.id, startedAt: s, finishedAt: f))
                  : _RoundView(round: r),
          ]))
        else
          // 재는 중이면 저장할 때 1회차가 생긴다고 알려 준다(시작만 하고 버리면 회차를 남기지 않는다). 빈 구역은 공용 EmptyLine
          EmptyLine(ReadingStore.instance.active?.myBookId == id ? '지금 읽는 중이에요. 기록을 저장하면 1회차가 생겨요.' : '읽기 시작하면 회차가 생겨요'),
      ];

  /// 남긴 갈피: 제목 옆 작은 회색 개수(감상과 같은 모양: 0이면 개수 없이). 없으면 다른 빈 구역과 같은 왼쪽 한 줄(2026-11-19 공통 규칙: 가운데 · 위아래 40이었다).
  /// 전체는 '독서 기록'과 같은 구역 머리 링크 '전체 보기'(갈피 보드, 2026-11-19 공통 규칙: 아래 보조 단추였다)
  List<Widget> _marks(Library lib) {
    final marks = bookmarksOf(lib, id);
    return [
      SectionHead(
        title: '남긴 갈피',
        count: marks.isEmpty ? null : '${marks.length}개',
        link: marks.isNotEmpty ? '전체 보기' : null,
        chevron: true,
        linkLabel: '남긴 갈피 전체 보기, 갈피 보드',
        onLink: () => openBookmarkBoard(context, id),
      ),
      if (marks.isNotEmpty) ...[
        ListGroup(children: [
          for (final m in marks.take(5))
            Semantics(
              button: true,
              label: [m.text.trim().isNotEmpty ? m.text.trim() : '사진 갈피', if (m.page != null && m.page != 0) '${m.page}쪽', dateShort(m.createdAt)].join(', '),
              excludeSemantics: true,
              onTap: () => openBookmark(context, m.id),
              child: Pressable(
                onPress: () => openBookmark(context, m.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.l),
                  // 글은 늘 왼쪽 끝에서 시작하고 사진은 오른쪽에, 한글은 낱말 단위로 줄을 바꾼다
                  // (2026-11-16 QA 은서 F12: 사진 갈피는 썸네일 오른쪽, 문장 갈피는 왼쪽 끝에서 시작해 들쭉날쭉했고 '앉/아'처럼 끊겼다)
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // 사진만 남긴 갈피는 글이 없다: '사진 갈피'로 보인다
                        if (m.text.trim().isNotEmpty)
                          WordText(m.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.quote)
                        else
                          Text('사진 갈피', style: AppType.row),
                        Padding(
                          padding: const EdgeInsets.only(top: Space.s),
                          child: MetaText([if (m.page != null && m.page != 0) '${m.page}쪽', dateShort(m.createdAt)].where((x) => x.isNotEmpty).join(metaSep), style: AppType.caption),
                        ),
                      ]),
                    ),
                    if (m.photoUri != null && m.photoUri!.isNotEmpty) ...[
                      const SizedBox(width: Space.m),
                      ClipRRect(borderRadius: BorderRadius.circular(Shape.cover), child: Container(width: 48, height: 64, color: AppColors.surface, child: BookmarkPhoto(uri: m.photoUri!))),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      ] else
        const EmptyLine('아직 남긴 갈피가 없어요'),
    ];
  }
}

/// 회차 하나(보기): 테두리 카드 안 '1회차'·오른쪽 상태, 시작일·완독일(dateLong '2026년 11월 14일', 없으면 —)
class _RoundView extends StatelessWidget {
  const _RoundView({required this.round});
  final Round round;

  @override
  Widget build(BuildContext context) {
    final r = round;
    String day(String? x) => x != null && isDay(x) ? dateLong(x) : '—';
    Widget col(String label, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppType.caption),
          const SizedBox(height: 2),
          Text(v, style: AppType.label.tnum),
        ]);
    return Semantics(
      container: true,
      label: '${r.index}회차, ${r.finishedAt != null ? '완독' : r.paused ? '보류' : '읽는 중'}, 시작일 ${day(r.startedAt)}, 완독일 ${r.finishedAt != null ? day(r.finishedAt) : '없음'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: OutlineBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: MetaText(['${r.index}회차', if (r.index > 1) '재독'].join(metaSep), style: AppType.labelStrong)),
            Text(r.finishedAt != null ? '완독' : r.paused ? '보류' : '읽는 중', style: AppType.caption),
          ]),
          // 글자 크기는 시안과 같고 줄 사이가 넓어 밀려 보였다(2026-11-18 사용자): 12 → 8, 이름–값 4 → 2
          const SizedBox(height: Space.s),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: col('시작일', day(r.startedAt))),
            const SizedBox(width: Space.m),
            Expanded(child: col('완독일', day(r.finishedAt))),
          ]),
        ])),
      ),
    );
  }
}

/// 회차 하나(고치기): 위 구분선 + '1회차 · 읽는 중' + 시작일·완독일(달력 고르기). 완독일은 시작일 이후·시작일은 완독일 이전만 고를 수 있다
class _RoundCard extends StatelessWidget {
  const _RoundCard({super.key, required this.round, required this.onSave});
  final Round round;
  final void Function(Object? startedAt, Object? finishedAt) onSave;

  @override
  Widget build(BuildContext context) {
    final r = round;
    final s = r.startedAt != null && isDay(r.startedAt!) ? r.startedAt! : '';
    final f = r.finishedAt != null && isDay(r.finishedAt!) ? r.finishedAt! : '';
    final today = todayKey();
    const keep = Object();
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.only(top: Space.xl),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: Hairline.of(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // '2회차 | 재독'은 옅은 세로줄(MetaText), 상태는 띄어 쓴 칸 대신 간격 12(2026-11-19 공통 규칙)
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          MetaText(['${r.index}회차', if (r.index > 1) '재독'].join(metaSep), style: AppType.rowStrong),
          const SizedBox(width: Space.m),
          Flexible(child: Text(r.finishedAt != null ? '완독' : r.paused ? '보류' : '읽는 중', style: AppType.sub)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: DateField(label: '시작일', value: s, max: f.isNotEmpty ? f : today, clearable: true, onChange: (v) => onSave(v.isEmpty ? null : v, keep)),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: DateField(
                label: '완독일',
                value: f,
                min: s.isNotEmpty ? s : null,
                max: today,
                placeholder: '완독하면',
                disabled: r.finishedAt == null,
                onChange: (v) {
                  if (v.isNotEmpty) onSave(keep, v);
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// 독서 기록을 날짜별로 묶는다(최근 날짜부터, 들어온 순서 그대로). 날짜는 목록 날짜 dateShort(올해가 아니면 연도까지, 2026-11-19 공통 규칙: 연도 없이 썼다)
List<({String day, List<Session> items})> _byDay(List<Session> list) {
  final out = <({String day, List<Session> items})>[];
  for (final x in list) {
    final d = dateShort(x.startedAt);
    if (out.isNotEmpty && out.last.day == d) {
      out.last.items.add(x);
    } else {
      out.add((day: d, items: [x]));
    }
  }
  return out;
}
