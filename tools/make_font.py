"""產生像素點陣字型：assets/fonts/pixel.png + assets/fonts/pixel.fnt（AngelCode BMFont 文字格式）。

涵蓋 ASCII 32–126。字形 5×7（定義在 art_common.GLYPHS），字距 1 px（xadvance 6），行高 8。
小寫字母沿用大寫字形。字是白色，在 Godot 裡用 modulate / font_color 上色。
Godot 會把 .fnt 匯入成 FontFile；Label 的字級設成 8 才會 1:1 清晰顯示。

用法：python3 tools/make_font.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from art_common import Canvas, glyph  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts")
CELL_W, CELL_H = 6, 8  # 圖集中每格大小（字 5×7 + 1 px 間隔）
GLYPH_W, GLYPH_H = 5, 7
COLS = 16
LINE_HEIGHT = 8
BASE = 7


def main():
    os.makedirs(OUT, exist_ok=True)
    chars = list(range(32, 127))
    rows = (len(chars) + COLS - 1) // COLS
    w, h = COLS * CELL_W, rows * CELL_H
    cv = Canvas(w, h)
    lines = []
    for idx, code in enumerate(chars):
        cx = (idx % COLS) * CELL_W
        cy = (idx // COLS) * CELL_H
        for j, row in enumerate(glyph(chr(code))):
            for i, b in enumerate(row):
                if b == "#":
                    cv.set(cx + i, cy + j, (255, 255, 255, 255))
        lines.append(
            f"char id={code:<4} x={cx:<5} y={cy:<5} width={GLYPH_W:<5} height={GLYPH_H:<5} "
            f"xoffset=0     yoffset=0     xadvance={GLYPH_W + 1:<5} page=0  chnl=15")
    cv.save(os.path.join(OUT, "pixel.png"))
    fnt = [
        'info face="Newt Pixel" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        'padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={LINE_HEIGHT} base={BASE} scaleW={w} scaleH={h} pages=1 packed=0 "
        "alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4",
        'page id=0 file="pixel.png"',
        f"chars count={len(chars)}",
        *lines,
    ]
    with open(os.path.join(OUT, "pixel.fnt"), "w", newline="\n") as f:
        f.write("\n".join(fnt) + "\n")
    print(f"wrote pixel.png {w}x{h} and pixel.fnt ({len(chars)} glyphs)")


if __name__ == "__main__":
    main()
