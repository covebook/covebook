// 공통 UI 규칙(docs/design/DESIGN.md 9~15장)의 공용 부품 동작: 토스트 · 실패 문구 · 날짜 글자 · 나가기 확인 · 빈 상태 · 탭 맨 위로
import 'dart:async';
import 'dart:io';

import 'package:chaekjang/features/book/labels.dart';
import 'package:chaekjang/services/sync.dart' show ApiError;
import 'package:chaekjang/ui/draft_guard.dart';
import 'package:chaekjang/ui/feedback.dart';
import 'package:chaekjang/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  group('실패 문구 errorText(예외 원문을 보이지 않는다)', () {
    test('연결 문제는 인터넷 안내', () {
      expect(errorText(const SocketException('Failed host lookup: covebook.kodeploy.com')), '인터넷 연결을 확인하고 다시 시도해 주세요.');
      expect(errorText(TimeoutException('x')), '인터넷 연결을 확인하고 다시 시도해 주세요.');
    });
    test('서버 4xx 한국어 메시지는 그대로(마침표), 5xx · 기본 메시지는 잠시 뒤', () {
      expect(errorText(ApiError(400, 'bad', '닉네임이 너무 길어요')), '닉네임이 너무 길어요.');
      expect(errorText(ApiError(500, 'http', '서버 응답 500')), '서버에 잠시 문제가 있어요. 잠시 뒤 다시 시도해 주세요.');
      expect(errorText(ApiError(404, 'http', '서버 응답 404')), '서버에 잠시 문제가 있어요. 잠시 뒤 다시 시도해 주세요.');
    });
    test('앱이 만든 StateError는 그 문장, 그 밖은 잠시 뒤', () {
      expect(errorText(StateError('서버 주소가 설정되지 않았어요')), '서버 주소가 설정되지 않았어요.');
      expect(errorText(const FormatException('Unexpected character')), '잠시 뒤 다시 시도해 주세요.');
      expect(errorText(Exception('PlatformException(boom)')), isNot(contains('PlatformException')));
    });
  });

  group('날짜 글자(DESIGN 4장)', () {
    final now = DateTime(2026, 11, 19, 20);
    test('가까운 날', () {
      expect(relativeDay(DateTime(2026, 11, 19, 1), now: now), '오늘');
      expect(relativeDay(DateTime(2026, 11, 18, 23), now: now), '어제');
      expect(relativeDay(DateTime(2026, 11, 16, 9), now: now), '3일 전');
      expect(relativeDay(DateTime(2026, 11, 1, 9), now: now), '11월 1일');
      expect(relativeDay(DateTime(2025, 11, 1, 9), now: now), '2025년 11월 1일');
    });
    test('날과 시각: 며칠 전이어도 시각만 보이지 않는다', () {
      expect(dateTimeLabel(DateTime(2026, 11, 19, 21, 5), now: now), '오늘 오후 9:05');
      expect(dateTimeLabel(DateTime(2026, 11, 18, 9, 5), now: now), '어제 오전 9:05');
      expect(dateTimeLabel(DateTime(2026, 11, 15, 0, 30), now: now), '11월 15일 오전 12:30');
    });
    test('날짜 사이와 시각 칸', () {
      expect(dateRange('2026-11-05', '2026-11-14'), contains(' ~ '));
      expect(dateRange('2026-11-05', '2026-11-05'), isNot(contains('~')));
      expect(hmLabel('21:05'), '오후 9:05');
      expect(hmLabel('00:00'), '오전 12:00');
      expect(hmLabel('12:30'), '오후 12:30');
    });
  });

  group('토스트(DESIGN 14장)', () {
    testWidgets('밀어 넣은 화면 위에서도 보이고, 되돌리기를 누르면 부르고 걷힌다', (t) async {
      var undone = 0;
      await t.pumpWidget(_app(Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
              builder: (c2) => Material(child: Center(child: TextButton(onPressed: () => showToast(c2, '책장에서 뺐어요.', action: '되돌리기', onAction: () => undone++), child: const Text('빼기')))),
            )),
            child: const Text('열기'),
          ),
        ),
      )));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
      await t.tap(find.text('빼기'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('책장에서 뺐어요.'), findsOneWidget);
      await t.tap(find.text('되돌리기'));
      await t.pump(const Duration(milliseconds: 300));
      expect(undone, 1);
      expect(find.text('책장에서 뺐어요.'), findsNothing);
    });

    testWidgets('화면 아래 단추 줄(ToastAvoid)이 보이면 토스트는 그 위에 뜬다(책 공유 사진 저장, 2026-11-20)', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return Material(
          child: Column(children: [
            const Expanded(child: SizedBox()),
            ToastAvoid(child: const SizedBox(height: 120, child: Center(child: Text('사진 저장')))),
          ]),
        );
      })));
      showToast(ctx, '사진첩에 저장했어요.');
      await t.pump(const Duration(milliseconds: 300));
      final toast = t.getRect(find.text('사진첩에 저장했어요.'));
      final footer = t.getRect(find.byType(ToastAvoid));
      expect(toast.bottom, lessThanOrEqualTo(footer.top));
    });

    testWidgets('되돌리기 없는 토스트는 2.5초 뒤 사라지고, 새 토스트는 앞 것을 바로 걷는다', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      showToast(ctx, '삭제했어요.');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('삭제했어요.'), findsOneWidget);
      showToast(ctx, '복사했어요.');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('삭제했어요.'), findsNothing);
      expect(find.text('복사했어요.'), findsOneWidget);
      // 시간은 화면이 넘어간 프레임으로 센다(프레임마다 0.1초씩)
      for (var i = 0; i < (toastShort.inMilliseconds + 400) ~/ 100; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('복사했어요.'), findsNothing);
    });

    testWidgets('화면이 몇 초 멈춘 동안은 토스트 시간에 넣지 않는다(책장 굽는 동안 그려지지도 않고 걷혔다)', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(_app(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      showToast(ctx, '2권을 책장에 진열했어요.');
      await t.pump();
      // 한 프레임이 5초 걸림(GPU가 책장을 굽는 동안)
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('2권을 책장에 진열했어요.'), findsOneWidget);
      for (var i = 0; i < (toastShort.inMilliseconds + 400) ~/ 100; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('2권을 책장에 진열했어요.'), findsNothing);
    });
  });

  group('나가기 확인(DESIGN 12장)', () {
    Future<void> open(WidgetTester t, Widget screen) async {
      await t.pumpWidget(_app(Builder(
        builder: (c) => Center(child: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => screen)), child: const Text('열기'))),
      )));
      await t.tap(find.text('열기'));
      await t.pumpAndSettle();
    }

    testWidgets('고친 것이 있으면 묻고, 계속 수정은 머물고, 버리기는 나간다', (t) async {
      await open(t, DraftGuard.edit(dirty: () => true, child: const Scaffold(body: Text('수정 화면'))));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('고친 내용을 버릴까요?'), findsOneWidget);
      await t.tap(find.text('계속 수정'));
      await t.pumpAndSettle();
      expect(find.text('수정 화면'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await t.tap(find.text('버리기'));
      await t.pumpAndSettle();
      expect(find.text('수정 화면'), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('바꾼 것이 없으면 묻지 않고 돌아간다', (t) async {
      await open(t, DraftGuard(dirty: () => false, child: const Scaffold(body: Text('쓰기 화면'))));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('쓰던 내용을 버릴까요?'), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });
  });

  group('상태 부품(DESIGN 11장)', () {
    testWidgets('화면 전체 실패: 제목은 머리, 다시 시도는 secondary 단추', (t) async {
      var retried = 0;
      await t.pumpWidget(_app(Scaffold(body: Empty(title: '목록을 불러오지 못했어요', body: errorText(const SocketException('x')), action: '다시 시도', actionKind: 'secondary', onAction: () => retried++))));
      expect(find.text('인터넷 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
      await t.tap(find.text('다시 시도'));
      expect(retried, 1);
    });

    testWidgets('구역 빈 줄과 구역 실패의 글자 단추', (t) async {
      var retried = 0;
      await t.pumpWidget(_app(Scaffold(body: Column(children: [const EmptyLine('아직 남긴 갈피가 없어요'), EmptyLine('후기를 불러오지 못했어요', action: '다시 시도', onAction: () => retried++)]))));
      expect(find.text('아직 남긴 갈피가 없어요'), findsOneWidget);
      await t.tap(find.text('다시 시도'));
      expect(retried, 1);
    });

    testWidgets('불러오는 중은 글이 없어도 화면 읽기 이름이 있다', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_app(const Scaffold(body: Loading())));
      expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
      h.dispose();
    });
  });

  group('누르는 자리 48(DESIGN 15장)', () {
    testWidgets('구역 링크 · 거르기 단추 · 작은 단추(칩 자리)', (t) async {
      await t.pumpWidget(_app(Scaffold(
        body: Column(children: [
          SectionHead(title: '독서 기록', link: '전체 보기', onLink: () {}, chevron: true),
          FilterButton(label: '모든 책', onPress: () {}),
          Btn(label: '다시 찍기', kind: 'secondary', size: 'small', onPress: () {}),
        ]),
      )));
      expect(t.getSize(find.ancestor(of: find.text('전체 보기'), matching: find.byType(ConstrainedBox)).first).height, greaterThanOrEqualTo(Space.hit));
      expect(t.getSize(find.byType(FilterButton)).height, greaterThanOrEqualTo(Space.hit));
      expect(t.getSize(find.byType(Btn)).height, greaterThanOrEqualTo(Space.hit));
    });
  });

  group('탭 맨 위로(DESIGN 10장)', () {
    for (final scroll in [true, false]) {
      testWidgets('탭이 준 스크롤을 화면 틀이 쓴다(scroll: $scroll)', (t) async {
        final c = ScrollController();
        await t.pumpWidget(_app(PrimaryScrollController(
          controller: c,
          child: Screen(
            back: false,
            title: '기록',
            scroll: scroll,
            children: [
              if (scroll) for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('줄 $i')) else Expanded(child: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('줄 $i'))])),
            ],
          ),
        )));
        await t.drag(find.text('줄 3'), const Offset(0, -600));
        await t.pumpAndSettle();
        expect(c.hasClients, isTrue);
        expect(c.offset, greaterThan(0));
        c.jumpTo(0);
        await t.pumpAndSettle();
        expect(find.text('기록'), findsOneWidget);
      });
    }
  });
}
