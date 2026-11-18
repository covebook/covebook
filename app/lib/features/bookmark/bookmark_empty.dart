// 갈피 탭 빈 화면(저장된 갈피가 하나도 없을 때만): 예시 갈피 한 장 + 안내 + '갈피 남기기'(지금 앱 BookmarkEmpty.tsx).
// 예시 카드는 갈피 탭 목록과 같은 카드 부품이다. 예시 문장은 화면 표현용이다(사용자 데이터에 저장하지 않는다)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../store/mini_timer_store.dart';
import '../../store/reading_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/labels.dart' show dateShort;
import 'bookmark_card.dart';

const _sample = '어떤 문장은\n책을 덮은 뒤에도\n곁에 남아요.';
// 예시 책: 실제 책 표지. 문장은 이 책의 문장이 아니라서 저자는 적지 않고 '예시'로 밝힌다
const _sampleBook = (title: '채식주의자', coverUri: 'https://image.yes24.com/goods/108422348/L', color: '#5276B3');

class BookmarkEmpty extends StatelessWidget {
  const BookmarkEmpty({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // 아래: 탭 바 + 안전 영역 + (독서 중이면 작은 타이머 자리, 아니면 24)
    final bottom = TabBarStyle.navHeight + MediaQuery.paddingOf(context).bottom + (ReadingStore.instance.active != null ? miniTimerSpace : 24);
    final cardW = math.min(MediaQuery.sizeOf(context).width - Space.page * 2, contentMax);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: EdgeInsets.only(top: Space.m, bottom: bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, box.maxHeight - Space.m - bottom)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.line, width: 2 / MediaQuery.devicePixelRatioOf(context))),
              child: Text('예시', style: AppType.micro),
            ),
            Semantics(
              label: '예시 갈피. ${_sample.replaceAll('\n', ' ')}',
              excludeSemantics: true,
              child: IgnorePointer(
                child: BookmarkCard(
                  compact: true,
                  width: cardW,
                  seed: 'sample',
                  data: BookmarkCardData(text: _sample, title: _sampleBook.title, page: 12, date: dateShort(DateTime.now().toIso8601String()), color: _sampleBook.color, coverUri: _sampleBook.coverUri),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Semantics(header: true, child: Text('첫 갈피를 남겨보세요', textAlign: TextAlign.center, style: AppType.heading)),
            ),
            // 공통 규칙: 빈 화면 안내 글은 Empty와 같은 sub · 위 8(2026-11-19. caption · 위 10이었다)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('문장이나 사진으로\n간직하고 싶은 순간을 모아요.', textAlign: TextAlign.center, style: AppType.sub),
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.xl),
              child: SizedBox(width: double.infinity, child: Btn(label: '갈피 남기기', onPress: onAdd)),
            ),
          ]),
        ),
      ),
    );
  }
}
