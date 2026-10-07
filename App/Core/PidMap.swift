// 产品矩阵与能力开关 — JS utils/pidmap.js 移植 (App Nn 枚举 + zn.can*)
// 差分基准: golden.pidTable / golden.capabilities
import Foundation

enum PidMap {
    static let K1 = 8097, KX = 8098, V1 = 7857, V1_Pro = 7858, JZ = 7873
    static let Z3 = 7891, Z3NFC = 7892, Z3AL = 7893, ZKBBV1 = 16289
    static let GW = 12193, GW_commercial = 12209, GW2_commercial = 12194

    static let names: [Int: String] = [
        K1: "K1", KX: "KX", V1: "V1", V1_Pro: "V1_Pro", JZ: "JZ",
        Z3: "Z3", Z3NFC: "Z3NFC", Z3AL: "Z3AL", ZKBBV1: "ZKBBV1",
        GW: "GW", GW_commercial: "GW_commercial", GW2_commercial: "GW2_commercial"
    ]
    // 中文产品名 (App rominfo getPNameWithPid)
    static let productNames: [Int: String] = [
        8097: "智能门锁 K1", 8098: "智能门锁 KX", 7857: "智能门锁 V1", 7873: "智能门锁 V1 Pro",
        7891: "智能门锁 Z3", 7892: "智能门锁 Z3 NFC", 7893: "智能门锁 Z3 AL"
    ]
    static let locks = [KX, V1, V1_Pro, JZ]
    static let gws = [GW, GW_commercial, GW2_commercial]

    static func modelName(_ pid: Int) -> String {
        if pid == 0 { return "自动识别" }
        if let n = names[pid] { return n }
        return "未知型号(pid=\(pid))"
    }
    static func productName(_ pid: Int) -> String { productNames[pid] ?? ("智能门锁 (pid=\(pid))") }
    static func isLock(_ pid: Int) -> Bool { pid == 0 || locks.contains(pid) }
    private static func isKnown(_ pid: Int) -> Bool { names[pid] != nil }
    private static func isGW(_ pid: Int) -> Bool { gws.contains(pid) }
    // 布防: 仅 KX/V1_Pro; 未知 pid (新品固件, 如实测 49408) 按 KX 家族放行
    static func canDefend(_ pid: Int) -> Bool {
        isGW(pid) ? false : (pid == KX || pid == V1_Pro || !isKnown(pid))
    }
    private static func cmpFw(_ fw: String, _ minV: String) -> Int {
        let a = fw.split(separator: ".").map { Int($0) ?? 0 }
        let b = minV.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
    // 尾随/自动上锁: V1_Pro 且固件 < 1.0.3 拒绝 (App tailgate_defend_romver)
    static func canTailgate(_ pid: Int, fw: String?) -> Bool {
        if !canDefend(pid) { return false }
        if pid == V1_Pro, let f = fw, !f.isEmpty, cmpFw(f, "1.0.3") < 0 { return false }
        return true
    }
    static func canClearPwd(_ pid: Int) -> Bool { isGW(pid) ? false : (locks.contains(pid) || !isKnown(pid)) }
    static func canDeviceInfo(_ pid: Int) -> Bool { canClearPwd(pid) }
    static func canDeviceUpgrade(_ pid: Int) -> Bool { canClearPwd(pid) }
}