// 장정 편집(지금 앱 app/book/[id]/binding.tsx): 책 색·재질·표지 그림·책등 글자 배치. 장정만 바뀌고 독서 기록·배치는 그대로다.
// 저장하면 사용자 장정으로 남아 다시 켜도 유지된다. 아무것도 고르지 않았으면 책장에 보이는 모습 그대로 보여 주고, 저장해도 바꾸지 않는다
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

  void _set(BindingDraft next) => setState(() {
        _touched = true;
        _v = next;
      });

  void _reset() => _set(resetBinding(_recommended, _v.seed));

  Future<void> _save() async {
    final nav = Navigator.of(context);
    if (!_touched) return nav.pop();
    if (_saving) return;
    setState(() => _saving = true);
    // 추천으로 되돌려 재질·표지 그림이 비면 예전 값도 지운다. 실패하면 고른 장정은 그대로 두고 확인창으로(말없이 멈췄다)
    try {
      await _model.setBinding(widget.id, _v);
      await PlacementStore.instance.reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      appAlert(context, '장정을 저장하지 못했어요', '고른 장정은 그대로 있어요. ${errorText(e)}');
      return;
    }
    // 저장했으니 나가기 확인(DraftGuard)을 거치지 않고 닫는다
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = _edition;
    if (_book == null || e == null) {
      return Screen(title: '장정 편집', children: [
        Empty(title: '책을 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop()),
      ]);
    }
    // 고른 장정이 있으면 나갈 때 묻는다(공용 DraftGuard.edit, 2026-11-19 공통 규칙: 말없이 버려졌다)
    return DraftGuard.edit(
      dirty: () => _touched && !_saving,
      child: Screen(
        title: '장정 편집',
        // 머리줄 글자 단추는 공용 TextLink(회색 보조, 누르는 자리 48, 2026-11-19 공통 규칙). 화면 읽기 이름은 '추천 장정으로 초기화' 그대로
        right: Semantics(
          button: true,
          label: '추천 장정으로 초기화',
          excludeSemantics: true,
          onTap: _reset,
          child: TextLink(label: '초기화', soft: true, onPress: _reset),
        ),
        // 화면 아래 주요 단추 xlarge, 이름 '○○ 저장'(docs/design/DESIGN.md 5장)
        footer: Btn(label: '장정 저장', size: 'xlarge', onPress: _save, busy: _saving),
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
          ),
        ],
      ),
    );
  }
}
