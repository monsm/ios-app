package com.aapk.kfkey

import android.content.Context
import android.os.VibrationEffect
import android.os.VibratorManager

/**
 * 触觉封装 —— 与 iOS 的 DS.Haptics 结果档对齐 (2026-10-18 门面改造新增)。
 *
 * 只保留**有调用点**的两档: ok / fail。原先还有 tick/trigger 与 Compose 的
 * rememberKfHaptics/KfTick/KfConfirm, 但全仓零调用 —— 同一件事留两套入口,
 * 下一个人就不知道该用哪套。要加过程触感时, 按 iOS .tick 语义在这里补一个函数,
 * 不要在页面里直接写 performHapticFeedback。
 *
 * minSdk = 33 (Android 13) ⇒ VibratorManager 恒可用, 不再需要 Build.VERSION 分支;
 * 旧代码那两段 fallback (VIBRATOR_SERVICE / 无 effect 的 vibrate) 是 minSdk 21 时代的残留。
 */
internal object KfHaptics {

    /** 结果触感: 操作成功 —— 对应 iOS 的 success */
    fun ok(ctx: Context) = buzz(ctx, 12, 90)

    /** 结果触感: 操作失败 —— 对应 iOS 的 error */
    fun fail(ctx: Context) = buzz(ctx, 35, 180)

    /**
     * 统一震动入口。
     * 触觉是锦上添花: 没有马达、系统关了触感、或厂商 ROM 抛异常时一律静默返回,
     * 绝不能让一次震动把开锁流程打断 (2026-10-18 真机事故的教训)。
     */
    private fun buzz(ctx: Context, ms: Long, amplitude: Int) {
        val v = (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            ?: return
        if (!v.hasVibrator()) return
        runCatching {
            v.vibrate(VibrationEffect.createOneShot(ms, amplitude.coerceIn(1, 255)))
        }
    }
}
