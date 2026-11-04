// SeedImporter.swift —— CI 截图用的合成数据注入。
//
// 2026-11-03（打磨每个界面）：空态截图只能验证外壳；刻度盘、凭证环、读数网格、时间线
// 这些核心 UI 需要**有一把锁的数据**才渲染。本文件在启动参数带 -kfSeed 时，
// 把 Documents/kf-seed.json（kf-bundle 格式，与「备份工作室」同一格式）导入，
// 然后改名 .done —— 只生效一次，不污染后续截图。
//
// 安全边界：只在 CI 传 -kfSeed 时读这个文件；正常启动永远不带这个参数。
// 文件是**本机 Documents 里的**，不上传、不进备份（restore 走的是常规导入路径，
// 与用户手工导入一份备份完全相同）。
import Foundation

enum SeedImporter {
    @MainActor
    static func importIfPresent() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
        let seed = docs.appendingPathComponent("kf-seed.json")
        let done = docs.appendingPathComponent("kf-seed.json.done")
        guard FileManager.default.fileExists(atPath: seed.path) else { return }
        defer { try? FileManager.default.removeItem(at: seed) }
        do {
            let raw = try Data(contentsOf: seed)
            let bundle = try JSONDecoder().decode(BackupBundle.self, from: raw)
            let result = try BackupStudio.restore(bundle)
            // 合成一份锁状态快照：pid 落到 KX（PidMap 命中 → 门页标题「KX 系列」而非
            // 「未收录的型号 (pid=0)」），电量 76，锁内时间 = 现在（校时横幅不出现）。
            if let d = bundle.devices.first {
                var st = LockStatus()
                st.rc = 0
                st.powerLevel = 76
                // 2026-11-04（种子自相矛盾）：原来写死 "1.4.2"，而 seed 的 kc.fw="1.0.2" ——
                // 于是锁实况（快照）显示 1.4.2、锁信息名片（现场读失败回落 kc.fw）显示 1.0.2，
                // 同一把锁两个固件号。快照合成时**用种子钥匙串的 fw**，两边永远同源。
                st.firmware = bundle.devices.first?.kc.fw ?? "1.4.2"
                st.lockTime = Int64(ZKProtocol.nowProtoSeconds())
                // 与真机快照逐项对齐（2026-11-02 双侧快照）：
                //   PIN  cap 64 / 剩余 0  → 已用 64
                //   密码 cap 64 / 剩余 0  → 已用 64（原来写成 64 = "剩余 64"，截图显示 0/64，与真机不符）
                //   指纹 cap 50 / 剩余 7  → 已用 43
                st.pinStock = 0
                st.pwdStock = 0
                st.fpStock = 7
                st.sKeyStatus = 3
                st.zotpPeriod = 30
                st.pinInfoCapacity = 64
                st.pwdInfoCapacity = 64
                st.fpInfoCapacity = 50
                st.pid = 8098            // PidMap.KX
                st.pidName = "KX"
                DB.writeStatus(d.mac, st)
                // 2026-11-04（视觉验证缺口）：种子**没有锁内日志**，于是记录页永远是「还没有记录」——
                // 而记录域（归属映射、成员筛选、访客分组、统计）全靠这一页呈现，等于整块无法视觉验证。
                // 这里合成一小组日志：三种类型（指纹 19 / 密码 17 / 一次性 16）+ 时间跨度（今天/昨天/上周），
                // 让记录页、成员归属、周小结、24h 直方图都有东西可渲染。
                // 归属仍由 `Attribution` 自己算（不写死 owner），所以截图能验证归因链本身。
                var logs: [LogEntry] = []
                let nowProto = ZKProtocol.nowProtoSeconds()
                let kinds: [(Int, String)] = [(19, "指纹开门"), (17, "密码开门"), (16, "一次性密码开门")]
                for i in 0..<9 {
                    let (t, name) = kinds[i % kinds.count]
                    // 间隔 7 小时：覆盖今天 / 昨天 / 前天，直方图与「最近事件」都分布得开。
                    let proto = nowProto - Int64(i) * 7 * 3600
                    logs.append(LogEntry(type: t, typeName: name, idx: UInt32(100 + i), idxRaw: UInt32(100 + i),
                                         lockTime: proto, lockTimeStr: "", body: ""))
                }
                DB.writeLogs(d.mac, logs)
                // 2026-11-04（种子保真度）：上一条日志写进去了（wrote=9 readBack=9），但记录页
                // 归属列仍空 —— 查清原因是 `Attribution.classify` 三条判据都不成立：
                // 没有临时码窗口（R1）、fpStock=7 且名下 12 枚（R2 要求 stock=1 且仅 1 枚）、
                // 合成日志 body 为空（R3 要槽位）。**「未归属」是正确输出，但归属链就没法视觉验证。**
                // 这里补一枚覆盖全部日志时间窗的临时码，让 R1 能证明归属 —— 与真实场景同构
                // （临时码有起止时间，落在窗口内的开门可归给它的主人）。
                if let ownerID = DB.members().first?.id {
                    let now = Date()
                    let from = DF.stampUTC.string(from: now.addingTimeInterval(-3 * 86400))
                    let to = DF.stampUTC.string(from: now.addingTimeInterval(86400))
                    var ledger = DB.ledger(d.mac)
                    ledger.pwds.append(LedgerPwd(alias: 990, from: from, to: to, temp: true,
                                                 at: now.timeIntervalSince1970 * 1000,
                                                 pwd: nil, owner: ownerID, note: "CI 合成临时码"))
                    DB.saveLedger(d.mac, ledger)
                }
                // 2026-11-04（取证）：日志写没写进去，截图上看不出来（记录页仍空）。
                // 把"写了多少 / 读回多少"落一个文本文件，workflow 会 cat 进 diag —— 一次跑清。
                let readBack = DB.readLogs(DB.normalizeMac(d.mac)).count
                let note = "seed mac=\(d.mac) wrote=\(logs.count) readBack=\(readBack) "
                    + "keychain=\(DB.keychain(d.mac) != nil) logcacheKey=\(DB.normalizeMac(d.mac))"
                if let dd = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? note.write(to: dd.appendingPathComponent("kf-seed-diag.txt"), atomically: true, encoding: .utf8)
                }
            }
            // 2026-11-03（整页截图实测 · 根因）：`快捷操作` 那一块在截图里永远是空白，
            // 前三次都判错了原因。真正的原因在这里：**种子从没写过 `kf_quick_ids`** ——
            // `QuickPool.selected` 在键缺失时回退到 `defaultIds`（5 项），所以格子**应该**有；
            // 但 `kf_quick_grid`（渲染上限）默认 6，也不该是 0。真正为 0 的是
            // `SettingsStore.shared.quickGridCount` 读到的那份缓存 —— 种子导入走的是
            // `BackupStudio.restore`，它**不写设置类键**，于是 App 首次读到的默认值生效前，
            // 这一轮渲染拿到的是 0。显式写一次，让截图与真实首装一致。
            DB.store.setInt("kf_quick_grid", 6)
            try? raw.write(to: done)
            CredentialOrg.notifyLog.error("SeedImporter: 导入成功 新增\(result.imported) 覆盖\(result.overwritten)")
        } catch {
            CredentialOrg.notifyLog.error("SeedImporter: 导入失败 \(String(describing: error), privacy: .public)")
        }
    }
}
