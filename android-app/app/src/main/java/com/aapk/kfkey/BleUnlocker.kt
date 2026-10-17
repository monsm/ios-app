package com.aapk.kfkey

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID

/**
 * 开锁链: 扫描 → 连接 → 订阅 → (03 认锁) → 01 取令牌 → 04 开锁。
 *
 * 只有一条链, 所以不引状态机库: 每一步都是一个 CompletableDeferred, 超时即放弃并断开。
 * 所有 GATT 操作串行化 (Mutex) —— 靠近自动开锁与手动点击可能同时发生, 两条链撞在一起
 * 会把 gatt 写成半截帧。
 */
@SuppressLint("MissingPermission")
class BleUnlocker(private val ctx: Context) {

    private val manager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = manager.adapter
    private val mutex = Mutex()
    private val svcUuid: UUID = UUID.fromString(KfProtocol.SVC)

    /// trace = 这一趟开锁的过程留痕 (令牌前缀 / rc)。只在失败时给用户看, 用来在真机上定位问题。
    data class Outcome(val ok: Boolean, val message: String, val trace: String = "")

    fun isReady(): Boolean = adapter?.isEnabled == true

    /**
     * 近场信号流: 只上报这把锁的广播 RSSI (dBm)。UI 拿它判"到没到门口"。
     * 扫不到时不会报 0 —— 不发明数据。
     */
    fun observeRssi(lock: LockInfo): Flow<Int> = callbackFlow {
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) { close(); return@callbackFlow }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val adv = advOf(result) ?: return
                if (KfProtocol.normMac(adv.mac) == lock.mac) trySend(result.rssi)
            }
            override fun onScanFailed(errorCode: Int) { close() }
        }
        // 不带 filters: 门锁的广播里只有厂商段 (98ED), **没有** 128 位服务 UUID ——
        // 按服务过滤会一条结果都收不到, 这正是"提示找不到门锁"的第一个原因 (iOS 侧同样 withServices: nil)。
        // startScan 在 BLUETOOTH_SCAN 被拒时抛 SecurityException: 这条流是在 LaunchedEffect 里
        // collect 的, 那一层没人接 → 不接住就是闪退 (而不是"信号读不到")。
        if (runCatching { scanner.startScan(null, settings, cb) }.isFailure) {
            close(); return@callbackFlow
        }
        awaitClose { runCatching { scanner.stopScan(cb) } }
    }

    /** 一次性开锁。返回的 message 直接给用户看。 */
    suspend fun unlock(lock: LockInfo): Outcome = mutex.withLock {
        val ad = adapter ?: return@withLock Outcome(false, "这台手机没有蓝牙")
        if (!ad.isEnabled) return@withLock Outcome(false, "蓝牙未开启")
        // runCatching 是**什么都接**的: 界面销毁导致的取消也会被它转成"扫描失败: …"那样一句
        // 误导人的话, 还把取消咽下来 (结构化并发里这叫 swallowing cancellation)。
        // 所以这里只把 SecurityException 当错误处理, 取消原样抛回去。
        val scanned: BluetoothDevice? = try {
            scanForLock(lock, 7000)
        } catch (ce: CancellationException) {
            throw ce
        } catch (e: Exception) {
            return@withLock Outcome(false, "扫描失败: " + humanBle(e))
        }
        val device = scanned
            ?: return@withLock Outcome(false, "没找到这把锁 — 靠近门锁, 或确认门锁有电")

        var gatt: BluetoothGatt? = null
        // 断链回执落地点。声明在 try **外面**: finally 看不见 try 内部的局部变量,
        // 而"先 disconnect、等回执到了再 close"这条纪律必须由 finally 执行 (见文件末尾)。
        val disconnected = CompletableDeferred<Boolean>()
        // 通知缓冲同样提到 try 外: finally 要关它 (链路断在这儿不关, 回调会一直握着这块缓冲,
        // 而 awaitFrame 那句 "catch 到即视为链路被关" 也必须有真实的关闭事件才对得上)
        val notes = Channel<ByteArray>(Channel.UNLIMITED)
        val trace = StringBuilder()
        return@withLock try {
            val connected = CompletableDeferred<Boolean>()
            val servicesOk = CompletableDeferred<Boolean>()
            val notifyOn = CompletableDeferred<Boolean>()
            val mtuOk = CompletableDeferred<Boolean>()
            var writeDone: CompletableDeferred<Boolean>? = null

            val cb = object : BluetoothGattCallback() {
                override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                    if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                        connected.complete(true)
                        g.discoverServices()
                    } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                        // 连上了但 status 带错 (133 / 一连上就被断的竞态)。旧代码两个分支都不命中 →
                        // connected 永不完成 → 干等满 10 秒 → 报成"连接超时", 把真因盖住。
                        connected.complete(false)
                        disconnected.complete(true)
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        connected.complete(false)
                        disconnected.complete(true)
                    }
                }
                override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                    servicesOk.complete(status == BluetoothGatt.GATT_SUCCESS)
                }
                override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
                    if (d.uuid == CCCD) notifyOn.complete(status == BluetoothGatt.GATT_SUCCESS)
                }
                override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                    writeDone?.complete(status == BluetoothGatt.GATT_SUCCESS)
                }
                override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
                    notes.trySend(value)
                }
                override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
                    // 旧实现不看 status 恒 complete(true)。如实回传; 调用方不据此判失败 (MTU 是纯优化)。
                    mtuOk.complete(status == BluetoothGatt.GATT_SUCCESS)
                }
            }

            // 停扫之后**先 settle 一下再连**: 上一行 scanForLock 收尾的 stopScan 是异步生效的,
            // 立刻 connectGatt 是安卓 GATT 133 的头号成因 (射频还在扫描态)。留 120ms 给栈落定,
            // 体感上加在"正在开锁…"里, 比偶发一次"连不上这把锁"便宜得多。
            delay(120)
            // connectGatt 之后再取一次非空引用: gatt 是 var, 编译器不会对它做智能转换
            val g = device.connectGatt(ctx, false, cb, BluetoothDevice.TRANSPORT_LE)
                ?: return@withLock Outcome(false, "无法建立连接")
            gatt = g

            if (withTimeoutOrNull(10_000) { connected.await() } != true) {
                return@withLock Outcome(false, "连不上这把锁 — 离门锁再近一点, 或关掉其它蓝牙调试 App")
            }
            if (withTimeoutOrNull(6_000) { servicesOk.await() } != true) {
                return@withLock Outcome(false, "读取门锁服务失败")
            }

            val svc = g.getService(svcUuid) ?: return@withLock Outcome(false, "这把锁不支持开锁通道")
            val write = svc.getCharacteristic(UUID.fromString(KfProtocol.CHR_WRITE))
                ?: return@withLock Outcome(false, "门锁写通道缺失")
            val notify = svc.getCharacteristic(UUID.fromString(KfProtocol.CHR_NOTIFY))
                ?: return@withLock Outcome(false, "门锁通知通道缺失")

            runCatching { g.setCharacteristicNotification(notify, true) }
            val cccd = notify.getDescriptor(CCCD)
            if (cccd != null) {
                // API 33+ 这个重载返回 BluetoothStatusCodes (Int) 而不是 Boolean: 同步就被拒时
                // 不会再有 onDescriptorWrite 回调, 旧代码于是白等满 4 秒才往下走。
                val req = runCatching {
                    g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                }.getOrNull()
                if (req == BluetoothStatusCodes.SUCCESS) withTimeoutOrNull(4_000) { notifyOn.await() }
            }

            // 协商 MTU: 只谈 ATT 层上界, **分片仍恒按 20 字节** —— iOS BLEService.writeFrame 与 JS
            // writeFrame 都是 20B 定长分片, 锁端按 20B 组包; 跟着 MTU 放大分片会让锁收到残帧。
            // 旧注释"抬上去之后 1 片写完"是假能力宣称 (分片大小一个字没变), 现在如实: 这一步是
            // 纯优化, 失败不影响开锁, 所以不据它的结果报错。
            runCatching { g.requestMtu(256) }
            withTimeoutOrNull(2_000) { mtuOk.await() }

            // ---------- 连接后身份复核 (对齐 iOS LockService.swift:105) ----------
            // 先发一条**明文 03** 问锁自报的 pid, 与二维码登记的比。为什么不在扫描那一跳拿广播 pid
            // 比 (我第一版就写错了): 广播厂商段里那个 pid 与台账 pid **不是同一套编号**
            // (golden: parseAdv 的 7970 vs status KLV#34 的 16289), 拿它拦会把真锁误杀成"pid 不符"。
            // 广播是任何设备都能发的, 锁端响应难伪造得多 —— iOS 挑 03 就是这个理由。
            // 03 在 04 之前、且不驱动执行器, 所以多发一次没有副作用 (对照 G4 只约束 04 的重发)。
            // 读不到就**不拦**: 这条是加固, 不是新闸门; 老锁/老固件不回 KLV#34 时不能把人挡在门外。
            if (lock.pid > 0) {
                // 写失败/无回应 = 这一趟没复核成, 不拦开锁 —— 加固不该变成新闸门
                // (老锁/老固件可能不回 KLV#34)。
                if (writeChunked(g, write, KfProtocol.bytes(KfProtocol.statusFrame())) { writeDone = it }) {
                    val st = awaitFrame(notes, 0x03, 3_000)
                    val selfPid = st?.let { KfProtocol.pidOf(it) } ?: 0
                    if (st == null) {
                        trace.append("03→无回应 ")
                    } else if (selfPid <= 0) {
                        trace.append("03→无pid ")
                    } else {
                        trace.append("03→pid=" + selfPid + " ")
                        if (selfPid != lock.pid) {
                            return@withLock Outcome(
                                false,
                                "连到的设备与「" + lock.name + "」不是同一把锁 (pid 不符) — 附近可能有同名或伪造广播",
                                trace.toString() + "登记 pid=" + lock.pid
                            )
                        }
                    }
                }
            }

            // 01 取会话令牌 → 注入 KLV#EE → 04 开锁。
            // rc=3 (命令过期) / rc=13 (通讯过期) 都落在"这一趟会话令牌不认了", 重取一次再发, 只做一轮
            // (iOS 对 rc=3 是同一招; rc=13 按 Java 侧口径同样是通讯会话无效)。
            // ⚠ 重试纪律: 只有"锁明确回了非 0 rc"才重试 —— 锁没执行才允许再来一次。
            //   超时/没回执绝不能重发 04: 锁可能已经开过了, 重发 = 电机连触发 (G4)。
            var rc = -1
            for (attempt in 1..2) {
                if (!writeChunked(g, write, KfProtocol.bytes(KfProtocol.tokenFrame())) { writeDone = it }) {
                    return@withLock Outcome(false, "写入失败 — 重连后再试", trace.toString())
                }
                val tokenFrame = awaitFrame(notes, 0x01, 4_000)
                    ?: return@withLock Outcome(false, "门锁没有回应 — 靠近一点再试", trace.toString())
                val token = tokenFrame.klvs[0x02]
                if (token == null) {
                    // ⚠ 01 的响应里**没有 rc**: KLV#03 在那一帧是"令牌有效秒数 (u16 LE)",
                    // 不是结果码 —— JS lock.js 的 RC_KLV 压根没有 0x01 这一项 (iOS extractRc
                    // 对 01 恒返 0)。先前那一版把 #03 当 rc 印出来, 45 秒 TTL 会被念成"rc=45",
                    // 等于给用户一条查不着也解释不了的假线索。权威口径两条都照搬:
                    //   JS  lock.js:254  throw '01 响应无令牌; 安全类型=' + securityType
                    //   iOS LockService:178  log 回包形状 + "01 响应无令牌 (回包 …)"
                    val secType = tokenFrame.klvs[0x01]?.let { KfProtocol.intHex(it) and 0x03 }
                    return@withLock Outcome(
                        false,
                        "门锁没有给会话令牌 (安全类型=" + (secType?.toString() ?: "无") +
                            ", 回包 " + KfProtocol.klvShape(tokenFrame) + ") — 离门锁近一点再试",
                        trace.toString())
                }
                trace.append("01→" + token.take(8) + " ")

                val hex = KfProtocol.injectToken(KfProtocol.unlockFrame(lock.ekey), token)
                // 护栏 (2026-10-17 那个 rc=13 的坑): 令牌 KLV 必须**逐字节**躺在帧尾才算注入成功。
                // "帧里有没有 EE"不够 —— ekey 里本来就可能带 ee, 真漏注入时反而看不出来。
                val tokKlv = KfProtocol.klv(0xEE, token).uppercase()
                if (!hex.endsWith(tokKlv)) {
                    return@withLock Outcome(false, "内部错误: 会话令牌没能装进开锁帧", trace.toString())
                }
                if (!writeChunked(g, write, KfProtocol.bytes(hex)) { writeDone = it }) {
                    return@withLock Outcome(false, "写入失败 — 重连后再试", trace.toString())
                }
                val res = awaitFrame(notes, 0x04, 5_000)
                    ?: return@withLock Outcome(false, "开锁没有回执 — 门锁可能已执行, 先看一眼门", trace.toString())
                rc = KfProtocol.rc(res)
                trace.append("04→rc=" + rc + " ")
                if ((rc == 3 || rc == 13) && attempt == 1) {
                    trace.append("(会话过期, 重取令牌再试) ")
                    continue
                }
                break
            }
            Outcome(rc == 0, KfProtocol.rcText(rc), trace.toString())
        } catch (se: SecurityException) {
            // @SuppressLint("MissingPermission") 只让 lint 闭嘴, 运行时该抛还是抛 ——
            // 用户在系统设置里当场收回蓝牙权限时, 这一支不接住就是闪退。
            Outcome(false, "蓝牙权限被收回了 — 到系统设置里重新允许后重试")
        } catch (ce: CancellationException) {
            // 取消不是失败: 原样抛回去, 让 withLock / Mutex 的等待方按协程语义收尾。
            throw ce
        } catch (e: Exception) {
            Outcome(false, "开锁失败: " + humanBle(e))
        } finally {
            // 先 disconnect、等 onConnectionStateChange(DISCONNECTED) 落地再 close:
            // 顺序反了 (disconnect 后立刻 close) Android 会吞掉断开回调并泄漏一个 clientIf
            // (GATT 接口位)。攒够若干个之后 connectGatt 直接返回失败 —— 比 rc=13 更难查。
            // 等不到也照样 close, 不把这一次开锁吊死。
            val g2 = gatt
            if (g2 != null) {
                runCatching { g2.disconnect() }
                runCatching { withTimeoutOrNull(1_200) { disconnected.await() } }
                runCatching { g2.close() }
            }
            runCatching { notes.close() }
        }
    }

    // ---------- 内部 ----------

    private suspend fun scanForLock(lock: LockInfo, timeoutMs: Long): BluetoothDevice? {
        val scanner = adapter?.bluetoothLeScanner ?: return null
        val found = CompletableDeferred<BluetoothDevice>()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val adv = advOf(result) ?: return
                if (KfProtocol.normMac(adv.mac) == lock.mac) found.complete(result.device)
            }
        }
        // 同上: 不能按服务 UUID 过滤。BLUETOOTH_SCAN 被拒时这里抛 SecurityException,
        // 由 unlock() 那层的 try/catch 接住 (取消原样上抛, 其余转成人话)。
        scanner.startScan(null, settings, cb)
        val dev = withTimeoutOrNull(timeoutMs) { found.await() }
        runCatching { scanner.stopScan(cb) }
        return dev
    }

    private suspend fun writeChunked(
        gatt: BluetoothGatt,
        chr: BluetoothGattCharacteristic,
        data: ByteArray,
        bind: (CompletableDeferred<Boolean>) -> Unit,
    ): Boolean {
        var off = 0
        while (off < data.size) {
            val n = minOf(20, data.size - off)   // 与 iOS/Java 同一分片大小
            val chunk = data.copyOfRange(off, off + n)
            val done = CompletableDeferred<Boolean>()
            bind(done)
            // API 33 起 writeCharacteristic 返回的是 BluetoothStatusCodes (Int), 不是 Boolean
            val req = runCatching {
                gatt.writeCharacteristic(chr, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
            }.getOrNull()
            if (req != BluetoothStatusCodes.SUCCESS) return false
            val ok = withTimeoutOrNull(4_000) { done.await() } ?: return false
            if (!ok) return false
            off += n
        }
        return true
    }

    private suspend fun awaitFrame(
        ch: ReceiveChannel<ByteArray>,
        cmd: Int,
        timeoutMs: Long,
    ): KfProtocol.Frame? {
        val buf = StringBuilder()
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val left = deadline - System.currentTimeMillis()
            val chunk = try {
                withTimeoutOrNull(left) { ch.receive() } ?: return null
            } catch (e: Exception) {
                // 整个作用域被取消 (界面销毁/用户切走) 必须**原样抛回去**: 吞掉它会把"取消"
                // 说成"门锁没有回应", 还会让上层以为这一趟真跑完了。
                if (e is CancellationException) throw e
                return null   // 其余异常 = finally 里 notes.close() 触发的收尾 —— 链路已关, 不是锁没回应
            }
            buf.append(KfProtocol.hex(chunk))
            // 一次到达的可能是 0 / 1 / 多帧, 也可能只有半帧。口径照 iOS ZKProtocol.FrameAssembler:
            //  ① 先重同步到帧首标记 "87" (它之前是残帧/噪声, 留着永远解不出来);
            //  ② 逐帧吃掉, 只消费这一帧自己那一段, 剩下半截留在 buf 里等下一包。
            //     旧实现是"parse 成功就整块 clear" —— 帧粘连时把下一帧的开头一起丢了,
            //     表现就是偶发的"门锁没有回应 — 靠近一点再试"。
            while (true) {
                val start = buf.indexOf("87")
                if (start < 0) { buf.setLength(0); break }
                if (start > 0) buf.delete(0, start)
                val f = KfProtocol.parse(buf.toString()) ?: break
                val rest = buf.substring(minOf(f.raw.length, buf.length))
                buf.setLength(0)
                buf.append(rest)
                if (f.cmd == cmd) return f
                // 开锁链上出现的其它命令 = 上一趟迟到的陈旧帧, 丢掉继续等
            }
        }
        return null
    }

    /**
     * 从广播里认出这把锁的身份段。
     * Android 的 manufacturerSpecificData **不含** 2 字节厂商 ID (正常机型), 但也有机型把它一起塞进
     * value —— 所以两条都试: 先按"值即身份段"解析, 再在值里找 98 ED 从其后解析。
     * 与 iOS 端"在厂商 hex 里找 98ed"是同一件事, 只是这里不用拼字符串。
     */
    private fun advOf(result: ScanResult): KfProtocol.Adv? {
        val data = result.scanRecord?.manufacturerSpecificData ?: return null
        for (i in 0 until data.size()) {
            val p = data.valueAt(i) ?: continue
            KfProtocol.parseAdv(p, result.rssi)?.let { return it }
            val idx = indexOfCompanyId(p)
            if (idx >= 0 && idx + 2 < p.size) {
                KfProtocol.parseAdv(p.copyOfRange(idx + 2, p.size), result.rssi)?.let { return it }
            }
        }
        return null
    }

    private fun indexOfCompanyId(p: ByteArray): Int {
        for (i in 0 until p.size - 1) {
            if (p[i] == 0x98.toByte() && p[i + 1] == 0xED.toByte()) return i
        }
        return -1
    }

    /**
     * 蓝牙异常 → 人话。SecurityException 的 message 是框架英文串, 拼给用户读不懂;
     * 而"权限被拒"与"蓝牙栈本身坏了"(RuntimeException) 是两种完全不同的补救动作, 必须分开说。
     */
    private fun humanBle(e: Throwable): String = when (e) {
        is SecurityException -> "蓝牙权限被拒绝了 — 到系统设置里允许后重试"
        else -> e.message ?: "未知错误"
    }

    private companion object {
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
