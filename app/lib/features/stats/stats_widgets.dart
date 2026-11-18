// 기록 화면 부품: 달력(날마다 읽은 책 표지를 겹쳐), 막대 그래프, 작은 막대(시간대·길이·요일), 책 한 권 기록, 서재 책 표지·제목·저자.
// 지금 앱 features/stats/ReadingCalendar·ReadingChart·MiniBars·BookRecord와 ui/BookVisual LinkedCover를 옮긴 것
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/cover_url.dart';
import '../../domain/library.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'chart_data.dart';

// 표지 부품은 lib/ui/book_cover.dart(책장 시트 등이 이 파일에서 가져다 써서 다시 내보낸다)
export '../../ui/book_cover.dart';
import '../../ui/book_cover.dart';
import '../book/labels.dart' show dateShort;

final _small = AppType.micro;


// ---------- 달력 ----------
const _maxLayers = 4, _stepX = 4.0, _stepY = 2.0, _coverH = 46.0, _coverRatio = 1.42, _numH = 24.0;

class ReadingCalendar extends StatelessWidget {
  const ReadingCalendar({super.key, required this.lib, required this.y, required this.m, required this.days, required this.selected, required this.today, required this.onSelect});
  final Library lib;
  final int y, m;
  final Map<String, DayBooks> days;
  final String? selected;
  final String today;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: LayoutBuilder(builder: (context, c) {
          final cell = c.maxWidth / 7;
          final weeks = calendarWeeks(y, m);
          return Column(children: [
            Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.track, width: 0.5))),
              child: Row(children: [for (final d in weekdays) SizedBox(width: cell, child: Text(d, textAlign: TextAlign.center, style: _small))]),
            ),
            // 주 사이에만 선(맨 아래 선은 없다: 아래 구역 선과 겹쳐 두 줄로 보였다, 2026-11-17 사용자 댓글)
            for (final (wi, week) in weeks.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: wi == weeks.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 0.5))),
                child: Row(children: [
                  for (final day in week)
                    day == null
                        ? SizedBox(width: cell)
                        : _DayCell(lib: lib, day: day, row: days[day], cell: cell, selected: selected == day, today: today == day, onSelect: onSelect),
                ]),
              ),
          ]);
        }),
      );
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.lib, required this.day, required this.row, required this.cell, required this.selected, required this.today, required this.onSelect});
  final Library lib;
  final String day;
  final DayBooks? row;
  final double cell;
  final bool selected, today;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final n = int.parse(day.substring(8));
    final w = math.min((_coverH / _coverRatio).roundToDouble(), math.max(16.0, cell - 4));
    final side = (cell - w) / 2;
    final ids = (row?.books ?? const <String>[]).where((id) => lib.books.containsKey(id)).take(_maxLayers).toList();
    final titles = [for (final id in ids) bookTitle(lib, id)].whereType<String>().toList();
    final label = row != null
        ? '$n일, ${titles.isNotEmpty ? '${titles.first}${row!.books.length > 1 ? ' 외 ${row!.books.length - 1}권' : ''}, ' : ''}${formatDuration(row!.ms)}'
        : '$n일, 기록 없음';
    return Semantics(
      button: true,
      selected: selected,
      enabled: row != null,
      label: label,
      child: Pressable(
        onPress: row == null ? null : () => onSelect(day),
        child: SizedBox(
          width: cell,
          child: Column(children: [
            SizedBox(
              height: _numH,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(minWidth: _numH),
                  height: _numH,
                  decoration: BoxDecoration(color: selected ? AppColors.accent : null, borderRadius: BorderRadius.circular(_numH / 2)),
                  alignment: Alignment.center,
                  child: Text('$n',
                      style: _small.copyWith(
                        fontFamily: selected || today ? AppFonts.uiBold : AppFonts.ui,
                        color: selected ? AppColors.onAccent : today ? AppColors.ink : AppColors.inkSoft,
                      )),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: _coverH + (_maxLayers - 1) * _stepY,
              child: Stack(children: [
                // 뒤 책부터 그린다
                for (final (i, id) in ids.indexed.toList().reversed)
                  Positioned(
                    right: side + i * _stepX,
                    top: i * _stepY,
                    child: _Paper(lib: lib, id: id, w: w, h: _coverH),
                  ),
                if (ids.isEmpty && row != null) Positioned(right: side, top: 0, child: _Paper(w: w, h: _coverH)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 달력 칸 표지(흰 표지도 바탕과 갈리게 얇은 선 + 옅은 그림자)
class _Paper extends StatelessWidget {
  const _Paper({this.lib, this.id, required this.w, required this.h});
  final Library? lib;
  final String? id;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    final b = id == null ? null : lib!.books[id];
    final e = b == null ? null : lib!.editions[b.editionId];
    final color = (b?.bindingId != null ? lib!.bindings[b!.bindingId]?.spineColor : null);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2.5),
        border: Border.all(color: const Color(0x24191F28), width: 0.5),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), offset: Offset(0, 1), blurRadius: 2)],
      ),
      child: CoverImage(uris: [coverAtSize(e?.coverUri, 'M'), e?.coverUri], color: color != null ? hexColor(color) : AppColors.input, width: w, height: h),
    );
  }
}

// ---------- 막대 그래프 ----------
/// 그래프 높이 160(시안의 약 1.5배, 2026-11-17 사용자: 높낮이를 좀 더 높게), 위 여유 14(고른 값은 그래프 위 머리줄 StatHead가 보인다)
const _plotH = 160.0, _topH = 14.0, _axisW = 38.0, _labelH = 26.0;

class ReadingChart extends StatelessWidget {
  const ReadingChart({super.key, required this.bars, required this.selected, required this.unit, required this.onSelect});
  final List<Bar> bars;
  final String? selected;
  final String unit;
  final ValueChanged<String> onSelect;

  // 고른 막대 위 말풍선은 뺐다(늘 꺼져 있었다: 값은 그래프 위 머리줄, 2026-11-17 통계 시안)
  @override
  Widget build(BuildContext context) => SizedBox(
        height: _topH + _plotH + _labelH,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final max = bars.fold<num>(0, (a, b) => math.max(a, b.ms));
          final ticks = yTicks(max);
          double scale(num ms) => max > 0 ? ms / max * (_plotH - 6) : 0;
          final plotW = math.max(0.0, w - _axisW);
          final cell = bars.isEmpty ? 0.0 : plotW / bars.length;
          final barW = math.max(3.0, math.min(unit == '월' ? 14.0 : 7.0, cell * 0.6));
          double cx(int i) => _axisW + cell * (i + 0.5);
          final sel = bars.indexWhere((b) => b.key == selected && b.ms > 0);
          const base = _topH + _plotH;
          double barH(num ms) => math.max(barW, scale(ms));
          return Stack(clipBehavior: Clip.none, children: [
            CustomPaint(
              size: Size(w, base + 6),
              painter: _ChartPainter(bars: bars, ticks: [for (final t in ticks) base - scale(t * 60000)], w: w, base: base, cx: cx, barW: barW, barH: barH, sel: sel),
            ),
            for (final t in ticks) Positioned(left: 0, width: _axisW - 6, top: base - scale(t * 60000) - 9, child: Text(tickLabel(t), style: _small)),
            Positioned(left: 0, width: _axisW - 6, top: base - 9, child: Text('0', style: _small)),
            for (final n in xLabels(bars.length))
              Positioned(left: cx(n - 1) - 15, width: 30, top: base + 6, child: Text('$n', textAlign: TextAlign.center, style: _small)),
            for (var i = 0; i < bars.length; i++)
              Positioned(
                left: _axisW + cell * i,
                width: cell,
                top: _topH,
                height: _plotH + _labelH,
                child: Semantics(
                  button: bars[i].ms > 0,
                  selected: i == sel,
                  label: '${bars[i].label}$unit ${formatDuration(bars[i].ms)}',
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: bars[i].ms > 0 ? () => onSelect(bars[i].key) : null),
                ),
              ),
          ]);
        }),
      );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.bars, required this.ticks, required this.w, required this.base, required this.cx, required this.barW, required this.barH, required this.sel});
  final List<Bar> bars;
  final List<double> ticks;
  final double w, base, barW;
  final double Function(int) cx;
  final double Function(num) barH;
  final int sel;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (final y in ticks) {
      for (var x = _axisW; x < w; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, w), y), line);
      }
    }
    canvas.drawLine(Offset(_axisW, base), Offset(w, base), line);
    for (var i = 0; i < bars.length; i++) {
      if (bars[i].ms <= 0) continue;
      final h = barH(bars[i].ms);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx(i) - barW / 2, base - h, barW, h), Radius.circular(barW / 2)),
        Paint()..color = i == sel ? AppColors.accent : AppColors.track,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

// ---------- 작은 막대 ----------
class MiniBar {
  const MiniBar(this.key, this.name, this.value);
  final String key;
  final String name;
  final num value;
}

/// 작은 막대 그래프 높이 96(2026-11-17 사용자: 높낮이를 더 높게)
const _miniPlotH = 96.0, _miniLabelH = 24.0, _miniBarMax = 52.0;

/// 통계 한 칸 머리줄(2026-11-17 시안): 왼쪽 제목, 오른쪽 가장 많은(또는 고른) 것 굵게와 그 값 회색 한 줄 아래
class StatHead extends StatelessWidget {
  const StatHead({super.key, required this.title, this.top, this.value});
  final String title;
  final String? top, value;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: AppType.section))),
        if (top != null)
          Semantics(
            liveRegion: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(top!, style: AppType.section.tnum),
              if (value != null) Text(value!, style: AppType.caption.tnum),
            ]),
          ),
      ]);
}

class MiniBars extends StatefulWidget {
  const MiniBars({super.key, required this.title, required this.bars, required this.labels, required this.emptyText, required this.valueText, this.extra, this.labelLines = 1});
  final String title;
  final List<MiniBar> bars;
  final List<(int, String)> labels;
  final String emptyText;
  final String Function(MiniBar bar) valueText;

  /// 머리줄과 그래프 사이(한 번에 읽은 시간의 평균·가장 오래 카드)
  final Widget? extra;

  /// 아래 이름 줄 수(길이 칸은 '30분~1시간'처럼 두 줄)
  final int labelLines;

  @override
  State<MiniBars> createState() => _MiniBarsState();
}

class _MiniBarsState extends State<MiniBars> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final bars = widget.bars;
    final max = bars.fold<num>(0, (a, b) => math.max(a, b.value));
    final peak = max > 0 ? bars.firstWhere((b) => b.value == max) : null;
    final chosen = bars.where((b) => b.key == _picked && b.value > 0).firstOrNull;
    final shown = chosen ?? peak;
    const plotH = _miniPlotH;
    final labelH = _miniLabelH + (widget.labelLines - 1) * 18.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StatHead(title: widget.title, top: shown?.name, value: shown == null ? null : widget.valueText(shown)),
      if (shown == null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(widget.emptyText, style: AppType.sub)),
      if (widget.extra != null) Padding(padding: const EdgeInsets.only(top: Space.l), child: widget.extra),
      const SizedBox(height: Space.l),
      SizedBox(
        height: plotH + labelH,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final cell = bars.isEmpty ? 0.0 : w / bars.length;
          // 칸이 좁은 시간대(24칸)는 가는 막대, 넓은 길이·요일 칸은 넓은 막대
          final barW = math.max(3.0, math.min(_miniBarMax, cell * (bars.length > 12 ? 0.62 : 0.7)));
          double barH(num v) => math.max(math.min(barW, 10.0), v / max * (plotH - 6));
          return Stack(clipBehavior: Clip.none, children: [
            CustomPaint(
              size: Size(w, plotH + 2),
              painter: _MiniPainter(bars: bars, cell: cell, barW: barW, barH: barH, shownKey: shown?.key, plotH: plotH),
            ),
            for (final (at, text) in widget.labels)
              Positioned(
                left: cell * (at + 0.5) - math.max(24.0, cell / 2),
                width: math.max(48.0, cell),
                top: plotH + 6,
                child: Text(text, maxLines: widget.labelLines, textAlign: TextAlign.center, style: _small),
              ),
            for (var i = 0; i < bars.length; i++)
              Positioned(
                left: cell * i,
                width: cell,
                top: 0,
                height: plotH + labelH,
                child: Semantics(
                  button: bars[i].value > 0,
                  selected: shown != null && bars[i].key == shown.key,
                  label: '${bars[i].name} ${widget.valueText(bars[i])}',
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: bars[i].value > 0 ? () => setState(() => _picked = bars[i].key) : null),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }
}

class _MiniPainter extends CustomPainter {
  _MiniPainter({required this.bars, required this.cell, required this.barW, required this.barH, required this.shownKey, required this.plotH});
  final List<MiniBar> bars;
  final double cell, barW, plotH;
  final double Function(num) barH;
  final String? shownKey;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, plotH), Offset(size.width, plotH), Paint()
      ..color = AppColors.line
      ..strokeWidth = 1);
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      if (b.value <= 0) continue;
      final bh = barH(b.value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cell * (i + 0.5) - barW / 2, plotH - bh, barW, bh), Radius.circular(math.min(barW / 2, 8))),
        Paint()..color = b.key == shownKey ? AppColors.accent : AppColors.track,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) => true;
}

// ---------- 책 한 권 기록 ----------
/// 이름 + 숫자 칸(작은 회색 이름 위, 굵은 숫자 19 아래): 통계 요약 · 평균 카드 · 책 한 권 기록이 모두 이것
/// (2026-11-19 공통 규칙: 같은 '읽은 날'이 24와 19로 달랐고, 같은 칸을 세 벌로 만들었다)
class StatNumber extends StatelessWidget {
  const StatNumber({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$label $value',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.caption),
            const SizedBox(height: Space.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              // 숫자 값 역할(figure 24: 통계 읽은 날 · 독서 횟수). 분석 위 요약이 쓰던 크기로 하나(2026-11-19 공통 규칙)
              child: Text(value, maxLines: 1, style: AppType.figure),
            ),
          ]),
        ),
      );
}

class BookRecordView extends StatelessWidget {
  const BookRecordView({super.key, required this.lib, required this.id});
  final Library lib;
  final String id;

  @override
  Widget build(BuildContext context) {
    final r = bookRecord(lib, id);
    String dot(String d) => dateShort(d);
    final span = r.firstDay != null ? (r.firstDay == r.lastDay ? dot(r.firstDay!) : '${dot(r.firstDay!)} ~ ${dot(r.lastDay!)}') : '아직 기록이 없어요';
    // 책 줄은 앱 공통 BookRow(작게 40, 2026-11-19 공통 규칙). 위아래 12는 BookRow가 가진다
    final w = BookRow.coverWidth(BookRowSize.small);
    return Column(children: [
      BookRow(cover: LinkedCover(lib: lib, id: id, width: w), title: bookTitle(lib, id) ?? '', meta: span),
      const SizedBox(height: Space.s),
      Row(children: [
        StatNumber(label: '총 독서 시간', value: formatDuration(r.readMs)),
        const SizedBox(width: Space.m),
        StatNumber(label: '읽은 날', value: '${r.days}일'),
        const SizedBox(width: Space.m),
        StatNumber(label: '완독', value: '${r.finished}회'),
      ]),
      if (r.pagesPerMin != null) ...[
        const SizedBox(height: Space.l),
        Row(children: [
          StatNumber(label: '읽는 속도', value: '분당 ${r.pagesPerMin!.toStringAsFixed(1)}쪽'),
          const SizedBox(width: Space.m),
          if (r.remainingMs != null) StatNumber(label: '다 읽기까지', value: '약 ${formatDuration(r.remainingMs!)}') else const Spacer(),
          const SizedBox(width: Space.m),
          const Spacer(),
        ]),
      ],
      const SectionBand(),
    ]);
  }
}
