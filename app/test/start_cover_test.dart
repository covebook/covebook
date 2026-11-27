// 로딩 화면(2026-11-27 사용자 시안): 로그인 화면과 같은 책장 그림 · '책장 한켠' · 두 줄 소개, 책장은 로그인보다 아래, 맨 아래 갈색 원 + 준비 단계 글
import 'package:chaekjang/app/startup.dart';
import 'package:chaekjang/features/auth/login_screen.dart' show loginShelfAsset;
import 'package:chaekjang/ui/kit.dart' show Spinner;
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => startStep.value = 1);

  testWidgets('책장 그림 → 이름 · 소개 → 맨 아래 원 + 단계 글(여는 중 → 진열하는 중 → 정리하는 중)', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    startStep.value = 1;
    await t.pumpWidget(const MaterialApp(home: StartCover()));
    await t.pump(const Duration(milliseconds: 300));
    final art = find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == loginShelfAsset);
    expect(art, findsOneWidget, reason: '로그인 화면과 같은 책장 그림');
    final title = find.text('책장 한켠');
    expect(t.widget<Text>(title).style?.fontSize, AppType.hero.fontSize);
    expect(t.getRect(art).top, greaterThan(80), reason: '로그인(맨 위 16)보다 아래로');
    expect(t.getRect(title).top, greaterThan(t.getRect(art).bottom));
    final spin = t.widget<Spinner>(find.byType(Spinner));
    expect(spin.color, AppColors.inkSoft, reason: '회색 원(2026-11-27 댓글)');
    expect(find.text('책장을 여는 중'), findsOneWidget);
    expect(t.getRect(find.text('책장을 여는 중')).top, greaterThan(t.getRect(find.textContaining('읽은 시간과 문장을')).bottom + 40), reason: '맨 아래');
    startStep.value = 2;
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('책을 진열하는 중'), findsOneWidget);
    startStep.value = 3;
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('책장을 정리하는 중'), findsOneWidget);
    startStep.value = 4;
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('책장을 정리하는 중'), findsOneWidget, reason: '다 된 뒤에도 마지막 글 그대로');
  });

  testWidgets('낮은 화면에서도 넘치지 않는다(그림만 줄어든다)', (t) async {
    t.view.physicalSize = const Size(720, 1280);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: StartCover()));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.text('책장을 여는 중'), findsOneWidget);
  });
}
