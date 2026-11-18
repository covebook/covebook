// 2026-11-16 메뉴 구조 개편: 하단 탭 5개(책장 · 내 책 · 읽기 · 기록 · 통계)의 차례·경로와 탭 넘나들기
import 'package:chaekjang/app/app_nav.dart';
import 'package:chaekjang/app/app_shell.dart' show tabPaths;
import 'package:chaekjang/ui/tab_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('하단 탭 차례와 경로: 책장 · 내 책 · 읽기 · 기록 · 통계', () {
    expect(tabPaths, ['/', '/books', '/read', '/records', '/stats']);
    expect([AppTab.shelf, AppTab.books, AppTab.read, AppTab.records, AppTab.stats], [0, 1, 2, 3, 4]);
    expect(tabPaths[AppTab.read], '/read');
  });

  test('갈피로 보내면 기록 탭의 갈피, 읽기로 보내면 읽기 탭', () {
    final nav = AppNav.instance;
    nav.goBookmarks('book-1');
    expect(nav.tab, AppTab.records);
    expect(nav.recordSection, RecordSection.marks);
    expect(nav.bookmarkBook, 'book-1');
    nav.goRecords(RecordSection.essays);
    expect(nav.tab, AppTab.records);
    expect(nav.recordSection, RecordSection.essays);
    nav.goRead('book-2');
    expect(nav.tab, AppTab.read);
    expect(nav.readBook, 'book-2');
    nav
      ..tab = null
      ..recordSection = null
      ..bookmarkBook = null
      ..readBook = null;
  });

  testWidgets('내 책 아이콘(닫힌 책)이 빈 모양·찬 모양 모두 그려진다', (t) async {
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [myBooksTabIcon(Colors.grey, Colors.white), myBooksTabIcon(Colors.black, Colors.white, filled: true)]),
    ));
    expect(t.takeException(), isNull);
  });
}
