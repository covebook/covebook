// 갈피 카드 글(2026-11-16 QA 은서 F11·F13): 목록에서 줄 수를 넘으면(줄바꿈으로 끝나도) 끝에 '…', 시는 폭 때문에 접힌 줄만 들여 쓴다.
// 원본 사진을 곁들인 문장 갈피는 '사진 갈피'가 아니라 쪽 'p. 118'과 문장이 주인공. 새 갈피에서 책을 안 고르면 저장이 꺼진 이유를 보인다(F15)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/bookmark/bookmark_card.dart';
import 'package:chaekjang/features/bookmark/new_bookmark_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const style = TextStyle(fontSize: 20, height: 1.5);

String plainOf(Widget w) => (w is Text ? (w.data ?? w.textSpan!.toPlainText()) : '').replaceAll('⁠', '');

Future<void> pump(WidgetTester t, Widget w, {double width = 300}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: width, child: w)))));
  await t.pump();
}

void main() {
  testWidgets('목록: 줄바꿈으로 끝나는 넷째 줄에서 잘려도 끝에 …', (t) async {
    await pump(t, const WordWrap('눈이 오면\n나는 정류장에 선다\n아무도\n오지 않는다\n다섯째 줄\n여섯째 줄', style: style, maxLines: 4));
    final text = plainOf(t.widget(find.byType(Text)));
    expect(text.endsWith('…'), isTrue, reason: text);
    expect(text.contains('다섯째'), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('목록: 줄 수 안이면 그대로', (t) async {
    await pump(t, const WordWrap('짧은 시\n두 줄', style: style, maxLines: 4));
    expect(plainOf(t.widget(find.byType(Text))), '짧은 시\n두 줄');
  });

  testWidgets('시: 폭 때문에 접힌 줄은 들여 쓰고, 진짜 줄은 왼쪽 끝에서', (t) async {
    await pump(t, const WordWrap('waiting for a bus that never comes\nshort', style: style, hang: 20), width: 200);
    final rows = t.widgetList<Text>(find.byType(Text)).map(plainOf).toList();
    expect(rows.length, 3, reason: '$rows');
    expect(rows.last, 'short');
    final first = t.getTopLeft(find.byType(Text).at(0)).dx;
    expect(t.getTopLeft(find.byType(Text).at(1)).dx - first, closeTo(20, 0.5), reason: '접힌 뒷부분');
    expect(t.getTopLeft(find.byType(Text).at(2)).dx - first, closeTo(0, 0.5), reason: '다음 줄');
    // 화면 읽기는 원문 한 덩어리
    expect(find.bySemanticsLabel('waiting for a bus that never comes\nshort'), findsOneWidget);
  });

  testWidgets('원본 사진을 곁들인 문장 갈피: 머리는 p. 118, 사진 갈피라고 하지 않는다', (t) async {
    const data = BookmarkCardData(text: '그날 밤 눈은 그치지 않았다.', title: '작별하지 않는다', date: '2026.11.16', page: 118, photoUri: 'file:///nope.jpg', photoRatio: 0.7);
    await pump(t, const BookmarkCard(data: data, width: 380, seed: 'x'), width: 380);
    expect(find.text('p. 118'), findsOneWidget);
    expect(find.text('사진 갈피'), findsNothing);
    expect(find.bySemanticsLabel('원본 사진 있음'), findsOneWidget);
    // 사진만 남긴 갈피는 사진 갈피, 쪽은 같은 'p. 118'
    const photo = BookmarkCardData(text: '', title: '작별하지 않는다', date: '2026.11.16', page: 118, photoUri: 'file:///nope.jpg', photoRatio: 0.7);
    await pump(t, const BookmarkCard(data: photo, width: 380, seed: 'y'), width: 380);
    expect(find.text('사진 갈피'), findsOneWidget);
    expect(find.text('p. 118'), findsOneWidget);
    expect(find.text('118쪽'), findsNothing);
  });

  testWidgets('새 갈피: 책을 안 고르면 저장이 꺼진 이유를 보인다', (t) async {
    const t0 = '2026-11-16T01:00:00.000Z';
    LibraryModel.instance
      ..lib = Library(
        editions: {'ed1': Edition(id: 'ed1', title: '작별하지 않는다', authors: const ['한강'], source: 'photo', createdAt: t0, updatedAt: t0)},
        books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.read, createdAt: t0, updatedAt: t0)},
      )
      ..loaded = true;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: NewBookmarkScreen()));
    await t.pump();
    expect(find.text('책을 골라야 저장할 수 있어요'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(const MaterialApp(home: NewBookmarkScreen(book: 'bk1')));
    await t.pump();
    expect(find.text('책을 골라야 저장할 수 있어요'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
