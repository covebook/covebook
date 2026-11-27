// 책장 탭에서 가만히 있으면 아래를 비운다(2026-11-25 사용자 '3초 정도 가만히 있으면 하단바 내려가서 책장만 온전히 보이게,
// 화면 터치하면 다시 보이게, 위아래로 내리면 그냥 안 보이게, 2번 연속 터치하면 보이게, 휴대폰 뒤로가기 이런 거처럼 내려가게')
import 'package:chaekjang/app/idle_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bars = IdleBars.instance;
  final modes = <Object?>[];
  setUp(() {
    modes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method.startsWith('SystemChrome.setEnabledSystemUI')) modes.add('${c.method}:${c.arguments}');
      return null;
    });
  });
  tearDown(() {
    bars.canHide = null;
    bars.stop();
  });

  Future<void> pump(WidgetTester t, {bool Function()? can}) async {
    bars.canHide = can ?? () => true;
    await t.pumpWidget(MaterialApp(
      home: IdleBarsListener(child: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('줄 $i'))])),
    ));
    bars.poke();
  }

  testWidgets('3초 가만히 있으면 내린다(시스템 아래 막대도 숨김), 누르면 올리고 3초를 새로 잰다, 두 번 눌러도 올라온다', (t) async {
    await pump(t);
    await t.pump(const Duration(milliseconds: 2900));
    expect(bars.down, isFalse);
    await t.pump(const Duration(milliseconds: 200));
    expect(bars.down, isTrue, reason: '3초 뒤 내림');
    expect('${modes.last}', contains('SystemUiOverlay.top'), reason: '시스템 아래 막대를 숨기고 위 상태 표시줄만 남긴다');
    expect('${modes.last}', isNot(contains('bottom')));
    await t.tap(find.text('줄 2'));
    expect(bars.down, isFalse, reason: '누르면 올라온다');
    await t.pump(const Duration(seconds: 2));
    expect(bars.down, isFalse, reason: '누른 뒤 3초를 새로 잰다');
    await t.pump(const Duration(milliseconds: 1100));
    expect(bars.down, isTrue);
    // 두 번 연달아 눌러도 올라온다
    await t.tap(find.text('줄 3'));
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(find.text('줄 3'));
    expect(bars.down, isFalse);
    bars.stop();
  });

  testWidgets('위아래로 밀면 바로 내리고(스크롤은 그대로), 밀기를 마쳐도 올리지 않는다', (t) async {
    await pump(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(bars.down, isFalse);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(bars.down, isTrue, reason: '밀면 바로 내림');
    expect(find.text('줄 0'), findsNothing, reason: '스크롤은 그대로 된다(맨 위 줄이 밀려 나갔다)');
    await t.pump(const Duration(seconds: 1));
    expect(bars.down, isTrue);
    bars.stop();
  });

  testWidgets('내리면 안 될 때(시트 · 꾸미기 · 다른 화면)는 내리지 않고, 다른 탭으로 가면 올리고 재지 않는다', (t) async {
    var can = false;
    await pump(t, can: () => can);
    await t.pump(const Duration(seconds: 4));
    expect(bars.down, isFalse);
    can = true;
    await t.pump(const Duration(seconds: 3));
    expect(bars.down, isTrue, reason: '되면 다음 3초에 내린다');
    bars.stop();
    expect(bars.down, isFalse);
    await t.pump(const Duration(seconds: 4));
    expect(bars.down, isFalse, reason: '멈추면 다시 재지 않는다');
  });

  testWidgets('붙잡은 동안(작은 타이머를 끄는 중)은 3초가 지나도 밀어도 내리지 않고, 놓으면 3초를 새로 잰다', (t) async {
    await pump(t);
    bars.hold();
    await t.pump(const Duration(seconds: 5));
    expect(bars.down, isFalse);
    bars.hideNow();
    expect(bars.down, isFalse);
    bars.release();
    await t.pump(const Duration(milliseconds: 2900));
    expect(bars.down, isFalse);
    await t.pump(const Duration(milliseconds: 200));
    expect(bars.down, isTrue);
    bars.stop();
  });

  test('시스템 막대를 숨긴 동안 책장 배치용 아래 여백은 숨기기 전 값', () {
    bars.canHide = () => true;
    expect(bars.stableBottom(48), 48);
    bars.hideNow();
    expect(bars.stableBottom(0), 48, reason: '숨긴 동안 0이 와도 48');
    bars.poke();
    expect(bars.stableBottom(48), 48);
  });
}
