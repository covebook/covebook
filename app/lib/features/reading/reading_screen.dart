// 독서 실행 화면(지금 앱 features/reading/ReadingScreen.tsx): 장면이 화면 가득, 바로 아래에 [스피커 · 밝은 시간 · 재생·일시정지]와 장면 점.
// 2026-11-27 사용자 시안 '읽기 누르면 왼쪽처럼 바로 밑에 있는 걸로': 열면 접은 모습이 기본(전에는 아래 흰 조작부가 펼쳐져 열렸다).
// 위 줄은 왼쪽 ⌄(나가기: 타이머는 계속, 오른쪽 아래 작은 타이머) · 오른쪽 읽는 책 이름(누르면 책 바꾸기). 끝내기는 일시정지해 나온 읽기 탭 카드 아래.
// 시간을 누르면 흰 조작부(연결된 책 · 시간 · [분위기 | 재생/일시정지 | 목표])가 열린다. 분위기 = 장면+환경음 한 세트.
// 정지(❚❚)를 누르면 독서를 끝내 묻지 않고 그 책에 거기까지 기록하고 이 화면을 닫아 시작한 화면으로 돌아간다(토스트). 2026-11-27 사용자 '그냥 정지 누르면 끝나는 거라니까'.
// 전에는 일시정지하고 나와 작은 타이머 · 읽기 탭에서 이어 읽었다(2026-11-24). 쪽 · 메모는 독서 기록 수정에서 적는다.
// 스피커를 누르면 그 줄 위에 왼쪽부터 차는 소리 막대가 열리고, 한 번 더 누르거나 막대를 맨 왼쪽까지 내리면 음소거.
// 장면은 옆으로 넘겨 고른다(손가락을 따라 다음 장면이 밀려 들어오고, 놓으면 그 장면 · 소리. 아래 점이 지금 장면). 소리만 듣기(soundOnly)는 타이머 없이 소리만: 독서 시간으로 기록하지 않는다
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../services/ambient.dart';
import '../../store/finish_reading.dart' show saveDraftAsIs;
import '../../ui/alert.dart' show appAlert;
import '../../ui/feedback.dart' show errorText;
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../store/settings_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/book_picker.dart';
import '../stats/stats_widgets.dart';
import 'finish_screen.dart';
import 'play_icons.dart';
import 'start_book.dart' show resumeReadingOrTell, startNewReading;
import 'switch_book.dart';

const _light = NightColors.ink;

/// 장면 위 단추는 겉모양(44)은 그대로 두고 누르는 자리만 48로 넓혔다(2026-11-19 공통 규칙). 넓힌 반쪽(2)만큼 둘레 여백을 줄여 자리를 지킨다
const _hitPad = (Space.hit - Space.touch) / 2;

/// 시간 아래 한 줄(caption 15/21)의 지금 글자 배율 높이
double _captionLine(BuildContext context) => MediaQuery.textScalerOf(context).scale(15) * 21 / 15;

/// 시트가 열릴 때 이 칸이 접힌 아래(또는 위)에 있으면 보이게 넘긴다(고른 칸 보이기)
class ShowWhenOpened extends StatefulWidget {
  const ShowWhenOpened({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<ShowWhenOpened> createState() => _ShowWhenOpenedState();
}

class _ShowWhenOpenedState extends State<ShowWhenOpened> {
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    // 시트가 올라오는 동안에도 자리는 정해져 있다: 첫 틀을 그린 뒤 넘긴다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Scrollable.maybeOf(context) != null) Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const _goals = [15, 30, 60];

/// 조작부 책 표지 폭과 가운데 재생 단추 지름(2026-11-18 시안 대조: 화면 폭의 11.4% · 18.4%)
const _coverW = 47.0;
const _roundD = 76.0;
const _shade = [Shadow(color: NightColors.shade, offset: Offset(0, 1), blurRadius: 6)];

const scenePosters = {'rain': 'assets/scenes/rain-window-poster.jpg', 'fire': 'assets/scenes/fireplace-poster.jpg'};
const _videos = {'rain': 'assets/scenes/rain-window.mp4', 'fire': 'assets/scenes/fireplace.mp4'};

/// 장면 화면 열기(앱 맨 위에 꽉 차게)
Future<void> openReadingScene(BuildContext context, {String? bookId, bool soundOnly = false}) =>
    Navigator.of(context, rootNavigator: true).push(readingSceneRoute(bookId: bookId, soundOnly: soundOnly));

/// 장면 화면 경로(화면을 닫은 뒤 뿌리 내비게이터로 열 때도 쓴다)
Route<void> readingSceneRoute({String? bookId, bool soundOnly = false}) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/reading/session'),
      builder: (_) => ReadingScreen(initialBookId: bookId, soundOnly: soundOnly),
    );

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, this.initialBookId, this.soundOnly = false});
  final String? initialBookId;
  final bool soundOnly;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> with WidgetsBindingObserver {
  final _lib = LibraryModel.instance;
  final _reading = ReadingStore.instance;
  final _settings = SettingsStore.instance;
  final _audio = Ambient.instance;
  /// 흰 조작부가 열렸나(소리만 듣기는 '지금부터 독서 기록' 단추가 있어 열고 시작)
  late bool _open = widget.soundOnly;
  bool _volOpen = false;
  double? _dragVolume;
  String? _draftBookId;
  bool _appActive = true;
  double _panelHeight = 310;
  final _panelKey = GlobalKey();
  final _rowKey = GlobalKey();
  double _rowW = 0;

  /// 장면 넘기기: 끝없이 돈다(마지막 다음은 처음). 쪽 번호 % 장면 수 = 장면
  late final PageController _pager = PageController(initialPage: scenes.length * 500 + _sceneIndex);
  int get _sceneIndex => math.max(0, scenes.indexWhere((x) => x.id == _settings.scene));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draftBookId = widget.initialBookId;
    for (final n in [_lib, _reading, _settings, _audio]) {
      n.addListener(_changed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final n in [_lib, _reading, _settings, _audio]) {
      n.removeListener(_changed);
    }
    _pager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => setState(() => _appActive = state == AppLifecycleState.resumed);

  void _changed() {
    if (!mounted) return;
    // 재는 것이 없어도 접은 모습 그대로(재생 단추가 읽기 시작이다). 전에는 조작부를 펼쳤다
    setState(() {});
  }

  Library get lib => _lib.lib;
  String? get _bookId {
    final a = _reading.active;
    final id = a != null ? a.myBookId : _draftBookId;
    return id != null && lib.books[id] != null ? id : null;
  }

  // 읽는 중에 다른 책을 골랐을 때: '이 기록의 책 정정'과 '다른 책 읽기 시작'을 나눈다
  // 고르자마자 조작부에 그 책을 보인다(바꾸는 규칙은 읽기 탭 · 책 정보와 하나, switch_book)
  void _askSwitch(String? nextId) => switchReadingBook(context, nextId, chosen: () => setState(() => _draftBookId = nextId));

  /// 이 화면에서 읽는 중인데 소리가 꺼져 있다(앱이 꺼졌다 켜진 뒤 등): 화면도 꺼짐으로 보인다(2026-11-15 QA 수아 F2)
  bool get _soundOff => !widget.soundOnly && _reading.active != null && !_audio.playing;

  void _leave() => Navigator.of(context).maybePop();

  void _start() {
    if (_reading.active != null || _reading.pending != null) {
      if (_reading.pending != null) openFinish(context);
      return;
    }
    startNewReading(_draftBookId != null && lib.books[_draftBookId] != null ? _draftBookId : null);
  }

  bool get _playing => widget.soundOnly ? _audio.playing : _reading.running;

  void _playPause() {
    if (widget.soundOnly) {
      _audio.playing ? _audio.pause() : _audio.play(_settings.scene);
    } else if (_reading.active == null) {
      _start();
    } else if (_reading.running) {
      _stop();
    } else {
      unawaited(resumeReadingOrTell(context));
    }
  }

  /// 정지 = 독서 끝(2026-11-27 사용자 '그냥 정지 누르면 끝나는 거라니까?'): 끝내고 소리를 멈추고 장면을 닫은 뒤, 묻지 않고 그 책에 거기까지 기록한다
  /// (독서 끝 화면에서 뒤로 · 통화로 끊길 때와 같은 저장, saveDraftAsIs). 시작한 화면에 토스트. 1초가 안 되면 남길 것이 없어 지운다.
  /// 펼친 조작부 · 접은 조작부의 단추가 같다
  void _stop() {
    final d = _reading.finish();
    _audio.stop();
    final nav = Navigator.of(context);
    _leave();
    if (d == null) return;
    saveDraftAsIs(d).then((saved) {
      if (saved && nav.mounted) showReadSaved(nav, d);
    }, onError: (Object e) {
      if (nav.mounted) appAlert(nav.context, '독서 기록을 저장하지 못했어요', '기록은 읽기 탭에 남아 있어요. ${errorText(e)}');
    });
  }

  // 장면 고르기: 배경과 환경음이 함께 바뀐다(소리가 나는 중이면 새 장면 소리로 바로 바꾼다). 넘기기가 아닌 곳(분위기 시트 · 화면 읽기)에서 고르면 그 쪽으로 넘긴다
  void _chooseScene(String id, {bool fromPager = false}) {
    if (id == _settings.scene) return;
    _settings.set({'scene': id});
    if (_audio.playing) _audio.play(id);
    if (!fromPager && _pager.hasClients) {
      final cur = (_pager.page ?? _pager.initialPage.toDouble()).round();
      _pager.jumpToPage(cur - cur % scenes.length + _sceneIndex);
    }
  }

  /// 넘기기가 멈췄다: 멈춘 쪽의 장면으로
  void _settleScene() {
    final p = _pager.hasClients ? _pager.page : null;
    if (p == null) return;
    _chooseScene(scenes[p.round() % scenes.length].id, fromPager: true);
  }

  void _stepScene(int dir) {
    if (!_pager.hasClients) return;
    final cur = (_pager.page ?? _pager.initialPage.toDouble()).round();
    _pager.animateToPage(cur + dir, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  // 스피커: 닫혀 있으면 막대를 연다(음소거였으면 소리를 켠다), 열려 있으면 음소거하고 닫는다. 소리가 꺼져 있으면 켠다
  void _tapSpeaker() {
    if (_soundOff) {
      if (_settings.muted) _settings.set({'muted': false});
      _audio.play(_settings.scene);
      return;
    }
    if (!_volOpen) {
      if (_settings.muted) _settings.set({'muted': false});
      setState(() => _volOpen = true);
    } else {
      _settings.set({'muted': true});
      setState(() => _volOpen = false);
    }
  }

  String get _volumeText => _settings.muted && _dragVolume == null ? '음소거' : '${((_dragVolume ?? _settings.volume) * 100).round()}%';
  // 일시정지에서 이어 가는 것은 '이어서 읽기'('다시 읽기'는 완독한 책 재독에만, DESIGN 9장), 시작은 앱 공통 '읽기 시작'
  String get _playLabel => widget.soundOnly
      ? (_audio.playing ? '소리 멈추기' : '소리 재생')
      : _reading.active == null
          ? '읽기 시작'
          : _reading.running
              ? '독서 끝내기'
              : '이어서 읽기';

  Future<void> _pickBook() async {
    // 지금 책(없으면 책 없이 읽기)은 고르는 원으로 보인다(DESIGN 13장 current)
    final a0 = _reading.active;
    // 책을 기록에 잇는 고르기는 모두 '+ 새 책 등록'(2026-11-21 사용자 '여기는 왜 책 추가 없어')
    final r = await pickBook(context, lib, allowNone: true, addNew: true, current: (id: a0 != null ? a0.myBookId : _draftBookId));
    if (!r.picked || !mounted) return;
    final a = _reading.active;
    if (a != null && a.myBookId != r.id) {
      _askSwitch(r.id);
    } else {
      setState(() => _draftBookId = r.id);
    }
  }

  void _goalSheet() => showSheet<void>(
        context,
        title: '목표 시간',
        description: '목표를 바꿔도 읽은 시간은 유지돼요.',
        scroll: true,
        maxHeight: 0.85,
        builder: (ctx) {
          void pick(int? min) {
            _settings.set({'goalMin': min});
            Navigator.pop(ctx);
          }

          final big = MediaQuery.textScalerOf(ctx).scale(10) >= 16 || MediaQuery.sizeOf(ctx).width < 330;
          final goal = _settings.goalMin;
          final tiles = [for (final m in _goals) ShowWhenOpened(enabled: goal == m, child: Choice(label: '$m분', compact: !big, selected: goal == m, onPress: () => pick(m)))];
          // 직접 정하기(2026-11-16 사용자 '사용자가 시간 지정은 못 하나'): 15·30·60분 밖의 목표면 이 칸이 골라진 상태로 그 시간을 보인다
          final custom = goal != null && !_goals.contains(goal);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            // 목표가 없는 상태는 조작부 칸 · 화면 읽기와 같은 말 '목표 없음'
            Choice(label: '목표 없음', selected: goal == null, onPress: () => pick(null)),
            const SizedBox(height: Space.s),
            if (big)
              for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(height: Space.s), t]
            else
              Row(children: [for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(width: Space.s), Expanded(child: t)]]),
            const SizedBox(height: Space.s),
            // 고른 칸이 접힌 아래에 있으면 시트를 열 때 그리로 넘긴다(2026-11-16 QA 영숙 F18: 2.0배에서 '직접 정하기 · 10분'이 안 보였다)
            ShowWhenOpened(
              enabled: custom,
              child: Choice(
                label: custom ? '직접 정하기$metaSep${minutesLabel(goal)}' : '직접 정하기',
                selected: custom,
                onPress: () async {
                  Navigator.pop(ctx);
                  final m = await showMinutesSheet(context, title: '목표 시간', description: '목표를 바꿔도 읽은 시간은 유지돼요.', initial: (goal ?? 45).round());
                  if (m != null) _settings.set({'goalMin': m});
                },
              ),
            ),
          ]);
        },
      );

  // 분위기 시트: 장면 칸 두 개 · 소리 크기 · 소리 켜고 끄기(긴 시트를 칸 · 소리 크기 · 소리 묶음으로 나눴다, 화면은 그대로)
  void _moodSheet() => showSheet<void>(
        context,
        title: '분위기',
        description: '장면과 소리가 함께 바뀌어요.',
        scroll: true,
        maxHeight: 0.88,
        builder: (ctx) => ListenableBuilder(
          listenable: Listenable.merge([_settings, _audio, _reading]),
          builder: (ctx, _) {
            final size = MediaQuery.sizeOf(ctx);
            final oneColumn = size.width < 340 || MediaQuery.textScalerOf(ctx).scale(10) >= 15;
            final tileW = oneColumn ? size.width - 2 * Space.page : (size.width - 2 * Space.page - Space.m) / 2;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              if (oneColumn)
                for (final (i, sc) in scenes.indexed) ...[if (i > 0) const SizedBox(height: Space.m), _sceneTile(sc, tileW, oneColumn)]
              else
                Row(children: [for (final (i, sc) in scenes.indexed) ...[if (i > 0) const SizedBox(width: Space.m), _sceneTile(sc, tileW, oneColumn)]]),
              ..._volumeRows(),
              _soundGroup(ctx, _reading.active != null),
            ]);
          },
        ),
      );

  /// 분위기 장면 칸(포스터 + 이름, 고르면 갈색 테두리와 고르는 원)
  Widget _sceneTile(SceneInfo sc, double tileW, bool oneColumn) {
    final on = _settings.scene == sc.id;
    final posterW = tileW - 16 - 3;
    // 화면 읽기는 칸 이름 한 번(안쪽 같은 이름 글자는 뺀다)
    return Semantics(
      selected: on,
      button: true,
      label: sceneName(sc.id),
      onTap: () => _chooseScene(sc.id),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _chooseScene(sc.id),
        child: Container(
          width: tileW,
          padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.m),
          decoration: BoxDecoration(
            color: AppColors.bg,
            // 고르는 큰 칸 모서리(Choice와 같은 14)
            borderRadius: BorderRadius.circular(Shape.choice),
            border: Border.all(color: on ? AppColors.accent : AppColors.line, width: 1.5),
          ),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(scenePosters[sc.id]!, width: posterW, height: (posterW / (oneColumn ? 2 : 4 / 3)).roundToDouble(), fit: BoxFit.cover),
              ),
              Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(sceneName(sc.id), style: AppType.button)),
            ]),
            // 고른 칸 표시는 앱 공통 고르는 원(RadioMark, 2026-11-19 공통 규칙: 같은 원을 체크 13으로 따로 그렸다)
            if (on) const Positioned(top: 14 - Space.s - 1.5, right: 14 - Space.s - 1.5, child: RadioMark(on: true)),
          ]),
        ),
      ),
    );
  }

  /// 소리 크기: 이름과 % 한 줄, 아래 음소거 원 + 막대.
  /// 이름은 시트 안 묶음 이름(SheetLabel과 같은 rowStrong · 머리 · 아래 12, 2026-11-19 공통 규칙). 오른쪽 % 자리가 있어 SheetLabel을 바로 쓰지 못한다
  List<Widget> _volumeRows() => [
        Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Semantics(header: true, child: Text('소리 크기', style: AppType.rowStrong))),
            Text(_volumeText, style: AppType.sub.tnum),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Row(children: [
            Semantics(
              button: true,
              selected: _settings.muted,
              label: _settings.muted ? '음소거 해제' : '음소거',
              child: Pressable(
                onPress: () => _settings.set({'muted': !_settings.muted}),
                // 원(44)은 그대로, 누르는 자리만 48: 오른쪽으로 넓힌 만큼 막대 앞 간격을 줄인다
                child: SizedBox(
                  width: Space.hit,
                  height: Space.hit,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: Space.touch,
                      height: Space.touch,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: _settings.muted ? Border.all(color: AppColors.track) : null),
                      child: Center(child: LucideIcon(_settings.muted ? 'VolumeX' : 'Volume2', color: _settings.muted ? AppColors.accent : AppColors.ink)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.s - 2 * _hitPad),
            Expanded(
              child: AppSlider(
                label: '소리 크기',
                value: _dragVolume ?? _settings.volume,
                dim: _settings.muted && _dragVolume == null,
                valueText: _volumeText,
                onChange: (v) {
                  setState(() => _dragVolume = v);
                  _audio.preview(v);
                },
                onCommit: (v) {
                  setState(() => _dragVolume = null);
                  _settings.set({'volume': (v * 100).round() / 100, 'muted': false});
                },
              ),
            ),
          ]),
        ),
      ];

  /// 소리 묶음: 회색 상자 대신 위 얇은 선과 여백으로 나눈다
  Widget _soundGroup(BuildContext ctx, bool active) => Container(
        margin: const EdgeInsets.only(top: Space.xl),
        padding: const EdgeInsets.only(top: Space.xl),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line, width: Hairline.of(ctx)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 시트 안 묶음 이름(2026-11-19 공통 규칙: label 16이었다)
          SheetLabel(active ? '소리' : '소리만 듣기'),
          WordText(active ? '소리는 독서 타이머와 따로 켜고 꺼요. 읽은 시간은 그대로예요.' : '시간을 재지 않고 소리만 들어요. 독서 시간에는 쌓이지 않아요.', style: AppType.sub),
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            // 시트 안 단추는 xlarge(TDS Button 기본값 · 2026-11-19 공통 규칙)
            child: Btn(
              label: _audio.playing ? (active ? '소리 끄기' : '소리 멈추기') : active ? '소리 켜기' : '소리만 듣기',
              kind: 'secondary',
              size: 'xlarge',
              onPress: () => _audio.playing ? _audio.pause() : _audio.play(_settings.scene),
            ),
          ),
        ]),
      );

  void _measure() {
    final p = _panelKey.currentContext?.size?.height;
    final r = _rowKey.currentContext?.size?.width;
    if ((p != null && _open && (p - _panelHeight).abs() > 0.5) || (r != null && (r - _rowW).abs() > 0.5)) {
      setState(() {
        if (p != null && _open) _panelHeight = p;
        if (r != null) _rowW = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final insets = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final vh = size.height;
    final reduce = _settings.reduceMotion == 'on' || (_settings.reduceMotion == 'system' && MediaQuery.disableAnimationsOf(context));
    final animate = _appActive && !reduce && (ModalRoute.of(context)?.isCurrent ?? true);
    final ticking = _appActive && _reading.running;
    final sceneH = _open ? math.max(vh * 0.3, vh - _panelHeight + 22) : vh;
    // 화면은 장면 · 위 줄 · 조작부(펼친 판) · 접은 장면 네 덩이(긴 build를 나눴다, 화면은 그대로)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 위는 밝은 글자(영상 위), 아래 내비 막대는 지금 앱처럼 투명 + 어두운 단추(아래는 흰 조작부)
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: const Color(0x00000000),
        systemNavigationBarDividerColor: const Color(0x00000000),
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Material(
        color: const Color(0xFF182C44),
        child: Stack(children: [
          // 옆으로 넘겨 장면 고르기(2026-11-27 사용자 '고르기는 그냥 옆으로 넘기면 골라지고'): 손가락을 따라 옆 장면(정지 그림 → 영상)이 밀려 들어오고,
          // 놓아 멈춘 쪽 장면 · 소리로 바뀐다. 왼쪽으로 넘기면 다음 장면, 끝에서는 처음으로 돈다. 보이는 쪽만 영상을 튼다
          Positioned(
            left: 0,
            top: 0,
            width: size.width,
            height: sceneH,
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                _settleScene();
                return false;
              },
              child: PageView.builder(
                controller: _pager,
                itemBuilder: (_, i) {
                  final sc = scenes[i % scenes.length];
                  return SceneVideo(key: ValueKey('scene-$i'), id: sc.id, play: animate && sc.id == _settings.scene);
                },
              ),
            ),
          ),
          _topBar(insets),
          _panel(context, insets, vh, ticking),
          if (!_open) ..._folded(insets, vh, ticking),
        ]),
      ),
    );
  }

  /// 위 줄(장면 위 밝은 글자): 왼쪽 ⌄ 나가기(독서는 계속, 오른쪽 아래 작은 타이머) · 오른쪽 읽는 책 이름(누르면 책 바꾸기).
  /// 2026-11-27 사용자 시안 '우측상단에 책 이름'. 가운데 '읽기'와 오른쪽 '끝내기'는 뺐다(끝내기는 일시정지해 나온 읽기 탭 카드 아래)
  Widget _topBar(EdgeInsets insets) {
    final active = _reading.active != null;
    final soundOnly = widget.soundOnly;
    final bookId = _bookId;
    final name = soundOnly ? '소리 듣기' : bookId != null ? bookTitle(lib, bookId) ?? '' : NoBookCover.name;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Padding(
        // 단추 누르는 자리 44 → 48: 늘어난 만큼 위 여백을 줄여 제목·단추 자리는 그대로. 책 이름 오른쪽 끝은 ⌄ 그림 왼쪽 끝과 맞선다(화면 끝에서 24)
        padding: EdgeInsets.fromLTRB(12, insets.top + 6 - _hitPad, Space.page, 16 - _hitPad),
        child: Row(children: [
          Semantics(
            container: true,
            button: true,
            // 장면은 시작한 화면 위에 열린다: 읽는 중이 아니면 앱 공통 뒤로 이름
            label: active ? '나가기(독서는 계속)' : '뒤로',
            onTap: _leave,
            excludeSemantics: true,
            child: Pressable(onPress: _leave, child: const SizedBox(width: 52, height: Space.hit, child: Center(child: LucideIcon('ChevronDown', size: 28, color: _light)))),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: !soundOnly,
                label: soundOnly ? name : '책 변경, $name',
                onTap: soundOnly ? null : _pickBook,
                excludeSemantics: true,
                child: Pressable(
                  onPress: soundOnly ? null : _pickBook,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Space.hit),
                    child: Align(
                      alignment: Alignment.centerRight,
                      widthFactor: 1,
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.title.copyWith(color: _light, shadows: _shade)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _maybeAvoid(Widget panel) => _open ? ToastAvoid(child: panel) : panel;

  /// 조작부(아래 흰 판): 1) 연결된 책 2) 시간 3) [분위기 | 재생·일시정지 | 목표]
  Widget _panel(BuildContext context, EdgeInsets insets, double vh, bool ticking) {
    final soundOnly = widget.soundOnly;
    final scene = _settings.scene;
    final goalMin = _settings.goalMin;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Offstage(
        offstage: !_open,
        // 펼친 조작부 위로 토스트를 띄운다(책을 바꿔 나눠 저장한 토스트가 시간 · 일시정지를 덮었다, 2026-11-21 촬영 확인).
        // 판은 GlobalKey라 감싸도 상태가 그대로 옮겨진다
        child: _maybeAvoid(Container(
          key: _panelKey,
          constraints: BoxConstraints(maxHeight: vh * 0.65),
          decoration: const BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet))),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            // 2026-11-18 사용자 '위랑 간격이랑 세로 길이가 안 맞다': 시안을 화면 폭 비율로 재서 위 여백 12 → 24, 표지 52 → 47,
            // 표지–시간 −8, 시간–단추 −4, 가운데 단추 84 → 76(조작부 315 → 약 306, 시안 306)
            padding: EdgeInsets.fromLTRB(Space.page, Space.l + Space.s, Space.page, insets.bottom + Space.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _bookLine(soundOnly),
              if (!soundOnly) _timeBlock(context, ticking, goalMin),
              // 3) [분위기 | 재생·일시정지 | 목표]
              Row(children: [
                Expanded(
                  child: _Side(
                    icon: _soundOff ? 'VolumeX' : 'AudioLines',
                    // 꺼졌으면 '꺼짐'만(분위기 이름까지 붙이면 길었다, 2026-11-20 사용자 '꺼짐 옆에 창가의 빗소리 | 이거 없애버려')
                    text: _soundOff ? '꺼짐' : sceneName(scene),
                    label: '분위기 고르기, ${sceneName(scene)}, ${_soundOff ? '소리 꺼짐' : _settings.muted ? '음소거' : '소리 ${(_settings.volume * 100).round()}%'}',
                    onPress: _moodSheet,
                  ),
                ),
                _Round(playing: _playing, label: _playLabel, onPress: _playPause),
                Expanded(
                  child: soundOnly
                      ? const SizedBox.shrink()
                      : _Side(icon: 'Timer', text: goalMin != null ? '목표 ${minutesLabel(goalMin)}' : '목표 없음', label: '목표 시간, ${goalMin != null ? minutesLabel(goalMin) : '목표 없음'}', onPress: _goalSheet),
                ),
              ]),
              // 소리 재생 실패는 글로 알리지 않는다: 분위기 칸이 '꺼짐'으로 보인다(2026-11-20 사용자 '저 빨간색은 왜 있어 … 다 지워', SCREENS 156 예외)
              // 소리만 듣다가 기록 시작: 같은 장면에 타이머를 띄운다
              if (soundOnly)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Btn(
                    label: '지금부터 독서 기록',
                    kind: 'ghost',
                    onPress: () {
                      _start();
                      Navigator.of(context).pushReplacement(readingSceneRoute());
                    },
                  ),
                ),
            ]),
          ),
        )),
      ),
    );
  }

  /// 1) 연결된 책(실제 표지·제목). 장면 카드라 책 줄(BookRow)과 따로 둔다. 누르면 바꾸기, 책 없이 시작해도 된다
  Widget _bookLine(bool soundOnly) {
    final bookId = _bookId;
    return Row(children: [
      Expanded(
        // 화면 읽기는 줄 하나로 한 번(안쪽 제목 · 저자를 '책 변경' 뒤에 따로 또 읽었다)
        child: Semantics(
          container: true,
          button: true,
          label: bookId != null ? '책 변경, ${bookTitle(lib, bookId) ?? ''}' : '책 연결하기',
          onTap: _pickBook,
          excludeSemantics: true,
          child: Pressable(
            onPress: _pickBook,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(children: [
                if (!soundOnly && bookId != null)
                  // 책을 바꾸면 표지도 새로 그린다(같은 자리 위젯이 이전 책 표지를 들고 있었다, 2026-11-15 QA 수아 F5).
                  // 표지 모서리는 둥글게·옅은 그림자(2026-11-17 시안)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: [cssShadow(const Color(0x22000000), 0, 2, 6)]),
                      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinkedCover(key: ValueKey(bookId), lib: lib, id: bookId, width: _coverW)),
                    ),
                  )
                else
                  // 책 없는 표지 자리는 앱 공통 회색 칸(2026-11-19 공통 규칙: 여기만 선을 두른 다른 비율이었다)
                  const NoBookCover(width: _coverW),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(soundOnly ? '소리와 함께 쉬어 가요' : bookTitle(lib, bookId) ?? '책 연결하기', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section),
                    const SizedBox(height: 2),
                    Text(soundOnly ? '독서 시간은 기록하지 않아요' : bookId != null ? bookAuthor(lib, bookId) : '책 없이 시작해도 좋아요', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookAuthor),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(width: Space.s),
      Semantics(
        button: true,
        label: '조작부 접기',
        onTap: () => setState(() => _open = false),
        excludeSemantics: true,
        child: Pressable(
          onPress: () => setState(() => _open = false),
          // 글자 없이 ⌄만(2026-11-17 시안)
          child: const SizedBox(width: Space.hit, height: Space.hit, child: Center(child: LucideIcon('ChevronDown', size: 26, color: AppColors.icon))),
        ),
      ),
    ]);
  }

  /// 2) 시간(가장 크게, 숫자 폭 고정). 아래 한 줄은 자리를 늘 지켜 멈춰도 시간이 위아래로 흔들리지 않는다.
  /// 아래 한 줄은 글자 배율만큼 내려 놓고 그만큼 아래를 비운다(2026-11-16 QA 영숙 F4: 2.0배에서 '목표 10분'이 숫자 아래를 덮었다). 1배는 그대로
  Widget _timeBlock(BuildContext context, bool ticking, num? goalMin) {
    final active = _reading.active;
    final running = _reading.running;
    final goalMs = goalMin == null ? null : goalMin * 60000;
    // 시간 숫자는 이 이름 뒤에 한 번 읽고, 아래 '목표 10분' 줄은 이름과 같은 말이라 뺀다(영숙 F9)
    return Semantics(
      container: true,
      button: true,
      label: '목표 시간 설정, ${goalMin != null ? minutesLabel(goalMin) : '목표 없음'}',
      onTap: _goalSheet,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: _goalSheet,
        child: Padding(
          padding: EdgeInsets.only(top: Space.s, bottom: Space.l + math.max(0.0, _captionLine(context) - 21)),
          child: Column(children: [
            ElapsedTicker(
              running: ticking,
              builder: (ms) => Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                // '11:03:25'처럼 길어져도 화면 폭을 넘을 때(아주 큰 글씨)만 그 안에 들어가게 줄인다. 보통은 글자 그대로
                FittedBox(fit: BoxFit.scaleDown, child: Text(clock(ms), maxLines: 1, style: AppType.timer)),
                Positioned(
                  left: -100,
                  right: -100,
                  bottom: -(_captionLine(context) - 2), // 지금 앱: 시간 칸 아래 여백(16) 안에 겹쳐 칸 바닥보다 3 아래(1배에서 −19)
                  child: ExcludeSemantics(
                    child: Text(
                      active != null && !running
                          ? '일시정지'
                          : goalMs != null
                              ? (ms >= goalMs ? '목표 ${minutesLabel(goalMin!)}을 채웠어요' : '목표 ${minutesLabel(goalMin!)}')
                              : ' ',
                      textAlign: TextAlign.center,
                      style: AppType.caption,
                    ),
                  ),
                ),
              ]),
            ),
            // 기기 저장 실패도 장면에 빨간 글로 보이지 않는다(2026-11-20 사용자 '다 지워', SCREENS 156 예외). 기록을 저장하지 못하면 독서 끝 저장 때 알린다
          ]),
        ),
      ),
    );
  }

  /// 접었을 때: 장면 아래쪽을 어둡게 물들이고 그 위에 장면 점, [스피커 · 밝은 시간 · 재생·일시정지]. 시간을 누르면 조작부가 다시 열린다.
  /// 단추 누르는 자리 44 → 48(겉모양은 그대로): 늘어난 만큼 단추 사이·아래 여백을 줄여 아이콘 자리를 지킨다
  List<Widget> _folded(EdgeInsets insets, double vh, bool ticking) {
    final scene = _settings.scene;
    final soundOnly = widget.soundOnly;
    return [
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: (vh * 0.42).roundToDouble(),
        child: const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00100D0B), Color(0x66100D0B), Color(0xC2100D0B)],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
        ),
      ),
      if (_volOpen) Positioned.fill(child: Semantics(label: '소리 크기 닫기', child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _volOpen = false)))),
      Positioned(
        left: 0,
        right: 0,
        bottom: insets.bottom + 18 - _hitPad,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 장면 점(지금 장면, 표시만). 바꾸기는 옆으로 밀기 · 화면 읽기 위아래 조절.
          // 7 점을 누르던 것은 뺐다: 누르는 자리 48이 안 되고(DESIGN 15장) 앱의 다른 넘김 점(PageDots)도 표시만 한다
          Semantics(
            label: '장면, ${sceneName(scene)}',
            hint: '옆으로 밀어 장면을 바꿔요',
            onIncrease: () => _stepScene(1),
            onDecrease: () => _stepScene(-1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (i, sc) in scenes.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: sc.id == scene ? NightColors.ink : const Color.fromRGBO(246, 239, 230, 0.42)),
                  ),
                ],
              ]),
            ),
          ),
          // 소리 막대: 스피커 줄과 같은 폭으로 그 위에, 왼쪽(스피커 쪽)부터 찬다. 맨 왼쪽까지 내리면 음소거
          if (_volOpen && _rowW > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: SizedBox(
                // 줄 폭은 누르는 자리를 넓힌 만큼(양쪽 2) 늘었다: 막대 폭은 그대로
                width: _rowW - 2 * _hitPad + 2 * Space.s,
                child: AppSlider(
                  night: true,
                  label: '소리 크기',
                  value: _dragVolume ?? (_settings.muted ? 0 : _settings.volume),
                  valueText: _volumeText,
                  onChange: (v) {
                    setState(() => _dragVolume = v);
                    _audio.preview(v);
                  },
                  onCommit: (v) {
                    setState(() => _dragVolume = null);
                    _settings.set(v <= 0.02 ? {'muted': true} : {'volume': (v * 100).round() / 100, 'muted': false});
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Space.s - _hitPad),
            child: Row(key: _rowKey, mainAxisSize: MainAxisSize.min, children: [
              Semantics(
                button: true,
                expanded: _volOpen,
                label: _settings.muted || _soundOff
                    ? '소리 꺼짐, 눌러서 소리 켜기'
                    : _volOpen
                        ? '소리 ${(_settings.volume * 100).round()}%, 눌러서 음소거'
                        : '소리 ${(_settings.volume * 100).round()}%, 눌러서 크기 조절',
                child: Pressable(
                  onPress: _tapSpeaker,
                  child: SizedBox(
                    width: Space.hit,
                    height: Space.hit,
                    child: Center(child: LucideIcon(_settings.muted || _soundOff ? 'VolumeX' : 'Volume2', size: 26, color: _settings.muted || _soundOff ? NightColors.inkSoft : NightColors.ink)),
                  ),
                ),
              ),
              const SizedBox(width: Space.xl - _hitPad),
              // 시간은 글자 폭만큼, 남는 자리를 넘으면(아주 큰 글씨) 줄인다: 'h:mm:ss' · 'hh:mm:ss'에서 양쪽 단추를 밀어내지 않게
              Flexible(
                child: Semantics(
                  button: true,
                  label: '조작부 열기',
                  child: Pressable(
                    onPress: () => setState(() {
                      _volOpen = false;
                      _open = true;
                    }),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: Space.hit),
                      // 글자 폭만큼(시안: 스피커 · 일시정지가 시간 바로 양옆). 전에는 남는 폭을 다 써 두 단추가 화면 끝으로 갔다
                      child: Center(
                        widthFactor: 1,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: soundOnly
                              ? Text('조작부 열기', maxLines: 1, style: _dockTime)
                              : ElapsedTicker(running: ticking, builder: (ms) => Text(clock(ms), maxLines: 1, style: _dockTime)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.xl - _hitPad),
              Semantics(
                button: true,
                label: _playLabel,
                child: Pressable(
                  onPress: _playPause,
                  child: SizedBox(
                    width: Space.hit,
                    height: Space.hit,
                    child: Center(child: _playing ? const PauseIcon(width: 5, height: 24, gap: 6, color: NightColors.ink) : const PlayIcon(size: 30, color: NightColors.ink)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ];
  }
}

/// 접은 장면 시간 글자(모듈 값은 getter: 글자 크기를 화소에 맞추는 값이 앱이 뜬 뒤 정해진다, theme.dart rnPx)
TextStyle get _dockTime => AppType.clock.copyWith(color: NightColors.ink, shadows: _shade);

/// 재는 동안 1초마다 builder만 다시 그린다(지금까지 잰 시간을 넘긴다). 읽기 장면 시간 · 읽기 탭 · 작은 타이머가 같이 쓴다
/// (같은 1초 타이머가 세 벌 있었다, 2026-11-19). 다시 그릴 범위만 감싼다
class ElapsedTicker extends StatefulWidget {
  const ElapsedTicker({super.key, required this.running, required this.builder});
  final bool running;
  final Widget Function(num ms) builder;

  @override
  State<ElapsedTicker> createState() => _ElapsedTickerState();
}

class _ElapsedTickerState extends State<ElapsedTicker> {
  Timer? _t;

  void _sync() {
    if (widget.running) {
      _t ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ElapsedTicker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(ReadingStore.instance.elapsed);
}

/// 조작부 양옆 칸(분위기·목표): 아이콘 + 두 줄까지 글자(정보 사이 세로줄은 MetaText)
class _Side extends StatelessWidget {
  const _Side({required this.icon, required this.text, required this.label, required this.onPress});
  final String icon, text, label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        onTap: onPress,
        excludeSemantics: true,
        child: Pressable(
          onPress: onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                LucideIcon(icon, size: 30, color: AppColors.inkSoft),
                const SizedBox(height: Space.xs),
                MetaText(text, maxLines: 2, textAlign: TextAlign.center, style: AppType.sub),
              ]),
            ),
          ),
        ),
      );
}

/// 가운데 둥근 재생 단추(단색 원): 누르는 동안 조금 작아지고 짙어진다
class _Round extends StatefulWidget {
  const _Round({required this.playing, required this.label, required this.onPress});
  final bool playing;
  final String label;
  final VoidCallback onPress;

  @override
  State<_Round> createState() => _RoundState();
}

class _RoundState extends State<_Round> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.label,
        onTap: widget.onPress,
        excludeSemantics: true,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPress,
          child: Transform.scale(
            scale: _down ? 0.96 : 1,
            child: Container(
              width: _roundD,
              height: _roundD,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _down ? AppColors.accentPressed : AppColors.accent),
              child: Center(child: widget.playing ? const PauseIcon(width: 8, height: 29, gap: 9, color: AppColors.onAccent) : const PlayIcon(size: 34, color: AppColors.onAccent)),
            ),
          ),
        ),
      );
}

/// 독서 장면 영상: 720×1280 세로 영상을 칸에 꽉 채운다(넘치는 위아래는 잘림). 영상 소리는 끄고 환경음과 섞는다.
/// 보이는 동안만 재생한다(나가거나 동작 줄이기면 멈춘 한 장면). 영상이 준비되기 전에는 같은 장면의 정지 그림
class SceneVideo extends StatefulWidget {
  const SceneVideo({super.key, required this.id, required this.play});
  final String id;
  final bool play;

  @override
  State<SceneVideo> createState() => _SceneVideoState();
}

class _SceneVideoState extends State<SceneVideo> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SceneVideo old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _c?.dispose();
      _c = null;
      _ready = false;
      _load();
    } else if (old.play != widget.play) {
      widget.play ? _c?.play() : _c?.pause();
    }
  }

  Future<void> _load() async {
    final c = VideoPlayerController.asset(_videos[widget.id]!, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    try {
      await c.initialize();
      if (!identical(_c, c)) {
        await c.dispose();
        return;
      }
      await c.setLooping(true);
      await c.setVolume(0);
      if (widget.play) await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // 영상을 못 열면 정지 그림으로 둔다
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return IgnorePointer(
      child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          Image.asset(scenePosters[widget.id]!, fit: BoxFit.cover),
          if (_ready && c != null)
            FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
        ]),
      ),
    );
  }
}
