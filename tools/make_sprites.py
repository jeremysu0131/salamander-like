"""產生正式美術：覆蓋 tools/make_placeholders.py 產生的色塊，檔名、尺寸、幀排列完全照
docs/ARCHITECTURE.md 的素材清單。只使用 Endesga 32 色盤（見 art_common.py）。

用法：python3 tools/make_sprites.py

風格摘要：
- 玩家機體朝右，冷色（白、灰藍、青）。敵人朝左。壁砲畫成裝在地面、砲口朝上。
- 玩家、敵人、子彈都有 1 px 深色外框（#181425）。
- 亮橘 #f77622 與 #feae34 只用在敵彈。玩家子彈用青、白。
- 紅色變體（敵人圖第 2 列）整體換成暗紅、紅、粉。
- 弱點（Boss 核心、觸手根部）一律是亮桃紅 #ff0044 的發光點。
- Boss 核心插槽中心在 boss_body.png 的 (30, 60)。
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from art_common import (  # noqa: E402
    C, OUTLINE, PALETTE_SET, Canvas, add_outline, dither, draw_text, from_map, glyph,
    hash2, recolor, text_width, wrap_noise,
)

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")

# 檔名: (幀寬, 幀高, 橫向幀數, 縱向幀數) —— 與 docs/ARCHITECTURE.md 素材清單一致
MANIFEST = {
    "player.png": (24, 12, 3, 1),
    "drone.png": (10, 8, 2, 1),
    "shield.png": (8, 20, 1, 1),
    "explosion.png": (16, 16, 5, 1),
    "bullet.png": (8, 3, 1, 1),
    "missile.png": (6, 4, 2, 1),
    "ring.png": (6, 40, 3, 1),
    "beam.png": (8, 4, 1, 1),
    "pickup.png": (12, 12, 2, 6),
    "enemy_worm.png": (12, 12, 2, 2),
    "enemy_spore.png": (12, 12, 2, 2),
    "enemy_turret.png": (16, 16, 2, 2),
    "enemy_charger.png": (16, 12, 2, 2),
    "enemy_bullet.png": (4, 4, 2, 1),
    "tiles.png": (8, 8, 8, 1),
    "tentacle.png": (8, 8, 2, 1),
    "tentacle_root.png": (12, 12, 1, 1),
    "boss_body.png": (96, 120, 1, 1),
    "boss_core.png": (16, 16, 2, 1),
    "boss_valve.png": (24, 24, 3, 1),
    "bg_rock.png": (384, 216, 1, 1),
    "bg_flesh.png": (384, 216, 1, 1),
    "hud_icons.png": (8, 8, 7, 1),
    "logo.png": (192, 40, 1, 1),
}

# Boss 版面（給玩法程式參考，也寫進最終報告）
BOSS_SOCKET = (30, 60)  # 核心插槽中心，boss_body.png 內的像素座標
BOSS_VENTS = [(44, 22), (44, 98)]  # 上下吐孢子的孔

# 共用圖例
LEG = {
    "K": C["black"], "W": C["white"], "L": C["lgrey"], "G": C["grey"], "S": C["slate"],
    "D": C["dslate"], "N": C["navy"], "C": C["cyan"], "B": C["blue"], "b": C["dblue"],
    "P": C["purple"], "M": C["magenta"], "p": C["pink"], "s": C["skin"], "R": C["dred"],
    "r": C["red"], "U": C["plum"], "Y": C["yellow"], "c": C["cream"], "t": C["tan"],
    "T": C["tanbrown"], "o": C["brown"], "O": C["dbrown"], "H": C["hot"],
    "g": C["green"], "e": C["dgreen"], "E": C["ddgreen"],
}


def sheet(frames, fw, fh):
    """frames 是二維串列 [列][幀]，回傳拼好的整張圖。"""
    ny = len(frames)
    nx = max(len(r) for r in frames)
    cv = Canvas(fw * nx, fh * ny)
    for j, row in enumerate(frames):
        for i, f in enumerate(row):
            assert (f.w, f.h) == (fw, fh), (f.w, f.h, fw, fh)
            cv.blit(f, i * fw, j * fh)
    return cv


def m(rows, outline=True, diagonal=False):
    cv = from_map(rows, LEG)
    if outline:
        add_outline(cv, OUTLINE, diagonal)
    return cv


def disc(cv, cx, cy, r, dark, mid, light, lx=-0.6, ly=-0.8, hi=0.35, lo=-0.25):
    """畫一個有左上光源明暗的圓。cx, cy 可為小數（像素中心 = 整數 + 0.5）。"""
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            if dx * dx + dy * dy <= r * r:
                s = (dx * lx + dy * ly) / max(r, 0.1)
                cv.set(x, y, light if s > hi else (dark if s < lo else mid))


# ---------------------------------------------------------------- 玩家 --------

PLAYER_FLAT = [
    "........................",
    "..GL....................",
    "..SGL...................",
    "...SGL.......CCW........",
    ".b.SGLLLLLLLbCCCWL......",
    "CBbSLWWWWWWWWWLLLLLLW...",
    "CBbSLLLBBBBLLLLLLLGGGGG.",
    ".b.SSDDDDDDSSSSSGG......",
    "...SGGLSS...............",
    "..SGL...................",
    "..GL....................",
    "........................",
]


def shear(rows, steps):
    """把每一欄依 steps(x) 垂直位移，用來從平飛圖做出上傾、下傾。"""
    h, w = len(rows), len(rows[0])
    grid = [["."] * w for _ in range(h)]
    for x in range(w):
        dy = steps(x)
        for y in range(h):
            ch = rows[y][x]
            if ch != "." and 0 <= y + dy < h:
                grid[y + dy][x] = ch
    return ["".join(r) for r in grid]


def player():
    up = shear(PLAYER_FLAT, lambda x: -1 if 13 <= x < 19 else (-2 if x >= 19 else 0))
    down = shear(PLAYER_FLAT, lambda x: 1 if 13 <= x < 19 else (2 if x >= 19 else 0))
    return sheet([[m(PLAYER_FLAT), m(up), m(down)]], 24, 12)


def drone():
    f1 = m([
        "..........",
        "...bBBb...",
        "..bBCCBb..",
        ".SbCWWCbS.",
        ".SbCWCCbS.",
        "..bBCCBb..",
        "...bBBb...",
        "..........",
    ])
    f2 = m([
        "..........",
        "...bBBb...",
        "..bBBCBb..",
        ".GbCCWCbG.",
        ".GbCWWCbG.",
        "..bBCCBb..",
        "...bBBb...",
        "..........",
    ])
    return sheet([[f1, f2]], 10, 8)


def arc(cv, ox, oy, w, h, rx, ry, bands, right=None):
    """在 (ox, oy, w, h) 範圍內畫一段往右凸的橢圓弧。bands: [(內緣比例, 顏色), ...]，由內往外。"""
    right = (w - 0.5) if right is None else right
    cx = right - rx
    cy = h / 2
    for y in range(h):
        for x in range(w):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            d = math.sqrt(dx * dx + dy * dy)
            if d > 1.0 or dx < 0:
                continue
            col = None
            for inner, c in bands:
                if d >= inner:
                    col = c
            if col:
                cv.set(ox + x, oy + y, col)


def shield():
    cv = Canvas(8, 20)
    arc(cv, 0, 0, 8, 20, 6.4, 9.9, [(0.62, C["dblue"]), (0.74, C["blue"]), (0.85, C["cyan"]), (0.95, C["white"])],
        right=6.6)
    # 能量紋：在青色帶上點幾個白點
    for y in (5, 9, 14):
        for x in range(8):
            if cv.get(x, y) == C["cyan"]:
                cv.set(x, y, C["white"])
                break
    add_outline(cv)
    return cv


def explosion():
    frames = []
    spec = [  # (半徑, [(比例上限, 顏色)])
        (3.5, [(0.55, C["white"]), (1.0, C["yellow"])]),
        (5.5, [(0.35, C["white"]), (0.7, C["yellow"]), (1.0, C["red"])]),
        (7.0, [(0.3, C["yellow"]), (0.6, C["red"]), (0.85, C["rust"]), (1.0, C["dred"])]),
        (7.5, [(0.45, C["rust"]), (0.75, C["dred"]), (1.0, C["dbrown"])]),
        (7.8, [(0.7, C["dbrown"]), (1.0, C["plum"])]),
    ]
    for i, (r, bands) in enumerate(spec):
        cv = Canvas(16, 16)
        hollow = [0, 0, 0.0, 0.35, 0.55][i]
        density = [1, 1, 0.95, 0.8, 0.55][i]
        for y in range(16):
            for x in range(16):
                dx, dy = x + 0.5 - 8, y + 0.5 - 8
                ang = math.atan2(dy, dx)
                rr = r * (0.85 + 0.15 * math.sin(ang * 5 + i * 1.7))
                d = math.sqrt(dx * dx + dy * dy) / rr
                if d > 1.0 or d < hollow:
                    continue
                if hash2(x, y, 40 + i) > density:
                    continue
                for lim, c in bands:
                    if d <= lim:
                        cv.set(x, y, c)
                        break
        frames.append(cv)
    return sheet([frames], 16, 16)


def bullet():
    return m([
        ".KKKKKK.",
        "KBCCWWWK",
        ".KKKKKK.",
    ], outline=False)


def missile():
    f1 = m([".KKKK.", "CSLLWK", "BSGGLK", ".KKKK."], outline=False)
    f2 = m([".KKKK.", "BSLLWK", "CSGGLK", ".KKKK."], outline=False)
    return sheet([[f1, f2]], 6, 4)


def ring():
    frames = []
    for h, rx in ((8, 2.6), (24, 3.6), (40, 4.6)):
        cv = Canvas(6, 40)
        sub = Canvas(6, h)
        arc(sub, 0, 0, 6, h, rx, h / 2 - 0.2,
            [(0.45, C["blue"]), (0.62, C["cyan"]), (0.82, C["white"])], right=5.2)
        add_outline(sub)
        cv.blit(sub, 0, (40 - h) // 2)
        frames.append(cv)
    return sheet([frames], 6, 40)


def beam():
    return m([
        "BBCBBBBC",
        "CWCCWCCC",
        "WWWCWWWW",
        "BBBBCBBB",
    ], outline=False)


# ---------------------------------------------------------------- 道具 --------

PICKUP_TYPES = [  # (字, 暗, 中, 亮)
    ("S", C["dblue"], C["blue"], C["cyan"]),          # speed
    ("M", C["ddgreen"], C["dgreen"], C["green"]),     # missile
    ("R", C["purple"], C["magenta"], C["pink"]),      # ring
    ("B", C["dred"], C["red"], C["skin"]),            # beam
    ("D", C["dbrown"], C["brown"], C["tan"]),         # drone
    ("*", C["dslate"], C["slate"], C["lgrey"]),       # shield（盾牌符號）
]

SHIELD_GLYPH = ["#####", "#####", "#####", "#####", ".###.", ".###.", "..#.."]


def capsule(dark, mid, light, letter, blink):
    cv = Canvas(12, 12)
    body_mid = light if blink else mid
    body_dark = mid if blink else dark
    for y in range(1, 11):
        for x in range(12):
            # 圓角膠囊：左右兩端是半圓
            inset = {1: 3, 2: 1, 9: 1, 10: 3}.get(y, 0)
            if x < inset or x > 11 - inset:
                continue
            if y in (1, 10) or x in (inset, 11 - inset):
                cv.set(x, y, OUTLINE)
            elif y == 2 or (y == 3 and x in (2, 9)):
                cv.set(x, y, C["white"] if blink else light)
            elif y >= 8:
                cv.set(x, y, body_dark)
            else:
                cv.set(x, y, body_mid)
    g = SHIELD_GLYPH if letter == "*" else None
    rows = g if g else glyph(letter)
    ink = OUTLINE if blink else C["white"]
    shadow = body_dark if blink else OUTLINE
    for j, row in enumerate(rows):
        for i, b in enumerate(row):
            if b == "#":
                if not blink and rows[j][i + 1:i + 2] != "#":
                    cv.set(4 + i + 1, 2 + j, shadow)
    for j, row in enumerate(rows):
        for i, b in enumerate(row):
            if b == "#":
                cv.set(4 + i, 2 + j, ink)
    return cv


def pickup():
    rows = []
    for letter, d, mi, li in PICKUP_TYPES:
        rows.append([capsule(d, mi, li, letter, False), capsule(d, mi, li, letter, True)])
    return sheet(rows, 12, 12)


# ---------------------------------------------------------------- 敵人 --------

def red_map(pairs):
    return {C[a]: C[b] for a, b in pairs}


def worm_frame(phase):
    cv = Canvas(12, 12)
    w = 1.4 if phase == 0 else -1.4
    disc(cv, 10.3, 6 - w, 1.5, C["ddgreen"], C["dgreen"], C["green"])
    disc(cv, 8.2, 6 + w * 0.8, 2.3, C["ddgreen"], C["dgreen"], C["green"])
    disc(cv, 4.6, 6, 3.4, C["ddgreen"], C["dgreen"], C["green"])
    # 眼睛朝左
    cv.set(3, 5, C["cream"])
    cv.set(2, 5, C["black"])
    cv.set(3, 4, C["cream"])
    # 口器
    cv.set(1, 7, C["cream"])
    cv.set(2, 8 if phase == 0 else 7, C["cream"])
    add_outline(cv)
    return cv


WORM_RED = red_map([("ddgreen", "dred"), ("dgreen", "red"), ("green", "pink"), ("cream", "skin")])


def enemy_worm():
    f = [worm_frame(0), worm_frame(1)]
    return sheet([f, [recolor(x, WORM_RED) for x in f]], 12, 12)


def spore_frame(phase):
    cv = Canvas(12, 12)
    cx = cy = 6.0
    for k in range(8):
        ang = k * math.pi / 4 + (math.pi / 8 if phase else 0)
        length = 5.6 if k % 2 == 0 else 4.6
        for t in (3.4, 4.2, 5.0):
            if t > length:
                continue
            x = int(math.floor(cx + math.cos(ang) * t))
            y = int(math.floor(cy + math.sin(ang) * t))
            cv.set(x, y, C["pink"] if t >= 4.6 else C["magenta"])
    disc(cv, cx, cy, 3.4, C["purple"], C["magenta"], C["pink"])
    # 核（偏左，像是看向左邊）
    cv.set(4, 5, C["skin"])
    cv.set(4, 6, C["skin"] if phase else C["pink"])
    cv.set(5, 6, C["purple"])
    add_outline(cv)
    return cv


SPORE_RED = red_map([("purple", "dred"), ("magenta", "red"), ("pink", "skin")])


def enemy_spore():
    f = [spore_frame(0), spore_frame(1)]
    return sheet([f, [recolor(x, SPORE_RED) for x in f]], 12, 12)


TURRET_IDLE = [
    "................",
    "................",
    "................",
    "......GUUG......",
    "......GLLG......",
    "......GLLG......",
    ".....GGLLGG.....",
    "....GLLcLLLG....",
    "...GLLcLLMpLG...",
    "...GLLLLLMMLG...",
    "...SGLLLLLLGS...",
    "..SSSGGGGGGSSS..",
    ".SDSSSSGSSSSSDS.",
    "SSDSSDSSSDSSSDSS",
    "SDSSSSDSSSSDSSSS",
    "DDDDDDDDDDDDDDDD",
]

TURRET_FIRE = [
    ".....Y....Y.....",
    "......WYYW......",
    ".....GWWWWG.....",
    ".....GpWWpG.....",
    "......GppG......",
    "......GLLG......",
    ".....GGLLGG.....",
    "....GLLcLLLG....",
    "...GLLcLLHpLG...",
    "...GLLLLLMMLG...",
    "...SGLLLLLLGS...",
    "..SSSGGGGGGSSS..",
    ".SDSSSSGSSSSSDS.",
    "SSDSSDSSSDSSSDSS",
    "SDSSSSDSSSSDSSSS",
    "DDDDDDDDDDDDDDDD",
]

TURRET_RED = red_map([("grey", "red"), ("lgrey", "pink"), ("cream", "skin"), ("slate", "dred"),
                      ("dslate", "plum"), ("magenta", "purple"), ("pink", "cream")])


def enemy_turret():
    f = [m(TURRET_IDLE), m(TURRET_FIRE)]
    return sheet([f, [recolor(x, TURRET_RED) for x in f]], 16, 16)


CHARGER_A = [
    "................",
    "........NNNb....",
    "......NbBBBBbN..",
    "....NbBBLBBBBbN.",
    "...bBBYBBLLBBBbN",
    ".ccbBBBBBBBLBBbN",
    "ccctbBBBBBBBBBbN",
    ".ccbbbBBBBBBBbb.",
    "...NbbbbbbbbbbN.",
    "....NNbNNbNNbN..",
    ".....N..N..N....",
    "................",
]
CHARGER_B = [
    "................",
    "........NNNb....",
    "......NbBBBBbN..",
    "....NbBBLBBBBbN.",
    "...bBBWBBLLBBBbN",
    ".ccbBBBBBBBLBBbN",
    "ccctbBBBBBBBBBbN",
    ".ccbbbBBBBBBBbb.",
    "...NbbbbbbbbbbN.",
    "...NNbNNbNNbNN..",
    "...N..N..N..N...",
    "................",
]
CHARGER_RED = red_map([("navy", "plum"), ("dblue", "dred"), ("blue", "red"), ("lgrey", "pink"),
                       ("cream", "skin"), ("tan", "pink")])


def enemy_charger():
    f = [m(CHARGER_A), m(CHARGER_B)]
    return sheet([f, [recolor(x, CHARGER_RED) for x in f]], 16, 12)


def enemy_bullet():
    o, w = C["orange"], C["white"]
    f1, f2 = Canvas(4, 4), Canvas(4, 4)
    for y in range(4):
        for x in range(4):
            if (x in (0, 3)) and (y in (0, 3)):
                continue
            inner = x in (1, 2) and y in (1, 2)
            f1.set(x, y, w if inner else o)
            f2.set(x, y, o if inner else w)
    # 角落用最暗色當半個外框，在亮地形上也看得出輪廓
    for f in (f1, f2):
        for x, y in ((0, 0), (3, 0), (0, 3), (3, 3)):
            f.set(x, y, (*OUTLINE[:3], 255))
    return sheet([[f1, f2]], 4, 4)


# ---------------------------------------------------------------- 地形 --------

ROCK_FILL = [
    "SSSSDSSS",
    "SGSSDSSS",
    "SSSDDSSS",
    "DDSSSSSD",
    "SSSSSSSS",
    "SSSSDDSS",
    "SSSDNSSS",
    "SSSSSSGS",
]
FLESH_FILL = [
    "PPRRRPPU",
    "PRRMRRPP",
    "PRRRRRPP",
    "UPRRRPPU",
    "PPPPPUPP",
    "RPPUPPRR",
    "RRPPPRRM",
    "RRUPPRRR",
]


def tiles():
    rock_ceil = ROCK_FILL[:5] + ["SGSSSSDS", "GGLGGGGL", "LGGLGLGG"]
    rock_floor = ["LWLGLLGL", "GGSGGLGG"] + ROCK_FILL[2:]
    flesh_ceil = FLESH_FILL[:5] + ["RPMRRPMR", "MMpMMMMp", "ppsppMpp"]
    flesh_floor = ["pspppspp", "MpMMMpMM", "PMRRPMRR"] + FLESH_FILL[3:]
    growth = [
        "UPPPPPPU",
        "PMMMMMMP",
        "PMpsMMMP",
        "PMppMMMP",
        "PMMMMMRP",
        "PMMMMMRP",
        "PMMMRRRP",
        "UPPPPPPU",
    ]
    bud = [
        "........",
        "..pppp..",
        ".pssppp.",
        ".psppMp.",
        ".ppppMp.",
        ".pppMMp.",
        "..pppp..",
        "........",
    ]
    fr = [m(t, outline=False) for t in (ROCK_FILL, rock_ceil, rock_floor, FLESH_FILL, flesh_ceil,
                                       flesh_floor, growth, bud)]
    return sheet([fr], 8, 8)


def tentacle():
    seg = m([
        "KPMppMPK",
        "KPMppMPK",
        "KPMMpMPK",
        "KPMMMMPK",
        "KKPPPPKK",
        "KPMpMMPK",
        "KPMppMPK",
        "KPMppMPK",
    ], outline=False)
    tip = m([
        "...KK...",
        "...KpK..",
        "..KMpK..",
        "..KMpPK.",
        ".KPMppK.",
        ".KPMppPK",
        "KPMMpMPK",
        "KPMppMPK",
    ], outline=False)
    return sheet([[seg, tip]], 8, 8)


def tentacle_root():
    cv = Canvas(12, 12)
    disc(cv, 6, 6, 5.5, C["purple"], C["dred"], C["magenta"])
    disc(cv, 6, 6.3, 2.6, C["dred"], C["hot"], C["pink"], hi=0.5, lo=-0.6)
    cv.set(5, 5, C["skin"])
    # 筋
    for x, y in ((1, 6), (2, 3), (9, 2), (10, 7), (6, 10), (3, 9)):
        cv.set(x, y, C["purple"])
    add_outline(cv)
    return cv


# ---------------------------------------------------------------- Boss --------

def bezier(p0, p1, p2, t):
    a = (1 - t) * (1 - t)
    b = 2 * (1 - t) * t
    c = t * t
    return (a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1])


def boss_body():
    W, H = 96, 120
    cv = Canvas(W, H)
    sx, sy = BOSS_SOCKET
    ecx, ecy, erx, ery = 46, 60, 33, 44

    def wall_x(y):
        t = abs(y - 60) / 60
        return 76 + 3 * math.sin(y / 7.0) + 8 * t * t

    vessels = [((46, 26), (54, 6), (84, -2), 5.0), ((60, 24), (70, 14), (90, 10), 4.0),
               ((54, 96), (64, 112), (88, 122), 5.0)]

    def vessel_d(x, y):
        best = 99
        for p0, p1, p2, rad in vessels:
            for k in range(25):
                px, py = bezier(p0, p1, p2, k / 24)
                d = math.hypot(x - px, y - py) / rad
                best = min(best, d)
        return best

    for y in range(H):
        for x in range(W):
            px, py = x + 0.5, y + 0.5
            ex, ey = (px - ecx) / erx, (py - ecy) / ery
            e = ex * ex + ey * ey
            # 心臟上半部兩個鼓起的腔室
            lobe = min(((px - 34) / 18) ** 2 + ((py - 30) / 16) ** 2, ((px - 34) / 18) ** 2 + ((py - 90) / 16) ** 2)
            if x >= wall_x(y):
                # 肉壁：暗色、條紋
                n = wrap_noise(x * 2, y, 192, seed=7, cell=8)
                band = math.sin(y / 3.0 + n * 4)
                col = C["plum"] if band < -0.2 else (C["purple"] if band < 0.7 else C["dred"])
                if x < wall_x(y) + 1.5:
                    col = C["black"]
                cv.set(x, y, col)
            elif e <= 1.0 or lobe <= 1.0:
                s = -ex * 0.55 - ey * 0.75 + (wrap_noise(x, y, 96, seed=3, cell=8) - 0.5) * 0.5
                if s > 0.55:
                    col = C["pink"] if dither(x, y, min(1, (s - 0.55) * 4)) else C["red"]
                elif s > 0.15:
                    col = C["red"] if dither(x, y, min(1, (s - 0.15) * 3)) else C["dred"]
                elif s > -0.45:
                    col = C["dred"]
                else:
                    col = C["purple"] if dither(x, y, min(1, (-0.45 - s) * 3)) else C["dred"]
                cv.set(x, y, col)
            else:
                vd = vessel_d(px, py)
                if vd <= 1.0:
                    col = C["magenta"] if vd < 0.45 else C["purple"]
                    if vd < 0.2:
                        col = C["pink"]
                    cv.set(x, y, col)

    # 血管紋路（在心臟上隨機漫步）
    import random
    rnd = random.Random(1234)
    for _ in range(9):
        x, y = rnd.uniform(20, 70), rnd.uniform(25, 95)
        ang = rnd.uniform(0, 2 * math.pi)
        for _ in range(rnd.randint(10, 22)):
            ix, iy = int(x), int(y)
            if math.hypot(ix - sx, iy - sy) > 14 and cv.get(ix, iy) in (C["dred"], C["red"]):
                cv.set(ix, iy, C["purple"] if cv.get(ix, iy) == C["dred"] else C["dred"])
            ang += rnd.uniform(-0.6, 0.6)
            x += math.cos(ang)
            y += math.sin(ang)

    # 核心插槽：骨質環 + 深腔
    for y in range(H):
        for x in range(W):
            d = math.hypot(x + 0.5 - sx, y + 0.5 - sy)
            if d <= 13:
                if d > 12:
                    cv.set(x, y, C["black"])
                elif d > 10:
                    a = math.atan2(y + 0.5 - sy, x + 0.5 - sx)
                    cv.set(x, y, C["cream"] if math.sin(a) < -0.3 else (C["tan"] if math.sin(a) < 0.4 else C["tanbrown"]))
                elif d > 9:
                    cv.set(x, y, C["dbrown"])
                else:
                    cv.set(x, y, C["plum"] if d > 6 else C["black"])

    # 上下的孢子孔
    for vx, vy in BOSS_VENTS:
        for y in range(vy - 3, vy + 4):
            for x in range(vx - 5, vx + 6):
                d = ((x + 0.5 - vx) / 5) ** 2 + ((y + 0.5 - vy) / 3) ** 2
                if d <= 1:
                    cv.set(x, y, C["pink"] if d > 0.55 else (C["plum"] if d > 0.3 else C["black"]))

    add_outline(cv)
    return cv


def boss_core():
    frames = []
    for k in range(2):
        cv = Canvas(16, 16)
        r = 6.6 if k == 0 else 7.4
        for y in range(16):
            for x in range(16):
                d = math.hypot(x + 0.5 - 8, y + 0.5 - 8) / r
                if d > 1:
                    continue
                if k == 0:
                    col = C["purple"] if d > 0.82 else C["magenta"] if d > 0.62 else C["hot"] if d > 0.32 else C["pink"]
                else:
                    col = C["magenta"] if d > 0.85 else C["hot"] if d > 0.55 else C["pink"] if d > 0.28 else C["white"]
                cv.set(x, y, col)
        cv.set(6, 5, C["skin"] if k == 0 else C["white"])
        cv.set(5, 6, C["skin"])
        add_outline(cv)
        frames.append(cv)
    return sheet([frames], 16, 16)


VALVE_SECTORS = {"upper": 60, "front": 180, "lower": 300}  # 扇形中心角（度，畫面上方為 90）


def boss_valve():
    frames = []
    for name in ("upper", "front", "lower"):
        center = math.radians(VALVE_SECTORS[name])
        cv = Canvas(24, 24)
        for y in range(24):
            for x in range(24):
                dx, dy = x + 0.5 - 12, -(y + 0.5 - 12)
                r = math.hypot(dx, dy)
                if r > 11.8:
                    continue
                a = math.atan2(dy, dx)
                da = abs((a - center + math.pi) % (2 * math.pi) - math.pi)
                half = math.radians(60)
                if da > half:
                    continue
                edge = (half - da) * r  # 離扇形邊的弧長距離
                if edge < 0.9 and r > 1.5:
                    continue
                if r > 10.9 or edge < 1.8:
                    col = C["dbrown"]
                elif r in () or abs(r - 7.5) < 0.6 or abs(r - 4.0) < 0.6:
                    col = C["tanbrown"]
                else:
                    # 光源左上
                    s = math.cos(a - math.radians(135))
                    col = C["cream"] if s > 0.4 else (C["tan"] if s > -0.3 else C["tanbrown"])
                    if r > 9.6:
                        col = C["tan"] if s > 0 else C["tanbrown"]
                cv.set(x, y, col)
        add_outline(cv)
        frames.append(cv)
    return sheet([frames], 24, 24)


# ---------------------------------------------------------------- 背景 --------

def wave(x, period, comps):
    return sum(a * math.sin(2 * math.pi * k * x / period + ph) for k, a, ph in comps)


def bg_rock():
    W, H = 384, 216
    cv = Canvas(W, H, C["black"])
    far_top = lambda x: 44 + wave(x, W, [(2, 12, 0.3), (5, 6, 1.1), (11, 3, 2.0)])
    far_bot = lambda x: 168 + wave(x, W, [(3, 10, 1.7), (7, 5, 0.4), (13, 2, 0.9)])
    near_top = lambda x: 18 + wave(x, W, [(3, 9, 2.4), (8, 5, 0.2), (17, 2, 1.3)])
    near_bot = lambda x: 196 + wave(x, W, [(2, 8, 0.8), (9, 4, 2.2), (19, 2, 0.5)])
    for x in range(W):
        ft, fb, nt, nb = far_top(x), far_bot(x), near_top(x), near_bot(x)
        for y in range(H):
            n = wrap_noise(x, y, W, seed=11, cell=16)
            if y < nt or y > nb:
                col = C["navy"]
                # 近景岩塊的邊緣微亮，內部有暗紋
                if abs(y - nt) < 1 or abs(y - nb) < 1:
                    col = C["dslate"] if hash2(x, y, 5) > 0.35 else C["navy"]
                elif n < 0.35 and dither(x, y, 0.5):
                    col = C["black"]
                cv.set(x, y, col)
            elif y < ft or y > fb:
                # 遠景：navy 與黑的抖色
                depth = 0.45 + 0.25 * n
                cv.set(x, y, C["navy"] if dither(x, y, depth) else C["black"])
            else:
                # 空洞中央：稀疏的漂浮塵粒
                if hash2(x, y, 9) > 0.9975:
                    cv.set(x, y, C["dslate"])
                elif wrap_noise(x, y, W, seed=13, cell=32) > 0.72 and dither(x, y, 0.12):
                    cv.set(x, y, C["navy"])
    return cv


def bg_flesh():
    W, H = 384, 216
    cv = Canvas(W, H, C["black"])
    top = lambda x: 30 + wave(x, W, [(2, 10, 1.0), (6, 6, 0.3), (13, 2, 2.0)])
    bot = lambda x: 186 + wave(x, W, [(3, 9, 0.2), (5, 6, 1.4), (12, 2, 0.6)])
    for x in range(W):
        t, b = top(x), bot(x)
        for y in range(H):
            n = wrap_noise(x, y, W, seed=21, cell=16)
            if y < t or y > b:
                fold = math.sin((y if y < t else H - y) / 4.0 + n * 6)
                col = C["plum"] if fold > -0.3 else C["black"]
                if abs(y - t) < 1 or abs(y - b) < 1:
                    col = C["purple"] if hash2(x, y, 3) > 0.5 else C["plum"]
                cv.set(x, y, col)
            else:
                d = min(y - t, b - y)
                if d < 14 and dither(x, y, (14 - d) / 28):
                    cv.set(x, y, C["plum"])
    # 遠方的血管網
    import random
    rnd = random.Random(77)
    for _ in range(14):
        x, y = rnd.uniform(0, W), rnd.uniform(40, 176)
        ang = rnd.uniform(-0.6, 0.6) + (math.pi if rnd.random() < 0.5 else 0)
        for _ in range(rnd.randint(30, 80)):
            ix, iy = int(x) % W, int(y)
            if 0 <= iy < H and cv.get(ix, iy) == C["black"]:
                cv.set(ix, iy, C["plum"])
            ang += rnd.uniform(-0.35, 0.35)
            x += math.cos(ang)
            y += math.sin(ang) * 0.8
    # 漂浮的細胞
    for _ in range(18):
        cx, cy, r = rnd.uniform(0, W), rnd.uniform(50, 166), rnd.uniform(2, 5)
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                xx = x % W
                if abs(d - r) < 0.6 and 0 <= y < H:
                    cv.set(xx, y, C["plum"])
    return cv


# ---------------------------------------------------------------- UI --------

def hud_icons():
    speed = m([
        "........",
        "bB..bB..",
        ".bC..bC.",
        "..CW..CW",
        ".bC..bC.",
        "bB..bB..",
        "........",
        "........",
    ])
    missile = m([
        "........",
        ".e......",
        ".eggg...",
        "eeggggW.",
        ".eggg...",
        ".e......",
        "........",
        "........",
    ])
    ring_i = m([
        "........",
        "..PM....",
        "....Mp..",
        ".....Mp.",
        ".....Mp.",
        "....Mp..",
        "..PM....",
        "........",
    ])
    beam_i = m([
        "........",
        "........",
        "RRrrrrr.",
        "RsssssW.",
        "RRrrrrr.",
        "........",
        "........",
        "........",
    ])
    drone_i = Canvas(8, 8)
    disc(drone_i, 3.5, 3.5, 2.7, C["dbrown"], C["brown"], C["tan"])
    drone_i.set(2, 2, C["cream"])
    add_outline(drone_i)
    shield_i = m([
        "........",
        ".GLLLLG.",
        ".GLWWLG.",
        ".GLWWLG.",
        ".GLLLLG.",
        "..GLLG..",
        "...GG...",
        "........",
    ])
    life = m([
        "........",
        ".G......",
        ".SGL.C..",
        "bSWWWWW.",
        ".SLLGG..",
        ".G......",
        "........",
        "........",
    ])
    return sheet([[speed, missile, ring_i, beam_i, drone_i, shield_i, life]], 8, 8)


LOGO_GLYPHS = {  # 標題用的粗體字（筆畫 2 單位寬）
    "P": ["#####.", "##..##", "##..##", "#####.", "##....", "##....", "##...."],
    "R": ["#####.", "##..##", "##..##", "#####.", "##.##.", "##..##", "##..##"],
    "O": [".####.", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
    "J": ["..####", "....##", "....##", "....##", "....##", "##..##", ".####."],
    "E": ["######", "##....", "##....", "#####.", "##....", "##....", "######"],
    "C": [".#####", "##....", "##....", "##....", "##....", "##....", ".#####"],
    "T": ["######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##.."],
    "N": ["##..##", "###.##", "######", "##.###", "##..##", "##..##", "##..##"],
    "W": ["##...##", "##...##", "##.#.##", "##.#.##", "#######", "###.###", "##...##"],
}


def logo():
    W, H = 192, 40
    cv = Canvas(W, H)
    grad = [C["white"], C["white"], C["lgrey"], C["cyan"], C["cyan"], C["blue"], C["blue"], C["dblue"]]

    def word(text, sx, sy, y0, spacing):
        glyphs = [LOGO_GLYPHS[ch] for ch in text]
        tw = sum(len(g[0]) * sx for g in glyphs) + spacing * sx * (len(glyphs) - 1)
        x = (W - tw) // 2
        layer = Canvas(W, H)
        h = 7 * sy
        for g in glyphs:
            for j, row in enumerate(g):
                for i, b in enumerate(row):
                    if b == "#":
                        for yy in range(y0 + j * sy, y0 + (j + 1) * sy):
                            col = grad[min(len(grad) - 1, (yy - y0) * len(grad) // h)]
                            layer.rect(x + i * sx, yy, sx, 1, col)
            x += (len(g[0]) + spacing) * sx
        return layer

    big = word("NEWT", 4, 4, 10, 1)
    small = word("PROJECT", 2, 1, 1, 2)
    # 陰影
    for lay in (small, big):
        for y in range(H):
            for x in range(W):
                if lay.get(x, y)[3] and not lay.get(x + 1, y + 1)[3]:
                    if 0 <= x + 1 < W and 0 <= y + 1 < H:
                        cv.set(x + 1, y + 1, C["dslate"])
                        cv.set(x + 2, y + 1, C["dslate"])
    cv.blit(small, 0, 0)
    cv.blit(big, 0, 0)
    add_outline(cv, OUTLINE, diagonal=True)
    # 兩側的細線裝飾
    for x in range(10, 36):
        cv.set(x, 4, C["blue"])
        cv.set(W - 1 - x, 4, C["blue"])
    return cv


GENERATORS = {
    "player.png": player, "drone.png": drone, "shield.png": shield, "explosion.png": explosion,
    "bullet.png": bullet, "missile.png": missile, "ring.png": ring, "beam.png": beam,
    "pickup.png": pickup, "enemy_worm.png": enemy_worm, "enemy_spore.png": enemy_spore,
    "enemy_turret.png": enemy_turret, "enemy_charger.png": enemy_charger,
    "enemy_bullet.png": enemy_bullet, "tiles.png": tiles, "tentacle.png": tentacle,
    "tentacle_root.png": tentacle_root, "boss_body.png": boss_body, "boss_core.png": boss_core,
    "boss_valve.png": boss_valve, "bg_rock.png": bg_rock, "bg_flesh.png": bg_flesh,
    "hud_icons.png": hud_icons, "logo.png": logo,
}

RESERVED = {C["orange"], C["gold"]}


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, (fw, fh, nx, ny) in MANIFEST.items():
        if only and name not in only:
            continue
        cv = GENERATORS[name]()
        assert (cv.w, cv.h) == (fw * nx, fh * ny), f"{name}: {cv.w}x{cv.h} != {fw * nx}x{fh * ny}"
        for p in cv.px:
            if p[3] == 0:
                continue
            assert p in PALETTE_SET, f"{name}: off-palette color {p}"
            if name != "enemy_bullet.png":
                assert p not in RESERVED, f"{name}: uses enemy-bullet-only color {p}"
        cv.save(os.path.join(OUT, name))
        print(f"wrote {name} {cv.w}x{cv.h}")


if __name__ == "__main__":
    main()
