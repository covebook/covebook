// 책 정보 평가·내 기록 탭 머리줄: 제목이 한 줄로 보인다(2026-11-18 머리줄 간격을 줄이다 OverflowBox 넓이가 끝없이 커져 '한/줄/평'이 세로로 깨졌다)
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/book/book_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';

void main() {
  setUp(() {
    final m = LibraryModel.instance;
    m.lib = Library(
      editions: {'ed1': Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 216, createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, note: '한 장 넘기기가 어려웠다', createdAt: t1, updatedAt: t1)},
      essays: {'es1': Essay(id: 'es1', myBookId: 'bk1', title: 'Second reading', body: '본문', createdAt: t1, updatedAt: t1)},
    );
    m.loaded = true;
  });

  testWidgets('평가·내 기록 머리줄 제목은 한 줄, 오른쪽 글자 단추는 제목 오른쪽', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: BookScreen(id: 'bk1', onRead: (_) {})));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('평가'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    for (final title in ['한줄평', '감상  1개']) {
      final r = t.getRect(find.text(title));
      expect(r.height, lessThan(40), reason: '$title 높이 ${r.height}');
      expect(r.width, greaterThan(40), reason: '$title 넓이 ${r.width}');
    }
    expect(t.getRect(find.text('수정')).left, greaterThanOrEqualTo(t.getRect(find.text('한줄평')).right));
    await t.tap(find.text('내 기록'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    await t.scrollUntilVisible(find.text('남긴 갈피  0개'), 300, scrollable: find.byType(Scrollable).first);
    final r = t.getRect(find.text('남긴 갈피  0개'));
    expect(r.height, lessThan(40));
    expect(t.takeException(), isNull);
  });
}
