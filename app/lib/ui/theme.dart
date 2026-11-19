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
  // 로그인 화면 아래쪽 회색(2026-11-18 사용자 '하단 그라데이션 좀 더 진하게': F1F2F4 → E4E7EB)
  static const loginFloor = Color(0xFFE4E7EB);
  static const sectionLine = Color(0xFFEFF1F3);
  static const chipOn = Color(0xFF6C534A);
  static const ink = Color(0xFF191F28);
  static const inkSoft = Color(0xFF646F7E);
  static const inkFaint = Color(0xFFB0B8C1);
  static const line = Color(0xFFE5E8EB);
  static const track = Color(0xFFD1D6DB);

  /// 정보 사이 세로줄(가운데 점 대신, 2026-11-18): 글자보다 옅고 흰·회색 바탕 모두에서 보이는 회색
  static const metaBar = Color(0xFFC9CED4);
  static const accent = Color(0xFF6C534A);
  static const accentPressed = Color(0xFF5A443C);
  static const onAccent = Color(0xFFFFFFFF);
  static const danger = Color(0xFFA5483A);
  static const star = Color(0xFFA8865F);
  static const scrim = Color(0x5C191F28);
  static const tabInk = Color(0xFF000000);
  static const tabInkSoft = Color(0xFF787676);

  /// 토스트(짧은 알림) 바탕: 본문색보다 조금 밝은 먹색(흰 화면 · 책장 장면 위 모두에서 보인다). 글자는 흰색
  static const toast = Color(0xFF2B323C);
  static const onToast = Color(0xFFFFFFFF);

  /// 이름 → (값, 쓰임). 토큰 내보내기 · 검사용(test/design_tokens_test.dart). 색을 더하면 여기에도 넣는다
  static const all = <String, (Color, String)>{
    'bg': (bg, '화면 바탕'),
    'white': (white, '카드 · 칩 위 흰색'),
    'input': (input, '입력칸 바탕'),
    'surface': (surface, '옅은 회색 면(칩 · 전환 칸 · 표지 자리)'),
    'loginFloor': (loginFloor, '로그인 화면 아래쪽'),
    'sectionLine': (sectionLine, '묶음 사이 띠'),
    'chipOn': (chipOn, '고른 칩'),
    'ink': (ink, '본문 · 제목'),
    'inkSoft': (inkSoft, '보조 글자 · 머리줄 아이콘 · 꺾쇠'),
    'inkFaint': (inkFaint, '흐린 글자 · 빈 칸 안내'),
    'line': (line, '구분선 · 테두리'),
    'track': (track, '막대 · 손잡이 자리'),
    'metaBar': (metaBar, '정보 사이 세로줄(|)'),
    'accent': (accent, '주요 단추 · 고른 것(갈색)'),
    'accentPressed': (accentPressed, '주요 단추 눌림'),
    'onAccent': (onAccent, '갈색 위 글자'),
    'danger': (danger, '삭제 · 오류'),
    'star': (star, '별점'),
    'scrim': (scrim, '시트 · 확인창 뒤 막'),
    'tabInk': (tabInk, '하단 탭 고른 아이콘'),
    'tabInkSoft': (tabInkSoft, '하단 탭 안 고른 아이콘'),
    'toast': (toast, '토스트(짧은 알림) 바탕'),
    'onToast': (onToast, '토스트 글자'),
  };
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

/// 글자 역할 하나의 값: 글꼴 · 크기 · 줄 높이(dp) · 색 · 숫자 폭 고정. 값은 [TypeSpecs]에서만 정한다
class TypeSpec {
  const TypeSpec(this.family, this.size, this.line, {this.color = AppColors.ink, this.tabular = false});
  final String family;
  final double size, line;
  final Color color;
  final bool tabular;

  TextStyle get style {
    final s = _text(family, size, line, color);
    return tabular ? s.copyWith(fontFeatures: _tab) : s;
  }
}

/// 글자 역할 값(유일한 정의). 화면은 [AppType]으로 쓰고, 시안용 토큰(design-system/tokens.json · web/styles.css)은
/// test/design_tokens_test.dart가 이 표에서 만든다. 값이 같아도 역할이 다르면 따로 둔다(책 제목과 굵은 줄 이름처럼): 한쪽만 고칠 수 있게.
/// 위계(토스 TDS): 큰 제목 26 Bold, 시트 · 창 제목 21, 구역 제목 19, 본문 17~18, 보조 16, 작은 메타 15, 아주 작은 표시 13
abstract final class TypeSpecs {
  /// 아주 큰 숫자(통계 '이번 달 읽은 시간')
  static const display = TypeSpec(AppFonts.uiTitle, 48, 58, tabular: true);
  /// 아주 큰 숫자의 단위
  static const displayUnit = TypeSpec(AppFonts.uiMedium, 22, 30);
  /// 읽기 장면 시간
  static const timer = TypeSpec(AppFonts.ui, 64, 72, tabular: true);
  /// 큰 시간(독서 끝 · 접은 읽기 장면)
  static const clock = TypeSpec(AppFonts.ui, 36, 44, tabular: true);
  /// 큰 점수(독자 평점 평균)
  static const score = TypeSpec(AppFonts.uiTitle, 36, 44, tabular: true);
  /// 숫자 값(통계 읽은 날 · 독서 횟수, 쪽수)
  static const figure = TypeSpec(AppFonts.uiTitle, 24, 32, tabular: true);
  /// 앱 이름처럼 화면에 하나뿐인 큰 이름(로그인 '책장 한켠')
  static const hero = TypeSpec(AppFonts.uiTitle, 32, 40);
  /// 탭 첫 화면 큰 제목
  static const title = TypeSpec(AppFonts.uiTitle, 26, 34);
  /// 머리줄 왼쪽 큰 제목(책 추가 등)
  static const pageTitle = TypeSpec(AppFonts.uiTitle, 23, 30);
  /// 밀어 넣은 화면 위 줄 가운데 제목
  static const navTitle = TypeSpec(AppFonts.uiBold, 18, 25);
  /// 시트 · 창 제목, 큰 카드 제목
  static const heading = TypeSpec(AppFonts.uiBold, 21, 29);
  /// 구역 제목
  static const section = TypeSpec(AppFonts.uiBold, 19, 27);
  /// 목록 줄 이름(설정 · 메뉴 · 이름+값)
  static const row = TypeSpec(AppFonts.ui, 18, 26);
  /// 굵은 줄 이름(시트 안 묶음 이름 등)
  static const rowStrong = TypeSpec(AppFonts.uiBold, 18, 26);
  /// 본문
  static const body = TypeSpec(AppFonts.ui, 17, 27);
  /// 보조 글(값 · 설명 · 출처)
  static const sub = TypeSpec(AppFonts.ui, 16, 23, color: AppColors.inkSoft);
  /// 작은 보조 글(묶음 이름 · 메타)
  static const caption = TypeSpec(AppFonts.ui, 15, 21, color: AppColors.inkSoft);
  /// 보통 · 큰 단추 글자
  static const button = TypeSpec(AppFonts.uiBold, 17, 24);
  /// 구역 제목 옆 개수(SectionHead '갈피  3')
  static const count = TypeSpec(AppFonts.uiMedium, 16, 23, color: AppColors.inkSoft);
  /// 돌려 고르는 숫자(분 · 시각 고르기 시트). 고른 값은 .strong + ink
  static const wheel = TypeSpec(AppFonts.ui, 19, 27, color: AppColors.inkSoft, tabular: true);
  /// 로그인 화면 아래 작은 글자 단추(약관 · 둘러보기)
  static const loginLink = TypeSpec(AppFonts.uiMedium, 15, 21, color: AppColors.inkSoft);
  /// 토스트 글과 되돌리기 단추(먹색 바탕 위 흰 글자)
  static const toast = TypeSpec(AppFonts.ui, 16, 22, color: AppColors.onToast);
  static const toastAction = TypeSpec(AppFonts.uiBold, 16, 22, color: AppColors.onToast);
  /// 글자 단추(TextLink: 밑줄 없음. 기본 갈색, 보조는 회색 · 끝내기는 본문색으로 색만 바꾼다)
  static const link = TypeSpec(AppFonts.uiBold, 16, 23, color: AppColors.accent);
  /// 작은 단추 글자
  static const buttonSmall = TypeSpec(AppFonts.uiBold, 16, 22);
  /// 작은 이름(칩 · 고르는 칸)
  static const label = TypeSpec(AppFonts.uiMedium, 16, 22);
  /// 굵은 작은 이름(카드 제목 · 닉네임 · 필터 칸)
  static const labelStrong = TypeSpec(AppFonts.uiBold, 16, 22);
  /// 작은 본문(체크 이름 · 날짜 칸 · 짧은 글)
  static const bodySmall = TypeSpec(AppFonts.ui, 16, 22);
  /// 아주 작은 표시(그래프 눈금 · 배지)
  static const micro = TypeSpec(AppFonts.ui, 13, 18, color: AppColors.inkSoft, tabular: true);
  /// 갈피 문장(명조)
  static const quote = TypeSpec(AppFonts.serif, 16, 27);
  /// 긴 글 본문(명조)
  static const reading = TypeSpec(AppFonts.reading, 17, 30);
  // 책 · 기록 역할: 값이 위 일반 역할과 같아도 따로 둔다(책 제목만, 기록 시간만 고칠 수 있게)
  /// 책 제목 · 책 정보 머리 가운데(표지 아래)
  static const bookHeadTitle = TypeSpec(AppFonts.uiTitle, 23, 30);
  /// 책 제목 · 읽기 탭 '최근 읽던 책' 큰 카드
  static const bookFeatureTitle = TypeSpec(AppFonts.uiBold, 21, 29);
  /// 책 제목 · 저장했어요 창(독서 저장 뒤, 사용자 시안)
  static const bookSavedTitle = TypeSpec(AppFonts.uiBold, 19, 27);
  /// 책 제목 · 책 한 줄(BookRow: 고르기 · 검색 결과 · 내 책 목록 · 기록 줄)
  static const bookTitle = TypeSpec(AppFonts.uiBold, 18, 26);
  /// 책 제목 · 내 책 격자 표지 아래
  static const bookGridTitle = TypeSpec(AppFonts.ui, 15, 21);
  /// 작가 · 책 줄 둘째 줄('작가 | 출판사', '작가 | 상태'), 책 정보 머리 작가
  static const bookAuthor = TypeSpec(AppFonts.ui, 16, 23, color: AppColors.inkSoft);
  /// 작가 · 내 책 격자 표지 아래 둘째 줄
  static const bookGridAuthor = TypeSpec(AppFonts.ui, 13, 18, color: AppColors.inkSoft, tabular: true);
  /// 한줄평 · 책 줄 셋째 줄(한줄평 · 미리보기 · 진행)
  static const bookNote = TypeSpec(AppFonts.ui, 15, 21, color: AppColors.inkSoft);
  /// 한줄평 · 평가 탭 본문
  static const review = TypeSpec(AppFonts.ui, 17, 27);
  /// 날짜 · 독서 기록 묶음 머리('11월 17일')
  static const recordDay = TypeSpec(AppFonts.ui, 18, 26);
  /// 시간 · 독서 기록 시간대('오후 9:05-9:30')
  static const recordRange = TypeSpec(AppFonts.ui, 16, 23, color: AppColors.inkSoft);
  /// 시간 · 독서 기록 한 줄의 읽은 시간('38분')
  static const recordDuration = TypeSpec(AppFonts.ui, 18, 26, tabular: true);

  /// 이름 → 값(토큰 내보내기 · 검사용, 위 역할을 모두 담는다)
  static const all = <String, TypeSpec>{
    'display': display,
    'displayUnit': displayUnit,
    'timer': timer,
    'clock': clock,
    'score': score,
    'figure': figure,
    'hero': hero,
    'title': title,
    'pageTitle': pageTitle,
    'navTitle': navTitle,
    'heading': heading,
    'section': section,
    'row': row,
    'rowStrong': rowStrong,
    'body': body,
    'sub': sub,
    'caption': caption,
    'button': button,
    'count': count,
    'wheel': wheel,
    'loginLink': loginLink,
    'toast': toast,
    'toastAction': toastAction,
    'link': link,
    'buttonSmall': buttonSmall,
    'label': label,
    'labelStrong': labelStrong,
    'bodySmall': bodySmall,
    'micro': micro,
    'quote': quote,
    'reading': reading,
    'bookHeadTitle': bookHeadTitle,
    'bookFeatureTitle': bookFeatureTitle,
    'bookSavedTitle': bookSavedTitle,
    'bookTitle': bookTitle,
    'bookGridTitle': bookGridTitle,
    'bookAuthor': bookAuthor,
    'bookGridAuthor': bookGridAuthor,
    'bookNote': bookNote,
    'review': review,
    'recordDay': recordDay,
    'recordRange': recordRange,
    'recordDuration': recordDuration,
  };
}

/// 글자 역할(docs/design/DESIGN.md 2장). 화면에서 글자 크기를 직접 쓰지 않는다: 같은 종류 항목은 같은 역할을 쓴다
/// (2026-11-18 사용자 '버튼·글씨 크기·여백·글씨체는 항목에 따라 통일해서 관리'). 숫자 역할(display · timer · clock · score · figure · micro · wheel · bookGridAuthor · recordDuration)은 숫자 폭이 고정이다
abstract final class AppType {
  static TextStyle get display => TypeSpecs.display.style;
  static TextStyle get displayUnit => TypeSpecs.displayUnit.style;
  static TextStyle get timer => TypeSpecs.timer.style;
  static TextStyle get clock => TypeSpecs.clock.style;
  static TextStyle get score => TypeSpecs.score.style;
  static TextStyle get figure => TypeSpecs.figure.style;
  static TextStyle get hero => TypeSpecs.hero.style;
  static TextStyle get title => TypeSpecs.title.style;
  static TextStyle get pageTitle => TypeSpecs.pageTitle.style;
  static TextStyle get navTitle => TypeSpecs.navTitle.style;
  static TextStyle get heading => TypeSpecs.heading.style;
  static TextStyle get section => TypeSpecs.section.style;
  static TextStyle get row => TypeSpecs.row.style;
  static TextStyle get rowStrong => TypeSpecs.rowStrong.style;
  static TextStyle get body => TypeSpecs.body.style;
  static TextStyle get sub => TypeSpecs.sub.style;
  static TextStyle get caption => TypeSpecs.caption.style;
  static TextStyle get button => TypeSpecs.button.style;
  static TextStyle get count => TypeSpecs.count.style;
  static TextStyle get wheel => TypeSpecs.wheel.style;
  static TextStyle get loginLink => TypeSpecs.loginLink.style;
  static TextStyle get toast => TypeSpecs.toast.style;
  static TextStyle get toastAction => TypeSpecs.toastAction.style;
  static TextStyle get link => TypeSpecs.link.style;
  static TextStyle get buttonSmall => TypeSpecs.buttonSmall.style;
  static TextStyle get label => TypeSpecs.label.style;
  static TextStyle get labelStrong => TypeSpecs.labelStrong.style;
  static TextStyle get bodySmall => TypeSpecs.bodySmall.style;
  static TextStyle get micro => TypeSpecs.micro.style;
  static TextStyle get quote => TypeSpecs.quote.style;
  static TextStyle get reading => TypeSpecs.reading.style;
  static TextStyle get bookHeadTitle => TypeSpecs.bookHeadTitle.style;
  static TextStyle get bookFeatureTitle => TypeSpecs.bookFeatureTitle.style;
  static TextStyle get bookSavedTitle => TypeSpecs.bookSavedTitle.style;
  static TextStyle get bookTitle => TypeSpecs.bookTitle.style;
  static TextStyle get bookGridTitle => TypeSpecs.bookGridTitle.style;
  static TextStyle get bookAuthor => TypeSpecs.bookAuthor.style;
  static TextStyle get bookGridAuthor => TypeSpecs.bookGridAuthor.style;
  static TextStyle get bookNote => TypeSpecs.bookNote.style;
  static TextStyle get review => TypeSpecs.review.style;
  static TextStyle get recordDay => TypeSpecs.recordDay.style;
  static TextStyle get recordRange => TypeSpecs.recordRange.style;
  static TextStyle get recordDuration => TypeSpecs.recordDuration.style;

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

/// '#RRGGBB'(또는 'RRGGBB') → 불투명 색. 앱의 색 글자 바꾸기는 이것 하나(2026-11-19 공통 규칙: 같은 함수가 여섯 벌 있었다)
Color hexColor(String hex) => Color(0xFF000000 | int.parse(hex.replaceAll('#', '').substring(0, 6), radix: 16));

/// 눌린 표시(아이콘 · 글자 단추)의 투명도
const pressOpacity = 0.55;

/// 꺼진 단추·글자 단추·아이콘의 투명도(하나로, 2026-11-19 공통 규칙: 0.45 · 0.4 · 0.3이 섞여 있었다)
const disabledOpacity = 0.4;

/// 역할 글자에 붙이는 덧칠 두 가지(그 밖의 덧칠은 색만, docs/design/DESIGN.md 1장)
extension AppTypeMods on TextStyle {
  /// 숫자 폭 고정(시간·쪽수·%가 바뀌어도 글 폭이 그대로)
  TextStyle get tnum => copyWith(fontFeatures: _tab);

  /// 고른 칸만 굵게
  TextStyle get strong => copyWith(fontFamily: AppFonts.uiBold);
}

/// 지금 앱 boxShadow(CSS: 흐림 반경 = 2σ)를 Flutter 그림자로(Flutter blurRadius r → σ = 0.57735·r + 0.5)
BoxShadow cssShadow(Color color, double dx, double dy, double blur, [double spread = 0]) =>
    BoxShadow(color: color, offset: Offset(dx, dy), blurRadius: blur / 2 <= 0.5 ? 0 : (blur / 2 - 0.5) / 0.57735, spreadRadius: spread);
