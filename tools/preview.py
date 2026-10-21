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
HAIRLINE    = (50, 50, 54)   # XPalette.hairline dark 0x323236
HAIRSTRONG  = (58, 58, 64)   # XPalette.hairlineStrong dark 0x3A3A40
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

def render_cyclering():
    """XCycleRing — 周期进度环三态"""
    W, H = 402, 200
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    cases = [(30, 60, "30", "天后", OK), (12, 60, "12", "天后", OK), (65, 60, "该做", "保养", WARN)]
    x = S(16)
    for elapsed, period, head, cap, tint in cases:
        cx = x + S(48)
        cy = H // 2
        R_OUT = S(44)
        lw = max(S(6), int(R_OUT*0.08))
        r = R_OUT - lw//2 - 1
        dr.ellipse([cx-r, cy-r, cx+r, cy+r], outline=HAIRLINE+(128,), width=lw)
        frac = min(elapsed/period, 1.0)
        if frac > 0.001:
            dr.arc([cx-r, cy-r, cx+r, cy+r], -90, -90+360*frac, fill=tint+(255,), width=lw)
        # 圆心
        text_center(dr, cx, cy-S(9), head, 15, TEXT)
        text_center(dr, cx, cy+S(8), cap, 7, tint)
        x += S(126)

    return save(img, "cyclering")

def render_seclamps():
    """SecurityPage — 三盏状态灯（带光环）"""
    W, H = 402, 220
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    panel(img, S(16), S(14), S(370), S(192))
    text(dr, (S(32), S(28)), "本机数据正常", 16)
    text(dr, (S(32), S(50)), "凭证 / 审计链 / 数据完整性 全部通过", 10, TEXT_SUB)
    dr.line([S(32), S(72), S(370), S(72)], fill=HAIRLINE+(255,), width=1)

    lamps = [("凭证", "无风险", True), ("审计链", "完整", True), ("数据", "2 项", False)]
    cx0 = S(16) + S(370)/6
    for k, (lab, det, ok) in enumerate(lamps):
        tone = OK if ok else WARN
        cx = cx0 + k*(S(370)/3)
        cy = S(14) + S(120)
        dr.ellipse([cx-S(15), cy-S(15), cx+S(15), cy+S(15)], fill=tone+(41,))
        dr.ellipse([cx-S(6), cy-S(6), cx+S(6), cy+S(6)], fill=tone+(255,))
        dr.ellipse([cx-S(3), cy-S(3), cx-S(1), cy-S(1)], fill=SPECULAR+(140,))
        text_center(dr, cx, cy+S(22), lab, 9, TEXT_SUB)
        text_center(dr, cx, cy+S(38), det, 9, tone)

    return save(img, "seclamps")

def render_stepbar():
    """XStepBar — 带标题的步骤指示器（三种进度）"""
    W, H = 402, 260
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    titles = ["选分区", "设口令", "导出前体检", "完成"]
    cases = [0, 1, 3]
    y = S(20)
    for cur in cases:
        text(dr, (S(16), y), f"第 {cur+1} 步", 9, TEXT_TERT)
        y += S(16)
        x = S(16)
        for i, t in enumerate(titles):
            ACTIVE = (i == cur)
            PAST = (i < cur)
            # 圆点
            cx = x + S(13)
            cy = y + S(13)
            if ACTIVE:
                dr.ellipse([cx-S(13), cy-S(13), cx+S(13), cy+S(13)], fill=ACCENT+(255,))
            elif PAST:
                dr.ellipse([cx-S(13), cy-S(13), cx+S(13), cy+S(13)], fill=ACCENT+(41,))
                dr.ellipse([cx-S(13), cy-S(13), cx+S(13), cy+S(13)], outline=ACCENT+(255,), width=2)
            else:
                dr.ellipse([cx-S(13), cy-S(13), cx+S(13), cy+S(13)], outline=HAIRLINE+(255,), width=2)
            # 内容
            if PAST:
                text_center(dr, cx, cy-S(6), "v", 11, ACCENT)
            else:
                text_center(dr, cx, cy-S(7), str(i+1), 11, ON_ACCENT if ACTIVE else TEXT_TERT)
            x += S(26) + S(4)
            # 标题
            col = TEXT if ACTIVE else (TEXT_SUB if PAST else TEXT_TERT)
            dr.text((x, y + S(6)), t, font=F(9), fill=col)
            x += S(len(t)*10 + 10)
            # 连接线
            if i < len(titles)-1:
                lw_total = (W - S(32)) - x
                line_len = S(16)
                ly = cy
                lc = ACCENT if PAST else HAIRLINE
                dr.line([x+S(2), ly, x+S(2)+line_len, ly], fill=lc+(180,), width=2)
                x += line_len + S(8)
        y += S(56)

    return save(img, "stepbar")

def render_xrows():
    """XRow — 图标徽章版（before / after）"""
    W, H = 402, 340
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    rows = [
        ("*", "本机数据保护", "应用锁 / 审计 / 销毁", "已开启", OK),
        ("o", "隐私与伪装", "偷窥模式 / 伪装 / 访客通道", None, TEXT_SUB),
        ("#", "设备管理", "排序 / 分组 / 批量", "3 把", TEXT_SUB),
        ("^", "校准门锁时间", None, None, TEXT_SUB),
        ("~", "备份与恢复", "全量导出 / 导入", "3 天前", TEXT_SUB),
        ("!", "检查固件更新", None, "V5.2.9", WARN),
    ]

    # AFTER (带徽章)
    text(dr, (S(16), S(10)), "AFTER  图标徽章 28pt + 12% 同色底", 10, TEXT)
    y = S(30)
    for icon, title, sub, val, tone in rows:
        # 徽章
        dr.rounded_rectangle([S(16), y+S(8), S(16)+S(28), y+S(8)+S(28)], S(8), fill=tone+(31,))
        text_center(dr, S(16)+S(14), y+S(13), icon, 12, tone)
        # 文字
        text(dr, (S(16)+S(40), y+S(11)), title, 14, TEXT)
        if sub: text(dr, (S(16)+S(40), y+S(30)), sub, 10, TEXT_SUB)
        # 值
        if val:
            bb = dr.textbbox((0,0), val, font=F(12))
            dr.text((W-S(40)-(bb[2]-bb[0]), y+S(16)), val, font=F(12), fill=TEXT_SUB)
        # chevron
        text(dr, (W-S(28), y+S(15)), ">", 10, TEXT_TERT)
        y += S(44)

    # BEFORE (无徽章)
    text(dr, (S(16), y+S(10)), "BEFORE  图标裸放, 无底色", 10, TEXT)
    y += S(30)
    for icon, title, sub, val, tone in rows[:3]:
        text(dr, (S(16)+S(10), y+S(11)), icon, 11, tone)
        text(dr, (S(16)+S(40), y+S(11)), title, 14, TEXT)
        if sub: text(dr, (S(16)+S(40), y+S(30)), sub, 10, TEXT_SUB)
        if val:
            bb = dr.textbbox((0,0), val, font=F(12))
            dr.text((W-S(40)-(bb[2]-bb[0]), y+S(16)), val, font=F(12), fill=TEXT_SUB)
        text(dr, (W-S(28), y+S(15)), ">", 10, TEXT_TERT)
        y += S(44)

    return save(img, "xrows")

def render_buttons():
    """按钮三式 + 主按钮顶部高光"""
    W, H = 402, 300
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    def btn(y, label, fill, text_col, gradient=False, stroke=None):
        x0, x1 = S(16), W-S(16)
        h = S(48)
        r = S(12)
        # 底
        dr.rounded_rectangle([x0, y, x1, y+h], r, fill=fill)
        # 顶部高光 (竖向渐变 0.10 → 0)
        if gradient:
            for i in range(h):
                a = int(0.10 * 255 * (1 - i/h)**1.2)
                dr.rounded_rectangle([x0, y+i, x1, y+i+1], 0, fill=SPECULAR+(a,))
            # 把四角重新圆一下
            dr.rounded_rectangle([x0, y, x1, y+h], r, outline=None)
        if stroke:
            dr.rounded_rectangle([x0, y, x1, y+h], r, outline=stroke, width=1)
        text_center(dr, (x0+x1)//2, y+h//2-S(9), label, 15, text_col)

    btn(S(30), "按住开锁", ACCENT+(255,), ON_ACCENT, gradient=True)
    btn(S(96), "换电指引", (0,0,0,0), ACCENT_TXT, stroke=ACCENT+(128,))
    btn(S(162), "彻底删除", DANGER+(26,), DANGER)

    text(dr, (S(16), S(12)), "主按钮 (顶部高光) / 次按钮 / 危险按钮", 10, TEXT_TERT)
    return save(img, "buttons")

def render_panels():
    """XPanel — group vs hero (改前像素相同 / 改后有区分)"""
    W, H = 402, 460
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    def plate(x0, y, w, h, kind, tone=None, label="", sub=""):
        r = S(16)
        # 底
        dr.rounded_rectangle([x0, y, x0+w, y+h], r, fill=SURFACE+(255,))
        if kind == "hero":
            # ① 品牌色微洗染 3%
            dr.rounded_rectangle([x0, y, x0+w, y+h], r, fill=ACCENT+(8,))
            # ② 顶部微光 (specular 5.5% → clear)
            for i in range(int(h*0.55)):
                a = int(0.055 * 255 * (1 - i/(h*0.55))**1.3)
                if a <= 0: break
                dr.rounded_rectangle([x0, y+i, x0+w, y+i+1], 0, fill=SPECULAR+(a,))
            dr.rounded_rectangle([x0, y, x0+w, y+h], r, outline=HAIRSTRONG+(255,), width=1)
        else:
            edge = HAIRLINE if tone is None else tone
            alpha = 255 if tone is None else 89
            dr.rounded_rectangle([x0, y, x0+w, y+h], r, outline=edge+(alpha,), width=1)
        pad = S(16)
        if label: text(dr, (x0+pad, y+pad), label, 13)
        if sub:   text(dr, (x0+pad, y+pad+S(20)), sub, 10, TEXT_SUB)

    # BEFORE: 两者完全相同
    text(dr, (S(16), S(8)), "BEFORE  group 与 hero 像素级相同（kind 只影响 padding）", 9, TEXT_TERT)
    plate(S(16), S(24),  W-S(32), S(70), "group", None, "普通分组卡", "hairline 描边")
    plate(S(16), S(102), W-S(32), S(70), "hero",  None, "所谓「主角卡」", "改前与上面完全一样")

    # AFTER: hero 有顶部微光 + hairlineStrong + 外投影
    text(dr, (S(16), S(190)), "AFTER  hero = 铜色洗染 3% + 顶部微光 5.5% + hairlineStrong + 外投影", 9, TEXT_TERT)
    plate(S(16), S(206), W-S(32), S(80), "group", None, "普通分组卡", "hairline 描边")
    # hero with shadow
    sh = Image.new('RGBA', img.size, (0,0,0,0))
    sd = ImageDraw.Draw(sh)
    for i in range(S(12), 0, -1):
        a = int(0.22 * 255 * (1 - i/S(12))**1.8 * 0.35)
        sd.rounded_rectangle([S(16)-i, S(300)-i+4, W-S(16)+i, S(300)+S(80)+i+4], S(16), fill=(0,0,0,a))
    img2 = Image.alpha_composite(img.convert('RGBA'), sh).convert('RGB')
    img.paste(img2, (0,0))
    dr = ImageDraw.Draw(img, "RGBA")
    plate(S(16), S(300), W-S(32), S(80), "hero", None, "主角卡", "现在看得出是主角")
    text(dr, (S(16), S(392)), "硬事实：7 处 kind:.hero 里有 5 处不传 tone ——", 9, TEXT_TERT)
    text(dr, (S(16), S(406)), "改之前那 5 张卡（设备/固件/网关/加密狗/安全页首卡）", 9, TEXT_TERT)
    text(dr, (S(16), S(420)), "与同屏普通卡没有任何视觉差别。", 9, TEXT_TERT)

    return save(img, "panels")


def render_skeleton():
    """XSkeleton — 首屏骨架屏"""
    W, H = 402, 400
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")
    text(dr, (S(16), S(10)), "XSkeleton — 3 块 · 错开内部高度 · 流光扫过", 9, TEXT_TERT)

    y = S(30)
    for i in range(3):
        block_h = S(108)
        x0, x1 = S(16), W-S(16)
        dr.rounded_rectangle([x0, y, x1, y+block_h], S(16), fill=SURFACE+(255,))
        # 内部占位条
        inner = [14, 10] if i % 2 == 0 else [10, 14, 10]
        cy = y + S(16)
        for hh in inner:
            w = S(180) if hh > 12 else (x1-x0-S(32))
            dr.rounded_rectangle([x0+S(16), cy, x0+S(16)+w, cy+S(hh)], S(4), fill=SURFACE_ALT+(255,))
            cy += S(hh) + S(8)
        # 流光 (右侧 1/3 处示意)
        sx = x0 + (x1-x0)*0.62
        sw = (x1-x0)*0.45
        for k in range(int(sw)):
            a = int(0.06*255*(1-abs(k/sw-0.5)*2))
            if a<=0: continue
            dr.rounded_rectangle([sx+k, y+S(1), sx+k+1, y+block_h-S(1)], 0, fill=SPECULAR+(a,))
        y += block_h + S(16)

    return save(img, "skeleton")


def render_tiles():
    """XMetricTile + XStatusPill + XEmptyState — 三个基础组件的形状"""
    W, H = 402, 400
    img = new_canvas(W, H)
    dr = ImageDraw.Draw(img, "RGBA")

    # ── XMetricTile × 3 (surfaceAlt 底, 半径 tile 14, pad 14) ──
    text(dr, (S(16), S(8)), "XMetricTile — surfaceAlt + XRadius.tile + pad 14", 9, TEXT_TERT)
    tiles = [("1.2%", "告警率", WARN, "@"), ("0", "有告警的天", OK, "#"), ("84", "总开门", TEXT_SUB, "o")]
    tw = (W - S(32) - S(24)) // 3
    for i, (val, lab, tone, icon) in enumerate(tiles):
        x0 = S(16) + i*(tw + S(12))
        y0 = S(26)
        th = S(84)
        dr.rounded_rectangle([x0, y0, x0+tw, y0+th], S(14), fill=SURFACE_ALT+(255,))
        text(dr, (x0+S(14), y0+S(14)), icon, 11, tone)
        text(dr, (x0+S(14), y0+S(34)), val, 20, TEXT)
        text(dr, (x0+S(14), y0+S(62)), lab, 9, TEXT_SUB)

    # ── XStatusPill × 4 (胶囊, pad h8/v3, tone 12% 底 + 24% 描边) ──
    text(dr, (S(16), S(128)), "XStatusPill — tone 12% 底 / 24% 描边 / caption 文字", 9, TEXT_TERT)
    pills = [("已连接", OK), ("连接中", ACCENT), ("未连接", TEXT_SUB), ("注意", WARN)]
    px = S(16)
    py_ = S(146)
    for label, tone in pills:
        pw = S(len(label)*15 + 30)
        dr.rounded_rectangle([px, py_, px+pw, py_+S(24)], S(12), fill=tone+(31,))
        dr.rounded_rectangle([px, py_, px+pw, py_+S(24)], S(12), outline=tone+(61,), width=1)
        text(dr, (px+S(10), py_+S(5)), label, 10, tone)
        px += pw + S(8)

    # ── XEmptyState (pad 24, 图标 44, headline + subheadline) ──
    text(dr, (S(16), S(196)), "XEmptyState — pad 24 / 图标 44 / 标题 headline + 说明 subheadline", 9, TEXT_TERT)
    y0 = S(214)
    text_center(dr, W//2, y0+S(6), "o", 22, TEXT_TERT)
    text_center(dr, W//2, y0+S(46), "还没有凭证", 14, TEXT)
    text_center(dr, W//2, y0+S(70), "点右上角 + 添加第一份授权。", 11, TEXT_SUB)
    dr.rounded_rectangle([S(16), y0, W-S(16), y0+S(112)], S(16), outline=HAIRLINE+(60,), width=1)

    return save(img, "tiles")


RENDERERS = {
    "codering": render_code_ring,
    "alarmchart": render_alarm_chart,
    "dayclock": render_dayclock,
    "battery": render_battery,
    "keysrows": render_keysrows,
    "alarmseverity": render_alarmseverity,
    "cyclering": render_cyclering,
    "seclamps": render_seclamps,
    "stepbar": render_stepbar,
    "xrows": render_xrows,
    "buttons": render_buttons,
    "panels": render_panels,
    "skeleton": render_skeleton,
    "tiles": render_tiles,
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
