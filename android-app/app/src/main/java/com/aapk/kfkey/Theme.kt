package com.aapk.kfkey

import androidx.compose.ui.graphics.Color

/**
 * 首页配色 (原在 MainActivity.kt 里是 private val) —— 抽出来是因为 SignalArrow.kt 也要用同一套,
 * 而 Kotlin 的顶层 private val 只在**本文件**可见: 留在 MainActivity 里, 第二个文件引用就是编译错误。
 * internal = 同模块跨文件可见, 但仍不泄漏到别的模块。暖金 (Accent) 是钥匙/黄铜的联想, 不是科技蓝紫。
 */
internal val BgTop = Color(0xFF0A0C10)
internal val BgBottom = Color(0xFF141A22)
internal val Surface = Color(0xFF161C24)
internal val Ink = Color(0xFFF3F6FA)
internal val InkSub = Color(0xFF8B96A8)
internal val Accent = Color(0xFFE8B45C)
internal val Ok = Color(0xFF6EE7A8)
internal val Bad = Color(0xFFF87171)
