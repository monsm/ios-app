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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * 开锁链: (预热) → 扫描 → 连接 → 订阅 → (03 认锁) → 01 取令牌 → 04 开锁。
 *
 * ── 链路复用: "靠近秒开"的全部秘密 ──
 * 开锁成功后**不拆链路**, 下一次靠近只剩 01+04 两个往返 (几十毫秒)。与 iOS 同一口径:
 * App/Services/LockService.swift:447 的 unlock() 里没有一处 disconnect, 而 ensureConnected(:75)
 * 命中"已连同一把"时零成本直接返回。安卓旧实现每次开锁都在 finally 拆链, 于是"靠近"永远要付
 * 全量冷启动: 扫描窗口 7s + 建链窗口 10s + 发现服务 6s + 订阅 4s + 认锁 3s。
 * 体感差距全部在这里 —— 不在协议, 不在锁端, 也不在任何安全门上。
 *
 * 再往前一步是 prewarm(): 信号刚进"快到门口"就后台把链路建好 (只建链, 一个命令都不发),
 * 等越过触发线时链路已是热的 —— 人还没站定, 门已经在开。这对应 iOS 的 93/134 信号围栏预握手
 * (LinkSenseKit.preconnect), 不是新发明。
 *
 * 所有 GATT 操作串行化 (Mutex): 预热、靠近自动开锁、手动点击可能同时发生, 两条链撞在一起
 * 会把 gatt 写成半截帧。
 */
@SuppressLint("MissingPermission")
class BleUnlocker(private val ctx: Context) {

    private val manager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = manager.adapter
    private val mutex = Mutex()
    private val svcUuid: UUID = UUID.fromString(KfProtocol.SVC)

    /// trace = 这一趟的过程留痕 (链路来源 / 令牌前缀 / rc)。只在失败时给用户看。
// 2026-10-27 审核补齐 (C-A1)：加 rc 字段 —— 调用方需要它做 F6 锁态门（25 锁忙 / 26 被撬）。
data class Outcome(val ok: Boolean, val message: String, val trace: String = "", val rc: Int = 0)

    fun isReady(): Boolean = adapter?.isEnabled == true

    // ---------- 链路会话 (复用单位) ----------

    /**
     * 一条已建立、已订阅、(可选) 已核过身份的连接。
     *
     * gatt/write 连上之后才有值所以是 var, 且被 GATT 回调线程与协程线程共享 ⇒ @Volatile
     * (旧写法把这些状态放在协程局部变量里给匿名回调捕获, 没有任何可见性保证)。
     */
    private class Session(val mac: String) {
        val notes = Channel<ByteArray>(Channel.UNLIMITED)
        val connected = CompletableDeferred<Boolean>()
        val servicesOk = CompletableDeferred<Boolean>()
        val notifyOn = CompletableDeferred<Boolean>()
        val disconnected = CompletableDeferred<Boolean>()

        @Volatile var gatt: BluetoothGatt? = null
        @Volatile var write: BluetoothGattCharacteristic? = null
        @Volatile var writeDone: CompletableDeferred<Boolean>? = null
        @Volatile var rssiRead: CompletableDeferred<Int?>? = null   // 连接层测距的落点
        @Volatile var identityVerified = false   // 这条链路已用锁端 03 自报 pid 核过身份
        @Volatile var lastUsedAt = System.currentTimeMillis()

        /**
         * 链路死了: 让所有还在等的步骤**立刻**拿到 false, 而不是各自空等满超时。
         *
         * 用 complete(false) 而不是 cancel(): cancel 会让等待方抛 CancellationException,
         * 而本文件把 CancellationException 一律原样上抛 (界面销毁/协程取消), 那会把一次
         * 普通断链错报成"开锁被中断"。
         */
        fun onLinkDown() {
            disconnected.complete(true)
            connected.complete(false)
            servicesOk.complete(false)
            notifyOn.complete(false)
            writeDone?.complete(false)
        }
    }

    private var warm: Session? = null

    /**
     * 最近一次在广播里见到这把锁时拿到的设备句柄 (mac → 句柄 + 时刻)。
     *
     * 为什么要缓存: 预热与冷启动开锁都要"先扫到再连"。而系统**同时只跑一路扫描** ——
     * 监测流 (observeRssi) 正在扫的时候, 另起一次 startScan 会把它顶掉, 而收尾那句
     * stopScan 又会把监测一起停掉 (表现 = "当前信号再也不更新")。缓存句柄之后, 预热
     * 和开锁都直接用监测流已经扫到的那个 device, **一次多余的扫描都不发起**。
     * 句柄只在同一台机器上当次有效, 所以带时刻, 超过 10 秒视为过期 (走扫描兜底)。
     *
     * 线程口径: 写点在 observeRssi 的 ScanCallback (蓝牙栈默认派发到注册者的主线程 looper,
     * 与 startScan 的四参重载里那个可传 Handler 同一个默认), 而**读/清在 mutex 里面** ——
     * mutex 不绑定线程, MainActivity.onDestroy 那条 release() 走的是自己起的后台线程,
     * 于是同一张表会出现"主线程写 + 另一线程清"。所以用并发容器, 不靠"大概都在主线程"。
     */
    private val seen = ConcurrentHashMap<String, Pair<BluetoothDevice, Long>>()
    private val seenTtlMs = 10_000L

    // ---------- 对外 ----------

    /**
     * 一次性开锁。命中复用链路时只做 01+04; 否则先建链。返回的 message 直接给用户看。
     *
     * ⚠ 重试纪律 (G4, 对齐 vendor/app/services/lock.js 的 retries: 2 与 iOS LockService:252):
     *   只有"锁明确回了非 0 rc"才允许再来一次 —— 那证明锁**没执行**。回执超时/链路断掉时
     *   绝不重发 04: 帧已经出去了, 锁可能已经开过, 重发 = 电机连触发 = 双开。
     */
    suspend fun unlock(lock: LockInfo): Outcome = mutex.withLock {
        val ad = adapter ?: return@withLock Outcome(false, "这台手机没有蓝牙")
        if (!ad.isEnabled) return@withLock Outcome(false, "蓝牙未开启")

        val trace = StringBuilder()

        // ① 先试复用链路
        val reuse = pickWarm(lock)
        if (reuse != null) {
            trace.append("warm ")
            // 预热刻意不核身份 (省一个往返), 但**开锁必须核**: verifyIdentity 自己带会话级
            // "核过就跳过"位, 这条链路是首次开锁时它才会真发 03, 之后每次都是零成本。
            val deniedWarm = verifyIdentity(reuse, lock, trace)
            if (deniedWarm != null) {
                closeWarm(reuse)
                return@withLock deniedWarm
            }
            val a = runUnlock(reuse, lock, trace)
            if (a.outcome != null) {
                if (a.linkBroken) closeWarm(reuse)
                return@withLock a.outcome
            }
            // outcome == null 只可能来自"写被同步拒绝 / 句柄已没了" —— 帧根本没出手机,
            // 所以不存在"锁已经开过了"的歧义, 拆掉重建是安全的。
            trace.append("热链路写不通, 重建 ")
            closeWarm(reuse)
        } else if (warm != null) {
            // 有链路但用不上: 另一把锁 / 已断 / 句柄没了 / 超过 warmStaleMs。
            // warm 是可变属性, withLock 的 lambda 里编译器不会对它做智能转换, 所以取局部引用再拆。
            trace.append("旧链路不可复用, 重建 ")
            val stale = warm
            if (stale != null) closeWarm(stale)
        }

        // ② 冷路径。先用监测流刚扫到的句柄 (不另起扫描); 没有/过期才自己扫一次。
        // 写成显式 if/else 而不是 `freshSeen(...) ?: try { ... } ?: ...`: elvis 右侧接 try 表达式
        // 再串第二个 elvis 属于可读性极差的写法, 而本文件只能在 CI 编译, 不该拿语法边界去赌。
        val seenDevice = freshSeen(lock.mac)
        val scanned: BluetoothDevice?
        if (seenDevice != null) {
            scanned = seenDevice
        } else {
            scanned = try {
                scanForLock(lock, 3000)
            } catch (ce: CancellationException) {
                throw ce
            } catch (e: Exception) {
                return@withLock Outcome(false, "扫描失败: " + humanBle(e))
            }
        }
        val device = scanned
            ?: return@withLock Outcome(false, "没找到这把锁 — 靠近门锁, 或确认门锁有电")

        val s = Session(lock.mac)
        val built = try {
            buildLink(s, device)
        } catch (ce: CancellationException) {
            teardown(s)
            throw ce
        } catch (se: SecurityException) {
            teardown(s)
            return@withLock Outcome(false, "蓝牙权限被收回了 — 到系统设置里重新允许后重试")
        } catch (e: Exception) {
            teardown(s)
            return@withLock Outcome(false, "连接失败: " + humanBle(e))
        }
        if (!built) {
            teardown(s)
            return@withLock Outcome(false, linkFailMessage(s))
        }
        warm = s

        // ③ 身份复核 (只在真正要开锁这一次做; 预热不核, 见 prewarm)
        val denied = verifyIdentity(s, lock, trace)
        if (denied != null) {
            closeWarm(s)
            return@withLock denied
        }
        val a2 = runUnlock(s, lock, trace)
        if (a2.linkBroken) closeWarm(s)
        return@withLock a2.outcome ?: Outcome(false, "开锁没有回执 — 门锁可能已执行, 先看一眼门", trace.toString())
    }

    // ---------- 链路选择 ----------

    /** 热链路最长可信时间: 超过它就重建。锁端广播间隔 1.5s, 真断了回调几秒内就到;
     *  60s 是给"对端睡了但没发 DISCONNECTED"这种半死状态留的兜底, 不是省电参数。 */
    private val warmStaleMs = 60_000L

// 2026-10-27 审核（AUDIT-A F-21）：本文件原先的超时窗口比 vendor 紧 2–5 倍
// （连接 3000 vs 15000、每片写 4000 vs 8000、开锁回包 3000 vs 8000），
// 而 04 超时**绝不重发**（防双开，这是对的）⇒ 弱信号下一次超时 = 一次开锁失败，没有第二次机会。
// 已对齐 vendor/app/services/lock.js:199 的 timeout: 8000 / 连接 15000。
// 唯一保留偏短的是「断开等待 1200ms」（那是 teardown 的礼貌等待，不是协议窗口）。

    /** 可以拿来直接开锁的链路; 有链路但不可用 → 返回 null 并把外层该拆谁写清楚。 */
    private fun pickWarm(lock: LockInfo): Session? {
        val w = warm ?: return null
        if (w.mac != lock.mac) return null
        if (w.disconnected.isCompleted) return null
        if (w.gatt == null || w.write == null) return null
        if (System.currentTimeMillis() - w.lastUsedAt > warmStaleMs) return null
        return w
    }

    private suspend fun closeWarm(s: Session) {
        if (warm === s) warm = null
        // 链路断了就把对应句柄一起丢掉: 那台设备的广播可能已经换了状态 (锁睡过去了 / 被人挪走),
        // 拿旧句柄重连只会换一种失败方式 (133) 而不是更快。
        seen.remove(s.mac)
        teardown(s)
    }

    /** 监测流给的句柄, 只在 TTL 内认。 */
    private fun freshSeen(mac: String): BluetoothDevice? {
        val (dev, at) = seen[mac] ?: return null
        if (System.currentTimeMillis() - at > seenTtlMs) { seen.remove(mac); return null }
        return dev
    }

    /**
     * 主动拆链路 (解绑 / 关开关 / 界面销毁)。只有挂起版: release() 要等断开回执落地 (teardown),
     * 那是挂起动作为。MainActivity.onDestroy 里用一条后台线程 runBlocking 调它 —— 不能在主线程
     * 直接 runBlocking (最长要等 1.2s, 会卡销毁流程), 也不该在 onDestroy 里起协程作用域 (它已经没了)。
     */
    suspend fun release() = mutex.withLock {
        val w = warm
        warm = null
        seen.clear()
        if (w != null) teardown(w)
    }

    /** 必须持锁调用: 先 disconnect、等断开回执落地再 close。 */
    private suspend fun teardown(s: Session) {
        val g = s.gatt
        if (g != null) {
            // 顺序反了 (disconnect 后立刻 close) Android 会吞掉断开回调并泄漏一个 clientIf
            // (GATT 接口位)。攒够若干个之后 connectGatt 直接返回失败 —— 比 rc=13 更难查。
            runCatching { g.disconnect() }
            runCatching { withTimeoutOrNull(1_200) { s.disconnected.await() } }
            runCatching { g.close() }
        }
        s.onLinkDown()
        runCatching { s.notes.close() }
    }

    /**
     * 建链失败到底卡在哪一步, 给用户分得开的那两档。
     *
     * getCompleted() 是 ExperimentalCoroutinesApi, 所以**只给这一个函数**加 @OptIn: 这里读的是
     * connected 已完成的那个 Boolean (true=GATT 连上了但服务没读到 / false=链路死了), 用
     * isCompletedExceptionally 区分不出来 (complete(false) 是正常完成, 不是异常完成)。
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    private fun linkFailMessage(s: Session): String {
        val connected = s.connected.isCompleted && runCatching { s.connected.getCompleted() }.getOrDefault(false)
        return if (connected) "连上了但读不到开锁通道 (服务/特征缺失) — 这把锁的凭证可能不是给本机的"
            else "连不上这把锁 — 离门锁再近一点, 或关掉其它蓝牙调试 App"
    }

    // ---------- 预热 ----------

    /**
     * 后台把链路建好: **只建链, 一个命令都不发** (01/03/04 都不发)。
     * 失败一律静默 —— 它只是让下一次开锁变快, 不是功能本身, 不该因此给用户报错。
     * 对应 iOS 的 93/134 信号围栏预握手 (LinkSenseKit.preconnect), 不是新发明。
     */
    suspend fun prewarm(lock: LockInfo) = mutex.withLock {
        // 一次只养一条链路: 同锁且还活着 = 已经预热好, 直接返回; 是别的锁或已断 = 先拆掉再预热。
        val cur = warm
        if (cur != null) {
            if (cur.mac == lock.mac && !cur.disconnected.isCompleted) return@withLock
            closeWarm(cur)
        }
        val ad = adapter ?: return@withLock
        if (!ad.isEnabled) return@withLock
        // 预热**绝不自己起扫描**: 安卓同时只跑一路扫描, 另起一次会顶掉监测流, 而它收尾那句
        // stopScan 又把监测一起停 (表现 = "当前信号再也不更新")。句柄一律从 observeSignal 的
        // 广播缓存里取 —— 监测窗 3 秒一轮, 首轮就会把句柄填进来。
        val device = freshSeen(lock.mac) ?: return@withLock
        seen.remove(lock.mac)   // 一次性: 句柄交给连接用了, 连着失败时不拿旧句柄反复重试
        val s = Session(lock.mac)
        try {
            if (buildLink(s, device)) {
                warm = s   // 身份复核留给真正开锁那一次 (prewarm 不碰 03, 少一个往返)
            } else {
                teardown(s)
            }
        } catch (ce: CancellationException) {
            teardown(s)
            throw ce
        } catch (_: Exception) {
            teardown(s)
        }
    }

    // ---------- 开锁动作 (热/冷两条路共用) ----------

    /** outcome=null = "帧没出手机"级别的失败, 外层可以安全拆链重建。 */
    private class Attempt(val outcome: Outcome?, val linkBroken: Boolean)

    private suspend fun runUnlock(s: Session, lock: LockInfo, trace: StringBuilder): Attempt {
        val g = s.gatt ?: return Attempt(null, false)
        val write = s.write ?: return Attempt(null, false)
        var rc = -1
        for (attempt in 1..2) {
            if (!writeChunked(g, write, KfProtocol.bytes(KfProtocol.tokenFrame()), s)) {
                s.lastUsedAt = System.currentTimeMillis()
                return Attempt(null, true)   // 01 都没写出去: 锁肯定没动作, 拆链重建安全
            }
            val tokenFrame = awaitFrame(s.notes, 0x01, 8_000)
                ?: return Attempt(Outcome(false, "门锁没有回应 — 靠近一点再试", trace.toString()),
                        s.disconnected.isCompleted)
            val token = tokenFrame.first(0x02)
            if (token == null) {
                // ⚠ 01 的响应里**没有 rc**: KLV#03 在那一帧是"令牌有效秒数 (u16 LE)"。
                // JS lock.js 的 RC_KLV 压根没有 0x01 这一项 (iOS extractRc 对 01 恒返 0)。
                // 权威口径两条都照搬: JS lock.js:254 报安全类型, iOS LockService:178 报回包形状。
                val secType = tokenFrame.first(0x01)?.let { KfProtocol.intHex(it) and 0x03 }
                return Attempt(
                    Outcome(
                        false,
                        "门锁没有给会话令牌 (安全类型=" + (secType?.toString() ?: "无") +
                            ", 回包 " + KfProtocol.klvShape(tokenFrame) + ") — 离门锁近一点再试",
                        trace.toString()),
                    s.disconnected.isCompleted)
            }
            trace.append("01→" + token.take(8) + " ")

            val hex = KfProtocol.injectToken(KfProtocol.unlockFrame(lock.ekey), token)
            // 护栏 (2026-10-17 那个 rc=13 的坑): 令牌 KLV 必须逐字节躺在帧尾才算注入成功。
            val tokKlv = KfProtocol.klv(0xEE, token).uppercase()
            if (!hex.endsWith(tokKlv)) {
                return Attempt(Outcome(false, "内部错误: 会话令牌没能装进开锁帧", trace.toString()), false)
            }
            if (!writeChunked(g, write, KfProtocol.bytes(hex), s)) {
                // 04 的写入被同步拒绝 = 没出手机; 但已经发出去过几片时不能一概而论 ——
                // writeChunked 只在"这片被拒/这片没确认"时返回 false, 前面的片可能已到锁端。
                // 保守起见: 报"可能已执行", linkBroken=true 让外层拆链, 但**绝不原地重发**。
                return Attempt(
                    Outcome(false, "开锁写入中断 — 门锁可能已执行, 先看一眼门", trace.toString()),
                    true)
            }
            val res = awaitFrame(s.notes, 0x04, 8_000)
                // 回执超时: 帧已出手机, 锁可能正在开 —— linkBroken=false, 绝不重建重发 (双开红线)
                ?: return Attempt(
                    Outcome(false, "开锁没有回执 — 门锁可能已执行, 先看一眼门", trace.toString()),
                    false)
            rc = KfProtocol.rc(res)
            trace.append("04→rc=" + rc + " ")
            s.lastUsedAt = System.currentTimeMillis()
            if ((rc == 3 || rc == 13) && attempt == 1) {
                trace.append("(会话过期, 重取令牌再试) ")
                continue
            }
            break
        }
        return Attempt(Outcome(rc == 0, KfProtocol.rcText(rc), trace.toString(), rc), s.disconnected.isCompleted)
    }
    // ---------- 建链 ----------

    private suspend fun buildLink(s: Session, device: BluetoothDevice): Boolean {
        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    s.connected.complete(true)
                    runCatching { g.discoverServices() }
                } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                    // 连上了但 status 带错 (133 / 一连上就被断的竞态)。旧代码两个分支都不命中 →
                    // connected 永不完成 → 干等满 10 秒 → 报成"连接超时", 把真因盖住。
                    s.onLinkDown()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    s.onLinkDown()
                }
            }
            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                s.servicesOk.complete(status == BluetoothGatt.GATT_SUCCESS)
            }
            override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
                if (d.uuid == CCCD) s.notifyOn.complete(status == BluetoothGatt.GATT_SUCCESS)
            }
            override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
                // 复用链路时 writeDone 是会话字段 (@Volatile), 不是协程局部 var
                s.writeDone?.complete(status == BluetoothGatt.GATT_SUCCESS)
            }
            override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
                s.notes.trySend(value)
            }
            override fun onReadRemoteRssi(g: BluetoothGatt, rssi: Int, status: Int) {
                // status 带错给 null: "读不到"与"读到 -80"是两件事, 不硬编数字。
                s.rssiRead?.complete(if (status == BluetoothGatt.GATT_SUCCESS) rssi else null)
            }
            override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
                // MTU 是纯优化 (分片恒 20B), 不参与判定, 所以这里什么都不做。
                // 旧实现不看 status 就恒 complete(true), 那是把"协商失败"报成"协商成功"。
            }
        }
        // 停扫之后 settle 一下再连: scanForLock 收尾那句 stopScan 是异步生效的, 立刻 connectGatt
        // 是安卓 GATT 133 的头号成因 (射频还在扫描态)。命中复用链路时**根本不走这里**, 不付这个钱。
        delay(80)   // 停扫后仍需 settle 一拍再连 (边扫边连 = 133 头号成因), 但从 120 收到 80
        val g = device.connectGatt(ctx, false, cb, BluetoothDevice.TRANSPORT_LE) ?: return false
        s.gatt = g
        if (withTimeoutOrNull(15_000) { s.connected.await() } != true) return false
        if (withTimeoutOrNull(8_000) { s.servicesOk.await() } != true) return false
        val svc = g.getService(svcUuid) ?: return false
        val write = svc.getCharacteristic(UUID.fromString(KfProtocol.CHR_WRITE)) ?: return false
        val notify = svc.getCharacteristic(UUID.fromString(KfProtocol.CHR_NOTIFY)) ?: return false
        s.write = write
        runCatching { g.setCharacteristicNotification(notify, true) }
        val cccd = notify.getDescriptor(CCCD)
        if (cccd != null) {
            // API 33+ 这个重载返回 BluetoothStatusCodes (Int): 同步就被拒时不会再有回调,
            // 旧代码于是白等满 4 秒才往下走。
            val req = runCatching {
                g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            }.getOrNull()
            if (req == BluetoothStatusCodes.SUCCESS) withTimeoutOrNull(8_000) { s.notifyOn.await() }
        }
        // 协商 MTU: 只谈 ATT 层上界, **分片仍恒按 20 字节** (iOS BLEService.writeFrame 与 JS
        // writeFrame 都是 20B 定长分片, 锁端按 20B 组包 —— 跟着 MTU 放大分片会让锁收到残帧)。
        runCatching { g.requestMtu(256) }
        s.lastUsedAt = System.currentTimeMillis()
        return true
    }

    // ---------- 身份复核 ----------

    /** 返回非 null = 该停手并把这个结论给用户。同一条链路只核一次 (核过就记在会话上)。 */
    private suspend fun verifyIdentity(s: Session, lock: LockInfo, trace: StringBuilder): Outcome? {
        if (lock.pid <= 0 || s.identityVerified) return null
        val g = s.gatt ?: return null
        val write = s.write ?: return null
        // 对齐 iOS LockService.swift:105。为什么不在扫描那一跳比广播 pid: 广播厂商段里那个 pid
        // 与台账 pid **不是同一套编号** (golden: parseAdv 的 7970 vs status KLV#34 的 16289),
        // 拿它拦会把真锁误杀成"pid 不符"。广播是任何设备都能发的, 锁端响应难伪造得多。
        // 03 在 04 之前、不驱动执行器, 多发一次没有副作用 (对照 G4 只约束 04 的重发)。
        if (!writeChunked(g, write, KfProtocol.bytes(KfProtocol.statusFrame()), s)) {
            trace.append("03→写不通 ")
            return null   // 加固不是新闸门: 这条发不出去就照开 (交给 04 自己判定)
        }
        val st = awaitFrame(s.notes, 0x03, 8_000)
        if (st == null) { trace.append("03→无回应 "); return null }
        val selfPid = KfProtocol.pidOf(st)
        if (selfPid <= 0) { trace.append("03→无pid "); return null }
        trace.append("03→pid=" + selfPid + " ")
        if (selfPid != lock.pid) {
            return Outcome(
                false,
                "连到的设备与「" + lock.name + "」不是同一把锁 (pid 不符) — 附近可能有同名或伪造广播",
                trace.toString() + "登记 pid=" + lock.pid)
        }
        s.identityVerified = true
        return null
    }

    // ---------- 近场信号 ----------

    /**
     * 统一信号流 —— **"靠近秒开"成不成立就在这一条上**。
     *
     * 物理事实: 门锁一旦被连上就**停掉广播** (连着还发广播是白费的, 厂商固件不为已连接的设备
     * 继续 advertise)。所以只看扫描结果的旧写法, 从"链路热起来"那一刻起就再也收不到样本。
     * 用户报的两条症状正是它:
     *   · "信号刷新很慢很慢" = 连上之后信号干脆不动了, 界面停在最后一次读数;
     *   · "自动解锁很慢/不开" = 没有新样本 ⇒ 武装位永远置不起来, 自动链根本不会点火。
     * iOS 侧更彻底: BLEService 里 readRSSI() 一次都没调过 (本轮查实), 所以自动开锁在
     * "已连接"状态下只能靠连接前最后一帧广播的陈旧值。
     *
     * 于是分两路: **有活链路就按连接层测距 (readRemoteRssi), 没有才去扫广播**。
     * 另两个好处: ① 测距顺带刷新 lastUsedAt, 热链路不会在 60 秒后被自己判过期 —— 那正是
     * "手动点击也要 3 秒以上"的成因 (又付一遍扫描+建链+订阅+认锁);
     * ② 连着的时候不再扫描, 手机射频与锁的电量都少一份开销 (与"后台不扫锁"同源)。
     *
     * 用 channelFlow 而不是 flow: 内层 withTimeoutOrNull 跑在子协程里, 从子协程向 flow{}
     * 的 emitter 发射违反 Flow 不变式 (运行期 IllegalStateException, 编译器抓不到)。
     */
    fun observeSignal(lock: LockInfo): Flow<Int> = channelFlow {
        val pump = launch {
            while (isActive) {
                val warm = pickWarm(lock)
                if (warm != null) {
                    val r = readLinkedRssi(warm)
                    if (r != null) send(r)
                    if (warm.disconnected.isCompleted) continue   // 链路刚死: 立刻回到循环去扫
                    delay(200)
                } else {
                    // 扫描只在"没有链路"时开, 3 秒一窗: 窗内若预热把链路建好, 下一窗自动
                    // 切到连接层测距, 而这一窗收尾时 stopScan 已经把射频放掉了。
                    withTimeoutOrNull(3_000) { observeRssi(lock).collect { send(it) } }
                }
            }
        }
        awaitClose { pump.cancel() }
    }

    /** 一次连接层测距。读到就算"这条链路还活着", 顺手刷新 lastUsedAt。 */
    private suspend fun readLinkedRssi(s: Session): Int? {
        val g = s.gatt ?: return null
        val d = CompletableDeferred<Int?>()
        s.rssiRead = d
        if (!runCatching { g.readRemoteRssi() }.getOrDefault(false)) return null
        val v = withTimeoutOrNull(1_500) { d.await() }
        if (v != null) s.lastUsedAt = System.currentTimeMillis()
        return v
    }

    /**
     * 近场信号流: 只上报这把锁的广播 RSSI (dBm)。UI 拿它判"到没到门口"以及触发预热。
     * 扫不到时不会报 0 —— 不发明数据。
     */
    fun observeRssi(lock: LockInfo): Flow<Int> = callbackFlow {
        val scanner = adapter?.bluetoothLeScanner
        if (scanner == null) { close(); return@callbackFlow }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            // 不加 setMatchMode/setNumOfMatches: 那两个只在**设了 ScanFilter 时**才生效,
            // 而这里必须 null filters (锁的广播只有厂商段 98ED、没有服务 UUID, 按 UUID 过滤
            // 一条都收不到)。写了就是假装提速的死配置 —— 刷新率的真实地板是锁端 1.5s 广播间隔,
            // 连上之后走 readRemoteRssi 的 200ms 轮询 (见 observeSignal), 那才是亚秒级的那一路。
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val adv = advOf(result) ?: return
                if (KfProtocol.normMac(adv.mac) == lock.mac) {
                    // 记句柄时顺手清掉过期项: 本 App 只存一把锁, 但解绑换锁后旧句柄不该留着
                    seen[lock.mac] = result.device to System.currentTimeMillis()
                    trySend(result.rssi)
                }
            }
            override fun onScanFailed(errorCode: Int) { close() }
        }
        // 不带 filters: 门锁的广播里只有厂商段 (98ED), **没有** 128 位服务 UUID ——
        // 按服务过滤会一条结果都收不到 (iOS 侧同样 withServices: nil)。
        // startScan 在 BLUETOOTH_SCAN 被拒时抛 SecurityException: 这条流在 LaunchedEffect 里
        // collect, 那一层没人接 → 不接住就是闪退 (而不是"信号读不到")。
        if (runCatching { scanner.startScan(null, settings, cb) }.isFailure) {
            close(); return@callbackFlow
        }
        awaitClose { runCatching { scanner.stopScan(cb) } }
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
        // 由调用方的 try/catch 接住 (取消原样上抛, 其余转成人话)。
        scanner.startScan(null, settings, cb)
        val dev = withTimeoutOrNull(timeoutMs) { found.await() }
        runCatching { scanner.stopScan(cb) }
        return dev
    }

    private suspend fun writeChunked(
        gatt: BluetoothGatt,
        chr: BluetoothGattCharacteristic,
        data: ByteArray,
        s: Session,
    ): Boolean {
        var off = 0
        while (off < data.size) {
            val n = minOf(20, data.size - off)   // 与 iOS/Java 同一分片大小
            val chunk = data.copyOfRange(off, off + n)
            val done = CompletableDeferred<Boolean>()
            s.writeDone = done
            // API 33 起 writeCharacteristic 返回的是 BluetoothStatusCodes (Int), 不是 Boolean
            val req = runCatching {
                gatt.writeCharacteristic(chr, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
            }.getOrNull()
            if (req != BluetoothStatusCodes.SUCCESS) return false
            val ok = withTimeoutOrNull(8_000) { done.await() } ?: return false
            if (!ok) return false
            off += n
        }
        return true
    }

        // 2026-10-27 审核说明 (AUDIT-A F-44)：这里用字符串 "87" 在缓冲区里重同步，
        // 而载荷内部也可能出现 0x87 —— 那时会误判成新帧起点。
        // vendor JS 侧同样这么写（它的 makeAssembler 也是 find("87")），
        // 属三端共同的历史做法。真要修得改成"按长度字段跳跃"而不是找字节。
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
                if (e is CancellationException) throw e
                return null   // 链路在等回包时被关掉 —— 不是"锁没回应", 别再报成那句
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
                val fr = KfProtocol.parse(buf.toString()) ?: break
                val rest = buf.substring(minOf(fr.raw.length, buf.length))
                buf.setLength(0)
                buf.append(rest)
                if (fr.cmd == cmd) return fr
                // 开锁链上出现的其它命令 = 上一趟迟到的陈旧帧, 丢掉继续等
            }
        }
        return null
    }

    /**
     * 从广播里认出这把锁的身份段。Android 的 manufacturerSpecificData **不含** 2 字节厂商 ID
     * (正常机型), 但也有机型把它一起塞进 value —— 所以两条都试。与 iOS"在厂商 hex 里找 98ed"同义。
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
     * 而"权限被拒"与"蓝牙栈本身坏了"(RuntimeException) 是两种不同的补救动作, 必须分开说。
     */
    private fun humanBle(e: Throwable): String = when (e) {
        is SecurityException -> "蓝牙权限被拒绝了 — 到系统设置里允许后重试"
        else -> e.message ?: "未知错误"
    }

    private companion object {
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
