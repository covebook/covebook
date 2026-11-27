// 통계 캘린더: 주마다 표지 자리를 늘 두어 기록 없는 주도 같은 높이, 기록이 생겨도 달력 높이가 그대로다
// (11-25 빈 주를 낮췄다가 2026-11-26 사용자 '기존이 낫다'로 되돌림)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/stats/chart_data.dart';
import 'package:chaekjang/features/stats/stats_widgets.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-01T01:00:00.000Z';

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '아몬드', authors: const ['손원평'], source: 'photo', createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1)},
    );

Future<void> pump(WidgetTester t, Map<String, DayBooks> days) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        // 2026년 11월: 1일이 일요일이라 1~7 · 8~14 · 15~21 · 22~28 · 29~30
        child: ReadingCalendar(lib: lib(), y: 2026, m: 11, days: days, selected: null, today: '2026-11-25', onSelect: (_) {}),
      ),
    ),
  ));
}

Rect cell(WidgetTester t, int n) => t.getRect(find.bySemanticsLabel(RegExp('^$n일,')));

void main() {
  testWidgets('기록 없는 주도 표지 자리까지 같은 높이', (t) async {
    await pump(t, {'2026-11-10': const DayBooks(['bk1'], false, 600000)});
    final full = cell(t, 10).height;
    expect(full, greaterThan(70), reason: '숫자 24 + 2 + 표지 자리 52');
    for (final d in [3, 8, 24, 30]) {
      expect(cell(t, d).height, full, reason: '$d일');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('빈 주에 기록이 생겨도 달력 높이는 그대로', (t) async {
    await pump(t, {'2026-11-10': const DayBooks(['bk1'], false, 600000)});
    final before = cell(t, 30).bottom;
    await pump(t, {'2026-11-10': const DayBooks(['bk1'], false, 600000), '2026-11-24': const DayBooks(['bk1'], false, 300000)});
    expect(cell(t, 30).bottom, before);
  });
}
