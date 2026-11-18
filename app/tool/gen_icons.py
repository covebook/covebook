# 화면 아이콘 표(lib/gen/lucide.g.dart)를 Lucide 아이콘(ISC, lucide-static 1.75.0, tool/lucide_icons/)으로 만든다.
# 2026-11-17 Tabler로 통일했다가, 2026-11-18 사용자 'lucide.dev 아이콘으로 바꿔'. 하단 탭·책장 머리 입체 아이콘은 그대로(따로 그린 그림).
# 이름은 부르는 곳의 이름(예전 lucide 컴포넌트 이름) 그대로. 새 아이콘은 아래 표에 더하고 SVG를 tool/lucide_icons/에 넣는다
#   (https://cdn.jsdelivr.net/npm/lucide-static@1.75.0/icons/<이름>.svg).
#   쓰는 법: python3 tool/gen_icons.py
import os, re

NAMES = {
    'BookMarked': 'book-marked', 'BookOpen': 'book-open', 'Bookmark': 'bookmark', 'Camera': 'camera', 'Check': 'check',
    'ChevronDown': 'chevron-down', 'ChevronLeft': 'chevron-left', 'ChevronRight': 'chevron-right', 'ChevronUp': 'chevron-up',
    'Eraser': 'eraser', 'MoreHorizontal': 'ellipsis', 'MoreVertical': 'ellipsis-vertical', 'Paintbrush': 'paintbrush', 'PenLine': 'pen-line',
    'Play': 'play', 'Timer': 'timer', 'Plus': 'plus', 'Search': 'search', 'Settings': 'settings', 'Star': 'star',
    'Undo2': 'undo-2', 'Volume2': 'volume-2', 'VolumeX': 'volume-x', 'X': 'x', 'Share': 'share',
    'UserRound': 'user-round', 'Heart': 'heart', 'MessageCircle': 'message-circle', 'LayoutGrid': 'layout-grid',
    # 목록 보기는 세 줄(2026-11-17 내 책 시안): Lucide 'menu'
    'ListIcon': 'menu',
    'SlidersHorizontal': 'sliders-horizontal', 'StickyNote': 'sticky-note', 'MoveDiagonal2': 'move-diagonal-2',
    'ScanBarcode': 'scan-barcode', 'FileSpreadsheet': 'file-spreadsheet', 'AudioLines': 'audio-lines',
}

root = os.path.dirname(os.path.abspath(__file__))
src_dir = os.path.join(root, 'lucide_icons')
lines = []
for name, f in NAMES.items():
    s = open(os.path.join(src_dir, f + '.svg')).read()
    body = re.search(r'<svg[^>]*>(.*)</svg>', s, re.S).group(1)
    body = re.sub(r'<!--.*?-->', '', body, flags=re.S)
    body = re.sub(r'\s+', ' ', body).replace(' />', '/>').replace('> <', '><').strip()
    lines.append(f"  '{name}': '<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"{{c}}\" stroke-width=\"{{w}}\" stroke-linecap=\"round\" stroke-linejoin=\"round\">{body}</svg>',")

out = os.path.join(root, '..', 'lib', 'gen', 'lucide.g.dart')
open(out, 'w').write("""// 화면 아이콘: Lucide(ISC, lucide-static 1.75.0, tool/lucide_icons/LICENSE). tool/gen_icons.py 가 만든다 — 손으로 고치지 말 것.
// 2026-11-17 Tabler로 바꿨다가 2026-11-18 다시 Lucide(사용자 'lucide.dev 아이콘으로')
library;

/// 이름 → SVG({c} 색, {w} 선 굵기)
const lucideSvg = <String, String>{
""" + '\n'.join(lines) + '\n};\n')
print(len(lines), 'icons')
