// 책장에 꽂기 시트(2026-11-24 사용자 시안: 홈 머리 '+'를 누르면 아래에서 올라온다).
// 내 책 표지를 옆으로 넘겨 보고, 표지를 위로 끌어 책장 원하는 자리에 꽂는다(놓을 자리 계산 · 미리 보기는 책장 끌기와 같다).
// 책장에 없는 책이 앞, 이미 책장에 있는 책은 맨 끝(오른쪽)이고 표지 오른쪽 아래에 책장 표시(하단 '책장' 탭 그림). 책장에 있는 책은 끌지 않는다.
// 오른쪽 위 '목록 보기'는 예전 '+'가 열던 책 추가 화면. 끄는 동안 시트는 숨어 책장이 다 보인다(끄는 손가락은 계속 이 시트가 받는다).
// 닫기: 손잡이를 누르거나 아래로 밀기, 기기 뒤로
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/library.dart';
import '../../ui/book_cover.dart' show bookTitle;
import '../../ui/book_visual.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/tab_icons.dart' show shelfIcon;
import '../../ui/theme.dart';

/// 시트에 보이는 책 한 권(책장에 있는지)
typedef PlaceItem = ({String id, bool onShelf});

/// 책장에 없는 책이 앞, 책장에 있는 책은 끝(각각 최근에 넣은 책부터). [placedNow]는 이 시트를 연 동안 꽂은 책(꽂은 차례):
/// 책장에 있으면 맨 오른쪽 끝으로 간다(2026-11-24 사용자 '넣은 책은 맨 우측으로 가서 우측 하단에 책장 표시')
List<PlaceItem> placeItems(Library lib, Iterable<String> ids, bool Function(String id) onShelf, {List<String> placedNow = const []}) {
  int newer(String a, String b) => (lib.books[b]?.createdAt ?? '').compareTo(lib.books[a]?.createdAt ?? '');
  final all = ids.toSet();
  final just = [for (final id in placedNow) if (all.contains(id) && onShelf(id)) id];
  final off = [for (final id in all) if (!onShelf(id)) id]..sort(newer);
  final on = [for (final id in all) if (onShelf(id) && !just.contains(id)) id]..sort(newer);
  return [for (final id in off) (id: id, onShelf: false), for (final id in [...on, ...just]) (id: id, onShelf: true)];
}

class PlaceSheet extends StatefulWidget {
  const PlaceSheet({
    super.key,
    required this.lib,
    required this.items,
    required this.hidden,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onList,
    required this.onClose,
  });
  final Library lib;
  final List<PlaceItem> items;

  /// 끄는 동안 숨는다(손가락은 계속 받는다)
  final bool hidden;

  /// 표지를 들었다: 책, 손가락 자리(화면 좌표), 표지 그림(끄는 동안 손가락을 따라간다)과 크기
  final void Function(String id, Offset global, ui.Image image, Size size) onDragStart;
  final ValueChanged<Offset> onDragMove;
  final VoidCallback onDragEnd, onDragCancel, onList, onClose;

  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  final _covers = <String, GlobalKey>{};

  /// 이 손가락이 표지를 들었는지(들기 전 취소는 알리지 않는다)
  bool _lifted = false;

  void _start(String id, Offset global) {
    final box = _covers[id]?.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || _lifted) return;
    final image = box.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    _lifted = true;
    widget.onDragStart(id, global, image, box.size);
  }

  void _move(Offset global) {
    if (_lifted) widget.onDragMove(global);
  }

  void _end() {
    if (!_lifted) return;
    _lifted = false;
    widget.onDragEnd();
  }

  void _cancel() {
    if (!_lifted) return;
    _lifted = false;
    widget.onDragCancel();
  }

  Widget _item(PlaceItem it) {
    final lib = widget.lib;
    final title = bookTitle(lib, it.id) ?? '';
    final key = _covers.putIfAbsent(it.id, GlobalKey.new);
    final cover = Stack(clipBehavior: Clip.none, children: [
      // 모두 같은 크기 틀(가장 큰 책에 맞춰 아래로 정렬하면 작은 책 위가 크게 비었다)
      RepaintBoundary(key: key, child: BookVisual(lib: lib, id: it.id, width: CoverSize.place, uniform: true)),
      // 이미 책장에 있는 책: 표지 오른쪽 아래 책장 표시. 작은 흰 원 안 회색 선 그림(표지를 가리지 않게 작고 옅게).
      // 2026-11-24 내 책 격자와 같은 흰 원 30 배지로 바꿨다가 사용자 '전이 낫다'로 되돌림(내 책 격자는 그 배지 그대로)
      if (it.onShelf)
        Positioned(
          right: -Space.xs,
          bottom: -Space.xs,
          child: Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle, boxShadow: [Shape.floatShadow]),
            child: shelfIcon(AppColors.icon, size: IconSize.small),
          ),
        ),
    ]);
    final body = SizedBox(
      width: CoverSize.place,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        cover,
        const SizedBox(height: Space.s),
        Text(keepAll(title), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.bookGridTitle),
      ]),
    );
    if (it.onShelf) {
      return Semantics(container: true, label: '$title, 책장에 있어요', excludeSemantics: true, child: body);
    }
    // 위아래로 끌거나 꾹 눌러 들면 책장으로(옆으로 밀면 목록이 넘어간다)
    return Semantics(
      container: true,
      label: '$title, 위로 끌어 책장에 꽂기',
      excludeSemantics: true,
      child: GestureDetector(
        onVerticalDragStart: (d) => _start(it.id, d.globalPosition),
        onVerticalDragUpdate: (d) => _move(d.globalPosition),
        onVerticalDragEnd: (_) => _end(),
        onVerticalDragCancel: _cancel,
        onLongPressStart: (d) => _start(it.id, d.globalPosition),
        onLongPressMoveUpdate: (d) => _move(d.globalPosition),
        onLongPressEnd: (_) => _end(),
        onLongPressCancel: _cancel,
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final items = widget.items;
    return IgnorePointer(
      ignoring: widget.hidden,
      child: AnimatedOpacity(
        opacity: widget.hidden ? 0 : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet)),
            boxShadow: [BoxShadow(color: Color(0x1A6F5843), blurRadius: 16, offset: Offset(0, -2))],
          ),
          padding: EdgeInsets.only(bottom: pad.bottom + Space.l),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // 손잡이: 누르거나 아래로 밀면 닫는다
            Semantics(
              button: true,
              label: '책장에 꽂기 닫기',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 0) widget.onClose();
                },
                child: SizedBox(
                  height: Space.l + Space.s,
                  child: Center(
                    child: Container(width: 38, height: 4.5, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3))),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: Row(children: [
                Expanded(child: Semantics(header: true, child: Text('책장에 꽂기', style: AppType.heading))),
                TextLink(label: '목록 보기', soft: true, onPress: widget.onList),
              ]),
            ),
            const SizedBox(height: Space.l),
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(horizontal: Space.page), child: EmptyLine('아직 내 책이 없어요'))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.page),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final (i, it) in items.indexed) ...[
                    if (i > 0) const SizedBox(width: Space.l),
                    _item(it),
                  ],
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
