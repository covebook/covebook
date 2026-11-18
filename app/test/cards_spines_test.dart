// 2026-11-15 페르소나 QA 갈래 D: 공유 카드 9:16, 로마자 책등 조판, 기록 탭 권수
import 'package:chaekjang/domain/library.dart';
import 'package:chaekjang/domain/title_layout.dart';
import 'package:chaekjang/features/share/share_scene.dart';
import 'package:chaekjang/features/stats/chart_data.dart' show bookCounts;
import 'package:flutter_test/flutter_test.dart';

ShareSceneInput _input({String? note, num? rating, List<String> extra = const []}) =>
    ShareSceneInput(title: '소년이 온다', author: '한강', note: note, rating: rating, extra: extra, coverAspect: 0.68, thicknessRatio: 0.08);

void main() {
  test('공유 카드는 한 줄 감상이 길어도 늘 9:16(폭 1080이면 1920), 글자는 ‘책장 한켠’ 위에서 끝난다', () {
    expect((cardH * 1080 / sceneW).round(), 1920);
    for (final note in [null, '짧은 감상', 'The boy is coming toward the light, and I could not stop reading until dawn. ' * 6]) {
      final l = layoutShareScene(_input(note: note, rating: 4.5, extra: const ['3시간 20분', '2026.10.12 — 11.05']));
      expect(l.height, cardH, reason: '$note');
      expect(l.y.foot, 1551, reason: '$note');
      final end = l.y.stars + 43;
      expect(end + 60, lessThanOrEqualTo(l.y.foot + 1e-6), reason: '$note');
      if (l.note != null) expect(l.y.note + l.note!.height, lessThanOrEqualTo(l.y.stars), reason: '$note');
    }
    expect(shareCardAspect(_input(note: 'x' * 400)), closeTo(16 / 9, 1e-9));
  });

  test('로마자 제목만 돌린 글줄(한글·한자·가나가 섞이면 세로 조판)', () {
    expect(isLatinTitle('Normal People'), isTrue);
    expect(isLatinTitle('The Odyssey: (Penguin)'), isTrue);
    expect(isLatinTitle('82년생 김지영'), isFalse);
    expect(isLatinTitle('Human Acts 한강'), isFalse);
    expect(isLatinTitle('1984'), isFalse);
  });

  test('돌린 글줄: 들어가면 한 줄, 두께가 되면 두 줄, 그래도 넘치면 말줄임', () {
    // 글자 폭을 글자 수 × 0.55 × 크기로 본다
    double w(String s, double fs) => s.length * 0.55 * fs;
    final short = rotatedSpineTitleLayout('Normal People', 220, 30, null, 0.92, w);
    expect(short.lines, ['Normal People']);
    expect(short.fontSize, 11);
    expect(short.start, 0.2);
    // 긴 제목, 두꺼운 책: 두 줄로 고르게
    final long = rotatedSpineTitleLayout('Haruki Murakami Goes to Meet Hayao Kawai', 200, 40, null, 0.92, w);
    expect(long.lines.length, 2);
    expect(long.lines.join(' '), 'Haruki Murakami Goes to Meet Hayao Kawai');
    for (final l in long.lines) {
      expect(w(l, long.fontSize), lessThanOrEqualTo((0.92 - long.start) * 200 + 1e-6));
    }
    // 아주 얇은 책: 한 줄 말줄임
    final thin = rotatedSpineTitleLayout('Haruki Murakami Goes to Meet Hayao Kawai', 120, 14, null, 0.92, w);
    expect(thin.lines.length, 1);
    expect(thin.lines.first.endsWith('…'), isTrue);
    expect(thin.fontSize, 7.5);
    // 장정 판짜기로 시작 자리를 정하면 그 자리에서
    expect(rotatedSpineTitleLayout('Intermezzo', 220, 30, 0.13, 0.85, w).start, 0.13);
  });

  test('기록 탭 권수: 기간에 넣은 책, 지금 서재(숨긴 책은 따로)', () {
    MyBook b(String id, String at, [String? hidden]) => MyBook(id: id, editionId: 'e', status: ReadStatus.want, createdAt: at, updatedAt: at, hiddenAt: hidden);
    final lib = Library(books: {
      'a': b('a', '2026-11-03T10:00:00'),
      'b': b('b', '2026-11-20T10:00:00'),
      'c': b('c', '2026-10-30T10:00:00'),
      'd': b('d', '2026-11-05T10:00:00', '2026-11-06T10:00:00'),
    });
    final c = bookCounts(lib, monthPeriod(2026, 11));
    expect(c.added, 3);
    expect(c.shelf, 3);
    expect(c.hidden, 1);
  });
}
