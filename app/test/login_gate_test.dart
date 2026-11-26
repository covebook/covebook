// 로그인 필수(2026-11-16): 로그인 전에는 로그인 화면, 로그인하면 앱. 로그아웃 때 지울 기기 값과 남길 설정
import 'package:chaekjang/features/auth/login_screen.dart';
import 'package:chaekjang/services/sync.dart';
import 'package:chaekjang/store/local_reset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = SyncService.instance;
  tearDown(() {
    s.account = (kakao: false, google: false, apple: false, nickname: '');
    s.providers = (kakao: false, google: false, apple: false, accountDeletion: false);
  });

  Widget app(bool required) => MaterialApp(home: AuthGate(required: required, child: const Text('앱 첫 화면')));

  testWidgets('로그인 전이면 로그인 화면과 세 로그인 단추', (t) async {
    s.providers = (kakao: true, google: true, apple: true, accountDeletion: true);
    await t.pumpWidget(app(true));
    await t.pump();
    expect(find.text('앱 첫 화면'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.bySemanticsLabel('카카오로 계속하기'), findsOneWidget);
    expect(find.bySemanticsLabel('Apple로 계속하기'), findsOneWidget);
    expect(find.bySemanticsLabel('Google로 계속하기'), findsOneWidget);
  });

  testWidgets('로그인 수단을 못 받으면 다시 시도', (t) async {
    await t.pumpWidget(app(true));
    await t.pump();
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('하나라도 연결돼 있으면 앱이 열린다', (t) async {
    s.account = (kakao: false, google: false, apple: true, nickname: '');
    await t.pumpWidget(app(true));
    expect(find.text('앱 첫 화면'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('계정이 바뀌면 바로 로그인 화면으로(로그아웃)', (t) async {
    s.account = (kakao: true, google: false, apple: false, nickname: '');
    await t.pumpWidget(app(true));
    expect(find.text('앱 첫 화면'), findsOneWidget);
    s.account = (kakao: false, google: false, apple: false, nickname: '');
    s.notifyListeners();
    await t.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('서버 없는 빌드(시험)는 로그인 없이 앱', (t) async {
    await t.pumpWidget(MaterialApp(home: AuthGate(child: const Text('앱 첫 화면'))));
    expect(find.text('앱 첫 화면'), findsOneWidget);
  });

  test('로그아웃 때 지울 기기 값: 동기화·계정·독서·백업 기록은 지우고 설정은 남긴다', () {
    for (final k in ['sync-token:v1', 'sync-rev:v1', 'sync-files:v1', 'sync-paused:v1', 'sync-epoch:v1', 'account:v1', 'reading-state:v2', 'active-reading:v1', 'finished-reading:v1', 'last-backup:v1', 'sync-pulling-all:v1']) {
      expect(wipesKey(k), isTrue, reason: k);
    }
    for (final k in ['app-settings:v1', 'shelf-skin', 'spine-look', 'spine-look-books', 'cover-accents-v2', 'yes24-spine-ratios-v1']) {
      expect(wipesKey(k), isFalse, reason: k);
    }
  });
}
