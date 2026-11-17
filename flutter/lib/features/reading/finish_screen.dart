// 독서 종료 기록(지금 앱 app/reading/finish.tsx): 연결된 책(바꾸거나 연결하기), 실제 독서 시간, 선택 입력(시작 쪽·도달한 쪽·짧은 메모) → 개인 기록 저장 또는 버리기.
// 적는 중인 쪽수·메모는 종료 초안에 함께 저장돼 앱이 꺼져도 이어서 쓴다. 분량은 시작 쪽과 도달한 쪽을 둘 다 알 때만 보인다.
// 저장 후: 읽기 탭으로 돌아가 그 위에 '저장했어요' 시트(이번 기록 요약 → 이어서 할 수 있는 일 → '확인').
// 2026-11-16 사용자 '페이지보다 팝업 느낌이 낫지 않나': 저장 뒤 화면 하나를 통째로 바꾸던 것을 시트로
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_nav.dart';
import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../services/ambient.dart';
import '../../store/finish_reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/book_picker.dart';
import '../stats/stats_widgets.dart' show LinkedCover;

int? _page(String? v) {
  final digits = (v ?? '').replaceAll(RegExp(r'[^\d]'), '');
  final n = int.tryParse(digits);
  return v != null && v.trim().isNotEmpty && n != null && n > 0 ? n : null;
}

String hm(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

const _tabular = [FontFeature.tabularFigures()];

class FinishScreen extends StatefulWidget {
  const FinishScreen({super.key});

  @override
  State<FinishScreen> createState() => _FinishScreenState();
}

class _FinishScreenState extends State<FinishScreen> {
  final _reading = ReadingStore.instance;
  final _lib = LibraryModel.instance;
  late String _startPage, _pages, _memo;
  ({String? bookId, String sessionId})? _saved;

  /// 저장한 초안(저장 뒤 화면이 닫히며 미끄러지는 동안 같은 입력 화면을 그대로 그린다)
  FinishDraft? _savedDraft;
  bool _saving = false;
  bool _leaving = false;
  Timer? _notes;
  String? _lastBook;

  @override
  void initState() {
    super.initState();
    final p = _reading.pending;
    final n = p?.notes;
    _startPage = n?.startPage ?? (p?.startPage != null ? '${p!.startPage}' : '');
    _pages = n?.pages ?? '';
    _memo = n?.memo ?? '';
    _lastBook = p?.myBookId;
    _reading.addListener(_changed);
    _lib.addListener(_changed);
    _lib.load();
  }

  @override
  void dispose() {
    _notes?.cancel();
    _reading.removeListener(_changed);
    _lib.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // 책을 바꾸면 시작 쪽 기본값도 그 책의 지금 쪽으로
    final p = _reading.pending;
    if (p != null && p.myBookId != _lastBook) {
      _lastBook = p.myBookId;
      _startPage = p.startPage != null ? '${p.startPage}' : '';
    }
    setState(() {});
  }

  // 적는 중인 값을 초안에 남긴다(잠깐 멈춘 뒤 한 번)
  void _edited() {
    setState(() {});
    _notes?.cancel();
    _notes = Timer(const Duration(milliseconds: 400), () {
      if (_saved == null) _reading.setPendingNotes(startPage: _startPage, pages: _pages, memo: _memo);
    });
  }

  // 읽기 탭으로: 연달아 눌러도 한 번만, 닫히는 동안 아래 탭 바가 눌리지 않게(2026-11-15 QA 민혁 F6)
  bool _closing = false;
  void _toRead() {
    if (_closing) return;
    _closing = true;
    AppNav.instance.blockTabs();
    Navigator.of(context).popUntil((r) => r.isFirst);
    AppNav.instance.goTab(2);
  }

  /// 적는 중인 값을 바로 초안에 남긴다(나갈 때)
  void _flushNotes() {
    _notes?.cancel();
    if (_saved == null) _reading.setPendingNotes(startPage: _startPage, pages: _pages, memo: _memo);
  }

  // 저장하지 않고 뒤로: 갈피 화면처럼 묻는다. 나가도 기록은 읽기 탭에 남아 나중에 저장·버릴 수 있다(2026-11-15 QA 민혁 F3)
  void _askLeave() => appAlert(context, '저장하지 않고 나갈까요?', '이 기록은 읽기 탭에 남아 있어 나중에 저장하거나 버릴 수 있어요.', [
        const AlertButton('계속 쓰기', style: AlertStyle.cancel),
        AlertButton('나가기', onPress: () {
          if (!mounted) return;
          _flushNotes();
          setState(() => _leaving = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }),
      ]);

  /// 숫자 칸에는 숫자만(붙여 넣은 글자가 섞여 '61rainy…'가 613쪽이 됐다, 2026-11-15 QA 수아 F6)
  static String _digits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

  Future<void> _save(FinishDraft pending, int? sp, int? ep) async {
    // 저장 뒤 화면이 닫히는 동안 다시 눌러도 두 번 저장하지 않는다
    if (_saving || _saved != null) return;
    setState(() => _saving = true);
    try {
      await saveFinishedReading(pending, startPage: pending.myBookId != null ? sp : null, pagesRead: pending.myBookId != null ? ep : null, memo: _memo.trim().isEmpty ? null : _memo.trim());
      Ambient.instance.stop();
      final saved = (bookId: pending.myBookId, sessionId: pending.id);
      _saved = saved;
      _savedDraft = pending;
      if (!mounted) return;
      final nav = Navigator.of(context);
      _toRead();
      // 읽기 탭이 보인 뒤 그 위에 시트(화면은 이미 닫히는 중이라 앱 Navigator의 오버레이로 띄운다)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final o = nav.overlay;
        if (o != null && o.mounted) showSavedSheet(o.context, bookId: saved.bookId, sessionId: saved.sessionId);
      });
    } catch (e) {
      if (mounted) appAlert(context, '저장하지 못했어요', '독서 기록을 유지하고 있어요. 다시 시도해 주세요.\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard(FinishDraft pending) => _saved != null ? null : appAlert(context, '이번 독서 기록을 버릴까요?', '${withJosa(formatDurationPrecise(pending.durationMs), '이', '가')} 저장되지 않아요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('버리기', style: AlertStyle.destructive, onPress: () {
          if (_leaving) return;
          _leaving = true;
          Ambient.instance.stop();
          final nav = Navigator.of(context);
          final reading = _reading;
          _toRead();
          // 화면을 먼저 옮긴 뒤 초안을 지운다
          Future<void>.delayed(const Duration(milliseconds: 500), () => reading.clearPending().catchError((_) {
                if (nav.mounted) appAlert(nav.context, '버리지 못했어요', '독서 기록을 저장소에서 지우지 못했어요. 다음에 다시 열면 다시 물어볼게요.');
              }));
        }),
      ]);

  @override
  Widget build(BuildContext context) {
    final lib = _lib.lib;
    // 저장 뒤 닫히는 동안에는 저장한 초안으로 같은 화면을 그린다(초안은 저장과 함께 비워진다)
    final pending = _reading.pending ?? _savedDraft;
    if (pending == null) {
      return Screen(title: '독서 기록', children: [Empty(title: '끝낸 독서가 없어요', action: '읽기로', onAction: _toRead)]);
    }
    final b = pending.myBookId == null ? null : lib.books[pending.myBookId];
    final e = b == null ? null : lib.editions[b.editionId];
    final sp = _page(_startPage), ep = _page(_pages);
    // 전체 쪽수를 넘는 쪽은 막는다(234쪽 책에 613쪽 → '이번에 588쪽'으로 저장됐다)
    final total = e?.pageCount != null && e!.pageCount! > 0 ? e.pageCount!.toInt() : null;
    final startOver = total != null && sp != null && sp > total;
    final endOver = total != null && ep != null && ep > total;
    final badRange = sp != null && ep != null && ep < sp;
    final amount = sp != null && ep != null && ep >= sp && !endOver && !startOver ? ep - sp : null;
    final hair = 1 / MediaQuery.devicePixelRatioOf(context);
    final screen = Screen(
      title: '독서 끝',
      back: false,
      topBar: true,
      footer: Btn(label: '개인 기록 저장', busy: _saving, disabled: !_lib.loaded || _saving || pending.durationMs < 1000 || badRange || startOver || endOver, onPress: () => _save(pending, sp, ep)),
      children: [
        if (_reading.error != null) Text('독서 기록을 기기에 저장하지 못했어요. 저장을 다시 시도해 주세요.', style: AppType.sub),
        Semantics(
          label: '실제 독서 시간 ${formatDurationPrecise(pending.durationMs)}',
          excludeSemantics: true,
          child: Container(
            margin: const EdgeInsets.only(top: Space.s, bottom: Space.xl),
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: hair))),
            child: Column(children: [
              Text('실제 독서 시간', style: AppType.sub),
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text(pending.durationMs < 60000 ? formatDurationPrecise(pending.durationMs) : formatDuration(pending.durationMs),
                    style: const TextStyle(fontFamily: AppFonts.ui, fontSize: 36, height: 44 / 36, color: AppColors.ink, fontFeatures: _tabular)),
              ),
              Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('${hm(pending.startedAt)} ~ ${hm(pending.endedAt)} · 일시정지 시간 제외', style: AppType.caption)),
            ]),
          ),
        ),
        SelectField(
          label: '연결된 책',
          value: e?.title,
          placeholder: '책 연결하기 (선택)',
          onPress: () async {
            final r = await pickBook(context, lib, allowNone: true);
            if (r.picked) _reading.setPendingBook(r.id, r.id == null ? null : lib.books[r.id]?.currentPage);
          },
        ),
        if (b != null) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Field(
                label: '시작 쪽 (선택)',
                unit: '쪽',
                number: true,
                value: _startPage,
                placeholder: b.currentPage != null && b.currentPage != 0 ? '지난번 ${b.currentPage}' : null,
                error: startOver ? '전체 $total쪽보다 커요' : null,
                onChange: (v) {
                  _startPage = _digits(v);
                  _edited();
                },
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Field(
                label: '도달한 쪽 (선택)',
                unit: '쪽',
                number: true,
                value: _pages,
                error: badRange ? '시작 쪽보다 앞이에요' : endOver ? '전체 $total쪽보다 커요' : null,
                onChange: (v) {
                  _pages = _digits(v);
                  _edited();
                },
              ),
            ),
          ]),
          if (amount != null) Transform.translate(offset: const Offset(0, -Space.s), child: Padding(padding: const EdgeInsets.only(bottom: Space.l - Space.s), child: Text('이번에 $amount쪽 읽었어요.', style: AppType.sub))),
        ],
        Field(
          label: '짧은 메모 (선택)',
          value: _memo,
          placeholder: '나만 보는 메모예요',
          multiline: true,
          minHeight: 80,
          onChange: (v) {
            _memo = v;
            _edited();
          },
        ),
        Padding(padding: const EdgeInsets.only(top: Space.s), child: TextLink(label: '이 기록 버리기', soft: true, onPress: () => _discard(pending))),
      ],
    );
    return PopScope(canPop: _leaving, onPopInvokedWithResult: (didPop, _) => didPop ? null : _askLeave(), child: screen);
  }
}


/// 독서 기록 저장 뒤 시트: 이번 기록(책 · 시간 · 쪽) → 이어서 할 수 있는 일(갈피 남기기 · 책 정보 · 통계) → 확인
/// 저장했어요(2026-11-17 사용자 시안): 가운데 작은 창에 표지 · 제목 · 저자, 'N분 N초 기록했어요', 확인. 뒤는 어둡게, 어디를 눌러도 닫힌다
Future<void> showSavedSheet(BuildContext context, {required String? bookId, required String sessionId}) {
  final lib = LibraryModel.instance.lib;
  final ss = lib.sessions[sessionId];
  final sb = bookId == null ? null : lib.books[bookId];
  final se = sb == null ? null : lib.editions[sb.editionId];
  final author = se != null && se.authors.isNotEmpty ? se.authors.join(', ') : '';
  final done = '${ss == null ? '' : formatDurationPrecise(ss.durationMs)} 기록했어요'.trim();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: const Color(0x8C000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: [se?.title ?? '책 없이 읽은 시간', done].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Material(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(Shape.dialog + 2),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.xl, Space.l + 4, Space.l + 4),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (sb != null && se != null)
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          ExcludeSemantics(child: LinkedCover(lib: lib, id: sb.id, width: 56)),
                          const SizedBox(width: Space.l),
                          Flexible(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(se.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.heading.copyWith(fontSize: 19, height: 26 / 19)),
                              if (author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub)),
                            ]),
                          ),
                        ])
                      else
                        Text('책 없이 읽은 시간', textAlign: TextAlign.center, style: AppType.sub),
                      const SizedBox(height: Space.l + 4),
                      WordText(done, textAlign: TextAlign.center, style: AppType.heading.copyWith(fontSize: 22, height: 30 / 22)),
                      const SizedBox(height: Space.l + 4),
                      Btn(label: '확인', onPress: () => Navigator.pop(ctx)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final t = Curves.easeOutCubic.transform(anim.value);
      return Opacity(opacity: t, child: Transform.scale(scale: 0.96 + 0.04 * t, child: child));
    },
  );
}
