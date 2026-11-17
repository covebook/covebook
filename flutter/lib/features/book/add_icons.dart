// 책 추가 아이콘(바코드·엑셀 파일): 다른 화면과 같은 Tabler 표(lib/gen/lucide.g.dart)를 쓴다(2026-11-17 Tabler로 통일)
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
