// 책 정보 › 책 소개(2026-11-26 사용자 '책 정보에 yes24에서 책 내용 요약 있잖아 그거 넣어서 해줘'): YES24 책 소개를 원문 그대로,
// 다섯 줄이 넘으면 접고 '더 보기', 출처 'YES24 제공'(링크 줄이 없으면 'YES24에서 보기'), 소개가 없으면 구역 없음, 못 받으면 다시 시도
import 'package:chaekjang/features/book/book_intro.dart';
import 'package:chaekjang/services/book_search.dart' show introText;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3; // 폭 360dp
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: w))));
  await t.pumpAndSettle();
}

Finder _text(String s) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().replaceAll('⁠', '') == s);

void main() {
  group('introText: 글은 그대로, 표시만 푼다', () {
    test('줄바꿈 표시는 줄로, 다른 꺾쇠 표시는 빼고, 글자 표시는 글자로', () {
      expect(introText('<b>소년이 온다</b><br/>1980년 5월&nbsp;광주.<br><br><br>&quot;너&quot; &amp; 나 &#8230; &#x2014;'), '소년이 온다\n1980년 5월 광주.\n\n"너" & 나 … —');
    });
    test('앞뒤 빈칸 · 줄 끝 빈칸은 지운다', () {
      expect(introText('  첫 줄  \r\n  둘째 줄 '), '첫 줄\n둘째 줄');
      expect(introText('<p> </p>'), '');
    });
  });

  testWidgets('짧은 소개: 접지 않고 출처 YES24 제공', (t) async {
    await _pump(t, BookIntro(isbn13: '9788936434120', linked: true, onOpen: (_) {}, load: (_) async => '짧은 소개 글이에요.'));
    expect(find.text('책 소개'), findsOneWidget);
    expect(_text('짧은 소개 글이에요.'), findsOneWidget);
    expect(find.text('더 보기'), findsNothing);
    expect(find.text('YES24 제공'), findsOneWidget);
    expect(find.text('YES24에서 보기'), findsNothing, reason: '같은 칸 맨 아래 링크 줄이 있다');
  });

  testWidgets('긴 소개: 다섯 줄로 접고 더 보기 → 펼침 → 접기. 링크 줄이 없으면 출처 자리가 YES24에서 보기', (t) async {
    final long = List.filled(40, '오래 기억될 문장이 이어지는 책 소개').join(' ');
    String? opened;
    await _pump(t, BookIntro(isbn13: '9788936434120', linked: false, onOpen: (u) => opened = u, load: (_) async => long));
    final body = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().replaceAll('\u2060', '').contains('오래 기억될'));
    final folded = t.getSize(body).height;
    expect(find.text('더 보기'), findsOneWidget);
    await t.tap(find.text('더 보기'));
    await t.pumpAndSettle();
    expect(t.getSize(body).height, greaterThan(folded * 2), reason: '펴면 전부 보인다');
    expect(find.text('접기'), findsOneWidget);
    await t.ensureVisible(find.text('접기'));
    await t.pumpAndSettle();
    await t.tap(find.text('접기'));
    await t.pumpAndSettle();
    expect(t.getSize(body).height, folded);
    await t.ensureVisible(find.text('YES24에서 보기'));
    await t.pumpAndSettle();
    await t.tap(find.text('YES24에서 보기'));
    expect(opened, contains('yes24.com'));
    expect(opened, contains('9788936434120'));
  });

  testWidgets('소개가 없으면 구역 없음, 못 받으면 구역만 실패 한 줄 + 다시 시도', (t) async {
    await _pump(t, BookIntro(isbn13: '9790000000018', linked: true, onOpen: (_) {}, load: (_) async => null));
    expect(find.text('책 소개'), findsNothing);
    var calls = 0;
    await _pump(
      t,
      BookIntro(key: UniqueKey(), isbn13: '9788936434120', linked: true, onOpen: (_) {}, load: (_) async {
        calls++;
        if (calls == 1) throw Exception('서버 응답 500');
        return '다시 받은 소개';
      }),
    );
    expect(find.text('책 소개'), findsOneWidget);
    expect(_text('책 소개를 불러오지 못했어요'), findsOneWidget);
    await t.tap(find.text('다시 시도'));
    await t.pumpAndSettle();
    expect(_text('다시 받은 소개'), findsOneWidget);
    expect(calls, 2);
  });
}
