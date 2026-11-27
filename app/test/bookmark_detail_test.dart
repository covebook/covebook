// 갈피 보기(2026-11-16 QA 은서 F1·영숙 F18): 옆으로 넘긴 뒤 수정에 들어갔다 나와도(뒤로·저장 모두) 보이는 갈피가 수정·삭제 대상이다.
// 삭제 확인창에 어느 갈피인지 보인다. 큰 글씨에서는 아래 줄이 '수정·공유'만 가운데로 모인다(빈 구분선 없음).
// 2026-11-19: 수정에서 고친 글이 있으면 나갈 때 묻는다(고치지 않았으면 바로 돌아온다)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/bookmark/bookmark_card.dart' show BookmarkCard, BookmarkCardData;
import 'package:chaekjang/features/bookmark/bookmark_detail_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t0 = '2026-11-16T01:00:00.000Z';

Bookmark mark(String id, String text, String at, {num? page}) => Bookmark(id: id, myBookId: 'bk1', text: text, createdAt: at, updatedAt: at, page: page);

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '작별하지 않는다', authors: const ['한강'], source: 'photo', createdAt: t0, updatedAt: t0)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.read, createdAt: t0, updatedAt: t0)},
      // 넘기는 차례는 남긴 차례(A → B → C)
      bookmarks: {
        'A': mark('A', '그날 밤 눈은 그치지 않았다. 나는 창가에 앉아 그녀가 남긴 쪽지를 몇 번이고 다시 읽었다.', '2026-11-16T01:00:00.000Z', page: 118),
        'B': mark('B', '사진 옆 두 번째 갈피', '2026-11-16T02:00:00.000Z'),
        'C': mark('C', '세 번째 갈피', '2026-11-16T03:00:00.000Z'),
      },
    );

Future<void> open(WidgetTester t, {double textScale = 1}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: const BookmarkDetailScreen(id: 'A'),
  ));
  await t.pumpAndSettle();
}

/// 화면에 보이는 카드의 갈피(넘기기 칸 가운데)
String shown(WidgetTester t) {
  final pv = find.byType(PageView);
  final mid = t.getCenter(pv);
  final cards = find.byType(BookmarkCard).evaluate().where((e) {
    final box = e.renderObject! as RenderBox;
    final r = box.localToGlobal(Offset.zero) & box.size;
    return r.left <= mid.dx && r.right >= mid.dx;
  });
  return (cards.single.widget as BookmarkCard).seed;
}

Future<void> swipeNext(WidgetTester t) async {
  await t.drag(find.byType(PageView), const Offset(-600, 0));
  await t.pumpAndSettle();
}

/// 글자(낱말 이음표 U+2060을 뺀 글이 같거나 담은 것)
Finder plain(String s, {bool contains = false}) => find.byWidgetPredicate((w) {
      final t = w is Text ? (w.data ?? w.textSpan?.toPlainText()) : w is RichText ? w.text.toPlainText() : null;
      if (t == null) return false;
      final p = t.replaceAll('\u2060', '');
      return contains ? p.contains(s) : p == s;
    });

Widget editScreen(WidgetTester t) => t.widget(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_EditBookmark'));

void main() {
  setUp(() {
    final m = LibraryModel.instance;
    m.lib = lib();
    m.loaded = true;
  });

  testWidgets('F1 재현: B로 넘겨 수정에 들어갔다 뒤로 나와도 B가 보이고, 다시 수정하면 B가 열린다', (t) async {
    await open(t);
    expect(shown(t), 'A');
    await swipeNext(t);
    expect(shown(t), 'B');
    await t.tap(find.text('수정'));
    await t.pumpAndSettle();
    expect((editScreen(t) as dynamic).m.id, 'B');
    // 저장하지 않고 뒤로
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(shown(t), 'B', reason: '전에는 처음 연 A가 보였다');
    await t.tap(find.text('수정'));
    await t.pumpAndSettle();
    expect((editScreen(t) as dynamic).m.id, 'B');
    expect(t.takeException(), isNull);
  });

  testWidgets('F1: 수정에서 저장으로 나와도(onDone) 고친 갈피가 보인다', (t) async {
    await open(t);
    await swipeNext(t);
    await swipeNext(t);
    expect(shown(t), 'C');
    await t.tap(find.text('수정'));
    await t.pumpAndSettle();
    // 저장 = 서재에 고친 글을 넣고 onDone(DB 없이 저장이 끝난 것처럼)
    final m = LibraryModel.instance;
    m.lib = m.lib.copy(bookmarks: {...m.lib.bookmarks, 'C': m.lib.bookmarks['C']!.edit(text: '고친 세 번째', updated: '2026-11-16T04:00:00.000Z')});
    (editScreen(t) as dynamic).onDone();
    await t.pumpAndSettle();
    expect(shown(t), 'C');
    expect(plain('고친 세 번째').evaluate().isNotEmpty, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('F1: 넘겨 수정했다 나온 뒤 삭제하면 보이는 갈피(B)가 지워지고, 확인창에 그 갈피 앞부분이 보인다', (t) async {
    await open(t);
    await swipeNext(t);
    await t.tap(find.text('수정'));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('더 보기'));
    await t.pumpAndSettle();
    await t.tap(find.text('삭제'));
    await t.pumpAndSettle();
    expect(plain('이 갈피를 삭제할까요?').evaluate().isNotEmpty, isTrue);
    expect(plain('“사진 옆 두 번째 갈피”', contains: true).evaluate().isNotEmpty, isTrue);
    await t.tap(find.text('삭제').last);
    await t.pumpAndSettle();
    final left = LibraryModel.instance.lib.bookmarks;
    expect(left.containsKey('B'), isFalse);
    expect(left.containsKey('A'), isTrue);
    expect(left.containsKey('C'), isTrue);
    // 지운 자리의 다음 갈피(C)가 보인다. 테스트에는 DB가 없어 '삭제를 저장하지 못했어요' 창이 뜬다
    if (find.text('삭제를 저장하지 못했어요').evaluate().isNotEmpty) {
      await t.tap(find.text('확인').last);
      await t.pumpAndSettle();
    }
    expect(shown(t), 'C');
  });

  testWidgets('수정에서 글을 고치고 뒤로 가면 묻는다(갈피 남기기 · 감상과 같은 확인창), 버리면 갈피 보기로', (t) async {
    await open(t);
    await t.tap(find.text('수정'));
    await t.pumpAndSettle();
    expect(find.text('갈피 저장'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '고친 글');
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(plain('수정을 그만할까요?').evaluate().isNotEmpty, isTrue);
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsNothing, reason: '취소면 수정 화면 그대로');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text('확인'));
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(shown(t), 'A');
    expect(LibraryModel.instance.lib.bookmarks['A']!.text.startsWith('그날 밤'), isTrue, reason: '버린 글은 저장하지 않는다');
    expect(t.takeException(), isNull);
  });

  testWidgets('F18: 보통 글씨는 서명과 수정·공유가 한 줄, 큰 글씨는 수정·공유만 가운데', (t) async {
    await open(t);
    expect(find.text('책장 한켠'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await open(t, textScale: 2);
    expect(find.text('책장 한켠'), findsNothing);
    final edit = t.getCenter(find.text('수정'));
    final share = t.getCenter(find.text('공유'));
    final mid = t.getCenter(find.byType(PageView)).dx;
    // 두 버튼 묶음의 가운데가 화면 가운데
    expect(((edit.dx + share.dx) / 2 - mid).abs(), lessThan(40));
    expect(t.takeException(), isNull);
  });

  testWidgets('3단계(2026-11-24): 카드 아래 출처를 누르면 그 책 화면, 화면 읽기는 \'작별하지 않는다 책 정보\' 단추, 넘기기 · 세로 밀기는 그대로, 더 보기에 책 정보 없음', (t) async {
    await open(t);
    final src = find.bySemanticsLabel('작별하지 않는다 책 정보');
    expect(src, findsOneWidget, reason: '보이는 카드(A)만 단추(넘기기 칸의 다른 카드는 화면 밖)');
    final r = t.getRect(src);
    expect(r.height, greaterThanOrEqualTo(48));
    // 옆으로 넘기기 · 세로로 밀기
    await swipeNext(t);
    expect(shown(t), 'B');
    await t.drag(find.byType(PageView), const Offset(0, -200));
    await t.pumpAndSettle();
    expect(shown(t), 'B');
    // 더 보기에는 책 정보가 없다
    await t.tap(find.bySemanticsLabel('더 보기'));
    await t.pumpAndSettle();
    expect(find.text('책 정보'), findsNothing);
    expect(find.text('수정'), findsWidgets);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    // 출처를 누르면 책 화면(전환 칸 '내 기록')
    await t.tap(find.bySemanticsLabel('작별하지 않는다 책 정보').first);
    await t.pumpAndSettle();
    expect(find.text('내 기록'), findsWidgets);
    expect(find.text('평가'), findsWidgets);
  });

  testWidgets('기록 탭 목록 카드 · 공유 카드는 출처가 단추가 아니다(onBook을 넘기지 않음)', (t) async {
    final data = BookmarkCardData(title: '작별하지 않는다', author: '한강', text: '문장', date: '11월 16일', bookId: 'bk1');
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: BookmarkCard(data: data, width: 360, seed: 'A')))));
    expect(find.bySemanticsLabel('작별하지 않는다 책 정보'), findsNothing);
  });
}

