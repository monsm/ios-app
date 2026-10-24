package com.aapk.kfkey

import android.content.Context
import org.json.JSONObject

/** 一把锁的全部信息 —— 就是二维码里那五个字段, 不多不少。 */
data class LockInfo(val name: String, val mac: String, val pid: Int, val ekey: String) {
    val macText: String
        get() = mac.chunked(2).joinToString(":").uppercase()
}

/**
 * 本机存储: 只存一把锁 (极简版的定位就是"一个人、一把门")。
 * 存下来之后就不再需要二维码 —— 这也是用户口径里那句"后续不用再扫一扫"。
 */
object LockStore {
    private const val PREF = "kf_key_v1"
    private const val KEY = "lock"
    private const val KEY_PROX = "proximity"

    fun load(ctx: Context): LockInfo? {
        val raw = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
        return runCatching {
            val o = JSONObject(raw)
            LockInfo(
                name = o.optString("n"),
                mac = o.optString("m"),
                pid = o.optInt("p"),
                ekey = o.optString("e"),
            )
        }.getOrNull()?.takeIf { it.mac.length == 12 && it.ekey.isNotEmpty() }
    }

    fun save(ctx: Context, lock: LockInfo) {
        val o = JSONObject()
            .put("n", lock.name)
            .put("m", lock.mac)
            .put("p", lock.pid)
            .put("e", lock.ekey)
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putString(KEY, o.toString()).apply()
    }

    /**
     * 「靠近自动开锁」开关要跨重启保留: 这是用户对这台手机的长期选择, 不是一次会话的临时态。
     * 之前只放在 Compose 的 remember 里 —— 关掉 App 再打开就回到默认关, 等于每次都白设一遍。
     */
    fun loadProximity(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getBoolean(KEY_PROX, false)

    fun saveProximity(ctx: Context, on: Boolean) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putBoolean(KEY_PROX, on).apply()
    }

    /**
     * 解绑 = 把这把锁的**全部**本机状态一起清掉。
     *
     * 旧实现只 remove(KEY), 而「靠近自动开锁」是另一个键 —— 内存里把 proximity 置 false 不等于落盘:
     * 下次扫一把新锁, loadProximity 读回 true ⇒ 新锁一绑上就默认自动开。这是 03 X-03 的真实后果。
     * 两个键必须同一次 commit 清掉, 否则又会出现"清了一个、留了一个"。
     */
    fun clear(ctx: Context) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
            .remove(KEY)
            .remove(KEY_PROX)
            .apply()
    }

    /**
     * 二维码正文: `KFA1:{...}` (iOS 端 AndroidPair 生成)。
     * 解析失败一律返回 null —— 宁可让用户重扫, 也不要把半截凭证存进来 (存进来就是一把开不了的"钥匙")。
     */
    fun parseQr(text: String): LockInfo? {
        val body = text.trim().removePrefix("KFA1:").trim()
        if (!body.startsWith("{")) return null
        return runCatching {
            val o = JSONObject(body)
            if (o.optInt("v", 0) != 1) return null
            val mac = KfProtocol.normMac(o.optString("m"))
            val ekey = o.optString("e").lowercase()
            if (mac.length != 12 || mac.any { it !in "0123456789abcdef" }) return null
            // 上界是协议逼出来的: KLV 的长度字段只有 1 字节 (≤255B), 帧总长只有 2 字节。
            // 不封顶的话, 一张被改过的二维码会把超长 ekey 塞进帧里 → 长度字节回绕 → 锁收到残帧
            // (表现同样是"没回执/报错码"), 而且这里存下来就是一把开不了的钥匙。
            // 真 ekey = AES 包络, iOS 侧恒 32B (64 个 hex 字符)。上界不是拍脑袋:
            // KLV 的长度字段只有 1 字节 ⇒ 值最长 255B = 510 个 hex 字符, 再长就要回绕成残帧。
            if (ekey.length < 16 || ekey.length % 2 != 0 || ekey.length > 510) return null
            // 锁名**只用于显示** (mac/ekey 才是开锁依据), 所以超长不拒收、只截断: iOS 侧对名字
            // 没有长度上限, 拒收等于把一张正常能用的码判成坏码, 用户会被挡在"这不是本 App 的钥匙码"外面。
            val name = o.optString("n").ifBlank { "门锁" }.take(40)
            LockInfo(
                name = name,
                mac = mac,
                pid = o.optInt("p", 0),
                ekey = ekey,
            )
        }.getOrNull()
    }
}
