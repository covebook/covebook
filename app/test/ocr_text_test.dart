// 문장 인식 결과 → 갈피 문장: 줄 잇기·영어 하이픈 붙이기·문단 사이 빈 줄·흐린 줄 세기,
// 그리고 2026-11-16 QA 은서 사진 5장(산문·흐림·기울어짐·영어·시)의 인식 원본으로 고치기 전후를 정답과 견준다(F5·F6)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chaekjang/domain/ocr_text.dart';
import 'package:flutter_test/flutter_test.dart';

OcrLine l(String t, [double c = 0.9]) => (text: t, left: 0, top: 0, right: 0, bottom: 0, confidence: c);

/// 고치기 전 규칙(줄은 늘 띄워 잇기, 블록 사이 빈 줄, 머리글·쪽번호 그대로)
String before(OcrResult r, LineMode mode) {
  final paras = <String>[];
  for (final b in r.blocks) {
    final lines = [for (final l in b.lines) if (l.text.trim().isNotEmpty) l.text.trim()];
    if (lines.isEmpty) continue;
    if (mode == LineMode.keep) {
      paras.add(lines.join('\n'));
      continue;
    }
    var out = lines.first;
    for (final next in lines.skip(1)) {
      out = RegExp(r'[A-Za-z]-$').hasMatch(out) && RegExp(r'^[A-Za-z]').hasMatch(next) ? out.substring(0, out.length - 1) + next : '$out $next';
    }
    paras.add(out.replaceAll(RegExp(r'\s{2,}'), ' '));
  }
  return paras.join('\n\n').trim();
}

int edits(String a, String b) {
  final x = a.runes.toList(), y = b.runes.toList();
  var prev = List<int>.generate(y.length + 1, (i) => i);
  for (var i = 1; i <= x.length; i++) {
    final cur = List<int>.filled(y.length + 1, 0)..[0] = i;
    for (var j = 1; j <= y.length; j++) {
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[y.length];
}

String noSpace(String s) => s.replaceAll(RegExp(r'\s'), '');

typedef Case = ({String name, OcrResult r, String answer, LineMode mode, int page});

List<Case> cases() {
  final d = jsonDecode(File('test/fixtures/ocr_pages.json').readAsStringSync()) as Map<String, Object?>;
  return [
    for (final p in (d['pages']! as List).cast<Map<String, Object?>>())
      (
        name: p['name']! as String,
        r: (
          width: p['width']! as int,
          height: p['height']! as int,
          blocks: [
            for (final b in (p['blocks']! as List).cast<Map<String, Object?>>())
              (
                text: '',
                lines: [
                  for (final x in (b['lines']! as List).cast<Map<String, Object?>>())
                    () {
                      final box = (x['box']! as List).cast<int>();
                      return (text: x['text']! as String, left: box[0], top: box[1], right: box[2], bottom: box[3], confidence: (x['confidence']! as num).toDouble());
                    }(),
                ],
              ),
          ],
        ),
        answer: p['answer']! as String,
        mode: p['mode'] == 'keep' ? LineMode.keep : LineMode.join,
        page: p['page']! as int,
      ),
  ];
}

void main() {
  final r = (
    width: 100,
    height: 100,
    blocks: <OcrBlock>[
      (text: '', lines: [l('나는 그 문장을 '), l('오래 붙잡고 있었다.  '), l('read-'), l('ing is fun', 0.3)]),
      (text: '', lines: [l('  '), l('두 번째 문단', 0)]),
    ],
  );
  test('줄 끝 이어 쓰기', () {
    expect(ocrText(r, LineMode.join), '나는 그 문장을 오래 붙잡고 있었다. reading is fun\n\n두 번째 문단');
  });
  test('줄바꿈 그대로', () {
    expect(ocrText(r, LineMode.keep), '나는 그 문장을\n오래 붙잡고 있었다.\nread-\ning is fun\n\n두 번째 문단');
  });
  test('흐린 줄(신뢰도 0은 세지 않는다)', () {
    expect(lowConfidenceLines(r), 1);
  });

  test('한글 줄 끝: 낱말 가운데 끊김(ㅆ 받침 끝·조사·어미로 시작)만 붙이고, 고르면 늘 붙이거나 늘 띄운다', () {
    expect(midWord('확인했', '을 뿐이다.'), isTrue);
    expect(midWord('잊지 않겠', '다는 뜻일까.'), isTrue);
    expect(midWord('물을 올', '렸다 — 물이'), isTrue);
    expect(midWord('바람이 문틈', '으로 스며들'), isTrue);
    expect(midWord('문장의 무게', '가 조금씩'), isTrue);
    expect(midWord('벽을 타', '고 천천히'), isTrue);
    expect(midWord('앉아 그녀가', '남긴 쪽지를'), isFalse);
    expect(midWord('불을 켜', '둘게.'), isFalse);
    // 혼자 낱말로도 흔한 '나·다·서'로 시작하면 띄운다
    expect(midWord('그때', '나는 웃었다'), isFalse);
    expect(midWord('여기,', '서 있다'), isFalse);
    final two = (width: 10, height: 10, blocks: <OcrBlock>[(text: '', lines: [l('나는 일어'), l('나지 않았다.')])]);
    expect(ocrText(two, LineMode.join), '나는 일어 나지 않았다.');
    expect(ocrText(two, LineMode.join, words: WordJoin.attach), '나는 일어나지 않았다.');
    final three = (width: 10, height: 10, blocks: <OcrBlock>[(text: '', lines: [l('확인했'), l('을 뿐이다.')])]);
    expect(ocrText(three, LineMode.join, words: WordJoin.space), '확인했 을 뿐이다.');
    // 여는 괄호 뒤·닫는 문장부호 앞은 띄우지 않는다
    final q = (width: 10, height: 10, blocks: <OcrBlock>[(text: '', lines: [l('그녀가 남긴 「'), l('돌아오면'), l('.」 짧은')])]);
    expect(ocrText(q, LineMode.join), '그녀가 남긴 「돌아오면.」 짧은');
  });

  test('좌표가 없으면 맨 끝의 쪽번호만 빼서 돌려준다', () {
    final p = (width: 10, height: 10, blocks: <OcrBlock>[(text: '', lines: [l('본문')]), (text: '', lines: [l('- 52 -')])]);
    expect(readOcr(p, LineMode.join), (text: '본문', page: 52));
    // 숫자만 있는 글 하나는 본문이다
    final only = (width: 10, height: 10, blocks: <OcrBlock>[(text: '', lines: [l('1984')])]);
    expect(readOcr(only, LineMode.join), (text: '1984', page: null));
  });

  group('QA 사진 5장(인식 원본 + 줄 상자)', () {
    final all = cases();
    final rows = <String>[];
    for (final c in all) {
      test('${c.name}: 정답과 거리가 줄고 쪽번호를 찾는다', () {
        final old = before(c.r, c.mode);
        final now = readOcr(c.r, c.mode);
        final a = (all: edits(old, c.answer), glyph: edits(noSpace(old), noSpace(c.answer)));
        final b = (all: edits(now.text, c.answer), glyph: edits(noSpace(now.text), noSpace(c.answer)));
        rows.add('${c.name.padRight(8)} 전 ${a.all}곳(글자 ${a.glyph}, 띄어쓰기·줄 ${a.all - a.glyph}) → 후 ${b.all}곳(글자 ${b.glyph}, 띄어쓰기·줄 ${b.all - b.glyph})');
        expect(b.all, lessThan(a.all));
        expect(now.page, c.page);
        expect(guessLineMode(c.r), c.mode, reason: '처음 고를 방식');
      });
    }
    test('산문: 머리글·쪽번호가 빠지고 낱말 가운데 줄 끝은 붙고 마지막 줄이 이어진다', () {
      final t = readOcr(all.firstWhere((c) => c.name == 'prose').r, LineMode.join).text;
      expect(t.startsWith('그날 밤'), isTrue);
      expect(t.contains('118'), isFalse);
      for (final w in ['무게가', '않겠다는', '올렸다', '문틈으로', '타고', '확인했을 뿐이다.', '그녀가 남긴', '켜 둘게']) {
        expect(t.contains(w), isTrue, reason: w);
      }
      expect('\n\n'.allMatches(t).length, 2, reason: '문단 셋');
    });
    test('시: 연 안은 줄바꿈 하나, 연 사이는 빈 줄, 들여 쓴 연은 앞에 공백', () {
      final t = readOcr(all.firstWhere((c) => c.name == 'poem').r, LineMode.keep).text;
      expect(t, '겨울 정류장\n\n눈이 오면\n나는 정류장에 선다.\n아무도 오지 않는 버스를 기다리며\n\n  손바닥에 내려앉는\n  하얀 것들의 이름을\n  하나씩 불러 본다\n\n불빛이 지나가고\n또지나가고\n\n나는 여전히\n여기, 서 있다');
    });
    test('영어: 하이픈 이음과 따로 잡힌 마지막 줄 잇기', () {
      final t = readOcr(all.firstWhere((c) => c.name == 'english').r, LineMode.join).text;
      expect(t.startsWith('When the Manager moved us to the front window,'), isTrue);
      expect(t.endsWith('as though the window were only a reflection of the street.'), isTrue);
      expect(t.contains('KLARA'), isFalse);
    });
    tearDownAll(() {
      // ignore: avoid_print
      if (rows.isNotEmpty) print('정답까지 고칠 곳(글자 단위 거리)\n${rows.join('\n')}');
    });
  });
}
