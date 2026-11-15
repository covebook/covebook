// 책 제목 조판: 세운 책등(세로로 글자를 바로 세워 쌓기), 눕힌 책등(가로 한 줄), 앞표지(고른 줄 나눔).
// 지금 앱 domain/title-layout.ts를 그대로 옮긴 것(값이 같은지는 test/title_layout_test.dart가 지금 앱 결과와 견준다).
library;

import 'dart:math' as math;

/// 세로 조판: 글자 크기, 열들, 글자 간격(글자 크기 배수)
class VerticalTitle {
  const VerticalTitle(this.fontSize, this.columns, this.pitch, {this.textTop = 0, this.artTop = 0});
  final double fontSize;
  final List<String> columns;
  final double pitch;

  /// 첫 글자 위 끝(책 높이 비율), 그림 칸 위 끝(책 높이 비율). layoutVerticalTitle만 부른 값은 0
  final double textTop;
  final double artTop;

  VerticalTitle at(double textTop, double artTop) => VerticalTitle(fontSize, columns, pitch, textTop: textTop, artTop: artTop);
}

/// 세로 조판의 띄어쓰기(글자 크기 배수). 시안 책등: 단어 사이가 글자 크기의 약 0.4배 더 벌어진다
const spineSpace = 0.4;

/// 세로 글자 간격(글자 크기 배수)
const linePitch = 1.24;

double _units(String s) => s.runes.fold(0.0, (n, ch) => n + (ch == 0x20 ? spineSpace : 1));

List<String>? _pack(List<String> words, int cap) {
  final cols = <String>[];
  var cur = '';
  for (final w in words) {
    final next = cur.isNotEmpty ? '$cur $w' : w;
    if (_units(next) <= cap) {
      cur = next;
      continue;
    }
    if (cur.isNotEmpty) cols.add(cur);
    if (_units(w) > cap) return null;
    cur = w;
  }
  if (cur.isNotEmpty) cols.add(cur);
  return cols;
}

/// 문자열을 글자(코드 포인트)로
List<String> _chars(String s) => [for (final r in s.runes) String.fromCharCode(r)];

/// height: 글자 영역 높이, width: 책등 폭. fontSizes는 큰 것부터 시도(최소값 아래로 줄이지 않음)
VerticalTitle layoutVerticalTitle(String title, double height, double width, List<double> fontSizes,
    [int maxColumns = 2, double pitch = linePitch]) {
  final words = title.trim().split(RegExp(r'\s+'));
  for (final fontSize in fontSizes) {
    final cap = (height / (fontSize * pitch)).floor();
    final maxCols = math.max(1, (width * 0.84 / (fontSize * 1.18)).floor());
    if (_units(title) <= cap) return VerticalTitle(fontSize, [title], pitch);
    if (maxCols >= 2 && maxColumns >= 2) {
      final cols = _pack(words, cap);
      if (cols != null && cols.length <= math.min(2, maxCols)) return VerticalTitle(fontSize, cols, pitch);
    }
  }
  // 넘치면 최소 글자 크기에서 말줄임
  final fontSize = fontSizes.last;
  final cap = math.max(1, (height / (fontSize * pitch)).floor());
  var out = '';
  for (final ch in _chars(title.replaceAll(RegExp(r'\s+'), ' '))) {
    if (_units(out + ch) > cap - 1) break;
    out += ch;
  }
  return VerticalTitle(fontSize, ['${out.trimRight()}⋯'], pitch);
}

/// JS Math.round(소수 반올림, .5는 위로)
double _round(double v) => (v + 0.5).floorToDouble();

/// 세운 책 제목 자리(장정 규칙). 글자 크기는 책등 폭의 0.42(8.5~11DU), 간격은 짧은 제목이 더 넉넉하고,
/// 그림 자리(artTop0 ~ artBottom)를 먼저 지킨다: 크기 → 간격 → 시작 위치로 맞추고, 그래도 안 되면 그림을 민다
VerticalTitle spineTitleLayout(String title, double hDU, double faceDU, double artTop0, [double artBottom = 0.93]) {
  const minSize = 8.5;
  final base = math.max(minSize, math.min(11.0, _round(faceDU * 0.42 * 2) / 2));
  final all = <double>[];
  for (var v = base; v >= minSize - 1e-9; v -= 0.5) {
    all.add(_round(v * 10) / 10);
  }
  final short = _units(title) <= 3;
  final pitches = short ? const [1.22, 1.16, 1.1, 1.04] : const [1.16, 1.1, 1.05, 1.0];
  const tops = [0.255, 0.23, 0.20];
  VerticalTitle? tryIt(List<double> sizes, double maxArt) {
    final hi = math.max(artTop0, maxArt);
    for (var top = artTop0; top <= hi + 1e-9; top += 0.02) {
      for (final size in sizes) {
        for (final pitch in pitches) {
          for (final tt in tops) {
            final r = layoutVerticalTitle(title, (top - tt) * hDU - 4, faceDU, [size], 1, pitch);
            if (!r.columns.any((c) => c.endsWith('⋯'))) return r.at(tt, _round(top * 100) / 100);
          }
        }
      }
    }
    return null;
  }

  // ① 거의 제 크기로 그림 칸 0.3을 지키며 ② 최소 크기까지 ③ 그림 칸 0.2까지 ④ 그림을 0.85까지 밀어 한 열 ⑤ 두 열
  final r = tryIt(all.sublist(0, math.min(2, all.length)), artBottom - 0.3) ??
      tryIt(all, artBottom - 0.3) ??
      tryIt(all, math.min(0.85, artBottom - 0.2)) ??
      tryIt(all, 0.85);
  if (r != null) return r;
  for (final size in all) {
    final two = layoutVerticalTitle(title, (math.min(0.85, artBottom - 0.2) - 0.12) * hDU - 4, faceDU, [size], 2, 1.05);
    if (!two.columns.any((c) => c.endsWith('⋯'))) return two.at(0.12, math.min(0.85, artBottom - 0.2));
  }
  return layoutVerticalTitle(title, (0.85 - 0.08) * hDU - 4, faceDU, [minSize], 2, 1.0).at(0.08, 0.85);
}

// ---------- 로마자 제목 책등(돌린 글줄) ----------
/// 한글·한자·가나 없이 로마자가 든 제목: 영어 책등처럼 글줄을 돌려 쓴다(한 자씩 세워 쌓으면 'Normal'이 오른쪽 줄부터 읽혔다, 2026-11-15 QA)
bool isLatinTitle(String title) {
  var latin = false;
  for (final c in title.runes) {
    if (c >= 0x1100 && c <= 0x11FF || c >= 0x3040 && c <= 0x30FF || c >= 0x3130 && c <= 0x318F || c >= 0x3400 && c <= 0x9FFF || c >= 0xAC00 && c <= 0xD7A3) return false;
    if (c >= 0x41 && c <= 0x5A || c >= 0x61 && c <= 0x7A || c >= 0xC0 && c <= 0x24F) latin = true;
  }
  return latin;
}

/// 돌린 글줄 조판: 글자 크기, 줄(두께 방향으로 첫 줄이 앞표지 쪽), 첫 글자 머리 쪽 끝(책 높이 비율)
class RotatedTitle {
  const RotatedTitle(this.fontSize, this.lines, this.start);
  final double fontSize;
  final List<String> lines;
  final double start;
}

/// 돌린 글줄의 줄 간격(글자 크기 배수)
const rotatedLineH = 1.1;

/// 세운 책등의 로마자 제목: 글줄을 시계 방향으로 돌려 머리 → 꼬리로 읽게(눕힌 책등과 같은 방향) 쓴다.
/// 글자 크기는 세로 조판과 같은 규칙(책등 폭의 0.42, 8.5~11DU)에서 시작한다. 한 줄로 조금 줄여 넣고 → 두께가 되면 두 줄 → 7.5DU까지 한 줄 → 말줄임.
/// start: 정한 시작 자리(장정 판짜기), 없으면 0.2부터 0.1까지 올려 본다. end: 글줄 끝 한계. widthOf: 글줄 길이(DU, 글자 크기 fs)
RotatedTitle rotatedSpineTitleLayout(String title, double hDU, double faceDU, double? start, double end, double Function(String s, double fs) widthOf) {
  final text = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  final words = text.split(' ');
  final base = math.max(8.5, math.min(11.0, _round(faceDU * 0.42 * 2) / 2));
  final sizes = [for (var v = base; v >= 7.5 - 1e-9; v -= 0.5) _round(v * 10) / 10];
  final starts = start != null ? [start] : const [0.2, 0.15, 0.1];
  RotatedTitle? one(Iterable<double> fss) {
    for (final fs in fss) {
      for (final s0 in starts) {
        if (widthOf(text, fs) <= (end - s0) * hDU) return RotatedTitle(fs, [text], s0);
      }
    }
    return null;
  }

  RotatedTitle? two() {
    if (words.length < 2) return null;
    for (final fs in sizes) {
      if (2 * fs * rotatedLineH > faceDU * 0.86) continue;
      List<String>? best;
      var bestW = double.infinity;
      for (var i = 1; i < words.length; i++) {
        final a = words.sublist(0, i).join(' '), b = words.sublist(i).join(' ');
        final w = math.max(widthOf(a, fs), widthOf(b, fs));
        if (w < bestW) {
          bestW = w;
          best = [a, b];
        }
      }
      for (final s0 in starts) {
        if (best != null && bestW <= (end - s0) * hDU) return RotatedTitle(fs, best, s0);
      }
    }
    return null;
  }

  final r = one(sizes.take(3)) ?? two() ?? one(sizes.skip(3));
  if (r != null) return r;
  // 넘치면 최소 크기 한 줄에서 말줄임
  final fs = sizes.last;
  final s0 = starts.last;
  var out = '';
  for (final ch in _chars(text)) {
    if (widthOf('$out$ch…', fs) > (end - s0) * hDU) break;
    out += ch;
  }
  return RotatedTitle(fs, ['${out.trimRight()}…'], s0);
}

// ---------- 눕힌 책등(가로 한 줄) ----------
const lyingStart = 0.14;
const _lyingEnd = 0.08;
const lyingTrack = 0.02;
double _lineUnits(String s) => s.runes.fold(0.0, (n, ch) => n + (ch == 0x20 ? 0.32 : 1)) * (1 + lyingTrack);

class LyingTitle {
  const LyingTitle(this.fontSize, this.text, this.start);
  final double fontSize;
  final String text;
  final double start;
}

/// 눕힌 책등 제목: 머리 쪽 끝에서 길이의 14%부터 한 줄, 글자는 두께의 0.38(11DU까지). 넘치면 7.5DU까지 줄이고 그래도 넘치면 말줄임
LyingTitle lyingTitleLayout(String title, double hDU, double tDU, [double endReserve = _lyingEnd]) {
  final text0 = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  final room = hDU * (1 - lyingStart - endReserve);
  final target = math.max(7.5, math.min(11.0, tDU * 0.38));
  final fit = room / math.max(1.0, _lineUnits(text0));
  if (fit >= target) return LyingTitle(_round(target * 10) / 10, text0, lyingStart);
  if (fit >= 7.5) return LyingTitle((fit * 10).floorToDouble() / 10, text0, lyingStart);
  final cap = room / 7.5;
  var out = '';
  for (final ch in _chars(text0)) {
    if (_lineUnits('$out$ch⋯') > cap) break;
    out += ch;
  }
  return LyingTitle(7.5, '${out.trimRight()}⋯', lyingStart);
}

// ---------- 앞표지 ----------
const coverLineH = 1.46;
const coverTrack = 0.0;
const coverSpace = 0.45;
const _coverAdv = 0.91;

class CoverTitle {
  const CoverTitle(this.lines, this.fontSize);
  final List<String> lines;
  final double fontSize;
}

/// 앞표지 제목: 줄 수마다 한 줄이 차지할 폭(한 줄 0.56W, 여러 줄 0.72W)과 크기 상한으로 크기를 정하고,
/// 줄을 늘려 글자가 15% 넘게 커질 때만 줄을 늘린다(단어는 깨지 않고 고르게). 제목 칸 높이는 표지 높이의 30% 안
CoverTitle coverTitleLayout(String title, double wDU, double hDU) {
  final words = title.trim().split(RegExp(r'\s+'));
  double width(String line) => line.runes.fold(0.0, (n, ch) => n + (ch == 0x20 ? coverSpace : _coverAdv + coverTrack));
  double sizeFor(int n, double w) => [
        (n == 1 ? 0.135 : 0.1) * wDU,
        16.0,
        (n == 1 ? 0.56 : 0.72) * wDU / w,
        0.3 * hDU / (n * coverLineH),
      ].reduce(math.min);
  List<List<String>> splits(int n) {
    if (n == 1) return [[words.join(' ')]];
    final out = <List<String>>[];
    void rec(int start, int left, List<String> acc) {
      if (left == 1) {
        if (start < words.length) out.add([...acc, words.sublist(start).join(' ')]);
        return;
      }
      for (var i = start + 1; i <= words.length - left + 1; i++) {
        rec(i, left - 1, [...acc, words.sublist(start, i).join(' ')]);
      }
    }

    rec(0, n, []);
    return out;
  }

  CoverTitle? pick;
  for (var n = 1; n <= math.min(3, words.length); n++) {
    List<String>? best;
    var bestW = double.infinity;
    for (final lines in splits(n)) {
      final w = lines.map(width).reduce(math.max);
      if (w < bestW) {
        bestW = w;
        best = lines;
      }
    }
    if (best == null) continue;
    final fs = sizeFor(n, bestW);
    if (pick == null || fs > pick.fontSize * 1.15) pick = CoverTitle(best, fs);
  }
  final f = pick ?? CoverTitle([title], 7.5);
  final desired = math.max(7.5, _round(f.fontSize * 10) / 10);
  // 아주 긴 제목도 표지 안에 들어가야 한다(읽기 하한보다 인쇄 칸이 먼저)
  final fit = math.min(wDU * 0.86 / math.max(1.0, f.lines.map(width).reduce(math.max)), hDU * 0.3 / (f.lines.length * coverLineH));
  return CoverTitle(f.lines, desired <= fit ? desired : (fit * 10).floorToDouble() / 10);
}

/// 제목 비교(지금 앱 localeCompare(…, 'ko')와 같은 순서): 숫자·기호 → 한글 → 로마자(대소문자 무시, 같으면 소문자 먼저).
/// Dart 기본 비교는 글자 코드 순이라 로마자가 한글보다 먼저 와 '제목순'이 지금 앱과 달랐다
int compareKoTitle(String a, String b) {
  int group(int c) {
    if (c >= 0xAC00 && c <= 0xD7A3 || c >= 0x3131 && c <= 0x318E) return 1;
    if (c >= 0x41 && c <= 0x5A || c >= 0x61 && c <= 0x7A) return 2;
    return 0;
  }

  final ra = a.runes.toList(), rb = b.runes.toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i], y = rb[i];
    if (x == y) continue;
    final gx = group(x), gy = group(y);
    if (gx != gy) return gx - gy;
    if (gx == 2) {
      final lx = x | 0x20, ly = y | 0x20;
      if (lx != ly) return lx - ly;
      continue; // 대소문자만 다르면 뒤에서 가린다
    }
    return x - y;
  }
  if (ra.length != rb.length) return ra.length - rb.length;
  // 대소문자만 다른 제목: 소문자 먼저
  for (var i = 0; i < ra.length; i++) {
    if (ra[i] != rb[i]) return rb[i] - ra[i];
  }
  return 0;
}
