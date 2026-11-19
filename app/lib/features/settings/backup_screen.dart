// 계정 및 동기화(설정 → 내 기록): 연결된 계정과 바로 아래 로그아웃 · 동기화 상태와 '지금 동기화' · 맨 아래 회원탈퇴.
// 2026-11-18 사용자: 안쪽 '계정 관리' 화면을 없애고 로그아웃은 연결된 계정 밑에, 회원탈퇴는 맨 밑에.
// 이어서 '다른 계정으로도 연결'은 지운다: 다른 계정은 로그아웃한 뒤 그 계정으로 로그인한다.
// 백업 파일 저장·공유·복원은 2026-11-17에 뺐다(사용자: 기록은 계정에, 가져오기만). 화면 모양은 2026-11-17 사용자 시안.
// 묶음 이름('연결된 계정' · '동기화')은 내 정보와 같은 작은 회색 이름(ListGroup), 계정 줄은 앱 목록 줄(ListItem)이다(2026-11-19 공통 규칙)
library;

import 'package:flutter/material.dart';

import '../../services/sync.dart';
import '../../store/entitlement_store.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/brand_button.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../iap/withdraw_notice.dart' show showWithdrawNotice;
import '../book/labels.dart' show dateTimeLabel;
import '../../ui/feedback.dart' show errorText;

Future<void> openBackup(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/backup'), builder: (_) => const BackupScreen()));

/// 마지막 동기화 시각: 앱 공통 날과 시각 글자('어제 오후 3:10', dateTimeLabel)
String syncTimeLabel(DateTime t, DateTime now) => dateTimeLabel(t, now: now);

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

/// 연결된 계정 줄 아래 글: 이메일 → (Apple 전달용 주소면) '이메일 가림' → 닉네임
String? _accountHint(String provider, SyncService s) {
  final mail = s.emails[provider];
  if (mail != null) return mail.endsWith('@privaterelay.appleid.com') ? '이메일 가림' : mail;
  final nick = s.account.nickname;
  return provider == 'kakao' && nick.isNotEmpty ? nick : null;
}

class _BackupScreenState extends State<BackupScreen> {
  final _sync = SyncService.instance;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// 회원탈퇴: 서버가 탈퇴를 받는지 아직 모르면(오프라인으로 켬) 먼저 묻고, 닿지 않으면 그 이유를 알린다(줄은 늘 보인다, ADR-0003 L4 탈퇴 경로)
  Future<void> _removeAccountTap() async {
    if (!_sync.providersKnown) await _sync.refreshProviders();
    if (!mounted) return;
    if (!_sync.providersKnown) {
      appAlert(context, '지금은 회원탈퇴할 수 없어요', '인터넷 연결을 확인하고 다시 시도해 주세요.');
      return;
    }
    if (!_sync.providers.accountDeletion && !_sync.deletionPending) {
      appAlert(context, '지금은 회원탈퇴할 수 없어요', '서버가 회원탈퇴를 받지 않고 있어요. 잠시 뒤 다시 시도해 주세요.');
      return;
    }
    _removeAccount();
  }

  /// 구독 중인 계정이 탈퇴하려 할 때(고지 문구 T12): 탈퇴해도 스토어 구독은 해지되지 않는다고 먼저 알린다.
  /// 탈퇴를 막지 않는다. '탈퇴 계속'을 누르면 원래 확인창으로 간다
  void _removeAccount() {
    final sub = iapOn ? EntitlementStore.instance.subscription : null;
    if (sub == null || !sub.active) return _confirmRemove();
    showWithdrawNotice(context, sub, onContinue: _confirmRemove);
  }

  void _confirmRemove() => appAlert(
        context,
        '회원탈퇴할까요?',
        _sync.loginRequired
            ? '연결된 로그인과 서버의 독서 기록, 사진 삭제를 요청해요.${iapOn ? ' 결제 기록은 법에 따라 계정과 분리해 보관해요.' : ''} 이 폰의 기록도 지워지고 로그인 화면으로 돌아가요. 다른 기기의 오래된 앱이 기록을 다시 올리지 않도록 먼저 최신 버전으로 업데이트해 주세요.'
            : '연결된 로그인과 서버의 독서 기록, 사진 삭제를 요청해요.${iapOn ? ' 결제 기록은 법에 따라 계정과 분리해 보관해요.' : ''} 이 기기의 책과 사진은 남고 동기화는 중지돼요. 다른 기기의 오래된 앱이 기록을 다시 올리지 않도록 먼저 최신 버전으로 업데이트해 주세요.',
        [
          const AlertButton('취소', style: AlertStyle.cancel),
          AlertButton('회원탈퇴', style: AlertStyle.destructive, onPress: () async {
            setState(() => _loggingIn = true);
            try {
              final nav = Navigator.of(context, rootNavigator: true);
              await _sync.deleteCloudAccount();
              if (_sync.loginRequired) {
                // 로그인 화면(앱 첫 화면)으로 돌아간다
                nav.popUntil((r) => r.isFirst);
                return;
              }
              if (mounted) appAlert(context, '삭제 요청을 접수했어요', '서버 접근을 차단하고 기록과 사진 삭제를 처리해요. 이 기기의 기록은 남아요.');
            } catch (e) {
              if (mounted) appAlert(context, '삭제 완료를 확인하지 못했어요', '${errorText(e)} 동기화 상태를 확인하고 삭제를 다시 요청해 주세요.');
            } finally {
              if (mounted) setState(() => _loggingIn = false);
            }
          }),
        ],
      );

  // 로그아웃: 이 폰의 기록을 지우고 로그인 화면으로(2026-11-16 사용자: 로그아웃하면 폰에서 지움). 올리지 못한 변경이 있으면 먼저 알린다
  void _logout() => appAlert(
        context,
        '로그아웃할까요?',
        '이 폰에 있는 책, 독서 기록, 갈피, 감상, 사진을 지우고 로그인 화면으로 돌아가요. 서버에 올라간 기록은 그대로라 다시 로그인하면 받아 와요.'
            '${ReadingStore.instance.active != null ? ' 지금 읽는 중인 시간은 저장되지 않아요.' : ''}',
        [
          const AlertButton('취소', style: AlertStyle.cancel),
          AlertButton('로그아웃', style: AlertStyle.destructive, onPress: () => _doLogout()),
        ],
      );

  Future<void> _doLogout({bool force = false}) async {
    final nav = Navigator.of(context, rootNavigator: true);
    setState(() => _loggingIn = true);
    try {
      if (!force) {
        final left = await _sync.flushBeforeLogout();
        if (left > 0) {
          if (!mounted) return;
          appAlert(context, '아직 올리지 못한 변경이 있어요', '서버에 올리지 못한 변경 $left개가 있어요. 지금 로그아웃하면 이 변경은 사라져요. 인터넷 연결을 확인하고 다시 시도해 주세요.', [
            const AlertButton('취소', style: AlertStyle.cancel),
            AlertButton('그래도 로그아웃', style: AlertStyle.destructive, onPress: () => _doLogout(force: true)),
          ]);
          return;
        }
      }
      await _sync.logout();
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) appAlert(context, '로그아웃하지 못했어요', errorText(e));
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _resume() => appAlert(context, '새 계정으로 동기화할까요?', '새 서버 계정을 만들고 이 기기에 남은 기록과 사진을 다시 올려요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('동기화 시작', onPress: () async {
          setState(() => _loggingIn = true);
          try {
            await _sync.resumeCloudSync();
          } catch (e) {
            if (mounted) appAlert(context, '다시 시작하지 못했어요', errorText(e));
          } finally {
            if (mounted) setState(() => _loggingIn = false);
          }
        }),
      ]);

  // ── 계정 및 동기화 ──
  List<Widget> _main() {
    final s = _sync, on = s.available;
    final linked = [if (s.account.google) 'google', if (s.account.kakao) 'kakao', if (s.account.apple) 'apple'];
    const names = {'google': 'Google 계정', 'kakao': '카카오 계정', 'apple': 'Apple 계정'};
    final last = s.lastAt == null ? null : DateTime.tryParse(s.lastAt!)?.toLocal();
    final headline = !on
        ? '기록은 이 기기에만 있어요'
        : s.paused
            ? '서버 동기화를 중지했어요'
            : s.state == SyncState.syncing
                ? '동기화하는 중이에요'
                : s.state == SyncState.error
                    ? '동기화하지 못했어요'
                    : s.pending > 0
                        ? '올리지 못한 변경이 ${s.pending}개 있어요'
                        : last != null
                            ? '기록이 최신 상태예요'
                            : '아직 동기화 전이에요';
    final sub = [
      if (last != null) '마지막 동기화 ${syncTimeLabel(last, DateTime.now())}',
      if (s.lastError != null && s.state == SyncState.error) s.lastError!,
      // 멈춘 이유(2026-11-19 규칙: 이유 없이 '중지했어요'만 보였다). 다시 잇는 길은 정책 결정 대기(DESIGN 16-1)
      if (on && s.paused && !s.deletionPending) '로그인이 끝났거나 계정이 삭제되어 동기화를 멈췄어요. 이 기기의 기록은 그대로 있어요.',
    ];
    final out = on && s.loginRequired && s.loggedIn && !s.deletionPending;
    // 탈퇴 줄은 서버 빌드에서 늘 보인다(오프라인으로 켜면 서버 지원 여부를 몰라 줄이 사라졌다, ADR-0003 L4). 서버가 받지 않는다고 답했을 때만 숨긴다
    final del = on && (s.deletionPending || ((!s.providersKnown || s.providers.accountDeletion) && !s.paused));
    return [
      if (on) ...[
        // 위 줄과 첫 구역 사이를 시안만큼 띄운다
        const SizedBox(height: Space.l),
        ListGroup(title: '연결된 계정', children: [
          if (linked.isEmpty)
            const ListItem(label: '연결된 계정이 없어요')
          else
            for (final p in linked)
              // 어느 계정인지: 공급자가 확인해 준 이메일(2026-11-18 사용자 '무슨 이메일로 로그인된지도 없고').
              // Apple '이메일 가리기'면 전달용 주소라 그 사실만, 이메일이 없으면(카카오 비즈 앱 전 등) 닉네임
              ListItem(icon: brandLogo(p, size: 36), label: names[p]!, sub: _accountHint(p, s)),
          // 로그아웃은 연결된 계정 바로 밑(2026-11-18 사용자)
          // 무엇이 지워지는지는 누르면 뜨는 확인창이 알린다(줄은 이름만, 시안)
          if (out) Opacity(opacity: _loggingIn ? disabledOpacity : 1, child: ListItem(label: '로그아웃', onPress: _loggingIn ? null : _logout)),
        ]),
        const SectionBand(inset: true),
      ],
      ListGroup(title: '동기화', children: [
        // 묶음 이름에서 상태 글까지는 목록 줄 글자와 같은 거리(4 + 12)
        const SizedBox(height: Space.m),
        // 상태 글은 구역 큰 글(21): 제목(26)이면 너무 컸다(2026-11-18 사용자)
        Semantics(liveRegion: true, child: Text(headline, style: AppType.heading)),
        for (final t in sub) Padding(padding: const EdgeInsets.only(top: Space.xs), child: WordText(t, style: AppType.sub)),
      ]),
      if (on && !s.paused) ...[
        const SizedBox(height: Space.l),
        Btn(label: '지금 동기화', busy: s.state == SyncState.syncing, disabled: _loggingIn, onPress: s.syncNow),
        const SizedBox(height: Space.m),
        Text('이 기기와 계정의 기록을 함께 저장해요.', style: AppType.caption),
      ],
      if (on && s.paused && !s.deletionPending && !s.loginRequired) ...[
        const SizedBox(height: Space.l),
        Btn(label: '새 계정으로 동기화', disabled: _loggingIn, onPress: _resume),
      ],
      // 회원탈퇴는 맨 밑에 따로(2026-11-18 사용자). 누르면 무엇이 지워지는지 확인창에서 한 번 더 알린다
      if (del) ...[
        const SectionBand(inset: true),
        Opacity(
          opacity: _loggingIn ? disabledOpacity : 1,
          child: ListItem(label: s.deletionPending ? '회원탈퇴 다시 요청' : '회원탈퇴', danger: true, onPress: _loggingIn ? null : _removeAccountTap),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => Screen(
        // 2026-11-17 사용자: 백업·복원·파일 내보내기를 없애고 '계정 및 동기화'로(기록은 계정에 보관된다. 다른 앱에서 갈아타는 가져오기만 둔다)
        title: '계정 및 동기화',
        children: _main(),
      );
}
