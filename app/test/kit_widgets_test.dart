// 공용 부품이 넘치거나 깨지지 않고 그려지는지(폰 폭 411·큰 글자 1.3배)
import 'package:chaekjang/ui/kit.dart';
import 'package:flutter/material.dart' hide Chip;
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('화면 틀·목록·전환 칸·작은 단추·빈 화면(글자 $scale배)', (t) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      var seg = 'month';
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(411, 891), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Screen(back: false, title: '기록', children: [
              StatefulBuilder(
                builder: (ctx, set) => Segmented<String>(
                  items: const [('month', '월'), ('year', '연도')],
                  value: seg,
                  onChange: (v) => set(() => seg = v),
                ),
              ),
              const H2('읽은 책', first: true),
              ListGroup(title: '묶음', children: [
                ListItem(label: '아주 긴 책 제목이 들어가도 줄을 넘겨 그린다 아주 긴 책 제목', sub: '저자', value: '1시간 20분', onPress: () {}, chevron: true),
                const ListItem(label: '두 번째 줄'),
              ]),
              const SectionBand(),
              // 칩은 없앴다(TDS에 칩 없음): 행동 칩 자리는 작은 weak 단추
              Wrap(spacing: 8, children: [Btn(label: '다시 찍기', kind: 'secondary', size: 'small', onPress: () {}), Btn(label: '사진 빼기', kind: 'secondary', size: 'small', onPress: () {})]),
              FilterButton(label: '모든 책', onPress: () {}),
              FilterButton(label: '2026년', onPress: () {}, active: true),
              Empty(title: '아직 기록이 없어요', body: '읽기 탭에서 시작해 보세요', action: '읽기 시작', onAction: () {}),
              const LucideIcon('Timer'),
            ]),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('기록'), findsOneWidget);
      await t.tap(find.text('연도'));
      await t.pump();
      expect(seg, 'year');
    });
  }

  // 2026-11-26 사용자 '전체적으로 아이콘 같은 라인에 있으면 사이 간격이 큰 거 같아': 나란한 아이콘은 IconRow(가운데 사이 40)
  testWidgets('IconRow: 아이콘 가운데 사이 40, 줄 바깥 끝은 48 칸과 같고, 누르는 칸은 이웃과 나눠 겹치지 않는다', (t) async {
    final hits = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: IconRow(children: [
            for (final n in ['a', 'b', 'c']) IconBtn(label: n, onPress: () => hits.add(n), child: const HeadIcon('Search')),
          ]),
        ),
      ),
    ));
    final row = t.getRect(find.byType(IconRow));
    expect(row.width, iconPitch * 2 + Space.hit, reason: '양끝은 48 칸의 바깥 반(24)을 그대로');
    expect(row.height, Space.hit);
    final icons = [for (var i = 0; i < 3; i++) t.getCenter(find.byType(HeadIcon).at(i))];
    expect(icons[1].dx - icons[0].dx, iconPitch);
    expect(icons[2].dx - icons[1].dx, iconPitch);
    expect(icons[0].dx - row.left, Space.hit / 2);
    expect(row.right - icons[2].dx, Space.hit / 2);
    // 누르는 칸 경계: 두 아이콘 가운데 바로 왼쪽은 앞 단추, 바로 오른쪽은 뒤 단추
    final mid = (icons[0].dx + icons[1].dx) / 2;
    await t.tapAt(Offset(mid - 1, icons[0].dy));
    await t.tapAt(Offset(mid + 1, icons[0].dy));
    await t.tapAt(Offset(row.right - 2, row.top + 2));
    expect(hits, ['a', 'b', 'c']);
    // 줄 밖 단추는 전처럼 48×48
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: IconBtn(label: 'x', onPress: () {}, child: const HeadIcon('Search'))))));
    expect(t.getSize(find.byType(IconBtn)), const Size(Space.hit, Space.hit));
  });
}
