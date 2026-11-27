// 첫 갈피(첫 안내의 두 번째이자 마지막 차례, 2026-11-27 사용자 '방금 꽂은 책에서 예시 문장 하나를 탭하면 책 위로 갈피가 살짝 나와.
// 직접 입력하는 건 건너뛸 수 있게 하고, 여기서 온보딩을 끝내'): 첫 책을 꽂고 선반을 잠깐 보여 준 뒤 아래 시트.
// 예시 한 줄을 누르면 그 책에 갈피로 꽂고(책 위로 갈피가 올라온다, home_screen 갈피 올리기) 안내를 끝낸다. '직접 쓰기' · '다음에 할게요'도 끝.
// 예시는 책 본문이 아니라 이 책을 두고 적는 짧은 한 줄이다(앱에는 책 본문이 없고, YES24 책 소개 글은 기기에 저장할 수 없다)
library;

import 'package:flutter/material.dart';

import '../../ui/kit.dart';

/// 예시 한 줄(누르면 그대로 첫 갈피 글이 된다)
const firstMarkLines = ['끝까지 읽어 보고 싶은 책', '천천히 아껴 읽을 책', '오늘 내 책장에 처음 꽂은 책'];

/// 고른 것: 예시 한 줄(line) · 직접 쓰기(write). 닫거나 '다음에 할게요'면 null
typedef FirstMarkPick = ({String? line, bool write});

Future<FirstMarkPick?> showFirstMarkSheet(BuildContext context, {required String title}) => showSheet<FirstMarkPick>(
      context,
      title: '첫 갈피를 꽂아 볼까요',
      description: '‘$title’에 꽂아 둘 한 줄을 눌러 보세요.',
      scroll: true,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final line in firstMarkLines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Choice(label: line, selected: false, onPress: () => Navigator.pop(ctx, (line: line, write: false))),
          ),
        const SizedBox(height: Space.s),
        Btn(label: '직접 쓰기', kind: 'secondary', size: 'large', onPress: () => Navigator.pop(ctx, (line: null, write: true))),
        Center(child: SubAction(label: '다음에 할게요', onPress: () => Navigator.pop(ctx))),
      ]),
    );
