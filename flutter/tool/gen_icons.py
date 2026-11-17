# 화면 아이콘 표(lib/gen/lucide.g.dart)를 Tabler 아이콘(MIT, tool/tabler_icons/)으로 만든다.
# 2026-11-17 사용자 'Tabler로 통일': 24칸·같은 선 굵기라 화면마다 아이콘 굵기가 같다. 하단 탭·책장 머리 입체 아이콘은 그대로(따로 그린 그림).
# 이름은 예전 lucide 이름을 그대로 쓴다(부르는 곳은 바꾸지 않는다). 새 아이콘은 아래 표에 더하고 tool/tabler_icons/에 SVG를 넣는다.
#   쓰는 법: python3 tool/gen_icons.py [Tabler 꾸러미의 icons/outline 폴더 — 주면 필요한 SVG를 tool/tabler_icons/로 복사]
import os, re, shutil, sys

NAMES = {
    'BookMarked': 'book-2', 'BookOpen': 'book', 'Bookmark': 'bookmark', 'Camera': 'camera', 'Check': 'check',
    'ChevronDown': 'chevron-down', 'ChevronLeft': 'chevron-left', 'ChevronRight': 'chevron-right', 'ChevronUp': 'chevron-up',
    'Eraser': 'eraser', 'MoreHorizontal': 'dots', 'MoreVertical': 'dots-vertical', 'Paintbrush': 'brush', 'PenLine': 'pencil',
    'Play': 'player-play', 'Timer': 'stopwatch', 'Plus': 'plus', 'Search': 'search', 'Settings': 'settings', 'Star': 'star',
    'Undo2': 'arrow-back-up', 'Volume2': 'volume', 'VolumeX': 'volume-off', 'X': 'x', 'Share': 'share-2',
    'UserRound': 'user', 'Heart': 'heart', 'MessageCircle': 'message-circle', 'LayoutGrid': 'layout-grid', 'ListIcon': 'menu-2',
    'SlidersHorizontal': 'adjustments-horizontal', 'StickyNote': 'note', 'MoveDiagonal2': 'arrows-diagonal',
    'ScanBarcode': 'barcode', 'FileSpreadsheet': 'file-spreadsheet',
}

# Tabler에 없는 것만 예외로 직접(같은 24칸·선 굵기): 소리 막대는 lucide audio-lines(ISC) 모양 그대로(2026-11-17 읽기 장면 시안)
EXTRA = {
    'AudioLines': '<path d="M2 10v3"/><path d="M6 6v11"/><path d="M10 3v18"/><path d="M14 8v7"/><path d="M18 5v13"/><path d="M22 10v3"/>',
}

root = os.path.dirname(os.path.abspath(__file__))
src_dir = os.path.join(root, 'tabler_icons')
if len(sys.argv) > 1:
    for f in NAMES.values():
        shutil.copy(os.path.join(sys.argv[1], f + '.svg'), os.path.join(src_dir, f + '.svg'))

lines = []
for name, f in NAMES.items():
    s = open(os.path.join(src_dir, f + '.svg')).read()
    body = re.search(r'<svg[^>]*>(.*)</svg>', s, re.S).group(1)
    # 24칸 테두리 투명 상자는 뺀다(채우기 색을 줄 때 상자까지 칠해진다)
    body = re.sub(r'<path stroke="none" d="M0 0h24v24H0z" fill="none"\s*/>', '', body)
    body = re.sub(r'\s+', ' ', body).replace(' />', '/>').replace('> <', '><').strip()
    lines.append(f"  '{name}': '<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"{{c}}\" stroke-width=\"{{w}}\" stroke-linecap=\"round\" stroke-linejoin=\"round\">{body}</svg>',")

for name, body in EXTRA.items():
    lines.append(f"  '{name}': '<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"{{c}}\" stroke-width=\"{{w}}\" stroke-linecap=\"round\" stroke-linejoin=\"round\">{body}</svg>',")

out = os.path.join(root, '..', 'lib', 'gen', 'lucide.g.dart')
open(out, 'w').write("""// 화면 아이콘: Tabler Icons(MIT, tool/tabler_icons/LICENSE). tool/gen_icons.py 가 만든다 — 손으로 고치지 말 것.
// 이름은 예전 lucide 이름 그대로(부르는 곳을 바꾸지 않으려고). 2026-11-17 lucide → Tabler
library;

/// 이름 → SVG({c} 색, {w} 선 굵기)
const lucideSvg = <String, String>{
""" + '\n'.join(lines) + '\n};\n')
print(len(lines), 'icons')
