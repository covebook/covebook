// 읽기 시작 규칙 하나(읽기 탭 줄 · '이어서 읽기', 책 정보·책 시트의 '읽기 시작'·'이어서 읽기'가 같이 쓴다. 같은 흐름이 세 벌 있었다, 2026-11-19):
// 끝냈지만 저장하지 않은 기록이 있으면 그것부터(독서 끝), 재는 중이 없으면 새로 시작(소리 함께), 그 책을 재는 중이면 이어서(멈춰 있으면 다시 시작),
// 다른 책을 재는 중이면 책 바꾸기 창(switch_book)을 따른다.
// 책 정보에서는 그 책으로 타이머를 시작하고 읽기 화면을 연다(2026-11-16 QA 영숙 F2: 읽기 탭 목록에 올리기만 하고 시계가 가지 않아, 표지 위 작은 ▶를 한참 찾았다).
// 장면에서 뒤로 나오면 읽기 탭 목록이다(그 책이 맨 앞)
library;

import 'package:flutter/material.dart';

import '../../app/app_nav.dart';
import '../../services/ambient.dart';
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
  if (bookId != null) LibraryModel.instance.markReadingStarted(bookId);
  Ambient.instance.play(SettingsStore.instance.scene);
}

/// 그 책(null은 책 없이)으로 읽기. 다 정한 뒤 [show]가 장면(finish: false)이나 독서 끝(finish: true)을 연다
Future<void> beginReading(BuildContext context, String? bookId, {required void Function({required bool finish}) show}) async {
  final reading = ReadingStore.instance;
  if (reading.pending != null) return show(finish: true);
  final cur = reading.active;
  if (cur == null) {
    startNewReading(bookId);
    return show(finish: false);
  }
  if (cur.myBookId == bookId) {
    if (cur.runningSince == null) reading.resume();
    return show(finish: false);
  }
  await switchReadingBook(context, bookId, then: () => show(finish: false));
}

/// 책 정보·책 시트의 '읽기 시작'·'이어서 읽기': 책장·책 정보는 닫고 읽기 탭(그 책을 맨 앞에) 위에 장면이나 독서 끝을 연다
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
    nav.popUntil((r) => r.isFirst);
    AppNav.instance.goRead(bookId);
    nav.push(finish ? finishRoute() : readingSceneRoute());
  });
}
