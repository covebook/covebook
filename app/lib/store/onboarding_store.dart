// 첫 안내(온보딩, 2026-11-27 사용자): 직접 해 보는 것은 두 가지뿐이다.
// 1) 첫 책 꽂기: 빈 책장에서 '첫 책 꽂기'로 책 한 권을 골라 책장에 꽂는다.
// 2) 첫 갈피: 꽂은 뒤 선반을 잠깐 그대로 보여 주고, 그 책에 꽂을 예시 한 줄을 누르면 책 위로 갈피가 나온다(직접 쓰기 · 건너뛰기 가능). 여기서 끝.
// 읽기 기록 · 달력은 안내하지 않는다(첫 독서를 마치면 '오늘 N분 읽었어요 · 달력에서 보기'로 이어진다, reading_screen).
// 끝나면 기기에 적어 두고 다시 띄우지 않는다(책을 전부 빼거나 앱을 다시 켜도). 이미 책이 있는 서재(기존 사용자 · 동기화로 받은 서재)는 처음부터 끝낸 것으로 친다.
// 갈피 차례에서 앱을 껐으면 다음에 책장을 열 때 그 차례를 한 번 더 보인다(닫거나 건너뛰면 끝)
library;

import 'package:flutter/foundation.dart';

import '../db/kv_store.dart';

class Onboarding extends ChangeNotifier {
  Onboarding._();
  static final instance = Onboarding._();

  /// 'active'(첫 책 꽂기) · 'mark'(첫 갈피) · 'done'(끝). 없으면 아직 정하지 않았다(처음 켬 · 이 안내가 생기기 전 사용자)
  static const _key = 'onboarding:first-book';
  static const _bookKey = 'onboarding:first-book-id';

  bool loaded = false;
  String _stage = 'done';

  /// 안내로 꽂은 첫 책(첫 갈피를 꽂을 책)
  String? firstBookId;

  /// 빈 책장 첫 책 안내 중('첫 책 꽂기' 단추 · 표지 강조)
  bool get active => loaded && _stage == 'active';

  /// 첫 갈피 차례면 그 책
  String? get markBook => loaded && _stage == 'mark' ? firstBookId : null;

  Future<void>? _loading;

  /// 서재를 다 읽은 뒤 한 번: 끝낸 적이 있으면 끝, 정하지 않았으면 책이 있는 서재는 끝 · 빈 서재는 시작
  Future<void> load({required bool anyBooks}) => _loading ??= () async {
        final v = await KvStore.get(_key);
        firstBookId = await KvStore.get(_bookKey);
        if (v == null) {
          _stage = anyBooks ? 'done' : 'active';
          await KvStore.set(_key, _stage);
        } else {
          _stage = v == 'mark' && firstBookId == null ? 'done' : v;
        }
        loaded = true;
        notifyListeners();
      }();

  /// 책장에 첫 책이 놓였다: 첫 책 차례를 끝낸다. [bookId]는 안내로 꽂은 책(첫 갈피 차례로 넘어간다, 없으면 다른 길로 책이 생긴 것이라 안내를 끝낸다)
  void finish([String? bookId]) {
    if (!active) return;
    _stage = bookId == null ? 'done' : 'mark';
    firstBookId = bookId;
    KvStore.set(_key, _stage).ignore();
    if (bookId != null) KvStore.set(_bookKey, bookId).ignore();
    notifyListeners();
  }

  /// 첫 갈피 차례가 끝났다(꽂았거나 · 직접 쓰러 갔거나 · 건너뛰었거나 · 그 책이 없어졌다): 안내 끝
  void finishMark() {
    if (_stage != 'mark') return;
    _stage = 'done';
    KvStore.set(_key, 'done').ignore();
    notifyListeners();
  }

  /// 시험: 정해 둔 상태에서 시작한다(기기에는 쓰지 않는다)
  @visibleForTesting
  void reset({bool loaded = true, bool active = false, String? firstBookId, bool mark = false}) {
    this.loaded = loaded;
    _stage = active ? 'active' : mark ? 'mark' : 'done';
    this.firstBookId = firstBookId;
    _loading = loaded ? Future.value() : null;
    notifyListeners();
  }
}
