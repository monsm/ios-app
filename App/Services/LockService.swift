// LockService — 离线管理端核心: 会话令牌生命周期 / 命令执行 / rc 守卫 / 配网编排
// 与 JS services/lock.js 同构: 无条件刷新令牌 (V81 语义) · rc=3 自愈重试 · G1~G8 守卫
import Foundation
import Combine

@MainActor
final class LockService: ObservableObject {
    static let shared = LockService()
    @Published var connectedMAC: String = ""
    @Published private(set) var lastError: String = ""
    @Published var logs: [String] = []
    /// 包11/740: 原始报文环形记录 (RX 帧 hex), 供诊断页 hex 查看, 不持久化
    @Published private(set) var recentFrames: [String] = []

    let ble = BLEService.shared
    var sessionTokenHex: String = "0000"   // 锁端上报令牌的原始 hex — 整串透传 (JS utils/session.js:15 保存 k.val 全串)
    var tokenExpiryMs: Int64 = 0
    var curMac: String = ""
    var pairMac: String?
    var connectedDeviceId: String = ""  // BLE deviceId (UUID); connectedMAC = 解析出的锁 MAC

    init() {
        ble.onFrame { [weak self] frame in
            Task { @MainActor in self?.handle(frame) }
        }
        ble.bootstrap()
    }

    var debugRaw: Bool { DB.store.getBool("kf_debug_raw") }

    func log(_ level: String, _ msg: String) {
        // 同一份时间戳口径收进 DiagTime (hhmmss 此前零调用, 而这里手写了一份重复实现)
        let t = DiagTime.hhmmss()
        // 原始帧 hex 只进内存环形 recentFrames (诊断页 740 即时查看用): 帧内携带 skey/ekey/PIN 明文
        // (cmd05 换钥 / cmd0A 写密码 / cmd13 录指纹)。任何持久化或可复制出口都必须先脱敏 ——
        // logs 会被诊断页写进剪贴板, DiagLogs 落 kf_diag_logs (全仓无 isExcludedFromBackup → 随系统备份出机)
        // 并被导出中心 rawHexLines + ShareLink 带走。违 AUTOOPEN-PLAN §1「永不记 ekey/skey 明文」。
        let rawFrame = msg.contains("hex=")
        if rawFrame {
            recentFrames.append(msg)
            if recentFrames.count > 60 { recentFrames.removeFirst(recentFrames.count - 60) }
        }
        // 2026-10-27 审核恢复 (AUDIT-A F-03)：帧脱敏回来了。含 hex= 的日志只留 8 字节帧头，
        // 载荷（skey / 密码 / PIN / ekey）整段遮掉。完整帧只留在内存 recentFrames（不落盘、不可复制）。
        let shown = rawFrame ? FrameRedact.apply(msg) : msg
        logs.append("\(t) [\(level)] \(shown)")
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        if level == "warn" || level == "error" { lastError = shown }
        // 包11: 分级日志台账 (153/283/542/543 的解析源), 按 751 保留策略留档
        DiagLogs.append(level, shown, date: DiagLogs.localDay(), time: t)
    }

    // ---------- 帧等待 ----------
    struct Waiter {
        var cmd: UInt8
        var cont: CheckedContinuation<ZKProtocol.ParsedFrame, Error>
        var timer: DispatchWorkItem?
    }
    var waiter: Waiter?
    var collector: ((ZKProtocol.ParsedFrame) -> Void)?   // 多响应命令 (13 录指纹)
    var collectorCmd: UInt8 = 0

    // ---------- 请求 (令牌注入 + 重试 + 写失败清 waiter) ----------
    @discardableResult

    // rc 所在 KLV key (JS lock.js RC_KLV, 勘误后权威表)
    /// 0x88 包络里带 MAC 的命令 (rc=12 的顺序自愈只对它们有意义; 网关/明面命令的 MAC 在别处)。
    static let macBearingCmds: Set<UInt8> = [0x03, 0x04, 0x08, 0x0a, 0x0b, 0x0e, 0x13, 0x14,
                                                    0x15, 0x16, 0x18, 0x19, 0x20, 0x21, 0x22, 0x24,
                                                    0x25, 0x41, 0x43, 0x44]
    static let rcKLV: [UInt8: Int] = [
        0x03: 3, 0x04: 3, 0x05: 1, 0x08: 3, 0x0a: 3, 0x0b: 3, 0x0e: 3, 0x12: 3,
        0x13: 3, 0x14: 3, 0x15: 3, 0x16: 3, 0x18: 3, 0x19: 3, 0x20: 3,
        0x21: 3, 0x22: 3, 0x23: 3, 0x24: 3, 0x25: 3
        // 2026-10-28 修：补登记 `0x23`（ExKeyWay，配网握手的关键一步 `LockService.pair` 里调用）。
        // 它走的是 `request`/`extractRc`，而表里原来没有 0x23 ⇒ `guard let key = rcKLV[cmd] else { return 0 }`
        // 让它的 rc **恒为 0**：锁端拒绝握手时 iOS 会当成功、继续走后面的 05→08→21，
        // 最后得到一份对不上号的半成品台账。其它走 `HardwareService.send` 的命令（41/43/44/38/31/35）
        // 用的是 `rcOf`（无条件读 KLV#03），不受这张表影响。
    ]
    struct ExecResult { var frame: ZKProtocol.ParsedFrame; var rc: Int; var klvs: [ZKLV] }

    @discardableResult

    /// 回包的 KLV 形状 —— **只报键与长度, 一个值都不带**: 真机排障时 "#02=0B" 这种事实
    /// (锁压根没回密钥) 比任何猜测都有用, 而值里可能含 skey/ekey/PIN 明文 (不得进日志)。
    nonisolated static func klvShape(_ f: ZKProtocol.ParsedFrame) -> String {
        f.klvs.isEmpty ? "(无 KLV)" : f.klvs.map { String(format: "#%02x=%dB", $0.key, $0.vlen) }.joined(separator: " ")
    }

    // ---------- 连通探测 (cmd12 回声) ----------
    /// 一次回声往返的结果。`matched` = 锁回显的 KLV#01 与本机发出去的值**逐字节相同**。
    struct EchoProbe { var ok: Bool; var rc: Int; var echoHex: String; var ms: Int; var matched: Bool }

    /// 校时 (cmd 0E): 发**手机当前时间** —— 与原版 APK synctime 页完全一致
    /// (那边就是 `new St(En.getNowTimeString(), mac)`, 载荷为手机此刻的协议秒)。
    /// 旧实现算的是 `target = now + (lockSec - now)`, 数学上等于**把锁自己的钟原样写回去**:
    /// 屏上报"同步成功"而锁钟一秒没动 —— 而锁的命令有效期判据 (rc=3 命令过期 / rc=13 通讯过期)
    /// 全看这个钟, 所以这个空操作会把后面每一类命令都拖进时间问题里。
    /// 先读锁钟现在只用来**报告偏差** (读了不写回去), 再回读一次作为"真的写进去了"的证据 ——
    /// rc=0 只证明命令被接收, 不证明锁钟变了。

    @discardableResult

    // ---------- 指纹 ----------
    struct FpPress {
        var orderIdx: UInt32?
        var featureNumber: UInt32?
        var batchNumber: UInt32?
        var nextTimeout: UInt32?
        var rc: Int
    }

    // ---------- 日志 ----------
    struct LogPage { var surplus: Int?; var logs: [LogEntry] }

}
