// 책장 책 시트: '책장에서 빼기'는 표지 · 제목 줄 오른쪽 아래, '책 정보 보기' 바로 위 휴지통 아이콘 단추(2026-11-24 사용자 '버튼 우측 바로 위에 쓰레기 아이콘으로'),
// 바탕 없이 회색 선 둥근 네모 칸 40(같은 날 '아이콘에 배경 말고 회색 선'). 아래 줄 글 아래는 시스템 아래 띠 + 14 대신 글 아래 빈 12만 띠에 걸친다(같은 날 '이어서 읽기 밑에 하단 여백').
// 손잡이 줄은 옛 높이(위 10 + 손잡이 4.5, 그 아래 16에 표지): 2026-11-23 글자 단추를 넣으며 48로 높였더니 '왤케 올라와있지'.
// 아래 줄은 '갈피 남기기 | 읽기' 둘(책 정보 아래 두 단추와 같은 순서). 지난 책장(보기 전용)에서는 빼기 · 아래 줄이 없다.
// 긴 제목 · 큰 글씨에서도 빼기 아이콘이 제목 · 단추와 겹치지 않는다
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/home/book_sheet.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/ui/kit.dart' show ControlSize, IconBtn, Shape, Space;
import 'package:chaekjang/ui/theme.dart' show AppColors;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';
const longTitle = '아몬드: 감정을 느끼지 못하는 소년의 특별한 성장 이야기 (20만 부 기념 리커버 특별판)';

Future<void> _open(WidgetTester t, {bool readOnly = false, double scale = 1, String title = longTitle}) async {
  // 서재는 시험 안에서 넣는다(밖에서 넣으면 읽기 기다림이 시험 시계로 끝나지 않는다)
  LibraryModel.instance.useForTest(Library(
    editions: {'ed1': Edition(id: 'ed1', title: title, authors: const ['손원평'], source: 'photo', pageCount: 264, createdAt: t1, updatedAt: t1)},
    books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, note: '감정을 배우는 이야기', createdAt: t1, updatedAt: t1)},
  ));
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3; // 폭 360dp
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: Scaffold(body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showBookSheet(c, 'bk1', readOnly: readOnly, status: readOnly ? '2025년 | 완독' : null), child: const Text('열기'))))),
  ));
  await t.tap(find.text('열기'));
  await t.pumpAndSettle();
}

final _remove = find.byWidgetPredicate((w) => w is IconBtn && w.label == '책장에서 빼기');

void main() {
  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    testWidgets('빼기는 책 정보 보기 바로 위 오른쪽 아이콘, 아래 줄은 갈피 남기기 | 이어서 읽기 (글자 ×$scale)', (t) async {
      await _open(t, scale: scale);
      final out = t.getRect(_remove);
      final title = t.getRect(find.text(longTitle).last); // 앞 것은 꾸민 표지 그림 속 제목
      final note = t.getRect(find.text('감정을 배우는 이야기'));
      final mark = t.getRect(find.text('갈피 남기기'));
      final read = t.getRect(find.text('이어서 읽기'));
      final info = t.getRect(find.ancestor(of: find.text('책 정보 보기'), matching: find.byType(GestureDetector)).first);
      // 누르는 자리 48. 보이는 칸은 회색 선 둥근 네모 40(바탕 없음): 오른쪽 끝은 내용 오른쪽 끝(화면 끝에서 28 = 책 정보 보기 단추 끝),
      // 아래 끝에서 책 정보 보기 단추까지 16
      expect(out.width, greaterThanOrEqualTo(48));
      expect(out.height, greaterThanOrEqualTo(48));
      final boxF = find.descendant(of: _remove, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null));
      final box = t.getRect(boxF), deco = t.widget<Container>(boxF).decoration! as BoxDecoration;
      expect(box.size, const Size(ControlSize.iconBox, ControlSize.iconBox));
      expect(deco.color, isNull, reason: '바탕 없음');
      expect((deco.border! as Border).top.color, AppColors.line);
      expect(deco.borderRadius, BorderRadius.circular(Shape.button));
      expect(360 - box.right, closeTo(28, 0.5));
      expect(info.right, closeTo(box.right, 0.5));
      expect(info.top - box.bottom, closeTo(Space.l, 0.5), reason: '단추 바로 위');
      expect(out.bottom, lessThanOrEqualTo(info.top + 0.5), reason: '빼기 $out · 단추 $info');
      // 글(제목 · 한줄평)은 아이콘 자리를 비운다
      expect(title.right, lessThanOrEqualTo(out.left + 0.5), reason: '제목 $title · 빼기 $out');
      expect(note.right, lessThanOrEqualTo(out.left + 0.5));
      // 아래 줄: 갈피 남기기 왼쪽, 읽기 오른쪽, 둘 다 '책 정보 보기' 아래
      expect(mark.center.dx, lessThan(read.center.dx));
      expect(mark.top, greaterThan(info.bottom));
      expect((mark.center.dy - read.center.dy).abs(), lessThan(1));
      // 글자 단추 '책장에서 빼기'는 없다(아이콘 하나뿐, 화면 읽기 이름만)
      expect(find.text('책장에서 빼기'), findsNothing);
      expect(find.bySemanticsLabel('책장에서 빼기'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('손잡이 줄은 옛 높이: 손잡이 칸 위 끝(= 시트 위 끝)에서 표지까지 30.5(위 10 + 손잡이 4.5 + Space.l 16, 2026-11-23 전과 같다)', (t) async {
    await _open(t, title: '가호');
    final handle = t.getRect(find.byWidgetPredicate((w) => w is Container && w.margin == const EdgeInsets.only(top: 10)));
    // 표지 사진이 없는 책: 꾸민 표지 그림 + '꾸민 표지' 글 칸
    final cover = t.getRect(find.ancestor(of: find.text('꾸민 표지'), matching: find.byType(Column)).first);
    expect(cover.top - handle.top, closeTo(10 + 4.5 + Space.l, 0.5));
  });

  testWidgets('아래 여백: 맨 아래 글자 줄(누르는 자리 48)의 글 아래 빈 12만 시스템 아래 띠에 걸친다(글자는 띠 위, 2026-11-24 사용자 \'이어서 읽기 밑에 하단 여백\')', (t) async {
    t.view.padding = const FakeViewPadding(bottom: 24 * 3); // 제스처 띠 24dp
    addTearDown(t.view.resetPadding);
    await _open(t, title: '가호');
    final read = t.getRect(find.text('이어서 읽기'));
    final row = t.getRect(find.ancestor(of: find.text('이어서 읽기'), matching: find.byType(ConstrainedBox)).first);
    expect(row.height, greaterThanOrEqualTo(48));
    expect(800 - row.bottom, closeTo(24 - 12, 0.5), reason: '줄 아래 끝은 띠 위 끝에서 12 아래');
    expect(read.bottom, lessThanOrEqualTo(800 - 24 + 0.5), reason: '글자는 띠 위');
    // 띠가 없는 기기도 화면 끝에 붙지 않는다(4)
    t.view.padding = FakeViewPadding.zero;
    await t.pumpAndSettle();
    expect(800 - t.getRect(find.ancestor(of: find.text('이어서 읽기'), matching: find.byType(ConstrainedBox)).first).bottom, closeTo(Space.xs, 0.5));
  });

  testWidgets('지난 책장(보기 전용): 빼기 · 갈피 · 읽기 없음', (t) async {
    await _open(t, readOnly: true);
    expect(_remove, findsNothing);
    expect(find.text('갈피 남기기'), findsNothing);
    expect(find.text('이어서 읽기'), findsNothing);
    expect(find.text('책 정보 보기'), findsOneWidget);
  });
}
