// 2026-11-21 비교 아티팩트 댓글 반영 시험: 책 정보 수정 표지 높이, 확인창 아래 '취소', 고르는 칸 덧붙임 글자, 입력칸 높이
import 'dart:math' as math;

import 'package:chaekjang/domain/layout.dart';
import 'package:chaekjang/domain/layout_engine.dart';
import 'package:chaekjang/domain/types.dart';
import 'package:chaekjang/features/bookmark/bookmark_tape.dart' show WashiStrip;
import 'package:chaekjang/features/bookmark/paper_grain.dart' show tapeStrip;
import 'package:chaekjang/features/bookmark/photo_plate.dart' show PhotoPlate;
import 'package:chaekjang/features/reading/mini_timer.dart' show miniTimerWidth, miniTimerPad;
import 'package:chaekjang/store/mini_timer_store.dart' show miniTimerSize;
import 'package:chaekjang/store/library_store.dart' show saveLayout;
import 'package:chaekjang/store/placement_store.dart';
import 'package:chaekjang/ui/alert.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('책 정보 수정 표지 높이 = 옆 제목 · 저자 두 칸(이름 줄 + 입력칸, 사이 Space.xl)', () {
    expect(CoverSize.editHeight, 2 * (TypeSpecs.label.line + Space.s + ControlSize.field) + Space.xl);
    expect(CoverSize.edit / CoverSize.ratio, closeTo(CoverSize.editHeight, 0.001));
  });

  testWidgets('입력칸(Field) 한 줄 높이는 ControlSize.field 48', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: Field(label: '쪽수', value: '', unit: '쪽', onChange: (_) {})))));
    final box = find.descendant(of: find.byType(Field), matching: find.byType(Container)).first;
    expect(ControlSize.field, 48);
    expect(t.getSize(box).height, ControlSize.field);
  });

  testWidgets('고르는 칸: 책 이름 옆 저자는 세로선 없이 작은 회색 글자', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 320, child: SelectField(label: '책', placeholder: '', value: '가호', sub: '무라카미 하루키', onPress: () {})))));
    expect(find.textContaining('|'), findsNothing);
    final sub = t.widget<Text>(find.text('무라카미 하루키'));
    expect(sub.style?.fontSize, AppType.caption.fontSize);
    expect(sub.style?.color, AppColors.inkSoft);
  });

  testWidgets('회색 글자 단추(SubAction · TextLink soft)는 작고 보통 굵기 sub 15, 갈색 글자 단추는 link 17', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SubAction(label: '장정 직접 고르기', onPress: () {}),
          TextLink(label: '저장', onPress: () {}),
        ]),
      ),
    ));
    TextStyle? styleOf(String s) => t.widget<RichText>(find.descendant(of: find.text(s), matching: find.byType(RichText)).first).text.style;
    final sub = styleOf('장정 직접 고르기');
    expect(sub?.fontSize, AppType.sub.fontSize);
    expect(sub?.fontFamily, AppType.sub.fontFamily);
    expect(sub?.color, AppColors.inkSoft);
    expect(styleOf('저장')?.fontSize, AppType.link.fontSize);
  });

  testWidgets('행동 둘 + 취소 확인창: 아래 취소는 SubAction, 보이는 글자 아래 여백은 Space.page', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () => appAlert(ctx, '지난 독서가 중간에 멈췄어요', '앱이 꺼져 있던 1분도 넣을까요?', [
              const AlertButton('넣기'),
              const AlertButton('빼기'),
              const AlertButton('나중에 정하기', style: AlertStyle.cancel),
            ]),
            child: const Text('열기'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(SubAction, '나중에 정하기'), findsOneWidget);
    expect(find.byType(Btn), findsNWidgets(2));
    // 창 판(Material) 아래 끝과 '나중에 정하기' 글자 줄 아래 끝 사이
    final card = t.getRect(find.ancestor(of: find.text('넣기'), matching: find.byType(Material)).first);
    final text = t.getRect(find.text('나중에 정하기'));
    expect(card.bottom - text.bottom, closeTo(Space.page, 1.5));
    await t.tap(find.text('나중에 정하기'));
    await t.pumpAndSettle();
    expect(find.text('나중에 정하기'), findsNothing);
  });

  test('배치 되돌리기는 여러 번: 확정한 차례 거꾸로 한 번에 하나씩', () async {
    final p = PlacementStore.instance;
    addTearDown(() => p.writeLayout = saveLayout);
    p.writeLayout = (_, _) async {};
    // 선반 수로 배치를 구별한다(확정은 홈 최소 선반 수까지 채우므로 그보다 많게)
    ShelfLayout shelves(int n) => ShelfLayout([for (var i = 0; i < n; i++) Shelf('s$i', i)], const []);
    p.layout = shelves(homeShelfCount + 1);
    p.books = {};
    expect(await p.commit(shelves(homeShelfCount + 2)), isTrue);
    expect(await p.commit(shelves(homeShelfCount + 3)), isTrue);
    expect(p.layout!.shelves.length, homeShelfCount + 3);
    expect(await p.undo(), isTrue);
    expect(p.layout!.shelves.length, homeShelfCount + 2);
    expect(p.canUndo, isTrue);
    expect(await p.undo(), isTrue);
    expect(p.layout!.shelves.length, homeShelfCount + 1);
    expect(p.canUndo, isFalse);
  });

  test('표지 책 기대기: 뒤로는 벽에 기대고(젖힘 > 0), 바로는 젖힘 0으로 선다', () {
    final BookMap books = {
      'b01': Book(id: 'b01', title: '모순', dims: BookDims(149.7, 27, 114)),
      'b02': Book(id: 'b02', title: '데미안', dims: BookDims(170, 34.8, 118)),
    };
    const start = ShelfLayout([Shelf('shelf-1', 0), Shelf('shelf-2', 1), Shelf('shelf-3', 2)], [
      BookPlacement(bookId: 'b01', shelfId: 'shelf-1', order: 0, pose: Pose.upright, tilt: 0),
      BookPlacement(bookId: 'b02', shelfId: 'shelf-1', order: 1, pose: Pose.upright, tilt: 0),
    ]);
    final front = setPose(start, books, 'b02', Pose.front);
    expect(front.ok, isTrue);
    double pitch(ShelfLayout l) => frontStateOf(l, books, 'b02')!.state.pitch;
    expect(pitch(front.layout!), greaterThan(0.5), reason: '표지로 세우면 처음엔 벽에 기대 선다');
    final straight = setFrontLean(front.layout!, books, 'b02', false);
    expect(straight.ok, isTrue);
    expect(pitch(straight.layout!), lessThan(0.5));
    final back = setFrontLean(straight.layout!, books, 'b02', true);
    expect(back.ok, isTrue);
    expect(pitch(back.layout!), greaterThan(0.5));
  });

  test('작은 타이머 폭은 시간 글자만큼 늘어난다(1:03:26 · 11:03:25 · 100:00:00), 원보다 좁지 않고 1초마다 흔들리지 않는다', () {
    const one = TextScaler.noScaling;
    double w(String s, [double max = 1000, TextScaler sc = one]) => miniTimerWidth(s, sc, max);
    // 같은 자릿수면 숫자가 달라도 같은 폭(고정 폭 숫자로 잰다)
    expect(w('1:03:26'), w('9:59:59'));
    expect(w('11:03:25'), w('10:00:00'));
    // 자릿수가 늘면 넓어진다
    expect(w('11:03:25'), greaterThan(w('1:03:26')));
    expect(w('100:00:00'), greaterThan(w('11:03:25')));
    // 글자 폭 + 양쪽 여백
    final p = TextPainter(text: TextSpan(text: '00:00:00', style: AppType.labelStrong.tnum), textDirection: TextDirection.ltr)..layout();
    expect(w('11:03:25'), (p.width + 2 * miniTimerPad).ceilToDouble());
    p.dispose();
    // 아주 작은 글자도 원(56)보다 좁지 않고, 화면 폭 한도는 넘지 않는다
    expect(w('03:27', 1000, const TextScaler.linear(0.1)), miniTimerSize);
    expect(w('100:00:00', 90), 90);
    // 큰 글씨면 더 넓어진다(줄이지 않는다)
    expect(w('1:03:26', 1000, const TextScaler.linear(1.5)), greaterThan(w('1:03:26')));
  });

  test('사진 테이프 띠: 일부러 틀어 붙인 각도(5~9°, 오른쪽이 올라감), 씨앗마다 같고 사진마다 조금 다르다', () {
    final a = tapeStrip('bm1-washi', 92, 30), b = tapeStrip('bm1-washi', 92, 30), c = tapeStrip('bm2-washi', 92, 30);
    expect(a.angle, b.angle);
    expect(a.outline, b.outline);
    for (final s in [a, c, tapeStrip('new-washi', 92, 30), tapeStrip('x-washi', 62, 20)]) {
      expect(s.angle, inInclusiveRange(-9, -5));
      expect(s.shift.abs(), lessThanOrEqualTo(92 * .05));
      expect(s.fringe, isNotEmpty);
    }
    expect(a.outline == c.outline && a.angle == c.angle, isFalse);
  });

  testWidgets('사진 갈피 테이프는 한지 띠(WashiStrip)를 그 각도로 돌려 붙인다', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: PhotoPlate(uri: '/nope.jpg', width: 220, seed: 'bm1')))));
    expect(find.byType(WashiStrip), findsOneWidget);
    final rot = t.widget<Transform>(find.ancestor(of: find.byType(WashiStrip), matching: find.byType(Transform)).first);
    final angle = math.atan2(rot.transform.entry(1, 0), rot.transform.entry(0, 0)) * 180 / math.pi;
    expect(angle, closeTo(tapeStrip('bm1-washi', 92, 30).angle, 0.01));
    expect(t.takeException(), isNull);
  });
}
