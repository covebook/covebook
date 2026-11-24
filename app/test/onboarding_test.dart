// 처음 쓰는 사람 안내(2026-11-25 사용자 '온보딩으로 무조건 책 하나 추가하게 해서 책장에 올리고 선택해서 회전 같은 꾸미기까지 하게')
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/onboarding/onboarding.dart';
import 'package:chaekjang/ui/kit.dart' show Btn;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb;

const t1 = '2026-11-10T01:00:00.000Z';

Library withBook(String createdAt) => Library(
      editions: {'e1': Edition(id: 'e1', title: '가호', authors: const ['무라카미 하루키'], source: 'photo', createdAt: createdAt, updatedAt: createdAt)},
      books: {'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.want, createdAt: createdAt, updatedAt: createdAt)},
    );

void main() {
  setUpAll(fakeDb);
  final o = Onboarding.instance;
  tearDown(() => o.reset());

  test('빈 서재로 처음 켜면 안내를 시작하고, 책이 있는 서재(기존 사용자)는 바로 끝낸 것으로 친다', () async {
    o.reset();
    await o.load(Library());
    expect(o.active, isTrue);
    o.reset();
    await o.load(withBook(t1));
    expect(o.active, isFalse);
    expect(o.done, isTrue);
  });

  test('안내 중 동기화로 예전 책이 들어오면 끝내고, 안내 중에 추가한 책이면 이어 간다', () async {
    o.reset();
    await o.load(Library());
    o.libraryChanged(withBook(DateTime.now().toUtc().toIso8601String()));
    expect(o.active, isTrue, reason: '방금 추가한 책');
    o.libraryChanged(withBook(t1));
    expect(o.active, isFalse, reason: '안내 전에 만든 책(다른 기기 서재)');
  });

  test('바꿔 봤다는 표시는 안내 중에만, 끝내면 다시 시작하지 않는다', () async {
    o.reset();
    await o.load(Library());
    o.markChanged();
    expect(o.changed, isTrue);
    o.finish();
    expect(o.active, isFalse);
  });

  testWidgets('첫 화면 카드: 제목 · 설명 · 첫 책 추가하기, 닫기 없이 뒤 화면은 눌리지 않는다', (t) async {
    var added = 0, behind = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(child: GestureDetector(onTap: () => behind++, child: const ColoredBox(color: Colors.white))),
          Positioned.fill(child: OnboardingWelcome(onAdd: () => added++)),
        ]),
      ),
    ));
    expect(find.text('첫 책을 책장에 꽂아 볼까요?'), findsOneWidget);
    expect(find.textContaining('닫기'), findsNothing);
    expect(find.textContaining('건너뛰기'), findsNothing);
    await t.tapAt(const Offset(200, 100));
    expect(behind, 0, reason: '덮개가 뒤 화면 누르기를 막는다');
    await t.tap(find.widgetWithText(Btn, '첫 책 추가하기'));
    expect(added, 1);
  });

  testWidgets('말풍선: 가리킬 자리 아래(머리 아이콘)에 뜨고 꼭지가 그 가운데를 가리킨다, 누르기는 통과', (t) async {
    var taps = 0;
    const target = Rect.fromLTWH(220, 40, 48, 48);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.white))),
          const Positioned.fill(child: CoachBubble(text: '꾸미기를 눌러 책을 꾸며 볼까요?', target: target, below: true)),
        ]),
      ),
    ));
    final bubble = t.getRect(find.text('꾸미기를 눌러 책을 꾸며 볼까요?'));
    expect(bubble.top, greaterThan(target.bottom), reason: '자리 아래');
    final tip = t.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.size == const Size(16, 8)));
    expect(tip.center.dx, closeTo(target.center.dx, 0.5), reason: '꼭지가 자리 가운데');
    await t.tapAt(bubble.center);
    expect(taps, 1, reason: '말풍선은 누르기를 막지 않는다');
  });
}
