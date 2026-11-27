# 로그인 · 로딩 책장 그림의 정면 표지 두 장을 직접 그린다(2026-11-27 사용자: 시판본 표지 『아몬드』 · 『코스모스』 대신 보호기간이 끝난 작품을 우리 그림으로).
# - 위 칸 『동백꽃』(김유정, 1936): 소설 속 '노란 동백꽃'(강원도 말로 생강나무 꽃) 가지. 크림 바탕, 갈색 가지에 노란 꽃송이, 세로 제목
# - 아래 칸 『메밀꽃 필 무렵』(이효석, 1936): '소금을 뿌린 듯이' 흰 메밀꽃 밭과 달밤. 남색 하늘, 큰 달, 언덕, 흰 꽃 점
# 글꼴은 앱에 든 마루부리(OFL). 책 크기는 바꾸기 전 책과 같은 비율(138×214 · 153×224mm)이라 책장 모양은 그대로다.
#   python3 tool/login_art/make_covers.py  →  tool/login_art/covers/{dongbaek,memil}.png
import math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = os.path.dirname(os.path.abspath(__file__))
fonts = os.path.join(root, '..', '..', 'assets', 'fonts')
out = os.path.join(root, 'covers')
os.makedirs(out, exist_ok=True)
K = 2  # 두 배로 그려 줄인다(가장자리 매끈하게)


def font(name, size):
    return ImageFont.truetype(os.path.join(fonts, name), size * K)


def grain(im, amount, seed):
    """종이 결: 아주 옅은 잡음"""
    rnd = random.Random(seed)
    n = Image.effect_noise(im.size, 64).convert('L')
    n = n.point(lambda v: 128 + (v - 128) * amount)
    return Image.composite(im, Image.blend(im, Image.merge('RGB', (n, n, n)), 0.06), Image.new('L', im.size, 200 + rnd.randint(0, 10)))


def vertical(d, text, x, y, f, fill, gap):
    for ch in text:
        w = d.textlength(ch, font=f)
        d.text((x - w / 2, y), ch, font=f, fill=fill)
        y += f.size + gap
    return y


# ---------- 동백꽃 ----------
W, H = 690 * K, 1070 * K
im = Image.new('RGB', (W, H), (243, 235, 219))
d = ImageDraw.Draw(im)
rnd = random.Random(11)
# 가지: 왼쪽 아래에서 오른쪽 위로 휘는 굵은 가지 + 잔가지
def branch(p0, p1, p2, w0, w1, col=(86, 62, 44)):
    pts = []
    for i in range(401):
        t = i / 400
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y, w0 + (w1 - w0) * t))
    for (x, y, w) in pts:
        d.ellipse((x - w, y - w, x + w, y + w), fill=col)
    return pts

main = branch((-40 * K, 900 * K), (260 * K, 700 * K), (470 * K, 300 * K), 15 * K, 5 * K)
twigs = [
    branch((180 * K, 760 * K), (150 * K, 600 * K), (90 * K, 470 * K), 7 * K, 3 * K),
    branch((330 * K, 560 * K), (400 * K, 520 * K), (490 * K, 530 * K), 6 * K, 2.5 * K),
    branch((410 * K, 400 * K), (380 * K, 300 * K), (330 * K, 210 * K), 5 * K, 2 * K),
    branch((250 * K, 680 * K), (330 * K, 700 * K), (400 * K, 760 * K), 5 * K, 2 * K),
]
# 꽃송이: 가지를 따라 작은 노란 꽃(둥근 꽃잎 넷) 뭉치
def cluster(cx, cy, n, r):
    for _ in range(n):
        a = rnd.uniform(0, math.tau)
        dist = rnd.uniform(0, r)
        x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist
        s = rnd.uniform(7, 12) * K
        col = rnd.choice([(232, 185, 58), (240, 199, 78), (222, 168, 40), (245, 210, 100)])
        for k in range(4):
            b = k * math.pi / 2 + rnd.uniform(0, 0.6)
            px, py = x + math.cos(b) * s * 0.55, y + math.sin(b) * s * 0.55
            d.ellipse((px - s * 0.5, py - s * 0.5, px + s * 0.5, py + s * 0.5), fill=col)
        d.ellipse((x - s * 0.18, y - s * 0.18, x + s * 0.18, y + s * 0.18), fill=(176, 120, 30))

for pts, every in [(main, 60), *[(t, 90) for t in twigs]]:
    for i in range(6, len(pts), every):
        x, y, _ = pts[i]
        cluster(x + rnd.uniform(-10, 10) * K, y + rnd.uniform(-14, 6) * K, rnd.randint(4, 8), 22 * K)
# 제목(세로, 오른쪽) · 지은이
ink = (59, 42, 32)
ft = font('MaruBuri-SemiBold.ttf', 92)
y = vertical(d, '동백꽃', W - 118 * K, 120 * K, ft, ink, 18 * K)
fa = font('MaruBuri-Regular.ttf', 30)
vertical(d, '김유정', W - 118 * K, y + 40 * K, fa, (110, 86, 66), 8 * K)
# 아래 작은 줄
fs = font('MaruBuri-Regular.ttf', 22)
d.text((60 * K, H - 92 * K), '단편소설 · 1936', font=fs, fill=(140, 116, 92))
im = im.filter(ImageFilter.GaussianBlur(0.6 * K)).resize((W // K, H // K), Image.LANCZOS)
grain(im, 0.5, 1).save(os.path.join(out, 'dongbaek.png'))

# ---------- 메밀꽃 필 무렵 ----------
W, H = 765 * K, 1120 * K
im = Image.new('RGB', (W, H))
d = ImageDraw.Draw(im)
top, bot = (24, 33, 62), (49, 66, 104)
for yy in range(H):
    t = yy / H
    d.line((0, yy, W, yy), fill=tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
# 달(번진 빛 + 둥근 달)
glow = Image.new('L', (W, H), 0)
gd = ImageDraw.Draw(glow)
mx, my, mr = 540 * K, 300 * K, 92 * K
gd.ellipse((mx - mr * 2.2, my - mr * 2.2, mx + mr * 2.2, my + mr * 2.2), fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(60 * K))
im = Image.composite(Image.new('RGB', (W, H), (236, 228, 200)), im, glow)
d = ImageDraw.Draw(im)
d.ellipse((mx - mr, my - mr, mx + mr, my + mr), fill=(244, 237, 214))
# 별 몇 개
rnd = random.Random(5)
for _ in range(40):
    x, y = rnd.uniform(0, W), rnd.uniform(0, 520 * K)
    if math.hypot(x - mx, y - my) < mr * 1.8:
        continue
    s = rnd.uniform(1, 2.4) * K
    d.ellipse((x - s, y - s, x + s, y + s), fill=(220, 222, 235))
# 먼 산 · 가까운 언덕(겹)
def hill(base, amp, ph, col):
    pts = [(0, H)]
    for xx in range(0, W + 8, 8):
        pts.append((xx, base + amp * math.sin(xx / W * math.pi * 1.6 + ph) + amp * 0.35 * math.sin(xx / W * math.pi * 4.1 + ph * 2)))
    pts.append((W, H))
    d.polygon(pts, fill=col)

hill(640 * K, 34 * K, 0.4, (36, 48, 80))
hill(720 * K, 26 * K, 2.1, (42, 58, 92))
hill(800 * K, 18 * K, 1.0, (50, 70, 104))
# 메밀꽃 밭: 아래로 갈수록 크고 촘촘한 흰 꽃 점(달빛에 소금을 뿌린 듯)
for _ in range(5200):
    y = rnd.uniform(790 * K, H)
    t = (y - 790 * K) / (H - 790 * K)
    x = rnd.uniform(0, W)
    s = (0.9 + 2.6 * t) * K * rnd.uniform(0.7, 1.3)
    c = rnd.randint(205, 248)
    d.ellipse((x - s, y - s * 0.8, x + s, y + s * 0.8), fill=(c, c, min(255, c + 6)))
# 밭 사이 오솔길(옅은 띠)
path = Image.new('L', (W, H), 0)
pd = ImageDraw.Draw(path)
for i in range(80):
    t = i / 79
    x = 200 * K + 260 * K * math.sin(t * 2.2) * (1 - t * 0.3)
    y = 800 * K + (H - 800 * K) * t
    w = (6 + 40 * t) * K
    pd.ellipse((x - w, y - w * 0.35, x + w, y + w * 0.35), fill=90)
path = path.filter(ImageFilter.GaussianBlur(8 * K))
im = Image.composite(Image.new('RGB', (W, H), (150, 160, 190)), im, path)
d = ImageDraw.Draw(im)
# 제목 · 지은이(위 왼쪽, 흰 글자)
ft = font('MaruBuri-SemiBold.ttf', 74)
d.text((64 * K, 92 * K), '메밀꽃', font=ft, fill=(246, 242, 230))
d.text((64 * K, 92 * K + 96 * K), '필 무렵', font=ft, fill=(246, 242, 230))
fa = font('MaruBuri-Regular.ttf', 30)
d.text((68 * K, 92 * K + 212 * K), '이효석', font=fa, fill=(196, 202, 220))
im = im.resize((W // K, H // K), Image.LANCZOS)
grain(im, 0.5, 2).save(os.path.join(out, 'memil.png'))
print('ok', os.listdir(out))
