// 서재 책의 표지 · 제목 · 저자(읽기 · 통계 · 기록 · 갈피 · 책장 시트가 같이 쓴다). 2026-11-19 통계 부품 파일에서 옮김
library;

import 'package:flutter/material.dart';

import '../domain/cover_url.dart';
import '../domain/library.dart';
import '../services/cover_cache.dart';
import 'kit.dart';
import 'theme.dart';

/// 표지 그림(기기에 받아 둔 것). 없거나 못 받으면 책 색 바탕
class CoverImage extends StatefulWidget {
  const CoverImage({super.key, required this.uris, required this.color, required this.width, required this.height, this.radius = 2.5});
  final List<String?> uris;
  final Color color;
  final double width;
  final double height;
  final double radius;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  RawImage? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 주소가 바뀌면 다시 읽는다(예전에는 처음 주소만 읽었다)
  @override
  void didUpdateWidget(CoverImage old) {
    super.didUpdateWidget(old);
    if (old.uris.join('|') != widget.uris.join('|')) {
      _img = null;
      _load();
    }
  }

  Future<void> _load() async {
    for (final u in {...widget.uris.whereType<String>()}) {
      final img = coverInMemory(u) ?? await loadCover(u);
      if (img != null) {
        if (mounted) setState(() => _img = RawImage(image: img, fit: BoxFit.cover, width: widget.width, height: widget.height));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Container(width: widget.width, height: widget.height, color: widget.color, child: _img),
      );
}

/// 서재 책의 제목(없는 책이면 null). 읽기 · 통계 · 독서 끝이 같이 쓴다(같은 식이 열 곳 넘게 있었다, 2026-11-19)
String? bookTitle(Library lib, String? id) {
  final b = id == null ? null : lib.books[id];
  return b == null ? null : lib.editions[b.editionId]?.title;
}

/// 서재 책의 저자('지은이1, 지은이2', 없으면 빈 글)
String bookAuthor(Library lib, String? id) {
  final b = id == null ? null : lib.books[id];
  final e = b == null ? null : lib.editions[b.editionId];
  return e != null ? authorLine(e.authors) : '';
}

/// 서재 책의 표지: 실제 표지가 있으면 그것, 없으면 책 색 대체 표지(제목)
class LinkedCover extends StatelessWidget {
  const LinkedCover({super.key, required this.lib, required this.id, required this.width});
  final Library lib;
  final String id;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = lib.books[id];
    final e = b == null ? null : lib.editions[b.editionId];
    final color = (b?.bindingId != null ? lib.bindings[b!.bindingId]?.spineColor : null) ?? RealCover.placeholder;
    if (e?.coverUri != null) {
      return Semantics(
        label: '${e!.title} 표지',
        child: CoverImage(uris: [coverAtSize(e.coverUri, 'M'), e.coverUri], color: AppColors.surface, width: width, height: width / 0.68, radius: 3),
      );
    }
    return RealCover(title: e?.title ?? '', color: color, width: width);
  }
}
