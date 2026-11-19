// 읽기 탭(지금 앱 features/reading/ReadList.tsx): 맨 위 오늘 날짜와 오늘 읽은 시간, '최근 읽던 책' 큰 카드(표지 · 오늘 시간 · 이어서 읽기),
// 아래 '내 읽기 목록'은 책마다 한 줄(표지 · 제목 · 저자 · 오늘 읽은 시간이나 ▶ 읽기). 줄을 누르면 그 책으로 타이머가 시작되고 분위기 장면으로 넘어간다.
// 줄을 길게 누르면 메뉴(책 정보 · 독서 기록 · 목록에서 빼기). 장면에서 뒤로 나오면 이 목록이다(타이머는 계속 돈다).
// 다른 책을 재는 중에 다른 책을 누르면 묻는다(앞 책 시간이 설명 없이 새 책으로 옮겨 가지 않게).
// '내 읽기 목록' 오른쪽 +는 여러 권을 골라 목록에 더하기만 한다(시작은 줄을 눌러서). 추가해 둔 책은 기기에 남고 메뉴에서 뺀다
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
import '../stats/stats_screen.dart';
import '../stats/stats_widgets.dart';
import 'finish_screen.dart';
import 'play_icons.dart';
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
              // 회색(위 +와 같은 색, 2026-11-19 사용자 '읽기 회색으로 하는 게 낫지 않나'): 줄마다 책 제목이 먼저 보인다
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const PlayIcon(size: 14, color: AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Text('읽기', style: AppType.rowStrong.copyWith(color: AppColors.inkSoft)),
                ]),
        ),
      ),
    );
  }

  /// 오늘 날짜와 오늘 총 시간(제목 바로 아래 한 줄). 날짜 글자는 앱 공통 날짜 머리 함수(DESIGN 4장 dayTitle)
  Widget _todayLine(String date, _Today t) {
    final day = dayTitle(date);
    return Semantics(
      label: '$day, 오늘 총 ${formatDuration(t.total)}${t.active != null ? (_reading.running ? ', 읽는 중' : ', 일시정지') : ''}',
      excludeSemantics: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(child: Text(day, style: AppType.sub.copyWith(color: AppColors.ink))),
        Text('오늘 총 ', style: AppType.sub),
        Text(formatDuration(t.total), style: AppType.rowStrong.tnum),
      ]),
    );
  }

  /// 최근 읽던 책 큰 카드(표지 120 · 제목 21 · 오늘 시간 · 이어서 읽기): 사용자 시안의 큰 카드라 책 줄(BookRow)로 바꾸지 않는다
  List<Widget> _featured(Library lib, _Today t, String? featured) {
    final active = t.active;
    final running = _reading.running;
    final fActive = active != null && active.myBookId == featured;
    final fMs = active != null && active.myBookId == featured ? math.max(t.of(featured), _reading.elapsed) : t.of(featured);
    final fRead = featured != null && lib.sessions.values.any((x) => x.myBookId == featured);
    final fLabel = fActive ? (running ? '읽기 화면으로' : '이어서 읽기') : (fRead ? '이어서 읽기' : '읽기 시작');
    final title = _titleOf(lib, featured), author = bookAuthor(lib, featured);
    void open() => featured == null ? null : openBook(context, featured);
    return [
      // 위아래 간격은 시안처럼 촘촘하게(2026-11-18 사용자 '간격이 좀 이상하네')
      Padding(padding: const EdgeInsets.only(top: Space.l, bottom: Space.m), child: Text(fActive ? (running ? '읽는 중' : '잠깐 멈춘 책') : '최근 읽던 책', style: AppType.sub)),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Semantics(
          button: true,
          label: '$title 책 정보',
          excludeSemantics: true,
          onTap: featured == null ? null : open,
          child: Pressable(onPress: featured == null ? null : open, child: _coverOf(lib, featured, CoverSize.feature)),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WordText(title, maxLines: 2, style: AppType.bookFeatureTitle),
            if (author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookAuthor)),
            const SizedBox(height: Space.l),
            Text(_timeText(fMs, fActive), textAlign: TextAlign.right, style: AppType.section.tnum),
            const SizedBox(height: Space.s),
            // 다른 화면 단추와 같은 보통 높이(m 48, 2026-11-18 사용자 '박스 세로 높이 다른 버튼처럼')
            Btn(label: fLabel, size: 'm', icon: const PlayIcon(size: 17, color: AppColors.onAccent), onPress: () => fActive && running ? _openScene() : _begin(featured)),
          ]),
        ),
      ]),
    ];
  }

  // 재는 동안은 1초마다 다시 그린다(줄 시간 · 오늘 총 · 화면 읽기 이름이 함께 바뀐다)
  @override
  Widget build(BuildContext context) => ElapsedTicker(running: _reading.running, builder: (_) => _screen(context));

  Widget _screen(BuildContext context) {
    // 서재를 읽기 전에는 빈 목록 안내가 잠깐 보이지 않게 불러오는 중(DESIGN 11장)
    if (!_lib.loaded) return const Screen(back: false, title: '읽기', children: [Loading()]);
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

    // 머리: 탭 첫 화면 공통 제목(위 16 · 아래 12, 2026-11-19 공통 규칙: 여기만 직접 만들어 아래 8이었다), 아래 오늘 날짜와 오늘 총 시간.
    // 소리만 듣기 아이콘은 뺐다(2026-11-17 사용자 '위에 음악 아이콘 없애')
    return Screen(
      back: false,
      title: '읽기',
      bottomPad: TabBarStyle.contentPad - Space.section,
      children: [
        _todayLine(day, t),
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
        // 내 읽기 목록(오른쪽 +: 읽을 책·다 읽은 책이나 책 없이 읽기를 여러 개 골라 더한다)
        Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: Row(children: [
            // 구역 제목은 앱 공통 구역 제목(19)
            Expanded(child: Semantics(header: true, child: Text('내 읽기 목록', style: AppType.section))),
            // +는 보이는 획의 오른쪽 끝을 아래 '▶ 읽기' 글자 끝 선에 맞춘다(2026-11-18 사용자 '+ 너무 작고 우측 라인에 안 맞아, 회색').
            // 26 그림(24칸에 획은 5~19)이 누르는 칸 48 가운데라 칸 끝까지 11, 그림 안 여백 5.4, 반 획 1을 빼 15.4만큼 민다
            Transform.translate(
              offset: const Offset(15.4, 0),
              child: IconBtn(label: '읽기 목록에 추가', onPress: openPicker, child: const LucideIcon('Plus', size: 26, color: AppColors.inkSoft, stroke: 2)),
            ),
          ]),
        ),
        if (rest.isNotEmpty || restNoBook)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final id in rest) _row(lib, t, id), if (restNoBook) _row(lib, t, null)]),
          )
        else if (!hasRows)
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
        else
          const EmptyLine('+로 읽을 책을 더 골라 둘 수 있어요'),
      ],
    );
  }
}
