// 시안용 디자인 토큰(design-system/tokens.json · design-system/web/)을 Flutter 원본 값에서 만들고, 어긋나면 실패한다.
// 원본: lib/ui/theme.dart(AppColors · AppFonts · TypeSpecs · TabHeader · TabBarStyle · 투명도), lib/ui/kit.dart(Space · Shape · ControlSize · IconSize · CoverSize · NightColors).
// 값을 바꾼 뒤 다시 만들기: DESIGN_TOKENS_UPDATE=1 flutter test test/design_tokens_test.dart
// 규칙과 쓰임은 docs/design/DESIGN.md
import 'dart:convert';
import 'dart:io';

import 'package:chaekjang/features/bookmark/bookmark_card.dart' show bookmarkCardShadow;
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokensPath = 'design-system/tokens.json';
const _webDir = 'design-system/web';
const _regen = 'DESIGN_TOKENS_UPDATE=1 flutter test test/design_tokens_test.dart';

/// Flutter 글꼴 이름 → (토큰 이름, 웹 글꼴, 굵기, 파일). 파일은 pubspec.yaml fonts와 같아야 한다(아래 시험이 본다)
const _fonts = <String, (String, String, int, String)>{
  AppFonts.ui: ('ui', 'Pretendard', 400, 'Pretendard-Regular.otf'),
  AppFonts.uiMedium: ('uiMedium', 'Pretendard', 500, 'Pretendard-Medium.otf'),
  AppFonts.uiBold: ('uiBold', 'Pretendard', 600, 'Pretendard-SemiBold.otf'),
  AppFonts.uiTitle: ('uiTitle', 'Pretendard', 700, 'Pretendard-Bold.otf'),
  AppFonts.reading: ('reading', 'Noto Serif KR', 400, 'NotoSerifKR-Regular.otf'),
  'Hahmlet': ('spineTitle', 'Hahmlet', 600, 'Hahmlet-SemiBold.ttf'),
  'MaruBuriRegular': ('share', 'MaruBuri', 400, 'MaruBuri-Regular.ttf'),
  'MaruBuriSemiBold': ('shareBold', 'MaruBuri', 600, 'MaruBuri-SemiBold.ttf'),
};

String _hex(Color c) {
  final v = c.toARGB32();
  final rgb = (v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  final a = v >>> 24;
  return a == 0xFF ? '#$rgb' : '#$rgb${a.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

String _kebab(String s) => s.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

num _n(double v) => v == v.roundToDouble() ? v.toInt() : double.parse(v.toStringAsFixed(2));

/// Flutter blurRadius r → CSS 흐림 반경(2σ, σ = 0.57735·r + 0.5)
num _cssBlur(double r) => r <= 0 ? 0 : _n(2 * (0.57735 * r + 0.5));

Map<String, Object> _shadow(BoxShadow s, String use) => {
  'color': _hex(s.color),
  'x': _n(s.offset.dx),
  'y': _n(s.offset.dy),
  'blurRadius': _n(s.blurRadius),
  'cssBlur': _cssBlur(s.blurRadius),
  if (s.spreadRadius != 0) 'spread': _n(s.spreadRadius),
  'use': use,
};

Map<String, Object> _nums(Map<String, double> m) => {for (final e in m.entries) e.key: _n(e.value)};

String _colorName(Color c) => AppColors.all.entries.firstWhere((e) => e.value.$1 == c, orElse: () => throw StateError('글자 역할 색 ${_hex(c)}가 AppColors.all에 없다')).key;

Map<String, Object> buildTokens() => {
  r'$meta': {
    'app': '책장 한켠 (Flutter)',
    'generatedBy': 'app/test/design_tokens_test.dart',
    'regenerate': _regen,
    'sources': [
      'app/lib/ui/theme.dart: AppColors · AppFonts · TypeSpecs(글자 역할) · TabHeader · TabBarStyle · pressOpacity · disabledOpacity',
      'app/lib/ui/kit.dart: Space · Shape · ControlSize · IconSize · CoverSize · NightColors · contentMax · sheetMax',
      'app/lib/features/bookmark/bookmark_card.dart: bookmarkCardShadow',
    ],
    'rules': 'docs/design/DESIGN.md',
    'notes': [
      '손으로 고치지 않는다. 값은 Flutter 원본에서만 바꾸고 위 명령으로 다시 만든다.',
      '다크 테마는 없다(라이트 하나). 어두운 읽기 장면 위 글자 · 조작부만 color.night를 쓴다.',
      '앱은 글자 크기 · 줄 높이를 화소 단위로 올린다(theme.dart rnPx). 시안 CSS는 dp 값 그대로 쓴다.',
      '책장 3D 장면(벽 · 판 · 책 빛)과 공유 그림 · 갈피 종이의 색은 UI 토큰이 아니다.',
    ],
  },
  'color': {
    'light': {
      for (final e in AppColors.all.entries) e.key: {'value': _hex(e.value.$1), 'use': e.value.$2},
    },
    'night': {
      for (final e in NightColors.all.entries) e.key: {'value': _hex(e.value.$1), 'use': e.value.$2},
    },
  },
  'font': {
    'families': {
      for (final e in _fonts.entries) e.value.$1: {'flutter': e.key, 'web': e.value.$2, 'weight': e.value.$3, 'file': 'assets/fonts/${e.value.$4}'},
    },
    'letterSpacing': 0,
  },
  'type': {
    for (final e in TypeSpecs.all.entries)
      e.key: {'font': _fonts[e.value.family]!.$1, 'size': _n(e.value.size), 'lineHeight': _n(e.value.line), 'color': _colorName(e.value.color), if (e.value.tabular) 'tabular': true},
    'input': {'font': _fonts[AppType.input.fontFamily]!.$1, 'size': _n(AppType.input.fontSize!), 'color': _colorName(AppType.input.color!), 'lineHeightNote': '플랫폼 기본(입력창)'},
  },
  'space': {
    ..._nums(Space.all),
    'contentMax': _n(contentMax),
    'sheetMax': _n(sheetMax),
    'tabHeader': _nums({'paddingTop': TabHeader.paddingTop, 'paddingBottom': TabHeader.paddingBottom, 'paddingH': TabHeader.paddingH, 'minHeight': TabHeader.minHeight}),
  },
  'radius': _nums(Shape.all),
  'shadow': {
    'float': _shadow(Shape.floatShadow, '떠 있는 단추 · 미니 타이머 · 메뉴'),
    'tabBar': _shadow(TabBarStyle.shadow, '하단 탭 알약'),
    'segmentedThumb': _shadow(Shape.segmentShadow, '전환 칸의 고른 칸'),
    'bookmarkCard': [for (final s in bookmarkCardShadow) _shadow(s, '갈피 카드 종이')],
  },
  'size': {
    'control': _nums(ControlSize.all),
    'touch': _n(Space.hit),
    'icon': {..._nums(IconSize.all), 'tabBar': _n(TabBarStyle.icon)},
    'navBar': _n(NavBar.height),
    'cover': _nums(CoverSize.all),
    'tabBar': _nums({
      'height': TabBarStyle.height,
      'navHeight': TabBarStyle.navHeight,
      'contentPad': TabBarStyle.contentPad,
      'side': TabBarStyle.side,
      'gap': TabBarStyle.gap,
      'paddingX': TabBarStyle.paddingX,
      'fade': TabBarStyle.fade,
    }),
  },
  'opacity': {'pressed': pressOpacity, 'disabled': disabledOpacity},
};

String _cssShadow(Map<String, Object> s) => '${s['x']}px ${s['y']}px ${s['cssBlur']}px ${s['spread'] ?? 0}px ${s['color']}';

/// tokens.json → web/styles.css(시안이 링크하는 파일 하나: 토큰 + 역할 글자 class + 바탕)
String buildCss(Map<String, Object> t) {
  final out = <String>[];
  void add(String s) => out.add(s);
  final color = t['color']! as Map<String, Object>;
  final light = color['light']! as Map<String, Object>;
  final night = color['night']! as Map<String, Object>;
  add('/* 책장 한켠 디자인 토큰 - app/test/design_tokens_test.dart가 Flutter 원본에서 만든다. 손으로 고치지 않는다 */');
  add('/* 다시 만들기: cd app && $_regen */');
  add("@import url('fonts.css');");
  add('');
  add(':root {');
  add('  /* 색(AppColors) */');
  for (final e in light.entries) {
    final v = e.value as Map<String, Object>;
    add('  --ck-${_kebab(e.key)}: ${v['value']}; /* ${v['use']} */');
  }
  add('  /* 어두운 장면 위(NightColors) */');
  for (final e in night.entries) {
    final v = e.value as Map<String, Object>;
    add('  --ck-night-${_kebab(e.key)}: ${v['value']}; /* ${v['use']} */');
  }
  add('');
  add('  /* 글꼴 */');
  add("  --ck-font-ui: 'Pretendard', sans-serif;");
  add("  --ck-font-reading: 'Noto Serif KR', serif;");
  add("  --ck-font-spine: 'Hahmlet', 'Noto Serif KR', serif;");
  add("  --ck-font-share: 'MaruBuri', 'Noto Serif KR', serif;");
  add('');
  add('  /* 글자 역할(TypeSpecs): 굵기 크기/줄높이 글꼴. 색 · 숫자 폭은 아래 .ck-type-* class */');
  final type = t['type']! as Map<String, Object>;
  final fams = (t['font']! as Map<String, Object>)['families']! as Map<String, Object>;
  for (final e in type.entries) {
    final v = e.value as Map<String, Object>;
    final f = fams[v['font']]! as Map<String, Object>;
    final stack = f['web'] == 'Pretendard' ? 'var(--ck-font-ui)' : 'var(--ck-font-reading)';
    final lh = v['lineHeight'] == null ? 'normal' : '${v['lineHeight']}px';
    add('  --ck-type-${_kebab(e.key)}: ${f['weight']} ${v['size']}px/$lh $stack;');
  }
  add('');
  add('  /* 간격(Space) */');
  final space = t['space']! as Map<String, Object>;
  for (final e in space.entries) {
    if (e.value is Map) {
      for (final e2 in (e.value as Map<String, Object>).entries) {
        add('  --ck-${_kebab(e.key)}-${_kebab(e2.key)}: ${e2.value}px;');
      }
    } else {
      add('  --ck-space-${_kebab(e.key)}: ${e.value}px;');
    }
  }
  add('');
  add('  /* 모서리(Shape) */');
  for (final e in (t['radius']! as Map<String, Object>).entries) {
    add('  --ck-radius-${_kebab(e.key)}: ${e.value}px;');
  }
  add('');
  add('  /* 그림자(CSS 흐림 반경으로 바꾼 값) */');
  for (final e in (t['shadow']! as Map<String, Object>).entries) {
    final v = e.value;
    final css = v is List ? v.map((s) => _cssShadow(s as Map<String, Object>)).join(', ') : _cssShadow(v as Map<String, Object>);
    add('  --ck-shadow-${_kebab(e.key)}: $css;');
  }
  add('');
  add('  /* 크기(ControlSize · IconSize · CoverSize · TabBarStyle) */');
  final size = t['size']! as Map<String, Object>;
  final control = size['control']! as Map<String, Object>;
  add('  --ck-btn-l: ${control['buttonL']}px;');
  add('  --ck-btn-m: ${control['buttonM']}px;');
  add('  --ck-btn-s: ${control['buttonS']}px;');
  for (final e in control.entries) {
    if (e.key.startsWith('button')) continue;
    add('  --ck-${_kebab(e.key)}: ${e.value}px;');
  }
  add('  --ck-segmented-height: ${_n((control['segment']! as num) + 2 * ((control['segmentPad']! as num) - (control['segmentInset']! as num)).toDouble())}px; /* 전환 칸 회색 칸 */');
  add('  --ck-touch: ${size['touch']}px;');
  final icon = size['icon']! as Map<String, Object>;
  add('  --ck-icon: ${icon['base']}px;');
  add('  --ck-icon-chevron: ${icon['chevron']}px;');
  add('  --ck-icon-stroke: ${icon['stroke']}px;');
  add('  --ck-icon-tab-bar: ${icon['tabBar']}px;');
  add('  --ck-icon-back: ${icon['back']}px;');
  add('  --ck-icon-mark: ${icon['mark']}px;');
  add('  --ck-nav-bar: ${size['navBar']}px;');
  for (final e in (size['cover']! as Map<String, Object>).entries) {
    add(e.key == 'ratio' ? '  --ck-cover-ratio: ${e.value};' : '  --ck-cover-${_kebab(e.key)}: ${e.value}px;');
  }
  for (final e in (size['tabBar']! as Map<String, Object>).entries) {
    add('  --ck-tabbar-${_kebab(e.key)}: ${e.value}px;');
  }
  final opa = t['opacity']! as Map<String, Object>;
  add('  --ck-press-opacity: ${opa['pressed']};');
  add('  --ck-disabled-opacity: ${opa['disabled']};');
  add('');
  add('  /* 옛 이름(이미 만든 시안이 깨지지 않게) */');
  add('  --ck-radius-chip: var(--ck-radius-pill);');
  add('  --ck-radius-tab-bar: var(--ck-radius-pill);');
  add('  --ck-radius-cover-image: var(--ck-radius-cover);');
  add('}');
  add('');
  add('/* 글자 역할 class: 앱과 같은 글자 · 색 · 숫자 폭 */');
  for (final e in type.entries) {
    final v = e.value as Map<String, Object>;
    final k = _kebab(e.key);
    add('.ck-type-$k { font: var(--ck-type-$k); color: var(--ck-${_kebab(v['color']! as String)});${v['tabular'] == true ? ' font-variant-numeric: tabular-nums;' : ''} }');
  }
  add('');
  add('/* 바탕: 앱 화면과 같은 글꼴 · 글자색 · 흰 바탕, 자간 0 */');
  add('html, body { background: var(--ck-bg); color: var(--ck-ink); font: var(--ck-type-body); letter-spacing: 0; -webkit-font-smoothing: antialiased; }');
  return '${out.join('\n')}\n';
}

String buildFontsCss() {
  final out = ['/* 책장 한켠 글꼴(app/assets/fonts, 모두 OFL) - app/test/design_tokens_test.dart가 만든다 */'];
  for (final f in _fonts.values) {
    final fmt = f.$4.endsWith('.otf') ? 'opentype' : 'truetype';
    out.add("@font-face { font-family: '${f.$2}'; font-weight: ${f.$3}; font-style: normal; font-display: swap; src: url('../../assets/fonts/${f.$4}') format('$fmt'); }");
  }
  return '${out.join('\n')}\n';
}

const _pkg = {'name': 'chaekjang-design-tokens', 'version': '0.1.0', 'private': true, 'description': '책장 한켠 디자인 토큰(Flutter 원본에서 생성)', 'main': 'index.js', 'module': 'index.js', 'style': 'styles.css'};
const _indexJs = '// 컴포넌트 없음: 책장 한켠 위젯은 Flutter라 웹 번들로 옮기지 않는다(토큰 · 글꼴 · 지침만)\nexport {};\n';

String _json(Object o) => '${const JsonEncoder.withIndent('  ').convert(o)}\n';

Map<String, String> buildFiles() {
  final t = buildTokens();
  return {_tokensPath: _json(t), '$_webDir/styles.css': buildCss(t), '$_webDir/fonts.css': buildFontsCss(), '$_webDir/package.json': _json(_pkg), '$_webDir/index.js': _indexJs};
}

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: w)),
  ),
);

Size _boxOf(WidgetTester t, Type owner) => t.getSize(find.descendant(of: find.byType(owner), matching: find.byType(Container)).first);

void main() {
  test('시안 토큰 · CSS가 Flutter 원본 값과 같다', () {
    final files = buildFiles();
    if (Platform.environment['DESIGN_TOKENS_UPDATE'] == '1') {
      for (final e in files.entries) {
        File(e.key)
          ..createSync(recursive: true)
          ..writeAsStringSync(e.value);
      }
      return;
    }
    for (final e in files.entries) {
      final f = File(e.key);
      expect(f.existsSync() ? f.readAsStringSync() : null, e.value, reason: '${e.key}가 Flutter 원본 값과 다르다. 원본을 고쳤다면 다시 만든다: $_regen');
    }
  });

  test('글꼴 표가 pubspec.yaml 글꼴과 같다', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    for (final e in _fonts.entries) {
      expect(pub, contains('- family: ${e.key}\n      fonts:\n        - asset: assets/fonts/${e.value.$4}'), reason: '${e.key} 글꼴 파일');
    }
  });

  test('글자 역할 표: AppType이 TypeSpecs를 그대로 쓴다', () {
    for (final e in TypeSpecs.all.entries) {
      final s = e.value.style;
      expect(s.fontFamily, e.value.family, reason: e.key);
      expect(s.fontSize, e.value.size, reason: e.key);
      expect(s.color, e.value.color, reason: e.key);
    }
    expect(AppType.bookTitle.fontSize, TypeSpecs.bookTitle.size);
  });

  testWidgets('공용 단추 높이 = ControlSize(TDS xlarge · large · medium · small), 누르는 자리 48 이상', (t) async {
    for (final (size, h) in [('xlarge', ControlSize.buttonL), ('large', ControlSize.buttonM), ('medium', ControlSize.buttonS), ('small', ControlSize.buttonS)]) {
      await _pump(t, Btn(label: '저장', size: size, onPress: () {}));
      expect(_boxOf(t, Btn).height, h, reason: 'Btn $size 겉높이');
      expect(t.getSize(find.byType(Btn)).height, greaterThanOrEqualTo(Space.hit), reason: 'Btn $size 누르는 자리');
    }
  });

  testWidgets('스위치 · 검색칸 · 고르는 칸 · 입력칸 크기 = ControlSize', (t) async {
    await _pump(t, Toggle(value: true, label: '진동', onChange: (_) {}));
    final track = find.descendant(of: find.byType(Toggle), matching: find.byType(Container)).first;
    expect(t.getSize(track), const Size(ControlSize.toggleWidth, ControlSize.toggleHeight));

    await _pump(
      t,
      SizedBox(
        width: 300,
        child: SearchField(value: '', onChange: (_) {}, placeholder: '검색'),
      ),
    );
    expect(_boxOf(t, SearchField).height, ControlSize.search);

    await _pump(
      t,
      SizedBox(
        width: 300,
        child: SelectField(label: '책', placeholder: '책 고르기', value: '데미안', onPress: () {}),
      ),
    );
    expect(t.getSize(find.descendant(of: find.byType(SelectField), matching: find.byType(Container)).last).height, greaterThanOrEqualTo(ControlSize.field));
  });

  testWidgets('책 한 줄 표지 폭 = CoverSize', (t) async {
    for (final (size, w) in [(BookRowSize.small, CoverSize.row), (BookRowSize.medium, CoverSize.result), (BookRowSize.large, CoverSize.list)]) {
      await _pump(
        t,
        SizedBox(
          width: 360,
          child: BookRow(
            size: size,
            cover: const SizedBox(key: Key('cover'), height: 10),
            title: '데미안',
            meta: '헤르만 헤세',
          ),
        ),
      );
      expect(t.getSize(find.byKey(const Key('cover'))).width, w, reason: '$size');
    }
  });

  test('DESIGN.md 표의 이름 · 숫자가 코드와 같다', () {
    final doc = File('../docs/design/DESIGN.md').readAsStringSync();
    final groups = <String, Map<String, double>>{'Space': Space.all, 'Shape': Shape.all, 'ControlSize': ControlSize.all, 'IconSize': IconSize.all, 'CoverSize': CoverSize.all};
    final wrong = <String>[];
    // 글자 역할 표: | `AppType.x` | 18/26 | …
    for (final m in RegExp(r'\|\s*`AppType\.(\w+)`\s*\|\s*([\d.]+)/([\d.—]+)\s*\|').allMatches(doc)) {
      final name = m[1]!;
      if (name == 'input') {
        if (double.parse(m[2]!) != AppType.input.fontSize) wrong.add('AppType.input ${m[2]}');
        continue;
      }
      final spec = TypeSpecs.all[name];
      if (spec == null) {
        wrong.add('AppType.$name: 없는 역할');
      } else if (double.parse(m[2]!) != spec.size || double.parse(m[3]!) != spec.line) {
        wrong.add('AppType.$name: 문서 ${m[2]}/${m[3]}, 코드 ${_n(spec.size)}/${_n(spec.line)}');
      }
    }
    // 크기 표: | `Group.name` | 52 | …
    for (final m in RegExp(r'\|\s*`(Space|Shape|ControlSize|IconSize|CoverSize)\.(\w+)`\s*\|\s*([\d.]+)\s*\|').allMatches(doc)) {
      final v = groups[m[1]]![m[2]];
      if (v == null) {
        wrong.add('${m[1]}.${m[2]}: 없는 이름');
      } else if (double.parse(m[3]!) != v) {
        wrong.add('${m[1]}.${m[2]}: 문서 ${m[3]}, 코드 ${_n(v)}');
      }
    }
    // 글 속 이름: `AppType.x` · `ControlSize.x` 등이 실제로 있어야 한다
    for (final m in RegExp(r'`(AppType|Space|Shape|ControlSize|IconSize|CoverSize|AppColors)\.(\w+)').allMatches(doc)) {
      final ok =
          m[2] == 'all' ||
          switch (m[1]) {
            'AppType' => TypeSpecs.all.containsKey(m[2]) || m[2] == 'input',
            'AppColors' => AppColors.all.containsKey(m[2]),
            'Shape' => Shape.all.containsKey(m[2]) || m[2] == 'floatShadow' || m[2] == 'segmentShadow',
            _ => groups[m[1]]!.containsKey(m[2]),
          };
      if (!ok) wrong.add('${m[1]}.${m[2]}: 없는 이름');
    }
    expect(wrong, isEmpty, reason: 'docs/design/DESIGN.md를 코드에 맞게 고친다(값은 코드가 원본)');
    // 모든 글자 역할이 문서 표에 있다(새 역할을 만들면 언제 쓰는지 문서에 적는다)
    final listed = RegExp(r'\|\s*`AppType\.(\w+)`').allMatches(doc).map((m) => m[1]).toSet();
    expect(TypeSpecs.all.keys.where((k) => !listed.contains(k)), isEmpty, reason: 'DESIGN.md 표에 없는 글자 역할');
  });

  test('시안 안내(conventions.md)가 가리키는 변수 · class가 styles.css에 있다', () {
    final css = File('$_webDir/styles.css').readAsStringSync();
    final vars = RegExp(r'(--ck-[a-z0-9-]+):').allMatches(css).map((m) => m[1]).toSet();
    final classes = RegExp(r'\.(ck-type-[a-z0-9-]+) \{').allMatches(css).map((m) => m[1]).toSet();
    final conv = File('.design-sync/conventions.md').readAsStringSync();
    final missing = [
      for (final m in RegExp(r'--ck-[a-z0-9-]*[a-z0-9]').allMatches(conv))
        if (!vars.contains(m[0]) && !RegExp(r'--ck-(space|radius|type|night)$').hasMatch(m[0]!)) m[0]!,
      for (final m in RegExp(r'\.(ck-type-[a-z0-9-]*[a-z0-9])').allMatches(conv))
        if (!classes.contains(m[1])) '.${m[1]}',
    ];
    expect(missing, isEmpty);
  });

  test('화면 코드에 글자 크기 숫자가 없다(DESIGN.md 16장 예외만)', () {
    // 옛 앱 화소 값을 그대로 옮긴 그림 · 종이와 글꼴 데우기만 예외
    const allowed = {'lib/services/warmup.dart', 'lib/features/bookmark/board_card.dart', 'lib/features/bookmark/bookmark_detail_screen.dart'};
    final raw = RegExp(r'fontSize:\s*[0-9]');
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart') || p.startsWith('lib/gen/') || p == 'lib/ui/theme.dart' || allowed.contains(p)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) hits.add('$p:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: '글자 크기는 AppType 역할로(theme.dart TypeSpecs). 그림 · 종이처럼 일부러 다른 값이면 DESIGN.md 16장과 이 시험 예외에 함께 적는다');
  });
}
