// 독서 종료 기록(지금 앱 app/reading/finish.tsx): 연결된 책(바꾸거나 연결하기), 독서 시간, 선택 입력(시작 쪽·도달한 쪽·짧은 메모) → 개인 기록 저장 또는 버리기.
// 적는 중인 쪽수·메모는 종료 초안에 함께 저장돼 앱이 꺼져도 이어서 쓴다. 분량은 시작 쪽과 도달한 쪽을 둘 다 알 때만 보인다.
// 저장 후: 읽기 탭으로 돌아가 그 위에 '저장했어요' 창(이번 기록의 책 · 'N분 기록했어요' → '확인').
// 2026-11-16 사용자 '페이지보다 팝업 느낌이 낫지 않나': 저장 뒤 화면 하나를 통째로 바꾸던 것을 가운데 창으로.
// 독서 끝 화면은 여는 곳이 여럿이라(읽기 탭 · 장면 · 책 정보 · 복구 창) 여는 길은 openFinish 하나로 둔다
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;

import '../../app/app_nav.dart';
import '../../domain/library.dart';
import '../../domain/reading.dart';
import '../../services/ambient.dart';
import '../../store/finish_reading.dart';
import '../../store/library_model.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/book_picker.dart';
import '../stats/chart_data.dart' show hasPause, timeRange;
import '../stats/stats_widgets.dart' show LinkedCover, bookAuthor;

int? _page(String? v) {
  final digits = (v ?? '').replaceAll(RegExp(r'[^\d]'), '');
  final n = int.tryParse(digits);
  return v != null && v.trim().isNotEmpty && n != null && n > 0 ? n : null;
}

/// 일시정지가 있었는지: 통계 기록 줄과 같은 판정(hasPause, 시작~끝이 독서 시간보다 1분 넘게 길면)
bool _paused(FinishDraft d) => hasPause(Session(id: d.id, startedAt: d.startedAt, endedAt: d.endedAt, durationMs: d.durationMs, createdAt: d.endedAt, updatedAt: d.endedAt));

/// 독서 끝 화면 경로. 이름 '/reading/finish'는 작은 타이머가 숨는 데 쓴다(mini_timer miniTimerHidden)
Route<void> finishRoute() => MaterialPageRoute<void>(settings: const RouteSettings(name: '/reading/finish'), builder: (_) => const FinishScreen());

/// 독서 끝 화면 열기(같은 경로를 여덟 곳에서 따로 만들었다, 2026-11-19). root: 앱 맨 위 내비게이터, replace: 지금 화면(읽기 장면)과 바꿔서
Future<void> openFinish(BuildContext context, {bool root = false, bool replace = false}) async {
  final nav = Navigator.of(context, rootNavigator: root);
  await (replace ? nav.pushReplacement<void, void>(finishRoute()) : nav.push<void>(finishRoute()));
}

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

  /// 저장 실패 안내(쓰던 칸이 있는 화면이라 확인창 대신 저장 단추 위 글, DESIGN 11장)
  String? _saveError;

  /// 쪽 칸 줄(저장을 눌렀을 때 칸 오류가 있으면 이 줄을 보인다)
  final _pagesKey = GlobalKey();
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
    AppNav.instance.goTab(AppTab.read);
  }

  /// 적는 중인 값을 바로 초안에 남긴다(나갈 때)
  void _flushNotes() {
    _notes?.cancel();
    if (_saved == null) _reading.setPendingNotes(startPage: _startPage, pages: _pages, memo: _memo);
  }

  // 저장하지 않고 뒤로: 갈피 화면처럼 묻는다. 나가도 기록은 읽기 탭에 남아 나중에 저장·버릴 수 있다(2026-11-15 QA 민혁 F3)
  // 단추는 다른 나가기 확인과 같은 '취소' · '확인'(2026-11-20 사용자 '취소 확인으로 테마색으로')
  void _askLeave() => appAlert(context, '저장하지 않고 나갈까요?', '이 기록은 읽기 탭에 남아 있어 나중에 저장하거나 버릴 수 있어요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('확인', onPress: () {
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
    // 적던 메모를 늦게 넣는 타이머가 저장 뒤에 초안을 되살리지 않게(점검 B10)
    _notes?.cancel();
    // 저장 뒤 화면이 닫히는 동안 다시 눌러도 두 번 저장하지 않는다
    if (_saving || _saved != null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
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
        if (o != null && o.mounted) showSavedDialog(o.context, bookId: saved.bookId, sessionId: saved.sessionId);
      });
    } catch (e) {
      // 예외 원문은 화면에 보이지 않는다(errorText가 로그로)
      if (mounted) setState(() => _saveError = '독서 기록을 저장하지 못했어요. 적은 내용은 그대로 있어요. ${errorText(e)}');
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
          // 화면을 먼저 옮긴 뒤 초안을 버린다. 보던 기록이 사라지는 일이라 읽기 탭에서 토스트로 알린다(DESIGN 10 · 14장)
          Future<void>.delayed(const Duration(milliseconds: 500), () => reading.clearPending().then((_) {
                if (nav.mounted) showToast(nav.context, '독서 기록을 버렸어요.');
              }, onError: (Object e) {
                if (nav.mounted) appAlert(nav.context, '버리지 못했어요', '독서 기록이 아직 읽기 탭에 남아 있어요. ${errorText(e)}');
              }));
        }),
      ]);

  /// 칸 오류가 있을 때 저장을 누르면: 저장하지 않고 쪽 칸을 보이고 오류를 읽어 준다(DESIGN 12장: 단추는 누를 수 있게 두고 첫 오류 칸을 보인다)
  void _showError(String message) {
    final c = _pagesKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignmentPolicy: ScrollPositionAlignmentPolicy.explicit, alignment: 0.2);
    SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final lib = _lib.lib;
    // 저장 뒤 닫히는 동안에는 저장한 초안으로 같은 화면을 그린다(초안은 저장과 함께 비워진다)
    final pending = _reading.pending ?? _savedDraft;
    if (pending == null) {
      // 제목은 이 화면 이름 그대로(독서 기록 화면과 헷갈렸다)
      return Screen(title: '독서 끝', children: [Empty(title: '끝낸 독서가 없어요', action: '읽기로', onAction: _toRead)]);
    }
    final b = pending.myBookId == null ? null : lib.books[pending.myBookId];
    final e = b == null ? null : lib.editions[b.editionId];
    final author = bookAuthor(lib, pending.myBookId);
    final sp = _page(_startPage), ep = _page(_pages);
    // 전체 쪽수를 넘는 쪽은 막는다(234쪽 책에 613쪽 → '이번에 588쪽'으로 저장됐다)
    final total = e?.pageCount != null && e!.pageCount! > 0 ? e.pageCount!.toInt() : null;
    final startOver = total != null && sp != null && sp > total;
    final endOver = total != null && ep != null && ep > total;
    final badRange = sp != null && ep != null && ep < sp;
    final amount = sp != null && ep != null && ep >= sp && !endOver && !startOver ? ep - sp : null;
    // 칸 오류(칸 아래 빨간 한 마디와 같은 말): 저장을 누르면 이것을 보인다
    final fieldError = startOver ? '전체 $total쪽보다 커요' : badRange ? '시작 쪽보다 앞이에요' : endOver ? '전체 $total쪽보다 커요' : null;
    // 1초가 안 되는 기록은 저장할 것이 없다: 단추를 끄고 이유는 단추 바로 위 글로(DESIGN 9장)
    final tooShort = pending.durationMs < 1000;
    // 시각 범위 옆 '일시정지 시간 제외'는 일시정지가 있었을 때만(DESIGN 9장, 통계와 같은 판정)
    final range = [timeRange(pending.startedAt, pending.endedAt), if (_paused(pending)) '일시정지 시간 제외'].join(metaSep);
    final screen = Screen(
      title: '독서 끝',
      back: false,
      topBar: true,
      // 화면 아래 주요 단추는 xlarge(2026-11-19 공통 규칙). 안내 · 저장 실패 글은 단추 바로 위
      footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (tooShort) const NoticeText('1초가 안 되는 기록은 저장할 수 없어요. 이 기록은 버려 주세요.'),
        if (_saveError != null) NoticeText(_saveError!, error: true),
        if (tooShort || _saveError != null) const SizedBox(height: Space.m),
        Btn(
          label: '개인 기록 저장',
          size: 'xlarge',
          busy: _saving,
          disabled: !_lib.loaded || tooShort,
          onPress: () => fieldError != null ? _showError(fieldError) : _save(pending, sp, ep),
        ),
        // 버리기는 저장 단추 바로 아래 보조 행동(큰 단추 아래 SubAction, 2026-11-21 사용자 '이 기록 버리기 간격이 이게 맞나':
        // 메모 칸 아래에 따로 떠 있어 위아래 간격이 어디에도 맞지 않았다)
        SubAction(label: '이 기록 버리기', onPress: () => _discard(pending)),
      ]),
      children: [
        // 기기 저장 실패 안내는 앱 공통 안내 · 오류 글
        if (_reading.error != null) const NoticeText('독서 기록을 기기에 저장하지 못했어요. 저장을 다시 시도해 주세요.', error: true),
        Semantics(
          label: '독서 시간 ${formatDurationPrecise(pending.durationMs)}, ${range.split(metaSep).join(', ')}',
          excludeSemantics: true,
          child: Container(
            margin: const EdgeInsets.only(top: Space.s, bottom: Space.xl),
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: Hairline.of(context)))),
            child: Column(children: [
              // '실제 독서'는 쓰지 않는 말(DESIGN 9장): 일시정지를 뺀 것은 아래 줄 '일시정지 시간 제외'가 알린다
              Text('독서 시간', style: AppType.sub),
              Padding(padding: const EdgeInsets.only(top: Space.s), child: Text(formatDurationShort(pending.durationMs), style: AppType.clock)),
              // 시각 범위는 통계와 같은 '오후 9:05-9:30'(24시간 ' ~ '이었다), 정보 사이는 옅은 세로줄(MetaText)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: MetaText(range, style: AppType.caption),
              ),
            ]),
          ),
        ),
        // 연결된 책 칸은 갈피·감상의 책 칸과 같게 저자를 아래 줄에(2026-11-19 공통 규칙)
        SelectField(
          label: '연결된 책',
          value: e?.title,
          sub: author.isEmpty ? null : author,
          placeholder: '책 연결하기 (선택)',
          onPress: () async {
            // 지금 연결된 책(없으면 책 없이 읽기)은 고르는 원으로 보인다(DESIGN 13장 current)
            final r = await pickBook(context, lib, allowNone: true, addNew: true, current: (id: b?.id));
            if (r.picked) _reading.setPendingBook(r.id, r.id == null ? null : lib.books[r.id]?.currentPage);
          },
        ),
        if (b != null) ...[
          Row(key: _pagesKey, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ],
    );
    return PopScope(canPop: _leaving, onPopInvokedWithResult: (didPop, _) => didPop ? null : _askLeave(), child: screen);
  }
}

/// 저장했어요(2026-11-17 사용자 시안): 가운데 작은 창에 표지 · 제목 · 저자, 'N분 N초 기록했어요', 확인. 뒤는 어둡게, 어디를 눌러도 닫힌다.
/// 창 모양(덮개 · 모서리 · 폭 · 나타나기)은 사용자 시안이라 확인창(appAlert)과 따로 둔다(DESIGN 16장)
Future<void> showSavedDialog(BuildContext context, {required String? bookId, required String sessionId}) {
  final lib = LibraryModel.instance.lib;
  final ss = lib.sessions[sessionId];
  final sb = bookId == null ? null : lib.books[bookId];
  final se = sb == null ? null : lib.editions[sb.editionId];
  // 책 없이 읽은 기록은 앱 어디서나 같은 이름 '책 없이 읽기'와 회색 표지 칸(DESIGN 3-1, 책 줄과 같게)
  final linked = sb != null && se != null ? sb.id : null;
  final title = se != null && sb != null ? se.title : NoBookCover.name;
  final author = se != null ? authorLine(se.authors) : '';
  final done = '${ss == null ? '' : formatDurationPrecise(ss.durationMs)} 기록했어요'.trim();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: const Color(0x8C000000),
    transitionDuration: const Duration(milliseconds: 180),
    // 경로 이름표는 안쪽 글·단추를 따로 둔다(explicitChildNodes가 없으면 화면 읽기를 켤 때 단언에 걸렸다)
    pageBuilder: (ctx, _, _) => Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: [title, done].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: ConstrainedBox(
                // 화면 폭의 약 8할(시안 308)
                constraints: const BoxConstraints(maxWidth: 308),
                child: Material(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(Shape.dialog + 2),
                  // 왼쪽 정렬로 낮게: 왼쪽 표지, 오른쪽에 제목 · 저자 · 'N분 기록했어요', 아래 확인(2026-11-18 사용자 '세로로 너무 길고 왼쪽 정렬이 나을 듯')
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      // 표지 52 → 72(2026-11-18 사용자 '썸네일 좀 더 크게'). 제목 · 저자는 표지 위 끝, 'N분 기록했어요'는 표지 아래 끝에 맞춘다
                      // (2026-11-19 사용자 '11초 위치가 좀 애매': 가운데 묶음 끝에 떠 있었다)
                      IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: ExcludeSemantics(child: linked != null ? LinkedCover(lib: lib, id: linked, width: CoverSize.saved) : const NoBookCover(width: CoverSize.saved)),
                          ),
                          const SizedBox(width: Space.m + 2),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bookSavedTitle),
                              if (linked != null && author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookAuthor)),
                              const Spacer(),
                              const SizedBox(height: Space.s),
                              WordText(done, style: AppType.rowStrong),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: Space.l),
                      // 가운데 작은 창 안 단추는 확인창과 같은 large(TDS ConfirmDialog 단추 기본값)
                      Btn(label: '확인', size: 'large', onPress: () => Navigator.pop(ctx)),
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
