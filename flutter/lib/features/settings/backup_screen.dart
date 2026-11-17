// 계정 및 동기화(설정 → 내 기록): 연결된 계정 · 동기화 상태와 '지금 동기화' · 계정 관리(다른 계정 연결·로그아웃·서버 계정 삭제).
// 백업 파일 저장·공유·복원은 2026-11-17에 뺐다(사용자: 기록은 계정에, 가져오기만). 화면 모양은 2026-11-17 사용자 시안
library;


import 'package:flutter/material.dart';

import '../../services/sync.dart';
import '../../store/reading_store.dart';
import '../../ui/alert.dart';
import '../../ui/brand_button.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

Future<void> openBackup(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/backup'), builder: (_) => const BackupScreen()));

Future<void> _openManage(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/backup/manage'), builder: (_) => const BackupScreen(manage: true)));

/// 마지막 동기화 시각: 오늘·어제는 그 말로, 그 밖은 날짜. 오전·오후 h:mm
String syncTimeLabel(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day), today = DateTime(now.year, now.month, now.day);
  final days = today.difference(d).inDays;
  final day = days == 0 ? '오늘' : days == 1 ? '어제' : t.year == now.year ? '${t.month}월 ${t.day}일' : '${t.year}년 ${t.month}월 ${t.day}일';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$day ${t.hour < 12 ? '오전' : '오후'} $h:${t.minute.toString().padLeft(2, '0')}';
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.manage = false});

  /// 계정 관리(다른 계정 연결·로그아웃·서버 계정 삭제) 화면
  final bool manage;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
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

  // 연결 전에 알린다: 이 기기의 기록이 계정 기록과 합쳐지고(같은 항목은 더 최근에 고친 쪽), 아무것도 자동 공개되지 않는다
  void _login(String provider) => appAlert(
        context,
        '계정을 연결할까요?',
        '이 기기의 책·독서 기록·갈피가 계정에 저장된 기록과 합쳐져요. 같은 항목을 양쪽에서 고쳤다면 더 최근에 고친 쪽이 남아요. 연결해도 내 기록은 공개되지 않아요(커뮤니티에는 직접 고른 것만 올라가요).',
        [
          const AlertButton('취소', style: AlertStyle.cancel),
          AlertButton('연결', onPress: () => _doLogin(provider)),
        ],
      );

  Future<void> _doLogin(String provider) async {
    setState(() => _loggingIn = true);
    try {
      final r = await (provider == 'apple' ? _sync.linkApple() : provider == 'google' ? _sync.linkGoogle() : _sync.linkKakao());
      if (!mounted) return;
      if (r.ok) {
        appAlert(context, '계정을 연결했어요', r.switched ? '연결된 계정으로 바꿨어요. 기기의 기록은 동기화가 끝나면 합쳐져요.' : '이 기기의 기록을 계정에 연결했어요.');
      } else if (!r.cancelled) {
        appAlert(context, '로그인하지 못했어요', r.message);
      }
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _removeAccount() => appAlert(
        context,
        '서버 계정을 삭제할까요?',
        _sync.loginRequired
            ? '연결된 로그인과 서버의 독서 기록·사진 삭제를 요청해요. 이 폰의 기록도 지워지고 로그인 화면으로 돌아가요. 다른 기기의 오래된 앱이 기록을 다시 올리지 않도록 먼저 최신 버전으로 업데이트해 주세요.'
            : '연결된 로그인과 서버의 독서 기록·사진 삭제를 요청해요. 이 기기의 책과 사진은 남고 동기화는 중지돼요. 다른 기기의 오래된 앱이 기록을 다시 올리지 않도록 먼저 최신 버전으로 업데이트해 주세요.',
        [
          const AlertButton('취소', style: AlertStyle.cancel),
          AlertButton('서버 계정 삭제', style: AlertStyle.destructive, onPress: () async {
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
              if (mounted) appAlert(context, '삭제 완료를 확인하지 못했어요', '$e\n동기화 상태를 확인하고 삭제를 다시 요청해 주세요.');
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
        '이 폰에 있는 책·독서 기록·갈피·감상·사진을 지우고 로그인 화면으로 돌아가요. 서버에 올라간 기록은 그대로라 다시 로그인하면 받아 와요.'
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
          appAlert(context, '아직 올리지 못한 변경이 있어요', '서버에 올리지 못한 변경 $left개가 있어요. 지금 로그아웃하면 이 변경은 사라져요. 인터넷 연결을 확인하고 다시 해 보세요.', [
            const AlertButton('취소', style: AlertStyle.cancel),
            AlertButton('그래도 로그아웃', style: AlertStyle.destructive, onPress: () => _doLogout(force: true)),
          ]);
          return;
        }
      }
      await _sync.logout();
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) appAlert(context, '로그아웃하지 못했어요', e is StateError ? e.message : '$e');
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
            if (mounted) appAlert(context, '다시 시작하지 못했어요', '$e');
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
      if (last != null) '마지막 동기화  ${syncTimeLabel(last, DateTime.now())}',
      if (s.lastError != null && s.state == SyncState.error) s.lastError!,
    ];
    return [
      if (on) ...[
        Semantics(header: true, child: Text('연결된 계정', style: AppType.caption)),
        const SizedBox(height: Space.m),
        if (linked.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: Text('연결된 계정이 없어요', style: AppType.row))
        else
          for (final p in linked)
            MergeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Row(children: [
                  SizedBox(width: 44, child: Center(child: brandLogo(p, size: 36))),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(names[p]!, style: AppType.rowStrong),
                      // 서버에는 닉네임만 있다(이메일은 받지 않는다)
                      if (p == 'kakao' && s.account.nickname.isNotEmpty) Text(s.account.nickname, style: AppType.sub),
                    ]),
                  ),
                ]),
              ),
            ),
        const SectionBand(inset: true),
      ],
      Semantics(header: true, child: Text('동기화', style: AppType.section)),
      const SizedBox(height: Space.l),
      Semantics(liveRegion: true, child: Text(headline, style: AppType.title.copyWith(fontSize: 26, height: 34 / 26))),
      for (final t in sub) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(t, style: AppType.sub)),
      if (on && !s.paused) ...[
        const SizedBox(height: Space.l + 4),
        Btn(label: '지금 동기화', busy: s.state == SyncState.syncing, disabled: _loggingIn, onPress: s.syncNow),
        const SizedBox(height: Space.m),
        Text('이 기기와 계정의 기록을 함께 저장해요.', style: AppType.caption),
      ],
      if (on && s.paused && !s.deletionPending && !s.loginRequired) ...[
        const SizedBox(height: Space.l + 4),
        Btn(label: '새 계정으로 동기화', disabled: _loggingIn, onPress: _resume),
      ],
      if (on) ...[
        const SectionBand(inset: true),
        ListItem(tight: true, label: '계정 관리', chevron: true, onPress: () => _openManage(context)),
      ],
    ];
  }

  // ── 계정 관리: 다른 계정 연결 · 로그아웃 · 서버 계정 삭제 ──
  List<Widget> _manage() {
    final s = _sync;
    final canLink = s.available && !s.paused;
    // 로그인 화면과 같은 순서(카카오 · Google · Apple), 세 단추 같은 크기
    final brands = <Widget>[
      if (canLink && !s.account.kakao && s.providers.kakao) BrandButton.kakao(onPress: _loggingIn ? null : () => _login('kakao')),
      if (canLink && !s.account.google && s.providers.google) BrandButton.google(onPress: _loggingIn ? null : () => _login('google')),
      if (canLink && !s.account.apple && s.providers.apple) BrandButton.apple(onPress: _loggingIn ? null : () => _login('apple')),
    ];
    final linked = s.account.kakao || s.account.apple || s.account.google;
    final out = s.loginRequired && s.loggedIn && !s.deletionPending;
    final del = s.deletionPending || (s.providers.accountDeletion && !s.paused);
    return [
      if (brands.isNotEmpty) ...[
        Semantics(header: true, child: Text(linked ? '다른 계정도 연결' : '계정 연결', style: AppType.section)),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs, bottom: Space.l),
          child: WordText(linked ? '어느 계정으로 들어와도 같은 기록을 봐요' : '연결하면 기기를 바꿔도 기록을 이어 봐요', style: AppType.sub),
        ),
        for (final (i, b) in brands.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : Space.s), child: b),
        if (out || del) const SectionBand(inset: true),
      ],
      // 지우는 줄은 로그인 단추 사이가 아니라 아래에 따로(누르려던 단추 바로 옆에 빨간 삭제가 있었다)
      if (out) ListItem(label: '로그아웃', sub: '이 폰의 기록을 지우고 로그인 화면으로', onPress: _loggingIn ? null : _logout),
      if (del) ListItem(label: s.deletionPending ? '계정 삭제 다시 요청' : '서버 계정 삭제', danger: true, onPress: _loggingIn ? null : _removeAccount),
      if (brands.isEmpty && !out && !del) Text('바꿀 수 있는 것이 없어요', style: AppType.sub),
    ];
  }

  @override
  Widget build(BuildContext context) => Screen(
        // 2026-11-17 사용자: 백업·복원·파일 내보내기를 없애고 '계정 및 동기화'로(기록은 계정에 보관된다. 다른 앱에서 갈아타는 가져오기만 둔다)
        title: widget.manage ? '계정 관리' : '계정 및 동기화',
        children: widget.manage ? _manage() : _main(),
      );
}
