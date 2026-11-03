// KeysParts.swift —— 钥匙域内的共享小件（只在 Features/Keys 里用）。
//
// 纪律：不新增 Design/Components 语义（那是 lead 的地盘，会冲突）；
// 这些件一律 Keys 前缀，避免与其他域撞名。样式全部走 V7 令牌（V.C / V.F / V.S），零字面量。
import SwiftUI

// MARK: - 类型分段

/// 凭证分段。all = 不筛；其余与 KeyItem.Kind 一一对应（手机钥匙单列，因为它是发出去的东西，不是锁内凭证）。
enum KeysFilter: String, CaseIterable, Hashable {
    case all
    case password
    case fingerprint
    case temp
    case mobile

    var title: String {
        switch self {
        case .all: return "全部"
        case .password: return "密码"
        case .fingerprint: return "指纹"
        case .temp: return "临时码"
        case .mobile: return "手机钥匙"
        }
    }

    func matches(_ key: KeyItem) -> Bool {
        switch self {
        case .all: return true
        case .password: return key.kind == .password
        case .fingerprint: return key.kind == .fingerprint
        case .temp: return key.kind == .temp
        case .mobile: return key.kind == .mobile
        }
    }
}

// MARK: - 状态推断（纯本地，可测）

/// 凭证状态。到期按自然日判断，与到期月历同一口径（不在两处各算一套）。
enum KeysState {
    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// 协议用 2118-12-31 23:59 当"永久"哨兵（见 KeyCreateScreen 的永久档注释）。
    /// 2026-11-03（整页截图暴露）：哨兵没被识别 —— 永久密码在列表行尾显示「33296」天。
    /// 口径：到期年 ≥ 2100 一律视为永久（返回 nil），所有派生读数自动变「永久」。
    static let permanentYearThreshold = 2100

    static func daysLeft(_ key: KeyItem, now: Int64) -> Int? {
        guard let expiresAt = key.expiresAt else { return nil }
        let cal = TimeFormat.calendar
        let to = TimeFormat.date(expiresAt)
        if cal.component(.year, from: to) >= permanentYearThreshold { return nil }
        let from = cal.startOfDay(for: TimeFormat.date(now))
        let toDay = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: from, to: toDay).day
    }

    static func expired(_ key: KeyItem, now: Int64) -> Bool {
        guard let days = daysLeft(key, now: now) else { return false }
        return days < 0
    }

    static func tone(_ key: KeyItem, now: Int64) -> Tone {
        if key.disabled { return .neutral }
        guard let days = daysLeft(key, now: now) else { return .ok }
        if days < 0 { return .critical }
        if days <= 3 { return .attention }
        return .ok
    }

    static func word(_ key: KeyItem, now: Int64) -> String {
        if key.disabled { return "已停用" }
        guard let days = daysLeft(key, now: now) else { return "永久有效" }
        if days < 0 { return "已过期" }
        if days == 0 { return "今天到期" }
        if days == 1 { return "明天到期" }
        return "\(days) 天后到期"
    }

    /// 行尾读数：永久不写数；有限期写剩余天数，单位是天。
    static func expiryReading(_ key: KeyItem, now: Int64) -> (value: String, unit: String?, tint: Color) {
        if key.disabled { return ("—", nil, V.C.text3) }
        guard let days = daysLeft(key, now: now) else { return ("永久", nil, V.C.text2) }
        if days < 0 { return ("过期", nil, V.C.critical) }
        if days <= 3 { return ("\(days)", "天", V.C.warning) }
        return ("\(days)", "天", V.C.text1)
    }

    /// 到期时刻拆成日期 + 时刻两个读数位；永久返回 (永久, nil)。
    /// 2026-11-01：加 `@MainActor` —— 时刻改用 `TimeDisplay.clock`（跟随用户 12/24 制式），
    /// 而 `TimeDisplay` 是 `@MainActor`（它读 `@MainActor` 的 `SettingsStore`）。
    /// 唯一调用点是 `KeyDetailScreen` 的 View body，本来就是主线程。
    @MainActor
    static func expiryLine(_ key: KeyItem) -> (value: String, unit: String?) {
        guard let expiresAt = key.expiresAt else { return ("永久", nil) }
        // 2026-11-03（全功能点排查）：这里漏了"永久哨兵"这一档 —— 永久密码的 expiresAt
        // 是 2118-12-31 23:59，于是详情页「到期日」显示 2118-12-31、「剩余」却显示「永久」，
        // 同一张卡里两行自相矛盾。与 daysLeft 用同一个阈值判定。
        if TimeFormat.calendar.component(.year, from: TimeFormat.date(expiresAt)) >= permanentYearThreshold {
            return ("永久", nil)
        }
        return (TimeFormat.dayShort(expiresAt), TimeDisplay.clock(expiresAt))
    }

    // 台账是值语义数组，改一条要整条重建（KeyItem 字段都是 let，这是有意的：改就是换一条）。

    /// 2026-11-01 修复：这两个"重建一条 KeyItem"的辅助函数**漏传了 `createdAt`** ——
    /// 而 `createdAt` 有默认值 0，所以编译不报错、但语义悄悄丢了：
    /// 用户一旦停用凭证或改到期日，详情页的「已使用 N 天」就消失（回到"未知"）。
    /// 凡是"逐字段重建"的辅助函数，新增字段时必须回来加一行。
    static func withDisabled(_ key: KeyItem, _ off: Bool) -> KeyItem {
        KeyItem(id: key.id, kind: key.kind, name: key.name, owner: key.owner,
                code: key.code, expiresAt: key.expiresAt, createdAt: key.createdAt, disabled: off)
    }

    static func withExpiry(_ key: KeyItem, _ at: Int64?) -> KeyItem {
        KeyItem(id: key.id, kind: key.kind, name: key.name, owner: key.owner,
                code: key.code, expiresAt: at, createdAt: key.createdAt, disabled: key.disabled)
    }

    static func replace(_ updated: KeyItem, in keys: [KeyItem]) -> [KeyItem] {
        var out = keys
        if let index = out.firstIndex(where: { $0.id == updated.id }) { out[index] = updated }
        return out
    }
}

// MARK: - 路由

/// 打开凭证详情。Router.request(.key(id:)) 只切 Tab 不 push（那是 Shell 的口径），
/// 所以这里两步走：先按 Dest push，再把定位上下文挂上去 —— 不裸改 Shell。
/// @MainActor：Router 是主线程隔离的 UI 状态机（CI 报 ActorIsolatedCall），
/// 这个辅助函数必须在同一隔离域里调它；调用点都在 SwiftUI 视图体内，天然满足。
@MainActor
enum KeysRoute {
    static func openDetail(_ id: String, router: Router) {
        router.request(.dest(.keyDetail))
        router.pending = .key(id: id)
    }
}

// MARK: - 分割线

/// 面板内极细分割线。台账行之间用它，不给每行套圆角卡。
struct KeysDivider: View {
    var body: some View {
        Divider()
    }
}

// MARK: - 台账行

/// 一行一枚凭证：状态点（形状+色+词）→ 名称 → 类型/归属/打码 → 行尾剩余天数读数。
struct KeysRow: View {
    let key: KeyItem
    let now: Int64

    private var subtitle: String {
        var bits: [String] = [key.kind.rawValue]
        // 内部值出屏：owner 可能是成员 id，统一换成可读名字（空则跳过，不留悬空的 " · "）。
        let owner = CredentialOrg.ownerName(key.owner)
        if !owner.isEmpty { bits.append(owner) }
        if let code = key.code, !code.isEmpty { bits.append(String(repeating: "•", count: code.count)) }
        return bits.joined(separator: " · ")
    }

    var body: some View {
        let read = KeysState.expiryReading(key, now: now)
        HStack(alignment: .center, spacing: V.S.gapMS) {
            VStateDot(tone: KeysState.tone(key, now: now), word: KeysState.word(key, now: now))
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(key.name)
                    .font(V.F.body)
                    .foregroundStyle(key.disabled ? V.C.text2 : V.C.text1)
                    .lineLimit(1)
                Text(subtitle)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: V.S.gapS)
            VReading(value: read.value, unit: read.unit, font: V.F.number15, tint: read.tint, animated: false)
        }
        .frame(minHeight: V.Hit.min + V.S.gapS)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.name)，\(key.kind.rawValue)，\(KeysState.word(key, now: now))")
    }
}