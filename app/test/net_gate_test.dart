// 인터넷이 없으면 앱 전체를 막는다(2026-11-21 사용자 '인터넷이 없으면 막자', SCREENS 314): 막는 화면 · 다시 시도로 걷힘 · 막힌 동안 기기 뒤로를 받아 끝냄
import 'package:chaekjang/app/net_gate.dart';
import 'package:chaekjang/services/net_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final net = NetStatus.instance;
  tearDown(net.reset);

  testWidgets('인터넷이 없으면 모든 화면 위를 막고, 다시 시도로 연결되면 걷힌다', (t) async {
    var up = false;
    net
      ..forceEnabled = true
      ..retry = Duration.zero
      ..probe = () async => up;
    await t.pumpWidget(MaterialApp(builder: (c, child) => NetGate(child: child!), home: const Scaffold(body: Text('책장'))));
    expect(find.text('인터넷에 연결되어 있지 않아요'), findsNothing, reason: '확인 전에는 막지 않는다');
    await t.runAsync(net.check);
    await t.pump();
    expect(find.text('인터넷에 연결되어 있지 않아요'), findsOneWidget);
    expect(find.text('책장').hitTestable(), findsNothing, reason: '아래 화면은 누를 수 없다');
    expect(await net.didPopRoute(), isTrue, reason: '막힌 동안 기기 뒤로는 여기서 끝낸다');
    up = true;
    await t.tap(find.text('다시 시도'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    expect(find.text('인터넷에 연결되어 있지 않아요'), findsNothing);
    expect(find.text('책장').hitTestable(), findsOneWidget);
    expect(await net.didPopRoute(), isFalse);
  });

  testWidgets('서버 없는 빌드는 막지 않는다', (t) async {
    net
      ..retry = Duration.zero
      ..probe = () async => false;
    await t.pumpWidget(MaterialApp(builder: (c, child) => NetGate(child: child!), home: const Scaffold(body: Text('책장'))));
    await t.runAsync(net.check);
    await t.pump();
    expect(find.text('인터넷에 연결되어 있지 않아요'), findsNothing);
  });
}
