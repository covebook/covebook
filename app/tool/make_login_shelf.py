# 로그인 화면 맨 위 책장 그림(assets/login/shelf.webp)을 우리 앱이 그린 책장 사진에서 만든다(2026-11-18 사용자: 선반 사진은 언제든 바꿀 수 있게, 우리 것으로).
# 바꾸는 법: 새 책장을 앱에서 찍어 tool/login_art/home-capture.png(1080×2400 화면 사진)로 두고 이 스크립트를 돌린다.
#   python3 tool/make_login_shelf.py [사진 경로]
# 찍은 사진에서 책장 틀 위 끝(가운데 세로줄 밝기)과 두 번째 선반 판(나무색 띠) 아래 끝을 찾아 그 사이를 자르고,
# 판 아래에는 흰 바탕으로 사라지는 옅은 그림자를 더한다(판 밑 벽까지 자르면 회색 띠가 남았다)
import os, sys
import numpy as np
from PIL import Image

root = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'login_art', 'home-capture.png')
im = Image.open(src).convert('RGB')
a = np.asarray(im).astype(int)
L = a.mean(2)
W = im.width
cx = W // 2
# 틀 위 끝: 머리줄 아래에서 처음 어두워지는 곳
top = next(y for y in range(150, 900) if L[y, cx] < 250) - 14
# 나무색 띠(판): R−B가 크고 밝은 줄 묶음 중 두 번째
wood = [y for y in range(top, a.shape[0]) if a[y, cx, 0] - a[y, cx, 2] > 35 and a[y, cx, 0] > 200]
bands = []
for y in wood:
    if bands and y == bands[-1][1] + 1:
        bands[-1][1] = y
    elif not bands or y > bands[-1][1] + 1:
        bands.append([y, y])
bands = [b for b in bands if b[1] - b[0] >= 20]
bottom = bands[1][1] + 1
crop = a[top:bottom].astype(float)
# 판 아래 그림자(틀 안 폭만): 바탕 흰색 위 옅은 회색이 아래로 사라진다
row = L[(top + bottom) // 2]
xs = [x for x in range(W) if row[x] < 250]
x0, x1 = xs[0], xs[-1]
pad = 28
shade = np.full((pad, W, 3), 255.0)
for i in range(pad):
    k = 0.10 * (1 - i / pad) ** 2
    shade[i, x0:x1 + 1] = 255 * (1 - k)
out = np.concatenate([crop, shade]).clip(0, 255).astype(np.uint8)
dst = os.path.join(root, '..', 'assets', 'login', 'shelf.webp')
Image.fromarray(out).save(dst, 'WEBP', quality=90, method=6)
print('top', top, 'bottom', bottom, 'size', out.shape[1], out.shape[0], os.path.getsize(dst), 'bytes')
