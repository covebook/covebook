// 앱 안 로그인(공급자 SDK, 2026-11-18 사용자: 브라우저 대신 카카오톡·Apple·Google 앱 안 로그인).
// SDK가 준 토큰을 서버 /auth/<공급자>/native로 보내면 서버가 공급자에게 직접 확인하고 계정을 잇는다.
//   카카오: Android·iOS 모두 SDK(카카오톡이 있으면 카카오톡으로, 없으면 카카오계정 창)
//   Apple: iOS만 SDK(Face ID 시트). Android는 Apple SDK가 없어 지금 브라우저 흐름
//   Google: Android만 SDK(자격 증명 관리자 계정 고르기). iOS는 Google SDK도 같은 시스템 웹 창이라 지금 브라우저 흐름
// SDK가 실패하면(설정 누락·기기에 Google 계정 없음 등) 부르는 쪽이 브라우저 흐름으로 넘어간다. 사용자가 닫은 것만 취소로 본다
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// 카카오 네이티브 앱 키(앱 안에 들어가는 공개 키). 카카오는 키마다 Android 패키지가 하나라
/// 시험 빌드(app.covebook.flqa, 디버그 서명)는 따로 만든 'QA 시험 빌드' 키를 쓴다. Android 주소 스킴은 build.gradle.kts가 같은 기준으로 고른다
const kakaoNativeKey = '86ba9f3ec4b64b2b00d66ddd1aaa2058';
const kakaoQaNativeKey = 'c4bb117637fe6f725f697b033b775ec9';

/// Google 웹 클라이언트(Covebook Login 프로젝트). 앱 안 로그인 ID 토큰의 aud가 되고 서버가 확인한다.
/// Android 클라이언트(app.covebook·app.covebook.flqa와 서명 SHA-1)는 같은 프로젝트에 등록해 두었다
const googleServerClientId = '987592975790-vbto284bbv1csukbhgv0gvulc1ue7lad.apps.googleusercontent.com';

/// 사용자가 로그인 창을 닫았다
class NativeLoginCancelled implements Exception {}

/// 이 기기에서 그 공급자를 앱 안 로그인으로 할지
bool nativeLoginAvailable(String provider) => switch (provider) {
  'kakao' => Platform.isAndroid || Platform.isIOS,
  'apple' => Platform.isIOS,
  'google' => Platform.isAndroid,
  _ => false,
};

/// SDK 로그인을 하고 서버에 보낼 값을 돌려준다
Future<Map<String, String>> nativeLogin(String provider) => switch (provider) {
  'kakao' => _kakao(),
  'apple' => _apple(),
  'google' => _google(),
  _ => throw UnsupportedError(provider),
};

bool _kakaoReady = false;

Future<Map<String, String>> _kakao() async {
  if (!_kakaoReady) {
    final pkg = (await PackageInfo.fromPlatform()).packageName;
    await KakaoSdk.init(nativeAppKey: pkg.endsWith('.flqa') ? kakaoQaNativeKey : kakaoNativeKey);
    _kakaoReady = true;
  }
  bool cancelled(Object e) =>
      (e is PlatformException && e.code == 'CANCELED') || (e is KakaoAuthException && e.error == AuthErrorCause.accessDenied);
  try {
    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      try {
        token = await UserApi.instance.loginWithKakaoTalk();
      } catch (e) {
        if (cancelled(e)) rethrow;
        // 카카오톡에 로그인돼 있지 않거나 연결이 안 된 경우: 카카오계정 창으로
        token = await UserApi.instance.loginWithKakaoAccount();
      }
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }
    return {'accessToken': token.accessToken};
  } catch (e) {
    if (cancelled(e)) throw NativeLoginCancelled();
    rethrow;
  }
}

Future<Map<String, String>> _apple() async {
  // 서버는 기기 토큰의 nonce가 이 값인지 본다(가로챈 토큰을 다른 요청에 못 쓰게)
  final r = Random.secure();
  final nonce = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  try {
    final c = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      nonce: nonce,
    );
    final token = c.identityToken;
    if (token == null) throw StateError('Apple 로그인 응답을 읽지 못했어요');
    // 이름은 처음 로그인할 때 한 번만 온다. 한글 이름은 성·이름을 붙이고, 그 밖은 '이름 성'
    final given = c.givenName?.trim() ?? '', family = c.familyName?.trim() ?? '';
    final hangul = RegExp(r'[가-힣]').hasMatch(given + family);
    final name = hangul ? '$family$given' : [given, family].where((v) => v.isNotEmpty).join(' ');
    return {'idToken': token, 'authorizationCode': c.authorizationCode, 'nonce': nonce, if (name.isNotEmpty) 'name': name};
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) throw NativeLoginCancelled();
    rethrow;
  }
}

bool _googleReady = false;

Future<Map<String, String>> _google() async {
  final g = GoogleSignIn.instance;
  if (!_googleReady) {
    await g.initialize(serverClientId: googleServerClientId);
    _googleReady = true;
  }
  try {
    final account = await g.authenticate(scopeHint: const ['email', 'profile']);
    final token = account.authentication.idToken;
    if (token == null) throw StateError('Google 로그인 응답을 읽지 못했어요');
    // 다음 로그인 때 계정을 다시 고를 수 있게 SDK 쪽 기억은 지운다(우리 계정 연결은 서버 토큰으로 유지된다)
    g.signOut().ignore();
    return {'idToken': token};
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) throw NativeLoginCancelled();
    rethrow;
  }
}
