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
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID

/**
 * 开锁链: 扫描 → 连接 → 订阅 → 01 取令牌 → 04 开锁。
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
        // 按服务过滤会一条结果都收不到, 这正是"提示找不到门锁"的第一个原因 (iOS 侧同样 withServices: nil)
        scanner.startScan(null, settings, cb)
        awaitClose { runCatching { scanner.stopScan(cb) } }
    }

    /** 一次性开锁。返回的 message 直接给用户看。 */
    suspend fun unlock(lock: LockInfo): Outcome = mutex.withLock {
        val ad = adapter ?: return@withLock Outcome(false, "这台手机没有蓝牙")
        if (!ad.isEnabled) return@withLock Outcome(false, "蓝牙未开启")
        val device = runCatching { scanForLock(lock, 7000) }.getOrElse { e ->
            return@withLock Outcome(false, "扫描失败: ${e.message ?: "蓝牙权限被拒绝?"}")
        } ?: return@withLock Outcome(false, "没找到这把锁 — 靠近门锁, 或确认门锁有电")

        var gatt: BluetoothGatt? = null
        return@withLock try {
            val notes = Channel<ByteArray>(Channel.UNLIMITED)
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
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        connected.complete(false)
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
                    mtuOk.complete(true)
                }
            }

            // connectGatt 之后再取一次非空引用: gatt 是 var, 编译器不会对它做智能转换
            val g = device.connectGatt(ctx, false, cb, BluetoothDevice.TRANSPORT_LE)
                ?: return@withLock Outcome(false, "无法建立连接")
            gatt = g

            if (withTimeoutOrNull(10_000) { connected.await() } != true) {
                return@withLock Outcome(false, "连接超时 — 离门锁再近一点")
            }
            if (withTimeoutOrNull(6_000) { servicesOk.await() } != true) {
                return@withLock Outcome(false, "读取门锁服务失败")
            }
            // 把 ATT MTU 抬起来: 安卓默认 23 (每包 20 字节), 而 iOS 侧自动协商到 180+。
            // 不抬也能用 (我们本来就是 20 字节分片), 但 56 字节的开锁帧要分成 3 片、每片等一次写确认。
            // 抬上去之后 1 片写完 —— "靠近自动开锁"的体感差别就在这儿。
            g.requestMtu(256)
            withTimeoutOrNull(2_000) { mtuOk.await() }

            val svc = g.getService(svcUuid) ?: return@withLock Outcome(false, "这把锁不支持开锁通道")
            val write = svc.getCharacteristic(UUID.fromString(KfProtocol.CHR_WRITE))
                ?: return@withLock Outcome(false, "门锁写通道缺失")
            val notify = svc.getCharacteristic(UUID.fromString(KfProtocol.CHR_NOTIFY))
                ?: return@withLock Outcome(false, "门锁通知通道缺失")

            g.setCharacteristicNotification(notify, true)
            val cccd = notify.getDescriptor(CCCD)
            if (cccd != null) {
                g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                withTimeoutOrNull(4_000) { notifyOn.await() }
            }

            val trace = StringBuilder()
            // 01 取会话令牌 → 04 开锁。rc=3 (命令过期) / rc=13 (通讯过期) 都是"会话令牌不认了":
            // 重取一次令牌再发, 只做一轮 (iOS 对 rc=3 是同一招; rc=13 在配对语境里也是令牌失效)。
            var rc = -1
            for (attempt in 1..2) {
                if (!writeChunked(g, write, KfProtocol.bytes(KfProtocol.tokenFrame())) { writeDone = it }) {
                    return@withLock Outcome(false, "写入失败 — 重连后再试", trace.toString())
                }
                val tokenFrame = awaitFrame(notes, 0x01, 4_000)
                    ?: return@withLock Outcome(false, "门锁没有回应 — 靠近一点再试", trace.toString())
                val token = tokenFrame.klvs[0x02]
                if (token == null) {
                    return@withLock Outcome(
                        false, "门锁未给会话令牌 (rc=${KfProtocol.rc(tokenFrame)})", trace.toString())
                }
                trace.append("01→${token.take(8)} ")

                val hex = KfProtocol.injectToken(KfProtocol.unlockFrame(lock.ekey), token)
                if (!writeChunked(g, write, KfProtocol.bytes(hex)) { writeDone = it }) {
                    return@withLock Outcome(false, "写入失败 — 重连后再试", trace.toString())
                }
                val res = awaitFrame(notes, 0x04, 5_000)
                    ?: return@withLock Outcome(false, "开锁没有回执 — 门锁可能已执行, 先看一眼门", trace.toString())
                rc = KfProtocol.rc(res)
                trace.append("04→rc=$rc ")
                if ((rc == 3 || rc == 13) && attempt == 1) {
                    trace.append("(会话过期, 重取令牌再试) ")
                    continue
                }
                break
            }
            Outcome(rc == 0, KfProtocol.rcText(rc), trace.toString())
        } catch (e: Exception) {
            Outcome(false, "开锁失败: ${e.message ?: "未知错误"}")
        } finally {
            runCatching { gatt?.disconnect() }
            runCatching { gatt?.close() }
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
        scanner.startScan(null, settings, cb)   // 同上: 不能按服务 UUID 过滤
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
            if (gatt.writeCharacteristic(chr, chunk, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
                != BluetoothStatusCodes.SUCCESS
            ) return false
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
            val chunk = withTimeoutOrNull(left) { ch.receive() } ?: return null
            buf.append(KfProtocol.hex(chunk))
            val f = KfProtocol.parse(buf.toString())
            if (f != null) {
                if (f.cmd == cmd) return f
                buf.clear()   // 开锁链上不会有别的命令, 收到即视为陈旧帧
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

    private companion object {
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
