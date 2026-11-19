// 갈피·감상 쓰기 화면이 함께 쓰는 부품(2026-11-19 공통 규칙): 쓰던 글 지킴(갈피 남기기 · 갈피 수정 · 감상 쓰기 · 감상 수정),
// 안내·오류 글(회색 상자 없이 글자만), 사진 칩 줄(다시 찍기 · 다른 사진 · 사진 빼기)
library;

import 'package:flutter/material.dart';

import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// 쓰던 글 지킴: 적은 것이 있으면 나갈 때 묻는다(docs/design/DESIGN.md 5장). 문구·단추는 네 화면이 같다.
/// onLeave가 없으면 화면(경로)을 닫고, 있으면(갈피 수정처럼 같은 화면 안 단계) 그것을 부른다
class DraftGuard extends StatelessWidget {
  const DraftGuard({super.key, required this.dirty, required this.child, this.title = '쓰던 내용을 버릴까요?', this.onLeave});

  /// 나갈 때 물을지(지금 값을 읽는다: 칸을 고쳐도 화면을 다시 그리지 않는 곳이 있다)
  final bool Function() dirty;
  final String title;
  final VoidCallback? onLeave;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: onLeave == null && !dirty(),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // 저장 뒤 닫기·버리기는 Navigator.pop이라 여기를 지나지 않는다(pop은 canPop과 상관없이 닫는다)
          final leave = onLeave ?? () => Navigator.of(context).pop();
          if (!dirty()) return leave();
          appAlert(context, title, '지금 나가면 저장되지 않아요.', [
            const AlertButton('계속 쓰기', style: AlertStyle.cancel),
            AlertButton('버리기', style: AlertStyle.destructive, onPress: leave),
          ]);
        },
        child: child,
      );
}

/// 안내·오류 글(지금 앱 Notice): 흰 화면 안 회색 상자 없이 글자만. 안내는 sub, 오류는 sub danger(2026-11-19 공통 규칙 8장)
class NoticeText extends StatelessWidget {
  const NoticeText(this.text, {super.key, this.error = false, this.center = false});
  final String text;
  final bool error;
  final bool center;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Semantics(
          liveRegion: true,
          child: WordText(text, textAlign: center ? TextAlign.center : null, style: error ? AppType.sub.copyWith(color: AppColors.danger) : AppType.sub),
        ),
      );
}

/// 사진 칩 줄(갈피 남기기 · 갈피 수정): 다시 찍기 · 다른 사진 · (onRemove가 있으면) 사진 빼기. 사진 아래 가운데
class PhotoChips extends StatelessWidget {
  const PhotoChips({super.key, required this.onCamera, required this.onLibrary, this.onRemove});
  final VoidCallback onCamera, onLibrary;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Wrap(alignment: WrapAlignment.center, spacing: Space.s, runSpacing: Space.s, children: [
          AppChip(label: '다시 찍기', onPress: onCamera),
          AppChip(label: '다른 사진', onPress: onLibrary),
          if (onRemove != null) AppChip(label: '사진 빼기', onPress: onRemove),
        ]),
      );
}
