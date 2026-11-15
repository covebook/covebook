// 탭 넘나들기(지금 앱 router.dismissTo('/read', {book}) 같은 일): 밀어 넣은 화면에서 하단 탭을 바꾸고, 읽기 탭에 책을 넘겨준다
library;

import 'package:flutter/foundation.dart';

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

  /// 갈피 탭에 넘겨준 책 거르기(갈피 탭이 읽고 비운다)
  String? bookmarkBook;

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// 갈피 탭으로 가서 그 책 갈피만(지금 앱 보드 '목록 보기': dismissTo('/bookmarks', {book}))
  void goBookmarks(String bookId) {
    bookmarkBook = bookId;
    goTab(1);
  }

  /// 읽기 탭으로 가서 그 책을 맨 앞에(시작은 재생을 눌러서)
  void goRead(String bookId) {
    readBook = bookId;
    goTab(2);
  }
}
