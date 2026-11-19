// 책을 책장에 놓기(지금 앱 features/book/place-books.ts + NoRoomSheet): 전체 책·책 정보·책 추가가 같이 쓴다. 책 정보는 그대로, 배치만 바꾼다.
// - 이미 책장에 있는 책은 건너뛴다. 다른 책을 옮기거나 눕혀 끼워 넣지 않는다(빈 자리에만).
// - 자리가 모자라면 묻는다: 선반 한 칸 더 열기(무료 세 칸까지) 또는 '보관만 하기'(책장에 없는 책으로). 무료 칸을 다 열었으면 보관하고
//   '책장이 꽉 찼다'고 사실대로 알린다(2026-11-15 QA: '무료로'는 곧 돈 받겠다는 뜻으로 읽혔고, 꽉 찬 뒤 '언제든 진열'은 틀린 말이었다).
//   바깥을 누르거나 닫으면 보관한다(책이 사라지지 않게)
library;

import 'package:flutter/material.dart';

import '../../domain/layout.dart' show placementOf;
import '../../scene_config/skin.dart' show skinPlank;
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/book_visual.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../home/locked_rows.dart' show allowedShelfSlots, freeShelfSlots, openableShelfCount;
import '../../services/iap.dart' show IapService;
import '../../store/entitlement_store.dart';

/// 놓을 수 있는 만큼 놓는다(놓은 책, 자리가 없어 남은 책)
Future<({List<String> placed, List<String> left})> placeBooks(Iterable<String> ids) async {
  final s = PlacementStore.instance;
  await s.ensure();
  final placed = <String>[], left = <String>[];
  for (final id in ids) {
    if (placementOf(s.layout!, id) != null) continue;
    (await s.placeOnShelf(id) ? placed : left).add(id);
  }
  return (placed: placed, left: left);
}

/// 놓아 보고, 남은 책이 있으면 선반 한 칸 더 열기 / 보관만 하기를 고르게 한다.
/// 끝나면 (놓은 수, 보관만 한 수, 무료 칸이 다 차서 보관했는지: 결과 문구는 keptTitle·keptNote)
Future<({int placed, int kept, bool full})> placeWithChoice(BuildContext context, List<String> ids) async {
  final s = PlacementStore.instance;
  var total = 0;
  var rest = ids;
  var afterNewShelf = false;
  while (true) {
    final r = await placeBooks(rest);
    total += r.placed.length;
    if (r.left.isEmpty) return (placed: total, kept: 0, full: false);
    Future<({int placed, int kept, bool full})> keep(bool full) async {
      for (final id in r.left) {
        await s.addToDrawer(id);
      }
      return (placed: total, kept: r.left.length, full: full);
    }

    // 새 빈 선반에도 한 권도 못 놓았으면(선반보다 큰 책) 더 묻지 않는다(선반이 끝없이 늘지 않게). 무료 칸을 다 열었으면 보관
    if (afterNewShelf && r.placed.isEmpty) return keep(false);
    final free = openableShelfCount(s.layout!.shelves.length, iapOn ? EntitlementStore.instance.shelves : 0);
    if (free == 0 || !context.mounted) return keep(free == 0);
    final open = await _askNoRoom(context, r.left, free);
    if (open != true || !await s.addShelf()) return keep(false);
    rest = r.left;
    afterNewShelf = true;
  }
}

/// 책장에 못 놓고 보관했을 때 결과 제목·설명(책 추가 결과·전체 책 진열이 같이 쓴다)
String keptTitle({required bool full}) => full ? '책장이 꽉 차서 내 책에 보관했어요' : '내 책에만 보관했어요';
String keptNote({required bool full}) =>
    full ? '선반 $freeShelfSlots칸이 다 찼어요. 책장에서 책을 빼면 그 자리에 진열할 수 있어요.' : '책장에는 아직 없어요. 내 책에서 진열할 수 있어요.';

/// 자리가 없을 때 전용 시트: 진열하려던 책이 선반 판 위에 서 있고, 아래에서 선반을 열거나 보관한다. true = 선반 열기. free: 더 열 수 있는 칸 수
Future<bool?> _askNoRoom(BuildContext context, List<String> ids, int free) {
  final lib = LibraryModel.instance.lib;
  final shown = [for (final id in ids) if (lib.books[id] != null) id].take(3).toList();
  final rest = ids.length - shown.length;
  return showSheet<bool>(
    context,
    title: '책장에 빈 자리가 없어요',
    description: '${ids.length}권을 진열할 자리가 없어요. 선반을 한 칸 더 열까요? 앞으로 $free칸 더 열 수 있어요.',
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        label: '진열하려던 책 ${ids.length}권',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(top: Space.s, bottom: Space.xl),
          child: Column(children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 100),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (i, id) in shown.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.m),
                  SizedBox(width: CoverSize.place, child: BookVisual(lib: lib, id: id, width: CoverSize.place)),
                ],
                if (rest > 0) Padding(padding: const EdgeInsets.only(left: Space.m, bottom: Space.xs), child: Text('외 $rest권', style: AppType.sub)),
              ]),
            ),
            // 선반 판(지금 책장 판 색), 좌우로 조금 넓게
            LayoutBuilder(
              builder: (_, box) => SizedBox(
                height: 8,
                child: OverflowBox(
                  maxWidth: box.maxWidth + Space.xs * 2,
                  child: Container(height: 8, decoration: BoxDecoration(color: Color(0xFF000000 | skinPlank.color), borderRadius: BorderRadius.circular(2))),
                ),
              ),
            ),
          ]),
        ),
      ),
      Btn(label: '선반 열고 진열하기', size: 'l', onPress: () => Navigator.pop(ctx, true)),
      SubAction(label: '보관만 하기', onPress: () => Navigator.pop(ctx, false)),
    ]),
  );
}

/// 환불로 구매한 선반 칸이 줄었으면 그 칸을 닫는다(ADR-0002 D13, 2026-11-19 정환: 무료 세 칸은 건드리지 않고,
/// 잠기는 칸은 책을 다 빼고 아직 안 연 선반처럼 잠근다). 뺀 책은 내 책에 보관된다. 옮긴 책 수를 돌려준다.
/// 서버에서 이번 실행에 받은 상태로만 한다: 기기에 남긴 지난번 값이나 받기 전의 0으로 선반을 닫지 않는다
Future<int> enforceShelfLimit() async {
  final e = EntitlementStore.instance;
  if (!iapOn || !IapService.instance.synced) return 0;
  final s = PlacementStore.instance;
  await s.ensure();
  return s.closeShelvesBeyondLimit(allowedShelfSlots(e.shelves));
}
