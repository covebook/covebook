// 책 목록 파일 가져오기(2026-11-15 사용자 'CSV·엑셀 가져오기 다 넣어', 페르소나 QA 장서가 F2 '엑셀·북적북적에서 옮겨 오기'):
// 파일 고르기 → 줄마다 검색(ISBN이 있으면 그 판, 없으면 제목·저자) → 확인 목록(찾은 책·이미 있는 책·못 찾은 책) → 한 번에 추가.
// 못 찾은 줄은 목록에 남겨 알려 주고, 누르면 그 검색어로 책 추가를 연다(넣고 오면 '추가한 책'으로). 읽기 상태 열이 있으면 그대로 옮긴다
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/book_list_import.dart';
import '../../domain/library.dart' show ReadStatus, authorLine;
import '../../services/book_search.dart';
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/draft_guard.dart';
import '../../ui/feedback.dart' show errorText;
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'add_book_screen.dart' show openAddBook;
import 'book_match.dart';
import 'book_widgets.dart';
import 'labels.dart' show statusLabel;
import 'bulk_add.dart';

Future<void> openImportList(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book/import'), builder: (_) => const ImportListScreen()));

/// 한 번에 몇 권씩 찾을지(서버에 한꺼번에 몰리지 않게)
const _parallel = 3;
const _files = MethodChannel('app.covebook/files');

class _Line {
  _Line(this.row);
  final ImportRow row;
  BookCandidate? book;
  String? ownedId;
  bool searched = false, picked = false, added = false;

  /// 검색이 실패한 까닭: network(인터넷 없음) · error(검색 오류). '다시 찾기'로 다시 찾는다
  String? fail;
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

  /// 찾아 본 줄 수(다시 찾는 줄은 찾기 전으로 돌려 세므로 전체를 넘지 않는다)
  int get _searched => _lines.where((l) => l.searched).length;

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
              _ => 'CSV, 엑셀(.xlsx) 파일만 읽을 수 있어요.',
            });
        return;
      }
      setState(() {
        _file = f.name;
        _parse = p;
        _lines = [for (final r in p.rows) _Line(r)];
      });
      await _searchAll();
    } catch (_) {
      if (mounted) setState(() => _error = '파일을 열지 못했어요. 다른 파일로 다시 골라 주세요.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// 줄마다 찾는다(한 번에 세 줄씩). 아직 안 찾은 줄과 검색이 실패한 줄을 찾는다. '그만 찾기'면 남은 줄은 찾지 않은 줄로 둔다
  Future<void> _searchAll() async {
    final todo = [for (final l in _lines) if (!l.searched || l.fail != null) l];
    setState(() {
      _searching = true;
      _stop = false;
      // 다시 찾는 줄은 찾기 전으로(진행 수가 전체를 넘지 않게: 2026-11-19 '10권 중 12권'이 될 수 있었다)
      for (final l in todo) {
        l.searched = false;
        l.fail = null;
      }
    });
    var next = 0;
    Future<void> worker() async {
      while (mounted && !_stop && next < todo.length) {
        final l = todo[next++];
        final r = await searchBooks(l.row.query);
        if (!mounted) return;
        final c = r.ok ? matchCandidate(l.row, r.items) : null;
        setState(() {
          l.searched = true;
          // 검색이 실패하면(인터넷 없음 · 서버 오류) 다시 찾을 줄로 둔다(2026-11-19 공통 규칙: 서버 오류는 그냥 '찾지 못한 책'이었다)
          l.fail = r.ok ? null : (r.reason == 'network' ? 'network' : 'error');
          l.book = c;
          l.ownedId = c == null ? null : ownedBookId(LibraryModel.instance.lib, c);
          l.picked = c != null && l.ownedId == null;
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

  /// 못 찾은 줄: 그 이름(없으면 ISBN)으로 책 추가를 열어 다시 찾거나 직접 등록한다. 넣었으면 '추가한 책'으로 옮긴다
  /// (2026-11-19 공통 규칙: 넣고 돌아와도 '찾지 못한 책'에 남았고, 추가 결과에서 '책장에서 보기'를 누르면 목록이 묻지 않고 사라졌다)
  Future<void> _addMissing(_Line l) async {
    final r = l.row;
    final id = await openAddBook(context, q: r.title.isNotEmpty ? [r.title, r.author].where((x) => x.isNotEmpty).join(' ') : r.query, fromList: true);
    if (id == null || !mounted) return;
    setState(() {
      l.added = true;
      l.fail = null;
    });
  }

  /// 나갈 때 물을지: 넣을 수 있는 책이나 아직 찾을 줄이 남았으면
  bool get _dirty => !_saving && _lines.any((l) => !l.added && (!l.searched || l.fail != null || (l.book != null && l.ownedId == null)));

  @override
  Widget build(BuildContext context) {
    final parse = _parse;
    if (parse == null) return _intro();
    final found = [for (final l in _lines) if (l.book != null && l.ownedId == null && !l.added) l];
    final owned = [for (final l in _lines) if (l.book != null && l.ownedId != null && !l.added) l];
    final added = [for (final l in _lines) if (l.added) l];
    final missing = [for (final l in _lines) if (l.searched && l.book == null && !l.added) l];
    final waiting = _lines.where((l) => !l.searched).length;
    final n = found.where((l) => l.picked).length;
    final failed = _lines.where((l) => l.fail != null && !l.added);
    // 찾은 책이 있으면 나갈 때 묻는다(docs/design/DESIGN.md 12장, 2026-11-19 공통 규칙: 묻지 않고 버렸다)
    return DraftGuard(
      dirty: () => _dirty,
      title: '찾은 책을 버릴까요?',
      keep: '계속 가져오기',
      child: Screen(
        title: '책 목록 가져오기',
        // 화면 아래 주요 단추 l. 단추 글자는 하는 일 이름, 꺼진 이유는 단추 위 안내 글(DESIGN 5-2 · 9장)
        footer: _searching
            ? Btn(label: '그만 찾기', kind: 'secondary', size: 'l', onPress: () => setState(() => _stop = true))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (n == 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: NoticeText(found.isEmpty ? '추가할 수 있는 책이 없어요.' : '추가할 책을 골라 주세요.', center: true),
                  ),
                Btn(label: n == 0 ? '추가' : '$n권 추가', size: 'l', disabled: n == 0, busy: _saving, onPress: _addAll),
              ]),
        children: [
          Text(_file ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: MetaText(
              [
                '${_lines.length}권',
                if (parse.columns.isNotEmpty) '열: ${parse.columns.values.join(metaSep)}',
                if (parse.duplicates > 0) '같은 ISBN ${parse.duplicates}줄은 한 번만',
              ].join(metaSep),
              style: AppType.caption,
            ),
          ),
          if (_searching || waiting > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // 진행 숫자는 폭 고정(여러 권 추가 진행 창과 같게)
                Text(_searching ? '${_lines.length}권 중 $_searched권 찾았어요' : '$waiting권은 찾지 않았어요', style: AppType.sub.tnum),
                const SizedBox(height: Space.s),
                ProgressBar(value: _lines.isEmpty ? 0 : _searched / _lines.length),
                if (!_searching && waiting > 0) Padding(padding: const EdgeInsets.only(top: Space.s), child: Btn(label: '이어서 찾기', kind: 'secondary', size: 's', onPress: _searchAll)),
              ]),
            ),
          // 검색이 실패한 줄: 오류 글(화면 읽기가 바로 읽는다) + 다시 찾기. 찾지 않은 줄이 있으면 '이어서 찾기'가 함께 찾는다(단추 하나만)
          if (failed.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                NoticeText(failed.any((l) => l.fail == 'network') ? '인터넷에 연결되지 않아 찾지 못한 책이 있어요.' : '검색에 잠시 문제가 있어 찾지 못한 책이 있어요.', error: true),
                if (waiting == 0) Padding(padding: const EdgeInsets.only(top: Space.s), child: Btn(label: '다시 찾기', kind: 'secondary', size: 's', onPress: _searchAll)),
              ]),
            ),
          if (found.isNotEmpty) ...[
            _Head(
              title: '찾은 책',
              count: '${found.length}권',
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
            _Head(title: '이미 내 책에 있는 책', count: '${owned.length}권', note: '중복으로 넣지 않아요'),
            for (final l in owned) _LineRow(l: l),
          ],
          if (missing.isNotEmpty) ...[
            _Head(title: '찾지 못한 책', count: '${missing.length}권', note: '누르면 그 이름으로 찾아요'),
            for (final l in missing) _LineRow(l: l, onTap: () => _addMissing(l)),
          ],
          if (added.isNotEmpty) ...[
            _Head(title: '추가한 책', count: '${added.length}권'),
            for (final l in added) _LineRow(l: l),
          ],
        ],
      ),
    );
  }

  // 예시 파일: 열 이름이 있는 CSV(UTF-8 BOM이라 엑셀에서도 한글이 안 깨진다). 안드로이드 10+는 다운로드/책장한켠에, 아니면 공유로
  Future<void> _sample() async {
    const name = '책장한켠 예시.csv';
    const csv = '\uFEFF제목,저자,ISBN,읽기 상태\r\n소년이 온다,한강,9788936434120,읽은 책\r\n데미안,헤르만 헤세,,읽는 중\r\n모순,양귀자,,읽고 싶은\r\n';
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsString(csv);
      if (await _files.invokeMethod<bool>('canSaveDownload').catchError((_) => false) == true) {
        await _files.invokeMethod<String>('saveDownload', {'path': f.path, 'name': name, 'mime': 'text/csv'});
        f.delete().ignore();
        if (mounted) appAlert(context, '예시 파일을 저장했어요', '다운로드 › 책장한켠 폴더의 ‘$name’을 엑셀에서 열어 내 책으로 고친 뒤 여기서 골라 주세요.');
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], title: name));
      }
    } catch (e) {
      // 실패 본문은 errorText(DESIGN 9장 '실패 알림')
      if (mounted) appAlert(context, '예시 파일을 저장하지 못했어요', errorText(e));
    }
  }

  // 2026-11-17 사용자 시안: 큰 두 줄 제목 · 한 줄 설명 · 파일 고르기 · 예시 파일 · 펼치는 두 줄(지원하는 파일과 항목 / 가져오기 전 확인)
  Widget _intro() => Screen(
        title: '책 목록 가져오기',
        children: [
          const SizedBox(height: Space.s),
          // 밀어 넣은 화면 본문 맨 위 큰 안내 제목(DESIGN 2-2 introTitle, 탭 첫 화면 제목 역할을 빌려 쓰고 있었다)
          Semantics(header: true, child: Text('다른 곳의 책 목록을\n한 번에 가져오세요', style: AppType.introTitle)),
          const SizedBox(height: Space.m),
          WordText('엑셀이나 CSV 파일을 선택해 주세요.', style: AppType.body.copyWith(color: AppColors.inkSoft)),
          const SizedBox(height: Space.xl),
          Btn(label: '파일 고르기', busy: _reading, onPress: _pick),
          const SizedBox(height: Space.s),
          // 글자만 단추는 밑줄 없는 TextLink(2026-11-19 공통 규칙). 다른 곳으로 가는 보조라 회색
          TextLink(label: '예시 파일 내려받기', soft: true, onPress: _sample),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.xs), child: NoticeText(_error!, error: true)),
          const SizedBox(height: Space.xl),
          const _Fold(title: '지원하는 파일과 항목', lines: [
            '엑셀 파일(.xlsx)은 그대로, CSV는 ‘CSV UTF-8’로 저장한 파일을 골라 주세요.',
            '첫 줄에 ‘제목’, ‘저자’, ‘ISBN’ 같은 열 이름이 있으면 더 정확하게 찾아요. 다른 독서 앱에서 내보낸 파일도 열 이름이 있으면 그대로 읽어요.',
            '‘읽기 상태’ 열(읽은 책, 읽는 중, 읽고 싶은)이 있으면 상태도 옮겨요.',
          ]),
          const _Fold(title: '가져오기 전 확인해 주세요', last: true, lines: [
            'ISBN이 있으면 그 판으로, 없으면 제목과 저자로 찾아요.',
            '찾은 책은 넣기 전에 한 번 더 확인해요. 이미 내 책에 있는 책은 중복으로 넣지 않아요.',
            '읽기 상태가 없으면 ‘읽기 전’으로 넣어요.',
          ]),
          const SizedBox(height: Space.m),
          Text('XLSX, CSV 파일 지원', style: AppType.caption),
        ],
      );
}

/// 안내 접는 줄 하나(책 확인 '추가 정보'와 같은 FoldRow, 2026-11-19 공통 규칙). 펼치면 점 붙은 안내 글
class _Fold extends StatefulWidget {
  const _Fold({required this.title, required this.lines, this.last = false});
  final String title;
  final List<String> lines;
  final bool last;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => FoldRow(
        title: widget.title,
        open: _open,
        last: widget.last,
        onToggle: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final t in widget.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 10, right: Space.s), child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.inkSoft, shape: BoxShape.circle))),
                  Expanded(child: WordText(t, style: AppType.sub)),
                ]),
              ),
          ]),
        ),
      );
}

/// 결과 묶음 머리: 공용 구역 머리(제목 19 · 개수 · 아래 설명 · 오른쪽 글자 단추, 2026-11-19 공통 규칙: 설명이 오른쪽 caption이었다)
class _Head extends StatelessWidget {
  const _Head({required this.title, this.count, this.note, this.action, this.onAction});
  final String title;
  final String? count, note, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xl, bottom: Space.xs),
        child: SectionHead(title: title, count: count, note: note, link: action, linkLabel: action, onLink: onAction),
      );
}

/// 가져온 한 줄(공용 책 줄 BookRow 작게, 바코드 찾은 책과 같은 모양): 오른쪽 고르는 원 · 이미 있음(흐린 원) · 추가함(체크) · 못 찾음(꺾쇠, 누르면 책 추가)
class _LineRow extends StatelessWidget {
  const _LineRow({required this.l, this.onTap});
  final _Line l;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = l.book;
    final r = l.row;
    // 못 찾은 줄은 파일의 제목 · 저자를 책 줄 제목 · 저자 자리에(2026-11-19 공통 규칙: '제목 | 저자'를 제목 한 줄로 그렸다)
    final title = b?.title ?? (r.title.isNotEmpty ? r.title : (r.isbn != null ? 'ISBN ${r.isbn}' : '(제목 없음)'));
    final meta = b != null ? (b.authors.isEmpty ? null : authorLine(b.authors)) : (r.author.isEmpty ? null : r.author);
    final sub = b == null
        ? (l.fail == 'network'
            ? '인터넷에 연결되지 않았어요'
            : l.fail != null
                ? '검색하지 못했어요'
                : ['${r.line}번째 줄', if (r.isbn != null && r.title.isNotEmpty) 'ISBN ${r.isbn}'].join(metaSep))
        : [?publisherLine(b), if (r.status != null) statusLabel[r.status]!].join(metaSep);
    final selectable = b != null && l.ownedId == null && !l.added;
    return BookRow(
      cover: RealCover(uri: b?.coverUrl, title: b?.title ?? r.title, width: BookRow.coverWidth(BookRowSize.small), ratio: 0.72),
      title: title,
      meta: meta,
      third: sub,
      trailing: selectable
          ? RadioMark(on: l.picked)
          : l.added
              ? const AddedMark()
              : b == null
                  ? const Chevron()
                  : const RadioMark(on: false, dim: true),
      onPress: onTap,
      // 여러 권 고르기 줄은 화면 읽기 '선택됨/선택 안 됨'(DESIGN 13장)
      checked: selectable ? l.picked : null,
      // 화면 읽기에는 세로줄 대신 쉼표(DESIGN 15장)
      label: [title, ?meta, if (sub.isNotEmpty) sub.split(metaSep).join(', ')].join(', '),
    );
  }
}
