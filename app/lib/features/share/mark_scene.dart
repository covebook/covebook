// 갈피 공유 그림 두 가지(지금 앱 features/bookmark/bookmark-scene.ts, 2026-11-10 사용자 시안 '두 버전으로 선택, 99% 동일하게'):
//  page: 펼친 책 한 쪽(왼쪽 제본 그늘·왼쪽 위 창빛, 종이에 찍힌 문장, 아래 '책장 한켠'과 쪽수)
//  note: 벽에 테이프로 붙인 찢은 종이(문장 왼쪽 정렬, 아래 책 제목·저자·쪽수, 벽 아래 '책장 한켠')
// 시안에서 글자를 지운 바탕(assets/share/bookmark-*.png) 위에 같은 자리·글꼴·색으로 글자만 얹는다. 좌표는 시안 화소(941×1672)
// 긴 글(2026-11-16 QA 은서 F3: 600자 넘는 글이 카드 밖으로 넘치고 제목·'책장 한켠'과 겹쳤다): 글 자리 높이 안에 들 때까지 글자를 줄이고
// (읽을 수 있는 크기까지), 그래도 넘치면 들어가는 줄까지만 두고 끝에 '…'(cut). 공유 시트는 cut이면 앞부분만 들어간다고 알린다.
// 책 제목·지은이는 한두 줄에서 말줄임해 쪽수·바닥 글과 겹치지 않는다
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../ui/keep_all.dart';
import 'share_scene.dart' show assetImage, blurRadiusOfSigma;

const markW = 941.0;
const markH = 1672.0;

enum MarkStyle { page, note }

const _fonts = (quote: 'MaruBuriRegular', ui: 'PretendardRegular', uiBold: 'PretendardSemiBold', serif: 'ReadingSerif');

typedef MarkInput = ({String text, String title, String? author, num? page});

typedef _Quote = ({double x, double maxW, double size, double pitch, double center, Color color, double maxBottom, double spacing});

// 시안에서 잰 값(글자 상자, 화소)
const _spec = {
  MarkStyle.page: (x: 193.0, maxW: 560.0, size: 68.5, pitch: 110.0, center: 725.0, color: Color(0xFF24211E), maxBottom: 1150.0, spacing: 0.9),
  MarkStyle.note: (x: 155.0, maxW: 600.0, size: 72.0, pitch: 108.0, center: 811.5, color: Color(0xFF2C2C2C), maxBottom: 1110.0, spacing: 0.8),
};

// 종이에 눌러 찍은 글자: 아래로 옅은 흰 테두리 + 위로 아주 옅은 그늘
final _emboss = [
  ui.Shadow(color: const Color.fromRGBO(255, 255, 255, 0.6), offset: const Offset(0, 1.6), blurRadius: blurRadiusOfSigma(1.2)),
  ui.Shadow(color: const Color.fromRGBO(0, 0, 0, 0.1), offset: const Offset(0, -0.6), blurRadius: blurRadiusOfSigma(1)),
];

ui.Paragraph _para(String text, {required String family, required double size, required Color color, double? pitch, double? spacing, double width = 800, bool emboss = false, bool keep = true, int? maxLines}) {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: family, fontSize: size, maxLines: maxLines, ellipsis: maxLines == null ? null : '…'))
    ..pushStyle(ui.TextStyle(
      color: color,
      fontFamily: family,
      fontSize: size,
      height: pitch == null ? null : pitch / size,
      letterSpacing: spacing,
      shadows: emboss ? _emboss : null,
    ))
    ..addText(keep ? keepAll(text) : text);
  return b.build()..layout(ui.ParagraphConstraints(width: width));
}

// 문장 줄 나누기(시안 '누구에게나 / 자기 자신에게로 / 가는 길이 있다.'처럼): 사용자가 넣은 줄바꿈은 그대로 두고, 각 문단은
// 가장 적은 줄 수 안에서 '가장 긴 줄'이 짧아지게 나눈다. 뒤 낱말을 꾸미는 짧은 낱말(두 글자 이하, '-는/-은/-의/-한/-던/-ㄹ' 끝) 뒤에서는 줄을 바꾸지 않는다
final _glue = RegExp(r'^(.{1,2}|.*(는|은|의|한|던|할|될|된|운|른|을|를))$');

List<String> breakLines(List<String> words, double Function(String) widthOf, double maxW) {
  final n = words.length;
  final cache = <int, double>{};
  double width(int a, int b) => cache[a * 1000 + b] ??= widthOf(words.sublist(a, b).join(' '));
  // lo[i]: i번째 낱말에서 끝나는 줄이 시작할 수 있는 가장 앞 낱말(폭을 넘지 않는 데까지, 한 낱말은 넘어도 된다).
  // 그보다 앞은 아래에서 어차피 건너뛰므로 폭을 재지 않는다(긴 글에서 모든 낱말 쌍을 재 느렸다). 고르는 결과는 같다
  final lo = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= n; i++) {
    var j = i - 1;
    while (j > 0 && width(j - 1, i) <= maxW) {
      j--;
    }
    lo[i] = j;
  }
  for (var lines = 1; lines <= n; lines++) {
    // prev[i]: 처음 i 낱말을 k줄로 나눈 가장 좋은 방법(벌점이 적은 쪽, 같으면 가장 긴 줄이 짧은 쪽)
    var prev = List<({double max, int pen, List<int> cut})?>.filled(n + 1, null);
    prev[0] = (max: 0, pen: 0, cut: const []);
    for (var k = 1; k <= lines; k++) {
      final cur = List<({double max, int pen, List<int> cut})?>.filled(n + 1, null);
      for (var i = k; i <= n; i++) {
        for (var j = math.max(k - 1, lo[i]); j < i; j++) {
          final b = prev[j];
          if (b == null) continue;
          final w = width(j, i);
          if (w > maxW && i - j > 1) continue;
          final pen = b.pen + (i < n && _glue.hasMatch(words[i - 1]) ? 1 : 0);
          final mx = math.max(b.max, w);
          final c = cur[i];
          if (c == null || pen < c.pen || (pen == c.pen && mx < c.max)) cur[i] = (max: mx, pen: pen, cut: [...b.cut, i]);
        }
      }
      prev = cur;
    }
    final r = prev[n];
    if (r != null && (r.max <= maxW || lines == n)) {
      final out = <String>[];
      var a = 0;
      for (final c in r.cut) {
        out.add(words.sublist(a, c).join(' '));
        a = c;
      }
      return out;
    }
  }
  return [words.join(' ')];
}

const _maxLines = 6;

/// 긴 글도 이보다 작게는 줄이지 않는다(폭 1080 그림에서 약 34px). 더 길면 자른다
const _minSize = 30.0;

typedef _QuoteFit = ({ui.Paragraph p, double size, double pitch, bool cut});

_QuoteFit _quotePara(_Quote s, String text) {
  final maxH = 2 * (s.maxBottom - s.center);
  final paras = [for (final line in text.split('\n')) line.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList()];
  double pitchAt(double size) => s.pitch * size / s.size;
  double spacingAt(double size) => s.spacing * size / s.size;
  // 폭을 잴 때는 줄이 바뀌지 않게 아주 넓게 놓는다
  double Function(String) widthAt(double size) =>
      (t) => _para(t, family: _fonts.quote, size: size, color: s.color, spacing: spacingAt(size), width: 100000).longestLine;
  List<String> broken(double size) {
    final widthOf = widthAt(size);
    return [for (final words in paras) ...(words.isEmpty ? [''] : breakLines(words, widthOf, s.maxW))];
  }

  // 줄 수 아래 한계(문단마다 한 줄로 늘어놓은 폭 ÷ 줄 폭, 줄 끝에서 빠지는 띄어쓰기 몫으로 15% 넉넉히):
  // 들 수 없는 크기는 줄 나누기를 하지 않고 넘긴다(긴 글에서 크기마다 줄 나누기를 다 해 느렸다)
  int fewest(double size) {
    final widthOf = widthAt(size);
    return paras.fold(0, (n, words) => n + (words.isEmpty ? 1 : math.max(1, (widthOf(words.join(' ')) / (s.maxW * 1.15)).ceil())));
  }

  ui.Paragraph build(List<String> lines, double size) =>
      _para(lines.join('\n'), family: _fonts.quote, size: size, color: s.color, pitch: pitchAt(size), width: 2000, spacing: spacingAt(size), emboss: true);
  // 시안 크기부터 3씩 줄이며 6줄 안. 그다음은 줄 수 제한 없이 높이 안: 그 마지막 크기(전에는 여기서 멈춰 넘쳤다), 40부터 2씩
  final big = [for (var size = s.size; size >= 40; size -= 3) size];
  final tries = [
    for (final size in big) (size: size, most: _maxLines),
    for (final size in [big.last, for (var size = 40.0; size >= _minSize; size -= 2) size]) (size: size, most: 1 << 20),
  ];
  for (final t in tries) {
    final pitch = pitchAt(t.size);
    final low = fewest(t.size);
    if (low > t.most || low * pitch > maxH) continue;
    final p = build(broken(t.size), t.size);
    final lines = p.computeLineMetrics().length;
    if (lines <= t.most && lines * pitch <= maxH && p.longestLine <= s.maxW + 40) return (p: p, size: t.size, pitch: pitch, cut: false);
  }
  // 가장 작은 크기에서도 넘친다: 들어가는 줄까지 두고 끝에 '…'
  final pitch = pitchAt(_minSize);
  final widthOf = widthAt(_minSize);
  final keep = broken(_minSize).take(math.max(1, (maxH / pitch).floor())).toList();
  while (keep.length > 1 && keep.last.trim().isEmpty) {
    keep.removeLast();
  }
  var last = keep.last.trimRight();
  while (last.contains(' ') && widthOf('$last…') > s.maxW + 40) {
    last = last.substring(0, last.lastIndexOf(' ')).trimRight();
  }
  keep[keep.length - 1] = '$last…';
  return (p: build(keep, _minSize), size: _minSize, pitch: pitch, cut: true);
}

final _fits = <(MarkStyle, String), _QuoteFit>{};

_QuoteFit _quoteOf(MarkStyle style, String text) {
  final hit = _fits[(style, text)];
  if (hit != null) return hit;
  if (_fits.length > 8) _fits.clear();
  return _fits[(style, text)] = _quotePara(_spec[style]!, text);
}

/// 문장 자리(시안 화소): 위·아래·글자 크기, 다 못 넣어 자른 글인지(공유 시트 안내·시험)
({double top, double bottom, double size, bool cut}) markQuoteBox(MarkStyle style, String text) {
  final spec = _spec[style]!;
  final q = _quoteOf(style, text);
  final h = q.p.computeLineMetrics().length * q.pitch;
  return (top: spec.center - h / 2, bottom: spec.center + h / 2, size: q.size, cut: q.cut);
}

final _plates = <MarkStyle, Future<ui.Image>>{};

Future<ui.Image> markPlate(MarkStyle style) => _plates[style] ??= assetImage('assets/share/bookmark-${style.name}.png');

void drawMarkScene(Canvas canvas, double width, MarkStyle style, ui.Image plate, MarkInput input) {
  final k = width / markW;
  canvas.save();
  canvas.scale(k, k);
  canvas.drawImageRect(plate, Rect.fromLTWH(0, 0, plate.width.toDouble(), plate.height.toDouble()), const Rect.fromLTWH(0, 0, markW, markH), Paint()..filterQuality = FilterQuality.medium);
  final spec = _spec[style]!;
  final q = _quoteOf(style, input.text);
  // 줄 수가 늘면 가운데를 지킨다
  final lineN = q.p.computeLineMetrics().length;
  final blockH = lineN * q.pitch;
  final top = spec.center - blockH / 2;
  canvas.drawParagraph(q.p, Offset(spec.x - 3, top));
  final bottom = top + blockH;
  if (style == MarkStyle.page) {
    final attr = [input.title, ?input.author].where((s) => s.isNotEmpty).join(' | ');
    final a = _para(attr, family: _fonts.ui, size: 36, color: const Color(0xFF423E3B), width: 640, emboss: true, maxLines: 2);
    canvas.drawParagraph(a, Offset(192, math.min(bottom + 62, 1420)));
    // 맨 아래 '책장 한켠'(넓은 자간) + 양옆 줄, 오른쪽 쪽수
    final f = _para('책장 한켠', family: _fonts.ui, size: 22.5, color: const Color(0xFF423F3C), spacing: 2.2);
    canvas.drawParagraph(f, Offset(471 - f.longestLine / 2 + 1, 1537));
    final lp = Paint()..color = const Color(0xFFABA8A6);
    canvas.drawRect(const Rect.fromLTWH(351, 1553.5, 54, 1.4), lp);
    canvas.drawRect(const Rect.fromLTWH(538, 1553.5, 53, 1.4), lp);
    if (input.page != null && input.page != 0) {
      final pg = _para('p. ${input.page}', family: _fonts.serif, size: 31, color: const Color(0xFF3B3937), spacing: -1, emboss: true);
      canvas.drawParagraph(pg, Offset(851 - pg.longestLine, 1525));
    }
  } else {
    // 제목은 한 줄(두 줄이면 지은이 줄과 겹쳤다), 지은이는 쪽수 앞까지 한 줄
    final t = _para(input.title, family: _fonts.uiBold, size: 42, color: const Color(0xFF2C2B2B), width: 520, emboss: true, maxLines: 1);
    canvas.drawParagraph(t, const Offset(154, 1193));
    final pg = input.page != null && input.page != 0 ? _para('p. ${input.page}', family: _fonts.ui, size: 34, color: const Color(0xFF69645F), emboss: true) : null;
    if (input.author != null && input.author!.isNotEmpty) {
      final w = pg == null ? 520.0 : math.min(520.0, 786 - pg.longestLine - 24 - 154);
      canvas.drawParagraph(_para(input.author!, family: _fonts.ui, size: 34, color: const Color(0xFF65615F), width: w, emboss: true, maxLines: 1), const Offset(154, 1252));
    }
    if (pg != null) canvas.drawParagraph(pg, Offset(786 - pg.longestLine, 1252));
    final f = _para('책장 한켠', family: _fonts.ui, size: 31, color: const Color(0xFF484443), spacing: 2);
    canvas.drawParagraph(f, Offset(470 - f.longestLine / 2, 1545));
    final lp = Paint()..color = const Color(0xFFA8A3A2);
    canvas.drawRect(const Rect.fromLTWH(317, 1565.6, 67, 1.6), lp);
    canvas.drawRect(const Rect.fromLTWH(557, 1565.6, 67, 1.6), lp);
  }
  canvas.restore();
}

/// 갈피 공유 그림(폭 pxWidth 화소). 미리보기·내보내기가 같이 쓴다
ui.Image renderMark(ui.Image plate, MarkStyle style, MarkInput input, int pxWidth) {
  final h = (markH * pxWidth / markW).round();
  final rec = ui.PictureRecorder();
  drawMarkScene(Canvas(rec), pxWidth.toDouble(), style, plate, input);
  final pic = rec.endRecording();
  final img = pic.toImageSync(pxWidth, h);
  pic.dispose();
  return img;
}
