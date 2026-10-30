package com.aapk.kfkey

import kotlin.math.log10
import kotlin.math.roundToInt

/**
 * 靠近自动开锁的判据纯函数 —— 搬 iOS App/Core/AutoOpen.swift 里 AutoOpenKit 的 F3 回差与 F5 一次性。
 *
 * 单独成文件而不是写在 Activity 里, 与 iOS 同一动机: 这两条是**能算错的算术**, 必须是纯函数
 * 才谈得上对拍 (iOS 那边有 Tests/AUTOOPENTests.swift + tools/autoopenshadow.js 锁着)。
 */
object AutoOpenKit {

    /**
     * 武装线 (dBm)。用户口径 (2026-10-17): "信号小于 40 就自动秒开" ⇒ -40。
     * (iOS 的武装线来自按锁标定 F3; 安卓极简版没标定页, 用这条固定线。)
     * 回差解除线仍按线性功率域 -3 dB 换算 ⇒ -43, 比旧值同步平移。
     */
    const val BASE = -40

    /**
     * 解除线必须在**线性功率域**换算, 不能对 dBm 直接乘系数: dBm 是对数单位,
     * 旧式 0.7×base / 0.5×base 在 base=-60 时会算出"解除线比武装线更强"→ 无回差、逐样本翻转。
     * iOS 那段教训 (AutoOpen.swift 里 F3 注释) 原样保留。base=-38 → -38 + 10·log10(0.5) ≈ -41。
     */
    fun armThreshold(base: Int = BASE): Int = base

    fun disarmThreshold(base: Int = BASE): Int =
        (base + 10 * log10(0.5)).roundToInt()

    /** 已武装需掉到解除线以下才解除; 未武装需越过武装线才武装 (AutoOpenKit.rssiSample 逐行)。 */
    fun rssiSample(prevArmed: Boolean, rssi: Int, base: Int = BASE): Boolean {
        val arm = armThreshold(base)
        val disarm = disarmThreshold(base)
        return if (prevArmed) rssi > disarm else rssi >= arm
    }

    /**
     * 2026-10-30（提速，与 iOS `rssiArmedByMedian` 同式）：**中值滤波的武装判据**。
     *
     * `rssiSample` 是**单样本**判定 —— 一个抖动样本就能让 armed 翻转：
     *   · 走近时被一次 -85 尖峰打断 ⇒ 不武装，用户要在门口多站一拍（"时灵时不灵"的成因）；
     *   · 已武装后被一次假强信号维持 ⇒ 走开了还留着 armed。
     * 现在取最近 3 个样本的**中位数**再判：单个尖峰被吃掉，而真的走近时**仍然 1 个样本就能过**
     * （3 样本窗里 2 个达线即中位数达线）⇒ 不会变慢，只会变稳。
     *
     * @param history 最近的样本，**最新的在前**（调用方维护，最多 3 个）。
     */
    fun rssiArmedByMedian(prevArmed: Boolean, history: List<Int>, base: Int = BASE): Boolean {
        val cur = history.firstOrNull() ?: return prevArmed
        val arm = armThreshold(base)
        val disarm = disarmThreshold(base)
        // 已武装 → 解除: **单样本**跌破解除线就解除（走开要快，不能被中值拖住）
        if (prevArmed && cur <= disarm) return false
        // 未武装 → 武装: 用 3 样本中值，抗单点尖峰
        val med = history.take(3).sorted()[history.take(3).size / 2]
        return if (prevArmed) med > disarm else med >= arm
    }

    /**
     * F5 冷却: 上次下发距今 >6s 才允许下一次。
     *
     * 旧值 60s 是"每个接近事件只发一次 04"之外的第二道闸。用户口径 (2026-10-17) 改成 6s:
     * 开完锁等 6 秒就恢复自动监测。双开风险由**另一条更强的闸**兜住, 不靠这个 60s:
     *   · 一次性闩锁 fired: 同一个接近事件内只发一次 04 (要信号先掉回解除线 -43 才放开);
     *   · 回差带 [-43,-40]: 人站在门口信号不会自己掉回去 ⇒ 站着不会反复开 (闸门 C 直接演算钉住);
     *   · 04 回执超时绝不重发 (G4 红线, 在 BleUnlocker.runUnlock 里)。
     * 所以 6s 只是"走开再回来至少要隔 6 秒", 不是防双开的那道闸。
     */
    const val COOLDOWN_MS = 6_000L

    fun coolReady(lastDispatchMs: Long, nowMs: Long): Boolean =
        lastDispatchMs == 0L || nowMs - lastDispatchMs > COOLDOWN_MS
}
