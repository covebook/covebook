// 책 추가 아이콘(바코드·엑셀 파일): 다른 화면과 같은 아이콘 표(lib/gen/lucide.g.dart, 2026-11-18 Lucide)를 쓴다
library;

import 'package:flutter/material.dart';

import '../../ui/kit.dart';
import '../../ui/theme.dart';

class AddIcon extends StatelessWidget {
  const AddIcon(this.name, {super.key, this.size = 22, this.color = AppColors.ink});
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => LucideIcon(name, size: size, color: color);
}
