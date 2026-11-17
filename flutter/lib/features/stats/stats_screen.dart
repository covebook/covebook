// 통계 탭(2026-11-16 메뉴 구조 개편 전 하단 '기록'): 캘린더(날마다 읽은 책) · 분석(기간 독서 시간·시간대·한 번 길이·요일·많이 읽은 책·완독·갈피).
// 지금 앱 features/stats/StatsScreen.tsx를 옮긴 것. 안쪽 틀은 그대로, 화면 제목·메뉴 이름만 바꿨다.
// 책을 고르면 달력·그래프·숫자가 그 책만으로 바뀐다. 오늘이 든 달(해) 다음으로는 가지 않는다
library;

import 'package:flutter/material.dart';

import '../../domain/library.dart' hide today;
import '../../domain/library.dart' as lib_d show today;
import '../../store/library_model.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'session_edit_screen.dart' show openSessionEdit;
import 'chart_data.dart';
import 'stats_widgets.dart';

const _coverW = 52.0;
String _shortMs(num ms) => ms < 60000 ? formatDurationPrecise(ms) : formatDuration(ms);

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.tab = true, this.initialBook});

  /// 하단 '통계' 탭(뒤로 없음, 탭 바만큼 아래를 비운다). 아니면 책·독서 끝에서 여는 '내 기록'
  final bool tab;
  final String? initialBook;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

/// 많이 읽은 시간대 이름: 새벽·오전·낮·오후·저녁·밤(시안 '밤 11시')
String _dayPart(int h) => switch (h) {
      0 => '밤 12시',
      < 6 => '새벽 $h시',
      < 12 => '오전 $h시',
      12 => '낮 12시',
      < 18 => '오후 ${h - 12}시',
      < 21 => '저녁 ${h - 12}시',
      _ => '밤 ${h - 12}시',
    };

/// 통계 칸 사이 간격: 앱 공통 구역 간격(Space.block)
const _gap = Space.block;

class _StatsScreenState extends State<StatsScreen> {
  final _model = LibraryModel.instance;
  Library? get _lib => _model.loaded ? _model.lib : null;
  String _view = 'calendar';
  bool _yearly = false;
  late int _y;
  late int _m;
  String? _book;
  String? _picked;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _y = now.year;
    _m = now.month;
    _book = widget.initialBook;
    _model.addListener(_changed);
    _model.load();
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _monthly => _view == 'calendar' || !_yearly;

  void _shift(int k) => setState(() {
        _picked = null;
        if (!_monthly) {
          _y += k;
          return;
        }
        var mm = _m + k, yy = _y;
        if (mm < 1) {
          mm = 12;
          yy--;
        } else if (mm > 12) {
          mm = 1;
          yy++;
        }
        _m = mm;
        _y = yy;
      });

  @override
  Widget build(BuildContext context) {
    final lib = _lib;
    if (lib == null) return Screen(back: !widget.tab, title: widget.tab ? '통계' : '내 기록', children: const [Loading()]);
    final now = DateTime.now();
    final monthly = _monthly;
    final book = _book != null && lib.books.containsKey(_book) ? _book : null;
    final period = monthly ? monthPeriod(_y, _m) : yearPeriod(_y);
    final st0 = periodStats(lib, period, book);
    final sessions = st0.sessions;
    final bars = monthly ? monthBars(sessions, _y, _m) : yearBars(sessions, _y);
    final days = booksByDay(sessions);
    final lastKey = bars.reversed.where((b) => b.ms > 0).firstOrNull?.key;
    final selected = _picked != null && bars.any((b) => b.key == _picked && b.ms > 0) ? _picked : lastKey;
    final selMs = bars.where((b) => b.key == selected).firstOrNull?.ms ?? 0;
    final activeDays = sessions.map(sessionDay).toSet().length;
    final selSessions = [for (final s in sessions) if (selected != null && sessionDay(s).startsWith(selected)) s];
    String? title(String? id) => id == null ? null : lib.editions[lib.books[id]?.editionId]?.title;
    final thisPeriod = monthly ? _y == now.year && _m == now.month : _y == now.year;
    final periodName = thisPeriod ? (monthly ? '이번 달' : '올해') : monthly ? '$_m월' : '$_y년';
    final today = lib_d.today(now);
    Widget cover(String? id) => id != null && lib.books.containsKey(id)
        ? LinkedCover(lib: lib, id: id, width: _coverW)
        : const RealCover(title: '책 없음', color: '#F2F4F6', width: _coverW, ratio: 0.7);
    final rowValue = AppType.section.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    Widget row({required String? id, required String label, required Widget middle, required Widget right, VoidCallback? onPress}) => Semantics(
          button: onPress != null,
          label: label,
          child: Pressable(
            onPress: onPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.m),
              child: Row(children: [
                SizedBox(width: _coverW, child: Center(child: cover(id))),
                const SizedBox(width: Space.l),
                Expanded(child: middle),
                const SizedBox(width: Space.l),
                right,
              ]),
            ),
          ),
        );

    final children = <Widget>[
      Padding(
        padding: EdgeInsets.only(top: widget.tab ? Space.s : 0),
        child: Segmented<String>(
          items: const [('calendar', '캘린더'), ('records', '분석')],
          value: _view,
          onChange: (v) => setState(() {
            _view = v;
            _picked = null;
          }),
        ),
      ),
      // 책 선택은 제목 줄 오른쪽(두 칸 모두 같은 자리: 달력·그래프·숫자가 함께 바뀐다, 2026-11-17 통계 시안)
      if (_view == 'records' && book != null) Padding(padding: const EdgeInsets.only(top: Space.m), child: BookRecordView(lib: lib, id: book)),
      // 달 넘기기는 왼쪽에 '‹ 2026년 11월 ›', 오른쪽에 '월별 ⌄'(분석만)
      Padding(
        padding: const EdgeInsets.only(top: Space.xs, bottom: Space.s),
        child: Row(children: [
          Transform.translate(
            offset: const Offset(-12, 0),
            child: IconBtn(label: monthly ? '이전 달' : '이전 해', onPress: () => _shift(-1), child: const LucideIcon('ChevronLeft')),
          ),
          Semantics(
            header: true,
            child: Text(monthly ? '$_y년 $_m월' : '$_y년', style: AppType.heading.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 2),
          IconBtn(
            label: monthly ? '다음 달' : '다음 해',
            disabled: monthly ? _y * 12 + _m >= now.year * 12 + now.month : _y >= now.year,
            onPress: () => _shift(1),
            child: const LucideIcon('ChevronRight'),
          ),
          const Spacer(),
          if (_view == 'records') FilterButton(plain: true, label: _yearly ? '연도별' : '월별', onPress: _periodSheet),
        ]),
      ),
      if (_view == 'calendar')
        ReadingCalendar(lib: lib, y: _y, m: _m, days: days, selected: selected, today: today, onSelect: (d) => setState(() => _picked = d))
      else ...[
        ..._summary(st0, sessions, activeDays, periodName),
        const SizedBox(height: _gap),
        StatHead(
          title: monthly ? '날짜별 독서' : '월별 독서',
          top: selected != null ? formatDuration(selMs) : null,
          value: selected != null ? (monthly ? '${int.parse(selected.substring(8))}일' : '${int.parse(selected.substring(5))}월') : null,
        ),
        const SizedBox(height: Space.s),
        // 그래프 높이는 시안의 약 1.5배(2026-11-17 사용자: 높낮이를 좀 더 높게)
        ReadingChart(bars: bars, selected: selected, unit: monthly ? '일' : '월', tip: false, plotH: 160, onSelect: (k) => setState(() => _picked = k)),
      ],
      if (_view == 'records') ..._records(lib, st0, sessions, activeDays, periodName, title, row, rowValue, period, book),
      if (_view == 'calendar')
        if (selected != null) ...[
          // 선 없이 구역 간격만(달력 아래 선과 두 줄로 보였다, 2026-11-17 사용자 댓글)
          const SizedBox(height: Space.xl),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Expanded(child: Semantics(header: true, child: Text(monthly ? dayTitle(selected) : '$_y년 ${int.parse(selected.substring(5))}월', style: AppType.section))),
                  Text(formatDuration(selMs), style: AppType.sub),
                ]),
              ),
              for (final s in selSessions)
                row(
                  id: s.myBookId,
                  onPress: () => openSessionEdit(context, s.id),
                  label: '${title(s.myBookId) ?? '책 없음'}, ${timeRange(s.startedAt, s.endedAt)}, ${_shortMs(s.durationMs)}',
                  middle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title(s.myBookId) ?? '책 없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(timeRange(s.startedAt, s.endedAt), maxLines: 1, style: AppType.sub)),
                  ]),
                  right: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_shortMs(s.durationMs), style: rowValue),
                    if (hasPause(s)) Text('실제 독서', style: AppType.caption),
                  ]),
                ),
            ]),
          ),
        ] else
          Empty(
            title: '$periodName에는 독서 기록이 없어요',
            body: book != null && title(book) != null ? '${title(book)} 기준이에요.' : thisPeriod ? '책을 읽으면 그날이 달력에 칠해져요.' : null,
          ),
    ];
    return Screen(
      back: !widget.tab,
      title: widget.tab ? '통계' : '내 기록',
      right: Padding(
        padding: const EdgeInsets.only(top: 10, right: 10),
        child: FilterButton(plain: true, label: title(book) ?? '모든 책', active: book != null, onPress: () => _pickBook(lib)),
      ),
      // 떠 있는 하단바 아래까지 내용이 내려가게
      bottomPad: widget.tab ? TabBarStyle.contentPad - Space.section : 0,
      children: children,
    );
  }

  List<Widget> _records(Library lib, PeriodStats st0, List<Session> sessions, int activeDays, String periodName, String? Function(String?) title,
      Widget Function({required String? id, required String label, required Widget middle, required Widget right, VoidCallback? onPress}) row, TextStyle rowValue, Period period, String? book) {
    final summary = sessionSummary(sessions);
    final hours = hourBars(sessions), lengths = lengthBins(sessions), wd = weekdayBars(sessions);
    final top = topBooks(sessions, 3).where((r) => lib.books.containsKey(r.id)).toList();
    const empty = '이 기간에는 기록이 없어요.';
    Widget pair(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppType.caption),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: AppType.section.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]);
    // 한 번에 읽은 시간 위 카드: 평균 | 가장 오래(테두리 상자, 가운데 세로 선)
    final lengthCard = Semantics(
      container: true,
      label: '한 번에 평균 ${summary.count > 0 ? _shortMs(summary.averageMs) : '없음'}, 가장 오래 읽은 시간 ${summary.count > 0 ? _shortMs(summary.longestMs) : '없음'}',
      excludeSemantics: true,
      child: OutlineBox(
        child: IntrinsicHeight(
          child: Row(children: [
            Expanded(child: pair('한 번에 평균', summary.count > 0 ? _shortMs(summary.averageMs) : '-')),
            Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), color: AppColors.line),
            Expanded(child: pair('가장 오래 읽은 시간', summary.count > 0 ? _shortMs(summary.longestMs) : '-')),
          ]),
        ),
      ),
    );
    return [
      const SizedBox(height: _gap),
      MiniBars(
        title: '많이 읽은 시간대',
        bars: [for (var h = 0; h < 24; h++) MiniBar('$h', _dayPart(h), hours[h])],
        labels: [for (final h in const [0, 6, 12, 18, 23]) (h, '$h시')],
        emptyText: empty,
        valueText: (b) => formatDuration(b.value),
      ),
      const SizedBox(height: _gap),
      MiniBars(
        title: '한 번에 읽은 시간',
        bars: [for (var i = 0; i < lengths.length; i++) MiniBar(lengthBinsDef[i].key, lengthBinsDef[i].name, lengths[i])],
        labels: [for (var i = 0; i < lengthBinsDef.length; i++) (i, lengthBinsDef[i].name)],
        labelLines: 2,
        extra: lengthCard,
        emptyText: empty,
        valueText: (b) => '${b.value}회',
      ),
      const SizedBox(height: _gap),
      MiniBars(
        title: '많이 읽은 요일',
        bars: [for (var i = 0; i < 7; i++) MiniBar(weekdays[i], '${weekdays[i]}요일', wd[i])],
        labels: [for (var i = 0; i < 7; i++) (i, weekdays[i])],
        emptyText: empty,
        valueText: (b) => formatDuration(b.value),
      ),
      if (top.isNotEmpty) ...[
        const SizedBox(height: _gap),
        Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Semantics(header: true, child: Text('많이 읽은 책', style: AppType.section))),
        for (final r in top)
          row(
            id: r.id,
            label: '${title(r.id)}, ${formatDuration(r.ms)}',
            middle: Text(title(r.id) ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
            right: Text(_shortMs(r.ms), style: rowValue),
          ),
      ],
      const SizedBox(height: _gap - Space.l),
      ListGroup(children: [
        // 넣은 책·지금 서재(모든 책일 때만): '전체 책'의 권수와 맞춰 볼 수 있게
        if (book == null) ListItem(label: '넣은 책', value: '${bookCounts(lib, period).added}권'),
        ListItem(
          label: '완독',
          sub: st0.completedRounds > st0.completedCount || st0.rereads > 0 ? '완독 ${st0.completedRounds}회 · 재독 ${st0.rereads}회' : null,
          value: '${st0.completedCount}권',
        ),
        ListItem(label: '남긴 갈피', value: '${st0.bookmarkCount}개'),
        if (book == null)
          () {
            final c = bookCounts(lib, period);
            return ListItem(label: '지금 서재', sub: c.hidden > 0 ? '숨긴 책 ${c.hidden}권은 빼고' : null, value: '${c.shelf}권');
          }(),
      ]),
    ];
  }

  // 큰 숫자: '이번 달 읽은 시간'과 '15시간 45분'(숫자 크게·단위 작게), 그 아래 읽은 날 · 독서 횟수(2026-11-17 시안)
  List<Widget> _summary(PeriodStats st0, List<Session> sessions, int activeDays, String periodName) {
    final ms = st0.readMs;
    final h = ms ~/ 3600000, m = (ms % 3600000) ~/ 60000, s = (ms % 60000) ~/ 1000;
    final parts = <(String, String)>[
      if (h > 0) ('$h', '시간'),
      if (m > 0 || (h == 0 && ms >= 60000)) ('$m', '분'),
      if (ms < 60000) ('$s', '초'),
    ];
    final big = AppType.display;
    final unit = AppType.displayUnit;
    Widget stat(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.caption),
            const SizedBox(height: 4),
            Text(value, style: AppType.figure),
          ]),
        );
    return [
      Semantics(
        container: true,
        label: '$periodName 읽은 시간 ${formatDuration(ms)}, 읽은 날 $activeDays일, 독서 ${sessions.length}회',
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$periodName 읽은 시간', style: AppType.sub),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              for (final (i, (n, u)) in parts.indexed) ...[
                if (i > 0) const TextSpan(text: '  '),
                TextSpan(text: n, style: big),
                TextSpan(text: ' $u', style: unit),
              ],
            ])),
          ),
          const SizedBox(height: Space.l),
          Row(children: [stat('읽은 날', '$activeDays일'), stat('독서 횟수', '${sessions.length}회')]),
        ]),
      ),
    ];
  }

  void _periodSheet() => showSheet<void>(
        context,
        title: '기간',
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (y, label) in const [(false, '월별'), (true, '연도별')])
            FilterOption(
              label: label,
              selected: _yearly == y,
              onPress: () {
                Navigator.pop(ctx);
                setState(() {
                  _yearly = y;
                  _picked = null;
                });
              },
            ),
        ]),
      );

  Future<void> _pickBook(Library lib) async {
    final withSessions = <String>[];
    for (final s in lib.sessions.values) {
      final id = s.myBookId;
      if (id != null && lib.books.containsKey(id) && !withSessions.contains(id)) withSessions.add(id);
    }
    String? title(String id) => lib.editions[lib.books[id]?.editionId]?.title;
    Widget pick(String? id, String label, {Widget? lead}) => Semantics(
          button: true,
          selected: _book == id,
          label: label,
          child: Pressable(
            onPress: () {
              setState(() {
                _book = id;
                _picked = null;
              });
              Navigator.pop(context);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Row(children: [
                if (lead != null) ...[SizedBox(width: 36, child: lead), const SizedBox(width: Space.m)],
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row)),
                const SizedBox(width: Space.m),
                RadioMark(on: _book == id),
              ]),
            ),
          ),
        );
    await showSheet<void>(
      context,
      title: '책 선택',
      scroll: true,
      builder: (_) => Column(children: [
        pick(null, '모든 책'),
        for (final id in withSessions) pick(id, title(id) ?? '', lead: LinkedCover(lib: lib, id: id, width: 36)),
      ]),
    );
  }
}
