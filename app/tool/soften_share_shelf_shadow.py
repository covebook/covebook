# 책 공유 카드 바탕(assets/share/plate.png)의 선반 판 아래 그림자를 시안 진하기로 옅게 한다(2026-11-18 사용자: 시안보다 하단바 그림자가 진하다).
# 측정(화면 1080폭): 시안 판 바로 아래 가장 어두운 곳 172, 우리 153(바탕 약 244) → 어두운 정도 72/91 ≈ 0.79.
# 그림자 양은 흐린 밝기로 잰다(벽 질감까지 재면 열마다 달라 세로 줄무늬가 생겼다). 밝히는 양만 더하므로 벽 질감은 그대로다.
# 띠 끝으로 갈수록 원래대로(이음매 없게). 한 번만 돌린다(다시 돌리면 더 옅어진다)
#   python3 tool/soften_share_shelf_shadow.py
import os
import numpy as np
from PIL import Image, ImageFilter

SCALE = 0.78
BAND = 90
root = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, '..', 'assets', 'share', 'plate.png')
img = Image.open(p).convert('RGB')
a = np.asarray(img).astype(float)
H, W = a.shape[:2]
wood = (a[..., 0] - a[..., 2] > 25) & (a[..., 0] > 200)
cols = np.where(wood.any(0))[0]
x0, x1 = cols.min(), cols.max()
# 판 아래 끝(열마다, 가운데값으로 매끈하게)
bottom = np.array([np.where(wood[:, x])[0].max() + 1 for x in range(x0, x1 + 1)])
y0 = int(np.median(bottom))
blur = np.asarray(img.convert('L').filter(ImageFilter.GaussianBlur(6))).astype(float)
ref = np.median(blur[y0 + BAND:y0 + BAND + 20, x0:x1 + 1])   # 띠 아래 벽 밝기
out = a.copy()
for y in range(y0, min(H, y0 + BAND)):
    t = (y - y0) / BAND
    keep = SCALE + (1 - SCALE) * t * t
    for x in range(max(0, x0 - 40), min(W, x1 + 41)):
        # 판 양 끝 밖으로는 서서히 줄인다
        edge = 1.0 if x0 <= x <= x1 else max(0.0, 1 - min(abs(x - x0), abs(x - x1)) / 40)
        dark = ref - blur[y, x]
        if dark > 0:
            out[y, x] += dark * (1 - keep) * edge
Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(p)
print('softened', x0, x1, 'plank bottom', y0, 'wall', round(ref))
