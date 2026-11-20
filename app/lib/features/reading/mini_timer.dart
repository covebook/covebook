// 공통 작은 타이머(지금 앱 features/reading/MiniTimer.tsx): 진행 중이거나 일시정지된 독서가 있을 때 화면 오른쪽 아래에 작은 원(누적 시간만).
// 원을 누르면 오른쪽 끝(시간 자리)은 그대로 두고 왼쪽으로 늘어나 '읽기 화면 바로가기'와 '재생/일시정지'가 나온다.
// 시간을 다시 누르거나 바깥을 누르면 접힌다(타이머·환경음 상태는 그대로). 시간은 같은 누적 값을 1초마다 다시 그릴 뿐 따로 재지 않는다.
// 읽기 화면·읽기 탭(책마다 흐르는 시간이 보인다)에서는 띄우지 않는다. 하단 탭·키보드·안전 영역과 겹치지 않게 둔다.
// 꾹 누른 채 끌면 자리를 옮긴다(2026-11-17 사용자 '타이머를 꾹 누르고 옮길 수 있게'). 옮긴 자리는 기기에 남고, 화면마다 하단 탭·고정 단추 위로는 내려가지 않는다
library;

import 'dart:async';
import '../../store/finish_reading.dart' show resumeReading;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../db/kv_store.dart';
import '../../domain/library.dart' show formatDurationPrecise;
import '../../domain/reading.dart';
import '../../store/mini_timer_store.dart';
import '../../store/reading_store.dart';
import '../../store/settings_store.dart';
import '../../ui/alert.dart';
import '../../ui/feedback.dart' show errorText;
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'play_icons.dart';
import 'reading_screen.dart';

const _actionsW = 112.0; // 펼친 왼쪽 부분(바로가기 + 재생/일시정지)

/// 펼쳤을 때 시간 오른쪽 여백(왼쪽 바로가기 그림 옆 여백과 맞춘다)
const _openPad = Space.l;
const _gap = 12.0;
// 하단 탭 화면(앱 틀 tabPaths에서 읽기 탭만 뺀 것: 읽기 탭에서는 타이머를 띄우지 않는다)
const _tabs = ['/', '/books', '/records', '/stats'];

bool miniTimerHidden(String path) => path == '/read' || path.startsWith('/reading');

/// 화면 읽기용 시간(초까지): 공용 formatDurationPrecise('20초' · '1분 20초' · '1시간 2분 3초', DESIGN 4장).
/// 보이는 시계(clock)처럼 초 아래는 버린다(읽어 주는 값과 보이는 값이 1초 어긋나지 않게)
String _speak(num ms) => formatDurationPrecise((ms / 1000).floor() * 1000);

class MiniTimer extends StatefulWidget {
  const MiniTimer({super.key, required this.navigator});
  final GlobalKey<NavigatorState> navigator;

  @override
  State<MiniTimer> createState() => _MiniTimerState();
}

class _MiniTimerState extends State<MiniTimer> {
  final _reading = ReadingStore.instance;
  final _place = MiniTimerPlace.instance;
  bool _open = false;
  String _lastKey = '';

  /// 사용자가 옮긴 자리(화면 오른쪽·아래 끝에서 거리). 없으면 기본 자리
  ({double right, double bottom})? _moved;
  ({double right, double bottom})? _dragFrom;
  static const _posKey = 'mini-timer-pos';

  @override
  void initState() {
    super.initState();
    _reading.addListener(_changed);
    _place.addListener(_changed);
    KvStore.get(_posKey).then((v) {
      final p = v?.split(',').map(double.tryParse).toList();
      if (mounted && p != null && p.length == 2 && !p.contains(null)) setState(() => _moved = (right: p[0]!, bottom: p[1]!));
    }).ignore();
  }

  @override
  void dispose() {
    _reading.removeListener(_changed);
    _place.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    final path = _place.path;
    // hidden(책장 꾸미기 조작부)은 탭 화면이 맨 위일 때만: 그 위에 밀어 넣은 화면에서는 보인다(2026-11-16 QA 현우 F9)
    final hidden = _reading.active == null || _reading.stale || miniTimerHidden(path) || (_place.hidden && _place.route == '/') || _place.modal || keyboard;
    // 화면이 바뀌거나 숨으면 접어 둔다(다시 나타날 때 늘 원)
    final key = '$path|$hidden';
    if (key != _lastKey) {
      _lastKey = key;
      _open = false;
    }
    if (hidden) return const SizedBox.shrink();
    // 재는 동안 1초마다 다시 그린다(읽기 장면 · 읽기 탭과 같은 타이머)
    return ElapsedTicker(running: _reading.running, builder: (ms) => _timer(mq, ms));
  }

  Widget _timer(MediaQueryData mq, num ms) {
    final path = _place.path;
    final running = _reading.running;
    final label = clock(ms);
    // 한 시간을 넘으면 숫자가 길어져 원 대신 같은 높이의 캡슐로 넓힌다
    // 펼치면 시간 오른쪽에 여백을 더한다: 동그라미 폭 그대로면 숫자가 캡슐 끝에 붙었다(2026-11-20 사용자 '펼쳤을 때 디자인 문제')
    final timeW = (label.length > 5 ? miniTimerSize + 24 : miniTimerSize) + (_open ? _openPad : 0);
    final s = SettingsStore.instance;
    final reduce = s.reduceMotion == 'on' || (s.reduceMotion == 'system' && mq.disableAnimations);
    final onTabs = _place.route == '/' && _tabs.contains(path);
    final minBottom = (onTabs ? TabBarStyle.navHeight + mq.padding.bottom : _place.bottom ?? _place.footer ?? mq.padding.bottom) + _gap;
    // 옮긴 자리: 화면 안, 하단 탭·고정 단추 위, 상태 표시줄 아래로만
    final maxRight = mq.size.width - timeW - (_open ? _actionsW : 0) - 8;
    final maxBottom = mq.size.height - mq.padding.top - miniTimerSize - 8;
    final double right = (_moved?.right ?? 16.0).clamp(8.0, math.max(8.0, maxRight)).toDouble();
    final double bottom = (_moved?.bottom ?? minBottom).clamp(minBottom, math.max(minBottom, maxBottom)).toDouble();
    final dragging = _dragFrom != null;
    // 테두리는 화소 2개
    final hair = 2 * Hairline.of(context);
    final speed = reduce ? Duration.zero : const Duration(milliseconds: 180);
    return Stack(children: [
      // 펼친 동안 바깥을 누르면 접는다(아래 화면은 눌리지 않는다)
      if (_open) Positioned.fill(child: Semantics(button: true, label: '작은 타이머 접기', child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _open = false)))),
      Positioned(
        right: right,
        bottom: bottom,
        height: miniTimerSize,
        child: GestureDetector(
          // 꾹 눌러 끌기: 손가락을 따라 옮기고, 놓으면 그 자리를 기억한다
          onLongPressStart: (_) {
            if (s.haptics) HapticFeedback.selectionClick();
            setState(() {
              _open = false;
              _dragFrom = (right: right, bottom: bottom);
            });
          },
          onLongPressMoveUpdate: (d) {
            final f = _dragFrom;
            if (f == null) return;
            setState(() => _moved = (right: f.right - d.offsetFromOrigin.dx, bottom: f.bottom - d.offsetFromOrigin.dy));
          },
          onLongPressEnd: (_) {
            setState(() {
              _dragFrom = null;
              _moved = (right: right, bottom: bottom);
            });
            KvStore.set(_posKey, '${right.round()},${bottom.round()}').ignore();
          },
          child: AnimatedScale(
            scale: dragging ? 1.08 : 1,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 120),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(miniTimerSize / 2),
                border: Border.all(color: AppColors.line, width: hair),
                boxShadow: const [Shape.floatShadow],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: speed,
                  width: _open ? _actionsW : 0,
                  child: AnimatedOpacity(
                    duration: speed,
                    opacity: _open ? 1 : 0,
                    child: IgnorePointer(ignoring: !_open, child: _actions(running, hair)),
                  ),
                ),
                _timeButton(label, ms, running, timeW, hair),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  /// 펼친 왼쪽: 읽기 화면 바로가기 | 재생·일시정지(그림은 읽기 장면과 같은 PlayIcon · PauseIcon)
  Widget _actions(bool running, double hair) {
    Widget divider() => Container(width: hair, height: 22, color: AppColors.line);
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerRight,
        minWidth: _actionsW,
        maxWidth: _actionsW,
        child: Row(children: [
          Semantics(
            button: true,
            label: '읽기 화면으로 가기',
            child: Pressable(
              onPress: () {
                setState(() => _open = false);
                // 쌓아서 연다: 지금 화면은 그대로 남는다
                final nav = widget.navigator.currentContext;
                if (nav != null) openReadingScene(nav);
              },
              // 바로가기 그림은 다른 선 아이콘과 같은 회색, 재생 · 일시정지는 먹색(주된 조작)
              child: const SizedBox(width: 52, height: miniTimerSize, child: Center(child: LucideIcon('BookOpen', color: AppColors.inkSoft))),
            ),
          ),
          divider(),
          Semantics(
            button: true,
            // 다시 재기는 앱 공통 말 '이어서 읽기'(DESIGN 9장)
            label: running ? '독서 일시정지' : '이어서 읽기',
            child: Pressable(
              onPress: () => running ? _reading.pause() : unawaited(_resume()),
              child: SizedBox(
                width: 52,
                height: miniTimerSize,
                child: Center(
                  child: running ? const PauseIcon(width: 3.5, height: 16, gap: 5, color: AppColors.ink) : const PlayIcon(size: 20, color: AppColors.ink),
                ),
              ),
            ),
          ),
          divider(),
        ]),
      ),
    );
  }

  /// 이어서 읽기. 지난 몫(어제 멈춘 독서)을 저장하지 못하면 확인창으로 알린다(2026-11-19 공통 규칙: 눌러도 아무 일 없었다)
  Future<void> _resume() async {
    final e = await resumeReading();
    final ctx = widget.navigator.currentContext;
    if (e == null || ctx == null || !ctx.mounted) return;
    appAlert(ctx, '이어서 읽지 못했어요', '지난 독서 기록은 그대로 있어요. 다음에 읽기를 시작하면 그 기록부터 저장해요. ${errorText(e)}');
  }

  /// 오른쪽 시간(원): 누르면 펼치고 접는다
  Widget _timeButton(String label, num ms, bool running, double timeW, double hair) => Semantics(
        container: true,
        button: true,
        expanded: _open,
        label: '독서 시간 ${_speak(ms)}${running ? '' : ', 일시정지'}. 눌러서 ${_open ? '접기' : '펼치기'}',
        onTap: () => setState(() => _open = !_open),
        excludeSemantics: true,
        // 누르는 동안 옅어진다(펼친 단추와 같은 Pressable, 2026-11-19 공통 규칙: 눌림 표시가 없었다)
        child: Pressable(
          onPress: () => setState(() => _open = !_open),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: timeW - hair * 2,
            height: miniTimerSize - hair * 2,
            // 큰 글씨에서는 동그라미 안에 들어가게 줄인다(1.5배에서 '03:3'으로 잘렸다, 2026-11-16 QA 확인). 펼치면 오른쪽 여백을 더 둔다
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(left: 4, right: 4 + (_open ? _openPad : 0)),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: AppType.labelStrong.tnum)),
              ),
            ),
          ),
        ),
      );
}
