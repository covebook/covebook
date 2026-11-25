// 처음 켤 때 책장 준비: 보기 책 책등 비율을 기억해 두고, 빈 서재면 빈 선반 세 칸을 깐다
// (예시 책장은 2026-11-25 사용자 '예시 책들 없애버려'로 없앴다. 예전에 깔린 예시 자리는 서재를 읽을 때 치운다, domain/sample_cleanup).
// 시험 빌드(--dart-define=QA_SEED_LIB=true)는 지금 앱 QA 비교 서재(store/seed.dart)를 넣는다(두 앱을 같은 데이터로 견줄 때)
library;

import '../db/local_db.dart';
import '../domain/layout.dart';
import '../domain/sample_cleanup.dart' show exampleLayoutAt;
import 'library_store.dart' show saveLayout;
import 'seed.dart';

const _qaSeedLib = bool.fromEnvironment('QA_SEED_LIB');

Future<void>? _preparing;

/// 한 번만(여러 곳에서 불러도 같은 작업을 기다린다)
Future<void> prepareFirstShelf() => _preparing ??= _prepare();

/// 로그아웃으로 기기 기록을 지운 뒤: 다음에 읽을 때 다시 준비한다
void resetFirstShelf() => _preparing = null;

Future<void> _prepare() async {
  // 보기 책 책등 비율(지금 앱이 잰 실제 두께): 같은 책을 가진 서재도 같은 두께로
  rememberSampleSpineRatios();
  if (_qaSeedLib) return seedIfEmpty();
  // 빈 서재: 빈 선반 세 칸. 예시 책장이 선반도 함께 깔았는데 예시를 없애자 선반 없이 잠긴 칸만 보였다(2026-11-26 아이폰 시뮬레이터).
  // 손대지 않은 배치 시각(exampleLayoutAt)으로 둬 서버에 올리지 않는다: 새 폰에서 기존 계정으로 들어오면 받은 책장이 이긴다
  final db = await openLibrary();
  Future<int> count(String table) async => ((await db.rawQuery('SELECT COUNT(*) c FROM $table')).first['c'] as int?) ?? 0;
  if (await count('my_books') > 0 || await count('shelf_placements') > 0 || await count('shelves') > 0) return;
  await saveLayout(const ShelfLayout([], []), ensureShelves(const ShelfLayout([], [])));
  await db.rawUpdate('UPDATE sync_meta SET layout_dirty = 0, layout_at = ? WHERE id = 1', [exampleLayoutAt]);
}
