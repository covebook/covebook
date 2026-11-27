// 첫 책 꽂기 안내(온보딩, 2026-11-27 사용자): 빈 책장에서 '첫 책 꽂기'로 책 한 권을 골라 책장에 꽂으면 끝난다.
// 끝나면 기기에 적어 두고 다시 띄우지 않는다(책을 전부 빼거나 앱을 다시 켜도). 이미 책이 있는 서재(기존 사용자 · 동기화로 받은 서재)는 처음부터 끝낸 것으로 친다.
// 꽂은 첫 책은 읽기 탭 첫 안내('방금 꽂은 책으로 읽기 시작')에 쓴다. 읽기 탭 안내도 한 번 보면 다시 띄우지 않는다
library;

import 'package:flutter/foundation.dart';

import '../db/kv_store.dart';

class Onboarding extends ChangeNotifier {
  Onboarding._();
  static final instance = Onboarding._();

  /// 'active'(안내 중) · 'done'(끝). 없으면 아직 정하지 않았다(처음 켬 · 이 안내가 생기기 전 사용자)
  static const _key = 'onboarding:first-book';
  static const _bookKey = 'onboarding:first-book-id';
  static const _readKey = 'onboarding:read-guide';

  bool loaded = false;
  bool _active = false;

  /// 안내로 꽂은 첫 책(읽기 탭 첫 안내가 권한다)
  String? firstBookId;

  /// 읽기 탭 첫 안내를 보았다
  bool readGuideSeen = false;

  /// 빈 책장 첫 책 안내 중('첫 책 꽂기' 단추 · 표지 강조)
  bool get active => loaded && _active;

  Future<void>? _loading;

  /// 서재를 다 읽은 뒤 한 번: 끝낸 적이 있으면 끝, 정하지 않았으면 책이 있는 서재는 끝 · 빈 서재는 시작
  Future<void> load({required bool anyBooks}) => _loading ??= () async {
        final v = await KvStore.get(_key);
        firstBookId = await KvStore.get(_bookKey);
        readGuideSeen = await KvStore.get(_readKey) == 'seen';
        if (v == null) {
          _active = !anyBooks;
          await KvStore.set(_key, _active ? 'active' : 'done');
        } else {
          _active = v == 'active';
        }
        loaded = true;
        notifyListeners();
      }();

  /// 책장에 첫 책이 놓였다: 안내를 끝내고 적어 둔다. [bookId]는 안내로 꽂은 책(읽기 탭 첫 안내가 권한다, 없으면 읽기 탭 안내도 없다)
  void finish([String? bookId]) {
    if (!active) return;
    _active = false;
    firstBookId = bookId;
    KvStore.set(_key, 'done').ignore();
    if (bookId != null) KvStore.set(_bookKey, bookId).ignore();
    notifyListeners();
  }

  /// 읽기 탭 첫 안내를 보고 다른 탭으로 갔다(또는 읽기를 시작했다)
  void markReadGuideSeen() {
    if (readGuideSeen) return;
    readGuideSeen = true;
    KvStore.set(_readKey, 'seen').ignore();
    notifyListeners();
  }

  /// 시험: 정해 둔 상태에서 시작한다(기기에는 쓰지 않는다)
  @visibleForTesting
  void reset({bool loaded = true, bool active = false, String? firstBookId, bool readGuideSeen = false}) {
    this.loaded = loaded;
    _active = active;
    this.firstBookId = firstBookId;
    this.readGuideSeen = readGuideSeen;
    _loading = loaded ? Future.value() : null;
    notifyListeners();
  }
}
