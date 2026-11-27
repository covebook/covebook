// 책 고르기 시트 하나(docs/design/DESIGN.md 13장, 지금 앱 features/bookmark/BookPicker.tsx에서 시작): 앱에서 책을 하나 고르는 시트는 모두 이것.
// 갈피 남기기 · 감상 쓰기 · 독서 끝 · 기록 수정 · 읽기 장면(내 책 전부, 최근 읽은 책 먼저)과 기록 탭 거르기 · 갈피 보드 · 통계(고를 책을 정해 준다)가
// 같은 모양: 제목 '책 고르기', 지금 고른 것은 고르는 원, '모든 책'은 책이 아니라 맨 위 하나 고르기 줄, 책이 많으면 검색, 검색 0건 안내(2026-11-19 공통 규칙: 세 벌이었다).
// multi: 여러 권 고르기(읽기 탭 '책 추가'). 줄을 누르면 체크만 되고 '완료'로 한꺼번에 넘긴다
library;

// 읽기 상태 이름은 features/book/labels.dart(책장 홈 파일들이 이 파일에서 가져다 써서 다시 내보낸다)
export '../book/labels.dart' show statusLabel;
import '../book/labels.dart' show statusLabel;
import 'package:flutter/material.dart';

import '../book/add_book_screen.dart' show openAddBook;

import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../stats/stats_widgets.dart';


/// 여러 권 고르기: fixed = 이미 목록에 있어 고를 수 없는 것(체크된 채 흐리게), none = '책 없이 읽기' 줄의 값
class MultiPick {
  const MultiPick({required this.fixed, required this.none});
  final List<String> fixed;
  final String none;
}

/// 고를 책이 이보다 많으면 위에 검색칸(기록 탭 책 고르기가 쓰던 기준)
const _searchFrom = 5;

/// 한 권 고르기: 고른 책 id(책 없이 읽기 · 모든 책이면 null)를 돌려준다. 닫으면 (picked: false)
/// - current: 지금 고른 것((id: null)은 책 없이 읽기 · 모든 책). 주면 줄마다 고르는 원, 고른 줄은 채운 원
/// - books: 고를 책(순서 그대로). 없으면 숨기지 않은 내 책 전부(최근 읽은 책 먼저). meta: 책 줄 둘째 줄(없으면 '저자 | 읽기 상태')
/// - all: 맨 위 '모든 책' 줄(고르면 null, allSub는 그 아래 작은 글). allowNone: '책 없이 읽기' 줄
/// - addNew: 맨 위 '+ 새 책 등록'(책 추가로 갔다가 등록한 책을 고른 것으로 돌아온다). 책을 기록에 잇는 고르기(갈피 · 감상 · 읽기 장면 · 독서 끝 · 기록 수정)는
///   모두 켠다(2026-11-21 사용자 '여기는 왜 책 추가 없어'). 이미 있는 기록을 거르는 고르기(기록 탭 · 통계)는 끈다.
///   holdNew: 새로 등록한 책을 책장에 진열하지 않고 들고 온다(첫 책 꽂기, openAddBook hold)
Future<({bool picked, String? id})> pickBook(
  BuildContext context,
  Library lib, {
  bool allowNone = false,
  bool addNew = false,
  ({String? id})? current,
  List<String>? books,
  String Function(String id)? meta,
  bool all = false,
  String? allSub,
  String? description,
  bool holdNew = false,
}) async {
  final r = await showSheet<({bool picked, String? id})>(
    context,
    title: '책 고르기',
    description: description,
    // 검색할 때는 시트가 화면 맨 위까지 올라간다(_Picker가 높이를 다 쓴다, 2026-11-20 사용자). 평소에는 목록 길이만큼
    maxHeight: 0.95,
    fit: true,
    builder: (ctx) => _Picker(
      lib: lib,
      allowNone: allowNone,
      current: current,
      books: books,
      meta: meta,
      all: all,
      allSub: allSub,
      onPick: (id) => Navigator.pop(ctx, (picked: true, id: id)),
      onAddNew: addNew ? () => Navigator.pop(ctx, (picked: false, id: _addNew)) : null,
    ),
  );
  if (r?.id == _addNew && context.mounted) {
    final id = await openAddBook(context, pick: !holdNew, hold: holdNew);
    return id != null ? (picked: true, id: id) : (picked: false, id: null);
  }
  return r ?? (picked: false, id: null);
}

const _addNew = '\u0000new';

/// 여러 권 고르기: 새로 고른 것(고른 순서). 닫거나 하나도 안 고르면 빈 목록
Future<List<String>> pickBooks(BuildContext context, Library lib, MultiPick multi, {bool allowNone = false}) async {
  final r = await showSheet<List<String>>(
    context,
    title: '읽기 목록에 추가',
    description: '타이머에 둘 책을 골라요. 여러 권 고를 수 있어요.',
    maxHeight: 0.85,
    fit: true,
    builder: (ctx) => _Picker(lib: lib, allowNone: allowNone, multi: multi, onDone: (ids) => Navigator.pop(ctx, ids)),
  );
  return r ?? const [];
}

class _Picker extends StatefulWidget {
  const _Picker({
    required this.lib,
    this.allowNone = false,
    this.multi,
    this.onPick,
    this.onDone,
    this.onAddNew,
    this.current,
    this.books,
    this.meta,
    this.all = false,
    this.allSub,
  });
  final Library lib;
  final bool allowNone;
  final MultiPick? multi;
  final ValueChanged<String?>? onPick;
  final ValueChanged<List<String>>? onDone;
  final VoidCallback? onAddNew;
  final ({String? id})? current;
  final List<String>? books;
  final String Function(String id)? meta;
  final bool all;
  final String? allSub;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String _q = '';
  final _picked = <String>[];

  /// 검색칸에 초점이 있다(검색 중): 시트를 화면 위까지 키운다
  bool _searchFocus = false;

  void _choose(String? id) {
    final m = widget.multi;
    if (m == null) return widget.onPick?.call(id);
    final k = id ?? m.none;
    setState(() => _picked.contains(k) ? _picked.remove(k) : _picked.add(k));
  }

  /// 고른 줄인지(id null = 책 없이 읽기 · 모든 책). 한 권 고르기는 current를 받았을 때만 안다
  bool _on(String? id) {
    final m = widget.multi;
    if (m != null) {
      final k = id ?? m.none;
      return m.fixed.contains(k) || _picked.contains(k);
    }
    return widget.current != null && widget.current!.id == id;
  }

  /// 고르는 원: 여러 권 고르기, 또는 지금 고른 것을 받은 한 권 고르기. 이미 목록에 있으면 흐린 채움
  Widget? _mark(String? id) {
    final m = widget.multi;
    if (m == null && widget.current == null) return null;
    return RadioMark(on: _on(id), dim: m != null && m.fixed.contains(id ?? m.none));
  }

  /// 책 줄과 '책 없이 읽기' 줄: BookRow 작게 하나가 이름 · 고른 상태 · 누르기를 함께 가진다(바깥에 이름을 또 달아 두 번 읽혔다, 2026-11-19)
  Widget _row({required Widget cover, required String title, String meta = '', required String? id, required bool fixed}) {
    final m = widget.multi;
    final on = _on(id);
    final row = BookRow(
      cover: cover,
      title: title,
      meta: meta,
      trailing: _mark(id),
      label: [title, ...meta.split(metaSep)].where((s) => s.isNotEmpty).join(', '),
      selected: m == null && widget.current != null ? on : null,
      checked: m != null ? on : null,
      onPress: fixed ? null : () => _choose(id),
    );
    return fixed ? Opacity(opacity: disabledOpacity, child: row) : row;
  }

  Widget _book(String id) {
    final lib = widget.lib, m = widget.multi;
    final b = lib.books[id]!;
    final e = lib.editions[b.editionId];
    final fixed = m?.fixed.contains(id) ?? false;
    final meta = widget.meta?.call(id) ?? [if (e != null && e.authors.isNotEmpty) authorLine(e.authors), fixed ? '목록에 있어요' : statusLabel[b.status]!].join(metaSep);
    return _row(
      cover: IgnorePointer(child: LinkedCover(lib: lib, id: id, width: BookRow.coverWidth(BookRowSize.small))),
      title: e?.title ?? '',
      meta: meta,
      id: id,
      fixed: fixed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.lib, m = widget.multi;
    final List<String> ids;
    if (widget.books != null) {
      ids = [for (final id in widget.books!) if (lib.books.containsKey(id)) id];
    } else {
      // 숨긴 책(연도 책장에만 남긴 책)은 고를 책에서 뺀다(지금 앱 서재에는 숨긴 책이 없다)
      final recent = [for (final id in recentBookIds(lib)) if (lib.books[id]?.hiddenAt == null) id];
      ids = [...recent, ...lib.books.keys.where((id) => !recent.contains(id) && lib.books[id]!.hiddenAt == null)];
    }
    final t = _q.trim();
    // 제목과 저자에서 찾는다. 판은 한 번만 찾는다(두 번 찾다 판이 없으면 'null' 글자가 검색에 걸렸다, 2026-11-19)
    bool hit(String id) {
      final e = lib.editions[lib.books[id]!.editionId];
      return e != null && '${e.title} ${e.authors.join(' ')}'.contains(t);
    }

    final list = [for (final id in ids) if (t.isEmpty || hit(id)) id];
    final noneFixed = m != null && m.fixed.contains(m.none);
    // 검색 중이면 시트가 높이를 다 쓴다(맨 위까지): 목록이 남은 높이를 채운다
    final tall = _searchFocus || t.isNotEmpty;
    final listView = ListView(shrinkWrap: !tall, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
          if (widget.onAddNew != null)
            Semantics(
              button: true,
              label: '새 책 등록',
              onTap: widget.onAddNew,
              excludeSemantics: true,
              child: Pressable(
                onPress: widget.onAddNew,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Space.hit),
                  // 회색 글자(갈색은 주요 단추 · 고른 것에만, 2026-11-20 사용자 '갈색 말고 그냥 회색으로')
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.m), child: Text('+ 새 책 등록', style: AppType.row.copyWith(color: AppColors.inkSoft))),
                ),
              ),
            ),
          // '모든 책'은 책이 아니라 조건이라 하나 고르기 줄(표지 자리 없이)
          if (widget.all && m == null) FilterOption(label: '모든 책', sub: widget.allSub, selected: _on(null), onPress: () => _choose(null)),
          for (final id in list) _book(id),
          // 공통 규칙 11장: 검색 0건은 검색어를 넣은 제목(다시 찾을 칸이 바로 위에 있어 본문 없음)
          if (list.isEmpty && t.isNotEmpty)
            Empty(title: '‘$t’에 맞는 책이 없어요')
          else if (ids.isEmpty && widget.books == null)
            const Empty(title: '내 책이 없어요', body: '먼저 책을 추가해 주세요.'),
        ]);
    final search = ids.length > _searchFrom;
    // 제목 아래 첫 칸은 늘 Space.s 아래에서 시작한다(검색칸이든 '책 없이 읽기'든 같게, 2026-11-21 사용자 '책 고르기랑 간격이 여기서도 원래 그런가':
    // 검색칸이 없는 책 적은 시트에서만 4 · 있으면 8이었다), 위 칸들 사이도 Space.s
    return Column(mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (search)
        Padding(
          padding: const EdgeInsets.only(top: Space.s, bottom: Space.s),
          child: Focus(
            onFocusChange: (f) => setState(() => _searchFocus = f),
            child: SearchField(value: _q, onChange: (v) => setState(() => _q = v), placeholder: '제목, 저자', label: '책 찾기'),
          ),
        ),
      // '책 없이 읽기'는 목록 위 폭 가득 보조 단추(2026-11-20 사용자 '좌우 꽉 차는 버튼 넣고 거기에다가 책 없이 읽기').
      // 여러 권 고르기도 같은 단추(2026-11-21 사용자 '책 없이 읽기 내가 좌우 꽉 찬 버튼으로 만들라 했던 것 같은데': 여기만 줄이었다):
      // 누르면 고르고 다시 누르면 뺀다, 고르면 앞에 체크. 이미 목록에 있으면 꺼 둔다
      if (widget.allowNone)
        Padding(
          padding: EdgeInsets.only(top: search ? 0 : Space.s, bottom: Space.s),
          child: Btn(
            label: m != null && noneFixed ? '${NoBookCover.name} · 목록에 있어요' : NoBookCover.name,
            kind: 'secondary',
            size: 'large',
            disabled: m != null && noneFixed,
            icon: m != null && _on(null) && !noneFixed ? const LucideIcon('Check', size: IconSize.small, color: AppColors.accent) : null,
            onPress: () => _choose(null),
          ),
        ),
      // 줄 사이 선 없이
      if (tall) Expanded(child: listView) else Flexible(child: listView),
      // 한 권 고르기는 줄을 누르면 닫힌다. 시트에 '닫기' 단추를 두지 않는다(밖 누르기 · 내려 닫기, 공통 규칙 7장)
      if (m != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Btn(label: _picked.isEmpty ? '완료' : '완료 (${_picked.length})', size: 'xlarge', onPress: () => widget.onDone?.call(List.of(_picked))),
        ),
    ]);
  }
}
