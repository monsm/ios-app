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

    fun clear(ctx: Context) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().remove(KEY).apply()
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
            if (ekey.length < 16 || ekey.length % 2 != 0) return null
            LockInfo(
                name = o.optString("n").ifBlank { "门锁" },
                mac = mac,
                pid = o.optInt("p", 0),
                ekey = ekey,
            )
        }.getOrNull()
    }
}
