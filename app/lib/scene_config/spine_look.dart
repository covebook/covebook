// 실제 책(YES24 표지가 있는 책)의 옆면(책등) 모양. 꾸미기 › 디자인 '책 옆면'에서 책마다 고른다
// (2026-11-23 사용자 '책 옆면은 책마다 따로 고르는 게 더 자연스러워요 … 고른 모양은 그 책에만'. 전에는 모든 책에 같이 걸렸다).
//  color  단색: 표지에서 책등과 맞닿는 띠의 색 한 가지 + 제목(기본)
//  photo  측면: YES24 책등 사진 그대로(제목·장식이 사진 안에 있다. 책등 사진이 없는 책은 단색)
//  stripe 겹무늬: 앞표지에서 책등과 맞닿는 가장자리 한 줄을 옆으로 늘려 표지 색이 책등까지 줄무늬로 이어지게 + 제목
// 실행 중에 바꿀 수 있다(책장이 표지 사진을 다시 읽어 그린다). 전처럼 이 기기에만 저장한다(동기화하지 않는다).
// 옛 저장 키 'spine-look'(모든 책에 같이 고른 값)은 아직 따로 고르지 않은 책의 기본값으로 읽는다(고쳐 놓은 책장이 바뀌지 않게)
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../db/kv_store.dart';

enum SpineLook { color, photo, stripe }

const _baseKey = 'spine-look', _booksKey = 'spine-look-books';

SpineLook? _parse(Object? v) => switch (v) { 'color' => SpineLook.color, 'photo' => SpineLook.photo, 'stripe' => SpineLook.stripe, _ => null };

/// 책마다 고른 옆면 모양(바뀌면 책장·책 그림이 다시 그린다)
class SpineLooks extends ChangeNotifier {
  SpineLook _base = SpineLook.color;
  Map<String, SpineLook> _byBook = const {};

  /// 이 책의 옆면 모양(고른 적 없으면 기본값)
  SpineLook of(String bookId) => _byBook[bookId] ?? _base;

  /// 그림을 다시 만들지 정하는 열쇠(고른 값이 바뀌면 달라진다)
  String get key => '${_base.name}|${[for (final e in _byBook.entries) '${e.key}:${e.value.name}'].join(',')}';

  /// 시작할 때 저장된 값을 읽는다(책장을 그리기 전에)
  Future<void> load() async {
    _base = _parse(await KvStore.get(_baseKey)) ?? SpineLook.color;
    final raw = await KvStore.get(_booksKey);
    Map<String, SpineLook> m = const {};
    if (raw != null) {
      try {
        m = {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: ?_parse(e.value)};
      } catch (_) {}
    }
    _byBook = m;
    notifyListeners();
  }

  /// 이 책의 모양을 바꾸고 저장한다
  Future<void> set(String bookId, SpineLook v) async {
    if (of(bookId) == v && _byBook.containsKey(bookId)) return;
    _byBook = {..._byBook, bookId: v};
    notifyListeners();
    await KvStore.set(_booksKey, jsonEncode({for (final e in _byBook.entries) e.key: e.value.name}));
  }

  @visibleForTesting
  void setForTest(Map<String, SpineLook> byBook, {SpineLook base = SpineLook.color}) {
    _base = base;
    _byBook = byBook;
    notifyListeners();
  }
}

final spineLooks = SpineLooks();

/// 시작할 때 저장된 값을 읽는다(책장을 그리기 전에)
Future<void> loadSpineLook() => spineLooks.load();
