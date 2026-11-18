// 첫 진입 멈춤 줄이기(2026-11-18 사용자: 기록 탭·갈피 추가로 갈 때 0.2초씩 끊긴다).
// 큰 한글 글꼴(본명조 Noto Serif KR 3.2MB, 마루부리 3.2MB)은 처음 쓰는 순간 UI 스레드에서 파일을 읽고 해석한다.
// 에뮬레이터 측정: 기록 탭(갈피 카드가 본명조) 첫 진입 한 프레임 build 158ms. 앱이 뜨고 쉬는 동안 글꼴마다 한 프레임씩
// 짧은 글을 배치해 미리 읽어 둔다(한 프레임에 하나씩이라 그 사이 화면은 멈추지 않는다)
library;

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import '../ui/theme.dart';

/// 처음 화면에서 쓰지 않아 나중에 처음 읽히는 글꼴(책장 첫 화면의 Pretendard·Hahmlet은 이미 읽혀 있다)
const _lateFonts = [AppFonts.serif, 'MaruBuriRegular', 'MaruBuriSemiBold'];

/// 이 시각 이후 글꼴을 미리 읽는다(시험 빌드 측정에서 미리 읽기 전/후를 가르는 데도 쓴다)
DateTime? fontWarmAt;

void warmFontsLater({Duration after = const Duration(seconds: 3)}) {
  // 글꼴 하나 읽기도 UI를 잠깐 멈춘다(에뮬레이터 약 0.5초): 손이 1.5초 넘게 쉬고 있을 때만 하나씩 읽는다
  var lastTouch = DateTime.now();
  void touched(PointerEvent e) => lastTouch = DateTime.now();
  GestureBinding.instance.pointerRouter.addGlobalRoute(touched);
  SchedulerBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(after, () async {
      fontWarmAt = DateTime.now();
      for (final f in _lateFonts) {
        while (DateTime.now().difference(lastTouch) < const Duration(milliseconds: 1500)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await SchedulerBinding.instance.endOfFrame;
        final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: f, fontSize: 16))..addText('책장 한켠 갈피 감상 가나다 0123 Abc');
        b.build().layout(const ui.ParagraphConstraints(width: 400));
      }
      GestureBinding.instance.pointerRouter.removeGlobalRoute(touched);
      // ignore: avoid_print
      if (const bool.fromEnvironment('QA_FRAMES')) print('[flwarm] fonts ${DateTime.now().difference(fontWarmAt!).inMilliseconds}ms');
    });
  });
}
