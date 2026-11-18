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

# 지난 책장 공유 아이콘(tool/header_art/share-art.png: 검은 바탕 위 흰 입체)도 점토 아이콘과 같은 모양으로(2026-11-18 사용자: 다른 아이콘처럼 그림자 더).
# 흰 바탕 위 점토처럼 밝기를 만든 뒤(면은 그림 밝기, 몸 밖은 아래로 지는 부드러운 그림자) 위와 같은 규칙(바탕과의 어둡기 차이 = 투명도, 색 = 그늘 색)으로 바꾼다
from PIL import ImageFilter
art = Image.open(os.path.join(root, 'header_art', 'share-art.png')).convert('L')
NS = 444
La = np.asarray(art.resize((NS, NS), Image.LANCZOS)).astype(np.float32)
m = np.clip((La - 90) / 70, 0, 1)
face = 150 + (np.clip(La, 150, 255) - 150) * 0.9
sh = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(16))).astype(np.float32) / 255
sh = np.roll(np.roll(sh, 20, axis=0), 8, axis=1)
gray = m * face + (1 - m) * (bg - 120 * sh)
a2 = np.clip((bg - gray) / (bg - c.mean()), 0, 1)
rgba = np.zeros((NS, NS, 4), np.uint8)
rgba[..., 0], rgba[..., 1], rgba[..., 2] = c[0], c[1], c[2]
rgba[..., 3] = (a2 * 255).astype(np.uint8)
im = Image.fromarray(rgba, 'RGBA')
for d, px in (('', 37), ('2.0x', 74), ('3.0x', 111)):
    im.resize((px, px), Image.LANCZOS).save(os.path.join(out, d, 'share.png') if d else os.path.join(out, 'share.png'))
print('share ok')
