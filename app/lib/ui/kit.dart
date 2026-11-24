// 공용 화면 부품: 화면 틀·버튼·목록 줄·전환 칸·거르기 단추·하단 시트·빈 화면·대체 표지.
// 디자인 시안(toss-official): 토스 TDS Mobile 공식 문서의 부품 기본값(크기 종류 · 색 · 여백 · 눌림 · 닫힘 동작)을 따른다. 값마다 출처는 시안 기록 DESIGN-APPLIED.md(design/toss-official 시안).
// 공식에 숫자가 없는 곳(단추 높이 · 모서리 · 그림자)은 지금 앱 값을 쓰고 '공식 없음'으로 적었다
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../gen/lucide.g.dart';
import '../services/cover_cache.dart';
import '../store/mini_timer_store.dart';
import '../store/reading_store.dart';
import 'keep_all.dart';
import 'theme.dart';

/// 간격. TDS에는 간격 단계 토큰이 없다(Foundation은 Colors · Typography뿐) → 단계는 지금 앱 값(4·8·12·16·28·40).
/// 부품에 박힌 공식 숫자는 아래 이름으로 따로 둔다(ListRow · Top · BottomSheet · BottomCTA · Border)
abstract final class Space {
  /// 화면 좌우 24 = TDS ListRow horizontalPadding medium(기본) 24 · Border padding24
  /// 구역 사이 section 40 → 32(2026-11-24 사용자 7단계) → 24(같은 날: 구역 제목 줄이 누르는 자리 때문에 48이라 실제 틈이 55~65로 보였다. 토스 실측 47~57)
  static const page = 24.0, section = 24.0, group = 28.0, item = 12.0, tight = 8.0;
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 28.0, xxl = 40.0;
  static const touch = 44.0;

  /// 한 화면 안 구역 사이(책 정보의 독서 기록 · 읽은 기간 · 남긴 갈피, 통계 그래프 사이). 같은 종류 구역은 이 간격만 쓴다(2026-11-18).
  /// 48 → 32(2026-11-24 사용자 7단계) → 24(같은 날: 구역 제목 줄 48 안 빈 자리까지 더해 내용과 다음 제목 사이가 토스 실측 47~57에 가깝게)
  static const block = 24.0;

  /// 촘촘한 정보 줄 높이(내 기록의 시간대 · 읽은 시간 줄)
  static const dense = 32.0;

  /// 누르는 자리 최소(안드로이드 접근성 기준 48). 겉모양은 그대로 두고 누르는 자리만 넓힐 때(2026-11-16 QA 영숙 F12)
  static const hit = 48.0;

  /// TDS ListRow verticalPadding: small 8 · medium 12(기본) · large 16 · xlarge 24(ListRow 이해하기 절 ListRowProps)
  static const rowS = 8.0, rowM = 12.0, rowL = 16.0, rowXL = 24.0;

  /// TDS BottomCTA paddingBottom: max(안전 영역, 20px)(BottomCTA Single · Double 절). 화면 아래 고정 단추 · 시트 아래 여백
  static const ctaBottom = 20.0;

  /// 구간을 나누는 회색 띠 높이. TDS Border variant height16(Border 절)은 16이지만 두꺼워 보여 반으로
  /// (2026-11-21 사용자 '이 선 좀 두껍지 않나? 이것도 토스 기준이야?'). 통계 분석 띠 사이 · 책 정보 · 책별 기록 구간 띠가 모두 이 값
  static const band = 8.0;

  /// 통계의 흰 띠(Band) 안 위아래(2026-11-20 토스 공식+: 회색 바탕 위 좌우 끝까지 붙인 흰 띠. 띠 사이는 band 회색)
  static const bandPad = 24.0;

  /// 이름 → 값(토큰 내보내기 · 검사용). 값이 같아도 역할이 다르면 이름을 따로 둔다(group 28 · xl 28 등)
  static const all = <String, double>{
    'page': page, 'section': section, 'group': group, 'item': item, 'tight': tight,
    'xs': xs, 's': s, 'm': m, 'l': l, 'xl': xl, 'xxl': xxl, 'touch': touch, 'block': block, 'dense': dense, 'hit': hit,
    'rowS': rowS, 'rowM': rowM, 'rowL': rowL, 'rowXL': rowXL, 'ctaBottom': ctaBottom, 'band': band, 'bandPad': bandPad,
  };
}

/// 정보 사이 구분: 가운데 점(·) 대신 세로줄(2026-11-18 사용자 '가운데 점 전부 빼고 | 선으로'). 글로 이어 붙일 때 쓴다
const metaSep = ' | ';

/// 진행 막대(쪽수 · 찾기 · 추가 진행): 두께 10, 끝 둥글게. value가 null이면 움직이는 막대
/// (2026-11-18 사용자 '얇다, 높이 조금 늘리고 다른 곳도': 내 기록 8, 목록 가져오기·여러 권 추가 6이었다)
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.soft = false});
  final double? value;

  /// 옅은 갈색(대표색을 흰 바탕에 65%, 내 기록 쪽수 시안)
  final bool soft;
  static const height = 10.0;

  @override
  Widget build(BuildContext context) {
    final fill = soft ? AppColors.accent.withValues(alpha: 0.65) : AppColors.accent;
    final v = value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: v == null
          ? LinearProgressIndicator(minHeight: height, color: fill, backgroundColor: AppColors.line)
          : SizedBox(
              height: height,
              child: Stack(children: [
                const Positioned.fill(child: ColoredBox(color: AppColors.line)),
                FractionallySizedBox(
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(height / 2))),
                ),
              ]),
            ),
    );
  }
}

/// 줄(Row) 안에서 두 글자·단추를 가르는 옅은 세로줄(가운데 점 대신, 2026-11-18)
class MetaBar extends StatelessWidget {
  const MetaBar({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.s), child: const SizedBox(width: 1, height: 12, child: ColoredBox(color: AppColors.metaBar))),
      );
}

/// [metaSep]으로 이은 정보 줄: 세로줄만 한 단계 옅게 그리고, 화면 읽기는 쉼표로 읽는다('세로 막대'라고 읽지 않게)
class MetaText extends StatelessWidget {
  const MetaText(this.text, {super.key, this.style, this.maxLines, this.overflow, this.textAlign, this.softWrap});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final parts = text.split(metaSep);
    if (parts.length == 1) return WordText(text, style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign, softWrap: softWrap);
    final base = DefaultTextStyle.of(context).style.merge(style);
    const bar = TextStyle(color: AppColors.metaBar, fontFamily: AppFonts.ui);
    final spans = <InlineSpan>[];
    for (final (i, p) in parts.indexed) {
      if (i > 0) spans.add(const TextSpan(text: metaSep, style: bar));
      spans.add(TextSpan(text: keepAll(p)));
    }
    return Text.rich(TextSpan(style: base, children: spans),
        maxLines: maxLines, overflow: overflow, textAlign: textAlign, softWrap: softWrap, semanticsLabel: parts.join(', '));
  }
}

/// 낱말 단위로 줄을 바꾸는 글자(keepAll: 한글이 '읽기 시 / 작'처럼 낱말 가운데서 끊기지 않게, 2026-11-16 QA 영숙 F6·현우 F10).
/// 그리는 글자에만 이음표를 넣고, 화면 읽기와 글자 찾기(data)는 원문 그대로다
class WordText extends Text {
  const WordText(super.data, {super.key, super.style, super.textAlign, super.maxLines, super.overflow, super.softWrap, super.textScaler, super.semanticsLabel});

  @override
  Widget build(BuildContext context) =>
      Text(keepAll(data!), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap, textScaler: textScaler, semanticsLabel: semanticsLabel ?? data).build(context);
}

/// 모서리(유일한 정의, docs/design/DESIGN.md 7-2): 조작 요소 10, 시트 20, 확인창 18, 알약.
/// TDS에 모서리 · 그림자 토큰이 없다(Foundation은 Colors · Typography뿐) → 모두 지금 앱 값
abstract final class Shape {
  static const button = 10.0, input = 10.0, sheet = 20.0, dialog = 18.0, tag = 6.0;

  /// 테두리 상자(읽은 기간 카드 · 통계 평균 카드)
  static const card = 12.0;

  /// 고르는 큰 칸(Choice) 14 · 전환 칸 바깥 12 · 고른 칸 9 · 칩 알약
  static const choice = 14.0, segmented = 12.0, segment = 9.0, pill = 999.0;

  /// 낮은 전환 칸(머리줄 안, 회색 칸 36): 바깥 8 · 고른 칸 6. 높이에 비해 12 · 9가 알약처럼 너무 둥글었다(2026-11-20 사용자 '버튼 모서리가 유난히 둥근데')
  static const segmentedCompact = 8.0, segmentCompact = 6.0;

  /// 표지 · 대체 표지 · 줄 안 막대 끝 3
  static const cover = 3.0;

  /// 떠 있는 것(떠 있는 단추 · 미니 타이머 · 메뉴)
  static const floatShadow = BoxShadow(color: Color(0x1F191F28), offset: Offset(0, 4), blurRadius: 10);

  /// 전환 칸의 고른 칸
  static const segmentShadow = BoxShadow(color: Color(0x14191F28), offset: Offset(0, 2), blurRadius: 6);

  /// 이름 → 값(토큰 내보내기 · 검사용)
  static const all = <String, double>{
    'button': button, 'input': input, 'sheet': sheet, 'dialog': dialog, 'tag': tag, 'card': card,
    'choice': choice, 'segmented': segmented, 'segment': segment, 'segmentedCompact': segmentedCompact, 'segmentCompact': segmentCompact, 'pill': pill, 'cover': cover,
  };
}

/// 조작부 크기(유일한 정의, docs/design/DESIGN.md 5-2 · 7장). 누르는 자리는 겉크기와 따로 늘 [Space.hit] 이상
abstract final class ControlSize {
  /// 단추 보이는 높이 = TDS Button 크기(높이 숫자는 공식 글에 없음 → 지금 앱 값): buttonL = xlarge(기본값: 화면 아래 고정 · 시트 안) ·
  /// buttonM = large(확인창 두 단추 · 빈 화면 · 카드 안) · buttonS = medium(줄 안 작은 단추) · small(사진 단추처럼 안쪽 여백만 좁은 것)
  static const buttonL = 52.0, buttonM = 48.0, buttonS = 40.0;

  /// 입력칸 · 고르는 칸(Field · SelectField · DateField · TimeField) 48(검색칸과 같다. 56이었다: 2026-11-21 사용자 '쪽수 박스 두께가 좀 두껍지 않나'), 여러 줄 입력칸 110, 검색칸 48.
  /// 검색칸: 11-18 사용자 '두께 좀 줄이고'로 52 → 44를 넣었지만 안쪽 검색 아이콘 칸(누르는 자리 48)이 높이를 정해 실제로는 48로 그려진다(2026-11-19 값 대조에서 발견). 지금 화면 그대로 48
  static const field = 48.0, fieldMultiline = 110.0, search = 48.0;

  /// 고르는 큰 칸(Choice) 56
  static const choice = 56.0;

  /// 전환 칸(Segmented): 고른 칸 38 + 위아래 7 = 줄 52(누르는 자리), 회색 칸은 위아래 4를 뺀 44
  static const segment = 38.0, segmentPad = 7.0, segmentInset = 4.0;

  /// 낮은 전환 칸(머리줄 안: 꾸미기 '책 배치 · 선반 · 벽지'): 고른 칸 30 + 위아래 9 = 줄 48(누르는 자리 그대로), 회색 칸은 위아래 6을 뺀 36
  /// (2026-11-20 사용자 '여기 버튼 세로 높이 좀 길지 않나': 옆 되돌리기 · 완료 글자 줄보다 회색 칸이 두꺼웠다)
  static const segmentCompact = 30.0, segmentCompactPad = 9.0, segmentCompactInset = 6.0;

  /// 스위치 50×30, 손잡이 24
  static const toggleWidth = 50.0, toggleHeight = 30.0, toggleKnob = 24.0;

  /// 고르는 원 · 여러 개 고르는 체크 원 24(TDS Checkbox size 기본 24, 형태는 Circle뿐: 예전 원 22 · 네모 22), 고르는 칸 모서리 체크 24
  static const radio = 24.0, choiceBadge = 24.0;

  /// 작은 돌아가는 원(단추 · 칸 · 줄 안 진행) 20, 굵기 2
  static const spinner = 20.0, spinnerStroke = 2.0;

  static const all = <String, double>{
    'buttonL': buttonL, 'buttonM': buttonM, 'buttonS': buttonS, 'field': field, 'fieldMultiline': fieldMultiline, 'search': search, 'choice': choice,
    'segment': segment, 'segmentPad': segmentPad, 'segmentInset': segmentInset,
    'segmentCompact': segmentCompact, 'segmentCompactPad': segmentCompactPad, 'segmentCompactInset': segmentCompactInset, 'toggleWidth': toggleWidth, 'toggleHeight': toggleHeight, 'toggleKnob': toggleKnob,
    'radio': radio, 'choiceBadge': choiceBadge, 'spinner': spinner, 'spinnerStroke': spinnerStroke,
  };
}

/// 아이콘 크기 · 선 굵기(유일한 정의, docs/design/DESIGN.md 6장)
abstract final class IconSize {
  /// 줄 안 기본 아이콘 22, 줄 끝 화살표 24(TDS Board Row ArrowIcon size 기본 24), 뒤로 꺾쇠 28, 선 굵기 1.6(처음 앱 lucide와 같은 굵기)
  static const base = 22.0, chevron = 24.0, back = 28.0, stroke = 1.6;

  /// 머리줄 아이콘(HeadIcon · FilterIcon) 24: TDS Icon Button iconSize 기본값
  static const head = 24.0;

  /// 이미 넣음 체크(AddedMark) 20 · 굵기 2, 고른 원 안 흰 체크 굵기 3
  static const mark = 20.0, markStroke = 2.0, checkStroke = 3.0;

  /// 줄 안 작은 표시 아이콘(내 책 목록 메모 · 갈피 카드 사진 표시): 18
  static const small = 18.0;

  static const all = <String, double>{
    'base': base, 'chevron': chevron, 'head': head, 'back': back, 'stroke': stroke, 'mark': mark, 'markStroke': markStroke, 'checkStroke': checkStroke, 'small': small,
  };
}

/// 책 표지 크기(폭, 유일한 정의, docs/design/DESIGN.md 3장)
abstract final class CoverSize {
  /// 책 한 줄(BookRow): 작게 40(고르기 · 선택 · 바코드 · 가져오기 · 읽기 목록 · 통계) · 보통 64(검색 결과 · 감상 목록) · 크게 80(내 책 목록)
  static const row = 40.0, result = 64.0, list = 64.0; // list 80 → 64(2026-11-24 사용자 7단계)

  /// 한 화면 하나뿐인 큰 표지: 책 정보 머리 140, 읽기 탭 '최근 읽던 책' 120, 책 확인(추가 전) 120.
  /// 책 정보 수정은 표지 위 끝 = '제목' 이름 줄 위, 아래 끝 = '저자' 칸 아래가 되는 폭(옆 두 칸 높이 [editHeight] × [ratio] ≈ 127.8,
  /// 2026-11-21 사용자 '책이랑 옆에 쓰는 거랑 라인이 안 맞아': 120이라 표지가 저자 칸보다 짧았다)
  static const head = 120.0, feature = 120.0, confirm = 120.0, edit = editHeight * ratio; // head 140 → 120(2026-11-24 사용자 7단계)

  /// 책 정보 수정 표지 옆 두 칸(이름 줄 24 + 8 + 입력칸 ControlSize.field, 사이 Space.xl 28) 높이 = 표지 높이
  static const editHeight = 2 * (24.0 + Space.s + ControlSize.field) + Space.xl;

  /// 창 · 시트 안 표지: '추가했어요' 88, 저장했어요 창 72(사용자 시안), 책장에 꽂기 68, 숨기기 · 삭제 확인 56
  static const added = 88.0, saved = 72.0, place = 68.0, sheet = 56.0;

  /// 작은 표지: 함께 읽기 글 안 36, 장정 고르기 칸 안 22
  static const post = 36.0, swatch = 22.0;

  /// 표지 가로:세로(대체 표지 · 책 없이 읽기 칸의 높이 = 폭 ÷ ratio)
  static const ratio = 0.68;

  static const all = <String, double>{
    'row': row, 'result': result, 'list': list, 'head': head, 'feature': feature, 'confirm': confirm, 'edit': edit, 'editHeight': editHeight,
    'added': added, 'saved': saved, 'place': place, 'sheet': sheet, 'post': post, 'swatch': swatch, 'ratio': ratio,
  };
}

/// 내용 폭 상한(태블릿에서 화면 끝까지 늘어나지 않게)
const contentMax = 640.0;
const sheetMax = 560.0;

/// 선 아이콘(지금 앱 lucide 아이콘, 굵기 1.6)
class LucideIcon extends StatelessWidget {
  // 선 굵기 1.6: 처음 앱(지금 앱 아이콘)과 같은 굵기(2026-11-19 사용자 '처음 썼던 걸로'. Tabler·lucide-static 때는 1.8)
  const LucideIcon(this.name, {super.key, this.size = IconSize.base, this.color = AppColors.ink, this.stroke = IconSize.stroke, this.fill});
  final String name;
  final double size;
  final Color color;
  final double stroke;
  /// 채움 색(없으면 선만)
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final svg = lucideSvg[name] ?? lucideSvg['X']!;
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    // 지금 앱 lucide는 굵기를 24칸 기준으로 준다(크기를 바꿔도 굵기는 칸 비율)
    var markup = svg.replaceAll('{c}', hex(color)).replaceAll('{w}', '$stroke');
    if (fill != null) markup = markup.replaceFirst('fill="none"', 'fill="${hex(fill!)}"');
    // 꾸밈 그림: 화면 읽기에서 빠진다(그림 표시가 붙은 버튼을 '이미지'로 읽었다, 2026-11-16 QA 영숙 F11). 이름은 감싼 버튼이 준다
    return SvgPicture.string(markup, width: size, height: size, excludeFromSemantics: true);
  }
}

/// 줄 끝 화살표: 다른 화면이나 시트로 넘어가는 줄. TDS ListRow withArrow의 색은 공식 글에 없어 가장 가까운 규칙에서:
/// ListHeader.RightArrow · Board Row 아이콘 · Stepper 화살표 기본 색 grey400, Board Row 아이콘 크기 기본 24
class Chevron extends StatelessWidget {
  const Chevron({super.key, this.color = AppColors.inkFaint});
  final Color color;

  @override
  Widget build(BuildContext context) => LucideIcon('ChevronRight', size: IconSize.chevron, color: color);
}

/// 머리줄 아이콘(검색 · + · 공유 · 더 보기 · 필터 · 보기 바꾸기): TDS Icon Button iconSize 기본 24 · 선 1.6 · 회색 [AppColors.icon]
/// (아이콘 색 기본값은 공식 없음 → 지금 앱 '우측 상단 아이콘 회색', 2026-11-18 사용자 · 11-18 '아이콘 색 좀 연하게, 통일')
class HeadIcon extends StatelessWidget {
  const HeadIcon(this.name, {super.key, this.color = AppColors.icon});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => LucideIcon(name, size: IconSize.head, color: color);
}

/// 머리줄 아이콘 사이(4)
const headIconGap = Space.xs;

/// 머리카락 선(화면 화소 1개): 가로선 · 세로선
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false, this.color = AppColors.line, this.length});
  final bool vertical;
  final Color color;
  final double? length;

  /// 화소 1개의 논리 길이
  static double of(BuildContext context) => 1 / MediaQuery.devicePixelRatioOf(context);

  @override
  Widget build(BuildContext context) {
    final t = of(context);
    return SizedBox(width: vertical ? t : length, height: vertical ? length : t, child: ColoredBox(color: color));
  }
}

/// 이미 넣은 책 표시(검색 결과 · 목록 가져오기의 '내 서재에 있음'): 체크 20 · 갈색 · 굵기 2
class AddedMark extends StatelessWidget {
  const AddedMark({super.key});

  @override
  Widget build(BuildContext context) => const LucideIcon('Check', size: IconSize.mark, color: AppColors.accent, stroke: IconSize.markStroke);
}

/// 여러 개 고르는 체크(공유 카드 '표시할 정보'): TDS Checkbox.Circle(체크 아이콘을 원으로 감싼 형태) · size 기본 24.
/// TDS Checkbox에는 네모가 없다(형태는 Circle · Line 두 가지) → 예전 네모 22를 원 24로. 켠 색은 TDS 파랑 자리라 갈색
class CheckCircle extends StatelessWidget {
  const CheckCircle({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => RadioMark(on: on);
}

/// 눌리는 동안 표시가 바뀌는 누를 것.
/// 기본(글자 단추 · 글자 링크): 옅어짐(pressOpacity, TDS TextButton 눌림 모양은 공식 없음 → 우리 값).
/// dim: 회색 바탕(greyOpacity100)을 깐다 — TDS ListRow 'withTouchEffect'(터치 효과, 모양은 공식 글에 없음)를
/// 가장 가까운 규칙인 Icon Button clear '클릭한 상태에서는 배경 색(greyOpacity100)이 보여요'에서 끌어왔다.
/// bleed: 바탕을 양옆으로 넓힐 폭(목록 줄은 화면 여백 24까지: ListRow는 좌우 여백 24를 줄 안에 가진다)
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onPress, this.disabled = false, this.dim = false, this.bleed = 0, this.radius = 0});
  final Widget child;
  final VoidCallback? onPress;
  final bool disabled;
  final bool dim;
  final double bleed;
  final double radius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onPress != null && !widget.disabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: on ? () => setState(() => _down = false) : null,
      onTapUp: on ? (_) => setState(() => _down = false) : null,
      onTap: on ? widget.onPress : null,
      child: widget.dim
          // 바탕 칸은 늘 두고 색만 바꾼다(눌릴 때 끼워 넣으면 줄 내용이 새로 만들어져 표지가 깜빡인다)
          ? Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
              Positioned(
                left: -widget.bleed,
                right: -widget.bleed,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: _down ? AppColors.greyOpacity100 : const Color(0x00000000), borderRadius: BorderRadius.circular(widget.radius)),
                  ),
                ),
              ),
              widget.child,
            ])
          : Opacity(opacity: _down ? pressOpacity : 1, child: widget.child),
    );
  }
}

/// 화면 틀: 위 안전 영역 + 머리줄 + 본문. 뒤로가 없는 화면(탭 첫 화면)은 TDS Top 모양: 제목 왼쪽 t3 22 Bold grey800 · 부제 t6 grey700 ·
/// 위아래 여백 24(upperGap · lowerGap 기본값). 밀어 넣은 화면은 위 줄(NavBar: 뒤로 · 가운데 제목 navTitle 18 · 오른쪽 행동,
/// TDS에 내비게이션 바가 없어 우리 값). 아래 고정 단추(footer)는 TDS FixedBottomCTA: 단추 xlarge · 아래 여백 max(안전 영역, 20).
/// bottomPad: 떠 있는 하단바 등에 가리지 않게 더할 아래 여백
/// 화면 본문 줄마다 양옆 여백(24). 직속 Bleed(또는 Expanded 속 Bleed)는 여백 없이 화면 폭 그대로 둔다:
/// 부모 범위 안에 있어야 넓힌 자리(양옆 24)에서도 누르고 끌 수 있다(지금 앱 marginHorizontal: -space.page와 같은 결과)
List<Widget> _padded(List<Widget> children) {
  Widget pad(Widget c) => Padding(padding: const EdgeInsets.symmetric(horizontal: Space.page), child: c);
  return [
    for (final c in children)
      if (c is Bleed && c.by == Space.page)
        c.child ?? const SizedBox.shrink()
      else if (c is Spacer)
        c
      else if (c is Flexible)
        Flexible(key: c.key, flex: c.flex, fit: c.fit, child: c.child is Bleed && (c.child as Bleed).by == Space.page ? (c.child as Bleed).child ?? const SizedBox.shrink() : pad(c.child))
      else
        pad(c),
  ];
}

/// 밀어 넣은 화면의 위 줄(높이 60): 뒤로(꺾쇠 28, 누르는 자리 48) · 가운데 제목(navTitle 18) · 오른쪽 행동.
/// Screen이 쓰고, Screen을 쓰지 않는 화면(갈피 상세 · 갈피 보드)도 이것을 쓴다(2026-11-19 공통 규칙: 제목 26 · 줄 56 · 꺾쇠 22가 섞여 있었다)
class NavBar extends StatelessWidget {
  const NavBar({super.key, this.title, this.left, this.back = true, this.onBack, this.headerField, this.right});
  final String? title;

  /// 뒤로 대신 왼쪽에 둘 것(고르는 중 '취소')
  final Widget? left;
  final bool back;

  /// 뒤로를 눌렀을 때(없으면 maybePop)
  final VoidCallback? onBack;

  /// 제목 대신 뒤로 옆에 둘 것(검색창 · 왼쪽 큰 제목)
  final Widget? headerField;
  final Widget? right;

  /// 줄 높이
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    void pop() => onBack != null ? onBack!() : Navigator.maybePop(context);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          if (title != null)
            Positioned(
              left: 64,
              right: 64,
              top: 4,
              bottom: 0,
              child: Center(child: Semantics(header: true, child: Text(title!, style: AppType.navTitle, maxLines: 1, overflow: TextOverflow.ellipsis))),
            ),
          Positioned.fill(
            top: 4,
            child: Row(children: [
              if (left != null)
                Padding(padding: const EdgeInsets.only(left: Space.page), child: left)
              else if (back)
                // 누르는 자리 48(꺾쇠 자리는 그대로: 왼쪽 여백을 2 줄인다, 2026-11-16 QA 영숙 F12)
                Padding(
                  padding: EdgeInsets.only(left: 8 - (Space.hit - Space.touch) / 2),
                  child: Semantics(
                    container: true,
                    button: true,
                    label: '뒤로',
                    onTap: pop,
                    excludeSemantics: true,
                    child: Pressable(
                      onPress: pop,
                      child: const SizedBox(width: Space.hit, height: Space.hit, child: Center(child: LucideIcon('ChevronLeft', size: IconSize.back))),
                    ),
                  ),
                ),
              if (headerField != null) Expanded(child: Padding(padding: const EdgeInsets.only(left: 2, right: Space.s), child: headerField)) else const Spacer(),
              if (right != null) Padding(padding: const EdgeInsets.only(right: 10), child: right) else if (headerField != null) const SizedBox(width: Space.page),
            ]),
          ),
        ],
      ),
    );
  }
}

/// 화면 아래에 붙인 단추 줄 바로 위 흰 그라데이션 높이(2026-11-20 사용자 '윗부분은 살짝 그라데이션')
const footerFade = Space.page;

/// 화면 틀(Screen)의 키보드 자리: 실제 키보드 높이, 또는 입력칸을 막 눌러 키보드가 올라오는 중이면 지난번 키보드 높이(처음에는 화면 높이의 0.38)만큼
/// 미리 비우고 입력칸을 그 위로 부드럽게 올린다. 키보드 높이가 오면(멈추면) 그 값으로 바꾼다.
/// 까닭: 키보드 높이를 다 올라온 뒤에야 앱에 알려 주는 기기에서는 입력칸이 키보드에 가렸다가 0.7초쯤 뒤 화면이 한 번에 튀어 올랐다
/// (2026-11-21 사용자 '한줄 메모 눌러서 키보드 올라올 때 드드득 하면서 걸리면서 올라와', 에뮬 녹화: 키보드는 1.38~1.74초, 화면은 2.50초에 331화소 한 번에).
/// 높이를 매 프레임 알려 주는 기기에서도 올라오는 동안 틀이 그대로라 프레임마다 다시 배치하지 않는다.
/// 키보드가 뜨지 않으면(물리 키보드 · 떠 있는 키보드) 1.5초 뒤 비운 자리를 거둔다
class KeyboardSpace extends StatefulWidget {
  const KeyboardSpace({super.key, required this.builder});
  final Widget Function(BuildContext context, double keyboard) builder;

  /// 마지막으로 멈춘 키보드 높이(앱을 켠 뒤 아직 없으면 0)
  static double last = 0;

  @override
  State<KeyboardSpace> createState() => _KeyboardSpaceState();
}

class _KeyboardSpaceState extends State<KeyboardSpace> {
  double _reserve = 0;
  bool _seen = false;
  FocusNode? _focus;
  Timer? _giveUp, _settle;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _giveUp?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  /// 이 화면 안의 입력칸에 초점이 왔는지
  bool _mine(FocusNode f) {
    final c = f.context;
    if (c == null || !c.mounted || c.findAncestorStateOfType<EditableTextState>() == null) return false;
    return identical(c.findAncestorStateOfType<_KeyboardSpaceState>(), this);
  }

  void _focusChanged() {
    final f = FocusManager.instance.primaryFocus;
    if (!mounted || identical(f, _focus)) return;
    _focus = f;
    _giveUp?.cancel();
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (f == null || open || !_mine(f)) {
      if (_reserve != 0) setState(() => _reserve = 0);
      return;
    }
    _seen = false;
    setState(() => _reserve = KeyboardSpace.last > 0 ? KeyboardSpace.last : MediaQuery.sizeOf(context).height * 0.38);
    // 줄어든 화면에 맞춰 입력칸을 비운 자리 위로(가려질 때만 움직인다). 입력칸 아래로 누르는 자리(48)만큼 더 보이게:
    // 키보드 높이가 오면 입력칸이 스스로 커서 아래를 그만큼(여백 20 + 손잡이) 띄우려고 한 번 더 튀었다(2026-11-21 녹화: 102화소)
    final reduce = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 그사이 화면이 닫혔거나 입력칸이 사라졌으면 그만(닫힌 칸의 그림을 찾으면 오류였다)
      final c = f.context;
      if (!mounted || _reserve == 0 || c == null || !c.mounted) return;
      final ro = c.findRenderObject();
      if (ro is! RenderBox || !ro.attached) return;
      ro.showOnScreen(
        rect: Offset.zero & Size(ro.size.width, ro.size.height + kMinInteractiveDimension),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
    _giveUp = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_seen && _reserve != 0) setState(() => _reserve = 0);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final k = MediaQuery.viewInsetsOf(context).bottom;
    if (k <= 0) return;
    _seen = true;
    // 키보드 높이가 멈추면 그 값을 기억하고 미리 비운 자리를 거둔다(실제 높이로)
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final now = MediaQuery.viewInsetsOf(context).bottom;
      if (now > 0) KeyboardSpace.last = now;
      if (_reserve != 0) setState(() => _reserve = 0);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, math.max(MediaQuery.viewInsetsOf(context).bottom, _reserve));
}

class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.right,
    this.back = true,
    this.scroll = true,
    this.bottomPad = 0,
    this.footer,
    this.left,
    this.headerField,
    this.topBar,
    this.pinned,
    this.fixedHead = false,
    this.hideTitle = false,
    this.background = AppColors.bg,
    this.pinFooter = true,
  });
  final List<Widget> children;
  final String? title;
  final String? subtitle;
  final Widget? right;
  final bool back;
  final bool scroll;
  final double bottomPad;
  final Widget? footer;

  /// 스크롤하는 화면에서도 아래 단추 줄을 화면 아래에 붙여 둔다(키보드가 열려 있을 때는 내용 끝으로). 기본으로 붙인다:
  /// 2026-11-20 사용자 '하단바 이런 거 그냥 고정해', '버튼 그냥 하단에 고정하고 윗부분은 살짝 그라데이션'. 붙인 단추 줄 바로 위는
  /// 흰 그라데이션([footerFade])으로 내용이 스며들 듯 사라진다. false면 내용 끝에 둔다
  final bool pinFooter;

  /// 뒤로 대신 왼쪽에 둘 것(예: 고르는 중 '취소')
  final Widget? left;

  /// 검색이 주인공인 화면: 제목 대신 뒤로 옆에 검색창
  final Widget? headerField;

  /// 위 줄 아래 칸. 스크롤하면 위 줄은 올라가 사라지고 이 칸만 화면 맨 위에 붙어 남는다
  /// (책 정보의 '책 정보 · 평가 · 내 기록' 전환, 2026-11-18 사용자 '천장 고정' → 11-19 위 줄 고정 없앰)
  final Widget? pinned;

  /// 화면 바탕. 흰색이 기본이고, 회색 바탕 + 흰 띠(Band)는 통계 화면만 쓴다(2026-11-20 사용자 '통계랑 캘린더에만')
  final Color background;

  /// 위 줄을 화면에 고정(스크롤해도 그대로). 카메라처럼 몸통이 스크롤하지 않는 화면만.
  /// 다른 화면은 위 줄도 내용·목록과 함께 올라간다(2026-11-19 사용자 '이런 고정들 다 없애버려')
  final bool fixedHead;

  /// 뒤로 없이도 가운데 제목 줄을 둘지(독서 끝처럼 밀어 넣었지만 뒤로를 막은 화면). 기본은 뒤로가 있을 때만
  final bool? topBar;

  /// 탭 첫 화면 왼쪽 위 큰 제목을 그리지 않는다(하단바에 이름이 있다, 2026-11-24 사용자 6단계). 제목은 화면 읽기 머리로만 남고
  /// 그 자리는 위 여백(TabHeader.paddingTop)만: 다섯 탭 첫 줄이 같은 높이에서 시작한다. right는 그리지 않는다(탭이 자기 줄에 둔다)
  final bool hideTitle;

  @override
  Widget build(BuildContext context) => KeyboardSpace(builder: _build);

  // keyboard: 키보드 자리(실제 키보드 높이, 입력칸을 막 눌렀으면 미리 비운 높이, KeyboardSpace)
  Widget _build(BuildContext context, double keyboard) {
    // 키보드가 열리면 아래 안전 여백 대신 키보드 높이만큼 비운다(키보드가 열리면 paddingOf 아래는 0이 된다)
    final insets = MediaQuery.paddingOf(context);
    // 아래 단추 줄을 화면 아래에 붙이나: 스크롤하지 않는 화면, 또는 pinFooter(기본)이고 키보드가 닫혀 있을 때
    final footerFixed = footer != null && (!scroll || (pinFooter && keyboard == 0));
    // 밀어 넣은 화면은 모두 가운데 작은 제목(2026-11-17 사용자: 가운데 제목이면 깔끔). 큰 왼쪽 제목은 탭 첫 화면에만 남긴다.
    // 부제목은 내용 맨 위 한 줄로 옮긴다
    final bar = topBar ?? back;
    // 부제는 TDS Top.SubtitleParagraph(size 15: t6 regular grey700)
    final subLine = bar && subtitle != null ? Padding(padding: const EdgeInsets.only(top: 4, bottom: Space.l), child: WordText(subtitle!, style: AppType.secondary)) : null;
    Widget tabHead() => hideTitle && headerField == null
        ? Semantics(header: true, label: title, child: const SizedBox(width: double.infinity, height: TabHeader.paddingTop))
        : Padding(
          padding: const EdgeInsets.fromLTRB(TabHeader.paddingH, TabHeader.paddingTop, TabHeader.paddingH, TabHeader.paddingBottom),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: TabHeader.minHeight - TabHeader.paddingTop - TabHeader.paddingBottom),
            // 탭 첫 화면의 검색 중(headerField): 제목 자리에 검색칸, 오른쪽에 right(예: 취소)(2026-11-18 내 책 사용자 그림)
            child: headerField != null
                ? Row(children: [
                    Expanded(child: headerField!),
                    if (right != null) Padding(padding: const EdgeInsets.only(left: Space.m), child: right!),
                  ])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(header: true, child: WordText(title ?? '', style: AppType.title)),
                            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: WordText(subtitle!, style: AppType.secondary)),
                          ],
                        ),
                      ),
                      // 지금 앱 marginRight −10·marginTop −6: 자리째 위로 당긴다(머리줄 높이도 6 줄어든다)
                      if (right != null) Transform.translate(offset: const Offset(10, 0), child: PullUp(dy: 6, child: right!)),
                    ],
                  ),
          ),
        );
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMax + Space.page * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 탭 첫 화면 제목도 내용과 함께 올라간다(머리줄 고정 아님). 뒤로 없이 제목 자리에 칸을 둔 화면(여러 권 고르기 'N권 고름')도 이 머리
            // (제목이 없으면 그리지 않아 위 줄 · 빨간 '취소'가 통째로 사라졌다, 2026-11-21 촬영 확인)
            if (!bar && (title != null || headerField != null) && scroll) tabHead(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: _padded([?subLine, ...children]),
            ),
          ],
        ),
      ),
    );
    // 스크롤하지 않는 화면: 본문이 남은 높이를 다 쓴다(안에서 목록이 Expanded로 스크롤)
    final fixed = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: contentMax + Space.page * 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _padded([?subLine, ...children])),
      ),
    );
    // 위 줄(뒤로·가운데 제목·오른쪽 단추): 다른 화면(갈피 상세·갈피 보드)도 같은 부품
    final barW = NavBar(title: headerField == null ? title : null, left: left, back: back, headerField: headerField, right: right);
    final pinnedSliver = pinned == null
        ? null
        : PinnedHeaderSliver(child: ColoredBox(color: background, child: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.page), child: Center(child: pinned!))));
    // 스크롤하는 화면은 위 줄·아래 단추도 내용과 함께 움직인다(2026-11-19 사용자 '상단이랑 하단이 고정, 이런 고정들 다 없애버려':
    // 감상 쓰기처럼 키보드가 올라오면 고정된 위아래가 쓸 자리를 먹었다). 아래 단추는 내용 끝에 붙는다
    final scrolled = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        if (footer != null && !footerFixed)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, Space.xl, Space.page, 0),
            // 내용 끝 단추 줄이 화면에 보이면 토스트가 그 위에 뜬다(ToastAvoid)
            child: ToastAvoid(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: contentMax), child: SizedBox(width: double.infinity, child: footer)))),
          ),
      ],
    );
    // 목록 화면(몸통이 스스로 스크롤): 위 줄은 목록과 함께 올라간다(NestedScrollView가 목록 스크롤을 이어 받는다)
    final head = bar ? barW : tabHead();
    // 독서 중이면 작은 타이머에 마지막 내용이 가리지 않게 아래를 더 비운다
    final body = scroll
        ? ListenableBuilder(
            listenable: ReadingStore.instance,
            builder: (context, _) {
              // 붙인 단추 줄이 아래 안전 영역을 맡으면 내용 아래는 그만큼 덜 비운다
              final pad = EdgeInsets.only(bottom: Space.section + bottomPad + (ReadingStore.instance.active != null ? miniTimerSpace : 0) + (footerFixed ? 0 : insets.bottom));
              if (pinnedSliver == null) {
                return SingleChildScrollView(
                  padding: pad,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [if (bar) barW, scrolled]),
                );
              }
              return CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (bar) SliverToBoxAdapter(child: barW),
                  pinnedSliver,
                  SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: scrolled)),
                ],
              );
            },
          )
        : fixedHead
            ? fixed
            : NestedScrollView(
                // 탭 첫 화면이면 탭의 스크롤(탭을 다시 누르면 맨 위로), 밀어 넣은 화면은 그 경로의 것
                controller: PrimaryScrollController.maybeOf(context),
                headerSliverBuilder: (_, _) => [SliverToBoxAdapter(child: head), ?pinnedSliver],
                body: fixed,
              );
    // Material: 글자 기본 모양·잉크 효과의 바탕(밀어 넣은 화면에서도 글자 밑에 노란 줄이 생기지 않게).
    // 아래를 키보드 높이만큼 비운다: 밀어 넣은 화면은 Scaffold 밖이라 키보드가 열려도 줄지 않아, 입력칸·아래 고정 버튼이 키보드에 가렸다
    // (2026-11-16 QA 영숙 F1·F13, 현우 F11, 은서 F7. 지금 앱 KeyboardAvoidingView). 탭 화면도 같다: 탭 틀(app_shell)은 몸통을 줄이지 않고
    // 보이는 탭에만 키보드 높이를 넘긴다(숨은 탭이 키보드 프레임마다 다시 배치되지 않게, 2026-11-18)
    return Material(
      color: background,
      child: Padding(
        padding: EdgeInsets.only(top: insets.top, bottom: keyboard),
        child: Column(
          children: [
            if (!scroll && fixedHead) head,
            if (!scroll && fixedHead && pinned != null) Padding(padding: const EdgeInsets.symmetric(horizontal: Space.page), child: Center(child: pinned!)),
            // 붙인 단추 줄 바로 위: 내용이 흰색으로 스며들며 사라지는 그라데이션(누름은 통과).
            // 몸통을 감싸는 틀은 키보드가 열려도 같게 둔다: 틀이 바뀌면 입력칸이 새로 만들어져 초점이 풀리고 키보드가 바로 닫혔다(2026-11-21 촬영 확인)
            Expanded(
              child: scroll
                  ? Stack(children: [
                      Positioned.fill(child: body),
                      if (footerFixed)
                        Positioned(left: 0, right: 0, bottom: 0, height: footerFade, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [background.withValues(alpha: 0), background]))))),
                    ])
                  : body,
            ),
            if (footerFixed)
              // 작은 타이머가 이 버튼 줄 위에 뜨도록 높이를 알린다(store/mini_timer_store setFooter)
              FooterReport(
                child: Container(
                  color: AppColors.bg,
                  // TDS BottomCTA: 아래 여백 = max(안전 영역, 20)(hasSafeAreaPadding 기본 true). 위 12는 공식 없음 → 우리 값
                  padding: EdgeInsets.fromLTRB(Space.page, 12, Space.page, math.max(insets.bottom, Space.ctaBottom)),
                  child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: contentMax), child: SizedBox(width: double.infinity, child: footer))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 다른 화면·시트에서 돌아올 때 앞 화면 입력칸이 초점을 되찾아 키보드가 저절로 뜨지 않게 한다(앱 뿌리 Navigator 관찰자, main.dart).
/// 돌아온 화면이 기억해 둔 마지막 초점이 입력칸이면 잊게 하고 화면 자체에 초점을 둔다(2026-11-16 QA 영숙 F14: 긴 감상에서 돌아오니 키보드가 버튼을 덮었다).
/// 돌아온 화면은 didPop 알림 전에 초점을 예약해 두므로(아직 키보드를 열기 전) 여기서 취소하면 키보드가 깜빡이지 않는다
class KeyboardRefocusGuard extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _forget(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _forget(previousRoute);

  static void _forget(Route<dynamic>? r) {
    if (r is! ModalRoute || !r.isCurrent) return;
    final ctx = r.subtreeContext;
    if (ctx == null || !ctx.mounted) return;
    FocusNode? n = FocusScope.of(ctx, createDependency: false).focusedChild;
    while (n is FocusScopeNode && n.focusedChild != null) {
      n = n.focusedChild;
    }
    if (n == null || n.context?.findAncestorWidgetOfExactType<EditableText>() == null) return;
    n.unfocus();
  }
}

/// 토스트가 가리면 안 되는 아래 단추 줄(Screen footer · FooterReport 줄). 맨 위 화면에서 이 줄이 화면에 보이면 토스트를 그 위에 띄운다
/// (2026-11-20 QA: 책 공유 '사진첩에 저장했어요'가 아래 '사진 저장 · 공유' 단추를 덮었다. 토스트는 하단 탭 바 높이에만 맞춰 떠 있었다)
class ToastAvoid extends StatefulWidget {
  const ToastAvoid({super.key, required this.child});
  final Widget child;

  @override
  State<ToastAvoid> createState() => _ToastAvoidState();
}

class _ToastAvoidState extends State<ToastAvoid> {
  static final _all = <_ToastAvoidState>{};

  @override
  void initState() {
    super.initState();
    _all.add(this);
  }

  @override
  void dispose() {
    _all.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 맨 위 화면(경로)에서 화면에 보이는 아래 단추 줄 윗변이 화면 아래 끝에서 떨어진 거리(보이는 줄이 없으면 0)
double toastFloor(double screenHeight) {
  var floor = 0.0;
  for (final s in _ToastAvoidState._all) {
    if (!s.mounted) continue;
    final route = ModalRoute.of(s.context);
    if (route != null && !route.isCurrent) continue;
    // 숨은 탭(IndexedStack에서 배치는 되지만 안 보이는 탭)의 단추 줄은 빼고
    if (!Visibility.of(s.context)) continue;
    final box = s.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top >= screenHeight || top + box.size.height <= 0) continue;
    floor = math.max(floor, screenHeight - top);
  }
  return floor;
}

/// 화면 아래 고정 버튼 줄의 높이를 그 화면(경로) 몫으로 작은 타이머에 알린다.
/// Screen의 footer가 아닌 화면(갈피 상세·갈피 보드처럼 아래 줄을 직접 그리는 곳)도 화면 아래 끝에 붙은 줄을 이것으로 감싼다
/// (2026-11-16: 작은 타이머가 갈피 상세 '공유'·보드 '+ 갈피'를 가렸다)
class FooterReport extends StatefulWidget {
  const FooterReport({super.key, required this.child});
  final Widget child;

  @override
  State<FooterReport> createState() => _FooterReportState();
}

class _FooterReportState extends State<FooterReport> {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (!identical(r, _route) && _route != null) MiniTimerPlace.instance.setFooter(_route!, null);
    _route = r;
  }

  @override
  void dispose() {
    final r = _route;
    if (r != null) MiniTimerPlace.instance.setFooter(r, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = _route, h = mounted ? context.size?.height : null;
      if (r != null && h != null) MiniTimerPlace.instance.setFooter(r, h);
    });
    // 토스트도 이 줄 위에 뜬다
    return ToastAvoid(child: widget.child);
  }
}

/// 구역 제목
class H2 extends StatelessWidget {
  const H2(this.text, {super.key, this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? Space.l : Space.section, bottom: Space.s),
        child: Semantics(header: true, child: WordText(text, style: AppType.section)),
      );
}

/// 단추 = TDS Button. 크기 small · medium · large · xlarge(기본값 xlarge), 종류는 color × variant:
///  - 'primary'    primary fill(파랑 자리에 갈색 채움 · 흰 글자): 주요 행동
///  - 'secondary'  흰 바탕 + 회색 선(AppColors.line) · 진회색 글자: ConfirmDialog 취소 단추 · BottomCTA.Double 왼쪽 단추.
///                 TDS dark weak(반투명 회색 바탕) 대신 원래 앱의 회색 선 단추(2026-11-20 사용자 '회색 배경 말고 지금까지 쓰던 회색 선으로 전부')
///  - 'danger'     danger weak(옅은 주의색 바탕 · 주의색 글자)
///  - 'dangerFill' danger fill(주의색 채움 · 흰 글자): 지우기를 확정하는 단추
///  - 'ghost'      글자 단추(TDS TextButton)
/// 눌림: 바탕 위에 딤 레이어(--button-pressed-background-color · --button-pressed-opacity). 꺼짐: 바탕 · 글자 투명도.
/// 불러오는 중: 점 3개가 차례로 움직이고 단추 폭은 그대로(Button 절 '로딩').
/// 높이 · 모서리 · 글자 크기는 공식 글에 없다 → 지금 앱 값: xlarge 52 · large 48 · medium 40 · small 40(앱의 가장 작은 조작 높이), 모서리 10.
/// 자리별 크기: 화면 아래 고정 단추 · 시트 단추 xlarge(Button 기본값), 확인창 두 단추 large(ConfirmDialog 기본값), 줄 안 작은 단추 medium.
/// 누르는 자리는 늘 48 이상(겉높이가 작으면 위아래 빈 자리까지 누른다)
class Btn extends StatefulWidget {
  const Btn({super.key, required this.label, required this.onPress, this.kind = 'primary', this.size = 'xlarge', this.disabled = false, this.busy = false, this.icon});
  final String label;
  final VoidCallback onPress;
  final String kind;
  final String size;
  final bool disabled;
  final bool busy;
  final Widget? icon;

  /// 크기별 겉높이(공식 없음 → 지금 앱 값 ControlSize. 누르는 자리는 위아래를 더해 48 이상)
  static double heightOf(String size) => switch (size) { 'xlarge' => ControlSize.buttonL, 'large' => ControlSize.buttonM, _ => ControlSize.buttonS };

  @override
  State<Btn> createState() => _BtnState();
}

class _BtnState extends State<Btn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final text = kind == 'ghost';
    final off = widget.disabled || widget.busy;
    final pressed = _down && !off;
    final (Color fill, Color ink) = switch (kind) {
      'primary' => (AppColors.accent, AppColors.onAccent),
      'secondary' => (AppColors.bg, AppColors.title),
      'danger' => (AppColors.dangerWeak, AppColors.danger),
      'dangerFill' => (AppColors.danger, AppColors.onAccent),
      _ => (Colors.transparent, AppColors.inkSoft),
    };
    final h = Btn.heightOf(widget.size);
    final big = widget.size == 'xlarge' || widget.size == 'large';
    final pad = switch (widget.size) { 'xlarge' || 'large' => 20.0, 'medium' => 16.0, _ => 14.0 };
    final radius = BorderRadius.circular(Shape.button);
    // 화면 읽기: 이름을 한 번만 읽는 버튼 하나(안쪽 글자까지 읽혀 '감상 저장 / 감상 저장'이었다, 2026-11-16 QA 영숙 F9)
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      enabled: !off,
      onTap: off ? null : widget.onPress,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: off ? null : (_) => setState(() => _down = true),
        onTapCancel: off ? null : () => setState(() => _down = false),
        onTapUp: off ? null : (_) => setState(() => _down = false),
        onTap: off ? null : widget.onPress,
        // 작은 버튼(40)도 누르는 자리는 48: 위아래 빈 자리까지 누른다(겉모양은 그대로, F12)
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: math.max(0, Space.hit - h) / 2),
          child: Opacity(
            // 꺼짐: 바탕 · 글자 투명도(TDS --button-disabled-opacity-color · --button-disabled-text-opacity)
            opacity: widget.disabled ? disabledOpacity : text && pressed ? pressOpacity : 1,
            child: Container(
              constraints: BoxConstraints(minHeight: h),
              // 위아래 여백은 글자 줄(t5 25.5)이 보이는 높이(ControlSize)를 넘지 않게: large 48 = 10 + 25.5 + 10 안(12였으면 50으로 커진다)
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: big ? 10 : 8),
              decoration: BoxDecoration(color: fill, borderRadius: radius, border: kind == 'secondary' ? Border.all(color: AppColors.line) : null),
              // 눌림: 바탕 위 딤 레이어(글자 단추는 옅어짐). 덧칠 칸은 늘 두고 색만 바꾼다(안쪽을 새로 만들지 않게)
              foregroundDecoration: BoxDecoration(color: pressed && !text ? AppColors.pressDim : const Color(0x00000000), borderRadius: radius),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: widget.busy ? 0 : 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 8)],
                        // 낱말 단위로 줄을 바꾸고, 줄 수를 막지 않는다: 큰 글씨에서 줄이 늘면 버튼이 늘어난다(두 줄로 막아 잘렸다, F6)
                        Flexible(
                          child: WordText(widget.label,
                              textAlign: TextAlign.center,
                              style: (text ? AppType.link : big ? AppType.button : AppType.buttonSmall).copyWith(color: ink)),
                        ),
                      ],
                    ),
                  ),
                  if (widget.busy) DotLoader(color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 단추 안 불러오는 중: 점 3개가 차례로 움직인다(TDS Button 로딩 '3개의 인디케이터가 순차적으로'). 점 크기 · 빠르기는 공식 없음 → 우리 값
class DotLoader extends StatefulWidget {
  const DotLoader({super.key, required this.color});
  final Color color;

  @override
  State<DotLoader> createState() => _DotLoaderState();
}

class _DotLoaderState extends State<DotLoader> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Builder(builder: (_) {
                // 점마다 1/3씩 늦게 밝아졌다 옅어진다
                final t = (_c.value - i / 3) % 1;
                final a = t < 0.5 ? 0.35 + 1.3 * t : 1.0 - 1.3 * (t - 0.5);
                return Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: a.clamp(0.35, 1.0))));
              }),
            ],
          ]),
        ),
      );
}

/// 아이콘 단추 = TDS Icon Button variant clear(기본): 바탕 없이 아이콘만, 누른 동안 바탕 색 greyOpacity100이 보인다.
/// 바탕 모양 · 크기는 공식 없음 → 누르는 자리(48) 원. 누르는 자리 48(2026-11-16 QA 영숙 F12). 화면 읽기에서는 이름 하나만 가진 버튼(TDS: aria-label 필수)
class IconBtn extends StatefulWidget {
  const IconBtn({super.key, required this.label, required this.onPress, required this.child, this.disabled = false});
  final String label;
  final VoidCallback onPress;
  final Widget child;
  final bool disabled;

  @override
  State<IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<IconBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = !widget.disabled;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      enabled: on,
      onTap: on ? widget.onPress : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: on ? 1 : disabledOpacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: on ? (_) => setState(() => _down = true) : null,
          onTapCancel: on ? () => setState(() => _down = false) : null,
          onTapUp: on ? (_) => setState(() => _down = false) : null,
          onTap: on ? widget.onPress : null,
          child: Container(
            width: Space.hit,
            height: Space.hit,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _down && on ? AppColors.greyOpacity100 : null),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 화면 전체가 빈 상태 · 불러오기 실패(docs/design/DESIGN.md 11장): 가운데 제목(heading, 마침표 없음) + 본문 한두 문장 + 다음 행동 단추 하나.
/// 첫 사용은 만들 것을 권하는 primary, 실패의 '다시 시도'·조건 0건의 '조건 지우기'는 secondary. 한 구역만 빈 것은 [EmptyLine].
/// = TDS Result 모양(제목 · 설명 · 단추). Result의 글자 · 단추 크기는 공식 글에 없어 가장 가까운 규칙에서:
/// 제목 t4 Bold grey800(Dialog · BottomSheet 제목) · 설명 t6 grey600(Dialog 설명) · 단추 large(ConfirmDialog · Top.LowerCTAButton 기본값)
class Empty extends StatelessWidget {
  const Empty({super.key, required this.title, this.body, this.action, this.onAction, this.actionKind = 'primary', this.link, this.onLink});
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;
  final String actionKind;

  /// 단추 아래 보조 글자 단추 하나(검색 실패 뒤 '직접 등록'처럼 다른 길)
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.block, horizontal: Space.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 제목은 옅은 굵은 글자(emptyTitle): 먹색 큰 제목이 너무 진했다(2026-11-20 사용자 '색 너무 진하지 않나')
            Semantics(header: true, child: WordText(title, textAlign: TextAlign.center, style: AppType.emptyTitle)),
            if (body != null) Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText(body!, textAlign: TextAlign.center, style: AppType.sub)),
            if (action != null && onAction != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xl),
                child: Center(child: ConstrainedBox(constraints: const BoxConstraints(minWidth: emptyActionMinWidth), child: Btn(label: action!, kind: actionKind, size: 'large', onPress: onAction!))),
              ),
            if (link != null && onLink != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Center(child: TextLink(label: link!, soft: true, onPress: onLink!))),
          ],
        ),
      );
}

/// 빈 화면 단추 최소 폭(가운데 짧은 단추)
const emptyActionMinWidth = 160.0;

/// 화면 전체를 불러오는 중: 가운데 원(accent) + 글(있으면). 화면 읽기는 글이 없어도 '불러오는 중'
class Loading extends StatelessWidget {
  const Loading({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.block),
        child: Semantics(
          label: label ?? '불러오는 중',
          liveRegion: true,
          child: Column(children: [
            const ExcludeSemantics(child: CircularProgressIndicator(color: AppColors.accent)),
            if (label != null) Padding(padding: const EdgeInsets.only(top: Space.m), child: ExcludeSemantics(child: WordText(label!, style: AppType.sub))),
          ]),
        ),
      );
}

/// 작은 돌아가는 원(단추 · 칸 · 줄 안 진행, 2026-11-19 규칙: 18 · 20 · 22가 섞여 있었다). 화면 전체는 [Loading]
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.color = AppColors.inkSoft, this.label});
  final Color color;

  /// 화면 읽기 이름(단추 안처럼 이미 이름이 있으면 비운다)
  final String? label;

  @override
  Widget build(BuildContext context) {
    final w = SizedBox(width: ControlSize.spinner, height: ControlSize.spinner, child: CircularProgressIndicator(strokeWidth: ControlSize.spinnerStroke, color: color));
    return label == null ? ExcludeSemantics(child: w) : Semantics(label: label, child: ExcludeSemantics(child: w));
  }
}

/// 한 구역만 빈 상태(docs/design/DESIGN.md 11장): 왼쪽 회색 한 줄(sub, 한 문장이면 마침표 없음) + 필요하면 글자 단추 하나('다시 시도' 등)
class EmptyLine extends StatelessWidget {
  const EmptyLine(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          WordText(text, style: AppType.sub),
          if (action != null && onAction != null) TextLink(label: action!, start: true, onPress: onAction!),
        ]),
      );
}

/// 안내 · 오류 글(회색 상자 없이 글자만, 화면 읽기가 바로 읽는다): 안내 sub, 오류 sub danger(문장, 마침표).
/// 권한 거부는 사용자가 고른 것이라 오류가 아닌 안내로 쓴다(docs/design/DESIGN.md 11장)
class NoticeText extends StatelessWidget {
  const NoticeText(this.text, {super.key, this.error = false, this.center = false});
  final String text;
  final bool error;
  final bool center;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Semantics(
          liveRegion: true,
          child: WordText(text, textAlign: center ? TextAlign.center : null, style: error ? AppType.sub.copyWith(color: AppColors.danger) : AppType.sub),
        ),
      );
}

bool _isLight(String hex) {
  final m = RegExp(r'^#([\da-f]{6})$', caseSensitive: false).firstMatch(hex);
  if (m == null) return false;
  final c = m.group(1)!;
  final r = int.parse(c.substring(0, 2), radix: 16), g = int.parse(c.substring(2, 4), radix: 16), b = int.parse(c.substring(4, 6), radix: 16);
  return 0.299 * r + 0.587 * g + 0.114 * b > 180;
}

/// 책 한 줄의 표지 크기 세 단계(2026-11-19 공통 규칙: 34 · 36 · 40 · 44 · 47 · 52 · 64 · 72 · 80이 섞여 있었다)
/// small 40: 고르기 · 선택 · 바코드 · 가져오기 · 읽기 목록 · 통계 기록 · 독서 끝 / medium 64: 검색 결과 · 감상 목록 / large 80: 내 책 목록
enum BookRowSize { small, medium, large }

/// 책 한 줄 = TDS ListRow(left 표지 · contents 글 · right): 위아래 verticalPadding medium 12(기본), 촘촘한 목록은 small 8.
/// 표지 + 16 + (제목 rowStrong t5 · 저자와 정보 MetaText sub t6 grey600 · 셋째 줄 caption t7) + 오른쪽. 누르면 회색 터치 바탕(withTouchEffect)
/// 앱의 책 줄은 모두 이것(검색 결과 · 내 책 목록 · 읽기 목록 · 책 고르기 · 책 선택 · 바코드 · 목록 가져오기 · 통계 · 감상)
class BookRow extends StatelessWidget {
  const BookRow({
    super.key,
    required this.cover,
    required this.title,
    this.meta,
    this.third,
    this.trailing,
    this.size = BookRowSize.small,
    this.titleLines,
    this.onPress,
    this.label,
    this.selected,
    this.dense = false,
    this.onLongPress,
    this.checked,
    this.titleTrailing,
  });

  /// 제목 줄 오른쪽 끝 작은 단추(내 책 목록의 메모, 그림 18 · 누르는 칸 48). 오른쪽 칸([trailing])과 달리 둘째 · 셋째 줄은 줄 폭을 다 쓴다
  /// (2026-11-20 사용자 '메모 제목 라인에 넣어놓고 한줄평이나 이런 거 더 길게 보이게')
  final Widget? titleTrailing;

  /// 꾹 누르기(내 책 목록: 고르기 시작)
  final VoidCallback? onLongPress;

  /// 여러 권 고르기 줄: 화면 읽기 '선택됨/선택 안 됨'(selected 대신)
  final bool? checked;

  /// 줄이 많은 목록(읽기 탭 '내 읽기 목록'): TDS ListRow verticalPadding small 8(공식 가장 작은 값. 지금 앱은 4였다, 2026-11-18 사용자 '간격 촘촘하게')
  final bool dense;

  /// 표지(폭은 [coverWidth])
  final Widget cover;
  final String title;

  /// 둘째 줄(저자 | 출판사 · 상태 등, metaSep으로 잇는다)
  final String? meta;

  /// 셋째 줄(한줄평 · 진행 등)
  final String? third;
  final Widget? trailing;
  final BookRowSize size;

  /// 제목 줄 수(기본: small 1, 그 밖 2)
  final int? titleLines;
  final VoidCallback? onPress;

  /// 줄 하나의 화면 읽기 이름(있으면 안쪽 글자는 빼고 이것만 읽는다)
  final String? label;
  final bool? selected;

  static double coverWidth(BookRowSize s) => switch (s) { BookRowSize.small => CoverSize.row, BookRowSize.medium => CoverSize.result, BookRowSize.large => CoverSize.list };

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? Space.rowS : Space.rowM),
      // 글 묶음 · 오른쪽은 표지 높이의 세로 가운데(TDS ListRow: 왼쪽 그림 옆 내용 가운데. 내 책 목록도, 2026-11-20 사용자)
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: coverWidth(size), child: label != null ? ExcludeSemantics(child: cover) : cover),
        const SizedBox(width: Space.l),
        Expanded(
          child: Stack(clipBehavior: Clip.none, children: [
            ExcludeSemantics(
              excluding: label != null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                // 제목 줄 단추 자리만큼 제목 오른쪽을 비운다(둘째 · 셋째 줄은 줄 폭 그대로)
                Padding(
                  padding: EdgeInsets.only(right: titleTrailing != null ? Space.touch - Space.s : 0),
                  child: Text(title, maxLines: titleLines ?? (size == BookRowSize.small ? 1 : 2), overflow: TextOverflow.ellipsis, style: AppType.bookTitle),
                ),
                if (meta != null && meta!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: MetaText(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookAuthor)),
                if (third != null && third!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: MetaText(third!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bookNote)),
              ]),
            ),
            // 누르는 칸 48의 가운데가 제목 첫 줄 가운데, 그림 오른쪽 끝이 글 묶음 오른쪽 끝
            if (titleTrailing != null)
              Positioned(
                top: (TypeSpecs.bookTitle.line - Space.hit) / 2,
                right: -(Space.hit - IconSize.small) / 2,
                child: SizedBox(width: Space.hit, height: Space.hit, child: Center(child: titleTrailing)),
              ),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: Space.m), trailing!],
      ]),
    );
    final tapped = onPress == null ? row : Pressable(onPress: onPress, dim: true, bleed: Space.page, child: row);
    return Semantics(
      container: true,
      button: onPress != null,
      selected: selected,
      checked: checked,
      label: label,
      onTap: onPress,
      onLongPress: onLongPress,
      child: onLongPress == null ? tapped : GestureDetector(onLongPress: onLongPress, child: tapped),
    );
  }
}

/// 책 없이 읽은 기록의 표지 자리: 옅은 회색 칸 + 펼친 책 그림(읽기 목록 · 읽기 장면 · 통계가 같은 모양, 이름은 '책 없이 읽기')
class NoBookCover extends StatelessWidget {
  const NoBookCover({super.key, required this.width});
  final double width;

  /// 이름(앱 어디서나 같은 말)
  static const name = '책 없이 읽기';

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width / CoverSize.ratio,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(Shape.cover)),
        child: Center(child: LucideIcon('BookOpen', size: width * 0.45, color: AppColors.inkFaint)),
      );
}

/// 실제 표지(도서 이미지·내가 찍은 사진). 없거나 못 읽으면 책 색 대체 표지(제목, 명조).
/// 원격 그림은 표지 캐시로 읽는다(오프라인에서도 한 번 본 표지는 보인다)
class RealCover extends StatefulWidget {
  const RealCover({super.key, this.uri, required this.title, this.color = placeholder, required this.width, this.ratio = 0.68});

  /// 책 색이 없을 때 대체 표지 바탕(AppColors.surface와 같은 값, 색 글자로 받는다)
  static const placeholder = '#F2F4F6';
  final String? uri;
  final String title;
  final String color;
  final double width;
  final double ratio;

  @override
  State<RealCover> createState() => _RealCoverState();
}

class _RealCoverState extends State<RealCover> {
  ui.Image? _img;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RealCover old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      _img = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final u = widget.uri;
    if (u == null) return;
    final img = coverInMemory(u) ?? await loadCover(u);
    if (!mounted || u != widget.uri) return;
    setState(() => img == null ? _failed = true : _img = img);
  }

  /// 대체 표지 제목 크기: 가장 긴 낱말이 한 줄에 들어갈 때까지 줄인다(로마자 제목이 'geomeu / n ip'처럼 낱말 가운데서 끊겼다, 2026-11-16 QA 은서 F16).
  /// 너무 작아지지 않게 처음 크기의 0.7까지만 줄이고, 그래도 넘치는 낱말은 끊는다
  double _titleSize(BuildContext context, TextStyle style, double room) {
    final scaler = MediaQuery.textScalerOf(context);
    // 실제로 그리는 모양(물려받는 자간 등)으로 잰다
    final shown = DefaultTextStyle.of(context).style.merge(style);
    final words = widget.title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map(keepAll).toList();
    final base = style.fontSize!;
    var size = base;
    for (var i = 0; i < 3; i++) {
      var widest = 0.0;
      for (final word in words) {
        final p = TextPainter(text: TextSpan(text: word, style: shown.copyWith(fontSize: size)), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
        widest = math.max(widest, p.width);
        p.dispose();
      }
      if (widest <= room) break;
      // 0.98: 글자 폭 반올림 여유(딱 맞추면 줄 끝에서 다시 끊겼다)
      size = math.max(base * 0.7, size * room / widest * 0.98);
    }
    return size;
  }

  // 표지는 꾸밈: 화면 읽기에서 빠진다. 제목은 옆 글자로 읽힌다('… 표지 / …' 이름 중복, 2026-11-16 QA 영숙 F9)
  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = w / widget.ratio;
    if (widget.uri == null || _failed) {
      const pad = 8.0;
      final style = TextStyle(fontFamily: AppFonts.serif, fontSize: math.max(10, w / 8), color: _isLight(widget.color) ? AppColors.inkSoft : AppColors.onAccent);
      return ExcludeSemantics(
        child: Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(pad),
          decoration: BoxDecoration(color: hexColor(widget.color), borderRadius: BorderRadius.circular(Shape.cover)),
          alignment: Alignment.center,
          child: WordText(widget.title, maxLines: 4, textAlign: TextAlign.center, style: style.copyWith(fontSize: _titleSize(context, style, w - pad * 2))),
        ),
      );
    }
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Shape.cover),
        child: Container(width: w, height: h, color: AppColors.surface, child: _img == null ? null : RawImage(image: _img, fit: BoxFit.cover, width: w, height: h)),
      ),
    );
  }
}


/// 목록 한 줄 = TDS ListRow: 위아래 12(verticalPadding medium 기본) · 좌우 24(horizontalPadding medium, 화면 여백이 맡는다).
/// 이름 t5 grey900(+ 아래 설명 t6 grey600) · 오른쪽 값 t6 grey700(ListHeader.RightText 기본 색) · 화살표 grey400(다른 화면으로 넘어가는 줄에만).
/// 구분선: TDS 기본은 indented지만 none도 공식 선택지('연결된 느낌') → 지금 앱처럼 줄 사이 선 없음. 누르면 회색 터치 바탕
class ListItem extends StatelessWidget {
  const ListItem({super.key, required this.label, this.sub, this.value, this.onPress, this.danger = false, this.chevron = false, this.right, this.icon, this.selected});
  final String label;
  final String? sub;
  final String? value;
  final VoidCallback? onPress;
  final bool danger;
  final bool chevron;
  final Widget? right;
  final Widget? icon;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    // 오른쪽이 스위치뿐인 줄(줄 자체는 누를 일이 없음)은 줄 전체가 스위치: 줄 어디를 눌러도 켜고 끄고, 화면 읽기도 스위치 하나로 읽는다
    // ('진동 / 진동 / 진동'으로 세 번 읽혔고 스위치 누르는 자리가 30이었다, 2026-11-16 QA 영숙 F9·F12)
    final toggle = _rowToggle(onPress, right);
    final tap = onPress ?? (toggle == null ? null : () => toggle.onChange(!toggle.value));
    // 이름은 줄 하나에 한 번: 안쪽 글자는 화면 읽기에서 빼고 줄 이름으로만 읽는다(F9)
    return Semantics(
      container: true,
      button: onPress != null,
      toggled: toggle?.value,
      selected: selected,
      label: [label, ?sub, ?value, if (toggle != null && toggle.label != label) toggle.label].join(', '),
      onTap: toggle != null ? tap : null,
      excludeSemantics: toggle != null,
      child: Pressable(
        onPress: tap,
        dim: true,
        bleed: Space.page,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Space.hit),
          child: Row(
            children: [
              // 왼쪽 그림(계정 줄의 회사 로고 36): 그림 + 12
              if (icon != null) Padding(padding: const EdgeInsets.only(right: Space.m), child: ExcludeSemantics(child: icon)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: Space.rowM, bottom: Space.rowM, right: right != null || value != null || chevron ? 12 : 0),
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WordText(label, style: AppType.row.copyWith(color: danger ? AppColors.danger : null)),
                        if (sub != null) Padding(padding: const EdgeInsets.only(top: 4), child: MetaText(sub!, style: AppType.sub)),
                      ],
                    ),
                  ),
                ),
              ),
              if (value != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: ExcludeSemantics(child: MetaText(value!, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: AppType.secondary)),
                  ),
                ),
              ?right,
              if (chevron) const Padding(padding: EdgeInsets.only(left: 4), child: Chevron()),
            ],
          ),
        ),
      ),
    );
  }
}

/// 줄 오른쪽이 스위치뿐이고 줄 자체를 누를 일이 없으면 그 스위치(줄 전체를 스위치로 쓴다)
Toggle? _rowToggle(VoidCallback? onPress, Widget? right) => onPress == null && right is Toggle ? right : null;

/// 전환 칸 = TDS SegmentedControl(여러 선택지 중 하나, Radio와 같은 역할 · size small 기본 · alignment fixed 기본).
/// TDS에 칩이 없어 하나 고르는 칩 자리도 이것을 쓴다. 높이 · 모양 · 글자는 공식 글에 없음 → 지금 앱 모양(회색 칸 44 안 고른 칸만 흰 바탕),
/// 글자는 t6 15(작은 본문): 고른 칸 SemiBold grey900, 나머지 Regular grey600. 화면 읽기는 라디오처럼 '선택됨'(role radio · aria-checked)
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.items, required this.value, required this.onChange, this.track = AppColors.surface, this.compact = false, this.disabled = const {}});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChange;

  /// 지금 고를 수 없는 칸(흐리게, 눌러도 그대로): 꾸미기 '기대기'에서 기댈 옆 책이 없는 쪽
  final Set<T> disabled;

  /// 칸 바탕
  final Color track;

  /// 낮은 칸(회색 칸 36): 머리줄 안처럼 옆 글자 줄과 높이를 맞출 때. 누르는 자리는 48 그대로
  final bool compact;

  /// 바탕 안 양옆 여백 · 칸 안 글자 양옆 여백
  static const _trackPad = 3.0, _cellPad = 4.0;

  static TextStyle _label(bool selected) => AppType.bodySmall.copyWith(
        fontFamily: selected ? AppFonts.uiBold : AppFonts.ui,
        color: selected ? AppColors.ink : AppColors.inkSoft,
      );

  /// 칸 폭이 모두 같을 때 가장 긴 이름(고른 칸의 굵은 글자)이 잘리지 않는 전체 폭. 기기 글자 크기를 따른다.
  /// 폭을 정해 둔 자리(꾸미기 제목 줄 오른쪽)에서 쓴다: 정해 둔 숫자는 글자를 조금만 키워도 잘렸다
  static double fitWidth(BuildContext context, Iterable<String> labels) {
    final scaler = MediaQuery.textScalerOf(context);
    // Text처럼 둘레 기본 글자 모양(자간 등)과 합쳐 잰다
    final style = DefaultTextStyle.of(context).style.merge(_label(true));
    var w = 0.0;
    for (final l in labels) {
      final tp = TextPainter(text: TextSpan(text: l, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      w = math.max(w, tp.width);
      tp.dispose();
    }
    return labels.length * (w.ceilToDouble() + 2 * _cellPad) + 2 * _trackPad;
  }

  // 겉모양은 회색 칸 44(고른 칸 38): 2026-11-17 사용자 '책 정보·평가·내 기록 바가 두껍다'(예전 50) → 40은 너무 얇아 조금 키움(2026-11-18 사용자 '조금만 더 키우라고').
  // 누르는 자리는 위아래 빈 4까지 48 그대로(2026-11-16 QA 영숙 F12). 큰 글씨면 칸이 글자만큼 늘어난다
  @override
  Widget build(BuildContext context) {
    final inset = compact ? ControlSize.segmentCompactInset : ControlSize.segmentInset;
    final pad = compact ? ControlSize.segmentCompactPad : ControlSize.segmentPad;
    final cell = compact ? ControlSize.segmentCompact : ControlSize.segment;
    return Stack(children: [
        Positioned.fill(
          top: inset,
          bottom: inset,
          child: DecoratedBox(decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(compact ? Shape.segmentedCompact : Shape.segmented))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _trackPad),
          child: Row(
            children: [
              for (final (id, label) in items)
                Expanded(
                  child: Semantics(
                    container: true,
                    inMutuallyExclusiveGroup: true,
                    checked: id == value,
                    enabled: !disabled.contains(id),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: disabled.contains(id) ? null : () => onChange(id),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: pad),
                        child: Container(
                          constraints: BoxConstraints(minHeight: cell),
                          padding: const EdgeInsets.symmetric(horizontal: _cellPad),
                          decoration: id == value
                              ? BoxDecoration(
                                  color: AppColors.bg,
                                  borderRadius: BorderRadius.circular(compact ? Shape.segmentCompact : Shape.segment),
                                  boxShadow: const [Shape.segmentShadow],
                                )
                              : null,
                          // 글자 가운데. heightFactor 1: 높이가 정해진 자리(꾸미기 머리줄 72)에서도 칸이 그 높이까지 늘지 않는다
                          // (Container alignment는 늘어났다: 회색 칸 44가 68로 보였다, 2026-11-20 사용자 '세로 높이 좀 길지 않나')
                          child: Center(
                            heightFactor: 1,
                            child: Opacity(
                              opacity: disabled.contains(id) && id != value ? disabledOpacity : 1,
                              // 아주 큰 글씨에서 칸보다 긴 이름은 자르지 않고 두 줄까지 접는다(꾸미기 '위치, 각도' 2배 글씨)
                              child: Text(label, maxLines: 2, textAlign: TextAlign.center, style: _label(id == value)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]);
  }
}

/// 거르기 단추 = TDS Top.SubtitleSelector · ListHeader.TitleSelector(글자 + 아래 화살표, 누르면 고르는 시트): size 17 기본 = t5 Medium grey700,
/// 화살표 색은 공식 없음 → 글자 색. 걸러진 상태(고른 값이 기본이 아님) 표시는 공식 없음 → 우리 값(SemiBold grey900)
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.label, required this.onPress, this.active = false});
  final String label;
  final VoidCallback onPress;
  final bool active;

  /// '모든 책 ⌄' · '월별 ⌄': 글자와 화살표, 누르면 고르기 시트. 누르는 자리 48(2026-11-19 규칙: 32였다)
  @override
  Widget build(BuildContext context) {
    final ink = active ? AppColors.ink : AppColors.inkSub;
    return Semantics(
      container: true,
      button: true,
      // 화면 읽기: '모든 책, 바꾸기' 한 번만(안쪽 글자까지 겹쳐 읽혔다, 2026-11-16 QA 영숙 F9)
      label: '$label, 바꾸기',
      onTap: onPress,
      excludeSemantics: true,
      child: Pressable(
        onPress: onPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Space.hit, maxWidth: 220),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: active ? AppType.row.strong : AppType.row.copyWith(fontFamily: AppFonts.uiMedium, color: ink)),
            ),
            const SizedBox(width: Space.xs),
            LucideIcon('ChevronDown', size: 16, color: ink),
          ]),
        ),
      ),
    );
  }
}

/// 목록 묶음(줄 사이에 선을 긋지 않는다): 묶음 이름 = TDS ListHeader.TitleParagraph t5 Bold grey800(공식 예시 BasicHeaders)
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.title});
  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Semantics(header: true, child: WordText(title!, style: AppType.listHeader))),
          ...children,
        ],
      );
}

/// 묶음 사이 = TDS Border. 구간을 나눌 때는 variant height16 자리(화면 끝까지 닿는 띠, 높이는 Space.band 8 = 공식 16의 반, 색은 공식 없음 → greyBackground = grey100),
/// inset은 variant padding24(양옆 24를 두고 그은 선, 색은 공식 없음 → 우리 값). 띠 앞뒤 여백은 공식 없음 → 지금 앱 값(20 · 16)
class SectionBand extends StatelessWidget {
  const SectionBand({super.key, this.inset = false});

  /// 내용 폭 안에만 긋는 옅은 선(TDS Border padding24, 내 정보·계정 및 동기화 시안 2026-11-17)
  final bool inset;

  @override
  Widget build(BuildContext context) => inset
      ? Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Container(height: 1, color: AppColors.sectionLine))
      : Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        // 내용 폭 안에서 양옆 여백(24)을 넘어 화면 끝까지
        child: SizedBox(
          height: Space.band,
          child: OverflowBox(
            minWidth: 0,
            maxWidth: double.infinity,
            child: Container(height: Space.band, width: MediaQuery.sizeOf(context).width, color: AppColors.greyBackground),
          ),
        ),
      );
}

/// 흰 띠: 좌우는 화면 끝까지 붙이고 위아래로만 층을 나눈다. 띠 위에 회색 칸(Space.band, greyBackground)을 화면 폭으로 깔아
/// 바로 위 띠(또는 맨 위 흰 머리)와 나눈다. 띠 안 위아래 Space.bandPad, 좌우는 화면 여백 Space.page.
/// 화면 바탕은 흰색 그대로라 맨 위(제목 · 전환 칸 · 달)도 흰색(2026-11-20 사용자 '맨 위쪽 배경 회색 넣지 말고 전부 흰색').
/// 통계 분석에만 쓴다(2026-11-20 사용자 '박스인데 위아래 층만 나누고 좌우는 붙히자' → '캘린더 쪽은 … 박스 모양 안 만들어도, 분석 쪽만 그렇게 하자 그래프 있는 쪽')
class Band extends StatelessWidget {
  const Band({super.key, required this.children, this.top = true});
  final List<Widget> children;

  /// 위 회색 칸을 깔지(맨 위 흰 머리 바로 아래 첫 띠는 깔지 않는다: 날짜 밑 회색선, 2026-11-20 사용자 '이 날짜 밑에는 회색선 없애')
  final bool top;

  @override
  Widget build(BuildContext context) => Bleed(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (top) const SizedBox(height: Space.band, child: ColoredBox(color: AppColors.greyBackground)),
          ColoredBox(
            color: AppColors.bg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.bandPad),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ]),
      );
}

/// 내용 폭 밖으로 양옆 [by]만큼 넓혀 화면 끝까지(지금 앱 marginHorizontal: -space.page). 넓힌 자리도 누를 수 있다
class Bleed extends SingleChildRenderObjectWidget {
  const Bleed({super.key, this.by = Space.page, super.child});
  final double by;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBleed(by);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderBleed).by = by;
}

class _RenderBleed extends RenderShiftedBox {
  _RenderBleed(this._by) : super(null);
  double _by;

  set by(double v) {
    if (v == _by) return;
    _by = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = constraints, child = this.child;
    if (child == null) {
      size = c.smallest;
      return;
    }
    if (!c.hasBoundedWidth) {
      child.layout(c, parentUsesSize: true);
      (child.parentData! as BoxParentData).offset = Offset.zero;
      size = child.size;
      return;
    }
    final w = c.maxWidth + 2 * _by;
    child.layout(BoxConstraints(minWidth: w, maxWidth: w, minHeight: c.minHeight, maxHeight: c.maxHeight), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(-_by, 0);
    size = c.constrain(Size(c.maxWidth, child.size.height));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (position.dx < -_by || position.dx >= size.width + _by || position.dy < 0 || position.dy >= size.height) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}

/// 줄 사이 선 = TDS Border variant full(전체 너비 선). 굵기 · 색은 공식 없음 → 우리 값(0.5 · grey200)
class AppDivider extends StatelessWidget {
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(height: 0.5, color: AppColors.line);
}

/// 하단 시트 = TDS BottomSheet: 어두운 덮개(딤) + 위쪽만 둥근 판(손잡이 · 제목 · 부제목 · 내용 · 단추).
/// 제목 BottomSheet.Header t4(굵기 · 색은 공식 없음 → Dialog 제목과 같은 Bold grey800) · 부제목 BottomSheet.HeaderDescription t6(grey600).
/// 딤을 누르거나 뒤로 가면 닫힌다(공식 '권장되는 동작'), 손잡이를 끌어 내려도 닫힌다. 내용과 아래 단추 사이는 지금 앱 값(TDS ctaContentGap 34는 쓰지 않는다),
/// 아래 여백 max(안전 영역, 20)(BottomCTA와 같게). 닫기 단추는 두지 않는다. 손잡이 · 모서리 크기는 공식 없음 → 우리 값
Future<T?> showSheet<T>(BuildContext context, {String? title, String? description, required WidgetBuilder builder, bool scroll = false, double? maxHeight, bool fit = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    // 뒤 덮개 이름(기본은 영어 'Scrim'으로 읽혔다, 2026-11-16 QA 영숙 F10)
    barrierLabel: '닫기',
    constraints: const BoxConstraints(maxWidth: sheetMax),
    builder: (ctx) {
      final insets = MediaQuery.paddingOf(ctx);
      final body = builder(ctx);
      final head = title == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: Space.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Space.touch),
                  child: Align(alignment: Alignment.centerLeft, child: Semantics(header: true, child: WordText(title, style: AppType.heading))),
                ),
                if (description != null) Padding(padding: const EdgeInsets.only(top: 2), child: WordText(description, style: AppType.sub)),
              ]),
            );
      // 더 큰 텍스트 160% 이상이면 머리(제목 · 부제목)도 스크롤 안에 넣는다(TDS BottomSheet a11yIncludeHeaderInScroll 기본 true).
      // 내용이 스스로 스크롤하는 시트(fit)는 머리를 그대로 둔다
      final headInScroll = head != null && scroll && MediaQuery.textScalerOf(ctx).scale(100) >= 160;
      // 키보드가 열리면 시트를 키보드 위로 올린다(지금 앱 시트의 KeyboardAvoidingView, F1)
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          // maxHeight: 화면 높이에 대한 비율(긴 목록 시트)
          constraints: maxHeight == null ? null : BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * maxHeight),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet)),
          ),
          padding: EdgeInsets.fromLTRB(Space.page, 8, Space.page, math.max(insets.bottom, Space.ctaBottom)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: EdgeInsets.only(bottom: title != null ? 4 : 16),
                  decoration: BoxDecoration(color: AppColors.track, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (title != null && !headInScroll) head!,
              // fit: 내용이 스스로 스크롤하는 시트(목록+아래 단추): 남은 높이 안에 맞춘다
              if (scroll)
                Flexible(child: SingleChildScrollView(child: headInScroll ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [head, body]) : body))
              else if (fit)
                Flexible(child: body)
              else
                body,
            ],
          ),
        ),
      );
    },
  );
}

/// 탭 = TDS Tab(size large 기본). 탭이 4개까지는 고정(fluid false: '최대 4개의 아이템 사용을 권장'), 5개부터는 fluid —
/// 칸 너비를 글자 폭에 맞추고 넘치면 가로 스크롤(Tab 절 '스크롤 되게 하기'). 글자는 t5 17(고른 칸 SemiBold grey900, 나머지 grey600).
/// 밑줄 모양 · 두께 · 색, fluid 칸 사이는 공식 글에 없음 → 지금 앱 값(2026-11-05 시안: 글자 폭 갈색 밑줄 3, 둥근 끝 · 칸 사이 28).
/// fill: 칸을 똑같이 나눠 화면 끝까지, 고른 칸은 굵은 본문색 + 칸 폭 밑줄(2), 아래 얇은 선
class Tabs<T> extends StatelessWidget {
  const Tabs({super.key, required this.items, required this.value, required this.onChange, this.fill = false, this.gap, this.line = true});
  final List<({T id, String label})> items;
  final T value;
  final ValueChanged<T> onChange;
  final bool fill;

  /// 밑줄 탭 아래 화면 폭 옅은 선(2026-11-20 사용자: 토스 앱 실측의 '은은한 선'). 고른 탭 밑줄이 그 위에 덮인다
  final bool line;
  /// 탭 사이(없으면 양 끝에 맞춰 벌린다)
  final double? gap;

  /// 고정 탭 최대 개수(TDS Tab fluid false '최대 4개 권장')
  static const fixedMax = 4;

  /// fluid 탭 사이(공식 없음 → 기록 탭 '갈피 · 감상' 간격과 같은 28)
  static const fluidGap = Space.xl;

  // 누르는 자리: 높이 48, 탭 사이 간격(gap)은 양쪽 탭이 반씩 나눠 누르는 자리로 쓴다(글자 자리는 그대로, '갈피' 37 → 51, 2026-11-16 QA 영숙 F12)
  @override
  Widget build(BuildContext context) {
    Widget tab(({T id, String label}) it, {double left = 0, double right = 0}) {
      final on = it.id == value;
      final text = fill
          ? AppType.labelStrong.copyWith(color: on ? AppColors.ink : AppColors.inkSoft)
          : (on ? AppType.body.strong : AppType.body.copyWith(color: AppColors.inkSoft));
      return Semantics(
        container: true,
        selected: on,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChange(it.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.hit),
            child: Padding(
              padding: EdgeInsets.only(top: fill ? 10 : 4, left: left, right: right),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  // 글자와 밑줄을 칸(48) 바닥에 붙인다: 고른 탭 밑줄이 탭 줄 아래 옅은 선과 같은 줄에 덮인다(2026-11-20 사용자 '1px 선이 선택 선이랑 같은 라인')
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(it.label, maxLines: 1, textAlign: TextAlign.center, style: text, textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25)),
                    Container(
                      height: fill ? 2 : 3,
                      margin: EdgeInsets.only(top: fill ? 10 : 7),
                      decoration: BoxDecoration(
                        color: on ? (fill ? AppColors.ink : AppColors.accent) : Colors.transparent,
                        borderRadius: BorderRadius.circular(fill ? 0 : 2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (fill) {
      return DecoratedBox(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 0.5))),
        child: Row(children: [for (final it in items) Expanded(child: tab(it))]),
      );
    }
    // 탭 줄 아래 옅은 선: 밑줄과 같은 바닥에 화면 폭(양옆 화면 여백까지)으로 깐다
    Widget lined(Widget row) => !line
        ? row
        : Stack(clipBehavior: Clip.none, children: [
            const Positioned(left: -Space.page, right: -Space.page, bottom: 0, child: Hairline(color: AppColors.divider)),
            row,
          ]);
    // TDS Tab fluid: 5개부터 글자 폭 칸 + 가로 스크롤(칸 사이는 반씩 나눠 누르는 자리)
    if (items.length > fixedMax) {
      final g = gap ?? fluidGap;
      return lined(SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, it) in items.indexed) tab(it, left: i > 0 ? g / 2 : 0, right: i < items.length - 1 ? g / 2 : 0),
        ]),
      ));
    }
    return lined(Row(
      mainAxisAlignment: gap == null ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, it) in items.indexed)
          tab(it, left: i > 0 && gap != null ? gap! / 2 : 0, right: i < items.length - 1 && gap != null ? gap! / 2 : 0),
      ],
    ));
  }
}

/// 필터 아이콘: 누르면 필터 시트. 걸러진 상태면 테마색 점
class FilterIcon extends StatelessWidget {
  const FilterIcon({super.key, required this.onPress, this.active = false});
  final VoidCallback onPress;
  final bool active;

  @override
  Widget build(BuildContext context) => IconBtn(
        label: active ? '필터, 걸러진 상태' : '필터',
        onPress: onPress,
        child: SizedBox(
          width: Space.touch,
          height: Space.touch,
          child: Stack(children: [
            const Center(child: LucideIcon('SlidersHorizontal', size: IconSize.head, color: AppColors.icon)),
            if (active)
              Positioned(
                top: 9,
                right: 7,
                child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
              ),
          ]),
        ),
      );
}

/// 필터 시트 묶음: 묶음 이름은 TDS ListHeader 제목(t5 Bold grey800), 첫 묶음 말고는 위에 선(Border full)
class FilterGroup extends StatelessWidget {
  const FilterGroup({super.key, required this.title, required this.children, this.first = false});
  final String title;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(top: first ? 0 : Space.m),
        padding: EdgeInsets.only(top: first ? 0 : Space.l),
        decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: 1))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.only(bottom: Space.xs), child: Semantics(header: true, child: WordText(title, style: AppType.listHeader))),
            ...children,
          ],
        ),
      );
}

/// 고르는 표시 원(필터·책 고르기 시트 줄 오른쪽): 안 고르면 빈 원, 고르면 갈색 원에 흰 체크(목표 시간·여러 권 고르기와 같은 원).
/// 2026-11-16 사용자 '조건 선택은 원으로': 고른 줄에만 체크가 뜨던 것을 모든 선택지에 원을 두는 방식으로
/// 고르는 원(하나 고르기 시트 · 여러 권 고르기 · 진열할 책 고르기 · 바코드 · 목록 가져오기 모두 이것, 2026-11-19 공통 규칙).
/// = TDS Checkbox.Circle(inputType radio로 하나 고르기에도 쓴다) · size 기본 24. 켠 색은 TDS 파랑 자리라 갈색, 끈 모양은 공식 없음 → 우리 값(흰 원 + 회색 테).
/// dim: 이미 있어서 고를 수 없는 것(흐린 채움 + 체크)
class RadioMark extends StatelessWidget {
  const RadioMark({super.key, required this.on, this.size = ControlSize.radio, this.dim = false});
  final bool on;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dim ? AppColors.inkFaint : on ? AppColors.accent : AppColors.white,
          border: Border.all(color: dim ? AppColors.inkFaint : on ? AppColors.accent : AppColors.line, width: 1.5),
        ),
        child: on || dim ? Center(child: LucideIcon('Check', size: size * 0.58, color: AppColors.onAccent, stroke: IconSize.checkStroke)) : null,
      );
}

/// 필터 항목(= TDS BottomSheet.Select의 선택지: 선택지마다 체크): 고른 항목은 진한 글씨, 오른쪽에 고르는 원(RadioMark 24).
/// chevron은 다른 시트로 넘어가는 항목, right는 스위치 등. 누르면 회색 터치 바탕
class FilterOption extends StatelessWidget {
  const FilterOption({super.key, required this.label, this.sub, this.selected = false, this.chevron = false, this.right, this.onPress});
  final String label;
  final String? sub;
  final bool selected;
  final bool chevron;
  final Widget? right;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    // 오른쪽이 스위치뿐이면 줄 전체가 스위치(ListItem과 같은 규칙, 2026-11-16 QA 영숙 F9·F12)
    final toggle = _rowToggle(onPress, right);
    final tap = onPress ?? (toggle == null ? null : () => toggle.onChange(!toggle.value));
    return Semantics(
      container: true,
      button: toggle == null,
      selected: toggle == null ? selected : null,
      toggled: toggle?.value,
      label: toggle == null ? null : [label, ?sub, if (toggle.label != label) toggle.label].join(', '),
      onTap: toggle != null ? tap : null,
      excludeSemantics: toggle != null,
      child: Pressable(
        onPress: tap,
        dim: true,
        bleed: Space.page,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: selected ? AppType.row.strong : AppType.row.copyWith(color: AppColors.inkSoft)),
                if (sub != null) WordText(sub!, style: AppType.caption),
              ]),
            ),
            const SizedBox(width: Space.m),
            right ?? (chevron ? const Chevron() : RadioMark(on: selected)),
          ]),
        ),
      ),
    );
  }
}

/// 검색창: 돋보기 + 입력 + 지우기(입력이 있을 때)
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.value, required this.onChange, this.placeholder, this.label, this.autofocus = false, this.onSubmit, this.busy = false, this.trailing, this.onBack});
  final String value;

  /// 검색 모드를 닫기(탭 첫 화면의 검색): 있으면 왼쪽 돋보기 자리에 뒤로 화살표(←). 오른쪽 '취소' 글자는 두지 않는다
  /// (2026-11-20 사용자 '검색할 때 취소는 저 글자 넣지 말고 맨 왼쪽 돋보기를 ← 이런 화살표로')
  final VoidCallback? onBack;
  /// 칸 오른쪽 끝에 둘 단추(예: 책 추가의 바코드). 지우기 단추 오른쪽에 놓인다
  final Widget? trailing;
  final ValueChanged<String> onChange;
  final String? placeholder;
  final String? label;
  final bool autofocus;
  final VoidCallback? onSubmit;
  final bool busy;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(SearchField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 돋보기: 검색어가 있으면 찾고, 없으면 입력칸을 연다(2026-11-15 QA 민혁 F8 '돋보기를 눌러도 아무 반응이 없다')
  void _magnifier() {
    if (_c.text.trim().isEmpty || widget.onSubmit == null) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      widget.onSubmit!();
    }
  }

  @override
  // 높이 ControlSize.search(2026-11-18 사용자 '검색창 두께 좀 줄이고', 예전 52)
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: ControlSize.search),
        padding: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(Shape.input)),
        child: Row(children: [
          Semantics(
            container: true,
            button: true,
            label: widget.onBack != null ? '검색 닫기' : '검색',
            onTap: widget.onBack ?? _magnifier,
            excludeSemantics: true,
            child: Pressable(
              onPress: widget.onBack ?? _magnifier,
              child: SizedBox(
                width: Space.hit,
                height: Space.hit,
                child: Center(child: LucideIcon(widget.onBack != null ? 'ArrowLeft' : 'Search', size: IconSize.base, color: widget.onBack != null ? AppColors.inkSoft : AppColors.icon)),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: widget.label,
              textField: true,
              child: TextField(
                controller: _c,
                focusNode: _focus,
                autofocus: widget.autofocus,
                onChanged: widget.onChange,
                onSubmitted: (_) => widget.onSubmit?.call(),
                textInputAction: widget.onSubmit != null ? TextInputAction.search : TextInputAction.done,
                style: AppType.input,
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  hintText: widget.placeholder,
                  hintStyle: AppType.input.copyWith(color: AppColors.inkFaint),
                ),
              ),
            ),
          ),
          if (widget.busy)
            const SizedBox(width: Space.touch, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkSoft))))
          else if (widget.value.isNotEmpty)
            Semantics(
              container: true,
              button: true,
              label: '검색어 지우기',
              onTap: () => widget.onChange(''),
              excludeSemantics: true,
              child: Pressable(
                onPress: () => widget.onChange(''),
                child: SizedBox(
                  width: Space.hit,
                  height: Space.hit,
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(color: AppColors.inkFaint, shape: BoxShape.circle),
                      child: const Center(child: LucideIcon('X', size: 14, color: AppColors.bg, stroke: 2.2)),
                    ),
                  ),
                ),
              ),
            ),
          // 오른쪽 끝 단추(바코드 등)는 검색어가 비었을 때만: 글자를 넣으면 같은 자리에 지우기(X)가 나온다(둘이 붙으면 선처럼 보였다, 2026-11-18 사용자)
          if (widget.value.isEmpty && !widget.busy) ?widget.trailing,
        ]),
      );
}


/// 음수 위 여백(지금 앱 marginTop −dy): 자식을 dy만큼 위로 그리고, 차지하는 높이도 dy만큼 줄인다
class PullUp extends SingleChildRenderObjectWidget {
  const PullUp({super.key, required this.dy, required Widget super.child});
  final double dy;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderPullUp(dy);

  @override
  void updateRenderObject(BuildContext context, RenderPullUp renderObject) => renderObject.dy = dy;
}

class RenderPullUp extends RenderShiftedBox {
  RenderPullUp(this._dy) : super(null);
  double _dy;
  set dy(double v) {
    if (v == _dy) return;
    _dy = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child!;
    c.layout(constraints.loosen(), parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = Offset(0, -_dy);
    size = constraints.constrain(Size(c.size.width, math.max(0, c.size.height - _dy)));
  }
}

/// 고르는 블록(서로 바꿔 고르는 선택지: 분위기·목표 시간). TDS에 같은 부품이 없다 → 모양은 우리 값(모서리 14, 안쪽 16, 흰 바탕 + 얇은 테두리,
/// 고르면 갈색 테두리). 이름 t5 SemiBold · 설명 t7 · 고른 표시는 Checkbox 원 24
class Choice extends StatelessWidget {
  const Choice({super.key, required this.label, required this.selected, required this.onPress, this.sub, this.compact = false, this.child});
  final String label;
  final String? sub;
  final bool selected, compact;
  final VoidCallback onPress;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // 고른 표시는 TDS Checkbox size 기본 24(예전 20 · 22)
    Widget check({double size = ControlSize.radio, bool ring = false}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: ring ? Border.all(color: AppColors.bg, width: 2) : null),
          child: const Center(child: LucideIcon('Check', size: 14, color: AppColors.onAccent, stroke: 3)),
        );
    final wide = !compact && sub == null;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: [label, ?sub].join(', '),
      onTap: onPress,
      excludeSemantics: true,
      child: _ChoiceBox(
        selected: selected,
        onPress: onPress,
        compact: compact,
        child: Stack(clipBehavior: Clip.none, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            ?child,
            Padding(
              padding: EdgeInsets.only(right: wide && selected ? 28 : 0),
              child: WordText(label, textAlign: compact ? TextAlign.center : TextAlign.left, style: AppType.rowStrong),
            ),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: WordText(sub!, textAlign: compact ? TextAlign.center : TextAlign.left, style: AppType.caption)),
          ]),
          // 넓은 한 줄은 오른쪽 세로 가운데, 좁은 칸은 모서리에 걸쳐, 설명이 있는 칸은 오른쪽 위
          if (selected)
            wide
                ? Positioned(top: 0, bottom: 0, right: 0, child: Center(child: check()))
                : compact
                    ? Positioned(top: -12 - 7, right: -8 - 7, child: check(ring: true))
                    : Positioned(top: -16 + 8, right: -16 + 8, child: check()),
        ]),
      ),
    );
  }
}

class _ChoiceBox extends StatefulWidget {
  const _ChoiceBox({required this.selected, required this.onPress, required this.compact, required this.child});
  final bool selected, compact;
  final VoidCallback onPress;
  final Widget child;

  @override
  State<_ChoiceBox> createState() => _ChoiceBoxState();
}

class _ChoiceBoxState extends State<_ChoiceBox> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: ControlSize.choice),
          padding: widget.compact ? const EdgeInsets.symmetric(vertical: 12, horizontal: 8) : const EdgeInsets.all(16),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _down && !widget.selected ? AppColors.surface : AppColors.bg,
            borderRadius: BorderRadius.circular(Shape.choice),
            border: Border.all(color: widget.selected ? AppColors.accent : AppColors.line, width: 1.5),
          ),
          child: widget.child,
        ),
      );
}

/// 밤 장면 위 밝은 색(독서 타이머를 접었을 때)
abstract final class NightColors {
  static const ink = Color(0xFFF6EFE6);
  static const inkSoft = Color.fromRGBO(246, 239, 230, 0.78);
  static const line = Color.fromRGBO(246, 239, 230, 0.22);
  static const shade = Color.fromRGBO(16, 13, 11, 0.28);
  static const fade = Color(0xFF100D0B);

  static const all = <String, (Color, String)>{
    'ink': (ink, '장면 위 글자'),
    'inkSoft': (inkSoft, '장면 위 보조 글자(ink 78%)'),
    'line': (line, '장면 위 선(ink 22%)'),
    'shade': (shade, '장면 위 글자 그림자(28%)'),
    'fade': (fade, '장면 아래 어둠'),
  };
}

/// 막대 조절(소리 크기): 누른 곳부터 끌어 바꾸고, 손을 떼면 onCommit. dim이면 켜진 쪽·손잡이를 회색으로(값은 지키되 꺼진 상태).
/// night: 어두운 장면 위(밝은 크림색 막대와 손잡이)
class AppSlider extends StatefulWidget {
  const AppSlider({super.key, required this.value, required this.onCommit, required this.label, this.onChange, this.valueText, this.dim = false, this.night = false});
  final double value;
  final ValueChanged<double>? onChange;
  final ValueChanged<double> onCommit;
  final String label;
  final String? valueText;
  final bool dim, night;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  static const _pad = 14.0;
  double _last = 0;

  double _at(double x, double w) {
    final span = w - _pad * 2;
    return span > 0 ? ((x - _pad) / span).clamp(0.0, 1.0) : _last;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.value * 100).round();
    final fill = widget.night ? (widget.dim ? NightColors.line : NightColors.ink) : widget.dim ? AppColors.inkFaint : AppColors.accent;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, span = math.max(0.0, w - _pad * 2);
      return Semantics(
        slider: true,
        label: widget.label,
        value: widget.valueText ?? '$pct%',
        increasedValue: '${math.min(100, pct + 10)}%',
        decreasedValue: '${math.max(0, pct - 10)}%',
        onIncrease: () => widget.onCommit(math.min(1, ((widget.value + 0.1) * 10).round() / 10)),
        onDecrease: () => widget.onCommit(math.max(0, ((widget.value - 0.1) * 10).round() / 10)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => widget.onChange?.call(_last = _at(d.localPosition.dx, w)),
          onHorizontalDragUpdate: (d) => widget.onChange?.call(_last = _at(d.localPosition.dx, w)),
          onHorizontalDragEnd: (_) => widget.onCommit(_last),
          onTapDown: (d) => widget.onChange?.call(_last = _at(d.localPosition.dx, w)),
          onTapUp: (_) => widget.onCommit(_last),
          // 누르는 자리 높이 48(44였다, 막대·손잡이 겉모양은 그대로 가운데, 2026-11-16 QA 영숙 F12)
          child: SizedBox(
            height: Space.hit,
            width: w,
            child: Stack(children: [
              Positioned(left: _pad, right: _pad, top: Space.hit / 2 - 3, height: 6, child: _bar(widget.night ? const Color.fromRGBO(246, 239, 230, 0.32) : AppColors.track)),
              Positioned(left: _pad, top: Space.hit / 2 - 3, height: 6, width: span * widget.value, child: _bar(fill)),
              Positioned(
                left: _pad + span * widget.value - 12,
                top: Space.hit / 2 - 12,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.night ? NightColors.ink : AppColors.white,
                    border: widget.night ? null : Border.all(color: fill, width: 2),
                    boxShadow: const [Shape.floatShadow],
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _bar(Color c) => DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));
}

/// 입력칸 이름 나누기: '쪽수 (선택)', '메모 (선택, 설명)' → 이름·'선택'/'필수'·설명
({String name, String? tag, String? note}) splitLabel(String label) {
  final m = RegExp(r'^(.+?) \((.+)\)$').firstMatch(label);
  if (m == null) return (name: label, tag: null, note: null);
  final parts = m[2]!.split(', ');
  final tag = parts.first == '선택' || parts.first == '필수' ? parts.removeAt(0) : null;
  return (name: m[1]!, tag: tag, note: parts.isEmpty ? null : parts.join(', '));
}

class _LabelRow extends StatelessWidget {
  const _LabelRow(this.name, this.tag);
  final String name;
  final String? tag;

  // 화면 읽기에서는 빠진다: 입력칸·고르는 칸이 같은 이름을 갖고 있어 두 번 읽혔다(2026-11-16 QA 영숙 F9)
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: ExcludeSemantics(
          // 필수 칸은 이름 뒤 주의색 '*', 선택 칸은 회색 '선택'(2026-11-21 책 정보 수정 · 갈피 남기기 시안)
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: tag == '필수' ? 4 : 8, children: [
            WordText(name, style: AppType.label),
            if (tag == '필수') Text('*', style: AppType.label.copyWith(color: AppColors.danger)) else if (tag != null) Text(tag!, style: AppType.caption.copyWith(color: AppColors.inkSoft)),
          ]),
        ),
      );
}

/// 입력칸: 입력칸색 단색 바탕, 테두리 없음, 누르면 갈색 테두리. 이름은 위에, 단위('쪽')는 칸 안 오른쪽, 도움말·오류는 아래
class Field extends StatefulWidget {
  const Field({super.key, required this.label, required this.value, required this.onChange, this.hint, this.error, this.unit, this.placeholder, this.multiline = false, this.number = false, this.minHeight, this.showLabel = true});
  final String label;

  /// 이름 줄을 그릴지(이름은 화면 읽기에만 남긴다): 화면이 이름 줄을 따로 그릴 때(갈피 남기기 '문장 · 사진만 저장')
  final bool showLabel;
  final String value;
  final ValueChanged<String> onChange;
  final String? hint, error, unit, placeholder;
  final bool multiline, number;
  final double? minHeight;

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  late final _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(Field old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = splitLabel(widget.label);
    final placeholder = widget.placeholder ?? l.note;
    final help = widget.placeholder != null && l.note != null ? l.note : widget.hint;
    final border = widget.error != null ? AppColors.danger : _focus.hasFocus ? AppColors.accent : AppColors.input;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.showLabel) _LabelRow(l.name, l.tag),
        Stack(children: [
          Container(
            constraints: BoxConstraints(minHeight: widget.minHeight ?? (widget.multiline ? ControlSize.fieldMultiline : ControlSize.field)),
            decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(Shape.input), border: Border.all(color: border)),
            child: Semantics(
              label: widget.label,
              textField: true,
              child: TextField(
                controller: _c,
                focusNode: _focus,
                onChanged: widget.onChange,
                maxLines: widget.multiline ? null : 1,
                keyboardType: widget.number ? TextInputType.number : (widget.multiline ? TextInputType.multiline : TextInputType.text),
                textInputAction: TextInputAction.done,
                // 한 줄 칸은 글자 줄 22로 고정: 위아래 12 + 22 + 테두리 2 = 48(줄 높이를 기기 글꼴에 맡기면 칸 높이가 기기마다 달랐다)
                style: AppType.input.copyWith(height: widget.multiline ? 25 / 16 : 22 / 16),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  // 한 줄 칸은 위아래 12(칸 높이 48 안에 글자 줄 가운데), 여러 줄은 위 14 · 아래 16
                  contentPadding: EdgeInsets.fromLTRB(16, widget.multiline ? 14 : 12, widget.unit != null ? 44 : 16, widget.multiline ? 16 : 12),
                  // 자리 표시 글도 낱말 단위로 줄을 바꾼다('…빠져 / 요'처럼 한 글자만 넘어갔다, 2026-11-21 촬영 확인)
                  hintText: placeholder == null ? null : keepAll(placeholder),
                  hintMaxLines: widget.multiline ? 3 : 1,
                  hintStyle: AppType.input.copyWith(color: AppColors.inkFaint, height: widget.multiline ? 25 / 16 : 22 / 16),
                ),
              ),
            ),
          ),
          if (widget.unit != null)
            Positioned(right: 16, top: 0, bottom: 0, child: IgnorePointer(child: Center(child: Text(widget.unit!, style: AppType.input.copyWith(color: AppColors.inkSoft))))),
        ]),
        if (widget.error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: WordText(widget.error!, style: AppType.caption.copyWith(color: AppColors.danger)))
        else if (help != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: WordText(help, style: AppType.caption)),
      ]),
    );
  }
}

/// 고르는 칸(누르면 시트·화면에서 고른다): 입력칸과 같은 모양 + 오른쪽 화살표
class SelectField extends StatelessWidget {
  const SelectField({super.key, required this.label, required this.placeholder, required this.onPress, this.value, this.sub, this.disabled = false, this.leading, this.showLabel = true, this.bottom = Space.xl, this.outlined = false});
  final String label, placeholder;
  final String? value, sub;
  final VoidCallback onPress;
  final bool disabled;

  /// 값 앞 그림(책 표지 작게 40): 화면 맨 위에서 이 화면의 책을 고르는 칸(독서 기록, 2026-11-21 사용자 '좌우 꽉 찬 썸네일이랑 이름 넣는 박스')
  final Widget? leading;

  /// 이름 줄을 그릴지(이름은 화면 읽기에 남는다). 화면 제목이 이미 무엇을 고르는지 말할 때 뺀다
  final bool showLabel;

  /// 칸 아래 여백(입력칸 사이 Space.xl). 바로 아래가 전환 칸이면 Space.l
  final double bottom;

  /// 흰 바탕 + 옅은 회색 테두리(line 1). 입력 양식 안의 고르는 칸은 회색 채움 그대로, 화면 맨 위에서 이 화면이 보여 줄 대상을 고르는 칸(독서 기록 책 칸)만
  /// (2026-11-21 사용자 '그냥 회색 선으로 감싸는 거 어때, 안에는 흰색에')
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final l = splitLabel(label);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showLabel) _LabelRow(l.name, l.tag),
        Semantics(
          container: true,
          button: true,
          enabled: !disabled,
          label: '$label, ${value ?? placeholder}',
          onTap: disabled ? null : onPress,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: disabled ? null : onPress,
            child: Container(
              // 입력칸(Field)과 같은 높이 ControlSize.field(2026-11-19 공통 규칙: 52였다)
              constraints: const BoxConstraints(minHeight: ControlSize.field),
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
              decoration: outlined
                  ? BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(Shape.input))
                  : BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(Shape.input)),
              child: Row(children: [
                if (leading != null) ...[leading!, const SizedBox(width: Space.m)],
                // 고른 값과 덧붙임(책 저자)은 한 줄: '데미안  헤르만 헤세', 덧붙임은 세로선 없이 작은 회색 글자(caption)로 글자 바닥을 맞춘다
                // (2026-11-21 갈피 남기기 시안: 두 줄이라 칸이 높았다. 같은 날 사용자 '가호 | 무라카미 이렇게 하지 말고 … 무라카미는 좀 작고 회색으로')
                Expanded(
                  child: value != null && sub != null
                      ? Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                          Flexible(child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.input.strong)),
                          const SizedBox(width: Space.s),
                          Flexible(child: Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption)),
                        ])
                      : WordText(value ?? placeholder, maxLines: 2, style: AppType.input.copyWith(color: value != null ? AppColors.ink : AppColors.inkFaint)),
                ),
                if (!disabled) ...[const SizedBox(width: Space.s), const Chevron()],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 글자 버튼 = TDS TextButton variant clear(기본, 밑줄 없음) · size medium(= t5, 'Migrate to v2.x' TextButton 표, AppType.link).
/// 색: 갈색 = 이어서 할 일(TDS 글자 단추 · 더 보기 blue500 자리), 회색 grey600 = 조심스러운 일(회색은 작고 보통 굵기 AppType.subLink 15). 눌림은 옅어짐(공식 없음 → 우리 값)
/// 큰 단추 바로 아래 보조 행동(계속 추가 · 장정 직접 고르기 · 보관만 하기 · 취소).
/// 간격(Space.xs) · 옅은 글자 · 누르는 높이 48을 한 곳에서 정한다(2026-11-18 사용자: 화면마다 간격·글자색·단추 모양이 달랐다)
class SubAction extends StatelessWidget {
  const SubAction({super.key, required this.label, required this.onPress, this.disabled = false});
  final String label;
  final VoidCallback onPress;
  final bool disabled;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: Space.xs), child: TextLink(label: label, soft: true, disabled: disabled, onPress: onPress));
}

class TextLink extends StatelessWidget {
  const TextLink({super.key, required this.label, required this.onPress, this.soft = false, this.disabled = false, this.start = false, this.ink = false, this.bold = false, this.danger = false});

  /// 본문 색(내 책 '선택', 2026-11-17 시안)
  final bool ink;

  /// 굵게 bold(AlertDialog.AlertButton fontWeight 기본 'bold')
  final bool bold;

  /// 주의색(지우기 알림의 확인 글자 단추)
  final bool danger;
  final String label;
  final VoidCallback onPress;
  final bool soft, disabled;

  /// 가운데가 아니라 왼쪽에 글자 폭만큼(지금 앱 alignSelf: 'flex-start')
  final bool start;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        enabled: !disabled,
        label: label,
        onTap: disabled ? null : onPress,
        excludeSemantics: true,
        child: Opacity(
          opacity: disabled ? disabledOpacity : 1,
          child: Align(
            alignment: start ? Alignment.centerLeft : Alignment.center,
            widthFactor: start ? 1 : null,
            child: Pressable(
              onPress: disabled ? null : onPress,
              child: ConstrainedBox(
                // 누르는 자리 높이 48(44였다, 2026-11-16 QA 영숙 F12)
                constraints: const BoxConstraints(minHeight: Space.hit),
                // 가운데 정렬은 양옆 8을 누르는 자리로 둔다(지금 앱 hitSlop 8). 왼쪽 정렬은 글자가 위 글줄과 맞게 여백 없이
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: start ? 0 : 8),
                  // 회색 글자 단추(soft: 장정 직접 고르기 · 계속 추가 · 나중에 정하기 · 조건 지우기 · 원문 보기 …)는 작고 보통 굵기 subLink 15(토스 '평생 수수료 무료'처럼,
                  // 2026-11-21 사용자 '서브 글씨들 토스랑 다르게 너무 두껍지 않나 크기랑 반영해서'). 갈색 · 본문색 · 주의색 글자 단추는 link 17 굵게
                  child: Center(widthFactor: 1, child: WordText(label,
                      style: soft && !danger
                          ? AppType.subLink.copyWith(fontFamily: bold ? AppFonts.uiTitle : null)
                          : AppType.link.copyWith(
                              fontFamily: bold ? AppFonts.uiTitle : null,
                              color: danger ? AppColors.danger : ink ? AppColors.ink : null,
                            ))),
                ),
              ),
            ),
          ),
        ),
      );
}

/// 구역 머리줄 = TDS ListHeader: 왼쪽 제목 TitleParagraph t4 Bold grey800, 제목 옆 작은 회색 개수('감상 1개', 공식 없음 → 우리 값),
/// 제목 아래 설명 DescriptionParagraph(t6 grey600, descriptionPosition bottom), 오른쪽 RightArrow(글자 t6 grey700 · 화살표 grey400).
/// 머리줄 높이는 글 높이만 차지해 제목과 내용 사이가 좁다(2026-11-17 시안)
class SectionHead extends StatelessWidget {
  const SectionHead({super.key, required this.title, this.count, this.note, this.link, this.onLink, this.chevron = false, this.linkLabel, this.extra, this.onExtra});
  final String title;
  final String? count, link;

  /// 제목 아래 한 줄(출처 'YES24 베스트셀러' 등, sub)
  final String? note;
  final VoidCallback? onLink;
  final bool chevron;

  /// 화면 읽기 이름(없으면 '제목 링크')
  final String? linkLabel;

  /// 링크 앞 글자 하나 더(같은 글자 · 꺾쇠 없음, 화면 읽기는 '제목 글자'): 책 정보 독서 기록 '추가 · 전체 보기'(2026-11-23)
  final String? extra;
  final VoidCallback? onExtra;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: note != null ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: Text.rich(TextSpan(text: title, style: AppType.section, children: [
                if (count != null) TextSpan(text: '  $count', style: AppType.count),
              ])),
            ),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: WordText(note!, style: AppType.sub)),
          ]),
        ),
        if (extra != null && onExtra != null)
          Semantics(
            button: true,
            label: '$title $extra',
            excludeSemantics: true,
            onTap: onExtra,
            child: Pressable(
              onPress: onExtra,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Space.hit, minWidth: Space.hit),
                child: Padding(
                  // 다음 링크와 사이(글자 사이 12)
                  padding: EdgeInsets.only(right: link != null && onLink != null ? Space.m : 0),
                  child: Center(widthFactor: 1, child: Text(extra!, style: AppType.secondary)),
                ),
              ),
            ),
          ),
        if (link != null && onLink != null)
          Semantics(
            button: true,
            label: linkLabel ?? '$title $link',
            excludeSemantics: true,
            onTap: onLink,
            child: Pressable(
              onPress: onLink,
              // 누르는 자리 48(2026-11-19 규칙: 30이었다). 글자는 TDS ListHeader.RightArrow(t6 grey700 + 화살표 grey400)
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Space.hit, minWidth: Space.hit),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(link!, style: AppType.secondary),
                  if (chevron) const Chevron(),
                ]),
              ),
            ),
          ),
      ]);
}

/// 테두리 상자(읽은 기간 카드 · 통계 평균 카드): 흰 바탕 · 옅은 선 · 둥근 모서리 12 · 안쪽 18/14
class OutlineBox extends StatelessWidget {
  const OutlineBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(Shape.card), border: Border.all(color: AppColors.line)),
        child: child,
      );
}

/// 시트 안 묶음 이름('정렬' · '유형'): TDS ListHeader 제목 t5 Bold grey800, 아래 12
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.m),
        child: Semantics(header: true, child: Text(text, style: AppType.listHeader)),
      );
}

/// 필터 켜고 끄는 줄('책장에 없는 책만 1권' · '아껴둔 갈피만'): 이름 + 회색 개수 + 스위치. 줄 어디를 눌러도 바뀌고 화면 읽기는 한 번.
/// 글자·높이는 화면의 켜고 끄는 줄(ListItem + Toggle, 내 정보 '진동')과 같다(row 18 보통 · 50, 2026-11-19 공통 규칙: 굵은 18 · 60이었다)
class FilterToggleRow extends StatelessWidget {
  const FilterToggleRow({super.key, required this.label, this.count, required this.value, required this.onChange});
  final String label;
  final String? count;
  final bool value;
  final ValueChanged<bool> onChange;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        toggled: value,
        label: [label, ?count].join(', '),
        onTap: () => onChange(!value),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChange(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Row(children: [
              Text(label, style: AppType.row),
              const SizedBox(width: Space.m),
              Expanded(child: count != null ? Text(count!, style: AppType.sub) : const SizedBox.shrink()),
              Toggle(label: label, value: value, onChange: onChange),
            ]),
          ),
        ),
      );
}

/// 필터 시트의 고르는 칸(갈피 유형·내 책 정렬, 2026-11-17 사용자 시안): 테두리 상자, 고르면 진한 테두리와 오른쪽 위 모서리에 체크.
/// 체크는 둥근 모서리 위에 걸치게(가운데가 모서리 곡선 위, 2026-11-17 사용자 '조금만 오른쪽으로, 모서리에')
/// 고르는 칸 모서리 체크 지름(바깥 흰 테 2 포함). 시안: 칸 높이의 약 0.45
const _choiceBadge = ControlSize.choiceBadge;

class ChoiceBox extends StatelessWidget {
  const ChoiceBox({super.key, required this.label, required this.on, required this.onPress});
  final String label;
  final bool on;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        label: label,
        excludeSemantics: true,
        onTap: onPress,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPress,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              constraints: const BoxConstraints(minHeight: Space.hit),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(Shape.button),
                // 고른 칸은 테마색 테두리·테마색 체크(2026-11-18 사용자 '테마색 어디 갔고 체크표시 왜 이렇게 작아': 회색이었고 체크 20)
                border: Border.all(color: on ? AppColors.accent : AppColors.line, width: on ? 1.5 : 1),
              ),
              child: Text(label, maxLines: 1, textAlign: TextAlign.center, style: AppType.label),
            ),
            if (on)
              Positioned(
                top: -_choiceBadge / 2 + 2,
                right: -_choiceBadge / 2 + 2,
                child: Container(
                  width: _choiceBadge,
                  height: _choiceBadge,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
                  child: const Center(child: LucideIcon('Check', size: 14, color: AppColors.bg, stroke: 3)),
                ),
              ),
          ]),
        ),
      );
}

/// 켜고 끄는 스위치(갈색 둥근 바탕 안에 흰 손잡이, 50×30·손잡이 24). 안드로이드 기본 스위치는 손잡이가 바탕 밖으로 커서 직접 그린다
/// 스위치 손잡이와 바탕 끝 사이((30 - 24) / 2)
const _toggleInset = (ControlSize.toggleHeight - ControlSize.toggleKnob) / 2;

class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.value, required this.onChange, required this.label});
  final bool value;
  final ValueChanged<bool> onChange;
  final String label;

  // 누르는 자리는 높이 48(겉모양 50×30은 가운데 그대로, 2026-11-16 QA 영숙 F12)
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        toggled: value,
        label: label,
        onTap: () => onChange(!value),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChange(!value),
          child: SizedBox(
            width: ControlSize.toggleWidth,
            height: Space.hit,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value ? 1 : 0),
                duration: const Duration(milliseconds: 160),
                builder: (_, x, _) => Container(
                  width: ControlSize.toggleWidth,
                  height: ControlSize.toggleHeight,
                  padding: const EdgeInsets.all(_toggleInset),
                  decoration: BoxDecoration(color: Color.lerp(AppColors.track, AppColors.accent, x), borderRadius: BorderRadius.circular(ControlSize.toggleHeight / 2)),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: Offset(x * (ControlSize.toggleWidth - ControlSize.toggleKnob - _toggleInset * 2), 0),
                      child: Container(
                        width: ControlSize.toggleKnob,
                        height: ControlSize.toggleKnob,
                        decoration: const BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color.fromRGBO(59, 42, 36, 0.18), offset: Offset(0, 1), blurRadius: 2)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// 화면 맨 아래 작은 브랜드 줄(짧은 선 + '책장 한켠')
class BrandFooter extends StatelessWidget {
  const BrandFooter({super.key, this.center = false});

  /// 가운데 글자만(내 정보 시안, 2026-11-17)
  final bool center;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '책장 한켠',
        excludeSemantics: true,
        child: center
            ? Padding(padding: const EdgeInsets.only(top: Space.block * 2, bottom: Space.l), child: Center(child: Text('책장 한켠', style: AppType.sub)))
            : Padding(
          padding: const EdgeInsets.only(top: Space.block),
          child: Row(children: [
            Container(width: 20, height: 2 / MediaQuery.devicePixelRatioOf(context), color: AppColors.inkFaint),
            const SizedBox(width: 12),
            Text('책장 한켠', style: AppType.sub),
          ]),
        ),
      );
}

/// 별점(1~5, 같은 별을 다시 누르면 지운다). onChange가 없으면 보이기만
class Stars extends StatelessWidget {
  const Stars({super.key, this.value, this.onChange, this.size = 24});
  final num? value;
  final ValueChanged<int?>? onChange;
  final double size;
  static const color = AppColors.star;

  // 누를 수 있는 별은 별마다 48×48 칸(별 크기는 그대로, 칸 가운데). 24 칸이라 4점을 주려다 3·5점이 눌리기 쉬웠다(2026-11-16 QA 영숙 F12)
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var n = 1; n <= 5; n++) ...[
          if (n > 1 && onChange == null) const SizedBox(width: 4),
          Semantics(
            container: true,
            button: onChange != null,
            selected: value != null && n <= value!,
            label: '별점 $n점',
            onTap: onChange == null ? null : () => onChange!(value == n ? null : n),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onChange == null ? null : () => onChange!(value == n ? null : n),
              child: onChange == null
                  ? LucideIcon('Star', size: size, color: color, stroke: 1.3, fill: value != null && n <= value! ? color : null)
                  : SizedBox(
                      width: math.max(Space.hit, size),
                      height: math.max(Space.hit, size),
                      child: Center(child: LucideIcon('Star', size: size, color: color, stroke: 1.3, fill: value != null && n <= value! ? color : null)),
                    ),
            ),
          ),
        ],
      ]);
}

/// 요일 이름(일요일부터). 앱의 요일 글자는 이것 하나(달력 · 통계 · 읽기 탭 날짜)
const weekdays = ['일', '월', '화', '수', '목', '금', '토'];
String _p2(int n) => n.toString().padLeft(2, '0');

/// 시각 글자 하나: '오후 9:05'(앱의 시각 글자, timeLabel · timeRange도 이것을 쓴다)
String clockText(int hour, int minute) => '${hour < 12 ? '오전' : '오후'} ${hour % 12 == 0 ? 12 : hour % 12}:${_p2(minute)}';

/// 'HH:MM' → '오후 9:05'(형식이 다르면 그대로)
String hmLabel(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm);
  return m == null ? hhmm : clockText(int.parse(m[1]!), int.parse(m[2]!));
}
String dayKey(int y, int m, int d) => '$y-${_p2(m)}-${_p2(d)}';
String todayKey([DateTime? now]) {
  final t = now ?? DateTime.now();
  return dayKey(t.year, t.month, t.day);
}

/// 칸에 보이는 날짜: 상세 날짜 쓰는 법('2026년 11월 9일', features/book/labels.dart dateLong과 같다)
String dayLabel(String v) {
  final p = v.split('-');
  return p.length == 3 ? '${p[0]}년 ${int.parse(p[1])}월 ${int.parse(p[2])}일' : v;
}

/// 날짜 칸: 누르면 한 달 달력 시트에서 하루를 고른다(고를 수 없는 날은 흐리게). 값은 'YYYY-MM-DD' 또는 ''(정하지 않음)
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChange, this.placeholder = '날짜 고르기', this.min, this.max, this.clearable = false, this.disabled = false});
  final String label, value, placeholder;
  final ValueChanged<String> onChange;
  final String? min, max;
  final bool clearable, disabled;

  @override
  Widget build(BuildContext context) => SelectField(
        label: label,
        value: value.isNotEmpty ? dayLabel(value) : null,
        placeholder: placeholder,
        disabled: disabled,
        onPress: () async {
          final r = await showDatePickerSheet(context, title: label.replaceAll(RegExp(r' \(.+\)$'), ''), value: value, min: min, max: max ?? todayKey(), clearable: clearable && value.isNotEmpty);
          if (r != null && r != value) onChange(r);
        },
      );
}

/// 날짜 고르기 시트: 고른 날('YYYY-MM-DD'), '날짜 지우기'면 '', 닫으면 null
Future<String?> showDatePickerSheet(BuildContext context, {required String title, required String value, String? min, String? max, bool clearable = false}) => showSheet<String>(
      context,
      title: title,
      builder: (ctx) => _DateBody(value: value, min: min, max: max, clearable: clearable),
    );

class _DateBody extends StatefulWidget {
  const _DateBody({required this.value, this.min, this.max, this.clearable = false});
  final String value;
  final String? min, max;
  final bool clearable;

  @override
  State<_DateBody> createState() => _DateBodyState();
}

class _DateBodyState extends State<_DateBody> {
  late int _y, _m;

  @override
  void initState() {
    super.initState();
    // 처음 보이는 달: 고른 날, 없으면 마지막으로 고를 수 있는 날(보통 오늘)이 든 달
    final start = widget.value.isNotEmpty ? widget.value : widget.max ?? todayKey();
    _y = int.parse(start.substring(0, 4));
    _m = int.parse(start.substring(5, 7));
  }

  void _shift(int k) {
    final t = DateTime(_y, _m + k, 1);
    setState(() {
      _y = t.year;
      _m = t.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_y, _m, 1).weekday % 7;
    final days = DateTime(_y, _m + 1, 0).day;
    final cells = <int?>[for (var i = 0; i < first; i++) null, for (var d = 1; d <= days; d++) d];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final month = '$_y-${_p2(_m)}';
    final canPrev = widget.min == null || month.compareTo(widget.min!.substring(0, 7)) > 0;
    final canNext = widget.max == null || month.compareTo(widget.max!.substring(0, 7)) < 0;
    final today = todayKey();
    final dayStyle = AppType.bodySmall.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconBtn(label: '이전 달', disabled: !canPrev, onPress: () => _shift(-1), child: LucideIcon('ChevronLeft', color: canPrev ? AppColors.icon : AppColors.inkFaint)),
          const SizedBox(width: Space.l),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 128),
            child: Semantics(header: true, child: Text('$_y년 $_m월', textAlign: TextAlign.center, style: AppType.section.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
          ),
          const SizedBox(width: Space.l),
          IconBtn(label: '다음 달', disabled: !canNext, onPress: () => _shift(1), child: LucideIcon('ChevronRight', color: canNext ? AppColors.icon : AppColors.inkFaint)),
        ]),
      ),
      LayoutBuilder(builder: (context, box) {
        final cw = box.maxWidth / 7;
        // 날짜 칸 높이 48(누르는 자리, 2026-11-16 QA 영숙 F12)
        Widget cell(Widget child) => SizedBox(width: cw, height: Space.hit, child: Center(child: child));
        return Wrap(children: [
          for (final w in weekdays) cell(ExcludeSemantics(child: Text(w, style: AppType.caption))),
          for (final (i, d) in cells.indexed)
            if (d == null)
              cell(const SizedBox.shrink())
            else
              Builder(builder: (_) {
                final k = dayKey(_y, _m, d);
                final off = (widget.min != null && k.compareTo(widget.min!) < 0) || (widget.max != null && k.compareTo(widget.max!) > 0);
                final on = k == widget.value;
                return Semantics(
                  container: true,
                  button: true,
                  enabled: !off,
                  selected: on,
                  label: '$_m월 $d일 ${weekdays[i % 7]}요일${k == today ? ', 오늘' : ''}',
                  onTap: off ? null : () => Navigator.pop(context, k),
                  excludeSemantics: true,
                  child: Pressable(
                    onPress: off ? null : () => Navigator.pop(context, k),
                    child: cell(Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: on ? AppColors.accent : null),
                      alignment: Alignment.center,
                      child: Text('$d',
                          style: dayStyle.copyWith(
                            fontFamily: on || k == today ? AppFonts.uiBold : AppFonts.ui,
                            color: on ? AppColors.onAccent : off ? AppColors.inkFaint : k == today ? AppColors.accent : AppColors.ink,
                          )),
                    )),
                  ),
                );
              }),
        ]);
      }),
      if (widget.clearable) Padding(padding: const EdgeInsets.only(top: Space.s), child: TextLink(label: '날짜 지우기', soft: true, onPress: () => Navigator.pop(context, ''))),
    ]);
  }
}

/// 시각 칸('HH:MM', 지금 앱 ui/pickers TimeField): 누르면 시·분 두 돌림 목록 시트
class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.label, required this.value, required this.onChange});
  final String label, value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) => SelectField(
        label: label,
        // 값은 'HH:MM'으로 두고 보이는 글자는 앱 시각 글자 하나('오후 9:05', 2026-11-19 규칙: 24시간 '21:05'로 보였다)
        value: value.isNotEmpty ? hmLabel(value) : null,
        placeholder: '시각 고르기',
        onPress: () async {
          final r = await showSheet<String>(context, title: label.replaceAll(RegExp(r' \(.+\)$'), ''), builder: (_) => _TimeBody(value: value));
          if (r != null && r != value) onChange(r);
        },
      );
}

class _TimeBody extends StatefulWidget {
  const _TimeBody({required this.value});
  final String value;

  @override
  State<_TimeBody> createState() => _TimeBodyState();
}

class _TimeBodyState extends State<_TimeBody> {
  late int _h, _m;

  @override
  void initState() {
    super.initState();
    final mt = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(widget.value);
    final now = DateTime.now();
    _h = mt == null ? now.hour : math.min(23, int.parse(mt[1]!));
    _m = mt == null ? now.minute : math.min(59, int.parse(mt[2]!));
  }

  @override
  Widget build(BuildContext context) {
    String p2(int n) => n.toString().padLeft(2, '0');
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: _wheelRow * _wheelVisible,
        child: Stack(children: [
          // 가운데 고른 줄(입력칸 색 띠)
          Positioned(
            left: 0,
            right: 0,
            top: _wheelRow * (_wheelVisible - 1) / 2,
            height: _wheelRow,
            child: DecoratedBox(decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(10))),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Wheel(count: 24, index: _h, unit: '시', onChange: (h) => setState(() => _h = h)),
            const SizedBox(width: Space.s),
            Text(':', style: AppType.section),
            const SizedBox(width: Space.s),
            _Wheel(count: 60, index: _m, unit: '분', onChange: (m) => setState(() => _m = m)),
          ]),
        ]),
      ),
      const SizedBox(height: Space.l),
      Btn(label: '확인', size: 'xlarge', onPress: () => Navigator.pop(context, '${p2(_h)}:${p2(_m)}')),
    ]);
  }
}

/// 걸리는 시간 고르기 시트(시간 0~5 · 분 5분 단위): 고른 분을 돌려준다(닫으면 null). 0분은 5분으로
Future<int?> showMinutesSheet(BuildContext context, {required String title, String? description, int initial = 45}) =>
    showSheet<int>(context, title: title, description: description, builder: (_) => _MinutesBody(initial: initial));

class _MinutesBody extends StatefulWidget {
  const _MinutesBody({required this.initial});
  final int initial;

  @override
  State<_MinutesBody> createState() => _MinutesBodyState();
}

class _MinutesBodyState extends State<_MinutesBody> {
  static const _maxH = 5;
  late int _h = math.min(_maxH, widget.initial ~/ 60), _m = ((widget.initial % 60) / 5).round().clamp(0, 11);

  int get _total => math.max(5, _h * 60 + _m * 5);

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: _wheelRow * _wheelVisible,
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              top: _wheelRow * (_wheelVisible - 1) / 2,
              height: _wheelRow,
              child: DecoratedBox(decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(10))),
            ),
            // 단위는 줄 글자 안에('1시간' · '45분'): 단위를 목록 밖에 따로 두면 숫자 폭에 따라 숫자–단위 사이가 열마다 달라지고 묶음이 가운데서 밀렸다(2026-11-16 사용자 '라인이랑 안 맞는')
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Wheel(count: _maxH + 1, index: _h, unit: '', width: 104, text: (i) => '$i시간', onChange: (h) => setState(() => _h = h)),
              const SizedBox(width: Space.l),
              _Wheel(count: 12, index: _m, unit: '', width: 104, text: (i) => '${i * 5}분', onChange: (m) => setState(() => _m = m)),
            ]),
          ]),
        ),
        const SizedBox(height: Space.l),
        Btn(label: '${minutesLabel(_total)}으로 정하기', size: 'xlarge', onPress: () => Navigator.pop(context, _total)),
      ]);
}

/// 분을 '45분' · '1시간' · '1시간 30분'으로(60분까지는 분으로: 목표 60분 칸과 같게)
String minutesLabel(num min) {
  final m = min.round();
  if (m <= 60) return '$m분';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h시간' : '$h시간 $r분';
}

// 줄 높이 = 누르는 자리 48(44였다, 2026-11-16 QA 영숙 F12)
const _wheelRow = Space.hit;
const _wheelVisible = 5;

/// 돌리는 목록 하나: 가운데 줄이 고른 값. 손을 떼면 가까운 줄에 멈춘다. 화면 읽기에서는 위아래로 쓸어 한 칸씩 바꾼다
class _Wheel extends StatefulWidget {
  const _Wheel({required this.count, required this.index, required this.unit, required this.onChange, this.text, this.width = 76});
  final int count, index;
  final String unit;
  final double width;
  final ValueChanged<int> onChange;

  /// 줄 글자(없으면 두 자리 번호)
  final String Function(int i)? text;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final _c = FixedExtentScrollController(initialItem: widget.index);
  late int _cur = widget.index;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _step(int k) {
    final i = (_cur + k).clamp(0, widget.count - 1);
    _c.animateToItem(i, duration: const Duration(milliseconds: 200), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        slider: true,
        label: '${widget.text?.call(_cur) ?? _cur}${widget.unit}',
        onIncrease: () => _step(1),
        onDecrease: () => _step(-1),
        child: SizedBox(
          width: widget.width,
          height: _wheelRow * _wheelVisible,
          child: ListWheelScrollView.useDelegate(
            controller: _c,
            itemExtent: _wheelRow,
            diameterRatio: 100, // 평평하게(지금 앱은 그냥 목록)
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) {
              setState(() => _cur = i);
              widget.onChange(i);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.count,
              builder: (_, i) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _step(i - _cur),
                child: Center(
                  child: Text(
                    widget.text?.call(i) ?? i.toString().padLeft(2, '0'),
                    // 고르지 않은 값도 읽히게 보조 글자색(옅은 회색은 흰 바탕에서 대비가 2:1이 안 됐다, 2026-11-16 QA 영숙 F18). 고른 값은 진한 굵은 글자 + 회색 띠
                    style: i == _cur ? AppType.wheel.strong.copyWith(color: AppColors.ink) : AppType.wheel,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

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
