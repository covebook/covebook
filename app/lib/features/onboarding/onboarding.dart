// 처음 쓰는 사람 안내(온보딩): 책 한 권을 꼭 추가해 책장에 꽂고, 그 책을 골라 돌려 보며 꾸미기까지 해 본다.
// 2026-11-25 사용자 '온보딩으로 무조건 책 하나 추가하게 해서 책장에 올리고 선택해서 회전 같은 꾸미기까지 하게 만들어주고'.
// 단계는 저장하지 않고 지금 상태에서 정한다(앱을 껐다 켜도 이어진다):
//  1 add      서재에 책이 없다: 책장 위 어두운 덮개 + 아래 카드 '첫 책 추가하기'(닫기 없음, 하단 탭도 숨긴다). 추가하면 책장에 바로 진열된다
//  2 place    책은 있는데 책장에 없다: 머리 '책장에 꽂기'(+)를 가리킨다. 시트가 열리면 '표지를 위로 끌어 꽂아요'
//  3 decorate 책장에 있다: 머리 '꾸미기'를 가리킨다
//  4 select   꾸미는 중 고른 책이 없다: '꽂은 책을 눌러 골라요'
//  5 rotate   고른 책이 있다: 회전 막대를 가리킨다(자세 · 기대기 · 앞뒤를 바꿔도 된다)
//  6 finish   바꿨다: 머리 '완료'를 가리킨다. 완료하면 끝(토스트)
// 이미 책이 있는 서재(기존 사용자 · 동기화로 받은 서재)는 바로 끝낸 것으로 친다
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../db/kv_store.dart';
import '../../domain/library.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

enum OnbStep { add, place, decorate, select, rotate, finish }

class Onboarding extends ChangeNotifier {
  Onboarding._();
  static final instance = Onboarding._();
  static const _key = 'onboarding-done';

  bool loaded = false;

  /// 끝났다(또는 처음부터 필요 없었다)
  bool done = true;

  /// 이번에 안내를 시작한 때: 이보다 먼저 만든 책이 들어오면(동기화) 기존 서재라 끝낸다
  DateTime? _since;

  /// 꾸미는 중 고른 책을 바꿔 봤다(회전 · 자세 · 기대기 · 앞뒤)
  bool changed = false;

  /// 안내가 가리킬 자리(화면 좌표, [CoachTarget]이 그릴 때마다 알린다)
  final targets = <String, Rect>{};
  bool _notifyQueued = false;

  bool get active => loaded && !done;

  /// 책이 하나라도 있는 서재(숨긴 책은 빼고)
  static bool hasBooks(Library lib) => lib.books.values.any((b) => b.hiddenAt == null);

  /// 서재를 다 읽은 뒤 한 번: 끝낸 적이 있거나 책이 이미 있으면 끝, 아니면 시작
  Future<void> load(Library lib) async {
    if (loaded) return;
    final v = await KvStore.get(_key);
    loaded = true;
    if (v == '1' || hasBooks(lib)) {
      done = true;
      if (v != '1') KvStore.set(_key, '1').ignore();
    } else {
      done = false;
      _since = DateTime.now();
    }
    notifyListeners();
  }

  /// 서재가 바뀌었다: 안내를 시작하기 전에 만든 책이 들어오면(다른 기기 서재를 받음) 끝낸다
  void libraryChanged(Library lib) {
    final since = _since;
    if (!active || since == null) return;
    final old = lib.books.values.any((b) => b.hiddenAt == null && (DateTime.tryParse(b.createdAt)?.isBefore(since.subtract(const Duration(minutes: 1))) ?? false));
    if (old) finish();
  }

  void markChanged() {
    if (!active || changed) return;
    changed = true;
    notifyListeners();
  }

  void finish() {
    if (done) return;
    done = true;
    KvStore.set(_key, '1').ignore();
    notifyListeners();
  }

  /// 시험 · 로그아웃 뒤 처음부터
  @visibleForTesting
  void reset({bool loaded = false, bool done = true}) {
    this.loaded = loaded;
    this.done = done;
    changed = false;
    _since = loaded && !done ? DateTime.now() : null;
    targets.clear();
  }

  void _setTarget(String id, Rect r) {
    if (targets[id] == r) return;
    targets[id] = r;
    if (!active || _notifyQueued) return;
    _notifyQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyQueued = false;
      notifyListeners();
    });
  }
}

/// 안내가 가리킬 자리: 그릴 때마다 화면 좌표 네모를 [Onboarding.targets]에 알린다(배치는 그대로)
class CoachTarget extends SingleChildRenderObjectWidget {
  const CoachTarget({super.key, required this.id, super.child});
  final String id;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderCoachTarget(id);

  @override
  void updateRenderObject(BuildContext context, RenderCoachTarget renderObject) => renderObject.id = id;
}

class RenderCoachTarget extends RenderProxyBox {
  RenderCoachTarget(this.id);
  String id;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (Onboarding.instance.active && attached && hasSize) Onboarding.instance._setTarget(id, localToGlobal(Offset.zero) & size);
  }
}

/// 첫 화면 카드: 책장 위 어두운 덮개(누르기를 막는다) + 아래 카드. 닫기는 없다(책 한 권은 꼭 추가)
class OnboardingWelcome extends StatelessWidget {
  const OnboardingWelcome({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(children: [
      Positioned.fill(child: AbsorbPointer(child: ColoredBox(color: AppColors.ink.withValues(alpha: 0.42)))),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Container(
            decoration: const BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet))),
            padding: EdgeInsets.fromLTRB(Space.page, Space.xl, Space.page, pad.bottom + Space.l),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMax),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Semantics(header: true, child: WordText('첫 책을 책장에 꽂아 볼까요?', style: AppType.heading)),
                  const SizedBox(height: Space.s),
                  WordText('읽고 있는 책이나 아끼는 책 한 권이면 돼요. 추가하면 책장에 바로 꽂히고, 돌려 세우거나 눕혀서 꾸밀 수 있어요.', style: AppType.secondary),
                  const SizedBox(height: Space.xl),
                  Btn(label: '첫 책 추가하기', size: 'xlarge', onPress: onAdd),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// 말풍선 안내: 가리킬 자리([target], 화면 좌표) 위나 아래에 뜨고 꼭지가 그 가운데를 가리킨다. 누르기는 통과한다.
/// 가리킬 자리가 없으면 [fallbackBottom](화면 아래에서) 위에 가운데로
class CoachBubble extends StatelessWidget {
  const CoachBubble({super.key, required this.text, this.target, this.below = false, this.fallbackBottom = 160});
  final String text;
  final Rect? target;

  /// 자리 아래에 띄운다(머리줄 아이콘 · 완료처럼 화면 위쪽 자리)
  final bool below;
  final double fallbackBottom;

  static const _tip = 8.0;
  static const _maxW = 280.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final t = target;
    final bubble = DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.toast, borderRadius: BorderRadius.all(Radius.circular(Shape.button)), boxShadow: [Shape.floatShadow]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        child: WordText(text, style: AppType.toast),
      ),
    );
    // 꼭지(작은 세모): 자리 가운데 x를 가리킨다
    Widget tip(double x) => Positioned(
          left: x - _tip,
          top: below ? 0 : null,
          bottom: below ? null : 0,
          child: CustomPaint(size: const Size(_tip * 2, _tip), painter: _TipPainter(down: !below)),
        );
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: LayoutBuilder(builder: (context, box) {
          final w = math.min(_maxW, box.maxWidth - Space.page * 2);
          if (t == null) {
            return Stack(children: [Positioned(left: (box.maxWidth - w) / 2, width: w, bottom: fallbackBottom, child: bubble)]);
          }
          final cx = t.center.dx.clamp(Space.page + _tip * 2, box.maxWidth - Space.page - _tip * 2).toDouble();
          final left = (cx - w / 2).clamp(Space.page, box.maxWidth - Space.page - w).toDouble();
          final column = Stack(clipBehavior: Clip.none, children: [
            Padding(padding: EdgeInsets.only(top: below ? _tip : 0, bottom: below ? 0 : _tip), child: bubble),
            tip(cx - left),
          ]);
          return Stack(children: [
            below
                ? Positioned(left: left, width: w, top: t.bottom + Space.xs, child: column)
                : Positioned(left: left, width: w, bottom: size.height - t.top + Space.xs, child: column),
          ]);
        }),
      ),
    );
  }
}

class _TipPainter extends CustomPainter {
  _TipPainter({required this.down});
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    if (down) {
      p
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    } else {
      p
        ..moveTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width / 2, 0)
        ..close();
    }
    canvas.drawPath(p, Paint()..color = AppColors.toast);
  }

  @override
  bool shouldRepaint(_TipPainter old) => old.down != down;
}
