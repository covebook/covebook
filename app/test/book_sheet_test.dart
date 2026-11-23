// 책장 책 시트(2026-11-23): '책장에서 빼기'는 손잡이 줄 오른쪽 작은 회색 글자 단추, 아래 줄은 '갈피 남기기 | 읽기' 둘(책 정보 아래 두 단추와 같은 순서).
// 지난 책장(보기 전용)에서는 빼기 · 아래 줄이 없다. 긴 제목 · 큰 글씨에서도 빼기 글자가 제목과 겹치지 않는다
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/home/book_sheet.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const t1 = '2026-11-16T01:00:00.000Z';
const longTitle = '아몬드: 감정을 느끼지 못하는 소년의 특별한 성장 이야기 (20만 부 기념 리커버 특별판)';

Future<void> _open(WidgetTester t, {bool readOnly = false, double scale = 1}) async {
  // 서재는 시험 안에서 넣는다(밖에서 넣으면 읽기 기다림이 시험 시계로 끝나지 않는다)
  LibraryModel.instance.useForTest(Library(
    editions: {'ed1': Edition(id: 'ed1', title: longTitle, authors: const ['손원평'], source: 'photo', pageCount: 264, createdAt: t1, updatedAt: t1)},
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

void main() {
  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    testWidgets('빼기는 손잡이 줄 오른쪽, 아래 줄은 갈피 남기기 | 이어서 읽기 (글자 ×$scale)', (t) async {
      await _open(t, scale: scale);
      final out = t.getRect(find.text('책장에서 빼기'));
      final title = t.getRect(find.text(longTitle).last); // 앞 것은 꾸민 표지 그림 속 제목
      final mark = t.getRect(find.text('갈피 남기기'));
      final read = t.getRect(find.text('이어서 읽기'));
      final info = t.getRect(find.text('책 정보 보기'));
      // 빼기는 제목보다 위, 손잡이(가운데 38) 오른쪽(겹치지 않음), 오른쪽 끝은 내용 오른쪽 끝(화면 끝에서 28)
      expect(out.bottom, lessThanOrEqualTo(title.top), reason: '빼기 $out · 제목 $title');
      expect(out.left, greaterThan(180 + 19), reason: '빼기 $out');
      expect(360 - out.right, closeTo(28, 1));
      // 아래 줄: 갈피 남기기 왼쪽, 읽기 오른쪽, 둘 다 '책 정보 보기' 아래
      expect(mark.center.dx, lessThan(read.center.dx));
      expect(mark.top, greaterThan(info.bottom));
      expect((mark.center.dy - read.center.dy).abs(), lessThan(1));
      // 아래 줄에는 빼기가 없다(하나뿐)
      expect(find.text('책장에서 빼기'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('빼기 누르는 자리는 높이 48', (t) async {
    await _open(t);
    final hit = t.getRect(find.ancestor(of: find.text('책장에서 빼기'), matching: find.byType(ConstrainedBox)).first);
    expect(hit.height, greaterThanOrEqualTo(48));
  });

  testWidgets('지난 책장(보기 전용): 빼기 · 갈피 · 읽기 없음', (t) async {
    await _open(t, readOnly: true);
    expect(find.text('책장에서 빼기'), findsNothing);
    expect(find.text('갈피 남기기'), findsNothing);
    expect(find.text('이어서 읽기'), findsNothing);
    expect(find.text('책 정보 보기'), findsOneWidget);
  });
}
