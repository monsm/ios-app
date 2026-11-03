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
                st.firmware = "1.4.2"
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
