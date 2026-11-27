// 갈피 보기(지금 앱 app/bookmark/[id].tsx): 같은 책의 갈피를 좌우로 넘기며 읽는다. 카드는 길면 세로로 스크롤.
// 아래 막대: 책장 한켠 · 수정 · 공유. 오른쪽 위 더 보기: 수정 · 메모 포함해 공유 · 삭제(갈피 색은 책 정보 › 책 꾸미기 › 갈피, 2026-11-23).
// 카드 아래 출처(표지·제목·저자)를 누르면 그 책 화면(감상 상세의 책 줄과 같다). 그래서 더 보기의 '책 정보'는 뺐다(2026-11-24 사용자 3단계)
// 공유는 화면 밖에 그린 같은 카드를 그림으로 떠서 공유창으로 보낸다(개인 메모는 기본 제외).
// 문장 갈피의 공유는 두 모양 '책 페이지·종이 메모'(mark_share_sheet). 문장 없는 사진 갈피와 '메모 포함해 공유'는 같은 카드를 이미지로 뜬다
// 2026-11-16 QA 은서 F1: 수정·삭제·공유는 늘 화면에 보이는 갈피(넘길 때마다 그 갈피 id를 기억한다). 수정에서 돌아오면 넘기기 목록을
// 그 갈피 자리에서 다시 붙인다(전에는 처음 연 갈피 자리로 붙어 보이는 갈피와 수정·삭제 대상이 달랐다). 삭제 확인창에 어느 갈피인지 보인다.
// 영숙 F18: 아래 줄은 한 줄에 다 들어가면 '— 책장 한켠'과 '수정·공유'를 양끝에, 안 들어가면(큰 글씨) '수정·공유'만 가운데(빈 구분선 없음)
// 공유 그림(화면 뒤 카드와 서명)의 글자·색 숫자는 옛 앱 화소 값 그대로(docs/design/DESIGN.md 16장 예외)
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/color.dart';
import '../../domain/library.dart';
import '../../services/photos.dart' show PhotoFail, PhotoOk;
import '../../store/files.dart';
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/book_screen.dart';
import '../book/labels.dart';
import 'bookmark_card.dart';
import 'form_parts.dart';
import 'mark_share_sheet.dart' show showMarkShareSheet;
import 'mark_text.dart';
import 'page_photo.dart';
import 'photo_plate.dart';

/// 갈피 카드에 넣을 값(상세 · 기록 탭 목록이 같은 것을 쓴다). short: 목록 날짜(dateShort), 아니면 상세 날짜(dateLong)
BookmarkCardData? cardData(Library lib, Bookmark m, {bool short = false}) {
  final b = lib.books[m.myBookId];
  final e = b == null ? null : lib.editions[b.editionId];
  if (e == null) return null;
  return BookmarkCardData(
    text: m.text,
    title: e.title,
    author: e.authors.isEmpty ? null : authorLine(e.authors),
    page: m.page,
    date: short ? dateShort(m.createdAt) : dateLong(m.createdAt),
    memo: m.memo,
    color: ribbonOf(lib, b!.id),
    coverUri: e.coverUri,
    bookId: b.id,
    bookColor: themeColorOf(lib, b.id),
    photoUri: m.photoUri,
    photoRatio: m.photoRatio,
  );
}

/// 그 책 갈피의 대표색(넘김 점 · 보드의 고른 테두리·손잡이·넘김 점)
Color markInk(Library lib, String bookId) => hexColor(tabColors(ribbonOf(lib, bookId), bookId).$1);

const _shareW = 380.0;

Future<void> openBookmark(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/bookmark'), builder: (_) => BookmarkDetailScreen(id: id)));

class BookmarkDetailScreen extends StatefulWidget {
  const BookmarkDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<BookmarkDetailScreen> createState() => _BookmarkDetailScreenState();
}

class _BookmarkDetailScreenState extends State<BookmarkDetailScreen> {
  final _model = LibraryModel.instance;
  String? _bookId;

  /// 화면에 보이는 갈피. 수정·삭제·공유 대상은 늘 이것(QA F1)
  String? _curId;

  /// 보이던 자리(보던 갈피가 다른 곳에서 지워지면 이 자리 갈피로)
  int _index = 0;
  PageController? _pages;
  Bookmark? _editing;
  bool _busy = false;
  ({bool withMemo, BookmarkCardData data, String seed})? _share;
  final _shot = GlobalKey();

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    // 서재를 이미 읽었으면 바로(목록에서 열 때), 아니면 읽은 뒤에
    if (_model.loaded) {
      _start();
    } else {
      _model.load().then((_) {
        if (mounted) setState(_start);
      });
    }
  }

  void _start() {
    // 넘기는 목록은 처음 연 갈피의 책 기준(연 갈피를 지워도 같은 책의 다른 갈피가 남는다)
    _bookId = _model.lib.bookmarks[widget.id]?.myBookId;
    final list = _list();
    _index = math.max(0, list.indexWhere((m) => m.id == widget.id));
    _curId = list.isEmpty ? null : list[_index].id;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    _pages?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<Bookmark> _list() => _bookId == null ? const [] : bookmarksOf(_model.lib, _bookId!).reversed.toList();

  // 보이는 갈피의 자리. 없으면(지워짐) 보던 자리의 갈피로 옮긴다
  int _at(List<Bookmark> list) {
    final i = list.indexWhere((m) => m.id == _curId);
    if (i >= 0) return _index = i;
    _index = _index.clamp(0, list.length - 1);
    _curId = list[_index].id;
    return _index;
  }

  void _edit(Bookmark m) => setState(() {
        _curId = m.id;
        _editing = m;
      });

  // 수정 화면은 넘기기 목록을 트리에서 뺀다. 돌아올 때(저장·뒤로 모두) 목록을 고친 갈피 자리에서 새로 붙인다
  void _endEdit() {
    final id = _editing?.id ?? _curId;
    final list = _list();
    final i = math.max(0, list.indexWhere((m) => m.id == id));
    _pages?.dispose();
    _pages = PageController(initialPage: i);
    setState(() {
      _editing = null;
      _index = i;
      _curId = list.isEmpty ? null : list[i].id;
    });
  }

  // 지운 뒤 토스트('삭제했어요.'), 실패는 확인창(공통 규칙 14장. 예외 원문을 보였다). 같은 책 갈피를 넘겨 보는 화면이라
  // 다른 갈피가 남아 있으면 화면을 닫지 않고 지운 자리의 갈피를 보인다
  Future<void> _delete(Bookmark cur, List<Bookmark> list) async {
    final i = list.indexWhere((m) => m.id == cur.id);
    // 지운 자리의 다음 갈피(마지막이었으면 앞 갈피)로
    final next = list.length <= 1 ? null : list[i + 1 < list.length ? i + 1 : i - 1];
    final nav = Navigator.of(context);
    final wrote = _model.deleteBookmark(cur.id);
    if (next == null) {
      nav.maybePop();
    } else {
      setState(() => _curId = next.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final at = _list().indexWhere((m) => m.id == next.id);
        if (mounted && at >= 0 && (_pages?.hasClients ?? false)) _pages!.jumpToPage(at);
      });
    }
    try {
      await wrote;
      if (nav.mounted) showToast(nav.context, '삭제했어요.');
    } catch (e) {
      if (nav.mounted) appAlert(nav.context, '갈피를 삭제하지 못했어요', errorText(e));
    }
  }

  // 화면 밖에 그린 같은 카드를 그림으로 떠서 공유
  Future<void> _shoot(bool withMemo, Bookmark cur, BookmarkCardData data) async {
    if (_busy) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    setState(() {
      _busy = true;
      _share = (withMemo: withMemo, data: data, seed: cur.id);
    });
    var imageReady = false;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 900)); // 표지·사진이 그려지기를 기다린다
      final boundary = _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('카드 이미지를 뜨지 못했어요');
      final img = await boundary.toImage(pixelRatio: dpr);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (png == null) throw StateError('카드 이미지를 뜨지 못했어요');
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/gallpi_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}.png');
      await f.writeAsBytes(png.buffer.asUint8List());
      imageReady = true;
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')], title: '갈피 공유'));
    } catch (e) {
      // 책 공유와 같은 창: 제목 · 사람 문장 · 취소 | 다시 시도(2026-11-20 QA: 갈피 공유만 '확인' 하나였다)
      if (mounted) {
        appAlert(context, imageReady ? '공유 창을 열지 못했어요' : '공유 이미지를 만들지 못했어요', errorText(e), [
          const AlertButton('취소', style: AlertStyle.cancel),
          AlertButton('다시 시도', onPress: () => _shoot(withMemo, cur, data)),
        ]);
      }
    } finally {
      if (mounted) {
        setState(() {
          _share = null;
          _busy = false;
        });
      }
    }
  }

  void _menu(Bookmark cur, BookmarkCardData data, List<Bookmark> list) => showSheet<void>(
        context,
        builder: (ctx) => ListGroup(children: [
          ListItem(label: '수정', onPress: () {
            Navigator.pop(ctx);
            _edit(cur);
          }),
          if (cur.memo != null && cur.memo!.isNotEmpty)
            ListItem(label: '메모 포함해 공유', onPress: () {
              Navigator.pop(ctx);
              _shoot(true, cur, data);
            }),
          ListItem(
            label: '삭제',
            danger: true,
            onPress: () {
              Navigator.pop(ctx);
              // 어느 갈피를 지우는지 보인다(QA F1)
              appAlert(context, '이 갈피를 삭제할까요?', '${markLabel(cur.text, cur.page)}\n되돌릴 수 없어요.', [
                const AlertButton('취소', style: AlertStyle.cancel),
                AlertButton('삭제', style: AlertStyle.destructive, onPress: () => _delete(cur, list)),
              ]);
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lib = _model.lib;
    final list = _list();
    if (!_model.loaded || _pages == null) return const Screen(children: [Loading()]);
    // 찾을 수 없음 틀(공통 규칙 9장): 제목 + '돌아가기'
    if (list.isEmpty) {
      return Screen(title: '갈피', children: [
        Empty(title: '갈피를 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop()),
      ]);
    }
    if (_editing != null) return _EditBookmark(m: _editing!, onDone: _endEdit);
    final at = _at(list);
    final cur = list[at];
    // 목록이 바뀌어(다른 곳에서 지움 등) 보이는 칸이 보던 갈피와 다르면 그 갈피로 옮긴다
    final pages = _pages!;
    if (pages.hasClients && !pages.position.isScrollingNotifier.value && pages.page?.round() != at) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pages.hasClients && !pages.position.isScrollingNotifier.value) pages.jumpToPage(_at(_list()));
      });
    }
    final curData = cardData(lib, cur);
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.paddingOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return Material(
      color: AppColors.bg,
      child: Padding(
        padding: EdgeInsets.only(top: insets.top),
        child: Stack(children: [
          // 공유 이미지용(화면 뒤에 같은 카드)
          if (_share != null) _shareShot(_share!),
          Positioned.fill(
            child: Column(children: [
              // 공통 규칙: 밀어 넣은 화면 위 줄은 NavBar(제목 18 · 줄 60 · 꺾쇠 28, 2026-11-19. 제목이 26이었다)
              NavBar(
                title: '갈피',
                right: IconBtn(
                  label: '더 보기',
                  disabled: curData == null,
                  onPress: () {
                    if (curData != null) _menu(cur, curData, list);
                  },
                  child: const HeadIcon('MoreHorizontal'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: list.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _curId = list[i].id;
                  }),
                  itemBuilder: (context, i) {
                    final d = cardData(lib, list[i]);
                    return _CardPage(
                      top: scale > 1.2 ? 18 : math.max(24, math.min(62, size.height * 0.073 - 4)),
                      child: Center(child: d == null ? const SizedBox.shrink() : BookmarkCard(data: d, showMemo: true, width: math.min(size.width, 440), seed: list[i].id, onBook: () => openBook(context, list[i].myBookId))),
                    );
                  },
                ),
              ),
              if (list.length > 1)
                Padding(
                  padding: EdgeInsets.only(top: 6, bottom: size.height * 0.047),
                  child: Column(children: [
                    // 넘김 점은 이 책의 갈피 색
                    PageDots(count: list.length, index: at, color: markInk(lib, cur.myBookId), max: 12, gap: 10),
                    const SizedBox(height: Space.m),
                    // 공통 규칙: 개수는 '갈피 N개' 어순, 글자는 sub(2026-11-19. 'N개의 갈피' caption이었다)
                    Text('갈피 ${list.length}개', style: AppType.sub),
                  ]),
                ),
              // 작은 타이머가 이 줄 위에 뜨게 높이를 알린다(공유 단추를 가렸다)
              FooterReport(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(Space.page, Space.m, Space.page, insets.bottom + size.height * 0.044),
                  child: _Bar(buttons: [
                    _BarBtn(icon: 'PenLine', label: '수정', onPress: () => _edit(cur)),
                    _BarBtn(
                      icon: 'Share',
                      label: _busy ? '준비 중' : '공유',
                      busy: _busy,
                      // 문장이 있으면 두 모양(책 페이지·종이 메모) 중 골라 공유, 문장 없는 사진 갈피는 같은 카드를 이미지로 뜬다
                      onPress: _busy || curData == null
                          ? null
                          : curData.text.trim().isNotEmpty
                              ? () => showMarkShareSheet(context, (text: curData.text, title: curData.title, author: curData.author, page: curData.page))
                              : () => _shoot(false, cur, curData),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// 공유 이미지로 뜰 카드(화면 뒤, 거의 투명). 서명 글자는 공유 그림이라 옛 앱 값 그대로(규칙 9장)
  Widget _shareShot(({bool withMemo, BookmarkCardData data, String seed}) share) => Positioned(
        left: 0,
        top: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.01,
            child: RepaintBoundary(
              key: _shot,
              child: Container(
                width: _shareW,
                color: AppColors.bg,
                padding: const EdgeInsets.only(top: 24, bottom: 30),
                child: Column(children: [
                  BookmarkCard(data: share.data, showMemo: share.withMemo, width: _shareW, seed: share.seed),
                  const Padding(padding: EdgeInsets.only(top: 4), child: Text('책장 한켠', style: TextStyle(fontFamily: AppFonts.serif, fontSize: 15, color: Color(0xFF68524A)))),
                ]),
              ),
            ),
          ),
        ),
      );
}

// 아래 줄 치수: 그리는 곳과 폭 재는 곳이 같은 값을 쓴다(따로 적혀 있어 한쪽만 바꾸면 큰 글씨 판정이 어긋났다, 2026-11-19)
const _brand = '책장 한켠';
const _brandLine = 20.0; // 서명 앞 짧은 선(BrandFooter와 같은 모양)
const _brandRoom = Space.l; // 서명과 구분선 사이 최소
const _btnBetween = 18.0; // 단추 사이 · 구분선 뒤

/// 아래 줄: 한 줄에 다 들어가면 왼쪽 '— 책장 한켠', 오른쪽 '| 수정 공유'. 안 들어가면(큰 글씨·좁은 화면) 꾸밈인 서명과 구분선을 빼고
/// '수정 공유'만 가운데(전에는 줄이 바뀌며 서명은 왼쪽, 버튼은 오른쪽으로 치우치고 빈 구분선이 남았다, QA 영숙 F18)
class _Bar extends StatelessWidget {
  const _Bar({required this.buttons});
  final List<_BarBtn> buttons;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final scaler = MediaQuery.textScalerOf(context);
        double tw(String t) {
          final p = TextPainter(text: TextSpan(text: t, style: AppType.sub), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
          final w = p.width;
          p.dispose();
          return w;
        }

        final hair = 2 / MediaQuery.devicePixelRatioOf(context);
        final actions = Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: _btnBetween), b],
        ]);
        final brandW = _brandLine + Space.m + tw(_brand);
        final actionsW = buttons.fold<double>(0, (a, b) => a + _BarBtn.chrome + tw(b.label)) + _btnBetween * (buttons.length - 1);
        if (brandW + _brandRoom + actionsW > c.maxWidth) return Center(child: actions);
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Semantics(
            label: _brand,
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(height: hair, width: _brandLine, color: AppColors.inkFaint),
              const SizedBox(width: Space.m),
              Text(_brand, style: AppType.sub),
            ]),
          ),
          // 서명과 단추 사이 세로선은 두지 않는다(2026-11-18 사용자 '이거 사이에 | 있을 필요도 없고')
          actions,
        ]);
      });
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({required this.icon, required this.label, required this.onPress, this.busy = false});
  final String icon, label;
  final VoidCallback? onPress;
  final bool busy;

  static const _pad = 2.0, _icon = 22.0, _gap = 6.0;

  /// 글자 밖 폭(양옆 · 아이콘 · 아이콘과 글자 사이)
  static const chrome = _pad * 2 + _icon + _gap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: busy ? '공유 준비 중' : label == '공유' ? '이미지로 공유' : label,
        onTap: onPress,
        excludeSemantics: true,
        child: Pressable(
          onPress: onPress,
          child: ConstrainedBox(
            // 누르는 자리 48(공통 규칙 8장, 44였다)
            constraints: const BoxConstraints(minHeight: Space.hit),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // 진행은 공용 작은 원(Spinner 20, 공통 규칙 11장)
                // 아이콘 · 글자는 옅은 회색(2026-11-18 사용자 '공유 버튼이랑 이런 게 너무 진해': 먹색이었다)
                busy ? const Spinner(color: AppColors.accent) : LucideIcon(icon, size: _icon, color: AppColors.icon),
                const SizedBox(width: _gap),
                Text(label, style: AppType.sub),
              ]),
            ),
          ),
        ),
      );
}

/// 갈피 수정: 같은 화면 안의 단계라 뒤로는 갈피 보기로 돌아온다. 고친 것이 있으면 나가기 전에 묻는다(갈피 남기기 · 감상과 같은 DraftGuard)
class _EditBookmark extends StatefulWidget {
  const _EditBookmark({required this.m, required this.onDone});
  final Bookmark m;
  final VoidCallback onDone;

  @override
  State<_EditBookmark> createState() => _EditBookmarkState();
}

class _EditBookmarkState extends State<_EditBookmark> {
  late final _firstPage = widget.m.page != null ? '${widget.m.page}' : '';
  late String _text = widget.m.text, _page = _firstPage, _memo = widget.m.memo ?? '';
  late ({String? uri, num? ratio, bool changed}) _photo = (uri: widget.m.photoUri, ratio: widget.m.photoRatio, changed: false);
  ({String text, bool error})? _msg; // 사진을 넣지 못한 이유(갈피 남기기와 같은 안내, form_parts)
  String? _saveError;
  bool _saving = false;

  bool get _dirty => _text != widget.m.text || _page != _firstPage || _memo != (widget.m.memo ?? '') || _photo.changed;

  Future<void> _swap(String from) async {
    final r = await pickPagePhoto(from);
    if (!mounted) return;
    switch (r) {
      case PhotoOk(:final uri, :final width, :final height):
        setState(() {
          _photo = (uri: uri, ratio: width != null && height != null && height > 0 ? width / height : null, changed: true);
          _msg = null;
        });
      case PhotoFail(:final reason, :final message):
        final notice = photoFailNotice(from, reason, message);
        if (notice != null) setState(() => _msg = notice);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final n = num.tryParse(_page);
      var photoUri = _photo.uri;
      if (_photo.changed) photoUri = _photo.uri != null ? await keepImage(_photo.uri!, 'page') : null;
      await LibraryModel.instance.updateBookmark(
        widget.m.id,
        // 앞 빈 줄·끝 공백만 정리(첫 줄 들여쓰기는 남긴다, QA F10)
        text: tidyMarkText(_text),
        page: n != null && n > 0 ? n.round() : null,
        memo: _memo.trim().isEmpty ? null : _memo.trim(),
        photoUri: photoUri,
        photoRatio: photoUri != null ? _photo.ratio : null,
      );
      widget.onDone();
    } catch (e) {
      // 갈피 남기기와 같은 모양: 고친 글이 있는 화면이라 화면 안 글(공통 규칙 11장. 원인과 상관없이 '사진을 옮기지 못했어요' + 예외 원문 확인창이었다)
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '갈피를 저장하지 못했어요. 고친 내용과 사진은 그대로 있어요. ${errorText(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = LibraryModel.instance.lib;
    final ed = lib.editions[lib.books[widget.m.myBookId]?.editionId ?? ''];
    // 글이 있던 갈피면 사진은 원본으로 곁들인 문장 갈피(QA F11). 치는 동안 제목·칸이 바뀌지 않게 처음 글로 정한다
    final isPhoto = isPhotoMark(widget.m.text, _photo.uri);
    final width = MediaQuery.sizeOf(context).width;
    return DraftGuard.edit(
      dirty: () => _dirty,
      onLeave: widget.onDone,
      child: Screen(
        title: isPhoto ? '사진 갈피 수정' : '갈피 수정',
        // 공통 규칙: 저장 단추는 '○○ 저장'(2026-11-19. '저장'이었다)
        footer: Btn(label: '갈피 저장', size: 'xlarge', busy: _saving, disabled: _text.trim().isEmpty && _photo.uri == null, onPress: _save),
        children: [
          const SizedBox(height: Space.m),
          // 책 칸은 갈피 남기기 · 감상 수정과 같은 고르는 칸(쓴 갈피의 책은 바꾸지 않는다. 회색 글 한 줄이었다)
          if (ed != null) SelectField(label: '책', value: ed.title, sub: ed.authors.isNotEmpty ? authorLine(ed.authors) : null, placeholder: '', disabled: true, onPress: () {}),
          if (_photo.uri != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: PhotoWithMenu(
                    plate: PhotoPlate(uri: _photo.uri!, ratio: _photo.ratio, width: math.min(300, width - Space.page * 2), seed: widget.m.id),
                    onCamera: () => _swap('camera'),
                    onLibrary: () => _swap('library'),
                    onRemove: _text.trim().isNotEmpty ? () => setState(() => _photo = (uri: null, ratio: null, changed: true)) : null,
                  ),
                ),
                if (_msg case final msg?) NoticeText(msg.text, error: msg.error, center: true),
              ]),
            ),
          // 갈피 남기기와 같은 칸 이름 · 안내 · 높이(form_parts, 2026-11-19 공통 규칙)
          Field(
            label: isPhoto ? '옮겨 적기 (선택)' : markTextLabel,
            value: _text,
            placeholder: isPhoto ? null : markTextHint,
            multiline: true,
            minHeight: isPhoto ? markTranscribeHeight : markTextHeight,
            onChange: (v) => setState(() => _text = v),
          ),
          Field(label: '쪽수 (선택)', unit: '쪽', number: true, value: _page, onChange: (v) => setState(() => _page = v)),
          Field(label: markMemoLabel, value: _memo, placeholder: markMemoHint, multiline: true, minHeight: markMemoHeight, onChange: (v) => setState(() => _memo = v)),
          if (_saveError != null) NoticeText(_saveError!, error: true),
        ],
      ),
    );
  }
}

/// 갈피 한 장 칸: 카드가 화면보다 길면 내려서 끝까지 본다. 아래에 더 있을 때만 아래 끝을 옅게 흐려 '더 있음'을 보이고
/// (지금 앱은 긴 카드 아래가 막대에 뚝 잘렸다, 2026-11-14 사용자 '밑에 짤리는 거 고쳐'), 끝까지 내리면 카드 그림자·뒤 종이까지 다 보이게 아래 여백을 둔다
class _CardPage extends StatefulWidget {
  const _CardPage({required this.top, required this.child});
  final double top;
  final Widget child;

  @override
  State<_CardPage> createState() => _CardPageState();
}

class _CardPageState extends State<_CardPage> {
  bool _more = false;

  // 처음 그린 뒤(크기 알림)와 내릴 때(움직임 알림) 모두 아래에 남은 길이를 본다
  bool _see(ScrollMetrics m) {
    final more = m.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _see(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) => _see(n.metrics),
          child: Stack(children: [
            SingleChildScrollView(padding: EdgeInsets.only(top: widget.top, bottom: 28), child: widget.child),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 36,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _more ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00FFFFFF), AppColors.bg])),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}
