# 화면 아이콘 표(lib/gen/lucide.g.dart)를 Lucide 아이콘(ISC, tool/lucide_icons/)으로 만든다.
# 아이콘은 처음 앱(지금 앱 lucide-react-native 1.48.0)과 같은 그림: 처음 옮긴 34개는 그때 표 그대로, 그 뒤 더한 것(ScanBarcode·FileSpreadsheet)과
# 목록 보기 세 줄(menu)은 같은 1.48.0에서. 2026-11-17 Tabler → 11-18 lucide-static 1.75.0 → 11-19 사용자 '처음 썼던 걸로'(목록 세 줄은 그대로).
# 하단 탭·책장 머리 입체 아이콘은 그대로(따로 그린 그림).
# 이름은 부르는 곳의 이름(예전 lucide 컴포넌트 이름) 그대로. 새 아이콘은 아래 표에 더하고 lucide-react-native 1.48.0의 같은 아이콘 SVG를 tool/lucide_icons/에 넣는다
#   (https://cdn.jsdelivr.net/npm/lucide-static@1.48.0/icons/<이름>.svg).
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
    # 2026-11-21: 검색 닫기 화살표(내 책 · 기록 검색), 책 정보 수정 시안의 표지 연필 · 표지 바꾸기 · 표지 삭제
    'ArrowLeft': 'arrow-left', 'Pencil': 'pencil', 'Image': 'image', 'Trash2': 'trash-2',
    # 2026-11-21: 인터넷 연결 없음 화면
    'WifiOff': 'wifi-off',
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
open(out, 'w').write("""// 화면 아이콘: Lucide(ISC, 처음 앱과 같은 lucide 1.48.0, tool/lucide_icons/LICENSE). tool/gen_icons.py 가 만든다 — 손으로 고치지 말 것.
// 2026-11-17 Tabler → 11-18 lucide-static 1.75.0 → 11-19 처음 썼던 아이콘으로(사용자)
library;

/// 이름 → SVG({c} 색, {w} 선 굵기)
const lucideSvg = <String, String>{
""" + '\n'.join(lines) + '\n};\n')
print(len(lines), 'icons')
