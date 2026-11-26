// 갈피 종이 결·테이프 모양(순수): 씨앗 글자에서 지금 앱과 같은 난수로 같은 SVG 경로 글자를 만든다.
// 지금 앱 features/bookmark/BookmarkPaper.tsx makeGrain·BookmarkTape.tsx material을 옮긴 것
// (같은지는 test/bookmark_paper_matches_app_test.dart)
library;

import 'dart:math' as math;

/// 지금 앱 `for (const c of seed) state = (Math.imul(state, 31) + c.charCodeAt(0)) >>> 0`
int _seedState(int start, String seed) {
  var state = start;
  for (final r in seed.runes) {
    // 코드 포인트마다 첫 UTF-16 칸(BMP 밖 글자는 높은 대리 칸)
    final c = r > 0xFFFF ? 0xD800 + ((r - 0x10000) >> 10) : r;
    state = (state * 31 + c) & 0xFFFFFFFF;
  }
  return state;
}

/// 지금 앱 선형 합동 난수(32비트)
class _Lcg {
  _Lcg(this.state);
  int state;
  double next() {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return state / 4294967296;
  }
}

/// JS toFixed(2)
String _f(double v) => v.toStringAsFixed(2);

class Grain {
  const Grain(this.fine, this.broad, this.pulp, this.cloud);
  final String fine, broad, pulp, cloud;
}

Grain makeGrain(String seed) {
  final rnd = _Lcg(_seedState(4129, seed));
  final fine = StringBuffer(), broad = StringBuffer(), pulp = StringBuffer(), cloud = StringBuffer();
  for (var i = 0; i < 290; i++) {
    final x = rnd.next() * 64, y = rnd.next() * 64;
    final dx = 0.35 + rnd.next() * 1.6, dy = (rnd.next() - 0.5) * 1.4;
    fine.write('M${_f(x)} ${_f(y)}q${_f(dx * 0.48)} ${_f(dy - 0.32)} ${_f(dx)} ${_f(dy)}');
  }
  for (var i = 0; i < 92; i++) {
    final x = rnd.next() * 91, y = rnd.next() * 91;
    final a = 1.7 + rnd.next() * 2.4;
    broad.write('M${_f(x)} ${_f(y)}q1.1 -.7 ${_f(a)} ${_f((rnd.next() - 0.5) * 1.8)}');
  }
  for (var i = 0; i < 150; i++) {
    final x = rnd.next() * 137, y = rnd.next() * 137;
    final w = .7 + rnd.next() * 2.1, h = .35 + rnd.next() * .9;
    pulp.write('M${_f(x)} ${_f(y)}q${_f(w * .4)} ${_f(-h)} ${_f(w)} 0q${_f(-w * .35)} ${_f(h * .8)} ${_f(-w)} 0Z');
  }
  for (var i = 0; i < 26; i++) {
    final x = rnd.next() * 137, y = rnd.next() * 137;
    final w = 3 + rnd.next() * 5, h = 1.5 + rnd.next() * 3;
    cloud.write('M${_f(x)} ${_f(y)}q${_f(w * .45)} ${_f(-h)} ${_f(w)} 0q${_f(-w * .25)} ${_f(h * .85)} ${_f(-w)} 0Z');
  }
  return Grain(fine.toString(), broad.toString(), pulp.toString(), cloud.toString());
}

/// 테이프 한 조각(44×45 재료 좌표): 윤곽·찢긴 아래 끝·섬유·주름
class TapeMaterial {
  const TapeMaterial(this.shape, this.torn, this.short, this.long, this.pulp, this.flecks, this.fringe, this.swirl);
  final String shape, torn, short, long, pulp, flecks, fringe, swirl;
}

TapeMaterial tapeMaterial(String seed) {
  final rnd = _Lcg(_seedState(1729, seed));
  final edge = <({double x, double y})>[];
  for (var x = 41.8; x > 2; x -= 2.25) {
    edge.add((x: x, y: 43.55 + rnd.next() * 0.9));
  }
  final torn = 'M43.15 42.8Q43.05 43.65 41.8 ${_f(edge[0].y)}${edge.skip(1).map((p) => 'L${_f(p.x)} ${_f(p.y)}').join()}L1.6 44Q.5 43.9 .62 42.6';
  final shape =
      'M2.1 .9Q.8 .8 .75 2.2L.45 13.8Q.75 27 .62 42.6L1.6 44${edge.reversed.map((p) => 'L${_f(p.x)} ${_f(p.y)}').join()}Q43.05 43.65 43.15 42.8Q43.05 32 43.45 22L43.65 2.4Q43.65 .65 42 .65Q23 .3 2.1 .9Z';
  final short = StringBuffer(), long = StringBuffer(), pulp = StringBuffer(), flecks = StringBuffer(), fringe = StringBuffer(), swirl = StringBuffer();
  for (var i = 0; i < 34; i++) {
    final x = rnd.next() * 44, y = rnd.next() * 45, len = 8 + rnd.next() * 14, a = rnd.next() * math.pi;
    final ex = x + math.cos(a) * len, ey = y + math.sin(a) * len * 0.6;
    final c1x = x + (rnd.next() - .5) * 16, c1y = y + (rnd.next() - .5) * 16, c2x = ex + (rnd.next() - .5) * 16, c2y = ey + (rnd.next() - .5) * 16;
    swirl.write('M${_f(x)} ${_f(y)}C${_f(c1x)} ${_f(c1y)} ${_f(c2x)} ${_f(c2y)} ${_f(ex)} ${_f(ey)}');
  }
  for (var i = 0; i < 340; i++) {
    final x = rnd.next() * 44, y = rnd.next() * 45;
    final dx = (0.6 + rnd.next() * 2.2) * (rnd.next() > .25 ? 1 : -1), dy = (rnd.next() - .5) * 1.8;
    short.write('M${_f(x)} ${_f(y)}q${_f(dx * .5)} ${_f(dy - .35)} ${_f(dx)} ${_f(dy)}');
  }
  for (var i = 0; i < 62; i++) {
    final x = rnd.next() * 44, y = rnd.next() * 45, dx = 2 + rnd.next() * 4;
    final a = (rnd.next() - .5) * 3;
    long.write('M${_f(x)} ${_f(y)}q${_f(dx * .4)} ${_f(a)} ${_f(dx)} ${_f((rnd.next() - .5) * 2)}');
  }
  for (var i = 0; i < 100; i++) {
    final x = rnd.next() * 44, y = rnd.next() * 45, r = .35 + rnd.next() * .7;
    pulp.write('M${_f(x)} ${_f(y)}q${_f(r)} ${_f(-r)} ${_f(r * 2.2)} 0q${_f(-r)} ${_f(r)} ${_f(-r * 2.2)} 0Z');
    final fx = rnd.next() * 44;
    flecks.write('M${_f(fx)} ${_f(rnd.next() * 45)}l.24 .16');
  }
  for (final p in edge) {
    final a = (rnd.next() - .5) * .7;
    fringe.write('M${_f(p.x)} ${_f(p.y - .15)}l${_f(a)} ${_f(.22 + rnd.next() * .45)}');
  }
  return TapeMaterial(shape, torn, short.toString(), long.toString(), pulp.toString(), flecks.toString(), fringe.toString(), swirl.toString());
}

/// 사진에 붙인 한지 테이프 띠(화면 좌표 w×h, 2026-11-21 사용자 '테이프 일부러 각도 틀게, 재질도 신경 써').
/// 위아래는 롤에서 나온 곧은 재단선, 양 끝은 손으로 찢어 들쭉날쭉한 섬유 끝(끝선도 조금 비스듬). 붙인 각도는 띠마다 5~9°(오른쪽이 올라감)
class TapeStrip {
  const TapeStrip({required this.outline, required this.torn, required this.fringe, required this.short, required this.long, required this.pulp, required this.clouds, required this.angle, required this.shift});

  /// 윤곽(닫힌 경로)
  final String outline;

  /// 찢긴 두 끝선(빛 받는 흰 섬유 끝을 그린다)
  final String torn;

  /// 찢긴 끝 밖으로 삐져나온 가는 섬유
  final String fringe;
  final String short, long, pulp;

  /// 고르지 않은 비침(한지는 섬유가 뭉친 곳 · 얇은 곳이 있다): (x, y, 가로 반지름, 세로 반지름, 밝은 쪽이면 true)
  final List<(double, double, double, double, bool)> clouds;

  /// 붙인 각도(도, 음수 = 오른쪽이 올라감)
  final double angle;

  /// 가운데에서 가로로 어긋난 정도
  final double shift;
}

TapeStrip tapeStrip(String seed, double w, double h) {
  final rnd = _Lcg(_seedState(5381, seed));
  final k = h / 30;
  final angle = -(5 + rnd.next() * 4);
  final shift = (rnd.next() - .5) * w * .1;
  // 찢긴 끝: 1.3 간격 섬유 이빨(앞 이빨과 조금 이어지는 들쭉날쭉) + 가끔 깊게 파이거나 튀어나온 곳, 끝선 전체는 비스듬
  List<({double x, double y})> end(double x0) {
    final slant = (rnd.next() - .5) * 7 * k;
    final n = math.max(6, (h / (1.3 * k)).round());
    var jag = 0.0;
    return [
      for (var i = 0; i <= n; i++)
        () {
          jag = jag * .45 + (rnd.next() - .5) * 1.9 * k;
          final notch = rnd.next() < .14 ? (rnd.next() - .5) * 3.2 * k : 0.0;
          final y = h * i / n;
          return (x: x0 + slant * (y / h - .5) + jag + notch, y: y);
        }(),
    ];
  }

  final left = end(2.6 * k), right = end(w - 2.6 * k);
  String pts(Iterable<({double x, double y})> p) => p.map((q) => 'L${_f(q.x)} ${_f(q.y)}').join();
  // 위 · 아래 재단선은 거의 곧다(아주 작은 물결)
  final top = [for (var x = left.first.x + 6; x < right.first.x - 3; x += 6 + rnd.next() * 4) (x: x, y: (rnd.next() - .5) * .3 * k)];
  final bottom = [for (var x = right.last.x - 6; x > left.last.x + 3; x -= 6 + rnd.next() * 4) (x: x, y: h + (rnd.next() - .5) * .3 * k)];
  final outline = 'M${_f(left.first.x)} ${_f(left.first.y)}${pts(top)}${pts(right)}${pts(bottom)}${pts(left.reversed)}Z';
  final torn = 'M${_f(left.first.x)} ${_f(left.first.y)}${pts(left.skip(1))}M${_f(right.first.x)} ${_f(right.first.y)}${pts(right.skip(1))}';
  final fringe = StringBuffer();
  for (final (side, p) in [for (final q in left) (-1.0, q), for (final q in right) (1.0, q)]) {
    if (rnd.next() < .45) continue;
    final len = (.5 + rnd.next() * 1.8) * k, a = (rnd.next() - .5) * 1.4;
    final ex = side * math.cos(a) * len, ey = math.sin(a) * len;
    fringe.write('M${_f(p.x - side * .3 * k)} ${_f(p.y)}q${_f(ex * .5)} ${_f(ey * .5 + (rnd.next() - .5) * .6 * k)} ${_f(ex)} ${_f(ey)}');
  }
  final area = w * h;
  final short = StringBuffer(), long = StringBuffer(), pulp = StringBuffer();
  for (var i = 0; i < (area * .16).round(); i++) {
    final x = rnd.next() * w, y = rnd.next() * h;
    final dx = (0.6 + rnd.next() * 2.2) * k * (rnd.next() > .25 ? 1 : -1), dy = (rnd.next() - .5) * 1.8 * k;
    short.write('M${_f(x)} ${_f(y)}q${_f(dx * .5)} ${_f(dy - .35 * k)} ${_f(dx)} ${_f(dy)}');
  }
  for (var i = 0; i < (area * .028).round(); i++) {
    final x = rnd.next() * w, y = rnd.next() * h, dx = (2.5 + rnd.next() * 6) * k;
    long.write('M${_f(x)} ${_f(y)}q${_f(dx * .4)} ${_f((rnd.next() - .5) * 3 * k)} ${_f(dx)} ${_f((rnd.next() - .5) * 2 * k)}');
  }
  for (var i = 0; i < (area * .045).round(); i++) {
    final x = rnd.next() * w, y = rnd.next() * h, r = (.35 + rnd.next() * .7) * k;
    pulp.write('M${_f(x)} ${_f(y)}q${_f(r)} ${_f(-r)} ${_f(r * 2.2)} 0q${_f(-r)} ${_f(r)} ${_f(-r * 2.2)} 0Z');
  }
  final clouds = [
    for (var i = 0; i < math.max(4, (w / 12).round()); i++) (rnd.next() * w, rnd.next() * h, (5 + rnd.next() * 10) * k, (3 + rnd.next() * 5) * k, i.isEven),
  ];
  return TapeStrip(outline: outline, torn: torn, fringe: fringe.toString(), short: short.toString(), long: long.toString(), pulp: pulp.toString(), clouds: clouds, angle: angle, shift: shift);
}
