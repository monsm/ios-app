// 应用锁安全族消费者 (389–395/398) — 这些键位原先只在设置页写与显示, 验证路径一个都不读,
// 于是"失败冷却 / 伪装码 / 胁迫码 / 失败留痕 / 锁定时机 / 免验窗口 / 救援码"全是死开关。
// 本文件是唯一消费者: AppLockView 与 RootView 的 scenePhase 都走这里, 口径集中便于审计。
// 原则: 任何配置缺失都按**最严格**解释 (fail-closed), 不因为读不到值就放行。
//
// 同一个道理的第二批 (第一百批): 文件末尾的 LockAction + SecurityPolicy 是 376/377/383/296 那五枚开关的
// 唯一判据口 —— 它们此前只改自己的标签, 全仓没有一个消费者, 于是"访客通道 / 分享遮半 / sudo 口令 /
// 只读安全模式"四句承诺一句都没兑现。界面与调用点一律读 SecurityPolicy, 不许再各处 DB.store.getBool。
import Foundation

@MainActor
enum LockGuard {
    // 393 的锁定时刻与 394/398 的解锁时刻没有既有键, 这里补两个 (同 kf. 前缀族, 与 Miniprogram 互通键无冲突)
    private static let bgDeadline = "kf_slock_bgdeadline"
    private static let unlockedAt = "kf_sses_unlockadat"
    private static let coolBaseSec = 30.0
    private static let coolCapSec = 600.0
    private static let traceCap = 50

    // ---------- 389 失败递增冷却 ----------
    /// 剩余冷却秒数; 0 = 可以接受下一次输入
    static func cooldownLeft(now: Date = Date()) -> Double {
        let until = DB.store.get(Double.self, SecKey.lockUntil) ?? 0
        return max(0, until - now.timeIntervalSince1970)
    }
    /// 冷却档位是否启用 (关时不锁, 但仍累计连败数供 392/877 用)
    static var cooldownEnabled: Bool { DB.store.getBool(SecKey.lockCoolOn) }

    /// 一次验证失败: 累加连败 → 按 30s·2^n 上取冷却 (封顶 10 分钟) → 392 留痕
    /// 392: `how` 是"方式" (密码/面容…) —— 原句要的留痕是「时间+方式+连败次数」,
    /// 原先只有密码一条路进得来, 留痕里读不出方式。默认"密码"不动既有两条调用点。
    static func registerFailure(now: Date = Date(), how: String = "密码") {
        let n = DB.store.getInt(SecKey.lockStreak) + 1
        DB.store.set(SecKey.lockStreak, n)
        if cooldownEnabled {
            let secs = min(coolCapSec, coolBaseSec * pow(2.0, Double(min(n, 6)) - 1))
            DB.store.set(SecKey.lockUntil, now.timeIntervalSince1970 + secs)
            appendTrace("应用锁\(how)验证失败 第\(n)次, 冷却 \(Int(secs)) 秒")
        } else {
            appendTrace("应用锁\(how)验证失败 第\(n)次 (冷却开关未开)")
        }
    }
    static func resetStreak() {
        DB.store.remove(SecKey.lockStreak)
        DB.store.remove(SecKey.lockUntil)
    }

    // ---------- 390 伪装码 / 391 胁迫码 / 395 救援码 ----------
    /// 口令类键位为空时一律不匹配 (否则空输入会被当成"伪装码命中")
    private static func matches(_ key: String, _ input: String) -> Bool {
        let saved = DB.store.getString(key)
        return !saved.isEmpty && !input.isEmpty && saved == input
    }
    static func isDecoy(_ input: String) -> Bool {
        DB.store.getBool(SecKey.decoyOn) && matches(SecKey.decoyCode, input)
    }
    static func isDuress(_ input: String) -> Bool {
        DB.store.getBool(SecKey.duressOn) && matches(SecKey.duressCodeRaw, input)
    }
    /// 391 胁迫放行: 只打位与留痕, 界面表现与正常解锁完全一致 (不给翻供者任何可见破绽)
    static func markDuress(now: Date = Date()) {
        DB.store.set(SecKey.sessionDuress, true)
        DB.store.set(SecKey.duressAt, now.timeIntervalSince1970)
        AuditLog().append(.admin, "应用锁放行", target: "胁迫会话已打标", duress: true)
    }
    /// 395 一次性救援码: 命中即消费 (清空), 用第二次不成立
    static func consumeRescue(_ input: String, now: Date = Date()) -> Bool {
        // 395: 未点「已手抄」的码不生效 — 卡面写着要手抄, 没确认手抄就还能被使用等于承诺落空
        guard DB.store.getBool(SecKey.rescueOn), DB.store.getBool(SecKey.rescueSeen),
              matches(SecKey.rescueCode, input) else { return false }
        DB.store.remove(SecKey.rescueCode)
        DB.store.remove(SecKey.rescueSeen)
        appendTrace("使用一次性救援码进入, 该码已作废")
        AuditLog().append(.admin, "救援码进入", target: "一次性码已消费清空")
        _ = now
        return true
    }

    // ---------- 392 失败留痕 (只存事件, 绝不存输入) ----------
    static func appendTrace(_ s: String, now: Date = Date()) {
        guard DB.store.getBool(SecKey.traceOn) else { return }
        var list = DB.store.get([String].self, SecKey.traceEvents) ?? []
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        list.insert(f.string(from: now) + " " + s, at: 0)
        if list.count > traceCap { list = Array(list.prefix(traceCap)) }
        DB.store.set(SecKey.traceEvents, list)
    }
    static func traces() -> [String] { DB.store.get([String].self, SecKey.traceEvents) ?? [] }
    /// 392: 留痕键位的清写口 (与 traces() 同属本文件, 界面不再自己摸 key)
    static func clearTraces() { DB.store.set(SecKey.traceEvents, [String]()) }

    // ---------- 393 退后台锁定时机 / 394 短时免验 ----------
    /// "" 或未知档位 = 退后台即锁 (最严); m1/m5/next 记锁定到期时刻
    static func onBackground(now: Date = Date()) {
        let t = now.timeIntervalSince1970
        let deadline: Double
        switch DB.store.getString(SecKey.lockTiming, "") {
        case "m1": deadline = t + 60
        case "m5": deadline = t + 300
        case "next":
            var c = WeekCal.gregorian.dateComponents([.year, .month, .day], from: now)
            c.day = (c.day ?? 1) + 1
            c.hour = 0; c.minute = 0; c.second = 0
            deadline = WeekCal.gregorian.date(from: c)?.timeIntervalSince1970 ?? t
        default: deadline = t
        }
        DB.store.set(bgDeadline, deadline)
    }
    /// 回前台是否必须重新验证
    static func shouldLockOnForeground(now: Date = Date()) -> Bool {
        guard let d = DB.store.get(Double.self, bgDeadline), d > 0 else { return false }
        DB.store.remove(bgDeadline)
        if now.timeIntervalSince1970 < d { return false }
        if DB.store.getBool(SecKey.graceOn) {
            let g = max(0, Double(DB.store.getInt(SecKey.graceSec)))
            let last = DB.store.get(Double.self, unlockedAt) ?? 0
            if now.timeIntervalSince1970 - last <= g { return false }
        }
        return true
    }

    // ---------- 398 会话方式记录 (成功进入时统一写) ----------
    static func noteSession(how: String, now: Date = Date()) {
        DB.store.set(SecKey.sessionAt, now.timeIntervalSince1970)
        DB.store.set(SecKey.sessionHow, how)
        DB.store.set(unlockedAt, now.timeIntervalSince1970)
    }
    /// 真密码/生物识别进入时清掉胁迫打标, 免得一次胁迫会话污染整个进程
    static func clearDuressMark() { DB.store.set(SecKey.sessionDuress, false) }
    // 2026-10-13 run 63: 原来它是 @MainActor 隔离的 (LockGuard 整个是 @MainActor), 而
    // Store.saveLedger (非隔离) 在写审计链时要读它 ⇒ "main actor-isolated static property
    // 'inDuressSession' can not be referenced from a nonisolated context"。
    // 它只是一次 DB.store 纯读 (DB.store 非隔离) ⇒ 按本文件既有口径 (见下方 LockAction 那段
    // "刻意不加 @MainActor") 标 nonisolated。
    nonisolated static var inDuressSession: Bool { DB.store.getBool(SecKey.sessionDuress) }
}

// ---------- 安全中心五枚开关的唯一判据口 (376/377/383/296) ----------
/// 危险动作族: 296 只读模式要停下来的那一族, 也是 383 要追问口令的那一族的父集。
/// 界面与调用点报的是同一个枚举, 不再各处写 `if DB.store.getBool(SecKey.xxx)` ——
/// 这五枚开关此前失效的成因正是"读点散在设置页的文案里": 标签跟着开关变, 行为一行没动。
enum LockAction {
    case unlock             // 圆盘/手势/自动开锁的开锁动作
    case writeCredential    // 凭证增删改 (口令/指纹/临时码)
    case provision          // 网关配网
    case dfu                // 固件升级
    case destroy            // 销毁/清空回收站/离职清除这类不可逆动作
    case importExport       // 备份导入与导出分享

    /// 只读安全模式 (296) 下全族都停: 开关的原话是"只读查看日志"。
    /// **设置页自身的开关不在这一族里** —— 把写类动作一把全锁死会把关掉只读模式的路也一起锁死,
    /// 那就不是应急位而是自锁。
    var blockedInReadOnly: Bool { true }

    /// 被拦下时对用户说的那句实话: 点名是哪枚开关拦的, 不写成含糊的"操作失败"
    var denial: String {
        switch self {
        case .unlock: return "只读安全模式已开: 开锁已停用, 要开门请先关掉这枚开关"   // 296 只读安全模式已开
        case .writeCredential: return "只读安全模式已开: 凭证写入已停用"   // 296 只读安全模式已开
        case .provision: return "只读安全模式已开: 网关配网已停用"   // 296 只读安全模式已开
        case .dfu: return "只读安全模式已开: 固件升级已停用"   // 296 只读安全模式已开
        case .destroy: return "只读安全模式已开: 销毁与清空已停用"   // 296 只读安全模式已开
        case .importExport: return "只读安全模式已开: 导入导出已停用"   // 296 只读安全模式已开
        }
    }
}

/// 383 毁灭动作的入场券。`init` 是 fileprivate ⇒ 本文件之外**造不出**它,
/// 只能由 SecurityPolicy.sudoTicket(from:) 当场验过应用锁口令之后发一张。
/// 为什么不用一个 Bool 标志: 布尔能被任何调用方随手写成 true, 而"要不要重输口令"这件事
/// 一旦可以由调用方自述, 383 就又是一枚只改标签的开关。
struct SudoTicket {
    let issuedAt: Double
    fileprivate init(issuedAt: Double) { self.issuedAt = issuedAt }
}

/// 安全中心五枚开关的唯一判据口。刻意**不加 @MainActor**:
/// 判据口要能被界面、逻辑层 (DestroyKit) 与静态上下文一律读到,
/// 一旦隔离到某个 actor, 每个调用点就得为边界绕路, 绕着绕着就又写回 `DB.store.getBool` 去了。
/// 失败留痕 (389/392 那条通道是 @MainActor 的 LockGuard) 因此放在界面侧那一步做。
enum SecurityPolicy {
    // ---------- 唯一读点: 界面与调用点一律从这里取, 不许再摸 DB.store ----------
    /// 377 访客通道: 真开时主 TabView 只暴露 设备/记录, 进 凭证/设置 要先过口令
    static var guestActive: Bool { DB.store.getBool(SecKey.guestOn, false) }
    /// 377 访客视图筛敏感成员 (本机没有成员敏感标记位, 见 SecurityCenterView 那行的实话文案)
    static var hideSensitiveInGuest: Bool { DB.store.getBool(SecKey.sensitiveOnly, false) }
    /// 383 毁灭操作需重输应用锁口令
    static var sudoRequired: Bool { DB.store.getBool(SecKey.sudoOn, true) }
    /// 296 只读安全模式
    static var readOnly: Bool { DB.store.getBool(SecKey.safeModeOn, false) }
    /// 376 口述卡与导出预览默认遮码值下半段
    static var shareHalf: Bool { DB.store.getBool(SecKey.shareHalfOn, true) }

    // ---------- 296: 动作闸 ----------
    /// 这个动作现在准不准做。只读模式开着 ⇒ 全族拦下。
    static func allows(_ action: LockAction) -> Bool { !(readOnly && action.blockedInReadOnly) }
    /// 拦下时该说的那句话
    static func denialMessage(_ action: LockAction) -> String { action.denial }

    // ---------- 376: 遮下半段 ----------
    private static let maskChar: Character = "●"
    /// 前一半原样、后一半逐位糊掉 (奇数时多出来的那一位算上半段, 遮到的位数永不超过看得见的)。
    /// 两位以下没有"下半段"可言, 原样返回 —— 一位码遮完就等于把口令吞了却不给任何提示。
    static func masked(_ digits: String) -> String {
        let n = digits.count
        guard n >= 3 else { return digits }
        let keep = (n + 1) / 2
        return String(digits.prefix(keep)) + String(repeating: maskChar, count: n - keep)
    }
    /// 376 渲染侧的一行读法: 开关关着原样给, 开着遮下半段 (调用点不必自己写三目)
    static func halfMasked(_ digits: String) -> String { shareHalf ? masked(digits) : digits }

    // ---------- 383: 毁灭动作的口令复核 (走既有 DB.verifyPasscode, 不新建存储也不新建口令位) ----------
    /// 当场比对应用锁口令。两处 fail-closed: 空输入不放行、本机没设口令不放行 (无凭据可验 = 不放行毁灭动作)。
    /// 只验不记: 失败留痕走界面侧那条 LockGuard 通道 (见 SecurityCenterView 的 sudoTicketFromReview)。
    static func sudoOk(_ input: String) -> Bool {
        guard !input.isEmpty else { return false }
        guard DB.hasPasscode() else { return false }
        return DB.verifyPasscode(input)
    }
    /// 验过才发券; 没验过就是 nil, 销毁那一步在 AuditChain 里自己停手
    static func sudoTicket(from input: String) -> SudoTicket? {
        guard sudoOk(input) else { return nil }
        return SudoTicket(issuedAt: Date().timeIntervalSince1970)
    }
}
