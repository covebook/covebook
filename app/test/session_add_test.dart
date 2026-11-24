// 읽은 시간 직접 추가(2026-11-23 사용자 F단계): 시작 시각은 묻지 않는다(오늘이면 지금에서 독서 시간을 뺀 때, 지난 날이면 그날 21시, 그날 안에 맞춤).
// 저장은 타이머 저장과 같은 길(읽기 전 → 읽는 중). 여는 곳: 책 정보 독서 기록 '추가' · 통계 캘린더 그날 '독서 기록 추가' · 읽기 탭 '오늘 총'
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/session_edit.dart';
import 'package:chaekjang/features/book/book_screen.dart';
import 'package:chaekjang/features/stats/session_edit_screen.dart';
import 'package:chaekjang/features/stats/stats_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/ui/kit.dart' show Field, LucideIcon, Stars;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-01T01:00:00.000Z';

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 216, createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.want, createdAt: t1, updatedAt: t1)},
    );

Finder label(String s) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == s);

Future<void> pumpIn(WidgetTester t, Widget home) async {
  final m = LibraryModel.instance;
  m.useForTest(lib());
  m.writeChanges = (_) async {};
  addTearDown(() => m.writeChanges = applyLocalChanges);
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

int ms(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  group('시작 · 끝 시각(manualSessionTimes)', () {
    final now = DateTime(2026, 11, 23, 15, 30);
    test('오늘: 지금에서 독서 시간을 뺀 때 시작해 지금 끝난다', () {
      final r = manualSessionTimes('2026-11-23', 30 * 60000, now);
      expect(DateTime.parse(r.startedAt).toLocal(), DateTime(2026, 11, 23, 15, 0));
      expect(DateTime.parse(r.endedAt).toLocal(), now);
    });
    test('오늘인데 자정 전부터가 되면 0시부터(그날 안)', () {
      final r = manualSessionTimes('2026-11-23', 60 * 60000, DateTime(2026, 11, 23, 0, 20));
      expect(DateTime.parse(r.startedAt).toLocal(), DateTime(2026, 11, 23));
      expect(DateTime.parse(r.endedAt).toLocal(), DateTime(2026, 11, 23, 1, 0));
    });
    test('지난 날: 그날 21시에 시작', () {
      final r = manualSessionTimes('2026-11-20', 60 * 60000, now);
      expect(DateTime.parse(r.startedAt).toLocal(), DateTime(2026, 11, 20, 21));
      expect(DateTime.parse(r.endedAt).toLocal(), DateTime(2026, 11, 20, 22));
    });
    test('지난 날 긴 독서는 24시 전에 끝나게 앞으로 당긴다', () {
      final r = manualSessionTimes('2026-11-20', 5 * 60 * 60000, now);
      expect(DateTime.parse(r.startedAt).toLocal(), DateTime(2026, 11, 20, 19));
      expect(DateTime.parse(r.endedAt).toLocal(), DateTime(2026, 11, 21));
      expect(today(DateTime.parse(r.startedAt)), '2026-11-20');
    });
    test('독서 시간 칸: 1분 ~ 24시간만', () {
      expect(manualDurationMs(''), isNull);
      expect(manualDurationMs('0'), isNull);
      expect(manualDurationMs('30'), 30 * 60000);
      expect(manualDurationMs('1440'), 1440 * 60000);
      expect(manualDurationMs('1441'), isNull);
    });
  });

  testWidgets('추가 화면: 책 · 날짜가 골라진 채, 빠른 고르기 30분으로 저장하면 그날 기록이 생기고 읽기 전 → 읽는 중', (t) async {
    await pumpIn(t, const SessionAddScreen(bookId: 'bk1', day: '2026-11-20'));
    expect(find.text('독서 기록 추가'), findsOneWidget);
    expect(find.text('소년이 온다'), findsOneWidget);
    expect(find.text('시작 시각'), findsNothing);
    for (final q in ['10분', '30분', '1시간']) {
      expect(find.text(q), findsOneWidget);
    }
    await t.tap(find.text('30분'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '30'), findsOneWidget, reason: '빠른 고르기 값이 칸에 들어간다');
    await t.tap(find.text('기록 저장'));
    await t.pumpAndSettle();
    final m = LibraryModel.instance;
    final s = m.lib.sessions.values.single;
    expect(s.myBookId, 'bk1');
    expect(s.durationMs, 30 * 60000);
    expect(DateTime.parse(s.startedAt).toLocal(), DateTime(2026, 11, 20, 21));
    expect(m.lib.books['bk1']!.status, ReadStatus.reading, reason: '타이머 저장과 같은 규칙');
    expect(t.takeException(), isNull);
  });

  testWidgets('추가 화면: 독서 시간이 비면 저장 단추가 꺼져 있고, 책 없이도 저장한다', (t) async {
    await pumpIn(t, const SessionAddScreen());
    await t.tap(find.text('기록 저장'));
    await t.pumpAndSettle();
    expect(LibraryModel.instance.lib.sessions, isEmpty, reason: '독서 시간이 비면 저장하지 않는다(단추 꺼짐)');
    await t.enterText(find.byType(TextField).first, '45');
    // 입력칸 초점을 풀어 아래 단추가 화면 아래로 돌아오게(키보드 자리를 비우는 동안은 내용 끝에 있다)
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle(const Duration(seconds: 2));
    await t.tap(find.text('기록 저장'));
    await t.pumpAndSettle();
    final s = LibraryModel.instance.lib.sessions.values.single;
    expect(s.myBookId, isNull);
    expect(s.durationMs, 45 * 60000);
    expect(today(DateTime.parse(s.startedAt)), today());
  });

  testWidgets('책 정보 › 내 기록 › 독서 기록 횟수 줄 맨 오른쪽 \'+\'는 그 책이 골라진 추가 화면(머리에는 전체 보기만, 2026-11-24 사용자)', (t) async {
    await pumpIn(t, BookScreen(id: 'bk1', onRead: (_) {}));
    await t.tap(find.text('내 기록'));
    await t.pumpAndSettle();
    expect(find.text('추가'), findsNothing, reason: '머리 오른쪽 글자 추가는 없다');
    // '+'는 횟수 줄('N회, 총 …' 또는 빈 글)과 같은 줄 맨 오른쪽, 누르는 자리 48
    final plus = t.getRect(label('독서 기록 추가'));
    final line = t.getRect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(RegExp(r'총 |타이머로 읽으면'))).first);
    final icon = t.getRect(find.descendant(of: label('독서 기록 추가'), matching: find.byType(LucideIcon)));
    expect(plus.size, const Size(48, 48));
    expect((icon.center.dy - line.center.dy).abs(), lessThan(1), reason: '횟수 줄 가운데');
    expect(plus.left, greaterThan(line.right - 0.5));
    await t.tap(label('독서 기록 추가'));
    await t.pumpAndSettle();
    expect(find.text('독서 기록 추가'), findsOneWidget);
    expect(find.text('소년이 온다'), findsWidgets);
    expect(find.text('기록 저장'), findsOneWidget);
  });

  testWidgets('통계 캘린더: 기록 없는 지난 날도 누르면 그날 머리와 \'독서 기록 추가\'', (t) async {
    await pumpIn(t, const StatsScreen(tab: true));
    final now = DateTime.now();
    // 이번 달 1일(오늘이 1일이어도 지난 날 · 오늘 중 하나)
    await t.tap(label('1일, 기록 없음'));
    await t.pumpAndSettle();
    expect(find.text('독서 기록 추가'), findsOneWidget);
    // 달력 아래 책 고르는 칸(2026-11-24)만큼 내려가 있어 보이게 민다
    await t.ensureVisible(find.text('독서 기록 추가'));
    await t.pumpAndSettle();
    await t.tap(find.text('독서 기록 추가'));
    await t.pumpAndSettle();
    expect(find.text('기록 저장'), findsOneWidget);
    expect(find.textContaining('${now.month}월 1일'), findsWidgets, reason: '그 날짜로 열린다');
  });

  testWidgets('추가 화면(1단계 규칙): 도달한 쪽을 마지막 쪽(216)으로 적어 저장하면 완독, 완독일은 그 날짜', (t) async {
    await pumpIn(t, const SessionAddScreen(bookId: 'bk1', day: '2026-11-20'));
    await t.tap(find.text('30분'));
    await t.pumpAndSettle();
    final pages = find.descendant(of: find.byWidgetPredicate((w) => w is Field && w.label == '도달한 쪽 (선택)'), matching: find.byType(TextField));
    await t.ensureVisible(pages);
    await t.enterText(pages, '216');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle(const Duration(seconds: 2));
    await t.tap(find.text('기록 저장'));
    await t.pumpAndSettle();
    final m = LibraryModel.instance;
    expect(m.lib.sessions.values.single.pagesRead, 216);
    expect(m.lib.books['bk1']!.status, ReadStatus.read);
    expect(m.lib.rounds.values.single.finishedAt, '2026-11-20');
    // 5단계: 완독이 된 기록은 연 자리로 돌아가 저장했어요 창 + 별점
    await t.pumpAndSettle();
    expect(find.textContaining('기록하고 완독했어요'), findsOneWidget);
    expect(find.byType(Stars), findsOneWidget);
  });
}

