// 결제 경로와 구독 요금제(스토어가 준 가격·주기).
library;

import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

/// 이 기기의 결제 경로(서버의 route 값)
String get iapRoute => Platform.isIOS ? 'apple' : 'google';

/// 구독 요금제 하나(스토어가 준 가격과 결제 주기). 구글은 구독 상품 하나에 요금제가 여럿이라 상품 ID만으로는 구분되지 않는다
class IapPlan {
  const IapPlan({required this.details, required this.period, this.planId = ''});
  final ProductDetails details;

  /// 결제 주기: month, year. 스토어가 다른 주기를 주면 빈 값(화면에 내지 않는다)
  final String period;

  /// 구글 요금제(base plan) ID. 애플은 빈 값
  final String planId;

  String get price => details.price;

  /// 화면에 보일 주기(고지 문구 T1의 {주기})
  String get periodLabel => period == 'year' ? '매년' : '매월';
  String get name => period == 'year' ? '연간' : '월간';
}

/// 구글이 주는 결제 주기(ISO 8601: P1M, P1Y)를 month, year로. 그 밖은 빈 값
String iapPeriodOf(String iso) => switch (iso) { 'P1M' => 'month', 'P1Y' || 'P12M' => 'year', _ => '' };

/// 스토어 상품에서 요금제를 읽는다. 구독이 아니거나 월·연이 아니면 null
IapPlan? iapPlanOf(ProductDetails d) {
  if (d is GooglePlayProductDetails) {
    final i = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    if (i == null || offers == null) return null;
    final offer = offers[i];
    // 할인·체험이 붙은 제안은 뺀다(기본 요금제만 판다). 가격이 달라지는 조건을 화면에 다 적을 수 없으면 팔지 않는다
    if (offer.offerId != null || offer.pricingPhases.length != 1) return null;
    final period = iapPeriodOf(offer.pricingPhases.last.billingPeriod);
    return period.isEmpty ? null : IapPlan(details: d, period: period, planId: offer.basePlanId);
  }
  if (d is AppStoreProduct2Details) {
    final p = d.sk2Product.subscription?.subscriptionPeriod;
    if (p == null || p.value != 1) return null;
    return switch (p.unit) {
      SK2SubscriptionPeriodUnit.month => IapPlan(details: d, period: 'month'),
      SK2SubscriptionPeriodUnit.year => IapPlan(details: d, period: 'year'),
      _ => null,
    };
  }
  if (d is AppStoreProductDetails) {
    final p = d.skProduct.subscriptionPeriod;
    if (p == null || p.numberOfUnits != 1) return null;
    return switch (p.unit) {
      SKSubscriptionPeriodUnit.month => IapPlan(details: d, period: 'month'),
      SKSubscriptionPeriodUnit.year => IapPlan(details: d, period: 'year'),
      _ => null,
    };
  }
  return null;
}
