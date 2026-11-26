// 예전 앱이 빈 서재에 깔던 예시 책장의 흔적을 치운다.
// 예시 책장(시안 예시 책 18권 자리 + 그림 표지 3장)은 2026-11-25 사용자 '예시 책들 없애버려'로 없앴다. 그 전에 설치한 폰에는
// 예시 책 자리(표시 전용 책 id)가 배치에 남아 있어, 서재를 읽을 때 치운다(store/library_store loadLibrary).
library;

import 'layout.dart';
import 'types.dart' show Shelf;

/// 예시 책 id(지금 앱 home-reference: home-reference-b01 꼴, 복사본은 -2 같은 꼬리)
final _sampleId = RegExp(r'^home-reference-b\d{2}(-\d+)?$');

bool isSampleBookId(String id) => _sampleId.hasMatch(id);

/// 손대지 않은 첫 배치(예전 예시 책장 자리, 지금은 빈 서재의 빈 선반 세 칸 store/first_shelf)의 시각.
/// 이 시각인 배치는 서버에 올리지 않고(services/sync), 서버에서 받은 배치가 늘 이긴다.
/// 새 폰에서 기존 계정으로 들어오면, 받기 전에 깔린 예시 자리가 '방금 고친 배치'로 올라가 진짜 책장을 덮을 수 있었다(2026-11-16).
/// 예시를 치운 배치도 이 시각을 그대로 둔다(치운 것만으로 서버 책장을 덮지 않게)
const exampleLayoutAt = '1970-01-01T00:00:00.000Z';

/// 예시 책을 전부 치운 배치(2026-11-15 사용자 결정 '첫 책을 넣는 순간 전부, 섞여 있으면 헷갈린다' 때 만든 규칙 그대로).
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
