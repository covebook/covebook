// 읽기 시작 규칙 하나(읽기 탭 줄 · '이어서 읽기', 책 정보·책 시트의 '읽기 시작'·'이어서 읽기'가 같이 쓴다. 같은 흐름이 세 벌 있었다, 2026-11-19):
// 끝냈지만 저장하지 않은 기록이 있으면 그것부터(독서 끝), 재는 중이 없으면 새로 시작(소리 함께), 그 책을 재는 중이면 이어서(멈춰 있으면 다시 시작),
// 다른 책을 재는 중이면 책 바꾸기 창(switch_book)을 따른다.
// 책 정보에서는 그 책으로 타이머를 시작하고 읽기 화면을 연다(2026-11-16 QA 영숙 F2: 읽기 탭 목록에 올리기만 하고 시계가 가지 않아, 표지 위 작은 ▶를 한참 찾았다).
// 2026-11-24 사용자 4단계: 읽기를 시작한 화면은 그대로 두고 그 위에 장면(또는 독서 끝)을 연다. 뒤로 나오거나 독서를 끝내면 시작한 화면으로 돌아온다
// (전에는 열린 화면을 모두 닫고 읽기 탭으로 바꿨다). 읽기 탭 목록에서 그 책이 맨 앞인 것은 그대로(AppNav.frontRead)
library;

import 'package:flutter/material.dart';

import '../../ui/alert.dart';
import '../../ui/feedback.dart';



import '../../domain/library.dart' show ReadStatus, currentRound;

import '../../app/app_nav.dart';
import '../../services/ambient.dart';
import '../../store/finish_reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../store/settings_store.dart';
import 'finish_screen.dart';
import 'reading_screen.dart' show readingSceneRoute;
import 'switch_book.dart';

/// 새 독서 시작: 그 책의 지금 쪽에서 타이머 + 지금 분위기 소리
void startNewReading(String? bookId) {
  final lib = LibraryModel.instance.lib;
  ReadingStore.instance.start(bookId, bookId == null ? null : lib.books[bookId]?.currentPage);
  Ambient.instance.play(SettingsStore.instance.scene);
}

/// 완독한 책을 새로 읽기 시작할 때: '다시 읽기를 시작할까요?'(새 회차). 모든 입구(책 정보 · 책장 시트 · 읽기 탭 · 공유)가 이 한 곳에서 묻는다
/// (2026-11-19 타이머 점검 B6: 책 정보만 물어서, 다른 입구에서 시작하면 끝난 회차에 기록이 붙었다). 고르지 않거나 새 회차를 저장하지 못하면 false
Future<bool> confirmReread(BuildContext context, String bookId) async {
  final model = LibraryModel.instance;
  final b = model.lib.books[bookId];
  final last = currentRound(model.lib, bookId);
  if (b == null || b.status != ReadStatus.read || last?.finishedAt == null) return true;
  // 창 단추는 창이 닫힐 때 불리고 기다려 주지 않는다: 고른 것만 적어 두고 새 회차 저장은 여기서 기다린다
  // (단추 안에서 저장을 기다린 뒤 ok를 바꿔, 창이 먼저 끝나 '다시 읽기'를 골라도 시작하지 않았다)
  Future<void>? reread;
  await appAlert(context, '다시 읽기를 시작할까요?', '${last!.index + 1}회차가 생기고 진도는 0쪽부터예요. 지난 회차의 완독일, 독서 기록, 갈피는 그대로 남아요.', [
    const AlertButton('취소', style: AlertStyle.cancel),
    AlertButton('다시 읽기', onPress: () => reread = model.reread(bookId)),
  ]);
  if (reread == null) return false;
  try {
    await reread;
    return true;
  } catch (e) {
    // 실패는 늘 알린다(DESIGN 11장)
    if (context.mounted) appAlert(context, '다시 읽기를 시작하지 못했어요', errorText(e));
    return false;
  }
}

/// 그 책(null은 책 없이)으로 읽기. 다 정한 뒤 [show]가 장면(finish: false)이나 독서 끝(finish: true)을 연다
Future<void> beginReading(BuildContext context, String? bookId, {required void Function({required bool finish}) show}) async {
  final reading = ReadingStore.instance;
  if (reading.pending != null) return show(finish: true);
  final cur = reading.active;
  // 지금 재는 책이 아니면(새로 시작 · 책 바꾸기) 완독한 책은 다시 읽기를 먼저 묻는다
  if (bookId != null && cur?.myBookId != bookId && !await confirmReread(context, bookId)) return;
  if (!context.mounted) return;
  if (cur == null) {
    startNewReading(bookId);
    return show(finish: false);
  }
  if (cur.myBookId == bookId) {
    if (cur.runningSince == null && !await resumeReadingOrTell(context)) return;
    return show(finish: false);
  }
  await switchReadingBook(context, bookId, then: () => show(finish: false));
}

/// 책 정보·책 시트·책 공유의 '읽기 시작'·'이어서 읽기': 지금 화면 위에 장면이나 독서 끝을 연다(읽기 탭 목록에서는 그 책이 맨 앞)
Future<void> startReadingBook(BuildContext context, String bookId) async {
  final reading = ReadingStore.instance;
  final model = LibraryModel.instance;
  try {
    await reading.load();
  } catch (_) {
    // 진행 기록을 못 읽어도 새로 시작은 된다(읽기 탭과 같다)
  }
  await model.load();
  if (!context.mounted || model.lib.books[bookId] == null) return;
  final nav = Navigator.of(context, rootNavigator: true);
  await beginReading(context, bookId, show: ({required bool finish}) {
    AppNav.instance.frontRead(bookId);
    nav.push(finish ? finishRoute() : readingSceneRoute());
  });
}

/// 이어서 읽기(멈춰 둔 독서). 지난 몫을 저장하지 못하면 확인창으로 알리고 false(실패는 조용히 끝나지 않는다, DESIGN 11장).
/// 작은 타이머 · 장면 · 읽기 시작 · 멈춰 둔 독서 창이 같은 문구를 쓴다
Future<bool> resumeReadingOrTell(BuildContext context) async {
  final e = await resumeReading();
  if (e == null) return true;
  if (context.mounted) appAlert(context, '이어서 읽지 못했어요', '지난 독서 기록은 그대로 있어요. 다음에 읽기를 시작하면 그 기록부터 저장해요. ${errorText(e)}');
  return false;
}
