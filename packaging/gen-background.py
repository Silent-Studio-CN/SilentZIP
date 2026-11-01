#!/usr/bin/env python3
"""生成 DMG 背景图 —— Silent 风格：近黑底 + 冷蓝环标 + 极简排版
   输出 2x（1240×800），DMG 窗口 620×400 时按 Retina 显示
"""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import os
W, H = 620, 400
S = int(os.environ.get("SCALE", "2"))
BG_TOP    = (13, 13, 16)
BG_BOTTOM = (22, 22, 27)
ACCENT    = (76, 140, 220)     # #4C8CDC
INK       = (237, 237, 239)
DIM       = (120, 120, 132)

def font(size, weight="regular"):
    paths = {
        "bold":    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "regular": "/System/Library/Fonts/Supplemental/Arial.ttf",
        "cn":      "/System/Library/Fonts/Hiragino Sans GB.ttc",
    }
    for p in (paths.get(weight), paths["cn"], paths["regular"]):
        if p:
            try: return ImageFont.truetype(p, size)
            except Exception: continue
    return ImageFont.load_default()

img = Image.new("RGB", (W*S, H*S), BG_TOP)
d = ImageDraw.Draw(img)

# 垂直渐变
for y in range(H*S):
    t = y / (H*S - 1)
    c = tuple(int(BG_TOP[i] + (BG_BOTTOM[i]-BG_TOP[i]) * t) for i in range(3))
    d.line([(0, y), (W*S, y)], fill=c)

# 左上角冷蓝光晕（直接逐像素加，不用 blend，避免偏色）
px = img.load()
gx, gy, gr = W*S*0.10, H*S*0.02, H*S*1.15
for y in range(H*S):
    for x in range(0, W*S, 2):
        dx, dy = x-gx, y-gy
        dist = math.hypot(dx, dy) / gr
        if dist >= 1: continue
        k = (1 - dist) ** 2.4
        r, g, b = px[x, y]
        px[x, y] = (min(255, int(r + 26*k)),
                    min(255, int(g + 46*k)),
                    min(255, int(b + 92*k)))
        if x+1 < W*S:
            px[x+1, y] = px[x, y]
d = ImageDraw.Draw(img)

# ── 左上：环标（环 + 六边形 + 双弧 + 刻点）──
cx, cy, R = 78*S, 62*S, 26*S
for i in range(36):
    a = math.radians(i*10 - 90)
    long_tick = (i % 3 == 0)
    r1, r2 = R + 5*S, R + (11*S if long_tick else 8*S)
    col = ACCENT if long_tick else (70, 70, 80)
    d.line([(cx+math.cos(a)*r1, cy+math.sin(a)*r1),
            (cx+math.cos(a)*r2, cy+math.sin(a)*r2)], fill=col, width=S)
d.ellipse([cx-R, cy-R, cx+R, cy+R], outline=(46, 60, 88), width=S)
# 六边形
hexR = R*0.62
pts = [(cx+math.cos(math.radians(-90+60*i))*hexR,
        cy+math.sin(math.radians(-90+60*i))*hexR) for i in range(7)]
d.line(pts, fill=INK, width=int(2.0*S), joint="curve")
# 中间一横
d.line([(cx-hexR*0.45, cy), (cx+hexR*0.45, cy)], fill=INK, width=int(2.0*S))

# ── 标题 ──
d.text((128*S, 44*S), "SilentZIP", font=font(int(26*S), "bold"), fill=INK)
d.text((130*S, 80*S), "拖到「应用程序」文件夹即可完成安装",
       font=font(int(12*S), "cn"), fill=DIM)

# ── 拖拽箭头 ──
ay = 210*S
x1, x2 = 236*S, 384*S
col = (58, 58, 68)
d.line([(x1, ay), (x2-14*S, ay)], fill=col, width=int(2*S))
d.polygon([(x2, ay), (x2-16*S, ay-8*S), (x2-16*S, ay+8*S)], fill=col)
for i in range(6):
    dx = x1 + (x2-x1-20*S) * (i/6)
    d.ellipse([dx-1.5*S, ay-1.5*S, dx+1.5*S, ay+1.5*S], fill=(70,70,84))

# ── 底部 ──
d.text((W*S//2, 366*S), "首次打开会自动接管 7z / zip / rar / tar 等压缩包",
       font=font(int(10*S), "cn"), fill=(92, 92, 104), anchor="mm")
d.text((W*S//2, 384*S), "Silent Studio",
       font=font(int(9*S), "regular"), fill=(62, 62, 72), anchor="mm")

out = sys.argv[1] if len(sys.argv) > 1 else "background.png"
img.save(out, "PNG")
print(f"  {out}  {img.size[0]}x{img.size[1]}")
