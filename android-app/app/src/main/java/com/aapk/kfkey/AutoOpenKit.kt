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
     * 武装线 (dBm)。iOS 的武装线来自按锁标定 (F3 P95); 安卓极简版没有标定页, 用固定基准 -38 ——
     * 与原代码里那条 -38 同一数值, 变的不是阈值, 是"越过线之后不再逐样本反复触发"。
     */
    const val BASE = -38

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

    /** F5 冷却: 上次下发距今 >60s 才允许下一次 —— 跨"接近事件"也拦 (AutoOpenKit.coolReady)。 */
    const val COOLDOWN_MS = 60_000L

    fun coolReady(lastDispatchMs: Long, nowMs: Long): Boolean =
        lastDispatchMs == 0L || nowMs - lastDispatchMs > COOLDOWN_MS
}
