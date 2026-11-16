#!/usr/bin/env python3
# design-system/tokens.json(Flutter lib/ui/theme.dart·kit.dart에서 뽑은 값) → Claude Design용 CSS(design-system/web/).
# 원본은 늘 Flutter 쪽: theme.dart를 고치면 tokens.json을 맞추고 이것을 다시 돌린 뒤 /design-sync로 올린다.
# 사용: cd flutter && python3 tool/gen_design_css.py
import json
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
T = json.load(open(os.path.join(ROOT, 'design-system', 'tokens.json'), encoding='utf-8'))
OUT = os.path.join(ROOT, 'design-system', 'web')
os.makedirs(OUT, exist_ok=True)


def kebab(s):
    return re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', s).lower()


lines = []
add = lines.append
add('/* 책장 한켠 디자인 토큰 - flutter/design-system/tokens.json에서 생성(tool/gen_design_css.py). 손으로 고치지 않는다 */')
add('')
add(':root {')
add('  /* 색(라이트 하나, 다크 테마 없음) */')
for k, v in T['color']['light'].items():
    add(f"  --ck-{kebab(k)}: {v['value']}; /* {v.get('use', '')} */")
add('  /* 어두운 읽기 장면 위 글자·조작부 */')
for k, v in T['color']['night'].items():
    if k.startswith('$'):
        continue
    add(f"  --ck-night-{kebab(k)}: {v['value']};")
add('')
add('  /* 글꼴 */')
add("  --ck-font-ui: 'Pretendard', sans-serif;")
add("  --ck-font-reading: 'Noto Serif KR', serif;")
add("  --ck-font-spine: 'Hahmlet', 'Noto Serif KR', serif;")
add("  --ck-font-share: 'MaruBuri', 'Noto Serif KR', serif;")
add('')
add('  /* 글자 위계: --ck-type-<이름> = font 단축(굵기 크기/줄높이 글꼴), 색은 따로(--ck-ink, sub·caption은 --ck-ink-soft) */')
weights = {'ui': 400, 'uiMedium': 500, 'uiBold': 600, 'uiTitle': 700}
for k, v in T['type'].items():
    if k.startswith('$'):
        continue
    w = weights[v['family']]
    lh = f"{v['lineHeight']}px" if v.get('lineHeight') else 'normal'
    add(f"  --ck-type-{kebab(k)}: {w} {v['size']}px/{lh} var(--ck-font-ui);")
add('')
add('  /* 간격 */')
for k, v in T['space'].items():
    if isinstance(v, dict):
        for k2, v2 in v.items():
            add(f"  --ck-{kebab(k)}-{kebab(k2)}: {v2}px;")
    else:
        add(f"  --ck-space-{kebab(k)}: {v}px;")
add('')
add('  /* 모서리 */')
for k, v in T['radius'].items():
    add(f"  --ck-radius-{kebab(k)}: {v}px;")
add('')
add('  /* 그림자(CSS 흐림 반경 그대로) */')
for k, v in T['shadow'].items():
    if k.startswith('$'):
        continue
    if isinstance(v, list):
        add(f"  --ck-shadow-{kebab(k)}: " + ', '.join(f"{s['x']}px {s['y']}px {s['blur']}px {s['color']}" for s in v) + ';')
    elif 'x' in v:
        add(f"  --ck-shadow-{kebab(k)}: {v['x']}px {v['y']}px {v['blur']}px {v['color']};")
add('  --ck-shadow-segmented-thumb: 0 1px 3px #191F2814;')
add('')
add('  /* 크기 */')
S = T['size']
for k, v in S['button'].items():
    add(f"  --ck-btn-{k}: {v}px;")
add(f"  --ck-touch: {S['iconButtonTouch']}px;")
add(f"  --ck-icon: {S['icon']['default']}px;")
add(f"  --ck-icon-stroke: {S['icon']['stroke']}px;")
add(f"  --ck-toggle-width: {S['toggle']['width']}px;")
add(f"  --ck-toggle-height: {S['toggle']['height']}px;")
add(f"  --ck-toggle-knob: {S['toggle']['knob']}px;")
add(f"  --ck-radio: {S['radioMark']}px;")
for k, v in S['tabBar'].items():
    add(f"  --ck-tabbar-{kebab(k)}: {v}px;")
add(f"  --ck-segmented-height: {S['segmented']['height']}px;")
add(f"  --ck-press-opacity: {T['motion']['pressOpacity']};")
add('}')
add('')
add('/* 바탕: 앱 화면과 같은 글꼴·글자색·흰 바탕, 자간 0 */')
add('html, body { background: var(--ck-bg); color: var(--ck-ink); font: var(--ck-type-body); letter-spacing: 0; -webkit-font-smoothing: antialiased; }')
open(os.path.join(OUT, 'styles.css'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')

# 글꼴: 앱이 쓰는 파일 그대로(flutter/assets/fonts). 웹 이름은 굵기로 한 가족에 묶는다
faces = [
    ('Pretendard', 400, 'Pretendard-Regular.otf', 'opentype'),
    ('Pretendard', 500, 'Pretendard-Medium.otf', 'opentype'),
    ('Pretendard', 600, 'Pretendard-SemiBold.otf', 'opentype'),
    ('Pretendard', 700, 'Pretendard-Bold.otf', 'opentype'),
    ('Noto Serif KR', 400, 'NotoSerifKR-Regular.otf', 'opentype'),
    ('Hahmlet', 600, 'Hahmlet-SemiBold.ttf', 'truetype'),
    ('MaruBuri', 400, 'MaruBuri-Regular.ttf', 'truetype'),
    ('MaruBuri', 600, 'MaruBuri-SemiBold.ttf', 'truetype'),
]
f = ['/* 책장 한켠 글꼴(flutter/assets/fonts, 모두 OFL) - tool/gen_design_css.py가 만든다 */']
for fam, w, file, fmt in faces:
    f.append(f"@font-face {{ font-family: '{fam}'; font-weight: {w}; font-style: normal; font-display: swap; src: url('../../assets/fonts/{file}') format('{fmt}'); }}")
open(os.path.join(OUT, 'fonts.css'), 'w', encoding='utf-8').write('\n'.join(f) + '\n')

# 변환기용 빈 패키지(컴포넌트 없는 토큰 디자인 시스템)
pkg = {'name': 'chaekjang-design-tokens', 'version': '0.1.0', 'private': True, 'description': '책장 한켠 디자인 토큰(Flutter 원본에서 생성)', 'main': 'index.js', 'module': 'index.js', 'style': 'styles.css'}
open(os.path.join(OUT, 'package.json'), 'w', encoding='utf-8').write(json.dumps(pkg, ensure_ascii=False, indent=2) + '\n')
open(os.path.join(OUT, 'index.js'), 'w', encoding='utf-8').write('// 컴포넌트 없음: 책장 한켠 위젯은 Flutter라 웹 번들로 옮기지 않는다(토큰·글꼴·지침만)\nexport {};\n')
print('wrote', OUT)
