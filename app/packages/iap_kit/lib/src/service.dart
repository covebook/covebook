// 인앱결제(스토어 결제 창과 서버 검증 사이를 잇는다). 결정 기록: docs/adr/0002-iap-design.md, 붙이는 법: README.md
//
// 흐름: 서버에서 계정 연결 값을 받는다 → 스토어 결제 → 스토어가 준 구매 증거를 서버에 낸다 → 서버가 지급했다고 답하면 거래를 끝낸다.
// - 지급 근거는 서버가 스토어에 다시 물어 받은 답이다. 앱은 증거를 전달만 한다.
// - 거래를 끝내는 것은 서버 응답 뒤다(D10). 끝내지 않은 거래는 iOS는 앱을 켤 때 스토어가 다시 주고, 안드로이드는 앱이 직접 물어 다시 낸다.
// - 구매 증거: 애플은 스토어가 서명한 거래(StoreKit 2의 JWS), 구글은 구매 토큰. 둘 다 verificationData.serverVerificationData에 있다.
// - 안드로이드의 확인(acknowledge·consume)은 서버가 한다. 앱은 completePurchase를 부르지 않는다(서버가 거절한 구매를 앱이 확인해 버리지 않게).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart' hide kIAPSource; // 같은 이름이 storekit에도 있다. 여기서는 애플 값을 쓴다
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'entitlements.dart';
import 'kit.dart';
import 'plan.dart';

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

  /// 한 번 사는 상품을 사려고 고른 대상. 구매 제출에 같이 보낸다(서버는 결제 의도의 대상을 먼저 본다)
  String? _target;

  /// 결제 의도 번호(POST /iap/intent). 서버가 이 번호로 어느 대상의 구매인지 찾고, 상한이 있으면 몇 분 동안 그 수량을 잡는다.
  /// 결제를 취소하거나 실패하면 바로 지운다. 결제 대기는 지우지 않는다(나중에 끝날 결제가 대상을 찾는다). 제출하면 서버가 지운다
  String? _reservation;

  /// 기기에 남긴 지금 결제(상품, 대상, 의도 번호). 결제 중 앱이 꺼져도 다시 켰을 때 그 거래에 붙여 낸다
  static const _buyingKey = 'iap-buying:v1';

  /// 지금 결제창을 띄운 상품. 예약 번호와 대상은 이 상품의 거래에만 붙인다(전에 끝내지 못한 다른 거래가 가져가지 않게)
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
    if (!IapKit.enabled) return;
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
  /// 비워진 수량(0)으로 앱이 산 것을 닫는 일(책장 한켠: enforceShelfLimit)이 돈다. 스토어 듣기는 그대로 둔다(앱 실행당 한 번)
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
    _target = null;
    _reservation = null;
    _lastResubmit = null;
    unawaited(_clearBuying()); // 앞 계정의 결제다
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
    if (!IapKit.enabled || loading) return;
    loading = true; // 여기서는 알리지 않는다(화면의 initState 안에서 불린다). 끝날 때 알린다
    final epoch = _epoch;
    try {
      try {
        final me = await IapKit.call('GET', '/iap/me');
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
  /// target: 한 번 사는 상품이 붙을 대상(없으면 IapKit.defaultTarget). 서버에 결제 의도로 남기고, 스토어에는 계정마다 하나인 계정 연결 값만 넘긴다(ADR-0002 D1·D7)
  Future<void> buy(IapProduct product, {IapPlan? plan, String? target}) async {
    final d = plan?.details ?? details[product.productId];
    final once = product.kind != 'subscription';
    if (busy || d == null || (!once && EntitlementStore.instance.accountToken.isEmpty)) return;
    _busy(true);
    try {
      String? account = EntitlementStore.instance.accountToken;
      if (once) {
        final to = target ?? IapKit.defaultTarget();
        try {
          final t = await intent(to, units: product.units);
          account = t?.token;
          _reservation = t?.reservation;
        } on IapApiError catch (e) {
          if (e.code == 'iap_cap_full') {
            // 다른 기기에서 그사이 샀다(상한에 닿았거나, 고른 상품이 남은 수량보다 많다). 결제창을 띄우지 않고 수량을 다시 받는다.
            // 문구는 서버가 앱 규칙(Rules.Messages)으로 정해 준다
            await refresh();
            _done(IapResult.rejected, e.message);
            return;
          }
          if (e.code == 'iap_target_busy') {
            _done(IapResult.retryLater, e.message);
            return;
          }
          rethrow;
        }
        _target = to;
        _buying = product.productId;
        unawaited(_saveBuying());
      }
      if (account == null || account.isEmpty) {
        _done(IapResult.retryLater, IapKit.text('start_failed'));
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
        _target = null;
        unawaited(_clearBuying());
        final cleared = await _resubmitIos();
        _done(
          IapResult.retryLater,
          IapKit.text(cleared ? 'unfinished_cleared' : 'unfinished_left'),
        );
        return;
      }
      _failStart();
    } catch (_) {
      _failStart();
    }
  }

  /// 지금 결제가 취소·실패했다. 뒤에 같은 상품의 옛 거래를 다시 낼 때 이번 대상이 붙지 않게 비운다
  void _forgetBuying(String productId) {
    if (productId != _buying) return;
    _buying = null;
    _target = null;
    unawaited(_clearBuying());
  }

  void _failStart() {
    unawaited(_release());
    _buying = null;
    _target = null;
    unawaited(_clearBuying());
    _done(IapResult.retryLater, IapKit.text('start_failed'));
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

  /// 한 번 사는 상품의 결제를 시작하기 직전에 서버에 결제 의도를 남긴다. 스토어에 넘길 계정 연결 값과 의도 번호를 받는다. 받지 못하면 null.
  /// 계정 연결 값은 계정마다 하나다. 어느 대상의 구매인지는 서버가 의도로 찾는다(애플·구글 모두 이 값을 계정 식별자로 쓰라고 한다).
  /// 상한에 닿았으면 409 iap_cap_full, 다른 기기가 결제 중이라 넘칠 수 있으면 409 iap_target_busy(IapApiError로 던진다)
  Future<({String token, String? reservation})?> intent(String target, {int units = 1}) async {
    try {
      final res = await IapKit.call('POST', '/iap/intent', {if (target.isNotEmpty) 'target': target, 'units': units});
      if (res is! Map || res['token'] is! String) return null;
      return (token: res['token'] as String, reservation: res['reservation'] is String ? res['reservation'] as String : null);
    } on IapApiError catch (e) {
      if (e.code == 'iap_cap_full' || e.code == 'iap_target_busy') rethrow;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 결제 의도를 지운다(결제를 취소·실패했을 때). 못 지워도 상한을 잡는 예약은 Rules.Hold가 지나면 풀리고, 의도는 Rules.Keep이 지나면 지워진다
  Future<void> _release() async {
    final r = _reservation;
    _reservation = null;
    if (r == null) return;
    try {
      await IapKit.call('POST', '/iap/intent/release', {'reservation': r});
    } catch (_) {}
  }

  Future<void> _saveBuying() async {
    final product = _buying;
    if (product == null) return;
    try {
      await IapKit.storage.set(_buyingKey, jsonEncode({'product': product, 'target': _target, 'reservation': _reservation}));
    } catch (_) {}
  }

  Future<void> _clearBuying() async {
    try {
      await IapKit.storage.remove(_buyingKey);
    } catch (_) {}
  }

  /// 기기에 남긴 결제가 이 상품의 것이면 그 대상과 의도 번호. 없거나 다른 상품이면 null
  Future<({String? target, String? reservation})?> _savedBuying(String productId) async {
    try {
      final raw = await IapKit.storage.get(_buyingKey);
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is! Map || m['product'] != productId) return null;
      final t = m['target'], r = m['reservation'];
      return (target: t is String ? t : null, reservation: r is String ? r : null);
    } catch (_) {
      return null;
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
      if (busy) _done(lastResult ?? IapResult.inactive, lastMessage ?? IapKit.text('nothing_to_restore'));
    } catch (_) {
      _done(IapResult.retryLater, IapKit.text('restore_failed'));
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
        // 결제 의도는 지우지 않는다. 앱을 닫아도 서버가 스토어 알림과 의도를 맞춰 대상을 찾는다(Rules.Keep, 기본 4일).
        // 버튼을 풀어 화면을 떠날 수 있게 한다
        _done(IapResult.pending, IapKit.text('pending'));
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
        _done(IapResult.retryLater, IapKit.text('not_paid'));
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
    final proof = d.verificationData.serverVerificationData;
    if (proof.isEmpty) return (IapResult.retryLater, false, IapKit.text('submit_failed'));
    final epoch = _epoch;
    try {
      final current = d.productID == _buying;
      // 대상과 의도 번호: 지금 산 상품이면 고른 것, 아니면 기기에 남긴 그 상품의 결제(앱이 꺼졌다 켜진 경우), 둘 다 없으면 기본 대상.
      // 서버는 의도 번호를 먼저 보고, 결제보다 뒤에 남긴 번호는 쓰지 않는다(옛 거래가 지금 결제의 번호를 가져가지 않게)
      var target = current ? _target : null;
      var reservation = current ? _reservation : null;
      var saved = false;
      if (!current) {
        final s = await _savedBuying(d.productID);
        if (s != null) {
          (target, reservation, saved) = (s.target, s.reservation, true);
        }
      }
      target ??= IapKit.defaultTarget();
      final res = await IapKit.call('POST', '/iap/purchases', {'route': iapRoute, 'productId': d.productID, 'proof': proof, 'restore': restore, if (target.isNotEmpty) 'target': target, 'reservation': ?reservation});
      if (res is! Map<String, dynamic>) {
        // 202: 결제가 아직 끝나지 않았다
        return (IapResult.pending, false, IapKit.text('checking'));
      }
      if (epoch != _epoch) {
        // 그사이 로그아웃했다. 서버는 앞 계정으로 처리를 마쳤으니 거래는 끝내고, 결과는 지금 계정의 상태에 넣지 않는다
        return (IapResult.retryLater, true, null);
      }
      EntitlementStore.instance.apply(res);
      if (current) {
        _reservation = null; // 서버가 제출을 처리하며 의도를 지웠다
        _buying = null;
      }
      if (current || saved) unawaited(_clearBuying());
      if (res['overCap'] == true) {
        // 다른 기기에서 먼저 상한까지 샀다. 이번 결제는 반영하지 않고 돌려준다(자세한 안내는 알림함과 창, 고지 T15)
        return (IapResult.granted, true, IapKit.text('over_cap'));
      }
      return switch (res['status']) {
        'already' => (IapResult.already, true, restore ? IapKit.text('restored') : null),
        'inactive' => (IapResult.inactive, true, IapKit.text('expired')),
        _ => (IapResult.granted, true, restore ? IapKit.text('restored') : null),
      };
    } on IapApiError catch (e) {
      final finish = iapShouldFinish(status: e.status, code: e.code);
      return (finish ? IapResult.rejected : IapResult.retryLater, finish, e.message);
    } catch (_) {
      return (IapResult.retryLater, false, IapKit.text('submit_failed'));
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
