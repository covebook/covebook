// 책 공유(지금 앱 app/book/[id]/share.tsx, 2026-11-09 사용자 '책 공유할 때 밑에 한줄평이랑 별점이랑'): 카드 미리보기 → 넣을 것 고르기 → 사진첩에 저장 또는 이미지로 공유.
// 한 줄 감상·별점은 여기서 바로 적을 수 있고 책 기록(평가 칸)에 그대로 저장된다. 이미지는 미리보기와 같은 그림을 폭 1080px로 따로 그린다(기기 화면 폭과 상관없이 같은 모양)
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/cover_url.dart' show coverAtSize;
import '../../services/cover_cache.dart' show loadCover;
import '../../services/share_image.dart';
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/alert.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../reading/start_book.dart' show startReadingBook;
import '../share/share_scene.dart';
import 'book_share.dart';

const _exportW = 1080;
const _wall = Color(0xFFF3F2F1); // 시안 벽 평균색(재료가 오기 전 빈 카드)
const _partLabel = {'note': '한줄평', 'rating': '별점', 'time': '독서 시간', 'period': '읽은 기간'};

/// 책 공유 화면. 비어 있는 항목을 누르면 그것을 적는 책 정보 탭 이름('rate' · 'mine')을 돌려주고 닫힌다
Future<String?> openBookShare(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<String>(settings: const RouteSettings(name: '/book/share'), builder: (_) => BookShareScreen(id: id)));

class BookShareScreen extends StatefulWidget {
  const BookShareScreen({super.key, required this.id});
  final String id;

  @override
  State<BookShareScreen> createState() => _BookShareScreenState();
}

class _BookShareScreenState extends State<BookShareScreen> {
  final _model = LibraryModel.instance;
  // 한줄평은 책 정보 › 평가에서 쓴다(이 화면의 '내 평가' 칸은 2026-11-17 시안에 맞춰 뺐다)
  String get _note => _model.lib.books[widget.id]?.note ?? '';
  ShareParts _parts = defaultParts;
  String? _busy; // save · share
  bool _saved = false, _canSave = false, _coverWaiting = true;
  Timer? _savedTimer;
  ShareSceneAssets? _assets;
  // 미리보기 그림(같은 입력·폭이면 다시 그리지 않는다)
  ui.Image? _preview;
  Object? _previewKey;
  // 비어 있는 칩을 누르면 쓰는 자리로 데려간다(2026-11-15 QA: 빈 '한 줄 감상'·'별점' 칩은 눌러도 반응이 없었다)
  String? _hint; // 방금 누른 빈 칩: 그 안내 줄을 잠깐 진하게
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    gallerySaveAvailable().then((v) {
      if (mounted) setState(() => _canSave = v);
    });
    _load();
  }

  // 그림 재료(바탕·오버레이·셰이더)와 표지. 표지는 책장과 같은 표지 보관으로 받는다(오프라인에서 멈추지 않게)
  Future<void> _load() async {
    final place = PlacementStore.instance;
    await place.ensure();
    final a = await loadShareAssets();
    final book = place.books[widget.id];
    final uri = coverAtSize(book?.coverArtUri ?? book?.coverUri, 'XL');
    if (!mounted) return;
    setState(() {
      _assets = a;
      _coverWaiting = uri != null;
    });
    if (uri == null) return;
    final img = await loadCover(uri);
    if (!mounted) return;
    setState(() {
      _assets = a.withCover(img);
      _coverWaiting = false;
    });
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    _savedTimer?.cancel();
    _hintTimer?.cancel();
    _preview?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }


  /// 비어 있는 항목을 누르면 바로 그것을 채우는 곳으로(2026-11-18 사용자 '없는 애 누르면 바로 추가 페이지로'):
  /// 한줄평·별점은 책 정보 › 평가, 읽은 기간은 내 기록(돌려준 탭으로 책 정보가 바꾼다), 독서 시간은 이 책으로 읽기 시작
  void _empty(String k) {
    switch (k) {
      case 'note' || 'rating':
        Navigator.of(context).pop('rate');
        return;
      case 'period':
        Navigator.of(context).pop('mine');
        return;
      case 'time':
        startReadingBook(context, widget.id);
        return;
    }
    _hintFor(k);
  }

  void _hintFor(String k) {
    _hintTimer?.cancel();
    setState(() => _hint = k == 'note' || k == 'rating' ? 'eval' : k);
    _hintTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  BookShareData? get _data {
    final d = bookShareData(_model.lib, widget.id, PlacementStore.instance.books[widget.id]);
    return d?.withNote(_note.trim().isEmpty ? null : _note.trim());
  }

  // 저장·공유 모두 같은 그림(폭 1080px)을 그린다
  Future<void> _run(String kind) async {
    final d = _data;
    if (_busy != null || d == null) return;
    setState(() => _busy = kind);
    try {
      // 표지를 받는 중이면 잠깐(최대 6초) 기다린다. 끝내 없으면 표지 색으로 그린다
      for (var t = 0; t < 6000 && (_assets == null || _coverWaiting); t += 150) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      final a = _assets;
      if (a == null) throw ShareImageError('image', '카드 이미지를 만들지 못했어요. 다시 눌러 주세요.');
      final img = renderShareCard(a, shareInputOf(d, _parts), _exportW);
      final png = await pngOf(img);
      img.dispose();
      if (kind == 'save') {
        await savePng(png, name: 'chaekjang_book');
        if (!mounted) return;
        setState(() => _saved = true);
        _savedTimer?.cancel();
        _savedTimer = Timer(const Duration(milliseconds: 2400), () {
          if (mounted) setState(() => _saved = false);
        });
      } else {
        await sharePng(png, name: 'chaekjang_book', title: '책 공유');
      }
    } catch (e) {
      if (mounted) appAlert(context, shareErrorTitle(e), '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _card(BookShareData d, double width) {
    final input = shareInputOf(d, _parts);
    final a = _assets;
    final height = width * shareCardAspect(input);
    if (a != null) {
      final px = (width * MediaQuery.devicePixelRatioOf(context)).round();
      final key = (input, px, a);
      if (key != _previewKey) {
        _preview?.dispose();
        _preview = renderShareCard(a, input, px);
        _previewKey = key;
      }
    }
    return Semantics(
      label: '${d.title} 공유 카드',
      image: true,
      child: Container(
        width: width,
        height: height,
        color: _wall,
        child: a == null || _preview == null ? null : RawImage(image: _preview, width: width, height: height, fit: BoxFit.fill),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _model.lib.books[widget.id];
    final d = _data;
    if (b == null || d == null) {
      return Screen(title: '책 공유', children: [
        Empty(title: '책을 찾을 수 없어요', action: '책장으로', onAction: () => Navigator.of(context).popUntil((r) => r.isFirst)),
      ]);
    }
    final has = {'note': d.note != null, 'rating': d.rating != null && d.rating != 0, 'time': d.readTime != null, 'period': d.period != null};
    final on = {'note': _parts.note, 'rating': _parts.rating, 'time': _parts.time, 'period': _parts.period};
    void toggle(String k) => setState(() => _parts = (
          note: k == 'note' ? !_parts.note : _parts.note,
          rating: k == 'rating' ? !_parts.rating : _parts.rating,
          time: k == 'time' ? !_parts.time : _parts.time,
          period: k == 'period' ? !_parts.period : _parts.period,
        ));
    final width = MediaQuery.sizeOf(context).width;
    // 미리보기는 화면에 맞춰 줄인 같은 카드(옵션이 보이게 화면 폭의 3/4 정도)
    final previewW = [width - Space.page * 2, math.max(240.0, width * 0.66), 340.0].reduce(math.min);
    final hair = 1 / MediaQuery.devicePixelRatioOf(context);
    // 비어 있는 것이 생기는 법(한 줄씩, 낱말 단위로 줄바꿈: '완/독일'처럼 낱말이 갈리지 않게)
    final missing = {
      if (!has['note']! || !has['rating']!) 'eval': '비어 있는 한줄평, 별점을 누르면 평가에서 적을 수 있어요',
      if (!has['time']!) 'time': '독서 시간을 누르면 이 책으로 타이머를 켜요',
      if (!has['period']!) 'period': '읽은 기간을 누르면 내 기록에서 날짜를 적어요',
    };
    return Screen(
      title: '책 공유',
      footer: Row(children: [
        if (_canSave) ...[
          Expanded(child: Btn(label: _saved ? '저장했어요' : '저장', kind: 'secondary', size: 'l', busy: _busy == 'save', disabled: _busy != null && _busy != 'save', onPress: () => _run('save'))),
          const SizedBox(width: Space.s),
        ],
        Expanded(child: Btn(label: '공유', size: 'l', busy: _busy == 'share', disabled: _busy != null && _busy != 'share', onPress: () => _run('share'))),
      ]),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Center(
            // 바탕이 흰색이라 카드 가장자리를 옅은 선과 그림자로 보인다(내보내는 그림에는 없다)
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line, width: hair),
                boxShadow: const [BoxShadow(color: Color(0x14191F28), offset: Offset(0, 6), blurRadius: 20)],
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(14), child: _card(d, previewW)),
            ),
          ),
        ),
        // 표시할 정보: 두 칸씩 체크 상자(2026-11-17 사용자 시안). 내용이 없는 것은 옅게, 누르면 생기는 법을 알린다
        const H2('표시할 정보'),
        for (final pair in [['note', 'rating'], ['time', 'period']])
          Row(children: [
            for (final k in pair)
              Expanded(
                child: _CheckLine(
                  label: _partLabel[k]!,
                  on: on[k]! && has[k]!,
                  enabled: has[k]!,
                  onPress: has[k]! ? () => toggle(k) : () => _empty(k),
                ),
              ),
          ]),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in missing.entries)
                Text(keepAll(e.value),
                    semanticsLabel: e.value, style: _hint == e.key ? AppType.caption.copyWith(color: AppColors.ink, fontFamily: AppFonts.uiBold) : AppType.caption),
            ]),
          ),
      ],
    );
  }
}

/// 체크 상자 한 줄(표시할 정보): 네모 상자 24(고르면 갈색 채움 + 흰 체크) + 글. 누르는 자리 48
class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.label, required this.on, required this.enabled, required this.onPress});
  final String label;
  final bool on, enabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        checked: on,
        enabled: enabled,
        label: label,
        onTap: onPress,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on ? AppColors.accent : AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: on ? null : Border.all(color: AppColors.inkFaint, width: 1.5),
                  ),
                  child: on ? const Center(child: LucideIcon('Check', size: 16, color: AppColors.bg, stroke: 2.6)) : null,
                ),
                const SizedBox(width: Space.m),
                Flexible(child: WordText(label, style: AppType.bodySmall)),
              ]),
            ),
          ),
        ),
      );
}
