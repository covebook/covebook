// 인터넷 연결 확인(2026-11-21 사용자 '인터넷이 없으면 막자'): 서버가 있는 빌드(로그인 필수)는 인터넷이 없으면 앱 전체를 막는다(app/net_gate.dart).
// 새 패키지 없이 짧게 붙어 본다: 서버 주소(443), 안 되면 공용 DNS(8.8.8.8:53). 서버만 멈춘 것은 인터넷이 없는 것이 아니라 막지 않는다.
// 한 번 실패하면 1.5초 뒤 한 번 더 본다(잠깐 끊긴 것으로 막지 않게). 연결돼 있으면 30초마다, 끊겨 있으면 4초마다 다시 본다.
// 앱이 앞으로 오면 바로 다시 보고, 뒤로 가면 쉰다. 막혀 있는 동안 기기 뒤로는 아무 일도 하지 않는다(뒤 화면이 닫히지 않게)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter/widgets.dart';

import 'sync.dart' show syncBase;

class NetStatus extends ChangeNotifier with WidgetsBindingObserver {
  NetStatus._();
  static final instance = NetStatus._();

  /// 붙어 보기(시험에서 바꿔 끼운다)
  Future<bool> Function() probe = _probe;

  /// 다시 볼 때까지(시험에서 줄인다)
  Duration retry = const Duration(milliseconds: 1500), onlineEvery = const Duration(seconds: 30), offlineEvery = const Duration(seconds: 4);

  bool _online = true;

  /// 인터넷에 닿는지(모르면 닿는 것으로 둔다: 확인 전에 막지 않는다)
  bool get online => _online;

  /// 막는 빌드인지: 서버가 있는 빌드(로그인 필수)만
  bool get enabled => forceEnabled ?? syncBase.isNotEmpty;

  /// 시험에서 서버 없는 빌드도 막는 빌드로
  @visibleForTesting
  bool? forceEnabled;

  Timer? _timer;
  Future<bool>? _checking;
  bool _started = false;

  /// 앱을 시작할 때 한 번(첫 화면보다 먼저: 기기 뒤로를 앱 화면보다 먼저 받는다)
  void start() {
    if (_started || !enabled) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    check().whenComplete(_schedule);
  }

  /// 시험이 끝나면 처음 상태로
  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _online = true;
    _checking = null;
    probe = _probe;
    forceEnabled = null;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_started) return;
    _timer = Timer(_online ? onlineEvery : offlineEvery, () => check().whenComplete(_schedule));
  }

  /// 지금 닿는지 본다(겹쳐 부르면 하나만 돈다)
  Future<bool> check() => _checking ??= _check().whenComplete(() => _checking = null);

  Future<bool> _check() async {
    var ok = await probe();
    if (!ok) {
      await Future<void>.delayed(retry);
      ok = await probe();
    }
    if (ok != _online) {
      _online = ok;
      notifyListeners();
    }
    return ok;
  }

  static Future<bool> _reach(String host, int port, Duration timeout) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _probe() async {
    final uri = Uri.tryParse(syncBase);
    if (uri != null && uri.host.isNotEmpty && await _reach(uri.host, uri.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443), const Duration(seconds: 4))) return true;
    return _reach('8.8.8.8', 53, const Duration(seconds: 3));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      check().whenComplete(_schedule);
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  // 막혀 있는 동안 기기 뒤로 · 뒤로 몸짓은 여기서 끝낸다(앱 화면 Navigator보다 먼저 등록돼 먼저 받는다)
  @override
  Future<bool> didPopRoute() async => !_online;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => !_online;
}
