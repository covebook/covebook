// 화면 색·글자·크기(지금 앱 ui/theme.ts·ui/tabBar.ts를 옮긴 것). 글자·바탕 회색은 토스 디자인 시스템 단계, 대표색 갈색은 주요 버튼·선택에만
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

abstract final class AppColors {
  static const bg = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const input = Color(0xFFF2F4F6);
  static const surface = Color(0xFFF2F4F6);

  /// 로그인 화면 아래쪽 바탕(위 흰색에서 이 색으로 점점, 회색 기운 도는 흰색. 2026-11-18 시안)
  static const loginFloor = Color(0xFFF1F2F4);
  static const sectionLine = Color(0xFFEFF1F3);
  static const chipOn = Color(0xFF6C534A);
  static const ink = Color(0xFF191F28);
  static const inkSoft = Color(0xFF646F7E);
  static const inkFaint = Color(0xFFB0B8C1);
  static const line = Color(0xFFE5E8EB);
  static const track = Color(0xFFD1D6DB);
  static const accent = Color(0xFF6C534A);
  static const accentPressed = Color(0xFF5A443C);
  static const onAccent = Color(0xFFFFFFFF);
  static const danger = Color(0xFFA5483A);
  static const star = Color(0xFFA8865F);
  static const scrim = Color(0x5C191F28);
  static const iconSoft = Color(0xFF858585);
  static const tabInk = Color(0xFF000000);
  static const tabInkSoft = Color(0xFF787676);
}

/// 글꼴(Pretendard 한 가족, 굵기는 파일로)
abstract final class AppFonts {
  static const ui = 'PretendardRegular';
  static const uiMedium = 'PretendardMedium';
  static const uiBold = 'PretendardSemiBold';
  static const uiTitle = 'PretendardBold';
  /// 갈피 문장·책 표지 같은 내용 글꼴(본명조 Noto Serif KR)
  static const reading = 'ReadingSerif';
  static const serif = 'ReadingSerif';
}

/// 지금 앱(RN Android) 글자 화소 맞춤: 글자 크기는 화소로 올리고(TextAttributeProps: ceil(sp × 밀도)), 줄 높이도 줄마다 화소로 올린다
/// (CustomLineHeightSpan: ceil(줄 높이 × 밀도)). 그대로 두면 17sp 글자가 44.625px(지금 앱 45px)라 줄이 약 0.8% 좁고, 목록 줄마다 0.4dp쯤 짧아 아래로 갈수록 어긋난다.
/// 글자 크기는 앱 뿌리의 RnTextScaler가 모든 Text에 맞추고, 줄 높이는 여기 글자 위계(AppType)에서 맞춘다
/// 지금 화면 밀도(읽을 때마다: 앱이 막 켜질 때는 아직 1.0일 수 있어 한 번만 읽어 두면 맞춤이 꺼진다)
double get _dpr => ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
double rnPx(double dp, [double dpr = 0]) {
  final d = dpr > 0 ? dpr : _dpr;
  return (dp * d - 1e-6).ceil() / d;
}

class RnTextScaler extends TextScaler {
  const RnTextScaler(this.base, this.dpr);
  final TextScaler base;
  final double dpr;
  @override
  double scale(double fontSize) => rnPx(base.scale(fontSize), dpr);
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor;
  @override
  bool operator ==(Object other) => other is RnTextScaler && other.base == base && other.dpr == dpr;
  @override
  int get hashCode => Object.hash(base, dpr);
}

TextStyle _text(String family, double size, double line, Color color) =>
    TextStyle(fontFamily: family, fontSize: size, height: rnPx(line) / rnPx(size), color: color, leadingDistribution: TextLeadingDistribution.even);

const _tab = [FontFeature.tabularFigures()];

/// 글자 위계(토스 TDS): 큰 제목 26 Bold, 시트·묶음 제목 21, 구역 제목 19, 본문 17~18, 보조 16, 작은 메타 15, 아주 작은 표시 13.
/// 화면에서 글자 크기를 직접 쓰지 않는다: 같은 종류 항목은 같은 역할을 쓴다(2026-11-18 사용자 '버튼·글씨 크기·여백·글씨체는 항목에 따라 통일해서 관리').
/// 숫자 역할(figure·display·clock·timer·score)은 숫자 폭이 고정이다
abstract final class AppType {
  /// 아주 큰 숫자(통계 '이번 달 읽은 시간' 48)와 그 단위(22)
  static TextStyle get display => _text(AppFonts.uiTitle, 48, 58, AppColors.ink).copyWith(fontFeatures: _tab);
  static TextStyle get displayUnit => _text(AppFonts.uiMedium, 22, 30, AppColors.ink);
  /// 읽기 장면 시간 64
  static TextStyle get timer => _text(AppFonts.ui, 64, 72, AppColors.ink).copyWith(fontFeatures: _tab);
  /// 큰 시간(독서 끝 · 접은 읽기 장면) 36
  static TextStyle get clock => _text(AppFonts.ui, 36, 44, AppColors.ink).copyWith(fontFeatures: _tab);
  /// 큰 점수(독자 평점 평균) 36
  static TextStyle get score => _text(AppFonts.uiTitle, 36, 44, AppColors.ink).copyWith(fontFeatures: _tab);
  /// 숫자 값(통계 읽은 날 · 독서 횟수, 쪽수) 24
  static TextStyle get figure => _text(AppFonts.uiTitle, 24, 32, AppColors.ink).copyWith(fontFeatures: _tab);
  /// 머리줄 왼쪽 큰 제목(책 추가 · 꾸미기 · 책 정보 제목) 23
  static TextStyle get pageTitle => _text(AppFonts.uiTitle, 23, 30, AppColors.ink);
  static TextStyle get title => _text(AppFonts.uiTitle, 26, 34, AppColors.ink);

  /// 앱 이름처럼 화면에 하나뿐인 큰 이름(로그인 '책장 한켠', 2026-11-18 시안)
  static TextStyle get hero => _text(AppFonts.uiTitle, 32, 40, AppColors.ink);
  static TextStyle get navTitle => _text(AppFonts.uiBold, 18, 25, AppColors.ink);
  static TextStyle get heading => _text(AppFonts.uiBold, 21, 29, AppColors.ink);
  static TextStyle get section => _text(AppFonts.uiBold, 19, 27, AppColors.ink);
  static TextStyle get row => _text(AppFonts.ui, 18, 26, AppColors.ink);
  static TextStyle get rowStrong => _text(AppFonts.uiBold, 18, 26, AppColors.ink);
  static TextStyle get body => _text(AppFonts.ui, 17, 27, AppColors.ink);
  static TextStyle get sub => _text(AppFonts.ui, 16, 23, AppColors.inkSoft);
  static TextStyle get caption => _text(AppFonts.ui, 15, 21, AppColors.inkSoft);
  static TextStyle get button => _text(AppFonts.uiBold, 17, 24, AppColors.ink);
  static TextStyle get label => _text(AppFonts.uiMedium, 16, 22, AppColors.ink);
  /// 굵은 작은 이름(카드 제목 · 닉네임 · 필터 칸) 16
  static TextStyle get labelStrong => _text(AppFonts.uiBold, 16, 22, AppColors.ink);
  /// 작은 본문(진한 16: 체크 이름 · 날짜 칸 · 짧은 글)
  static TextStyle get bodySmall => _text(AppFonts.ui, 16, 22, AppColors.ink);
  /// 작은 단추 글자 16
  static TextStyle get buttonSmall => _text(AppFonts.uiBold, 16, 22, AppColors.ink);
  /// 아주 작은 표시(그래프 눈금 · 배지 · 쓴 날) 13
  static TextStyle get micro => _text(AppFonts.ui, 13, 18, AppColors.inkSoft).copyWith(fontFeatures: _tab);
  /// 갈피 문장(명조) 16 · 긴 글 본문(명조) 17
  static TextStyle get quote => _text(AppFonts.serif, 16, 27, AppColors.ink);
  static TextStyle get reading => _text(AppFonts.reading, 17, 30, AppColors.ink);
  /// 입력창(줄 높이는 플랫폼에 맡긴다)
  static const input = TextStyle(fontFamily: AppFonts.ui, fontSize: 16, color: AppColors.ink);
}

/// 탭 첫 화면 머리줄
abstract final class TabHeader {
  static const paddingTop = 16.0;
  static const paddingBottom = 12.0;
  static const paddingH = 24.0;
  static const minHeight = 64.0;
}

/// 하단 탭 바(알약): 양옆 15, 높이 58, 아래 틈 4, 안쪽 좌우 9, 아이콘 23, 그림자 0 3 14 rgba(25,31,40,.13)
abstract final class TabBarStyle {
  static const height = 58.0;

  /// 탭 바가 차지하는 높이(지금 앱 navigation.height: 알약 + 틈). 작은 타이머·목록 아래 여백의 기준
  static const navHeight = 66.0;

  /// 탭 화면 내용 아래 여백(지금 앱 TAB_CONTENT_PAD)
  static const contentPad = navHeight + 40;
  static const side = 15.0;
  static const gap = 4.0;
  static const paddingX = 9.0;
  static const icon = 23.0;
  static const shadow = BoxShadow(color: Color(0x21191F28), offset: Offset(0, 3), blurRadius: 14);

  /// 홈 화면에서 하단바 위로 벽 색이 옅어지는 높이
  static const fade = 72.0;
}

/// 눌린 표시(아이콘·글자 버튼)
const pressOpacity = 0.55;

/// 지금 앱 boxShadow(CSS: 흐림 반경 = 2σ)를 Flutter 그림자로(Flutter blurRadius r → σ = 0.57735·r + 0.5)
BoxShadow cssShadow(Color color, double dx, double dy, double blur, [double spread = 0]) =>
    BoxShadow(color: color, offset: Offset(dx, dy), blurRadius: blur / 2 <= 0.5 ? 0 : (blur / 2 - 0.5) / 0.57735, spreadRadius: spread);
