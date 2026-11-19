// 알림함으로 들어가는 길(홈 '내 정보' 아이콘의 새 알림 점, 내 정보의 '알림' 줄) 그림.
// 결제 화면과 동기화 서버가 켜진 빌드에서만 '알림' 줄이 있어서, 두 값을 켜고 돌린다:
//   IAP_SHOTS=1 flutter test test/iap_entry_test.dart --dart-define=IAP=true --dart-define=SYNC_URL=http://localhost
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chaekjang/features/home/home_screen.dart' show headerIconsPreview;
import 'package:chaekjang/features/settings/settings_screen.dart';
import 'package:chaekjang/features/settings/terms.dart' show paidArticles, showTermsSheet, termsArticles;
import 'package:chaekjang/services/sync.dart' show SyncService;
import 'package:chaekjang/store/entitlement_store.dart';
import 'package:chaekjang/ui/kit.dart' show Btn;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _shots = Platform.environment['IAP_SHOTS'] == '1';
const _shotDir = '../docs/screenshots/2026-11-19-iap';
final _root = GlobalKey();

Future<void> _fonts() async {
  for (final (family, file) in [
    ('PretendardRegular', 'Pretendard-Regular.otf'),
    ('PretendardMedium', 'Pretendard-Medium.otf'),
    ('PretendardSemiBold', 'Pretendard-SemiBold.otf'),
    ('PretendardBold', 'Pretendard-Bold.otf'),
  ]) {
    final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync())));
    await l.load();
  }
}

Future<void> _pump(WidgetTester t, Widget home, {double height = 2340}) async {
  t.view.physicalSize = Size(1080, height);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.pumpWidget(RepaintBoundary(key: _root, child: MaterialApp(debugShowCheckedModeBanner: false, home: home)));
  await t.pumpAndSettle();
}

Future<void> _shot(WidgetTester t, String name) async {
  if (!_shots) return;
  await t.runAsync(() async {
    // 아이콘 그림(애셋)이 다 풀린 뒤에 찍는다
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final boundary = _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.625);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_shotDir).createSync(recursive: true);
    File('$_shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final on = iapOn && SyncService.instance.available;
  setUpAll(_fonts);
  tearDown(() => EntitlementStore.instance.setUnread(0));

  testWidgets('홈 머리줄: 새 알림이 있으면 내 정보에 점, 화면 읽기도 알린다', (t) async {
    Widget header(bool unread) => Scaffold(
          backgroundColor: const Color(0xFFF4F3F2),
          body: SafeArea(child: Align(alignment: Alignment.topRight, child: Padding(padding: const EdgeInsets.all(16), child: headerIconsPreview(unread: unread)))),
        );
    await _pump(t, header(false), height: 260);
    expect(find.bySemanticsLabel('내 정보'), findsOneWidget);
    await _pump(t, header(true), height: 260);
    expect(find.bySemanticsLabel('내 정보, 새 알림 있음'), findsOneWidget);
    await _shot(t, '23-header-unread-dot');
  });

  testWidgets('내 정보: 알림 줄에 새 알림 개수', (t) async {
    EntitlementStore.instance.setUnread(1);
    await _pump(t, const SettingsScreen());
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('새 알림 1개'), findsOneWidget);
    await _shot(t, '24-profile-notices-row');
    // 다 읽으면 개수가 사라진다
    EntitlementStore.instance.setUnread(0);
    await t.pumpAndSettle();
    expect(find.text('새 알림 1개'), findsNothing);
  }, skip: !on);

  test('결제를 켠 빌드의 약관: 유료 조가 서비스 변경 조 앞에 들어가고 번호가 이어진다', () {
    final titles = [for (final a in termsArticles) a.$1];
    expect(titles.length, 10 + paidArticles.length);
    expect(titles[6], '제7조 (유료 서비스)');
    expect(titles[10], '제11조 (서비스의 변경과 중단)');
    expect(titles.last, '제14조 (문의)');
    expect(termsArticles[3].$2.last, contains('결제 기록은 관계 법령에 따라'));
  }, skip: !iapOn);

  testWidgets('결제를 켠 빌드의 약관 시트: 유료 서비스 조', (t) async {
    await _pump(t, Builder(builder: (c) => Scaffold(body: Center(child: Btn(label: '열기', onPress: () => showTermsSheet(c))))));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('제7조 (유료 서비스)'), 300, scrollable: find.byType(Scrollable).last);
    // 제7조 제목을 시트 맨 위로
    Scrollable.ensureVisible(t.element(find.text('제7조 (유료 서비스)')));
    await t.pumpAndSettle();
    expect(find.text('제8조 (구독의 자동 갱신과 해지)'), findsOneWidget);
    await _shot(t, '25-terms-paid');
  }, skip: !iapOn);
}
