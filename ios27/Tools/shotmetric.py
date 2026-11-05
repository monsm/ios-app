#!/usr/bin/env python3
"""shotmetric.py —— 截图的客观测量工具（不使用肉眼判断）。

2026-11-05（Round 36）：前几轮我两次用「肉眼 + 单色阈值」判断截图里的
「空白卡 / 卡片被拆开」，两次都判断错了：

  · 第一次把卡片之间的**阴影压暗带**当成空卡；
  · 第二次把**卡面颜色**当成背景色，于是把卡内空白当成了卡间缝。

这个脚本用三种稳健判据代替肉眼：
  1) 取竖线，统计颜色直方图 —— 主色（卡面）与次主色（页面背景）**分别打印**，
     不做假设；
  2) 「均匀带」检测：连续 >=8px 且通道极差 <=3 的段落，按颜色分组打印，
     这样卡间缝（含阴影）、卡内空白、文字行可以区分；
  3) 卡片数与「VCard2 个数」对照由人工完成（脚本只给客观事实）。

用法：python3 Tools/shotmetric.py <png> [<png> ...]
"""
import sys
import os
from collections import Counter

try:
    from PIL import Image
except Exception as exc:      # CI 上不一定装 Pillow
    print("PIL unavailable:", exc)
    sys.exit(0)


def analyse(path: str) -> None:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    x = w // 2
    px = [im.getpixel((x, y)) for y in range(h)]

    print("===", os.path.basename(path), "size", w, h)
    common = Counter(px).most_common(3)
    for color, count in common:
        print("   color %s  x%d" % (color, count))

    # 均匀带
    bands = []
    start = 0
    for y in range(1, h):
        a, b = px[y], px[y - 1]
        if max(abs(a[i] - b[i]) for i in range(3)) > 2:
            if y - start >= 8:
                seg = px[start:y]
                mn = tuple(min(s[i] for s in seg) for i in range(3))
                mx = tuple(max(s[i] for s in seg) for i in range(3))
                if max(mx[i] - mn[i] for i in range(3)) <= 3:
                    bands.append((start, y, y - start, mn))
            start = y

    # 按颜色归类，便于一眼看出「卡面 / 卡间缝 / 其它」
    buckets = {}
    for b in bands:
        buckets.setdefault(b[3], []).append(b)

    print("   均匀带 %d 段，按颜色分组：" % len(bands))
    for color, items in sorted(buckets.items(), key=lambda kv: -len(kv[1])):
        total = sum(i[2] for i in items)
        print("     color %s  %d 段  合计 %dpx" % (color, len(items), total))
    tallest = sorted(bands, key=lambda b: -b[2])[:6]
    for b in tallest:
        print("     最高带 y %4d-%4d  %3dpx  color=%s" % b)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    for p in sys.argv[1:]:
        analyse(p)
