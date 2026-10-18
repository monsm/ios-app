package com.aapk.kfkey

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.runtime.Composable
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback

/**
 * 触觉封装 —— 对应 iOS 的 DS.Haptics 三档 (2026-10-18 门面改造新增)。
 *
 * iOS 侧只允许三档: tick(light, 过程) / trigger(medium, 动作) / 结果档(success/warning/error)。
 * Android 侧用同一套语义, 底层映射到 HapticFeedbackConstants / VibratorManager。
 *
 * 为什么必须封装: 散写 performHapticFeedback 会让"三档"这个约定失效,
 * 而 iOS 侧的设计令牌已经把它钉死了 (DesignSystem.swift:248-258)。
 */
internal object KfHaptics {

    /** 过程触感: 充能刻度 / 围栏解锁 / 就绪轻震 —— 对应 iOS .tick */
    fun tick(ctx: Context) = buzz(ctx, 8, 60)

    /** 动作触感: 手势确认 / 断连提醒 —— 对应 iOS .trigger */
    fun trigger(ctx: Context) = buzz(ctx, 20, 120)

    /** 结果触感: 操作成功 —— 对应 iOS 的 success */
    fun ok(ctx: Context) = buzz(ctx, 12, 90)

    /** 结果触感: 操作失败 —— 对应 iOS 的 error */
    fun fail(ctx: Context) = buzz(ctx, 35, 180)

    /**
     * 统一震动入口。
     * 尊重系统"触感反馈"开关: 关掉时这里静默返回 (视觉必须自成一体, 不依赖触觉)。
     */
    private fun buzz(ctx: Context, ms: Long, amplitude: Int) {
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            (ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)
        }
        if (v == null || !v.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createOneShot(ms, amplitude.coerceIn(1, 255)))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(ms)
        }
    }
}

/**
 * Compose 侧的触觉入口 —— 走平台的 HapticFeedback, 由系统按用户设置自动抑制。
 * 用在需要与点击同步的场景 (按键反馈), 长震动仍用 KfHaptics。
 */
@Composable
internal fun rememberKfHaptics(): androidx.compose.ui.hapticfeedback.HapticFeedback {
    return LocalHapticFeedback.current
}

internal val KfTick = HapticFeedbackType.TextHandleMove
internal val KfConfirm = HapticFeedbackType.LongPress
