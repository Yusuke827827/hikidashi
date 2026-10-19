"""App Store 用の宣伝画像を作る。scripts/screenshots.sh が撮った画面写真に、見出しと背景を付ける。
   python3 scripts/store_shots.py [画面写真のフォルダ（既定: screenshots）] [出力先（既定: screenshots/store）]
   出力: store/ja/1.png 〜 5.png、store/en/1.png 〜 5.png（1320x2868。6.9 インチの iPhone 用）
   見出しの書体は Mac ならヒラギノ、無ければ IPA ゴシックなどを使う（Pillow が必要）。"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
SRC = sys.argv[1] if len(sys.argv) > 1 else "screenshots"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(SRC, "store")

FONTS = [
    "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
]

# (画面写真, 見出し 1 行目, 2 行目, 背景の上の色, 下の色)
SETS = {
    "ja": [
        ("01-plain-light", "しまっておけば、", "必要なときに出てくる", 0xD86348, 0xB0402A),
        ("03-recall", "「これから〇〇する」で", "役立つメモが出てくる", 0x3C5A8A, 0x23395E),
        ("04-washi", "AI がフォルダと", "使う場面を自動で付ける", 0x8A6A3C, 0x5E4626),
        ("07-night", "11 種類の壁紙で", "自分好みに", 0x1B2A55, 0x0B1430),
        ("09-settings", "メモは端末の中だけ", "あなたの API キーで動く", 0x3B5E4A, 0x24402F),
    ],
    "en": [
        ("11-en-light", "Save it once.", "It finds you when it matters.", 0xD86348, 0xB0402A),
        ("12-en-recall", "Say what you're doing.", "Get the tips that help.", 0x3C5A8A, 0x23395E),
        ("13-en-washi", "Filed for you:", "folders, moments, reminders", 0x8A6A3C, 0x5E4626),
        ("14-en-night", "Eleven wallpapers", "to make it yours", 0x1B2A55, 0x0B1430),
        ("15-en-settings", "Private by design.", "Runs on your own API key.", 0x3B5E4A, 0x24402F),
    ],
}


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def font(size):
    for path in FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)


def gradient(top, bottom):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    a, b = rgb(top), rgb(bottom)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3)))
    return img


def fit_text(d, text, max_w, size):
    f = font(size)
    while d.textlength(text, font=f) > max_w and size > 40:
        size -= 4
        f = font(size)
    return f


def make(shot_path, line1, line2, top, bottom, out_path):
    img = gradient(top, bottom)
    d = ImageDraw.Draw(img)
    for i, (text, size) in enumerate(((line1, 104), (line2, 104))):
        f = fit_text(d, text, W - 160, size)
        tw = d.textlength(text, font=f)
        d.text(((W - tw) / 2, 190 + i * 150), text, font=f, fill=(255, 255, 255))

    shot = Image.open(shot_path).convert("RGB")
    sw = 1000
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), radius=96, fill=255)
    x, y = (W - sw) // 2, 600

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 30, x + sw, y + sh + 30), radius=96, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    img.paste(shadow, (0, 0), shadow)
    img.paste(shot, (x, y), mask)
    # 画面の縁（端末の枠の代わりの細い線）
    ImageDraw.Draw(img).rounded_rectangle((x - 6, y - 6, x + sw + 6, y + sh + 6), radius=102, outline=(255, 255, 255), width=6)
    img.save(out_path)


def main():
    made = 0
    for lang, items in SETS.items():
        os.makedirs(os.path.join(OUT, lang), exist_ok=True)
        for i, (name, l1, l2, top, bottom) in enumerate(items, 1):
            src = os.path.join(SRC, name + ".png")
            if not os.path.exists(src):
                print("skip (no screenshot):", src)
                continue
            dst = os.path.join(OUT, lang, f"{i}.png")
            make(src, l1, l2, top, bottom, dst)
            print("saved", dst)
            made += 1
    if made == 0:
        sys.exit("no screenshots found in " + SRC)


if __name__ == "__main__":
    main()
