// 읽는 중에 다른 책을 고르면(읽기 화면 · 읽기 탭 · 책 정보가 같이 쓴다): 묻지 않고 나눠 저장한다.
// 2026-11-20 사용자 '이건 왜 있는 거야? 그냥 아몬드로 읽기 시작했으면 아몬드지, 읽다가 책 바꾸면 나눠서 저장하고' →
// 지금까지 읽은 것은 지금 책 기록으로 저장하고 고른 책으로 새로 읽는다. 1분이 안 됐으면 잘못 고른 책을 바로잡는 것으로 보고 이 기록의 책만 바꾼다
// (몇 초짜리 기록이 따로 생기지 않게). 어느 쪽이든 토스트로 알린다(DESIGN 14장: 다른 곳에 기록이 생긴다)
library;

import 'package:flutter/widgets.dart';

import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../store/finish_reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/feedback.dart';
import '../stats/stats_widgets.dart' show bookTitle;

/// 이보다 짧게 읽었으면 나누지 않고 이 기록의 책만 바꾼다
const _splitFromMs = 60 * 1000;

/// 재는 중에 다른 책으로. [chosen]은 고르자마자(장면이 고른 책을 먼저 보이게), [then]은 다 바꾼 뒤(장면 열기)
Future<void> switchReadingBook(BuildContext context, String? nextId, {VoidCallback? chosen, VoidCallback? then}) async {
  final reading = ReadingStore.instance;
  final cur = reading.active;
  if (cur == null) return;
  final lib = LibraryModel.instance.lib;
  final curTitle = bookTitle(lib, cur.myBookId);
  final nextTitle = bookTitle(lib, nextId);
  final next = nextTitle != null ? '‘$nextTitle’${josa(nextTitle, '을', '를')}' : '책 없이';
  final elapsed = reading.elapsed;
  chosen?.call();
  if (elapsed < _splitFromMs) {
    reading.setBook(nextId, nextId == null ? null : lib.books[nextId]?.currentPage);
    then?.call();
    if (context.mounted) showToast(context, nextTitle != null ? '$next 읽고 있어요.' : '책 없이 읽고 있어요.');
    return;
  }
  final so = formatDurationShort(elapsed);
  final saved = curTitle != null ? '‘$curTitle’ ${withJosa(so, '을', '를')}' : '책 없이 읽은 ${withJosa(so, '을', '를')}';
  try {
    await saveAndStartOther(nextId);
  } catch (e) {
    // 저장하지 못하면 지금까지 읽은 것은 저장 전 기록으로 남는다(읽기 탭 '저장하지 않은 독서 기록'). 예외 원문은 보이지 않는다
    if (context.mounted) appAlert(context, '저장하지 못했어요', '지금까지 읽은 기록은 읽기 탭에 남아 있어요. ${errorText(e)}');
    return;
  }
  then?.call();
  if (context.mounted) showToast(context, '$saved 저장하고 ${nextTitle != null ? '$next 새로 읽어요' : '책 없이 새로 읽어요'}.');
}
