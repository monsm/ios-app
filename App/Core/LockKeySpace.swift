// 每锁数据族的**唯一所有权表**。
//
// 背景: UserDefaults 里 300+ 个 `kf_*` 键没有命名空间机制, 而"删一把设备"必须把它那一族全清掉,
// 否则解绑后重配会撞上过期快照/待发队列/说明便签。旧实现把这 35 个前缀写在 `removeDevice` 里,
// 再用一条"键名含 MAC 即属本锁"的兜底扫尾 —— 两套判据写在同一个函数里, 新增键族时没人知道该加到哪。
//
// 现在只有三档, 每个键族必须落在其中一档:
//   1. `suffixPrefixes` — `前缀 + mac`, 精确删即可;
//   2. `segmentedPrefixes` — `前缀 + mac + "_" + 尾段`, 按前缀段整族扫;
//   3. 兜底 — 键名含 MAC (大小写不敏感) 即删除。给"mac 后面还有多层尾段"且前缀不统一的族用,
//      同时兼容 DemoKit 的大写 demoMac。
//
// 新增每锁键时: 优先选 1; mac 后还有尾段就选 2; 只有确实拿不出一致前缀时才依赖 3。
// `tools/keyspace.js` 会检查 removeDevice 仍然只走这张表, 且表里没有重复项。
enum LockKeySpace {
    /// `前缀 + mac` 的族。
    static let suffixPrefixes: [String] = [
        // 快照 / 记录 / 台账
        "kf_ledger_", "kf_snap_", "kf_logcache_", "kf_lockmeta_", "kf_migok_",
        // 锁端配置镜像
        "kf_defend_", "kf_tailgate_", "kf_synctime_", "otpStatus_", "otpIdx_", "kf_macorder_",
        // 事件 / 电量 / 保养 / 固件
        "kf_fevents_", "kf_mevents_", "kf_batt_", "kf_batt_state_", "kf_maint_",
        "kf_fwsince_", "kf_clock_notify_", "kf_damp_last_", "kf_fp_last_", "kf_care_notify_",
        // 凭证队列 / 告警 / 列表 / 序号
        "kf_cbin_", "kf_cqueue_", "kf_cstar_", "kf_calert_", "kf_clists_", "kf_cseq_",
        // 记录备注与标旗 (自由文本可能含人名/地址, 必须随锁清除)
        "kf_rnote_", "kf_rflag_",
        // 停用原因便签 (逐条, 只留最近 200 条)
        "kf_cdisrea_",
        // 链路 / 自动开锁
        "kf_linkrssi_", "kf_link_auto_",
        "kf_autocal_", "kf_autoopen_audit_", "kf_autoopen_suspend_until_",
    ]

    /// `前缀 + mac + "_" + 尾段` 的族 (整段前缀扫)。
    static let segmentedPrefixes: [String] = [
        "kf_chist_",   // kf_chist_<mac>_<kind>_<...>
    ]

    /// 键名里直接含 MAC 的兜底族说明 (不列举前缀): 这些键在 mac 之后还有多层尾段,
    /// 且历史上前缀不统一 —— 精确前缀删够不着, 只能按键名判定。
    /// 例: kf_calert_<mac>_<kind>_<key>、kf_cestudy_earlyexp_<mac>_<alias>、
    ///     kf_cotp_t_<mac>、kf_cdraft_<mac>、kf_logarch_<mac>、
    ///     kf_mborrow_/kf_mclaim_/kf_mig_lockact_<mac>、kf_offboard_<member>。
    static let macInKeyFamilies = [
        "kf_calert_", "kf_cestudy_", "kf_cotp_t_", "kf_cdraft_", "kf_logarch_",
        "kf_mborrow_", "kf_mclaim_", "kf_mig_lockact_", "kf_offboard_",
    ]

    /// 这把锁的键是否属于本锁数据族 (兜底判据)。大小写不敏感: DemoKit 用大写 demoMac。
    static func owns(_ key: String, _ mac: String) -> Bool {
        key.contains(mac) || key.contains(mac.uppercased())
    }

    /// 清掉一把锁的全部逐锁键。调用方负责钥匙串/未完成配网记录/全局指针。
    static func purge(_ mac: String) {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        guard !m.isEmpty else { return }
        for p in suffixPrefixes { DB.store.remove(p + m) }
        for p in segmentedPrefixes {
            let full = p + m + "_"
            for k in DB.store.keys() where k.hasPrefix(full) { DB.store.remove(k) }
        }
        for k in DB.store.keys() where owns(k, m) { DB.store.remove(k) }
    }
}
