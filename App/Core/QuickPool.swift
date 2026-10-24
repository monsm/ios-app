// 905 快捷格"十选六"池 + 1047 常用动作排前 + 921「再开一次」格。
//
// 两件事共用一份数据源，避免出现"格子里的顺序"和"统计说谁常用"两套真相。
//
// 905 的原话是"四选十"。这里把池子做成**真实存在的去处**：原先十个是设备页现状那六格 +
// 四个 App 里**已经能到达的真实页面** (备份与恢复 / 告警中心 / 固件升级 / 家政与维保，
// 分别从设置页与 Sheets 的既有入口可达 —— 逐个 grep 过构造点)，默认选中现状那六个
// —— 也就是**不改变任何人现在看到的界面**。921 后来加第 11 项「再开一次」：
// 点按不推开新页，而是切到凭证 Tab 并定位星标/最高频凭证 (载荷走 577 深链同一套)。
// 池子里每一项都对应一个真视图；没有为凑十格而新造的假入口。
//
// 1047 ("使用满 30 天后快捷格首格自动推荐最常用动作") 的完整口径:
// · 静默学习: 从第一次点快捷格起本机记次数 (只存本机, 绝不上传); 点一次 +1。
// · 满 30 天 (口径 30×86400s, 与仓内其它"30 天"一致) 且从没手动动过开关 →
//   首格自动推荐最常用的一格, 其余保持用户手选次序。
// · 开关开着 = 全序按次数降序 (平次保序); 手动关掉 = 硬退出: 停止记录 + 清空计数 +
//   排序回用户手选 (kf_quick_smart_set 标记保证"关就是关", 自动首格不再介入)。
import SwiftUI

struct QuickAction: Identifiable, Hashable {
    let id: String
    let icon: String
    let label: String
}

enum QuickPool {
    /// 候选格子 (id 一旦发布就是存储值，改名会把用户已有的 kf_quick_ids 打空 → 只能加不能改)
    /// 921「再开一次」是后来加的第 11 项：它不推开新页，点按 = 切凭证 Tab 并定位星标/最高频那条。
    static let all: [QuickAction] = [
        QuickAction(id: "addPwd",   icon: "plus.rectangle.on.rectangle", label: "添加密码"),
        QuickAction(id: "otp",      icon: "clock.badge.questionmark",    label: "临时密码"),
        QuickAction(id: "syncTime", icon: "clock.arrow.circlepath",      label: "校准时间"),
        QuickAction(id: "addFp",    icon: "touchid",                     label: "录指纹"),
        QuickAction(id: "studio",   icon: "wrench.and.screwdriver",      label: "钥匙工坊"),
        QuickAction(id: "again",    icon: "arrow.counterclockwise",      label: "再开一次"),   // 921
        // ↓ 四个是从本页其它位置也到达得到的真实页面，不是新造的入口
        QuickAction(id: "backup",   icon: "archivebox",                  label: "备份与恢复"),
        QuickAction(id: "alarm",    icon: "bell.badge",                  label: "告警中心"),
        QuickAction(id: "firmware", icon: "memorychip",                  label: "固件升级"),
        QuickAction(id: "care",     icon: "house.and.flag",              label: "家政与维保"),
    ]
    /// 默认选中现状那六格 = 与旧版观感一致
    static let defaultIds = ["addPwd", "otp", "syncTime", "addFp", "studio"]

    static let idsKey = "kf_quick_ids"
    static let freqKey = "kf_quick_freq"
    static let smartKey = "kf_quick_smart"
    static let sinceKey = "kf_quick_since"            // 1047: 首次点击时刻 (Unix 秒)
    static let smartSetKey = "kf_quick_smart_set"     // 1047: 用户手动动过开关的标记 (关掉就不再自动学习)

    /// 读池子: 白名单过滤 + 去重 + 保用户排的序; 空了或全是不认识的 id → 回退默认六格
    static var selected: [QuickAction] {
        let stored = DB.store.get([String].self, idsKey) ?? defaultIds
        var seen = Set<String>()
        let picked = stored.filter { seen.insert($0).inserted }
            .compactMap { id in all.first { $0.id == id } }
        return picked.isEmpty ? all.filter { defaultIds.contains($0.id) } : picked
    }
    static func setSelected(_ ids: [String]) {
        let clean = all.filter { ids.contains($0.id) }.map { $0.id }
        if clean.sorted() == defaultIds.sorted() && clean.count == defaultIds.count {
            DB.store.remove(idsKey)          // 与默认等价就删键，不给备份/统计留等价副本
        } else {
            DB.store.set(idsKey, clean)
        }
    }

    static var smartFirst: Bool { DB.store.getBool(smartKey) }     // 默认关
    static func setSmartFirst(_ v: Bool) {
        DB.store.set(smartKey, v)
        DB.store.set(smartSetKey, true)   // 手动动过开关 = 从此由用户说了算, 1047 的自动首格不再介入
    }
    /// 记录中: 从没动过开关 = 静默学习 (1047 的"满 30 天"需要 30 天前的数据);
    /// 手动关过 = 硬退出 (开关文案承诺"停止记录并清空计数", 这里兑现)。
    static var recordingOn: Bool { !DB.store.getBool(smartSetKey) || smartFirst }
    /// 1047: 自首次点击起满 30 天。口径 30×86400s, 与仓内其它 "30 天" (校时/固件复提醒) 一致。
    static var reached30d: Bool {
        guard let since = DB.store.get(Double.self, sinceKey) else { return false }
        return Date().timeIntervalSince1970 - since >= 30 * 86400
    }

    /// 频次表: 键 → 本机累计点击数
    static var counts: [String: Int] { DB.store.get([String: Int].self, freqKey) ?? [:] }
    static func recordTap(_ id: String) {
        guard recordingOn else { return }
        if DB.store.get(Double.self, sinceKey) == nil {
            DB.store.set(sinceKey, Date().timeIntervalSince1970)   // 1047: 学习起点 = 第一次真的用了快捷格
        }
        var c = counts
        c[id, default: 0] += 1
        DB.store.set(freqKey, c)
    }
    static func clearCounts() { DB.store.remove(freqKey) }

    /// 排给设备页看的顺序, 三档 (1047):
    /// · 开关开 = 点过的按次数降序排前, 次数相同或没点过的保持原序 (稳定排序, 不做预测);
    /// · 开关关但从未手动调整过 ∧ 满 30 天 = 只把最常用的一格提到首格, 其余保序;
    /// · 其余 = 用户选的池子原序。
    static func ordered() -> [QuickAction] {
        let picked = selected
        let c = counts
        if smartFirst {
            return picked.enumerated()
                .sorted { a, b in
                    let ca = c[a.element.id] ?? 0, cb = c[b.element.id] ?? 0
                    if ca != cb { return ca > cb }
                    return a.offset < b.offset          // 平次保序: 稳定, 不会每次刷新换队
                }
                .map { $0.element }
        }
        guard !DB.store.getBool(smartSetKey), reached30d,
              let top = picked.max(by: { (c[$0.id] ?? 0) < (c[$1.id] ?? 0) }),
              (c[top.id] ?? 0) > 0 else { return picked }
        var out = picked.filter { $0.id != top.id }
        out.insert(top, at: 0)
        return out
    }

    /// 921「再开一次」的目标: 星标密码 > 星标指纹 > 921 高频推断 (临时码, 标"约")。
    /// 返回 (显示名, 深链载荷); 一个都没有 = nil —— 调用方给"先去点亮星标"的空态, 不替用户猜一条。
    /// 354: 已归档的条目不再作为直达目标 —— 收起的东西不许从快捷入口"复活"
    static func repeatTarget(_ mac: String) -> (name: String, nav: String)? {
        let stars = CredentialOrg.stars(mac)
        if let p = DB.listPwds(mac).first(where: { stars.contains($0.alias) && !CredentialOrg.isArchived(mac, "pwd", $0.alias) }) {
            return (CredentialOrg.displayPwd(p), "pwd:" + String(p.alias))
        }
        if let f = DB.listFps(mac).first(where: { stars.contains(100000 + $0.batch) && !CredentialOrg.isArchived(mac, "fp", $0.batch) }) {
            return (f.name.isEmpty ? "指纹 #" + String(f.batch) : f.name, "fp:" + String(f.batch))
        }
        if let s = CredentialOrg.starSuggestion(mac), s.hasPrefix("p"),
           let alias = Int(s.dropFirst()),
           let p = DB.listPwds(mac).first(where: { $0.alias == alias && !CredentialOrg.isArchived(mac, "pwd", $0.alias) }) {
            return (CredentialOrg.displayPwd(p) + " (约)", s)
        }
        return nil
    }
}

/// 目标视图集中一处，免得 DeviceHomeView 里散落十个 `if`
/// 十个目标视图的 init 都是主 actor 的 (View 协议隔离), 所以这一枚也必须在主 actor 上。
@MainActor
@ViewBuilder
func quickDestination(_ id: String) -> some View {
    switch id {
    case "addPwd":   NavigationStack { AddKeyPage() }
    case "otp":      SafemodeIntroView(mode: "otp")
    case "syncTime": SyncTimeView()
    case "addFp":    NavigationStack { AddFingerPage() }
    // ═══ 2026-10-24 功能点归位修正 ═══
    //
    // 这三行原来指向 **2026-10-21 之前的老页面**：
    //   StudioPage     → 旧「钥匙工坊」（新页是 KeysPage）
    //   BackupView     → 旧「备份」（新页是 BackupPage，注释写明"全新重写"）
    //   AlarmCenterView→ 旧「告警中心」（新页是 AlarmsPage，同上）
    //
    // 后果：用户从设备页快捷格点「钥匙工坊 / 备份 / 告警」，
    // 进到的是**已经被替代的旧界面** —— 两套页面并存，旧的那套还在被入口引用。
    // 这是"页面被合理归位"最典型的反例：同一个功能点有两个实现，入口指向报废的那个。
    //
    // 三个旧文件零其他引用（全仓只有这里和它们的定义行），因此这条改完之后
    // 它们是**真正的死代码**，已同步删除（见同批提交）。
    case "studio":   KeysPage()
    case "backup":   BackupPage()
    case "alarm":    Text("告警功能已移除")   // 2026-10-24: AlarmsPage 已删
    case "firmware": FirmwarePage()
    case "care":     Text("保养功能已随原版对照精简移除")   // 2026-10-24
    case "again":    Text("「再开一次」在设备页长按编辑或直接点按, 不需要新页面")   // 921 再开一次
    default:         Text("这个快捷入口对应的页面已不存在，请到设置-外观里重新选择")
    }
}

