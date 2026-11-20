// 바코드 연속 스캔(2026-11-15 사용자 '바코드 연속 스캔 다 넣어', 페르소나 QA 장서가 F2): 책 뒷면 ISBN 바코드(EAN-13, 978·979)를 비추는 대로
// 찾아 아래 목록에 쌓고, 다 모은 뒤 한 번에 추가한다(추천 장정, 진열 규칙은 한 권 추가와 같다). 같은 바코드는 한 번만 센다.
// 이미 내 책에 있는 책은 '내 책에 있음'(흐린 원)으로 보이고 고르지 않는다(같은 책을 또 넣으려면 책 추가에서 별도 소장본으로).
// 못 찾은 바코드는 누르면 책 추가에서 다시 찾거나 직접 등록한다(목록 가져오기와 같다)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/book_list_import.dart' show ImportRow, isbn13Of;
import '../../domain/library.dart' show ReadStatus, authorLine;
import '../../services/book_search.dart';
import '../../store/library_model.dart';
import '../../store/settings_store.dart';
import '../../ui/draft_guard.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'add_book_screen.dart' show openAddBook;
import 'book_match.dart';
import 'bulk_add.dart';

Future<void> openBarcodeScan(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book/scan'), builder: (_) => const BarcodeScanScreen()));

class _Scanned {
  _Scanned(this.code);
  final String code;
  BookCandidate? book;
  String? ownedId;
  bool busy = true, picked = false;

  /// 검색이 실패한 까닭: network(인터넷 없음) · error(검색 오류). 둘 다 '다시 찾기'(찾지 못한 책과 다르다)
  String? fail;
}

class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  // 책 바코드만(EAN-13). 같은 장면을 너무 자주 읽지 않게 0.4초 간격
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.ean13], detectionTimeoutMs: 400);
  final _items = <_Scanned>[];
  final _seen = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    // 위에 다른 화면 · 확인창이 떠 있으면(책 추가 · 나가기 확인) 읽지 않는다
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    for (final b in cap.barcodes) {
      final code = isbn13Of(b.rawValue ?? '');
      if (code == null || !_seen.add(code)) continue;
      final s = _Scanned(code);
      setState(() => _items.insert(0, s));
      if (SettingsStore.instance.haptics) HapticFeedback.selectionClick();
      _lookup(s);
    }
  }

  /// 목록에서 뺀다. 뺀 바코드는 다시 비추면 다시 찾는다(2026-11-19 공통 규칙: 한 번 본 코드는 빼도 다시 잡히지 않았다)
  void _forget(_Scanned s) {
    _items.remove(s);
    _seen.remove(s.code);
  }

  Future<void> _lookup(_Scanned s) async {
    setState(() {
      s.busy = true;
      s.fail = null;
    });
    final r = await searchBooks(s.code);
    if (!mounted) return;
    final c = r.ok ? matchCandidate(ImportRow(line: 0, isbn: s.code), r.items) : null;
    setState(() {
      s.busy = false;
      // 검색이 실패하면(인터넷 없음 · 서버 오류) '찾지 못했어요'가 아니라 다시 찾기(2026-11-19 공통 규칙: 서버 오류도 '찾지 못했어요'였다)
      s.fail = r.ok ? null : (r.reason == 'network' ? 'network' : 'error');
      s.book = c;
      s.ownedId = c == null ? null : ownedBookId(LibraryModel.instance.lib, c);
      s.picked = c != null && s.ownedId == null;
    });
  }

  /// 못 찾은 바코드: 책 추가를 그 ISBN으로 열어 다시 찾거나 직접 등록한다(목록 가져오기의 못 찾은 줄과 같은 다음 행동).
  /// 카메라는 그동안 멈추고, 넣었으면 목록에서 뺀다(여러 권 추가 뒤와 같다)
  Future<void> _addMissing(_Scanned s) async {
    await _scanner.stop();
    if (!mounted) return;
    final id = await openAddBook(context, q: s.code, fromList: true);
    if (!mounted) return;
    if (id != null) setState(() => _forget(s));
    await _scanner.start();
  }

  Future<void> _addAll() async {
    final picks = [for (final s in _items.reversed) if (s.picked && s.book != null) (book: s.book!, status: ReadStatus.want)];
    if (picks.isEmpty || _saving) return;
    setState(() => _saving = true);
    // 카메라는 추가하는 동안 멈춘다(진행 창 뒤에서 계속 읽지 않게)
    await _scanner.stop();
    if (!mounted) return;
    final r = await addBooks(context, picks);
    if (!mounted) return;
    // 더한 책은 목록에서 빼고(실패한 책만 남긴다), 남은 줄은 '내 책에 있음'을 다시 잰다
    final failed = r.failed.toSet();
    setState(() {
      _saving = false;
      for (final s in [for (final s in _items) if (s.picked && s.book != null && !failed.contains(s.book!.title)) s]) {
        _forget(s);
      }
      for (final s in _items) {
        if (s.book != null) s.ownedId = ownedBookId(LibraryModel.instance.lib, s.book!);
        if (s.ownedId != null) s.picked = false;
      }
    });
    final next = await showBulkDone(context, r);
    if (!mounted) return;
    if (next != null) return goAfterBulk(context, next);
    await _scanner.start();
  }

  /// 나갈 때 물을지: 넣을 수 있는 책 · 찾는 중 · 다시 찾을 줄이 있으면(못 찾은 줄 · 이미 있는 책만 있으면 묻지 않는다)
  bool get _dirty => !_saving && _items.any((s) => s.busy || s.fail != null || (s.book != null && s.ownedId == null));

  @override
  Widget build(BuildContext context) {
    final n = _items.where((s) => s.picked && s.book != null).length;
    // 찾아 둔 책이 있으면 나갈 때 묻는다(docs/design/DESIGN.md 12장, 2026-11-19 공통 규칙: 묻지 않고 버렸다)
    return DraftGuard(
      dirty: () => _dirty,
      title: '바코드 찾기를 그만할까요?',
      body: '지금 나가면 찾은 책은 추가되지 않아요.',
      child: Screen(
        title: '바코드로 찾기',
        scroll: false,
        // 카메라 화면은 스크롤하지 않으니 위 줄을 그대로 둔다
        fixedHead: true,
        footer: ValueListenableBuilder<MobileScannerState>(
          valueListenable: _scanner,
          builder: (context, cam, _) {
            // 카메라를 열지 못하면(권한 꺼짐 · 지원 안 함) 아래 단추는 할 수 있는 일로: 검색으로 돌아가 제목으로 찾기(DESIGN 11장 '권한 거부')
            if (cam.error != null && _items.isEmpty) return Btn(label: '제목으로 찾기', size: 'xlarge', onPress: () => Navigator.maybePop(context));
            // 화면 아래 주요 단추 xlarge. 단추 글자는 하는 일 이름, 꺼진 이유는 단추 위 안내 글(DESIGN 5-2 · 9장)
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (n == 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s),
                  child: NoticeText(_items.isEmpty ? '책 뒷면 바코드를 비춰 주세요.' : '추가할 책을 골라 주세요.', center: true),
                ),
              Btn(label: n == 0 ? '추가' : '$n권 추가', size: 'xlarge', disabled: n == 0, busy: _saving, onPress: _addAll),
            ]);
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(fit: StackFit.expand, children: [
                  MobileScanner(controller: _scanner, onDetect: _onDetect, errorBuilder: (ctx, e) => _CameraError(e)),
                  // 비출 자리(가운데 가로로 긴 틀)와 안내
                  IgnorePointer(
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.72,
                        heightFactor: 0.38,
                        child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xE6FFFFFF), width: 2))),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Text('바코드를 틀 안에 비추면 바로 찾아요', textAlign: TextAlign.center, style: AppType.label.copyWith(color: AppColors.white, shadows: const [Shadow(color: Color(0x80000000), blurRadius: 6)])),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
            // 찾은 수가 바뀌면 화면 읽기가 바로 읽는다(진동만으로는 모른다, DESIGN 15장)
            child: Semantics(
              liveRegion: true,
              child: MetaText(_items.isEmpty ? '찾은 책이 여기에 쌓여요. 여러 권을 이어서 비춰도 돼요.' : ['찾은 책 ${_items.length}권', '고른 책 $n권'].join(metaSep), style: AppType.sub),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final s in _items)
                  _ScanRow(s: s, onToggle: () => setState(() => s.picked = !s.picked), onRetry: () => _lookup(s), onMissing: () => _addMissing(s)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 카메라를 열지 못했을 때 카메라 자리(회색 칸 안 안내). 권한 거부는 사용자가 고른 것이라 오류 빨강이 아닌 안내(DESIGN 11장),
/// 다른 길은 아래 단추 '제목으로 찾기'
class _CameraError extends StatelessWidget {
  const _CameraError(this.e);
  final MobileScannerException e;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: NoticeText(
              e.errorCode == MobileScannerErrorCode.permissionDenied
                  ? '카메라 권한이 꺼져 있어요. 기기 설정에서 켜 주세요.'
                  : e.errorCode == MobileScannerErrorCode.unsupported
                      ? '이 기기에서는 바코드를 읽을 수 없어요. 제목으로 찾아 주세요.'
                      : '카메라를 열지 못했어요. 잠시 뒤 다시 열어 주세요.',
              center: true,
            ),
          ),
        ),
      );
}

/// 찾은 책 한 줄(공용 책 줄 BookRow 작게, 2026-11-19 공통 규칙): 표지 · 제목 · 저자 · 상태, 오른쪽은 목록 가져오기 줄과 같게
/// 고르는 원 · 다시 찾기(검색 실패) · 꺾쇠(못 찾음: 누르면 책 추가) · 흐린 원(이미 내 책에 있음)
class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.s, required this.onToggle, required this.onRetry, required this.onMissing});
  final _Scanned s;
  final VoidCallback onToggle, onRetry, onMissing;

  @override
  Widget build(BuildContext context) {
    final b = s.book;
    final title = b?.title ?? 'ISBN ${s.code}';
    final status = s.busy
        ? '찾는 중이에요'
        : s.fail == 'network'
            ? '인터넷에 연결되지 않았어요'
            : s.fail != null
                ? '검색하지 못했어요'
                : b == null
                    ? '이 바코드의 책을 찾지 못했어요'
                    : s.ownedId != null
                        ? '내 책에 있음'
                        : publisherLine(b);
    final selectable = b != null && s.ownedId == null && !s.busy;
    final missing = !s.busy && s.fail == null && b == null;
    return BookRow(
      cover: RealCover(uri: b?.coverUrl, title: b?.title ?? s.code, width: BookRow.coverWidth(BookRowSize.small), ratio: 0.72),
      title: title,
      meta: b != null && b.authors.isNotEmpty ? authorLine(b.authors) : null,
      third: status,
      trailing: s.busy
          ? const Spinner()
          : selectable
              ? RadioMark(on: s.picked)
              : s.fail != null
                  // 목록 가져오기 '다시 찾기'와 같은 줄 안 작은 단추
                  ? Btn(label: '다시 찾기', kind: 'secondary', size: 'medium', onPress: onRetry)
                  : missing
                      ? const Chevron()
                      // 이미 내 책에 있는 책: 흐린 원(여러 권 고르기 · 목록 가져오기와 같게, 2026-11-19 공통 규칙: 빼기 X였다)
                      : const RadioMark(on: false, dim: true),
      onPress: selectable ? onToggle : (s.fail != null ? onRetry : (missing ? onMissing : null)),
      // 여러 권 고르기 줄은 화면 읽기 '선택됨/선택 안 됨'(DESIGN 13장)
      checked: selectable ? s.picked : null,
      // 화면 읽기에는 세로줄 대신 쉼표(DESIGN 15장)
      label: [title, ?status?.split(metaSep).join(', ')].join(', '),
    );
  }
}
