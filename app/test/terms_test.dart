// 이용약관: 내 정보에서 열면 외부 제공 정보(표지) 조항이 보이고, 문서 초안과 앱 전문이 같은 조를 가진다(2026-11-18)
import 'dart:io';

import 'package:chaekjang/features/settings/terms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('이용약관 화면: 제6조 외부 제공 정보와 기본 표지 대체 문구', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => openTermsPage(c), child: const Text('열기'))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('이용약관'), findsOneWidget);
    await t.scrollUntilVisible(find.text('제6조 (외부 제공 정보)'), 300, scrollable: find.byType(Scrollable).last);
    // 낱말 단위 줄바꿈(keepAll)이 글자 사이에 이음표를 넣으니 빼고 찾는다
    final clause = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll(RegExp('[\u2060\u200B\uFEFF]'), '').contains('기본 표지로 대체될 수 있으며'));
    expect(clause, findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('문서 초안(docs/legal/terms-draft-2026-11-18.md)과 앱 전문이 같은 조 제목', () {
    final doc = File('../docs/legal/terms-draft-2026-11-18.md').readAsStringSync();
    for (final (title, paras) in termsArticles) {
      expect(doc.contains('### $title'), isTrue, reason: title);
      for (final p in paras) {
        expect(doc.contains(p), isTrue, reason: p);
      }
    }
  });
}
