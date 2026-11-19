// 실패 문구(docs/design/DESIGN.md 9장 '실패 알림'): 화면에 예외 원문 · 영어 · 상태 번호를 보이지 않는다. 원문은 로그로
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_error.dart';

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

