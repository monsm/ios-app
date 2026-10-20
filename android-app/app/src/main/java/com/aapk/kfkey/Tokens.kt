package com.aapk.kfkey

import androidx.compose.ui.unit.dp

/**
 * 设计令牌 —— 与 iOS 的 App/Core/DesignSystem.swift **数值逐字相同**（D9/D14）。
 *
 * 2026-10-20 缩表 (Q19): 原文件 82 行, 其中 Hit/Icon/Duration/Curve/Text 五个 object **零引用**,
 * 已删。只保留真有消费点的两组:
 *   · Space  ← MainActivity.kt:687 (KfTokens.Space.l ×2)
 *   · Radius ← MainActivity.kt:685 (KfTokens.Radius.card)
 * 若将来要用图标尺寸/动效时长, 请先在 iOS DesignSystem.swift 找到对应令牌再加, 不要凭记忆写值。
 *
 * 色板不在这里: 各端保留 (D14), 具体色值走 KfTheme.kt 的 LocalKfColors。
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
}
