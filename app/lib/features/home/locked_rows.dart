// 잠긴 선반(지금 앱 features/home/LockedShelves·domain/locked-preview): 마지막 선반 아래 칸은 흐린 책과 자물쇠로 보이고,
// 누르면 '선반 한 칸 더 열기' 시트가 뜬다. 칸 수는 여섯 칸(shelfSlots)에서 지금 선반 수를 뺀 만큼. 무료는 세 칸까지, 나머지 세 칸은 유료 예정(준비 중 안내 확인창).
// 2026-11-19 정환: 책장 6칸 = 무료 3 + 유료 3, 유료 칸은 연도 책장마다 산다(ADR-0002 D1)
// 흐린 책은 지금 앱이 고른 예시 책(색만, 제목·표지 없음)과 배치 계산이 끝난 상자 그대로(assets/locked_preview.json)
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/book3.dart';
import '../../domain/book3_physics.dart';
import '../../domain/placed.dart';
import '../../domain/types.dart';

const shelfSlots = 6;
int lockedShelfCount(int shelves) => (shelfSlots - shelves).clamp(0, shelfSlots);

/// 무료로 쓸 수 있는 선반 칸 수(2026-11-15 사용자 결정: 3칸까지 무료, 그 위는 유료 예정·결제는 아직 없음)
const freeShelfSlots = 3;

/// 지금 바로 더 열 수 있는 선반 칸 수(무료 칸까지)
int openableShelfCount(int shelves) => (freeShelfSlots - shelves).clamp(0, freeShelfSlots);

class LockedRow {
  const LockedRow(this.books, this.bodies);
  final List<Book> books;
  final List<Book3> bodies;
}

List<LockedRow>? _rows;

HeightClass _h(String? v) => HeightClass.values.firstWhere((e) => e.name == v, orElse: () => HeightClass.medium);
ThicknessClass _t(String? v) => ThicknessClass.values.firstWhere((e) => e.name == v, orElse: () => ThicknessClass.medium);
Pose _pose(String? v) => switch (v) { 'front' => Pose.front, 'horizontal' => Pose.horizontal, _ => Pose.upright };

/// 잠긴 칸 i번째의 흐린 책(칸 세 종류를 돌려 쓴다)
Future<LockedRow> lockedRow(int i) async {
  if (_rows == null) {
    final raw = jsonDecode(await rootBundle.loadString('assets/locked_preview.json')) as Map<String, dynamic>;
    _rows = [
      for (final r in (raw['rows'] as List).cast<Map<String, dynamic>>())
        LockedRow(
          [
            for (final b in (r['books'] as List).cast<Map<String, dynamic>>())
              Book(
                id: b['id'] as String,
                title: '',
                themeColor: int.parse((b['themeColor'] as String).substring(1), radix: 16),
                heightClass: _h(b['heightClass'] as String?),
                thicknessClass: _t(b['thicknessClass'] as String?),
                coverAspectRatio: (b['coverAspectRatio'] as num).toDouble(),
                physical: b['physical'] == null
                    ? null
                    : Physical(
                        widthMm: ((b['physical'] as Map)['widthMm'] as num?)?.toDouble(),
                        heightMm: ((b['physical'] as Map)['heightMm'] as num?)?.toDouble(),
                        pages: ((b['physical'] as Map)['pages'] as num?)?.toInt(),
                      ),
                dims: b['dims'] == null
                    ? null
                    : BookDims(((b['dims'] as Map)['height'] as num).toDouble(), ((b['dims'] as Map)['thickness'] as num).toDouble(),
                        ((b['dims'] as Map)['coverWidth'] as num).toDouble()),
              ),
          ],
          [
            for (final x in (r['boxes'] as List).cast<Map<String, dynamic>>())
              fromPlaced(Placed(
                x['bookId'] as String,
                _pose(x['pose'] as String?),
                BoxSize(((x['size'] as Map)['w'] as num).toDouble(), ((x['size'] as Map)['h'] as num).toDouble(), ((x['size'] as Map)['d'] as num).toDouble()),
                (x['x'] as num).toDouble(),
                (x['y'] as num).toDouble(),
                (x['z'] as num).toDouble(),
                (x['angle'] as num).toDouble(),
                spin: (x['spin'] as num?)?.toDouble(),
                pitch: (x['pitch'] as num?)?.toDouble(),
                flip: x['flip'] == true,
              )),
          ],
        ),
    ];
  }
  return _rows![i % _rows!.length];
}
