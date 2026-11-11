"""把所有精靈圖放大 ×4（最近鄰）排在中灰底上，附檔名標籤，輸出成一張 PNG 方便檢查。

另外附上：圖塊 6×6 平鋪測試、天花板／地面拼接示範、背景水平接縫測試（兩張並排、×1），
以及 1× 的「情境」小圖（背景＋地形＋角色，再放大 ×3），檢查實際大小下的可讀性。

用法：python3 tools/preview_sheet.py [輸出路徑]（預設 /tmp/newt_art/preview.png）
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from art_common import C, Canvas, crop, draw_text, scale, text_width  # noqa: E402
from make_sprites import MANIFEST  # noqa: E402
from png import load  # noqa: E402

SPR = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
BG = (128, 128, 128, 255)
MAXW = 1800


def tile_demo(tiles):
    t = [crop(tiles, i * 8, 0, 8, 8) for i in range(8)]
    out = Canvas(8 * 30, 8 * 12, (0, 0, 0, 0))
    # 左：各圖塊自己平鋪 3×3
    for k in (0, 3, 6):
        for j in range(3):
            for i in range(3):
                out.blit(t[k], (k // 3) * 32 + i * 8, j * 8)
    # 右：天花板（填充 + 邊）與地面（邊 + 填充），起伏
    prof = [2, 2, 3, 3, 3, 2, 1, 1, 2, 3, 4, 4, 3, 2, 2, 2, 3, 3]
    for col, hgt in enumerate(prof):
        base = 0 if col < 9 else 3
        for r in range(hgt):
            out.blit(t[base + (1 if r == hgt - 1 else 0)], 96 + col * 8, r * 8)
        fh = 5 - hgt + 1
        for i in range(fh):
            row = 11 - i
            out.blit(t[base + (2 if i == fh - 1 else 0)], 96 + col * 8, row * 8)
    # 增生壁 3×6，下方一格芽體
    for j in range(4, 10):
        for i in range(3):
            out.blit(t[6], i * 8 + 4, j * 8 + (0 if j < 9 else 0))
    out.blit(t[7], 32, 72)
    return out


def context(sprites):
    """384×216 的一小塊情境：背景 + 地形 + 角色。"""
    w, h = 192, 108
    cv = crop(sprites["bg_rock.png"], 0, 50, w, h)
    tiles = sprites["tiles.png"]
    t = [crop(tiles, i * 8, 0, 8, 8) for i in range(8)]
    for col in range(w // 8):
        flesh = col >= 14
        base = 3 if flesh else 0
        ch = 2 + (col * 7 % 5 == 0)
        fh = 2 + (col * 3 % 4 == 0)
        for r in range(ch):
            cv.blit(t[base + (1 if r == ch - 1 else 0)], col * 8, r * 8)
        for i in range(fh):
            cv.blit(t[base + (2 if i == fh - 1 else 0)], col * 8, h - 8 - i * 8 + 4)

    def put(name, fx, fy, fw, fh, x, y):
        cv.blit(crop(sprites[name], fx * fw, fy * fh, fw, fh), x, y)
    put("player.png", 0, 0, 24, 12, 20, 50)
    put("drone.png", 0, 0, 10, 8, 6, 40)
    put("bullet.png", 0, 0, 8, 3, 50, 54)
    put("bullet.png", 0, 0, 8, 3, 66, 54)
    put("enemy_worm.png", 0, 0, 12, 12, 120, 40)
    put("enemy_worm.png", 1, 1, 12, 12, 136, 46)
    put("enemy_spore.png", 0, 0, 12, 12, 150, 64)
    put("enemy_spore.png", 1, 1, 12, 12, 100, 70)
    put("enemy_charger.png", 0, 0, 16, 12, 170, 44)
    put("enemy_turret.png", 1, 0, 16, 16, 80, h - 8 - 16 + 4 - 4)
    put("enemy_turret.png", 0, 1, 16, 16, 140, h - 8 - 16 + 4 - 4)
    put("enemy_bullet.png", 0, 0, 4, 4, 90, 70)
    put("enemy_bullet.png", 1, 0, 4, 4, 100, 60)
    put("enemy_bullet.png", 0, 0, 4, 4, 160, 30)
    put("pickup.png", 0, 2, 12, 12, 60, 30)
    put("missile.png", 0, 0, 6, 4, 40, 70)
    put("tentacle_root.png", 0, 0, 12, 12, 168, 15)
    return cv


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/newt_art/preview.png"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sprites = {n: load(os.path.join(SPR, n)) for n in MANIFEST}
    items = []
    for name in MANIFEST:
        k = 2 if name.startswith("bg_") else 4
        items.append((f"{name} x{k}", scale(sprites[name], k)))
    items.append(("tiles demo x4", scale(tile_demo(sprites["tiles.png"]), 4)))
    for bg in ("bg_rock.png", "bg_flesh.png"):
        pair = Canvas(768, 216)
        pair.blit(sprites[bg], 0, 0)
        pair.blit(sprites[bg], 384, 0)
        items.append((f"{bg} seam test x1 (seam at x=384)", pair))
    items.append(("context 1x shown x3", scale(context(sprites), 3)))

    pad, lab = 12, 14
    x = y = pad
    row_h = 0
    places = []
    for label, img in items:
        w = max(img.w, text_width(label, 2) + 2)
        if x + w > MAXW and x > pad:
            x = pad
            y += row_h + pad
            row_h = 0
        places.append((label, img, x, y))
        x += w + pad
        row_h = max(row_h, img.h + lab + 8)
    total_h = y + row_h + pad
    sheet = Canvas(MAXW, total_h, BG)
    for label, img, x, y in places:
        draw_text(sheet, x, y, label, C["black"], 2, 2)
        sheet.blit(img, x, y + lab + 8)
    sheet.save(out_path)
    print("wrote", out_path, sheet.w, "x", sheet.h)


if __name__ == "__main__":
    main()
