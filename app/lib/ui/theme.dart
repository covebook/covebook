// 화면 색·글자·크기. 디자인 시안(toss-official): 토스 TDS Mobile 공식 문서(tossmini-docs.toss.im/tds-mobile llms-full.txt · Typography 렌더 HTML)만 근거로
// 글자 토큰(t1~t7 · st1~st13)·회색 단계 이름·부품 기본값을 넣었다. 값마다 출처는 시안 기록 DESIGN-APPLIED.md(design/toss-official 시안).
// 대표색은 TDS 파랑(blue500 · blue400) 자리에 갈색, 공식이 회색·검정을 쓰는 자리는 회색 단계 그대로
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

abstract final class AppColors {
  // ── TDS 회색 단계(Colors 절: 이름 grey50~900만 공개, 헥스는 견본 그림뿐이고 렌더 HTML에도 없다 → 헥스는 지금 앱 값 · 이전 시안 design/toss 값)
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF2F4F6);
  static const grey200 = Color(0xFFE5E8EB);
  static const grey300 = Color(0xFFD1D6DB);
  static const grey400 = Color(0xFFB0B8C1);
  static const grey500 = Color(0xFF8B95A1);
  static const grey600 = Color(0xFF6B7684);
  static const grey700 = Color(0xFF4E5968);
  static const grey800 = Color(0xFF333D4B);
  static const grey900 = Color(0xFF191F28);

  /// TDS greyOpacity100(Icon Button bgColor 기본값: 눌린 투명 단추 바탕 · ListRow.IconButton 바탕). 공식 헥스 없음 →
  /// 흰 바탕에서 grey100처럼 보이는 grey900 5%(우리 값). Button weak의 '반투명' 바탕에도 쓴다
  static const greyOpacity100 = Color(0x0D191F28);

  /// TDS greyBackground(Bottom Info 기본 바탕 이름). 헥스 없음 → grey100. 구간을 나누는 띠(Border height16)에 쓴다
  static const greyBackground = grey100;

  static const bg = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const input = grey100;
  static const surface = grey100;

  /// 로그인 화면 아래쪽 바탕(공식 없음 → 우리 값, 2026-11-18 사용자 '하단 그라데이션 좀 더 진하게')
  static const loginFloor = Color(0xFFE4E7EB);
  static const sectionLine = Color(0xFFEFF1F3);

  /// 본문 글자: grey900(Paragraph 기본 색, 렌더 HTML var(--tds-paragraph-color, var(--adaptiveGrey900)))
  static const ink = grey900;

  /// 제목 글자: grey800(Top 제목 · AlertDialog/ConfirmDialog 제목 · ListHeader 제목 기본 색)
  static const title = grey800;

  /// 부제 · 오른쪽 값 글자: grey700(Top 부제 · ListHeader 오른쪽 글 · 화살표 옆 글 기본 색)
  static const inkSub = grey700;

  /// 설명 글자: grey600(AlertDialog/ConfirmDialog 설명 기본 색, 흰 바탕 대비 4.6:1)
  static const inkSoft = grey600;

  /// 자리 표시 글자 · 꺼진 것 · 줄 끝 화살표: grey400(ListHeader 화살표 · Board Row 아이콘 · Stepper 화살표 기본 색)
  static const inkFaint = grey400;

  /// 선 아이콘(머리줄 · 검색칸 · 카드 · 줄 안): grey500. 글자(inkSoft)보다 한 단계 옅게(2026-11-18 사용자 '아이콘 색 좀 연하게, 통일')
  static const icon = grey500;
  static const line = grey200;

  /// 밑줄 탭 아래 화면 폭 옅은 선(토스 앱 실측 #EBECEE, 2026-11-20 사용자 '이런 은은한 선 괜찮은 듯'). 테두리 line보다 옅다
  static const divider = Color(0xFFEBECEE);
  static const track = grey300;

  /// 정보 사이 세로줄(가운데 점 대신, 2026-11-18): 글자보다 옅고 흰·회색 바탕 모두에서 보이는 회색
  static const metaBar = Color(0xFFC9CED4);
  static const accent = Color(0xFF6C534A);
  static const accentPressed = Color(0xFF5A443C);
  static const onAccent = Color(0xFFFFFFFF);
  static const danger = Color(0xFFA5483A);

  /// Button weak 바탕(공식: 'weak는 반투명해서 배경색이 살짝 드러나요', 투명도 숫자는 없음 → 우리 값 10%)
  static const accentWeak = Color(0x1A6C534A);
  static const dangerWeak = Color(0x1AA5483A);

  /// Button 눌림 딤 레이어(공식: --button-pressed-background-color · --button-pressed-opacity, 값은 없음).
  /// 우리 값: 지금 앱의 눌린 갈색(accentPressed)이 갈색 위 검정 약 18% 덧칠과 같아 그 덧칠을 모든 단추에
  static const pressDim = Color(0x2E000000);
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
    'white': (white, '카드 위 흰색 · 전환 칸 고른 칸'),
    'input': (input, '입력칸 바탕'),
    'surface': (surface, '옅은 회색 면(전환 칸 · 표지 자리)'),
    'loginFloor': (loginFloor, '로그인 화면 아래쪽'),
    'sectionLine': (sectionLine, '묶음 사이 띠'),
    'ink': (ink, '본문(grey900)'),
    'title': (title, '제목(grey800): 탭 · 머리줄 · 시트 · 확인창 · 구역 제목'),
    'inkSub': (inkSub, '부제 · 오른쪽 값(grey700)'),
    'inkSoft': (inkSoft, '설명 · 보조 글자(grey600)'),
    'icon': (icon, '선 아이콘: 머리줄 · 검색칸 · 카드 · 줄 안(grey500)'),
    'inkFaint': (inkFaint, '흐린 글자 · 빈 칸 안내 · 줄 끝 화살표(grey400)'),
    'line': (line, '구분선 · 테두리'),
    'divider': (divider, '밑줄 탭 아래 화면 폭 옅은 선'),
    'track': (track, '막대 · 손잡이 자리'),
    'metaBar': (metaBar, '정보 사이 세로줄(|)'),
    'accent': (accent, '주요 단추 · 고른 것(갈색)'),
    'accentPressed': (accentPressed, '주요 단추 눌림'),
    'onAccent': (onAccent, '갈색 위 글자'),
    'danger': (danger, '삭제 · 오류'),
    'accentWeak': (accentWeak, '갈색 weak 단추 바탕(10%)'),
    'dangerWeak': (dangerWeak, '주의색 weak 단추 바탕(10%)'),
    'pressDim': (pressDim, '바탕 있는 단추 눌림 덧칠(검정 18%)'),
    'greyOpacity100': (greyOpacity100, '회색 weak 단추 바탕 · 목록 줄 · 아이콘 단추 눌림 바탕(grey900 5%)'),
    'greyBackground': (greyBackground, '구간을 나누는 띠(Border height16)'),
    'star': (star, '별점'),
    'scrim': (scrim, '시트 · 확인창 뒤 막'),
    'tabInk': (tabInk, '하단 탭 고른 아이콘'),
    'tabInkSoft': (tabInkSoft, '하단 탭 안 고른 아이콘'),
    'toast': (toast, '토스트(짧은 알림) 바탕'),
    'onToast': (onToast, '토스트 글자'),
    'grey50': (grey50, 'TDS 회색 단계'),
    'grey100': (grey100, 'TDS 회색 단계'),
    'grey200': (grey200, 'TDS 회색 단계'),
    'grey300': (grey300, 'TDS 회색 단계'),
    'grey400': (grey400, 'TDS 회색 단계'),
    'grey500': (grey500, 'TDS 회색 단계'),
    'grey600': (grey600, 'TDS 회색 단계'),
    'grey700': (grey700, 'TDS 회색 단계'),
    'grey800': (grey800, 'TDS 회색 단계'),
    'grey900': (grey900, 'TDS 회색 단계'),
  };
}

/// 글꼴(Pretendard 한 가족, 굵기는 파일로). TDS 굵기 regular 400 · medium 500 · semibold 600 · bold 700(Typography 렌더 HTML font-weight 400/500/600/700)
abstract final class AppFonts {
  /// regular 400
  static const ui = 'PretendardRegular';

  /// medium 500
  static const uiMedium = 'PretendardMedium';

  /// semibold 600
  static const uiBold = 'PretendardSemiBold';

  /// bold 700(TDS 제목 기본 굵기 'bold': Top · Dialog 제목 · ListHeader 제목 · 글자 단추)
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

/// TDS '더 큰 텍스트' 최대 크기(Typography 절 Android 표: 토큰 크기 × NN% 하되 이 값에서 멈춘다).
/// 열쇠는 100%일 때 글자 크기(t1 30 · st1 29 … st13 11). 표에 없는 크기(숫자 전용 48 · 64 · 36 · 32)는 공식 규칙이 없어 시스템 배율 그대로
const tdsLargeTextMax = <int, double>{
  30: 42, 29: 42, 28: 41, 27: 41, 26: 41, 25: 41, 24: 40, 23: 40, 22: 40, 21: 40, 20: 40,
  19: 40, 18: 39, 17: 39, 16: 39, 15: 37, 14: 36, 13: 34, 12: 32, 11: 31,
};

class RnTextScaler extends TextScaler {
  const RnTextScaler(this.base, this.dpr);
  final TextScaler base;
  final double dpr;
  @override
  double scale(double fontSize) {
    var s = base.scale(fontSize);
    // TDS 토큰 크기면 큰 글씨 최대에서 멈춘다(Typography 절 '더 큰 텍스트' Android 표)
    final whole = fontSize.round();
    final cap = (fontSize - whole).abs() < 1e-6 ? tdsLargeTextMax[whole] : null;
    if (cap != null && s > cap) s = cap;
    return rnPx(s, dpr);
  }

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
/// 크기/줄 높이는 TDS Typography 토큰(DESIGN-APPLIED.md 2-1): t1 30/40 · st2 28/37 · t2 26/35 · st5 24/33 · t3 22/31 · t4 20/29 · st9 18/27 ·
/// t5 17/25.5 · st10 16/24 · t6 15/22.5 · t7 13/19.5. 쓰임은 t3 일반 제목 · t4 작은 제목 · t5 일반 본문 · t6 작은 본문 · t7 안 읽어도 됨.
/// 위계: 탭 첫 화면 · 머리줄 제목 t3 22 Bold(Top 기본) · 시트 · 확인창 · 구역 제목 t4 20 Bold(BottomSheet.Header · Dialog 제목 · ListHeader), 제목은 grey800.
/// 본문 t5 17 grey900 · 설명 t6 15 grey600 · 부제 · 오른쪽 값 t6 grey700 · 메타 t7 13. 표 밖 숫자 크기(48 · 64 · 36)와 명조 내용 글자는 우리 값
abstract final class TypeSpecs {
  /// 아주 큰 숫자(통계 '이번 달 읽은 시간'): TDS 표 밖(최대 t1 30) → 우리 값
  static const display = TypeSpec(AppFonts.uiTitle, 48, 58, tabular: true);
  /// 아주 큰 숫자의 단위: t3 Medium
  static const displayUnit = TypeSpec(AppFonts.uiMedium, 22, 31);
  /// 읽기 장면 시간(표 밖 → 우리 값)
  static const timer = TypeSpec(AppFonts.ui, 64, 72, tabular: true);
  /// 큰 시간(독서 끝 · 접은 읽기 장면, 표 밖 → 우리 값)
  static const clock = TypeSpec(AppFonts.ui, 36, 44, tabular: true);
  /// 큰 점수(독자 평점 평균, 표 밖 → 우리 값)
  static const score = TypeSpec(AppFonts.uiTitle, 36, 44, tabular: true);
  /// 숫자 값(통계 읽은 날 · 독서 횟수, 쪽수): st5 Bold(조금 큰 제목)
  static const figure = TypeSpec(AppFonts.uiTitle, 24, 33, tabular: true);
  /// 앱 이름처럼 화면에 하나뿐인 큰 이름(로그인 '책장 한켠'): t1 Bold grey800(매우 큰 제목)
  static const hero = TypeSpec(AppFonts.uiTitle, 30, 40, color: AppColors.title);
  /// 탭 첫 화면 제목: Top.TitleParagraph 기본 size 22 = t3 Bold grey800
  /// (11-19 사용자 '토스 앱에 저렇게 큰 거 없는 거 같은데': 28은 Top의 선택지일 뿐이라 기본값 22로)
  /// (2026-11-24 사용자 7단계 토스 앱 실측: 22/31 → 20/29)
  static const title = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 머리줄 왼쪽 제목(책 추가 등): Top 기본 t3 Bold grey800
  /// (2026-11-24 사용자 7단계 토스 앱 실측: 22/31 → 20/29)
  static const pageTitle = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 밀어 넣은 화면 위 줄 가운데 제목: TDS에 내비게이션 바 없음 → 우리 크기 18 SemiBold, 줄 높이는 표의 st9
  static const navTitle = TypeSpec(AppFonts.uiBold, 18, 27);
  /// 시트 · 확인창 · 빈 화면 제목, 큰 카드 제목: t4 Bold grey800(BottomSheet.Header · AlertDialog/ConfirmDialog.Title)
  static const heading = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 빈 화면 · 검색 0건 · 조건 0건 제목(Empty): t5 SemiBold grey600. 먹색 굵은 제목이 너무 진했다(2026-11-20 사용자 '색 너무 진하지 않나')
  static const emptyTitle = TypeSpec(AppFonts.uiBold, 17, 25.5, color: AppColors.inkSoft);
  /// 구역 제목(H2 · SectionHead · 달력 달): ListHeader.TitleParagraph t4 Bold grey800
  /// (2026-11-24 사용자 7단계: 20/29 → 17/25.5, 굵기 · 색 그대로)
  static const section = TypeSpec(AppFonts.uiTitle, 17, 25.5, color: AppColors.title);
  /// 묶음 이름(ListGroup · FilterGroup · SheetLabel): ListHeader.TitleParagraph t5 Bold grey800(공식 예시 BasicHeaders)
  static const listHeader = TypeSpec(AppFonts.uiTitle, 17, 25.5, color: AppColors.title);
  /// 목록 줄 이름(설정 · 메뉴 · 이름+값): t5 Regular grey900
  static const row = TypeSpec(AppFonts.ui, 17, 25.5);
  /// 굵은 줄 이름: t5 SemiBold(세트 굵기는 공식 글에 없음 → 우리 굵기)
  static const rowStrong = TypeSpec(AppFonts.uiBold, 17, 25.5);
  /// 본문: t5 Regular grey900(일반 본문)
  static const body = TypeSpec(AppFonts.ui, 17, 25.5);
  /// 설명(값 · 출처 · 시트 부제목 · 안내): t6 Regular grey600(BottomSheet.HeaderDescription · Dialog 설명 색)
  /// (2026-11-24 사용자 7단계: 설명 글만 15/22.5 → 13/19.5. 누르는 회색 글자 단추는 subLink 15 그대로)
  static const sub = TypeSpec(AppFonts.ui, 13, 19.5, color: AppColors.inkSoft);
  /// 누르는 회색 글자 단추(TextLink(soft) · SubAction): 설명(sub)이 13이 되며 따로 둔 역할, 15 그대로(2026-11-24 사용자 7단계)
  static const subLink = TypeSpec(AppFonts.ui, 15, 22.5, color: AppColors.inkSoft);
  /// 부제 · 오른쪽 값(탭 머리 부제 · 목록 줄 오른쪽 값 · 구역 머리 오른쪽 글자): t6 Regular grey700(Top.SubtitleParagraph · ListHeader.RightText)
  static const secondary = TypeSpec(AppFonts.ui, 15, 22.5, color: AppColors.inkSub);
  /// 확인창 설명: t6 Medium grey600(AlertDialog/ConfirmDialog.Description 기본값)
  static const dialogBody = TypeSpec(AppFonts.uiMedium, 15, 22.5, color: AppColors.inkSoft);
  /// 작은 보조 글(날짜 · 메타 · 도움말): t7 Regular grey600(안 읽어도 됨)
  static const caption = TypeSpec(AppFonts.ui, 13, 19.5, color: AppColors.inkSoft);
  /// 큰 단추 글자(xlarge · large): t5 SemiBold(단추 글자는 공식 글에 없음 → 크기 t5)
  static const button = TypeSpec(AppFonts.uiBold, 17, 25.5);
  /// 구역 제목 옆 개수(SectionHead '갈피  3'): t6 Medium grey600
  static const count = TypeSpec(AppFonts.uiMedium, 15, 22.5, color: AppColors.inkSoft);
  /// 돌려 고르는 숫자(분 · 시각 고르기 시트): t4. 고른 값은 .strong + ink
  static const wheel = TypeSpec(AppFonts.ui, 20, 29, color: AppColors.inkSoft, tabular: true);
  /// 로그인 화면 아래 작은 글자 단추(약관 · 둘러보기): t7 Medium grey600
  static const loginLink = TypeSpec(AppFonts.uiMedium, 13, 19.5, color: AppColors.inkSoft);
  /// 토스트 글과 되돌리기 단추(먹색 바탕 위 흰 글자). TDS Toast 글자는 공식 없음 → 우리 크기 16, 줄 높이는 표의 st10
  static const toast = TypeSpec(AppFonts.ui, 16, 24, color: AppColors.onToast);
  static const toastAction = TypeSpec(AppFonts.uiBold, 16, 24, color: AppColors.onToast);
  /// 글자 단추(TextLink · ghost 단추): TDS TextButton size medium = t5('Migrate to v2.x' TextButton 표), SemiBold 갈색.
  /// 보조는 회색 · 끝내기는 본문색으로 색만 바꾼다. 확인창 글자 단추(AlertDialog.AlertButton)는 bold
  static const link = TypeSpec(AppFonts.uiBold, 17, 25.5, color: AppColors.accent);
  /// 작은 단추 글자(medium · small): 우리 크기 16 SemiBold, 줄 높이는 표의 st10
  static const buttonSmall = TypeSpec(AppFonts.uiBold, 16, 24);
  /// 작은 이름(고르는 칸 · 입력칸 이름): st10 Medium
  static const label = TypeSpec(AppFonts.uiMedium, 16, 24);
  /// 굵은 작은 이름(카드 제목 · 닉네임 · 필터 칸): st10 SemiBold
  static const labelStrong = TypeSpec(AppFonts.uiBold, 16, 24);
  /// 작은 본문(체크 이름 · 날짜 칸 · 짧은 글): t6 Regular grey900(작은 본문)
  static const bodySmall = TypeSpec(AppFonts.ui, 15, 22.5);
  /// 아주 작은 표시(그래프 눈금 · 배지): t7 grey600
  static const micro = TypeSpec(AppFonts.ui, 13, 19.5, color: AppColors.inkSoft, tabular: true);
  /// 하단 탭 이름(아이콘 아래, 2026-11-24 사용자 6단계 '글자 11'): TDS 표 밖(최소 t7 13) → 우리 값. 색은 그 탭 아이콘 색(고른 탭은 tabInk)
  static const tabLabel = TypeSpec(AppFonts.uiMedium, 11, 14, color: AppColors.tabInkSoft);
  /// 감상 읽기 화면의 감상 제목(값은 탭 첫 화면 제목과 같지만 감상만 바꿀 수 있게): t3 Bold grey800
  /// (2026-11-24 사용자 7단계 토스 앱 실측: 22/31 → 20/29)
  static const essayTitle = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 밀어 넣은 화면 본문 맨 위 큰 안내 제목(책 목록 가져오기 첫 화면): t3 Bold grey800
  /// (2026-11-24 사용자 7단계 토스 앱 실측: 22/31 → 20/29)
  static const introTitle = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 사람 이름(독자 프로필 닉네임): t3 Bold grey800
  /// (2026-11-24 사용자 7단계 토스 앱 실측: 22/31 → 20/29)
  static const profileName = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 약관 · 처리방침 조 제목: st10 SemiBold
  static const legalHeading = TypeSpec(AppFonts.uiBold, 16, 24);
  /// 갈피 문장(명조): 내용 글꼴이라 TDS UI 글자가 아니다(우리 값)
  static const quote = TypeSpec(AppFonts.serif, 16, 27);
  /// 긴 글 본문(명조, 우리 값)
  static const reading = TypeSpec(AppFonts.reading, 17, 30);
  // 책 · 기록 역할: 값이 위 일반 역할과 같아도 따로 둔다(책 제목만, 기록 시간만 고칠 수 있게)
  /// 책 제목 · 책 정보 머리 가운데(표지 아래): t3 Bold grey800(머리줄 제목과 같은 단계)
  /// (2026-11-24 사용자 7단계 토스 앱 실측: 22/31 → 20/29)
  static const bookHeadTitle = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 책 제목 · 읽기 탭 '최근 읽던 책' 큰 카드: t4 Bold grey800
  static const bookFeatureTitle = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 책 제목 · 저장했어요 창(독서 저장 뒤, 사용자 시안): t4 Bold grey800
  static const bookSavedTitle = TypeSpec(AppFonts.uiTitle, 20, 29, color: AppColors.title);
  /// 책 제목 · 책 한 줄(BookRow: 고르기 · 검색 결과 · 내 책 목록 · 기록 줄): t5 SemiBold
  static const bookTitle = TypeSpec(AppFonts.uiBold, 17, 25.5);
  /// 책 제목 · 내 책 격자 표지 아래: t7 grey900
  static const bookGridTitle = TypeSpec(AppFonts.ui, 13, 19.5);
  /// 작가 · 책 줄 둘째 줄('작가 | 출판사', '작가 | 상태')과 그 밖의 쓰임: 13/19.5 grey700(2026-11-24 사용자 7단계: 15/22.5 grey600이었다)
  static const bookAuthor = TypeSpec(AppFonts.ui, 13, 19.5, color: AppColors.inkSub);
  /// 작가 · 책 정보 머리(표지 아래 가운데): 15/22.5 grey600 그대로(2026-11-24 사용자 7단계: 다른 작가 줄만 13)
  static const bookHeadAuthor = TypeSpec(AppFonts.ui, 15, 22.5, color: AppColors.inkSoft);
  /// 작가 · 내 책 격자 표지 아래 둘째 줄: t7 grey600
  static const bookGridAuthor = TypeSpec(AppFonts.ui, 13, 19.5, color: AppColors.inkSoft, tabular: true);
  /// 한줄평 · 책 줄 셋째 줄(한줄평 · 미리보기 · 진행): t7 grey600
  static const bookNote = TypeSpec(AppFonts.ui, 13, 19.5, color: AppColors.inkSoft);
  /// 한줄평 · 평가 탭 본문: t5
  static const review = TypeSpec(AppFonts.ui, 17, 25.5);
  /// 날짜 · 독서 기록 묶음 머리('11월 17일'): t5
  static const recordDay = TypeSpec(AppFonts.ui, 17, 25.5);
  /// 시간 · 독서 기록 시간대('오후 9:05-9:30'): t6 grey600
  static const recordRange = TypeSpec(AppFonts.ui, 15, 22.5, color: AppColors.inkSoft);
  /// 시간 · 독서 기록 한 줄의 읽은 시간('38분'): t5
  static const recordDuration = TypeSpec(AppFonts.ui, 17, 25.5, tabular: true);

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
    'emptyTitle': emptyTitle,
    'section': section,
    'listHeader': listHeader,
    'row': row,
    'rowStrong': rowStrong,
    'body': body,
    'sub': sub,
    'subLink': subLink,
    'secondary': secondary,
    'dialogBody': dialogBody,
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
    'tabLabel': tabLabel,
    'essayTitle': essayTitle,
    'introTitle': introTitle,
    'profileName': profileName,
    'legalHeading': legalHeading,
    'quote': quote,
    'reading': reading,
    'bookHeadTitle': bookHeadTitle,
    'bookFeatureTitle': bookFeatureTitle,
    'bookSavedTitle': bookSavedTitle,
    'bookTitle': bookTitle,
    'bookGridTitle': bookGridTitle,
    'bookAuthor': bookAuthor,
    'bookHeadAuthor': bookHeadAuthor,
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
  static TextStyle get emptyTitle => TypeSpecs.emptyTitle.style;
  static TextStyle get section => TypeSpecs.section.style;
  static TextStyle get listHeader => TypeSpecs.listHeader.style;
  static TextStyle get row => TypeSpecs.row.style;
  static TextStyle get rowStrong => TypeSpecs.rowStrong.style;
  static TextStyle get body => TypeSpecs.body.style;
  static TextStyle get sub => TypeSpecs.sub.style;
  static TextStyle get subLink => TypeSpecs.subLink.style;
  static TextStyle get secondary => TypeSpecs.secondary.style;
  static TextStyle get dialogBody => TypeSpecs.dialogBody.style;
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
  static TextStyle get tabLabel => TypeSpecs.tabLabel.style;
  static TextStyle get essayTitle => TypeSpecs.essayTitle.style;
  static TextStyle get introTitle => TypeSpecs.introTitle.style;
  static TextStyle get profileName => TypeSpecs.profileName.style;
  static TextStyle get legalHeading => TypeSpecs.legalHeading.style;
  static TextStyle get quote => TypeSpecs.quote.style;
  static TextStyle get reading => TypeSpecs.reading.style;
  static TextStyle get bookHeadTitle => TypeSpecs.bookHeadTitle.style;
  static TextStyle get bookFeatureTitle => TypeSpecs.bookFeatureTitle.style;
  static TextStyle get bookSavedTitle => TypeSpecs.bookSavedTitle.style;
  static TextStyle get bookTitle => TypeSpecs.bookTitle.style;
  static TextStyle get bookGridTitle => TypeSpecs.bookGridTitle.style;
  static TextStyle get bookAuthor => TypeSpecs.bookAuthor.style;
  static TextStyle get bookHeadAuthor => TypeSpecs.bookHeadAuthor.style;
  static TextStyle get bookGridAuthor => TypeSpecs.bookGridAuthor.style;
  static TextStyle get bookNote => TypeSpecs.bookNote.style;
  static TextStyle get review => TypeSpecs.review.style;
  static TextStyle get recordDay => TypeSpecs.recordDay.style;
  static TextStyle get recordRange => TypeSpecs.recordRange.style;
  static TextStyle get recordDuration => TypeSpecs.recordDuration.style;

  /// 입력창(줄 높이는 플랫폼에 맡긴다). TextField 글자 크기는 공식 글에 없음 → 우리 값 16
  static const input = TextStyle(fontFamily: AppFonts.ui, fontSize: 16, color: AppColors.ink);
}

/// 탭 첫 화면 머리줄 = TDS Top: upperGap 24 · lowerGap 24(Top 절 기본값). 양옆은 ListRow horizontalPadding medium 24와 같은 24
abstract final class TabHeader {
  /// 상태 표시줄 아래(2026-11-23 사용자 '나의 책장이랑 2026라인이랑 아이콘 라인이 위아래 간격이 안 맞잖아, 위쪽이 넓어서 그 부분을 줄이라고':
  /// 24면 책장 머리 글자 위가 약 31, 아래가 약 10이었다. 4로 줄여 위아래 빈 곳을 맞춘다. 다섯 탭 첫 화면이 같이 쓴다)
  static const paddingTop = 4.0;

  /// 제목 아래(2026-11-20 사용자: 토스 공식 24는 '밑에랑 간격이 너무 커', 갈피 · 감상 탭은 아이콘 줄 바로 아래)
  static const paddingBottom = 4.0;
  static const paddingH = 24.0;
  /// 머리줄 최소 높이(위 · 아래 여백 포함). 안쪽 최소 36은 그대로(64 − 24 − 4였다)
  static const minHeight = 44.0;
}

/// 알림 줄(토스트) 시간: TDS Toast duration 기본 3000ms, 버튼이 있으면 5000ms(Toast 절 · useToast 절)
abstract final class Motion {
  static const toast = Duration(milliseconds: 3000);
  static const toastAction = Duration(milliseconds: 5000);

  /// 닫을 수 없는 확인창 바깥을 누르면 좌우로 흔든다(AlertDialog/ConfirmDialog closeOnDimmerClick false: 'Wiggle 애니메이션'). 길이·폭은 공식 없음 → 우리 값
  static const wiggle = Duration(milliseconds: 360);
  static const wiggleDx = 8.0;
}

/// 하단 탭 바(알약): 양옆 12, 높이 56, 아래 틈 4, 안쪽 좌우 9, 아이콘 22, 그림자 0 3 14 rgba(25,31,40,.13). 2026-11-24 토스증권 하단바 사진 참고(전에는 15 · 58 · 23).
/// TDS에는 하단 탭이 없다(앱인토스 UI/UX 가이드: '토스에서 제공하는 플로팅 형태 유지 · 탭 2~5개'). 지금 앱 탭 바가 이미 떠 있는 알약 · 5개라 값은 우리 값 그대로
abstract final class TabBarStyle {
  /// 알약 높이(2026-11-24 사용자 '토스증권 하단바 참고': 그 사진 360dp 기준 56)
  static const height = 56.0;

  /// 탭 바가 차지하는 높이(알약 56 + 틈 8). 작은 타이머 · 목록 아래 여백의 기준
  static const navHeight = 64.0;

  /// 탭 화면 내용 아래 여백(지금 앱 TAB_CONTENT_PAD)
  static const contentPad = navHeight + 40;

  /// 알약 좌우 여백(토스증권 사진 12)
  static const side = 12.0;
  static const gap = 4.0;
  static const paddingX = 9.0;

  /// 아이콘 칸 높이(토스증권 사진: 그림 높이 약 20 → 우리 아이콘 칸 22)
  static const icon = 22.0;

  /// 아이콘과 이름 사이(토스증권 사진: 그림 끝 ~ 글자 위 7. 아이콘 22 + 4 + 이름 줄 14 = 40, 알약 56 안 가운데)
  static const labelGap = 4.0;

  /// 큰 글씨에서도 이름이 알약(56)을 넘지 않게 이름 글자 배율 상한(1.3배: 22 + 4 + 18.2 = 44.2)
  static const labelScaleMax = 1.3;
  static const shadow = BoxShadow(color: Color(0x21191F28), offset: Offset(0, 3), blurRadius: 14);

  /// 홈 화면에서 하단바 위로 벽 색이 옅어지는 높이
  static const fade = 72.0;
}

/// '#RRGGBB'(또는 'RRGGBB') → 불투명 색. 앱의 색 글자 바꾸기는 이것 하나(2026-11-19 공통 규칙: 같은 함수가 여섯 벌 있었다)
Color hexColor(String hex) => Color(0xFF000000 | int.parse(hex.replaceAll('#', '').substring(0, 6), radix: 16));

/// 눌린 표시(바탕이 없는 글자 단추 · 글자 링크): 옅어짐. TDS TextButton 눌림 모양은 공식 글에 없음 → 우리 값.
/// 바탕이 있는 단추는 딤 덧칠(AppColors.pressDim), 목록 줄 · 아이콘 단추는 회색 바탕(AppColors.greyOpacity100)
const pressOpacity = 0.55;

/// 꺼진 단추·글자 단추·아이콘의 투명도(하나로, 2026-11-19 공통 규칙). TDS Button은 꺼질 때 바탕·글자 투명도만 바꾼다
/// (--button-disabled-opacity-color · --button-disabled-text-opacity, 값은 없음 → 우리 값 0.4)
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
