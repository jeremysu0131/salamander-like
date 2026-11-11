"""產生暫代用的精靈圖：每一幀是帶深色外框的色塊，尺寸與幀數完全符合 docs/ARCHITECTURE.md 的素材清單。

正式美術（tools/make_sprites.py）會以同樣的檔名與尺寸覆蓋這些檔案。

用法：python3 tools/make_placeholders.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from png import Canvas  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
OUTLINE = (20, 12, 28, 255)

# 檔名: (幀寬, 幀高, 橫向幀數, 縱向幀數, 顏色)
MANIFEST = {
    "player.png": (24, 12, 3, 1, (120, 200, 255)),
    "drone.png": (10, 8, 2, 1, (255, 160, 60)),
    "shield.png": (8, 20, 1, 1, (90, 220, 255)),
    "explosion.png": (16, 16, 5, 1, (255, 200, 80)),
    "bullet.png": (8, 3, 1, 1, (200, 255, 255)),
    "missile.png": (6, 4, 2, 1, (220, 220, 220)),
    "ring.png": (6, 40, 3, 1, (120, 255, 220)),
    "beam.png": (8, 4, 1, 1, (160, 240, 255)),
    "pickup.png": (12, 12, 2, 6, (255, 80, 80)),
    "enemy_worm.png": (12, 12, 2, 2, (120, 220, 80)),
    "enemy_spore.png": (12, 12, 2, 2, (200, 120, 220)),
    "enemy_turret.png": (16, 16, 2, 2, (160, 160, 120)),
    "enemy_charger.png": (16, 12, 2, 2, (220, 200, 80)),
    "enemy_bullet.png": (4, 4, 2, 1, (255, 140, 40)),
    "tiles.png": (8, 8, 8, 1, (90, 100, 130)),
    "tentacle.png": (8, 8, 2, 1, (200, 90, 120)),
    "tentacle_root.png": (12, 12, 1, 1, (240, 120, 120)),
    "boss_body.png": (96, 120, 1, 1, (150, 60, 90)),
    "boss_core.png": (16, 16, 2, 1, (255, 220, 120)),
    "boss_valve.png": (24, 24, 3, 1, (220, 210, 190)),
    "bg_rock.png": (384, 216, 1, 1, (24, 28, 44)),
    "bg_flesh.png": (384, 216, 1, 1, (44, 18, 30)),
    "hud_icons.png": (8, 8, 7, 1, (240, 240, 240)),
    "logo.png": (192, 40, 1, 1, (120, 200, 255)),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (fw, fh, nx, ny, color) in MANIFEST.items():
        c = Canvas(fw * nx, fh * ny)
        for j in range(ny):
            for i in range(nx):
                shade = 1.0 - 0.12 * i
                col = tuple(int(v * shade) for v in color)
                if j == 1:
                    col = (min(255, col[0] + 100), col[1] // 2, col[2] // 2)
                c.rect(i * fw, j * fh, fw, fh, col)
                if fw >= 4 and fh >= 4 and not name.startswith("bg_"):
                    c.outline(i * fw, j * fh, fw, fh, OUTLINE)
        c.save(os.path.join(OUT, name))
        print("wrote", name)


if __name__ == "__main__":
    main()
