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




def clip_check(path: str) -> None:
    """检测「横向溢出」：内容宽度超过屏幕时，左右两侧会被裁掉。

    2026-11-05（Round 66）：锁设置页的三枚容量环合计 408pt 而可用宽度只有 ~336pt，
    整页内容被撑宽、左右各裁一条。这种缺陷**闸门和编译都发现不了**，只有截图能看见。

    判据：取最左一列像素，统计「深色行」占比。正常页面文字有安全边距（gutterCard ≈ 16.6pt），
    左边缘应是纯背景 → 深色行 ≈ 0；一旦内容被裁，文字会直接压到 x=0。

    实测标定：锁设置页（已知溢出）70/874 行；其余 14 张子页截图全部 1/874 行。
    """
    im = Image.open(path).convert("RGB")
    w, h = im.size
    # 2026-11-05：只看中间带。整页成像的顶部有状态栏、底部有浮动 Tab 栏，
    # 它们本来就贴到屏幕边缘，会把「左边缘深色行」的占比抬到 3%–8%，造成误报。
    top, bottom = int(h * 0.06), int(h * 0.90)
    dark = 0
    rows = range(top, bottom, 3)
    for y in rows:
        px = im.getpixel((1, y))
        if px[0] < 120 and px[1] < 120 and px[2] < 120:
            dark += 1
    total = len(list(rows)) or 1
    ratio = dark / total
    verdict = "CLIPPED? 左侧文字贴边" if ratio > 0.02 else "ok"
    print("  %-28s %5.1f%%  %s" % (os.path.basename(path), ratio * 100, verdict))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    args = sys.argv[1:]
    if args and args[0] == "--clip":
        print("左侧裁切检测（深色行占比 > 2% 即疑似横向溢出）：")
        for p in args[1:]:
            clip_check(p)
    else:
        for p in args:
            analyse(p)