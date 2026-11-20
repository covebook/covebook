// 로그아웃·서버 계정 삭제 뒤 이 폰의 기록을 지운다(2026-11-16 사용자: 로그인 필수, 로그아웃하면 폰에서 지움).
// 지우는 것: 서재 DB의 모든 표(책·장정·회차·독서·갈피·감상·배치·연도 책장·올릴 목록), 진행 중 독서·저장 전 초안,
// 앱 안 사진(갈피·표지 사진), 받아 둔 표지, 책장 시작 사진, 동기화 토큰·계정. 남기는 것: 기기 설정(아래 keepKeys)
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/kv_store.dart';
import '../db/local_db.dart';
import '../features/home/home_screen.dart' show homeSnapshotFile;
import '../services/ambient.dart';
import 'bookcase_store.dart';
import 'entitlement_store.dart';
import 'files.dart';
import 'first_shelf.dart';
import 'library_model.dart';
import 'placement_store.dart';
import 'reading_store.dart';

/// 로그아웃해도 남기는 기기 설정: 진동·움직임 줄이기, 고른 선반·벽지, 책 측면 모양, 표지에서 잰 색·책등 비율(공개 책 정보), 지금 앱 보기 설정
const keepKeys = {'app-settings:v1', 'shelf-skin', 'spine-look', 'cover-accents-v2', 'yes24-spine-ratios-v1', 'view-settings:v3'};

/// 키·값 저장에서 지울 키인지(시험용으로 따로 둔다)
bool wipesKey(String key) => !keepKeys.contains(key);

Future<void> _emptyDir(Directory d) async {
  if (!d.existsSync()) return;
  for (final e in d.listSync()) {
    try {
      await e.delete(recursive: true);
    } catch (_) {
      // 쓰는 중인 파일은 다음에(지울 수 없어도 로그아웃은 계속한다)
    }
  }
}

Future<void> wipeLocalData() async {
  // 1) 읽는 중이면 멈추고 버린다(소리도 끈다)
  await ReadingStore.instance.discardAll();
  await Ambient.instance.stop().catchError((_) {});
  // 2) 서재 DB: 모든 표를 비우고 sync_meta만 처음 값으로
  final db = await openLibrary();
  await db.transaction((t) async {
    await t.execute('PRAGMA defer_foreign_keys = ON');
    final tables = await t.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'");
    for (final r in tables) {
      await t.rawDelete('DELETE FROM "${r['name']}"');
    }
    await t.execute('INSERT OR IGNORE INTO sync_meta(id) VALUES(1)');
  });
  // 3) 기기 값: 설정만 남긴다(동기화 토큰·계정·진행 중 독서·마지막 백업·예시 책장 표시 등은 지운다)
  await KvStore.removeAllExcept(keepKeys);
  // 4) 사진·표지·책장 시작 사진
  await _emptyDir(await imageDir());
  await _emptyDir(Directory('${(await getTemporaryDirectory()).path}/covers'));
  try {
    final snap = await homeSnapshotFile();
    if (snap.existsSync()) await snap.delete();
  } catch (_) {}
  // 5) 화면용 상태를 다시 읽는다(다음에 읽을 때 예시 책장을 다시 준비)
  // 결제 상태: 디스크 캐시는 3)에서 지웠고 메모리 값(구독·연도별 선반)도 비운다. 다른 계정으로 로그인했는데 /iap/me가 실패하면 앞 계정의 칸이 보이지 않게
  await EntitlementStore.instance.clear();
  resetFirstShelf();
  await LibraryModel.instance.reload();
  await PlacementStore.instance.reload();
  await BookcaseStore.instance.load();
}
