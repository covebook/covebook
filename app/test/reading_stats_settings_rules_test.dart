// 2026-11-19 공통 규칙(읽기 · 통계 · 내 정보): 하나 고르기 시트는 FilterOption + 고르는 원, 책 줄은 BookRow, 책 없음은 '책 없이 읽기',
// 시각은 '오후 9:05', 1분 미만은 초까지, 저장했어요 창은 사용자 시안 그대로
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/reading/finish_screen.dart' show showSavedDialog;
import 'package:chaekjang/features/settings/backup_screen.dart';
import 'package:chaekjang/features/settings/settings_screen.dart';
import 'package:chaekjang/features/stats/chart_data.dart';
import 'package:chaekjang/features/stats/stats_screen.dart';
import 'package:chaekjang/features/stats/stats_widgets.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '데미안', authors: const ['헤르만 헤세'], source: 'photo', createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, createdAt: t1, updatedAt: t1)},
      sessions: {
        's1': Session(id: 's1', myBookId: 'bk1', startedAt: '2026-11-16T12:00:00.000Z', endedAt: '2026-11-16T12:25:00.000Z', durationMs: 25 * 60000, createdAt: t1, updatedAt: t1),
        's2': Session(id: 's2', startedAt: '2026-11-16T13:00:00.000Z', endedAt: '2026-11-16T13:00:45.000Z', durationMs: 45000, createdAt: t1, updatedAt: t1),
      },
    );

/// 글자(낱말 이음표 U+2060을 뺀 글이 같은 것): WordText · MetaText는 그릴 때 이음표를 넣는다
Finder plain(String s) => find.byWidgetPredicate((w) {
      final t = w is RichText ? w.text.toPlainText() : null;
      return t != null && t.replaceAll('\u2060', '') == s;
    });

/// 그 글로 시작하는 글자(이음표를 뺀 글)
Finder plainStarts(String s) => find.byWidgetPredicate((w) {
      final t = w is RichText ? w.text.toPlainText() : null;
      return t != null && t.replaceAll('\u2060', '').startsWith(s);
    });

Future<void> pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pump();
}

void main() {
  setUp(() {
    final m = LibraryModel.instance;
    m.lib = lib();
    m.loaded = true;
  });

  test('시각 · 지난 시간 글자: 오후 9:05, 1분 미만은 초까지', () {
    expect(timeLabel(DateTime(2026, 11, 16, 21, 5)), '오후 9:05');
    expect(timeLabel(DateTime(2026, 11, 16, 0, 30)), '오전 12:30');
    expect(formatDurationShort(45000), '45초');
    expect(formatDurationShort(25 * 60000), '25분');
    expect(dayTitle('2026-11-15'), '11월 15일 일요일');
    expect(syncTimeLabel(DateTime(2026, 11, 19, 15, 10), DateTime(2026, 11, 19, 20)), '오늘 오후 3:10');
  });

  test('서재 책 제목 · 저자', () {
    final l = lib();
    expect(bookTitle(l, 'bk1'), '데미안');
    expect(bookAuthor(l, 'bk1'), '헤르만 헤세');
    expect(bookTitle(l, null), isNull);
    expect(bookAuthor(l, 'nope'), '');
  });

  testWidgets('내 정보 › 움직임 줄이기: 하나 고르기 줄(FilterOption)과 고르는 원, 설명은 시트 설명 자리', (t) async {
    await pump(t, const SettingsScreen());
    await t.tap(find.text('움직임 줄이기'));
    await t.pumpAndSettle();
    expect(find.byType(FilterOption), findsNWidgets(3));
    expect(find.byType(RadioMark), findsNWidgets(3));
    expect(find.text('켜면 책이 움직이는 연출과 독서 장면의 움직임을 줄여요.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('계정 및 동기화: 묶음 이름은 작은 회색 이름(ListGroup)', (t) async {
    await pump(t, const BackupScreen());
    expect(find.widgetWithText(ListGroup, '동기화'), findsOneWidget);
    expect(find.text('기록은 이 기기에만 있어요'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('책 한 권 기록: 머리는 \'이 책 전체\' 구역 머리(책 줄은 화면 맨 위 책 칸에 있어 되풀이하지 않는다), 숫자 칸은 StatNumber 하나', (t) async {
    await pump(t, Scaffold(body: BookRecordView(lib: lib(), id: 'bk1')));
    // 2026-11-21: 독서 기록 맨 위 책 칸(SelectField)을 넣으며 책 줄이 두 번 보였다 → 여기서는 뺐다. 아래 회색 띠도 다음 흰 띠가 깐다
    expect(find.byType(BookRow), findsNothing);
    expect(find.widgetWithText(SectionHead, '이 책 전체'), findsOneWidget);
    expect(find.byType(SectionBand), findsNothing);
    expect(find.byType(StatNumber), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });

  testWidgets('저장했어요 창: 사용자 시안 그대로(표지 72 · 제목 · 저자, \'N분 기록했어요\'는 표지 아래 끝), 책 없는 기록은 \'책 없이 읽기\'(DESIGN 3-1)', (t) async {
    await pump(t, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showSavedDialog(c, bookId: 'bk1', sessionId: 's1'), child: const Text('열기')))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(plainStarts('25분'), findsOneWidget);
    expect(find.byType(LinkedCover), findsOneWidget);
    expect(t.getSize(find.byType(LinkedCover)).width, 72);
    // 'N분 기록했어요' 아래 끝 = 표지 아래 끝(2026-11-19 사용자 '11초 위치가 애매')
    expect(t.getRect(plainStarts('25분')).bottom, closeTo(t.getRect(find.byType(LinkedCover)).bottom, 1.5));
    await t.tap(find.text('확인'));
    await t.pumpAndSettle();
    expect(plainStarts('25분'), findsNothing);

    await pump(t, Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showSavedDialog(c, bookId: null, sessionId: 's2'), child: const Text('열기')))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(plainStarts('45초'), findsOneWidget);
    expect(find.text('책 없이 읽기'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('한 책 독서 기록 분석: 달 숫자는 달 · 책 칸 바로 아래, \'이 책 전체\'는 맨 아래. 책 칸은 흰 바탕 + 회색 테두리(2026-11-21)', (t) async {
    await pump(t, const StatsScreen(tab: false, initialBook: 'bk1'));
    final box = t.widget<SelectField>(find.byType(SelectField));
    expect(box.outlined, isTrue);
    await t.tap(find.text('분석'));
    await t.pumpAndSettle();
    await t.dragUntilVisible(find.text('이 책 전체'), find.byType(Scrollable).first, const Offset(0, -300));
    await t.pumpAndSettle();
    final month = t.getRect(find.text('독서 횟수'));
    final whole = t.getRect(find.text('이 책 전체'));
    expect(month.top, lessThan(whole.top));
    expect(t.getRect(find.text('날짜별 독서')).top, lessThan(whole.top));
    // 한 권이면 '많이 읽은 책'(늘 그 책 한 줄)은 없고, 달 완독은 '이 책 전체'와 같은 '회'
    expect(find.text('많이 읽은 책'), findsNothing);
    expect(find.text('0권'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('통계 탭 책 고르기: 맨 위 줄 오른쪽이 아니라 달력과 그날 기록 머리 사이 테두리 칸, 고르면 책 이름(검정) · 저자(작고 회색) (2026-11-24)', (t) async {
    await pump(t, const StatsScreen(tab: true));
    await t.pumpAndSettle();
    expect(find.byType(FilterButton), findsNothing, reason: '위 줄 오른쪽 모든 책 ⌄는 없다');
    final box = find.byType(SelectField);
    expect(t.widget<SelectField>(box).outlined, isTrue);
    expect(find.descendant(of: box, matching: plain('모든 책')), findsOneWidget);
    // 달력 아래, 그날 기록 머리 위
    expect(t.getRect(find.byType(ReadingCalendar)).bottom, lessThan(t.getRect(box).top));
    final head = find.textContaining('일요일');
    if (head.evaluate().isNotEmpty) expect(t.getRect(box).bottom, lessThan(t.getRect(head.first).top));
    // 분석: 달 바로 아래
    await t.tap(find.text('분석'));
    await t.pumpAndSettle();
    expect(find.byType(SelectField), findsOneWidget);

    await t.pumpWidget(const SizedBox()); // 같은 화면 상태를 다시 쓰지 않게(고른 책은 처음 열 때 읽는다)
    await pump(t, const StatsScreen(tab: true, initialBook: 'bk1'));
    await t.pumpAndSettle();
    // 앞 것은 표지(꾸민 표지 그림 속 제목), 마지막이 칸 글자
    final title = find.descendant(of: find.byType(SelectField), matching: find.text('데미안')).last;
    final author = find.descendant(of: find.byType(SelectField), matching: find.text('헤르만 헤세'));
    final ts = t.widget<Text>(title).style!, as = t.widget<Text>(author).style!;
    expect(ts.color, AppColors.ink);
    expect(as.color, AppColors.inkSoft);
    expect(as.fontSize!, lessThan(ts.fontSize!));
    expect(t.takeException(), isNull);
  });
}
