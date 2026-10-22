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
    // ── 画布 ──
    val canvas: Color,
    // ── 表面三档 (范式 3.1) ──
    val surface: Color,
    val surfaceAlt: Color,
    val surfaceSunken: Color,
    // ── 描边 ──
    val hairline: Color,
    val hairlineStrong: Color,
    // ── 文字 ──
    val text: Color,
    val specular: Color,
    val textSub: Color,
    val textTertiary: Color,
    // ── 强调 ──
    val accent: Color,
    val accentText: Color,
    val onAccent: Color,
    // ── 语义 ──
    val ok: Color,
    val warn: Color,
    val danger: Color,
)

/**
 * 只做深色 —— 规范 §13.4「应用体：只做深色，不提供 App 内明暗切换」。
 *
 * 2026-10-22 审计修正：上一版是 KfDarkColors + KfLightColors 双档、由 isSystemInDarkTheme() 切换。
 * 那是「App 内明暗切换」的实现本体，与规范直接冲突 —— light 档已整块删除。
 *
 * 逐值对账 iOS 的 App/Core/Theme.swift XPalette（深色档），两端一致性由 tools/tokendrift.js 机检。
 *
 * 故意不镜像（本端没有对应界面，镜像过来就是死令牌）：
 *   surfaceChip 无 StatChip 顶部胶囊行
 *   veil        无 8% 白纱（本端没有 StatChip 图标底那种薄衬）
 *   segTrack    无 分段控件（本端没有 XSegmented，也没有系统分段样式）
 *   segThumb    无 分段控件
 *   segOn       无 分段控件
 *   segOff      无 分段控件
 *   kindFp      无 凭证工坊，无凭证三类语义
 *   kindTemp    无 凭证工坊
 *   kindOtp     无 凭证工坊
 */
internal val KfDarkColors = KfColors(
    canvas = Color(0xFF000000),          // 范式 §2.1: 画布纯黑
    surface = Color(0xFF1C1C1E),         // 范式 §2.2: 应用体卡片
    surfaceAlt = Color(0xFF24242A),
    surfaceSunken = Color(0xFF101012),
    // 规范 §2 原文就是半透明白 rgba(255,255,255,0.08) —— 不是实色。0.08*255 = 20 = 0x14
    hairline = Color(0x14FFFFFF),
    hairlineStrong = Color(0xFF4A4A52),
    text = Color(0xFFFFFFFF),
    specular = Color(0xFFC8C8D4),
    textSub = Color(0xFF8D8D93),
    // 规范 §3.3: #6A6A6E, on 黑 3.90:1, 仅 >=17pt 或 Bold。
    textTertiary = Color(0xFF6A6A6E),
    accent = Color(0xFFD98B45),
    accentText = Color(0xFFE8A05C),
    onAccent = Color(0xFF14100A),
    ok = Color(0xFF30D158),
    warn = Color(0xFFFF9F0A),
    danger = Color(0xFFFF3B30),   // 规范 §3.4 accentRed
)
internal fun KfTheme(
    // 参数保留（调用点不必改），但**不再生效**：规范 §13.4 不允许 App 内明暗切换。
    @Suppress("UNUSED_PARAMETER") dark: Boolean = true,
    content: @Composable () -> Unit
) {
    CompositionLocalProvider(LocalKfColors provides KfDarkColors, content = content)
}
