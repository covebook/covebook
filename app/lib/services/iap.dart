// 인앱결제(스토어 결제 창과 서버 검증 사이를 잇는다). 결정 기록: docs/adr/0002-iap-design.md
//
// 흐름: 서버에서 계정 연결 값을 받는다 → 스토어 결제 → 스토어가 준 구매 증거를 서버에 낸다 → 서버가 지급했다고 답하면 거래를 끝낸다.
// - 지급 근거는 서버가 스토어에 다시 물어 받은 답이다. 앱은 증거를 전달만 한다.
// - 거래를 끝내는 것은 서버 응답 뒤다(D10). 끝내지 않은 거래는 스토어가 앱을 켤 때 다시 준다. 그러면 다시 낸다.
// - 구매 증거: 애플은 스토어가 서명한 거래(StoreKit 2의 JWS), 구글은 구매 토큰. 둘 다 verificationData.serverVerificationData에 있다.
// - 안드로이드의 확인(acknowledge·consume)은 서버가 한다. 앱은 completePurchase를 부르지 않는다(서버가 거절한 구매를 앱이 확인해 버리지 않게).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../db/kv_store.dart';
import '../store/entitlement_store.dart';
import 'sync.dart' show ApiError, api, syncTokenKey;

/// 서버 응답을 보고 스토어 거래를 끝내도 되는지 정한다.
/// - 200: 지급했거나 전에 지급한 거래 → 끝낸다
/// - 409, 422: 환불됐거나 다른 계정·다른 앱의 구매. 다시 내도 결과가 같다 → 끝낸다
/// - 그 밖(결제 대기 202, 스토어 확인 실패 503, 요청이 많음 429, 통신 실패): 끝내지 않는다. 다시 낼 수 있어야 한다
/// - 증거를 확인할 수 없음(iap_bad_proof), 스토어에 없는 거래(404): 끝내지 않는다. 서버 쪽 문제일 수 있어 구매를 버리지 않는다
bool iapShouldFinish({required int status, String code = ''}) {
  if (status == 200) return true;
  if (code == 'iap_bad_proof') return false;
  return status == 409 || status == 422;
}

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

enum IapResult { granted, already, inactive, pending, rejected, retryLater }

class IapService extends ChangeNotifier {
  IapService._();
  static final instance = IapService._();

  // 스토어 플러그인은 실제로 쓸 때 처음 만든다(결제가 꺼진 빌드와 시험에서는 만들지 않는다)
  InAppPurchase get _store => InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _restoring = false;

  /// 결제·복원이 진행 중인지(버튼을 잠근다. 연타와 결제 중 계정 전환을 막는다)
  bool busy = false;

  /// 마지막 결과와 사용자에게 보일 말
  IapResult? lastResult;
  String? lastMessage;

  /// 스토어가 알려 준 상품(가격 문자열 포함). 키는 상품 ID
  Map<String, ProductDetails> details = const {};

  /// 살 수 있는 구독 요금제(월간 먼저)
  List<IapPlan> plans = const [];

  /// 앱을 켤 때 한 번: 스토어가 주는 거래를 듣기 시작하고 서버에서 내 상태를 받는다.
  /// 끝내지 않은 거래는 여기서 다시 와서 서버에 다시 낸다.
  Future<void> start() async {
    if (!iapOn || _sub != null) return;
    await EntitlementStore.instance.restore();
    _sub = _store.purchaseStream.listen(_onPurchases, onError: (Object _) {});
    await refresh();
  }

  /// 서버에서 내 상태와 상품 목록을 받고, 스토어에서 그 상품의 가격을 받는다
  Future<void> refresh() async {
    if (!iapOn) return;
    final token = await KvStore.get(syncTokenKey);
    if (token == null) return;
    try {
      final me = await api('GET', '/iap/me', token);
      if (me is Map<String, dynamic>) EntitlementStore.instance.apply(me);
    } catch (_) {
      return; // 서버에 닿지 못하면 지난번 값으로 둔다
    }
    final ids = {for (final p in EntitlementStore.instance.products) if (p.route == iapRoute) p.productId};
    if (ids.isEmpty || !await _store.isAvailable()) return;
    final res = await _store.queryProductDetails(ids);
    // 구글은 구독 하나에 요금제마다 한 줄씩 온다(상품 ID가 같다). 상품 ID로는 첫 줄만 남기고, 요금제는 따로 모은다
    details = {for (final d in res.productDetails.reversed) d.id: d};
    final subs = {for (final p in EntitlementStore.instance.products) if (p.kind == 'subscription') p.productId};
    plans = [for (final d in res.productDetails) if (subs.contains(d.id)) ?iapPlanOf(d)]..sort((a, b) => a.period.compareTo(b.period));
    notifyListeners();
  }

  /// 구매를 시작한다. 결과는 purchaseStream으로 온다
  /// plan: 구독은 고른 요금제를 넘긴다(구글은 요금제마다 스토어 상품 줄이 다르다)
  Future<void> buy(IapProduct product, {IapPlan? plan}) async {
    final d = plan?.details ?? details[product.productId];
    final account = EntitlementStore.instance.accountToken;
    if (busy || d == null || account.isEmpty) return;
    _busy(true);
    try {
      // 계정 연결 값을 스토어에 넘긴다(애플 appAccountToken, 구글 obfuscatedAccountId). 서버가 이 값으로 누구의 구매인지 본다
      final param = PurchaseParam(productDetails: d, applicationUserName: account);
      if (product.kind == 'subscription') {
        await _store.buyNonConsumable(purchaseParam: param);
      } else {
        // 소비는 서버가 한다(autoConsume을 끈다)
        await _store.buyConsumable(purchaseParam: param, autoConsume: false);
      }
    } catch (_) {
      _done(IapResult.retryLater, '결제를 시작하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    }
  }

  /// 구매 복원: 스토어가 이 스토어 계정의 구매를 다시 준다. 구독이 다른 계정에 있었으면 이 계정으로 옮겨진다(D8)
  Future<void> restorePurchases() async {
    if (busy) return;
    _busy(true);
    _restoring = true;
    try {
      await _store.restorePurchases(applicationUserName: EntitlementStore.instance.accountToken);
      // 복원할 것이 없으면 스토어가 아무것도 보내지 않는다. 잠깐 기다렸다가 끝낸다
      await Future<void>.delayed(const Duration(seconds: 3));
      if (busy) _done(lastResult ?? IapResult.inactive, lastMessage ?? '복원할 구매가 없어요.');
    } catch (_) {
      _done(IapResult.retryLater, '복원하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
    } finally {
      _restoring = false;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final d in list) {
      await _handle(d);
    }
  }

  Future<void> _handle(PurchaseDetails d) async {
    switch (d.status) {
      case PurchaseStatus.pending:
        _busy(true);
        return;
      case PurchaseStatus.canceled:
        if (Platform.isIOS && d.pendingCompletePurchase) await _store.completePurchase(d);
        _done(IapResult.rejected, null);
        return;
      case PurchaseStatus.error:
        if (Platform.isIOS && d.pendingCompletePurchase) await _store.completePurchase(d);
        _done(IapResult.retryLater, '결제가 이뤄지지 않았어요.');
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final result = await _submit(d, restore: _restoring || d.status == PurchaseStatus.restored);
        final finish = result.$2;
        // 애플만 앱이 거래를 끝낸다. 안드로이드는 서버가 확인·소비한다
        if (finish && Platform.isIOS && d.pendingCompletePurchase) await _store.completePurchase(d);
        _done(result.$1, result.$3);
    }
  }

  /// 구매 증거를 서버에 낸다. (결과, 거래를 끝내도 되는지, 사용자에게 보일 말)
  Future<(IapResult, bool, String?)> _submit(PurchaseDetails d, {required bool restore}) async {
    final token = await KvStore.get(syncTokenKey);
    final proof = d.verificationData.serverVerificationData;
    if (token == null || proof.isEmpty) return (IapResult.retryLater, false, '구매를 확인하지 못했어요. 앱을 다시 켜면 이어서 확인해요.');
    try {
      final res = await api('POST', '/iap/purchases', token, {'route': iapRoute, 'productId': d.productID, 'proof': proof, 'restore': restore});
      if (res is! Map<String, dynamic>) {
        // 202: 결제가 아직 끝나지 않았다
        return (IapResult.pending, false, '결제를 확인하고 있어요. 끝나면 자동으로 반영돼요.');
      }
      EntitlementStore.instance.apply(res);
      return switch (res['status']) {
        'already' => (IapResult.already, true, restore ? '구매를 복원했어요.' : null),
        'inactive' => (IapResult.inactive, true, '구독 기간이 끝난 구매예요.'),
        _ => (IapResult.granted, true, restore ? '구매를 복원했어요.' : null),
      };
    } on ApiError catch (e) {
      final finish = iapShouldFinish(status: e.status, code: e.code);
      return (finish ? IapResult.rejected : IapResult.retryLater, finish, e.message);
    } catch (_) {
      return (IapResult.retryLater, false, '구매를 확인하지 못했어요. 앱을 다시 켜면 이어서 확인해요.');
    }
  }

  void _busy(bool v) {
    busy = v;
    notifyListeners();
  }

  void _done(IapResult r, String? message) {
    busy = false;
    lastResult = r;
    lastMessage = message;
    notifyListeners();
  }
}
