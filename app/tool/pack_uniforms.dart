// 셰이더의 낱개 uniform(float · vec · mat)을 vec4 배열 하나(uP)로 묶는다. tool/gen_shaders.sh가 GLSL로 바꾼 뒤 부른다.
//
// 왜: 아이폰(Impeller Metal)은 uniform 하나마다 버퍼 칸 하나를 쓰는데, Metal은 그리기 함수 하나에 버퍼 칸을 31개(0~30)까지만 받는다.
// 벽·판(lit)과 책 빛(book)은 48칸을 써서 아이폰에서 셰이더가 만들어지지 않았고, 벽·선반 판이 비고 책은 빛 없이 평평하게 보였다(2026-11-25).
// 안드로이드 Vulkan은 uniform을 구조체 하나로 묶어 넘겨 문제가 없었다. 묶으면 백엔드마다 버퍼 칸 1개 + 배열 uniform 수만 쓴다.
//
// 묶는 법: 선언 차례대로 빈틈 없이 float 자리를 매기고(float 1 · vec2 2 · vec3 3 · vec4 4 · mat2 4 · mat3 9 · mat4 16),
// 선언 줄은 같은 이름의 보통 전역 변수로 바꾸고, main() 맨 앞에서 uP에서 꺼내 채운다. 셰이더 본문은 그대로다
// (#define으로 바꾸면 같은 이름의 함수 인자 · 지역 변수까지 바뀌어 컴파일이 깨진다. 전역 변수는 GLSL 이름 가림을 그대로 따른다).
// vec4 배열 하나라 Metal · Vulkan · GLES 어디서나 자리 간격이 같다(vec3 · mat3의 16바이트 맞춤 차이가 없다).
// 배열 uniform(box[160] 같은 것)과 그림(sampler2D)은 그대로 둔다.
//
// Dart 쪽은 lib/gen/packed_uniforms.g.dart(이 도구가 쓴다)의 자리 표로 uP 시작 + 자리에 값을 넣는다(ui/bake.dart ShaderSlots).
// 이미 묶인 파일은 선언 끝의 `// uP@자리` 표시로 자리를 다시 읽어 표만 새로 쓴다(두 번 돌려도 같다).
//
// 쓰는 법(app/에서): dart run tool/pack_uniforms.dart lib/gen/packed_uniforms.g.dart shaders/lit.frag shaders/book.frag ...
import 'dart:io';

const _sizes = {'float': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4, 'mat2': 4, 'mat3': 9, 'mat4': 16};
const packedName = 'uP';

final _decl = RegExp(r'^(\s*)uniform\s+(float|vec2|vec3|vec4|mat2|mat3|mat4)\s+(\w+)\s*;(.*)$');
final _packedVar = RegExp(r'^\s*(?:float|vec2|vec3|vec4|mat2|mat3|mat4)\s+(\w+)\s*;.*//.*\buP@(\d+)\s*$');
final _packedDecl = RegExp(r'^\s*uniform\s+vec4\s+uP\[(\d+)\]\s*;');
final _main = RegExp(r'^\s*void\s+main\s*\(\s*\)\s*\{\s*$');

const _lanes = ['x', 'y', 'z', 'w'];

/// float 자리 o부터 n개를 uP에서 꺼내는 식: 같은 vec4 안에서 이어지면 스위즐 하나, 넘어가면 조각을 이어 붙인다
String _read(int o, int n) {
  final parts = <String>[];
  var i = o;
  while (i < o + n) {
    final slot = i ~/ 4, lane = i % 4;
    final take = (4 - lane).clamp(1, o + n - i);
    parts.add(take == 4 ? '$packedName[$slot]' : '$packedName[$slot].${_lanes.sublist(lane, lane + take).join()}');
    i += take;
  }
  if (parts.length == 1) return parts.single;
  return 'vec$n(${parts.join(', ')})';
}

String _expr(String type, int o) => switch (type) {
      'mat2' => 'mat2(${_read(o, 2)}, ${_read(o + 2, 2)})',
      'mat3' => 'mat3(${_read(o, 3)}, ${_read(o + 3, 3)}, ${_read(o + 6, 3)})',
      'mat4' => 'mat4(${_read(o, 4)}, ${_read(o + 4, 4)}, ${_read(o + 8, 4)}, ${_read(o + 12, 4)})',
      _ => _read(o, _sizes[type]!),
    };

/// 한 파일을 묶고(이미 묶였으면 그대로) 이름 → float 자리 표와 uP 칸 수를 돌려준다
(Map<String, int>, int) packFile(File f) {
  final lines = f.readAsLinesSync();
  final table = <String, int>{};
  final packed = lines.map(_packedDecl.firstMatch).whereType<RegExpMatch>().firstOrNull;
  if (packed != null) {
    for (final l in lines) {
      final m = _packedVar.firstMatch(l);
      if (m != null) table[m[1]!] = int.parse(m[2]!);
    }
    return (table, int.parse(packed[1]!));
  }
  var floats = 0;
  final vars = <int, String>{};
  final fills = <String>[];
  int? first;
  for (var i = 0; i < lines.length; i++) {
    final m = _decl.firstMatch(lines[i]);
    if (m == null) continue;
    final (indent, type, name, rest) = (m[1]!, m[2]!, m[3]!, m[4]!.trim());
    first ??= i;
    table[name] = floats;
    final note = rest.startsWith('//') ? ' ${rest.substring(2).trim()}' : '';
    vars[i] = '$indent$type $name; //$note uP@$floats';
    fills.add('  $name = ${_expr(type, floats)};');
    floats += _sizes[type]!;
  }
  if (first == null) return (table, 0);
  final mainAt = lines.indexWhere(_main.hasMatch);
  if (mainAt < 0) throw StateError('${f.path}: `void main() {` 줄을 찾지 못했다');
  final slots = (floats + 3) ~/ 4;
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i == first) {
      final indent = _decl.firstMatch(lines[i])![1]!;
      out.add('$indent// 낱개 uniform을 묶은 것(tool/pack_uniforms.dart): 아이폰 Metal은 버퍼 칸이 31개까지라 낱개로는 셰이더가 만들어지지 않는다.');
      out.add('$indent// 아래 같은 이름의 전역 변수들은 main() 맨 앞에서 채운다');
      out.add('${indent}uniform vec4 $packedName[$slots];');
    }
    out.add(vars[i] ?? lines[i]);
    if (i == mainAt) out.addAll(fills);
  }
  f.writeAsStringSync('${out.join('\n')}\n');
  return (table, slots);
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('쓰는 법: dart run tool/pack_uniforms.dart <표.g.dart> <셰이더.frag>...');
    exit(64);
  }
  final buf = StringBuffer()
    ..writeln('// 만든 파일(tool/pack_uniforms.dart): 셰이더마다 묶인 uniform의 uP 안 float 자리. 손으로 고치지 않는다')
    ..writeln()
    ..writeln("const packedUniformName = '$packedName';")
    ..writeln()
    ..writeln('const packedUniforms = <String, Map<String, int>>{');
  for (final path in args.skip(1)) {
    final (table, slots) = packFile(File(path));
    buf.writeln("  '$path': {");
    for (final e in table.entries) {
      buf.writeln("    '${e.key}': ${e.value},");
    }
    buf.writeln('  },');
    stdout.writeln('$path: 낱개 ${table.length}개 → $packedName[$slots]');
  }
  buf.writeln('};');
  File(args.first).writeAsStringSync(buf.toString());
}
