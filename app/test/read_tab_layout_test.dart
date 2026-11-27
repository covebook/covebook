// 읽기 탭 배치(2026-11-25 사용자 시안, 2026-11-26 머리): 맨 위 가운데 '‹ 날짜 ›'(전날 · 다음 날 기록 보기), 그 아래 '오늘 N'(2026-11-27 '오늘 읽은 시간'에서) · 오른쪽 '시간 추가',
// 최근 읽던 책 표지 92 · 제목은 표지 위 끝 줄 · 오늘 시간은 단추 오른쪽 위 · 단추 아래 끝은 표지 아래 끝, '+ 책 추가'는 목록 아래(제목 오른쪽 +는 없다)
import 'dart:math' as math;
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/reading/mini_timer.dart' show miniTimerHidden;
import 'package:chaekjang/features/reading/read_list.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/mini_timer_store.dart' show MiniTimerPlace;
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';

/// 어제 그 시각(기기 시간대)
String yesterday(int h, [int m = 0]) {
  final d = DateTime.now();
  return DateTime(d.year, d.month, d.day - 1, h, m).toUtc().toIso8601String();
}

Library lib() {
  final now = DateTime.now().toUtc();
  // 오늘 기록이어야 한다: 자정 직후(00:00~00:30)에 돌리면 '30분 전'이 어제가 되어 '오늘 10분'이 안 보였다(2026-11-26 00:22)
  final local = DateTime.now();
  final today = DateTime(local.year, local.month, local.day).toUtc();
  String at(int min) {
    final t = now.subtract(Duration(minutes: min));
    return (t.isBefore(today) ? today : t).toIso8601String();
  }
  return Library(
    editions: {
      'ed1': Edition(id: 'ed1', title: '아몬드', authors: const ['손원평'], source: 'photo', createdAt: t1, updatedAt: t1),
      'ed2': Edition(id: 'ed2', title: '데미안', authors: const ['헤르만 헤세'], source: 'photo', createdAt: t1, updatedAt: t1),
    },
    books: {
      'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1),
      'bk2': MyBook(id: 'bk2', editionId: 'ed2', status: ReadStatus.reading, createdAt: t1, updatedAt: t1),
    },
    sessions: {
      's1': Session(id: 's1', startedAt: at(30), endedAt: at(20), durationMs: 600000, createdAt: at(20), updatedAt: at(20), myBookId: 'bk1'),
      // 어제 기록(날 넘기기로 본다)
      's0': Session(id: 's0', startedAt: yesterday(9), endedAt: yesterday(9, 25), durationMs: 1500000, createdAt: t1, updatedAt: t1, myBookId: 'bk2'),
    },
  );
}

/// 머리 '다음 날' 단추
IconBtn nextBtn(WidgetTester t) => t.widget<IconBtn>(find.byWidgetPredicate((w) => w is IconBtn && w.label == '다음 날'));

/// 큰 카드 제목(표지 그림 안 제목 글자와 구별)
Finder featureTitle(String s) => find.byWidgetPredicate((w) => w is Text && w.data == s && w.style?.fontSize == AppType.bookFeatureTitle.fontSize);

void main() {
  Future<void> pump(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3; // 360dp
    addTearDown(t.view.reset);
    final m = LibraryModel.instance;
    m.lib = lib();
    m.loaded = true;
    await t.pumpWidget(MediaQuery(
      data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
      child: const MaterialApp(home: Scaffold(body: ReadList())),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('맨 위: 가운데 ‹ 날짜 ›(다음 날은 꺼짐), 그 아래 오늘 읽은 시간 · 오른쪽 끝 시간 추가', (t) async {
    await pump(t);
    expect(find.textContaining('오늘 총'), findsNothing);
    final line = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('오늘 '));
    expect(line, findsOneWidget);
    final date = find.textContaining('요일');
    final screenW = t.getSize(find.byType(ReadList)).width;
    expect(t.getRect(date).center.dx, closeTo(screenW / 2, 0.5), reason: '날짜는 가운데');
    expect(t.widget<Text>(date).style?.fontSize, AppType.heading.fontSize, reason: '통계 달 넘기기와 같은 큰 글씨');
    final prev = find.bySemanticsLabel('이전 날'), next = find.bySemanticsLabel('다음 날');
    expect(prev, findsOneWidget);
    expect(next, findsOneWidget);
    expect(nextBtn(t).disabled, isTrue, reason: '오늘 다음 날은 없다');
    expect(t.getRect(prev).right, lessThanOrEqualTo(t.getRect(date).left + 0.5));
    expect(t.getRect(line).top, greaterThanOrEqualTo(t.getRect(date).bottom), reason: '날짜 아래 줄');
    final add = find.text('시간 추가');
    expect(add, findsOneWidget);
    final pageRight = screenW - t.getRect(line).left;
    expect(t.getRect(add).right, closeTo(pageRight, 0.5), reason: '글자 끝 = 내용 오른쪽 끝');
    expect(t.getRect(add).center.dy, closeTo(t.getRect(line).center.dy, 1.5), reason: '오늘 읽은 시간 줄과 한 줄');
    expect(find.bySemanticsLabel('시간 추가'), findsOneWidget);
  });

  testWidgets('‹ 를 누르면 어제 기록(읽은 시간 · 기록 줄), 최근 읽던 책 · 읽기 목록은 없고 › 로 오늘', (t) async {
    await pump(t);
    await t.tap(find.bySemanticsLabel('이전 날'));
    await t.pump(const Duration(milliseconds: 300));
    final d = DateTime.now();
    final y = DateTime(d.year, d.month, d.day - 1);
    expect(find.text('${y.month}월 ${y.day}일 ${['일', '월', '화', '수', '목', '금', '토'][y.weekday % 7]}요일'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '읽은 시간 25분'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^데미안, 오전 9:00')), findsOneWidget, reason: '그날 기록 줄(통계와 같은 줄)');
    expect(find.text('내 읽기 목록'), findsNothing);
    expect(find.widgetWithText(Btn, '이어서 읽기'), findsNothing);
    expect(nextBtn(t).disabled, isFalse);
    await t.tap(find.bySemanticsLabel('이전 날'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('이날은 독서 기록이 없어요'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('다음 날'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.bySemanticsLabel('다음 날'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('내 읽기 목록'), findsOneWidget, reason: '오늘로 돌아왔다');
    expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('오늘 ')), findsOneWidget);
    // 다른 날을 보다가 다른 탭에 갔다 오면 오늘
    await t.tap(find.bySemanticsLabel('이전 날'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('내 읽기 목록'), findsNothing);
    MiniTimerPlace.instance.setTab('/stats');
    MiniTimerPlace.instance.setTab('/read');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('내 읽기 목록'), findsOneWidget, reason: '다른 탭에 갔다 오면 오늘');
  });

  testWidgets('최근 읽던 책: 표지 92, 제목 줄 위 = 표지 위, 단추 아래 = 표지 아래, 오늘 시간은 단추 오른쪽 위', (t) async {
    await pump(t);
    final cover = find.bySemanticsLabel('아몬드 책 정보');
    final c = t.getRect(cover);
    expect(c.width, CoverSize.feature);
    expect(CoverSize.feature, 92);
    final title = featureTitle('아몬드');
    expect(title, findsOneWidget);
    expect(t.getRect(title).top, closeTo(c.top, 0.5));
    final btn = find.widgetWithText(Btn, '이어서 읽기');
    final b = t.getRect(btn);
    expect(b.bottom, closeTo(c.bottom, 0.5));
    expect(b.left, closeTo(c.right + 16, 0.5), reason: '표지가 작아진 만큼 단추가 넓다');
    final time = find.text('10분').first;
    expect(t.getRect(time).right, closeTo(b.right, 0.5));
    expect(t.getRect(time).bottom, lessThanOrEqualTo(b.top));
  });

  testWidgets('카드 위 이름 글자(최근 읽던 책)는 없고 오늘 줄과 표지 사이 28', (t) async {
    await pump(t);
    expect(find.text('최근 읽던 책'), findsNothing);
    expect(find.text('잠깐 멈춘 책'), findsNothing);
    final line = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('오늘 '));
    final c = t.getRect(find.bySemanticsLabel('아몬드 책 정보'));
    final add = t.getRect(find.text('시간 추가'));
    expect(c.top - math.max(t.getRect(line).bottom, add.bottom), closeTo(Space.xl, 1.5));
  });

  testWidgets('목록 제목 오른쪽 +는 없고(2026-11-26 사용자 \'+ 지워줘\') 목록 아래 + 책 추가(+ 획 왼쪽 끝 = 표지 줄 왼쪽 끝)', (t) async {
    await pump(t);
    expect(find.bySemanticsLabel('읽기 목록에 추가'), findsNothing);
    final add = find.bySemanticsLabel('읽기 목록에 책 추가');
    expect(add, findsOneWidget);
    expect(find.text('책 추가'), findsOneWidget);
    final row = find.bySemanticsLabel(RegExp('^데미안'));
    expect(t.getRect(add).top, greaterThanOrEqualTo(t.getRect(row).bottom - 0.5), reason: '목록 줄 아래');
    expect(t.getRect(add).height, greaterThanOrEqualTo(48));
    final plus = find.descendant(of: add, matching: find.byType(LucideIcon));
    final glyphLeft = t.getRect(plus).left + 22 * 4.2 / 24;
    final pageLeft = t.getRect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('오늘 '))).left;
    expect(glyphLeft, closeTo(pageLeft, 0.5));
  });

  testWidgets('글씨 1.3배: 겹치거나 넘치지 않고 표지는 위에 붙는다', (t) async {
    await pump(t, scale: 1.3);
    expect(t.takeException(), isNull);
    final c = t.getRect(find.bySemanticsLabel('아몬드 책 정보'));
    expect(t.getRect(featureTitle('아몬드')).top, closeTo(c.top, 0.5));
    final b = t.getRect(find.widgetWithText(Btn, '이어서 읽기'));
    expect(b.bottom, greaterThanOrEqualTo(c.bottom - 0.5));
    final line = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('오늘 '));
    expect(t.getRect(find.text('시간 추가')).center.dy, closeTo(t.getRect(line).center.dy, 2));
  });

  test('작은 타이머: 읽기 탭은 재는 동안만, 장면 · 독서 끝에서는 숨김(2026-11-27)', () {
    expect(miniTimerHidden('/read', running: true), isFalse, reason: '장면에서 ⌄로 나오면 오른쪽 아래');
    expect(miniTimerHidden('/read'), isTrue, reason: '멈춘 독서는 카드의 이어서 읽기');
    expect(miniTimerHidden('/reading/session', running: true), isTrue);
    expect(miniTimerHidden('/reading/finish'), isTrue);
    expect(miniTimerHidden('/books'), isFalse);
  });
}
