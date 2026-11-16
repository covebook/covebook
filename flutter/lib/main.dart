// 책장한켠(Flutter). 지금 앱(React Native, ../app)을 옮기는 중이다.
import 'dart:io';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

import 'domain/reference_home.dart';
import 'scene_config/spine_look.dart';
import 'store/skin_store.dart';
import 'package:flutter/services.dart';

import 'app/app_shell.dart';
import 'app/startup.dart';
import 'features/auth/login_screen.dart' show AuthGate;
import 'services/sync.dart';
import 'services/ambient.dart';
import 'services/cover_colors.dart';
import 'features/reading/mini_timer.dart';
import 'features/home/home_screen.dart' show bootAt, homeSnapshotFile;
import 'ui/bake.dart';
import 'store/mini_timer_store.dart';
import 'ui/kit.dart' show KeyboardRefocusGuard, Shape, Space;
import 'ui/theme.dart';

/// 시험 빌드 전용 프록시(예: --dart-define=QA_PROXY=127.0.0.1:8899 + adb reverse): 인터넷이 끊긴 에뮬레이터에서 표지·책 검색을 호스트로 보낸다. 출시 빌드는 비어 있다
const _qaProxy = String.fromEnvironment('QA_PROXY');

class _QaProxy extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context)
    ..findProxy = (uri) => uri.host == '127.0.0.1' || uri.host == 'localhost' ? 'DIRECT' : 'PROXY $_qaProxy';
}

Future<void> main() async {
  if (_qaProxy.isNotEmpty) HttpOverrides.global = _QaProxy();
  bootAt = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  // 시작 화면부터 그린다: 아래 준비가 몇 초 걸려 그동안 흰 화면만 보였다(지난 책장 사진이 있으면 그 사진)
  final snap = await usableSnapshot(homeSnapshotFile);
  startedWithSnapshot = snap != null;
  runApp(StartApp(snapshot: snap));
  // 환경음 배경 재생(잠금 화면·알림): 플레이어를 만들기 전에 준비해 둔다(기다리지 않는다)
  initAmbientBackground().catchError((Object e) {
    // ignore: avoid_print
    print('환경음 배경 재생 준비 실패 $e');
  });
  await initBake();
  // 기기에 재 둔 책등 비율·갈피 색(책장 책 크기·갈피 색)
  await loadCoverMeasures();
  // 고른 스킨(선반·벽지·벽)·책 측면 모양: 책장을 굽기 전에
  await loadSkin();
  await loadSpineLook();
  // 새 서재 예시 책장(표시 전용 예시 책): 책장을 읽기 전에
  await loadReferenceHome();
  // 로그인 화면을 띄울지: 이 기기에 남긴 계정 사본을 먼저 읽는다(서버 있는 빌드만)
  await SyncService.instance.loadLocalState();
  startStep.value = 2;
  runApp(const ChaekjangApp());
}

final appNavigator = GlobalKey<NavigatorState>();
final _miniTimerObserver = MiniTimerObserver();
final _refocusGuard = KeyboardRefocusGuard();

/// 머티리얼 기본 문구 한국어(앱은 한국어만): 화면 읽기가 시트 뒤 덮개를 영어 'Scrim', 시트를 'Dialog'로 읽었다(2026-11-16 QA 영숙 F10).
/// 글자 고르기 메뉴(복사·붙여넣기)도 한국어로
class KoMaterialLocalizations extends DefaultMaterialLocalizations {
  const KoMaterialLocalizations();
  static const LocalizationsDelegate<MaterialLocalizations> delegate = _KoMaterialDelegate();

  @override
  String get scrimLabel => '닫기';
  @override
  String scrimOnTapHint(String modalRouteContentName) => '$modalRouteContentName 닫기';
  @override
  String get bottomSheetLabel => '아래 시트';
  @override
  String get dialogLabel => '대화상자';
  @override
  String get alertDialogLabel => '알림';
  @override
  String get modalBarrierDismissLabel => '닫기';
  @override
  String get backButtonTooltip => '뒤로';
  @override
  String get closeButtonTooltip => '닫기';
  @override
  String get closeButtonLabel => '닫기';
  @override
  String get moreButtonTooltip => '더 보기';
  @override
  String get clearButtonTooltip => '지우기';
  @override
  String get okButtonLabel => '확인';
  @override
  String get cancelButtonLabel => '취소';
  @override
  String get copyButtonLabel => '복사';
  @override
  String get cutButtonLabel => '잘라내기';
  @override
  String get pasteButtonLabel => '붙여넣기';
  @override
  String get selectAllButtonLabel => '모두 선택';
  @override
  String get lookUpButtonLabel => '찾아보기';
  @override
  String get searchWebButtonLabel => '웹 검색';
  @override
  String get shareButtonLabel => '공유';
}

class _KoMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _KoMaterialDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) => SynchronousFuture(const KoMaterialLocalizations());
  @override
  bool shouldReload(_KoMaterialDelegate old) => false;
}

// 글자 자간: Material 3 기본 글자(bodyMedium 0.25 등)를 Text가 물려받아 모든 글자가 지금 앱보다 약 1.4% 넓었다(줄바꿈이 달라짐).
// 지금 앱(RN)은 자간을 따로 주지 않으면 0이다 → 테마 글자 전부 0
final appTheme = (() {
  final base = ThemeData(
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: AppFonts.ui,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, surface: AppColors.bg),
  );
  TextStyle? flat(TextStyle? s) => s?.copyWith(letterSpacing: 0);
  final t = base.textTheme;
  return base.copyWith(
    textTheme: TextTheme(
      displayLarge: flat(t.displayLarge), displayMedium: flat(t.displayMedium), displaySmall: flat(t.displaySmall),
      headlineLarge: flat(t.headlineLarge), headlineMedium: flat(t.headlineMedium), headlineSmall: flat(t.headlineSmall),
      titleLarge: flat(t.titleLarge), titleMedium: flat(t.titleMedium), titleSmall: flat(t.titleSmall),
      bodyLarge: flat(t.bodyLarge), bodyMedium: flat(t.bodyMedium), bodySmall: flat(t.bodySmall),
      labelLarge: flat(t.labelLarge), labelMedium: flat(t.labelMedium), labelSmall: flat(t.labelSmall),
    ),
    // 알림 줄(스낵바)은 떠 있는 탭 바 위에 띄운다: 화면 바닥에 붙으면 탭 바를 덮어 그동안 탭을 누를 수 없었다(2026-11-16 QA 현우 F1).
    // 되돌리기가 달린 알림이 정한 시간 뒤 사라지게 하는 것은 테마로 못 한다(Flutter 3.47: action이 있으면 persist 기본 true) → 부르는 곳에서 persist: false
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(TabBarStyle.side, Space.xs, TabBarStyle.side, TabBarStyle.navHeight + Space.s),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Shape.button)),
    ),
  );
})();

class ChaekjangApp extends StatelessWidget {
  const ChaekjangApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '책장한켠',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        localizationsDelegates: const [KoMaterialLocalizations.delegate],
        navigatorKey: appNavigator,
        // _refocusGuard: 돌아온 화면 입력칸이 초점을 되찾아 키보드가 저절로 뜨지 않게(ui/kit.dart, 2026-11-16 QA 영숙 F14)
        navigatorObservers: [_miniTimerObserver, _refocusGuard],
        // 서버가 있는 빌드는 로그인해야 책장이 열린다(2026-11-16)
        home: const AuthGate(child: AppShell()),
        // 공통 작은 타이머: 모든 화면 위에 한 겹(읽기 화면·읽기 탭에서는 숨는다)
        builder: (context, child) {
          // 글자 크기를 지금 앱처럼 화소로 올린다(RnTextScaler, ui/theme.dart)
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: RnTextScaler(mq.textScaler, mq.devicePixelRatio)),
            // 상태 표시줄 기본 = 어두운 글자(지금 앱 StatusBar style="dark"). 읽기 장면은 자기 화면에서 밝은 글자로 덮고, 나오면 이 값으로 돌아온다
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              // 아래 내비게이션 막대도 지금 앱처럼 투명 + 어두운 단추(세 단추 내비에서 Android가 덧씌우는 짙은 막 끄기)
              value: const SystemUiOverlayStyle(
                statusBarColor: Color(0x00000000),
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: Color(0x00000000),
                systemNavigationBarDividerColor: Color(0x00000000),
                systemNavigationBarIconBrightness: Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
              child: Stack(children: [
                ?child,
                Material(type: MaterialType.transparency, child: MiniTimer(navigator: appNavigator)),
              ]),
            ),
          );
        },
      );
}
