package com.aapk.kfkey

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 设计令牌 —— 与 iOS 的 App/Core/DesignSystem.swift **数值逐字相同**（D9/D14）。
 * 2026-10-18 门面改造新增。
 *
 * 分工：
 *   · 几何/间距/圆角/字号/时长/曲线 —— 两端同源，改这里必须同步改 DesignSystem.swift；
 *   · 色板 —— **各端保留**（D14）：iOS 是浅色暖白 + 蓝，Android 是暗色 + 暖金。
 *     所以下面只声明"语义槽位"，具体色值仍来自 Theme.kt 的既有 val。
 *
 * 为什么单独一个文件而不是散在 MainActivity 里：
 *   散写必然漂移（本仓 iOS 侧已有"页面各自写死颜色"的先例）。
 */
internal object KfTokens {

    /** 间距 4/8 节奏 —— 与 iOS DS.Space 同值。 */
    object Space {
        val xxs = 2.dp
        val xs = 4.dp
        val s = 8.dp
        val m = 12.dp
        val l = 16.dp
        val xl = 24.dp
        val xxl = 32.dp
        val gutter = 16.dp
    }

    /** 圆角 —— 与 iOS DS.Radius 同值（card 22 / control 16 / tile 18）。 */
    object Radius {
        val card = 22.dp
        val control = 16.dp
        val tile = 18.dp
    }

    /** 触达：Android 平台最小值 48dp（**不与 iOS 的 44pt 混用**）。 */
    object Hit {
        val min = 48.dp
    }

    /** 图标尺寸 —— 与 iOS DS.Icon 同值。 */
    object Icon {
        val xs = 13.dp
        val sm = 16.dp
        val md = 20.dp
        val lg = 26.dp
        val xl = 44.dp
    }

    /** 动效时长（毫秒）—— 与 iOS DS.Motion / DS.Duration 对齐。 */
    object Duration {
        const val quick = 150
        const val standard = 250
        const val slow = 400
    }

    /**
     * 曲线控制点 —— 与 iOS 的 cubic-bezier 逐字相同。
     * 用法：CubicBezierEasing(KfTokens.Curve.soft.x1, ...)
     * 门面专属的 (.22,.76,.03,1) **不在这里**：Android 不做门面（D11）。
     */
    object Curve {
        /** 标准软（easeInOut）—— 对应 iOS DS.Motion.soft。 */
        val soft = floatArrayOf(0.42f, 0f, 0.58f, 1f)
        /** 出场（easeOut）—— 对应 iOS DS.Motion.exit。 */
        val exit = floatArrayOf(0f, 0f, 0.58f, 1f)
    }

    /** 中文排版下限：正文 12sp（iOS 侧是 .caption 12pt）。 */
    object Text {
        val caption = 12.sp
        val footnote = 13.sp
        val body = 16.sp
        val headline = 17.sp
        val title = 34.sp
    }
}
