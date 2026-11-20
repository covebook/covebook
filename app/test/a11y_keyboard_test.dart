// 2026-11-16 페르소나 QA(큰 글씨·화면 읽기·키보드) 공통 틀 고침: 키보드 위로 올라오는 화면·시트, 돌아올 때 키보드 안 뜸,
// 화면 읽기 이름 한 번·버튼 역할, 누르는 자리 48, 낱말 단위 줄바꿈, 시트 덮개 한국어, 알림 줄이 탭 바를 덮지 않음
import 'package:chaekjang/main.dart' show KoMaterialLocalizations, appTheme;
import 'package:chaekjang/ui/alert.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 360×640dp 폰(밀도 3)
void phone(WidgetTester t, {double safeBottom = 0}) {
  t.view.physicalSize = const Size(1080, 1920);
  t.view.devicePixelRatio = 3;
  t.view.padding = FakeViewPadding(bottom: safeBottom * 3);
  t.view.viewPadding = FakeViewPadding(bottom: safeBottom * 3);
  addTearDown(t.view.reset);
}

/// 키보드 열기(아래 안전 여백은 키보드에 덮여 0이 된다: 엔진이 padding = viewPadding − viewInsets로 준다)
void keyboard(WidgetTester t, double dp) {
  t.view.viewInsets = FakeViewPadding(bottom: dp * 3);
  t.view.padding = const FakeViewPadding();
}

Rect caretOf(WidgetTester t) {
  final re = t.state<EditableTextState>(find.byType(EditableText)).renderEditable;
  final c = re.getLocalRectForCaret(re.selection!.extent);
  return MatrixUtils.transformRect(re.getTransformTo(null), c);
}

void main() {
  group('키보드(영숙 F1·F13·F14, 현우 F11, 은서 F7)', () {
    testWidgets('밀어 넣은 화면: 위 줄은 내용과 함께 스크롤, 아래 버튼은 화면 아래에 붙고 키보드가 열리면 내용 끝으로(커서 줄은 키보드 위)', (t) async {
      // 2026-11-19 사용자 '이런 고정들 다 없애버려'(위 줄 · 키보드와 함께 쓸 자리) → 11-20 '하단바 이런 거 그냥 고정해':
      // 아래 단추 줄은 키보드가 닫혀 있을 때만 화면 아래에 붙는다(키보드가 열리면 내용 끝이라 쓸 자리를 먹지 않는다)
      phone(t, safeBottom: 24);
      await t.pumpWidget(MaterialApp(
        home: Screen(
          title: '갈피 남기기',
          footer: Btn(label: '갈피 저장', onPress: () {}),
          children: [const SizedBox(height: 400), Field(label: '문장', value: '', multiline: true, onChange: (_) {})],
        ),
      ));
      // 키보드가 닫혀 있으면 버튼은 화면 아래(아래 여백 = 안전 영역 24와 20 중 큰 것)
      expect(t.getRect(find.byType(Btn)).bottom, closeTo(640 - 24, 1));

      await t.tap(find.byType(TextField));
      await t.pump();
      keyboard(t, 300);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), List.generate(16, (i) => '줄 $i 띄어쓰기까지 보며 옮긴다').join('\n'));
      await t.pumpAndSettle();
      final caret = caretOf(t);
      expect(caret.bottom, lessThanOrEqualTo(340));
      expect(caret.top, greaterThan(0));
      // 글을 쓰며 내려가면 위 줄(뒤로)도 같이 올라가 사라진다
      expect(find.bySemanticsLabel('뒤로').hitTestable(), findsNothing);
      // 끝까지 밀면 버튼이 키보드 위에 보인다
      await t.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(Btn)).bottom, lessThanOrEqualTo(340));
      expect(t.takeException(), isNull);
    });

    testWidgets('아래 단추 줄이 있는 화면: 키보드가 열려도 입력칸 초점이 그대로(단추 줄이 내용 끝으로 옮겨도 칸을 새로 만들지 않는다)', (t) async {
      // 2026-11-21 촬영: 감상 쓰기 · 갈피 남기기에서 칸을 누르면 키보드가 뜨자마자 초점이 풀려 글을 쓸 수 없었다
      phone(t, safeBottom: 24);
      await t.pumpWidget(MaterialApp(
        home: Screen(title: '감상 쓰기', footer: Btn(label: '감상 저장', onPress: () {}), children: [Field(label: '감상', value: '', multiline: true, onChange: (_) {})]),
      ));
      await t.tap(find.byType(TextField));
      await t.pump();
      final state = t.state<EditableTextState>(find.byType(EditableText));
      expect(state.widget.focusNode.hasFocus, isTrue);
      keyboard(t, 300);
      await t.pumpAndSettle();
      expect(t.state<EditableTextState>(find.byType(EditableText)), same(state), reason: '같은 칸(새로 만들지 않음)');
      expect(state.widget.focusNode.hasFocus, isTrue);
    });

    testWidgets('탭 화면(Scaffold 안)은 Scaffold가 줄이므로 두 번 비키지 않는다', (t) async {
      phone(t);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: Screen(back: false, title: '내 책', pinFooter: false, footer: Btn(label: '확인', onPress: () {}), children: const [SizedBox(height: 100)])),
      ));
      keyboard(t, 300);
      await t.pumpAndSettle();
      // 스크롤 칸은 키보드 위 340을 다 쓴다(두 번 비키면 40)
      expect(t.getSize(find.byType(SingleChildScrollView)).height, 340);
      expect(t.getRect(find.byType(Btn)).bottom, lessThanOrEqualTo(340));
    });

    testWidgets('시트도 키보드 위로 올라온다', (t) async {
      phone(t);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () => showSheet<void>(ctx, title: '한 줄 후기', builder: (_) => Field(label: '후기', value: '', onChange: (_) {})),
              child: const Text('열기'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      keyboard(t, 300);
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(340));
    });

    testWidgets('다른 화면에서 돌아오면 앞 화면 입력칸이 초점을 되찾지 않는다(키보드가 저절로 뜨지 않음)', (t) async {
      phone(t);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [KeyboardRefocusGuard()],
        home: Screen(title: '책', children: [Field(label: '한 줄 감상', value: '', onChange: (_) {})]),
      ));
      await t.tap(find.byType(TextField));
      await t.pump();
      expect(t.testTextInput.isVisible, isTrue);
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Screen(title: '긴 감상', children: [SizedBox()])));
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isFalse);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isFalse);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>(), isNull);
      // 다시 누르면 평소처럼 키보드가 뜬다
      await t.tap(find.byType(TextField));
      await t.pump();
      expect(t.testTextInput.isVisible, isTrue);
    });

    testWidgets('관찰자가 없으면(전) 돌아올 때 입력칸이 초점을 되찾았다', (t) async {
      phone(t);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Screen(title: '책', children: [Field(label: '한 줄 감상', value: '', onChange: (_) {})]),
      ));
      await t.tap(find.byType(TextField));
      await t.pump();
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Screen(title: '긴 감상', children: [SizedBox()])));
      await t.pumpAndSettle();
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(t.testTextInput.isVisible, isTrue);
    });
  });

  group('화면 읽기(영숙 F9·F10·F11)', () {
    testWidgets('버튼·아이콘 버튼·목록 줄·글자 버튼·거르기 단추: 이름을 한 번만, 그림이 아니라 버튼', (t) async {
      final s = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            Btn(label: '감상 저장', onPress: () {}),
            IconBtn(label: '더 보기', onPress: () {}, child: const LucideIcon('MoreHorizontal')),
            ListItem(label: '백업 및 복원', sub: '기록은 이 기기에 저장돼요', chevron: true, onPress: () {}),
            const ListItem(label: '앱 정보', value: '0.1.0'),
            TextLink(label: '고치기', onPress: () {}),
            FilterButton(label: '모든 책', onPress: () {}),
            Choice(label: '직접 정하기', sub: '10분', selected: true, onPress: () {}),
            const Empty(title: '아직 쓴 감상이 없어요'),
            Btn(label: '감상 쓰기', onPress: () {}),
          ]),
        ),
      ));
      expect(t.getSemantics(find.byType(Btn).first), isSemantics(label: '감상 저장', isButton: true, isImage: false, hasTapAction: true));
      expect(t.getSemantics(find.byType(IconBtn)), isSemantics(label: '더 보기', isButton: true, isImage: false, hasTapAction: true));
      expect(t.getSemantics(find.byType(ListItem).first), isSemantics(label: '백업 및 복원, 기록은 이 기기에 저장돼요', isButton: true, isImage: false, hasTapAction: true));
      expect(t.getSemantics(find.byType(ListItem).last), isSemantics(label: '앱 정보, 0.1.0'));
      expect(t.getSemantics(find.byType(TextLink)), isSemantics(label: '고치기', isButton: true));
      expect(t.getSemantics(find.byType(FilterButton)), isSemantics(label: '모든 책, 바꾸기', isButton: true));
      expect(t.getSemantics(find.byType(Choice)), isSemantics(label: '직접 정하기, 10분', isButton: true, isSelected: true));
      // 빈 화면 글이 옆 버튼 이름에 섞이지 않는다
      expect(t.getSemantics(find.byType(Btn).last), isSemantics(label: '감상 쓰기', isButton: true));
      s.dispose();
    });

    testWidgets('스위치뿐인 줄: 줄 전체가 스위치 하나(이름 한 번), 줄 어디를 눌러도 켜고 끈다', (t) async {
      final s = t.ensureSemantics();
      phone(t);
      var on = true;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, set) => Column(children: [
              ListItem(label: '진동', right: Toggle(label: '진동', value: on, onChange: (v) => set(() => on = v))),
              FilterOption(label: '책장에 없는 책', sub: '3권', right: Toggle(label: '책장에 없는 책', value: false, onChange: (_) {})),
            ]),
          ),
        ),
      ));
      expect(t.getSemantics(find.byType(ListItem)), isSemantics(label: '진동', hasToggledState: true, isToggled: true, hasTapAction: true));
      expect(t.getSemantics(find.byType(FilterOption)), isSemantics(label: '책장에 없는 책, 3권', hasToggledState: true, isToggled: false));
      await t.tap(find.text('진동'));
      await t.pump();
      expect(on, isFalse);
      // 스위치를 직접 눌러도 한 번만 바뀐다
      await t.tap(find.byType(Toggle).first);
      await t.pump();
      expect(on, isTrue);
      s.dispose();
    });

    testWidgets('하단 시트 뒤 덮개는 한국어 \'닫기\'(영어 Scrim 아님)', (t) async {
      final s = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: const [KoMaterialLocalizations.delegate],
        home: Builder(
          builder: (ctx) => Center(child: TextButton(onPressed: () => showSheet<void>(ctx, title: '목표 시간', builder: (_) => const SizedBox(height: 100)), child: const Text('열기'))),
        ),
      ));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Scrim'), findsNothing);
      expect(find.bySemanticsLabel('닫기'), findsWidgets);
      final ko = const KoMaterialLocalizations();
      expect(ko.scrimLabel, '닫기');
      expect(ko.scrimOnTapHint(ko.bottomSheetLabel), '아래 시트 닫기');
      s.dispose();
    });
  });

  group('누르는 자리 48(영숙 F12)', () {
    testWidgets('아이콘 버튼 48, 별은 별마다 48(별 크기는 그대로), 스위치 높이 48', (t) async {
      final s = t.ensureSemantics();
      phone(t);
      int? rating;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (_, set) => Column(mainAxisSize: MainAxisSize.min, children: [
                IconBtn(label: '뒤로', onPress: () {}, child: const LucideIcon('ChevronRight')),
                Stars(value: rating, onChange: (v) => set(() => rating = v)),
                Toggle(label: '진동', value: false, onChange: (_) {}),
              ]),
            ),
          ),
        ),
      ));
      expect(t.getSize(find.byType(IconBtn)), const Size(48, 48));
      final star3 = t.getSemantics(find.bySemanticsLabel('별점 3점')).rect;
      expect(star3.width, greaterThanOrEqualTo(48));
      expect(star3.height, greaterThanOrEqualTo(48));
      expect(t.getSize(find.byType(LucideIcon).at(3)), const Size(24, 24));
      // 별 그림 바깥(위로 20) 눌러도 그 별
      final c = t.getCenter(find.byType(LucideIcon).at(3));
      await t.tapAt(c.translate(0, -20));
      await t.pump();
      expect(rating, 3);
      expect(t.getSize(find.byType(Toggle)).height, 48);
      s.dispose();
    });

    testWidgets('전환 칸은 겉모양 44(2026-11-18 조금 키움), 누르는 자리 52', (t) async {
      phone(t);
      var v = 'a';
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            StatefulBuilder(
              builder: (_, set) => Segmented<String>(items: const [('a', '책 정보'), ('b', '평가')], value: v, onChange: (x) => set(() => v = x)),
            ),
          ]),
        ),
      ));
      final box = t.getRect(find.byType(Segmented<String>));
      expect(box.height, 52);
      // 회색 테두리 위 끝(1dp 안쪽)을 눌러도 바뀐다
      await t.tapAt(Offset(box.right - 40, box.top + 1));
      await t.pump();
      expect(v, 'b');
    });

    testWidgets('밑줄 탭: 탭 사이 간격을 반씩 누르는 자리로(글자 자리는 그대로)', (t) async {
      phone(t);
      var v = 'marks';
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (_, set) => Tabs<String>(items: const [(id: 'marks', label: '갈피'), (id: 'essays', label: '감상')], value: v, gap: Space.xl, onChange: (x) => set(() => v = x)),
            ),
          ),
        ),
      ));
      final a = t.getRect(find.text('갈피')), b = t.getRect(find.text('감상'));
      // 글자 사이 간격은 예전 그대로 28
      expect(b.left - a.right, closeTo(Space.xl, 0.01));
      // 둘 사이 가운데에서 조금 오른쪽을 누르면 '감상'
      await t.tapAt(Offset((a.right + b.left) / 2 + 2, a.center.dy));
      await t.pump();
      expect(v, 'essays');
      expect(t.getSize(find.byType(Tabs<String>)).height, greaterThanOrEqualTo(48));
    });
  });

  group('큰 글씨 낱말 줄바꿈(영숙 F6, 현우 F10, 은서 F16)', () {
    testWidgets('버튼 이름은 낱말 단위로 줄을 바꾸고 버튼이 늘어난다. 찾기·화면 읽기는 원문', (t) async {
      final s = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(child: SizedBox(width: 150, child: Btn(label: '갈피 남기기', onPress: () {}))),
          ),
        ),
      ));
      expect(find.text('갈피 남기기'), findsOneWidget);
      expect(t.getSemantics(find.byType(Btn)), isSemantics(label: '갈피 남기기'));
      final p = t.renderObject<RenderParagraph>(find.descendant(of: find.byType(Btn), matching: find.byType(RichText)));
      final shown = p.text.toPlainText();
      // '남기기'가 한 줄에 다 있다('갈피 남 / 기기'가 아님)
      final start = shown.indexOf('남');
      final end = shown.lastIndexOf('기');
      expect(p.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy, p.getOffsetForCaret(TextPosition(offset: end), Rect.zero).dy);
      expect(t.getSize(find.byType(Btn)).height, greaterThan(54));
      expect(t.takeException(), isNull);
      s.dispose();
    });

    testWidgets('확인창 두 버튼: 한쪽만 두 줄이어도 높이가 같다', (t) async {
      phone(t);
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2)),
          child: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => appAlert(ctx, '쓰던 감상을 버릴까요?', null, [const AlertButton('계속 쓰기', style: AlertStyle.cancel), const AlertButton('버리기', style: AlertStyle.destructive)]),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      final bs = find.byType(Btn);
      expect(bs, findsNWidgets(2));
      expect(t.getSize(bs.first).height, t.getSize(bs.last).height);
      expect(t.takeException(), isNull);
    });

    testWidgets('대체 표지: 로마자 제목을 낱말 가운데서 끊지 않는다(geomeu / n ip)', (t) async {
      phone(t);
      await t.pumpWidget(const MaterialApp(
        // 시험 글꼴은 글자마다 1em 폭이라 실제 명조보다 두 배쯤 넓다: 실제 47dp 표지와 비슷하게 넓은 표지로 본다
        home: Scaffold(body: Center(child: RealCover(title: 'Ip sogui geomeun ip', color: '#5B7594', width: 84))),
      ));
      final p = t.renderObject<RenderParagraph>(find.descendant(of: find.byType(RealCover), matching: find.byType(RichText)));
      final shown = p.text.toPlainText();
      final start = shown.indexOf('geomeun');
      double dy(int i) => p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
      expect(dy(start), dy(start + 'geomeun'.length - 1));
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('맨 아래 브랜드 줄: 끝까지 내리면 제스처 막대(아래 안전 여백) 위에 온다(영숙 F18)', (t) async {
    phone(t, safeBottom: 24);
    await t.pumpWidget(MaterialApp(
      home: Screen(title: '내 정보', children: [for (var i = 0; i < 12; i++) ListItem(label: '줄 $i'), const BrandFooter()]),
    ));
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(t.getRect(find.byType(BrandFooter)).bottom, lessThanOrEqualTo(640 - 24 - Space.section));
  });

  testWidgets('되돌리기 알림 줄은 떠 있는 탭 바 위에 뜬다(탭을 덮지 않음, 현우 F1)', (t) async {
    phone(t, safeBottom: 24);
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      theme: appTheme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Stack(children: [
            Center(
              child: TextButton(
                onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: const Text('책장에서 뺐어요.'),
                  duration: const Duration(seconds: 4),
                  persist: false,
                  action: SnackBarAction(label: '되돌리기', onPressed: () {}),
                )),
                child: const Text('빼기'),
              ),
            ),
            // 탭 바 자리
            Positioned(
              left: TabBarStyle.side,
              right: TabBarStyle.side,
              bottom: 24 + TabBarStyle.gap,
              height: TabBarStyle.height,
              child: GestureDetector(onTap: () => tapped = true, child: const ColoredBox(color: AppColors.white)),
            ),
          ]),
        ),
      ),
    ));
    await t.tap(find.text('빼기'));
    await t.pumpAndSettle();
    final bar = t.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
    expect(bar.bottom, lessThanOrEqualTo(640 - 24 - TabBarStyle.navHeight));
    await t.tapAt(const Offset(180, 640 - 24 - TabBarStyle.gap - TabBarStyle.height / 2));
    expect(tapped, isTrue);
    // persist: false면 정한 시간 뒤 사라진다
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('돌림 목록: 고르지 않은 값도 보조 글자색(옅은 회색 아님, 영숙 F18)', (t) async {
    phone(t);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Center(child: TextButton(onPressed: () => showMinutesSheet(ctx, title: '목표 시간', initial: 10), child: const Text('열기'))),
      ),
    ));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    final other = t.widget<Text>(find.text('5분'));
    expect(other.style!.color, AppColors.inkSoft);
  });
}
