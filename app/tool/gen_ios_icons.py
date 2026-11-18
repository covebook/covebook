# iOS 앱 아이콘 세트를 우리 아이콘 원본(tool/app_icon/icon-1024.png, 지금 Android 런처·Play와 같은 그림)에서 만든다.
# 2026-11-18: Flutter로 옮길 때 iOS 아이콘이 Flutter 기본 로고로 남아 TestFlight에 그대로 올라갔다. 아이콘을 바꾸면 원본만 바꾸고 다시 돌린다.
# 사용: python3 tool/gen_ios_icons.py  (app/에서)
import json
from pathlib import Path

from PIL import Image

SRC = Path('tool/app_icon/icon-1024.png')
SET = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')

src = Image.open(SRC).convert('RGB')  # App Store 아이콘은 투명 금지
assert src.size == (1024, 1024), src.size
for img in json.loads((SET / 'Contents.json').read_text())['images']:
    side = round(float(img['size'].split('x')[0]) * int(img['scale'].rstrip('x')))
    out = src if side == 1024 else src.resize((side, side), Image.LANCZOS)
    out.save(SET / img['filename'], optimize=True)
    print(img['filename'], side)
