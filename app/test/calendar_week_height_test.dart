// 통계 캘린더: 표지가 하나도 없는 주는 날짜 숫자 줄만(누르는 높이 48), 그 주에 기록이 생기면 표지 자리만큼 높아진다
// (2026-11-25 사용자 '좀 줄이고 추가하면 늘리는 거': 전에는 주마다 표지 자리를 늘 비워 두어 마지막 주가 떠 보였다)
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
  testWidgets('표지 없는 주는 48, 표지 있는 주는 표지 자리만큼 높다', (t) async {
    await pump(t, {'2026-11-10': const DayBooks(['bk1'], false, 600000)});
    final full = cell(t, 10).height;
    expect(full, greaterThan(80), reason: '숫자 24 + 2 + 표지 자리 52 + 위아래 6');
    expect(cell(t, 8).height, full, reason: '같은 주 빈 날도 같은 높이');
    expect(cell(t, 3).height, Space.hit, reason: '표지 없는 주는 누르는 높이만');
    expect(cell(t, 24).height, Space.hit);
    expect(cell(t, 30).height, Space.hit, reason: '마지막 주가 비면 낮다');
    expect(t.takeException(), isNull);
  });

  testWidgets('빈 주에 기록이 생기면 그 주만 높아진다', (t) async {
    await pump(t, {'2026-11-10': const DayBooks(['bk1'], false, 600000)});
    final full = cell(t, 10).height;
    final before = cell(t, 30).bottom;
    await pump(t, {'2026-11-10': const DayBooks(['bk1'], false, 600000), '2026-11-24': const DayBooks(['bk1'], false, 300000)});
    expect(cell(t, 24).height, full);
    expect(cell(t, 30).height, Space.hit);
    expect(cell(t, 30).bottom - before, closeTo(full - Space.hit, 0.5), reason: '달력 전체가 그 주 표지 자리만큼 길어진다');
  });
}
