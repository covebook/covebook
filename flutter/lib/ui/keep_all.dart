// 낱말 단위 줄바꿈(CSS word-break: keep-all처럼). 한글은 글자마다 끊겨 '다/시'처럼 낱말이 갈린다.
// 낱말 안 글자 사이에 단어 이음표(U+2060, 폭 없음)를 넣어 띄어쓰기에서만 끊게 한다(지금 앱 ui/keep-all.ts).
// 라틴 글자·숫자끼리는 원래 안 끊기므로 넣지 않는다
library;

final _space = RegExp(r'(\s+)');

String keepAll(String t) {
  final out = StringBuffer();
  var at = 0;
  for (final m in _space.allMatches(t)) {
    out.write(_join(t.substring(at, m.start)));
    out.write(m.group(0));
    at = m.end;
  }
  out.write(_join(t.substring(at)));
  return out.toString();
}

/// 원래 낱말 안에서 끊기지 않는 글자(라틴 글자·숫자·아포스트로피): 둘이 이웃하면 이음표가 필요 없다.
/// 넣으면 갈피 문장처럼 이음표에 자간을 따로 주는 곳(WordWrap)에서 글자가 조각마다 나뉘어, 줄 끝 글자(about의 t)가 잘렸다(2026-11-16)
final _inWord = RegExp(r"[A-Za-z0-9\u00C0-\u024F'\u2019]");

/// 앞에서 줄이 바뀌지 않는 닫는 문장부호, 뒤에서 줄이 바뀌지 않는 여는 문장부호(유니코드 줄바꿈 규칙): 그 자리에도 이음표가 필요 없다.
/// 넣으면 'little.'의 마침표가 조각으로 나뉘어 줄 끝에서 통째로 잘렸다(2026-11-16 QA 은서 F4)
final _closing = RegExp(r'[.,!?;:)\]}’”」』…%]');
final _opening = RegExp(r'[(\[{‘“「『]');

String _join(String w) {
  final cs = w.runes.map(String.fromCharCode).toList();
  final out = StringBuffer();
  for (var i = 0; i < cs.length; i++) {
    if (i > 0 && !(_inWord.hasMatch(cs[i - 1]) && _inWord.hasMatch(cs[i])) && !_closing.hasMatch(cs[i]) && !_opening.hasMatch(cs[i - 1])) {
      out.write('\u2060');
    }
    out.write(cs[i]);
  }
  return out.toString();
}
