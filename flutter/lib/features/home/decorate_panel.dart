// 꾸미기 모드에서 하단 탭 바 자리에 뜨는 조작부(지금 앱 features/home/DecoratePanel.tsx, 2026-10-26 꾸미기 시안):
// 고른 책 제목·되돌리기·완료, 자세 탭(책등·표지·눕힘, 아이콘 + 밑줄), 줄마다 '이름 · 막대 · 숫자'(위치 mm, 회전 °),
// 책등 책은 회전 대신 기대기(왼쪽·바로·오른쪽: 방향만 고르고 각도는 옆 책과의 틈으로). 막대에는 갈 수 있는 범위를 진한 띠로.
// 막대는 놓을 때 확정한다(끄는 동안은 숫자와 손잡이만 따라간다).
// 2026-11-16 QA 영숙 F7·F8: 큰 글씨에서는 제목·라벨을 따로 줄에 두고(잘리거나 '위치기대기'로 세로로 섰다), 안내에 끌어 옮기기를 넣고,
// 고른 책을 왼쪽·오른쪽으로 한 칸씩 옮기는 단추를 둔다(끌기를 못 하는 화면 읽기 사용자도 순서를 바꾼다)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/geometry.dart';
import '../../domain/types.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

const _thumb = 26.0, _track = 4.0;

class DecoratePanel extends StatelessWidget {
  const DecoratePanel({
    super.key,
    required this.title,
    required this.pose,
    required this.lean,
    required this.canLean,
    required this.msg,
    this.angles,
    required this.spin,
    required this.spinMax,
    required this.spinRange,
    required this.depth,
    required this.canUndo,
    required this.onPose,
    required this.onLean,
    required this.onSpin,
    required this.onDepth,
    required this.onUndo,
    required this.onDone,
    this.bookKey,
    this.onSkin,
    this.onMove,
    this.canMove = (left: false, right: false),
    this.place,
  });

  final String? title;
  final Pose? pose;
  final int lean;
  final ({bool left, bool right}) canLean;
  final String? msg;

  /// 표지 책: 지금 뒤로 젖힌 각도(머리 손잡이)
  final String? angles;
  final double spin;
  final double spinMax;
  final ({double lo, double hi})? spinRange;
  final ({double lo, double hi, double z})? depth;
  final bool canUndo;
  final ValueChanged<Pose> onPose;
  final ValueChanged<int> onLean;
  final ValueChanged<double> onSpin;
  final ValueChanged<double> onDepth;
  final VoidCallback onUndo;
  final VoidCallback onDone;

  /// 고른 책이 바뀌면 막대 상태를 새로
  final Object? bookKey;

  /// 선반·벽지 고르기(스토어) 열기
  final VoidCallback? onSkin;

  /// 고른 책을 같은 선반에서 왼쪽(-1)·오른쪽(1)으로 한 칸
  final ValueChanged<int>? onMove;
  final ({bool left, bool right}) canMove;

  /// 고른 책 자리('1번째 선반 · 왼쪽에서 3번째'): 옮기면 화면 읽기가 새 자리를 읽는다
  final String? place;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final turns = pose == Pose.horizontal || pose == Pose.front;
    final big = largeText(context);
    final head = Text(
      keepAll(title ?? '꾸밀 책을 눌러 고르세요'),
      maxLines: big ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: title != null ? AppType.pageTitle : AppType.row.copyWith(color: AppColors.inkSoft),
    );
    final actions = <Widget>[
      // 선반·벽지(스토어): 2026-11-16 메뉴 구조 개편으로 책장 머리에서 빼고 꾸미기 안에서 연다
      if (onSkin != null) ...[
        Semantics(
          button: true,
          label: '선반·벽지',
          onTap: onSkin,
          excludeSemantics: true,
          child: Pressable(
            onPress: onSkin,
            child: SizedBox(height: 40, child: Center(child: Text('선반·벽지', softWrap: false, style: AppType.caption))),
          ),
        ),
        const SizedBox(width: 14),
      ],
      Semantics(
        button: true,
        enabled: canUndo,
        label: '되돌리기',
        onTap: canUndo ? onUndo : null,
        excludeSemantics: true,
        child: Opacity(
          opacity: canUndo ? 1 : 0.35,
          child: Pressable(onPress: canUndo ? onUndo : null, child: const SizedBox(width: 40, height: 40, child: Center(child: LucideIcon('Undo2', size: 22, stroke: 1.5)))),
        ),
      ),
      const SizedBox(width: 10),
      Semantics(
        button: true,
        label: '완료',
        onTap: onDone,
        excludeSemantics: true,
        child: Pressable(
          onPress: onDone,
          child: SizedBox(height: 40, child: Center(child: Text('완료', softWrap: false, style: AppType.buttonSmall))),
        ),
      ),
    ];
    return Container(
      // 큰 글씨에서도 책장이 위에 보이게 높이를 막고 안을 밀어 본다
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet)),
        border: Border(top: BorderSide(color: AppColors.line, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(Space.page + 4, 0, Space.page + 4, bottom + 6),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(width: 38, height: 4.5, margin: const EdgeInsets.only(top: 10), decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3))),
        ),
        // 큰 글씨: 단추 줄 아래에 제목을 두 줄까지(한 줄에 두면 제목·안내가 잘려 옆 단추에 붙었다)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: big
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                  Padding(padding: const EdgeInsets.only(top: Space.xs), child: head),
                ])
              : Row(children: [Expanded(child: head), ...actions]),
        ),
        // 처음 안내: 끌어서 자리를 옮기는 길(길게 눌러 끌기 말고는 알려 주지 않았다)
        if (title == null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: WordText('책을 눌러 고르면 자세를 바꿀 수 있어요. 책을 끌어 자리를 옮겨요.', style: AppType.caption),
          ),
        if (msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(msg!, style: AppType.caption.copyWith(color: AppColors.danger))),
        // 큰 글씨에서 조작부가 화면보다 길어지면 안에서 밀어 본다
        Flexible(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Row(children: [
                  for (final p in const [Pose.upright, Pose.front, Pose.horizontal])
                    Expanded(child: _PoseTab(pose: p, on: title != null && pose == p, disabled: title == null, onPress: () => onPose(p))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Column(children: [
                  if (title != null && onMove != null)
                    _Row(
                      label: '순서',
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: _MoveChoice(dir: -1, disabled: !canMove.left, onPress: () => onMove!(-1))),
                          const SizedBox(width: 6),
                          Expanded(child: _MoveChoice(dir: 1, disabled: !canMove.right, onPress: () => onMove!(1))),
                        ]),
                        if (place != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Semantics(liveRegion: true, child: Text(place!, style: AppType.caption)),
                          ),
                      ]),
                    ),
                  if (depth != null)
                    _Row(label: '위치', child: _DepthSlider(key: ValueKey(('d', bookKey)), lo: depth!.lo, hi: depth!.hi, value: depth!.z, onChange: onDepth)),
                  if (title != null && turns)
                    _Row(label: '회전', child: _SpinSlider(key: ValueKey(('s', bookKey, pose)), value: spin, max: spinMax, range: spinRange, onChange: onSpin)),
                  if (title != null && !turns)
                    _Row(
                      label: '기대기',
                      child: Row(children: [
                        for (final (i, d) in const [-1, 0, 1].indexed) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: _LeanChoice(
                              dir: d,
                              on: pose == Pose.upright && lean == d,
                              disabled: pose != Pose.upright || (d < 0 && !canLean.left) || (d > 0 && !canLean.right),
                              onPress: () => onLean(d),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  if (angles != null && pose == Pose.front)
                    Padding(padding: EdgeInsets.only(left: big ? 0 : 48), child: Align(alignment: Alignment.centerLeft, child: Text(angles!, style: AppType.caption))),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// 글자를 크게 키운 화면(1.3배부터): 라벨을 위에, 제목을 따로 줄에
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) >= 13;

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, softWrap: false, style: AppType.sub.copyWith(color: AppColors.ink));
    // 큰 글씨: 라벨을 위 줄에(48 칸에서 '위치'·'기대기'가 한 글자씩 세로로 섰다)
    if (largeText(context)) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, child]),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(children: [
        SizedBox(width: 48, child: text),
        Expanded(child: child),
      ]),
    );
  }
}

const _poseNames = {Pose.upright: '책등', Pose.front: '표지', Pose.horizontal: '눕힘'};

class _PoseTab extends StatelessWidget {
  const _PoseTab({required this.pose, required this.on, required this.disabled, required this.onPress});
  final Pose pose;
  final bool on, disabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.accent : AppColors.inkSoft;
    return Semantics(
      button: true,
      selected: on,
      enabled: !disabled,
      label: _poseNames[pose],
      onTap: disabled ? null : onPress,
      excludeSemantics: true,
      child: Opacity(
        opacity: disabled ? 0.35 : 1,
        child: Pressable(
          onPress: disabled ? null : onPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.touch),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 2),
              CustomPaint(size: const Size(30, 30), painter: _PoseIcon(pose, color)),
              const SizedBox(height: 6),
              Text(_poseNames[pose]!, style: (on ? AppType.labelStrong : AppType.bodySmall).copyWith(color: on ? AppColors.ink : AppColors.inkSoft)),
              const SizedBox(height: 9),
              Container(width: 52, height: 2.5, decoration: BoxDecoration(color: on ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 자세 아이콘(26 칸 viewBox를 30으로): 책등 세로 막대·표지 넓은 판·눕힘 가로 막대
class _PoseIcon extends CustomPainter {
  _PoseIcon(this.pose, this.color);
  final Pose pose;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26);
    final r = switch (pose) {
      Pose.upright => const Rect.fromLTWH(10, 3, 6, 20),
      Pose.front => const Rect.fromLTWH(6, 4, 14, 18),
      Pose.horizontal => const Rect.fromLTWH(2.5, 10, 21, 6),
    };
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.4)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color);
  }

  @override
  bool shouldRepaint(_PoseIcon old) => old.pose != pose || old.color != color;
}

const _leanNames = {-1: '왼쪽', 0: '바로', 1: '오른쪽'};

class _LeanChoice extends StatelessWidget {
  const _LeanChoice({required this.dir, required this.on, required this.disabled, required this.onPress});
  final int dir;
  final bool on, disabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        enabled: !disabled,
        label: _leanNames[dir],
        onTap: disabled ? null : onPress,
        excludeSemantics: true,
        child: Opacity(
          opacity: disabled ? 0.3 : 1,
          child: Pressable(
            onPress: disabled ? null : onPress,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Shape.input), border: on ? Border.all(color: AppColors.inkFaint) : null),
              child: Flex(
                direction: largeText(context) ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(size: const Size(26, 26), painter: _LeanIcon(dir)),
                  const SizedBox(width: 6),
                  Text(_leanNames[dir]!, softWrap: false, style: AppType.micro.copyWith(color: AppColors.ink)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 순서 단추: 같은 선반에서 왼쪽·오른쪽으로 한 칸(끝이면 흐리게)
class _MoveChoice extends StatelessWidget {
  const _MoveChoice({required this.dir, required this.disabled, required this.onPress});
  final int dir;
  final bool disabled;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final name = dir < 0 ? '왼쪽으로' : '오른쪽으로';
    return Semantics(
      button: true,
      enabled: !disabled,
      label: '$name 한 칸 옮기기',
      onTap: disabled ? null : onPress,
      excludeSemantics: true,
      child: Opacity(
        opacity: disabled ? 0.3 : 1,
        child: Pressable(
          onPress: disabled ? null : onPress,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Shape.input), border: Border.all(color: AppColors.line)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (dir < 0) const LucideIcon('ChevronLeft', size: 20),
              Flexible(child: WordText(name, textAlign: TextAlign.center, style: AppType.micro.copyWith(color: AppColors.ink))),
              if (dir > 0) const LucideIcon('ChevronRight', size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 기대기 아이콘: 기대는 쪽 옆 책(옅게) + 기운 책
class _LeanIcon extends CustomPainter {
  _LeanIcon(this.dir);
  final int dir;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26);
    final side = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = AppColors.ink.withValues(alpha: 0.55);
    final me = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.ink;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(dir < 0 ? 5 : dir > 0 ? 15 : 7, 4, 6, 19), const Radius.circular(1.2)), side);
    canvas.save();
    if (dir != 0) {
      canvas.translate(13, 23);
      canvas.rotate(dir * 16 * math.pi / 180);
      canvas.translate(-13, -23);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(dir < 0 ? 13 : dir > 0 ? 7 : 14, 4, 6, 19), const Radius.circular(1.2)), me);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LeanIcon old) => old.dir != dir;
}

/// 막대 공통 그림: 전체(옅게) · 갈 수 있는 범위(진한 띠) · 기준점에서 손잡이까지 갈색 · 손잡이
class _BarPainter extends CustomPainter {
  _BarPainter({required this.band, required this.fill, required this.thumb, this.tick});
  final (double, double) band, fill;
  final double thumb;
  final double? tick;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    RRect bar(double a, double b) => RRect.fromRectAndRadius(Rect.fromLTRB(math.min(a, b), y - _track / 2, math.max(a, b), y + _track / 2), const Radius.circular(_track / 2));
    canvas.drawRRect(bar(0, size.width), Paint()..color = AppColors.surface);
    canvas.drawRRect(bar(band.$1, band.$2), Paint()..color = AppColors.track);
    canvas.drawRRect(bar(fill.$1, fill.$2), Paint()..color = AppColors.accent);
    if (tick != null) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tick! - 1, y - 6, 2, 12), const Radius.circular(1)), Paint()..color = AppColors.inkFaint);
    final c = Offset(thumb, y);
    canvas.drawCircle(c, _thumb / 2, Paint()..color = AppColors.bg);
    canvas.drawCircle(c, _thumb / 2 - 0.75, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.inkSoft);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.band != band || old.fill != fill || old.thumb != thumb || old.tick != tick;
}

/// 회전 막대(-max ~ +max): 손잡이를 잡으면 끈 거리만큼, 빈 트랙을 누르면 그 자리 값. 0 근처는 살짝 붙는다
class _SpinSlider extends StatefulWidget {
  const _SpinSlider({super.key, required this.value, required this.max, required this.range, required this.onChange});
  final double value, max;
  final ({double lo, double hi})? range;
  final ValueChanged<double> onChange;

  @override
  State<_SpinSlider> createState() => _SpinSliderState();
}

class _SpinSliderState extends State<_SpinSlider> {
  double? _live;
  ({double x0, double v0})? _grab;

  double _snap(double d) {
    final c = math.max(-widget.max, math.min(widget.max, d));
    return c.abs() < 0.75 ? 0 : (c * 2).roundToDouble() / 2;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _live ?? widget.value;
    return Row(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final w = math.max(1.0, box.maxWidth - 4);
          double xOf(double d) => (math.max(-widget.max, math.min(widget.max, d)) / widget.max + 1) / 2 * w;
          double toDeg(double x) {
            final d = math.max(-1.0, math.min(1.0, x / w * 2 - 1)) * widget.max;
            return d.abs() < 1.5 ? 0 : (d * 2).roundToDouble() / 2;
          }

          final pos = xOf(shown), zero = xOf(0);
          final band = widget.range != null ? (xOf(widget.range!.lo), xOf(widget.range!.hi)) : (0.0, w);
          return Semantics(
            slider: true,
            label: '회전',
            value: '${shown.round()}도',
            increasedValue: '${math.min(widget.max, shown.round() + 2)}도',
            decreasedValue: '${math.max(-widget.max, shown.round() - 2.0)}도',
            onIncrease: () => widget.onChange(math.min(widget.max, shown.roundToDouble() + 2)),
            onDecrease: () => widget.onChange(math.max(-widget.max, shown.roundToDouble() - 2)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (e) {
                final x = e.localPosition.dx - 4;
                final v = (x - pos).abs() <= 22 ? shown : toDeg(x);
                _grab = (x0: x, v0: v);
                setState(() => _live = v);
              },
              onHorizontalDragUpdate: (e) {
                final g = _grab;
                if (g == null) return;
                final x = e.localPosition.dx - 4;
                setState(() => _live = (x - g.x0).abs() < 1 ? g.v0 : _snap(g.v0 + (x - g.x0) / w * 2 * widget.max));
              },
              onHorizontalDragEnd: (_) {
                final v = _live ?? widget.value;
                _grab = null;
                setState(() => _live = null);
                widget.onChange(v);
              },
              onTapUp: (e) => widget.onChange(toDeg(e.localPosition.dx - 4)),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(height: 44, child: CustomPaint(painter: _BarPainter(band: band, fill: (math.min(zero, pos), math.max(zero, pos)), thumb: pos, tick: zero))),
              ),
            ),
          );
        }),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52),
        child: Text('${shown.round() > 0 ? '+' : ''}${shown.round()}°', softWrap: false, textAlign: TextAlign.right, style: AppType.sub.copyWith(color: AppColors.ink, fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}

/// 위치(앞뒤) 막대: 막대 한 폭이 선반 깊이 전체, 왼쪽이 벽 쪽(가장 뒤). 숫자는 가장 뒤에서 앞으로 몇 mm
class _DepthSlider extends StatefulWidget {
  const _DepthSlider({super.key, required this.lo, required this.hi, required this.value, required this.onChange});
  final double lo, hi, value;
  final ValueChanged<double> onChange;

  @override
  State<_DepthSlider> createState() => _DepthSliderState();
}

class _DepthSliderState extends State<_DepthSlider> {
  double? _live;
  double _start = 0;

  @override
  Widget build(BuildContext context) {
    const full = shelfFront + shelfDepth;
    final shown = _live ?? widget.value;
    int mmOf(double z) => math.max(0, ((widget.hi - z) / duPerMm).round());
    return Row(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final w = math.max(1.0, box.maxWidth - 4);
          double xOf(double z) => (1 - (z + shelfFront) / full) * w;
          double toZ(double dx) => (math.max(widget.lo, math.min(widget.hi, _start - dx / w * full)) * 2).roundToDouble() / 2;
          final pos = xOf(shown), back = xOf(widget.hi);
          return Semantics(
            slider: true,
            label: '위치',
            value: '가장 뒤에서 ${mmOf(shown)}밀리미터 앞',
            // 늘이고 줄인 값도 함께(없으면 화면 읽기를 켠 디버그 빌드에서 의미 구조 검사에 걸렸다)
            increasedValue: '가장 뒤에서 ${mmOf(math.max(widget.lo, math.min(widget.hi, widget.value + 10 * duPerMm)))}밀리미터 앞',
            decreasedValue: '가장 뒤에서 ${mmOf(math.max(widget.lo, math.min(widget.hi, widget.value - 10 * duPerMm)))}밀리미터 앞',
            onIncrease: () => widget.onChange(math.max(widget.lo, math.min(widget.hi, widget.value + 10 * duPerMm))),
            onDecrease: () => widget.onChange(math.max(widget.lo, math.min(widget.hi, widget.value - 10 * duPerMm))),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _start = widget.value,
              onHorizontalDragUpdate: (e) => setState(() => _live = toZ(e.localPosition.dx - 4 - xOf(_start))),
              onHorizontalDragEnd: (_) {
                final v = _live;
                setState(() => _live = null);
                if (v != null) widget.onChange(v);
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(height: 44, child: CustomPaint(painter: _BarPainter(band: (back, xOf(widget.lo)), fill: (back, math.max(back, pos)), thumb: pos))),
              ),
            ),
          );
        }),
      ),
      // 글자를 키워도 '22 / mm'처럼 갈리지 않게 값 칸이 글자 폭만큼 넓어진다(2026-11-16 QA 영숙 F7)
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52),
        child: Text('${mmOf(shown)}mm', softWrap: false, textAlign: TextAlign.right, style: AppType.sub.copyWith(color: AppColors.ink, fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}
