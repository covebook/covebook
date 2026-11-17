// 로그인 화면과 로그인 문(2026-11-16 사용자: 시작할 때 무조건 로그인).
// 서버가 있는 빌드는 카카오·Apple·Google 중 하나로 로그인해야 책장이 열린다. 서버 없는 시험 빌드는 문을 지나친다.
// 로그인은 기존 계정 연결 흐름(SyncService.link*) 그대로: 기기 계정을 만들고 소셜 계정을 붙인다. 이미 있는 계정이면 그 계정으로 바뀌고 서버 기록을 받아 온다
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/sync.dart';
import '../../ui/alert.dart';
import '../../ui/brand_button.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../settings/settings_screen.dart' show privacyUrl;
import '../settings/terms.dart' show showTermsSheet;

/// 로그인했을 때만 child(앱)를 보여 준다. required를 주지 않으면 서버가 있는 빌드에서만 막는다
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child, this.required});
  final Widget child;
  final bool? required;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SyncService.instance,
        builder: (context, _) {
          final s = SyncService.instance;
          return (required ?? s.loginRequired) && !s.loggedIn ? const LoginScreen() : child;
        },
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _sync = SyncService.instance;
  bool? _ready; // 로그인 수단을 받았는지(null: 받는 중)
  String? _busy; // 로그인 중인 수단

  @override
  void initState() {
    super.initState();
    final p = _sync.providers;
    _ready = _sync.providersKnown || p.kakao || p.apple || p.google ? true : null;
    _load();
  }

  Future<void> _load() async {
    if (_ready != true) setState(() => _ready = null);
    final ok = await _sync.refreshProviders();
    final p = _sync.providers;
    if (mounted) setState(() => _ready = ok || _sync.providersKnown || p.kakao || p.apple || p.google);
  }

  Future<void> _login(String provider) async {
    setState(() => _busy = provider);
    try {
      final r = await (provider == 'apple' ? _sync.linkApple() : provider == 'google' ? _sync.linkGoogle() : _sync.linkKakao());
      if (!mounted) return;
      // 성공하면 계정 사본이 바뀌어 AuthGate가 앱을 연다
      if (!r.ok && !r.cancelled) appAlert(context, '로그인하지 못했어요', r.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _sync.providers;
    final off = _busy != null;
    final buttons = <Widget>[
      // 카카오 · Google · Apple 순(2026-11-17 사용자 시안)
      if (p.kakao) BrandButton.kakao(onPress: off ? null : () => _login('kakao')),
      if (p.google) BrandButton.google(onPress: off ? null : () => _login('google')),
      if (p.apple) BrandButton.apple(onPress: off ? null : () => _login('apple')),
    ];
    Widget bottom;
    if (_ready == null) {
      bottom = const SizedBox(height: 54, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))));
    } else if (_ready == false || buttons.isEmpty) {
      bottom = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        WordText(_ready == false ? '로그인 방법을 불러오지 못했어요. 인터넷 연결을 확인해 주세요.' : '지금은 로그인할 수 없어요. 잠시 뒤 다시 시도해 주세요.',
            textAlign: TextAlign.center, style: AppType.sub),
        const SizedBox(height: Space.m),
        Btn(label: '다시 시도', kind: 'secondary', onPress: _load),
      ]);
    } else {
      bottom = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, b) in buttons.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : Space.s), child: b),
      ]);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        // 시작 화면과 같은 책·선반(quiet-start.png에서 잘라 둔 그림)
                        ExcludeSemantics(child: Image.asset('assets/loading/login-shelf.png', width: 210, gaplessPlayback: true)),
                        const SizedBox(height: Space.l),
                        Semantics(
                          header: true,
                          child: Text('책장 한켠', textAlign: TextAlign.center, style: AppType.title.copyWith(color: AppColors.accent)),
                        ),
                        const SizedBox(height: Space.s),
                        WordText('읽은 책을 책장에 진열하고,\n읽은 시간과 문장을 남겨요', textAlign: TextAlign.center, style: AppType.sub),
                      ]),
                    ),
                  ),
                ),
                if (off)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.m),
                    child: WordText('로그인하는 중…', textAlign: TextAlign.center, style: AppType.caption),
                  ),
                bottom,
                // 단추 아래 긴 설명은 뺐다(2026-11-17 사용자 '구구절절 설명 지워'): 처리방침 글자 단추만
                const SizedBox(height: Space.xl),
                // 이용약관 · 개인정보 처리방침 두 글자 단추(2026-11-18 약관 추가)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft, minimumSize: const Size(Space.hit, Space.hit)),
                    onPressed: () => showTermsSheet(context),
                    child: Text('이용약관', style: AppType.caption.copyWith(fontFamily: AppFonts.uiMedium)),
                  ),
                  ExcludeSemantics(child: Text('·', style: AppType.caption)),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft, minimumSize: const Size(Space.hit, Space.hit)),
                    onPressed: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication),
                    child: Text('개인정보 처리방침', style: AppType.caption.copyWith(fontFamily: AppFonts.uiMedium)),
                  ),
                ]),
                const SizedBox(height: Space.s),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
