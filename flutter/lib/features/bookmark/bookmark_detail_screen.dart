// 갈피 보기(지금 앱 app/bookmark/[id].tsx): 같은 책의 갈피를 좌우로 넘기며 읽는다. 카드는 길면 세로로 스크롤.
// 아래 막대: 책장 한켠 · 수정 · 공유. 오른쪽 위 더 보기: 수정 · 메모 포함해 공유 · 갈피 색 · 연결된 책 열기 · 삭제.
// 공유는 화면 밖에 그린 같은 카드를 그림으로 떠서 공유창으로 보낸다(개인 메모는 기본 제외).
// 문장 갈피의 공유는 두 모양 '책 페이지·종이 메모'(mark_share_sheet). 문장 없는 사진 갈피와 '메모 포함해 공유'는 같은 카드를 이미지로 뜬다
// 2026-11-16 QA 은서 F1: 수정·삭제·공유는 늘 화면에 보이는 갈피(넘길 때마다 그 갈피 id를 기억한다). 수정에서 돌아오면 넘기기 목록을
// 그 갈피 자리에서 다시 붙인다(전에는 처음 연 갈피 자리로 붙어 보이는 갈피와 수정·삭제 대상이 달랐다). 삭제 확인창에 어느 갈피인지 보인다.
// 영숙 F18: 아래 줄은 한 줄에 다 들어가면 '— 책장 한켠'과 '수정·공유'를 양끝에, 안 들어가면(큰 글씨) '수정·공유'만 가운데(빈 구분선 없음)
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
import '../../services/photos.dart' show PhotoFail, PhotoOk, deniedMessage;
import '../../store/files.dart';
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/book_screen.dart';
import '../book/labels.dart';
import 'bookmark_card.dart';
import 'mark_share_sheet.dart' show showMarkShareSheet;
import 'mark_text.dart';
import 'page_photo.dart';
import 'photo_plate.dart';
import 'ribbon_color_sheet.dart';

BookmarkCardData? cardData(Library lib, Bookmark m) {
  final b = lib.books[m.myBookId];
  final e = b == null ? null : lib.editions[b.editionId];
  if (e == null) return null;
  return BookmarkCardData(
    text: m.text,
    title: e.title,
    author: e.authors.isEmpty ? null : e.authors.join(', '),
    page: m.page,
    date: ymd(m.createdAt),
    memo: m.memo,
    color: ribbonOf(lib, b!.id),
    coverUri: e.coverUri,
    bookId: b.id,
    bookColor: themeColorOf(lib, b.id),
    photoUri: m.photoUri,
    photoRatio: m.photoRatio,
  );
}

const _shareW = 380.0;

Future<void> openBookmark(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/bookmark'), builder: (_) => BookmarkDetailScreen(id: id)));

/// 넘김 점(지금 앱 PageDots): 지금 칸은 크고 진하게, 나머지는 같은 색을 옅게. 많으면 지금 칸 둘레 max개만
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.index, required this.color, this.max = 7, this.gap = 8});
  final int count, index, max;
  final Color color;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final from = count <= max ? 0 : math.max(0, math.min(count - max, index - max ~/ 2));
    final to = count <= max ? count : from + max;
    return ExcludeSemantics(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = from; i < to; i++) ...[
          if (i > from) SizedBox(width: gap),
          Container(
            width: i == index ? 10 : 7,
            height: i == index ? 10 : 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: i == index ? 1 : 0.32)),
          ),
        ],
      ]),
    );
  }
}

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

  Future<void> _delete(Bookmark cur, List<Bookmark> list) async {
    final i = list.indexWhere((m) => m.id == cur.id);
    // 지운 자리의 다음 갈피(마지막이었으면 앞 갈피)로
    final next = list.length <= 1 ? null : list[i + 1 < list.length ? i + 1 : i - 1];
    final wrote = _model.deleteBookmark(cur.id);
    if (next == null) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _curId = next.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final at = _list().indexWhere((m) => m.id == next.id);
        if (mounted && at >= 0 && (_pages?.hasClients ?? false)) _pages!.jumpToPage(at);
      });
    }
    try {
      await wrote;
    } catch (e) {
      if (mounted) appAlert(context, '삭제를 저장하지 못했어요', '$e');
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
      if (mounted) appAlert(context, imageReady ? '공유 창을 열지 못했어요' : '공유 이미지를 만들지 못했어요', '$e');
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
          ListItem(label: '갈피 색 바꾸기', onPress: () {
            Navigator.pop(ctx);
            showRibbonColorSheet(context, cur.myBookId);
          }),
          ListItem(label: '연결된 책 열기', onPress: () {
            Navigator.pop(ctx);
            openBook(context, cur.myBookId);
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
    if (list.isEmpty) return const Screen(title: '갈피', children: [Empty(title: '갈피를 찾을 수 없어요')]);
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
    // 넘김 점은 이 책의 갈피 색
    final dot = hexColor(tabColors(curData?.color, cur.myBookId).$1);
    final hair = 2 / MediaQuery.devicePixelRatioOf(context);
    return PopScope(
      canPop: true,
      child: Material(
        color: AppColors.bg,
        child: Padding(
          padding: EdgeInsets.only(top: insets.top),
          child: Stack(children: [
            // 공유 이미지용(화면 뒤에 같은 카드)
            if (_share != null)
              Positioned(
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
                          BookmarkCard(data: _share!.data, showMemo: _share!.withMemo, width: _shareW, seed: _share!.seed),
                          const Padding(padding: EdgeInsets.only(top: 4), child: Text('책장 한켠', style: TextStyle(fontFamily: AppFonts.serif, fontSize: 15, color: Color(0xFF68524A)))),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Container(
                color: AppColors.bg,
                child: Column(children: [
                  SizedBox(
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                      child: Row(children: [
                        IconBtn(label: '뒤로', onPress: () => Navigator.of(context).maybePop(), child: const LucideIcon('ChevronLeft', size: 28)),
                        Expanded(child: Center(child: Semantics(header: true, child: Text('갈피', style: AppType.title)))),
                        IconBtn(label: '더 보기', onPress: curData == null ? () {} : () => _menu(cur, curData, list), child: const LucideIcon('MoreHorizontal')),
                      ]),
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
                          child: Center(child: d == null ? const SizedBox.shrink() : BookmarkCard(data: d, showMemo: true, width: math.min(size.width, 440), seed: list[i].id)),
                        );
                      },
                    ),
                  ),
                  if (list.length > 1)
                    Padding(
                      padding: EdgeInsets.only(top: 6, bottom: size.height * 0.047),
                      child: Column(children: [
                        PageDots(count: list.length, index: at, color: dot, max: 12, gap: 10),
                        const SizedBox(height: 12),
                        Text('${list.length}개의 갈피', style: AppType.caption),
                      ]),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(Space.page, 12, Space.page, insets.bottom + size.height * 0.044),
                    child: _Bar(
                      brand: Semantics(
                        label: '책장 한켠',
                        excludeSemantics: true,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(height: hair, width: 20, color: AppColors.inkFaint),
                          const SizedBox(width: 12),
                          Text('책장 한켠', style: AppType.sub),
                        ]),
                      ),
                      rule: Container(width: hair, height: 28, color: AppColors.line),
                      labels: ['수정', _busy ? '준비 중' : '공유'],
                      actions: Row(mainAxisSize: MainAxisSize.min, children: [
                        _BarBtn(icon: 'PenLine', label: '수정', onPress: () => _edit(cur)),
                        const SizedBox(width: 18),
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
            ),
          ]),
        ),
      ),
    );
  }
}

/// 아래 줄: 한 줄에 다 들어가면 왼쪽 '— 책장 한켠', 오른쪽 '| 수정 공유'. 안 들어가면(큰 글씨·좁은 화면) 꾸밈인 서명과 구분선을 빼고
/// '수정 공유'만 가운데(전에는 줄이 바뀌며 서명은 왼쪽, 버튼은 오른쪽으로 치우치고 빈 구분선이 남았다, QA 영숙 F18)
class _Bar extends StatelessWidget {
  const _Bar({required this.brand, required this.rule, required this.actions, required this.labels});
  final Widget brand, rule, actions;

  /// 버튼 글자들(폭 재기)
  final List<String> labels;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final scaler = MediaQuery.textScalerOf(context);
        double tw(String t, TextStyle st) {
          final p = TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
          final w = p.width;
          p.dispose();
          return w;
        }

        // 서명: 줄 20 + 12 + 글자. 버튼: 양옆 2 + 아이콘 22 + 6 + 글자, 버튼 사이 18. 서명과 구분선 사이 16, 구분선 뒤 18
        final brandW = 32 + tw('책장 한켠', AppType.sub);
        final actionsW = [for (final l in labels) 30 + tw(l, AppType.sub)].fold<double>(0, (a, b) => a + b) + 18 * (labels.length - 1);
        if (brandW + 16 + 1 + 18 + actionsW <= c.maxWidth) {
          return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            brand,
            Row(mainAxisSize: MainAxisSize.min, children: [rule, const SizedBox(width: 18), actions]),
          ]);
        }
        return Center(child: actions);
      });
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({required this.icon, required this.label, required this.onPress, this.busy = false});
  final String icon, label;
  final VoidCallback? onPress;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: busy ? '공유 준비 중' : label == '공유' ? '이미지로 공유' : label,
        onTap: onPress,
        excludeSemantics: true,
        child: Pressable(
          onPress: onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.touch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                    : LucideIcon(icon),
                const SizedBox(width: 6),
                Text(label, style: AppType.sub.copyWith(color: AppColors.ink)),
              ]),
            ),
          ),
        ),
      );
}

/// 갈피 수정: 같은 화면 안의 단계라 뒤로는 갈피 보기로 돌아온다
class _EditBookmark extends StatefulWidget {
  const _EditBookmark({required this.m, required this.onDone});
  final Bookmark m;
  final VoidCallback onDone;

  @override
  State<_EditBookmark> createState() => _EditBookmarkState();
}

class _EditBookmarkState extends State<_EditBookmark> {
  late String _text = widget.m.text, _page = widget.m.page != null ? '${widget.m.page}' : '', _memo = widget.m.memo ?? '';
  late ({String? uri, num? ratio, bool changed}) _photo = (uri: widget.m.photoUri, ratio: widget.m.photoRatio, changed: false);
  String? _msg;
  bool _saving = false;

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
        if (reason == 'denied') setState(() => _msg = deniedMessage(from));
        if (reason == 'crop') setState(() => _msg = cropCanceledMessage);
        if (reason == 'error') setState(() => _msg = '사진을 가져오지 못했어요. ${message ?? ''}');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
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
      if (!mounted) return;
      setState(() => _saving = false);
      appAlert(context, '저장하지 못했어요', '사진을 옮기지 못했어요. 다시 눌러 주세요.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = LibraryModel.instance.lib;
    final ed = lib.editions[lib.books[widget.m.myBookId]?.editionId ?? ''];
    final bookLine = ed == null ? '' : [ed.title, if (ed.authors.isNotEmpty) ed.authors.join(', ')].join(' · ');
    // 글이 있던 갈피면 사진은 원본으로 곁들인 문장 갈피(QA F11). 치는 동안 제목·칸이 바뀌지 않게 처음 글로 정한다
    final isPhoto = isPhotoMark(widget.m.text, _photo.uri);
    final width = MediaQuery.sizeOf(context).width;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onDone();
      },
      child: Screen(
        title: isPhoto ? '사진 갈피 수정' : '갈피 수정',
        footer: Btn(label: '저장', busy: _saving, disabled: _text.trim().isEmpty && _photo.uri == null, onPress: _save),
        children: [
          if (bookLine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.page), child: Text(bookLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub)),
          if (_photo.uri != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.group + 8),
              child: Column(children: [
                PhotoPlate(uri: _photo.uri!, ratio: _photo.ratio, width: math.min(300, width - Space.page * 2), seed: widget.m.id),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(spacing: Space.s, children: [
                    AppChip(label: '다시 찍기', onPress: () => _swap('camera')),
                    AppChip(label: '다른 사진', onPress: () => _swap('library')),
                    if (_text.trim().isNotEmpty) AppChip(label: '사진 빼기', onPress: () => setState(() => _photo = (uri: null, ratio: null, changed: true))),
                  ]),
                ),
                if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: AppType.sub)),
              ]),
            )
          else
            const SizedBox(height: Space.group + 2),
          Field(
            label: isPhoto ? '옮겨 적기 (선택)' : '문장 (줄바꿈으로 문단을 나눠요)',
            value: _text,
            multiline: true,
            minHeight: isPhoto ? 120 : 190,
            onChange: (v) => setState(() => _text = v),
          ),
          Field(label: '쪽수 (선택)', unit: '쪽', number: true, value: _page, onChange: (v) => _page = v),
          Field(label: '한 줄 메모 (선택, 공유 이미지에는 기본으로 빠져요)', value: _memo, multiline: true, minHeight: 80, onChange: (v) => _memo = v),
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
