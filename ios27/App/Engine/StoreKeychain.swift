// DB · 钥匙串（读取 / 保存 / 移除 / 迁移 / 待配对 / MAC 排序）
// 2026-10-29 从 Store.swift（621 行）拆出。
import Foundation

/// 2026-10-29 性能：keychain(mac) 原来每次都 Keychain.fromDict → **4 次 SecItemCopyMatching**
/// （skey / bkey / ekey / pins 各一次）。全仓 39 个调用点，其中不少在列表与比较式里。
/// 这里按 mac 缓存整份 Keychain（密钥只在内存），写路径负责失效。
private let keychainCache = Locked<[String: Keychain]>([:])

extension DB {
    // 钥匙串 (多锁)
    static func keychains() -> [Keychain] {
        let map = store.getDict("kf_keychains")
        let list = map.values.compactMap { $0 as? [String: Any] }
            .compactMap { Keychain.fromDict($0) }
            .sorted { ($0.pairedAt) < ($1.pairedAt) }
        // 顺手把整表填进缓存，后续逐把 keychain(mac) 不必再打 Keychain API。
        keychainCache.withLock { c in for kc in list { c[normalizeMac(kc.mac)] = kc } }
        return list
    }

    static func keychain(_ mac: String) -> Keychain? {
        let m = normalizeMac(mac)
        if let hit = keychainCache.withLock({ $0[m] }) { return hit }
        let map = store.getDict("kf_keychains")
        guard let d = map[m] as? [String: Any], let kc = Keychain.fromDict(d) else { return nil }
        keychainCache.withLock { $0[m] = kc }
        return kc
    }

    /// MAC 归一化 —— **全仓唯一入口**（2026-10-27 审核合并，AUDIT-C A11）。
    /// 去冒号 + 去连字符 + 小写。
    /// 补「去连字符」的理由：`BluetoothDevice.getAddress()` 在部分机型/厂商 SDK 上带连字符，
    /// 而 Android 版早就去掉了（`KfProtocol.kt:230`）—— iOS 没去，于是同一份带连字符的 MAC
    /// 从备份/二维码进来会建出**两个不同的台账键**。Android 那版是对的，这里对齐它。
    static func normalizeMac(_ m: String) -> String {
        m.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    // ---------- 0x88 包络 MAC 字节序 (per MAC, 2026-10-17) ----------
    /// 顺序是"这台手机跟这把锁谈过话"的**观测结果**, 不是密钥材料, 所以刻意**不进 `Keychain`**:
    /// 那个结构是要随备份/导出走的密钥台账, 多一个字段就要动它的 Codable 容错链与备份口径;
    /// 而顺序认不出来时的代价很小 (默认回原版 APK 语义, 错一次由 rc=12 自愈纠正)。
    static func macOrderKey(_ mac: String) -> String { "kf_macorder_" + normalizeMac(mac) }

    static func macOrder(_ mac: String) -> ZKProtocol.MacOrder {
        ZKProtocol.MacOrder(rawValue: store.getString(macOrderKey(mac))) ?? .display
    }

    /// 落盘 + 同步进协议层注册表 (协议层成帧只看注册表)
    static func setMacOrder(_ mac: String, _ o: ZKProtocol.MacOrder) {
        store.set(macOrderKey(mac), o.rawValue)
        ZKProtocol.setMacOrder(mac, o)
    }

    /// 启动窗口把已裁定的顺序灌回协议层 —— 协议层不读库, 补不上这一支时进程重启后第一帧会回 rc=12,
    /// 由 exec 的顺序自愈再学一次 (代价: 多一个来回, 不会写错锁)。
    static func hydrateMacOrders() {
        for kc in keychains() { ZKProtocol.setMacOrder(kc.mac, macOrder(kc.mac)) }
    }

    /// 密钥材料 (skey/bkey/ekey) 的系统 Keychain 账户名。
    static func secretAccount(_ mac: String, _ field: String) -> String { "kc." + normalizeMac(mac) + "." + field }

    /// 2026-10-14 一次性迁移: 把旧 plist 里明文的 skey/bkey/ekey 搬进系统 Keychain, 并从 plist 抹掉。
    /// 幂等 (没有明文字段时不动), 启动时调一次。
    static func migrateSecretsToKeychain() {
        // 2026-10-27 审核修复 (D-07)：读出来的字典若解码失败过，**绝不能写回** ——
        // 那会把其它设备的钥匙串整表抹掉。这里直接放弃本次写入（密钥已进 Keychain，
        // plist 里的非密字段下次保存会再试）。
        if store.isDictCorrupt("kf_keychains") { return }
        var map = store.getDict("kf_keychains")
        var changed = false
        for (m, v) in map {
            guard var d = v as? [String: Any] else { continue }
            var touched = false
            for f in ["skey", "bkey", "ekey"] {
                guard let legacy = d[f] as? String, !legacy.isEmpty else { continue }
                // 关键: 只有 Keychain 里确实有值 (原本就有, 或本次写成功) 才允许抹掉 plist 明文。
                // 否则 (如首次解锁前的后台启动) 写失败 + 抹明文 = 永久丢密钥, 门锁再也开不了。
                let stored = SecretStore.get(secretAccount(m, f)) != nil
                if stored || SecretStore.set(legacy, for: secretAccount(m, f)) {
                    d.removeValue(forKey: f)
                    touched = true
                }
            }
            if touched { map[m] = d; changed = true }
        }
        if changed { store.set("kf_keychains", map) }
    }

    static func saveKeychain(_ kc: Keychain) {
        // 2026-10-14: 门锁密钥不再随偏好明文写进 plist (越狱/iTunes 备份即可读走), 改存系统 Keychain;
        // plist 只留非密字段 (mac/名称/pid/pins…)。读侧 fromDict 自动回填。
        // 空 skey 不覆盖既有值 (Keychain 读失败回填 "" 时, 一次无关的 saveKeychain 会把真密钥写成空)。
        // 2026-10-27 审核修复：三把密钥写 Keychain 的返回值原先全部被丢弃 ——
        // 写入失败时用户看不到任何异常，下次开锁才莫名失败（且查不出原因）。
        // 现在失败一律记一条遥测（诊断页已删，但记录仍在 kf_ble_events 里可导出）。
        var failed: [String] = []
        if !kc.skey.isEmpty, !SecretStore.set(kc.skey, for: secretAccount(kc.mac, "skey")) {
            failed.append("skey")
        }
        if kc.bkey.isEmpty { SecretStore.remove(secretAccount(kc.mac, "bkey")) }
        else if !SecretStore.set(kc.bkey, for: secretAccount(kc.mac, "bkey")) { failed.append("bkey") }
        if kc.ekey.isEmpty { SecretStore.remove(secretAccount(kc.mac, "ekey")) }
        else if !SecretStore.set(kc.ekey, for: secretAccount(kc.mac, "ekey")) { failed.append("ekey") }
        // 2026-10-27 审核修复 (AUDIT-D D-06)：pins 也进 Keychain。
        // 原先 pins（最多 64 个）明文落 plist，而 skey/bkey/ekey 走 Keychain ——
        // 等于钥匙劈两半：`buildEkeyOpen(skey, mac, pin)` 要两件才签得出开锁凭据，
        // 一半锁保险箱、一半贴冰箱。现在与其它密钥同一套。
        // 空 pins 时清掉（与 bkey/ekey 同款语义），否则留着一份过期的 pin 池更危险。
        let pinsJoined = kc.pins.joined(separator: ",")
        if pinsJoined.isEmpty { SecretStore.remove(secretAccount(kc.mac, "pins")) }
        else if !SecretStore.set(pinsJoined, for: secretAccount(kc.mac, "pins")) { failed.append("pins") }
        if !failed.isEmpty {
            BleTelemetry.recordEvent("Keychain 写入失败： " + failed.joined(separator: "/")
                                     + " @ " + String(kc.mac.prefix(6)), ok: false)
        }
        // 2026-10-27 审核修复 (AUDIT-D D-18)：`读 → 改 → 写` 三步必须原子。
        // 原先没有同步：两个线程同时保存不同设备的钥匙串时，后写的那个用的是
        // 自己那份旧快照，会把对方刚加的键覆盖掉 —— 表现是「配了两把锁只剩一把」。
        keychainWriteLock.withLock { _ in
            var map = store.getDict("kf_keychains")
            map[normalizeMac(kc.mac)] = kc.toDict()
            store.set("kf_keychains", map)
            // 缓存失效而不是写入 kc：调用方可能带着空 skey 进来（空值不覆盖既有密钥），
            // 那种情况下把 kc 塞进缓存会把真密钥遮掉。下次读会重新从 plist+Keychain 组装。
            keychainCache.withLock { $0[normalizeMac(kc.mac)] = nil }
        }
    }

    // ---------- 配网中断保护 (防软砖) ----------
    /// 05 换钥一 rc=0, 锁内 skey 就已经是**新的**了。本机若没把这套钥落盘, 后面任何一步失败
    /// (断链 / App 被杀 / 08·21·03 被拒) 都只能靠"去门锁键盘重置一遍"收场 —— 那是最接近"变砖"的状态:
    /// 锁在你手上、门就在那儿, 却谁也配不上, 而重置需要人到锁跟前。
    /// 所以: 换钥成功后**先落盘**这套密钥 (密钥材料进系统 Keychain, plist 只留非密字段),
    /// 尾链走完再提升为正式钥匙串; 走到一半断了就用这份记录**续配** (跳过 05, 不碰锁内密钥域)。
    static func pendingPairAccount(_ mac: String, _ field: String) -> String { "pair." + normalizeMac(mac) + "." + field }

    static func savePendingPair(_ kc: Keychain) -> Bool {
        guard !kc.skey.isEmpty, !kc.pins.isEmpty else { return false }
        var ok = true
        for (f, v) in [("skey", kc.skey), ("bkey", kc.bkey), ("ekey", kc.ekey), ("pins", kc.pins.joined(separator: ","))] {
            if v.isEmpty { SecretStore.remove(pendingPairAccount(kc.mac, f)); continue }
            if !SecretStore.set(v, for: pendingPairAccount(kc.mac, f)) { ok = false }
        }
        var d = kc.toDict()
        d["at"] = Date().timeIntervalSince1970 * 1000
        store.set("kf_pending_pair_" + normalizeMac(kc.mac), d)
        return ok
    }

    static func pendingPair(_ mac: String) -> Keychain? {
        let m = normalizeMac(mac)
        let d = store.getDict("kf_pending_pair_" + m)
        guard !d.isEmpty, var kc = Keychain.fromDict(d) else { return nil }
        kc.skey = SecretStore.get(pendingPairAccount(m, "skey")) ?? ""
        kc.bkey = SecretStore.get(pendingPairAccount(m, "bkey")) ?? ""
        kc.ekey = SecretStore.get(pendingPairAccount(m, "ekey")) ?? ""
        let pins = SecretStore.get(pendingPairAccount(m, "pins")) ?? ""
        kc.pins = pins.isEmpty ? [] : pins.components(separatedBy: ",")
        return kc.skey.isEmpty ? nil : kc   // 只有 plist 标记、没有密钥材料 = 无用的残片
    }

    static func clearPendingPair(_ mac: String) {
        let m = normalizeMac(mac)
        for f in ["skey", "bkey", "ekey", "pins"] { SecretStore.remove(pendingPairAccount(m, f)) }
        store.remove("kf_pending_pair_" + m)
    }

    /// 只清钥匙串本身。**不动**未完成的配网记录: 配网尾链失败时 UI 的 rollback 会调到这里,
    /// 而那一份记录正是"再点一次配网就能接着配完"的依据 (2026-10-17 真机截图里的承诺就是它)。
    /// 真要连记录一起清 —— 用户主动删设备 —— 走 `removeDevice`。
    static func removeKeychain(_ mac: String) {
        let m = normalizeMac(mac)
        SecretStore.remove(secretAccount(m, "skey"))
        SecretStore.remove(secretAccount(m, "bkey"))
        SecretStore.remove(secretAccount(m, "ekey"))
        // 2026-10-27 (D-06)：pins 已进 Keychain，删除时一并清（否则删设备后 pin 池残留）。
        SecretStore.remove(secretAccount(m, "pins"))
        var map = store.getDict("kf_keychains")
        map.removeValue(forKey: m)
        store.set("kf_keychains", map)
        keychainCache.withLock { $0[m] = nil }
    }

    // 删除设备: 钥匙串 + 每锁数据族 + 指针 (JS removeDevice 全量语义)
    /// 2026-10-27 审核说明 (AUDIT-A F-30)：报告说本仓清理列表「漏了 kf_fpnames_」——
    /// 实测该键在当前代码里**不存在**（指纹名存在 `LedgerFp.name` 里，不单独落键）。
    /// 且第 496 行的兜底清理 `k.contains(m)` 已覆盖所有含本锁 MAC 的键，
    /// 所以没有遗漏。跨端差异在于：vendor 用独立键存指纹名，本仓存在台账里。
    static func removeDevice(_ mac: String) {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        removeKeychain(m)
        clearPendingPair(m)   // 删设备 = 连"未完成的配网记录"一起删 (否则下次配对先撞上一份过期密钥)
        // 2026-10-30 修复（第 94 轮）：**先把该设备全部凭证的到期提醒取消，再删数据**。
        // 下面那圈键族会删掉 `kf_calert_<mac>_` —— 但已排程的本地通知**不会随键消失**，
        // 删完设备后它们仍会按原时间弹出「密码临期」，指向一把已经不存在的锁。
        // 必须在删数据之前读台账（删完就读不到了）。
        for p in ledger(m).pwds { CredentialOrg.cancelAlerts(mac: m, alias: p.alias) }
        for p in ["kf_ledger_", "kf_snap_", "kf_logcache_", "kf_defend_", "kf_tailgate_", "kf_synctime_", "otpStatus_", "otpIdx_", "kf_fevents_", "kf_lockmeta_", "kf_migok_",
                  "kf_batt_", "kf_batt_state_", "kf_mevents_", "kf_maint_", "kf_fwsince_", "kf_clock_notify_", "kf_damp_last_", "kf_fp_last_", "kf_care_notify_",
                  "kf_cbin_", "kf_calert_", "kf_clists_", "kf_cseq_",
                  "kf_linkrssi_", "kf_link_auto_", "kf_macorder_"] {
            store.remove(p + m)
        }
        // 自动开锁每锁键 (kf_autocal_ / kf_autoopen_audit_ / kf_autoopen_suspend_until_, 尾段带 mac)
        for p in ["kf_autocal_", "kf_autoopen_audit_", "kf_autoopen_suspend_until_"] {
            store.remove(p + m)
        }
        // 包6 历史表键带 <mac>_ 段 (kf_chist_<mac>_...), 按前缀段整族清
        for p in ["kf_chist_" + m + "_"] {
            for k in store.keys() where k.hasPrefix(p) { store.remove(k) }
        }
        // 兜底清理 (审计 §6.6): 一批每锁键在 mac 之后**还带尾段**, 精确前缀删永远删不掉 ——
        // kf_cdraft_<mac>、kf_logarch_<mac>、kf_mborrow_/kf_mclaim_/kf_mig_lockact_<mac>、kf_offboard_<member> 等。
        // 判据: 键名里含本锁 MAC (大小写不敏感) 即属该锁数据族。
        let up = m.uppercased()
        for k in store.keys() where k.contains(m) || k.contains(up) { store.remove(k) }
        // 指针类全局键: 删除后不得悬空
        let defWasThis = store.getString("kf_default_mac") == m
        if defWasThis { store.remove("kf_default_mac") }
        if store.getString("kf_current_mac") == m { store.remove("kf_current_mac") }
        if store.getString("kf_last_device") == m { store.remove("kf_last_device") }
        // 766 手工顺序表是全局键 (mac 数组), 逐锁族前缀删够不着它 → 按元素剪, 否则会留下解绑锁的幽灵位
        var ord = store.get([String].self, "kf_lock_order") ?? []
        if ord.contains(m) {
            ord.removeAll { $0 == m }
            store.setCodable("kf_lock_order", ord)
            // 删掉的正好是首位 → 默认锁交棒给新的首位。不接这一棒, "第一行就是启动默认锁" (271/766)
            // 会一直断到用户下次动顺序为止, 而冷启动落点也悄悄退回"上次选中"。
            if defWasThis, let h = ord.first { store.set("kf_default_mac", h) }
        }
    }

    /// 子页默认锁: 优先用户当前所在锁 (且在台账里真实存在), 否则退回第一把。
    /// 旧写法各处直接 `DB.keychains().first?.mac` → 多锁时子页 (借用登记/791 认领/家政窗)
    /// 默认绑到最旧那把锁, 与用户当前锁不一致。
    static func preferredMac() -> String {
        let ks = keychains().map { $0.mac }
        return ks.contains(currentMac) ? currentMac : (ks.first ?? "")
    }

}
