// 바코드 연속 스캔(2026-11-15 사용자 '바코드 연속 스캔 다 넣어', 페르소나 QA 장서가 F2): 책 뒷면 ISBN 바코드(EAN-13, 978·979)를 비추는 대로
// 찾아 아래 목록에 쌓고, 다 모은 뒤 한 번에 추가한다(추천 장정, 진열 규칙은 한 권 추가와 같다). 같은 바코드는 한 번만 센다.
// 이미 서재에 있는 책은 '내 서재에 있음'으로 보이고 고르지 않는다(같은 책을 또 넣으려면 책 추가에서 별도 소장본으로)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/book_list_import.dart' show ImportRow, isbn13Of;
import '../../domain/library.dart' show ReadStatus;
import '../../services/book_search.dart';
import '../../store/library_model.dart';
import '../../store/settings_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'book_match.dart';
import 'bulk_add.dart';

Future<void> openBarcodeScan(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book/scan'), builder: (_) => const BarcodeScanScreen()));

class _Scanned {
  _Scanned(this.code);
  final String code;
  BookCandidate? book;
  String? ownedId;
  bool busy = true, offline = false, picked = false;
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
    for (final b in cap.barcodes) {
      final code = isbn13Of(b.rawValue ?? '');
      if (code == null || !_seen.add(code)) continue;
      final s = _Scanned(code);
      setState(() => _items.insert(0, s));
      if (SettingsStore.instance.haptics) HapticFeedback.selectionClick();
      _lookup(s);
    }
  }

  Future<void> _lookup(_Scanned s) async {
    setState(() {
      s.busy = true;
      s.offline = false;
    });
    final r = await searchBooks(s.code);
    if (!mounted) return;
    final c = r.ok ? matchCandidate(ImportRow(line: 0, isbn: s.code), r.items) : null;
    setState(() {
      s.busy = false;
      s.offline = !r.ok && r.reason == 'network';
      s.book = c;
      s.ownedId = c == null ? null : ownedBookId(LibraryModel.instance.lib, c);
      s.picked = c != null && s.ownedId == null;
    });
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
    // 더한 책은 목록에서 빼고(실패한 책만 남긴다), 남은 줄은 '내 서재에 있음'을 다시 잰다
    final failed = r.failed.toSet();
    setState(() {
      _saving = false;
      _items.removeWhere((s) => s.picked && s.book != null && !failed.contains(s.book!.title));
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

  @override
  Widget build(BuildContext context) {
    final n = _items.where((s) => s.picked && s.book != null).length;
    return Screen(
      title: '바코드로 찾기',
      scroll: false,
      footer: Btn(label: n == 0 ? '책 뒷면 바코드를 비춰 주세요' : '$n권 추가', disabled: n == 0, busy: _saving, onPress: _addAll),
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
                    child: Text('바코드를 틀 안에 비추면 바로 찾아요', textAlign: TextAlign.center, style: AppType.label.copyWith(color: const Color(0xFFFFFFFF), shadows: const [Shadow(color: Color(0x80000000), blurRadius: 6)])),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
          child: Text(_items.isEmpty ? '찾은 책이 여기에 쌓여요. 여러 권을 이어서 비춰도 돼요.' : '찾은 책 ${_items.length}권 | 고른 책 $n권', style: AppType.sub),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [for (final s in _items) _ScanRow(s: s, onToggle: () => setState(() => s.picked = !s.picked), onRetry: () => _lookup(s), onRemove: () => setState(() => _items.remove(s)))],
          ),
        ),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError(this.e);
  final MobileScannerException e;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(
              e.errorCode == MobileScannerErrorCode.permissionDenied
                  ? '카메라 권한이 꺼져 있어요. 기기 설정에서 책장 한켠의 카메라를 허용하면 바코드로 찾을 수 있어요.'
                  : e.errorCode == MobileScannerErrorCode.unsupported
                      ? '이 기기에서는 바코드를 읽을 수 없어요. 검색으로 찾아 주세요.'
                      : '카메라를 열지 못했어요. 잠시 뒤 다시 열어 주세요.',
              textAlign: TextAlign.center,
              style: AppType.sub,
            ),
          ),
        ),
      );
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.s, required this.onToggle, required this.onRetry, required this.onRemove});
  final _Scanned s;
  final VoidCallback onToggle, onRetry, onRemove;

  @override
  Widget build(BuildContext context) {
    final b = s.book;
    final status = s.busy
        ? '찾는 중이에요'
        : s.offline
            ? '인터넷에 연결되지 않았어요'
            : b == null
                ? '이 바코드의 책을 찾지 못했어요'
                : s.ownedId != null
                    ? '내 서재에 있음'
                    : publisherLine(b);
    final selectable = b != null && s.ownedId == null && !s.busy;
    return Semantics(
      button: selectable,
      selected: selectable && s.picked,
      label: [b?.title ?? 'ISBN ${s.code}', ?status].join(', '),
      excludeSemantics: true,
      child: Pressable(
        onPress: selectable ? onToggle : (s.offline ? onRetry : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Row(children: [
            RealCover(uri: b?.coverUrl, title: b?.title ?? s.code, color: '#F2F4F6', width: 40, ratio: 0.72),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b?.title ?? 'ISBN ${s.code}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong),
                if (b != null && b.authors.isNotEmpty) Text(b.authors.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sub),
                if (status != null)
                  Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: s.ownedId != null ? AppColors.accent : null)),
              ]),
            ),
            const SizedBox(width: Space.s),
            if (s.busy)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkSoft))
            else if (selectable)
              PickMark(on: s.picked)
            else if (s.offline)
              // 줄 안이라 폭이 정해지지 않으므로 Btn 대신 글자 버튼
              Pressable(
                onPress: onRetry,
                child: Padding(padding: const EdgeInsets.all(Space.s), child: Text('다시 찾기', style: AppType.button.copyWith(color: AppColors.accent))),
              )
            else
              IconBtn(label: '목록에서 빼기', onPress: onRemove, child: const LucideIcon('X', size: 18, color: AppColors.inkSoft)),
          ]),
        ),
      ),
    );
  }
}

/// 고름 표시(전체 책 '책장에 진열'과 같은 동그라미 체크): 고르면 대표색 채움 + 흰 체크, 아니면 회색 테두리
class PickMark extends StatelessWidget {
  const PickMark({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? AppColors.accent : AppColors.bg,
          border: on ? null : Border.all(color: AppColors.line, width: 1.5),
        ),
        child: on ? const Center(child: LucideIcon('Check', size: 14, color: AppColors.onAccent, stroke: 3)) : null,
      );
}
