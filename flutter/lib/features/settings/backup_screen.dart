// 백업 및 복원(지금 앱 app/backup.tsx, 설정 → 내 기록): 백업 파일 저장·공유·복원, 서버 동기화 상태·계정 연결.
// 2026-11-01 토스식: 세로로 쌓인 버튼 대신 누르는 줄 목록, 설명은 한 줄
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/sync.dart';
import '../../store/backup.dart';
import '../../ui/alert.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

Future<void> openBackup(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/backup'), builder: (_) => const BackupScreen()));

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _sync = SyncService.instance;
  bool _loggingIn = false;
  String? _busy; // export · share · restore
  ({String at, String how})? _last; // 마지막 백업(이 기기)

  @override
  void initState() {
    super.initState();
    _sync.addListener(_changed);
    _loadLast();
  }

  Future<void> _loadLast() async {
    final l = await lastBackup();
    if (mounted) setState(() => _last = l);
  }

  @override
  void dispose() {
    _sync.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // 저장된 시각은 UTC라 기기 시간대로 보여 준다
  String _localTime(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${t.month}월 ${t.day}일 ${p(t.hour)}:${p(t.minute)}';
  }

  String _countsText(Counts c) => '책 ${c.books}권 · 갈피 ${c.bookmarks}개${c.essays > 0 ? ' · 감상 ${c.essays}편' : ''} · 독서 회차 ${c.rounds}개 · 독서 기록 ${c.sessions}개 · 장정 ${c.bindings}개 · 사진 ${c.images}장';

  Future<void> _saveToDownloads() async {
    setState(() => _busy = 'export');
    try {
      final r = await exportToDownloads();
      _loadLast();
      if (mounted) appAlert(context, '백업 파일을 저장했어요', '다운로드/책장한켠/${r.name}\n${_countsText(r.counts)}');
    } catch (e) {
      if (mounted) appAlert(context, '저장하지 못했어요', e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = 'share');
    try {
      await exportShare();
      _loadLast();
    } catch (e) {
      if (mounted) appAlert(context, '내보내지 못했어요', '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = 'restore');
    final r = await readBackupFile();
    if (!mounted) return;
    setState(() => _busy = null);
    if (r.data == null) {
      if (r.error != null) appAlert(context, '복원할 수 없어요', r.error);
      return;
    }
    final c = r.counts!;
    appAlert(
      context,
      '백업으로 바꿀까요?',
      // 만든 날짜와 시각(기기 시각): 같은 날 여러 번 백업해도 어느 것인지 안다(2026-11-16 QA 현우 F6)
      '백업(${backupTimeLabel(r.data!['exportedAt']! as String)}): 책 ${c.books}권 · 갈피 ${c.bookmarks}개${c.essays > 0 ? ' · 감상 ${c.essays}편' : ''} · 독서 기록 ${c.sessions}개 · 사진 ${c.images}장\n지금 기기의 기록은 이 백업 내용으로 바뀌어요.',
      [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('복원', style: AlertStyle.destructive, onPress: () async {
          setState(() => _busy = 'restore');
          try {
            await restoreBackup(r.data!);
            if (mounted) appAlert(context, '복원했어요');
          } catch (e) {
            if (mounted) appAlert(context, '복원하지 못했어요', e is StateError ? e.message : '$e');
          } finally {
            if (mounted) setState(() => _busy = null);
          }
        }),
      ],
    );
  }

  Widget? _spin(String kind) => _busy == kind ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)) : null;

  List<Widget> _backupSection() => [
        const H2('백업 파일', first: true),
        // 들어가는 것에 감상을, 책 표지는 파일에 넣지 않고 인터넷에서 다시 받는다는 것을 알린다(2026-11-16 QA 현우 F2·F7)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.xs),
          child: Text(keepAll('책·독서 기록·갈피·감상·장정·책장 배치·설정과 직접 찍거나 고른 사진이 들어가요. 검색으로 넣은 책 표지는 파일에 넣지 않고 인터넷에서 다시 받아요. 진행 중인 타이머는 빠져요.'), style: AppType.sub),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: Text(
            _last == null ? '이 기기에서는 아직 백업하지 않았어요.' : '마지막 백업 ${backupTimeLabel(_last!.at)} · ${_last!.how == 'share' ? '공유로 보냄' : '다운로드 폴더'}',
            style: AppType.caption,
          ),
        ),
        ListGroup(children: [
          // iOS에는 다운로드 폴더가 없다: 공유창의 '파일에 저장'을 쓴다
          if (Platform.isAndroid)
            ListItem(label: '다운로드 폴더에 백업 파일 저장', sub: '다운로드/책장한켠에 저장돼요', chevron: _busy != 'export', right: _spin('export'), onPress: _busy != null ? null : _saveToDownloads),
          ListItem(label: '공유로 보내기', sub: '메신저·드라이브로 보내요', chevron: _busy != 'share', right: _spin('share'), onPress: _busy != null ? null : _share),
          ListItem(label: '백업에서 복원', sub: '지금 기기의 기록이 백업 내용으로 바뀌어요', chevron: _busy != 'restore', right: _spin('restore'), onPress: _busy != null ? null : _restore),
        ]),
      ];

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
        '연결된 로그인과 서버의 독서 기록·사진 삭제를 요청해요. 이 기기의 책과 사진은 남고 동기화는 중지돼요. 다른 기기의 오래된 앱이 기록을 다시 올리지 않도록 먼저 최신 버전으로 업데이트해 주세요.',
        [
          const AlertButton('취소', style: AlertStyle.cancel),
          AlertButton('서버 계정 삭제', style: AlertStyle.destructive, onPress: () async {
            setState(() => _loggingIn = true);
            try {
              await _sync.deleteCloudAccount();
              if (mounted) appAlert(context, '삭제 요청을 접수했어요', '서버 접근을 차단하고 기록과 사진 삭제를 처리해요. 이 기기의 기록은 남아요.');
            } catch (e) {
              if (mounted) appAlert(context, '삭제 완료를 확인하지 못했어요', '$e\n동기화 상태를 확인하고 삭제를 다시 요청해 주세요.');
            } finally {
              if (mounted) setState(() => _loggingIn = false);
            }
          }),
        ],
      );

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

  List<Widget> _syncSection() {
    final s = _sync, on = s.available;
    final label = !on
        ? '이 기기에만 저장돼요'
        : s.paused
            ? '서버 동기화를 중지했어요'
            : s.state == SyncState.syncing
                ? '동기화하는 중…'
                : s.state == SyncState.error
                    ? '동기화하지 못했어요'
                    : s.lastAt != null
                        ? '마지막 동기화 ${_localTime(s.lastAt!)}'
                        : '아직 동기화 전이에요';
    final sub = on
        ? '${s.pending > 0 ? '올리지 못한 변경 ${s.pending}개' : s.lastAt != null && !s.paused && s.state != SyncState.error ? '대기 중인 변경이 없어요' : '기기에 기록을 보관하고 있어요'}${s.lastError != null ? ' · ${s.lastError}' : ''}'
        : '기록은 이 기기에만 있어요. 백업 파일로 옮길 수 있어요.';
    final canLink = on && !s.paused;
    // 연결할 수 있는 계정: 세 회사 단추를 같은 크기·같은 줄 간격으로(예전엔 카카오는 목록 줄, Apple은 검은 알약, Google은 영어 그림 단추로 셋이 달랐다, 2026-11-16)
    final brands = <Widget>[
      if (canLink && !s.account.kakao && s.providers.kakao) _BrandButton.kakao(onPress: _loggingIn ? null : () => _login('kakao')),
      if (canLink && !s.account.apple && s.providers.apple) _BrandButton.apple(onPress: _loggingIn ? null : () => _login('apple')),
      if (canLink && !s.account.google && s.providers.google) _BrandButton.google(onPress: _loggingIn ? null : () => _login('google')),
    ];
    final linked = s.account.kakao || s.account.apple || s.account.google;
    return [
      const H2('동기화', first: true),
      ListGroup(children: [
        ListItem(
          label: label,
          sub: sub,
          right: s.state == SyncState.syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)) : null,
        ),
        if (on && !s.paused) ListItem(label: '지금 동기화', onPress: s.state == SyncState.syncing || _loggingIn ? null : s.syncNow),
        if (on && s.account.kakao) ListItem(label: '카카오 계정 연결됨', sub: s.account.nickname.isNotEmpty ? '${s.account.nickname} · 다른 기기에서도 이어 봐요' : '다른 기기에서도 이어 봐요'),
        if (on && s.account.apple) const ListItem(label: 'Apple 계정 연결됨', sub: '다른 기기에서도 이어 봐요'),
        if (on && s.account.google) const ListItem(label: 'Google 계정 연결됨', sub: '다른 기기에서도 이어 봐요'),
        if (on && s.paused && !s.deletionPending) ListItem(label: '새 계정으로 동기화', chevron: true, onPress: _loggingIn ? null : _resume),
      ]),
      if (brands.isNotEmpty) ...[
        H2(linked ? '다른 계정도 연결' : '계정 연결'),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.l),
          child: WordText(linked ? '어느 계정으로 들어와도 같은 기록을 봐요' : '연결하면 기기를 바꿔도 기록을 이어 봐요', style: AppType.sub),
        ),
        for (final (i, b) in brands.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : Space.s), child: b),
      ],
      // 지우는 줄은 로그인 단추 사이가 아니라 맨 아래에 따로 둔다(누르려던 단추 바로 옆에 빨간 삭제가 있었다)
      if (on && (s.deletionPending || (s.providers.accountDeletion && !s.paused))) ...[
        const SizedBox(height: Space.xl),
        ListGroup(children: [
          ListItem(label: s.deletionPending ? '계정 삭제 다시 요청' : '서버 계정 삭제', danger: true, onPress: _loggingIn ? null : _removeAccount),
        ]),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: '백업 및 복원',
        subtitle: _sync.available ? '기록은 이 기기와 서버에 함께 저장돼요' : '모든 기록은 이 기기에만 저장돼요',
        children: [
          ..._backupSection(),
          const SectionBand(),
          ..._syncSection(),
        ],
      );
}

/// 로그인 단추: 세 회사 모두 같은 틀(높이 54, 모서리 Shape.button, 가운데 로고+글자)에 각 회사 규칙의 색만 다르다.
/// 카카오: 노랑 #FEE500·검은 말풍선·글자 85% 검정. Apple: 검정 바탕·흰 로고(HIG 사용자 정의 단추). Google: 흰 바탕·#747775 선·네 색 G(브랜딩 지침의 '계속하기' 문구)
class _BrandButton extends StatefulWidget {
  const _BrandButton({required this.label, required this.bg, required this.fg, required this.logo, required this.onPress, required this.border});

  _BrandButton.kakao({required VoidCallback? onPress})
      : this(label: '카카오로 계속하기', bg: const Color(0xFFFEE500), fg: const Color(0xD9000000), logo: SvgPicture.string(_kakaoSvg, width: 20, height: 20), border: null, onPress: onPress);

  const _BrandButton.apple({required VoidCallback? onPress})
      : this(label: 'Apple로 계속하기', bg: const Color(0xFF000000), fg: const Color(0xFFFFFFFF), logo: const Icon(Icons.apple, size: 22, color: Color(0xFFFFFFFF)), border: null, onPress: onPress);

  _BrandButton.google({required VoidCallback? onPress})
      : this(label: 'Google로 계속하기', bg: const Color(0xFFFFFFFF), fg: const Color(0xFF1F1F1F), border: const Color(0xFF747775), logo: SvgPicture.string(_googleSvg, width: 20, height: 20), onPress: onPress);

  final String label;
  final Color bg, fg;
  final Color? border;
  final Widget logo;
  final VoidCallback? onPress;

  static const _kakaoSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 3.2C6.7 3.2 2.4 6.6 2.4 10.8c0 2.7 1.8 5.1 4.5 6.4l-.9 3.4c-.1.3.3.5.5.4l4-2.7c.5.1 1 .1 1.5.1 5.3 0 9.6-3.4 9.6-7.6S17.3 3.2 12 3.2z"/></svg>';
  static const _googleSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>';

  @override
  State<_BrandButton> createState() => _BrandButtonState();
}

class _BrandButtonState extends State<_BrandButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final off = widget.onPress == null;
    // 눌림: 바탕 위에 옅은 검정을 얹는다(회사 색은 그대로 두고 어둡게만)
    final bg = _down && !off ? Color.alphaBlend(const Color(0x14000000), widget.bg) : widget.bg;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      enabled: !off,
      onTap: widget.onPress,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: off ? null : (_) => setState(() => _down = true),
        onTapCancel: off ? null : () => setState(() => _down = false),
        onTapUp: off ? null : (_) => setState(() => _down = false),
        onTap: widget.onPress,
        child: Opacity(
          opacity: off ? 0.45 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Shape.button),
              border: widget.border == null ? null : Border.all(color: widget.border!),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 22, height: 22, child: Center(child: widget.logo)),
              const SizedBox(width: 10),
              Flexible(child: WordText(widget.label, textAlign: TextAlign.center, style: AppType.button.copyWith(fontSize: 16, height: 22 / 16, color: widget.fg))),
            ]),
          ),
        ),
      ),
    );
  }
}
