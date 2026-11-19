// 갈피·감상 쓰기 화면이 함께 쓰는 부품(2026-11-19 공통 규칙): 쓰던 글 지킴(갈피 남기기 · 갈피 수정 · 감상 쓰기 · 감상 수정),
// 갈피 칸 이름 · 높이, 사진을 못 넣었을 때 안내, 사진 칩 줄(다시 찍기 · 다른 사진 · 사진 빼기)
library;

import 'package:flutter/material.dart';

export '../../ui/draft_guard.dart';
import '../../services/photos.dart' show deniedMessage;
import '../../ui/feedback.dart' show errorText;
import '../../ui/kit.dart';
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

/// 사진 단추 줄(갈피 남기기 · 갈피 수정): 다시 찍기 · 다른 사진 · (onRemove가 있으면) 사진 빼기. 사진 아래 가운데.
/// TDS에 칩이 없어 행동 단추는 Button small weak(dark)
class PhotoChips extends StatelessWidget {
  const PhotoChips({super.key, required this.onCamera, required this.onLibrary, this.onRemove});
  final VoidCallback onCamera, onLibrary;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Wrap(alignment: WrapAlignment.center, spacing: Space.s, runSpacing: Space.s, children: [
          Btn(label: '다시 찍기', kind: 'secondary', size: 'small', onPress: onCamera),
          Btn(label: '다른 사진', kind: 'secondary', size: 'small', onPress: onLibrary),
          if (onRemove != null) Btn(label: '사진 빼기', kind: 'secondary', size: 'small', onPress: onRemove!),
        ]),
      );
}
