// 조사 고르기: 앞 낱말 끝소리에 받침이 있으면 '을 · 이 · 은 · 과 · 으로', 없으면 '를 · 가 · 는 · 와 · 로'.
// 화면 글에 이름(책 제목 · 파일 이름 · 열려는 곳 · 시간)을 넣을 때 쓴다(2026-11-20 '처리방침를 열 수 없어요', "'…예시.csv'을" 오류).
// 앱의 조사 고르기는 모두 이것(domain/reading.dart가 다시 내보낸다, ui/josa.dart도 같은 것)
// 끝 글자가 한글이면 받침, 숫자 · 라틴 글자는 읽는 소리(1 일 · 3 삼 · l 엘 · m 엠 · n 엔 · r 알)로 본다. 끝의 따옴표 · 괄호 · 마침표는 건너뛴다
library;

final _skip = RegExp(r'''[\s'"’”」』)\]}.,!?…·]''');

/// 끝소리 받침: null(판단할 글자 없음) · 0(없음) · 1(있음, ㄹ 아님) · 2(ㄹ)
int? _final(String word) {
  final cs = word.runes.toList();
  for (var i = cs.length - 1; i >= 0; i--) {
    final c = cs[i];
    final ch = String.fromCharCode(c);
    if (_skip.hasMatch(ch)) continue;
    if (c >= 0xAC00 && c <= 0xD7A3) {
      final jong = (c - 0xAC00) % 28;
      return jong == 0 ? 0 : (jong == 8 ? 2 : 1);
    }
    if (c >= 0x30 && c <= 0x39) return const {0: 1, 1: 2, 3: 1, 6: 1, 7: 2, 8: 2}[c - 0x30] ?? 0;
    final low = ch.toLowerCase();
    if (RegExp(r'[a-z]').hasMatch(low)) return low == 'l' || low == 'r' ? 2 : (low == 'm' || low == 'n' ? 1 : 0);
    return null;
  }
  return null;
}

/// 받침 있음 / 없음 조사 중 하나(판단할 수 없으면 없음 쪽). 예: josa('처리방침', '을', '를') → '을'
String josa(String word, String withFinal, String withoutFinal) => (_final(word) ?? 0) > 0 ? withFinal : withoutFinal;

/// 낱말 + 조사(예전 domain/reading.dart의 withJosa를 여기로 합침)
String withJosa(String word, String withFinal, String withoutFinal) => '$word${josa(word, withFinal, withoutFinal)}';

/// 낱말 + 을/를. 예: eulReul('처리방침') → '처리방침을', eulReul('페이지') → '페이지를'
String eulReul(String word) => '$word${josa(word, '을', '를')}';

/// 낱말 + 이/가
String iGa(String word) => '$word${josa(word, '이', '가')}';

/// 낱말 + 은/는
String eunNeun(String word) => '$word${josa(word, '은', '는')}';

/// 낱말 + 으로/로(ㄹ 받침은 '로': 서울로)
String euroRo(String word) => '$word${_final(word) == 1 ? '으로' : '로'}';
