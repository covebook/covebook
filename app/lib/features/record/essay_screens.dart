// 긴 감상(2026-11-16 기록 > 감상): 목록 줄 · 읽기 화면 · 쓰기/수정 화면.
// 별점·한 줄 감상(책 정보 평가)·갈피 메모·독서 메모와 따로 저장한다(서재 essays). 책 정보 '평가'에서도 같은 감상을 그 책만 골라 본다.
// 읽기 화면은 본문이 주인공: 입력 칸 테두리·키보드·저장 단추 없이 글만 보이고, 수정은 머리줄 단추로 따로 연다.
// 2026-11-19 공통 규칙: 같은 동작은 갈피와 같은 이름('수정' · '삭제'), 책 줄은 BookRow, ' | '는 MetaText
library;

import 'package:flutter/material.dart';

import '../../domain/library.dart';
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/labels.dart';
import '../bookmark/book_picker.dart' show pickBook;
import '../bookmark/form_parts.dart';
import '../stats/stats_widgets.dart' show LinkedCover;

/// 감상 읽기 화면 열기
Future<void> openEssay(BuildContext context, String id) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/essay'), builder: (_) => EssayScreen(id: id)));

/// 감상 쓰기(책을 정해 두면 그 책으로). 저장하면 그 감상 읽기 화면으로 바뀐다
Future<void> openNewEssay(BuildContext context, {String? book}) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/essay/new'), builder: (_) => EssayEditScreen(book: book)));

/// 감상 수정
Future<void> openEditEssay(BuildContext context, String id) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/essay/edit'), builder: (_) => EssayEditScreen(id: id)));

/// 감상 날짜 줄: 쓴 날(고쳤으면 고친 날도). 목록은 짧게, 읽기 화면은 길게
String essayDateLine(Essay e, {bool long = false}) {
  final f = long ? dateLong : dateShort;
  final made = f(e.createdAt), changed = f(e.updatedAt);
  return changed.isNotEmpty && changed != made ? '$made$metaSep$changed 고침' : made;
}

/// 감상 목록 한 줄(표지 · 책 제목 · 지은이 · 감상 제목 · 미리보기 · 쓴 날). 상자 없이 줄로 나눈다
class EssayRow extends StatelessWidget {
  const EssayRow({super.key, required this.lib, required this.essay, this.showBook = true, this.onOpen, this.compact = false});
  final Library lib;
  final Essay essay;

  /// 책 정보 › 평가의 짧은 줄: 제목 · 쓴 날 · 미리보기 한 줄 · 오른쪽 꺾쇠(2026-11-17 사용자 시안)
  final bool compact;

  /// 책 정보 화면 안에서는 책이 정해져 있어 표지·제목을 빼고 감상만
  final bool showBook;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final b = lib.books[essay.myBookId];
    final e = b == null ? null : lib.editions[b.editionId];
    final head = essayHeadline(essay);
    final preview = essayPreview(essay);
    return Semantics(
      button: true,
      label: [if (showBook && e != null) e.title, head, dateShort(essay.createdAt)].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onPress: onOpen ?? () => openEssay(context, essay.id),
        child: compact
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.m),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // 구역 제목 '감상'(19)과 같은 크기로 보여 구분이 안 됐다(2026-11-18 사용자): 한 단계 작게
                      _headline(head, lines: 1, style: AppType.labelStrong),
                      Padding(padding: const EdgeInsets.only(top: 2), child: _date()),
                      if (preview.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub.copyWith(color: AppColors.ink))),
                    ]),
                  ),
                  const SizedBox(width: Space.s),
                  // 공통 규칙: 줄 끝 꺾쇠는 Chevron(옅은 회색이었다)
                  const Chevron(),
                ]),
              )
            : showBook && b != null && e != null
                ? _withCover(b.id, e.title, head, preview)
                : Padding(padding: const EdgeInsets.symmetric(vertical: Space.l), child: _text(head, preview)),
      ),
    );
  }

  Widget _headline(String head, {int lines = 2, TextStyle? style}) => Text(head.isEmpty ? '(빈 감상)' : head,
      maxLines: lines, overflow: TextOverflow.ellipsis, style: style ?? AppType.rowStrong);

  /// 쓴 날(고쳤으면 고친 날도). 공통 규칙: ' | '는 MetaText, 감상 날짜는 목록·읽기 모두 caption(2026-11-19. 목록 micro였다)
  Widget _date() => MetaText(essayDateLine(essay), maxLines: 1, style: AppType.caption);

  /// 책 정보 화면 안(표지 없이): 감상 제목 · 미리보기 · 쓴 날
  Widget _text(String head, String preview) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _headline(head),
        if (preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.sub.copyWith(color: AppColors.ink)),
          ),
        Padding(padding: const EdgeInsets.only(top: Space.s), child: _date()),
      ]);

  /// 기록 탭 목록: 표지 · 감상 제목 · '책 제목 | 쓴 날' · 미리보기 두 줄(세 줄 묶음 높이가 표지 높이와 맞는다).
  /// 2026-11-16 사용자 '책 크기랑 옆에 글 내용이랑 맞춰야'. 2026-11-19 공통 규칙: 책 줄은 BookRow(감상 목록은 보통 64, 표지 80이었다)
  Widget _withCover(String bookId, String title, String head, String preview) => BookRow(
        size: BookRowSize.medium,
        cover: IgnorePointer(child: LinkedCover(lib: lib, id: bookId, width: BookRow.coverWidth(BookRowSize.medium))),
        title: head.isEmpty ? '(빈 감상)' : head,
        titleLines: 1,
        meta: [title, essayDateLine(essay)].join(metaSep),
        third: preview,
      );
}

/// 감상 읽기: 책 줄 · 제목 · 날짜 · 본문. 수정·삭제는 머리줄에서
class EssayScreen extends StatefulWidget {
  const EssayScreen({super.key, required this.id});
  final String id;

  @override
  State<EssayScreen> createState() => _EssayScreenState();
}

class _EssayScreenState extends State<EssayScreen> {
  final _model = LibraryModel.instance;

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // 공통 규칙: 갈피와 같은 말('삭제', 2026-11-19. '지우기'였다)
  Future<void> _delete() => appAlert(context, '이 감상을 삭제할까요?', '되돌릴 수 없어요. 별점, 한줄평, 갈피는 그대로 남아요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('삭제', style: AlertStyle.destructive, onPress: () async {
          final nav = Navigator.of(context);
          await _model.deleteEssay(widget.id);
          if (nav.canPop()) nav.pop();
        }),
      ]);

  // 더 보기 메뉴: 갈피 더 보기와 같은 묶음 · 같은 이름('수정' · '삭제')
  void _menu() => showSheet<void>(
        context,
        builder: (ctx) => ListGroup(children: [
          ListItem(
            label: '수정',
            onPress: () {
              Navigator.pop(ctx);
              openEditEssay(context, widget.id);
            },
          ),
          ListItem(
            label: '삭제',
            danger: true,
            onPress: () {
              Navigator.pop(ctx);
              _delete();
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lib = _model.lib;
    final essay = lib.essays[widget.id];
    // 다른 곳에서 지웠으면 빈 화면(뒤로 가면 된다)
    if (essay == null) return const Screen(children: [Empty(title: '지운 감상이에요')]);
    final b = lib.books[essay.myBookId];
    final e = b == null ? null : lib.editions[b.editionId];
    final title = essay.title?.trim() ?? '';
    return Screen(
      // 공통 규칙: 머리줄 아이콘은 HeadIcon, 사이 headIconGap(2026-11-19. 사이가 0이었다)
      right: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(label: '감상 수정', onPress: () => openEditEssay(context, widget.id), child: const HeadIcon('PenLine')),
        const SizedBox(width: headIconGap),
        IconBtn(label: '더 보기', onPress: _menu, child: const HeadIcon('MoreHorizontal')),
      ]),
      children: [
        // 공통 규칙: 책 줄은 BookRow small(2026-11-19. 제목 16 · 저자 caption이었다)
        if (b != null && e != null)
          BookRow(
            cover: IgnorePointer(child: LinkedCover(lib: lib, id: b.id, width: BookRow.coverWidth(BookRowSize.small))),
            title: e.title,
            meta: authorLine(e.authors),
          ),
        Padding(
          padding: const EdgeInsets.only(top: Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title.isNotEmpty) Semantics(header: true, child: Text(title, style: AppType.title)),
            Padding(padding: EdgeInsets.only(top: title.isNotEmpty ? Space.s : 0), child: MetaText(essayDateLine(essay, long: true), style: AppType.caption)),
          ]),
        ),
        // 본문: 읽는 글꼴로 넉넉한 줄 간격. 고를 수 있게만(입력 칸이 아니다)
        Padding(
          padding: const EdgeInsets.only(top: Space.xl, bottom: Space.xxl),
          child: SelectableText(essay.body, style: AppType.reading),
        ),
      ],
    );
  }
}

/// 감상 쓰기·수정: 책(새로 쓸 때만 고른다) · 제목(선택) · 본문
class EssayEditScreen extends StatefulWidget {
  const EssayEditScreen({super.key, this.id, this.book});

  /// 수정할 감상(없으면 새로 쓴다)
  final String? id;

  /// 새로 쓸 때 정해 둔 책
  final String? book;

  @override
  State<EssayEditScreen> createState() => _EssayEditScreenState();
}

class _EssayEditScreenState extends State<EssayEditScreen> {
  final _model = LibraryModel.instance;
  late final Essay? _old = widget.id == null ? null : _model.lib.essays[widget.id];
  late String? _bookId = _old?.myBookId ?? (widget.book != null && _model.lib.books[widget.book] != null ? widget.book : null);
  late String _title = _old?.title ?? '';
  late String _body = _old?.body ?? '';
  bool _saving = false;
  String? _error;

  bool get _canSave => _bookId != null && _body.trim().isNotEmpty && !_saving;
  bool get _dirty => _old == null ? (_title.trim().isNotEmpty || _body.trim().isNotEmpty) : (_title.trim() != (_old.title ?? '') || _body != _old.body);

  Future<void> _save() async {
    final book = _bookId;
    if (!_canSave || book == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final old = _old;
      if (old != null) {
        await _model.updateEssay(old.id, title: _title, body: _body);
        if (mounted) Navigator.of(context).pop();
      } else {
        final id = await _model.addEssay(myBookId: book, title: _title, body: _body);
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(settings: const RouteSettings(name: '/essay'), builder: (_) => EssayScreen(id: id)));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '감상을 저장하지 못했어요. 쓴 글은 그대로 있어요. ($e)');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = _model.lib;
    final b = _bookId == null ? null : lib.books[_bookId];
    final e = b == null ? null : lib.editions[b.editionId];
    // 쓰던 글 지킴: 갈피 남기기 · 갈피 수정과 같은 부품(form_parts). 저장 뒤 닫기는 pop이라 묻지 않는다
    return DraftGuard(
      dirty: () => _dirty,
      title: '쓰던 감상을 버릴까요?',
      child: Screen(
        title: _old == null ? '감상 쓰기' : '감상 수정',
        footer: Btn(label: '감상 저장', size: 'l', onPress: _save, busy: _saving, disabled: !_canSave),
        children: [
          const SizedBox(height: Space.m),
          SelectField(
            label: '책',
            value: e?.title,
            sub: e != null && e.authors.isNotEmpty ? authorLine(e.authors) : null,
            placeholder: '책을 골라 주세요',
            // 쓴 감상의 책은 바꾸지 않는다(다른 책 감상이면 새로 쓴다)
            disabled: _old != null,
            onPress: () async {
              final r = await pickBook(context, lib, addNew: true);
              if (r.picked && r.id != null && mounted) setState(() => _bookId = r.id);
            },
          ),
          Field(label: '제목 (선택)', value: _title, onChange: (t) => setState(() => _title = t), placeholder: '없으면 첫 문장이 제목처럼 보여요'),
          Field(
            label: '감상',
            value: _body,
            onChange: (t) => setState(() => _body = t),
            placeholder: '이 책을 읽고 남기고 싶은 생각을 적어 보세요',
            multiline: true,
            minHeight: 280,
          ),
          if (_error != null) NoticeText(_error!, error: true),
        ],
      ),
    );
  }
}
