// 앱 시작 화면(지금 앱 ui/LoadingScreen과 같은 몫): 켤 때 준비(굽기 셰이더·스킨·예시 책장 읽기)와 첫 책장 굽기 동안 흰 화면만 보이던 것을 바꾼다
// (2026-11-15 QA 지민 F4: 새 설치 첫 실행 8초 넘게 아무 표시 없는 흰 화면).
// 지난번에 굳힌 책장 사진(home_snapshot.png)이 있으면 그 사진을, 없으면 '느린 계절' 책이 선반에 선 그림 + '책장 한켠' + 준비 단계 점 세 개를 보인다.
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

/// 시작 그림: 선반 위 책 한 권, 이름, 안내, 준비 단계 점
class StartCover extends StatelessWidget {
  const StartCover({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '책장 한켠, 책장을 준비하고 있어요',
        child: ColoredBox(
          color: AppColors.bg,
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth.isFinite ? c.maxWidth : 400.0;
            final bookW = (w * 0.34).clamp(110.0, 170.0);
            final plankW = bookW * 1.85;
            return Column(children: [
              const Spacer(flex: 5),
              SizedBox(
                width: plankW,
                child: Column(children: [
                  // 책: 앞표지 그림(예시 책장 '느린 계절')에 얇은 그늘
                  Container(
                    width: bookW,
                    decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(2, 4))]),
                    child: ClipRRect(borderRadius: BorderRadius.circular(3), child: Image.asset('assets/reference/night.png', fit: BoxFit.fitWidth)),
                  ),
                  // 선반 판
                  Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFDDC4),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [BoxShadow(color: Color(0x1F5A3B1E), blurRadius: 12, offset: Offset(0, 6))],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 44),
              const Text('책장 한켠', style: TextStyle(fontFamily: AppFonts.uiTitle, fontSize: 30, height: 1.2, color: AppColors.ink)),
              const SizedBox(height: 10),
              const Text('책장을 준비하고 있어요', style: TextStyle(fontFamily: AppFonts.ui, fontSize: 16, height: 1.4, color: AppColors.inkSoft)),
              const SizedBox(height: 22),
              ValueListenableBuilder<int>(
                valueListenable: startStep,
                builder: (context, step, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 1; i <= 3; i++) ...[
                    if (i > 1) const SizedBox(width: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i <= step ? AppColors.ink : AppColors.line),
                    ),
                  ],
                ]),
              ),
              const Spacer(flex: 4),
            ]);
          }),
        ),
      );
}
