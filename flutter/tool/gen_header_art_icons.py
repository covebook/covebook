# 사용자가 준 입체 아이콘 그림(tool/header_art/*-art.png: 검은 바탕 위 흰 입체)을 다른 책장 머리 아이콘과 같은 방식
# (흰 바탕 위에 덮는 따뜻한 회색 그늘 한 장, 색 (41,31,0) + 알파)으로 바꾼다. 2026-11-17 사용자 '책장 사람 아이콘이랑 과거 책장 공유 아이콘 이거 써'.
# 면 밝기는 그림 그대로(윗면 약 225 = add.png 윗면 226과 같은 톤), 몸 밖은 다른 머리 아이콘처럼 아래로 지는 그림자를 새로 그린다(검은 바탕의 빛 번짐은 버린다).
# 사용: cd flutter && python3 tool/gen_header_art_icons.py
import numpy as np
from PIL import Image, ImageFilter

for name in ('profile', 'share'):
    src = Image.open(f'tool/header_art/{name}-art.png').convert('L')
    N = 372                                   # 93의 4배로 다룬 뒤 줄인다
    L = np.array(src.resize((N, N), Image.LANCZOS)).astype(float)
    # 몸: 밝은 곳(빛 번짐 10~60은 빼고 가장자리는 부드럽게)
    m = np.clip((L - 90) / 70, 0, 1)
    face = np.clip(L, 150, 255)
    # 아래로 지는 그림자(gen_profile_icon.py와 같은 값): 몸을 흐려 내리고 몸 밖에서만
    sh = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10))).astype(float) / 255
    sh = np.roll(np.roll(sh, 13, axis=0), 3, axis=1)
    shadow = 255 - 70 * sh
    gray = np.clip(m * face + (1 - m) * shadow, 0, 255)
    dd = (255 - gray) / 0.907
    out = np.zeros((N, N, 4))
    out[..., 0], out[..., 1], out[..., 2] = 41, 31, 0
    out[..., 3] = np.clip(dd / 255, 0, 1) * 255
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')
    for path, size in ((f'assets/header/3.0x/{name}.png', 93), (f'assets/header/2.0x/{name}.png', 62), (f'assets/header/{name}.png', 31)):
        img.resize((size, size), Image.LANCZOS).save(path)
    print(name, 'ok')
