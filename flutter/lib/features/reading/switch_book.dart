// 읽는 중에 다른 책을 고르면 묻는 창(읽기 화면·읽기 탭이 같이 쓴다).
// 바꿀 책 이름과 지금까지 시간을 보이고, 진한 기본 버튼은 안전한 쪽('지금까지 저장하고 새로 읽기')이다
// (2026-11-15 QA 수아 F4: 진한 버튼이 '이 기록의 책을 바꾸기'라 졸린 밤에 누르면 15분이 통째로 다른 책 기록이 됐다)
library;

import 'package:flutter/widgets.dart';

import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../ui/alert.dart';
import 'read_list.dart' show bookTitle;

/// 버튼에 넣을 책 이름(길면 줄인다)
String _short(String s) => s.characters.length > 12 ? '${s.characters.take(11)}…' : s;

/// 지금까지 시간(1분이 안 되면 초까지)
String _sofar(num ms) => ms < 60000 ? formatDurationPrecise(ms) : formatDuration(ms);

Future<void> askSwitchBook(
  BuildContext context, {
  required Library lib,
  required String? curId,
  required String? nextId,
  required num elapsedMs,
  required VoidCallback onSaveNew,
  required VoidCallback onMove,
}) {
  final cur = bookTitle(lib, curId);
  final next = bookTitle(lib, nextId);
  final so = _sofar(elapsedMs);
  final reading = cur != null ? '지금 ‘$cur’${josa(cur, '을', '를')} $so째 읽는 중이에요.' : '지금 책 없이 $so째 읽는 중이에요.';
  final saved = cur != null ? '‘$cur’ 기록으로' : '책 없는 기록으로';
  return appAlert(
    context,
    '읽는 책을 바꿀까요?',
    '$reading 새로 읽으면 지금까지 ${withJosa(so, '은', '는')} $saved 저장돼요.',
    [
      const AlertButton('계속 읽기', style: AlertStyle.cancel),
      AlertButton(next != null ? '저장하고 ‘${_short(next)}’ 새로 읽기' : '저장하고 책 없이 새로 읽기', onPress: onSaveNew),
      AlertButton(next != null ? '${withJosa(so, '을', '를')} ‘${_short(next)}’ 기록으로 옮기기' : '${withJosa(so, '을', '를')} 책 없는 기록으로 옮기기', onPress: onMove),
    ],
    true,
    true,
  );
}
