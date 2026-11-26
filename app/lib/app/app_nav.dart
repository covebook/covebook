// 탭 넘나들기(지금 앱 router.dismissTo('/read', {book}) 같은 일): 밀어 넣은 화면에서 하단 탭을 바꾸고, 읽기 탭에 책을 넘겨준다
library;

import 'package:flutter/foundation.dart';

/// 하단 탭 차례(goTab 번호, 앱 틀 _tabs와 같은 차례): 책장 · 내 책 · 읽기 · 기록 · 통계(2026-11-16 메뉴 구조 개편)
abstract final class AppTab {
  static const shelf = 0, books = 1, read = 2, records = 3, stats = 4;
}

/// 기록 탭 안 글자 탭
enum RecordSection { marks, essays }

class AppNav extends ChangeNotifier {
  AppNav._();
  static final instance = AppNav._();

  /// 바꿀 탭(앱 틀이 읽고 비운다)
  int? tab;

  /// 이 시각(ms)까지 하단 탭 누르기를 무시한다: 화면을 닫는 동안 연달아 누른 손가락이 아래 탭 바를 눌러 다른 탭으로 가는 것을 막는다
  /// (2026-11-15 QA 민혁 F6: 저장 뒤 '확인' 두 번 → 기록 탭)
  int tabsBlockedUntil = 0;

  void blockTabs([Duration d = const Duration(milliseconds: 600)]) => tabsBlockedUntil = DateTime.now().add(d).millisecondsSinceEpoch;

  bool get tabsBlocked => DateTime.now().millisecondsSinceEpoch < tabsBlockedUntil;

  /// 읽기 탭에 넘겨준 책(읽기 탭이 읽고 비운다)
  String? readBook;

  /// 갈피 목록에 넘겨준 책 거르기(기록 탭 갈피가 읽고 비운다)
  String? bookmarkBook;

  /// 기록 탭에서 열 글자 탭(기록 탭이 읽고 비운다): 갈피로 보낼 때 marks, 감상으로 보낼 때 essays
  RecordSection? recordSection;

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// 내 책 탭에 넘겨준 조건: 책장에 없는 책만(내 책 탭이 읽고 비운다)
  bool booksOffShelf = false;

  /// 내 책 탭으로(책 추가 결과 '내 책 보기'·꽉 차서 보관했을 때: 책장에 없는 책만 걸러 보인다)
  void goBooks({bool offShelf = false}) {
    booksOffShelf = offShelf;
    goTab(AppTab.books);
  }

  /// 기록 탭 갈피로 가서 그 책 갈피만(지금 앱 보드 '목록 보기': dismissTo('/bookmarks', {book}))
  void goBookmarks(String bookId) {
    bookmarkBook = bookId;
    recordSection = RecordSection.marks;
    goTab(AppTab.records);
  }

  /// 기록 탭의 갈피·감상으로
  void goRecords(RecordSection section) {
    recordSection = section;
    goTab(AppTab.records);
  }

  /// 읽기 탭으로 가서 그 책을 맨 앞에(시작은 재생을 눌러서)
  void goRead(String bookId) {
    readBook = bookId;
    goTab(AppTab.read);
  }

  /// 탭은 그대로 두고 읽기 탭 목록에서만 그 책을 맨 앞에(다른 화면에서 읽기를 시작할 때, 2026-11-24 사용자 4단계)
  void frontRead(String bookId) {
    readBook = bookId;
    notifyListeners();
  }
}
