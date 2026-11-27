// 목록 가져오기(2026-11-20 QA): 응답이 멈춘 검색이 있어도 '그만 찾기'가 바로 끝나고, 요청 하나는 본문까지 한도 안에서 끝난다.
// 예시 파일 저장 안내는 실제로 저장된 이름과 맞는 조사(‘책장한켠 예시 (4).csv’를)
import 'dart:async';
import 'dart:io';

import 'package:chaekjang/features/book/import_list_screen.dart';
import 'package:chaekjang/services/book_search.dart' show getJsonWith;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('줄 찾기 멈추기', () {
    test('끝나지 않는 검색이 있어도 멈추면 바로 끝나고, 늦게 온 결과는 버린다', () async {
      final hang = Completer<String>();
      final done = <String>[];
      final job = LineSearch<String, String>(['a', 'b', 'c', 'd', 'e'], (q) => q == 'b' ? hang.future : Future.value(q), (q, r) => done.add(r), parallel: 2);
      final run = job.run();
      // a는 바로 끝나고, b는 멈춰 있다. 다른 일꾼이 c · d · e를 찾는다
      await pumpEventQueue();
      expect(done, ['a', 'c', 'd', 'e']);
      var finished = false;
      unawaited(run.then((_) => finished = true));
      await pumpEventQueue();
      expect(finished, isFalse, reason: '멈춘 검색을 기다리는 중');
      job.stop();
      await run.timeout(const Duration(seconds: 1));
      hang.complete('b');
      await pumpEventQueue();
      expect(done, ['a', 'c', 'd', 'e'], reason: '멈춘 뒤 온 결과는 넣지 않는다');
    });

    test('멈추면 남은 줄은 찾지 않는다', () async {
      final asked = <String>[];
      late final LineSearch<String, String> job;
      job = LineSearch<String, String>(['a', 'b', 'c'], (q) async {
        asked.add(q);
        if (q == 'a') job.stop();
        return q;
      }, (_, _) {}, parallel: 1);
      await job.run();
      expect(asked, ['a']);
    });

    test('한 번에 parallel줄까지만 찾는다', () async {
      var now = 0, most = 0;
      final job = LineSearch<int, int>(List.generate(9, (i) => i), (i) async {
        most = now + 1 > most ? now + 1 : most;
        now++;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        now--;
        return i;
      }, (_, _) {}, parallel: 3);
      await job.run();
      expect(most, 3);
    });
  });

  test('요청 하나는 본문을 다 받기까지 한도가 있다(머리만 보내고 멈춘 응답)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..contentLength = 1000
        ..write('{"items": [');
      await req.response.flush();
      // 본문 나머지는 보내지 않는다
    });
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final sw = Stopwatch()..start();
    await expectLater(getJsonWith(http, 'http://127.0.0.1:${server.port}/books/search?q=x', timeout: const Duration(milliseconds: 300)), throwsA(isA<TimeoutException>()));
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  });

  group('예시 파일 저장 안내', () {
    const name = '책장한켠 예시.csv';
    test('기기가 바꿔 저장한 이름을 쓰고 조사는 그 이름 끝소리로', () {
      expect(sampleSavedText('책장한켠 예시 (4).csv', name), '다운로드 › 책장한켠 폴더의 ‘책장한켠 예시 (4).csv’를 엑셀에서 열어 내 책으로 고친 뒤 여기서 골라 주세요.');
    });
    test('이름을 돌려주지 않으면(주소 · 빈 값) 고른 이름', () {
      expect(sampleSavedText(null, name), contains('‘책장한켠 예시.csv’를 '));
      expect(sampleSavedText('content://media/external_primary/downloads/42', name), contains('‘책장한켠 예시.csv’를 '));
      expect(sampleSavedText('', name), contains('‘책장한켠 예시.csv’를 '));
    });
  });
}
