// 작은 타이머(다른 화면에 뜨는 원): 꾹 누르지 않고 잡고 끌면 바로 옮겨진다(2026-11-24 사용자 '꾹 누르면 움직이게 말고 그냥 잡고 움직이면 바로 움직이게').
// 움직이지 않고 떼면 누르기 그대로(펼치기). 끄는 동안 아래 가운데 빼기 자리, 거기에 놓으면 일시정지하고 숨긴다(2026-11-25 사용자)
import 'package:chaekjang/app/idle_bars.dart';
import 'package:chaekjang/domain/reading.dart';
import 'package:chaekjang/features/home/decorate_panel.dart' show RemoveZone;
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
  // 끌기를 놓으면 '가만히 있으면 내리기'가 3초를 새로 잰다: 시험 끝에 멈춘다
  IdleBars.instance.stop();
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

  testWidgets('끄는 동안 아래 가운데 빼기 자리, 거기에 놓으면 일시정지하고 숨긴다(시간은 그대로), 되돌리기로 다시 재며 나타난다', (t) async {
    final timer = await _pump(t);
    expect(find.byType(RemoveZone), findsNothing);
    final g = await t.startGesture(t.getCenter(timer));
    await g.moveBy(const Offset(-20, 30));
    await t.pump();
    expect(find.byType(RemoveZone), findsOneWidget, reason: '끄는 동안 빼기 자리');
    // 끄는 동안은 '가만히 있으면 내리기'를 붙잡는다(3초가 지나도 타이머가 손가락 아래에서 사라지지 않게)
    IdleBars.instance.canHide = () => true;
    await t.pump(const Duration(seconds: 4));
    expect(IdleBars.instance.down, isFalse);
    expect(find.byType(RemoveZone), findsOneWidget);
    IdleBars.instance.canHide = null;
    // 화면 아래 가운데(안전 영역 위 RemoveZone.lift)
    await g.moveTo(const Offset(180, 800 - RemoveZone.lift));
    await t.pump();
    expect(t.widget<RemoveZone>(find.byType(RemoveZone)).active, isTrue);
    await g.up();
    await t.pump(const Duration(milliseconds: 300));
    expect(ReadingStore.instance.active, isNotNull, reason: '독서는 남는다');
    expect(ReadingStore.instance.running, isFalse, reason: '일시정지');
    expect(timer, findsNothing, reason: '작은 타이머를 숨긴다');
    expect(find.byType(RemoveZone), findsNothing);
    expect(find.text('되돌리기'), findsOneWidget);
    await t.tap(find.text('되돌리기'));
    await t.pump(const Duration(milliseconds: 300));
    expect(ReadingStore.instance.running, isTrue, reason: '되돌리면 다시 잰다');
    expect(timer, findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    // 다시 재며 켠 심장 박동(주기 타이머)을 멈추고 끝낸다
    ReadingStore.instance.pause();
    await _end(t);
  });

  testWidgets('빼기 자리 밖에 놓으면 그 자리에 남는다(하단 탭 위로)', (t) async {
    final timer = await _pump(t);
    await t.drag(timer, const Offset(-150, -40));
    await t.pump(const Duration(milliseconds: 200));
    expect(timer, findsOneWidget);
    expect(find.byType(RemoveZone), findsNothing);
    expect(ReadingStore.instance.running, isTrue);
    await _end(t);
  });

  testWidgets('움직이지 않고 누르면 펼친다(끌기와 섞이지 않는다)', (t) async {
    final timer = await _pump(t);
    final before = t.getTopRight(timer);
    await t.tap(timer);
    // 펼치는 움직임이 시작되는 프레임 + 다 펼쳐지는 시간
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('읽기 화면으로 가기'), findsOneWidget);
    expect(t.getTopRight(timer), before, reason: '자리는 그대로(오른쪽 끝 기준으로 왼쪽으로 펼친다)');
    await _end(t);
  });
}
