package com.aapk.kfkey

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * 深浅双模色板 —— 2026-10-18 门面改造新增。
 *
 * 口径 (D14):
 *   · 暗色档 = **保留现有值** (Theme.kt 的 BgTop/BgBottom/Surface/Ink/InkSub/Accent),
 *     作者在 Theme.kt:8 写明这套色是刻意的"钥匙/黄铜的联想, 不是科技蓝紫"。
 *   · 浅色档 = 新做, 规则照 iOS 的做法反推: 暖白底 + 深墨字 + **暖金取深色版本**
 *     (#B8862F 而不是 #E8B45C, 保证浅底上 >= 4.5:1)。
 *
 * 为什么不用 MaterialTheme 的 colorScheme:
 *   本工程的视觉语言不是 Material 那套 (没有 M3 的 tonal palette),
 *   套进去会得到一堆"M3 默认感"的颜色, 与本仓暗色暖金基调打架。
 */
internal data class KfColors(
    val bgTop: Color,
    val bgBottom: Color,
    val surface: Color,
    val ink: Color,
    val inkSub: Color,
    val accent: Color,
    // 强调色上的前景色: 暗色档的暖金很亮, 用深墨字; 浅色档的暖金被压深, 必须用白字。
    val onAccent: Color,
    val ok: Color,
    val bad: Color
)

/** 暗色档 —— 沿用既有 Theme.kt 的取值, 一个都不改 (D14)。 */
internal val KfDarkColors = KfColors(
    bgTop = Color(0xFF0A0C10),
    bgBottom = Color(0xFF141A22),
    surface = Color(0xFF161C24),
    ink = Color(0xFFF3F6FA),
    inkSub = Color(0xFF8B96A8),
    accent = Color(0xFFE8B45C),
    onAccent = Color(0xFF14181E),
    ok = Color(0xFF6EE7A8),
    bad = Color(0xFFF87171)
)

/**
 * 浅色档 —— 新做。
 * 底 #F5F3EF 暖白 (与 iOS 门面的 #F6F3ED 同族, 但**不是同一个值**: 各端保留自己的基调, D14),
 * 强调色取 #8F6119: 暖金在白底上要压到 4.5:1 才够。实测对比度 ——
 *   #E8B45C 对白底 1.90 (不够) / #B8862F 对白底 3.24 (不够) / **#8F6119 对白底 5.40, 对暖白底 4.96 (通过)**。
 */
internal val KfLightColors = KfColors(
    bgTop = Color(0xFFF7F5F1),
    bgBottom = Color(0xFFEDE9E1),
    surface = Color(0xFFFFFFFF),
    ink = Color(0xFF17140F),
    inkSub = Color(0xFF5C5245),
    accent = Color(0xFF8F6119),
    onAccent = Color(0xFFFFFFFF),
    ok = Color(0xFF15803D),
    bad = Color(0xFFB91C1C)
)

internal val LocalKfColors = staticCompositionLocalOf { KfDarkColors }

/**
 * 包一层深浅双模。跟随系统; 将来要加 App 内三档开关 (跟随系统/亮/暗) 时,
 * 只需在这里加一个参数, 调用点不用动。
 */
@Composable
internal fun KfTheme(
    dark: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colors = if (dark) KfDarkColors else KfLightColors
    CompositionLocalProvider(LocalKfColors provides colors, content = content)
}
