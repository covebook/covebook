// 꾸미기 화면 부품(지금 앱 features/home/DecoratePanel.tsx, 2026-10-26 꾸미기 시안을 2026-11-19 사용자 시안으로 바꿈):
// 맨 위 줄 DecorateBar('책 배치 | 선반 | 벽지' 탭, 되돌리기·완료), 아래는 탭마다
//  - 책 배치: 책을 고르기 전 DecorateHint(떠 있는 안내 '책을 하나 골라 주세요'), 고르면 DecoratePanel('위치, 각도 | 디자인' 전환 칸, 2026-11-20 사용자. 이름은 2026-11-23)
//  - 선반·벽지: SkinSheet(선반 색·벽 틀 / 벽지, 고르는 대로 책장에 바로 보인다. 예전 '선반, 벽지' 스토어 화면을 대신한다)
// DecoratePanel: 고른 책 제목, '위치, 각도 | 디자인'. 위치, 각도는 자세 전환 칸(책등·표지·눕힘), 줄마다 '이름 · 막대 · 숫자'(앞뒤 mm, 회전 °),
// 디자인은 책 옆면(단색 | 측면 | 겹무늬, 고른 책에만)과 이 책의 책 꾸미기(그림, 색상, 재질)로 가는 줄.
// 2026-11-23 사용자: 책 옆면은 책마다 따로('가호를 눌러 연 화면이니까 여기서 고른 모양은 가호에만'), 그래서 적용 범위 글('모든 책')을 뺐다.
// 이름도 사용자 정리대로 '움직임 | 겉모습' → '위치, 각도 | 디자인', '실물 측면' → '측면', '표지 이어 쌓기' → '겹무늬', 나열은 쉼표로.
// 기대기는 자세처럼 전환 칸(2026-11-21 사용자 '기대기도 다른 버튼처럼'): 책등 책은 왼쪽 · 바로 · 오른쪽(방향만 고르고 각도는 옆 책과의 틈으로,
// 기댄 각도를 아래 글로), 표지 책은 바로 · 뒤로(벽에 기대기, 사용자 '표지 쪽은 뒤로 기대기가 안 돼': 머리 손잡이를 끌어야만 됐다).
// 막대에는 갈 수 있는 범위를 진한 띠로.
// 막대는 놓을 때 확정한다(끄는 동안은 숫자와 손잡이만 따라간다).
// 2026-11-16 QA 영숙 F7: 큰 글씨에서는 라벨을 따로 줄에 둔다(잘리거나 '위치기대기'로 세로로 섰다).
// 2026-11-18 사용자: '순서' 줄·자리 표시와 안내 글을 뺐다. 한 칸씩 옮기기는 책장 책 칸의 화면 읽기 동작으로 남겼다(home_screen)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/geometry.dart';
import '../../domain/types.dart';
import '../../scene_config/skin.dart';
import '../../scene_config/spine_look.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// 막대 손잡이 원 지름(2026-11-18 사용자 '원 줄이기' 26 → 18). 잡는 칸은 막대 그림 칸 높이(누르는 자리 48, Space.hit)
const _thumb = 18.0, _track = 4.0;

/// 막대 양 끝 안쪽 여백 = 손잡이 반지름 + 2: 끝까지 가도 손잡이가 막대 밖 숫자('193mm')를 덮지 않는다(2026-11-18 사용자)
const _inset = _thumb / 2 + 2;

/// 꾸미기 탭
enum DecorateTab { books, shelf, wall }

/// 꾸미기 맨 위 줄(책장 머리줄 자리, 같은 높이라 들어가고 나와도 책장이 밀리지 않는다): 왼쪽 탭, 오른쪽 되돌리기·완료
class DecorateBar extends StatelessWidget {
  const DecorateBar({super.key, required this.tab, required this.onTab, required this.canUndo, required this.onUndo, required this.onDone});
  final DecorateTab tab;
  final ValueChanged<DecorateTab> onTab;
  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onDone;

  // 책 배치 · 선반 · 벽지는 꾸미기 아래 칸을 통째로 바꾸는 모드라 전환 칸(DESIGN 7장 '전환 칸과 밑줄 탭', 2026-11-20 사용자 '캘린더 분석같이 버튼으로').
  // 되돌리기 · 완료는 전환 칸 오른쪽에 세로 가운데로
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Segmented<DecorateTab>(
            items: const [(DecorateTab.books, '책 배치'), (DecorateTab.shelf, '선반'), (DecorateTab.wall, '벽지')],
            value: tab,
            onChange: onTab,
            // 머리줄 안이라 낮은 칸(회색 칸 36): 옆 되돌리기 · 완료와 높이를 맞춘다(2026-11-20 사용자 '세로 높이 좀 길지 않나')
            compact: true,
          ),
        ),
        const SizedBox(width: Space.l),
        Semantics(
          button: true,
          enabled: canUndo,
          label: '되돌리기',
          onTap: canUndo ? onUndo : null,
          excludeSemantics: true,
          child: Pressable(
            onPress: canUndo ? onUndo : null,
            child: SizedBox(
              height: Space.hit,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LucideIcon('Undo2', size: 20, color: canUndo ? AppColors.inkSoft : AppColors.inkFaint),
                const SizedBox(width: Space.xs),
                Text('되돌리기', softWrap: false, style: AppType.body.copyWith(color: canUndo ? AppColors.inkSoft : AppColors.inkFaint)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: Space.l),
        // 머리줄 '완료'는 본문색 글자 단추(DESIGN 5-1). 이 줄은 폭이 빠듯해 양옆 여백 없이 글자 폭만큼(start), 높이는 누르는 자리 48
        SizedBox(height: Space.hit, child: TextLink(label: '완료', ink: true, start: true, onPress: onDone)),
      ]);
}

/// 아래 칸 공통 겉모양: 흰 바탕, 위 모서리 둥글게, 위 얇은 선, 아래 안전 여백
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child, this.top = Space.l});
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => Container(
        // 큰 글씨에서도 책장이 위에 보이게 높이를 막고 안을 밀어 본다
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet)),
          border: Border(top: BorderSide(color: AppColors.line, width: 0.5)),
        ),
        padding: EdgeInsets.fromLTRB(Space.page + 4, top, Space.page + 4, MediaQuery.paddingOf(context).bottom + 6),
        child: child,
      );
}

/// 책 배치 탭에서 책을 고르기 전: 떠 있는 안내 하나(놓지 못한 까닭이 있으면 그 글).
/// 책 옆면 고르기는 책을 고른 뒤 '디자인'으로 옮겼다(그때 이름은 '겉모습')(2026-11-20 사용자 '책 선택하면 있어야지', '책을 하나 선택하세요 뜬 다음에')
class DecorateHint extends StatelessWidget {
  const DecorateHint({super.key, required this.msg});
  final String? msg;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + Space.xl),
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 2),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(Shape.pill),
                border: Border.all(color: AppColors.line, width: Hairline.of(context)),
                boxShadow: const [Shape.floatShadow],
              ),
              child: Text(msg ?? '책을 하나 골라 주세요', style: AppType.caption.copyWith(color: msg != null ? AppColors.danger : AppColors.ink)),
            ),
          ),
        ),
      );
}

/// 선반·벽지 탭: 고르는 대로 책장에 바로 보인다(실시간 스킨). 저장은 고를 때, 빛 다시 굽기는 꾸미기를 마칠 때(home_screen)
class SkinSheet extends StatelessWidget {
  const SkinSheet({super.key, required this.tab, required this.choice, required this.onPick});
  final DecorateTab tab;
  final SkinChoice choice;
  final ValueChanged<SkinChoice> onPick;

  Widget _section(BuildContext context, String label, Map<String, SkinPart?> table, String value, SkinChoice Function(String k) next) => Padding(
        padding: const EdgeInsets.only(bottom: Space.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 묶음 이름은 꾸미기 시안 모양 그대로(DESIGN 16장 예외)
          Text(label, style: AppType.sub.copyWith(color: AppColors.ink)),
          const SizedBox(height: Space.s),
          // 한 줄 네 칸 폭(칸이 셋이어도 같은 폭으로 왼쪽부터)
          LayoutBuilder(
            builder: (_, box) => Wrap(spacing: Space.s, runSpacing: Space.s, children: [
              for (final e in table.entries)
                if (e.value != null)
                  SizedBox(
                    width: (box.maxWidth - Space.s * 3) / 4,
                    child: Choice(
                      compact: true,
                      label: e.value!.name,
                      selected: value == e.key,
                      onPress: () => onPick(next(e.key)),
                      child: Container(
                        height: 28,
                        margin: const EdgeInsets.only(bottom: Space.s),
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | e.value!.color),
                          borderRadius: BorderRadius.circular(Shape.tag),
                          border: Border.all(color: AppColors.line, width: Hairline.of(context)),
                        ),
                      ),
                    ),
                  ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => _Sheet(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (tab == DecorateTab.shelf) ...[
              _section(context, '선반', plankSkins, choice.plank, (k) => choice.copyWith(plank: k)),
              _section(context, '벽', frameSkins, choice.frame, (k) => choice.copyWith(frame: k)),
            ] else
              _section(context, '벽지', wallSkins, choice.wall, (k) => choice.copyWith(wall: k)),
          ]),
        ),
      );
}

/// 고른 책 조작부의 두 칸: 위치, 각도(자세 · 앞뒤 · 회전/기대기) | 디자인(책 옆면 · 이 책 꾸미기)
enum DecoPart { move, look }

/// 책 배치 탭에서 책을 골랐을 때: 제목, 전환 칸 '위치, 각도 | 디자인', 그 아래 고른 칸의 조작부
/// (2026-11-20 사용자 '각도 같은 움직임, 책 색상이나 표면 측면 같은 거 선택하는 버튼 … 누르면 그 밑에 해당 내용들이 뜨게').
/// 자세(책등 · 표지 · 눕힘)도 전환 칸(2026-11-20 사용자 '눕힘 세움 이런 거 버튼으로 하라 하지 않았나? 통계 캘린더 분석 같은')
class DecoratePanel extends StatefulWidget {
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
    required this.onPose,
    required this.onLean,
    required this.onSpin,
    required this.onDepth,
    required this.spine,
    required this.onSpine,
    required this.onBinding,
    this.bookKey,
    this.leanDeg,
    this.frontBack,
    this.onFrontLean,
  });

  /// 책등 책: 지금 기댄 각도(°, 옆 책과의 틈으로 정해진다)
  final double? leanDeg;

  /// 표지 책: 뒤로 기대 있는지(젖힌 각도가 있으면 '뒤로')
  final bool? frontBack;
  final ValueChanged<bool>? onFrontLean;

  final String title;
  final Pose? pose;
  final int lean;
  final ({bool left, bool right}) canLean;
  final String? msg;

  /// 표지 책: 지금 뒤로 젖힌 각도(머리 손잡이)
  final String? angles;
  final double spin;
  final double spinMax;
  final ({double lo, double hi})? spinRange;
  final ({double lo, double hi, double z, double back})? depth;
  final ValueChanged<Pose> onPose;
  final ValueChanged<int> onLean;
  final ValueChanged<double> onSpin;
  final ValueChanged<double> onDepth;

  /// 고른 책의 옆면 모양(이 책에만): 디자인 칸
  final SpineLook spine;
  final ValueChanged<SpineLook> onSpine;

  /// 이 책의 책 꾸미기(장정 그림, 색상, 재질과 갈피)로. 줄 이름 '이 책 꾸미기', 값 '그림, 색상, 재질'(2026-11-23 사용자 정리)
  final VoidCallback onBinding;

  /// 고른 책이 바뀌면 막대 상태를 새로
  final Object? bookKey;

  @override
  State<DecoratePanel> createState() => _DecoratePanelState();
}

class _DecoratePanelState extends State<DecoratePanel> {
  DecoPart _part = DecoPart.move;

  Widget _move(BuildContext context, bool big) {
    final w = widget, pose = w.pose;
    final turns = pose == Pose.horizontal || pose == Pose.front;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Row(
        label: '자세',
        child: Segmented<Pose>(
          items: [for (final p in const [Pose.upright, Pose.front, Pose.horizontal]) (p, _poseNames[p]!)],
          // 고른 자세가 없으면(아직 못 놓은 책) 책등 칸이 고른 모양
          value: pose ?? Pose.upright,
          onChange: w.onPose,
        ),
      ),
      if (w.depth != null)
        // '위치'는 좌우로 읽혀 '앞뒤'로(2026-11-18 사용자: 옮기면 기대는 각이 바뀌어야 한다고 봄. 이 막대는 앞뒤만 옮긴다)
        _Row(label: '앞뒤', child: _DepthSlider(key: ValueKey(('d', w.bookKey)), lo: w.depth!.lo, hi: w.depth!.hi, back: w.depth!.back, value: w.depth!.z, onChange: w.onDepth)),
      if (turns)
        _Row(label: '회전', child: _SpinSlider(key: ValueKey(('s', w.bookKey, pose)), value: w.spin, max: w.spinMax, range: w.spinRange, onChange: w.onSpin)),
      // 표지 책: 바로 서기 | 뒤 벽에 기대기
      if (pose == Pose.front && w.onFrontLean != null)
        _Row(
          label: '기대기',
          child: Segmented<bool>(items: const [(false, '바로'), (true, '뒤로')], value: w.frontBack ?? false, onChange: w.onFrontLean!),
        ),
      // 책등 책: 왼쪽 · 바로 · 오른쪽(기댈 옆 책이 없는 쪽은 흐리게)
      if (!turns)
        _Row(
          label: '기대기',
          child: Segmented<int>(
            items: [for (final d in const [-1, 0, 1]) (d, _leanNames[d]!)],
            value: pose == Pose.upright ? w.lean : 0,
            disabled: {if (pose != Pose.upright || !w.canLean.left) -1, if (pose != Pose.upright || !w.canLean.right) 1},
            onChange: w.onLean,
          ),
        ),
      if (_angleNote(pose) case final note?)
        Padding(padding: EdgeInsets.only(left: big ? 0 : 48), child: Align(alignment: Alignment.centerLeft, child: Text(note, style: AppType.caption))),
    ]);
  }

  /// 기댄 각도 글: 표지 책은 뒤로 젖힌 각도, 책등 책은 기댄 쪽과 각도(각도는 옆 책과의 틈만큼이라 늘 같지 않다)
  String? _angleNote(Pose? pose) {
    final w = widget;
    if (pose == Pose.front) return w.angles;
    if (pose != Pose.upright || w.lean == 0 || w.leanDeg == null) return null;
    return '${_leanNames[w.lean]}으로 ${w.leanDeg!.round()}° 기대 있어요(옆 책과의 틈만큼 기울어요)';
  }

  Widget _look(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 묶음 이름은 꾸미기 시안 모양(본문색 16 보통, 1c111a7 사용자 시안) 그대로: DESIGN 16장 예외(시트 안 SheetLabel 18 굵게와 다름).
        // 고른 책에만 걸려 적용 범위 글은 없다(2026-11-23 사용자)
        Text('책 옆면', style: AppType.sub.copyWith(color: AppColors.ink)),
        const SizedBox(height: Space.xs),
        Segmented<SpineLook>(
          items: const [(SpineLook.color, '단색'), (SpineLook.photo, '측면'), (SpineLook.stripe, '겹무늬')],
          value: widget.spine,
          onChange: widget.onSpine,
        ),
        const SizedBox(height: Space.s),
        // 그림 · 색상 · 재질 · 갈피는 책 꾸미기(책 정보 › 책 정보 칸 › 책 꾸미기와 같은 화면).
        // '그림, 색상, 재질'은 이름 아래 회색 글: 오른쪽 값으로 두면 360 폭 기본 글씨에서도 '이 책 꾸미기'가 두 줄로 접혔다
        ListItem(label: '이 책 꾸미기', sub: '그림, 색상, 재질', chevron: true, onPress: widget.onBinding),
      ]);

  static const _partNames = {DecoPart.move: '위치, 각도', DecoPart.look: '디자인'};

  @override
  Widget build(BuildContext context) {
    final big = largeText(context);
    final part = Segmented<DecoPart>(compact: !big, items: [for (final e in _partNames.entries) (e.key, e.value)], value: _part, onChange: (v) => setState(() => _part = v));
    return _Sheet(
      top: 0,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(width: 38, height: 4.5, margin: const EdgeInsets.only(top: 10), decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3))),
        ),
        // 제목 줄 오른쪽에 '위치, 각도 | 디자인'(낮은 전환 칸, 2026-11-21 사용자 '움직임 겉모습 버튼 가호랑 같은 라인 우측에', 이름은 2026-11-23).
        // 큰 글씨이거나, 같은 줄에 두면 제목이 세 글자도 안 남을 때(좁은 화면 · 조금 키운 글씨): 제목 두 줄까지, 전환 칸은 아래 줄.
        // 전환 칸 폭은 굵은 '위치, 각도'가 한 칸에 다 들어가게 글자 크기에 맞춘다(152로 두면 잘렸다)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: LayoutBuilder(builder: (context, box) {
            final partW = Segmented.fitWidth(context, _partNames.values);
            final titleMin = MediaQuery.textScalerOf(context).scale(AppType.pageTitle.fontSize! * 3);
            if (big || box.maxWidth - Space.m - partW < titleMin) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(keepAll(widget.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle),
                const SizedBox(height: Space.s),
                part,
              ]);
            }
            return Row(children: [
              Expanded(child: Text(keepAll(widget.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pageTitle)),
              const SizedBox(width: Space.m),
              SizedBox(width: partW, child: part),
            ]);
          }),
        ),
        // 고른 뒤 놓지 못한 까닭: 오류 글(화면 읽기가 바로 읽는다)
        if (widget.msg != null) NoticeText(widget.msg!, error: true),
        // 큰 글씨에서 조작부가 화면보다 길어지면 안에서 밀어 본다
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: Space.m, bottom: 6),
              child: _part == DecoPart.move ? _move(context, big) : _look(context),
            ),
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

const _leanNames = {-1: '왼쪽', 0: '바로', 1: '오른쪽'};

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
          final w = math.max(1.0, box.maxWidth - _inset * 2);
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
                final x = e.localPosition.dx - _inset;
                final v = (x - pos).abs() <= 22 ? shown : toDeg(x);
                _grab = (x0: x, v0: v);
                setState(() => _live = v);
              },
              onHorizontalDragUpdate: (e) {
                final g = _grab;
                if (g == null) return;
                final x = e.localPosition.dx - _inset;
                setState(() => _live = (x - g.x0).abs() < 1 ? g.v0 : _snap(g.v0 + (x - g.x0) / w * 2 * widget.max));
              },
              onHorizontalDragEnd: (_) {
                final v = _live ?? widget.value;
                _grab = null;
                setState(() => _live = null);
                widget.onChange(v);
              },
              onTapUp: (e) => widget.onChange(toDeg(e.localPosition.dx - _inset)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _inset),
                child: SizedBox(height: Space.hit, child: CustomPaint(painter: _BarPainter(band: band, fill: (math.min(zero, pos), math.max(zero, pos)), thumb: pos, tick: zero))),
              ),
            ),
          );
        }),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52),
        child: Text('${shown.round() > 0 ? '+' : ''}${shown.round()}°', softWrap: false, textAlign: TextAlign.right, style: AppType.sub.copyWith(color: AppColors.ink).tnum),
      ),
    ]);
  }
}

/// 앞뒤 막대: 막대 한 폭이 선반 깊이 전체, 왼쪽이 벽 쪽(가장 뒤). 옅은 띠는 실제로 갈 수 있는 범위(옆·뒤 책에 닿는 곳까지),
/// 숫자는 벽 쪽 끝(back)에서 앞으로 몇 mm
class _DepthSlider extends StatefulWidget {
  const _DepthSlider({super.key, required this.lo, required this.hi, required this.back, required this.value, required this.onChange});
  final double lo, hi, back, value;
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
    int mmOf(double z) => math.max(0, ((widget.back - z) / duPerMm).round());
    return Row(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final w = math.max(1.0, box.maxWidth - _inset * 2);
          double xOf(double z) => (1 - (z + shelfFront) / full) * w;
          double toZ(double dx) => (math.max(widget.lo, math.min(widget.hi, _start - dx / w * full)) * 2).roundToDouble() / 2;
          final pos = xOf(shown), back = xOf(widget.hi), wall = xOf(widget.back);
          return Semantics(
            slider: true,
            label: '앞뒤',
            value: '가장 뒤에서 ${mmOf(shown)}밀리미터 앞',
            // 늘이고 줄인 값도 함께(없으면 화면 읽기를 켠 디버그 빌드에서 의미 구조 검사에 걸렸다)
            increasedValue: '가장 뒤에서 ${mmOf(math.max(widget.lo, math.min(widget.hi, widget.value + 10 * duPerMm)))}밀리미터 앞',
            decreasedValue: '가장 뒤에서 ${mmOf(math.max(widget.lo, math.min(widget.hi, widget.value - 10 * duPerMm)))}밀리미터 앞',
            onIncrease: () => widget.onChange(math.max(widget.lo, math.min(widget.hi, widget.value + 10 * duPerMm))),
            onDecrease: () => widget.onChange(math.max(widget.lo, math.min(widget.hi, widget.value - 10 * duPerMm))),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _start = widget.value,
              onHorizontalDragUpdate: (e) => setState(() => _live = toZ(e.localPosition.dx - _inset - xOf(_start))),
              onHorizontalDragEnd: (_) {
                final v = _live;
                setState(() => _live = null);
                if (v != null) widget.onChange(v);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _inset),
                child: SizedBox(height: Space.hit, child: CustomPaint(painter: _BarPainter(band: (back, xOf(widget.lo)), fill: (wall, math.max(wall, pos)), thumb: pos))),
              ),
            ),
          );
        }),
      ),
      // 글자를 키워도 '22 / mm'처럼 갈리지 않게 값 칸이 글자 폭만큼 넓어진다(2026-11-16 QA 영숙 F7)
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52),
        child: Text('${mmOf(shown)}mm', softWrap: false, textAlign: TextAlign.right, style: AppType.sub.copyWith(color: AppColors.ink).tnum),
      ),
    ]);
  }
}

/// 책을 끄는 동안 화면 아래 빼기 자리(2026-11-24 사용자 '책 옮길 때 하단 쪽으로 넣으면 삭제되게, 흰색 x에 주변에 그라데이션').
/// 흰 X 둘레로 어두운 빛이 둥글게 번져 사라진다(단색 원이 아니다). 책이 그 위에 오면 번짐이 짙어지고 X가 커진다.
/// 놓으면 책장에서 뺀다(책은 내 책에 남고 토스트로 되돌린다). 누르는 자리는 없다(끄는 손가락 자리로만 본다)
class RemoveZone extends StatelessWidget {
  const RemoveZone({super.key, required this.active, required this.centerFromBottom});
  final bool active;

  /// 이 칸 아래 끝에서 X 가운데까지
  final double centerFromBottom;

  /// 번지는 빛 지름(누르는 자리 48의 세 배쯤)
  static const _glow = Space.hit * 3;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final speed = reduce ? Duration.zero : const Duration(milliseconds: 140);
    final c = AppColors.toast.withValues(alpha: active ? 0.8 : 0.55);
    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        bottom: centerFromBottom - _glow / 2,
        height: _glow,
        child: Center(
          child: AnimatedContainer(
            duration: speed,
            width: _glow,
            height: _glow,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)], stops: const [0.2, 1]),
            ),
            child: Center(
              child: AnimatedScale(
                duration: speed,
                scale: active ? 1.25 : 1,
                child: const LucideIcon('X', size: IconSize.back, color: AppColors.white, stroke: IconSize.markStroke),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
