// 책 꾸미기(지금 앱 app/book/[id]/binding.tsx 장정 편집): 책 색·재질·표지 그림·책등 글자 배치와 갈피 색. 겉모습만 바뀌고 독서 기록·배치는 그대로다.
// 저장하면 사용자 장정으로 남아 다시 켜도 유지된다. 장정을 고르지 않았으면 책장에 보이는 모습 그대로 보여 주고, 저장해도 장정은 바꾸지 않는다.
// 2026-11-23 사용자: 화면 이름을 '책 꾸미기'로(책장 '꾸미기'와 구분), 갈피 색 시트를 '갈피' 칸으로 넣고 장정과 함께 '저장'으로만 반영(한 화면에 저장 방식 하나)
library;

import 'package:flutter/material.dart';

import '../../domain/library.dart' show authorLine;
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/alert.dart';
import '../../ui/draft_guard.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import 'binding_editor.dart';

Future<void> openBindingEditor(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book/binding'), builder: (_) => BindingScreen(id: id)));

class BindingScreen extends StatefulWidget {
  const BindingScreen({super.key, required this.id});
  final String id;

  @override
  State<BindingScreen> createState() => _BindingScreenState();
}

class _BindingScreenState extends State<BindingScreen> {
  final _model = LibraryModel.instance;
  late final _book = _model.lib.books[widget.id];
  late final _edition = _book == null ? null : _model.lib.editions[_book.editionId];
  late final _recommended = BindingDraft.recommended(_edition);
  late BindingDraft _v = BindingDraft.saved(_book?.bindingId == null ? null : _model.lib.bindings[_book!.bindingId], _recommended);
  bool _touched = false, _saving = false;

  /// 갈피 색(null = 표지에서 고른 색): 처음 값과 다르면 저장할 것이 있다
  late final String? _ribbon0 = (_book?.ribbonColor?.isEmpty ?? true) ? null : _book!.ribbonColor;
  late String? _ribbon = _ribbon0;
  bool get _ribbonTouched => _ribbon != _ribbon0;

  void _set(BindingDraft next) => setState(() {
        _touched = true;
        _v = next;
      });

  void _reset() => _set(resetBinding(_recommended, _v.seed));

  Future<void> _save() async {
    final nav = Navigator.of(context);
    if (!_touched && !_ribbonTouched) return nav.pop();
    if (_saving) return;
    setState(() => _saving = true);
    // 장정과 갈피 색은 한 번에 저장한다(바꾼 것만). 추천으로 되돌려 재질·표지 그림이 비면 예전 값도 지운다.
    // 실패하면 고른 것은 그대로 두고 확인창으로(말없이 멈췄다)
    try {
      if (_ribbonTouched) {
        await _model.setBookLook(widget.id, binding: _touched ? _v : null, ribbonColor: _ribbon);
      } else {
        await _model.setBookLook(widget.id, binding: _v);
      }
      await PlacementStore.instance.reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      appAlert(context, '책 꾸미기를 저장하지 못했어요', '고른 장정과 갈피 색은 그대로 있어요. ${errorText(e)}');
      return;
    }
    // 저장했으니 나가기 확인(DraftGuard)을 거치지 않고 닫는다
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = _edition;
    if (_book == null || e == null) {
      return Screen(title: '책 꾸미기', children: [
        Empty(title: '책을 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop()),
      ]);
    }
    // 고른 장정이 있으면 나갈 때 묻는다(공용 DraftGuard.edit, 2026-11-19 공통 규칙: 말없이 버려졌다)
    return DraftGuard.edit(
      dirty: () => (_touched || _ribbonTouched) && !_saving,
      child: Screen(
        title: '책 꾸미기',
        // 머리줄 글자 단추는 공용 TextLink(회색 보조, 누르는 자리 48, 2026-11-19 공통 규칙). 화면 읽기 이름은 '추천 장정으로 초기화' 그대로
        right: Semantics(
          button: true,
          label: '추천 장정으로 초기화',
          excludeSemantics: true,
          onTap: _reset,
          child: TextLink(label: '초기화', soft: true, onPress: _reset),
        ),
        // 화면 아래 주요 단추 xlarge, 이름 '○○ 저장'(docs/design/DESIGN.md 5장)
        // 장정과 갈피 색을 함께 저장하니 '꾸미기 저장'(장정 저장이었다)
        footer: Btn(label: '꾸미기 저장', size: 'xlarge', onPress: _save, busy: _saving),
        children: [
          BindingEditor(
            title: e.title,
            author: authorLine(e.authors),
            size: e.widthMm != null && e.heightMm != null ? (widthMm: e.widthMm!, heightMm: e.heightMm!) : null,
            pages: e.pageCount,
            value: _v,
            recommended: _recommended,
            current: _touched ? null : PlacementStore.instance.books[widget.id],
            realCover: e.coverUri,
            onChange: _set,
            bookId: widget.id,
            ribbon: _ribbon,
            marks: _model.lib.bookmarks.values.where((m) => m.myBookId == widget.id).length,
            onRibbon: (c) => setState(() => _ribbon = c),
          ),
        ],
      ),
    );
  }
}
