// AccessScreen.swift —— 通行：凭证 / 成员 / 手机钥匙。
import SwiftUI

@MainActor
struct AccessScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var segment = 0
    @State private var query = ""

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行", subtitle: summary) {
                HStack(spacing: 14) {
                    Button {
                        segment = 0
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(T.C.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索")

                    Button {
                        switch segment {
                        case 0: router.push(.credentialCreate)
                        case 1: router.push(.memberCreate)
                        default: router.push(.mobileKeys)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(T.C.brass)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建")
                }
            }

            SegmentedBar(items: ["凭证", "成员", "手机钥匙"], selected: $segment)
                .padding(.top, 10)

            switch segment {
            case 0: CredentialsSection(query: $query)
            case 1: MembersSection()
            default: MobileKeysSection()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var summary: String {
        let expiring = app.credentials.filter { $0.isExpiringSoon }.count
        var parts = ["\(app.credentials.count) 枚在册"]
        if expiring > 0 { parts.append("\(expiring) 枚临期") }
        if app.ledgerCorrupt { parts.append("台账读取异常") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 凭证

@MainActor
struct CredentialsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Binding var query: String

    private var expiring: [Credential] {
        app.credentials.filter { $0.isExpiringSoon || $0.isExpired }
            .sorted { ($0.expiresAt ?? 0) < ($1.expiresAt ?? 0) }
    }

    private var filtered: [Credential] {
        let base = app.credentials.sorted { lhs, rhs in
            if lhs.isExpiringSoon != rhs.isExpiringSoon { return lhs.isExpiringSoon }
            return lhs.createdAt > rhs.createdAt
        }
        guard !query.isEmpty else { return base }
        let needle = query.lowercased()
        return base.filter { item in
            if item.name.lowercased().range(of: needle) != nil { return true }
            if let owner = item.ownerName, owner.lowercased().range(of: needle) != nil { return true }
            return item.kind.title.range(of: query) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisplayLine(text: headline, size: 36)
                .padding(.top, 22)
            Text(detail)
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .padding(.top, 8)
                .padding(.bottom, 18)

            FieldInput(placeholder: "搜名字、成员或类型", text: $query, symbol: "magnifyingglass")

            if !expiring.isEmpty {
                SectionHead(index: "01", title: "临期", trailing: "\(expiring.count)")
                ForEach(expiring) { item in
                    credentialRow(item)
                }
            }

            SectionHead(index: expiring.isEmpty ? "01" : "02", title: "全部凭证", trailing: "\(filtered.count)")

            if filtered.isEmpty {
                EmptyNote(line: query.isEmpty ? "还没有凭证。" : "没有搜到。",
                          detail: query.isEmpty
                            ? "密码、指纹、临时码都会出现在这里。先加一枚，门才认得你。"
                            : "换个名字、成员或类型再试。",
                          action: query.isEmpty ? "新建凭证" : nil,
                          run: query.isEmpty ? { router.push(.credentialCreate) } : nil)
            } else {
                ForEach(filtered) { item in
                    credentialRow(item)
                }
            }

            if app.ledgerCorrupt {
                Text("本机台账读取异常：现在新增的凭证不会被保存。建议先备份，再重新配对。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 16)
            }
        }
    }

    private var headline: String {
        if expiring.first(where: { $0.isExpired }) != nil { return "有钥匙已经过期。" }
        if !expiring.isEmpty { return "两枚钥匙\n这周到期。" }
        return "一切都在\n有效期内。"
    }

    private var detail: String {
        if let first = expiring.first {
            if first.isExpired { return "「\(first.name)」已经过期，门锁不再认它。" }
            return "「\(first.name)」\(When.expiryLabel(first.expiresAt))到期。"
        }
        return "\(app.credentials.count) 枚凭证 · 没有即将到期的"
    }

    @ViewBuilder
    private func credentialRow(_ item: Credential) -> some View {
        Button {
            router.openCredential(item.id)
        } label: {
            ContentRow(symbol: item.kind.symbol,
                       tone: item.isExpiringSoon || item.isExpired ? .danger : .brass,
                       title: item.name,
                       subtitle: subtitle(item),
                       chevron: true) {
                if item.isExpired {
                    Badge(text: "已过期", kind: .danger)
                } else if item.isExpiringSoon {
                    Badge(text: "剩 \(days(item.expiresAt)) 天", kind: .danger)
                } else if item.disabled {
                    Badge(text: "已停用", kind: .calm)
                } else {
                    Text(item.masked ?? "")
                        .type(T.F.mono)
                        .foregroundStyle(T.C.ink3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ item: Credential) -> String {
        var parts: [String] = []
        parts.append(item.kind.title)
        if let owner = item.ownerName, !owner.isEmpty { parts.append(owner) }
        if item.expiresAt == nil { parts.append("长期有效") }
        return parts.joined(separator: " · ")
    }

    private func days(_ ms: Int64?) -> Int {
        guard let ms else { return 0 }
        let left = ms - Int64(Date().timeIntervalSince1970 * 1000)
        return max(0, Int(ceil(Double(left) / 86_400_000)))
    }
}

// MARK: - 成员

@MainActor
struct MembersSection: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var active: [MemberCard] { app.members.filter { !$0.archived } }
    private var archived: [MemberCard] { app.members.filter { $0.archived } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisplayLine(text: active.isEmpty ? "还没有家人。" : "\(active.count) 个人，\n一个家。", size: 36)
                .padding(.top, 22)
            Text("成员只是本机的名册：谁名下有几枚钥匙、最近谁回来过。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .padding(.top, 8)
                .padding(.bottom, 18)

            SectionHead(index: "01", title: "成员", trailing: "\(active.count)")
            ForEach(active) { member in
                Button {
                    router.openMember(member.id)
                } label: {
                    MemberRow(member: member)
                }
                .buttonStyle(.plain)
            }

            if !archived.isEmpty {
                SectionHead(index: "02", title: "已归档", trailing: "\(archived.count)")
                ForEach(archived) { member in
                    Button {
                        router.openMember(member.id)
                    } label: {
                        MemberRow(member: member)
                    }
                    .buttonStyle(.plain)
                }
            }

            if active.isEmpty {
                EmptyNote(line: "从一个人开始。",
                          detail: "给家人建一份名册，再把钥匙分给 TA。",
                          action: "新建成员") {
                    router.push(.memberCreate)
                }
            }
        }
    }
}

@MainActor
struct MemberRow: View {
    var member: MemberCard

    var body: some View {
        HStack(spacing: 14) {
            MemberOrb(member: member, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .type(T.F.body)
                        .fontWeight(.medium)
                        .foregroundStyle(T.C.ink)
                    Text(member.role.title)
                        .type(T.F.kicker)
                        .foregroundStyle(T.C.ink3)
                }
                Text(subtitle)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if member.archived {
                Badge(text: "已归档", kind: .calm)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(T.C.ink4)
        }
        .padding(.vertical, 13)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = ["\(member.keyCount) 枚钥匙"]
        if let last = member.lastActiveAt {
            parts.append("最近 \(When.ago(last))")
        } else {
            parts.append("还没开过门")
        }
        if !member.groupTag.isEmpty { parts.append(member.groupTag) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
struct MemberOrb: View {
    var member: MemberCard
    var size: CGFloat = 42

    private var color: Color {
        Color(hex: member.colorHex) ?? T.C.brass
    }

    var body: some View {
        Text(String(member.name.prefix(1)))
            .type(T.F.headline).fontWeight(.semibold)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background {
                Circle().fill(color.opacity(0.14))
            }
            .overlay {
                Circle().strokeBorder(color.opacity(0.28), lineWidth: 0.5)
            }
    }
}

// MARK: - 手机钥匙

@MainActor
struct MobileKeysSection: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var keys: [Credential] { app.credentials.filter { $0.kind == .mobile } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisplayLine(text: keys.isEmpty ? "还没有\n发过手机钥匙。" : "\(keys.count) 把钥匙\n在手机里。", size: 36)
                .padding(.top, 22)
            Text("手机钥匙是一枚签好有效期的 ekey。吊销时会把对应的 PIN 从锁里删掉。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .padding(.top, 8)
                .padding(.bottom, 18)

            SectionHead(index: "01", title: "已发出", trailing: "\(keys.count)")
            ForEach(keys) { key in
                Button {
                    router.openCredential(key.id)
                } label: {
                    ContentRow(symbol: "iphone",
                               tone: key.isExpired ? .danger : .brass,
                               title: key.name,
                               subtitle: sub(key),
                               chevron: true) {
                        if key.isExpired {
                            Badge(text: "已过期", kind: .danger)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if keys.isEmpty {
                EmptyNote(line: "把钥匙发到家人的手机里。",
                          detail: "对方用二维码接收，不需要联网。",
                          action: "签发手机钥匙") {
                    router.push(.mobileKeys)
                }
            }

            Button {
                router.push(.mobileKeys)
            } label: {
                Text("签发与管理")
                    .type(T.F.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.brass)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }

    private func sub(_ key: Credential) -> String {
        var parts: [String] = []
        if let owner = key.ownerName, !owner.isEmpty { parts.append(owner) }
        parts.append(key.expiresAt == nil ? "永久有效" : When.expiryLabel(key.expiresAt))
        return parts.joined(separator: " · ")
    }
}
