// 피드백 공용: 짧은 알림(토스트)과 실패 문구. 언제 무엇을 쓰는지는 docs/design/DESIGN.md '피드백' 장
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

export '../services/error_text.dart';
import '../services/error_text.dart';
import '../services/share_image.dart' show ShareImageError, shareErrorTitle;
import '../store/settings_store.dart';
import 'alert.dart';
import 'josa.dart';
import 'kit.dart';
import 'theme.dart';

/// 토스트를 얼마나 보이나 = TDS Toast duration: 짧은 확인은 기본 3초, 되돌리기(단추)가 있으면 5초(theme.dart Motion)
const toastShort = Motion.toast, toastWithAction = Motion.toastAction;

/// 토스트 시간을 셀 때 한 프레임으로 치는 가장 긴 시간(멈춘 화면은 시간에 넣지 않는다)
const _frameCap = Duration(milliseconds: 100);

_ToastHandle? _current;

/// 짧은 알림 한 줄(되돌리기 하나까지). 어느 화면(밀어 넣은 화면 · 시트 위)에서도 맨 위 겹에 떠서 보인다.
/// 하단 탭 바 위에 띄워 탭을 막지 않고, 새 알림이 오면 앞 것을 바로 걷는다. 화면 읽기에는 글을 읽어 준다
/// below: 단추를 글 아래 줄에(결과 한 줄 + 그 결과를 보러 가기, 2026-11-27 독서를 끝내면 '오늘 N분 읽었어요' 아래 '달력에서 보기')
void showToast(BuildContext context, String text, {String? action, VoidCallback? onAction, bool below = false}) {
  final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay ?? Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.remove();
  final handle = _ToastHandle();
  final entry = OverlayEntry(builder: (_) => _Toast(text: text, action: action, onAction: onAction, below: below && action != null, handle: handle));
  handle.entry = entry;
  _current = handle;
  overlay.insert(entry);
  SemanticsService.sendAnnouncement(View.of(context), action == null ? text : '$text $action 단추가 있어요', Directionality.of(context));
  HapticFeedback.selectionClick();
}

class _ToastHandle {
  OverlayEntry? entry;
  void remove() {
    entry?.remove();
    entry = null;
    if (identical(_current, this)) _current = null;
  }
}

class _Toast extends StatefulWidget {
  const _Toast({required this.text, required this.action, required this.onAction, required this.handle, this.below = false});
  final String text;
  final String? action;
  final bool below;
  final VoidCallback? onAction;
  final _ToastHandle handle;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  bool _shown = false;
  late final Ticker _clock = createTicker(_tick);
  Duration _last = Duration.zero, _seen = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _shown = true);
      _clock.start();
    });
  }

  /// 보인 시간은 화면이 실제로 넘어간 프레임으로 센다(한 프레임은 최대 [_frameCap]). 시계 시간으로 세면 책장을 다시 굽는 동안
  /// (GPU가 몇 초 바빠 화면이 멈춘 동안) 3초가 다 흘러, 토스트가 한 번도 그려지지 않고 걷혔다
  /// (2026-11-20 에뮬: 내 책 고르기 2권 진열 · 삭제 토스트가 다섯 번 모두 안 보임. 첫 프레임 뒤부터 세도 같았다)
  void _tick(Duration t) {
    final dt = t - _last;
    _last = t;
    _seen += dt > _frameCap ? _frameCap : dt;
    if (_seen >= (widget.action != null ? toastWithAction : toastShort)) {
      _clock.stop();
      _hide();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _hide() {
    if (!mounted) return;
    setState(() => _shown = false);
    Timer(const Duration(milliseconds: 200), widget.handle.remove);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = SettingsStore.instance;
    final still = s.reduceMotion == 'on' || (s.reduceMotion == 'system' && mq.disableAnimations);
    final ms = still ? 0 : 180;
    Widget actionButton() => Pressable(
      onPress: () {
        widget.onAction?.call();
        _clock.stop();
        _hide();
      },
      child: Semantics(
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Space.hit, minWidth: Space.hit),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Center(widthFactor: 1, child: Text(widget.action!, style: AppType.toastAction)),
          ),
        ),
      ),
    );
    return Positioned(
      left: TabBarStyle.side,
      right: TabBarStyle.side,
      // 떠 있는 하단 탭 바 위(2026-11-16 QA 현우 F1: 바닥에 붙으면 탭을 막았다). 키보드가 열리면 키보드 위.
      // 화면 아래 단추 줄이 보이면 그 위(ToastAvoid, 2026-11-20 책 공유 '사진 저장' 단추를 덮었다)
      bottom: math.max((mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.viewPadding.bottom + TabBarStyle.navHeight), toastFloor(mq.size.height)) + Space.s,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: sheetMax),
          child: AnimatedOpacity(
            opacity: _shown ? 1 : 0,
            duration: Duration(milliseconds: ms),
            child: AnimatedSlide(
              offset: _shown ? Offset.zero : const Offset(0, 0.25),
              duration: Duration(milliseconds: ms),
              curve: Curves.easeOutCubic,
              // 맨 위 겹(오버레이)은 화면의 Material 밖이라 글자 바탕을 따로 깐다(없으면 글자 밑에 노란 줄)
              child: Material(
                type: MaterialType.transparency,
                child: Semantics(
                container: true,
                liveRegion: true,
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: AppColors.toast, borderRadius: BorderRadius.all(Radius.circular(Shape.button)), boxShadow: [Shape.floatShadow]),
                  child: Padding(
                    padding: EdgeInsets.only(left: Space.l, right: widget.action == null ? Space.l : Space.xs, top: Space.xs, bottom: Space.xs),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: ControlSize.buttonM - Space.xs * 2),
                      child: widget.below
                          // 단추는 글 아래 줄 왼쪽(글과 같은 들여쓰기: 단추 안쪽 여백만큼 왼쪽으로 당긴다)
                          // 폭은 다른 토스트처럼 가득(글이 짧아도 가운데 작은 상자가 되지 않게)
                          ? SizedBox(
                              width: double.infinity,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Padding(padding: const EdgeInsets.only(top: Space.s, right: Space.m), child: WordText(widget.text, style: AppType.toast)),
                                Transform.translate(offset: const Offset(-Space.m, 0), child: actionButton()),
                              ]),
                            )
                          : Row(children: [
                              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: WordText(widget.text, style: AppType.toast))),
                              if (widget.action != null) actionButton(),
                            ]),
                    ),
                  ),
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 앱 밖(웹 · 메일 · 스토어)을 연다. 열지 못하면 확인창으로 알린다(DESIGN 10장: 조용히 끝나지 않게)
Future<bool> openExternal(BuildContext context, String url, {String what = '페이지'}) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  // 조사는 이름 끝소리로('처리방침를'이었다, 2026-11-20)
  if (!ok && context.mounted) appAlert(context, '${eulReul(what)} 열 수 없어요', '인터넷 연결이나 기본 브라우저를 확인하고 다시 시도해 주세요.');
  return ok;
}

/// 공유 · 사진첩 저장 실패 창(책 공유 · 갈피 공유 · 지난 책장 공유가 같은 모양). 본문은 앱이 만든 안내(이미지 · 기기 안 됨)는 그대로,
/// 그 밖 예외는 사람 문장(DESIGN 9장). 기기가 못 하는 경우 말고는 취소 · 다시 시도(2026-11-20 QA: 갈피 공유 시트 · 지난 책장은 '확인' 하나였다)
void shareFailAlert(BuildContext context, Object e, VoidCallback retry) {
  final again = !(e is ShareImageError && e.stage == 'unavailable');
  final body = e is ShareImageError && (e.stage == 'image' || e.stage == 'unavailable') ? e.message : errorText(e);
  appAlert(context, shareErrorTitle(e), body, [
    if (again) const AlertButton('취소', style: AlertStyle.cancel),
    AlertButton(again ? '다시 시도' : '확인', onPress: again ? retry : null),
  ]);
}
