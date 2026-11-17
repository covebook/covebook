// 긴 감상 화면(기록 > 감상): 읽기 화면은 본문만(입력 칸·저장 단추 없음), 고치기 화면은 쓴 글을 채워 연다, 목록 줄
import 'package:chaekjang/domain/library.dart';
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
    expect(find.text('2026년 11월 16일 · 2026년 11월 17일 고침'), findsOneWidget); // 상세 날짜는 '2026년 11월 16일'(11-17 날짜 통일)
    expect(find.widgetWithText(SelectableText, '길게 쓴 감상\n\n둘째 문단'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('감상 저장'), findsNothing);
    expect(find.bySemanticsLabel('감상 고치기'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('감상 고치기: 쓴 제목·본문을 채워 열고, 책은 바꾸지 않는다', (t) async {
    await pump(t, const EssayEditScreen(id: 'es1'));
    expect(find.text('감상 고치기'), findsOneWidget);
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

  testWidgets('목록 줄: 표지·책 제목·지은이·제목(없으면 첫 줄)·미리보기·쓴 날', (t) async {
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
    // 책을 보이는 두 줄: 그린 표지 위 제목 + '책 제목 · 지은이' 한 줄(표지 높이에 글 묶음을 맞추려 한 줄로 합쳤다)
    expect(find.text('데미안'), findsNWidgets(2));
    expect(find.text('데미안 · 헤르만 헤세', findRichText: true), findsNWidgets(2));
    expect(find.text('알을 깨는 일'), findsOneWidget);
    expect(find.text('길게 쓴 감상 둘째 문단'), findsOneWidget);
    expect(find.text('제목 없이 쓴 첫 줄'), findsNWidgets(2));
    expect(find.text('이어지는 생각'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
}
