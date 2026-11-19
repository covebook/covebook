// 갈피·감상 쓰기 화면이 함께 쓰는 부품(2026-11-19 공통 규칙): 쓰던 글 지킴(갈피 남기기 · 갈피 수정 · 감상 쓰기 · 감상 수정),
// 안내·오류 글(회색 상자 없이 글자만), 사진 칩 줄(다시 찍기 · 다른 사진 · 사진 빼기)
library;

import 'package:flutter/material.dart';

export '../../ui/draft_guard.dart';
import '../../ui/kit.dart';

/// 사진 칩 줄(갈피 남기기 · 갈피 수정): 다시 찍기 · 다른 사진 · (onRemove가 있으면) 사진 빼기. 사진 아래 가운데
class PhotoChips extends StatelessWidget {
  const PhotoChips({super.key, required this.onCamera, required this.onLibrary, this.onRemove});
  final VoidCallback onCamera, onLibrary;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Wrap(alignment: WrapAlignment.center, spacing: Space.s, runSpacing: Space.s, children: [
          AppChip(label: '다시 찍기', onPress: onCamera),
          AppChip(label: '다른 사진', onPress: onLibrary),
          if (onRemove != null) AppChip(label: '사진 빼기', onPress: onRemove),
        ]),
      );
}
