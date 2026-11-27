// 책장 한켠의 결제 연결. 결제 흐름은 결제 키트(packages/iap_kit)가 맡고, 여기서는 책장 한켠만의 것을 넣는다:
// 서버 호출(동기화와 같은 로그인 토큰), 기기 저장소(KvStore), 기본 대상(지금 책장의 연도), 선반 말로 쓴 문구.
// 결정 기록: docs/adr/0002-iap-design.md
library;

import 'package:iap_kit/iap_kit.dart';

import '../db/kv_store.dart';
import '../store/entitlement_store.dart';
import 'sync.dart' show ApiError, api, syncBase, syncTokenKey;

// 결제 흐름 쪽 이름을 내보낸다. 결제 상태(EntitlementStore 등)는 store/entitlement_store.dart가 내보낸다
export 'package:iap_kit/iap_kit.dart'
    show IapKit, IapPlan, IapResult, IapService, iapPeriodOf, iapPlanOf, iapRoute, iapShouldFinish,
        // 고지·구매 내역·갱신 알림 시각(글과 화면은 features/iap)
        IapHistoryItem, IapNotice, IapNoticesUnavailable, fetchIapNotices, fetchIapPurchases, iapNoticeToShow, iapRenewalNoticeDays, markIapNoticesRead, renewalReminderAt;

/// 책장 한켠이 바꾼 키트 문구(나머지는 키트 기본 문구). 서버가 문구를 주는 오류는 서버 규칙(covebookIAPRules.Messages)에 있다
const covebookIapMessages = <String, String>{
  'over_cap': '이 책장의 선반은 이미 모두 열려 있어 이번 결제는 칸을 열지 않았어요. 환불 안내는 알림에서 확인해 주세요.',
};

/// 앱을 켤 때 한 번 부른다(main). 결제가 꺼진 빌드에서도 불러 두면 키트가 아무 일도 하지 않는다
void configureIap() {
  IapKit.configure(
    enabled: iapOn,
    api: (method, path, [body]) async {
      final token = await KvStore.get(syncTokenKey);
      // 서버가 없는 빌드도 로그인하지 않은 것으로 친다(알림함은 기기 기준으로 알린다)
      if (token == null || syncBase.isEmpty) throw const IapSignedOut();
      try {
        return await api(method, path, token, body);
      } on ApiError catch (e) {
        throw IapApiError(e.status, e.code, e.message);
      }
    },
    storage: const IapStorage(get: KvStore.get, set: KvStore.set, remove: KvStore.remove),
    defaultTarget: () => '${liveShelfYear()}',
    messages: covebookIapMessages,
  );
}
