"""最小的 PNG 讀寫工具，只用標準函式庫（本機沒有 Pillow）。

影像以 Canvas 表示：寬、高與一維的 RGBA tuple 陣列。
"""

import struct
import zlib


class Canvas:
    def __init__(self, w, h, fill=(0, 0, 0, 0)):
        self.w = w
        self.h = h
        self.px = [fill] * (w * h)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y * self.w + x]
        return (0, 0, 0, 0)

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            if len(c) == 3:
                c = (*c, 255)
            self.px[y * self.w + x] = c

    def rect(self, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.set(i, j, c)

    def outline(self, x, y, w, h, c):
        for i in range(x, x + w):
            self.set(i, y, c)
            self.set(i, y + h - 1, c)
        for j in range(y, y + h):
            self.set(x, j, c)
            self.set(x + w - 1, j, c)

    def blit(self, other, ox, oy):
        for j in range(other.h):
            for i in range(other.w):
                c = other.get(i, j)
                if c[3] > 0:
                    self.set(ox + i, oy + j, c)

    def save(self, path):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            for x in range(self.w):
                raw.extend(self.px[y * self.w + x])

        def chunk(tag, data):
            body = tag + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        png += chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


def load(path):
    """讀取 8-bit RGBA 或 RGB、非交錯的 PNG（Godot 截圖與本工具輸出的格式）。"""
    with open(path, "rb") as f:
        data = f.read()
    pos = 8
    w = h = 0
    color_type = 6
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            w, h, _depth, color_type = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    bpp = 4 if color_type == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    canvas = Canvas(w, h)
    prev = bytearray(stride)
    i = 0
    for y in range(h):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 255
            elif ftype == 2:
                line[x] = (line[x] + b) & 255
            elif ftype == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        for x in range(w):
            px = line[x * bpp:(x + 1) * bpp]
            canvas.px[y * w + x] = tuple(px) if bpp == 4 else (*px, 255)
        prev = line
    return canvas
