// 긴 감상 화면(기록 > 감상): 읽기 화면은 본문만(입력 칸·저장 단추 없음), 수정 화면은 쓴 글을 채워 연다, 목록 줄.
// 2026-11-19 공통 규칙: '고치기' → '수정'(갈피와 같은 말), ' | ' 날짜·책 줄은 MetaText, 목록 줄은 BookRow(감상 제목 · '책 제목 | 쓴 날' · 미리보기)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/book/labels.dart' show dateShort;
import 'package:chaekjang/features/record/essay_screens.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/ui/kit.dart' show Btn;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';
const t2 = '2026-11-17T01:00:00.000Z';

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '데미안', authors: const ['헤르만 헤세'], source: 'photo', createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.read, createdAt: t1, updatedAt: t1)},
      essays: {
        'es1': Essay(id: 'es1', myBookId: 'bk1', title: '알을 깨는 일', body: '길게 쓴 감상\n\n둘째 문단', createdAt: t1, updatedAt: t2),
        'es2': Essay(id: 'es2', myBookId: 'bk1', body: '제목 없이 쓴 첫 줄\n이어지는 생각', createdAt: t1, updatedAt: t1),
      },
    );

/// 글자(낱말 이음표 U+2060을 뺀 글이 같은 것). MetaText는 조각마다 이음표를 넣은 Text.rich라 find.text(findRichText 포함)로는 못 찾는다
Finder plain(String s) => find.byWidgetPredicate((w) {
      final t = w is RichText ? w.text.toPlainText() : null;
      return t != null && t.replaceAll('\u2060', '') == s;
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

  testWidgets('감상 읽기: 책·제목·날짜·본문, 입력 칸과 저장 단추는 없다', (t) async {
    await pump(t, const EssayScreen(id: 'es1'));
    // 책 줄 제목 + 그린 표지 위 제목
    expect(find.text('데미안'), findsNWidgets(2));
    expect(find.text('알을 깨는 일'), findsOneWidget);
    expect(plain('2026년 11월 16일 | 2026년 11월 17일 고침'), findsOneWidget); // 상세 날짜는 '2026년 11월 16일'(11-17 날짜 통일)
    expect(find.widgetWithText(SelectableText, '길게 쓴 감상\n\n둘째 문단'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('감상 저장'), findsNothing);
    expect(find.bySemanticsLabel('감상 수정'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('감상 수정: 쓴 제목·본문을 채워 열고, 책은 바꾸지 않는다', (t) async {
    await pump(t, const EssayEditScreen(id: 'es1'));
    expect(find.text('감상 수정'), findsOneWidget);
    expect(find.widgetWithText(TextField, '알을 깨는 일'), findsOneWidget);
    expect(find.widgetWithText(TextField, '길게 쓴 감상\n\n둘째 문단'), findsOneWidget);
    expect(find.text('감상 저장'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('새 감상: 책을 정해 열면 그 책, 본문이 비면 저장할 수 없다', (t) async {
    await pump(t, const EssayEditScreen(book: 'bk1'));
    expect(find.text('감상 쓰기'), findsOneWidget);
    expect(find.text('데미안'), findsOneWidget);
    Btn save() => t.widget<Btn>(find.widgetWithText(Btn, '감상 저장'));
    expect(save().disabled, isTrue);
    await t.enterText(find.byType(TextField).last, '읽고 든 생각');
    await t.pump();
    expect(save().disabled, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('목록 줄: 표지·감상 제목(없으면 첫 줄)·책 제목과 쓴 날·미리보기', (t) async {
    final l = lib();
    await pump(
      t,
      Scaffold(
        body: ListView(children: [
          EssayRow(lib: l, essay: l.essays['es1']!),
          EssayRow(lib: l, essay: l.essays['es2']!),
          EssayRow(lib: l, essay: l.essays['es2']!, showBook: false),
        ]),
      ),
    );
    // 책을 보이는 두 줄: 그린 표지 위 제목 + '책 제목 | 쓴 날' 한 줄(BookRow 둘째 줄. 고쳤으면 고친 날도)
    expect(find.text('데미안'), findsNWidgets(2));
    final made = dateShort(t1), changed = dateShort(t2);
    expect(plain('데미안 | $made | $changed 고침'), findsOneWidget);
    expect(plain('데미안 | $made'), findsOneWidget);
    expect(find.text('알을 깨는 일'), findsOneWidget);
    expect(find.text('길게 쓴 감상 둘째 문단'), findsOneWidget);
    expect(find.text('제목 없이 쓴 첫 줄'), findsNWidgets(2));
    expect(find.text('이어지는 생각'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
}
