// 환불로 잠긴 선반의 표시(A안, B안): 표시만 눌리고 아래의 책은 그대로 눌린다.
// REFUND_MARK_OUT=폴더 로 돌리면 표시만 투명 배경 PNG로 남긴다(책장 화면 그림 위에 얹어 비교하는 용도).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chaekjang/features/home/refunded_shelf_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['REFUND_MARK_OUT'];

void main() {
  setUpAll(() async {
    for (final (family, file) in [('PretendardRegular', 'Pretendard-Regular.otf'), ('PretendardMedium', 'Pretendard-Medium.otf'), ('PretendardSemiBold', 'Pretendard-SemiBold.otf'), ('PretendardBold', 'Pretendard-Bold.otf')]) {
      final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync())));
      await l.load();
    }
  });

  for (final look in RefundedLook.values) {
    testWidgets('환불된 선반 표시 ${look.name}: 표시를 누르면 안내, 그 밖의 자리는 아래 책이 눌린다', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.625;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      var mark = 0, book = 0;
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 384.8,
            height: 200,
            child: Stack(children: [
              // 아래의 책(선반 전체)
              Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => book++)),
              Positioned.fill(child: RepaintBoundary(key: key, child: RefundedShelfMark(look: look, onTap: () => mark++))),
            ]),
          ),
        ),
      ));
      await t.pump();
      // 표시가 없는 자리(왼쪽 아래)는 책이 눌린다
      await t.tapAt(const Offset(20, 180));
      expect((mark, book), (0, 1));
      await t.tap(find.bySemanticsLabel('환불된 선반, 눌러서 안내 보기'));
      await t.pump(const Duration(milliseconds: 300));
      expect((mark, book), (1, 1));
      final out = _out;
      if (out != null) {
        await t.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2.625);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/mark-${look.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
