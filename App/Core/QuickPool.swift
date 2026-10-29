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
        QuickAction(id: "studio",   icon: "wrench.and.screwdriver",      label: "凭证工坊"),
        QuickAction(id: "again",    icon: "arrow.counterclockwise",      label: "再开一次"),   // 921
        // ↓ 四个是从本页其它位置也到达得到的真实页面，不是新造的入口
        QuickAction(id: "backup",   icon: "archivebox",                  label: "备份与恢复"),
        // 2026-10-29：页面型能力 —— 默认不展示（defaultIds 不含），用户到「设置→外观→快捷格」自查勾选。
        // 加它们是因为「设置→锁段」7 项里没有其它直达路径；这三项都是既有 Destination，不新增任何东西。
        QuickAction(id: "tailgate", icon: "figure.walk.arrival", label: "防尾随"),
        QuickAction(id: "safemode", icon: "lock.rotation",       label: "安全模式"),
        QuickAction(id: "dfu",      icon: "arrow.up.circle",     label: "固件升级"),
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
        // 2026-10-30 性能：原来对每个存储 id 都 `all.first { $0.id == id }`（O(stored × all)），
        // 而本属性在设置页是**逐格**调用的（ForEach 里每行一次）—— 11 格 × 11 次线性查找。
        // 一次建表后按 id 取。
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let picked = stored.filter { seen.insert($0).inserted }.compactMap { byID[$0] }
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
        let stars: Set<Int> = []   // 2026-10-26: 星标已删
        return nil
    }
}

/// 目标视图集中一处，免得 DeviceHomeView 里散落十个 `if`
/// 十个目标视图的 init 都是主 actor 的 (View 协议隔离), 所以这一枚也必须在主 actor 上。
@MainActor
@ViewBuilder
func quickDestination(_ id: String) -> some View {
    switch id {
    case "addPwd":   PwdStudio(embedded: true)
    // 2026-10-28 修（**入口指错**）：原来这里给的是 `SafemodeIntroView(mode: "otp")` ——
    // 那是「临时密码介绍」页（纯说明文字），用户在设备页点「临时密码」快捷格，
    // 看到的是一段介绍、没有任何生成入口。
    // APK `OpendevicePage.imgClick(3)` → `queryOtpStatus` → 命中后直接 `page-otpgenerate`，
    // 也就是**直达生成页**。这里改成 `TempCodeStudio()`（与凭证页 StudioHome 的 sheet 同一个视图），
    // 它自带 `@Environment(\.dismiss)`，作为 NavigationLink 目的地压栈后可正常返回。
    case "otp":      TempCodeStudio()
    case "syncTime": SyncTimeView()
    case "addFp":    FpStudio(embedded: true)
    case "studio":   StudioHome(embedded: true)
    case "backup":   BackupView(embedded: true)
    case "tailgate": TailgateView()
    case "safemode": SafemodeIntroView()
    case "dfu":      DFUView()
    case "again":    Text("「再开一次」在设备页长按编辑或直接点按， 不需要新页面")   // 921 再开一次
    default:         Text("这个快捷入口对应的页面已不存在，请到设置-外观里重新选择")
    }
}

