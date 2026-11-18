// 책 정보(지금 앱 app/book/[id]/index.tsx): 표지 위 가운데 전환 칸 [책 정보 | 평가 | 내 기록]. 이어서 읽기와 갈피 남기기는 아래에 늘 보인다.
// 날짜·쪽수·별점은 모두 선택 입력. 완독 여부는 사용자가 정한다(타이머로 자동 판정하지 않는다).
// 완독한 책을 '읽는 중'·'보류'로 바꾸면 새 회차(다시 읽기)라 먼저 묻는다
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:url_launcher/url_launcher.dart';

import '../../domain/color.dart';
import '../../domain/library.dart';
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/book_visual.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/book_picker.dart' show statusLabel;
import '../bookmark/bookmark_detail_screen.dart' show openBookmark;
import '../bookmark/bookmark_card.dart' show hexColor;
import '../bookmark/photo_plate.dart' show BookmarkPhoto;
import '../bookmark/ribbon_color_sheet.dart';
import '../stats/chart_data.dart' show timeRange;
import '../stats/session_edit_screen.dart' show openSessionEdit;
import '../stats/stats_screen.dart';
import 'labels.dart';
import '../bookmark/new_bookmark_screen.dart';
import '../../domain/layout.dart' show placementOf;
import '../../store/library_store.dart' show archivedYears;
import '../../store/placement_store.dart';
import '../home/home_screen.dart' show showBookOnShelf;
import 'all_books.dart' show deleteNote, deleteSummary;
import '../bookmark/board_screen.dart' show openBookmarkBoard;
import 'binding_screen.dart' show openBindingEditor;
import 'book_share_screen.dart' show openBookShare;
import 'edit_book_screen.dart' show openEditBook;
import 'place_books.dart' show keptNote, keptTitle, placeWithChoice;
import '../community/book_reviews.dart';
import '../record/essay_screens.dart' show EssayRow, openNewEssay;
import '../reading/start_book.dart' show startReadingBook;

const _views = [('info', '책 정보'), ('rate', '평가'), ('mine', '내 기록')];
const _statuses = [ReadStatus.want, ReadStatus.reading, ReadStatus.read, ReadStatus.paused];

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
  String _tab = 'info';
  bool _pageEdit = false;
  bool _noteEdit = false; // 평가 탭 한줄평을 고치는 중
  bool _roundEdit = false; // 내 기록 탭 읽은 기간 날짜를 고치는 중
  Timer? _noteTimer;
  final _note = TextEditingController();
  final _page = TextEditingController();
  bool _noteLoaded = false;
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
    _model.load();
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    // 화면을 떠나도 적던 한 줄 감상은 남긴다
    if (_noteTimer?.isActive ?? false) {
      _noteTimer!.cancel();
      _saveNote();
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

  void _chooseStatus(MyBook b, Round? last, ReadStatus s) {
    if (s == b.status) return;
    if ((s == ReadStatus.reading || s == ReadStatus.paused) && last?.finishedAt != null) {
      appAlert(context, '다시 읽기를 시작할까요?', '${last!.index + 1}회차가 생기고 진도는 0쪽부터예요. 지난 회차의 완독일, 독서 기록, 갈피는 그대로 남아요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('다시 읽기', onPress: () async {
          await _model.reread(id);
          if (s == ReadStatus.paused) await _model.setStatus(id, ReadStatus.paused);
        }),
      ]);
      return;
    }
    _model.setStatus(id, s);
  }

  /// 책 메뉴(지금 앱): 공유·정보 수정·장정 편집·책장에서 보기·책장에서 빼기/진열·숨기기/삭제
  Future<void> _menu() async {
    final place = PlacementStore.instance;
    await place.ensure();
    final years = (await archivedYears([id]))[id] ?? const <int>[];
    if (!mounted) return;
    final onShelf = place.layout != null && placementOf(place.layout!, id) != null;
    showSheet<void>(
      context,
      builder: (ctx) => ListGroup(children: [
        ListItem(label: '이미지로 공유', sub: '한줄평, 별점을 넣은 카드', onPress: () {
          Navigator.pop(ctx);
          _share();
        }),
        ListItem(label: '책 정보 수정', onPress: () {
          Navigator.pop(ctx);
          openEditBook(context, id);
        }),
        ListItem(label: '장정 편집', onPress: () {
          Navigator.pop(ctx);
          openBindingEditor(context, id);
        }),
        // 책을 옮기지 않고 책장에서 그 책을 비춰 보인다(2026-11-16 QA 영숙 F8: '이동'이라 자리를 옮기는 줄 알았다)
        if (onShelf)
          ListItem(label: '책장에서 보기', onPress: () {
            Navigator.pop(ctx);
            showBookOnShelf(context, id);
          }),
        // 책장에서 빼기는 배치만 푼다(책 정보·장정·독서 기록·갈피 그대로). 삭제(빨간 글자)는 책 데이터 자체를 지운다
        if (onShelf)
          ListItem(label: '책장에서 빼기', sub: '기록은 그대로, 내 책에 남아요', onPress: () async {
            Navigator.pop(ctx);
            if (await place.toDrawer(id) && mounted) appAlert(context, '책장에서 뺐어요. 내 책에 그대로 있어요.');
          })
        else
          ListItem(label: '책장에 진열', onPress: () async {
            Navigator.pop(ctx);
            // 뺐던 책은 뺄 때 자리로 돌아간다(placement_store). 진열했는지·어디인지 알린다(2026-11-16 QA 현우 F12: 화면이 그대로라 됐는지 몰랐다)
            final back = place.hadSpot(id);
            final r = await placeWithChoice(context, [id]);
            if (!mounted) return;
            if (r.placed > 0) {
              final spot = back && place.lastRestored == id;
              appAlert(context, '책장에 진열했어요', spot ? '뺄 때 있던 자리에 다시 진열했어요.' : '빈 자리에 진열했어요. 꾸미기에서 자리를 옮길 수 있어요.', [
                const AlertButton('확인', style: AlertStyle.cancel),
                AlertButton('책장에서 보기', onPress: () => showBookOnShelf(context, id)),
              ]);
            } else if (r.kept > 0) {
              appAlert(context, keptTitle(full: r.full), keptNote(full: r.full));
            }
          }),
        if (years.isNotEmpty)
          ListItem(label: '책 숨기기', sub: '${years.join(', ')}년 책장에는 남아요', onPress: () {
            Navigator.pop(ctx);
            _confirmDelete(years);
          })
        else
          ListItem(label: '책 삭제', sub: '갈피, 감상, 독서 회차까지 지워요', danger: true, onPress: () {
            Navigator.pop(ctx);
            _confirmDelete(years);
          }),
      ]),
    );
  }

  /// 연도 책장에 있는 책은 지우지 않고 숨긴다(2026-11-06 사용자 '삭제 말고 숨기기로').
  /// 여러 권 삭제(내 책 › 선택)와 같은 아래 시트: 표지와 제목, 무엇이 지워지고 남는지, 위 [삭제] 아래 '취소'
  /// (2026-11-16 QA 현우 F5: 한 권 삭제만 가운데 창에 책 이름이 없고 버튼 자리가 달랐다)
  Future<void> _confirmDelete(List<int> years) async {
    final hide = years.isNotEmpty;
    final lib = _model.lib;
    final title = lib.editions[lib.books[id]?.editionId]?.title ?? '이 책';
    final ok = await showSheet<bool>(
      context,
      title: hide ? '이 책을 숨길까요?' : '이 책을 삭제할까요?',
      description: hide ? '지금 책장과 책 목록에서 빠지고, ${years.join(', ')}년 책장에는 그대로 남아요.' : null,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.xs, bottom: Space.l),
          child: Column(children: [
            ExcludeSemantics(child: SizedBox(width: 56, child: BookVisual(lib: lib, id: id, width: 56))),
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: WordText(title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
            ),
          ]),
        ),
        WordText(hide ? '내 책 › 필터 › 숨긴 책 보기에서 다시 꺼낼 수 있어요.' : deleteNote(deleteSummary(lib, [id])), style: AppType.sub),
        const SizedBox(height: Space.l),
        Btn(label: hide ? '숨기기' : '삭제', kind: hide ? 'primary' : 'danger', size: 'l', onPress: () => Navigator.pop(ctx, true)),
        SubAction(label: '취소', onPress: () => Navigator.pop(ctx, false)),
      ]),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await _model.deleteBook(id, archived: hide);
    await PlacementStore.instance.forget([id]);
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final lib = _model.lib;
    final b = lib.books[id];
    final e = b == null ? null : lib.editions[b.editionId];
    if (!_model.loaded) return const Screen(children: [Loading()]);
    if (b == null || e == null) {
      return Screen(title: '책', children: [Empty(title: '책을 찾을 수 없어요', body: '삭제되었거나 예시 책장 책이에요.', action: '책장으로', onAction: () => Navigator.of(context).popUntil((r) => r.isFirst))]);
    }
    if (!_noteLoaded) {
      _note.text = b.note ?? '';
      _noteLoaded = true;
    }
    final rounds = roundsOf(lib, id);
    final marks = bookmarksOf(lib, id);
    final readMs = bookReadMs(lib, id);
    final sessions = lib.sessions.values.where((s) => s.myBookId == id).length;
    final done = completions(lib, id);
    final pub = [?e.publisher, if (e.publishedAt != null && e.publishedAt!.length >= 4) e.publishedAt!.substring(0, 4)].where((x) => x.isNotEmpty).join(' | ');
    final last = rounds.isEmpty ? null : rounds.last;
    final reviews = _reviewsOf(e.isbn13);
    final essays = _model.essaysOf(id);
    final hair = 1 / MediaQuery.devicePixelRatioOf(context);
    final readLabel = b.status == ReadStatus.reading || b.status == ReadStatus.paused
        ? '이어서 읽기'
        : b.status == ReadStatus.read
            ? '다시 읽기'
            : '읽기 시작';

    Widget infoPane() => ListGroup(children: [
          ListItem(label: '출판', value: pub.isEmpty ? '미입력' : pub),
          ListItem(label: 'ISBN', value: e.isbn13 ?? '미입력'),
          ListItem(label: '쪽수', value: e.pageCount != null ? '${e.pageCount}쪽' : '미입력'),
          ListItem(
            label: '판형',
            value: e.widthMm != null && e.heightMm != null ? '${e.widthMm}×${e.heightMm}mm' : '확인 전',
            sub: e.widthMm != null && e.heightMm != null ? null : '책장에는 기본 크기로 표시해요',
          ),
          ListItem(label: '도서 정보', value: e.source == 'search' ? e.sourceName ?? '검색' : e.source == 'photo' ? '사진으로 추가' : '직접 입력'),
          ListItem(
            label: '갈피 색',
            sub: b.ribbonColor != null ? '직접 고른 색' : '표지에서 고른 색',
            onPress: () => showRibbonColorSheet(context, id),
            right: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hexColor(paperColors(ribbonOf(lib, id), id).tape),
                border: Border.all(color: AppColors.line, width: hair * 2),
              ),
            ),
          ),
          // 판매 페이지는 맨 아래(YES24 약관: 출처와 상품 링크를 함께 보인다)
          if (e.link != null) ListItem(label: '${e.sourceName ?? '판매처'}에서 보기', onPress: () => launchUrl(Uri.parse(e.link!), mode: LaunchMode.externalApplication)),
        ]);

    // 평가 탭(2026-11-17 사용자 시안): 별은 표지·제목·저자 아래 가운데, 그 아래 '한줄평'(오른쪽 수정)과 '감상 N'(오른쪽 쓰기).
    // 한줄평은 회색 상자 없이 글만 두고 '수정'을 누르면 그 자리에서 고친다. 별점·한줄평은 나만 본다
    // 구역 머리줄은 공용 SectionHead(제목 · 회색 개수 · 오른쪽 글자 단추)
    Widget sectionHead(String title, String? link, VoidCallback? onLink, {String? count}) => SectionHead(title: title, count: count, link: link, onLink: onLink);
    void endNote() {
      _noteTimer?.cancel();
      _saveNote();
      FocusScope.of(context).unfocus();
      setState(() => _noteEdit = false);
    }
    final note = (b.note ?? '').trim();
    Widget ratePane() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Semantics(label: '내 별점, 나만 봐요', child: Stars(value: b.rating, onChange: (v) => _model.updateBook(id, rating: v)))),
          const SizedBox(height: Space.xl),
          sectionHead('한줄평', _noteEdit ? '완료' : (note.isEmpty ? '쓰기' : '수정'), () {
            if (_noteEdit) {
              endNote();
            } else {
              _note.text = b.note ?? '';
              setState(() => _noteEdit = true);
            }
          }),
          const SizedBox(height: 6),
          if (_noteEdit)
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(Shape.input)),
              child: Semantics(
                label: '한줄평',
                textField: true,
                // 여러 줄로 다 보인다(2026-11-16 QA 영숙 F15). 줄바꿈은 넣지 않고 완료로 닫는다
                child: TextField(
                  controller: _note,
                  autofocus: true,
                  maxLength: 140,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  style: AppType.input,
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    hintText: '이 책은 나에게…',
                    hintStyle: AppType.input.copyWith(color: AppColors.inkFaint),
                  ),
                  // 적는 대로 잠깐 뒤 저장한다(입력 중에 칸을 바꾸거나 화면을 떠나도 남게)
                  onChanged: (_) {
                    _noteTimer?.cancel();
                    _noteTimer = Timer(const Duration(milliseconds: 600), _saveNote);
                  },
                  onEditingComplete: endNote,
                ),
              ),
            )
          else
            WordText(note.isEmpty ? '이 책을 한 줄로 남겨 보세요' : note, style: note.isEmpty ? AppType.sub.copyWith(color: AppColors.inkFaint) : AppType.body),
          const SizedBox(height: Space.block),
          // 감상(기록 › 감상과 같은 데이터, 이 책 것만)
          sectionHead('감상', '쓰기', () => openNewEssay(context, book: id), count: essays.isEmpty ? null : '${essays.length}개'),
          if (essays.isEmpty)
            Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText('이 책을 읽고 든 생각을 길게 남겨요', style: AppType.sub))
          else
            for (final (i, x) in essays.indexed) ...[if (i > 0) const AppDivider(), EssayRow(key: ValueKey(x.id), lib: lib, essay: x, showBook: false, compact: true)],
          if (reviews.available) ...[
            const SectionBand(),
            Padding(padding: const EdgeInsets.only(top: Space.xl), child: ReviewsPane(title: e.title, myRating: b.rating, state: reviews)),
          ],
        ]);

    void togglePage() => setState(() {
          _pageEdit = !_pageEdit;
          _page.text = b.currentPage != null && b.currentPage != 0 ? '${b.currentPage}' : '';
        });
    // 내 기록 탭(2026-11-17 사용자 시안): 위에 읽기 상태(누르면 고르는 시트)와 쪽수, 진행 막대, 'N% 읽음 · 총 시간 · 횟수',
    // 그 아래 최근 독서 기록(날짜·시간대·걸린 시간, 전체 보기는 통계). 읽은 기간(회차)과 남긴 갈피는 그 아래 그대로
    final pc = e.pageCount;
    final cur = b.currentPage ?? 0;
    final pct = pc != null && pc > 0 ? ((cur / pc).clamp(0.0, 1.0) * 100).round() : null;
    final recent = lib.sessions.values.where((x) => x.myBookId == id).toList()..sort((a, c) => c.startedAt.compareTo(a.startedAt));
    void pickStatus() => showSheet<void>(
          context,
          title: '읽기 상태',
          builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final st in _statuses)
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
    void openAllSessions() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsScreen(tab: false, initialBook: id)));
    String dayOf(String iso) {
      final t = DateTime.parse(iso).toLocal();
      return '${t.month}월 ${t.day}일';
    }

    Widget minePane() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Semantics(
              button: true,
              label: '읽기 상태 ${statusLabel[b.status]}, 바꾸기',
              onTap: pickStatus,
              excludeSemantics: true,
              child: Pressable(
                onPress: pickStatus,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Space.hit),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(statusLabel[b.status]!, style: AppType.rowStrong.copyWith(color: AppColors.accent)),
                    const SizedBox(width: 4),
                    const LucideIcon('ChevronDown', size: 20, color: AppColors.accent, stroke: 2),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Semantics(
                button: true,
                label: '현재 쪽 $cur${pc != null ? ' / $pc쪽' : '쪽'}, 눌러서 고치기',
                onTap: togglePage,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: togglePage,
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
                    Text('$pct%', style: AppType.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ])
                : Text('전체 쪽수 미입력', style: AppType.caption),
          ),
          if (_pageEdit)
            Container(
              margin: const EdgeInsets.only(top: Space.s),
              decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(Shape.input)),
              child: TextField(
                controller: _page,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                style: AppType.input,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                  hintText: '읽은 쪽수',
                  hintStyle: AppType.input.copyWith(color: AppColors.inkFaint),
                ),
                onSubmitted: (v) {
                  final n = num.tryParse(v);
                  _model.updateBook(id, currentPage: n != null && n > 0 ? n.round() : null);
                  setState(() => _pageEdit = false);
                },
              ),
            ),
          // 최근 독서 기록: 날짜 · 시간대 · 걸린 시간(누르면 고치기), 전체는 통계에서
          const SizedBox(height: Space.block),
          SectionHead(title: '독서 기록', link: recent.isNotEmpty ? '전체 보기' : null, chevron: true, linkLabel: '독서 기록 전체 보기', onLink: openAllSessions),
          // 횟수·총 시간은 '독서 기록' 아래 한 줄(2026-11-18 사용자 시안: '9회, 총 41분')
          if (sessions > 0 || readMs > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text([if (sessions > 0) '$sessions회', '총 ${formatDuration(readMs)}', if (done > 0) '완독 $done회'].join(', '), style: AppType.sub),
            ),
          if (recent.isEmpty)
            Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText('타이머로 읽으면 여기에 쌓여요', style: AppType.sub))
          else
            // 같은 날짜는 묶고(날짜 한 줄 아래 시간대는 연하게, 읽은 시간은 오른쪽에 진하게), 구분선 없이 날짜 사이 여백으로(2026-11-17 시안). 최근 5개
            for (final g in _byDay(recent.take(5).toList(), dayOf))
              Padding(
                // 머리–첫 날짜 8 → 12(2026-11-18 사용자 '줄 위치가 좀 더 밑으로': 시안은 머리와 첫 날짜 사이가 더 넓다)
                padding: const EdgeInsets.only(top: Space.m),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Semantics(header: true, child: Text(g.day, style: AppType.row)),
                  for (final x in g.items)
                    Semantics(
                      button: true,
                      label: '${g.day}, ${timeRange(x.startedAt, x.endedAt)}, ${formatDuration(x.durationMs)}, 고치기',
                      excludeSemantics: true,
                      onTap: () => openSessionEdit(context, x.id),
                      child: Pressable(
                        onPress: () => openSessionEdit(context, x.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: Space.dense),
                          child: Row(children: [
                            // 다른 화면 기록 줄과 같은 크기(시간대 16 · 읽은 시간 18, 2026-11-18 사용자 '독서 기록 글자가 좀 작다')
                            Expanded(child: Text(timeRange(x.startedAt, x.endedAt), style: AppType.sub)),
                            Text(formatDuration(x.durationMs), style: AppType.rowStrong.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
          // 읽은 기간(회차, 2026-11-17 사용자 시안): 테두리 카드에 'N회차'·상태, 시작일·완독일. 오른쪽 '수정'을 누르면 그 자리에서 날짜를 고른다
          const SizedBox(height: Space.block),
          sectionHead('읽은 기간', rounds.isEmpty ? null : (_roundEdit ? '완료' : '수정'), () => setState(() => _roundEdit = !_roundEdit)),
          const SizedBox(height: Space.s),
          if (rounds.isNotEmpty)
            Column(children: [
              for (final r in rounds)
                _roundEdit
                    ? _RoundCard(key: ValueKey('${r.id}|${r.startedAt}|${r.finishedAt}'), round: r, onSave: (s, f) => _model.updateRound(r.id, startedAt: s, finishedAt: f))
                    : _RoundView(round: r),
            ])
          else
            Text('읽기 시작하면 회차가 생겨요. 날짜는 나중에 고칠 수 있어요.', style: AppType.sub),
          // 남긴 갈피: 제목 옆 작은 회색 개수(감상과 같은 모양), 없으면 가운데 한 줄
          const SizedBox(height: Space.block),
          sectionHead('남긴 갈피', null, null, count: '${marks.length}개'),
          if (marks.isNotEmpty) ...[
            ListGroup(children: [
              for (final m in marks.take(5))
                Pressable(
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
                            child: MetaText([if (m.page != null && m.page != 0) '${m.page}쪽', dateShort(m.createdAt)].where((x) => x.isNotEmpty).join(' | '), style: AppType.caption),
                          ),
                        ]),
                      ),
                      if (m.photoUri != null && m.photoUri!.isNotEmpty) ...[
                        const SizedBox(width: Space.m),
                        ClipRRect(borderRadius: BorderRadius.circular(3), child: Container(width: 48, height: 64, color: AppColors.surface, child: BookmarkPhoto(uri: m.photoUri!))),
                      ],
                    ]),
                  ),
                ),
            ]),
            Padding(padding: const EdgeInsets.only(top: Space.m), child: Btn(label: '갈피 보드로 보기', kind: 'secondary', onPress: () => openBookmarkBoard(context, id))),
          ] else
            Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('아직 남긴 갈피가 없어요', style: AppType.sub))),
        ]);

    return Screen(
      compact: true,
      right: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(label: '책 공유', onPress: _share, child: const LucideIcon('Share')),
        IconBtn(label: '더 보기', onPress: _menu, child: const LucideIcon('MoreHorizontal')),
      ]),
      // 두 단추 중 하나가 두 줄이 되면 높이를 맞춘다
      footer: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Btn(label: '갈피 남기기', kind: 'secondary', size: 'l', onPress: () => openNewBookmark(context, book: widget.id))),
          const SizedBox(width: Space.s),
          Expanded(
            child: Btn(
              label: readLabel,
              size: 'l',
              // 그 책으로 바로 독서를 시작하고 읽기 화면을 연다(2026-11-16 QA 영숙 F2: 읽기 탭 목록에 올리기만 하고 시계가 가지 않았다)
              // 완독한 책의 '다시 읽기'는 새 회차를 먼저 묻는다(지난 회차에 이어 붙지 않게)
              onPress: () {
                if (widget.onRead != null) return widget.onRead!(id);
                if (b.status != ReadStatus.read || last?.finishedAt == null) return unawaited(startReadingBook(context, id));
                appAlert(context, '다시 읽기를 시작할까요?', '${last!.index + 1}회차가 생기고 진도는 0쪽부터예요. 지난 회차의 완독일, 독서 기록, 갈피는 그대로 남아요.', [
                  const AlertButton('취소', style: AlertStyle.cancel),
                  AlertButton('다시 읽기', onPress: () async {
                    await _model.reread(id);
                    if (context.mounted) unawaited(startReadingBook(context, id));
                  }),
                ]);
              },
            ),
          ),
        ]),
      ),
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: SizedBox(width: 300, child: Segmented<String>(items: _views, value: _tab, onChange: _chooseTab)),
          ),
        ),
        // 표지와 제목·지은이
        // 2026-11-17 시안에 맞춰 표지·간격을 줄였다(표지 170 → 140, 제목 24 → 22)
        Padding(
          padding: const EdgeInsets.only(top: Space.l + 8),
          child: Column(children: [
            BookVisual(lib: lib, id: id, width: 140),
            Padding(
              padding: const EdgeInsets.only(top: Space.l),
              child: Text(e.title, textAlign: TextAlign.center, style: AppType.pageTitle),
            ),
            if (e.authors.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(e.authors.join(', '), textAlign: TextAlign.center, style: AppType.sub)),
            ReaderRating(data: reviews.data),
          ]),
        ),
        Padding(
          key: _paneKey,
          padding: const EdgeInsets.only(top: Space.l),
          child: switch (_tab) { 'rate' => ratePane(), 'mine' => minePane(), _ => infoPane() },
        ),
      ],
    );
  }
}

/// 회차 하나(보기): 테두리 카드 안 '1회차'·오른쪽 상태, 시작일·완독일(2026.11.14, 없으면 —)
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
          Text(v, style: AppType.label.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]);
    return Semantics(
      container: true,
      label: '${r.index}회차, ${r.finishedAt != null ? '완독' : r.paused ? '보류' : '읽는 중'}, 시작일 ${day(r.startedAt)}, 완독일 ${r.finishedAt != null ? day(r.finishedAt) : '없음'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: OutlineBox(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${r.index}회차${r.index > 1 ? ' | 재독' : ''}', style: AppType.labelStrong)),
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
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1 / MediaQuery.devicePixelRatioOf(context)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(TextSpan(
          text: '${r.index}회차${r.index > 1 ? ' | 재독' : ''}',
          style: AppType.rowStrong,
          children: [TextSpan(text: r.finishedAt != null ? '   완독' : r.paused ? '   보류' : '   읽는 중', style: AppType.sub)],
        )),
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

/// 독서 기록을 날짜별로 묶는다(최근 날짜부터, 들어온 순서 그대로)
List<({String day, List<Session> items})> _byDay(List<Session> list, String Function(String) dayOf) {
  final out = <({String day, List<Session> items})>[];
  for (final x in list) {
    final d = dayOf(x.startedAt);
    if (out.isNotEmpty && out.last.day == d) {
      out.last.items.add(x);
    } else {
      out.add((day: d, items: [x]));
    }
  }
  return out;
}
