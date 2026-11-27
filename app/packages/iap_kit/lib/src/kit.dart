// 앱이 키트에 넣는 것(서버 호출, 기기 저장소, 문구, 기본 대상)과 키트가 쓰는 오류.
library;

/// 서버 호출. 성공하면 JSON 본문(본문이 없거나 202면 null), 실패하면 IapApiError를 던진다.
/// 로그인하지 않았으면 아무 오류나 던진다(키트는 "지금은 못 한다"로 보고 다음에 다시 한다)
typedef IapApi = Future<Object?> Function(String method, String path, [Object? body]);

/// 서버가 준 오류 응답 {"error":{"code","message"}}
class IapApiError implements Exception {
  const IapApiError(this.status, this.code, this.message);
  final int status;
  final String code, message;
  @override
  String toString() => 'IapApiError($status, $code)';
}

/// 기기 저장소(키·값 문자열). 결제 상태의 사본을 남겨 서버에 닿기 전에도 보인다
class IapStorage {
  const IapStorage({required this.get, required this.set, required this.remove});
  final Future<String?> Function(String key) get;
  final Future<void> Function(String key, String value) set;
  final Future<void> Function(String key) remove;
}

class IapKit {
  IapKit._();

  /// 결제를 켠 빌드인지. 꺼져 있으면 키트는 아무 일도 하지 않는다(스토어 플러그인도 만들지 않는다)
  static bool enabled = false;
  static IapApi? _api;
  static IapStorage? _storage;

  /// 한 번 사는 상품을 대상 없이 살 때 쓸 대상(책장 한켠: 지금 책장의 연도). 대상이 없는 앱은 빈 값 그대로 둔다
  static String Function() defaultTarget = () => '';

  /// 앱이 바꾼 문구. 없는 키는 defaultMessages를 쓴다
  static Map<String, String> messages = const {};

  /// 앱을 켤 때 한 번 부른다(결제 화면보다 먼저)
  static void configure({required bool enabled, required IapApi api, required IapStorage storage, Map<String, String> messages = const {}, String Function()? defaultTarget}) {
    IapKit.enabled = enabled;
    _api = api;
    _storage = storage;
    IapKit.messages = messages;
    if (defaultTarget != null) IapKit.defaultTarget = defaultTarget;
  }

  static Future<Object?> call(String method, String path, [Object? body]) {
    final api = _api;
    if (api == null) throw StateError('IapKit.configure를 먼저 부르세요');
    return api(method, path, body);
  }

  static IapStorage get storage => _storage ?? _memory;

  static String text(String key) => messages[key] ?? defaultMessages[key] ?? key;
}

// configure 전(시험 등)에는 메모리에 둔다
final _mem = <String, String>{};
final _memory = IapStorage(get: (k) async => _mem[k], set: (k, v) async => _mem[k] = v, remove: (k) async => _mem.remove(k));

/// 키트가 사용자에게 보이는 기본 문구. 대상·수량을 모르는 말로 쓴다. 앱은 IapKit.configure(messages:)로 바꾼다.
/// 서버가 문구를 주는 오류(iap_cap_full 등)는 서버 문구를 그대로 보인다(서버 Rules.Messages)
const defaultMessages = <String, String>{
  'start_failed': '결제를 시작하지 못했어요. 잠시 뒤 다시 시도해 주세요.',
  'pending': '결제가 끝나면 자동으로 반영돼요. 이 화면을 닫아도 돼요.',
  'checking': '결제를 확인하고 있어요. 끝나면 자동으로 반영돼요.',
  'not_paid': '결제가 이뤄지지 않았어요.',
  'submit_failed': '구매를 확인하지 못했어요. 앱을 다시 켜면 이어서 확인해요.',
  'restored': '구매를 복원했어요.',
  'nothing_to_restore': '복원할 구매가 없어요.',
  'restore_failed': '복원하지 못했어요. 잠시 뒤 다시 시도해 주세요.',
  'expired': '구독 기간이 끝난 구매예요.',
  'over_cap': '이미 더 살 수 없는 상태라 이번 결제는 반영하지 않았어요. 환불 안내는 알림에서 확인해 주세요.',
  'unfinished_cleared': '끝나지 않은 지난 결제를 먼저 확인했어요. 반영된 내용을 확인한 뒤 필요하면 다시 결제해 주세요.',
  'unfinished_left': '지난 결제를 아직 확인하지 못해 새 결제를 시작할 수 없어요. 잠시 뒤 다시 시도해 주세요.',
};

/// 서버 응답을 보고 스토어 거래를 끝내도 되는지 정한다.
/// - 200: 지급했거나 전에 지급한 거래 → 끝낸다
/// - 409, 422: 환불됐거나 다른 계정·다른 앱의 구매. 다시 내도 결과가 같다 → 끝낸다
///   (다른 계정이 결제한 상품은 서버가 결제한 계정에 넣은 뒤 409를 준다)
/// - 그 밖(결제 대기 202, 스토어 확인 실패 503, 요청이 많음 429, 통신 실패): 끝내지 않는다. 다시 낼 수 있어야 한다
/// - 증거를 확인할 수 없음(iap_bad_proof), 스토어에 없는 거래(404): 끝내지 않는다. 서버 쪽 문제일 수 있어 구매를 버리지 않는다
/// - 대상을 모름(iap_target_missing): 끝내지 않는다. 서버가 소비하지 않았으니 대상을 붙여 다시 낼 수 있다
/// - 서버 상품 테이블에 없는 상품(iap_unknown_product): 끝내지 않는다. 설정 문제라 고친 뒤 다시 낸다
bool iapShouldFinish({required int status, String code = ''}) {
  if (status == 200) return true;
  if (code == 'iap_bad_proof' || code == 'iap_target_missing' || code == 'iap_unknown_product') return false;
  return status == 409 || status == 422;
}
