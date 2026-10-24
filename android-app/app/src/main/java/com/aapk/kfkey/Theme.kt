package com.aapk.kfkey

import androidx.compose.ui.graphics.Color

/**
 * 首页配色 —— SignalArrow.kt 也要用同一套, 而 Kotlin 的顶层 private val 只在**本文件**可见,
 * 留在 MainActivity 里第二个文件引用就是编译错误。internal = 同模块跨文件可见。
 * 暖金 (Accent) 是钥匙/黄铜的联想, 不是科技蓝紫。
 *
 * ⚠️ 2026-10-18 一次未采纳的尝试 (记录在案, 免得后人再踩):
 * 曾把这 8 个 val 改成 `@Composable get() = LocalKfColors.current.xxx` 以支持深浅双模,
 * **编译不过** —— 它们被用在两类非 Composable 上下文里:
 *   ① DrawScope 里 (GearButton / SignalArrow 的 Canvas 绘制);
 *   ② 非 Composable 的普通 fun 里 (maybeAutoUnlock 拼状态色)。
 * @Composable 属性在那种位置读不了。所以这里保持固定值。
 * 深浅双模的入口是 KfTheme.kt 的 LocalKfColors。Composable 页面一律从它取色 ——
 * 2026-10-20 已把 MainActivity 的 ProximityCard/Header/UnlockDial/EmptyState/PillButton
 * 与 SignalArrow 的描边全部接上。下面这几个固定 val 只留给**非 Composable 的默认参数**
 * (SignalArrow 的 okColor/outlineColor) 与 DrawScope 兜底, 不再是页面取色入口。
 */
internal val BgTop = Color(0xFF0A0C10)
internal val BgBottom = Color(0xFF141A22)
internal val Surface = Color(0xFF161C24)
internal val Ink = Color(0xFFF3F6FA)
internal val InkSub = Color(0xFF8B96A8)
internal val Accent = Color(0xFFE8B45C)
internal val Ok = Color(0xFF6EE7A8)
internal val Bad = Color(0xFFF87171)
