// 하단 '내 책' 탭(2026-11-16 메뉴 개편: 책장 / 내 책 / 읽기 / 기록 / 통계): 전체 책 화면(all_books_screen)을 탭 모양으로.
// 뒤로 없이 '내 책' 제목과 검색·추가, 아래로 읽기 상태 글자 탭, '책 N권'·선택·보기 전환·필터. 앱 틀의 IndexedStack이 상태를 붙들어
// 탭을 오가도 검색어·필터·보기·스크롤 위치가 그대로다
library;

import 'package:flutter/widgets.dart';

import 'all_books_screen.dart';

class MyBooksTab extends StatelessWidget {
  const MyBooksTab({super.key});

  @override
  Widget build(BuildContext context) => const AllBooksScreen();
}
