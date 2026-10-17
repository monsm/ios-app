package com.aapk.kfkey

/**
 * 协议层 —— 从 iOS 端 (App/Core/ZKProtocol.swift) 逐字节搬过来的最小子集。
 *
 * 这里只保留"开锁"这一条链需要的东西: 帧头 8 字节 + KLV + 会话令牌注入 + 响应解析。
 * 没有 AES: 开锁用的是配网时签好的 ekey (二维码带过来), 令牌 (01) 是明文索取 —— 所以本机
 * 不需要 skey, 也就不需要加密实现。少一份密钥材料, 少一份能泄漏的东西。
 */
object KfProtocol {
    const val SVC = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    const val CHR_WRITE = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    const val CHR_NOTIFY = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

    fun hex(b: ByteArray): String {
        val sb = StringBuilder(b.size * 2)
        for (x in b) sb.append(String.format("%02x", x.toInt() and 0xff))
        return sb.toString()
    }

    fun bytes(h: String): ByteArray {
        val n = h.length / 2
        val out = ByteArray(n)
        for (i in 0 until n) out[i] = h.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        return out
    }

    /** KLV = key(1B) + len(1B) + value */
    fun klv(key: Int, valHex: String): String =
        String.format("%02x%02x", key and 0xff, (valHex.length / 2) and 0xff) + valHex

    /**
     * 帧头 8 字节: 87 00 lenLE(2) cmd 00 00 00, 之后是 KLV 串。
     * 与 Java 生产链 / iOS 端完全一致 (长度是**小端 16 位**)。
     */
    fun frame(cmd: Int, klvHex: String): String {
        val len = klvHex.length / 2
        return ("87" + "00" + String.format("%02x%02x", len and 0xff, (len shr 8) and 0xff) +
                String.format("%02x", cmd and 0xff) + "000000" + klvHex).uppercase()
    }

    /** 会话令牌走 KLV#EE (固件特判通道), 追加在原有 KLV 之后并重算长度。 */
    fun injectToken(frameHex: String, tokenHex: String): String {
        if (tokenHex.isEmpty() || frameHex.length < 16) return frameHex
        val len = frameHex.substring(2, 4).toInt(16) or (frameHex.substring(4, 6).toInt(16) shl 8)
        val cmd = frameHex.substring(8, 10).toInt(16)
        val bodyStart = 16
        if (frameHex.length < bodyStart + len * 2) return frameHex
        val body = frameHex.substring(bodyStart, bodyStart + len * 2)
        return frame(cmd, body + klv(0xEE, tokenHex))
    }

    data class Frame(val cmd: Int, val klvs: Map<Int, String>, val raw: String)

    /**
     * 响应解析: 长度同样是 LE16, 帧头有三种历史形状 (8/7/10 字节), 但 cmd 恒在字节 4。
     * 先按 8 字节头试 (Java 生产链口径), 解析不通再试 10 / 7。
     */
    fun parse(hexIn: String): Frame? {
        val hex = hexIn.lowercase()
        if (hex.length < 14) return null
        val b = bytes(hex)
        val len = (b[2].toInt() and 0xff) or ((b[3].toInt() and 0xff) shl 8)
        val cmd = b[4].toInt() and 0xff
        val version = b[1].toInt() and 0xff
        val orders = if (version == 0x01) intArrayOf(8, 7, 10) else intArrayOf(8, 10, 7)
        for (off in orders) {
            if (b.size < off + len) continue
            val klvHex = hex.substring(off * 2, (off + len) * 2)
            val map = parseKlv(klvHex) ?: continue
            return Frame(cmd, map, hex)
        }
        return null
    }

    private fun parseKlv(hex: String): Map<Int, String>? {
        val b = bytes(hex)
        val out = LinkedHashMap<Int, String>()
        var off = 0
        while (off < b.size) {
            if (off + 2 > b.size) return null
            val key = b[off].toInt() and 0xff
            val len = b[off + 1].toInt() and 0xff
            if (off + 2 + len > b.size) return null
            out[key] = hex.substring((off + 2) * 2, (off + 2 + len) * 2)
            off += 2 + len
        }
        return out
    }

    /** rc 在 KLV#03; 缺省 -1 (与 iOS 的 extractRc 同口径)。 */
    fun rc(f: Frame): Int = f.klvs[0x03]?.let { runCatching { it.toInt(16) }.getOrNull() } ?: -1

    /** 锁端结果码的人话 —— 只翻开锁链上真会遇到的那几个, 其余如实给码。 */
    fun rcText(rc: Int): String = when (rc) {
        0 -> "已开锁"
        1, 11 -> "通讯受干扰, 靠近门锁再试一次"
        3 -> "指令已过期 (锁内时钟不准), 请先在 iOS 端校准时间"
        6 -> "这条开锁凭证已绑定到别的设备"
        12 -> "MAC 地址不正确 (这把锁的凭证不是给这台机器的)"
        21 -> "门从里面反锁了"
        22 -> "需要二次验证"
        25 -> "锁正忙, 等两秒再试"
        27 -> "门锁处于布防状态"
        else -> "开锁失败 (错误码 $rc)"
    }

    /** 开锁帧: 04 + KLV#01 (16 字节零) + KLV#02 (ekey)。 */
    fun unlockFrame(ekeyHex: String): String {
        val klv01 = klv(0x01, "0".repeat(32))
        return frame(0x04, klv01 + klv(0x02, ekeyHex.lowercase()))
    }

    fun tokenFrame(): String = frame(0x01, "")

    /**
     * 广播解析: 厂商段 98ED 之后 10 字节 = [fc, b3, pidLo, pidHi, mac(6)]。
     * fc 的 bit2/bit3 必须同时置位 (含 pid + 含 mac), 否则这包不带身份信息, 不能用来认锁。
     */
    data class Adv(val pid: Int, val mac: String, val rssi: Int)

    fun parseAdv(manufacturer: ByteArray?, rssi: Int): Adv? {
        if (manufacturer == null || manufacturer.size < 10) return null
        val fc = manufacturer[0].toInt() and 0xff
        if (fc and 0x0c != 0x0c) return null
        val pid = (manufacturer[2].toInt() and 0xff) or ((manufacturer[3].toInt() and 0xff) shl 8)
        val mac = StringBuilder(17)
        for (i in 5 downTo 0) {
            if (mac.isNotEmpty()) mac.append(':')
            mac.append(String.format("%02X", manufacturer[4 + i].toInt() and 0xff))
        }
        return Adv(pid, mac.toString(), rssi)
    }

    /** 台账里存的是不带冒号的小写; 广播里是 AA:BB:CC 大写 —— 统一到前者再比。 */
    fun normMac(m: String): String = m.replace(":", "").replace("-", "").lowercase()
}
