// 책 화면들(책 추가 · 내 책 · 책 정보 · 바코드 · 목록 가져오기 · 책 정보 수정)이 같이 쓰는 값과 작은 부품.
// 2026-11-19 공통 규칙: 화면마다 따로 있던 읽기 상태 차례 · 숫자 칸 읽기 · ISBN 정리 · 대체 표지색 · 표지 단추 · 접는 줄을 하나로
library;

import 'package:flutter/material.dart';

import '../../domain/library.dart' show ReadStatus;
import '../../services/photos.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// 읽기 상태 차례(읽고 싶은 · 읽는 중 · 읽은 책 · 보류). 책 추가 칩 · 내 책 탭 · 책 정보 상태 시트가 같은 차례
const bookStatuses = [ReadStatus.want, ReadStatus.reading, ReadStatus.read, ReadStatus.paused];

/// 표지가 없을 때 대체 표지 바탕(AppColors.surface와 같은 회색. RealCover는 색을 '#rrggbb' 글자로 받는다)
const coverPlaceholder = '#F2F4F6';

/// 칸에 적은 숫자(쪽수 · 판형 mm): 숫자만 읽어 반올림. 0 이하이거나 못 읽으면 null
int? numOf(String v) {
  final n = double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), ''));
  return n != null && n.isFinite && n > 0 ? n.round() : null;
}

/// ISBN 정리: 숫자와 X만 남긴다
String cleanIsbn(String? v) => (v ?? '').replaceAll(RegExp(r'[^\dXx]'), '');

/// 표지 사진 고르기(책 확인 · 책 정보 수정이 같은 이름 · 모양: 줄 안 작은 보조 단추). 표지가 있으면 '표지 바꾸기', 없으면 '표지 사진 등록'
class CoverPhotoButton extends StatelessWidget {
  const CoverPhotoButton({super.key, required this.hasCover, required this.onPicked, required this.onDenied});
  final bool hasCover;
  final ValueChanged<String> onPicked;

  /// 사진 보관함 권한이 없을 때(안내 글을 넘긴다)
  final ValueChanged<String> onDenied;

  @override
  Widget build(BuildContext context) => Btn(
        label: hasCover ? '표지 바꾸기' : '표지 사진 등록',
        kind: 'secondary',
        size: 's',
        onPress: () async {
          final r = await pickPhoto('library');
          if (!context.mounted) return;
          if (r case PhotoOk(:final uri)) {
            onPicked(uri);
          } else if (r case PhotoFail(reason: 'denied')) {
            onDenied(deniedMessage('library'));
          }
        },
      );
}

/// 누르면 펼쳐지는 줄(책 확인 '추가 정보' · 목록 가져오기 안내 두 줄): 위 머리카락 선, 제목(구역 제목 19)과 그 아래 설명 한 줄(sub),
/// 오른쪽 ⌄(펼치면 뒤집힌다). last면 아래에도 선. 2026-11-19 공통 규칙: 두 화면이 글자 · 선 · 높이 · 펼침 표시가 서로 달랐다
class FoldRow extends StatelessWidget {
  const FoldRow({super.key, required this.title, this.note, required this.open, required this.onToggle, required this.child, this.last = false});
  final String title;

  /// 제목 아래 한 줄([metaSep]으로 이을 수 있다)
  final String? note;
  final bool open, last;
  final VoidCallback onToggle;

  /// 펼쳤을 때 보일 내용
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Hairline(),
        Semantics(
          button: true,
          expanded: open,
          label: [title, ?note?.split(metaSep).join(', ')].join(', '),
          excludeSemantics: true,
          onTap: onToggle,
          child: Pressable(
            onPress: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.l),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    WordText(title, style: AppType.section),
                    if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: MetaText(note!, style: AppType.sub)),
                  ]),
                ),
                const SizedBox(width: Space.m),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 160), child: const LucideIcon('ChevronDown', color: AppColors.inkSoft)),
              ]),
            ),
          ),
        ),
        if (open) child,
        if (last) const Hairline(),
      ]);
}
