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
            fpCap: st.fpInfoCapacity > 0 ? st.fpInfoCapacity : nil,
            pinInfoBinding: st.pinInfoBinding > 0 ? st.pinInfoBinding : nil)
        // 2026-10-29 性能：每次 getStatus 成功都会走到这里，而状态大多时候没变。
        // 原先无条件 set → 每次都是一次 JSONSerialization + UserDefaults(plist) 落盘。
        //
        // 但不能"没变就完全不写"：信封里的 `at` 是「数据截至」的展示基准（statusTime()），
        // 完全不写会让用户看到一条明明刚读过、却标着很旧时间的快照。
        // 所以：字段全等 且 距上次落盘 < 60s 才跳过；超过 60s 仍刷新一次 `at`。
        let nowMs = Date().timeIntervalSince1970 * 1000
        if let old = get(StatusSnapshot.self, "kf_snap_" + mac), old.status == d, nowMs - old.at < 60_000 { return }
        set(StatusSnapshot(at: nowMs, status: d), "kf_snap_" + mac)
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
        // 2026-10-29 性能：本函数在**分页循环**里被调（每页 5 条、最多 20 页），
        // 每次都要 get(整份缓存解码) + 合并 + set(整份写回) ⇒ O(页数 × 缓存条数) 的编解码，
        // 外加最多 20 次 UserDefaults 落盘。调用方已改成「循环结束只写一次」。
        //
        // 合并语义保持不变（新页 + 已有缓存、按 idxRaw 去重、上限见下方 4096 的说明）；
        // 这里把结果按 idxRaw 倒序排一次 —— idxRaw 是锁端日志序号，越大越新，
        // 与原先「新页在前 + 旧缓存在后」的顺序等价，且不依赖调用方的拉取顺序。
        var byIdx = [UInt32: CachedLog]()
        for l in cache.logs { byIdx[l.idxRaw] = l }
        for e in logs {
            byIdx[e.idxRaw] = CachedLog(type: e.type, typeName: e.typeName, idxRaw: e.idxRaw,
                                       lockTime: e.lockTime, lockTimeStr: e.lockTimeStr,
                                       diff: e.diffDescription)
        }
        let merged = Array(byIdx.values).sorted { $0.idxRaw > $1.idxRaw }
        // 2026-11-07（真机审计）：上限 300 → 4096。锁端日志约 2000 条滚存，而「断点续读」
        // （AppModel.readLogs + RecordsSource.logCursor）要能把更早的段落留在缓存里 ——
        // 300 条会把续读翻到的旧记录立刻截掉，"继续读更早" 就成了白翻。
        // 4096 表示"整锁日志全量 + 余量"：解码成本只在 readLogs 时一次付出。
        cache.logs = Array(merged.prefix(4096))
        set(cache, "kf_logcache_" + mac)
    }

    /// 清空一把锁的记录缓存。
    ///
    /// 读日志的新口径是「每轮先清空、再读全量」—— 这个口就是那一下。
    /// 它只删本机副本，不动锁端，也不动备注/旗标（那些在 RecordOverlay 里，键不同）。
    static func clearLogs(_ mac: String) {
        guard cacheWritable(mac) else { return }
        store.remove("kf_logcache_" + mac)
    }

    static func readLogs(_ mac: String) -> [CachedLog] {
        // SEC-03：空壳模式不返回任何锁内日志（记录页/门页/导出都读这里）。
        if DB.isDecoy { return [] }
        return get(LogCache.self, "kf_logcache_" + mac)?.logs ?? []
    }

    /// 2026-10-30 性能：`readLogs(mac).count` 的专用口 —— 只数条数，不解码每一条。
    /// 实现直接用 `JSONSerialization` 取根数组的 count（LogCache 的 logs 就是根下第一个数组），
    /// 不走 Codable：`readLogs` 的成本是「最多 4096 条 CachedLog 逐条解码」，这里的成本只是解析一遍结构。
    /// 调用方：warmLocks（多锁预热排序，每把锁一次）。
    static func readLogCount(_ mac: String) -> Int {
        guard let d = UserDefaults.standard.data(forKey: "kf.kf_logcache_" + mac),
              let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let logs = root["logs"] as? [Any] else { return 0 }
        return logs.count
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
    /// SEC-03：空壳里一律当作「没开通」。
    ///
    /// 这个读法原先不判空壳 —— 于是锁上真的开过动态密码时，空壳里的「动态密码」页会
    /// **完整可用**：周期、序号、失效时刻都是从真实数据读的，点一下就能算出一串
    /// 此刻真能开门、还会推进真实 `otpIdx_` 的数字。凭证页在空壳里是空的，
    /// 这一页却把同一把锁的开锁凭证摆出来，等于在空壳里开了一扇后门。
    static func otpStatus(_ mac: String) -> OtpStatus? {
        if DB.isDecoy { return nil }
        return get(OtpStatus.self, "otpStatus_" + mac)
    }

    static func saveOtpStatus(_ mac: String, _ s: OtpStatus) { set(s, "otpStatus_" + mac) }

    static func otpIdx(_ mac: String) -> OtpIdx? { get(OtpIdx.self, "otpIdx_" + mac) }

    static func saveOtpIdx(_ mac: String, _ i: OtpIdx) { set(i, "otpIdx_" + mac) }

}
