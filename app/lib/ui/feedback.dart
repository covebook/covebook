// 피드백 공용: 짧은 알림(토스트)과 실패 문구. 언제 무엇을 쓰는지는 docs/design/DESIGN.md '피드백' 장
import 'dart:async';
import 'dart:io';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/sync.dart' show ApiError;
import '../store/settings_store.dart';
import 'kit.dart';
import 'theme.dart';

/// 실패를 사람이 읽는 문장으로(화면에 예외 원문·영어를 보이지 않는다, 원문은 로그로).
/// 앱이 직접 만든 StateError · 서버가 보낸 한국어 메시지(ApiError 4xx)는 그대로, 연결 문제는 '인터넷 연결을 확인해 주세요.', 그 밖은 '잠시 뒤 다시 시도해 주세요.'
String errorText(Object e) {
  debugPrint('[error] $e');
  if (isOffline(e)) return '인터넷 연결을 확인하고 다시 시도해 주세요.';
  if (e is ApiError) return e.status >= 500 || e.message.startsWith('서버 응답') ? '서버에 잠시 문제가 있어요. 잠시 뒤 다시 시도해 주세요.' : _sentence(e.message);
  if (e is StateError) return _sentence(e.message);
  if (e is FileSystemException) return '기기 저장 공간을 확인하고 다시 시도해 주세요.';
  return '잠시 뒤 다시 시도해 주세요.';
}

/// 서버 · 인터넷에 닿지 못한 실패인지(오프라인 안내를 고를 때)
bool isOffline(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is HttpException ||
    RegExp('SocketException|Connection (refused|reset|closed)|Failed host lookup|Network is unreachable', caseSensitive: false).hasMatch('$e');

String _sentence(String s) {
  final t = s.trim();
  return t.isEmpty || RegExp(r'[.?!요]$').hasMatch(t) ? (t.endsWith('요') ? '$t.' : t) : '$t.';
}

/// 토스트를 얼마나 보이나: 되돌리기가 있으면 4초, 짧은 확인은 2.5초
const toastShort = Duration(milliseconds: 2500), toastWithAction = Duration(seconds: 4);

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _shown = true);
    });
    _timer = Timer(widget.action != null ? toastWithAction : toastShort, _hide);
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
      // 떠 있는 하단 탭 바 위(2026-11-16 QA 현우 F1: 바닥에 붙으면 탭을 막았다). 키보드가 열리면 키보드 위
      bottom: (mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.viewPadding.bottom + TabBarStyle.navHeight) + Space.s,
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
    );
  }
}
