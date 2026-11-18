// 시험 빌드 전용 프레임 기록(--dart-define=QA_FRAMES=true): 20ms 넘은 프레임의 build(UI)·raster(GPU) 시간을 logcat에 [flframe]으로,
// 2초마다 [flframes] 요약(프레임 수 · 느린 수 · 최대). 출시 빌드에는 꺼져 있다(2026-11-18 사용자: 화면 이동·키보드·책 옮길 때 0.2초씩 끊김)
library;

import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';

import '../store/mini_timer_store.dart';
import 'qa_probe.dart';

const _on = bool.fromEnvironment('QA_FRAMES');

void startFrameLog() {
  if (!_on) return;
  var n = 0, slow = 0, worstBuild = 0, worstRaster = 0;
  var since = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> ts) {
    for (final t in ts) {
      n++;
      final b = t.buildDuration.inMilliseconds, r = t.rasterDuration.inMilliseconds;
      if (b > worstBuild) worstBuild = b;
      if (r > worstRaster) worstRaster = r;
      if (t.totalSpan.inMilliseconds <= 20) qaProbeTotals.clear();
      if (t.totalSpan.inMilliseconds > 20) {
        slow++;
        // 기다림: vsync 늦음(vsync) · build 끝나고 raster 시작까지(queue)
        final vs = t.vsyncOverhead.inMilliseconds;
        final q = (t.timestampInMicroseconds(FramePhase.rasterStart) - t.timestampInMicroseconds(FramePhase.buildFinish)) ~/ 1000;
        // ignore: avoid_print
        print('[flframe] ${MiniTimerPlace.instance.path} build ${b}ms raster ${r}ms vsync ${vs}ms queue ${q}ms total ${t.totalSpan.inMilliseconds}ms');
        final probe = qaProbeTake();
        // ignore: avoid_print
        if (probe.isNotEmpty) print('[flprobe] $probe');
      }
    }
    final now = DateTime.now();
    if (now.difference(since).inMilliseconds >= 2000 && n > 0) {
      // ignore: avoid_print
      print('[flframes] ${MiniTimerPlace.instance.path} frames $n slow $slow worstBuild ${worstBuild}ms worstRaster ${worstRaster}ms');
      n = slow = worstBuild = worstRaster = 0;
      since = now;
    }
  });
}
