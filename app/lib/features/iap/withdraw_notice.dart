// 탈퇴 화면의 구독 안내(고지 문구 T12). 구독 중인 계정이 탈퇴하려 할 때 탈퇴해도 스토어 구독은 해지되지 않는다고 먼저 알린다.
// 탈퇴를 막지 않는다. '탈퇴 계속'을 누르면 원래 탈퇴 확인으로 간다(탈퇴 경로를 숨기지 않는다, ADR-0003).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../store/entitlement_store.dart';
import '../../ui/alert.dart';
import 'subscription_screen.dart' show storeManageUrl, storeName;

/// 가운데 확인창으로 알린다(이어지는 탈퇴 확인도 가운데 창이다)
Future<void> showWithdrawNotice(BuildContext context, IapSubscription sub, {required VoidCallback onContinue}) {
  final store = storeName(sub.route);
  return appAlert(
    context,
    '지금 책장 한켠 플러스를 구독하고 있습니다',
    '탈퇴해도 $store 구독은 자동으로 해지되지 않습니다. 먼저 $store에서 구독을 해지해 주세요.',
    [
      AlertButton('$store에서 해지하기', onPress: () => launchUrl(storeManageUrl(sub.route, sub.productId), mode: LaunchMode.externalApplication).then((_) {}, onError: (_) {})),
      AlertButton('탈퇴 계속', onPress: onContinue),
      const AlertButton('취소', style: AlertStyle.cancel),
    ],
    true,
    true,
  );
}
