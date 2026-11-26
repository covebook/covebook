// 앱 틀: 하단 탭(책장 · 내 책 · 읽기 · 기록 · 통계). 지금 앱 app/(tabs)/_layout.tsx와 ui/tabBar.ts를 옮긴 뒤 2026-11-16 메뉴 구조 개편:
// 갈피는 기록 탭 안(갈피 | 감상)으로, 예전 기록 화면은 통계로, 내 정보는 책장 머리 프로필로 옮겼다. 커뮤니티는 이번에 하단에 넣지 않는다(코드는 그대로 둔다).
// 하단바는 화면 양옆·아래에서 띄운 흰 알약(옅은 그림자), 글자 없이 아이콘만: 고르지 않은 탭은 속이 빈 회색, 고른 탭은 검정으로 속이 찬 모양
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/library.dart';
import '../domain/reading.dart' show FinishDraft, withJosa;
import '../features/book/my_books_tab.dart' show MyBooksTab;
import '../features/community/community_screens.dart' show watchCommunityOpen;
import '../features/home/home_screen.dart';
import '../features/reading/read_list.dart';
import '../features/record/record_tab.dart' show RecordTab;
import '../features/stats/stats_screen.dart';
import '../features/stats/stats_widgets.dart' show bookTitle;
import '../services/ambient.dart';
import '../services/cover_colors.dart';
import '../services/error_text.dart';
import '../services/sync.dart';
import '../services/warmup.dart';
import '../store/finish_reading.dart' show resumeReading, saveDraftAsIs, settleLeftoverReading;
import '../store/bookcase_store.dart';
import '../store/library_model.dart';
import '../store/mini_timer_store.dart';
import '../store/reading_store.dart';
import '../store/settings_store.dart';
import '../ui/alert.dart';
import '../ui/feedback.dart' show showToast;
import '../ui/tab_icons.dart';
import '../ui/kit.dart' show Pressable;
import '../ui/theme.dart';
import 'app_nav.dart';
import 'idle_bars.dart';
import 'startup.dart';

const _app = MethodChannel('app.covebook/app');

/// 첫 책장이 끝내 다 그려졌다는 알림이 없어도 시작 덮개를 걷는 시각
const _coverLimit = Duration(seconds: 15);

/// 꾸미기 중 탭 바 숨기기(홈이 켠다)
final tabBarHidden = ValueNotifier<bool>(false);

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

  @override
  void initState() {
    super.initState();
    // 목표·소리 크기·장면 설정은 앱을 켤 때 읽는다(읽기 탭을 열기 전에 복구 창에서 이어 읽으면 기본값으로 보였다, 2026-11-15 QA 수아 F2)
    SettingsStore.instance.load();
    ReadingStore.instance.onInterrupted = _callCut;
    ReadingStore.instance.watchInterruptions();
    Ambient.instance.onExternal = _soundToggledOutside;
    if (_cover && shelfReady.value) _cover = false;
    if (_cover) {
      shelfReady.addListener(_shelfChanged);
      _coverTimer = Timer(_coverLimit, _dropCover);
    }
    // 지난 독서가 중간에 멈췄거나 멈춰 뒀거나 끝낸 기록을 저장하지 않았으면 다시 켰을 때 묻지 않고 거기까지 기록한다(2026-11-26)
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
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_settleLeftover()));
    }, onError: (_) {});
  }

  // 다른 화면에서 탭을 바꾸라고 했을 때
  void _nav() {
    final t = AppNav.instance.tab;
    if (t == null || !mounted) return;
    AppNav.instance.tab = null;
    _select(t);
  }

  void _select(int i) {
    setState(() {
      _index = i;
      _opened.add(i);
      MiniTimerPlace.instance.setTab(tabPaths[i]);
    });
    // 가만히 있으면 아래를 비우는 건 책장 탭만(다른 탭으로 가면 올리고 재지 않는다)
    i == AppTab.shelf ? IdleBars.instance.poke() : IdleBars.instance.stop();
  }

  void _shelfChanged() {
    if (shelfReady.value) _dropCover();
  }

  void _dropCover() {
    _coverTimer?.cancel();
    shelfReady.removeListener(_shelfChanged);
    startStep.value = 3;
    if (mounted && _cover) setState(() => _cover = false);
  }

  /// 통화 등으로 소리가 끊기면 묻지 않고 그 자리에서 독서를 끝내 그 책에 거기까지 기록한다(2026-11-26 사용자 '중간에 멈췄어요 이딴 거 넣지말고
  /// 그냥 바로 끊으라고 전화오면 없애고 그냥 해당 책에 끊긴거까지 기록해 자꾸 쳐묻지말고'. 전에는 끝난 뒤 '소리가 멈췄던 동안도 넣을까요?'를 물었다).
  /// 밖에서 소리가 먼저 멈춰 막 같이 멈춘 독서도 끊는다(멈춘 때까지). 읽기 장면은 닫아 시작한 화면으로, 토스트는 앱으로 돌아왔을 때 보인다
  /// (앱이 뒤에 있는 동안은 토스트 시간이 흐르지 않는다). 소리를 켜지 않고 읽으면 통화를 알 수 없어 그대로 잰다
  void _callCut(num at, {required bool running}) {
    final rs = ReadingStore.instance;
    final a = rs.active;
    if (a == null || !(running || _soundPaused == a.id)) return;
    _soundPaused = null;
    final d = rs.finish(running ? at : a.lastBeat);
    Ambient.instance.stop();
    if (d == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name != '/reading/session');
    final title = bookTitle(LibraryModel.instance.lib, d.myBookId);
    saveDraftAsIs(d).then((saved) {
      if (saved && mounted) showToast(context, '전화 등으로 끊겨서 ${title == null ? '' : '‘$title’ '}${withJosa(formatDurationPrecise(d.durationMs), '을', '를')} 기록했어요.');
    }, onError: (Object e) {
      if (mounted) appAlert(context, '독서 기록을 저장하지 못했어요', '기록은 읽기 탭에 남아 있어요. ${errorText(e)}');
    });
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
    IdleBars.instance.stop();
    AppNav.instance.removeListener(_nav);
    ReadingStore.instance.onInterrupted = null;
    shelfReady.removeListener(_shelfChanged);
    _coverTimer?.cancel();
    for (final c in _tabScroll) {
      c.dispose();
    }
    super.dispose();
  }

  /// 다시 켰을 때 남아 있던 독서는 묻지 않고 거기까지 기록하고 토스트로 알린다(2026-11-26 사용자 '멈춰 둔 독서가 있어요 이런 거 그냥 기록해'):
  /// 멈춰 둔 독서는 멈춘 때까지, 앱이 꺼져 멈춘 독서는 마지막으로 확인된 때까지, 끝내고 저장하지 않은 기록은 적어 둔 그대로(finish_reading settleLeftoverReading).
  /// 전에는 창 셋(저장하지 않은 독서 기록이 있어요 · 멈춰 둔 독서가 있어요 · 지난 독서가 중간에 멈췄어요)이 물었다.
  /// 저장하지 못하면 확인창(실패는 늘 알린다, DESIGN 11장). 그 기록은 읽기 탭 '저장하지 않은 독서 기록'에 남는다
  Future<void> _settleLeftover() async {
    final List<FinishDraft> saved;
    try {
      saved = await settleLeftoverReading();
    } catch (e) {
      if (mounted) appAlert(context, '지난 독서 기록을 저장하지 못했어요', '기록은 읽기 탭에 남아 있어요. ${errorText(e)}');
      return;
    }
    if (!mounted || saved.isEmpty) return;
    final d = saved.last;
    final title = bookTitle(LibraryModel.instance.lib, d.myBookId);
    showToast(
      context,
      saved.length > 1
          ? '지난 독서 기록 ${saved.length}개를 저장했어요.'
          : '지난 독서${title == null ? '' : ' ‘$title’'} ${withJosa(formatDurationPrecise(d.durationMs), '을', '를')} 기록했어요.',
    );
  }

  /// 알림 · 잠금 화면 · 이어폰 단추로 소리를 멈추거나 켜면 독서 타이머도 같이(앱 안에서는 타이머 일시정지가 소리도 멈춘다: pauseReading).
  /// 통화로 끊긴 소리는 _callCut이 독서를 끝낸다. 끊김 알림이 소리 멈춤보다 늦게 올 수 있어 잠깐 기다려 본다(그 사이 끊기면 여기서는 할 일이 없다)
  /// 밖에서 소리를 켜면 타이머는 밖에서 소리를 멈춰 멈춘 그 독서일 때만 이어 간다. 앱 안에서 멈춘 독서는 소리만 난다
  /// (2026-11-26 사용자 '읽은 적도 없는데 1:37이 떠 있어': 블루투스 · 이어폰 연결로 시스템이 소리를 다시 켜면 멈춰 둔 타이머가 저절로 돌았다)
  void _soundToggledOutside(bool playing) {
    final rs = ReadingStore.instance;
    if (playing) {
      final id = _soundPaused;
      _soundPaused = null;
      if (rs.active != null && rs.active!.id == id && !rs.running && !rs.stale) unawaited(resumeReading());
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (rs.running && !Ambient.instance.playing) {
        _soundPaused = rs.active?.id;
        rs.pause();
      }
    });
  }

  /// 밖에서 소리를 멈춰 같이 멈춘 독서(그 독서만 밖에서 소리를 켜면 이어 간다)
  String? _soundPaused;

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
          // 책장 탭에서 가만히 있으면(IdleBars) 아래로 미끄러져 내려간다. 내려간 동안은 누르기 · 화면 읽기에서 빠진다
          ListenableBuilder(
            listenable: Listenable.merge([tabBarHidden, IdleBars.instance]),
            builder: (context, _) => tabBarHidden.value || keyboard
                ? const SizedBox.shrink()
                : AnimatedPositioned(
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: TabBarStyle.side,
                    right: TabBarStyle.side,
                    bottom: IdleBars.instance.down ? -(TabBarStyle.height + TabBarStyle.gap * 4) : bottom + TabBarStyle.gap,
                    height: TabBarStyle.height,
                    child: IgnorePointer(
                    ignoring: IdleBars.instance.down,
                    child: ExcludeSemantics(
                    excluding: IdleBars.instance.down,
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
                            // 화면 읽기: 탭마다 이름 하나·버튼·고른 상태만(아이콘 그림이 섞여 '이미지'로 읽혔다, 2026-11-16 QA 영숙 F9·F11). 아래 글자는 같은 이름이라 읽지 않는다.
                            // 아이콘 아래 이름(2026-11-24 사용자 6단계): 글자 11, 색은 아이콘과 같게(고른 탭은 진하게). 큰 글씨는 1.3배까지.
                            // 크기는 토스증권 하단바 사진에 맞춤(같은 날): 알약 56 · 좌우 12 · 아이콘 22 · 아이콘과 이름 사이 4
                            for (var i = 0; i < _tabs.length; i++)
                              Expanded(child: TabBarItem(label: _tabs[i].label, icon: _tabs[i].icon, selected: i == _index, onTap: () => tap(i))),
                          ],
                        ),
                      ),
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

/// 하단 탭 하나: 아이콘과 그 아래 이름(2026-11-24 사용자 6단계: 글자 11, 색은 아이콘과 같게, 고른 탭은 진하게).
/// 알약 56 · 아이콘 22 · 사이 4(토스증권 하단바 사진 참고, 같은 날), 이름 글자 배율은 1.3배까지(큰 글씨에서도 알약을 넘지 않게).
/// 화면 읽기: 탭마다 이름 하나 · 버튼 · 고른 상태만(아이콘 그림이 섞여 '이미지'로 읽혔다, 2026-11-16 QA 영숙 F9·F11). 아래 글자는 같은 이름이라 따로 읽지 않는다
class TabBarItem extends StatelessWidget {
  const TabBarItem({super.key, required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final Widget Function(Color color, bool filled) icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.tabInk : AppColors.tabInkSoft;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      // 누르는 동안 옅어짐(다른 아이콘 단추와 같은 Pressable, 2026-11-19 규칙: 탭만 표시가 없었다)
      child: Pressable(
        onPress: onTap,
        child: SizedBox.expand(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            icon(color, selected),
            const SizedBox(height: TabBarStyle.labelGap),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: TabBarStyle.labelScaleMax,
              child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: AppType.tabLabel.copyWith(color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}
