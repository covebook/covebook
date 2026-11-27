// 책장 한켠의 결제 상태. 결제 키트(packages/iap_kit)의 EntitlementStore에 책장 한켠의 말을 붙인다:
// 구독 권한 'plus'(유료 꾸미기), 연도 책장마다 산 선반 칸(키트의 대상 = 연도 "2026", 수량 = 칸).
// 결제 화면은 빌드 플래그로 꺼 둔다(--dart-define=IAP=true일 때만 켜짐, AGENTS.md)
library;

import 'package:iap_kit/iap_kit.dart';

export 'package:iap_kit/iap_kit.dart' show EntitlementStore, IapProduct, IapSubscription, iapCachedEntitlementsValid;

/// 결제 기능을 켠 빌드인지. 기본은 꺼짐
const iapOn = bool.fromEnvironment('IAP');

/// 구독이 주는 권한 이름(서버 iap_products.entitlement)
const plusEntitlement = 'plus';

/// 연도 책장 하나에 돈을 내고 여는 칸의 최대(책장 6칸 = 무료 3 + 유료 3, ADR-0002 D1). 서버 규칙(covebookIAPRules.Cap)과 같다
const paidShelfMax = 3;

/// 홈에 보이는 책장(지금 쓰는 책장)의 연도. 해가 바뀌면 지난 책장은 연도 책장으로 남고 새 책장이 된다(store/bookcase_store)
int liveShelfYear([DateTime? now]) => (now ?? DateTime.now()).year;

/// 상태 변화 알림이 지난번에 본 상태를 남기는 자리(features/iap/notice.dart). 로그아웃하면 다른 기기 값과 함께 지워진다(local_reset)
const iapSeenKey = 'iap-seen:v1';

/// 책장 한켠의 말로 읽는 결제 상태
extension CovebookEntitlements on EntitlementStore {
  /// 구독 권한(유료 꾸미기)
  bool get plus => has(plusEntitlement);

  /// 연도 책장마다 구매한 선반 칸 수. 산 칸이 있는 해만 들어 있다(대상이 연도가 아닌 값은 뺀다)
  Map<int, int> get shelvesByYear => {
    for (final e in unitsByTarget.entries)
      ?int.tryParse(e.key): e.value,
  };

  /// 그 해 책장에서 구매한 선반 칸 수
  int shelvesFor(int year) => unitsFor('$year');

  /// 지금 쓰는 책장(올해)에서 구매한 선반 칸 수
  int get shelves => shelvesFor(liveShelfYear());

  /// 모든 연도 책장에서 구매한 칸의 합(환불이면 줄어든다. 해가 바뀌어도 줄지 않는다)
  int get shelvesTotal => shelvesByYear.values.fold(0, (a, b) => a + b);
}

/// 한 번 사는 상품이 주는 선반 칸 수
extension CovebookProduct on IapProduct {
  int get shelves => units;
}
