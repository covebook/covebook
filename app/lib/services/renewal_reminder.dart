// 연 구독 갱신 전 기기 알림(ADR-0003 L9, 고지 문구 T4).
// 서버도 같은 때 알림함에 '갱신 예정' 고지를 쌓는다(renewal_upcoming). 이쪽은 앱을 열지 않아도 닿게 하는 보조다(L8: 기준은 알림함).
// - 대상: 연 구독, 이용 중, 자동 갱신 켜짐, 결제 실패 유예가 아님. 월 구독은 보내지 않는다(L9)
// - 때: 다음 결제일 14일 전(L12 한국 기본값, 서버 IAP_RENEWAL_NOTICE_DAYS 기본값과 같다) 그날 오전 10시(기기 시각). 시각 계산은 결제 키트 renewalReminderAt
// - 앱이 상태를 받을 때마다 다시 건다. 조건이 깨지면(해지, 만료, 월로 바꿈) 지운다. 같은 번호라 겹치지 않는다
// - 권한은 연 구독 결제를 마친 뒤 한 번만 묻는다. 거절해도 알림함에는 남는다
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../db/kv_store.dart';
import '../store/entitlement_store.dart';
import 'iap.dart' show renewalReminderAt;

export 'iap.dart' show renewalReminderAt;

const _id = 41001;
const _askedKey = 'renewal-perm-asked:v1';

/// 알림 글(T4). price는 스토어가 준 현지 가격, 모르면 금액 줄을 뺀다
(String, String) renewalReminderText(IapSubscription sub, {String? price}) {
  final pay = sub.expiresAt.toLocal();
  final last = pay.subtract(const Duration(days: 1));
  String date(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';
  return (
    '책장 한켠 플러스가 ${date(pay)}에 갱신됩니다',
    '${price == null ? '' : '결제 예정 금액은 $price입니다. '}계속 이용하려면 할 일이 없습니다. 갱신을 원하지 않으면 ${date(last)}까지 내 정보 › 구독 관리에서 해지할 수 있습니다.',
  );
}

final _plugin = FlutterLocalNotificationsPlugin();
Future<bool>? _ready;

Future<bool> _init() => _ready ??= () async {
      try {
        // 초기화만으로는 권한을 묻지 않는다(묻는 때는 askRenewalPermission)
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
          ),
        );
        return true;
      } catch (e) {
        debugPrint('renewal reminder init: $e');
        return false;
      }
    }();

/// 지금 상태에 맞게 갱신 전 알림을 걸거나 지운다. 실패해도 넘어간다(알림함이 기준이다)
Future<void> syncRenewalReminder({String? price, DateTime? now}) async {
  if (!iapOn || !await _init()) return;
  final sub = EntitlementStore.instance.subscription;
  final at = renewalReminderAt(sub, now ?? DateTime.now());
  try {
    if (at == null || sub == null) {
      await _plugin.cancel(id: _id);
      return;
    }
    final (title, body) = renewalReminderText(sub, price: price);
    await _plugin.zonedSchedule(
      id: _id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('iap', '결제 안내', channelDescription: '구독 갱신처럼 결제와 관련된 안내', styleInformation: BigTextStyleInformation(body)),
        iOS: const DarwinNotificationDetails(),
      ),
      // 정확한 시각 알람 권한을 쓰지 않는다. 몇 분 늦어도 되는 안내다
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  } catch (e) {
    debugPrint('renewal reminder: $e');
  }
}

/// 연 구독 결제를 마친 뒤 알림 권한을 한 번만 묻는다. 거절한 사람에게 다시 묻지 않는다
Future<void> askRenewalPermission() async {
  if (!iapOn || !await _init()) return;
  try {
    if (await KvStore.get(_askedKey) != null) return;
    await KvStore.set(_askedKey, '1');
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true);
  } catch (e) {
    debugPrint('renewal permission: $e');
  }
}
