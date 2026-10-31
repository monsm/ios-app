// HouseholdParts.swift —— 家域私有的小零件（不进 Design/，避免与 lead 的组件库冲突）。
//
// 纪律：只组合已有令牌（T./Ink./Signal./State.），不发明第二种行语法。
// 家域的行一律「符号 → 文字 → 右侧读数/箭头」，与 DoorScreen 的 shortcutRow 同形。
import SwiftUI
import UIKit

// MARK: - 几何（由令牌组合，不写魔法数）

enum HHMetric {
    /// 行内头像：与 18pt 图标同视觉重量。
    static let avatarRow: CGFloat = T.Icon.xl + T.S.s
    /// 页头头像：与 34pt 标题同排，需要 44 触达那一档。
    static let avatarHero: CGFloat = T.Icon.xl + T.S.l
    /// 行内读数字号：比正文读数小一档，与右侧「活跃/久未用」小字同排。
    static let readingRow: CGFloat = T.Icon.s
    /// 序列刻度字号（向导 01/02/03/04）：与读数网格 22 之下的一档。
    static let readingStep: CGFloat = T.Icon.m
}

// MARK: - 头像（首字 / emoji 代号，零图片资源）

struct HHAvatar: View {
    let name: String
    var emoji: String = ""
    var size: CGFloat = HHMetric.avatarRow
    /// emoji 代号的字号：调用方按头像档位给一个令牌字号，不在视图里算比例。
    var glyph: Font = T.F.body

    var body: some View {
        ZStack {
            Circle().fill(Ink.plateAlt)
            Circle().strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
            if emoji.isEmpty {
                Text(initial)
                    .font(T.F.bodyStrong)
                    .foregroundStyle(Ink.inkSub)
            } else {
                Text(emoji)
                    .font(glyph)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initial: String {
        let ch = String(name.prefix(1))
        return ch.isEmpty ? "员" : ch
    }
}

// MARK: - 角色标记（形状 + 文字两通道，不靠颜色）

struct HHRoleMark: View {
    let role: MemberCard.Role
    var compact: Bool = false

    var body: some View {
        HStack(spacing: T.S.xs) {
            Image(systemName: symbol)
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(T.F.icon(T.Icon.s, weight: .regular))
            Text(role.rawValue)
                .font(compact ? T.F.unit : T.F.caption)
        }
        .foregroundStyle(Ink.inkSub)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("角色 \(role.rawValue)")
    }

    private var symbol: String {
        switch role {
        case .owner: return "crown"
        case .guest: return "person.badge.clock"
        case .member: return "person"
        }
    }
}

// MARK: - 通用行零件

struct HHRule: View {
    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
    }
}

/// 入口行：符号 + 标题 + 右侧读数/箭头。整行 44 可点。
struct HHRowButton: View {
    let title: String
    var symbol: String? = nil
    /// 文字型副信息（不带数字；数字请走 readingValue）。
    var detail: String? = nil
    /// 数字型副信息：走 Reading，等宽右对齐。
    var readingValue: String? = nil
    var readingUnit: String? = nil
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.S.m) {
                if let symbol {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                        .font(T.F.icon(T.Icon.m, weight: .regular))
                        .foregroundStyle(Ink.inkSub)
                        .frame(width: T.Icon.xl, alignment: .leading)
                }
                Text(title)
                    .font(T.F.body)
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: T.S.s)
                if let readingValue {
                    Reading(value: readingValue, unit: readingUnit, size: HHMetric.readingRow, tint: Ink.ink, animated: false)
                } else if let detail {
                    Text(detail)
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .multilineTextAlignment(.trailing)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                        .font(T.F.icon(T.Icon.s, weight: .medium))
                        .foregroundStyle(Ink.inkFaint)
                }
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        if let readingValue {
            return "\(title)，\(readingValue) \(readingUnit ?? "")"
        }
        return detail.map { "\(title)，\($0)" } ?? title
    }
}

/// 允许/禁用：勾与叉是形状通道，颜色只是第二通道。
struct HHPill: View {
    let allowed: Bool

    var body: some View {
        HStack(spacing: T.S.xs) {
            Image(systemName: allowed ? "checkmark.circle" : "xmark.circle")
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(T.F.icon(T.Icon.s, weight: .regular))
            Text(allowed ? "允许" : "禁用")
                .font(T.F.unit)
                .tracking(0.6)
        }
        .foregroundStyle(allowed ? Ink.ink : Ink.inkFaint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(allowed ? "允许" : "禁用")
    }
}

// MARK: - 页头（大标题 + 一行状态；Tab 根与子页共用同一形状）

struct HHPageHeader: View {
    let title: String
    var overline: String? = nil
    let tone: Tone
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            if let overline {
                Text(overline)
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .tracking(0.6)
            }
            Text(title)
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: T.S.s) {
                StateDot(tone: tone, word: status)
                Text(status)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 输入（用凹槽块包住，不做自定义输入框外观）

struct HHTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text(label)
                .font(T.F.unit)
                .foregroundStyle(Ink.inkFaint)
                .tracking(0.6)
            TextField(placeholder, text: $text)
                .font(T.F.body)
                .foregroundStyle(Ink.ink)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(.horizontal, T.S.m)
                .frame(minHeight: T.Hit.min)
                .background(Ink.plateAlt, in: .rect(cornerRadius: T.R.control))
                .overlay {
                    RoundedRectangle(cornerRadius: T.R.control, style: .continuous)
                        .strokeBorder(Ink.hairline, lineWidth: T.Stroke.hair)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - 成员行（名册与归档列表共用）

struct HHMemberRow: View {
    let member: MemberCard
    let extras: HHMemberExtras
    /// 副行补充（「最近 …」这类时间/推断口径）。
    var subline: String
    var status: HHMemberStatus = .active

    var body: some View {
        HStack(spacing: T.S.m) {
            HHAvatar(name: member.name, emoji: extras.emoji)
            VStack(alignment: .leading, spacing: T.S.xxs) {
                HStack(spacing: T.S.s) {
                    Text(HHDisplay.name(member, extras: extras))
                        .font(T.F.bodyStrong)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    HHRoleMark(role: member.role, compact: true)
                    Spacer(minLength: 0)
                }
                Text(subline)
                    .font(T.F.unit)
                    .foregroundStyle(status == .stale || status == .archived ? Ink.inkFaint : Ink.inkSub)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: T.S.s)
            VStack(alignment: .trailing, spacing: T.S.xxs) {
                Reading(value: "\(member.keyCount)", unit: "枚", size: HHMetric.readingRow, tint: Ink.ink, animated: false)
                Text(status == .stale ? "久未用" : "活跃")
                    .font(T.F.unit)
                    .foregroundStyle(status == .stale ? Ink.inkFaint : State.ok)
            }
        }
        .frame(minHeight: T.Hit.min + T.S.s)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HHDisplay.a11y(member, extras: extras, subline: subline))
    }
}

// MARK: - 显示口径（称呼（备注）/ 未命名兜底 / 无障碍一句）

enum HHDisplay {
    /// 「称呼（备注）」双层文本。备注为空就只给称呼。
    static func name(_ member: MemberCard, extras: HHMemberExtras) -> String {
        let base = member.name.isEmpty ? "未命名成员" : member.name
        return extras.remark.isEmpty ? base : base + "（" + extras.remark + "）"
    }

    static func a11y(_ member: MemberCard, extras: HHMemberExtras, subline: String) -> String {
        let role = member.role.rawValue
        let name = name(member, extras: extras)
        return "\(name)，\(role)，名下 \(member.keyCount) 枚凭证，\(subline)"
    }

    static func statusWord(_ status: HHMemberStatus) -> String {
        switch status {
        case .active: return "活跃约"
        case .stale: return "久未用"
        case .never: return "还没用过"
        case .archived: return "已归档"
        }
    }

    /// 副行四段：关系 / 备注 / 最近开门 / 分组。全空时写实话，不写「暂无」。
    static func subline(_ member: MemberCard, extras: HHMemberExtras) -> String {
        var bits: [String] = []
        if !extras.relation.isEmpty { bits.append(extras.relation) }
        if !extras.groupTag.isEmpty { bits.append(extras.groupTag) }
        if member.lastActiveAt != nil { bits.append(HHStats.lastOpen(member)) }
        if bits.isEmpty { return "还没有档案扩展 · 补一条关系或分组" }
        return bits.joined(separator: " · ")
    }
}

// MARK: - 开关行（墨色；同屏唯一 signal 留给主动作）

/// 一枚开关：形状（方块/圆点）+ 文字（开/关）+ 颜色三通道，点击即翻。
/// 刻意不用系统 Toggle —— 它的 accent 会吃掉本屏唯一的 signal 填充。
struct HHToggleRow: View {
    let title: String
    var detail: String? = nil
    let isOn: Bool
    var enabled: Bool = true
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: T.S.m) {
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    Text(title)
                        .font(T.F.body)
                        .foregroundStyle(enabled ? Ink.ink : Ink.inkFaint)
                    if let detail {
                        Text(detail)
                            .font(T.F.unit)
                            .foregroundStyle(Ink.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: T.S.s)
                HStack(spacing: T.S.s) {
                    StateDot(tone: isOn ? .live : .neutral, word: isOn ? "开" : "关")
                    Text(isOn ? "开" : "关")
                        .font(T.F.caption)
                        .foregroundStyle(isOn ? Ink.ink : Ink.inkSub)
                }
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "开" : "关")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
