// 읽기 탭(지금 앱 features/reading/ReadList.tsx): 맨 위 가운데 '‹ 11월 26일 목요일 ›'(전날 · 다음 날 기록 보기)와 그날 읽은 시간,
// 오늘이면 '최근 읽던 책' 큰 카드(표지 · 오늘 시간 · 이어서 읽기)와 '내 읽기 목록'(책마다 한 줄: 표지 · 제목 · 저자 · 오늘 읽은 시간이나 '읽기', 맨 아래 '+ 책 추가'),
// 다른 날이면 그날 독서 기록 줄(통계 캘린더 그날 기록과 같은 줄). 줄을 누르면 그 책으로 타이머가 시작되고 분위기 장면으로 넘어간다.
// 줄을 길게 누르면 메뉴(책 정보 · 독서 기록 · 목록에서 빼기). 장면에서 뒤로 나오면 이 목록이다(타이머는 계속 돈다).
// 다른 책을 재는 중에 다른 책을 누르면 묻는다(앞 책 시간이 설명 없이 새 책으로 옮겨 가지 않게).
// 아래 '+ 책 추가'는 여러 권을 골라 목록에 더하기만 한다(시작은 줄을 눌러서). 추가해 둔 책은 기기에 남고 메뉴에서 뺀다
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../store/settings_store.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../../app/app_nav.dart';
import '../book/add_book_screen.dart' show openAddBook;
import '../book/book_screen.dart';
import '../bookmark/book_picker.dart';
import '../stats/chart_data.dart' show dayTitle;
import '../stats/session_edit_screen.dart' show openSessionEdit;
import '../stats/session_edit_screen.dart' show openSessionAdd;
import '../stats/stats_screen.dart';
import '../stats/stats_widgets.dart';
import 'finish_screen.dart';
import 'reading_screen.dart';
import 'start_book.dart';

/// 오늘 읽은 시간: 저장한 기록 + 지금 재는 시간(시작한 날이 오늘일 때만)
class _Today {
  _Today(this.saved, this.active, this.activeMs);
  final TodayRead saved;
  final Active? active;
  final num activeMs;

  bool get noBookActive => active != null && active!.myBookId == null;
  num get total => saved.total + activeMs;

  /// 책 하나(null은 책 없이 읽기)의 오늘 시간
  num of(String? id) => id != null ? (saved.byBook[id] ?? 0) + (active?.myBookId == id ? activeMs : 0) : saved.noBook + (noBookActive ? activeMs : 0);
}

class ReadList extends StatefulWidget {
  const ReadList({super.key});

  @override
  State<ReadList> createState() => _ReadListState();
}

class _ReadListState extends State<ReadList> {
  final _lib = LibraryModel.instance;
  final _reading = ReadingStore.instance;
  final _settings = SettingsStore.instance;
  String? _focusId;

  /// 보고 있는 날(null은 오늘): 머리 ‹ › 로 전날 · 다음 날 기록을 본다(2026-11-26 사용자 '중앙에 좀 더 큰 글씨로 두고 <> 둬서 전날이나 후 기록 볼 수 있게')
  String? _day;

  @override
  void initState() {
    super.initState();
    for (final n in [_lib, _reading, _settings]) {
      n.addListener(_changed);
    }
    AppNav.instance.addListener(_navHandoff);
    _lib.load().then((_) => _navHandoff());
    _reading.load().catchError((_) {});
    _settings.load();
  }

  @override
  void dispose() {
    for (final n in [_lib, _reading, _settings]) {
      n.removeListener(_changed);
    }
    AppNav.instance.removeListener(_navHandoff);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // 다른 화면이 '읽기'로 넘겨준 책(책 정보의 읽기 시작·이어서 읽기): 목록 맨 앞에 두고 추가해 둔다(시작은 줄을 눌러서)
  void _navHandoff() {
    final id = AppNav.instance.readBook;
    if (id == null || !_lib.loaded) return;
    AppNav.instance.readBook = null;
    final b = _lib.lib.books[id];
    if (b == null || !mounted) return;
    setState(() => _focusId = id);
    if (b.status != ReadStatus.reading) _addToList([id]);
  }

  void _addToList(List<String> more) {
    final cur = _settings.readList;
    final next = [...cur, ...more.where((id) => !cur.contains(id))];
    if (next.length != cur.length) _settings.set({'readList': next});
  }

  void _openScene() => openReadingScene(context);

  // 그 책으로 읽기: 시작 규칙은 책 정보의 '읽기 시작'과 하나(start_book beginReading)
  void _begin(String? id) => beginReading(context, id, show: ({required bool finish}) => finish ? openFinish(context, root: true) : _openScene());

  // 줄을 누르면: 재는 책은 장면으로 돌아가고, 아니면 그 책으로 읽기
  void _tapRow(String? id) => _reading.active != null && _reading.active!.myBookId == id ? _openScene() : _begin(id);

  // 길게 누르기 메뉴: 메뉴 시트 줄에는 꺾쇠를 두지 않는다(2026-11-19 공통 규칙). 열리는 화면 이름과 같게 '독서 기록'
  void _menu(String id, String title, bool removable) => showSheet<void>(
        context,
        title: title,
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (id != noBook) ...[
            ListItem(label: '책 정보', onPress: () {
              Navigator.pop(ctx);
              openBook(context, id);
            }),
            ListItem(label: '독서 기록', onPress: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsScreen(tab: false, initialBook: id)));
            }),
          ],
          // 줄이 목록에서 사라지는 일이라 토스트로 알린다(DESIGN 14장). 되돌리는 기능은 따로 없다(+로 다시 더한다)
          if (removable)
            ListItem(label: '목록에서 빼기', onPress: () {
              Navigator.pop(ctx);
              _settings.set({'readList': _settings.readList.where((x) => x != id).toList()});
              if (_focusId == id) setState(() => _focusId = null);
              showToast(context, '읽기 목록에서 뺐어요.');
            }),
        ]),
      );

  /// 목록에서 빼기: 추가해 둔 줄만(읽는 중인 책·오늘 읽은 책·재는 책은 그 까닭으로 목록에 있어 빼도 남는다)
  bool _removable(Library lib, _Today t, String id) =>
      _settings.readList.contains(id) &&
      (id == noBook ? !t.noBookActive && t.saved.noBook == 0 : lib.books[id]?.status != ReadStatus.reading && !t.saved.byBook.containsKey(id) && t.active?.myBookId != id);

  String _titleOf(Library lib, String? id) => id != null ? bookTitle(lib, id) ?? '' : NoBookCover.name;

  Widget _coverOf(Library lib, String? id, double w) => id != null ? LinkedCover(lib: lib, id: id, width: w) : NoBookCover(width: w);

  void _moreOf(Library lib, _Today t, String? id) {
    if (id == null && !_removable(lib, t, noBook)) return;
    _menu(id ?? noBook, _titleOf(lib, id), _removable(lib, t, id ?? noBook));
  }

  /// 재는 중이면 '00:45'(장면·작은 타이머와 같은 시계, 1분이 넘으면 'N분'), 아니면 오늘 읽은 시간
  String _timeText(num ms, bool live) => live && ms < 60000 ? clock(ms) : formatDuration(ms);

  /// 내 읽기 목록 한 줄: 앱 공통 책 줄(BookRow 작게 40, 2026-11-19 공통 규칙). 오른쪽은 오늘 읽었으면 그 시간, 아니면 ▶ 읽기
  Widget _row(Library lib, _Today t, String? id) {
    final active = t.active;
    final isActive = active != null && active.myBookId == id;
    final playing = isActive && _reading.running;
    final title = _titleOf(lib, id), author = bookAuthor(lib, id);
    // 재는 책은 적어도 지금 잰 시간(자정을 넘겨 재는 중이면 오늘 몫이 0이라 00:00에 멈춰 보였다, 점검 B2)
    final ms = isActive ? math.max(t.of(id), _reading.elapsed) : t.of(id);
    // 화면 읽기 이름과 '더 보기' 동작은 줄 하나에(BookRow 안 이름은 뺀다)
    return Semantics(
      key: ValueKey(id ?? '~none'),
      container: true,
      button: true,
      label: '$title${author.isNotEmpty ? ', $author' : ''}${ms > 0 ? ', 오늘 ${formatDuration(ms)}' : ''}${isActive ? (playing ? ', 읽는 중' : ', 일시정지') : ', 읽기'}',
      customSemanticsActions: {CustomSemanticsAction(label: '$title 더 보기'): () => _moreOf(lib, t, id)},
      excludeSemantics: true,
      onTap: () => _tapRow(id),
      child: GestureDetector(
        onLongPress: () => _moreOf(lib, t, id),
        child: BookRow(
          // 위아래 4(2026-11-18 사용자 시안 '촘촘하게')
          dense: true,
          cover: _coverOf(lib, id, BookRow.coverWidth(BookRowSize.small)),
          title: title,
          meta: author,
          onPress: () => _tapRow(id),
          trailing: ms > 0 || isActive
              ? Text(_timeText(ms, isActive), style: AppType.rowStrong.tnum)
              // 회색(위 +와 같은 색, 2026-11-19 사용자 '읽기 회색으로 하는 게 낫지 않나'): 줄마다 책 제목이 먼저 보인다.
              // 글자 앞 ▶는 두지 않는다(DESIGN 5장 '단추 글자 앞 기호 없음', 2026-11-20 사용자 '삼각형 없애고')
              : Text('읽기', style: AppType.rowStrong.copyWith(color: AppColors.inkSoft)),
        ),
      ),
    );
  }

  /// 맨 위 가운데 날 넘기기 '‹ 11월 26일 목요일 ›': 통계 달 넘기기와 같은 모양(글자 heading, 양옆 아이콘 단추. 2026-11-26 사용자
  /// '11월 26일 목요일 저렇게 있는 거 좀 애매하지 않나 차라리 중앙에 좀 더 큰 글씨로 두고 <> 이거 둬서 전날이나 후 기록 볼 수 있는 게 나은듯').
  /// 다음 날은 오늘까지. 날짜 글자는 앱 공통 날짜 머리 함수(DESIGN 4장 dayTitle)
  Widget _dayBar(String date, String todayDay) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconBtn(label: '이전 날', onPress: () => _shiftDay(date, -1), child: const LucideIcon('ChevronLeft', color: AppColors.icon)),
        // 좁은 화면 · 큰 글씨에서도 한 줄(넘치면 글자만 줄인다)
        Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Semantics(header: true, child: Text(dayTitle(date), maxLines: 1, style: AppType.heading.tnum)))),
        IconBtn(label: '다음 날', disabled: date == todayDay, onPress: () => _shiftDay(date, 1), child: const LucideIcon('ChevronRight', color: AppColors.icon)),
      ]);

  void _shiftDay(String date, int dir) {
    final p = date.split('-').map(int.parse).toList();
    final next = today(DateTime(p[0], p[1], p[2] + dir));
    final now = today();
    if (next.compareTo(now) > 0) return;
    setState(() => _day = next == now ? null : next);
  }

  /// 날 넘기기 아래 한 줄: 왼쪽 '오늘 읽은 시간 N'(다른 날은 '읽은 시간 N'), 오른쪽 '시간 추가'(그 날짜로 독서 기록 추가, 타이머 없이 읽은 시간).
  /// 2026-11-25 사용자 시안 '수동 시간 추가는 오른쪽에'. '시간 추가'는 회색 글자 단추(누르는 높이 48)
  Widget _totalLine(String date, bool isToday, num total, Active? active) {
    final name = isToday ? '오늘 읽은 시간' : '읽은 시간';
    final label = '$name ${formatDuration(total)}${isToday && active != null ? (_reading.running ? ', 읽는 중' : ', 일시정지') : ''}';
    final ink = AppType.sub.copyWith(color: AppColors.ink);
    return Row(children: [
      Expanded(
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Text.rich(TextSpan(text: '$name ', style: ink, children: [TextSpan(text: formatDuration(total), style: AppType.rowStrong.tnum)])),
        ),
      ),
      const SizedBox(width: Space.m),
      TextLink(label: '시간 추가', soft: true, end: true, onPress: () => openSessionAdd(context, day: date)),
    ]);
  }

  /// 다른 날의 독서 기록 줄(통계 캘린더 그날 기록과 같은 줄, 누르면 기록 수정). 기록이 없으면 한 줄 안내
  List<Widget> _dayRecords(Library lib, String date) {
    final list = [for (final s in lib.sessions.values) if (sessionDay(s) == date) s]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return [
      const SizedBox(height: Space.l),
      if (list.isEmpty) const EmptyLine('이날은 독서 기록이 없어요'),
      for (final s in list) SessionRow(lib: lib, session: s, onPress: () => openSessionEdit(context, s.id)),
    ];
  }

  /// 최근 읽던 책 큰 카드(표지 92 · 제목 · 오늘 시간 · 이어서 읽기, 위에 이름 글자 없음): 사용자 시안의 큰 카드라 책 줄(BookRow)로 바꾸지 않는다
  List<Widget> _featured(Library lib, _Today t, String? featured) {
    final active = t.active;
    final running = _reading.running;
    final fActive = active != null && active.myBookId == featured;
    final fMs = active != null && active.myBookId == featured ? math.max(t.of(featured), _reading.elapsed) : t.of(featured);
    final fRead = featured != null && lib.sessions.values.any((x) => x.myBookId == featured);
    // 완독한 책은 '다시 읽기'(책 정보 아래 단추와 같은 말. 완독으로 바꾼 책이 '이어서 읽기'로 보였다, 2026-11-20 QA)
    final fDone = featured != null && lib.books[featured]?.status == ReadStatus.read;
    final fLabel = fActive ? (running ? '읽기 화면으로' : '이어서 읽기') : (fDone ? '다시 읽기' : fRead ? '이어서 읽기' : '읽기 시작');
    final title = _titleOf(lib, featured), author = bookAuthor(lib, featured);
    void open() => featured == null ? null : openBook(context, featured);
    return [
      // 카드 위 '최근 읽던 책 · 읽는 중 · 잠깐 멈춘 책' 글자는 없다(2026-11-25 사용자 시안 · '지워'). 재는 중인지는 단추 이름과 시간 글자로 보인다.
      // 오늘 줄 글자 아래 ~ 표지 28(Space.xl): 오늘 줄은 '시간 추가'가 누르는 높이 48이라 글자 아래로 12가 비어 16만 더한다
      const SizedBox(height: Space.l),
      // 표지 92(2026-11-25 사용자 '썸네일 저 정도로 줄이고, 줄이면서 버튼 좌우 길이 늘려'), 제목은 표지 위 끝 줄에서(사용자 '썸네일 상단 라인에 맞춰'),
      // 오늘 시간은 전처럼 단추 오른쪽 위, 단추 아래 끝은 표지 아래 끝. 글이 표지보다 길면(큰 글씨 · 두 줄 제목) 줄이 그만큼 길어지고 표지는 위에 붙는다
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.topCenter,
            child: Semantics(
              button: true,
              label: '$title 책 정보',
              excludeSemantics: true,
              onTap: featured == null ? null : open,
              child: Pressable(onPress: featured == null ? null : open, child: _coverOf(lib, featured, CoverSize.feature)),
            ),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WordText(title, maxLines: 2, style: AppType.bookFeatureTitle),
              if (author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookAuthor)),
              const Spacer(),
              Text(_timeText(fMs, fActive), textAlign: TextAlign.right, style: AppType.section.tnum),
              const SizedBox(height: Space.s),
              // 다른 화면 단추와 같은 보통 높이(large 48, 2026-11-18 사용자 '박스 세로 높이 다른 버튼처럼')
              Btn(label: fLabel, size: 'large', onPress: () => fActive && running ? _openScene() : _begin(featured)),
            ]),
          ),
        ]),
      ),
    ];
  }

  /// 목록 아래 '+ 책 추가'(회색, 누르는 높이 48): + 그림 왼쪽 끝을 내용 왼쪽 끝(위 표지 줄)에 맞춘다(Lucide + 획은 24칸의 4.2부터).
  /// 화면 읽기 이름은 하는 일대로 '읽기 목록에 책 추가'(보이는 글자를 품는다)
  Widget _addRow(VoidCallback onPress) => Semantics(
        button: true,
        label: '읽기 목록에 책 추가',
        excludeSemantics: true,
        onTap: onPress,
        child: Pressable(
          onPress: onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.hit),
            child: Transform.translate(
              offset: const Offset(-IconSize.base * 4.2 / 24, 0),
              child: Row(children: [
                const LucideIcon('Plus', color: AppColors.icon),
                const SizedBox(width: Space.s),
                Expanded(child: Text('책 추가', style: AppType.subLink)),
              ]),
            ),
          ),
        ),
      );

  // 재는 동안은 1초마다 다시 그린다(줄 시간 · 오늘 총 · 화면 읽기 이름이 함께 바뀐다)
  @override
  Widget build(BuildContext context) => ElapsedTicker(running: _reading.running, builder: (_) => _screen(context));

  Widget _screen(BuildContext context) {
    // 서재를 읽기 전에는 빈 목록 안내가 잠깐 보이지 않게 불러오는 중(DESIGN 11장)
    if (!_lib.loaded) return const Screen(back: false, title: '읽기', hideTitle: true, children: [Loading()]);
    final lib = _lib.lib;
    final active = _reading.active;
    final added = _settings.readList;
    final now = DateTime.now();
    final day = today(now);
    final saved = todayRead(lib, day);
    final ids = readListIds(lib, day: day, activeId: active?.myBookId, focusId: _focusId, added: added);
    // 지금 재는 시간은 시작한 날의 몫으로 더한다(자정을 넘겨도 끝낼 때 시작 날짜로 저장되는 것과 같게)
    final t = _Today(saved, active, active != null && today(DateTime.parse(active.startedAt)) == day ? _reading.elapsed : 0);
    // 오늘 책 없는 시간은 오늘 책 없이 읽어 저장했을 때만 줄로 띄운다(finish_reading noBookDay): 지운 책의 독서 시간도 책 연결이 비어
    // 여기에 들어온다(2026-11-16 QA 현우 F4: 읽기 탭에 넣은 적 없는 '책 없이 읽기' 줄이 생겼다)
    final showNoBook = t.noBookActive || (saved.noBook > 0 && _settings.noBookDay == day) || added.contains(noBook);
    final hasRows = ids.isNotEmpty || showNoBook;
    // 고를 책이 하나도 없으면(숨긴 책은 고르기에서 빠진다) 빈 안내 단추는 내 책에 책을 넣는 '책 추가'
    final noBooks = !lib.books.values.any((b) => b.hiddenAt == null);
    Future<void> openPicker() async {
      final picked = await pickBooks(context, lib, MultiPick(fixed: showNoBook ? [...ids, noBook] : ids, none: noBook), allowNone: true);
      if (picked.isNotEmpty) _addToList(picked);
    }

    // 최근 읽던 책: 재는 책 → 오늘·최근에 읽은 책 → 목록 첫 책
    String? featured;
    var hasFeatured = false;
    if (active != null) {
      featured = active.myBookId;
      hasFeatured = true;
    } else {
      final recent = lib.sessions.values.where((x) => x.myBookId != null && ids.contains(x.myBookId)).toList()..sort((a, c) => c.startedAt.compareTo(a.startedAt));
      if (recent.isNotEmpty) {
        featured = recent.first.myBookId;
        hasFeatured = true;
      } else if (ids.isNotEmpty) {
        featured = ids.first;
        hasFeatured = true;
      }
    }
    final rest = [for (final id in ids) if (!(hasFeatured && id == featured)) id];
    final restNoBook = showNoBook && !(hasFeatured && featured == null);

    // 머리: 왼쪽 위 제목 '읽기'는 없다(하단바에 이름, 2026-11-24 사용자 6단계. 화면 읽기 머리로만), 맨 위가 가운데 날 넘기기와 그날 총 시간.
    // 소리만 듣기 아이콘은 뺐다(2026-11-17 사용자 '위에 음악 아이콘 없애')
    final shown = _day != null && _day!.compareTo(day) < 0 ? _day! : day;
    if (shown != day) {
      // 다른 날: 날 넘기기 · 그날 읽은 시간 · 그날 기록 줄만(최근 읽던 책 · 읽기 목록은 오늘만)
      return Screen(
        back: false,
        title: '읽기',
        hideTitle: true,
        bottomPad: TabBarStyle.contentPad - Space.section,
        children: [_dayBar(shown, day), _totalLine(shown, false, todayRead(lib, shown).total, null), ..._dayRecords(lib, shown)],
      );
    }
    return Screen(
      back: false,
      title: '읽기',
      hideTitle: true,
      bottomPad: TabBarStyle.contentPad - Space.section,
      children: [
        _dayBar(day, day),
        _totalLine(day, true, t.total, t.active),
        // 끝냈지만 저장하지 않은 기록(독서 끝 화면에서 뒤로 나왔을 때 등): 여기서 다시 연다(2026-11-15 QA 민혁 F3)
        if (_reading.pending != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: ListItem(
              label: '저장하지 않은 독서 기록이 있어요',
              sub: [bookTitle(lib, _reading.pending!.myBookId) ?? NoBookCover.name, formatDurationPrecise(_reading.pending!.durationMs)].join(metaSep),
              chevron: true,
              onPress: () => openFinish(context, root: true),
            ),
          ),
        if (hasFeatured) ..._featured(lib, t, featured),
        // 내 읽기 목록. 더하기는 목록 아래 '+ 책 추가' 줄 하나(읽을 책·다 읽은 책이나 책 없이 읽기를 여러 개 골라 더한다).
        // 제목 오른쪽 +는 2026-11-25 뺐다 되살렸다가 2026-11-26 사용자 '내 읽기 목록 옆에 있는 + 지워줘'로 다시 뺐다
        Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          // 구역 제목은 앱 공통 구역 제목. 줄 높이는 누르는 높이(+가 있던 때와 아래 목록 자리가 같게)
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.hit),
            child: Align(alignment: Alignment.centerLeft, child: Semantics(header: true, child: Text('내 읽기 목록', style: AppType.section))),
          ),
        ),
        if (rest.isNotEmpty || restNoBook)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final id in rest) _row(lib, t, id), if (restNoBook) _row(lib, t, null)]),
          ),
        // 첫 사용(목록이 빔)에는 두지 않는다: 아래 안내 단추와 같은 일이라 헷갈렸다(2026-11-20 사용자 '+랑 책 추가랑 무슨 차이야')
        if (hasRows)
          _addRow(openPicker)
        else
          // 첫 사용(2026-11-17 시안: 안내 한 줄 + 단추). 단추 이름은 하는 일대로: 읽기 목록에 고르기는 '읽기 목록에 추가'
          // ('책 추가'는 내 책에 새 책을 넣는 일이라 이름이 같으면 헷갈린다), 고를 책이 없으면 내 책에 넣는 '책 추가'
          Padding(
            padding: const EdgeInsets.only(top: Space.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WordText(noBooks ? '책을 추가하면 읽기 목록에 골라 두고 시간을 잴 수 있어요' : '읽을 책을 골라 두고 눌러서 시간을 재요', style: AppType.sub),
              const SizedBox(height: Space.m),
              noBooks ? Btn(label: '책 추가', onPress: () => openAddBook(context)) : Btn(label: '읽기 목록에 추가', onPress: openPicker),
            ]),
          )
      ],
    );
  }
}
