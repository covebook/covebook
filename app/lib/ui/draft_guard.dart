// 쓰던 것 지킴(docs/design/DESIGN.md 12장 '입력 · 저장 · 취소'): 저장 단추가 있는 화면에서 바꾼 것이 있으면 나갈 때 한 번 묻는다.
// 2026-11-20 사용자: '버릴까요 말고 다른 느낌으로 취소할까요나 그만 쓸까요 이런 느낌으로 하고 취소 확인으로 테마색으로'
// → 제목은 '○○을 그만할까요?', 단추는 왼쪽 '취소'(머문다, secondary) · 오른쪽 '확인'(나간다, primary 갈색)
import 'package:flutter/material.dart';

import 'alert.dart';

/// 나갈 때 묻기. 새로 쓰는 화면(갈피 남기기 · 감상 쓰기)은 '그만 쓸까요?',
/// 고치는 화면(갈피 · 감상 · 책 정보 · 장정 · 독서 기록 수정)은 [DraftGuard.edit]: '수정을 그만할까요?'.
/// 단추는 늘 '취소'(머물기) · '확인'(나가기). onLeave가 없으면 화면(경로)을 닫고, 있으면(갈피 수정처럼 같은 화면 안 단계) 그것을 부른다
class DraftGuard extends StatelessWidget {
  const DraftGuard({super.key, required this.dirty, required this.child, this.title = '그만 쓸까요?', this.body = '지금 나가면 쓴 내용은 저장되지 않아요.', this.onLeave});

  /// 고치는 화면
  const DraftGuard.edit({super.key, required this.dirty, required this.child, this.onLeave})
      : title = '수정을 그만할까요?',
        body = '지금 나가면 고친 내용은 저장되지 않아요.';

  /// 나갈 때 물을지(지금 값을 읽는다: 칸을 고쳐도 화면을 다시 그리지 않는 곳이 있다)
  final bool Function() dirty;
  final String title;

  /// 확인창 본문(찾아 둔 목록처럼 '저장'이 아닌 화면은 그에 맞게)
  final String body;
  final VoidCallback? onLeave;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: onLeave == null && !dirty(),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // 저장 뒤 닫기·나가기는 Navigator.pop이라 여기를 지나지 않는다(pop은 canPop과 상관없이 닫는다)
          final leave = onLeave ?? () => Navigator.of(context).pop();
          if (!dirty()) return leave();
          appAlert(context, title, body, [
            const AlertButton('취소', style: AlertStyle.cancel),
            AlertButton('확인', onPress: leave),
          ]);
        },
        child: child,
      );
}
