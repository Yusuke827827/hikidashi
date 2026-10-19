"""アプリアイコン（1024x1024）を描く。引き出しから紙片が少しのぞく形。
   python3 scripts/make_icon.py  →  App/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
   配色は Flowa / Hikidashi と同じ朱色と生成り。角丸は iOS がかけるので、ここでは四角のまま描く。"""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 2048  # 2 倍で描いて縮める（線をなめらかにするため）
OUT = os.path.join(os.path.dirname(__file__), "..", "App/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

img = Image.new("RGB", (S, S))
top, bottom = (0xD8, 0x63, 0x48), (0xB0, 0x40, 0x2A)  # 朱色の縦グラデーション
px = img.load()
for y in range(S):
    c = lerp(top, bottom, y / (S - 1))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)

cream, cream_dark, ink = (0xF6, 0xF1, 0xE6), (0xE6, 0xDC, 0xC8), (0x3B, 0x2A, 0x22)

# 紙片（引き出しからのぞく。少し傾ける）
slip = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(slip)
sd.rounded_rectangle((760, 470, 1290, 1060), radius=36, fill=(255, 253, 248, 255))
for i, y in enumerate((590, 680, 770)):
    sd.rounded_rectangle((850, y, 1200 - i * 90, y + 34), radius=17, fill=(0xD8, 0x63, 0x48, 255))
slip = slip.rotate(-8, resample=Image.BICUBIC, center=(1024, 900))

# 影
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle((430, 930, 1618, 1650), radius=90, fill=(60, 20, 10, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(40))
img.paste(shadow, (0, 30), shadow)
img.paste(slip, (0, 0), slip)

# 引き出しの前板
d = ImageDraw.Draw(img)
d.rounded_rectangle((430, 900, 1618, 1620), radius=90, fill=cream)
d.rounded_rectangle((430, 900, 1618, 990), radius=40, fill=cream_dark)  # 上辺の厚み
d.rectangle((430, 950, 1618, 990), fill=cream_dark)
# 取っ手
d.rounded_rectangle((834, 1210, 1214, 1300), radius=45, fill=ink)
d.rounded_rectangle((874, 1236, 1174, 1262), radius=13, fill=(0x5A, 0x44, 0x38))

img = img.resize((1024, 1024), Image.LANCZOS)
img.save(OUT)
print("saved", os.path.normpath(OUT))
