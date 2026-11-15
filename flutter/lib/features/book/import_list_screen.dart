// 책 목록 파일 가져오기(2026-11-15 사용자 'CSV·엑셀 가져오기 다 넣어', 페르소나 QA 장서가 F2 '엑셀·북적북적에서 옮겨 오기'):
// 파일 고르기 → 줄마다 검색(ISBN이 있으면 그 판, 없으면 제목·저자) → 확인 목록(찾은 책·이미 있는 책·못 찾은 책) → 한 번에 추가.
// 못 찾은 줄은 목록에 남겨 알려 주고, 누르면 그 검색어로 책 추가를 연다. 읽기 상태 열이 있으면 그대로 옮긴다
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/book_list_import.dart';
import '../../domain/library.dart' show ReadStatus;
import '../../services/book_search.dart';
import '../../store/library_model.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/book_picker.dart' show statusLabel;
import 'add_book_screen.dart' show openAddBook;
import 'barcode_scan_screen.dart' show PickMark;
import 'book_match.dart';
import 'bulk_add.dart';

Future<void> openImportList(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book/import'), builder: (_) => const ImportListScreen()));

/// 한 번에 몇 권씩 찾을지(서버에 한꺼번에 몰리지 않게)
const _parallel = 3;

class _Line {
  _Line(this.row);
  final ImportRow row;
  BookCandidate? book;
  String? ownedId;
  bool searched = false, offline = false, picked = false, added = false;
}

class ImportListScreen extends StatefulWidget {
  const ImportListScreen({super.key});

  @override
  State<ImportListScreen> createState() => _ImportListScreenState();
}

class _ImportListScreenState extends State<ImportListScreen> {
  String? _file, _error;
  ImportParse? _parse;
  List<_Line> _lines = const [];
  bool _reading = false, _searching = false, _stop = false, _saving = false;
  int _searched = 0;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _reading = true;
    });
    try {
      // 확장자 거르기는 기기마다 CSV·엑셀 형식을 다르게 알아 파일이 흐리게 막히기도 해서 모든 파일을 보이고 고른 뒤 확인한다
      final f = await FilePicker.pickFile(type: FileType.any, dialogTitle: '책 목록 파일 고르기');
      if (f == null || !mounted) return;
      final bytes = await f.xFile.readAsBytes();
      final p = parseBookList(bytes, f.name);
      if (!mounted) return;
      if (p.error != null) {
        setState(() => _error = switch (p.error) {
              'encoding' => '파일의 글자를 읽지 못했어요. 엑셀에서 ‘CSV UTF-8’로 저장하거나 엑셀 파일(.xlsx)을 그대로 골라 주세요.',
              'empty' => '가져올 책이 없어요. 제목이나 ISBN 열에 값이 있는지 확인해 주세요.',
              _ => 'CSV·엑셀(.xlsx) 파일만 읽을 수 있어요.',
            });
        return;
      }
      setState(() {
        _file = f.name;
        _parse = p;
        _lines = [for (final r in p.rows) _Line(r)];
        _searched = 0;
      });
      await _searchAll();
    } catch (_) {
      if (mounted) setState(() => _error = '파일을 열지 못했어요. 다른 파일로 다시 골라 주세요.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// 줄마다 찾는다(한 번에 세 줄씩). '그만 찾기'면 남은 줄은 못 찾은 줄로 둔다
  Future<void> _searchAll() async {
    setState(() {
      _searching = true;
      _stop = false;
    });
    final todo = [for (final l in _lines) if (!l.searched || l.offline) l];
    var next = 0;
    Future<void> worker() async {
      while (mounted && !_stop && next < todo.length) {
        final l = todo[next++];
        final r = await searchBooks(l.row.query);
        if (!mounted) return;
        final c = r.ok ? matchCandidate(l.row, r.items) : null;
        setState(() {
          l.searched = true;
          l.offline = !r.ok && r.reason == 'network';
          l.book = c;
          l.ownedId = c == null ? null : ownedBookId(LibraryModel.instance.lib, c);
          l.picked = c != null && l.ownedId == null;
          _searched++;
        });
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _addAll() async {
    final picks = [
      for (final l in _lines)
        if (l.picked && l.book != null && !l.added) (book: l.book!, status: l.row.status ?? ReadStatus.want),
    ];
    if (picks.isEmpty || _saving) return;
    setState(() => _saving = true);
    final r = await addBooks(context, picks);
    if (!mounted) return;
    final failed = r.failed.toSet();
    setState(() {
      _saving = false;
      for (final l in _lines) {
        if (l.picked && l.book != null && !failed.contains(l.book!.title)) {
          l.added = true;
          l.picked = false;
        }
      }
    });
    final next = await showBulkDone(context, r);
    if (mounted) goAfterBulk(context, next);
  }

  @override
  Widget build(BuildContext context) {
    final parse = _parse;
    if (parse == null) return _intro();
    final found = [for (final l in _lines) if (l.book != null && l.ownedId == null && !l.added) l];
    final owned = [for (final l in _lines) if (l.book != null && l.ownedId != null && !l.added) l];
    final added = [for (final l in _lines) if (l.added) l];
    final missing = [for (final l in _lines) if (l.searched && l.book == null) l];
    final waiting = _lines.where((l) => !l.searched).length;
    final n = found.where((l) => l.picked).length;
    final offline = _lines.any((l) => l.offline);
    return PopScope(
      canPop: !_saving,
      child: Screen(
        title: '책 목록 가져오기',
        footer: _searching
            ? Btn(label: '그만 찾기', kind: 'secondary', onPress: () => setState(() => _stop = true))
            : Btn(label: n == 0 ? '추가할 책을 고르세요' : '$n권 추가', disabled: n == 0, busy: _saving, onPress: _addAll),
        children: [
          Text(_file ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [
                '${_lines.length}권',
                if (parse.columns.isNotEmpty) '열: ${parse.columns.values.join(' · ')}',
                if (parse.duplicates > 0) '같은 ISBN ${parse.duplicates}줄은 한 번만',
              ].join(' · '),
              style: AppType.caption,
            ),
          ),
          if (_searching || waiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_searching ? '${_lines.length}권 중 $_searched권 찾았어요' : '$waiting권은 찾지 않았어요', style: AppType.sub),
                const SizedBox(height: Space.s),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: _lines.isEmpty ? 0 : _searched / _lines.length, minHeight: 6, color: AppColors.accent, backgroundColor: AppColors.surface),
                ),
                if (!_searching && waiting > 0) Padding(padding: const EdgeInsets.only(top: Space.s), child: Btn(label: '이어서 찾기', kind: 'secondary', size: 's', onPress: _searchAll)),
              ]),
            ),
          if (offline && !_searching)
            Padding(
              padding: const EdgeInsets.only(top: Space.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('인터넷에 연결되지 않아 찾지 못한 책이 있어요.', style: AppType.sub.copyWith(color: AppColors.danger)),
                const SizedBox(height: Space.s),
                Btn(label: '다시 찾기', kind: 'secondary', size: 's', onPress: _searchAll),
              ]),
            ),
          if (found.isNotEmpty) ...[
            _Head(
              title: '찾은 책 ${found.length}권',
              action: found.every((l) => l.picked) ? '모두 빼기' : '모두 고르기',
              onAction: () => setState(() {
                final all = found.every((l) => l.picked);
                for (final l in found) {
                  l.picked = !all;
                }
              }),
            ),
            for (final l in found) _LineRow(l: l, onTap: () => setState(() => l.picked = !l.picked)),
          ],
          if (owned.isNotEmpty) ...[
            _Head(title: '이미 서재에 있는 책 ${owned.length}권', note: '중복으로 넣지 않아요'),
            for (final l in owned) _LineRow(l: l),
          ],
          if (missing.isNotEmpty) ...[
            _Head(title: '찾지 못한 책 ${missing.length}권', note: '누르면 그 이름으로 찾아요'),
            for (final l in missing) _LineRow(l: l, onTap: l.offline ? null : () => openAddBook(context, q: l.row.title.isNotEmpty ? [l.row.title, l.row.author].where((x) => x.isNotEmpty).join(' ') : l.row.query)),
          ],
          if (added.isNotEmpty) ...[
            _Head(title: '추가한 책 ${added.length}권'),
            for (final l in added) _LineRow(l: l),
          ],
        ],
      ),
    );
  }

  Widget _intro() => Screen(
        title: '책 목록 가져오기',
        footer: Btn(label: '파일 고르기', busy: _reading, onPress: _pick),
        children: [
          Text('엑셀이나 CSV로 정리해 둔 책 목록을 한 번에 넣어요.', style: AppType.body),
          const SizedBox(height: Space.l),
          for (final t in const [
            '첫 줄에 ‘제목’, ‘저자’, ‘ISBN’ 같은 열 이름이 있으면 더 정확하게 찾아요. 다른 독서 앱에서 내보낸 파일도 열 이름이 있으면 그대로 읽어요.',
            'ISBN이 있으면 그 판으로, 없으면 제목과 저자로 찾아요. 찾은 책은 넣기 전에 한 번 더 확인해요.',
            '‘읽기 상태’ 열(읽은 책·읽는 중·읽고 싶은)이 있으면 상태도 옮겨요.',
            '엑셀 파일(.xlsx)은 그대로, CSV는 ‘CSV UTF-8’로 저장한 파일을 골라 주세요.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 9, right: Space.s), child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.inkSoft, shape: BoxShape.circle))),
                Expanded(child: Text(t, style: AppType.sub)),
              ]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.l),
              child: Semantics(liveRegion: true, child: Text(_error!, style: AppType.sub.copyWith(color: AppColors.danger))),
            ),
        ],
      );
}

class _Head extends StatelessWidget {
  const _Head({required this.title, this.note, this.action, this.onAction});
  final String title;
  final String? note, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: AppType.section))),
          if (note != null) Text(note!, style: AppType.caption),
          if (action != null && onAction != null) TextLink(label: action!, soft: true, onPress: onAction!),
        ]),
      );
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.l, this.onTap});
  final _Line l;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = l.book;
    final sub = b == null
        ? (l.offline ? '인터넷 연결 없음' : '${l.row.line}번째 줄${l.row.isbn != null ? ' · ISBN ${l.row.isbn}' : ''}')
        : [?publisherLine(b), if (l.row.status != null) statusLabel[l.row.status]!].join(' · ');
    final selectable = b != null && l.ownedId == null && !l.added;
    return Semantics(
      button: onTap != null,
      selected: selectable && l.picked,
      label: [b?.title ?? l.row.label, if (sub.isNotEmpty) sub].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onPress: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Row(children: [
            RealCover(uri: b?.coverUrl, title: b?.title ?? l.row.title, color: '#F2F4F6', width: 40, ratio: 0.72),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b?.title ?? (l.row.label.isEmpty ? '(제목 없음)' : l.row.label), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
                if (b != null && b.authors.isNotEmpty) Text(b.authors.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption),
              ]),
            ),
            const SizedBox(width: Space.s),
            if (selectable) PickMark(on: l.picked) else if (l.added) const LucideIcon('Check', size: 18, color: AppColors.accent) else if (b == null && !l.offline) const LucideIcon('ChevronRight', size: 18, color: AppColors.inkSoft),
          ]),
        ),
      ),
    );
  }
}
