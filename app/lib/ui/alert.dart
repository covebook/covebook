// 앱이 직접 그리는 확인창(지금 앱 ui/alert.tsx) = TDS Dialog.
//  - 단추 하나(알림 확인) = AlertDialog: 제목 · 설명 · 글자 단추 하나(AlertDialog.AlertButton = TextButton medium · bold · blue500 자리에 갈색)
//  - 단추 둘 = ConfirmDialog: 왼쪽 취소 단추(dark weak large) · 오른쪽 확인 단추(primary fill large). 글자가 길면 세로로 쌓고 단추마다 전체 폭
//  - 셋 이상(TDS에 없음 → 우리 값): 세로로 쌓고 취소는 맨 아래 글자 단추
// 제목 t4 Bold grey800 · 설명 t6 Medium grey600(AlertDialog/ConfirmDialog.Title · Description 기본값).
// 바깥(딤) 누르기 · 뒤로 가기는 닫기(closeOnDimmerClick · closeOnBackEvent 기본 true): 취소 단추가 있으면 취소로, 단추 하나면 그 단추로 닫는다.
// 닫을 수 없는 확인창(cancelable false이거나 고를 것이 둘 이상인데 취소가 없음)은 바깥을 누르면 좌우로 흔든다(closeOnDimmerClick false의 Wiggle)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kit.dart';
import 'theme.dart';

enum AlertStyle { normal, cancel, destructive }

class AlertButton {
  const AlertButton(this.text, {this.onPress, this.style = AlertStyle.normal});
  final String text;
  final VoidCallback? onPress;
  final AlertStyle style;
}

/// stacked: 버튼을 늘 세로로 쌓는다(지금 앱 Dialog처럼: 주요 → 보조 → 맨 아래 글자 버튼)
Future<void> appAlert(BuildContext context, String title, [String? message, List<AlertButton>? buttons, bool cancelable = true, bool stacked = false]) async {
  final list = buttons == null || buttons.isEmpty ? const [AlertButton('확인')] : buttons;
  final cancel = list.where((b) => b.style == AlertStyle.cancel).firstOrNull;
  final dismissTo = cancel ?? (list.length == 1 ? list.first : null);
  final closable = cancelable && dismissTo != null;
  final picked = await showGeneralDialog<AlertButton>(
    context: context,
    // 딤 누르기는 아래 _AlertPage가 직접 받는다(닫거나 흔들기)
    barrierDismissible: false,
    barrierLabel: dismissTo?.text ?? '닫기',
    barrierColor: AppColors.scrim,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => _AlertPage(title: title, message: message, list: list, cancel: cancel, dismissTo: dismissTo, closable: closable, stacked: stacked),
  );
  (picked ?? dismissTo)?.onPress?.call();
}

class _AlertPage extends StatefulWidget {
  const _AlertPage({required this.title, required this.message, required this.list, required this.cancel, required this.dismissTo, required this.closable, required this.stacked});
  final String title;
  final String? message;
  final List<AlertButton> list;
  final AlertButton? cancel, dismissTo;
  final bool closable, stacked;

  @override
  State<_AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<_AlertPage> with SingleTickerProviderStateMixin {
  late final _wiggle = AnimationController(vsync: this, duration: Motion.wiggle);

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  /// 바깥 누르기: 닫을 수 있으면 닫고(취소 · 단추 하나), 아니면 흔든다
  void _outside() {
    if (widget.closable) {
      Navigator.pop(context, widget.dismissTo);
    } else {
      _wiggle.forward(from: 0);
    }
  }

  /// ConfirmDialog 두 단추가 나란히 들어가는지(글자가 길면 세로로 쌓는다, ConfirmDialog 절 '긴 버튼 텍스트')
  bool _fits(BuildContext context, double width, List<AlertButton> pair) {
    final scaler = MediaQuery.textScalerOf(context);
    // 단추 하나 폭(두 단추 사이 8)에서 단추 안 좌우 여백(large 20 · 20)을 뺀 글자 자리
    final room = (width - Space.s) / 2 - 20 * 2;
    for (final b in pair) {
      final p = TextPainter(text: TextSpan(text: b.text, style: AppType.button), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      final w = p.width;
      p.dispose();
      if (w > room) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.list, cancel = widget.cancel;
    final actions = list.where((b) => b != cancel).toList();
    // ConfirmDialog 단추 크기 large(CancelButton · ConfirmButton 기본값). 지우기 확인은 danger fill
    Widget btn(AlertButton b, String kind) => Btn(label: b.text, kind: kind, size: 'large', onPress: () => Navigator.pop(context, b));
    String kindOf(AlertButton b, {bool first = true}) => b.style == AlertStyle.destructive ? 'dangerFill' : first ? 'primary' : 'secondary';
    String leftKind(AlertButton b) => b.style == AlertStyle.destructive ? 'dangerFill' : 'secondary';

    Widget body(double width) {
      // AlertDialog: 단추 하나는 글자 단추(TextButton medium · bold · 갈색), 오른쪽 끝(자리는 공식 없음 → 우리 값)
      if (list.length == 1 && !widget.stacked) {
        final b = list.first;
        return Align(
          alignment: Alignment.centerRight,
          // start: 글자 폭만큼(가운데 맞춤 TextLink는 줄 폭을 다 차지한다)
          child: TextLink(label: b.text, bold: true, start: true, danger: b.style == AlertStyle.destructive, onPress: () => Navigator.pop(context, b)),
        );
      }
      // ConfirmDialog: 취소(dark weak) 왼쪽 · 확인(primary fill) 오른쪽. 두 단추 높이는 같게(큰 글씨에서 한쪽만 두 줄이어도 어긋나지 않게, 2026-11-16 QA 영숙 F6)
      if (list.length == 2 && !widget.stacked) {
        final left = cancel ?? actions.first;
        final right = cancel != null ? actions.first : actions.last;
        if (_fits(context, width, [left, right])) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: btn(left, leftKind(left))),
              const SizedBox(width: Space.s),
              Expanded(child: btn(right, kindOf(right))),
            ]),
          );
        }
        // 글자가 길면 세로로: 확인 단추가 위, 취소가 아래, 단추마다 전체 폭
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          btn(right, kindOf(right)),
          const SizedBox(height: Space.s),
          btn(left, leftKind(left)),
        ]);
      }
      // 셋 이상 · stacked(TDS에 없음 → 우리 값): 주요 → 보조 → 맨 아래 취소 글자 단추
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, b) in actions.indexed) ...[
          if (i > 0) const SizedBox(height: Space.s),
          btn(b, kindOf(b, first: i == 0)),
        ],
        if (cancel != null) ...[const SizedBox(height: Space.s), btn(cancel, 'ghost')],
      ]);
    }

    final card = Material(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(Shape.dialog),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.page + 2, Space.page, Space.page),
        child: LayoutBuilder(
          builder: (context, box) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // 설명이 길면 스크롤(AlertDialog · ConfirmDialog '긴 설명 사용하기')
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: WordText(widget.title, style: AppType.heading)),
                  if (widget.message != null && widget.message!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText(widget.message!, style: AppType.dialogBody)),
                ]),
              ),
            ),
            const SizedBox(height: Space.xl),
            body(box.maxWidth),
          ]),
        ),
      ),
    );

    // 뒤로 가기도 바깥 누르기와 같은 규칙(닫을 수 없으면 흔든다)
    return PopScope(
      canPop: widget.closable,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _wiggle.forward(from: 0);
      },
      child: Stack(children: [
        // 딤 영역(바깥) 누르기. 화면 읽기 이름은 닫을 수 있을 때만('취소' · '확인' 등 닫는 단추 이름)
        Positioned.fill(
          child: widget.closable
              ? Semantics(label: widget.dismissTo?.text ?? '닫기', button: true, child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _outside))
              : ExcludeSemantics(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _outside)),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.page),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 400, maxHeight: MediaQuery.sizeOf(context).height * 0.86),
                child: AnimatedBuilder(
                  animation: _wiggle,
                  // 좌우로 두 번 흔들고 제자리(폭 · 길이는 공식 없음 → Motion.wiggle · wiggleDx)
                  builder: (_, child) => Transform.translate(
                    offset: Offset(math.sin(_wiggle.value * math.pi * 4) * Motion.wiggleDx * (1 - _wiggle.value), 0),
                    child: child,
                  ),
                  // 판 안의 빈 곳을 눌러도 바깥으로 치지 않게 판이 누름을 받는다(안의 단추가 먼저 받는다)
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: card),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
