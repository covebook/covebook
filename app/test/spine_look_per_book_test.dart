// 책 옆면은 책마다(2026-11-23 사용자 '가호를 눌러 연 화면이니까 여기서 고른 모양은 가호에만'):
// 고른 책만 바뀌고, 따로 고르지 않은 책은 옛 '모든 책' 값(기본값)을 그대로 쓴다
import 'package:chaekjang/scene_config/spine_look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'all_books_select_toast_test.dart' show fakeDb;

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    fakeDb();
  });
  tearDown(() => spineLooks.setForTest(const {}));

  test('고른 책만 그 모양, 나머지는 기본값(옛 모든 책 값)', () {
    spineLooks.setForTest({'gaho': SpineLook.photo}, base: SpineLook.stripe);
    expect(spineLooks.of('gaho'), SpineLook.photo);
    expect(spineLooks.of('other'), SpineLook.stripe);
  });

  test('한 책을 바꾸면 그 책만 바뀌고, 다시 그리라는 알림과 열쇠가 바뀐다', () async {
    spineLooks.setForTest({'gaho': SpineLook.photo});
    final key0 = spineLooks.key;
    var told = 0;
    void listen() => told++;
    spineLooks.addListener(listen);
    addTearDown(() => spineLooks.removeListener(listen));
    await spineLooks.set('other', SpineLook.stripe);
    expect(spineLooks.of('other'), SpineLook.stripe);
    expect(spineLooks.of('gaho'), SpineLook.photo);
    expect(spineLooks.of('third'), SpineLook.color);
    expect(told, 1);
    expect(spineLooks.key, isNot(key0));
  });
}
