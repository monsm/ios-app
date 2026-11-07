// Capabilities.swift —— 能力协商（B15）。
//
// 过去界面判断「这把锁能不能布防」是直接调 `PidMap.canDefend(pid)` ——
// 而 pid 只是能力的一半：固件版本决定另一半（V1_Pro 固件 < 1.0.3 不认尾随）。
// 散在页面里的 `PidMap.canXxx(pid)` 调用迟早会漏掉固件这一半，
// 于是「不支持的功能」变成「点了报错的按钮」。
//
// 现在统一成一份 `LockCapabilities`：**界面只问能力，不自己判**。
// 判据仍然只有一处（PidMap），这里只负责把它拼成一张完整的表，
// 并标出「这台锁我们还没验证过」的诚实边界。
import Foundation

/// 一把锁当前支持什么。
struct LockCapabilities: Equatable {
    var pid: Int = 0
    var firmware: String = ""

    // 锁端能力（按型号/固件）
    var canDefend: Bool = false        // 布防（cmd25）
    var canTailgate: Bool = false      // 尾随 / 自动上锁（cmd24）
    var canClearPasswords: Bool = false // 清空全部密码（cmd0a delAll）
    var canSilent: Bool = true         // 静音（cmd18）
    var canDualVerify: Bool = true     // 双验（cmd20）
    var canAutoLock: Bool = true       // 自动上锁时长（cmd24）
    var canZotp: Bool = true           // 动态密码（cmd19）
    var canFingerprint: Bool = true    // 指纹（cmd13/14/15）
    var canUpgrade: Bool = false       // 固件升级
    var canStatusReadback: Bool = true // 读状态（cmd03）

    // **我们**的验证边界（不是锁的能力，是本 App 的）
    /// 型号不在我们收录的表里 —— 能力按「未知型号的宽松档」给，但界面要提示。
    var unknownModel: Bool = false
    /// 固件版本高于我们验证过的版本 —— 能力按「最新验证档」给。
    var newerThanTested: Bool = false
    /// 布防**没有回读校验**：只知锁回了 rc=0，不知它真的布防了。
    /// 界面因此不能写「已布防」，只能写「指令已下发」。
    var defendReadbackUnknown: Bool = true

    /// 界面上要显示的一句话边界说明（没有就 nil）。
    var caveat: String? {
        if unknownModel {
            return "这把锁的型号还没收录，功能可能与已验证的型号不同。"
        }
        if newerThanTested {
            return "固件版本比本 App 验证过的更新，功能表现可能不同。"
        }
        return nil
    }

    /// 布防是否真的可以承诺「已生效」。
    var canPromiseDefence: Bool { canDefend && !defendReadbackUnknown }
}

enum CapabilityResolver {
    /// 本 App 验证过的最高固件版本（用来判「比验证过的更新」）。
    static let testedFirmware = "1.0.3"

    /// 按型号 + 固件解析能力表。
    ///
    /// `pid == 0`（还没读到型号）时给**保守档**：什么写操作都不放行，
    /// 只读的东西照常。理由：宁可少给功能，也不要在未知型号上乱下发写命令。
    static func resolve(pid: Int, firmware: String) -> LockCapabilities {
        var c = LockCapabilities()
        c.pid = pid
        c.firmware = firmware

        if pid == 0 {
            c.canDefend = false
            c.canTailgate = false
            c.canClearPasswords = false
            c.canSilent = false
            c.canDualVerify = false
            c.canAutoLock = false
            c.canZotp = false
            c.canFingerprint = false
            c.canUpgrade = false
            c.unknownModel = true
            return c
        }

        c.unknownModel = PidMap.names[pid] == nil
        c.canDefend = PidMap.canDefend(pid)
        c.canTailgate = PidMap.canTailgate(pid, fw: firmware.isEmpty ? nil : firmware)
        c.canClearPasswords = PidMap.canClearPwd(pid)
        c.canUpgrade = PidMap.canDeviceUpgrade(pid)
        // 其余能力目前所有已收录型号都支持；未收录型号按宽松档（与 canDefend 的口径一致）。
        c.canSilent = true
        c.canDualVerify = true
        c.canAutoLock = true
        c.canZotp = true
        c.canFingerprint = true
        c.newerThanTested = compareFw(firmware, testedFirmware) > 0
        return c
    }

    /// 从锁档案直接解析（读本机快照里的固件 + 钥匙串里的型号）。
    static func resolve(mac: String) -> LockCapabilities {
        let kc = DB.keychain(mac)
        let snap = DB.readStatus(mac)
        let pid = kc?.pid ?? 0
        let fw = snap?.firmware ?? kc?.fw ?? ""
        return resolve(pid: pid, firmware: fw)
    }

    /// 固件版本比较（a > b ⇒ 1）。解析不出的段按 0 算 —— 「读不出来」不等于「新」。
    static func compareFw(_ a: String, _ b: String) -> Int {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< 3 {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}
