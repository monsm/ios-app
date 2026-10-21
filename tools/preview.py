#!/usr/bin/env python3
"""
渲染验证工具 —— 把 SwiftUI 组件按真实参数画成 PNG, 用眼睛看。

为什么需要它:
    21 道静态闸门查的是语法 / 令牌 / 对比度 / 括号平衡,
    查不出「码值压到环线上」「刻度被容器裁掉」「整屏 40% 是空白」这类
    几何与构图问题。这些只有画出来才看得见。

    已经靠它抓到 4 个真缺陷:
      1. XCodeRing: 56pt 码值压环线 (8 位时直接穿过)
      2. DoorFront: Spacer + maxHeight 导致布局退化, 整屏 40% 空白
      3. AlarmCenter: 柱状图容器 56 < 内容 58, 刻度被裁且撞下一行
      4. DoorFront: 锁体直径 52% 在 402pt 屏上偏小, 主体撑不起整屏

用法:
    python tools/preview.py <组件名>
    python tools/preview.py --list

输出到 docs/redesign/preview/<组件名>.png

注意: 这是**近似渲染**, 不是 SwiftUI 真机截图。
    - 字体用 Noto Sans SC 代替 SF Pro / SF Rounded
    - 渐变、blur、blendMode 都是近似
    - 布局按 SwiftUI 的 VStack/HStack 规则手工推算
    用途是查构图与几何是否合理, 不是校验像素级还原。
"""

import sys
import os
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "docs", "redesign", "preview")

# ── 设计令牌 (与 App/Core/Theme.swift 的 XPalette 对齐, 取 dark 档) ──
CANVAS      = (10, 10, 11)
SURFACE     = (22, 22, 24)
SURFACE_ALT = (31, 31, 34)
SUNKEN      = (18, 18, 20)
HAIRLINE    = (50, 50, 54)
TEXT        = (245, 245, 247)
TEXT_SUB    = (160, 160, 172)
TEXT_TERT   = (136, 136, 146)
ACCENT      = (217, 139, 69)
ACCENT_TXT  = (232, 160, 92)
ON_ACCENT   = (10, 10, 11)
OK          = (61, 214, 140)
WARN        = (245, 165, 36)
DANGER      = (255, 107, 107)
SPECULAR    = (200, 200, 212)

CJK = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
SCALE = 2   # 2x 渲染

def F(size):
    return ImageFont.truetype(CJK, int(size * SCALE))

def S(v):
    return int(v * SCALE)

def new_canvas(w_pt, h_pt, bg=CANVAS):
    return Image.new("RGB", (S(w_pt), S(h_pt)), bg)

def rounded(dr, box, r, fill=None, outline=None, width=1):
    dr.rounded_rectangle(box, S(r), fill=fill, outline=outline, width=width)

def panel(img, x, y, w, h, r=16, fill=SURFACE, edge=None):
    dr = ImageDraw.Draw(img, "RGBA")
    rounded(dr, [x, y, x + w, y + h], r, fill=fill + (255,))
    if edge:
        rounded(dr, [x, y, x + w, y + h], r, outline=edge + (255,), width=1)

def text(dr, pos, s, size, color=TEXT, bold=False):
    dr.text((pos[0], pos[1]), s, font=F(size), fill=color)

def text_center(dr, cx, y, s, size, color=TEXT):
    f = F(size)
    bb = dr.textbbox((0, 0), s, font=f)
    dr.text((cx - (bb[2] - bb[0]) // 2, y), s, font=f, fill=color)

def sec_label(dr, x, y, s, size=11):
    text(dr, (x, y), s, size, TEXT_TERT)

def save(img, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".png")
    img.save(path)
    print("saved:", path, img.size)
    return path


# ═══════════════════════════════════════════════════════════════
# 组件渲染器
# ═══════════════════════════════════════════════════════════════

def render_code_ring():
    """XCodeRing — OTP 时效大卡三种状态"""
    W, H = 1240, 640
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    text(dr, (S(13), S(9)), "XCodeRing — OTP 页时效大卡", 10, TEXT)

    CARD_W, CARD_H = 384, 512
    def card(x0, y0, fraction, secs, warn, code, label, nxt):
        tint = WARN if warn else ACCENT
        c = Image.new("RGBA", (S(CARD_W), S(CARD_H)), (0, 0, 0, 0))
        cd = ImageDraw.Draw(c, "RGBA")
        rounded(cd, [0, 0, S(CARD_W) - 1, S(CARD_H) - 1], 16, fill=SURFACE + (255,))
        g = Image.new("RGBA", c.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(g)
        ccx, ccy = S(CARD_W) // 2, S(250)
        maxr = S(175)
        for rr in range(maxr, 0, -3):
            a = int((0.10 + 0.10 * fraction) * 255 * (1 - rr / maxr) ** 1.5)
            gd.ellipse([ccx - rr, ccy - rr, ccx + rr, ccy + rr], fill=tint + (a,))
        c = Image.alpha_composite(c, g)
        cd = ImageDraw.Draw(c, "RGBA")
        rounded(cd, [0, 0, S(CARD_W) - 1, S(CARD_H) - 1], 16, outline=tint + (60,), width=1)
        text(cd, (S(24), S(22)), label, 16)
        text(cd, (S(CARD_W - 56), S(24)), "30s", 13, TEXT_TERT)

        R_OUT, lw = S(140), S(11)
        cd.ellipse([ccx - R_OUT, ccy - R_OUT, ccx + R_OUT, ccy + R_OUT],
                   outline=HAIRLINE + (150,), width=lw)
        if fraction > 0.001:
            start, end = -90, -90 + 360 * fraction
            cd.arc([ccx - R_OUT, ccy - R_OUT, ccx + R_OUT, ccy + R_OUT],
                   start=start, end=end, fill=tint + (255,), width=lw)
            a = math.radians(end)
            px, py = ccx + R_OUT * math.cos(a), ccy + R_OUT * math.sin(a)
            dotr = lw * 0.62
            for sc, al in [(2.1, 60), (1.0, 255)]:
                rr = dotr * sc
                cd.ellipse([px - rr, py - rr, px + rr, py + rr], fill=tint + (al,))

        n = len(code.replace(" ", ""))
        cs = 56 if n <= 6 else (50 if n == 7 else 44)
        cf = F(cs)
        bb = cd.textbbox((0, 0), code, font=cf)
        cd.text((S(CARD_W) // 2 - (bb[2] - bb[0]) // 2, ccy - S(40)), code, font=cf, fill=TEXT)
        text_center(cd, S(CARD_W) // 2, ccy + S(66), f"{secs} 秒后刷新", 13,
                    WARN if warn else TEXT_TERT)
        text(cd, (S(24), S(CARD_H - 58)), "下一个", 12, TEXT_TERT)
        text(cd, (S(80), S(CARD_H - 60)), nxt, 15, TEXT_SUB)
        img.paste(c, (S(x0), S(y0)), c)

    card(24, 64, 0.83, 25, False, "483 921", "家门 · 登录码", "512 004")
    card(430, 64, 0.42, 13, False, "771 268", "工作台 · 二次验证", "338 190")
    card(836, 64, 0.13, 4, True, "902 415", "保险箱 · 应急", "664 072")
    return save(img, "codering")


def render_alarm_chart():
    """AlarmCenter — 24 小时柱状分布"""
    W, H = 402, 232
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    panel(img, S(16), S(14), S(370), S(204))
    sec_label(dr, S(32), S(28), "24 小时回放")

    counts = [0,0,1,0,2,3,1,0,1,2,4,2,1,0,2,5,3,2,1,1,0,2,3,1]
    peak = max(counts)
    base_y = S(174)
    x0, step = S(32), S(338) / 24
    sel = 15
    for h in range(24):
        c = counts[h]
        hgt = S(3) if c == 0 else S(10 + 34 * (c / peak))
        wid = S(7) if h == sel else S(3.5)
        x = x0 + h * step + step / 2
        col = ACCENT if h == sel else WARN
        al = 255 if h == sel else 184
        rounded(dr, [x - wid, base_y - hgt, x + wid, base_y], 2,
                fill=(col + (al,)) if c > 0 else (SURFACE_ALT + (255,)))
        if c > 0:
            dr.ellipse([x - S(1.7), base_y - hgt - S(3.2), x + S(1.7), base_y - hgt - S(0.2)],
                       fill=(ON_ACCENT if h == sel else DANGER) + (255,))
        if h % 6 == 0 or h == sel:
            text_center(dr, x, base_y + S(6), str(h), 8,
                        ACCENT_TXT if h == sel else TEXT_TERT)
    text(dr, (S(32), S(198)), "点某一小时，只看那一时段前后事件", 11, TEXT_SUB)
    return save(img, "alarmchart")


def render_dayclock():
    """XDayClock — 24 小时极坐标时钟"""
    W, H = 402, 260
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    panel(img, S(16), S(14), S(370), S(232))
    sec_label(dr, S(32), S(28), "一天里的开门分布")

    # 模拟 24 小时分布: 早晚两个峰
    opens = [0,0,0,0,0,0,1,4,7,3,2,2,3,2,2,3,5,9,12,8,4,2,1,0]
    alarms = [0]*24; alarms[7]=1; alarms[17]=1
    peak = max(opens)
    total = sum(opens)

    cx = S(16) + S(12) + S(78)
    cy = S(14) + S(232) // 2
    R_OUT = S(78)
    R_IN = R_OUT * 0.42

    def pt(r, deg):
        a = math.radians(deg)
        return (cx + r*math.cos(a), cy + r*math.sin(a))

    # 刻度
    for h in range(24):
        ang = -90 + h/24*360
        major = h % 6 == 0
        r0 = R_OUT - (S(8) if major else S(4))
        dr.line([pt(r0,ang), pt(R_OUT,ang)],
                fill=HAIRLINE + ((230 if major else 115),),
                width=(2 if major else 1))
    # 内圈
    dr.ellipse([cx-R_IN, cy-R_IN, cx+R_IN, cy+R_IN], fill=SURFACE_ALT+(140,))
    # 辐条
    lw = max(3, int(S(168*0.022)))
    for h in range(24):
        if opens[h] == 0: continue
        ang = -90 + h/24*360
        frac = opens[h]/peak
        ln = (R_OUT - R_IN - S(10)) * frac
        night = (h >= 22 or h < 6)
        col = ACCENT if not night else (int(ACCENT[0]*0.65), int(ACCENT[1]*0.65), int(ACCENT[2]*0.65))
        dr.line([pt(R_IN+S(2),ang), pt(R_IN+S(2)+ln,ang)], fill=col+(255,), width=lw)
        if alarms[h] > 0:
            tx, ty = pt(R_IN+S(2)+ln+S(7), ang)
            dr.ellipse([tx-S(2.6),ty-S(2.6),tx+S(2.6),ty+S(2.6)], fill=DANGER+(255,))

    # 圆心
    text_center(dr, cx, cy-S(10), str(total), 21, TEXT)
    text_center(dr, cx, cy+S(14), "次开门", 7, TEXT_TERT)

    # 右侧读数
    rx = S(16) + S(12) + S(156) + S(12)
    ry = S(70)
    for val, lab, note in [("12 时","9 次","最集中的一小时"), ("1 个","小时无人开门","安静的时段"), ("2 条","告警","红点标出的小时")]:
        text(dr, (rx, ry), val, 14)
        text(dr, (rx, ry+S(20)), lab, 11, TEXT_SUB)
        text(dr, (rx, ry+S(36)), note, 10, TEXT_TERT)
        ry += S(62)

    return save(img, "dayclock")

def render_battery():
    """XBatteryGauge — 电量仪表环三档"""
    W, H = 402, 200
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    panel(img, S(16), S(14), S(370), S(172))
    text(dr, (S(32), S(28)), "家门", 16)
    text(dr, (S(32), S(48)), "握手耗时 320ms · 信号 -58 dBm", 10, TEXT_SUB)

    cx = S(16) + S(12) + S(58)
    cy = S(14) + S(172) // 2 + S(6)
    R_OUT = S(50)
    lw = max(S(7), int(R_OUT*0.085))
    r = R_OUT - lw//2 - 1
    START, SWEEP = 135, 270

    def pt(rad, deg):
        a = math.radians(deg)
        return (cx + rad*math.cos(a), cy + rad*math.sin(a))

    # 三档演示用一个, 取 78%
    level = 78
    frac = level/100
    tint = OK if level > 20 else (WARN if level > 10 else DANGER)
    # 底弧
    dr.arc([cx-r, cy-r, cx+r, cy+r], START, START+SWEEP, fill=HAIRLINE+(140,), width=lw)
    # 前景
    dr.arc([cx-r, cy-r, cx+r, cy+r], START, START+SWEEP*frac, fill=tint+(255,), width=lw)
    # 末端点
    ex, ey = pt(r, START+SWEEP*frac)
    drr = lw*0.42
    dr.ellipse([ex-drr,ey-drr,ex+drr,ey+drr], fill=tint+(255,))
    # 圆心
    f1 = F(16); f2 = F(8)
    bb1 = dr.textbbox((0,0),str(level),font=f1)
    bb2 = dr.textbbox((0,0),"%",font=f2)
    tw = (bb1[2]-bb1[0]) + (bb2[2]-bb2[0])
    x0 = cx - tw//2
    dr.text((x0, cy-S(11)), str(level), font=f1, fill=TEXT)
    dr.text((x0 + (bb1[2]-bb1[0]), cy-S(3)), "%", font=f2, fill=TEXT_SUB)
    text_center(dr, cx, cy+S(8), "充足", 8, tint)

    # 右侧两个余量
    rx = S(16) + S(12) + S(116) + S(16)
    ry = S(14) + S(46)
    for icon_ch, val, lab in [("#", "3", "密码余量"), ("@", "2", "指纹余量")]:
        text(dr, (rx, ry), icon_ch, 10, TEXT_TERT)
        text(dr, (rx+S(18), ry-S(2)), val, 14, TEXT)
        text(dr, (rx+S(18), ry+S(16)), lab, 9, TEXT_SUB)
        ry += S(54)

    return save(img, "battery")

def render_keysrows():
    """KeysPage — 类型徽章 + 带数量的分段选择器"""
    W, H = 402, 300
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    # 分段选择器
    segs = [("全部 7", True), ("密码 4", False), ("指纹 2", False), ("临时码 1", False)]
    x = S(16); y = S(16)
    total_w = W - S(32)
    seg_w = total_w / 4
    dr.rounded_rectangle([x, y, x+total_w, y+S(32)], S(9), fill=SURFACE_ALT+(255,))
    for i, (lab, on) in enumerate(segs):
        sx = x + i*seg_w
        if on:
            dr.rounded_rectangle([sx+S(2), y+S(2), sx+seg_w-S(2), y+S(30)], S(7), fill=SURFACE+(255,))
        text_center(dr, sx+seg_w/2, y+S(9), lab, 10, TEXT if on else TEXT_SUB)

    # 凭证行 (小卡片列表)
    rows = [
        (0, "家门主密码", "妈妈 · 30 天后到期", "进行中", OK),
        (0, "保洁阿姨临时", "王阿姨 · 明天到期", "进行中", OK),
        (0, "备用密码", "未归属", "已排期", TEXT_SUB),
        (1, "爸爸左手拇指", "爸爸", "有效", OK),
        (2, "访客一次性", "快递", "进行中", OK),
        (0, "旧密码 (已停用)", "未归属", "已过期", DANGER),
        (1, "奶奶右手食指", "奶奶", "有效", OK),
    ]
    kinds = {0: ("$", ACCENT), 1: ("o", OK), 2: ("*", WARN)}
    ry = y + S(44)
    for kind, title, sub, state, tone in rows:
        icon, tint = kinds[kind]
        # 徽章
        dr.rounded_rectangle([S(20), ry, S(20)+S(32), ry+S(32)], S(8), fill=tint+(36,))
        text_center(dr, S(20)+S(16), ry+S(8), icon, 14, tint)
        # 文本
        text(dr, (S(64), ry), title, 14, TEXT)
        text(dr, (S(64), ry+S(20)), sub, 10, TEXT_SUB)
        # 状态胶囊
        pill_w = S(len(state)*11 + 14)
        dr.rounded_rectangle([W-S(20)-pill_w, ry+S(8), W-S(20), ry+S(26)], S(9), fill=tone+(28,))
        text_center(dr, W-S(20)-pill_w/2, ry+S(11), state, 9, tone)
        ry += S(38)

    return save(img, "keysrows")

def render_alarmseverity():
    """AlarmsPage — 严重度概览 + 告警行"""
    W, H = 402, 300
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    # 概览卡
    px, py_, pw = S(16), S(16), S(370)
    ch = S(96)
    panel(img, px, py_, pw, ch)
    lv3, lv2, lv1 = 3, 5, 4
    total = lv3+lv2+lv1
    bx, by = px+S(16), py_+S(18)
    bw = pw - S(32)
    x = bx
    for n, col in [(lv3, DANGER), (lv2, WARN), (lv1, (int(WARN[0]*0.55), int(WARN[1]*0.55), int(WARN[2]*0.55)))]:
        if n == 0: continue
        seg_w = (bw - S(4)) * n / total
        dr.rounded_rectangle([x, by, x+seg_w, by+S(8)], S(4), fill=col+(255,))
        x += seg_w + S(2)
    # 三级读数
    iy = by + S(26)
    ix = bx
    for lab, n, col in [("严重", lv3, DANGER), ("警告", lv2, WARN), ("提示", lv1, (int(WARN[0]*0.55), int(WARN[1]*0.55), int(WARN[2]*0.55)))]:
        dr.ellipse([ix, iy+S(2), ix+S(7), iy+S(9)], fill=col+(255,))
        t = f"{lab} {n}"
        dr.text((ix+S(12), iy), t, font=F(11), fill=(TEXT if n>0 else TEXT_TERT))
        ix += S(78)

    # 告警行 ×3
    rows = [
        ("防撬告警", "14:32 · 家门", DANGER),
        ("试错锁定", "11:08 · 家门", WARN),
        ("低电量", "09:15 · 家门", (int(WARN[0]*0.55), int(WARN[1]*0.55), int(WARN[2]*0.55))),
    ]
    ry = py_ + ch + S(16)
    for name, sub, col in rows:
        dr.rounded_rectangle([px, ry, px+pw, ry+S(52)], S(12), fill=SURFACE+(255,))
        dr.rounded_rectangle([px+S(2), ry+S(8), px+S(5), ry+S(44)], S(2), fill=col+(255,))
        # 三角图标
        text(dr, (px+S(16), ry+S(10)), "!", 12, col)
        text(dr, (px+S(34), ry+S(8)), name, 14, TEXT)
        text(dr, (px+S(34), ry+S(26)), sub, 10, TEXT_SUB)
        # 勾选按钮
        dr.ellipse([px+pw-S(40), ry+S(14), px+pw-S(16), ry+S(38)], outline=ACCENT+(255,), width=2)
        ry += S(56)

    return save(img, "alarmseverity")

RENDERERS = {
    "codering": render_code_ring,
    "alarmchart": render_alarm_chart,
    "dayclock": render_dayclock,
    "battery": render_battery,
    "keysrows": render_keysrows,
    "alarmseverity": render_alarmseverity,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--list", "-l"):
        print("可用组件:")
        for k in RENDERERS:
            print("  " + k)
        return
    for name in sys.argv[1:]:
        fn = RENDERERS.get(name)
        if not fn:
            print(f"未知组件: {name} (用 --list 看清单)")
            continue
        fn()


if __name__ == "__main__":
    main()
