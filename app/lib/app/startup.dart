// 앱 시작 화면(지금 앱 ui/LoadingScreen과 같은 몫): 켤 때 준비(굽기 셰이더·스킨·예시 책장 읽기)와 첫 책장 굽기 동안 흰 화면만 보이던 것을 바꾼다
// (2026-11-15 QA 지민 F4: 새 설치 첫 실행 8초 넘게 아무 표시 없는 흰 화면).
// 지난번에 굳힌 책장 사진(home_snapshot.png)이 있으면 그 사진을, 없으면 지금 앱 시작 그림('느린 계절' 책이 선반에 선 그림 + '책장 한켠') 위에 준비 단계 점 세 개를 보인다.
// 1단계: 앱 준비 · 2단계: 책장 그리는 중 · 3단계: 다 됨(홈이 첫 책장을 다 그리면 shelfReady를 켠다)
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// 준비 단계(점 세 개 중 채운 수)
final startStep = ValueNotifier<int>(1);

/// 홈이 첫 책장을 다 그렸다(앱 틀의 시작 덮개를 걷는다). 홈 화면이 첫 굽기를 마치면 켠다
final shelfReady = ValueNotifier<bool>(false);

/// 켤 때 지난 책장 사진이 있었는지(있으면 홈이 그 사진을 먼저 보이므로 앱 틀은 덮개를 띄우지 않는다)
bool startedWithSnapshot = false;

/// 화면 폭과 같은 폭으로 찍힌 지난 책장 사진(없거나 폭이 다르면 null: 홈과 같은 규칙)
Future<File?> usableSnapshot(Future<File> Function() file) async {
  try {
    final f = await file();
    if (!f.existsSync()) return null;
    final view = ui.PlatformDispatcher.instance.views.first;
    final bytes = await f.readAsBytes();
    // PNG 머리(IHDR)의 폭: 16~19번째 바이트
    if (bytes.length < 24) return null;
    final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    return w == view.physicalSize.width.ceil() ? f : null;
  } catch (_) {
    return null;
  }
}

/// 앱 준비 동안(runApp 전 단계) 띄우는 뿌리 화면
class StartApp extends StatelessWidget {
  const StartApp({super.key, this.snapshot});
  final File? snapshot;

  @override
  Widget build(BuildContext context) {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final snap = snapshot;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.bg,
        child: snap != null
            ? Align(alignment: Alignment.topLeft, child: Image.file(snap, scale: dpr, filterQuality: FilterQuality.none, gaplessPlayback: true))
            : const StartCover(),
      ),
    );
  }
}

/// 시작 그림(지금 앱 ui/LoadingScreen과 같은 그림 assets/loading/quiet-start.png 853×1844를 가운데 맞춤).
/// 그림에서는 점을 지웠고 준비 단계(startStep)만큼 채운 점 세 개를 그림 위 같은 자리(가운데 426,1286 · 간격 37.5 · 지름 16)에 그린다.
/// 2026-11-16 사용자 '시작 화면 디자인도 바뀐 거 같은데': 그림을 흉내 내 그리던 것을 지금 앱 그림 그대로로 되돌림
class StartCover extends StatelessWidget {
  const StartCover({super.key});

  static const _art = Size(853, 1844);
  static const _dotX = 426.0, _dotY = 1286.0, _gap = 37.5, _d = 16.0;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '책장 한켠, 책장을 준비하고 있어요',
        child: ColoredBox(
          color: AppColors.bg,
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 400.0, h = c.maxHeight.isFinite ? c.maxHeight : 860.0;
            final k = (w / _art.width) < (h / _art.height) ? w / _art.width : h / _art.height;
            final x0 = (w - _art.width * k) / 2, y0 = (h - _art.height * k) / 2;
            final d = _d * k;
            return Stack(children: [
              Positioned(left: x0, top: y0, width: _art.width * k, height: _art.height * k, child: Image.asset('assets/loading/quiet-start.png', fit: BoxFit.fill, gaplessPlayback: true)),
              ValueListenableBuilder<int>(
                valueListenable: startStep,
                builder: (context, step, _) => Stack(children: [
                  for (var i = 0; i < 3; i++)
                    Positioned(
                      left: x0 + (_dotX + (i - 1) * _gap) * k - d / 2,
                      top: y0 + _dotY * k - d / 2,
                      width: d,
                      height: d,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: i < step ? const Color(0xFF7C6253) : const Color(0xFFDBCDC1)),
                      ),
                    ),
                ]),
              ),
            ]);
          }),
        ),
      );
}
