// 통계 탭(2026-11-16 메뉴 구조 개편 전 하단 '기록'): 캘린더(날마다 읽은 책) · 분석(기간 독서 시간·시간대·한 번 길이·요일·많이 읽은 책·완독·갈피).
// 지금 앱 features/stats/StatsScreen.tsx를 옮긴 것. 안쪽 틀은 그대로, 화면 제목·메뉴 이름만 바꿨다.
// 책을 고르면 달력·그래프·숫자가 그 책만으로 바뀐다. 오늘이 든 달(해) 다음으로는 가지 않는다
// 2026-11-19 공통 규칙: 한 책으로 연 화면 이름 '독서 기록'('내 기록'은 책 정보 안 칸 이름과 겹쳤다), 책 고르기는 앱 공통 시트(book_picker),
// 책 줄은 누르면 책 정보, 기록 줄 읽은 시간은 책 정보 독서 기록과 같은 recordDuration, 큰 숫자는 formatDuration('0분')
// 2026-11-20 토스 공식+(사용자 비교 댓글): 회색 바탕 + 좌우 끝까지 붙인 흰 띠(Band, 이 화면만), 맨 위 줄 '통계 · 모든 책' 아래
// 가운데 '‹ 2026년 11월 ›' → 캘린더|분석 순서, 기간 고르기(월별 · 연도별)는 뺐다(늘 한 달), 분석 맨 위 숫자 셋(읽은 시간 · 읽은 날 · 독서 횟수) 한 줄
// 2026-11-24 사용자 '모든 책 선택은 저 사이로 추가해줘': 통계 탭도 책 고르기를 맨 위 줄 오른쪽 '모든 책 ⌄' 대신 한 책으로 연 독서 기록과 같은 테두리 칸으로
// (캘린더는 달력과 그날 기록 머리 사이, 분석은 달 바로 아래). 고르면 칸에 표지 · 책 이름(검정) · 저자(작은 회색)
library;

import 'package:flutter/material.dart';

import '../../app/app_nav.dart' show AppNav;
import '../../domain/library.dart';
import '../../services/qa_probe.dart';
import '../../store/library_model.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/book_screen.dart' show openBook;
import '../bookmark/book_picker.dart' show pickBook;
import 'chart_data.dart';
import 'session_edit_screen.dart' show openSessionEdit, openSessionAdd;
import 'stats_widgets.dart';

/// 책 줄 오른쪽 읽은 시간: 책 정보 › 내 기록의 독서 기록 줄과 같은 역할(recordDuration 15 보통, 숫자 폭 고정. 굵은 rowStrong이었다).
/// 쓸 때마다 읽는다(모듈 final은 화소 맞춤 배율을 놓친다)
TextStyle get _rowValue => AppType.recordDuration;

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.tab = true, this.initialBook});

  /// 하단 '통계' 탭(뒤로 없음, 탭 바만큼 아래를 비운다). 아니면 책 정보 · 읽기 목록에서 한 책으로 여는 '독서 기록'
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

class _StatsScreenState extends State<StatsScreen> {
  final _model = LibraryModel.instance;
  Library? get _lib => _model.loaded ? _model.lib : null;
  String _view = 'calendar';
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
    if (widget.tab) {
      AppNav.instance.addListener(_navDay);
      _navDay();
    }
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    if (widget.tab) AppNav.instance.removeListener(_navDay);
    super.dispose();
  }

  /// 독서를 끝낸 알림의 '달력에서 보기'(app_nav goCalendar): 캘린더 · 모든 책 · 그달 · 그날
  void _navDay() {
    final day = AppNav.instance.calendarDay;
    if (day == null || !mounted) return;
    AppNav.instance.calendarDay = null;
    final p = day.split('-');
    setState(() {
      _view = 'calendar';
      _book = null;
      _y = int.parse(p[0]);
      _m = int.parse(p[1]);
      _picked = day;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _shift(int k) => setState(() {
        _picked = null;
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
  Widget build(BuildContext context) => qaProbe('stats', _qaBuild(context));

  Widget _qaBuild(BuildContext context) {
    final lib = _lib;
    if (lib == null) return Screen(back: !widget.tab, title: widget.tab ? '통계' : '독서 기록', hideTitle: widget.tab, children: const [Loading()]);
    final now = DateTime.now();
    final book = _book != null && lib.books.containsKey(_book) ? _book : null;
    final period = monthPeriod(_y, _m);
    final st0 = periodStats(lib, period, book);
    final sessions = st0.sessions;
    final bars = monthBars(sessions, _y, _m);
    final days = booksByDay(sessions);
    final lastKey = bars.reversed.where((b) => b.ms > 0).firstOrNull?.key;
    // 고른 날: 캘린더는 기록 없는 날도 고를 수 있다(그날 '독서 기록 추가', 2026-11-23). 분석 그래프는 기록 있는 날만
    final selected = _picked != null && bars.any((b) => b.key == _picked && (b.ms > 0 || _view == 'calendar')) ? _picked : lastKey;
    final selMs = bars.where((b) => b.key == selected).firstOrNull?.ms ?? 0;
    final activeDays = sessions.map(sessionDay).toSet().length;
    final thisPeriod = _y == now.year && _m == now.month;
    final periodName = thisPeriod ? '이번 달' : '$_m월';
    final todayDay = today(now);
    final bookName = bookTitle(lib, book);

    // 책 고르는 칸: 폭 가득 '표지 + 책 이름  저자'(누르면 책 고르기 시트, 2026-11-21 사용자 '좌우 꽉 찬 썸네일이랑 이름 넣는 박스').
    // 자리는 맨 위가 아니라 캘린더는 그날 기록 머리('11월 18일 목요일') 바로 위, 분석은 달('2026년 11월') 바로 아래(같은 날 사용자).
    // 통계 탭도 같은 칸(2026-11-24 사용자: 위 줄 오른쪽 '모든 책 ⌄'였다)
    Widget bookBox({double top = 0, double bottom = Space.l}) => Padding(
          padding: EdgeInsets.only(top: top),
          child: SelectField(
            label: '책',
            showLabel: false,
            bottom: bottom,
            leading: book != null ? IgnorePointer(child: LinkedCover(lib: lib, id: book, width: CoverSize.row)) : null,
            value: bookName ?? '모든 책',
            sub: book != null && bookAuthor(lib, book).isNotEmpty ? bookAuthor(lib, book) : null,
            placeholder: '모든 책',
            onPress: () => _pickBook(lib),
            outlined: true,
          ),
        );

    final children = <Widget>[
      // 캘린더|분석 → 그 아래 가운데 달 넘기기. 맨 위(제목 · 전환 칸 · 달)는 흰 바탕, 회색은 아래 띠 사이만
      // (2026-11-20 사용자 '맨 위쪽 배경 회색 넣지 말고 전부 흰색, 날짜랑 버튼 위치 바꿔')
      Segmented<String>(
        items: const [('calendar', '캘린더'), ('records', '분석')],
        value: _view,
        onChange: (v) => setState(() {
          _view = v;
          _picked = null;
        }),
      ),
      _periodBar(now),
      // 분석: 달 바로 아래 책 칸. 날짜 바로 밑에는 회색 띠를 두지 않는다(2026-11-20 사용자 '이 날짜 밑에는 회색선 없애')
      if (_view == 'records') bookBox(top: Space.s, bottom: 0),
      if (_view == 'calendar') ...[
        // 캘린더는 회색 띠 · 흰 상자 없이 흰 바탕 그대로(2026-11-20 사용자 '캘린더 쪽은 회색선 넣어서 박스 모양 안 만들어도', '분석 쪽만 그렇게').
        // 달 아래 여백은 달 위 여백과 같게(전환 칸 → 달 Space.s, 달 → 달력 Space.s, 2026-11-20 사용자 '년도랑 월 위아래 여백 맞춰')
        const SizedBox(height: Space.s),
        ReadingCalendar(lib: lib, y: _y, m: _m, days: days, selected: selected, today: todayDay, onSelect: (d) => setState(() => _picked = d)),
        // 캘린더: 그날 기록 머리 바로 위 책 칸. 위아래 16(2026-11-24 사용자 '여기 간격 좀 줄이는 게': 28 · 28이었다.
        // 달력 마지막 주는 표지 자리 52를 늘 비워 두어 표지가 없으면 그만큼 더 떠 보인다)
        const SizedBox(height: Space.l),
        bookBox(bottom: Space.l),
        if (selected != null)
          ..._dayRecords(lib, selected, selMs, [for (final s in sessions) if (sessionDay(s).startsWith(selected)) s], book)
        else
          Empty(
            title: '$periodName에는 독서 기록이 없어요',
            // 책 이름은 ‘…’로 감싼다(공통 규칙 9장)
            body: bookName != null ? '‘$bookName’ 기준이에요.' : thisPeriod ? '책을 읽으면 그날이 달력에 칠해져요.' : null,
          ),
      ] else ...[
        // 달 숫자는 늘 달 · 책 칸 바로 아래(달 고르기와 붙어 있어야 그 달 숫자로 읽힌다). 책 한 권이면 '이 책 전체'는 맨 아래 따로
        // (2026-11-21 사용자 '이건 왜 위아래로 2개가 있는 거야': '이 책 전체'가 달과 달 숫자 사이에 끼어 같은 숫자 두 줄로 보였다)
        Band(top: false, children: [_summary(st0, sessions, activeDays, periodName)]),
        Band(children: [
          StatHead(
            title: '날짜별 독서',
            top: selected != null ? formatDuration(selMs) : null,
            value: selected != null ? '${int.parse(selected.substring(8))}일' : null,
          ),
          const SizedBox(height: Space.s),
          ReadingChart(bars: bars, selected: selected, unit: '일', onSelect: (k) => setState(() => _picked = k)),
        ]),
        ..._records(lib, st0, sessions, period, book),
        if (book != null) Band(children: [BookRecordView(lib: lib, id: book)]),
      ],
    ];
    return Screen(
      back: !widget.tab,
      title: widget.tab ? '통계' : '독서 기록',
      // 통계 탭은 왼쪽 위 제목 없이 캘린더 | 분석이 맨 위(하단바에 이름, 2026-11-24 사용자 6단계). 책 고르기는 달력 아래 칸(같은 날 사용자)
      hideTitle: widget.tab,
      // 떠 있는 하단바 아래까지 내용이 내려가게
      bottomPad: widget.tab ? TabBarStyle.contentPad - Space.section : 0,
      // 바탕은 흰색. 띠 사이 회색은 띠(Band)가 위에 깐다
      children: children,
    );
  }

  /// 달 넘기기: 가운데 '‹ 2026년 11월 ›'(날짜 고르기 시트 머리와 같은 모양, 2026-11-20 사용자 '날짜는 중앙'). 기간 고르기는 뺐다(늘 한 달).
  /// 전환 칸 바로 아래(위 Space.s), 아래는 첫 띠의 회색 칸
  Widget _periodBar(DateTime now) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconBtn(label: '이전 달', onPress: () => _shift(-1), child: const LucideIcon('ChevronLeft', color: AppColors.icon)),
          Semantics(header: true, child: Text(monthTitle(_y, _m), style: AppType.heading.tnum)),
          IconBtn(label: '다음 달', disabled: _y * 12 + _m >= now.year * 12 + now.month, onPress: () => _shift(1), child: const LucideIcon('ChevronRight', color: AppColors.icon)),
        ]),
      );

  /// 책 줄 표지(작게 40): 책 없이 읽은 기록은 앱 공통 '책 없이 읽기' 칸
  Widget _cover(Library lib, String? id) {
    final w = BookRow.coverWidth(BookRowSize.small);
    return id != null && lib.books.containsKey(id) ? LinkedCover(lib: lib, id: id, width: w) : NoBookCover(width: w);
  }

  /// 캘린더에서 고른 날(달)의 기록 줄. 머리는 분석 쪽 그래프 머리와 같은 모양(제목 19 · 오른쪽 굵은 시간, 2026-11-19 공통 규칙: 여기만 회색 16이었다)
  /// 그날 기록(캘린더에서 고른 날): 머리(날짜 · 그날 총 시간) · 기록 줄들 · 맨 아래 '독서 기록 추가'(그 날짜로, 한 책으로 연 화면이면 그 책으로, 2026-11-23).
  /// 기록 없는 날은 머리와 '독서 기록 추가'만(제목과 줄만으로 뜻이 통해 안내 글은 두지 않는다, DESIGN 11장)
  List<Widget> _dayRecords(Library lib, String selected, num selMs, List<Session> selSessions, String? book) => [
        StatHead(title: dayTitle(selected), top: selMs > 0 ? formatDuration(selMs) : null),
        const SizedBox(height: Space.s),
        for (final s in selSessions) SessionRow(lib: lib, session: s, onPress: () => openSessionEdit(context, s.id)),
        ListItem(label: '독서 기록 추가', chevron: true, onPress: () => openSessionAdd(context, bookId: book, day: selected)),
      ];


  List<Widget> _records(Library lib, PeriodStats st0, List<Session> sessions, Period period, String? book) {
    final summary = sessionSummary(sessions);
    final hours = hourBars(sessions), lengths = lengthBins(sessions), wd = weekdayBars(sessions);
    final top = topBooks(sessions, 3).where((r) => lib.books.containsKey(r.id)).toList();
    final counts = bookCounts(lib, period);
    const empty = '이 기간에는 기록이 없어요.';
    // 한 번에 읽은 시간 위 카드: 평균 | 가장 오래(테두리 상자, 가운데 세로 선)
    final lengthCard = Semantics(
      container: true,
      label: '한 번에 평균 ${summary.count > 0 ? formatDurationShort(summary.averageMs) : '없음'}, 가장 오래 읽은 시간 ${summary.count > 0 ? formatDurationShort(summary.longestMs) : '없음'}',
      excludeSemantics: true,
      child: OutlineBox(
        child: IntrinsicHeight(
          child: Row(children: [
            StatNumber(label: '한 번에 평균', value: summary.count > 0 ? formatDurationShort(summary.averageMs) : '-'),
            // 가운데 세로선: 머리카락 선 두께(공통 규칙 7장 Hairline), 간격은 Space 이름으로
            Container(width: Hairline.of(context), margin: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs), color: AppColors.line),
            StatNumber(label: '가장 오래 읽은 시간', value: summary.count > 0 ? formatDurationShort(summary.longestMs) : '-'),
          ]),
        ),
      ),
    );
    // 그래프마다 흰 띠 하나(2026-11-20 토스 공식+: 위아래 층만 나누고 좌우는 화면 끝까지)
    return [
      Band(children: [
        MiniBars(
          title: '많이 읽은 시간대',
          bars: [for (var h = 0; h < 24; h++) MiniBar('$h', _dayPart(h), hours[h])],
          labels: [for (final h in const [0, 6, 12, 18, 23]) (h, '$h시')],
          emptyText: empty,
          valueText: (b) => formatDuration(b.value),
        ),
      ]),
      Band(children: [
        MiniBars(
          title: '한 번에 읽은 시간',
          bars: [for (var i = 0; i < lengths.length; i++) MiniBar(lengthBinsDef[i].key, lengthBinsDef[i].name, lengths[i])],
          labels: [for (var i = 0; i < lengthBinsDef.length; i++) (i, lengthBinsDef[i].name)],
          labelLines: 2,
          extra: lengthCard,
          emptyText: empty,
          valueText: (b) => '${b.value}회',
        ),
      ]),
      Band(children: [
        MiniBars(
          title: '많이 읽은 요일',
          bars: [for (var i = 0; i < 7; i++) MiniBar(weekdays[i], '${weekdays[i]}요일', wd[i])],
          labels: [for (var i = 0; i < 7; i++) (i, weekdays[i])],
          emptyText: empty,
          valueText: (b) => formatDuration(b.value),
        ),
      ]),
      // 책 한 권으로 열면 '많이 읽은 책'은 늘 그 책 한 줄이라 뺀다(2026-11-21 사용자 '왜 2개가 있어': 같은 것이 되풀이됐다)
      if (top.isNotEmpty && book == null)
        Band(children: [
          const Padding(padding: EdgeInsets.only(bottom: Space.s), child: SectionHead(title: '많이 읽은 책')),
          // 다른 책 줄처럼 누르면 책 정보(눌러도 아무 일 없었다)
          for (final r in top)
            BookRow(
              cover: _cover(lib, r.id),
              title: bookTitle(lib, r.id) ?? '',
              label: '${bookTitle(lib, r.id)}, ${formatDurationShort(r.ms)}',
              trailing: Text(formatDurationShort(r.ms), style: _rowValue),
              onPress: () => openBook(context, r.id),
            ),
        ]),
      Band(children: [
        ListGroup(children: [
          // 넣은 책·지금 서재(모든 책일 때만): '전체 책'의 권수와 맞춰 볼 수 있게
          if (book == null) ListItem(label: '넣은 책', value: '${counts.added}권'),
          // 책 한 권이면 '권'이 아니라 '이 책 전체'와 같은 '회'(이번 달 이 책을 다 읽은 횟수)
          ListItem(
            label: '완독',
            sub: book == null && (st0.completedRounds > st0.completedCount || st0.rereads > 0) ? ['완독 ${st0.completedRounds}회', '재독 ${st0.rereads}회'].join(metaSep) : null,
            value: book == null ? '${st0.completedCount}권' : '${st0.completedRounds}회',
          ),
          ListItem(label: '남긴 갈피', value: '${st0.bookmarkCount}개'),
          if (book == null) ListItem(label: '지금 서재', sub: counts.hidden > 0 ? '숨긴 책 ${counts.hidden}권은 빼고' : null, value: '${counts.shelf}권'),
        ]),
      ]),
    ];
  }

  // 맨 위 숫자 셋 한 줄: 읽은 시간 · 읽은 날 · 독서 횟수(2026-11-20 사용자 '이번 달 읽은 시간 말고 짧게 해서 3개 다 넣고', 이름 '읽은 시간').
  // 세 칸 모두 책 한 권 기록의 숫자 칸과 같은 StatNumber, 시간 글은 앱의 지난 시간 글자 formatDuration 하나(공통 규칙 4장).
  // '21시간 5분'처럼 긴 시간 값이 옆 칸 '17일'에 붙어 보여서 첫 칸을 넓게(4:3:3) 하고 칸 사이를 띄운다(2026-11-20 촬영 확인)
  Widget _summary(PeriodStats st0, List<Session> sessions, int activeDays, String periodName) => Semantics(
        container: true,
        label: '$periodName 읽은 시간 ${formatDuration(st0.readMs)}, 읽은 날 $activeDays일, 독서 ${sessions.length}회',
        excludeSemantics: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StatNumber(label: '읽은 시간', value: formatDuration(st0.readMs), flex: 4),
          const SizedBox(width: Space.l),
          StatNumber(label: '읽은 날', value: '$activeDays일', flex: 3),
          const SizedBox(width: Space.l),
          StatNumber(label: '독서 횟수', value: '${sessions.length}회', flex: 3),
        ]),
      );

  // 책 고르기: 앱 공통 책 고르기 시트(book_picker, 2026-11-19 공통 규칙: 기록 탭과 따로 만들어 검색 · 높이 제한이 없었다).
  // 기록이 있는 책만, '모든 책'은 맨 위 하나 고르기 줄, 지금 고른 책은 고르는 원. 고른 책이 기록이 없어도 목록에 남겨 고른 표시가 보이게
  Future<void> _pickBook(Library lib) async {
    final withSessions = <String>[];
    for (final s in lib.sessions.values) {
      final id = s.myBookId;
      if (id != null && lib.books.containsKey(id) && !withSessions.contains(id)) withSessions.add(id);
    }
    final cur = _book;
    if (cur != null && lib.books.containsKey(cur) && !withSessions.contains(cur)) withSessions.insert(0, cur);
    final r = await pickBook(context, lib, books: withSessions, meta: (id) => bookAuthor(lib, id), all: true, current: (id: cur));
    if (!r.picked || !mounted) return;
    setState(() {
      _book = r.id;
      _picked = null;
    });
  }
}
