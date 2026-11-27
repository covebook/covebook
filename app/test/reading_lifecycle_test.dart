import 'package:chaekjang/domain/reading.dart';
import 'package:flutter_test/flutter_test.dart';

Active _running({num acc = 0, num since = 1000, num beat = 1000}) =>
    Active(id: 'ss_1', startedAt: isoOf(0), accumulatedMs: acc, runningSince: since, lastBeat: beat);

void main() {
  group('앱이 꺼졌다 켜졌을 때(복구)', () {
    // 0초에 시작해 600초(10분)까지 확인됨, 900초에 다시 엶 → 꺼진 5분
    final saved = Active(id: 'ss_1', startedAt: isoOf(0), accumulatedMs: 0, runningSince: 0, lastBeat: 600000);
    final r = recoverOnLoad(saved, 900000);
    final it = r.interrupted!;

    test('다시 연 시각 = 마지막 확인 + 꺼진 시간', () {
      expect(it.countedMs, 600000);
      expect(it.gapMs, 300000);
      expect(it.reopenAt, 900000);
    });

    test('넣기: 꺼진 시간과 안내창이 떠 있던 시간이 모두 들어간다', () {
      // 안내창이 30초 떠 있다가 930초에 고름
      final a = resumeInterruptedActive(it, includeGap: true, now: 930000);
      expect(elapsedMs(a, 930000), 930000);
      expect(a.interruptedAt, isNull);
    });

    test('빼기: 꺼진 시간만 빠지고 안내창이 떠 있던 시간은 들어간다', () {
      final a = resumeInterruptedActive(it, includeGap: false, now: 930000);
      expect(elapsedMs(a, 930000), 600000 + 30000);
    });

    test('1분 미만 꺼짐은 묻지 않는다', () {
      expect(askGapMs, 60000);
    });
  });

  test('저장하는 시간은 초 단위로 내린다(읽기 탭 시계와 기록 화면이 같은 초)', () {
    final p = finishActive(_running(since: 0), 924600);
    expect(p.durationMs, 924600);
    expect(wholeSeconds(p).durationMs, 924000);
    expect(hms(924600), '0:15:24');
  });

  test('받침에 맞는 조사', () {
    expect(withJosa('3분 32초', '이', '가'), '3분 32초가');
    expect(withJosa('15분', '이', '가'), '15분이');
    expect(withJosa('1분 미만', '을', '를'), '1분 미만을');
    expect(withJosa('채식주의자', '을', '를'), '채식주의자를');
    expect(withJosa('데미안', '을', '를'), '데미안을');
    expect(withJosa('Normal People', '을', '를'), 'Normal People를');
    expect(withJosa('3', '은', '는'), '3은');
    expect(withJosa('2', '은', '는'), '2는');
  });
}
