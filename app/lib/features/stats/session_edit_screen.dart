// 독서 기록 수정(지금 앱 app/session/[id].tsx): 잘못 저장한 시간·날짜·책 연결을 고치거나 삭제한다.
// 고친 칸만 저장한다(domain/session_edit): 메모만 고치면 시작·끝 시각과 초 단위 독서 시간이 그대로 남는다. 고친 칸이 있으면 나가기 전에 묻는다.
// 책과 연결된 기록은 커뮤니티가 열려 있으면 공유할 수 있다(고른 것만 공개)
// 2026-11-19 공통 규칙: 나가기 묻기는 DraftGuard.edit(따로 만든 PopScope였다), 저장 · 삭제는 결과를 기다려 실패를 알린다(기다리지 않고 닫았다),
// 저장 단추 '기록 저장', 쪽 칸 검증 · 메모 칸은 독서 끝과 같게, 삭제 뒤 토스트('삭제했어요.')
// 독서 기록 추가(SessionAddScreen, 2026-11-23 사용자 '타이머를 켜지 않고 읽은 사람도 기록을 쉽게'): 같은 칸으로 새 기록을 쓴다.
// 연결된 책(들어온 곳의 책, 책 없이도) · 날짜(기본 오늘) · 독서 시간(10분 · 30분 · 1시간 빠른 고르기와 직접 입력) · 쪽(선택) · 메모(선택).
// 시작 시각은 묻지 않는다(오늘이면 지금에서 독서 시간을 뺀 때, 지난 날이면 그날 21시, domain/session_edit manualSessionTimes).
// 저장은 타이머 저장과 같은 길(store/finish_reading saveManualReading). 여는 곳: 책 정보 › 내 기록 › 독서 기록 '추가', 통계 캘린더 그날 '독서 기록 추가', 읽기 탭 '오늘 총'
// 저장으로 완독이 되면(적은 쪽이 마지막 쪽) 연 자리로 돌아가 독서 저장과 같은 저장했어요 창 + 별점(2026-11-24 사용자 5단계)
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../domain/library.dart' show ReadStatus, formatDurationPrecise, today;
import '../../domain/reading.dart' show SessionInput;
import '../../domain/session_edit.dart';
import '../../store/finish_reading.dart' show saveManualReading;
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/draft_guard.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../bookmark/book_picker.dart' show pickBook;
import '../community/community_screens.dart' show communityOpen, openCommunityShare;
import '../reading/finish_screen.dart' show showSavedDialog;
import 'chart_data.dart' show hasPause;
import 'stats_widgets.dart' show bookAuthor, bookTitle;

/// 쪽 칸 값(독서 끝과 같은 규칙: 숫자만, 0보다 클 때만)
int? _page(String v) {
  final n = int.tryParse(v.trim());
  return n != null && n > 0 ? n : null;
}

/// 숫자 칸에는 숫자만(독서 끝과 같게: 붙여 넣은 글자가 섞이지 않게)
String _digits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

Future<void> openSessionEdit(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/session'), builder: (_) => SessionEditScreen(id: id)));

class SessionEditScreen extends StatefulWidget {
  const SessionEditScreen({super.key, required this.id});
  final String id;

  @override
  State<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _SessionEditScreenState extends State<SessionEditScreen> {
  final _pagesKey = GlobalKey();

  /// 쪽 칸 오류가 있을 때 저장을 누르면: 저장하지 않고 쪽 칸을 보이고 오류를 읽어 준다(DESIGN 12장)
  void _showPageError() {
    final c = _pagesKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignmentPolicy: ScrollPositionAlignmentPolicy.explicit, alignment: 0.2);
    SemanticsService.sendAnnouncement(View.of(context), '쪽 칸을 확인해 주세요', Directionality.of(context));
  }

  final _model = LibraryModel.instance;
  late final _s = _model.lib.sessions[widget.id];
  late final SessionForm? _initial = _s == null ? null : sessionFormOf(_s);
  late SessionForm _f = _initial ?? (bookId: null, day: '', time: '', minutes: '', startPage: '', pages: '', memo: '');
  bool _saving = false;

  bool get _dirty => _initial != null && _f != _initial;

  void _set({Object? bookId = _keep, String? day, String? time, String? minutes, String? startPage, String? pages, String? memo}) => setState(() => _f = (
        bookId: identical(bookId, _keep) ? _f.bookId : bookId as String?,
        day: day ?? _f.day,
        time: time ?? _f.time,
        minutes: minutes ?? _f.minutes,
        startPage: startPage ?? _f.startPage,
        pages: pages ?? _f.pages,
        memo: memo ?? _f.memo,
      ));

  /// 저장: 고친 칸만 넣고 기기에 저장된 뒤 닫는다(고친 것은 이전 화면에 보인다). 실패하면 화면에 남아 알린다
  Future<void> _save(SessionPatch patch) async {
    if (_saving) return;
    if (patch.isEmpty) return Navigator.of(context).pop();
    setState(() => _saving = true);
    try {
      await _model.updateSession(widget.id, patch);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        appAlert(context, '기록을 저장하지 못했어요', '고친 내용은 그대로 있어요. ${errorText(e)}');
      }
    }
  }

  /// 삭제: 보고 있던 기록이 사라지니 화면을 닫고 토스트. 실패는 확인창(공통 규칙 10 · 14장)
  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final wrote = _model.deleteSession(widget.id);
    nav.pop();
    try {
      await wrote;
      if (nav.mounted) showToast(nav.context, '삭제했어요.');
    } catch (e) {
      if (nav.mounted) appAlert(nav.context, '기록을 삭제하지 못했어요', errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s, initial = _initial;
    if (s == null || initial == null) {
      // 찾을 수 없음 틀(공통 규칙 9장)
      // 제목은 정상 화면과 같게(다른 '찾을 수 없음' 화면처럼, 2026-11-20)
      return Screen(title: '독서 기록 수정', children: [
        Empty(title: '기록을 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop()),
      ]);
    }
    final lib = _model.lib;
    final patch = sessionEditPatch(s, initial, _f);
    final minutesBad = _f.minutes != initial.minutes && !((num.tryParse(_f.minutes) ?? 0) > 0);
    // 쪽 검증은 독서 끝과 같게: 전체 쪽수를 넘거나 도달한 쪽이 시작 쪽보다 앞이면 칸 아래 오류.
    // 저장 단추는 누를 수 있게 두고 누르면 쪽 칸을 보인다(DESIGN 12장, 독서 끝과 같음)
    final e = _f.bookId == null ? null : lib.editions[lib.books[_f.bookId]?.editionId ?? ''];
    final total = e?.pageCount != null && e!.pageCount! > 0 ? e.pageCount!.toInt() : null;
    final sp = _page(_f.startPage), ep = _page(_f.pages);
    final startOver = total != null && sp != null && sp > total;
    final endOver = total != null && ep != null && ep > total;
    final badRange = sp != null && ep != null && ep < sp;
    final pageBad = startOver || endOver || badRange;
    // 고친 것이 있으면 나갈 때 묻는다(공통 규칙 12장 고치는 화면: '수정을 그만할까요?' + 취소 · 확인). 저장 · 삭제 뒤 닫기는 pop이라 묻지 않는다
    return DraftGuard.edit(
      dirty: () => _dirty,
      child: Screen(
        title: '독서 기록 수정',
        // 화면 아래 주요 단추는 xlarge, 이름은 '○○ 저장'(2026-11-19 공통 규칙)
        footer: Btn(
          label: '기록 저장',
          size: 'xlarge',
          busy: _saving,
          disabled: patch == null,
          onPress: () {
            if (pageBad) return _showPageError();
            if (patch != null) _save(patch);
          },
        ),
        children: [
          // 일시정지 시간 제외는 일시정지가 있었던 기록에만(공통 규칙 9장, 늘 '(일시정지 제외)'였다)
          Padding(
            padding: const EdgeInsets.only(top: Space.item, bottom: Space.group),
            child: MetaText(['지금 저장된 독서 시간 ${formatDurationPrecise(s.durationMs)}', if (hasPause(s)) '일시정지 시간 제외'].join(metaSep), style: AppType.sub),
          ),
          // 독서 끝의 '연결된 책' 칸과 같은 칸(저자 아래 줄 · 빈 글, 2026-11-19 공통 규칙)
          SelectField(
            label: '연결된 책',
            value: bookTitle(lib, _f.bookId),
            sub: bookAuthor(lib, _f.bookId).isEmpty ? null : bookAuthor(lib, _f.bookId),
            placeholder: '책 연결하기 (선택)',
            onPress: () async {
              final r = await pickBook(context, lib, allowNone: true, addNew: true, current: (id: _f.bookId));
              if (r.picked) _set(bookId: r.id);
            },
          ),
          // 날짜·시각은 눌러서 고른다
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 13, child: DateField(label: '날짜', value: validDay(_f.day) ? _f.day : '', onChange: (v) => _set(day: v))),
            const SizedBox(width: Space.m),
            Expanded(flex: 10, child: TimeField(label: '시작 시각', value: validTime(_f.time) ? _f.time : '', onChange: (v) => _set(time: v))),
          ]),
          // 단위는 칸 안 오른쪽(쪽 칸과 같게, '독서 시간(분)'이었다)
          Field(
            label: '독서 시간',
            unit: '분',
            value: _f.minutes,
            number: true,
            onChange: (v) => _set(minutes: v),
            hint: _f.minutes == initial.minutes ? '고치지 않으면 저장된 시간(초 단위)이 그대로 남아요.' : null,
            error: minutesBad ? '1분 이상으로 적어 주세요' : null,
          ),
          // 쪽 칸은 독서 끝과 같게: 단위 '쪽', 칸 사이 12, 숫자만, 같은 오류 한 마디
          Row(key: _pagesKey, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Field(
                label: '시작 쪽 (선택)',
                unit: '쪽',
                value: _f.startPage,
                number: true,
                error: startOver ? '전체 $total쪽보다 커요' : null,
                onChange: (v) => _set(startPage: _digits(v)),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Field(
                label: '도달한 쪽 (선택)',
                unit: '쪽',
                value: _f.pages,
                number: true,
                error: badRange ? '시작 쪽보다 앞이에요' : endOver ? '전체 $total쪽보다 커요' : null,
                onChange: (v) => _set(pages: _digits(v)),
              ),
            ),
          ]),
          // 메모 칸은 독서 끝과 같은 칸(같은 값을 적는다: 이름 · 안내 · 여러 줄)
          Field(label: '짧은 메모 (선택)', value: _f.memo, placeholder: '나만 보는 메모예요', multiline: true, minHeight: 80, onChange: (v) => _set(memo: v)),
          // 기록으로 할 일은 줄 목록으로(버튼을 쌓지 않는다). 저장은 아래 고정 버튼 하나
          Padding(
            padding: const EdgeInsets.only(top: Space.tight),
            child: ListGroup(children: [
              if (s.myBookId != null && communityOpen.value)
                ListItem(label: '커뮤니티에 공유하기', sub: '고른 것만 공개돼요', chevron: true, onPress: () => openCommunityShare(context, widget.id)),
              ListItem(
                label: '이 기록 삭제',
                danger: true,
                onPress: () => appAlert(context, '이 독서 기록을 삭제할까요?', '통계에서도 빠져요. 되돌릴 수 없어요.', [
                  const AlertButton('취소', style: AlertStyle.cancel),
                  AlertButton('삭제', style: AlertStyle.destructive, onPress: _delete),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

const _keep = Object();

/// 독서 기록 추가 열기: bookId 그 책이 골라진 채로(없으면 책 없이), day 그 날짜로(없으면 오늘)
Future<void> openSessionAdd(BuildContext context, {String? bookId, String? day}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/session/new'), builder: (_) => SessionAddScreen(bookId: bookId, day: day)));

/// 독서 시간 빠른 고르기(분)
const _quickMinutes = [(10, '10분'), (30, '30분'), (60, '1시간')];

class SessionAddScreen extends StatefulWidget {
  const SessionAddScreen({super.key, this.bookId, this.day});
  final String? bookId, day;

  @override
  State<SessionAddScreen> createState() => _SessionAddScreenState();
}

class _SessionAddScreenState extends State<SessionAddScreen> {
  final _model = LibraryModel.instance;
  final _pagesKey = GlobalKey();
  final _minutesKey = GlobalKey();
  late final SessionForm _initial = (
    bookId: widget.bookId != null && _model.lib.books.containsKey(widget.bookId) ? widget.bookId : null,
    day: widget.day != null && validDay(widget.day!) && widget.day!.compareTo(today()) <= 0 ? widget.day! : today(),
    time: '',
    minutes: '',
    startPage: '',
    pages: '',
    memo: '',
  );
  late SessionForm _f = _initial;
  bool _saving = false;

  void _set({Object? bookId = _keep, String? day, String? minutes, String? startPage, String? pages, String? memo}) => setState(() => _f = (
        bookId: identical(bookId, _keep) ? _f.bookId : bookId as String?,
        day: day ?? _f.day,
        time: '',
        minutes: minutes ?? _f.minutes,
        startPage: startPage ?? _f.startPage,
        pages: pages ?? _f.pages,
        memo: memo ?? _f.memo,
      ));

  void _showError(GlobalKey key, String say) {
    final c = key.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 200), alignmentPolicy: ScrollPositionAlignmentPolicy.explicit, alignment: 0.2);
    SemanticsService.sendAnnouncement(View.of(context), say, Directionality.of(context));
  }

  /// 저장: 기기에 저장된 뒤 닫는다(들어온 곳에 새 기록이 보인다). 실패하면 화면에 남아 알린다
  Future<void> _save(int durationMs) async {
    if (_saving) return;
    setState(() => _saving = true);
    final t = manualSessionTimes(_f.day, durationMs, DateTime.now());
    final memo = _f.memo.trim();
    final book = _f.bookId;
    final wasRead = book != null && _model.lib.books[book]?.status == ReadStatus.read;
    try {
      final id = await saveManualReading(SessionInput(
        myBookId: _f.bookId,
        startedAt: t.startedAt,
        endedAt: t.endedAt,
        durationMs: durationMs,
        startPage: _page(_f.startPage),
        pagesRead: _page(_f.pages),
        memo: memo.isEmpty ? null : memo,
      ));
      if (!mounted) return;
      // 이번 기록으로 완독이 됐으면(적은 쪽이 마지막 쪽) 연 자리로 돌아가 독서 저장과 같은 저장했어요 창 + 별점(2026-11-24 사용자 5단계)
      final finished = book != null && !wasRead && _model.lib.books[book]?.status == ReadStatus.read;
      final nav = Navigator.of(context);
      nav.pop();
      if (finished) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final o = nav.overlay;
          if (o != null && o.mounted) showSavedDialog(o.context, bookId: book, sessionId: id, finished: true);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        appAlert(context, '기록을 저장하지 못했어요', '적은 내용은 그대로 있어요. ${errorText(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = _model.lib;
    final durationMs = manualDurationMs(_f.minutes);
    final minutesTyped = _f.minutes.trim().isNotEmpty;
    final minutesBad = minutesTyped && durationMs == null;
    // 쪽 검증은 독서 끝 · 기록 수정과 같다
    final e = _f.bookId == null ? null : lib.editions[lib.books[_f.bookId]?.editionId ?? ''];
    final total = e?.pageCount != null && e!.pageCount! > 0 ? e.pageCount!.toInt() : null;
    final sp = _page(_f.startPage), ep = _page(_f.pages);
    final startOver = total != null && sp != null && sp > total;
    final endOver = total != null && ep != null && ep > total;
    final badRange = sp != null && ep != null && ep < sp;
    final pageBad = startOver || endOver || badRange;
    final quick = int.tryParse(_f.minutes.trim());
    // 쓰던 것이 있으면 나갈 때 묻는다(새로 쓰기: '그만 쓸까요?', DESIGN 12장)
    return DraftGuard(
      dirty: () => _f != _initial && !_saving,
      child: Screen(
        title: '독서 기록 추가',
        // 독서 시간이 비면 할 일이 없어 꺼 둔다. 칸 오류면 누를 수 있게 두고 누르면 그 칸을 보인다(DESIGN 12장)
        footer: Btn(
          label: '기록 저장',
          size: 'xlarge',
          busy: _saving,
          disabled: !minutesTyped,
          onPress: () {
            if (durationMs == null) return _showError(_minutesKey, '독서 시간을 확인해 주세요');
            if (pageBad) return _showError(_pagesKey, '쪽 칸을 확인해 주세요');
            _save(durationMs);
          },
        ),
        children: [
          const SizedBox(height: Space.item),
          // 기록 수정 · 독서 끝의 '연결된 책'과 같은 칸
          SelectField(
            label: '연결된 책',
            value: bookTitle(lib, _f.bookId),
            sub: bookAuthor(lib, _f.bookId).isEmpty ? null : bookAuthor(lib, _f.bookId),
            placeholder: '책 연결하기 (선택)',
            onPress: () async {
              final r = await pickBook(context, lib, allowNone: true, addNew: true, current: (id: _f.bookId));
              if (r.picked) _set(bookId: r.id);
            },
          ),
          // 날짜는 오늘까지(DateField 기본 끝), 시작 시각은 묻지 않는다
          DateField(label: '날짜', value: _f.day, onChange: (v) => _set(day: v)),
          // 독서 시간: 칸에 직접 적거나 아래 빠른 고르기(고르면 칸에 그 분이 들어간다)
          KeyedSubtree(
            key: _minutesKey,
            child: Field(
              label: '독서 시간',
              unit: '분',
              value: _f.minutes,
              number: true,
              onChange: (v) => _set(minutes: _digits(v)),
              error: minutesBad ? '1분에서 $manualMaxMinutes분까지 적어 주세요' : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.l),
            child: Segmented<int>(
              items: _quickMinutes,
              value: quick ?? -1,
              onChange: (m) => _set(minutes: '$m'),
            ),
          ),
          Row(key: _pagesKey, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Field(
                label: '시작 쪽 (선택)',
                unit: '쪽',
                value: _f.startPage,
                number: true,
                error: startOver ? '전체 $total쪽보다 커요' : null,
                onChange: (v) => _set(startPage: _digits(v)),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Field(
                label: '도달한 쪽 (선택)',
                unit: '쪽',
                value: _f.pages,
                number: true,
                error: badRange ? '시작 쪽보다 앞이에요' : endOver ? '전체 $total쪽보다 커요' : null,
                onChange: (v) => _set(pages: _digits(v)),
              ),
            ),
          ]),
          Field(label: '짧은 메모 (선택)', value: _f.memo, placeholder: '나만 보는 메모예요', multiline: true, minHeight: 80, onChange: (v) => _set(memo: v)),
        ],
      ),
    );
  }
}
