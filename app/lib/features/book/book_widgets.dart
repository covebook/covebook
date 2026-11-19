// 책 화면들(책 추가 · 내 책 · 책 정보 · 바코드 · 목록 가져오기 · 책 정보 수정)이 같이 쓰는 값과 작은 부품.
// 2026-11-19 공통 규칙: 화면마다 따로 있던 읽기 상태 차례 · 숫자 칸 읽기 · ISBN 정리 · 대체 표지색 · 표지 단추 · 접는 줄을 하나로
library;

import 'package:flutter/material.dart';

import '../../services/photos.dart';
import '../../store/library_model.dart';
import '../../store/library_store.dart' show archivedYears;
import '../../store/placement_store.dart';
import '../../ui/alert.dart';
import '../../ui/book_visual.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'all_books.dart' show deleteNote, deleteSummary, hiddenWhere;

/// 칸에 적은 숫자(쪽수 · 판형 mm): 숫자만 읽어 반올림. 0 이하이거나 못 읽으면 null
int? numOf(String v) {
  final n = double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), ''));
  return n != null && n.isFinite && n > 0 ? n.round() : null;
}

/// ISBN 정리: 숫자와 X만 남긴다
String cleanIsbn(String? v) => (v ?? '').replaceAll(RegExp(r'[^\dXx]'), '');

/// 표지 사진 고르기(책 확인 · 책 정보 수정이 같은 이름 · 모양: 줄 안 작은 보조 단추). 표지가 있으면 '표지 바꾸기', 없으면 '표지 사진 등록'
class CoverPhotoButton extends StatelessWidget {
  const CoverPhotoButton({super.key, required this.hasCover, required this.onPicked, required this.onDenied, this.onError});
  final bool hasCover;
  final ValueChanged<String> onPicked;

  /// 사진 보관함 권한이 없을 때(안내 글을 넘긴다)
  final ValueChanged<String> onDenied;

  /// 사진을 읽지 못했을 때(실패 문장을 넘긴다). 없으면 확인창으로 알린다(2026-11-19 공통 규칙: 실패는 늘 알린다. 말없이 넘어갔다)
  final ValueChanged<String>? onError;

  @override
  Widget build(BuildContext context) => Btn(
        label: hasCover ? '표지 바꾸기' : '표지 사진 등록',
        kind: 'secondary',
        size: 's',
        onPress: () async {
          final r = await pickPhoto('library');
          if (!context.mounted) return;
          if (r case PhotoOk(:final uri)) {
            onPicked(uri);
          } else if (r case PhotoFail(reason: 'denied')) {
            onDenied(deniedMessage('library'));
          } else if (r case PhotoFail(reason: 'error', :final message)) {
            final m = message ?? '사진을 불러오지 못했어요. 다른 사진으로 다시 시도해 주세요.';
            if (onError != null) {
              onError!(m);
            } else {
              appAlert(context, '사진을 불러오지 못했어요', '다른 사진으로 다시 시도해 주세요.');
            }
          }
        },
      );
}

/// 책 삭제 · 숨기기 결과: 지운 책, 숨긴 책(연도 책장에 있어 지우지 않고 숨긴다, 2026-11-06 사용자 '삭제 말고 숨기기로')
typedef BookRemoval = ({List<String> deleted, List<String> hidden});

/// 책 삭제 · 숨기기 확인(내 책 › 선택 여러 권 · 책 정보 › 더 보기 한 권이 같은 시트, 2026-11-19 공통 규칙: 두 벌이 글자 · 제목이 달랐다).
/// 표지(세 권까지)와 한 권이면 제목, 무엇이 지워지고 남는지, 위 [삭제] 아래 '취소'(2026-11-16 QA 현우 F5). 고르면 무엇을 지우고 숨길지, 취소면 null
Future<BookRemoval?> confirmRemoveBooks(BuildContext context, List<String> ids) async {
  if (ids.isEmpty) return null;
  final lib = LibraryModel.instance.lib;
  final yearsOf = await archivedYears(ids);
  if (!context.mounted) return null;
  final hidden = [for (final id in ids) if (yearsOf[id]?.isNotEmpty ?? false) id];
  final deleted = [for (final id in ids) if (!hidden.contains(id)) id];
  final hideOnly = deleted.isEmpty;
  final years = {for (final id in hidden) ...yearsOf[id]!}.toList()..sort();
  final yearText = '${years.join(', ')}년 책장';
  String titleOf(String id) => lib.editions[lib.books[id]?.editionId]?.title ?? '제목 없음';
  final one = ids.length == 1;
  final what = one ? '이 책을' : '${ids.length}권을';
  final shown = ids.take(3).toList();
  final ok = await showSheet<bool>(
    context,
    title: hideOnly ? '$what 숨길까요?' : '$what 삭제할까요?',
    description: hideOnly ? '지금 책장과 책 목록에서 빠지고, $yearText에는 그대로 남아요.' : null,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: Space.xs, bottom: Space.l),
        child: Column(children: [
          // 여러 권이면 표지 묶음을 제목으로 읽는다(표지만 있어 어떤 책인지 몰랐다). 한 권은 아래 제목을 읽는다
          Semantics(
            label: one ? null : [...shown.map(titleOf), if (ids.length > 3) '외 ${ids.length - 3}권'].join(', '),
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (i, id) in shown.indexed) ...[
                if (i > 0) const SizedBox(width: Space.m),
                SizedBox(width: CoverSize.sheet, child: BookVisual(lib: lib, id: id, width: CoverSize.sheet)),
              ],
              if (ids.length > 3) Padding(padding: const EdgeInsets.only(left: Space.m, bottom: Space.xs), child: Text('외 ${ids.length - 3}권', style: AppType.sub)),
            ]),
          ),
          if (one)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: WordText(titleOf(ids.first), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bookTitle),
            ),
        ]),
      ),
      if (deleted.isNotEmpty) WordText('${hidden.isNotEmpty ? '${deleted.length}권은 ' : ''}${deleteNote(deleteSummary(lib, deleted))}', style: AppType.sub),
      if (hidden.isNotEmpty && !hideOnly) Padding(padding: const EdgeInsets.only(top: Space.xs), child: WordText('${hidden.length}권은 $yearText에 있어서 숨기기만 해요.', style: AppType.sub)),
      if (hidden.isNotEmpty) Padding(padding: EdgeInsets.only(top: hideOnly ? 0 : Space.s), child: WordText(hiddenWhere, style: AppType.sub)),
      const SizedBox(height: Space.l),
      Btn(label: hideOnly ? '숨기기' : '삭제', kind: hideOnly ? 'primary' : 'danger', size: 'l', onPress: () => Navigator.pop(ctx, true)),
      SubAction(label: '취소', onPress: () => Navigator.pop(ctx, false)),
    ]),
  );
  return ok == true ? (deleted: deleted, hidden: hidden) : null;
}

/// 확인한 삭제 · 숨기기를 한다. 지운 책 · 숨긴 책은 책장 배치에서도 빠진다
Future<void> removeBooks(BookRemoval r) async {
  final model = LibraryModel.instance;
  for (final id in r.deleted) {
    await model.deleteBook(id, archived: false);
  }
  for (final id in r.hidden) {
    await model.deleteBook(id, archived: true);
  }
  await PlacementStore.instance.forget([...r.deleted, ...r.hidden]);
}

/// 삭제 · 숨기기 결과 토스트 글(한 권이면 제목으로)
String removedText(BookRemoval r, {String? title}) {
  final d = r.deleted.length, h = r.hidden.length;
  if (title != null && d + h == 1) return h > 0 ? '‘$title’ 책을 숨겼어요.' : '‘$title’ 책을 삭제했어요.';
  return h > 0 && d > 0 ? '$d권을 삭제하고 $h권을 숨겼어요.' : h > 0 ? '$h권을 숨겼어요.' : '$d권을 삭제했어요.';
}

/// 숨긴 책 다시 보이기(내 책 › 숨긴 책 · 숨긴 책의 책 정보 메뉴가 같은 일): 갈피 · 기록과 함께 돌아오고 책장에는 '책장에 없는 책'으로 들어간다
Future<void> unhideBook(String id) async {
  await LibraryModel.instance.unhideBook(id);
  // 책장 쪽 책 목록에 다시 넣고 '책장에 없는 책'으로
  await PlacementStore.instance.reload();
  await PlacementStore.instance.addToDrawer(id);
}

/// 다시 보이기 결과 토스트 글
String unhiddenText(String title) => '‘$title’ 책을 다시 보이게 했어요. 책장에 없는 책에 있어요.';

/// 누르면 펼쳐지는 줄(책 확인 '추가 정보' · 목록 가져오기 안내 두 줄): 위 머리카락 선, 제목(구역 제목 19)과 그 아래 설명 한 줄(sub),
/// 오른쪽 ⌄(펼치면 뒤집힌다). last면 아래에도 선. 2026-11-19 공통 규칙: 두 화면이 글자 · 선 · 높이 · 펼침 표시가 서로 달랐다
class FoldRow extends StatelessWidget {
  const FoldRow({super.key, required this.title, this.note, required this.open, required this.onToggle, required this.child, this.last = false});
  final String title;

  /// 제목 아래 한 줄([metaSep]으로 이을 수 있다)
  final String? note;
  final bool open, last;
  final VoidCallback onToggle;

  /// 펼쳤을 때 보일 내용
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Hairline(),
        Semantics(
          button: true,
          expanded: open,
          label: [title, ?note?.split(metaSep).join(', ')].join(', '),
          excludeSemantics: true,
          onTap: onToggle,
          child: Pressable(
            onPress: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.l),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    WordText(title, style: AppType.section),
                    if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: MetaText(note!, style: AppType.sub)),
                  ]),
                ),
                const SizedBox(width: Space.m),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 160), child: const LucideIcon('ChevronDown', color: AppColors.inkSoft)),
              ]),
            ),
          ),
        ),
        if (open) child,
        if (last) const Hairline(),
      ]);
}
