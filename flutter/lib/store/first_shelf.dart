// 처음 켤 때 책장 준비(지금 앱 bootStores의 installReferenceHome): 빈 서재면 시안 예시 책장 자리를 저장한다(예시 책 자체는 저장하지 않는다, domain/reference_home).
// 시험 빌드(--dart-define=QA_SEED_LIB=true)는 대신 지금 앱 QA 비교 서재(store/seed.dart)를 넣는다(두 앱을 같은 데이터로 견줄 때)
library;

import 'dart:convert';

import '../db/kv_store.dart';
import '../db/local_db.dart';
import '../domain/layout.dart';
import '../domain/layout_json.dart';
import '../domain/reference_home.dart';
import 'library_store.dart' show saveLayout;
import 'seed.dart';

const _qaSeedLib = bool.fromEnvironment('QA_SEED_LIB');

Future<void>? _preparing;

/// 예시 책장 자리의 시각. 이 시각인 배치는 서버에 올리지 않고(services/sync), 서버에서 받은 배치가 늘 이긴다.
/// 로그인이 필수가 되어 새 폰에서 기존 계정으로 들어오면, 받기 전에 깔린 예시 자리가 '방금 고친 배치'로 올라가 진짜 책장을 덮을 수 있었다(2026-11-16)
const exampleLayoutAt = '1970-01-01T00:00:00.000Z';

/// 한 번만(여러 곳에서 불러도 같은 작업을 기다린다)
Future<void> prepareFirstShelf() => _preparing ??= _prepare();

/// 로그아웃으로 기기 기록을 지운 뒤: 다음에 읽을 때 예시 책장을 다시 준비한다
void resetFirstShelf() => _preparing = null;

Future<void> _prepare() async {
  // 보기 책 책등 비율(지금 앱이 잰 실제 두께): 같은 책을 가진 서재도 같은 두께로
  rememberSampleSpineRatios();
  if (_qaSeedLib) return seedIfEmpty();
  await loadReferenceHome();
  final home = referenceHome;
  if (home == null || home.books.isEmpty) return;
  // 지금 앱에서 넘어온 서재·이미 설치한 서재는 그대로
  if (await KvStore.get(referenceHomeKey) != null) return;
  final db = await openLibrary();
  Future<int> count(String table) async => ((await db.rawQuery('SELECT COUNT(*) c FROM $table')).first['c'] as int?) ?? 0;
  // 시안은 새 서재에만: 책·자리·선반이 하나라도 있으면 사용자의 기록이다
  if (await count('my_books') > 0 || await count('shelf_placements') > 0 || await count('shelves') > 0) return;
  final layout = layoutFromJson(home.layoutJson);
  if (layout == null) return;
  await saveLayout(const ShelfLayout([], []), layout);
  await db.rawUpdate('UPDATE sync_meta SET layout_dirty = 0, layout_at = ? WHERE id = 1', [exampleLayoutAt]);
  await KvStore.set(referenceHomeKey, jsonEncode({'complete': true, 'profile': home.profile}));
}
