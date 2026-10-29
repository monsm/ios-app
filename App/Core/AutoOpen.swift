// 靠近自动开锁 — AUTOOPEN-PLAN.md 落地 (docs)
// 门控链 F0 前台 / F1 面容双档 /  F3 距离标定 / F4 布防互锁 / F5 一次性 / F6 锁态,
// 全绿才经既有 LockService.unlock 管线下发 cmd04 (不改协议/命令构造); 任一门不过 = 静默拒绝 + 审计落盘
// (审计只记"哪道门拒了、哪把锁、何时", 永不记 ekey/skey 明文)。默认全关、fail-closed。
// 96 铁律对照: 本特性是 96 的显式用户开关例外 — 未开 = 绝不自动开锁, 开 = 全门绿才出手。
import Foundation
import SwiftUI          // 本文件尾部有 SwiftUI 视图 (标定页/面板): 缺这一行 = View/@State/@EnvironmentObject 全找不到
// 2026-10-27 审核 (AUDIT-D D-53)：删掉 `import CoreMotion` ——
// 全仓 0 处 CMMotionManager（原先大概是给"摇一摇"或姿态判断准备的，功能已删）。
// 留着一个不用的框架 import 会让编译期多一层依赖，也误导读者以为这里有运动传感器逻辑。
import LocalAuthentication
import UIKit

// ================= 存储 accessor (Store.swift 同步, kf.* 自动进备份) =================
enum AutoOpen {
    /// 主开关 (默认关): kf_autoopen
    static var on: Bool {
        get { DB.store.getBool("kf_autoopen", false) }
        set { DB.store.set("kf_autoopen", newValue) }
    }
    /// 面容档位: 0 免额外验证(靠"手机已解锁+App 前台", 默认) / 1 严格(进前台必刷): kf_autoopen_face
    /// 0 不是"没有门" —— 机主在场由 f0Foreground(sceneActive && appUnlocked && !decoyMode) 兜:
    /// 手机没解锁进不了 App, App 在后台也不放行。iOS 没有静默生物识别, 0 档因此**一次弹窗都不发起**
    /// (这正是用户要的"闸门不许弹前台黑窗")。要严格复核请把这里切到 1。
    static var faceTier: Int {
        get { DB.store.getInt("kf_autoopen_face", 0) }
        set { DB.store.set("kf_autoopen_face", newValue) }
    }
    /// rc=26 防拆事件自动关闭 24h: 到点前一律 fail-closed 拒 (kf_autoopen_suspend_until_<mac>, epoch ms)
    static func suspendUntil(_ mac: String) -> Int64 {
        guard let v = DB.store.get("kf_autoopen_suspend_until_" + mac, Int64.self) else { return 0 }
        return v
    }
    static func setSuspendUntil(_ mac: String, _ ms: Int64) {
        DB.store.set("kf_autoopen_suspend_until_" + mac, ms)
    }
    static func isSuspended(mac: String, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let t = suspendUntil(mac)
        return t > 0 && Double(t) / 1000.0 > now
    }

    // ---------- 审计: 只记哪道门拒了, 永不记密钥材料; 尾段 500 条 ----------
    struct AuditEntry: Codable {
        var at: String        // 手机侧 mm-dd HH:mm
        var mac: String
        var reason: String    // 门名 + 拒因 (哪道门 F0-F6)

    enum CodingKeys: String, CodingKey { case at, mac, reason }
    init(at: String, mac: String, reason: String) { self.at = at; self.mac = mac; self.reason = reason }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
        mac = try c.decodeIfPresent(String.self, forKey: .mac) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
    }
    /// 2026-10-29 性能：同 mac + 同 reason **10 秒内只记一次**。
    ///
    /// audit 在「已武装但某道门不过」时会被**每个 RSSI 样本**调用（站在门口每秒好几次），
    /// 而每次都是「读整份 500 条 → 插入 → 整份编码 → UserDefaults 落盘」——
    /// 不节流等于每秒几次 50KB 级的 plist 写入，还全是同一条拒因。
    private static let autoOpenAuditLast = Locked<[String: TimeInterval]>([:])

    static func audit(_ mac: String, _ reason: String) {
        let throttleKey = mac + "|" + reason
        let nowTs = Date().timeIntervalSince1970
        let skip = autoOpenAuditLast.withLock { m -> Bool in
            if let t = m[throttleKey], nowTs - t < 10 { return true }
            // 组合数有限，但仍给个上限：reason 里偶尔会带可变文案
            if m.count > 200 { m.removeAll() }
            m[throttleKey] = nowTs
            return false
        }
        if skip { return }
        var list = audits(mac)
        list.insert(AuditEntry(at: DiagTime.mmddHHmm(), mac: mac, reason: reason), at: 0)
        if list.count > 500 { list = Array(list.prefix(500)) }
        DB.store.set("kf_autoopen_audit_" + mac, list)
    }
    static func audits(_ mac: String) -> [AuditEntry] {
        DB.store.get([AuditEntry].self, "kf_autoopen_audit_" + mac) ?? []
    }
    static func lastReject(_ mac: String) -> AuditEntry? { audits(mac).first }
    /// 诊断页最近 3 条拒开记录
    static func recent(_ mac: String, _ n: Int) -> [AuditEntry] {
        Array(audits(mac).prefix(n))
    }

    // ---------- F3 标定: kf_autocal_<mac> 锁×手机对的 RSSI P95 ----------
    struct AutoCal: Codable { var rssiP95: Int; var at: Double }
    static func autocal(_ mac: String) -> AutoCal? {
        DB.store.get(AutoCal.self, "kf_autocal_" + mac)
    }
    /// 删除设备时随每锁数据族清 (DB.removeDevice 已按族清 kf_autocal_/kf_autoopen_audit_/kf_autoopen_suspend_until_ 前缀键)

    /// §3.4 标准档风险披露文案 (强制展示, 不得弱化)
    /// §3.4 风险披露 (强制展示, 不得弱化)。讲的是**现在的门** —— 默认档不再额外验面容,
    /// 而不是旧的"60 秒复用窗"; 文案描述已经不存在的门就等于对用户说谎。
    static let riskDisclosure = "默认档只认「手机已解锁 + App 在前台」: 别人拿你已解锁的手机走近门锁， 6 秒后仍可能自动开门。介意请切严格档 (每次进前台刷一次脸)。"
}

// ================= 纯逻辑: 门控判定 / 标定 / 滤波器 / 0E 双确认 (可单测, 无 UI 依赖) =================
enum AutoOpenKit {

    // ---------- F4 布防互锁: control==2 时段布防, 当前时刻在 start/end 内 → 一票否决 (跨午夜 start>end) ----------
    /// startSec/endSec 为日内秒 (SETDEFENCE 协议口径, 半秒分辨率)；仅 control==2 生效, 0/1/3 不拒。
    /// 跨午夜: start > end 时时段 = [start, 24h) ∪ [0, end)。
    /// start == end 按**全天布防**处理 (fail-closed)：这是一道"否决门"，把退化成空集的窗口读成"不布防"
    /// 等于让一次配错直接把门关掉 —— 本模块的门序里没有任何其它门会替它兜住这段时段。
    /// cal 注入保证 CI 可测 (传 UTC 日历即可确定性)；生产默认走 `WeekCal.gregorian`
    /// —— 它照抄当前时区与周序，但把历法钉成公历，用户把系统历法切成佛历/农历时 `.hour/.minute` 的
    /// 取法不会跟着换基准日 (全仓取分量都走这一个出口，理由见 WeekCal 头注)。
    static func defendActive(control: Int, startSec: Int, endSec: Int, now: Date, cal: Calendar = WeekCal.gregorian) -> Bool {
        // 2026-10-28 修复（**安全级**）：原来 `guard control == 2 else { return false }` ——
        // control==1（`DefendMode.once`「不定期布防 / 出门布防」，一直生效到手动撤防）**直接返回 false**。
        // 于是用户点了「出门布防」，界面上说「布防期间靠近门锁不会自动开门」，
        // 实际 `defendActive` 恒 false ⇒ F4 否决门形同不存在，自动开锁照样开门。
        // 正确语义：只有 control==0（撤防）不否决；1 与 2 都是布防态。
        guard control != 0 else { return false }
        // control == 1：不定期布防 = 全天生效，恒 active
        guard control == 2 else { return true }
        guard startSec != endSec else { return true }
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        // 2026-10-27 审核修复：startSec/endSec 是协议值（一天内秒数 / 2），
        // 原实现在这里拿「当前秒数」直接与它比 ⇒ 全天错位（如 22:00 存成 39600，
        // 而当前 22:00 的时刻秒数是 79200，永远比不过）。当前时刻也 /2 后才同口径。
        let secOfDay = ((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)) / 2
        if startSec < endSec {
            return secOfDay >= startSec && secOfDay < endSec
        }
        return secOfDay >= startSec || secOfDay < endSec
    }

    // ---------- F1 面容双档: 标准=60s 窗口静默复用 / 严格=进前台必刷 (LAContext 经 FaceService 注入) ----------
    /// 档位判据只有"是不是严格档"这一件事：0 = 免额外验证 (默认)，**其余任何值一律按严格档处理**。
    /// 未知档位往严的一侧靠: 台账加了第三档、或设置被旧备份带回一个陌生数时, 宁可多刷一次脸,
    /// 也不要静默掉进宽松档 —— 这是本模块唯一一处"配置漂移可能放松安全门"的形状。
    static func isStrict(_ tier: Int) -> Bool { tier != 0 }

    /// 面容门 (两档): 0 = 免额外验证 (默认) / 非 0 = 严格 (本次进前台必须刷过脸)。
    /// 0 档为什么直接放行: 机主在场由 F0 (sceneActive && appUnlocked && !decoyMode) 兜 —— 手机没解锁
    /// 进不到 App, 在后台也不放行。旧写法 0 档要求"60 秒内有一次 App 内容容", 而 iOS 没有静默生物识别
    /// (LAContext 一调就弹模态窗), 于是没主动刷过脸的人 lastFace 恒 nil ⇒ 恒拒 ⇒
    /// 用户报的"iOS 从来不会自动解锁"正是这条。默认档不能依赖任何弹窗。
    /// 严格档 = 0 窗口: 弹窗在途可放行 (下发前还有 F6 锁态门兜), 否则必须是本次进前台之后刷成的脸。
    /// 严格档面容弹窗是否仍在途中。
    /// 判据只看时间窗：发起过（startedAt != nil）+ 未超时（< 30s）+ 这次还没成功（lastFace 早于 startedAt）。
    /// ⚠ 不能用 `lastFace == 发起时的快照` 判 —— 失败/取消时 lastFace 与快照都是 nil，`nil == nil` 恒真。
    static func facePromptInFlight(startedAt: Date?, lastFace: Date?, now: Date) -> Bool {
        guard let s = startedAt else { return false }
        if now.timeIntervalSince(s) > 30 { return false }       // 弹窗超时未回 = 视为未在途
        if let lf = lastFace, lf >= s { return false }          // 这之后成功过 = 已不在途
        return true
    }
    static func faceFresh(tier: Int, lastFace: Date?, now: Date, pendingPrompt: Bool, strictSince: Date? = nil) -> Bool {
        if !isStrict(tier) { return true }
        if pendingPrompt { return true }
        guard let lf = lastFace, let since = strictSince else { return false }
        return lf >= since
    }

    // ---------- F3 距离标定: P95 取法 (线性插值) ----------
    static func p95(_ samples: [Int]) -> Int? {
        guard samples.count >= 5 else { return nil }
        let sorted = samples.sorted()
        let rank = Double(sorted.count - 1) * 0.95
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        if lo == hi { return sorted[lo] }
        let v = Double(sorted[lo]) + (Double(sorted[hi]) - Double(sorted[lo])) * frac
        return Int(v.rounded())
    }
    /// 标定基准: 做过按锁标定 (F3) 用它的 P95; 没标定退回固定线 -40 —— 与安卓 AutoOpenKit.BASE 同值。
    /// 旧写法未标定返回 nil ⇒ feedRssi 直接 return ⇒ armed 永不置位 ⇒ 自动开锁对没标定过的用户**永不触发**。
    /// 用户口径是"信号优于 -40 就开", 标定从"必需"降级为"可选精修" (标定过仍按你的实际距离算, 更贴这把锁)。
    static let fallbackBase = -40
    static func rssiBase(mac: String) -> Int {
        AutoOpen.autocal(mac)?.rssiP95 ?? fallbackBase
    }
    /// F3 回差阈值在**线性功率域**换算 — dBm 是对数单位, 直接对负数乘系数会把方向搞反:
    /// 旧式 0.7×base / 0.5×base 在 base=-60 时得 武装线 -42 / 解除线 -30, 解除线反而比武装线更强
    /// → 无回差且逐样本翻转, 标定距离 (-60) 上永不武装。方案 §F3 原意: 基准即武装线, 功率掉回 0.5× 才解除。
    static func armThreshold(base: Int) -> Int { base }
    static func disarmThreshold(base: Int) -> Int { Int((Double(base) + 10 * log10(0.5)).rounded()) }

    /// RSSI 回差滤波 (纯函数): 已武装需掉到解除线以下才解除; 未武装需越过武装线才武装。
    /// 基准 P95 = -60 时：武装线 = -60 (回到标定点即武装)，解除线 = -60 + 10·log10(0.5) ≈ -63
    /// (信号功率掉到标定的一半、即比武装线再弱 3 dB 才解除) ⇒ 回差带是 [-63, -60]，
    /// 门口来回走不会逐样本翻转。**上面那段 0.7×/0.5× 的说法是修好之前的旧公式**：
    /// dBm 是对数单位，直接对负数乘系数会把方向搞反 (算出 -42 / -30 这两条比基准**更强**的线，
    /// 结果在标定距离上永不武装)。
    static func rssiSample(prevArmed: Bool, rssi: Int, base: Int) -> Bool {
        let arm = armThreshold(base: base)
        let disarm = disarmThreshold(base: base)
        if prevArmed {
            return rssi > disarm
        }
        return rssi >= arm
    }

    // ---------- F5 冷却: 每次接近事件只发一次 04, 成功后 6s 冷却 ----------
    // 60s 太保守 (人走开再回来要等一分钟), 用户口径 6 秒。双开不靠这个数兜: 靠 F5 一次性闩锁
    // (eventFired, 信号掉回解除线才放开) + 回差带 (-43..-40) + 04 超时绝不重发。
    static let cooldownSeconds: TimeInterval = 6
    static func coolReady(lastDispatch: TimeInterval, now: TimeInterval) -> Bool {
        lastDispatch == 0 || now - lastDispatch > cooldownSeconds
    }

    // ---------- 0E 双确认 (rc=3 自愈校时): 30s < |偏差| < 24h 才写; ≥24h 仅 NTP 对表一致时放宽到 48h ----------
    /// phoneProto = 手机协议秒, lockProto = 锁协议秒 (03 #04), ntpConfirmed = 有网且 NTP 对表偏差 < 5min。
    /// 防"把错手机时间写进锁 → 全凭证时间窗集体错乱"自伤 DoS。
    static func dualTimeSync(phoneProto: Int64, lockProto: Int64, ntpConfirmed: Bool) -> Bool {
        let dev = abs(phoneProto - lockProto)
        if dev < 30 { return false }           // 偏差在容差内, 无需写 (rc=3 走既有刷令牌路径)
        if dev < 24 * 3600 { return true }      // 30s < 偏差 < 24h → 自动写 (自愈)
        if ntpConfirmed && dev < 48 * 3600 { return true }
        return false
    }

    // ---------- F1 面容成功时刻记账 (进程内语义: 重启即失效 = fail-closed) ----------
    // 原生形态: 状态**活在锁里面** —— 不是"一个 static var + 一把锁", 那样 Swift 6 仍然看得见
    // 那个全局可变变量。把值交给 Locked 持有, 可变性就只存在于临界区内部。
    private static let lastFaceLock = Locked<Date?>(nil)
    static func noteFaceSuccess() { lastFaceLock.withLock { $0 = Date() } }
    static func lastFace() -> Date? { lastFaceLock.withLock { $0 } }
}

// ================= 门控矩阵: 全绿才允许下发 04 =================
struct AutoOpenGate {
    var f0Foreground: Bool        // App 前台且不在伪装模式 (sceneActive && !decoyMode)
    var faceTier: Int             // 0 标准 / 1 严格
    var lastFace: Date?          // 最近一次面容成功时刻 (nil = 从未)
    var facePendingPrompt: Bool  // 严格档弹窗在途
    var facePromptStartedAt: Date? = nil   // 严格档 0 窗口基准: 本次进前台发起弹窗的时刻
    var now: Date
    var defendControl: Int       // DB.defend(mac)?.control ?? 0 (无布防 = 0)
    var defendStartSec: Int
    var defendEndSec: Int
    var rssiArmed: Bool          // F3 滤波当前态
    var coolReady: Bool          // F5 冷却: 上一次下发距今 > cooldownSeconds(=6s)。曾误写 60s —— 60 是热链路上限, 不是冷却
    var lockReady: Bool          // F6: 非 busy(25) 且非防拆(26)

    enum Reject: Equatable {
        case off                 // 主开关未开
        case suspended           // rc=26 自动挂起到点前
        case f0                  // 非前台/App 未解锁
        case f1face             // 面容档不满足 (无面容/过期/严格未刷)
        case f4defend          // 布防时段一票否决
        case f3rssi            // 信号未武装
        case f5cool            // 6s 冷却中
        case f6busy            // 锁忙 / 防拆 (锁态门)
        case none
    }

    /// 返回拒因; .none = 全绿可下发。顺序即门序: 开关/挂起 → F0 → F1 → F4 → F3 → F5 → F6。
    func rejectReason(
        autoOpenOn: Bool,
        suspended: Bool,
        faceAvailable: Bool
    ) -> Reject {
        guard autoOpenOn else { return .off }
        guard !suspended else { return .suspended }
        guard f0Foreground else { return .f0 }
        // 生物识别可用性只在**严格档**才是硬条件: 默认档不发起任何面容验证,
        // 没有 Face ID / 用户关了生物识别的机器上也该能自动开 (机主在场由 F0 兜)。
        // 上一版把这条放在档位判断之前, 等于 tier 0 也被生物识别可用性否决 —— 死门换个位置留着。
        if AutoOpenKit.isStrict(faceTier) {
            guard faceAvailable else { return .f1face }
        }
        guard AutoOpenKit.faceFresh(tier: faceTier, lastFace: lastFace, now: now,
                                    pendingPrompt: facePendingPrompt, strictSince: facePromptStartedAt)
        else { return .f1face }
        guard !AutoOpenKit.defendActive(control: defendControl, startSec: defendStartSec, endSec: defendEndSec, now: now)
        else { return .f4defend }
        // F3 不再要求"必须做过标定": 未标定走 AutoOpenKit.fallbackBase (-40, 与安卓 AutoOpenKit.BASE 同值)。
        // 旧写法把"没标定"当一票否决 ⇒ 新用户/新锁永远开不了, 而标定页要站着等 30 秒, 多数人不会做。
        // 标定降级为可选精修 (做过就按你这把锁的实际信号定线)。calibrated 仍留着给界面如实显示。
        guard rssiArmed else { return .f3rssi }
        guard coolReady else { return .f5cool }
        guard lockReady else { return .f6busy }
        return .none
    }

    /// 人话拒因 (审计文案: 门名 + 时刻 + 哪道门)
    static func rejectText(_ r: Reject) -> String {
        switch r {
        case .off: return "主开关未开"
        case .suspended: return "rc=26 防拆挂起， 自动开锁 24h 内禁用"
        case .f0: return "F0 非前台/App 未解锁"
        case .f1face: return "F1 面容未确认 (严格档要求本次进前台刷过脸)"
        case .f4defend: return "F4 布防时段内， 一票否决"
        case .f3rssi: return "F3 信号未达武装线"
        case .f5cool: return "F5 冷却中 (6 秒)"
        case .f6busy: return "F6 锁态未知或忙 (rc=25/无 03 回显)"
        case .none: return "可开"
        }
    }
}

// ================= 面容抽象 (F1, LAContext 可 mock) =================
protocol FaceService {
    var biometricAvailable: Bool { get }
    /// 严格档: 进前台必弹 (LAContext.evaluatePolicy 系统弹窗), 成功即记 lastFace
    func promptFace()
}

struct SystemFaceService: FaceService {
    /// FaceService 协议要求的成员 (旧实现漏写 → 类型检查不过)
    var biometricAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }
    func promptFace() {
        Task { @MainActor in
            var err: NSError?
            let ctx = LAContext()
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err),
                  err?.code != LAError.biometryNotAvailable.rawValue else { return }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "确认是你， 才允许靠近自动开门") { ok, _ in
                if ok { AutoOpenKit.noteFaceSuccess() }
            }
        }
    }
}


// ================= 控制器: 状态机 + 全门绿才走既有 unlock 管线下发 04 =================
@MainActor
final class AutoOpenController {
    static let shared = AutoOpenController()
    let face: FaceService
    private var armed = false
    private var armedMac = ""
    private var lastDispatch: [String: TimeInterval] = [:]   // F5: 按锁记上次下发时刻
    private var eventFired: Set<String> = []                 // F5: 本次接近事件已发过 04 (掉回解除线才放开)
    private var promptStartedAt: Date?                       // F1 严格档: 本次进前台是否已发起弹窗
    /// 2026-10-27 审核修复 (AUDIT-D D-49)：上一次 scenePhase 是否真的进过后台。
    /// `.inactive`（来电横幅、下拉控制中心、任务切换器预览）也会触发 `.active`，
    /// 而每次 onForeground 都重置 promptStartedAt 会把「本次进前台必刷脸」的窗口
    /// 无限延长 —— 用户反复进出，面容门就一直处于「刚发起」状态。
    private var wasInBackground = true   // 冷启动视为「从后台来」
    private var inFlight = false

    init(face: FaceService = SystemFaceService()) {
        self.face = face
    }

    // ---------- F0/F1: 进前台 (RootView scenePhase .active) ----------
    func onForeground(mac: String) {
        guard AutoOpen.on, !mac.isEmpty else { return }
        guard !AutoOpen.isSuspended(mac: mac) else {
            AutoOpen.audit(mac, "拒开 rc=26 防拆挂起中， 面容不刷新")
            return   // rc=26 挂起期不弹面容, 门保持不过
        }
        eventFired.removeAll()          // 新的一次"进前台 + 接近"事件, 放开一次性闩锁
        if AutoOpenKit.isStrict(AutoOpen.faceTier) {
            // 2026-10-27 (D-49)：**只在真的从后台回来时**才重置弹窗时刻。
            // `.inactive → .active`（下拉控制中心、来电横幅）不算 —— 否则反复进出会把
            // "本次进前台必刷脸"的窗口无限延长，面容门形同虚设。
            if wasInBackground {
                promptStartedAt = Date()
                wasInBackground = false
                face.promptFace()
            }
        }
    }
    func onBackground() {
        // 2026-10-14: 清理与"停传感器"不能挂在开关值上 —— 运行中把开关关掉时 AutoOpen.on 已为 false,
                // 退后台必须收全部传感器与会话状态
        // 退后台: 清武装态 (F0 同时失效, 双保险) + 清一次性/面容在途位
        wasInBackground = true   // 2026-10-27 (D-49)：下次 .active 才算真的从后台回来
        armed = false
        eventFired.removeAll()
        promptStartedAt = nil
        // 旧实现从不调 stop(): 回前台 start() 因 mgr != nil 幂等早退, 而传感器流已被系统停止
        // → met() 用陈旧 stillSince 恒判"已停留" (fail-open)
    }

    // ---------- F3 喂入: RSSI 事件 (LinkSenseKit saveRssi 后调) ----------
    func feedRssi(mac: String, rssi: Int) {
        guard AutoOpen.on else { return }
        if mac != armedMac { armedMac = mac; armed = false; eventFired.remove(mac) }
        // rssiBase 现在恒有值 (未标定退回 -40), 所以不再有"没标定就 return"这条 —— 那正是
        // 旧写法让未标定用户 armed 永远置不起来、自动开锁一次都不触发的那道死门。
        let base = AutoOpenKit.rssiBase(mac: mac)
        armed = AutoOpenKit.rssiSample(prevArmed: armed, rssi: rssi, base: base)
        // 2026-10-27 审核修复：闩锁解除原先跟着 `armed` 走，而 `armed` 在开锁成功后被置 false
        // （下方 case 0），于是信号落进回差带 (-43..-40) 就会执行本行把闩锁放开 —— 
        // 于是退半步再进一步就能再开一次。改用独立的「走远」判据：信号掉到解除线**以下再 3dB**
        // （即真正离开门口，不只是回差带内抖动）才放开闩锁。armed 复位不再影响它。
        let farAway = rssi < AutoOpenKit.disarmThreshold(base: base) - 3
        if farAway { eventFired.remove(mac) }
        // 2026-10-18 性能分级（用户口径："只在箭头界面追求极致，退出就完全切断"）:
        // 原本这里按 `FindArrowPower.intensive` 分档 —— 那个开关属于「精确查找箭头界面」，
        // 而该界面从未接到任何入口上，所以 intensive 恒为 false，**这一行从未执行过**。
        //
        // 现改为无条件事件驱动：信号武装的那一拍立即判定，不等 2s tick。
        // 为什么这样安全：`attempt()` 本身就是完整门判定（F0 前台+已解锁 / F1 面容档 /
        // F5 每个接近事件只发一次 / 伪装会话拒 / 演示模式拒 / 冷却闸），
        // 早判定只是把「同样的判定」提前到广播到达那一刻，不新增任何放行路径。
        // 省电也没变差：真正耗电的是持续开着扫描，而这里只是收到广播后多做一次纯计算。
        if armed { tickDwell(mac: mac) }
    }

    // ---------- 全门判定 + 下发 (每个接近事件只发一次: F5) ----------
    /// 每 2 秒由 LinkSense 驱动一次: 武装态下检查信号是否已达标, 达标则尝试下发。
    /// 静置判定已删 —— 信号达标即唯一条件 (与 F3 门控口径一致)。
    func tickDwell(mac: String) {
        guard AutoOpen.on, armed else { return }
        attempt(mac: mac)
    }

    func attempt(mac: String) {
        guard AutoOpen.on, !inFlight else { return }
        guard let app = AppState.hostRef else { return }
        guard app.currentMac == mac, !mac.isEmpty else { return }
        guard app.unlockState == .idle else { return }
        // 2026-10-13 对抗式排查: 补 390 伪装会话红线 (两道, 这里是指令入口, 下面 F0 是门判据)。
        // 原实现在**指令入口**没有 decoy 判断, F0 只看 `appUnlocked`; 而伪装口令进来的会话
        // **也是** appUnlocked==true (空壳界面 + 锁已解开)。于是被胁迫场景下:
        //   ①机主在门口, AutoOpen 已武装且 60s 内刚刷过脸 (标准档);
        //   ②胁迫者让机主点「立即锁定」(只置 appUnlocked=false, 不清 armed/lastFace);
        //   ③输入伪装口令 → decoyMode=true, appUnlocked=true;
        //   ④LinkSense 的 2s tick 继续驱动 tickDwell → F0 查 appUnlocked(true) ✓ F1 脸在窗内 ✓ → 下发 04。
        // 390 行原话: "伪装口令进来的会话只渲染空壳" —— 空壳后面门被打开, 就是这个 bug。
        // 手动锁定也应清零武装/面容时刻 （原 SecurityCenterView 那条，该页已删）, 这里先保证自动链在伪装态一律拒。
        guard !app.decoyMode else {
            AutoOpen.audit(mac, "拒开： 伪装会话期间禁止自动下发 04")
            return
        }
        if eventFired.contains(mac) { return }   // F5 一次性: 每个接近事件只发一次 04

        let ctx = makeContext(mac: mac, app: app)
        let rej = ctx.rejectReason(
            autoOpenOn: true,
            suspended: AutoOpen.isSuspended(mac: mac),
            faceAvailable: face.biometricAvailable
        )
        switch rej {
        case .none:
            inFlight = true
            Task { await self.dispatch(mac: mac, app: app) }
        default:
            let door = Self.doorName(mac: mac)
            AutoOpen.audit(mac, "拒开 " + AutoOpenGate.rejectText(rej) + " · " + door)
        }
    }

    private func makeContext(mac: String, app: AppState) -> AutoOpenGate {
        let d = DB.defend(mac)
        let lastAt = lastDispatch[mac] ?? 0
        let snap = app.snapshot
        let coolReady = AutoOpenKit.coolReady(lastDispatch: lastAt, now: Date().timeIntervalSince1970)
        return AutoOpenGate(
            f0Foreground: LinkSense.shared.sceneActive && !app.decoyMode,
            faceTier: AutoOpen.faceTier,
            lastFace: AutoOpenKit.lastFace(),
            // 严格档在途位: 弹窗已发起且面容时刻尚未刷新 = 正在确认 (旧实现恒 false → 在途分支是死代码)
            // 2026-10-27 审核修复：原判据是 `promptStartedAt != nil && lastFace() == faceAtPrompt`，
            // 而弹窗失败/取消时 noteFaceSuccess() 不调用 ⇒ lastFace() 与 faceAtPrompt 都是 nil，
            // `nil == nil` 恒真 ⇒ 弹窗"在途"状态在本会话内永久为真 ⇒ faceFresh 永远放行。
            // 现改为纯时间窗判定：发起过弹窗、距发起 < 30s、且这次还没成功。
            facePendingPrompt: AutoOpenKit.facePromptInFlight(startedAt: promptStartedAt, lastFace: AutoOpenKit.lastFace(), now: Date()),
            facePromptStartedAt: promptStartedAt,
            now: Date(),
            // F4: 用户配了布防 (control=2) 就照常一票否决 + 落审计; 但"本机没存过布防记录"不能再读成
            // "全天布防" —— 那等于从没进过布防页的人被永久否决。按用户口径改 ?? 0 (没配 = 没布防)。
            // 这不是拆门: 一旦布防设置存在, control=2 仍严格生效 (defendActive 的时段判定一字未改)。
            defendControl: d?.control ?? 0,
            defendStartSec: d?.startSec ?? 0,
            defendEndSec: d?.endSec ?? 0,
            rssiArmed: armed,
            // calibrated 现在如实表示"做过按锁标定" (不再是能不能开的硬条件 —— 未标定走 fallbackBase)
            coolReady: coolReady,
            // F6 锁态门 fail-closed: StatusSnapshotData.rc 默认 0 = "成功", 无快照时旧写法会误判锁态绿
            lockReady: snap != nil && snap?.rc != 25 && snap?.rc != 26
        )
    }

    private func dispatch(mac: String, app: AppState) async {
        defer { inFlight = false }
        do {
            try await app.lock.ensureConnected(mac: mac)
            // 2026-10-27 审核修复：闩锁与冷却必须在**下发之前**落，否则异常/超时路径
            // 两者都不置位，而 lastDispatch 已经写了 —— 6 秒冷却一过就再发一帧，
            // 站在门口链路抖动时会每 6 秒重试一次真实开门（手动路径明确禁止这么做）。
            eventFired.insert(mac)
            lastDispatch[mac] = Date().timeIntervalSince1970
            let rc = try await app.lock.unlock(mac: mac)
            switch rc {
            case 0:
                // 成功: 冷却起算 (lastDispatch 已置)。复位 armed 只影响回差滤波的起点，
                // **不再解除一次性闩锁** —— 闩锁现在由 feedRssi 的 farAway（走远）判据独立管理。
                armed = false
                // 先刷新锁态快照再报成功: 双验模式 (verifyMode==1) 下 rc=0 只是第一道过了,
                // 直接喊"自动开锁成功"就是谎报 —— 与手动档 settleUnlockSuccess 同一口径 (2026-10-15 走查)。
                _ = try? await app.lock.getStatus()   // 顺带刷新 F6 锁态快照
                // 来源标注 (用户 2026-10-17): 自动链不经过 AppState.runUnlock, 那句"开锁成功"
                // 在自动档下从来没出现过 —— 门开了却没人说是谁开的。这里点明"自动"。
                if app.status?.verifyMode == 1 {
                    app.showToast("自动： 第一道已通过 — 请再用指纹或密码完成第二道")
                } else {
                    app.showToast("自动开锁成功 — \(app.displayName)")
                }
            case 3:
                // 0E 双确认自愈 (rc=3 命令过期): 30s < |偏差| < 24h 才写, ≥24h 只提示不写
                await selfHealTime(mac: mac)
            case 5:
                // G3 times 语义未确证: 只提示, 不自动重签 (方案 §3.3 前置实验未过前保持保守)
                AutoOpen.audit(mac, "rc=5 次数用完 — 提示联系主人换钥， 不自动重签")
                app.showToast("凭证次数用完 (rc=5) — 请联系主人换钥， 不自动重签")
            case 25:
                AutoOpen.audit(mac, "rc=25 锁正忙， 拒绝自动开锁")
            case 26:
                // 防拆: 拒 + 自动关自动开锁 24h (记审计 + 挂起键)
                AutoOpen.setSuspendUntil(mac, Int64(Date().timeIntervalSince1970 * 1000) + 24 * 3600 * 1000)
                AutoOpen.audit(mac, "rc=26 防拆事件 → 自动关自动开锁 24h")
                app.showToast("检测到防拆事件， 自动开锁已暂停 24 小时")
            default:
                AutoOpen.audit(mac, "rc=\(rc) " + StatusParser.rcFriendly(rc))
            }
        } catch {
            // 失败也要复位武装: 否则 armed 一直 true，RSSI 稍动就再触发一轮判定
            armed = false
            AutoOpen.audit(mac, "下发异常 " + error.localizedDescription)
        }
    }

    /// 0E 双确认自愈校时: 读锁钟算偏差, 按 dualTimeSync 判定; ≥24h 只提示不写 (防自伤 DoS)
    private func selfHealTime(mac: String) async {
        guard let app = AppState.hostRef else { return }
        guard let lockSec = try? await app.lock.readLockTime() else {
            AutoOpen.audit(mac, "rc=3 读锁钟失败， 未自动校时")
            return
        }
        let phone = ZKProtocol.nowProtoSeconds()
        let write = AutoOpenKit.dualTimeSync(phoneProto: phone, lockProto: lockSec, ntpConfirmed: false)
        if write {
            do {
                try await app.lock.syncTime()
                AutoOpen.audit(mac, "rc=3 → 偏差 \(abs(phone - lockSec))s 在 30s~24h 窗内， 已自动校时 (0E 双确认)")
            } catch {
                AutoOpen.audit(mac, "rc=3 → 自动校时失败 " + error.localizedDescription)
            }
        } else {
            let dev = Int(abs(phone - lockSec))
            AutoOpen.audit(mac, "rc=3 → 偏差 \(dev)s 超出双确认窗， 只提示不写 (0E 双确认)")
            app.showToast("锁钟偏差约 \(dev / 3600) 小时 — 为避免误写仅提示， 请手动校准门锁时间")
        }
    }

    static func doorName(mac: String) -> String {
        DB.keychain(mac)?.name ?? String(mac.prefix(6))
    }
}


// ================= 设置 Section (§4 原文 + §3.4 强制风险披露) =================
struct AutoOpenSection: View {
    var mac: String
    var body: some View {
        Section {
            VariantToggle("走近自动开门", isOn: Binding(
                get: { AutoOpen.on },
                set: { AutoOpen.on = $0 }))
            if AutoOpen.on {
                Picker("面容确认", selection: Binding(
                    get: { AutoOpen.faceTier },
                    set: { AutoOpen.faceTier = $0 })) {
                    Text("免额外验证 (默认)").tag(0)
                    Text("严格 (每次必刷)").tag(1)
                }
                .pickerStyle(.menu)
                Text(AutoOpen.riskDisclosure)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                // 门是 fail-closed 的, 拒开又是静默的 —— 用户在门口等半天只知道"没开"。
                // 拒因**早就落进审计**了 (AutoOpen.audit / lastReject), 这里只是把它显示出来,
                // 既不新增门也不放宽门: 看得见原因才知道下一步该做什么 (标定 / 布防时段 / 刷脸)。
                if let r = AutoOpen.lastReject(mac) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("上一次没自动开：\(r.reason)")
                            .vkFont(.footnote)
                        Text(r.at)
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("靠近自动开锁")
        } footer: {
            Text("仅 App 在前台且门不在布防时段生效; 布防时段与防拆事件自动关闭自动开锁。睡觉场景请确认布防时段覆盖夜间。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
