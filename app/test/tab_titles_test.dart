// 6단계(2026-11-24 사용자): 하단바 아이콘 아래 이름(글자 11, 색은 아이콘과 같게, 고른 탭은 진하게, 알약(TabBarStyle.height, 토스증권 사진 참고 56) 안, 이름은 한 번만 읽힘)과
// 탭 다섯 화면 왼쪽 위 큰 제목 없애기(화면 읽기 머리는 남김, 첫 줄은 위 여백 4 바로 아래). 내 책: 맨 위 상태 탭, 둘째 줄 '책 N권' · 검색 · 보기 · 필터 · ＋,
// '선택' 글자 단추 없음(길게 눌러 고르면 둘째 줄이 'N권 선택' · '취소'), 검색은 맨 위 한 줄. 기록: '갈피 | 감상' 줄 오른쪽에 검색 · ＋
import 'package:chaekjang/app/app_shell.dart' show TabBarItem;
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/book/all_books_screen.dart';
import 'package:chaekjang/features/home/home_screen.dart' show homeHeaderForTest, homeHeaderHeight;
import 'package:chaekjang/features/record/record_tab.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/library_store.dart' show saveLayout;
import 'package:chaekjang/store/placement_store.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb, lib, shelfBook;

Future<void> _view(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: home,
    );

void main() {
  setUpAll(fakeDb);

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('하단 탭 하나: 아이콘 아래 이름(11, 아이콘 색), 알약 56 안, 이름은 화면 읽기에 한 번 (글자 ×$scale)', (t) async {
      await _view(t);
      final taps = <int>[];
      await t.pumpWidget(_app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: TabBarStyle.height,
              child: Row(children: [
                for (final (i, n) in const ['책장', '내 책', '읽기', '기록', '통계'].indexed)
                  Expanded(child: TabBarItem(label: n, icon: (c, f) => Icon(Icons.circle, size: TabBarStyle.icon, color: c), selected: i == 0, onTap: () => taps.add(i))),
              ]),
            ),
          ),
        ),
        scale: scale,
      ));
      final bar = t.getRect(find.byType(Row).last);
      for (final n in ['책장', '내 책', '읽기', '기록', '통계']) {
        final r = t.getRect(find.text(n));
        expect(r.top, greaterThanOrEqualTo(bar.top), reason: n);
        expect(r.bottom, lessThanOrEqualTo(bar.bottom + 0.5), reason: '$n 이름이 막대 안');
        expect(find.bySemanticsLabel(n), findsOneWidget, reason: '$n 은 한 번만 읽힌다');
      }
      final sel = t.widget<Text>(find.text('책장')).style!, other = t.widget<Text>(find.text('통계')).style!;
      expect(sel.fontSize, 11);
      expect(sel.color, AppColors.tabInk);
      expect(other.color, AppColors.tabInkSoft);
      await t.tap(find.text('기록'));
      expect(taps, [3]);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('탭 화면 제목 숨김(hideTitle): 큰 제목 글자 없이 화면 읽기 머리만, 첫 줄은 위 여백(TabHeader.paddingTop) 바로 아래', (t) async {
    await _view(t);
    await t.pumpWidget(_app(const Screen(back: false, title: '읽기', hideTitle: true, children: [Text('첫 줄')])));
    expect(find.text('읽기'), findsNothing);
    expect(find.bySemanticsLabel('읽기'), findsOneWidget);
    final top = MediaQuery.paddingOf(t.element(find.text('첫 줄'))).top;
    expect(t.getRect(find.text('첫 줄')).top, closeTo(top + TabHeader.paddingTop, 0.5));
  });

  group('내 책', () {
    final m = LibraryModel.instance, p = PlacementStore.instance;
    void use() {
      m.useForTest(lib());
      m.writeChanges = (_) async {};
      p.writeLayout = (_, _) async {};
      p.books = {'b1': shelfBook('b1', '소년이 온다'), 'b2': shelfBook('b2', '모순')};
      p.layout = const ShelfLayout([Shelf('s1', 0)], [], ['b1', 'b2']);
    }

    tearDown(() {
      m.writeChanges = applyLocalChanges;
      p.writeLayout = saveLayout;
    });

    testWidgets('맨 위 상태 탭, 둘째 줄 책 N권 · 검색 · 보기 · 필터 · ＋, 선택 글자 없음. 길게 누르면 둘째 줄이 N권 선택 · 취소. 검색은 맨 위 한 줄', (t) async {
      use();
      await _view(t);
      await t.pumpWidget(_app(const AllBooksScreen()));
      await t.pumpAndSettle();
      expect(find.text('내 책'), findsNothing, reason: '왼쪽 위 제목 없음');
      expect(find.text('선택'), findsNothing);
      final tabs = t.getRect(find.text('전체'));
      final count = t.getRect(find.text('책 2권'));
      expect(tabs.top, lessThan(count.top), reason: '상태 탭이 맨 위');
      for (final Pattern l in ['내 책 검색', RegExp('^(목록으로|표지 격자로) 보기\$'), '책 추가']) {
        final r = t.getRect(find.bySemanticsLabel(l));
        expect((r.center.dy - count.center.dy).abs(), lessThan(4), reason: '$l 은 책 N권 줄');
      }
      // 길게 눌러 고르기
      await t.longPress(find.text('모순').first);
      await t.pumpAndSettle();
      expect(find.text('1권 선택'), findsOneWidget);
      expect(find.text('취소'), findsOneWidget);
      expect((t.getRect(find.text('1권 선택')).center.dy - t.getRect(find.text('취소')).center.dy).abs(), lessThan(4));
      expect(t.getRect(find.text('1권 선택')).top, greaterThan(tabs.bottom), reason: '상태 탭 아래 둘째 줄');
      await t.tap(find.text('취소'));
      await t.pumpAndSettle();
      // 검색: 맨 위 한 줄에 검색칸, 끄면 사라진다
      await t.tap(find.bySemanticsLabel('내 책 검색'));
      await t.pumpAndSettle();
      final field = find.byType(SearchField);
      expect(field, findsOneWidget);
      expect(t.getRect(field).bottom, lessThanOrEqualTo(t.getRect(find.text('전체')).top + 1), reason: '검색칸이 맨 위');
    });
  });

  testWidgets('기록: 왼쪽 위 제목 없이 갈피 | 감상 줄 오른쪽에 검색 · ＋', (t) async {
    LibraryModel.instance.useForTest(lib());
    await _view(t);
    await t.pumpWidget(_app(const RecordTab()));
    await t.pumpAndSettle();
    expect(find.text('기록'), findsNothing);
    final tabs = t.getRect(find.text('갈피').first);
    for (final l in ['갈피 검색', '갈피 추가']) {
      expect((t.getRect(find.bySemanticsLabel(l)).center.dy - tabs.center.dy).abs(), lessThan(6), reason: '$l 은 갈피 | 감상 줄');
    }
    await t.tap(find.bySemanticsLabel('갈피 검색'));
    await t.pumpAndSettle();
    expect(find.byType(SearchField), findsOneWidget);
    expect(t.getRect(find.byType(SearchField)).bottom, lessThanOrEqualTo(t.getRect(find.text('갈피').first).top + 1));
  });

  testWidgets('책장 머리: 보이는 글자 없이(나의 책장 · 해 없음, 2026-11-24 사용자 \'2026도 없애버려\') 오른쪽 아이콘 셋, 화면 읽기 머리는 나의 책장, 2026, 높이는 homeHeaderHeight', (t) async {
    await _view(t);
    var added = 0;
    await t.pumpWidget(_app(Scaffold(body: Align(alignment: Alignment.topCenter, child: homeHeaderForTest(year: 2026, onAdd: () => added++)))));
    expect(find.text('나의 책장'), findsNothing);
    expect(find.text('2026'), findsNothing);
    expect(find.bySemanticsLabel('나의 책장, 2026'), findsOneWidget);
    final year = t.getRect(find.bySemanticsLabel('나의 책장, 2026'));
    expect(year.left, closeTo(TabHeader.paddingH, 1));
    for (final l in ['꾸미기', '책장에 꽂기', '내 정보']) {
      final r = t.getRect(find.bySemanticsLabel(l));
      expect(r.width, Space.hit, reason: l);
      expect(r.left, greaterThan(360 / 2), reason: '$l 은 오른쪽');
      expect((r.center.dy - year.center.dy).abs(), lessThan(2), reason: '$l 은 머리줄 가운데');
    }
    expect(t.getSize(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Header')).height, closeTo(homeHeaderHeight, 0.5));
    // 누르기는 아이콘 줄 전체 칸이 받는다(화면 읽기 칸은 자리만)
    await t.tap(find.bySemanticsLabel('책장에 꽂기'), warnIfMissed: false);
    expect(added, 1);
    expect(t.takeException(), isNull);
  });
}

