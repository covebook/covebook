// 첫 책 꽂기 안내(2026-11-27 사용자): 꽂기 시트 표지 누르기 · 끌기, 안내 겹(글 · 화살표 자리), 안내 상태 저장, 읽기 탭 첫 안내, 갈피 빈 화면 한 줄
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/features/bookmark/bookmark_empty.dart';
import 'package:chaekjang/features/home/first_book_coach.dart';
import 'package:chaekjang/features/home/place_sheet.dart';
import 'package:chaekjang/features/reading/read_list.dart';
import 'package:chaekjang/store/library_model.dart';
import 'package:chaekjang/store/mini_timer_store.dart' show MiniTimerPlace;
import 'package:chaekjang/store/onboarding_store.dart';
import 'package:chaekjang/ui/kit.dart' show Space;
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

const t1 = '2026-11-16T05:00:00.000Z', t2 = '2026-11-20T05:00:00.000Z';

Library lib({bool read = false}) => Library(
      editions: {
        for (final (id, title) in const [('e1', '가호'), ('e2', '싯다르타')]) id: Edition(id: id, title: title, authors: const ['작가'], source: 'photo', createdAt: t1, updatedAt: t1),
      },
      books: {
        'b1': MyBook(id: 'b1', editionId: 'e1', status: ReadStatus.want, createdAt: t1, updatedAt: t1),
        'b2': MyBook(id: 'b2', editionId: 'e2', status: ReadStatus.want, createdAt: t2, updatedAt: t2),
      },
      sessions: {
        if (read) 's1': Session(id: 's1', startedAt: t1, endedAt: t1, durationMs: 600000, createdAt: t1, updatedAt: t1, myBookId: 'b2'),
      },
    );

/// 기기 키 · 값 저장(sqflite) 대신 빈 결과(안내 상태를 적는 쓰기는 버린다)
void fakeDb() {
  databaseFactory = databaseFactorySqflitePlugin;
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => Directory.systemTemp.path);
  m.setMockMethodCallHandler(const MethodChannel('com.tekartik.sqflite'), (c) async {
    final sql = ((c.arguments as Map?)?['sql'] as String?) ?? '';
    return switch (c.method) {
      'openDatabase' => 1,
      'query' => sql.contains('user_version') ? {'columns': ['user_version'], 'rows': [[10]]} : {'columns': <String>[], 'rows': <List<Object?>>[]},
      _ => null,
    };
  });
}

void main() {
  setUp(fakeDb);
  tearDown(() => Onboarding.instance.reset(loaded: false));

  group('꽂기 시트', () {
    test('들고 온 책(lead)은 책장에 없으면 맨 앞(최근 넣은 책보다 앞)', () {
      final items = placeItems(lib(), const ['b1', 'b2'], (_) => false, lead: 'b1');
      expect([for (final i in items) i.id], ['b1', 'b2']);
      expect([for (final i in placeItems(lib(), const ['b1', 'b2'], (_) => false)) i.id], ['b2', 'b1'], reason: 'lead가 없으면 최근 넣은 책부터');
    });

    Future<({List<String> events, GlobalKey key})> pumpSheet(WidgetTester t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final events = <String>[];
      final key = GlobalKey();
      final l = lib();
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlaceSheet(
                lib: l,
                items: placeItems(l, const ['b1', 'b2'], (_) => false, lead: 'b1'),
                hidden: false,
                onDragStart: (id, g, ui.Image img, s) {
                  events.add('start:$id');
                  img.dispose();
                },
                onDragMove: (_) {},
                onDragEnd: () => events.add('end'),
                onDragCancel: () => events.add('cancel'),
                onList: () => events.add('list'),
                onClose: () => events.add('close'),
                onPlace: (id) => events.add('place:$id'),
                spot: (id: 'b1', key: key),
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      return (events: events, key: key);
    }

    testWidgets('표지를 한 번 누르면 꽂기(끌기 · 들기는 일어나지 않는다)', (t) async {
      final r = await pumpSheet(t);
      await t.tap(find.bySemanticsLabel('가호, 눌러서 꽂거나 위로 끌어 책장에 꽂기'));
      await t.pump(const Duration(milliseconds: 600));
      expect(r.events, ['place:b1']);
    });

    testWidgets('끌면 들기만 하고 누르기로 처리되지 않는다(두 번 꽂히지 않게)', (t) async {
      final r = await pumpSheet(t);
      await t.drag(find.bySemanticsLabel('가호, 눌러서 꽂거나 위로 끌어 책장에 꽂기'), const Offset(0, -200));
      await t.pump(const Duration(milliseconds: 600));
      expect(r.events, ['start:b1', 'end']);
      r.events.clear();
      // 꾹 눌러 들고 놓아도 누르기는 없다
      await t.longPress(find.bySemanticsLabel('싯다르타, 눌러서 꽂거나 위로 끌어 책장에 꽂기'));
      await t.pump(const Duration(milliseconds: 600));
      expect(r.events, ['start:b2', 'end']);
    });

    testWidgets('들고 온 책 표지에 열쇠를 단다(안내 겹이 그 자리를 재어 비운다)', (t) async {
      final r = await pumpSheet(t);
      final box = r.key.currentContext!.findRenderObject()! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final cover = t.getRect(find.descendant(of: find.bySemanticsLabel('가호, 눌러서 꽂거나 위로 끌어 책장에 꽂기'), matching: find.byType(RepaintBoundary)).first);
      expect(rect.left, closeTo(cover.left, 0.5));
      expect(rect.width, closeTo(cover.width, 0.5));
      expect(rect.left, closeTo(Space.page, 0.5), reason: '맨 앞(왼쪽 끝) 표지');
    });
  });

  group('안내 겹 자리', () {
    const screen = Size(360, 800);
    const cover = Rect.fromLTWH(24, 640, 68, 100);
    const text = Size(190, 52);

    test('글은 표지보다 위, 시트 위 끝보다 위, 선반 판 띠와 겹치지 않고 그 위 벽에', () {
      final bands = [(top: 248.0, bottom: 276.0), (top: 425.0, bottom: 452.0), (top: 600.0, bottom: 630.0)];
      final l = coachLayout(screen: screen, target: cover, text: text, top: 80, floor: 562, blocked: bands);
      expect(l.text.bottom, lessThanOrEqualTo(562));
      expect(l.text.bottom, lessThan(cover.top));
      for (final b in bands) {
        expect(l.text.bottom <= b.top || l.text.top >= b.bottom, isTrue, reason: '판 띠 $b와 겹침 ${l.text}');
      }
      // 표지에 가장 가까운 벽(셋째 줄 벽 452~562)
      expect(l.text.top, greaterThanOrEqualTo(452));
      // 표지 오른쪽으로 비켜 화면 안
      expect(l.text.left, greaterThan(cover.right));
      expect(l.text.right, lessThanOrEqualTo(screen.width - Space.page));
      // 화살표: 글 아래에서 표지 오른쪽 위 모서리 바로 바깥으로
      expect(l.from.dy, greaterThan(l.text.bottom));
      expect((l.to - Offset(cover.right, cover.top)).distance, lessThan(Space.l));
    });

    test('작은 화면: 판 사이가 좁으면 그중 넓은 벽 가운데(시트 · 표지는 가리지 않는다)', () {
      final bands = [(top: 300.0, bottom: 330.0), (top: 380.0, bottom: 410.0)];
      final l = coachLayout(screen: const Size(320, 600), target: const Rect.fromLTWH(24, 470, 68, 100), text: const Size(180, 52), top: 70, floor: 420, blocked: bands);
      expect(l.text.bottom, lessThanOrEqualTo(420));
      for (final b in bands) {
        expect(l.text.bottom <= b.top || l.text.top >= b.bottom, isTrue);
      }
      expect(l.text.right, lessThanOrEqualTo(320 - Space.page));
    });

    testWidgets('흰 글 두 줄, 누르기는 아래로 지나간다', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: screen),
          child: Stack(children: [
            Positioned.fill(child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.white))),
            const Positioned.fill(child: FirstBookCoach(target: cover, top: 80, floor: 562)),
          ]),
        ),
      ));
      final txt = find.text(firstBookCoachText);
      expect(txt, findsOneWidget);
      expect(t.widget<Text>(txt).style?.color, AppColors.white);
      await t.tapAt(const Offset(180, 300));
      await t.pump(const Duration(milliseconds: 500));
      await t.tapAt(cover.center);
      await t.pump(const Duration(milliseconds: 500));
      expect(taps, 2);
    });
  });

  group('안내 상태', () {
    test('끝내면 꽂은 책을 적고 다시 안내하지 않는다', () {
      final o = Onboarding.instance..reset(active: true);
      expect(o.active, isTrue);
      o.finish('b1');
      expect(o.active, isFalse);
      expect(o.firstBookId, 'b1');
      // 이미 끝났으면 그대로
      o.finish('b2');
      expect(o.firstBookId, 'b1');
    });
  });

  group('읽기 탭 첫 안내', () {
    Future<void> pump(WidgetTester t, Library l) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      LibraryModel.instance.useForTest(l);
      MiniTimerPlace.instance.setTab('/read');
      await t.pumpWidget(const MediaQuery(data: MediaQueryData(size: Size(360, 800)), child: MaterialApp(home: Scaffold(body: ReadList()))));
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('꽂은 첫 책을 큰 카드로 · 한 줄 안내 · 읽기 시작. 다른 탭으로 가면 본 것으로', (t) async {
      Onboarding.instance.reset(firstBookId: 'b1');
      await pump(t, lib());
      expect(find.text('방금 꽂은 책으로 읽기를 시작해 보세요'), findsOneWidget);
      expect(find.text('읽기 시작'), findsOneWidget);
      expect(find.text('읽기 목록에 추가'), findsNothing, reason: '주요 단추가 둘이 되지 않게 아래는 + 책 추가');
      expect(find.bySemanticsLabel('읽기 목록에 책 추가'), findsOneWidget);
      MiniTimerPlace.instance.setTab('/');
      await t.pump();
      expect(Onboarding.instance.readGuideSeen, isTrue);
      MiniTimerPlace.instance.setTab('/read');
      await t.pump();
      expect(find.text('방금 꽂은 책으로 읽기를 시작해 보세요'), findsNothing);
      expect(find.text('읽기 목록에 추가'), findsOneWidget);
    });

    testWidgets('읽은 기록이 있거나 안내로 꽂은 책이 없으면 안내하지 않는다', (t) async {
      Onboarding.instance.reset(firstBookId: 'b1');
      await pump(t, lib(read: true));
      expect(find.text('방금 꽂은 책으로 읽기를 시작해 보세요'), findsNothing);
      Onboarding.instance.reset();
      await pump(t, lib());
      expect(find.text('방금 꽂은 책으로 읽기를 시작해 보세요'), findsNothing);
      expect(find.text('읽기 목록에 추가'), findsOneWidget);
    });
  });

  testWidgets('갈피 빈 화면: \'책에서 간직하고 싶은 문장을 남겨 보세요\' 한 줄', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MediaQuery(data: const MediaQueryData(size: Size(360, 800)), child: MaterialApp(home: Scaffold(body: BookmarkEmpty(onAdd: () {})))));
    await t.pump(const Duration(milliseconds: 300));
    // 한 줄에 드는지는 실제 글꼴이라 에뮬레이터에서 본다(시험 글꼴은 글자마다 정사각형)
    final line = find.text('책에서 간직하고 싶은 문장을 남겨 보세요');
    expect(line, findsOneWidget);
    expect(t.widget<Text>(line).style?.fontSize, AppType.section.fontSize);
    expect(find.text('첫 갈피를 남겨 보세요'), findsNothing);
    expect(find.text('갈피 남기기'), findsOneWidget);
  });
}
