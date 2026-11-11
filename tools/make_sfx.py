"""合成 2 個復古音效（類 sfxr），只用標準函式庫的 wave 模組。16-bit 單聲道 44100 Hz。

- assets/audio/shoot.wav：約 0.1 秒，下滑的方波加一點雜訊，音量偏低，可每秒連發 6 次不刺耳。
- assets/audio/pickup.wav：約 0.25 秒，上升的三音琶音。
頭尾都有短淡入淡出，避免爆音。

用法：python3 tools/make_sfx.py
"""

import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
RATE = 44100


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print(f"wrote {name} ({len(samples) / RATE:.3f} s)")


def fade(samples, fin=0.003, fout=0.012):
    n_in, n_out = int(fin * RATE), int(fout * RATE)
    n = len(samples)
    for i in range(n):
        g = 1.0
        if i < n_in:
            g = i / n_in
        if i >= n - n_out:
            g = min(g, (n - 1 - i) / n_out)
        samples[i] *= g
    return samples


def lowpass(samples, k):
    out, y = [], 0.0
    for s in samples:
        y += k * (s - y)
        out.append(y)
    return out


def shoot():
    dur = 0.1
    n = int(dur * RATE)
    rnd = random.Random(3)
    out, phase = [], 0.0
    noise = 0.0
    for i in range(n):
        t = i / n
        freq = 1400 * (1 - t) ** 1.6 + 260  # 下滑
        phase += freq / RATE
        sq = 1.0 if (phase % 1.0) < 0.35 else -1.0  # 35% 脈寬的方波
        if i % 6 == 0:
            noise = rnd.uniform(-1, 1)
        env = (1 - t) ** 2
        out.append((sq * 0.8 + noise * 0.2 * (1 - t)) * env * 0.32)
    return fade(lowpass(out, 0.45))


def pickup():
    notes = [(659.25, 0.06), (880.0, 0.06), (1318.5, 0.13)]  # E5 A5 E6
    out, phase = [], 0.0
    for k, (f, d) in enumerate(notes):
        n = int(d * RATE)
        for i in range(n):
            t = i / n
            # 每個音帶一點上滑，最後一音加顫音
            freq = f * (1 + 0.03 * t) * (1 + (0.01 * math.sin(2 * math.pi * 18 * i / RATE) if k == 2 else 0))
            phase += freq / RATE
            sq = 1.0 if (phase % 1.0) < 0.5 else -1.0
            tri = 4 * abs((phase % 1.0) - 0.5) - 1
            env = 1.0 if k < 2 else (1 - t) ** 1.3
            out.append((sq * 0.45 + tri * 0.55) * env * 0.38)
    return fade(lowpass(out, 0.5), fin=0.002, fout=0.02)


def main():
    write("shoot.wav", shoot())
    write("pickup.wav", pickup())


if __name__ == "__main__":
    main()
