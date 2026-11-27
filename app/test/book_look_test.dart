// 책 꾸미기(2026-11-23): 장정 편집 화면 이름을 '책 꾸미기'로, 그림 · 색상 · 재질 옆 '갈피' 칸에서 갈피 색을 고르고 장정과 함께 '꾸미기 저장'으로만 반영한다.
// 책이 아직 없는 책 추가 확인(BindingEditor만)에는 '갈피' 칸이 없다. 책 정보 '갈피 색' 줄 · 갈피 상세 '갈피 색 바꾸기'는 없앴다
import 'package:chaekjang/db/library_write.dart';
import 'package:chaekjang/domain/color.dart' show ribbonPalette;
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/book/binding_editor.dart';
import 'package:chaekjang/features/book/binding_screen.dart';
import 'package:chaekjang/features/book/book_screen.dart';
import 'package:chaekjang/features/bookmark/bookmark_detail_screen.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/library_store.dart' show saveLayout;
import 'package:chaekjang/store/placement_store.dart';
import 'package:chaekjang/ui/bake.dart' show initBake;
import 'package:chaekjang/ui/theme.dart' show AppColors;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb;

const t1 = '2026-11-16T01:00:00.000Z';

Library lib() => Library(
      editions: {'ed1': Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'photo', pageCount: 216, createdAt: t1, updatedAt: t1)},
      books: {'bk1': MyBook(id: 'bk1', editionId: 'ed1', status: ReadStatus.reading, bindingId: 'd1', createdAt: t1, updatedAt: t1)},
      bindings: {'d1': Binding(id: 'd1', myBookId: 'bk1', spineColor: '#4E4C33', motif: 'none', source: 'auto', status: 'ready', seed: 0, createdAt: t1, updatedAt: t1)},
      bookmarks: {'m1': Bookmark(id: 'm1', myBookId: 'bk1', text: '첫 갈피', createdAt: t1, updatedAt: t1)},
    );

/// 색 견본처럼 화면 읽기 이름만 있는 것
Finder label(String s) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == s);

Future<void> pumpIn(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3; // 폭 360dp
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

void main() {
  final m = LibraryModel.instance, p = PlacementStore.instance;
  setUpAll(() async {
    fakeDb();
    // 미리보기 책 그림이 쓰는 1×1 그림(앱은 켤 때 준비한다)
    await initBake();
  });
  tearDown(() {
    m.writeChanges = applyLocalChanges;
    p.writeLayout = saveLayout;
  });

  void use() {
    m.useForTest(lib());
    m.writeChanges = (_) async {};
    p.writeLayout = (_, _) async {};
  }

  group('setBookLook: 장정과 갈피 색을 한 번에', () {
    test('갈피 색만 바꾸면 장정은 그대로', () async {
      use();
      await m.setBookLook('bk1', ribbonColor: '#5276B4');
      expect(m.lib.books['bk1']!.ribbonColor, '#5276B4');
      expect(m.lib.books['bk1']!.bindingId, 'd1');
      expect(m.lib.bindings['d1']!.spineColor, '#4E4C33');
    });

    test('장정만 주면 갈피 색은 그대로, null을 주면 표지에서 고른 색(비움)', () async {
      use();
      await m.setBookLook('bk1', ribbonColor: '#5276B4');
      const v = BindingDraft(spineColor: '#123456', motif: 'none', seed: 0, inkColor: '#FFFFFF', accentColor: '#AA0000', layout: 'spine_a');
      await m.setBookLook('bk1', binding: v.custom(material: 'linen'));
      final b = m.lib.books['bk1']!;
      expect(b.ribbonColor, '#5276B4');
      expect(m.lib.bindings[b.bindingId]!.spineColor, '#123456');
      await m.setBookLook('bk1', ribbonColor: null);
      expect(m.lib.books['bk1']!.ribbonColor, isNull);
    });
  });

  testWidgets('책 꾸미기: 제목 · 갈피 칸 · 고른 색은 저장해야 반영', (t) async {
    use();
    await pumpIn(t, const BindingScreen(id: 'bk1'));
    expect(find.text('책 꾸미기'), findsOneWidget);
    expect(find.text('장정 편집'), findsNothing);
    expect(find.text('꾸미기 저장'), findsOneWidget);
    for (final tab in ['그림', '색상', '재질', '갈피']) {
      expect(find.text(tab), findsOneWidget, reason: tab);
    }
    await t.tap(find.text('갈피'));
    await t.pumpAndSettle();
    // 자동은 한 줄(묶음 이름 '자동' 아래 '표지에서 고른 색' 줄이 따로 있었다, 2026-11-24 사용자)
    expect(find.text('자동'), findsOneWidget);
    expect(find.text('표지에서 고른 색'), findsNothing);
    await t.ensureVisible(label('갈피 색 7'));
    await t.tap(label('갈피 색 7'));
    await t.pumpAndSettle();
    expect(m.lib.books['bk1']!.ribbonColor, isNull, reason: '고르기만 해서는 저장하지 않는다');
    await t.tap(find.text('꾸미기 저장'));
    await t.pumpAndSettle();
    expect(m.lib.books['bk1']!.ribbonColor, ribbonPalette[6]);
    expect(m.lib.bindings['d1']!.spineColor, '#4E4C33', reason: '장정은 고르지 않았으니 그대로');
    expect(t.takeException(), isNull);
  });

  testWidgets('책 꾸미기: 갈피 색만 고르고 나가면 그만할지 묻는다', (t) async {
    use();
    await pumpIn(t, Builder(
      builder: (c) => Center(child: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const BindingScreen(id: 'bk1'))), child: const Text('열기'))),
    ));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.tap(find.text('갈피'));
    await t.pumpAndSettle();
    await t.ensureVisible(label('갈피 색 2'));
    await t.tap(label('갈피 색 2'));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('수정을 그만할까요?'), findsOneWidget);
  });

  testWidgets('책 추가 확인처럼 책이 없는 편집기에는 갈피 칸이 없다', (t) async {
    const rec = BindingDraft(spineColor: '#8F6E55', motif: 'none', inkColor: '#F5EFE6', accentColor: '#C9A46A', layout: 'spine_a');
    await pumpIn(t, Scaffold(body: SingleChildScrollView(child: BindingEditor(title: '새 책', value: rec, recommended: rec, onChange: (_) {}))));
    expect(find.text('재질'), findsOneWidget);
    expect(find.text('갈피'), findsNothing);
  });

  testWidgets('책 화면(2026-11-24 2단계 · 2026-11-26): 전환 칸 내 기록 | 평가 | 책 정보, 열면 내 기록. 책 꾸미기 줄은 내 기록 맨 아래(남긴 갈피 아래), 책 정보 칸 · ⋯ 메뉴에는 없음', (t) async {
    use();
    LibraryModel.instance.lib.editions['ed1'] = Edition(id: 'ed1', title: '소년이 온다', authors: const ['한강'], source: 'search', sourceName: 'YES24', link: 'https://example.com', pageCount: 216, createdAt: t1, updatedAt: t1);
    await pumpIn(t, BookScreen(id: 'bk1', onRead: (_) {}));
    final x = {for (final n in ['내 기록', '평가', '책 정보']) n: t.getCenter(find.text(n).first).dx};
    expect(x['내 기록']!, lessThan(x['평가']!));
    expect(x['평가']!, lessThan(x['책 정보']!));
    expect(find.text('독서 기록'), findsOneWidget, reason: '열면 내 기록 칸');
    final deco = find.text('책 꾸미기');
    expect(deco, findsOneWidget, reason: '내 기록 칸 맨 아래(2026-11-26 사용자 \'책 꾸미기는 내 기록 맨 밑에\')');
    expect(t.getRect(find.textContaining('남긴 갈피')).top, lessThan(t.getRect(deco).top));
    await t.tap(find.text('책 정보').first);
    await t.pumpAndSettle();
    expect(find.text('갈피 색'), findsNothing);
    expect(find.text('책 꾸미기'), findsNothing, reason: '책 정보 칸에서는 뺐다');
    expect(t.getRect(find.text('도서 정보')).top, lessThan(t.getRect(find.text('YES24에서 보기')).top));
    await t.tap(label('더 보기'));
    await t.pumpAndSettle();
    expect(find.text('책 정보 수정'), findsOneWidget);
    expect(find.text('책 공유'), findsNothing);
    expect(find.text('책 꾸미기'), findsNothing, reason: '메뉴에도 없다');
    expect(find.text('장정 편집'), findsNothing);
    Navigator.of(t.element(find.text('책 정보 수정'))).pop();
    await t.pumpAndSettle();
    await t.tap(find.text('내 기록').first);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('책 꾸미기'));
    await t.pumpAndSettle();
    await t.tap(find.text('책 꾸미기'));
    await t.pumpAndSettle();
    expect(find.byType(BindingScreen), findsOneWidget, reason: '⋯ 메뉴가 열던 것과 같은 책 꾸미기 화면');
  });

  testWidgets('내 기록 읽기 상태: 읽기 전은 회색(inkSoft), 읽는 중은 갈색(2026-11-26 사용자 \'읽기 전은 컨벤션에 맞춰서 회색으로\')', (t) async {
    use();
    final b = LibraryModel.instance.lib.books['bk1']!;
    LibraryModel.instance.lib.books['bk1'] = MyBook(id: b.id, editionId: b.editionId, status: ReadStatus.want, bindingId: b.bindingId, createdAt: t1, updatedAt: t1);
    await pumpIn(t, BookScreen(id: 'bk1', onRead: (_) {}));
    Color? colorOf(String s) => t.widget<Text>(find.text(s).first).style?.color;
    expect(colorOf('읽기 전'), AppColors.inkSoft);
    LibraryModel.instance.lib.books['bk1'] = MyBook(id: b.id, editionId: b.editionId, status: ReadStatus.reading, bindingId: b.bindingId, createdAt: t1, updatedAt: t1);
    await pumpIn(t, BookScreen(key: UniqueKey(), id: 'bk1', onRead: (_) {}));
    expect(colorOf('읽는 중'), AppColors.accent);
  });

  testWidgets('갈피 상세 ⋯ 메뉴에 갈피 색 바꾸기가 없다', (t) async {
    use();
    await pumpIn(t, const BookmarkDetailScreen(id: 'm1'));
    await t.tap(label('더 보기'));
    await t.pumpAndSettle();
    expect(find.text('책 정보'), findsNothing, reason: '3단계(2026-11-24): 카드 아래 출처를 누르면 책 화면이라 메뉴에서 뺐다');
    expect(find.text('갈피 색 바꾸기'), findsNothing);
  });
}
