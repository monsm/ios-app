// DB · 锁状态 / 日志缓存 / 布防 / 防尾随 / 校时 / OTP
// 2026-10-29 从 Store.swift 拆出。
import Foundation

extension DB {
    // 快照
    static func writeStatus(_ mac: String, _ st: LockStatus) {
        let d = StatusSnapshotData(
            rc: st.rc, powerLevel: st.powerLevel, firmware: st.firmware,
            lockTime: st.lockTime ?? 0, pinStock: st.pinStock, pwdStock: st.pwdStock, fpStock: st.fpStock,
            verifyMode: st.verifyMode, broadcastMode: st.broadcastMode, tempPwdMode: st.tempPwdMode,
            securityLevel: st.securityLevel, sKeyStatus: st.sKeyStatus,
            zotpPeriod: st.zotpPeriod > 0 ? st.zotpPeriod : nil,
            pinCap: st.pinInfoCapacity > 0 ? st.pinInfoCapacity : nil,
            pwdCap: st.pwdInfoCapacity > 0 ? st.pwdInfoCapacity : nil,
            fpCap: st.fpInfoCapacity > 0 ? st.fpInfoCapacity : nil)
        // 2026-10-29 性能：每次 getStatus 成功都会走到这里，而状态大多时候没变。
        // 原先无条件 set → 每次都是一次 JSONSerialization + UserDefaults(plist) 落盘。
        // 现在先比一遍：字段全等就不写（at 时间戳不参与比较，它只是"上次读到"的标记）。
        if let old = get(StatusSnapshot.self, "kf_snap_" + mac)?.status, old == d { return }
        set(StatusSnapshot(at: Date().timeIntervalSince1970 * 1000, status: d), "kf_snap_" + mac)
    }

    static func readStatus(_ mac: String) -> StatusSnapshotData? {
        get(StatusSnapshot.self, "kf_snap_" + mac)?.status
    }

    /// 包2/125 最后已知状态: 快照采样时刻 (信封 at), 断连展示"数据截至 14:32 · 缓存"用
    static func statusTime(_ mac: String) -> Double {
        get(StatusSnapshot.self, "kf_snap_" + mac)?.at ?? 0
    }

    static func writeLogs(_ mac: String, _ logs: [LogEntry]) {
        guard cacheWritable(mac) else { return }
        var cache = get(LogCache.self, "kf_logcache_" + mac) ?? LogCache(at: 0, logs: [])
        cache.at = Date().timeIntervalSince1970 * 1000
        var seen = Set<String>()
        var merged = [CachedLog]()
        for l in (logs.map { CachedLog(type: $0.type, typeName: $0.typeName, idxRaw: $0.idxRaw, lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr) } + cache.logs) {
            let k = String(l.idxRaw)
            if seen.contains(k) { continue }
            seen.insert(k)
            merged.append(l)
            if merged.count >= 300 { break }
        }
        cache.logs = merged
        set(cache, "kf_logcache_" + mac)
    }

    static func readLogs(_ mac: String) -> [CachedLog] {
        get(LogCache.self, "kf_logcache_" + mac)?.logs ?? []
    }

    // 配置记忆
    static func defend(_ mac: String) -> DefendCfg? { get(DefendCfg.self, "kf_defend_" + mac) }

    static func saveDefend(_ mac: String, _ c: DefendCfg) { set(c, "kf_defend_" + mac) }

    static func tailgate(_ mac: String) -> TailgateCfg? { get(TailgateCfg.self, "kf_tailgate_" + mac) }

    static func saveTailgate(_ mac: String, _ c: TailgateCfg) { set(c, "kf_tailgate_" + mac) }

    static func syncTime(_ mac: String) -> Double { store.get("kf_synctime_" + mac, Double.self) ?? 0 }

    static func saveSyncTime(_ mac: String, _ t: Double) { store.set("kf_synctime_" + mac, t) }

    // 靠近自动开锁 (AUTOOPEN-PLAN)：**唯一一份**读写口径在 App/Core/AutoOpen.swift
    // (`AutoOpen.on` / `AutoOpen.faceTier` / `suspendUntil` / `AuditEntry`)。这里曾有四个入口：
    // autoOpenAudit(_:) 用 getDict 取一个存 [AuditEntry] JSON 的键 (类型就不对，取回来必然是空)、
    // autoOpenSuspendUntil(_:) 与 AutoOpen.suspendUntil 逐字重复 —— 那两个先删了；
    // `autoOpen` / `autoOpenFaceTier` 是同一对键的第二处读写入口且全仓零调用
    // (grep `DB.autoOpen\b`、`DB.autoOpenFaceTier` 皆空)，第一百七十一批按同一条理由一并删掉。
    // 留着就是"看着像另一条读法"的假入口：改档位语义时只会改到其中一处，两份默认值也就各自漂 (§10.43)。
    static func otpStatus(_ mac: String) -> OtpStatus? { get(OtpStatus.self, "otpStatus_" + mac) }

    static func saveOtpStatus(_ mac: String, _ s: OtpStatus) { set(s, "otpStatus_" + mac) }

    static func otpIdx(_ mac: String) -> OtpIdx? { get(OtpIdx.self, "otpIdx_" + mac) }

    static func saveOtpIdx(_ mac: String, _ i: OtpIdx) { set(i, "otpIdx_" + mac) }

}
