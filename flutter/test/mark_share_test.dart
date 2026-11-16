// 갈피 공유 그림(2026-11-16 QA 은서 F3): 600자 넘는 글도 두 모양 모두 글 자리 안에 든다(글자를 줄이고, 그래도 넘치면 끝을 '…'로 자른다).
// 짧은 글은 전처럼 시안 크기. 글 상자가 제목·'책장 한켠' 자리와 겹치지 않는다. 갈피 글 정리·표시 도움도 함께
import 'dart:io';

import 'package:chaekjang/features/bookmark/mark_text.dart';
import 'package:chaekjang/features/share/mark_scene.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> font(String family, String file) async {
  final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
  await l.load();
}

// QA 은서가 넣은 긴 산문(직접 입력 607자와 같은 길이의 영어+한글)
final long = [
  'That night the snow did not stop. I sat by the window and read the note she had left, again and again: "I will keep the light on when you come back." It was only a single line, yet each time I read it the weight of the sentence shifted a little.',
  'Did (keep it on) mean waiting, or did it mean not forgetting? I put the kettle on without knowing the answer — only the sound of boiling water filled the room\'s quiet. The candle leaned whenever the wind slipped through the door, and the shadow spread slowly up the wall.',
  '새벽 네 시, 마침내 멀리서 발소리가 들렸다. 나는 일어나지 않았다. 다만 불이 꺼지지 않았는지 한 번 더 확인했을 뿐이다. 그날 밤은 그렇게 지나갔다.',
].join('\n\n');

void main() {
  setUpAll(() async {
    await font('MaruBuriRegular', 'assets/fonts/MaruBuri-Regular.ttf');
    await font('PretendardRegular', 'assets/fonts/Pretendard-Regular.otf');
    await font('PretendardSemiBold', 'assets/fonts/Pretendard-SemiBold.otf');
    await font('ReadingSerif', 'assets/fonts/NotoSerifKR-Regular.otf');
  });

  test('긴 글(600자+)은 글 자리 안에 들고, 읽을 수 있는 크기 아래로는 줄이지 않고 잘라 알린다', () {
    expect(long.length, greaterThan(600));
    final sw = Stopwatch()..start();
    // 글 자리(시안 화소): 책 페이지는 지은이 줄(아래 62) 위, 종이 메모는 찢은 종이 안·제목 줄(1193) 위
    const room = {MarkStyle.page: (top: 300.0, bottom: 1150.0), MarkStyle.note: (top: 513.0, bottom: 1110.0)};
    for (final s in MarkStyle.values) {
      final b = markQuoteBox(s, long);
      expect(b.top, greaterThanOrEqualTo(room[s]!.top - 0.5), reason: '$s 위');
      expect(b.bottom, lessThanOrEqualTo(room[s]!.bottom + 0.5), reason: '$s 아래');
      expect(b.size, greaterThanOrEqualTo(30), reason: '$s 글자 크기');
      expect(b.cut, isTrue, reason: '$s 앞부분만');
    }
    // 미리보기는 화면을 그리는 길에서 잰다: 두 모양 합쳐 오래 걸리지 않는다
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });

  test('조금 긴 글(200자)은 자르지 않고 글자만 줄여 다 넣는다', () {
    final mid = long.substring(0, 200);
    for (final s in MarkStyle.values) {
      final b = markQuoteBox(s, mid);
      expect(b.cut, isFalse, reason: '$s');
      expect(b.size, lessThan(60), reason: '$s');
    }
  });

  test('짧은 글은 전처럼 시안 크기', () {
    expect(markQuoteBox(MarkStyle.page, '누구에게나 자기 자신에게로 가는 길이 있다.').size, 68.5);
    expect(markQuoteBox(MarkStyle.note, '누구에게나 자기 자신에게로 가는 길이 있다.').size, 72);
    expect(markQuoteBox(MarkStyle.page, '누구에게나 자기 자신에게로 가는 길이 있다.').cut, isFalse);
  });

  test('저장할 글: 앞 빈 줄·끝 공백만 정리하고 첫 줄 들여쓰기는 지킨다(F10)', () {
    expect(tidyMarkText('\n \n  When the snow comes\n    I stand\n\n  '), '  When the snow comes\n    I stand');
    expect(tidyMarkText('줄 안  공백과\n \n공백만 있는 줄 '), '줄 안  공백과\n \n공백만 있는 줄');
    expect(tidyMarkText('   '), '');
  });

  test('사진 갈피는 글 없이 사진만, 쪽 표기는 p. 하나, 삭제 확인에 보일 한 줄(F1·F11)', () {
    expect(isPhotoMark('', 'file:///a.jpg'), isTrue);
    expect(isPhotoMark(' \n', 'file:///a.jpg'), isTrue);
    expect(isPhotoMark('옮긴 문장', 'file:///a.jpg'), isFalse);
    expect(isPhotoMark('', null), isFalse);
    expect(pageLabel(118), 'p. 118');
    expect(markLabel('그날 밤 눈은 그치지 않았다.\n나는 창가에 앉아 그녀가 남긴 쪽지를', 118), '“그날 밤 눈은 그치지 않았다. 나는 창가에…” · p. 118');
    expect(markLabel('', 52), '사진 갈피 · p. 52');
    expect(markLabel('짧은 글', null), '“짧은 글”');
  });
}
