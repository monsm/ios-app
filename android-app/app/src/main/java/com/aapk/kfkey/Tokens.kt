package com.aapk.kfkey

import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 设计令牌 —— 与 iOS **App/Core/Theme.swift** 逐值同源 (2026-10-22 对齐版)。
 *
 * ⚠ 上一版这里写着「与 iOS 的 App/Core/DesignSystem.swift 数值逐字相同」——
 *   那句话是假的, 三处都不成立, 已在重写时删掉:
 *   ① App/Core/DesignSystem.swift **已被删除**, Theme.swift:394 自己记着
 *      「2026-10-21 从已删的 DesignSystem.swift 迁入」。引用一个不存在的文件 = 无法核对。
 *   ② 旧 Radius 写着「card 22 / control 16 / tile 18 与 iOS 同值」, 而 iOS 当时是 16/12/14。
 *   ③ 旧注释标的消费点行号 (MainActivity.kt:687 / :685) 与实际 (696 / 698) 差了十来行。
 *
 * ⚠ **只留真有消费点的成员**（2026-10-22 收紧）。
 *   iOS 侧有 tools/apisig.js 的「零使用令牌」检查盯着, 声明了没人用就报; Android 没有这道闸门。
 *   所以本文件改成"消费点驱动": 没有消费点的成员一律删掉, 而不是留着凑一个"看起来完整"的令牌表。
 *   被删掉的成员与理由 (想加回来时先读这一段):
 *     · Space.xxs(2) / Space.rowGap(8) / Space.colGap(12) / Space.tile(14) / Space.control(12)
 *       —— 本端只有一屏一卡, 没有卡片流/双列网格/瓦片, 这些间距无处落地。
 *     · Space.align(29) —— 范式 5.4 的"文字对齐线"。本端各屏都是**居中排版**, 没有左对齐的
 *       文字块, 这条线没有可对齐的对象。**规则本身没丢**, 记在这里: 一旦出现左对齐正文块,
 *       它的左边距必须是 gutter(14) + card(16) - 1 = 29, 不是 24。
 *     · Radius.cardLg(34) / inner(12) / tile(14) / chip(14) / min(8) / shell(40) / device(44)
 *       —— 没有渐变主视觉卡、没有缩略图、没有网格瓦片、没有顶部胶囊、没有展示壳、没有设备样机。
 *         (shell 是 iOS 侧同步删除的: 本 App 没有展示壳层, 见 docs/GLASS/DEVIATIONS.md §5)
 *     · Icon.xs(12) / sm(16) / xl(44) / lock(72) / empty(28)
 *       —— 本端没有独立图标位: 圆盘/齿轮/关闭/喇叭全是自绘 Canvas, 尺寸在各自的 Canvas 里算。
 *   若下一轮真的要用, 加回来的同时**必须**把消费点写进注释 —— 否则又变成一次"零引用冒充完整"。
 *
 * 单位纪律: dp 与 pt 不是同一个单位。Android 最小触达 **48dp**, iOS 是 **44pt**, 两者不许混成一个数。
 */

internal object KfTokens {

    /**
     * 间距 (4dp 基数)。逐值对账 iOS App/Core/Theme.swift:171-204 的 enum XSpace。
     */
    object Space {
        val xs = 4.dp
        val xsm = 6.dp           // = iOS XSpace.xs  (Theme.swift:173)
        val s = 8.dp            // = iOS XSpace.s   (Theme.swift:174)
        val m = 12.dp           // = iOS XSpace.m   (Theme.swift:175)
        val l = 16.dp           // = iOS XSpace.l   (Theme.swift:176)
        val xl = 24.dp          // = iOS XSpace.xl  (Theme.swift:177)

        /** 屏幕左右边距 **14** —— 范式 5.1 实测 3.62% 屏宽; iOS 同为 14 (Theme.swift:182)。
         *  旧值 16 是 iOS 平台惯例值, 不是这个设计值。它是根 token: 卡片宽度与大环直径都由它派生。 */
        val gutter = 14.dp
        /** 区块之间 28 —— 范式 5.1 的 s7 (= iOS XSpace.section, Theme.swift:187)。 */
        val section = 28.dp
        /** 页面顶部留白 40 —— 范式 5.1 的 s8 (= iOS XSpace.pageTop, Theme.swift:189)。 */
        val pageTop = 40.dp
        /** 卡片内边距 16 —— 范式 5.1 的 s4 (= iOS XSpace.card, Theme.swift:192)。 */
        val card = 16.dp
    }

    /**
     * 圆角。逐值对账 iOS App/Core/Theme.swift:206-225 的 enum XRadius。
     */
    object Radius {
        /** 应用体标准卡片 **24** (范式 5.2 实测 23.6)。 = iOS XRadius.card (Theme.swift:208) */
        val card = 26.dp
        /** 控件 / 按钮 12。 = iOS XRadius.control (Theme.swift:214)。
         *  主按钮用这个而不是胶囊: iOS XPrimaryButtonStyle 用的是 XRadius.control
         *  (App/Core/Components.swift:277/280), 两端按钮同一个形状。 */
        val control = 12.dp
    }

    /**
     * 触达尺寸。
     *
     * ⚠ **这是 Android 独有的口径, 不是 iOS 的 44pt**。
     *   iOS 的 XHit.min = 44 (App/Core/Theme.swift:230) 是 HIG 的 pt 值;
     *   Android 的无障碍最小触达是 48dp (Material / TalkBack 口径)。
     *   两个数不能互相替换, 也不能取平均 —— 在 Android 上写 44.dp 就是不达标。
     */
    object Hit {
        val min = 48.dp
        /** 紧凑行的**视觉高度** 20dp。范式 7.7 明确: 视觉行高与最小触达是两件事,
         *  「高度 44pt」那种写法是把最小触达当成了视觉行高。 */
        val metricRow = 20.dp
    }

    /**
     * 图标尺寸。逐值对账 iOS App/Core/Theme.swift:234-242 的 enum XIcon。
     * 范式 10: 全 App 只用这一套, 不许在各屏就地写 30.dp / 3.5f 这种裸值。
     */
    object Icon {
        // 规范 §10 的图标尺寸是**固定七档**：12 / 13 / 17 / 20 / 22 / 28 / 34。
        // iOS 侧已把不在档位上的 16/26/44/72 全部改掉（lg 从 26 → **28**）。
        // 本端原来还是 26 —— 两端同一个令牌不同值，是 tokendrift 抓不到的那类漂移
        // （tokendrift 只对账颜色，尺寸由本文件自己保证）。
        /** 20dp —— 齿轮画布 / 关闭与喇叭字形画布。 = iOS XIcon.md */
        val md = 20.dp
        /** 28dp —— 齿轮本体画布（规范 §10 档位 6）。 = iOS XIcon.lg */
        val lg = 28.dp
    }
}

/**
 * 字阶 —— 规范 §4.2，与 iOS 的 `XText` (App/Core/Theme.swift) 逐值同源。
 *
 * 为什么现在才补：本端此前把字号散写在调用点，于是出现了 `15.sp` ——
 * 那正是规范点名批评的 HIG `subheadline` 默认值（规范已下修成 14）。
 * iOS 侧 766 处排版全部收到 `XText` 之后，本端也补一个，两边才谈得上“同源”。
 *
 * 规范原话：**已全线下修 34→30 / 22→19 / 20→18 / 17→16 / 15→14 / 13→12 / 12→11**。
 * 所以这里的数**不是** Compose 的 `Typography` 默认值，是规范实测值。
 */
object Type {
    /** 56 Bold -1.5 —— 大环内数字 */
    val displayNumber = 56.sp
    /** 36 Bold -0.6 */
    val display = 36.sp
    /** 30 Bold -0.4 —— 页面大标题 */
    val largeTitle = 30.sp
    /** 19 Bold -0.3 —— 卡片主标题 */
    val title2 = 19.sp
    /** 18 Semibold -0.2 —— 区块标题 */
    val title3 = 18.sp
    /** 16 Semibold -0.2 —— 行标题 */
    val headline = 16.sp
    /** 16 Regular -0.1 —— 正文 */
    val body = 16.sp
    /** 14 Regular 0 —— 卡片副标题、卡头链接 */
    val subhead = 14.sp
    /** 12 Regular 0 —— 辅助说明 */
    val footnote = 12.sp
    /** 11 Medium +0.1 —— 图表轴标签（极限值） */
    val caption = 11.sp
}
