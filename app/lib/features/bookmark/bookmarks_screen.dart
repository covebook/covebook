// 예전 갈피 탭 이름(2026-11-16 메뉴 구조 개편으로 기록 탭 '갈피'로 옮김: features/record/record_tab.dart).
// 앞서 쓰던 자리가 그대로 열리게 남겨 둔 이름이다. 새로 쓰는 곳은 RecordTab을 쓴다
library;

import 'package:flutter/material.dart';

import '../../app/app_nav.dart';
import '../record/record_tab.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key, this.initialBook});
  final String? initialBook;

  @override
  Widget build(BuildContext context) => RecordTab(initialBook: initialBook, initialSection: RecordSection.marks);
}
