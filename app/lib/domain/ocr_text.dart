// 문장 인식 결과(블록 = 문단 후보, 줄 = 인쇄된 한 줄) → 갈피 문장(지금 앱 domain/ocr-text.ts에서 시작). 인식한 글자만 쓰고 빈 곳을 지어내지 않는다.
// - 줄 끝 이어 쓰기(산문): 한 블록 안의 인쇄 줄바꿈을 잇는다. 영어 단어가 하이픈으로 줄을 넘었으면 하이픈을 빼고 붙인다.
//   한글끼리는 낱말 가운데서 끊긴 곳(앞 줄이 '했·겠'처럼 낱말 끝이 될 수 없는 글자로 끝나거나 다음 줄이 조사·어미로 시작)은 붙이고
//   나머지는 띄운다(2026-11-16 QA 은서 F5: 줄 끝마다 공백이 끼었다). 사용자가 '붙여 잇기·띄어 잇기'로 정할 수도 있다.
//   문장부호로 안 끝나고 끝 줄이 오른쪽 끝까지 찬 블록은 다음 블록과 잇는다(모델이 마지막 줄을 따로 잡았다).
// - 줄바꿈 그대로(시 등): 인쇄된 줄을 그대로 두고, 줄 사이가 크게 벌어진 곳만 빈 줄(연 구분)로 둔다. 들여 쓴 줄은 앞에 공백(F6).
// - 맨 위·맨 아래의 쪽번호와 작은 글씨 머리글은 뺀다. 쪽번호는 따로 돌려준다(쪽수 칸이 비면 채운다).
// 줄 상자가 없으면(좌표 0) 예전처럼 블록 사이를 빈 줄 하나로 둔다
library;

import 'dart:math' as math;

typedef OcrLine = ({String text, int left, int top, int right, int bottom, double confidence});
typedef OcrBlock = ({String text, List<OcrLine> lines});
typedef OcrResult = ({int width, int height, List<OcrBlock> blocks});

enum LineMode { join, keep }

/// 줄 끝에서 한글끼리 이을 때: 알아서(낱말 가운데 끊김만 붙임) · 늘 붙임 · 늘 띄움
enum WordJoin { auto, attach, space }

/// 인식 글과 사진에서 찾은 쪽번호
typedef OcrRead = ({String text, int? page});

final _hyphenEnd = RegExp(r'[A-Za-z]-$');
final _latinStart = RegExp(r'^[A-Za-z]');
final _spaces = RegExp(r'[ \t]{2,}');
// 쪽번호만 있는 줄: '118', '- 118 -', 'p. 118', '118쪽'
final _pageOnly = RegExp(r'^[-–—·\s]*(?:p\.?\s*)?(\d{1,4})\s*(?:쪽)?[-–—·\s]*$', caseSensitive: false);
// 머리글에 붙은 쪽번호: '118  작별의 밤', '작별의 밤  118'
final _headPage = RegExp(r'^(\d{1,4})\s+\S|\S\s+(\d{1,4})$');
// 문장이 끝난 블록(마침표·물음표·말줄임·닫는 따옴표·괄호)
final _ended = RegExp('[.!?。…:;」』”’"\'\\)\\]~]\$');
final _opens = RegExp('[(\\[「『“‘]\$');
final _closes = RegExp('^[.,!?…:;)\\]」』”’]');

// 다음 줄 첫 낱말이 이것이면 앞 줄 낱말의 끝(조사·어미)이다. 혼자 낱말로도 흔한 것('이·다·나·지·서·만·어서'…)은 넣지 않는다
const _tails = {
  '을', '를', '은', '는', '의', '에', '와', '과', '로', '고', '며', '면', '게', '도', '요', '랑', '께', '가', //
  '으로', '으로는', '으로도', '으로서', '으로써', '로는', '로도', '로서', '로써', '에서', '에서는', '에서도', '에게', '에게는', '에게도', '에는', '에도', //
  '와는', '과는', '와도', '과도', '까지', '부터', '처럼', '마다', '만큼', '밖에', '조차', '마저', '이나', '이든', '든지', '거나', //
  '라는', '다는', '라고', '다고', '다가', '면서', '지만', '는데', '은데', '니까', '도록', '려고', '으려고', '으며', '으면', '으니', '으나', //
  '이다', '이고', '이며', '이라', '이란', '이라는', '이라고', '이었다', '였다', '었다', '았다', '였고', '었고', '았고', '였던', '었던', '았던', //
  '는지', '은지', '을지', '라면', '다면', '냐고', '느냐', '습니다', '니다', '어요', '아요', '어도', '아도',
};
// 낱말 첫 글자가 될 수 없는 어미 글자(이+었 → 였 …)
const _tailHeads = {'었', '았', '였', '렸', '겠', '웠', '겼', '혔', '셨'};

bool _hangul(int c) => c >= 0xAC00 && c <= 0xD7A3;

/// 받침이 ㅆ인 글자(했·겠·었 …)는 낱말 끝이 될 수 없다
bool _ssEnd(int c) => _hangul(c) && (c - 0xAC00) % 28 == 20;

/// 한글 줄 끝 a와 다음 줄 b가 한 낱말 가운데서 끊겼는지(알아서 잇기)
bool midWord(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (_ssEnd(a.codeUnitAt(a.length - 1))) return true;
  final head = b.split(RegExp(r'\s')).first.replaceAll(RegExp(r'[.,!?…:;)\]」』”’"\x27-]+$'), '');
  if (_tails.contains(head)) return true;
  return head.isNotEmpty && _tailHeads.contains(head[0]);
}

/// 앞 줄 a 끝과 다음 줄 b 처음을 잇는다
String _joint(String a, String b, WordJoin words) {
  if (_hyphenEnd.hasMatch(a) && _latinStart.hasMatch(b)) return a.substring(0, a.length - 1) + b;
  if (_opens.hasMatch(a) || _closes.hasMatch(b)) return a + b;
  final x = a.codeUnitAt(a.length - 1), y = b.codeUnitAt(0);
  if (_hangul(x) && _hangul(y)) {
    final glue = switch (words) { WordJoin.attach => true, WordJoin.space => false, WordJoin.auto => midWord(a, b) };
    return glue ? a + b : '$a $b';
  }
  return '$a $b';
}

int _h(OcrLine l) => l.bottom - l.top;

double _quantile(List<num> xs, double q) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  return s[math.min(s.length - 1, (q * (s.length - 1)).round())].toDouble();
}

/// 정리한 쪽: 본문 블록(빈 줄 뺌), 쪽번호, 줄 상자 정보
class _Page {
  _Page(OcrResult r) {
    for (final b in r.blocks) {
      final lines = [
        for (final l in b.lines)
          if (l.text.trim().isNotEmpty) (text: l.text.trim(), left: l.left, top: l.top, right: l.right, bottom: l.bottom, confidence: l.confidence),
      ];
      if (lines.isNotEmpty) blocks.add(lines);
    }
    final all = [for (final b in blocks) ...b];
    geo = all.isNotEmpty && all.every((l) => l.bottom > l.top && l.right > l.left);
    if (!geo) {
      _dropPageOnly();
      return;
    }
    lineH = _quantile([for (final l in all) _h(l)], 0.5);
    // 바로 선 사진인지(기운 사진은 상자 높이가 제각각이라 줄 사이·들여쓰기를 믿지 않는다)
    upright = all.where((l) => (_h(l) - lineH).abs() <= 0.35 * lineH).length >= 0.7 * all.length;
    // 위에서 아래 차례(모델이 대개 그렇게 주지만 보장하지 않는다). 기운 사진은 상자 위치를 믿지 않고 모델 차례대로
    if (upright) blocks.sort((a, b) => a.first.top.compareTo(b.first.top));
    final flat = [for (final b in blocks) ...b];
    gap = _quantile([for (var i = 1; i < flat.length; i++) flat[i].top - flat[i - 1].bottom], 0.3);
    _dropMargins();
    final body = [for (final b in blocks) ...b];
    if (body.isNotEmpty) {
      colLeft = body.map((l) => l.left).reduce(math.min);
      colRight = body.map((l) => l.right).reduce(math.max);
    }
  }

  final blocks = <List<OcrLine>>[];
  bool geo = false, upright = false;
  double lineH = 0, gap = 0;
  int colLeft = 0, colRight = 0;
  int? page;

  int? _pageNo(String t) {
    final m = _pageOnly.firstMatch(t);
    return m == null ? null : int.parse(m[1]!);
  }

  // 좌표가 없으면 맨 앞·맨 뒤의 쪽번호만 뺀다(본문이 남을 때만)
  void _dropPageOnly() {
    for (final last in [true, false]) {
      if (blocks.length < 2) return;
      final b = last ? blocks.last : blocks.first;
      final no = b.length == 1 ? _pageNo(b.single.text) : null;
      if (no == null) continue;
      page ??= no;
      last ? blocks.removeLast() : blocks.removeAt(0);
    }
  }

  // 맨 위·맨 아래(각 두 블록까지): 쪽번호만 있는 한 줄, 또는 본문보다 작은 글씨의 짧은 한 줄이 본문과 떨어져 있으면 머리글
  void _dropMargins() {
    for (final last in [true, false]) {
      for (var k = 0; k < 2 && blocks.length > 1; k++) {
        final b = last ? blocks.last : blocks.first;
        if (b.length != 1) break;
        final l = b.single;
        final next = last ? blocks[blocks.length - 2].last : blocks[1].first;
        final apart = (last ? l.top - next.bottom : next.top - l.bottom) > math.max(gap * 1.5, 0.5 * lineH);
        final no = _pageNo(l.text);
        if (no != null && _h(l) <= 1.3 * lineH) {
          page ??= no;
        } else if (upright && _h(l) < 0.8 * lineH && l.text.replaceAll(' ', '').length <= 24 && apart) {
          final m = _headPage.firstMatch(l.text);
          if (m != null) page ??= int.parse(m[1] ?? m[2]!);
        } else {
          break;
        }
        last ? blocks.removeLast() : blocks.removeAt(0);
      }
    }
  }

  /// 블록 끝 줄이 오른쪽 끝까지 찼고 다음 블록 첫 줄이 들여 쓰지 않고 바로 붙어 있으면 한 문단이 갈린 것
  bool continues(List<OcrLine> a, List<OcrLine> b) {
    if (!geo || !upright || _ended.hasMatch(a.last.text)) return false;
    final full = a.last.right >= colRight - 1.5 * lineH;
    final flush = b.first.left <= colLeft + 0.5 * lineH;
    final near = b.first.top - a.last.bottom <= math.max(gap * 1.5, 0.5 * lineH);
    return full && flush && near;
  }
}

/// 인식 결과 → 갈피 문장과 쪽번호
OcrRead readOcr(OcrResult r, LineMode mode, {WordJoin words = WordJoin.auto}) {
  final p = _Page(r);
  if (mode == LineMode.keep) return (text: _keep(p).trim(), page: p.page);
  final paras = <String>[];
  List<OcrLine>? prev;
  for (final b in p.blocks) {
    var out = b.first.text;
    for (final next in b.skip(1)) {
      out = _joint(out, next.text, words);
    }
    out = out.replaceAll(_spaces, ' ');
    if (prev != null && p.continues(prev, b)) {
      paras[paras.length - 1] = _joint(paras.last, out, words);
    } else {
      paras.add(out);
    }
    prev = b;
  }
  return (text: paras.join('\n\n').trim(), page: p.page);
}

String _keep(_Page p) {
  if (!p.geo || !p.upright) return [for (final b in p.blocks) b.map((l) => l.text).join('\n')].join('\n\n');
  final lines = [for (final b in p.blocks) ...b];
  // 본문 크기 줄의 왼쪽 끝을 기준으로 들여쓰기를 센다(한 글자 들여쓰기는 문단 첫 줄이라 두지 않는다)
  final sameSize = lines.where((l) => (_h(l) - p.lineH).abs() <= 0.3 * p.lineH);
  final left = sameSize.isEmpty ? p.colLeft : sameSize.map((l) => l.left).reduce(math.min);
  final stanza = math.max(p.gap * 1.8, p.gap + 0.5 * p.lineH);
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (i > 0) out.write(l.top - lines[i - 1].bottom > stanza ? '\n\n' : '\n');
    final indent = l.left - left;
    if (indent >= 1.25 * p.lineH && (_h(l) - p.lineH).abs() <= 0.3 * p.lineH) out.write(' ' * (1.5 * indent / p.lineH).round().clamp(2, 8));
    out.write(l.text);
  }
  return out.toString();
}

String ocrText(OcrResult r, LineMode mode, {WordJoin words = WordJoin.auto}) => readOcr(r, mode, words: words).text;

/// 처음 고를 방식: 줄 대부분이 오른쪽 끝에 못 미치면 시(줄바꿈 그대로), 아니면 산문
LineMode guessLineMode(OcrResult r) {
  final p = _Page(r);
  final lines = [for (final b in p.blocks) ...b];
  if (!p.geo || !p.upright || lines.length < 3) return LineMode.join;
  final w = p.colRight - p.colLeft;
  final short = lines.where((l) => l.right < p.colRight - 0.2 * w).length;
  return short >= 0.6 * lines.length ? LineMode.keep : LineMode.join;
}

/// 인식 신뢰도가 낮은 줄 수(모델이 신뢰도를 주지 않으면 0으로 와서 세지 않는다)
int lowConfidenceLines(OcrResult r, [double below = 0.5]) {
  var n = 0;
  for (final b in r.blocks) {
    for (final l in b.lines) {
      if (l.confidence > 0 && l.confidence < below) n++;
    }
  }
  return n;
}
