// 앱 시작 화면(지금 앱 ui/LoadingScreen과 같은 몫): 켤 때 준비(굽기 셰이더·스킨·예시 책장 읽기)와 첫 책장 굽기 동안 흰 화면만 보이던 것을 바꾼다
// (2026-11-15 QA 지민 F4: 새 설치 첫 실행 8초 넘게 아무 표시 없는 흰 화면).
// 지난번에 굳힌 책장 사진(home_snapshot.png)이 있으면 그 사진을, 없으면 로딩 화면(2026-11-27 사용자 시안 '로그인 화면에서 책장 좀 내리고 맨 밑에
// 책장 여는 중 · 진열 중 · 정리 중, 색상이나 디자인은 로그인 화면이랑 유사하게'): 로그인 화면과 같은 책장 그림 · '책장 한켠' · 두 줄 소개 · 바탕,
// 맨 아래 갈색 원 + 준비 단계 글. 전에는 '느린 계절' 책 그림 + 점 세 개.
// 1단계 '책장을 여는 중'(앱 준비) · 2단계 '책을 진열하는 중'(서재 읽기) · 3단계 '책장을 정리하는 중'(책장 그리기) · 4 다 됨(홈이 첫 책장을 다 그리면 shelfReady)
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart' show loginShelfAsset;
import '../ui/kit.dart';
import '../ui/theme.dart';

/// 준비 단계: 1 앱 준비 · 2 서재 읽기 · 3 책장 그리기 · 4 다 됨
final startStep = ValueNotifier<int>(1);

/// 단계마다 로딩 화면 맨 아래 글(다 된 뒤에는 마지막 글 그대로: 덮개가 걷힐 때 글이 바뀌어 보이지 않게)
String startStepText(int step) => switch (step) { 1 => '책장을 여는 중', 2 => '책을 진열하는 중', _ => '책장을 정리하는 중' };

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

/// 로딩 화면(2026-11-27 사용자 시안): 로그인 화면과 같은 바탕(흰색 → 아래로 회색 기운) · 책장 그림 · '책장 한켠'(hero) · 두 줄 소개(row 회색).
/// 책장은 로그인보다 아래(위 · 아래 남는 높이를 2:3으로 나눠 가운데보다 조금 위), 맨 아래 갈색 원 + 준비 단계 글(startStepText).
/// 화면이 낮으면 그림만 줄어든다(높이의 절반까지)
class StartCover extends StatelessWidget {
  const StartCover({super.key});

  /// 책장 그림(assets/login/shelf.webp) 크기
  static const _art = Size(1080, 1121);

  @override
  Widget build(BuildContext context) => DecoratedBox(
        // 로그인 화면과 같은 색. 책장이 더 아래라 흰색이 그림 아래까지 이어지게 회색은 60%부터
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg, AppColors.bg, AppColors.loginFloor],
            stops: [0, 0.6, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth.isFinite ? c.maxWidth : 400.0, h = c.maxHeight.isFinite ? c.maxHeight : 860.0;
                final artH = (w * _art.height / _art.width).clamp(0.0, h * 0.5);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Spacer(flex: 2),
                  SizedBox(
                    height: artH,
                    child: ExcludeSemantics(child: Image.asset(loginShelfAsset, fit: BoxFit.contain, gaplessPlayback: true)),
                  ),
                  const SizedBox(height: Space.xl),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Semantics(header: true, child: Text('책장 한켠', textAlign: TextAlign.center, style: AppType.hero)),
                      const SizedBox(height: Space.m),
                      WordText('읽은 책을 책장에 진열하고,\n읽은 시간과 문장을 남겨요', textAlign: TextAlign.center, style: AppType.row.copyWith(color: AppColors.inkSoft)),
                    ]),
                  ),
                  const Spacer(flex: 3),
                  // 맨 아래: 갈색 원 + 지금 단계(바뀌면 살짝 겹쳐 바뀐다)
                  ValueListenableBuilder<int>(
                    valueListenable: startStep,
                    builder: (context, step, _) => Semantics(
                      liveRegion: true,
                      label: startStepText(step),
                      excludeSemantics: true,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Spinner(color: AppColors.accent),
                        const SizedBox(width: Space.s),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(startStepText(step), key: ValueKey(startStepText(step)), style: AppType.secondary.copyWith(color: AppColors.inkSoft)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: Space.xxl),
                ]);
              }),
            ),
          ),
        ),
      );
}
