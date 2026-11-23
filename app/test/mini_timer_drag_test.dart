// 작은 타이머(다른 화면에 뜨는 원): 꾹 누르지 않고 잡고 끌면 바로 옮겨진다(2026-11-24 사용자 '꾹 누르면 움직이게 말고 그냥 잡고 움직이면 바로 움직이게').
// 움직이지 않고 떼면 누르기 그대로(펼치기)
import 'package:chaekjang/domain/reading.dart';
import 'package:chaekjang/features/reading/mini_timer.dart';
import 'package:chaekjang/store/reading_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb;

Future<Finder> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final now = DateTime.now().millisecondsSinceEpoch;
  ReadingStore.instance.active = Active(id: 'ss1', startedAt: DateTime.now().toUtc().toIso8601String(), accumulatedMs: 0, runningSince: now, lastBeat: now);
  final nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(), builder: (c, child) => Stack(children: [child!, MiniTimer(navigator: nav)])));
  await t.pump(const Duration(milliseconds: 300));
  return find.descendant(of: find.byType(MiniTimer), matching: find.byType(AnimatedScale));
}

Future<void> _end(WidgetTester t) async {
  ReadingStore.instance.active = null;
  await t.pumpWidget(const SizedBox());
}

void main() {
  setUpAll(fakeDb);

  testWidgets('잡고 끌면 꾹 누르지 않아도 손가락만큼 옮겨진다', (t) async {
    final timer = await _pump(t);
    final before = t.getTopLeft(timer);
    // 누르자마자(기다림 없이) 끈다
    await t.drag(timer, const Offset(-80, -120));
    await t.pump(const Duration(milliseconds: 200));
    final after = t.getTopLeft(timer);
    expect(after.dx - before.dx, closeTo(-80, 1));
    expect(after.dy - before.dy, closeTo(-120, 1));
    expect(find.bySemanticsLabel('읽기 화면으로 가기'), findsNothing, reason: '끌기는 펼치지 않는다');
    await _end(t);
  });

  testWidgets('움직이지 않고 누르면 펼친다(끌기와 섞이지 않는다)', (t) async {
    final timer = await _pump(t);
    final before = t.getTopRight(timer);
    await t.tap(timer);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('읽기 화면으로 가기'), findsOneWidget);
    expect(t.getTopRight(timer), before, reason: '자리는 그대로(오른쪽 끝 기준으로 왼쪽으로 펼친다)');
    await _end(t);
  });
}
