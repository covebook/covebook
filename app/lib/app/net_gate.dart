// 인터넷이 없으면 앱 전체를 막는 화면(SCREENS 314, 2026-11-21 사용자 '인터넷이 없으면 막자'). 서버가 있는 빌드(로그인 필수)만.
// 앱 화면(모든 경로 · 확인창 · 시트) 위에 한 겹으로 덮는다: 아래 화면은 그대로 두어(읽던 타이머 · 쓰던 글) 다시 연결되면 저절로 걷히고 이어서 쓴다.
// 모양은 화면 전체 실패 상태(DESIGN 11장 `Empty`): 제목 + 짧은 본문 + '다시 시도'
library;

import 'package:flutter/material.dart';

import '../services/net_status.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

class NetGate extends StatefulWidget {
  const NetGate({super.key, required this.child});
  final Widget child;

  @override
  State<NetGate> createState() => _NetGateState();
}

class _NetGateState extends State<NetGate> {
  final _net = NetStatus.instance;
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _net.check();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _net,
        builder: (context, child) => Stack(children: [
          child!,
          if (_net.enabled && !_net.online)
            Positioned.fill(
              child: Material(
                color: AppColors.bg,
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: Space.page),
                      child: Semantics(
                        liveRegion: true,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const ExcludeSemantics(child: LucideIcon('WifiOff', size: 40, color: AppColors.icon)),
                          const SizedBox(height: Space.l),
                          Empty(
                            title: '인터넷에 연결되어 있지 않아요',
                            body: '책장 한켠은 인터넷에 연결되어 있어야 쓸 수 있어요. 와이파이나 모바일 데이터를 켜 주세요.',
                            action: '다시 시도',
                            actionKind: 'secondary',
                            onAction: _retry,
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        child: widget.child,
      );
}
