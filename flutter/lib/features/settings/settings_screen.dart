// 설정(지금 앱 app/settings.tsx, 하단 '내 정보' 탭): 독서 환경(진동·움직임 줄이기) / 내 기록(백업 및 복원·커뮤니티 공개 프로필) / 앱 안내(문의·개인정보·앱 정보).
// 흰 바탕, 줄 사이 선 없음, 묶음 사이 화면 끝까지 닿는 1dp 선. 다른 화면으로 가는 줄에만 화살표.
// 서버 주소가 없는 빌드는 '이 기기에만 저장' 쪽 문구를 쓴다(지금 앱도 서버를 못 쓰면 같은 문구)
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../community/community_screens.dart' show communityOpen, openCommunityProfile;
import 'package:url_launcher/url_launcher.dart';

import '../../store/settings_store.dart';
import '../../ui/alert.dart';
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../services/sync.dart';
import '../../ui/theme.dart';
import '../book/import_list_screen.dart' show openImportList;
import 'backup_screen.dart' show openBackup;

const privacyUrl = 'https://midi-broccoli-56c.notion.site/Covebook-3eb50284670881b0a0e2c6029cea29c7';
const _mail = 'yuntyu01@gmail.com';
const _motion = [
  (id: 'system', label: '기기 설정 따르기', short: '기기 설정'),
  (id: 'on', label: '켜기', short: '켬'),
  (id: 'off', label: '끄기', short: '끔'),
];

/// 서버 동기화를 쓸 수 있는지(서버 주소가 있는 빌드)
bool get _syncAvailable => SyncService.instance.available;

/// 내 정보(설정·백업 및 복원·계정·진동·움직임 줄이기·문의·개인정보): 책장 머리 프로필에서 연다(2026-11-16 메뉴 구조 개편, 하단 '내 정보' 탭을 뺐다)
Future<void> openProfile(BuildContext context) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/me'), builder: (_) => const SettingsScreen()));

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.tab = false});

  /// 하단 탭으로 둘 때(뒤로 없음, 떠 있는 탭 바만큼 아래 여백). 지금은 머리 프로필에서 밀어 넣어 연다
  final bool tab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = SettingsStore.instance;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
    communityOpen.addListener(_changed);
    _s.load();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    communityOpen.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _motionSheet() => showSheet<void>(
        context,
        title: '움직임 줄이기',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Text('켜면 책이 움직이는 연출과 독서 장면의 움직임을 줄여요.', style: AppType.sub)),
          ListGroup(children: [
            for (final m in _motion)
              ListItem(
                label: m.label,
                selected: _s.reduceMotion == m.id,
                right: _s.reduceMotion == m.id ? const LucideIcon('Check', color: AppColors.accent, stroke: 2) : null,
                onPress: () {
                  _s.set({'reduceMotion': m.id});
                  Navigator.pop(ctx);
                },
              ),
          ]),
        ]),
      );

  // 실제 동작과 맞춘 안내(2026-11-16 QA 현우 F3): 글자 인식·바코드는 기기 안, 검색은 책장 한켠 서버 → Google Books → Open Library,
  // 백업은 다운로드/책장한켠에 바로 저장하거나 공유로 보낸다, 계정 삭제는 서버를 쓰는 빌드에서만, 공개되는 것이 있는지.
  // 웹 전문(노션)에 맞출 문구 초안은 docs/privacy-draft-2026-11-16.md
  void _privacySheet() => showSheet<void>(
        context,
        title: '개인정보 처리 안내',
        scroll: true,
        maxHeight: 0.8,
        builder: (ctx) {
          final p = AppType.body.copyWith(color: AppColors.ink);
          Widget para(String t) => Padding(padding: const EdgeInsets.only(bottom: Space.item), child: Text(keepAll(t), style: p));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            para(_syncAvailable
                ? '책장 한켠은 로그인 없이 쓸 수 있어요. 책·독서 기록·갈피·감상·사진은 이 기기에 저장되고, 이 기기 전용 계정으로 책장 한켠 서버에도 동기화돼요. Apple·카카오·Google을 연결하면 그 서비스의 회원 식별자와 고른 닉네임이 서버에 저장되고, 다른 기기에서 같은 기록을 이어 볼 수 있어요.'
                : '책장 한켠은 로그인 없이 써요. 책·독서 기록·갈피·감상·사진은 이 기기 안에만 저장돼요.'),
            para('책을 찾으면 검색어가 책장 한켠 서버를 거쳐 YES24로 전송돼요. 서버에 닿지 않거나 결과가 없으면 Google Books로, 그래도 없으면 Open Library로 바로 전송돼요. 인기 많은 책 목록도 책장 한켠 서버에서 받아요. 검색과 표지 그림을 받을 때 IP 주소 같은 통신 정보가 함께 전달돼요.'),
            para('사진은 표지를 넣거나 갈피 원문을 보관하는 데만 쓰고, 읽었다는 인증에는 쓰지 않아요. 갈피 사진의 글자 인식과 바코드 읽기는 기기 안에서 하고, 그 사진을 밖으로 보내지 않아요.'
                '${_syncAvailable ? ' 동기화를 위해 사진은 책장 한켠 서버에 올라가요.' : ''}'),
            para(Platform.isAndroid
                ? '백업 파일은 직접 만들 때만 생겨요. 다운로드/책장한켠 폴더에 바로 저장하거나, 공유로 고른 앱(드라이브·메신저 등)으로 보내요. 그 파일에는 위 기록과 직접 찍거나 고른 사진이 들어 있어요(검색으로 넣은 책 표지는 빠져요).'
                : '백업 파일은 직접 만들 때만 생기고, 공유로 고른 곳(파일·드라이브·메신저 등)으로 보내요. 그 파일에는 위 기록과 직접 찍거나 고른 사진이 들어 있어요(검색으로 넣은 책 표지는 빠져요).'),
            para(_syncAvailable && communityOpen.value
                ? '내 기록은 공개되지 않아요. 커뮤니티에 직접 올린 글과 고른 항목만 공개돼요.'
                : '공개되는 기록은 없어요. 별점·한줄평·감상·갈피는 나만 봐요.'),
            // 계정 삭제는 서버를 쓰는 빌드에만 있다(로그인 없는 빌드에서 '서버 계정 삭제'를 말하지 않는다)
            if (_syncAvailable) para('서버 계정 삭제를 요청하면 연결된 로그인과 서버 기록·사진을 삭제 처리하고, 이 기기의 기록은 남겨요.'),
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Btn(label: '처리방침 전문 보기(웹)', kind: 'secondary', onPress: () => launchUrl(Uri.parse(privacyUrl), mode: LaunchMode.externalApplication)),
            ),
          ]);
        },
      );

  Future<void> _mailTo() async {
    final ok = await launchUrl(Uri.parse('mailto:$_mail')).catchError((_) => false);
    if (!ok && mounted) appAlert(context, '메일 앱을 열 수 없어요', '$_mail 으로 보내 주세요.');
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return Screen(
      title: '내 정보',
      back: !tab,
      bottomPad: tab ? TabBarStyle.contentPad - Space.section : 0,
      children: [
        ListGroup(title: '독서 환경', children: [
          ListItem(label: '진동', right: Toggle(label: '진동', value: _s.haptics, onChange: (v) => _s.set({'haptics': v}))),
          ListItem(label: '움직임 줄이기', value: _motion.where((m) => m.id == _s.reduceMotion).firstOrNull?.short, onPress: _motionSheet),
        ]),
        const SectionBand(),
        ListGroup(title: '내 기록', children: [
          ListItem(label: '백업 및 복원', sub: _syncAvailable ? '기록은 이 기기와 서버에 저장돼요' : '기록은 이 기기에 저장돼요', chevron: true, onPress: () => openBackup(context)),
          // 다른 앱·엑셀에 정리해 둔 책을 한 번에(2026-11-15 사용자 'CSV·엑셀 가져오기 다 넣어')
          ListItem(label: '책 목록 가져오기', sub: '엑셀·CSV 파일로 여러 권을 한 번에', chevron: true, onPress: () => openImportList(context)),
          // 커뮤니티가 열렸고 서버를 쓰는 빌드일 때만
          if (communityOpen.value && _syncAvailable) ListItem(label: '커뮤니티 공개 프로필', chevron: true, onPress: () => openCommunityProfile(context)),
        ]),
        const SectionBand(),
        ListGroup(title: '앱 안내', children: [
          ListItem(label: '문의하기', sub: _mail, onPress: _mailTo),
          ListItem(label: '개인정보 처리방침', onPress: _privacySheet),
          ListItem(label: '앱 정보', value: _version),
        ]),
        const BrandFooter(),
      ],
    );
  }
}
