// 包6 凭证列表·批量·流转 — 本地组织层 (纯本地数据, 不碰协议命令集, 不读 vendor/)
// 新增表全部 kf_ 前缀, 与既有 kf_ledger_ / kf_members 同库, 不进备份包 schema (492 留包8 勾选):
//   kf_chist_<mac>        487/488 版本快照 (保存自动快照 + 自动还原点置顶标记)
//   kf_cbin_<mac>        497-506 回收站 (来源过滤 / 剩余天数 / 彻底删除)
//   kf_cqueue_<mac>      365 下发状态队列 (本地容错步条: 待下发→已下发→锁端确认, 不改协议层)
//   kf_cstar_<mac>       526/921 置顶星标 + 921 高频标记
//   kf_calert_<mac>      359 三档预警设定
//   kf_clists_<mac>      527 命名智能列表
//   kf_cseq_<mac>        182/352 拖拽排序序
//   kf_ccred_prefs       355/914 双视图分组与四维排序的持久化
//   kf_calias_display    919 别名显示切换 (全局)
//   kf_csearch_hist      531 最近搜索词
//   kf_cbin_reclaim_days 497 回收站保留天数 (设置可改)
// 展示层语义: 一次性/周期/暂停锁端协议未定义 (CAPABILITY §4) — 全部按时间窗推断, 标注"约"。
import Foundation
import SwiftUI
@preconcurrency import UserNotifications   // 通知中心对象是系统侧线程安全的, SDK 未标 Sendable
import os   // 2026-10-13 对抗式排查: 凭证通知排期失败要能查 (原先 try? 静默吞掉)
// 502 彻底删除的统一门槛口 (guardedPurge) 要问生物识别, 所以本文件也吃这一套系统框架;
// 与 AccessibilityKit 的 AuthKit (877) 同源, 那边不复用的理由写在 guardedPurge 上方。
import LocalAuthentication

struct CredAlert: Codable {
    var day: Bool = false
    var d3: Bool = false       // 930: 到期前 3 天
    var d1: Bool = false       // 930: 到期前 1 天
    var h24: Bool = false
    var h2: Bool = false
    init(day: Bool = false, d3: Bool = false, d1: Bool = false, h24: Bool = false, h2: Bool = false) {
        self.day = day; self.d3 = d3; self.d1 = d1; self.h24 = h24; self.h2 = h2
    }
    enum CodingKeys: String, CodingKey { case day, d3, d1, h24, h2 }
    /// 930 新增 d3/d1 之后, 老包 `kf_calert_` 的 JSON 里没有这两个键。合成解码器遇到**缺键**是抛错,
    /// 一抛整组开关会被 `?? CredAlert()` 吞成"全关" —— 用户已经开好的 7 天/24 小时档会静默消失。
    /// 所以显式解码: 缺键 = 那一档关, 不牵动别的档 (与恢复包"缺字段=不动本机"同一条纪律)。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Bool.self, forKey: .day)) ?? false
        d3 = (try? c.decodeIfPresent(Bool.self, forKey: .d3)) ?? false
        d1 = (try? c.decodeIfPresent(Bool.self, forKey: .d1)) ?? false
        h24 = (try? c.decodeIfPresent(Bool.self, forKey: .h24)) ?? false
        h2 = (try? c.decodeIfPresent(Bool.self, forKey: .h2)) ?? false
    }
}

// ================= 组织层 =================
enum CredentialOrg {
    /// 2026-10-13 对抗式排查: 凭证通知排期失败的可见出口。
    /// 原先 `Task { try? await UNUserNotificationCenter…add(req) }` 把失败静默吞掉, 界面照显"已排程"。
    /// 凭证到期预警是这条链唯一的提醒出口, 静默失败 = "说要提醒但没人提醒"。
    static let notifyLog = Logger(subsystem: "com.aapk.OfflineLock", category: "credentialNotify")

    static func alertKey(_ mac: String, _ kind: String, _ key: Int) -> String { "kf_calert_\(mac)_\(kind)_\(key)" }
    static func seqKey(_ mac: String) -> String { "kf_cseq_" + mac }

    // ---------- 时间解析 (台账串 "yyyy-MM-dd HH:mm:ss", 本地时区) ----------
    static let credFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")   // 这一份既格式化也**反解析**台账串，必须钉公元历 (原 zh_CN 对纯数字格式没起作用，反而跟着系统历法跑)
        return f
    }()
    static func parseLocal(_ s: String) -> Date? {
        let t = String(s.prefix(19))
        return credFormatter.date(from: t)
    }
    /// 永久有效期 (2118) 返回 nil — 不参与到期排序与预警
    static func expiryDate(_ p: LedgerPwd) -> Date? {
        guard !p.to.hasPrefix("2118") else { return nil }
        return parseLocal(p.to)
    }
    static var nowSec: Double { Date().timeIntervalSince1970 }

    static func quota(_ mac: String) -> Int { DB.store.getInt("kf_ccred_quota", 10) }

    // ---------- 489 修订着色 diff (删除红/新增绿/修改黄, 逐字段对齐) ----------
    struct Diff: Identifiable {
        var id: String { label }
        let label: String
        let old: String
        let neu: String
        var kind: String {
            if old.isEmpty { return "add" }
            if neu.isEmpty { return "del" }
            return old == neu ? "same" : "mod"
        }
    }




    /// 502 彻底删除的**统一门槛**: 单条与清空回收站走同一个函数, 两条路的深浅必须一样。
    /// 为什么收在一处 (与 323 双签同型的那次整改同一条理由): 原先「清空」自己写了半套生物识别 +
    /// 兜底弹窗, 「单条」只有一遍 confirmationDialog, 两套深浅各说各话 —— 门槛分叉就是漏问的开始。
    /// 口径:
    ///  · 设备有可用的 Face ID / Touch ID ⇒ 先刷, **通过即执行** commit, 不再多问一句;
    ///  · 没录生物 / 系统判不可用 / 刷失败 ⇒ 把**同一个** commit 交回调用方, 由
    ///    `onDeniedPresentFallback` 决定 UI 怎么问双确认 (confirmDestructive 或 confirmationDialog 都行),
    ///    用户确认之后才执行。
    /// fail-closed: 「没法刷脸」不等于放行 —— 那一支必须过 UI 的第二问。
    /// commit 落的只有 purgeBin / saveBin 这一条裸执行路, 门槛与执行因此分得开也查得清。
    /// ⚠ 为什么不走 AccessibilityKit 的 `AuthKit.verifyBiometric` (877): 那份把 localizedReason
    ///   写死成代替密码那句, 也没有 denied 分支 —— 502 要说的是彻底删除 N 条, 且未通过时得有第二条路。
    // 整条门槛在主 actor 上: 它只由界面上的删除按钮触发, 两支回调也都是界面动作。
    // 两个闭包参数标 @MainActor 之后**本身即 Sendable**, 于是 evaluatePolicy 的 @Sendable reply
    // 可以合法地把它们转交给主 actor —— 这是 Swift 6 里跨回调边界的原生写法。
    @MainActor
    /// 501/349 成员删除: 名下凭证随成员入回收站 (同一个 `batchId`, 可整组还原)
    /// D-152a (2026-10-11 拍板 方案③): 弹窗当场选「只移除档案 / 连锁端一起收回」, 默认第一项。
    ///  · revokeLocks = false: 只动本机台账, 整组可还原 (501); 锁里那些指纹与密码仍然有效, TA 照旧能开门。
    ///  · revokeLocks = true: 每条再排 365 队列的 `del_pwd`/`del_fp` —— 与 629 逐条停用、353 批量停用
    ///    走的是同一条现成队列, 到场连接后真正生效, 没有新数据面。
    ///    ⚠ 指纹在锁端删掉就无法远程补录 (670), 还原时对指纹只剩本机记录 —— 这句话必须和选择写在同一屏,
    ///    两处弹窗都是这么写的。
    /// 返回本次排上锁端删除的条数: 界面按实数报, 不写死一句"已删除"。
    /// 删除成员时的级联：把名下凭证移入回收站，并（可选）安排锁端撤销。
    ///
    /// 2026-10-27 审核修复 (AUDIT-D D-57)：`revokeLocks` 原先**只 `queued += 1`，什么都不排** ——
    /// 报告说 UI 因此告诉用户「已排 N 条，连接后生效」，那是**安全承诺级别的假话**。
    /// 而且那两个 `var cp = p` 副本算完就丢（本意应是"清掉 owner 后写回"，实际没写）。
    ///
    /// 现在的处置（不假装有队列）：
    ///   · 本机侧：凭证照旧移入回收站（`DB.delPwd`/`DB.delFp` 已在做）
    ///   · 锁端：**不排队**，返回值恒为 0；调用方 UI 必须如实说「锁端凭证仍在，需要时手动删除」
    /// 真要实现队列得先有：持久化队列 + 连接时消费 + 失败重试 + 冲突处理 —— 那是独立功能，
    /// 不是这一条能顺手补上的。留假计数比不留更危险（用户以为已经处理了）。
    @discardableResult
    static func cascadeBinMember(_ mac: String, _ memberID: String, revokeLocks: Bool = false) -> Int {
        for p in DB.listPwds(mac).filter({ $0.owner == memberID }) {
            DB.delPwd(mac, p.alias)
        }
        for f in DB.listFps(mac).filter({ $0.owner == memberID }) {
            DB.delFp(mac, f.batch)
        }
        // revokeLocks 保留形参（调用方还在传），但当前**不做任何锁端排队** ——
        // 见上方注释：没有队列基础设施，返回真数才是诚实的。
        _ = revokeLocks
        return 0
    }
    /// 501/263 删除成员预告: 名下将入回收站的凭证清单 (跨锁合计)。
    /// 两处「删除成员」弹窗共用这一份, 免得同一条预览各写一遍; 锁名一律走 LockArchive.displayName (769 口径)。
    static func memberCredentialPreview(_ memberID: String) -> [String] {
        var out: [String] = []
        for kc in DB.keychains() {
            let lockName = LockArchive.displayName(kc)
            for p in DB.listPwds(kc.mac).filter({ $0.owner == memberID }) {
                out.append("密码 #" + String(p.alias) + " · " + lockName)
            }
            for f in DB.listFps(kc.mac).filter({ $0.owner == memberID }) {
                out.append("指纹「" + f.name + "」· " + lockName)
            }
        }
        return out
    }
    /// 504 还原即重新下发: 在用 (未过期) 密码还原后并入队, 由 UI 询问"立即重新下发"。
    /// 返回补进提示的那半句 (第一百五十四批): 排没排上、为什么没排，界面要说得出来，
    /// 不能一律"已还原" —— 锁上那条没跟着变，用户拿恢复后的码去开门会吃闭门羹。

    /// 启动清理: 全锁回收站 497 保留期巡检 (LockKeeperApp.onLaunch 调用)

    // ---------- 347/348/349/357 批量本地操作 (下发部分只入队, UI 标注本地意图) ----------
    /// 348 统一延期: 本地改写所选过期字段并留变更清单 (逐条入队, 到场后统一补发)
    /// 批量延期。2026-10-27 (D-58)：同 batchDisable —— 找不到的条目如实返回，不静默跳过。
    static func batchExtend(_ mac: String, _ aliases: [Int], _ from: String, _ to: String)
        -> (done: [Int], failed: [Int]) {
        var out: [Int] = []
        var failed: [Int] = []
        for a in aliases {
            guard DB.ledger(mac).pwds.contains(where: { $0.alias == a }) else {
                failed.append(a)
                continue
            }
            DB.setPwdPeriod(mac, a, from, to)
            out.append(a)
        }
        return (out, failed)
    }
    /// 357 前缀批量备注
    // 【保留未接 2026-10-29】批量给多条凭证加同一个前缀备注（用户 B1 未选，保留待接：凭证页多选菜单可挂）
    static func batchPrefixNote(_ mac: String, pwdAliases: [Int], fpBatches: [Int], prefix: String) -> Int {
        var n = 0
        var l = DB.ledger(mac)
        for i in l.pwds.indices where pwdAliases.contains(l.pwds[i].alias) && !(l.pwds[i].note.hasPrefix(prefix)) {
            l.pwds[i].note = prefix + l.pwds[i].note; n += 1
        }
        for i in l.fps.indices where fpBatches.contains(l.fps[i].batch) && !(l.fps[i].note.hasPrefix(prefix)) {
            l.fps[i].note = prefix + l.fps[i].note; n += 1
        }
        DB.saveLedger(mac, l)
        return n
    }
    /// 353 批量停用: 所选过期/老旧项本地移除并入回收站, 锁端删除入队
    /// 批量停用：把选中的密码/指纹移入回收站（同一批次，可整组还原）。
    ///
    /// 2026-10-27 审核修复 (AUDIT-D D-58)：原先 `guard ... else { continue }` **静默跳过**
    /// 找不到的条目，只返回成功数 —— 用户看到「已停用 8 条」却不知道有 2 条根本没动
    /// （可能是别处已经删了、或台账里编号对不上）。
    /// 现在返回 (done, failed)：failed 是"选中了但没找到"的编号，UI 必须如实报出来。
    static func batchDisable(_ mac: String, pwdAliases: [Int], fpBatches: [Int])
        -> (done: Int, failedPwds: [Int], failedFps: [Int]) {
        var n = 0
        var failedPwds: [Int] = []
        var failedFps: [Int] = []
        let batchId = UUID().uuidString   // 353: 一次批量停用 = 一个批次, 回收站里可整组还原
        for a in pwdAliases {
            guard DB.ledger(mac).pwds.contains(where: { $0.alias == a }) else {
                failedPwds.append(a)   // D-58：找不到就记下来，不静默跳过
                continue
            }
            DB.delPwd(mac, a)
            n += 1
        }
        for b in fpBatches {
            guard DB.ledger(mac).fps.contains(where: { $0.batch == b }) else {
                failedFps.append(b)
                continue
            }
            DB.delFp(mac, b)
            n += 1
        }
        return (n, failedPwds, failedFps)
    }

    // ---------- 524/526/528 计数与三态 ----------
    static func typeCounts(_ mac: String) -> (all: Int, pwd: Int, fp: Int, otp: Int) {
        let pwds = DB.listPwds(mac), fps = DB.listFps(mac)
        return (pwds.count + fps.count, pwds.count, fps.count, DB.otpStatus(mac)?.on == true ? 1 : 0)
    }
    static func pwdState(_ p: LedgerPwd) -> Int {
        // 0 进行中 / 1 已排期 / 2 已过期 (按时间窗推断, 一次性语义锁端未定义故不区分)
        if let to = expiryDate(p), to.timeIntervalSinceNow <= 0 { return 2 }
        if let f = parseLocal(p.from), f.timeIntervalSinceNow > 0 { return 1 }
        return 0
    }



    // ---------- 359 三档预警 (本地通知; 2 小时档做 App 内提醒行, 7 天/24 小时档排程) ----------
    static func alert(_ mac: String, _ p: LedgerPwd) -> CredAlert {
        DB.get(CredAlert.self, alertKey(mac, "pwd", p.alias)) ?? CredAlert()
    }
    static func saveAlert(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        DB.setCodable(a, alertKey(mac, "pwd", p.alias))
    }
    /// 926/930 替代: 7 / 3 / 1 天 + 24 / 2 小时**都**排本地通知, 另加"到期时"一条。
    /// 原 359 把 2 小时档做成"只插列表提醒行, 不排通知"(详情页卡片上写着这句话);
    /// 926/930 判 ❌ 后拍板按替代执行 —— 替代栏原话是"到期前 2 小时与到期时各发本地通知"。
    /// 排程扩到六条, 列表提醒行 (dueSoonPwds) **照旧保留**: 前台多一处提示不是坏事。
    static func scheduleAlerts(_ mac: String, _ p: LedgerPwd, _ a: CredAlert) {
        let c = UNUserNotificationCenter.current()
        let id = "c6.alert.\(mac).p\(p.alias)"
        c.getPendingNotificationRequests { reqs in
            let stale = reqs.map(\.identifier).filter { $0 == id || $0.hasPrefix(id + ".") }
            if !stale.isEmpty { c.removePendingNotificationRequests(withIdentifiers: stale) }
        }
        // "到期时"不看单档开关: 开了任何一档 = 在意这条凭证的到期, 到点本身最该说话。
        let any = a.day || a.d3 || a.d1 || a.h24 || a.h2
        guard let to = expiryDate(p), any else { return }
        let name = displayPwd(p)
        // 天数档是**日历日** ⇒ 走 WeekCal.shifted; 小时档说的是"还有 N 小时" = 时长。
        // 两种口径在这里不是一回事 (§10.33), 混用会让 -1 天那条在夏令时切换日多/少一小时。
        func dayTier(_ on: Bool, _ k: Int, _ suf: String, _ tail: String) {
            if on {
                addCalendar(id: id + suf, date: WeekCal.shifted(to, days: -k),
                            title: "密码临期", body: "\(name) 距到期还有 \(k) 天。" + tail)
            }
        }
        dayTier(a.day, 7, ".d7", "记得续期或停用。")
        dayTier(a.d3, 3, ".d3", "")
        dayTier(a.d1, 1, ".d1", "明天就失效了。")
        if a.h24 {
            addCalendar(id: id + ".h24", date: to.addingTimeInterval(-86400),
                        title: "密码临期", body: "\(name) 距到期不足 24 小时。")
        }
        if a.h2 {
            addCalendar(id: id + ".h2", date: to.addingTimeInterval(-7200),
                        title: "密码临期", body: "\(name) 距到期还有 2 小时。")
        }
        addCalendar(id: id + ".t0", date: to, title: "已到期",
                    body: "\(name) 到期了, 锁端到这个时刻后不再放行这条凭证。")
    }

    /// 930 凭证 Tab 角标: 近 7 日内到期的条数。
    /// 与 363 月历格、dueSoonPwds 同源同一把尺 (expiryDate), 不另算第二套; 长期有效 (2118) 与归档条不计。
    static func expiringSoonCount(macs: [String], within days: Int = 7) -> Int {
        let limit = nowSec + Double(days) * 86400
        var n = 0
        for mac in macs {
            for p in DB.listPwds(mac) {
                if let to = expiryDate(p) {
                    let t = to.timeIntervalSince1970
                    if t >= nowSec && t <= limit { n += 1 }
                }
            }
        }
        return n
    }
    private static func addCalendar(id: String, date: Date, title: String, body: String) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = WeekCal.gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        // 2026-10-13 对抗式排查: 原写 `Task { try? await … }` —— 排期失败被静默吞掉,
        // 而界面照样显示"已排程/已设定"。凭证到期预警是这条链唯一的提醒出口, 静默失败
        // 等于"账单说要扣钱但没人扣"。改成 catch 里写 os 日志 (authFail/log 之外唯一可见出口)。
        Task {
            do { try await UNUserNotificationCenter.current().add(req) }
            catch { CredentialOrg.notifyLog.error("凭证通知排期失败 id=\(id, privacy: .public) err=\(String(describing: error), privacy: .public)") }
        }
    }
    /// App 内 2 小时档: 到期前 2 小时且开了 h2 的条 (设备 Tab Hero 卡下插提醒行)
    /// 359: 提醒行点按要跳最近一条的详情 —— 名单与计数必须同源同一个 filter, 抽出来共用
    static func dueSoonPwds(_ mac: String) -> [LedgerPwd] {
        let soon = nowSec + 2 * 3600
        return DB.listPwds(mac).filter { p in
            if let to = expiryDate(p) {
                let a = alert(mac, p)
                return a.h2 && to.timeIntervalSince1970 <= soon && to.timeIntervalSince1970 >= nowSec - 3600
            }
            return false
        }
    }

    // ---------- 358/505 整理建议中心 ----------
    struct Advice: Identifiable {
        let id: String
        let title: String
        let sub: String
        let icon: String
        let action: String   // "expired" / "dups" / "noowner" / "bin" / "memberExpired" (471)
    }


    // ---------- 361 停用原因回溯 (逐条存, 由 313 的必填原因采集) ----------
// 台账在停用后就没有这条凭证了, 详情卡无从打开。
// 2026-10-27 审核修复 (AUDIT-B 2.8 #7)：原注释说「回显落在回收站行 (CredBinView)」，
// 而 `CredBinView` 已随回收站整套移除（全仓 0 命中）。现在回显只落在本页的 Toast。
    struct DisableMark: Codable {
        var label: String    // 313 四选一的中文标签
        var at: Double
        var via: String      // 真实来源只有本机这几条路径, 不写"操作端"这种无法证实的值
    }
    /// 2026-10-27 七轮：`kf_cdisrea_` 停用便签**保留** —— 它是停用功能的一部分，
    /// 不是死键（disableMark / disableMarks / setDisableMark 三处都在用）。
    static func disReasonKey(_ mac: String) -> String { "kf_cdisrea_" + mac }
    static func disableMark(_ mac: String, kind: String, key: Int) -> DisableMark? {
        (DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:])["\(kind):\(key)"]
    }
    static func markDisabled(_ mac: String, kind: String, keys: [Int], label: String, via: String) {
        guard !keys.isEmpty else { return }
        var m = DB.store.get([String: DisableMark].self, disReasonKey(mac)) ?? [:]
        let now = Date().timeIntervalSince1970
        for k in keys { m["\(kind):\(k)"] = DisableMark(label: label, at: now, via: via) }
        // 只留最近 200 条: 这是回溯用的便签, 不是第二本台账, 不该无限增长
        if m.count > 200 {
            let keep = m.sorted { $0.value.at > $1.value.at }.prefix(200)
            m = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        DB.store.setCodable(disReasonKey(mac), m)   // 注意层间参数序相反: store.setCodable(键,值), DB.setCodable(值,键)
    }
    /// 361 回显文案: 停用原因 + 时刻 + 来源路径; 没有标记 (非本 App 停用) 就不编造
    // 【保留未接 2026-10-29】停用原因回显（用户 B1 未选，保留待接：凭证详情页的停用行）
    static func disableMarkText(_ mac: String, kind: String, key: Int) -> String? {
        guard let d = disableMark(mac, kind: kind, key: key) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return "停用原因 \(d.label) · \(f.string(from: Date(timeIntervalSince1970: d.at))) · \(d.via)"   // 361 停用原因
    }

    // ---------- 355/914 组织偏好持久化 ----------
    // kf_ccred_prefs 只有 bit0 是分组模式 (setGroupMode 的掩码一直是这么写的), 其余位留给后续偏好。
    // CredGroupMode 此前是"另一套没人用的表示", UI 拿裸 Int 比 == 1 → 让枚举成为唯一口径。
    /// 2026-10-26 恢复：`CredGroupMode` 在清理四件套时被误删，但 `groupMode` 属性仍依赖它。
    enum CredGroupMode: Int {
        case type = 0     // 按类型分组
        case owner = 1    // 按成员分组
    }


    static var groupMode: CredGroupMode {
        CredGroupMode(rawValue: DB.store.getInt("kf_ccred_prefs", 0) & 1) ?? .type
    }
    static var aliasDisplay: Bool { DB.store.getBool("kf_calias_display", true) }

    // ---------- 182/352 拖拽排序序: "p"/"f" 段各自存 index→元素 数组 ----------
    static func seq(_ mac: String) -> [String: [Int]] {
        DB.get([String: [Int]].self, seqKey(mac)) ?? [:]
    }
    static func setSeq(_ mac: String, _ map: [String: [Int]]) {
        DB.setCodable(map, seqKey(mac))
    }

    // ---------- 531 最近搜索词 ----------
    static func searchHistory() -> [String] {
        DB.get([String].self, "kf_csearch_hist") ?? []
    }
    static func pushSearchHistory(_ q: String) {
        var list = Array(searchHistory().filter { $0 != q }.prefix(4))
        list.insert(q, at: 0)
        DB.setCodable(list, "kf_csearch_hist")
    }
    static func removeSearchHistory(_ q: String) {
        DB.setCodable(searchHistory().filter { $0 != q }, "kf_csearch_hist")
    }

    // ---------- 363 月历到期 (每日格右上角当日到期凭证数) ----------
    // 【保留未接 2026-10-29】月历到期角标（用户 B1 未选，保留待接：凭证页月历视图）
    static func monthDeadlines(_ mac: String, year: Int, month: Int) -> [Date: Int] {
        var cal = WeekCal.gregorian
        cal.timeZone = TimeZone.current
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return [:] }
        var out: [Date: Int] = [:]
        for p in DB.listPwds(mac) {
            guard let to = expiryDate(p),
                  cal.component(.year, from: to) == year,
                  cal.component(.month, from: to) == month,
                  let key = cal.date(from: DateComponents(year: year, month: month, day: cal.component(.day, from: to))) else { continue }
            out[key, default: 0] += 1
            _ = start
        }
        return out
    }
    // 【保留未接 2026-10-29】某天到期凭证列表 —— monthDeadlines 的配套读侧，同日历一起接
    static func dayDeadlines(_ mac: String, _ date: Date) -> [LedgerPwd] {
        let cal = WeekCal.gregorian
        return DB.listPwds(mac).filter { p in
            guard let to = expiryDate(p) else { return false }
            return cal.isDate(to, inSameDayAs: date)
        }
    }


    // ---------- 529 组尾统计 (基于台账推断, 标"约") ----------
    /// 近 N 天使用次数: 临时密码按时间窗命中开门日志 (type2/4) 计, 长期密码只在
    /// 锁内唯一且有归属时计 (推断口径, UI 必须带"约"字)。日志缺失返回 nil (不出行)。
    static func recentUseCount(_ mac: String, pwdAlias: Int, days: Int = 30) -> Int? {
        let p = DB.ledger(mac).pwds.first { $0.alias == pwdAlias }
        guard let p else { return nil }
        let logs = DB.readLogs(mac).filter { $0.type == 2 || $0.type == 4 }
        guard !logs.isEmpty else { return nil }
        var n = 0
        for l in logs {
            let t = ZKProtocol.protoSecondsToUnix(Int64(l.lockTime))
            guard t >= nowSec - Double(days) * 86400 else { continue }
            if p.temp {
                if let f = parseLocal(p.from), let to = parseLocal(p.to),
                   f.timeIntervalSince1970 <= t, t <= to.timeIntervalSince1970 { n += 1 }
            } else if p.owner != nil, l.type == 2 {
                let owned = DB.ledger(mac).pwds.filter { !$0.temp && $0.owner != nil }
                if owned.count == 1 { n += 1 }
            }
        }
        return n
    }

    // ---------- 351 合包导出: 仅凭证分区的最小 AES 信封 (口令由 UI 生成, 不走全量 schema) ----------
    struct CredPackage: Codable {
        var v: Int
        var mac: String
        var lockName: String
        var pwds: [LedgerPwd]
        var fps: [LedgerFp]
        var at: Double
    }
    /// 返回 (Base64 信封文本, 口令)。UI 用 ShareLink 发文本 + 口令单列展示, 不与凭证混排。
    static func exportPackage(_ mac: String, pwdAliases: [Int], fpBatches: [Int], password: String) -> (data: Data, size: Int)? {
        let l = DB.ledger(mac)
        let pwds = l.pwds.filter { pwdAliases.isEmpty || pwdAliases.contains($0.alias) }
        let fps = l.fps.filter { fpBatches.isEmpty || fpBatches.contains($0.batch) }
        guard !pwds.isEmpty || !fps.isEmpty else { return nil }
        let pkg = CredPackage(v: 1, mac: mac, lockName: LockArchive.displayName(DB.keychain(mac) ?? Keychain(mac: mac, skey: "")),
                              pwds: pwds, fps: fps, at: nowSec)
        guard let json = try? JSONEncoder().encode(pkg),
              let text = String(data: json, encoding: .utf8),
              let enc = try? CryptoBox.encryptText(text, password: password) else { return nil }
        return (Data(enc.utf8), pwds.count + fps.count)
    }


    // ---------- 通知分派 (App 前台时由 didReceive 转发; 后台由系统弹出) ----------
    // 只认全仓真实排期过的标识: `c6.alert.<mac>.p<alias>.d7|.d3|.d1|.h24|.h2|.t0` (scheduleAlerts) 与 `c6.monthly`
    // (scheduleMonthlySweep)。旧版里的 c6.expired / c6.center / c6.queue / c6.restore.* 没有任何生产者
    // (grep 全仓仅命中这个函数自身), 属"分派一个不存在的通知" → 删掉而不是留着装作能跳。
    enum Action {
        case locatePwd(mac: String, alias: Int)
        case panel(String)          // 面板名: 与 CredentialsView.consumeCredPanel 同一词表
    }
    static func handleNotificationAction(_ id: String) -> Action? {
        // 标识形如 c6.alert.<mac>.p<alias>.d7 —— MAC 归一化后是纯 hex (无点), 按 "." 切是安全的
        let parts = id.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        if parts.count == 5, parts[0] == "c6", parts[1] == "alert", parts[3].hasPrefix("p"),
           let alias = Int(parts[3].dropFirst(1)), alias > 0, !parts[2].isEmpty {
            return .locatePwd(mac: parts[2], alias: alias)
        }
        if id == "c6.monthly" { return .panel("organize") }   // 文案就写着"到「凭证」点「整理」"
        return nil
    }
    /// 366/1013 通知落地 (此前 handleNotificationAction 零调用 = 点通知什么也不发生)。
    /// 只走已有的两条跳法: 单条凭证定位 (577) 与面板打开; 应用锁没开时值一直挂着, 解锁后才落地。
    @MainActor static func applyNotification(_ a: Action) {
        guard let app = AppState.hostRef else { return }
        // 2026-10-13 对抗式点击审计: 原写直写 `app.tabSelection = 1`, **绕过 377 访客门禁**。
        // 全仓其他编程式跳转 (深链 / 自检黄条 / 粘贴建议条 / 逃生) 走的都是 requestTab ——
        // 访客通道开着时凭证/设置两个 Tab 根本**不进层级树**, 直写 tabSelection 会让系统落到一个
        // 看不见的 Tab, 用户以为点了通知没反应。改走 requestTab (访客时它只会挂起 pending)。
        app.requestRoute(.credentials)
        switch a {
        case .locatePwd(let mac, let alias):
            if !mac.isEmpty, DB.keychain(mac) != nil { app.select(mac) }   // 陌生 MAC 不改当前锁
            app.pendingCredNav = "pwd:\(alias)"
            app.pendingCredNavMac = mac
        case .panel(let p):
            app.pendingCredPanel = p
        }
    }

    // ================= 包5 凭证工坊辅助 (纯本地推断, 不新增协议命令) =================
    // 展示层语义纪律: 锁端一次性/周期/暂停未定义 (CAPABILITY §4), 所有推断值 UI 必须带"约"字。

    // ---------- 304 全库重复拦截 ----------
    static func duplicatePwdValues(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        DB.listPwds(mac).filter { $0.pwd == value && $0.alias != excluding }
    }
    /// 跨锁同值 (304 "全库"): 只报**其它锁**的显示名 (去重)。
    /// 旧版 `duplicatePwdValuesAnyLock` 返回 [LedgerPwd] 却不带 mac —— 调用方拿到条目也说不出是哪把锁,
    /// 还把当前锁的其它别名一起算进来, 与上面的同锁检查重复计数。改成直接给一句警告需要的信息。
    static func duplicatePwdLockNames(_ value: String, excludingMac: String) -> [String] {
        guard !value.isEmpty else { return [] }
        var names: [String] = []
        for k in DB.keychains() where k.mac != excludingMac {
            guard DB.listPwds(k.mac).contains(where: { $0.pwd == value }) else { continue }
            let n = LockArchive.displayName(k)
            if !names.contains(n) { names.append(n) }
        }
        return names
    }
    /// 314 前缀混淆: 同锁内其它密码前 4 位相同, 口头易混淆
    static func prefixConflict(_ mac: String, _ value: String, excluding: Int) -> [LedgerPwd] {
        guard value.count >= 4 else { return [] }
        let pre = value.prefix(4)
        return DB.listPwds(mac).filter { $0.alias != excluding && $0.pwd?.hasPrefix(pre) == true }
    }

    /// 弱口令三条判据 (都可证伪; 不评"强度分"): 少于 6 位 / 全部同一位 / 连续递增递减
    // 【保留未接 2026-10-29】弱口令判据（少于6位/全同位/连续）—— 新密码输入时可用于即时提示
    static func weakReason(_ v: String) -> String? {
        guard !v.isEmpty else { return nil }
        if v.count < 6 { return "少于 6 位" }
        if Set(v).count == 1 { return "全部同一位数字" }
        let digits = v.compactMap { $0.wholeNumberValue }
        if digits.count == v.count, digits.count >= 3 {
            var up = true, down = true
            for i in 1..<digits.count {
                if digits[i] != digits[i - 1] + 1 { up = false }
                if digits[i] != digits[i - 1] - 1 { down = false }
            }
            if up || down { return "连续递增/递减序列" }
        }
        return nil
    }
    static func pwdAgeDays(_ p: LedgerPwd) -> Int? {
        guard p.at > 0 else { return nil }
        // 单位口径：毫秒 —— LedgerPwd.at 写的是 `timeIntervalSince1970 * 1000` (见 CredentialStudio 提交那两处)，先除回秒再算天数。
        return Int(max(0, (nowSec - p.at / 1000)) / 86400)
    }

    // ---------- 307 保存前逐位 diff: 改动位集合 (1 起; 长度变化补 "·" 对齐) ----------
    static func digitDiff(old: String, new: String) -> Set<Int> {
        var ch = Set<Int>()
        let n = max(old.count, new.count)
        for i in 0..<n {
            let a = i < old.count ? old[old.index(old.startIndex, offsetBy: i)] : " "
            let b = i < new.count ? new[new.index(new.startIndex, offsetBy: i)] : " "
            if a != b { ch.insert(i + 1) }
        }
        return ch
    }

    // ---------- 327 租期重叠检测 ----------
    static func overlapWindows(_ mac: String, from: String, to: String, owner: String?, excluding: Int) -> [LedgerPwd] {
        guard let f = parseLocal(from), let t = parseLocal(to) else { return [] }
        return DB.listPwds(mac).filter { p in
            p.alias != excluding &&
            (owner == nil || p.owner == owner) &&
            {
                guard let pf = parseLocal(p.from), let pt = parseLocal(p.to) else { return false }
                return pf < t && f < pt
            }()
        }
    }

    // ---------- 319 重录继承 / 324 冗余横条 ----------
    /// 该成员名下可用指纹数 (0 = 最后一枚 → 删除需双签 323; 冗余横条 324 用全锁口径)
    static func fpCountByOwner(_ mac: String, _ owner: String?) -> Int {
        guard let o = owner else { return 0 }
        return DB.listFps(mac).filter { $0.owner == o }.count
    }
    static func fpCountTotal(_ mac: String) -> Int { DB.listFps(mac).count }

    // ---------- 311/316/320/326/335/333 台账推断统计 (⚠ 全部标"约") ----------
    // 这一族的文案与数据源是**同一份**判据, 不各说一套; 也不许把"约"写成精确:
    // docs/CAPABILITY.md §3 写明 cmd16 日志每条只有 [type][len][idx][lockTime][body],
    // **无 alias / 无指纹批号**这类身份字段 ⇒ "谁用它开的门"只能拿凭证自己的时间窗去框。
    // 约族核对结论: 311/316/320/332 四处 UI 小字与下面这几个函数的口径本就对齐, 本轮不动;
    // 333 原只滤下界 (超窗的旧日志也会命中, 见 firstUse 的补界)、335/326 的小字原把"时间窗推断"
    // 说成"本地计次" —— 这两处已改成与数据源同一句话。
    /// 311 同码引用: 时间窗内用它"开过的门"计数 (无 alias 日志字段, 按时间窗推断, 标"约")
    static func openCountInWindow(_ mac: String, p: LedgerPwd) -> Int {
        guard let f = parseLocal(p.from), let to = parseLocal(p.to) else { return 0 }
        return DB.readLogs(mac).filter { log in
            guard log.type == 2 || log.type == 4 else { return false }
            let t = ZKProtocol.protoSecondsToUnix(Int64(log.lockTime))
            return f.timeIntervalSince1970 <= t && t <= to.timeIntervalSince1970
        }.count
    }
    /// 316 指纹档案统计: 近 30 天 type3 (指纹开门) 日志条数 — ⚠ 日志无指纹身份字段, 只能按锁整体推断, 标"约"
    static func fpUseCount30d(_ mac: String) -> Int {
        let cut = nowSec - 30 * 86400
        return DB.readLogs(mac).filter { l in
            guard l.type == 3 else { return false }
            return ZKProtocol.protoSecondsToUnix(Int64(l.lockTime)) >= cut
        }.count
    }
    /// 320 误识计数: 本地日志 type13 (指纹告警) 出现次数 — ⚠ 锁端语义待实测, 只做展示标"约"
    static func fpAlarmLogCount(_ mac: String) -> Int {
        DB.readLogs(mac).filter { $0.type == 13 }.count
    }

    // ---------- 315/174 指纹命名建议轮播 ----------
    /// 按该成员已录数量给 "成员·手指 (N)" 式建议; 手指序 食指→中指→备用→应急 循环 (315/174)
    /// extra = 轮播额外下标 (录入页同时给出 3 个备选)
    static func fpNameSuggestion(_ mac: String, owner: String?, extra: Int = 0) -> String {
        let who = ownerName(owner)
        let n = (owner.flatMap { fpCountByOwner(mac, $0) } ?? 0) + max(extra, 0)
        let names = ["食指", "中指", "备用", "应急"]
        let pick = names[n % names.count]
        let base = n > 0 ? pick + " (\(n + 1))" : pick
        return who.isEmpty ? "指纹·" + base : who + "·" + base
    }

    /// 331 是否已过本机设定的提前失效时刻。`now` 由调用方给一次、两处提示共用 (顶部提醒条与状态行
    /// 同帧同判据), 不留隐式 Date() —— 隐式取时刻会让同一屏里两条结论各自漂。没设提前量恒 false。
    /// 331 本地提前失效时刻; 滑杆为 0 时就等于锁端到期时刻, 长期有效 (2118) 无到期点 ⇒ nil。
    static func effectiveExpiry(_ mac: String, _ p: LedgerPwd) -> Date? {
        guard let to = expiryDate(p) else { return nil }
        let m = earlyExpireMin(mac, p.alias)
        guard m > 0 else { return to }
        return to.addingTimeInterval(-Double(m) * 60)
    }

    static func isEarlyExpired(_ mac: String, _ p: LedgerPwd, _ now: Date) -> Bool {
        guard earlyExpireMin(mac, p.alias) > 0, let e = effectiveExpiry(mac, p) else { return false }
        return now >= e
    }
    /// 331 详情页状态行的后缀: 设了提前量才给, 没设就空串 (提示语不吹一件没设过的事)。
    static func earlyExpiryNote(_ mac: String, _ p: LedgerPwd) -> String {
        let m = earlyExpireMin(mac, p.alias)
        guard m > 0, let e = effectiveExpiry(mac, p) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return " · 本机提前 " + String(m) + " 分钟 (约 " + f.string(from: e) + ", 锁端未改)"
    }
    static func earlyExpireMin(_ mac: String, _ alias: Int) -> Int {
        DB.store.getInt("kf_cestudy_earlyexp_" + mac + "_" + String(alias), 0)
    }
    static func setEarlyExpireMin(_ mac: String, _ alias: Int, _ m: Int) {
        DB.store.set("kf_cestudy_earlyexp_" + mac + "_" + String(alias), m)
    }

    // ---------- 341/343/346 OTP 独立口令组与静态备份码 (纯本地, 不走锁端) ----------
    struct StudioDraft: Codable {
        var step: Int
        var kind: Int          // 0 密码 / 1 临时码
        var pwd: String
        var permanent: Bool
        var fromISO: String
        var toISO: String
        var owner: String?
        var useTemplate: Bool
        var note: String
        var batch: Int
        var at: Double
    }
    static func draft(_ mac: String) -> StudioDraft? {
        DB.get(StudioDraft.self, "kf_cdraft_" + mac)
    }
    static func saveDraft(_ mac: String, _ d: StudioDraft) {
        DB.setCodable(d, "kf_cdraft_" + mac)
    }
    static func clearDraft(_ mac: String) {
        // 2026-10-14: set(_, Data()) 走 JSONSerialization 必抛 (Data 非 JSON) => 键从未清掉, draft() 仍返回旧草稿。
        DB.store.remove("kf_cdraft_" + mac)
    }

    // ---------- 显示层辅助 (919 别名显示切换: 成员"别名"字段 = relation 备注, 空则回退真名) ----------
    static func ownerName(_ id: String?) -> String {
        guard let id, let m = DB.member(id) else { return "" }
        if aliasDisplay, !m.relation.isEmpty { return m.relation }
        return m.name
    }
    static func displayPwd(_ p: LedgerPwd) -> String {
        if !p.note.isEmpty {
            let s = p.note.split(separator: "·").map { String($0).trimmingCharacters(in: .whitespaces) }.first
            if let s, !s.isEmpty, s.count <= 12 { return s }
        }
        let o = ownerName(p.owner)
        if !o.isEmpty { return "\(o) 的密码 #\(p.alias)" }
        return p.temp ? "临时密码 #\(p.alias)" : "密码 #\(p.alias)"
    }
    /// 到期时刻的界面读法。`2118-01-01 00:00` 是**"永不到期"的哨兵值** (写库与 363/331 那两条判据都用它),
    /// 直接印出来就是"到 2118-01-01"这种把内部哨兵当事实报给用户的话。
    /// 这条判据此前在 `displayPwd` 那侧有一份、在回收站/历史/延期三处界面各有一份, 收成一处。
    /// - Parameter verb: 要不要带"到 "这个前缀; 两段式 ("原来 → 新的") 那侧自己拼动词, 传 false。
    static func expiryLabel(_ to: String, verb: Bool = true, prefix: Int = 10) -> String {
        let head = to.hasPrefix("2118") ? "长期有效" : String(to.prefix(prefix))
        return verb && !to.hasPrefix("2118") ? "到 " + head : head
    }
    /// 918 命名模板 "谁-哪里-何时" 占位建议 (锁端无名称字段, 台账本地展示)
    static func namingTemplate(_ p: LedgerPwd) -> String {
        var who = ownerName(p.owner)
        var where_ = ""
        var when = "长期"
        if let to = expiryDate(p), let f = parseLocal(p.from) {
            when = f.formatted(.dateTime.month().day()) + "-" + to.formatted(.dateTime.month().day())
        }
        if who.isEmpty { who = "未归属" }
        if where_.isEmpty { where_ = "大门" }
        return [who, where_, when].joined(separator: "-")
    }
    static func stateLabel(_ s: Int) -> String {
        switch s {
        case 1: return "已排期"
        case 2: return "已过期"
        default: return "进行中"
        }
    }
}

