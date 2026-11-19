// 앱 틀: 하단 탭(책장 · 내 책 · 읽기 · 기록 · 통계). 지금 앱 app/(tabs)/_layout.tsx와 ui/tabBar.ts를 옮긴 뒤 2026-11-16 메뉴 구조 개편:
// 갈피는 기록 탭 안(갈피 | 감상)으로, 예전 기록 화면은 통계로, 내 정보는 책장 머리 프로필로 옮겼다. 커뮤니티는 이번에 하단에 넣지 않는다(코드는 그대로 둔다).
// 하단바는 화면 양옆·아래에서 띄운 흰 알약(옅은 그림자), 글자 없이 아이콘만: 고르지 않은 탭은 속이 빈 회색, 고른 탭은 검정으로 속이 찬 모양
library;

import '../features/reading/start_book.dart' show resumeReadingOrTell;
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/library.dart';
import '../domain/reading.dart' show askGapMs, withJosa;
import '../features/book/my_books_tab.dart' show MyBooksTab;
import '../features/community/community_screens.dart' show watchCommunityOpen;
import '../features/home/home_screen.dart';
import '../features/reading/finish_screen.dart';
import '../features/reading/read_list.dart';
import '../features/reading/reading_screen.dart';
import '../features/record/record_tab.dart' show RecordTab;
import '../features/book/labels.dart' show dateTimeLabel, relativeDay;
import '../features/stats/stats_screen.dart';
import '../features/stats/stats_widgets.dart' show bookTitle;
import '../services/ambient.dart';
import '../services/cover_colors.dart';
import '../services/sync.dart';
import '../services/warmup.dart';
import '../store/bookcase_store.dart';
import '../store/library_model.dart';
import '../store/mini_timer_store.dart';
import '../store/reading_store.dart';
import '../store/settings_store.dart';
import '../ui/alert.dart';
import '../ui/tab_icons.dart';
import '../ui/kit.dart' show Pressable;
import '../ui/theme.dart';
import 'app_nav.dart';
import 'startup.dart';

const _app = MethodChannel('app.covebook/app');

/// 첫 책장이 끝내 다 그려졌다는 알림이 없어도 시작 덮개를 걷는 시각
const _coverLimit = Duration(seconds: 15);

/// 꾸미기 중 탭 바 숨기기(홈이 켠다)
final tabBarHidden = ValueNotifier<bool>(false);

/// 이보다 오래 꺼져 있었던 독서는 꺼진 시간을 넣을지 묻지 않고 뺀다
const longGapMs = 3 * 60 * 60 * 1000;

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

typedef _TabIcon = Widget Function(Color color, bool filled);

class _Tab {
  const _Tab(this.label, this.icon, this.build);
  final String label;
  final _TabIcon icon;
  final WidgetBuilder build;
}

final _tabs = <_Tab>[
  _Tab('책장', (c, f) => shelfIcon(c, size: TabBarStyle.icon, filled: f), (_) => const HomeScreen()),
  _Tab('내 책', (c, f) => myBooksTabIcon(c, AppColors.bg, size: TabBarStyle.icon, filled: f), (_) => const MyBooksTab()),
  _Tab('읽기', (c, f) => readTabIcon(c, AppColors.bg, size: TabBarStyle.icon, filled: f), (_) => const ReadList()),
  _Tab('기록', (c, f) => bookmarkTabIcon(c, size: TabBarStyle.icon, filled: f), (_) => const RecordTab()),
  _Tab('통계', (c, f) => recordTabIcon(c, AppColors.bg, size: TabBarStyle.icon, filled: f), (_) => const StatsScreen()),
];

/// 탭마다 경로(작은 타이머 자리·숨김을 정한다, mini_timer.dart 탭 목록과 같게)
const tabPaths = ['/', '/books', '/read', '/records', '/stats'];

/// 시험 빌드 전용: --dart-define=QA_SEED_YEAR=2025로 빌드하면 켤 때 지금 책장을 그해 책장으로 남긴다(지난 책장 화면 확인용)
const _qaSeedYear = int.fromEnvironment('QA_SEED_YEAR');

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// 탭마다 첫 화면 스크롤(탭을 다시 누르면 맨 위로, docs/design/DESIGN.md 10장)
  final _tabScroll = [for (var i = 0; i < 5; i++) ScrollController()];

  void _toTop(int i) {
    final c = _tabScroll[i];
    if (!c.hasClients) return;
    final s = SettingsStore.instance;
    final still = s.reduceMotion == 'on' || (s.reduceMotion == 'system' && MediaQuery.disableAnimationsOf(context));
    if (still) {
      c.jumpTo(0);
    } else {
      c.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  /// 한 번 연 탭은 살려 둔다(책장 그림·굽기를 다시 하지 않게)
  final _opened = <int>{0};

  /// 시작 덮개(지난 책장 사진이 없을 때 첫 책장이 다 그려질 때까지)
  bool _cover = !startedWithSnapshot;
  Timer? _coverTimer;
  bool _spanAsking = false;

  @override
  void initState() {
    super.initState();
    // 목표·소리 크기·장면 설정은 앱을 켤 때 읽는다(읽기 탭을 열기 전에 복구 창에서 이어 읽으면 기본값으로 보였다, 2026-11-15 QA 수아 F2)
    SettingsStore.instance.load();
    ReadingStore.instance.addListener(_readingChanged);
    ReadingStore.instance.watchInterruptions();
    if (_cover && shelfReady.value) _cover = false;
    if (_cover) {
      shelfReady.addListener(_shelfChanged);
      _coverTimer = Timer(_coverLimit, _dropCover);
    }
    // 지난 독서가 중간에 멈췄거나 끝낸 기록을 저장하지 않았으면 다시 켰을 때 묻는다(지금 앱 RecoveryDialog)
    AppNav.instance.addListener(_nav);
    final reading = ReadingStore.instance;
    // 서재는 첫 화면이 뜬 뒤 미리 읽어 둔다(복구 창·다른 탭이 책을 바로 찾게)
    // 책장이 뜬 뒤 쉬는 동안 나중에 처음 쓰는 큰 글꼴을 미리 읽는다(기록 탭 첫 진입 멈춤, services/warmup.dart)
    warmFontsLater();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LibraryModel.instance.load();
      // 해가 바뀌었으면 그해 책장을 남긴다(다른 저장보다 먼저: 새해에 먼저 고치면 마지막으로 손댄 해가 올해가 되어 지난해가 안 남는다).
      // 시험 빌드(QA_SEED_YEAR)는 지금 책장을 그 해 책장으로 남긴다
      final books = BookcaseStore.instance;
      final first = _qaSeedYear > 0 ? books.seedYear(_qaSeedYear) : books.checkYear();
      first.catchError((Object e) {
        // ignore: avoid_print
        print('연도 책장 확인 실패 $e');
        return null;
      }).whenComplete(() {
        books.watch();
        // 서버 동기화(서버 주소가 있는 빌드만): 연도 책장 확인 뒤에 시작한다(받는 도중의 서재로 한 해를 남기지 않게)
        SyncService.instance.start();
        watchCommunityOpen();
        // 표지 색·두께·갈피 색 맞추기는 켠 뒤 조금 있다 뒤에서(지금 앱 _layout: 3초 뒤)
        Future<void>.delayed(const Duration(seconds: 3), () => backfillCoverColors().catchError((Object e) {
              // ignore: avoid_print
              print('표지 색 맞추기 실패(다음 시작 때 다시) $e');
            }));
      });
    });
    reading.load().then((_) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _askRecovery());
    }, onError: (_) {});
  }

  // 다른 화면에서 탭을 바꾸라고 했을 때
  void _nav() {
    final t = AppNav.instance.tab;
    if (t == null || !mounted) return;
    AppNav.instance.tab = null;
    _select(t);
  }

  void _select(int i) => setState(() {
        _index = i;
        _opened.add(i);
        MiniTimerPlace.instance.setTab(tabPaths[i]);
      });

  void _shelfChanged() {
    if (shelfReady.value) _dropCover();
  }

  void _dropCover() {
    _coverTimer?.cancel();
    shelfReady.removeListener(_shelfChanged);
    startStep.value = 3;
    if (mounted && _cover) setState(() => _cover = false);
  }

  // 통화 등으로 소리가 끊긴 동안을 넣을지(사용자 결정 2026-11-15 '물어보기'). 타이머는 그동안에도 흘렀다
  void _readingChanged() {
    final g = ReadingStore.instance.spanGap;
    if (g == null || _spanAsking || !mounted) return;
    _spanAsking = true;
    final span = formatDuration(g.counted);
    appAlert(context, '소리가 멈췄던 동안도 넣을까요?', '통화 등으로 소리가 $span 동안 멈췄어요. 그동안도 읽은 시간에 넣을까요?', [
      AlertButton('빼기', onPress: () => ReadingStore.instance.answerSpan(include: false)),
      AlertButton('넣기', onPress: () => ReadingStore.instance.answerSpan(include: true)),
    ], false).whenComplete(() => _spanAsking = false);
  }

  // 맨 아래 화면에서 뒤로 키: 다른 탭이면 책장 탭으로, 책장 탭이면 앱을 끝내지 않고 뒤로 보낸다
  // (끝내면 다시 열 때 엔진이 새로 떠 읽던 독서가 '중간에 멈췄어요'로 바뀌고 시간이 빠졌다, 2026-11-15 QA 민혁 F1·F2). 꾸미기 중이면 홈이 꾸미기를 끝낸다
  void _back() {
    if (tabBarHidden.value) return;
    if (_index != AppTab.shelf) {
      _select(AppTab.shelf);
      return;
    }
    if (Platform.isAndroid) {
      _app.invokeMethod<bool>('moveToBack').catchError((_) => SystemNavigator.pop().then((_) => false));
    }
  }

  @override
  void dispose() {
    AppNav.instance.removeListener(_nav);
    ReadingStore.instance.removeListener(_readingChanged);
    shelfReady.removeListener(_shelfChanged);
    _coverTimer?.cancel();
    for (final c in _tabScroll) {
      c.dispose();
    }
    super.dispose();
  }

  void _askRecovery() {
    final reading = ReadingStore.instance;
    final it = reading.interrupted;
    final pending = reading.pending;
    if (it == null && pending != null && reading.pendingRestored) {
      appAlert(context, '저장하지 않은 독서 기록이 있어요', '지난번에 끝낸 ${formatDuration(pending.durationMs)} 기록을 아직 저장하거나 버리지 않았어요.', [
        AlertButton('기록 확인하기', onPress: () {
          reading.ackPendingRestored();
          openFinish(context);
        }),
        AlertButton('나중에', style: AlertStyle.cancel, onPress: reading.ackPendingRestored),
      ], true, true);
      return;
    }
    if (it == null && reading.stale && reading.active != null) {
      final a = reading.active!;
      final title = bookTitle(LibraryModel.instance.lib, a.myBookId);
      // 달력 날짜로(12~24시간 전 어제를 '오늘'로 적었다, 점검 B12). 앱 공통 가까운 날 글자(relativeDay)
      final when = relativeDay(DateTime.fromMillisecondsSinceEpoch(a.lastBeat.toInt()));
      appAlert(
        context,
        '멈춰 둔 독서가 있어요',
        '$when ${title == null ? '' : '${withJosa('‘$title’', '을', '를')} '}${formatDuration(a.accumulatedMs)} 읽다가 멈춰 뒀어요.',
        [
          AlertButton('이어서 읽기', onPress: () async {
            reading.clearStale();
            if (!await resumeReadingOrTell(context) || !mounted) return;
            // 이어 읽으면 소리도 함께(복구 창 이어 읽기와 같게, 점검 B14)
            Ambient.instance.resumeIfWanted();
            openReadingScene(context);
          }),
          AlertButton('여기서 끝내고 기록하기', onPress: () {
            reading.clearStale();
            reading.finish();
            openFinish(context);
          }),
          // 지우는 일은 확인을 거친다(DESIGN 12장, 독서 끝 '이번 독서 기록을 버릴까요?'와 같은 창)
          AlertButton('기록 버리기', style: AlertStyle.destructive, onPress: () {
            appAlert(context, '이번 독서 기록을 버릴까요?', '${withJosa(formatDuration(a.accumulatedMs), '이', '가')} 저장되지 않아요.', [
              const AlertButton('취소', style: AlertStyle.cancel),
              AlertButton('버리기', style: AlertStyle.destructive, onPress: () => reading.discardActive()),
            ]);
          }),
          // 다른 복구 창처럼 미룰 수 있게: 멈춘 채로 두고(작은 타이머) 다시 묻지 않는다
          AlertButton('나중에', style: AlertStyle.cancel, onPress: reading.clearStale),
        ],
        true,
        true,
      );
      return;
    }
    if (it == null) return;
    // 날과 시각: 며칠 꺼져 있었어도 언제인지 보이게('어제 오후 9:05', DESIGN 4장 dateTimeLabel)
    final hm = dateTimeLabel(DateTime.fromMillisecondsSinceEpoch(it.lastBeat.toInt()));
    // 1분 미만 꺼졌던 것은 묻지 않고 넣는다(읽던 중일 가능성이 크다)
    if (it.gapMs < askGapMs) {
      _askContinue(true, '지난 독서가 중간에 멈췄어요', '앱이 잠깐(1분 미만) 꺼져 있었어요. 그 시간도 읽은 시간에 넣었어요.');
      return;
    }
    // 오래(3시간 넘게) 꺼져 있었으면 그 시간은 묻지 않고 뺀다(2026-11-19 타이머 점검 B8: 사흘 꺼져 있다 '넣기'면 72시간 기록이 됐다)
    if (it.gapMs >= longGapMs) {
      _askContinue(false, '지난 독서가 중간에 멈췄어요',
          '앱이 ${formatDuration(it.gapMs)} 꺼져 있어서 그 시간은 뺐어요. 마지막으로 확인된 $hm까지 ${withJosa(formatDuration(it.countedMs), '을', '를')} 읽었어요.');
      return;
    }
    // 꺼져 있던 시간을 넣을지 먼저 묻는다(사용자 결정 2026-11-15 '물어보기'). 넣거나 빼도 안내창이 떠 있던 동안은 읽은 시간에 들어간다
    appAlert(
      context,
      '지난 독서가 중간에 멈췄어요',
      '마지막으로 확인된 $hm까지 ${withJosa(formatDuration(it.countedMs), '을', '를')} 읽었어요. 앱이 꺼져 있던 ${formatDuration(it.gapMs)}도 읽은 시간에 넣을까요?',
      [
        AlertButton('넣기', onPress: () => _askContinue(true)),
        AlertButton('빼기', onPress: () => _askContinue(false)),
        AlertButton('나중에 정하기(일시정지로 둠)', style: AlertStyle.cancel, onPress: reading.dismissInterrupted),
      ],
      true,
      true,
    );
  }

  /// 꺼져 있던 시간을 정한 뒤: 이어 읽기 · 여기서 끝내기 · 나중에
  void _askContinue(bool includeGap, [String? title, String? message]) {
    final reading = ReadingStore.instance;
    final it = reading.interrupted;
    if (it == null || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final total = it.countedMs + (includeGap ? now - it.lastBeat : now - it.reopenAt);
    appAlert(
      context,
      title ?? '이어서 읽을까요?',
      message ?? '지금까지 ${withJosa(formatDuration(total), '을', '를')} 읽었어요.',
      [
        AlertButton('이어서 읽기', onPress: () {
          reading.resumeInterrupted(includeGap: includeGap);
          // 소리를 켜 둔 채 꺼졌으면 다시 켠다(이어 읽기 뒤 빗소리가 꺼져 있었다, 2026-11-15 QA 수아 F2)
          Ambient.instance.resumeIfWanted();
          openReadingScene(context);
        }),
        AlertButton('여기서 끝내고 기록하기', onPress: () {
          reading.finishInterrupted(includeGap: includeGap);
          openFinish(context);
        }),
        AlertButton('나중에 정하기(일시정지로 둠)', style: AlertStyle.cancel, onPress: reading.dismissInterrupted),
      ],
      true,
      true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    // 키보드가 열려 있으면 탭 바를 숨긴다: 탭 화면은 Scaffold가 키보드 위로 줄이므로 탭 바가 키보드 바로 위에 떠서 입력하는 내용을 가렸다(2026-11-16 QA 키보드 F1 묶음)
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    void tap(int i) {
      if (AppNav.instance.tabsBlocked) return;
      // 보고 있는 탭을 다시 누르면 그 탭 첫 화면 맨 위로(2026-11-19 규칙: 아무 일도 없었다)
      if (i == _index) return _toTop(i);
      _select(i);
    }

    // 키보드가 오르내리는 동안 숨은 탭(특히 책장)이 매 프레임 다시 배치되지 않게(2026-11-18 측정: 키보드 프레임마다 책장 배치 43ms).
    // 예전에는 Scaffold가 몸통을 키보드만큼 줄여 IndexedStack의 모든 탭이 매 프레임 다시 배치됐다. 이제 몸통 크기는 그대로 두고
    // 보이는 탭(이 화면이 맨 위일 때만)에만 키보드 높이를 넘겨 그 탭의 화면 틀(Screen)이 스스로 비킨다. 숨은 탭과 다른 화면에 덮인 탭은
    // 키보드 높이 0을 받아(같은 값이라 알림도 없다) 다시 만들거나 배치하지 않는다
    final mq = MediaQuery.of(context);
    final noKeyboard = mq.removeViewInsets(removeBottom: true);
    final front = ModalRoute.isCurrentOf(context) ?? true;
    final shell = Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                MediaQuery(
                  data: i == _index && front ? mq : noKeyboard,
                  child: _opened.contains(i) ? PrimaryScrollController(controller: _tabScroll[i], child: _tabs[i].build(context)) : const SizedBox.shrink(),
                ),
            ],
          ),
          ValueListenableBuilder<bool>(
            valueListenable: tabBarHidden,
            builder: (context, hidden, _) => hidden || keyboard
                ? const SizedBox.shrink()
                : Positioned(
                    left: TabBarStyle.side,
                    right: TabBarStyle.side,
                    bottom: bottom + TabBarStyle.gap,
                    height: TabBarStyle.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(TabBarStyle.height / 2),
                        boxShadow: const [TabBarStyle.shadow],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: TabBarStyle.paddingX),
                        child: Row(
                          children: [
                            // 화면 읽기: 탭마다 이름 하나·버튼·고른 상태만(아이콘 그림이 섞여 '이미지'로 읽혔다, 2026-11-16 QA 영숙 F9·F11). 탭 아래 글자는 두지 않는다(메뉴 개편: 아이콘 중심)
                            for (var i = 0; i < _tabs.length; i++)
                              Expanded(
                                child: Semantics(
                                  container: true,
                                  button: true,
                                  selected: i == _index,
                                  label: _tabs[i].label,
                                  onTap: () => tap(i),
                                  excludeSemantics: true,
                                  // 누르는 동안 옅어짐(다른 아이콘 단추와 같은 Pressable, 2026-11-19 규칙: 탭만 표시가 없었다)
                                  child: Pressable(
                                    onPress: () => tap(i),
                                    child: SizedBox.expand(child: Center(child: _tabs[i].icon(i == _index ? AppColors.tabInk : AppColors.tabInkSoft, i == _index))),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          // 시작 덮개: 지난 책장 사진이 없으면 첫 책장이 다 그려질 때까지 시작 그림(앱 준비 때와 같은 그림)을 덮어 둔다
          if (_cover) const Positioned.fill(child: StartCover()),
        ],
      ),
    );
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) => didPop ? null : _back(), child: shell);
  }
}
