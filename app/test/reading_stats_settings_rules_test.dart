// 2026-11-19 공통 규칙(읽기 · 통계 · 내 정보): 하나 고르기 시트는 FilterOption + 고르는 원, 책 줄은 BookRow, 책 없음은 '책 없이 읽기',
// 시각은 '오후 9:05', 1분 미만은 초까지, 저장했어요 창은 사용자 시안 그대로
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/reading/finish_screen.dart' show showSavedDialog;
import 'package:chaekjang/features/settings/backup_screen.dart';
import 'package:chaekjang/features/settings/settings_screen.dart';
import 'package:chaekjang/features/stats/chart_data.dart';
import 'package:chaekjang/features/stats/stats_widgets.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/ui/kit.dart';
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

  testWidgets('책 한 권 기록: 책 줄은 BookRow, 숫자 칸은 StatNumber 하나', (t) async {
    await pump(t, Scaffold(body: BookRecordView(lib: lib(), id: 'bk1')));
    // 제목은 책 줄과 그린 대체 표지에 한 번씩
    expect(find.byType(BookRow), findsOneWidget);
    expect(find.descendant(of: find.byType(BookRow), matching: find.text('데미안')), findsNWidgets(2));
    expect(find.byType(StatNumber), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });

  testWidgets('저장했어요 창: 사용자 시안 그대로(표지 72 · 제목 · 저자, \'N분 기록했어요\'는 표지 아래 끝), 책 없는 기록은 \'책 없이 읽은 시간\'', (t) async {
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
    expect(find.text('책 없이 읽은 시간'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
