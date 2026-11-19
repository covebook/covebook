// 쓰던 것 지킴(docs/design/DESIGN.md 12장 '입력 · 저장 · 취소'): 저장 단추가 있는 화면에서 바꾼 것이 있으면 나갈 때 한 번 묻는다
import 'package:flutter/material.dart';

import 'alert.dart';

/// 나갈 때 묻기. 새로 쓰는 화면(갈피 남기기 · 감상 쓰기)은 '쓰던 내용을 버릴까요?' + '계속 쓰기',
/// 고치는 화면(갈피 · 감상 · 책 정보 · 장정 · 독서 기록 수정)은 [DraftGuard.edit]: '고친 내용을 버릴까요?' + '계속 수정'.
/// onLeave가 없으면 화면(경로)을 닫고, 있으면(갈피 수정처럼 같은 화면 안 단계) 그것을 부른다
class DraftGuard extends StatelessWidget {
  const DraftGuard({super.key, required this.dirty, required this.child, this.title = '쓰던 내용을 버릴까요?', this.keep = '계속 쓰기', this.onLeave});

  /// 고치는 화면
  const DraftGuard.edit({super.key, required this.dirty, required this.child, this.onLeave})
      : title = '고친 내용을 버릴까요?',
        keep = '계속 수정';

  /// 나갈 때 물을지(지금 값을 읽는다: 칸을 고쳐도 화면을 다시 그리지 않는 곳이 있다)
  final bool Function() dirty;
  final String title;

  /// 머무는 쪽 단추 이름(취소 자리)
  final String keep;
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
            AlertButton(keep, style: AlertStyle.cancel),
            AlertButton('버리기', style: AlertStyle.destructive, onPress: leave),
          ]);
        },
        child: child,
      );
}
