// HouseholdRoster.swift —— 家域的本机档案扩展层（旧仓 MemberHub.MemberExt 的 iOS 27 落点）。
//
// 这层干什么：AppModel 的 MemberCard 只带「锁端可证」的字段（称呼 / 角色 / 名下凭证数 / 最近活跃 / 归档）；
//   备注名、emoji 代号、与你的关系、分组标签、家庭便签、紧急联系、紧急管理员、本周主责
//   这些**纯本机**的档案扩展放在这一层（旧仓 kf_member_ext 的语义），不碰协议层，也不碰备份包 schema。
// 数据从哪来：真落盘走 Engine/MemberHub 的 kf_member_ext 与 kf_duty_week（UserDefaults 键值表）。
//   第一次运行没有档案时，用 AppModel.sample 那四位成员的种子当**展示底稿**；一旦写过一次就以落盘值为准。
// 主动作：各屏调 update / setDuty / forget —— 这一层只存不画。
// 边界：角色（MemberCard.role）与归档位仍落在 AppModel.MemberCard 上（那份模型不归本域改）。
import SwiftUI

/// 一位成员的本机档案扩展（对应 Engine MemberExt 的可展示字段）。
struct HHMemberExtras: Hashable {
    var emoji: String = ""
    var remark: String = ""
    var relation: String = ""
    var groupTag: String = ""
    var note: String = ""
    var emergency: String = ""
    var emergencyAdmin: Bool = false
    /// 480 孩子码关怀文案（家人打开的关怀便签）。
    var careText: String = ""
    /// 484 访客欢迎语（归属靠时间推断，展示带「约」）。
    var welcome: String = ""
    /// 468 代管标记（管理员代操作时在停用便签里补一句）。
    var proxy: Bool = false
}

@MainActor
@Observable
final class HouseholdRoster {
    static let shared = HouseholdRoster()

    /// 已落盘的档案表。构造时读一次，之后由 update / forget 维护 ——
    /// 不在 body 里读库（视图求值期间改 @Observable 属性会把 SwiftUI 卷进重算）。
    private var table: [String: HHMemberExtras]
    /// 关系覆盖层。Engine 的 Member.relation 是锁端/备份共用字段；样例成员还没进 kf_members 时
    /// 写进去会静默丢失，所以这里再存一份本机覆盖层（键 = 成员 id）。
    private var relationOverlay: [String: String]
    /// 本周轮值表（键 = "yyyy-Www" → 成员 id）。放在这里是为了改完当帧就刷新；
    /// 落盘仍是 Engine 的 kf_duty_week（MemberHub.dutyThisWeek 读同一份）。
    private var dutyTable: [String: String]
    /// 成员 360 的落点（Dest.memberDetail 不带参数，由来源页先写这里再 push）。
    var focusMember: String?

    init() {
        table = MemberHub.allExt().mapValues(Self.extras(from:))
        relationOverlay = DB.store.get([String: String].self, Self.relationKey) ?? [:]
        dutyTable = DB.store.get([String: String].self, Self.dutyKey) ?? [:]
    }

    // MARK: 读

    func extras(for id: String) -> HHMemberExtras {
        // 2026-11-04（S6 · 02 6.2 点名的假数据）：原来是 table[id] ?? Self.seed[id] ?? HHMemberExtras()。
        // 那份 seed 底稿会**伪装成真实成员档案**（「血压药在玄关第二格」「妈妈 · 手机号见通讯录」），
        // 而它们并不属于任何真实成员：用户第一次打开成员页看到的是别人家的备注。
        // 删掉底稿，缺失就是缺失 —— 空字段由界面如实显示「未填」。
        var e = table[id] ?? HHMemberExtras()
        // 关系是成员的独立字段（Engine Member.relation），不在 MemberExt 里。
        // 优先本机覆盖层（样例成员也存得住），其次锁端成员字段，最后才是种子。
        if let relation = relationOverlay[id], !relation.isEmpty {
            e.relation = relation
        } else if let relation = DB.member(id)?.relation, !relation.isEmpty {
            e.relation = relation
        }
        return e
    }

    func dutyID() -> String? { dutyTable[Self.weekKey()] }

    // MARK: 写（真落盘）

    func update(_ id: String, _ mutate: (inout HHMemberExtras) -> Void) {
        var e = extras(for: id)
        mutate(&e)
        table[id] = e
        persist(id, e)
    }

    func forget(_ id: String) {
        table.removeValue(forKey: id)
        MemberHub.saveExt(id, MemberExt())
    }

    /// 角色与归档位：UI 上落 AppModel.MemberCard（那份模型不归本域改），
    /// 但真值在 Engine 的 kf_member_ext 里也有一份（role / archived）—— 写回一次，免得冷启动后两处各说一套。
    /// 2026-11-04（走查发现 · 过时 TODO）：原文写「成员列表改由 DB.members() + MemberHub.allExt() 驱动时…」
    /// —— 那个时点**已经来了**（`AppModel.reload` 就是 `DB.members().map { … MemberHub.allExt() }`）。
    /// 这两个写回点现在就是唯一入口，不是"将来"。
    func mirrorRole(_ id: String, _ role: MemberCard.Role) {
        var ext = MemberHub.ext(id)
        ext.role = HHPerm.code(role)
        MemberHub.saveExt(id, ext)
    }

    func mirrorArchived(_ id: String, _ archived: Bool) {
        var ext = MemberHub.ext(id)
        ext.archived = archived
        MemberHub.saveExt(id, ext)
    }

    func setDuty(_ id: String?) {
        if let id {
            dutyTable[Self.weekKey()] = id
        } else {
            dutyTable.removeValue(forKey: Self.weekKey())
        }
        DB.store.setCodable(Self.dutyKey, dutyTable)
    }

    // MARK: 周键（与 MemberHub 的轮值键同一口径：同一个 Calendar、同一组分量）

    static func weekKey(_ date: Date = Date()) -> String {
        let c = WeekCal.calendar
        let y = c.component(.yearForWeekOfYear, from: date)
        let w = c.component(.weekOfYear, from: date)
        return String(y) + "-W" + String(w)
    }

    // MARK: 落盘桥（MemberExt ↔ HHMemberExtras）

    private static let dutyKey = "kf_duty_week"
    private static let relationKey = "kf_member_relation"

    private func persist(_ id: String, _ e: HHMemberExtras) {
        var ext = MemberHub.ext(id)
        ext.emoji = e.emoji
        ext.remark = e.remark
        ext.emergency = e.emergency
        ext.groupTag = e.groupTag
        ext.note = e.note
        ext.emergencyAdmin = e.emergencyAdmin
        ext.careText = e.careText
        ext.welcome = e.welcome
        ext.proxy = e.proxy
        MemberHub.saveExt(id, ext)
        // 关系另有独立的成员字段（旧仓 DB.setMemberInfo(["relation": …]) 同一口径）：
        // 成员已在 kf_members 里就写那边；同时写本机覆盖层，样例成员也能存住。
        relationOverlay[id] = e.relation
        DB.store.setCodable(Self.relationKey, relationOverlay)
        if DB.member(id) != nil {
            DB.setMemberInfo(id, ["relation": e.relation])
        }
    }

    private static func extras(from e: MemberExt) -> HHMemberExtras {
        HHMemberExtras(emoji: e.emoji,
                       remark: e.remark,
                       relation: "",
                       groupTag: e.groupTag,
                       note: e.note,
                       emergency: e.emergency,
                       emergencyAdmin: e.emergencyAdmin,
                       careText: e.careText,
                       welcome: e.welcome,
                       proxy: e.proxy)
    }

}

// MARK: - 角色与权限矩阵（470 / 843）
//
// 矩阵的唯一定义在 Engine/MemberHub.swift 的 permRows —— 这里只做「MemberCard.Role → 角色码」的翻译，
// 不另写一份五行表（两处各写一遍迟早互相打脸）。

enum HHPerm {
    /// 五行能力名（顺序即矩阵行序），从 MemberHub 现取。
    static let rows: [String] = MemberHub.permRows("member").map { $0.name }

    /// MemberCard 的三档 → Engine 的角色码（main / member / guest）。
    static func code(_ role: MemberCard.Role) -> String {
        switch role {
        case .owner: return "main"
        case .guest: return "guest"
        case .member: return "member"
        }
    }

    static func allows(_ role: MemberCard.Role, _ cap: String) -> Bool {
        MemberHub.permAllows(code(role), cap)
    }

    static func can(_ role: MemberCard.Role) -> [String] { rows.filter { allows(role, $0) } }
    static func cannot(_ role: MemberCard.Role) -> [String] { rows.filter { !allows(role, $0) } }

    /// 建档向导第二步的副标题：这一档相对「成员」档多/少哪几项，由矩阵现算，不手写第二份说明。
    static func hint(_ role: MemberCard.Role) -> String {
        let mine = can(role)
        let base = can(.member)
        if role == .member { return mine.joined(separator: "/") }
        let more = mine.filter { !base.contains($0) }
        if !more.isEmpty { return "比成员多 " + more.joined(separator: "/") }
        let less = base.filter { !mine.contains($0) }
        if !less.isEmpty { return "比成员少 " + less.joined(separator: "/") }
        return "与成员同"
    }

    /// 角色示例的「场景话术」——只有这一句是写死的文案，权限位全部现算。
    static func scene(_ role: MemberCard.Role) -> String {
        switch role {
        case .owner: return "通常是房子主人：这台机器上的所有事都归 Ta。"
        case .guest: return "通常是访客/钟点工：锁端仍可给临时码，本机这边不给代管、不给成员管理。"
        case .member: return "通常是家人：日常开门与补凭证够用，导出与备份不给。"
        }
    }
}

/// 成员行的活跃度说法。四种状态各有各的词，不合并。
enum HHMemberStatus: Hashable {
    case active, stale, never, archived
}

// MARK: - 名册统计（全部是台账推断，展示一律带「约」）

enum HHStats {
    /// 本机成员上限（旧仓判据写 16、文案写 15；这里统一按 15 —— 文案才是用户看到的那句）。
    ///
    /// 2026-11-04（走查发现 · 假 TODO）：原文写「上限来自锁端槽位表，接 Engine 后应由协议读回来」——
    /// **锁端根本没有成员这个概念**。成员是本机增值功能（`kf_members` 表，vendor 的凭证是平铺的），
    /// 协议里没有任何"成员槽位"可读。15 是**产品决策**，不是协议约束 —— 说成"等协议"会让人
    /// 一直等一个永远不会来的字段。
    static let memberLimit = 15

    static func active(_ members: [MemberCard]) -> [MemberCard] { members.filter { !$0.archived } }
    static func archived(_ members: [MemberCard]) -> [MemberCard] { members.filter { $0.archived } }

    /// 名下凭证合计（枚）。锁端 keyCount 是真字段。
    static func ownedKeys(_ members: [MemberCard]) -> Int { members.reduce(0) { $0 + $1.keyCount } }

    /// 近 7 天可证明归属的开门次数（约）。归属靠台账 owner 字段，锁端日志本身没有身份字段。
    /// TODO(engine)：接 MemberHub.activityBundle（Attribution.classify 按指纹/密码归属推断）；
    ///   现在只认台账里已写 owner 的行。
    static func weekOpens(_ entries: [LedgerEntry], names: Set<String>) -> Int {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - 7 * 86_400_000
        return entries.filter { entry in
            guard entry.at >= cutoff, let owner = entry.owner else { return false }
            return names.contains(owner)
        }.count
    }

    /// 799 周小结一句人话：近 7 天可证明归属次数 + 工作日最活跃小时段。
    ///
    /// 2026-11-04（走查发现 · 同一句两个引擎）：`MemberOpsScreen:291` 早就用
    /// `MemberHub.weekSentence(id)`（锁内 cmd16 日志 + `Attribution.classify` —— 能推出
    /// 多成员家庭里"这条日志是谁的"），而这一份还在用「台账 owner == 成员名」的本地近似。
    /// 多成员家庭里 `LedgerEntry.owner` 恒为 nil（见 `RecordsModels.owner` 的单成员启发式），
    /// 于是**成员 360 的周小结永远是空的，而成员操作页有数** —— 同一句、两个答案。
    /// 现在优先读引擎；引擎读不到（无日志缓存）时才回落本地近似。
    static func weekSentence(_ member: MemberCard, entries: [LedgerEntry]) -> String? {
        if let engine = MemberHub.weekSentence(member.id) { return engine }
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - 7 * 86_400_000
        let mine = entries.filter { $0.owner == member.name && $0.at >= cutoff }
        guard !mine.isEmpty else { return nil }
        var byHour: [Int: Int] = [:]
        for entry in mine {
            let d = TimeFormat.date(entry.at)
            let weekday = TimeFormat.calendar.component(.weekday, from: d)
            if (2 ... 6).contains(weekday) {
                byHour[TimeFormat.calendar.component(.hour, from: d), default: 0] += 1
            }
        }
        let name = member.name.isEmpty ? "成员" : member.name
        if let peak = byHour.max(by: { $0.value < $1.value })?.key {
            return "\(name) 近 7 天开门约 \(mine.count) 次，工作日 \(HHStats.hourSpan(peak)) 最活跃。"
        }
        return "\(name) 近 7 天开门约 \(mine.count) 次（工作日样本不足）。"
    }

    /// 成员行副行「最近开门」：没有可证明记录时不写 0，写实话。
    static func lastOpen(_ member: MemberCard) -> String {
        guard let at = member.lastActiveAt else { return "还没有可归属的开门" }
        return "最近 " + TimeFormat.ago(at)
    }

    /// 30 天无归属开门 = 久未用（262 的判据；锁端日志无身份字段，所以是「约」）。
    /// 一次都没用过 ≠ 久未用：新成员不该一进名册就被标成「久未用」。
    static func status(_ member: MemberCard) -> HHMemberStatus {
        if member.archived { return .archived }
        guard let at = member.lastActiveAt else { return .never }
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - 30 * 86_400_000
        return at < cutoff ? .stale : .active
    }

    static func stale(_ member: MemberCard) -> Bool { status(member) == .stale }

    /// 小时段的显示：`23` 的下一个小时是 **次日 0 点**，不是「24 点」。
    /// 2026-11-01 修复：`weekSentence` 原来直接写 `\(peak)–\(peak + 1) 点`，
    /// 于是在 23 点开门最频繁的成员会被写成「23–24 点最活跃」—— 24 点不存在。
    static func hourSpan(_ hour: Int) -> String {
        let next = (hour + 1) % 24
        return next == 0 ? "\(hour)–次日 0 点" : "\(hour)–\(next) 点"
    }
}

// MARK: - 成员值替换（MemberCard 的字段是 let，改角色/归档要换一个值，不就地改）

extension MemberCard {
    func hh(role: MemberCard.Role? = nil, archived: Bool? = nil) -> MemberCard {
        MemberCard(id: id,
                   name: name,
                   role: role ?? self.role,
                   keyCount: keyCount,
                   lastActiveAt: lastActiveAt,
                   archived: archived ?? self.archived)
    }
}
