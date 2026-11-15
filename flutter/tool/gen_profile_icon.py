# 책장 머리줄 프로필 입체 아이콘(assets/header/profile.png, 1x·2.0x·3.0x).
# 다른 머리 아이콘(시안에서 오린 add·decorate 등)과 같은 방식으로 만든다: 흰 바탕 위에 덮는 '따뜻한 회색 그늘' 한 장
# (색은 거의 고정 (41,31,0), 진하기는 알파). 톤은 add.png를 잰 값에 맞춘다(2026-11-16 사용자 '사람 아이콘도 다른 아이콘이랑 비슷하게'):
#   윗면 226 · 위 모서리 248 · 왼 모서리 244 · 오른 모서리 202 · 아래 모서리 164 · 아래로 지는 그림자 188→253(약 10px)
# 사용: cd flutter && python3 tool/gen_profile_icon.py
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # 4배로 그려 줄인다
N = 93 * S


def c(v):
    return int(round(v * S))


# 모양: 머리 원 + 어깨(위가 둥근 판)
m = Image.new('L', (N, N), 0)
d = ImageDraw.Draw(m)
d.ellipse([c(47 - 11.5), c(18), c(47 + 11.5), c(41)], fill=255)
d.rounded_rectangle([c(24), c(47), c(70), c(73)], radius=c(12), fill=255)
d.rounded_rectangle([c(24), c(60), c(70), c(73)], radius=c(3.5), fill=255)
mask = np.array(m).astype(float) / 255

# 모서리 띠: 가장자리까지 거리(약 2.5px)와 바깥 법선으로 밝기를 더하고 뺀다
soft = np.array(m.filter(ImageFilter.GaussianBlur(c(1.6)))).astype(float) / 255
gy, gx = np.gradient(soft)
ln = np.hypot(gx, gy) + 1e-9
nx, ny = -gx / ln, -gy / ln          # 바깥을 향한 법선
edge = np.clip(1 - np.abs(soft - 0.5) * 2, 0, 1) ** 0.8   # 가장자리에서 1, 안쪽 평평한 곳에서 0
delta = np.where(nx > 0, -24 * nx, -18 * nx) + np.where(ny > 0, -60 * ny, -22 * ny)
face = 226 + delta * edge

# 아래(조금 오른쪽)로 지는 그림자: 몸을 흐려 내리고, 몸 밖에서만 보인다
sh = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(c(2.6)))
sh = np.array(sh).astype(float) / 255
sh = np.roll(np.roll(sh, c(3.2), axis=0), c(0.8), axis=1)
shadow = 255 - 70 * sh

gray = mask * face + (1 - mask) * shadow
gray = np.clip(gray, 0, 255)

# 흰 바탕 위 회색 → (41,31,0) 색 + 알파(add.png의 (255-T) 비율 R:G:B = 0.84:0.88:1)
dd = (255 - gray) / 0.907
alpha = np.clip(dd / 255, 0, 1)
out = np.zeros((N, N, 4))
out[..., 0] = 41
out[..., 1] = 31
out[..., 2] = 0
out[..., 3] = alpha * 255
img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA')
for name, size in (('assets/header/3.0x/profile.png', 93), ('assets/header/2.0x/profile.png', 62), ('assets/header/profile.png', 31)):
    img.resize((size, size), Image.LANCZOS).save(name)
