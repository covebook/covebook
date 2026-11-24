// 재장정 미리보기·편집(지금 앱 features/book/BindingEditor.tsx: 책 추가 확인 화면과 책 꾸미기가 함께 쓴다). 2026-10-10 시안: 책 미리보기 → 그림·색상·재질 탭 → 그 탭의 옵션.
// 책장과 같은 책 그림·빛으로 같은 책을 돌려 보며 고른 장정이 바로 반영된다.
// - 그림: 기본 정면 장정 6종(3열) + '그림 없음'(단색 정면 또는 실제 표지). 그림을 골라도 책 색은 그대로
// - 색상: 표지 색(많은 순서) + 이 책 추천 색 + 모든 색 + 직접 고르기(R · G · B 막대와 색 코드, 2026-11-21 사용자 '표지색 rgb 고를 수 있게').
//   고른 색에 테두리와 체크. 추천 장정으로 되돌리기
// - 재질: 고운 종이·린넨·매끈 무광·줄무늬 종이 + 책등 글자 배치
// - 갈피(책 꾸미기만, onRibbon이 있을 때. 책이 아직 없는 책 추가 확인에는 없다): 자동(표지에서 고른 색) · 표지 색 · 다른 색.
//   미리보기 책 머리에 갈피 탭을 고른 색으로 그린다(2026-11-23 사용자: 갈피 색 시트를 장정 편집 안으로, 저장도 함께)
// 탭을 바꿔도 고르던 값은 그대로다(값은 부르는 쪽이 가진다). 고르면 사용자 장정(source 'custom')
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/binding_draft.dart';
import '../../domain/color.dart' show isNeutralColor, paperColors, ribbonPalette;
import '../../domain/cover_artworks.dart';
import '../../domain/cover_url.dart' show coverAtSize, spineRatioOf;
import '../../domain/geometry.dart' show realDimensions;
import '../../domain/rebinding.dart';
import '../../domain/types.dart';

import '../../services/cover_colors.dart' show coverPalette;
import '../../ui/kit.dart';
import '../../ui/standalone_book.dart';
import '../../ui/theme.dart';

export '../../domain/binding_draft.dart';

const _layoutNames = {'spine_a': '기본', 'spine_b': '제목 낮게', 'spine_c': '무늬 낮게'};
const _materials = ['fine', 'linen', 'matte', 'laid'];
const _materialNames = {'fine': '고운 종이', 'linen': '린넨', 'matte': '매끈 무광', 'laid': '줄무늬 종이'};

int _hex(String h) => int.tryParse(h.substring(1, 7), radix: 16) ?? 0x8F6E55;

/// 추천 장정으로 되돌린 값(장정 편집 '초기화' · 색상 '추천 장정으로 되돌리기'가 같은 값). 무늬 씨앗은 지금 것을 둔다.
/// 추천 장정에는 재질 · 표지 그림이 없다(BindingDraft.of · recommended)
BindingDraft resetBinding(BindingDraft rec, num seed) =>
    BindingDraft(spineColor: rec.spineColor, motif: rec.motif, seed: seed, inkColor: rec.inkColor, accentColor: rec.accentColor, layout: rec.layout);

/// 미리보기 책: 고른 장정으로 그린 책(실제 표지가 있고 그림을 고르지 않았으면 정면은 실제 표지)
/// id: 책이 있으면 그 책 id(책장과 같은 결 · 갈피 탭 모양), 없으면 'preview'
Book previewBook({required String title, String? author, ({num widthMm, num heightMm})? size, num? pages, required BindingDraft binding, String? realCover, String id = 'preview'}) {
  final w = (size?.widthMm ?? 128).toDouble(), h = (size?.heightMm ?? 188).toDouble();
  final art = isCoverArtworkId(binding.coverArtId);
  return Book(
    id: id,
    title: title.isEmpty ? '제목' : title,
    author: author == null || author.isEmpty ? null : author,
    themeColor: _hex(binding.spineColor),
    coverAspectRatio: w / h,
    physical: Physical(widthMm: w, heightMm: h, pages: (pages ?? 250).toInt()),
    dims: realDimensions(w, h, (pages ?? 250).toInt(), spineRatioOf(realCover)),
    coverArtUri: art ? null : coverAtSize(realCover, 'XL'),
    coverUri: realCover,
    inkColor: binding.inkColor,
    titleTop: switch (binding.layout ?? 'spine_a') {
      'spine_b' => 0.16,
      'spine_c' => 0.11,
      _ => null,
    },
    material: binding.material,
    coverArtId: art ? binding.coverArtId : null,
  );
}

/// current: 아직 아무것도 고르지 않았을 때 보여 줄 지금 모습(책장에 놓인 그대로). 하나라도 고르면 고른 장정으로 바뀐다
class BindingEditor extends StatefulWidget {
  const BindingEditor({
    super.key,
    required this.title,
    this.author,
    this.size,
    this.pages,
    required this.value,
    required this.recommended,
    this.current,
    this.realCover,
    required this.onChange,
    this.bookId,
    this.ribbon,
    this.marks = 0,
    this.onRibbon,
  });
  final String title;
  final String? author, realCover;
  final ({num widthMm, num heightMm})? size;
  final num? pages;
  final BindingDraft value, recommended;
  final Book? current;
  final ValueChanged<BindingDraft> onChange;

  /// 책 꾸미기의 책 id(책 추가 확인처럼 책이 아직 없으면 null)
  final String? bookId;

  /// 고른 갈피 색(null = 표지에서 고른 색). onRibbon이 있을 때만 '갈피' 칸이 보인다
  final String? ribbon;

  /// 이 책의 갈피 수(미리보기 탭 수, 없어도 하나는 그린다)
  final int marks;
  final ValueChanged<String?>? onRibbon;

  @override
  State<BindingEditor> createState() => _BindingEditorState();
}

class _BindingEditorState extends State<BindingEditor> {
  String _tab = 'art';
  List<String> _fromCover = const [];

  @override
  void initState() {
    super.initState();
    // 표지에서 많은 색 순서(표지가 없거나 못 읽으면 빈 목록이라 줄이 보이지 않는다)
    final uri = widget.realCover == null ? null : coverAtSize(widget.realCover, 'L');
    if (uri != null) {
      coverPalette(uri, 6).then((p) {
        if (mounted) setState(() => _fromCover = coverSwatches(p));
      });
    }
  }

  Book _book(BindingDraft b) => previewBook(title: widget.title, author: widget.author, size: widget.size, pages: widget.pages, binding: b, realCover: widget.realCover, id: widget.bookId ?? 'preview');

  bool get _hasRibbon => widget.onRibbon != null && widget.bookId != null;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 갈피 칸에서는 미리보기 책 머리에 고른 색 갈피 탭(갈피가 없는 책도 하나)
    final ribbonTab = _hasRibbon && _tab == 'ribbon';
    final base = widget.current ?? _book(widget.value);
    final shown = ribbonTab ? base.withRibbon(widget.ribbon, math.max(1, widget.marks)) : base;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Column(
            children: [
              RotatableBook(key: ValueKey(shown), book: shown, frontWidth: math.min(170, width * 0.39), initialSpin: 32, shadow: true, ribbons: ribbonTab),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('드래그해서 돌려 보세요', style: AppType.caption),
              ),
            ],
          ),
        ),
        // 전환 칸은 공용 Segmented(2026-11-19 공통 규칙: 모서리 · 높이 · 그림자를 따로 그린 복사본이었다). 회색 칸은 위 여백 4 안쪽에서 시작해 16 아래에 그대로
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Segmented<String>(
            items: [('art', '그림'), ('color', '색상'), ('material', '재질'), if (_hasRibbon) ('ribbon', '갈피')],
            value: _tab,
            onChange: (id) => setState(() => _tab = id),
          ),
        ),
        switch (_tab) {
          'color' => _colorPane(),
          'material' => _materialPane(),
          'ribbon' when _hasRibbon => _ribbonPane(),
          _ => _artPane(),
        },
      ],
    );
  }

  /// 고른 칸 모서리 표시: 공용 고르는 원(켬, 20)
  Widget _check() => const RadioMark(on: true, size: 20);

  /// 그림: 6종 3열. 고른 그림만 얇은 테두리 + 작은 체크. 아래에 '그림 없음'(실제 표지가 있으면 실제 표지)
  Widget _artPane() {
    final v = widget.value;
    // 책장 모습 그대로 보여 주는 중이면 아무것도 고르지 않은 상태로 둔다
    final none = v.coverArtId == null && widget.current == null;
    return LayoutBuilder(
      builder: (_, box) {
        final cell = box.maxWidth * 0.315;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: Space.l,
                children: [
                  for (final a in coverArtworks)
                    Semantics(
                      button: true,
                      selected: v.coverArtId == a.id,
                      label: '표지 그림 ${a.name}',
                      excludeSemantics: true,
                      onTap: () => widget.onChange(v.custom(coverArtId: a.id)),
                      // 누르면 옅어지는 공용 눌림(2026-11-19 공통 규칙: 고르는 칸만 눌림 표시가 없었다)
                      child: Pressable(
                        onPress: () => widget.onChange(v.custom(coverArtId: a.id)),
                        child: SizedBox(
                          width: cell,
                          child: Column(
                            children: [
                              Container(
                                width: cell,
                                height: cell,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: v.coverArtId == a.id ? AppColors.accent : Colors.transparent, width: 1.5),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.asset(artworkThumb(a.id), fit: BoxFit.cover),
                                    ),
                                    if (v.coverArtId == a.id) Positioned(top: Space.xs, right: Space.xs, child: _check()),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(a.name, style: v.coverArtId == a.id ? AppType.caption.strong.copyWith(color: AppColors.ink) : AppType.caption),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 기본 정면 그림을 고르지 않으면: 실제 표지가 있는 책은 실제 표지(책장과 같다), 없는 책은 단색 정면
            Semantics(
              button: true,
              selected: none,
              label: widget.realCover != null ? '실제 표지' : '그림 없음, 단색 정면',
              excludeSemantics: true,
              onTap: () => widget.onChange(v.custom(coverArtId: null)),
              child: Pressable(
                onPress: () => widget.onChange(v.custom(coverArtId: null)),
                // 흰 화면 안 회색 상자 대신 고르는 칸(ChoiceBox)과 같은 흰 바탕 · 옅은 선 · 고르면 갈색 선(docs/design/DESIGN.md 1장)
                child: Container(
                  margin: const EdgeInsets.only(top: 18),
                  constraints: const BoxConstraints(minHeight: 50),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(Shape.button),
                    border: Border.all(color: none ? AppColors.accent : AppColors.line, width: none ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      if (widget.realCover != null)
                        RealCover(uri: coverAtSize(widget.realCover, 'L'), title: widget.title, color: v.spineColor, width: CoverSize.swatch)
                      else
                        Container(
                          width: 22,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(0xFF000000 | _hex(v.spineColor)),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0x1F000000)),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetaText(
                          widget.realCover != null ? '실제 표지' : ['그림 없음', '단색 정면'].join(metaSep),
                          style: none ? AppType.sub.strong.copyWith(color: AppColors.ink) : AppType.sub,
                        ),
                      ),
                      // 고른 표시는 공용 체크(20 · 굵기 2, 16 · 2.2였다)
                      if (none) const AddedMark(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 색상: 표지 색 + 이 책에 어울리는 색 + 모든 색. 맨 아래 추천 장정으로 되돌리기
  Widget _colorPane() {
    final v = widget.value, rec0 = widget.recommended;
    final rec = [
      for (final h in suggestColors(rec0.spineColor))
        if (!_fromCover.contains(h)) h,
    ];
    final rest = [
      for (final c in bookColors)
        if (!rec.contains(c.hex) && !_fromCover.contains(c.hex)) c,
    ];
    // 추천 장정에는 재질 · 표지 그림이 없다(resetBinding)
    final same = v.spineColor == rec0.spineColor && v.motif == rec0.motif && v.layout == rec0.layout && (v.material ?? 'fine') == 'fine' && v.coverArtId == null;
    void pick(String hex) {
      final t = tonesFor(hex);
      widget.onChange(v.custom(spineColor: hex, inkColor: t.inkColor, accentColor: t.accentColor));
    }

    // 지금 색이 위 목록에 없으면(직접 고른 색 · 표지 사진에서 온 색) '직접 고르기' 칸에 그 색을 고른 채로 보인다
    final listed = {..._fromCover, ...rec, for (final c in bookColors) c.hex};
    final mine = listed.contains(v.spineColor) ? null : v.spineColor;
    Widget swatch(String hex, String name) {
      final on = v.spineColor == hex;
      return Semantics(
        button: true,
        selected: on,
        label: '책 색 $name',
        excludeSemantics: true,
        onTap: () {
          final t = tonesFor(hex);
          widget.onChange(v.custom(spineColor: hex, inkColor: t.inkColor, accentColor: t.accentColor));
        },
        child: Pressable(
          onPress: () {
            final t = tonesFor(hex);
            widget.onChange(v.custom(spineColor: hex, inkColor: t.inkColor, accentColor: t.accentColor));
          },
          // 누르는 칸 48(44였다). 칸 사이를 4 줄여 원 사이 간격은 그대로
          child: SizedBox(
            width: Space.hit,
            height: Space.hit,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | _hex(hex)),
                  shape: BoxShape.circle,
                  border: Border.all(color: on ? AppColors.accent : const Color(0x14000000), width: on ? 2.5 : 1),
                ),
                child: on ? Center(child: LucideIcon('Check', size: 16, color: Color(0xFF000000 | _hex(tonesFor(hex).inkColor)), stroke: 2.4)) : null,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 구역 제목은 공용 H2(화면 읽기 머리, 아래 8. 따로 그린 제목은 아래 12였다)
        if (_fromCover.isNotEmpty) ...[
          const H2('표지 색'),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [for (final (i, h) in _fromCover.indexed) swatch(h, '표지 색 ${i + 1}')]),
        ],
        const H2('이 책에 어울리는 색'),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [for (final (i, h) in rec.indexed) swatch(h, i == 0 ? '추천' : '추천 ${i + 1}')]),
        const H2('모든 색'),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [for (final c in rest) swatch(c.hex, c.name)]),
        const H2('직접 고르기'),
        Row(children: [
          if (mine != null) ...[swatch(mine, '지금 색 ${mine.toUpperCase()}'), const SizedBox(width: Space.s)],
          Btn(
            label: 'RGB로 고르기',
            kind: 'secondary',
            size: 'medium',
            onPress: () async {
              final hex = await pickRgbColor(context, v.spineColor);
              if (hex != null && mounted) pick(hex);
            },
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: Space.group),
          // 머리줄 '초기화'와 같은 일이라 같은 말(2026-11-19 공통 규칙: '되돌리기'는 토스트 단추 말)
          child: TextLink(
            label: '추천 장정으로 초기화',
            soft: true,
            disabled: same && v.source != 'custom',
            onPress: () => widget.onChange(resetBinding(rec0, v.seed)),
          ),
        ),
      ],
    );
  }

  /// 갈피(옛 갈피 색 시트 features/bookmark/ribbon_color_sheet.dart를 옮긴 것): 책마다 하나. 책장 갈피 탭 · 갈피 카드 뒤 종이 · 테이프가 함께 바뀐다.
  /// 자동 = 표지에서 고른 색. 표지에서 뽑은 색(무채색 빼고)과 기본 색 중에서 고르고, 자동으로 되돌릴 수 있다. 저장은 화면 아래 '꾸미기 저장'과 함께
  Widget _ribbonPane() {
    final id = widget.bookId!, picked = widget.ribbon;
    void pick(String? c) => widget.onRibbon!(c);
    final fromCover = [for (final c in _fromCover) if (!isNeutralColor(c)) c];
    final hair = 1 / MediaQuery.devicePixelRatioOf(context);
    // 색 견본: 색상 칸과 같은 크기(원 40 · 누르는 칸 48). 색은 갈피 테이프 색, 화면 읽기는 색 코드 대신 '갈피 색 N' · '표지 색 N'(DESIGN 15장)
    Widget swatches(List<String> list, String name) => Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          for (final (i, c) in list.indexed)
            Builder(builder: (_) {
              final on = picked?.toLowerCase() == c.toLowerCase();
              return Semantics(
                button: true,
                selected: on,
                label: '$name ${i + 1}',
                onTap: () => pick(c),
                excludeSemantics: true,
                child: Pressable(
                  onPress: () => pick(c),
                  child: SizedBox(
                    width: Space.hit,
                    height: Space.hit,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hexColor(paperColors(c, id).tape),
                          border: Border.all(color: on ? AppColors.accent : AppColors.line, width: on ? 2 : hair * 2),
                        ),
                        child: on ? const Center(child: LucideIcon('Check', size: 20, color: AppColors.accent, stroke: 2.4)) : null,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 색은 갈피마다가 아니라 책에 하나라는 걸 분명히(2026-11-16 QA 현우 F8: 한 갈피만 바꾸려 했는데 다른 갈피도 바뀌었다)
        Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: WordText('이 책의 갈피 모두가 같은 색으로 바뀌어요(책장 위 갈피 끈과 갈피 카드).', style: AppType.sub),
        ),
        // 자동은 한 줄(2026-11-24 사용자 '자동이랑 표지에서 고른 색이 같은 건데 왜 따로': 묶음 이름 '자동' 아래 '표지에서 고른 색' 줄이었다)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: FilterOption(label: '자동', selected: picked == null, onPress: () => pick(null)),
        ),
        if (fromCover.isNotEmpty) ...[const H2('표지 색'), swatches(fromCover, '표지 색')],
        const H2('다른 색'),
        swatches(ribbonPalette, '갈피 색'),
      ],
    );
  }

  /// 재질: 이 책 색에 그 재질의 결을 크게 그린 견본 + 책등 글자 배치(이 책 책등)
  Widget _materialPane() {
    final v = widget.value;
    final material = v.material ?? 'fine', layout = v.layout ?? 'spine_a';
    return LayoutBuilder(
      builder: (_, box) {
        // 고르는 칸 하나(재질 견본 · 책등 글자가 같은 꾸밈: 둥근 모서리 · 고르면 갈색 테두리와 모서리 원). 높이는 폭의 0.86
        Widget tileBox({required double width, required bool on, required Widget child, bool spine = false}) => Container(
              width: width,
              height: width * 0.86,
              decoration: BoxDecoration(
                color: spine ? AppColors.bg : AppColors.surface,
                borderRadius: BorderRadius.circular(Shape.input),
                border: Border.all(color: on ? AppColors.accent : (spine ? AppColors.line : Colors.transparent), width: spine && !on ? 1.5 : 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  child,
                  if (on) Positioned(top: 7, right: 7, child: _check()),
                ],
              ),
            );
        Widget name(String t, bool on) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t, style: on ? AppType.caption.strong.copyWith(color: AppColors.ink) : AppType.caption),
            );
        // 책등 배율: 칸 높이에 맞게
        final tile = (box.maxWidth - 16) / 3;
        final swatchW = (box.maxWidth - 24) / 4;
        final spineBook = _book(v);
        final spineH = (spineBook.dims?.height ?? 188) + bookPad * 2;
        final zoom = tile * 0.8 / spineH;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const H2('표면'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final m in _materials)
                  Semantics(
                    button: true,
                    selected: material == m,
                    label: '재질 ${_materialNames[m]}',
                    excludeSemantics: true,
                    onTap: () => widget.onChange(v.custom(material: m)),
                    child: Pressable(
                      onPress: () => widget.onChange(v.custom(material: m)),
                      child: SizedBox(
                        width: swatchW,
                        child: Column(
                          children: [
                            tileBox(
                              width: swatchW,
                              on: material == m,
                              child: Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: CustomPaint(painter: _MaterialSwatch(m, Color(0xFF000000 | _hex(v.spineColor)))),
                                ),
                              ),
                            ),
                            name(_materialNames[m]!, material == m),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const H2('책등 글자'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final l in const ['spine_a', 'spine_b', 'spine_c'])
                  Semantics(
                    button: true,
                    selected: layout == l,
                    label: '책등 글자 ${_layoutNames[l]}',
                    excludeSemantics: true,
                    onTap: () => widget.onChange(v.custom(layout: l)),
                    child: Pressable(
                      onPress: () => widget.onChange(v.custom(layout: l)),
                      child: Column(
                        children: [
                          tileBox(
                            width: tile,
                            on: layout == l,
                            spine: true,
                            child: IgnorePointer(
                              child: StandaloneBook(
                                book: _book(v.custom(layout: l)),
                                pose: Pose.upright,
                                scale: zoom,
                              ),
                            ),
                          ),
                          name(_layoutNames[l]!, layout == l),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 재질 견본: 책 그림의 결은 아주 은은해서 작은 칸에서는 똑같아 보인다. 견본은 결을 과장해 차이가 보이게 그린다
/// 고운 종이 = 고른 잔 얼룩, 린넨 = 가로세로 실 짜임, 줄무늬 종이 = 가로 줄, 매끈 무광 = 비스듬한 광택
class _MaterialSwatch extends CustomPainter {
  _MaterialSwatch(this.material, this.color);
  final String material;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Shape.input));
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    if (material == 'fine') {
      var x = 7;
      double rnd() => (x = (x * 16807) % 2147483647) / 2147483647;
      for (var i = 0; i < 140; i++) {
        final cx = rnd() * w, cy = rnd() * h, rr = 0.5 + rnd() * 1.4, o = 0.05 + rnd() * 0.08, dark = rnd() > 0.25;
        canvas.drawCircle(Offset(cx, cy), rr, Paint()..color = (dark ? Colors.black : Colors.white).withValues(alpha: dark ? o : o * 0.5));
      }
    }
    if (material == 'linen' || material == 'laid') {
      final horiz = Paint()
        ..color = Colors.black.withValues(alpha: material == 'linen' ? 0.22 : 0.14)
        ..strokeWidth = material == 'linen' ? 1.1 : 1;
      for (var y = 1.0; y < h; y += 3) {
        canvas.drawLine(Offset(0, y), Offset(w, y), horiz);
      }
      if (material == 'linen') {
        final vert = Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..strokeWidth = 1.1;
        for (var x2 = 1.0; x2 < w; x2 += 3) {
          canvas.drawLine(Offset(x2, 0), Offset(x2, h), vert);
        }
      }
    }
    final shade = material == 'matte'
        ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x33FFFFFF), Color(0x0AFFFFFF), Color(0x38000000)], stops: [0, 0.45, 1])
        : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x0FFFFFFF), Color(0x14000000)]);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shade.createShader(Offset.zero & size));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaterialSwatch old) => old.material != material || old.color != color;
}

/// 색 직접 고르기 시트: R · G · B 막대(0~255)와 색 코드(#RRGGBB), 위에 고른 색 미리보기. '이 색으로'를 누르면 '#rrggbb', 닫으면 null
Future<String?> pickRgbColor(BuildContext context, String start) {
  var rgb = [for (var i = 0; i < 3; i++) (_hex(start) >> (16 - 8 * i)) & 0xFF];
  var code = _rgbCode(rgb);
  return showSheet<String>(
    context,
    title: '색 직접 고르기',
    scroll: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final color = Color(0xFF000000 | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]);
        Widget channel(int i, String name) => Row(children: [
              SizedBox(width: 24, child: Text(name, style: AppType.sub.strong.copyWith(color: AppColors.ink))),
              Expanded(
                child: AppSlider(
                  label: '$name 값',
                  value: rgb[i] / 255,
                  valueText: '${rgb[i]}',
                  onChange: (x) => set(() {
                    rgb[i] = (x * 255).round();
                    code = _rgbCode(rgb);
                  }),
                  onCommit: (x) => set(() {
                    rgb[i] = (x * 255).round();
                    code = _rgbCode(rgb);
                  }),
                ),
              ),
              SizedBox(width: 40, child: Text('${rgb[i]}', textAlign: TextAlign.end, style: AppType.sub.tnum)),
            ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: const Color(0x14000000))),
            ),
            const SizedBox(width: Space.l),
            Text(code.toUpperCase(), style: AppType.row.tnum),
          ]),
          const SizedBox(height: Space.l),
          channel(0, 'R'),
          channel(1, 'G'),
          channel(2, 'B'),
          const SizedBox(height: Space.l),
          // 색 코드를 넣으면 막대도 그 값으로(여섯 자리가 다 맞을 때만)
          Field(
            label: '색 코드',
            value: code,
            placeholder: '#RRGGBB',
            onChange: (t) {
              final h = t.trim().replaceFirst('#', '');
              final n = h.length == 6 ? int.tryParse(h, radix: 16) : null;
              if (n == null) return;
              set(() {
                rgb = [(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
                code = _rgbCode(rgb);
              });
            },
          ),
          Btn(label: '이 색으로', onPress: () => Navigator.pop(ctx, code)),
        ]);
      },
    ),
  );
}

String _rgbCode(List<int> rgb) => '#${[for (final c in rgb) c.toRadixString(16).padLeft(2, '0')].join()}';
