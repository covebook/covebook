// 책 추가에만 쓰는 선 아이콘(lucide scan-barcode·file-spreadsheet, ISC). gen/lucide.g.dart는 지금 앱 아이콘 목록에서 만들어지므로 여기 따로 둔다
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ui/theme.dart';

const _svg = <String, String>{
  'ScanBarcode': '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/>'
      '<path d="M8 7v10"/><path d="M12 7v10"/><path d="M17 7v10"/>',
  'FileSpreadsheet': '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>'
      '<path d="M8 13h2"/><path d="M14 13h2"/><path d="M8 17h2"/><path d="M14 17h2"/>',
};

/// LucideIcon과 같은 모양(24칸, 굵기 1.6)
class AddIcon extends StatelessWidget {
  const AddIcon(this.name, {super.key, this.size = 22, this.color = AppColors.ink});
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="$hex" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${_svg[name]}</svg>',
      width: size,
      height: size,
    );
  }
}
