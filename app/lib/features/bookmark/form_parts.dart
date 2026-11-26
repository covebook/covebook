// 갈피·감상 쓰기 화면이 함께 쓰는 부품(2026-11-19 공통 규칙): 쓰던 글 지킴(갈피 남기기 · 갈피 수정 · 감상 쓰기 · 감상 수정),
// 갈피 칸 이름 · 높이, 사진을 못 넣었을 때 안내, 사진 메뉴(다시 찍기 · 다른 사진 · 사진 빼기)
library;

import 'package:flutter/material.dart';

export '../../ui/draft_guard.dart';
import '../../services/photos.dart' show deniedMessage;
import '../../ui/feedback.dart' show errorText;
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'page_photo.dart' show cropCanceledMessage;

/// 갈피 글 칸(갈피 남기기 · 갈피 수정이 같은 이름 · 안내 · 높이, 2026-11-19 공통 규칙: 두 화면이 '문장' 160 · '문장 (줄바꿈으로…)' 190,
/// 메모 안내도 달랐다). 높이 역할은 kit ControlSize에 아직 없어 여기 한곳에 둔다
const markTextLabel = '문장', markTextHint = '마음에 남은 문장을 옮겨 적어 주세요', markTextHeight = 160.0;

/// 사진 갈피의 옮겨 적기 칸(갈피 수정)
const markTranscribeHeight = 120.0;

/// 갈피 메모 칸: 나만 보는 메모, 공유 그림에는 '메모 포함해 공유'를 고를 때만 들어간다
const markMemoLabel = '한 줄 메모 (선택)', markMemoHint = '나만 보는 메모예요. 공유 이미지에는 기본으로 빠져요', markMemoHeight = 80.0;

/// 사진을 넣지 못했을 때 안내(갈피 남기기 · 갈피 수정): 권한 거부 · 자르기 취소는 사용자가 고른 것이라 회색 안내, 그 밖은 오류(공통 규칙 11장).
/// 플랫폼 오류 원문은 화면에 보이지 않는다(errorText가 로그로). 고르기 취소는 조용히(null)
({String text, bool error})? photoFailNotice(String from, String reason, String? message) => switch (reason) {
      'denied' => (text: deniedMessage(from), error: false),
      'crop' => (text: cropCanceledMessage, error: false),
      'error' => (text: '사진을 가져오지 못했어요. ${errorText(message ?? reason)}', error: true),
      _ => null,
    };

/// 사진과 사진 메뉴(갈피 남기기 · 갈피 수정): 사진 오른쪽 아래 흰 원 '⋯'. 누르면 시트 다시 찍기 · 다른 사진 · (onRemove가 있으면) 사진 빼기.
/// 사진 아래 단추 줄(다시 찍기 · 다른 사진 · 사진 빼기)이 자리를 차지했다(2026-11-21 갈피 남기기 시안)
class PhotoWithMenu extends StatelessWidget {
  const PhotoWithMenu({super.key, required this.plate, required this.onCamera, required this.onLibrary, this.onRemove});
  final Widget plate;
  final VoidCallback onCamera, onLibrary;
  final VoidCallback? onRemove;

  /// 메뉴 단추 지름
  static const size = 36.0;

  Future<void> _menu(BuildContext context) => showSheet<void>(
        context,
        builder: (ctx) => ListGroup(children: [
          ListItem(label: '다시 찍기', icon: const LucideIcon('Camera', color: AppColors.icon), onPress: () {
            Navigator.pop(ctx);
            onCamera();
          }),
          ListItem(label: '다른 사진', icon: const LucideIcon('Image', color: AppColors.icon), onPress: () {
            Navigator.pop(ctx);
            onLibrary();
          }),
          if (onRemove != null)
            ListItem(label: '사진 빼기', danger: true, icon: const LucideIcon('Trash2', color: AppColors.danger), onPress: () {
              Navigator.pop(ctx);
              onRemove!();
            }),
        ]),
      );

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        plate,
        Positioned(
          right: Space.s,
          bottom: Space.s,
          child: Semantics(
            container: true,
            button: true,
            label: '사진 메뉴',
            onTap: () => _menu(context),
            excludeSemantics: true,
            child: Pressable(
              onPress: () => _menu(context),
              // 누르는 자리 48, 보이는 원 36
              child: SizedBox(
                width: Space.hit,
                height: Space.hit,
                child: Center(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle, boxShadow: [Shape.floatShadow]),
                    child: const Center(child: LucideIcon('MoreHorizontal', size: IconSize.small, color: AppColors.inkSoft)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
}
