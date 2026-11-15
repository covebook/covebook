# 책장 머리줄 프로필 입체 아이콘(assets/header/profile.png, 2.0x·3.0x). 다른 머리 아이콘(시안에서 오린 회색 점토 느낌)에 맞춰 만든다:
# 모양(머리 원 + 어깨) → 부드러운 높이 → 왼쪽 위 빛 → 회색 → 아래 그림자. 사용: cd flutter && python3 tool/gen_profile_icon.py
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
S=4; N=93*S
m=Image.new('L',(N,N),0); d=ImageDraw.Draw(m)
def c(v): return int(v*S)
d.ellipse([c(47-12.5),c(30-12.5),c(47+12.5),c(30+12.5)],fill=255)
d.rounded_rectangle([c(23),c(49),c(71),c(74)],radius=c(12),fill=255)
d.rounded_rectangle([c(23),c(62),c(71),c(74)],radius=c(3.5),fill=255)
mask=np.array(m).astype(float)/255
h=np.array(m.filter(ImageFilter.GaussianBlur(c(2.6)))).astype(float)/255
h=np.minimum(h,mask)
gy,gx=np.gradient(h*c(5))
nz=np.ones_like(h); nx=-gx; ny=-gy
ln=np.sqrt(nx*nx+ny*ny+nz*nz); nx/=ln; ny/=ln; nz/=ln
L=np.array([-0.45,-0.65,0.62]); L/=np.linalg.norm(L)
lam=np.clip(nx*L[0]+ny*L[1]+nz*L[2],0,1)
flat=L[2]
t=214+ (lam-flat)*120   # 평평한 곳 200, 빛 받는 모서리 밝게, 반대쪽 어둡게
t=np.clip(t,135,228)
sh=Image.fromarray((mask*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(c(3.2)))
sh=np.roll(np.array(sh).astype(float)/255,c(3.5),axis=0)
shadowA=sh*0.16
out=np.zeros((N,N,4))
bodyA=mask
# 그림자 위에 몸(검정 그림자 + 회색 몸), 미리 곱한 값으로 합성
A=bodyA+shadowA*(1-bodyA)
col=np.zeros((N,N,3))
tone=np.stack([t,t-1.5,t-4],axis=2)
pre=tone*bodyA[...,None]+0*shadowA[...,None]*(1-bodyA[...,None])
col=np.where(A[...,None]>1e-6,pre/np.maximum(A[...,None],1e-6),0)
out[...,:3]=col; out[...,3]=A*255
img=Image.fromarray(np.clip(out,0,255).astype(np.uint8))
for name,size in (('assets/header/3.0x/profile.png',93),('assets/header/2.0x/profile.png',62),('assets/header/profile.png',31)):
  img.resize((size,size),Image.LANCZOS).save(name)
