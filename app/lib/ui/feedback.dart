// 피드백 공용: 짧은 알림(토스트)과 실패 문구. 언제 무엇을 쓰는지는 docs/design/DESIGN.md '피드백' 장
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

export '../services/error_text.dart';
import '../store/settings_store.dart';
import 'alert.dart';
import 'josa.dart';
import 'kit.dart';
import 'theme.dart';

/// 토스트를 얼마나 보이나 = TDS Toast duration: 짧은 확인은 기본 3초, 되돌리기(단추)가 있으면 5초(theme.dart Motion)
const toastShort = Motion.toast, toastWithAction = Motion.toastAction;

_ToastHandle? _current;

/// 짧은 알림 한 줄(되돌리기 하나까지). 어느 화면(밀어 넣은 화면 · 시트 위)에서도 맨 위 겹에 떠서 보인다.
/// 하단 탭 바 위에 띄워 탭을 막지 않고, 새 알림이 오면 앞 것을 바로 걷는다. 화면 읽기에는 글을 읽어 준다
void showToast(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay ?? Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.remove();
  final handle = _ToastHandle();
  final entry = OverlayEntry(builder: (_) => _Toast(text: text, action: action, onAction: onAction, handle: handle));
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
  const _Toast({required this.text, required this.action, required this.onAction, required this.handle});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final _ToastHandle handle;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 보이는 시간은 처음 그려진 뒤부터 센다: 무거운 프레임(책장 다시 굽기)과 겹치면 그려지기 전에 3초가 다 가
    // 토스트가 한두 장면만 보였다(2026-11-20 QA: 내 책 고르기 삭제 · 진열 토스트가 안 보임, 토스트가 짧음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _shown = true);
      _timer = Timer(widget.action != null ? toastWithAction : toastShort, _hide);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
                      child: Row(children: [
                        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: WordText(widget.text, style: AppType.toast))),
                        if (widget.action != null)
                          Pressable(
                            onPress: () {
                              widget.onAction?.call();
                              _timer?.cancel();
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
                          ),
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
