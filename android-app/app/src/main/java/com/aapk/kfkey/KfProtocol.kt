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

    /**
     * 会话令牌走 KLV#EE (固件特判通道), 追加在原有 KLV 之后并重算长度。
     *
     * ⚠ 2026-10-17 真机勘误 —— 安卓端恒报"错误码 13"(通讯过期) 的根因就在这里:
     * 长度是帧的**字节 2..3** (小端 16 位), 在十六进制串里对应**字符 4..8**;
     * 旧代码写的是 substring(2,4) | substring(4,6), 等于把"版本字节 00"和长度低字节拼成长度
     * (0x34 → 0x3400 = 13312), 于是下面那行长度守卫必然成立 → **原帧原样返回, KLV#EE 被静默丢掉**
     * → 04 开锁不带令牌裸发 → 锁按"通讯会话无效"回 rc=13。表现就是"令牌拿到了、帧也写了、永远 13"。
     * 现在与 vendor/app/utils/kernel/protocol.js:155 injectToken 同口径 (含 8B/10B 头型自适应)。
     */
    fun injectToken(frameHex: String, tokenHex: String): String {
        if (tokenHex.isEmpty() || frameHex.length < 16) return frameHex
        val f = frameHex.uppercase()
        // 字节 2=长度低, 字节 3=长度高 → 字符 4..6 / 6..8
        val len = f.substring(4, 6).toInt(16) or (f.substring(6, 8).toInt(16) shl 8)
        val cmd = f.substring(8, 10).toInt(16)
        // 头型判别 (protocol.js:159): 10B 头总长 = len+10, 8B 头总长 = len+8; 本 App 自造的帧恒为 8B
        val header10 = f.length >= 20 + len * 2
        val bodyStart = if (header10) 20 else 16
        if (f.length < bodyStart + len * 2) return f
        val body = f.substring(bodyStart, bodyStart + len * 2)
        val klv = body + klv(0xEE, tokenHex)
        if (!header10) return frame(cmd, klv)
        val n = klv.length / 2
        return ("87" + "00" + String.format("%02x%02x", n and 0xff, (n shr 8) and 0xff) +
                String.format("%02x", cmd and 0xff) + f.substring(10, 14) + "000000" + klv).uppercase()
    }

    /** raw = 这一帧自己占的 hex (不含缓冲区里它后面那半截), 调用方据此把流里剩下的字节留着。 */
data class Frame(val cmd: Int, val klvs: List<Pair<Int, String>>, val raw: String) {
    // 2026-10-27 审核修复 (AUDIT-C A5)：KLV 容器从 `Map<Int, String>` 改成保序列表。
    // 原实现 `out[key] = ...` 让**重复键被后者覆盖** —— 而锁端所有「每项一个 KLV」的帧
    // （0x16 日志每页 N 条 KLV#05、0x13 录指纹多帧、0x43/0x44 MAC 列表）在安卓侧只留最后一条。
    // 现在只发 01/03/04 恰好都是单值帧所以没炸，但这是个「看起来通用」的解析器，
    // 下一个接 16 日志的人会直接踩进去（iOS 的 StatusParser 已把 0x05 当数组用）。

    /** 取首个匹配值（原 `klvs[key]` 的语义）—— 单值帧的调用方用这个。 */
    fun first(key: Int): String? = klvs.firstOrNull { it.first == key }?.second
}


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
            return Frame(cmd, map, hex.substring(0, (off + len) * 2))
        }
        return null
    }

    private fun parseKlv(hex: String): List<Pair<Int, String>>? {
        val b = bytes(hex)
        val out = ArrayList<Pair<Int, String>>()
        var off = 0
        while (off < b.size) {
            if (off + 2 > b.size) return null
            val key = b[off].toInt() and 0xff
            val len = b[off + 1].toInt() and 0xff
            if (off + 2 + len > b.size) return null
            out.add(key to hex.substring((off + 2) * 2, (off + 2 + len) * 2))
            off += 2 + len
        }
        return out
    }

    /**
     * JS status.js intHex 同口径: parseInt(val || "0", 16) || 0 —— 取**前缀** hex, 空串/非 hex 一律 0。
     *
     * 不是抠细节: 旧写法是 runCatching { toInt(16) } ?: -1, 于是"锁回了 KLV#03 但值为空"这种退化帧
     * 在安卓端读成 rc=-1 (报"开锁失败 错误码 -1"), 而 iOS/JS 读成 rc=0。同一把锁、同一帧,
     * 两端结论相反 —— 与 iOS 的字节级差分口径就断在这里。
     */
    fun intHex(h: String): Int {
        var v = 0L
        var n = 0
        for (ch in h) {
            val d = Character.digit(ch, 16)
            if (d < 0) break
            v = v * 16 + d
            n++
            if (v > 0xFFFFFFFFL) v = 0xFFFFFFFFL   // 饱和: 反正超出 rc 表 (0..27)
        }
        if (n == 0) return 0
        return if (v > Int.MAX_VALUE.toLong()) Int.MAX_VALUE else v.toInt()
    }

    /**
     * 回包形状 (iOS LockService.klvShape 等价): 只在"没拿到想要的东西"时印出来, 供真机排障。
     * 形如 "#01=1B #03=2B" —— 只有键和字节数, 不含值本身 (令牌/ekey 的字节不进用户可见文案)。
     */
    fun klvShape(f: Frame): String =
        if (f.klvs.isEmpty()) "(无 KLV)"
        else f.klvs.joinToString(" ") { "#" + String.format("%02x", it.first) + "=" + (it.second.length / 2) + "B" }

    /** rc 在 KLV#03 (JS lock.js RC_KLV: 0x03/0x04 → 3); **整项缺失**才 -1 (= 回包里没有结果码)。 */
    fun rc(f: Frame): Int = f.first(0x03)?.let { intHex(it) } ?: -1

    /** 锁端结果码 (JS lock.js RC_MSG / StatusParser.swift rcMsg 原文, 逐字搬过来, 不自造语义)。 */
    private val RC_NAME = mapOf(
        0 to "已开锁", 1 to "解密失败", 2 to "无效的PIN码", 3 to "命令过期", 5 to "次数使用完毕",
        6 to "开锁指令已绑定其他设备", 7 to "执行的操作不在指定的状态", 8 to "溢出", 9 to "时间误差过大",
        10 to "未知错误", 11 to "解密失败", 12 to "mac地址不正确", 13 to "通讯过期",
        14 to "不支持的秘钥交换方式", 15 to "未知协议", 16 to "参数不在范围内", 17 to "丢包",
        18 to "不能设置重复的值", 19 to "找不到指定的值", 20 to "指纹传感器错误", 21 to "门锁处于反锁状态",
        22 to "不能重复验证", 23 to "无法获取有效的指纹图片", 24 to "录入指纹超时",
        25 to "锁正忙，请稍后重试", 26 to "门锁被撬", 27 to "您的门锁处于布防状态"
    )

    /** rcFriendly (StatusParser.swift rcHint) 那一层: 开锁链上真会遇到、且用户能照做的那几条。 */
    private val RC_HINT = mapOf(
        1 to "通讯受干扰, 请靠近门锁再试一次",
        3 to "指令已过期, 多为锁内时钟不准 — 请先在 iOS 端校准时间再试",
        5 to "这条凭证的使用次数已用完, 请换一条或重新添加",
        6 to "这条开锁凭证已绑定到别的设备, 请重新下发凭证",
        9 to "锁内时间与手机偏差过大 — 请先在 iOS 端校准时间再试",
        11 to "通讯受干扰, 请靠近门锁再试一次",
        // rc=13 权威表 (StatusParser.rcHint) 没有对应档, 回落原文"通讯过期"。安卓端这一条是
        // **新写的**并且如实: 走到这里说明本机已经自动重取过一次令牌 (attempt 1→2), 所以
        // 括号里那句不是空话。
        13 to "会话已过期 (本机已自动重取令牌仍被拒) — 请离门锁近一点再试",
        21 to "门从里面反锁了, 先解除反锁再试",
        25 to "锁正忙 (可能刚有人操作过), 等两秒再试",
        27 to "门锁处于布防状态, 请先解除布防再开锁"
    )

    /** 锁端结果码的人话: 先给"该怎么办", 再给权威原文, 最后兜底如实给码。 */
    fun rcText(rc: Int): String = when {
        rc == -1 -> "门锁回了帧但没带结果码, 无法确认这一趟 — 先看一眼门有没有开, 再重试"
            // JS lock.js:290 把 rc=-1 当成功放行, iOS StatusParser/LockService:345 判"回包缺少 rc KLV,
            // 无法确认"并要调用方回读。两端口径本就不同 —— 开锁这一条不能赌"当成成功",
            // 说成"没开"也不诚实 (门可能已经开了), 只能如实让人先看门。
        rc > 27 || rc < -1 -> "开锁失败 (错误码 $rc)"
        else -> RC_HINT[rc] ?: RC_NAME[rc] ?: "开锁失败 (错误码 $rc)"
    }

    /** 开锁帧: 04 + KLV#01 (16 字节零) + KLV#02 (ekey)。 */
    fun unlockFrame(ekeyHex: String): String {
        val klv01 = klv(0x01, "0".repeat(32))
        return frame(0x04, klv01 + klv(0x02, ekeyHex.lowercase()))
    }

    fun tokenFrame(): String = frame(0x01, "")

    /**
     * 明文 03 状态帧 (无 KLV 载荷) = 8700000003000000, 与 fixtures/golden.json 的
     * cmds.cmd03StatusPlain 逐字节一致。免令牌、不需要 skey ⇒ 本 App 发得出去。
     * 用途: 连接后的身份复核 (锁**自报**的 pid 在 KLV#34), 对齐 iOS LockService.swift:105。
     */
    fun statusFrame(): String = frame(0x03, "")

    /** KLV 值里的 u32 小端 (JS status.js leHexToU32 同口径; pid 量级远小于 2^31)。 */
    fun u32le(hexIn: String): Int {
        val b = bytes(hexIn.lowercase())
        var v = 0
        for (i in 0 until minOf(4, b.size)) v = v or ((b[i].toInt() and 0xff) shl (i * 8))
        return v
    }

    /**
     * 锁自报的产品号: KLV#34 (JS status.js STATUS_KEYS 0x34 = pid, u32 LE)。
     * 广播厂商段里那个 pid 是**另一套编号** (golden: parseAdv 的 pid=7970 vs status 的
     * 16289 就不是一个口径), 而二维码里的 p 抄的是 status 那一套 (iOS AndroidPair 写 kc.pid
     * ← LockService 配网时的 st.pid)。所以核身份只能拿锁端响应比, 拿广播比会误杀真锁。
     */
    fun pidOf(f: Frame): Int = f.first(0x34)?.let { u32le(it) } ?: 0

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
