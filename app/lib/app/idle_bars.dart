// 책장 탭에서 가만히 있으면 아래를 비운다: 3초 동안 손대지 않으면 하단 탭 · 작은 타이머 · 하단바 위 덮개가 내려가고
// 시스템 아래 막대(뒤로 · 홈 · 제스처 막대)도 숨어 책장만 보인다. 화면을 누르면(두 번 연달아 눌러도) 다시 보이고 3초를 새로 잰다.
// 위아래로 밀면(스크롤) 보이지 않게 바로 내린다.
// 2026-11-25 사용자 '홈화면에서 3초 정도 가만히 있으면 하단바 내려가서 책장만 온전히 보이게, 화면 터치하면 다시 보이게, 위아래로 내리면
// 그냥 안 보이게, 2번 연속 터치하면 보이게, 휴대폰 뒤로가기 이런 거처럼 내려가게, 애들도 내려가게 되나'.
// 내려도 되는지(책장 탭 첫 화면 · 꾸미기 · 시트 · 끌기 없음)는 책장 화면이 [canHide]로 알려 준다. 안 되면 바로 올리고 3초 뒤 다시 본다
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class IdleBars extends ChangeNotifier {
  IdleBars._();
  static final instance = IdleBars._();

  /// 가만히 있은 뒤 내릴 때까지
  static const after = Duration(seconds: 3);

  /// 내려가 있나
  bool down = false;

  /// 지금 내려도 되는지(책장 화면이 정한다). 없으면 내리지 않는다
  bool Function()? canHide;

  Timer? _timer;

  /// 붙잡아 둔 수(작은 타이머를 끄는 동안처럼 내리면 안 되는 손짓): 0이 될 때까지 내리지 않는다
  int _holds = 0;

  /// 시스템 아래 막대가 있을 때의 아래 안전 여백(막대를 숨긴 동안에도 책장 배치는 이 값으로: 줄 자리가 바뀌어 책장을 다시 그리지 않게)
  double _bottom = 0;

  /// 화면을 눌렀다: 올리고 3초를 새로 잰다
  void poke() {
    _set(false);
    _arm();
  }

  /// 밀었다(스크롤): 내려도 되면 바로 내린다
  void hideNow() {
    if (_mayHide) _set(true);
    _arm();
  }

  /// 내리지 않게 붙잡는다(올려 두고). 손을 떼면 [release]: 다시 3초를 잰다.
  /// 작은 타이머를 끄는 동안 3초가 지나 내려가면 타이머가 손가락 아래에서 사라져 끌기가 끊겼다(2026-11-25 에뮬 확인)
  void hold() {
    _holds++;
    _set(false);
  }

  void release() {
    if (_holds > 0) _holds--;
    _arm();
  }

  bool get _mayHide => _holds == 0 && (canHide?.call() ?? false);

  /// 책장 탭을 떠났다: 올리고 재지 않는다
  void stop() {
    _timer?.cancel();
    _timer = null;
    _holds = 0;
    _set(false);
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(after, () {
      if (_mayHide) {
        _set(true);
      } else {
        // 지금은 안 된다(시트 · 꾸미기 · 다른 화면): 올려 두고 다시 잰다
        _set(false);
        _arm();
      }
    });
  }

  /// 책장 배치에 쓸 아래 안전 여백: 시스템 막대를 숨겨 0이 된 동안에는 숨기기 전 값
  double stableBottom(double now) {
    if (now > 0) _bottom = now;
    return down ? _bottom : now;
  }

  void _set(bool v) {
    if (v == down) return;
    down = v;
    notifyListeners();
    // 시스템 아래 막대도 함께(위 상태 표시줄은 그대로). 올릴 때는 앱 기본(가장자리까지 그리기)으로
    if (v) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: const [SystemUiOverlay.top]).ignore();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge).ignore();
    }
  }
}

/// 책장 화면 전체를 감싸 누르기와 밀기를 가린다(아래 위젯의 누르기 · 스크롤은 그대로 받는다).
/// 손가락이 거의 움직이지 않고 떼면 누르기(올린다), 누르기 문턱보다 움직이면 밀기(내린다)
class IdleBarsListener extends StatefulWidget {
  const IdleBarsListener({super.key, required this.child});
  final Widget child;

  @override
  State<IdleBarsListener> createState() => _IdleBarsListenerState();
}

class _IdleBarsListenerState extends State<IdleBarsListener> {
  final _down = <int, Offset>{};
  final _moved = <int>{};

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _down[e.pointer] = e.position,
        onPointerMove: (e) {
          final p = _down[e.pointer];
          if (p == null || _moved.contains(e.pointer)) return;
          if ((e.position - p).distance > kTouchSlop) {
            _moved.add(e.pointer);
            IdleBars.instance.hideNow();
          }
        },
        onPointerUp: (e) {
          final moved = _moved.remove(e.pointer);
          if (_down.remove(e.pointer) != null && !moved) IdleBars.instance.poke();
        },
        onPointerCancel: (e) {
          _down.remove(e.pointer);
          _moved.remove(e.pointer);
        },
        child: widget.child,
      );
}
