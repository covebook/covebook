# 책장 머리 아이콘(꾸미기 · 추가 · 프로필)을 사용자 그림(tool/header_art/header-clay.png: 흰 바탕 위 흰 점토 붓·+·사람)에서 만든다(2026-11-18).
# 바탕(254)과의 어둡기 차이를 투명도로, 색은 가장 어두운 그늘 색으로: 흰 머리줄 위에서 원본과 같은 밝기로 보인다.
# 세 그림을 같은 배율로 잘라(정사각 490px, 몸통 가운데 기준) 1x/2x/3x(37·74·111px)로 assets/header/{decorate,add,profile}.png에 쓴다
import os
import numpy as np
from PIL import Image

root = os.path.dirname(os.path.abspath(__file__))
src = np.asarray(Image.open(os.path.join(root, 'header_art', 'header-clay.png')).convert('RGB')).astype(np.float32)
L = src.mean(2)
bg = float(np.median(L[:20, :]))
dark = L < 170
c = src[dark].mean(0) if dark.any() else np.array([110.0, 104.0, 98.0])
lo = float(L.min())
alpha = np.clip((bg - L) / (bg - c.mean()), 0, 1)
side = 490
# 몸통 가운데(그림자 빼고): 붓 · + · 사람
centers = {'decorate': (405, 350), 'add': (997, 350), 'profile': (1587, 372)}
out = os.path.join(root, '..', 'assets', 'header')
for name, (cx, cy) in centers.items():
    x0, y0 = cx - side // 2, cy - side // 2
    a = alpha[y0:y0 + side, x0:x0 + side]
    rgba = np.zeros((side, side, 4), np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = c[0], c[1], c[2]
    rgba[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    im = Image.fromarray(rgba, 'RGBA')
    for d, px in (('', 37), ('2.0x', 74), ('3.0x', 111)):
        path = os.path.join(out, d, f'{name}.png') if d else os.path.join(out, f'{name}.png')
        im.resize((px, px), Image.LANCZOS).save(path)
print('bg', bg, 'shade', [round(v) for v in c], 'min', lo)
