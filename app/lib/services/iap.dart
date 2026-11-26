// 인앱결제(스토어 결제 창과 서버 검증 사이를 잇는다). 결정 기록: docs/adr/0002-iap-design.md
//
// 흐름: 서버에서 계정 연결 값을 받는다 → 스토어 결제 → 스토어가 준 구매 증거를 서버에 낸다 → 서버가 지급했다고 답하면 거래를 끝낸다.
// - 지급 근거는 서버가 스토어에 다시 물어 받은 답이다. 앱은 증거를 전달만 한다.
// - 거래를 끝내는 것은 서버 응답 뒤다(D10). 끝내지 않은 거래는 iOS는 앱을 켤 때 스토어가 다시 주고, 안드로이드는 앱이 직접 물어 다시 낸다.
// - 구매 증거: 애플은 스토어가 서명한 거래(StoreKit 2의 JWS), 구글은 구매 토큰. 둘 다 verificationData.serverVerificationData에 있다.
// - 안드로이드의 확인(acknowledge·consume)은 서버가 한다. 앱은 completePurchase를 부르지 않는다(서버가 거절한 구매를 앱이 확인해 버리지 않게).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart' hide kIAPSource; // 같은 이름이 storekit에도 있다. 여기서는 애플 값을 쓴다
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import '../db/kv_store.dart';
import '../store/entitlement_store.dart';
import 'sync.dart' show ApiError, api, syncTokenKey;

/// 서버 응답을 보고 스토어 거래를 끝내도 되는지 정한다.
/// - 200: 지급했거나 전에 지급한 거래 → 끝낸다
/// - 409, 422: 환불됐거나 다른 계정·다른 앱의 구매. 다시 내도 결과가 같다 → 끝낸다
///   (다른 계정이 결제한 선반은 서버가 결제한 계정에 넣은 뒤 409를 준다)
/// - 그 밖(결제 대기 202, 스토어 확인 실패 503, 요청이 많음 429, 통신 실패): 끝내지 않는다. 다시 낼 수 있어야 한다
/// - 증거를 확인할 수 없음(iap_bad_proof), 스토어에 없는 거래(404): 끝내지 않는다. 서버 쪽 문제일 수 있어 구매를 버리지 않는다
/// - 어느 해 책장인지 모름(iap_shelf_year_missing): 끝내지 않는다. 서버가 소비하지 않았으니 연도를 붙여 다시 낼 수 있다
/// - 우리 상품 테이블에 없는 상품(iap_unknown_product): 끝내지 않는다. 우리 설정 문제라 고친 뒤 다시 낸다
bool iapShouldFinish({required int status, String code = ''}) {
  if (status == 200) return true;
  if (code == 'iap_bad_proof' || code == 'iap_shelf_year_missing' || code == 'iap_unknown_product') return false;
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
  AppLifecycleListener? _life;
  DateTime? _lastResubmit;

  /// 계정 세대. reset()마다 오른다. 비동기 일은 시작할 때 값을 잡아 두고, 끝났을 때 값이 다르면(그사이 계정이 바뀌었으면)
  /// 앞 계정의 응답을 지금 계정의 상태에 넣지 않는다
  int _epoch = 0;

  /// 이번 실행에서 선반을 사려고 연 책장의 연도. 구매 제출에 같이 보낸다(서버는 계정 연결 값의 연도를 먼저 본다)
  int? _shelfYear;

  /// 선반 결제 중 예약 번호(서버가 5분 동안 그 해 칸을 잡아 둔다. 두 기기가 함께 사서 3칸을 넘지 않게).
  /// 결제를 취소하거나 실패하면 바로 푼다. 제출하면 서버가 푼다
  String? _reservation;

  /// 지금 결제창을 띄운 상품. 예약 번호와 연도는 이 상품의 거래에만 붙인다(전에 끝내지 못한 다른 거래가 가져가지 않게)
  String? _buying;
  bool _restoring = false;

  /// 결제·복원이 진행 중인지(버튼을 잠근다. 연타와 결제 중 계정 전환을 막는다)
  bool busy = false;

  /// 스토어에서 상품과 가격을 받는 중인지(화면이 '살 수 없어요'를 먼저 보이지 않게)
  bool loading = false;

  /// 이번 실행에서 서버 상태를 받았는지(기기에 남긴 지난번 값이 아니라)
  bool synced = false;

  /// 마지막 결과와 사용자에게 보일 말
  IapResult? lastResult;
  String? lastMessage;

  /// 스토어가 알려 준 상품(가격 문자열 포함). 키는 상품 ID
  Map<String, ProductDetails> details = const {};

  /// 살 수 있는 구독 요금제(월간 먼저)
  List<IapPlan> plans = const [];

  /// 책장 화면이 뜰 때마다(앱을 켤 때, 로그아웃 뒤 다시 로그인했을 때): 서버에서 지금 계정의 상태를 받는다.
  /// 스토어의 거래를 듣는 일은 앱 실행당 한 번이고, 상태 받기는 계정마다 한다(로그인하면 셸이 새로 만들어져 다시 불린다).
  /// iOS는 끝내지 않은 거래가 구매 스트림으로 다시 온다. 안드로이드는 다시 오지 않아 직접 묻는다(_resubmitAndroid)
  Future<void> start() async {
    if (!iapOn) return;
    final first = _sub == null;
    if (first) _sub = _store.purchaseStream.listen(_onPurchases, onError: (Object _) {});
    await EntitlementStore.instance.restore();
    await refresh();
    if (Platform.isAndroid) {
      unawaited(_resubmitAndroid());
      // 다시 앞으로 올 때도 묻는다(결제 대기가 앱 밖에서 끝난 경우 등). 결제창에서 돌아올 때는 구매 스트림이 처리하므로 건너뛴다
      if (first) {
        _life = AppLifecycleListener(onResume: () {
          if (!busy) unawaited(_resubmitAndroid());
        });
      }
    }
  }

  /// 로그아웃·계정 전환 때(local_reset) 앞 계정의 값을 비운다. 특히 synced: 남아 있으면 새 계정의 상태를 받기 전에
  /// 비워진 칸 수(0)로 선반을 닫는 일(enforceShelfLimit)이 돈다. 스토어 듣기는 그대로 둔다(앱 실행당 한 번)
  void reset() {
    _epoch++;
    // 앞 계정의 refresh가 아직 돌고 있어도 새 계정의 refresh가 돌 수 있게 푼다. 앞 계정의 응답은 세대가 달라 버린다
    loading = false;
    synced = false;
    details = const {};
    plans = const [];
    busy = false;
    lastResult = null;
    lastMessage = null;
    _buying = null;
    _shelfYear = null;
    _reservation = null;
    _lastResubmit = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _life?.dispose();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  /// 안드로이드: 결제는 됐는데 서버가 아직 확인(소비)하지 못한 구매를 스토어에 물어 다시 낸다.
  /// 구매 스트림은 앱이 떠 있을 때만 와서, 제출이 실패한 채 앱이 꺼지면 다시 오지 않는다. 3일 안에 확인하지 않으면 구글이 환불한다.
  /// 복원(restore)으로 내지 않는다. 다른 계정의 구독을 이 계정으로 옮기지 않게
  Future<void> _resubmitAndroid() async {
    final now = DateTime.now();
    if (_lastResubmit != null && now.difference(_lastResubmit!) < const Duration(minutes: 1)) return;
    _lastResubmit = now;
    try {
      final past = await _store.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>().queryPastPurchases();
      for (final p in past.pastPurchases) {
        if (p.status != PurchaseStatus.purchased || p.billingClientPurchase.isAcknowledged) continue;
        await _submit(p, restore: false);
      }
    } catch (_) {
      // 스토어에 닿지 못했다. 다음 실행에 다시 본다
    }
  }

  /// 서버에서 내 상태와 상품 목록을 받고, 스토어에서 그 상품의 가격을 받는다
  Future<void> refresh() async {
    if (!iapOn || loading) return;
    loading = true; // 여기서는 알리지 않는다(화면의 initState 안에서 불린다). 끝날 때 알린다
    final epoch = _epoch;
    try {
      final token = await KvStore.get(syncTokenKey);
      if (token == null || epoch != _epoch) return;
      try {
        final me = await api('GET', '/iap/me', token);
        if (epoch != _epoch) return; // 그사이 로그아웃했다
        if (me is Map<String, dynamic>) {
          EntitlementStore.instance.apply(me);
          synced = true;
        }
      } catch (_) {
        return; // 서버에 닿지 못하면 지난번 값으로 둔다
      }
      final ids = {for (final p in EntitlementStore.instance.products) if (p.route == iapRoute) p.productId};
      if (ids.isEmpty || !await _store.isAvailable()) return;
      final res = await _store.queryProductDetails(ids);
      if (epoch != _epoch) return;
      // 구글은 구독 하나에 요금제마다 한 줄씩 온다(상품 ID가 같다). 상품 ID로는 첫 줄만 남기고, 요금제는 따로 모은다
      details = {for (final d in res.productDetails.reversed) d.id: d};
      final subs = {for (final p in EntitlementStore.instance.products) if (p.kind == 'subscription') p.productId};
      plans = [for (final d in res.productDetails) if (subs.contains(d.id)) ?iapPlanOf(d)]..sort((a, b) => a.period.compareTo(b.period));
    } catch (_) {
      // 스토어에 닿지 못했다: 상품 없이 둔다
    } finally {
      // 세대가 바뀌었으면 loading은 reset이 이미 풀었고, 새 계정의 refresh가 다시 잡았을 수 있다. 건드리지 않는다
      if (epoch == _epoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// plan: 구독은 고른 요금제를 넘긴다(구글은 요금제마다 스토어 상품 줄이 다르다)
  /// year: 선반은 칸을 열 연도 책장(없으면 지금 책장). 서버가 연도마다 따로 준 계정 연결 값을 스토어에 넘긴다(ADR-0002 D1·D7)
  Future<void> buy(IapProduct product, {IapPlan? plan, int? year}) async {
    final d = plan?.details ?? details[product.productId];
    final shelf = product.kind != 'subscription';
    if (busy || d == null || (!shelf && EntitlementStore.instance.accountToken.isEmpty)) return;
    _busy(true);
    try {
      String? account = EntitlementStore.instance.accountToken;
      if (shelf) {
        final y = year ?? liveShelfYear();
        try {
          final t = await shelfToken(y, shelves: product.shelves);
          account = t?.token;
          _reservation = t?.reservation;
        } on ApiError catch (e) {
          if (e.code == 'iap_shelf_full') {
            // 다른 기기에서 그사이 칸을 샀다(다 열었거나, 고른 상품이 남은 칸보다 많다). 결제창을 띄우지 않고 칸 수를 다시 받는다
            await refresh();
            _done(IapResult.rejected, EntitlementStore.instance.shelvesFor(y) >= paidShelfMax ? '이 책장의 선반은 모두 열었어요.' : '이 책장에 남은 칸이 바뀌었어요. 다시 골라 주세요.');
            return;
          }
          if (e.code == 'iap_shelf_busy') {
            _done(IapResult.retryLater, '다른 기기에서 이 책장의 선반을 결제하고 있어요. 잠시 뒤 다시 시도해 주세요.');
            return;
          }
          rethrow;
        }
        _shelfYear = y;
        _buying = product.productId;
      }
      if (account == null || account.isEmpty) {
        _done(IapResult.retryLater, '결제를 시작하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
        return;
      }
      // 계정 연결 값을 스토어에 넘긴다(애플 appAccountToken, 구글 obfuscatedAccountId). 서버가 이 값으로 누구의 구매인지 본다
      final param = PurchaseParam(productDetails: d, applicationUserName: account);
      // 결제창을 띄우지 못하면 false가 온다(구글 launchBillingFlow가 OK가 아님). 이때는 구매 스트림이 오지 않을 수 있어 여기서 끝낸다
      final started = product.kind == 'subscription'
          ? await _store.buyNonConsumable(purchaseParam: param)
          // 안드로이드 소비는 서버가 한다(autoConsume을 끈다). iOS 플러그인은 true만 받는다(디버그 빌드 assert). iOS는 앱이 거래를 끝낸다
          : await _store.buyConsumable(purchaseParam: param, autoConsume: Platform.isIOS);
      if (!started) _failStart();
    } on PlatformException catch (e) {
      // iOS: 같은 상품에 끝내지 않은 거래가 있으면 새 결제를 받지 않는다(서버가 404·503이라 앱이 끝내지 않은 거래).
      // 그 거래는 앱을 다시 켜야 스트림으로 다시 오므로, 여기서 꺼내 서버에 다시 내고 결과대로 끝낸다
      if (Platform.isIOS && e.code == 'storekit_duplicate_product_object') {
        unawaited(_release());
        _buying = null;
        _shelfYear = null;
        final cleared = await _resubmitIos();
        _done(
          IapResult.retryLater,
          cleared ? '끝나지 않은 지난 결제를 먼저 확인했어요. 반영된 내용을 확인한 뒤 필요하면 다시 결제해 주세요.' : '지난 결제를 아직 확인하지 못해 새 결제를 시작할 수 없어요. 잠시 뒤 다시 시도해 주세요.',
        );
        return;
      }
      _failStart();
    } catch (_) {
      _failStart();
    }
  }

  /// 지금 결제가 취소·실패했다. 뒤에 같은 상품의 옛 거래를 다시 낼 때 이번 연도가 붙지 않게 비운다
  void _forgetBuying(String productId) {
    if (productId != _buying) return;
    _buying = null;
    _shelfYear = null;
  }

  void _failStart() {
    unawaited(_release());
    _buying = null;
    _shelfYear = null;
    _done(IapResult.retryLater, '결제를 시작하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
  }

  /// iOS: 끝내지 않은 거래(StoreKit 2 Transaction.unfinished)를 서버에 다시 내고, 끝내도 되는 것만 끝낸다.
  /// 전부 끝냈으면 true. 하나라도 남았으면(서버가 404·503 등) false: 같은 상품은 그 거래가 끝날 때까지 새로 살 수 없다
  Future<bool> _resubmitIos() async {
    var cleared = true;
    try {
      for (final t in await SK2Transaction.unfinishedTransactions()) {
        final proof = t.receiptData ?? '';
        if (proof.isEmpty) continue;
        final d = SK2PurchaseDetails(
          productID: t.productId,
          purchaseID: t.id,
          verificationData: PurchaseVerificationData(localVerificationData: t.jsonRepresentation ?? '', serverVerificationData: proof, source: kIAPSource),
          transactionDate: t.purchaseDate,
          status: PurchaseStatus.purchased,
          appAccountToken: t.appAccountToken,
          sk2Transaction: t,
        );
        final result = await _submit(d, restore: false);
        if (result.$2) {
          await _store.completePurchase(d);
        } else {
          cleared = false;
        }
      }
    } catch (_) {
      // 스토어에 닿지 못했다. 앱을 다시 켜면 스트림으로 다시 온다
      cleared = false;
    }
    return cleared;
  }

  /// 선반을 살 때 스토어에 넘길 그 해 책장의 계정 연결 값과 결제 중 예약 번호. 서버가 이 값으로 어느 해 책장의 칸인지 찾는다. 받지 못하면 null.
  /// 그 해 칸을 다 열었으면 409 iap_shelf_full, 다른 기기가 결제 중이라 넘칠 수 있으면 409 iap_shelf_busy(ApiError로 던진다)
  Future<({String token, String? reservation})?> shelfToken(int year, {int shelves = 1}) async {
    final token = await KvStore.get(syncTokenKey);
    if (token == null) return null;
    try {
      final res = await api('POST', '/iap/shelf-token', token, {'year': year, 'shelves': shelves});
      if (res is! Map || res['token'] is! String) return null;
      return (token: res['token'] as String, reservation: res['reservation'] is String ? res['reservation'] as String : null);
    } on ApiError catch (e) {
      if (e.code == 'iap_shelf_full' || e.code == 'iap_shelf_busy') rethrow;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 결제 중 예약을 푼다(결제를 취소·실패했을 때). 못 풀어도 5분 뒤 저절로 풀린다
  Future<void> _release() async {
    final r = _reservation;
    _reservation = null;
    if (r == null) return;
    try {
      final token = await KvStore.get(syncTokenKey);
      if (token != null) await api('POST', '/iap/shelf-token/release', token, {'reservation': r});
    } catch (_) {}
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
        // 결제가 아직 끝나지 않았다(편의점 결제, 보호자 승인 등). 끝나면 스토어가 다시 알려 주고 그때 서버에 낸다.
        // 버튼을 풀어 화면을 떠날 수 있게 한다
        _done(IapResult.pending, '결제가 끝나면 자동으로 반영돼요. 이 화면을 닫아도 돼요.');
        return;
      case PurchaseStatus.canceled:
        if (Platform.isIOS && d.pendingCompletePurchase) await _store.completePurchase(d);
        _forgetBuying(d.productID);
        unawaited(_release());
        _done(IapResult.rejected, null);
        return;
      case PurchaseStatus.error:
        if (Platform.isIOS && d.pendingCompletePurchase) await _store.completePurchase(d);
        _forgetBuying(d.productID);
        unawaited(_release());
        _done(IapResult.retryLater, '결제가 이뤄지지 않았어요.');
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final epoch = _epoch;
        final result = await _submit(d, restore: _restoring || d.status == PurchaseStatus.restored);
        final finish = result.$2;
        // 애플만 앱이 거래를 끝낸다. 안드로이드는 서버가 확인·소비한다
        if (finish && Platform.isIOS && d.pendingCompletePurchase) await _store.completePurchase(d);
        if (epoch == _epoch) _done(result.$1, result.$3); // 계정이 바뀌었으면 앞 계정의 결과 문구를 보이지 않는다
    }
  }

  /// 구매 증거를 서버에 낸다. (결과, 거래를 끝내도 되는지, 사용자에게 보일 말)
  Future<(IapResult, bool, String?)> _submit(PurchaseDetails d, {required bool restore}) async {
    final token = await KvStore.get(syncTokenKey);
    final proof = d.verificationData.serverVerificationData;
    if (token == null || proof.isEmpty) return (IapResult.retryLater, false, '구매를 확인하지 못했어요. 앱을 다시 켜면 이어서 확인해요.');
    final epoch = _epoch;
    try {
      final current = d.productID == _buying;
      final res = await api('POST', '/iap/purchases', token, {'route': iapRoute, 'productId': d.productID, 'proof': proof, 'restore': restore, 'year': (current ? _shelfYear : null) ?? liveShelfYear(), if (current && _reservation != null) 'reservation': _reservation});
      if (res is! Map<String, dynamic>) {
        // 202: 결제가 아직 끝나지 않았다
        return (IapResult.pending, false, '결제를 확인하고 있어요. 끝나면 자동으로 반영돼요.');
      }
      if (epoch != _epoch) {
        // 그사이 로그아웃했다. 서버는 앞 계정으로 처리를 마쳤으니 거래는 끝내고, 결과는 지금 계정의 상태에 넣지 않는다
        return (IapResult.retryLater, true, null);
      }
      EntitlementStore.instance.apply(res);
      if (current) {
        _reservation = null; // 서버가 제출을 처리하며 예약을 풀었다
        _buying = null;
      }
      if (res['overCap'] == true) {
        // 다른 기기에서 먼저 3칸을 다 열었다. 칸은 열리지 않고 돌려준다(자세한 안내는 알림함과 창, 고지 T15)
        return (IapResult.granted, true, '이 책장의 선반은 이미 모두 열려 있어 이번 결제는 칸을 열지 않았어요. 환불 안내는 알림에서 확인해 주세요.');
      }
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
    if (v) {
      // 새 작업을 시작한다: 이전 작업의 결과가 이번 결과처럼 보이지 않게 비운다(복원은 끝날 때 lastResult를 본다)
      lastResult = null;
      lastMessage = null;
    }
    notifyListeners();
  }

  /// 결제 화면·시트를 열 때: 이전 작업의 결과 문구가 처음부터 보이지 않게 비운다. 진행 중이면 그대로 둔다.
  /// 결제 대기(pending)는 끝난 결과가 아니라 아직 기다리는 상태라 남긴다("이 화면을 닫아도 돼요"라고 안내했다).
  /// initState에서 부르므로 알리지 않는다
  void clearResult() {
    if (busy || lastResult == IapResult.pending) return;
    lastResult = null;
    lastMessage = null;
  }

  void _done(IapResult r, String? message) {
    busy = false;
    lastResult = r;
    lastMessage = message;
    notifyListeners();
  }
}
