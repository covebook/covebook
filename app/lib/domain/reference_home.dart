// 새 서재 예시 책장(지금 앱 domain/home-reference·store/home-reference-install): 처음 켠 빈 서재에 시안 예시 18권 자리를 놓는다.
// 예시 책은 서재에 저장하지 않는다(2026-11): 책장에만 보이는 표시 전용 책이라 전체 책·통계·동기화 책 목록에 들어가지 않는다.
// 자리(책장 배치)는 저장하고 동기화한다(다른 기기에서도 같은 예시가 보인다). 데이터는 지금 앱 코드로 뽑은 assets/reference_home.json(tool/dump_reference.test.ts)
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'layout.dart';
import 'types.dart';

/// 설치 표시 키(지금 앱 HOME_REFERENCE_KEY와 같다: 지금 앱에서 넘어온 서재는 다시 설치하지 않는다)
const referenceHomeKey = 'home-reference:2026-10';

class ReferenceHome {
  const ReferenceHome(this.layoutJson, this.books, this.profile);

  /// 저장할 책장 배치(지금 앱 shelf-layout JSON)
  final String layoutJson;

  /// 표시 전용 예시 책(id → 책)
  final Map<String, Book> books;

  /// 설치 기록(지금 앱 profile: 시안 자리 → 책 id)
  final Object? profile;
}

ReferenceHome? _home;

/// 시작할 때 한 번 읽는다(없거나 깨졌으면 예시 없이)
Future<void> loadReferenceHome() async {
  if (_home != null) return;
  try {
    _home = referenceHomeOf(jsonDecode(await rootBundle.loadString('assets/reference_home.json')) as Map<String, Object?>);
  } catch (_) {
    _home = const ReferenceHome('', {}, null);
  }
}

ReferenceHome? get referenceHome => _home;

/// 표시 전용 예시 책(읽기 전이면 빈 것)
Map<String, Book> get referenceBooks => _home?.books ?? const {};

int _hex(String h) => int.parse(h.substring(1), radix: 16);

ReferenceHome referenceHomeOf(Map<String, Object?> j) {
  final books = <String, Book>{};
  for (final raw in (j['books']! as List).cast<Map<String, Object?>>()) {
    final d = raw['dims'] as Map<String, Object?>?;
    final b = Book(
      id: raw['id']! as String,
      title: raw['title']! as String,
      themeColor: _hex(raw['themeColor']! as String),
      heightClass: HeightClass.values.byName(raw['heightClass']! as String),
      thicknessClass: ThicknessClass.values.byName(raw['thicknessClass']! as String),
      coverAspectRatio: (raw['coverAspectRatio']! as num).toDouble(),
      dims: d == null ? null : BookDims((d['height']! as num).toDouble(), (d['thickness']! as num).toDouble(), (d['coverWidth']! as num).toDouble()),
      titleTop: (raw['titleTop'] as num?)?.toDouble(),
      ribbonColor: raw['ribbon'] as String?,
      // 예시 책은 문장이 없어도 시안처럼 갈피가 보인다(지금 앱 ribbonVisible·ribbonCount)
      quotes: ((raw['ribbons'] as num?) ?? 0).toInt(),
      material: raw['material'] as String?,
      plainCover: raw['plainCover'] == true,
      reference: raw['cover'] as String?,
    );
    books[b.id] = b;
  }
  return ReferenceHome(jsonEncode(j['layout']), books, j['profile']);
}

/// 내 책이 생기면 예시 책을 전부 치운 배치(2026-11-15 사용자 결정: 첫 책을 넣는 순간 전부, 섞여 있으면 헷갈린다).
/// 예시 자리·서랍을 빼고, 책이 남은 선반을 위로 모은 뒤 빈 선반은 기본 칸 수(3)까지만 남긴다. 치울 예시가 없으면 null
ShelfLayout? withoutSamples(ShelfLayout layout, bool Function(String id) isSample) {
  if (!layout.placements.any((p) => isSample(p.bookId)) && !layout.drawer.any(isSample)) return null;
  final placements = [for (final p in layout.placements) if (!isSample(p.bookId)) p];
  final used = {for (final p in placements) p.shelfId};
  final shelves = sortedShelves(layout);
  final full = [for (final s in shelves) if (used.contains(s.id)) s];
  final empty = [for (final s in shelves) if (!used.contains(s.id)) s];
  final keep = [...full, ...empty.take((homeShelfCount - full.length).clamp(0, empty.length))];
  return normalize(ShelfLayout(
    [for (final (i, s) in keep.indexed) Shelf(s.id, i)],
    placements,
    [for (final id in layout.drawer) if (!isSample(id)) id],
  ));
}
