// 책 정보·책 시트의 '읽기 시작'·'이어서 읽기': 그 책으로 타이머를 시작하고 읽기 화면을 연다
// (2026-11-16 QA 영숙 F2: 읽기 탭 목록에 올리기만 하고 시계가 가지 않아, 표지 위 작은 ▶를 한참 찾았다).
// 읽기 탭 재생 단추와 같은 규칙: 끝냈지만 저장하지 않은 기록이 있으면 그것부터, 그 책을 재는 중이면 이어서(멈춰 있으면 다시 시작),
// 다른 책을 재는 중이면 책 바꾸기 창(switch_book)을 따른다. 장면에서 뒤로 나오면 읽기 탭 목록이다(그 책이 맨 앞)
library;

import 'package:flutter/material.dart';

import '../../app/app_nav.dart';
import '../../services/ambient.dart';
import '../../store/finish_reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../store/settings_store.dart';
import '../../ui/alert.dart';
import 'finish_screen.dart';
import 'reading_screen.dart' show readingSceneRoute;
import 'switch_book.dart';

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

  // 책장·책 정보는 닫고 읽기 탭(그 책을 맨 앞에) 위에 장면을 연다
  void open(Route<void> route) {
    nav.popUntil((r) => r.isFirst);
    AppNav.instance.goRead(bookId);
    nav.push(route);
  }

  if (reading.pending != null) {
    open(MaterialPageRoute<void>(settings: const RouteSettings(name: '/reading/finish'), builder: (_) => const FinishScreen()));
    return;
  }
  final cur = reading.active;
  final page = model.lib.books[bookId]?.currentPage;
  if (cur == null) {
    reading.start(bookId, page);
    Ambient.instance.play(SettingsStore.instance.scene);
    return open(readingSceneRoute());
  }
  if (cur.myBookId == bookId) {
    if (cur.runningSince == null) reading.resume();
    return open(readingSceneRoute());
  }
  await askSwitchBook(
    context,
    lib: model.lib,
    curId: cur.myBookId,
    nextId: bookId,
    elapsedMs: reading.elapsed,
    onSaveNew: () {
      saveAndStartOther(bookId).then((_) => open(readingSceneRoute()), onError: (Object e) {
        if (context.mounted) appAlert(context, '저장하지 못했어요', '$e');
      });
    },
    onMove: () {
      reading.setBook(bookId, page);
      open(readingSceneRoute());
    },
  );
}
