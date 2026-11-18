// 시험 빌드 전용(QA_FRAMES) 부분별 시간 재기: 감싼 부분의 만들기(build: 처음 붙일 때·다시 만들 때)·배치(layout)·그리기(paint) 시간을
// 프레임마다 이름별로 더해 두고, 느린 프레임이 기록될 때 함께 찍는다([flprobe]). 출시 빌드에서는 감싸지 않고 그대로 돌려준다
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const qaFrames = bool.fromEnvironment('QA_FRAMES');

/// 이번 프레임 이름별 누적(마이크로초): build · layout · paint
final Map<String, List<int>> qaProbeTotals = {};

void _add(String name, int i, int us) => (qaProbeTotals[name] ??= [0, 0, 0])[i] += us;

/// 함수 하나의 시간을 더한다(phase 0 = build 칸에)
T qaTime<T>(String name, T Function() f) {
  if (!qaFrames) return f();
  final sw = Stopwatch()..start();
  final r = f();
  _add(name, 0, sw.elapsedMicroseconds);
  return r;
}

/// 쌓인 값을 '이름 b/l/p ms' 한 줄로 내고 비운다
String qaProbeTake() {
  if (qaProbeTotals.isEmpty) return '';
  String ms(int us) => (us / 1000).toStringAsFixed(1);
  final s = [for (final e in qaProbeTotals.entries) '${e.key} b${ms(e.value[0])} l${ms(e.value[1])} p${ms(e.value[2])}'].join(' | ');
  qaProbeTotals.clear();
  return s;
}

Widget qaProbe(String name, Widget child) => qaFrames ? _Probe(name: name, child: child) : child;

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.name, required Widget super.child});
  final String name;

  @override
  SingleChildRenderObjectElement createElement() => _ProbeElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe(name);

  @override
  void updateRenderObject(BuildContext context, _RenderProbe renderObject) => renderObject.name = name;
}

class _ProbeElement extends SingleChildRenderObjectElement {
  _ProbeElement(super.widget);

  @override
  void mount(Element? parent, Object? newSlot) {
    final sw = Stopwatch()..start();
    super.mount(parent, newSlot);
    _add((widget as _Probe).name, 0, sw.elapsedMicroseconds);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    final sw = Stopwatch()..start();
    super.update(newWidget);
    _add((widget as _Probe).name, 0, sw.elapsedMicroseconds);
  }
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.name);
  String name;

  @override
  void performLayout() {
    final sw = Stopwatch()..start();
    super.performLayout();
    _add(name, 1, sw.elapsedMicroseconds);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sw = Stopwatch()..start();
    super.paint(context, offset);
    _add(name, 2, sw.elapsedMicroseconds);
  }
}
