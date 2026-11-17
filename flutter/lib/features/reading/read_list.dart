// 읽기 탭(지금 앱 features/reading/ReadList.tsx): 맨 위 오늘 날짜와 오늘 읽은 시간, 아래 책마다 [표지·재생 단추 · 책 이름(밑에 지은이) · 오늘 읽은 시간 · ⋮].
// 재생을 누르면 그 책으로 타이머가 시작되고 분위기 장면으로 넘어간다. 장면에서 뒤로 나오면 이 목록이다(타이머는 계속 돈다).
// 다른 책을 재는 중에 재생을 누르면 묻는다(앞 책 시간이 설명 없이 새 책으로 옮겨 가지 않게).
// 맨 아래 '+ 책 추가'는 여러 권을 골라 '완료'하면 목록에 더하기만 한다(시작은 재생 단추로). 추가해 둔 책은 기기에 남고 ⋮에서 뺀다
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../services/ambient.dart';
import '../../store/finish_reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../store/settings_store.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/book_screen.dart';
import '../../app/app_nav.dart';
import '../bookmark/book_picker.dart';
import '../stats/stats_screen.dart';
import '../stats/stats_widgets.dart';
import 'finish_screen.dart';
import 'play_icons.dart';
import 'reading_screen.dart';
import 'switch_book.dart';

const _week = ['일', '월', '화', '수', '목', '금', '토'];
const _tabular = [FontFeature.tabularFigures()];

String? bookTitle(Library lib, String? id) {
  final b = id == null ? null : lib.books[id];
  return b == null ? null : lib.editions[b.editionId]?.title;
}

class ReadList extends StatefulWidget {
  const ReadList({super.key, this.handoff});

  /// 책 정보·책장·기록에서 '읽기'로 넘겨받은 책
  final String? handoff;

  @override
  State<ReadList> createState() => _ReadListState();
}

class _ReadListState extends State<ReadList> {
  final _lib = LibraryModel.instance;
  final _reading = ReadingStore.instance;
  final _settings = SettingsStore.instance;
  String? _focusId;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    for (final n in [_lib, _reading, _settings]) {
      n.addListener(_changed);
    }
    AppNav.instance.addListener(_navHandoff);
    _lib.load().then((_) {
      _takeHandoff(widget.handoff);
      _navHandoff();
    });
    _reading.load().catchError((_) {});
    _settings.load();
    _sync();
  }

  @override
  void dispose() {
    for (final n in [_lib, _reading, _settings]) {
      n.removeListener(_changed);
    }
    AppNav.instance.removeListener(_navHandoff);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  // 재는 동안만 1초마다 다시 그린다
  void _sync() {
    if (_reading.running) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  // 넘겨받은 책은 목록 맨 앞에 두고 추가해 둔다(시작은 재생을 눌러서)
  // 다른 화면이 '읽기'로 넘겨준 책(책 정보의 읽기 시작·이어서 읽기)
  void _navHandoff() {
    final id = AppNav.instance.readBook;
    if (id == null || !_lib.loaded) return;
    AppNav.instance.readBook = null;
    _takeHandoff(id);
  }

  void _takeHandoff(String? h) {
    final b = h == null ? null : _lib.lib.books[h];
    if (b == null || !mounted) return;
    setState(() => _focusId = h);
    if (b.status != ReadStatus.reading) _addToList([h!]);
  }

  void _addToList(List<String> more) {
    final cur = _settings.readList;
    final next = [...cur, ...more.where((id) => !cur.contains(id))];
    if (next.length != cur.length) _settings.set({'readList': next});
  }

  void _openScene() => openReadingScene(context);

  void _startNew(String? id) {
    _reading.start(id, id == null ? null : _lib.lib.books[id]?.currentPage);
    Ambient.instance.play(_settings.scene);
    _openScene();
  }

  // 재생 단추(책마다): 재는 책이면 일시정지·다시 시작, 아니면 그 책으로 시작하고 장면으로
  void _begin(String? id) {
    if (_reading.pending != null) {
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/reading/finish'), builder: (_) => const FinishScreen())); // 끝냈지만 저장하지 않은 기록부터
      return;
    }
    final cur = _reading.active;
    if (cur == null) return _startNew(id);
    if (cur.myBookId == id) {
      if (cur.runningSince != null) return _reading.pause();
      _reading.resume();
      return _openScene();
    }
    final lib = _lib.lib;
    askSwitchBook(
      context,
      lib: lib,
      curId: cur.myBookId,
      nextId: id,
      elapsedMs: _reading.elapsed,
      onSaveNew: () {
        saveAndStartOther(id).then((_) => _openScene(), onError: (Object e) {
          if (mounted) appAlert(context, '저장하지 못했어요', '$e');
        });
      },
      onMove: () {
        _reading.setBook(id, id == null ? null : lib.books[id]?.currentPage);
        _openScene();
      },
    );
  }

  void _openPending() => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/reading/finish'), builder: (_) => const FinishScreen()));

  // 줄을 누르면: 재는 책은 장면으로 돌아가고, 아니면 재생과 같다
  void _tapRow(String? id) => _reading.active != null && _reading.active!.myBookId == id ? _openScene() : _begin(id);

  void _menu(String id, String title, bool removable) => showSheet<void>(
        context,
        title: title,
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (id != noBook) ...[
            ListItem(label: '책 정보', chevron: true, onPress: () {
              Navigator.pop(ctx);
              openBook(context, id);
            }),
            ListItem(label: '이 책 독서 기록', chevron: true, onPress: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsScreen(tab: false, initialBook: id)));
            }),
          ],
          if (removable)
            ListItem(label: '목록에서 빼기', onPress: () {
              Navigator.pop(ctx);
              _settings.set({'readList': _settings.readList.where((x) => x != id).toList()});
              if (_focusId == id) setState(() => _focusId = null);
            }),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lib = _lib.lib;
    final active = _reading.active;
    final running = _reading.running;
    final added = _settings.readList;
    final now = DateTime.now();
    final day = today(now);
    final liveMs = _reading.elapsed;
    final saved = todayRead(lib, day);
    final ids = readListIds(lib, day: day, activeId: active?.myBookId, focusId: _focusId, added: added);
    // 지금 재는 시간은 시작한 날의 몫으로 더한다(자정을 넘겨도 끝낼 때 시작 날짜로 저장되는 것과 같게)
    final activeToday = active != null && today(DateTime.parse(active.startedAt)) == day ? liveMs : 0;
    final total = saved.total + activeToday;
    num msOf(String id) => (saved.byBook[id] ?? 0) + (active?.myBookId == id ? activeToday : 0);
    final noBookActive = active != null && active.myBookId == null;
    // 오늘 책 없는 시간은 오늘 책 없이 읽어 저장했을 때만 줄로 띄운다(finish_reading noBookDay): 지운 책의 독서 시간도 책 연결이 비어
    // 여기에 들어온다(2026-11-16 QA 현우 F4: 읽기 탭에 넣은 적 없는 '책 없이 읽기' 줄이 생겼다)
    final showNoBook = noBookActive || (saved.noBook > 0 && _settings.noBookDay == day) || added.contains(noBook);
    // 목록에서 빼기: 추가해 둔 줄만(읽는 중인 책·오늘 읽은 책·재는 책은 그 까닭으로 목록에 있어 빼도 남는다)
    bool removable(String id) =>
        added.contains(id) &&
        (id == noBook ? !noBookActive && saved.noBook == 0 : lib.books[id]?.status != ReadStatus.reading && !saved.byBook.containsKey(id) && active?.myBookId != id);

    // 2026-11-17 사용자 시안: 위에 '최근 읽던 책' 카드(큰 표지 · 오늘 시간 · 이어서 읽기), 아래 '내 읽기 목록'(제목·저자, 오늘 읽었으면 시간, 아니면 ▶ 읽기).
    // 누르면 타이머 장면으로 넘어간다. 줄을 길게 누르면 예전 ⋮ 메뉴(책 정보 · 이 책 독서 기록 · 목록에서 빼기)
    String titleOf(String? id) => id != null ? bookTitle(lib, id) ?? '' : '책 없이 읽기';
    String authorOf(String? id) {
      final ed = id == null ? null : lib.editions[lib.books[id]?.editionId ?? ''];
      return ed != null && ed.authors.isNotEmpty ? ed.authors.join(', ') : '';
    }
    num timeOf(String? id) => id != null ? msOf(id) : saved.noBook + (noBookActive ? activeToday : 0);
    Widget coverOf(String? id, double w) => id != null
        ? LinkedCover(lib: lib, id: id, width: w)
        : Container(
            width: w,
            height: (w / 0.68).roundToDouble(),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(4)),
            child: const Center(child: LucideIcon('BookOpen', color: AppColors.inkSoft)),
          );
    void moreOf(String? id) {
      if (id == null && !removable(noBook)) return;
      _menu(id ?? noBook, id == null ? '책 없이 읽기' : titleOf(id), removable(id ?? noBook));
    }

    Widget row(String? id) {
      final isActive = active != null && active.myBookId == id;
      final playing = isActive && running;
      final title = titleOf(id), author = authorOf(id);
      final ms = timeOf(id);
      return Semantics(
        key: ValueKey(id ?? '~none'),
        container: true,
        button: true,
        label: '$title${author.isNotEmpty ? ', $author' : ''}${ms > 0 ? ', 오늘 ${formatDuration(ms)}' : ''}${isActive ? (playing ? ', 읽는 중' : ', 일시정지') : ', 읽기'}',
        customSemanticsActions: {CustomSemanticsAction(label: '$title 더 보기'): () => moreOf(id)},
        excludeSemantics: true,
        onTap: () => _tapRow(id),
        child: GestureDetector(
          onLongPress: () => moreOf(id),
          child: Pressable(
            onPress: () => _tapRow(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Row(children: [
                coverOf(id, 48),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
                    if (author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub)),
                  ]),
                ),
                const SizedBox(width: Space.m),
                // 오늘 읽었으면 그 시간, 아니면 ▶ 읽기(재는 중이면 시간이 늘어난다)
                if (ms > 0 || isActive)
                  Text(isActive && ms < 60000 ? hms(ms) : formatDuration(ms), style: AppType.rowStrong.copyWith(fontFeatures: _tabular))
                else
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const PlayIcon(size: 14, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text('읽기', style: AppType.rowStrong.copyWith(color: AppColors.accent)),
                  ]),
              ]),
            ),
          ),
        ),
      );
    }

    final hasRows = ids.isNotEmpty || showNoBook;
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
    final fActive = hasFeatured && active != null && active.myBookId == featured;
    final fMs = hasFeatured ? timeOf(featured) : 0;
    final fRead = featured != null && lib.sessions.values.any((x) => x.myBookId == featured);
    final fLabel = fActive ? (running ? '읽기 화면으로' : '이어서 읽기') : (fRead ? '이어서 읽기' : '읽기 시작');

    return Screen(
      back: false,
      bottomPad: TabBarStyle.contentPad - Space.section,
      children: [
        // 머리: '읽기' 제목(오른쪽 소리만 듣기), 아래 오늘 날짜와 오늘 총 시간
        Padding(
          padding: const EdgeInsets.only(top: TabHeader.paddingTop),
          child: Row(children: [
            Expanded(child: Semantics(header: true, child: Text('읽기', style: AppType.title))),
            IconBtn(label: '소리만 듣기', onPress: () => openReadingScene(context, soundOnly: true), child: const LucideIcon('AudioLines')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Semantics(
            label: '${now.month}월 ${now.day}일 ${_week[now.weekday % 7]}요일, 오늘 총 ${formatDuration(total)}${active != null ? (running ? ', 읽는 중' : ', 일시정지') : ''}',
            excludeSemantics: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(child: Text('${now.month}월 ${now.day}일 ${_week[now.weekday % 7]}요일', style: AppType.sub.copyWith(color: AppColors.ink))),
              Text('오늘 총 ', style: AppType.sub),
              Text(formatDuration(total), style: AppType.rowStrong.copyWith(fontFeatures: _tabular)),
            ]),
          ),
        ),
        // 끝냈지만 저장하지 않은 기록(독서 끝 화면에서 뒤로 나왔을 때 등): 여기서 다시 연다(2026-11-15 QA 민혁 F3)
        if (_reading.pending != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: ListItem(
              label: '저장하지 않은 독서 기록이 있어요',
              sub: [bookTitle(lib, _reading.pending!.myBookId) ?? '책 없이 읽기', formatDurationPrecise(_reading.pending!.durationMs)].join(' · '),
              chevron: true,
              onPress: _openPending,
            ),
          ),
        if (hasFeatured) ...[
          Padding(padding: const EdgeInsets.only(top: Space.xl, bottom: Space.m), child: Text(fActive ? (running ? '읽는 중' : '잠깐 멈춘 책') : '최근 읽던 책', style: AppType.sub)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Semantics(
              button: true,
              label: '${titleOf(featured)} 책 정보',
              excludeSemantics: true,
              onTap: featured == null ? null : () => openBook(context, featured!),
              child: Pressable(onPress: featured == null ? null : () => openBook(context, featured!), child: coverOf(featured, 120)),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                WordText(titleOf(featured), maxLines: 2, style: AppType.heading),
                if (authorOf(featured).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(authorOf(featured), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub)),
                const SizedBox(height: Space.l),
                Text(fActive && fMs < 60000 ? hms(fMs) : formatDuration(fMs), textAlign: TextAlign.right, style: AppType.rowStrong.copyWith(fontSize: 20, fontFeatures: _tabular)),
                const SizedBox(height: Space.s),
                Btn(label: fLabel, icon: const PlayIcon(size: 15, color: AppColors.onAccent), onPress: () => fActive ? (running ? _openScene() : _begin(featured)) : _begin(featured)),
              ]),
            ),
          ]),
        ],
        // 내 읽기 목록(오른쪽 +: 읽을 책·다 읽은 책이나 책 없이 읽기를 여러 개 골라 더한다)
        Padding(
          padding: const EdgeInsets.only(top: Space.section),
          child: Row(children: [
            Expanded(child: Semantics(header: true, child: Text('내 읽기 목록', style: AppType.heading))),
            IconBtn(label: '읽기 목록에 책 추가', onPress: openPicker, child: const LucideIcon('Plus', size: 26)),
          ]),
        ),
        if (rest.isNotEmpty || restNoBook)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final id in rest) row(id), if (restNoBook) row(null)]),
          )
        else if (!hasRows)
          Padding(
            padding: const EdgeInsets.only(top: Space.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WordText('읽을 책을 골라 두고 눌러서 시간을 재요', style: AppType.sub),
              const SizedBox(height: Space.m),
              Btn(label: '책 추가', onPress: openPicker),
            ]),
          )
        else
          Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText('+로 읽을 책을 더 골라 둘 수 있어요', style: AppType.sub)),
      ],
    );
  }
}
