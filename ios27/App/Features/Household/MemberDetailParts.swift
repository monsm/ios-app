// MemberDetailParts.swift —— 成员 360 里两块可独立复用的列表（名下凭证 / 最近开门）。
//
// 为什么单独成文件：MembersDetailScreen 已过 400 行；这两块只吃数据 + 回调，不持有状态，
// 拆出来以后将来「凭证页按成员筛」也能直接复用同一个形状。
import SwiftUI

// MARK: - 名下凭证

struct HHMemberKeysCard: View {
    let member: MemberCard
    let keys: [KeyItem]
    let openKey: (String) -> Void
    let createKey: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "名下凭证", trailing: "\(keys.count) 枚")
                if keys.isEmpty {
                    Text("TA 名下还没有凭证。到「钥匙」页新建一枚，归属选 \(member.name)。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    HHRowButton(title: "去新建凭证", symbol: "plus.circle",
                                detail: nil, action: createKey)
                } else {
                    VStack(spacing: 0) {
                        ForEach(keys.indices, id: \.self) { index in
                            if index > 0 { HHRule() }
                            keyRow(keys[index])
                        }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func keyRow(_ key: KeyItem) -> some View {
        Button {
            openKey(key.id)
        } label: {
            HStack(spacing: V.S.gapMS) {
                Text(key.kind.rawValue)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .tracking(0.6)
                    .frame(width: V.Hit.min + V.S.gap24, alignment: .leading)
                Text(key.name)
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                    .lineLimit(1)
                Spacer(minLength: V.S.gapS)
                if key.disabled {
                    Text("已停用")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.critical)
                } else if let exp = key.expiresAt {
                    Text(TimeFormat.dayShort(exp))
                        .font(V.F.stamp)
                        .foregroundStyle(V.C.text2)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon15Medium)
                    .foregroundStyle(V.C.text3)
            }
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(key.kind.rawValue) \(key.name)")
    }
}

// MARK: - 最近开门（归属可证明才进，展示带「约」）

struct HHMemberExcerptsCard: View {
    let entries: [LedgerEntry]
    let openRecords: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "最近开门", trailing: "约")
                if entries.isEmpty {
                    Text("台账里还没有可证明归属到 TA 的开门。锁端日志没有身份字段，只有归属明确的条目才会出现在这里。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    HHRowButton(title: "去台账按 TA 筛", symbol: "line.3.horizontal.decrease.circle",
                                detail: nil, action: openRecords)
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries.indices, id: \.self) { index in
                            if index > 0 { HHRule() }
                            VLedgerRow(entry: entries[index], showDay: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }
}


// MARK: - 这一周（有才显示；没有就如实说出路）

struct HHMemberWeekCard: View {
    let member: MemberCard
    let entries: [LedgerEntry]
    let openRecords: () -> Void

    var body: some View {
        let sentence = HHStats.weekSentence(member, entries: entries)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "这一周", trailing: "约")
                if let sentence {
                    Text(sentence)
                        .font(V.F.body)
                        .foregroundStyle(V.C.text1)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("这一周还没有可证明归属到 TA 的开门。锁端日志没有身份字段，只有归属明确的条目才会算进来。")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    HHRowButton(title: "去台账看全部记录", symbol: "list.bullet.rectangle.portrait",
                                detail: nil, action: openRecords)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }
}

// MARK: - 家庭场景（本周主责 + 便签回显）

struct HHMemberSceneCard: View {
    let member: MemberCard
    let note: String
    let isDuty: Bool
    let toggleDuty: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "家庭场景")
                HStack(spacing: V.S.gapMS) {
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        Text("本周主责")
                            .font(V.F.body)
                            .foregroundStyle(V.C.text1)
                        Text(isDuty ? "本周的家里事归 TA。" : "把这一周的事指给 TA；下周可重新指。")
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: V.S.gapS)
                    Button(action: toggleDuty) {
                        Text(isDuty ? "取消主责" : "设为本周主责")
                            .font(V.F.bodyStrong)
                            .foregroundStyle(V.C.text1)
                            .padding(.horizontal, V.S.gapMS)
                            .frame(minHeight: V.Hit.min)
                            .overlay {
                                RoundedRectangle(cornerRadius: V.R.control, style: .continuous)
                                    .strokeBorder(V.C.hairline, lineWidth: V.S.hair)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDuty ? "取消本周主责" : "设为本周主责")
                }
                .frame(minHeight: V.Hit.min)

                if !note.isEmpty {
                    HHRule()
                    VFieldRow(label: "便签", value: note, mono: false)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }
}

// MARK: - 收尾（归档不删历史；删除的两种后果写在同一屏）

struct HHMemberClosingCard: View {
    let member: MemberCard
    let toggleArchive: () -> Void
    let askDelete: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "档案收尾")
                HHRowButton(
                    title: member.archived ? "恢复进名册" : "归档（保留历史）",
                    symbol: "archivebox",
                    detail: member.archived ? "回到成员名册" : "记录页仍能筛到 TA",
                    action: toggleArchive
                )
                HHRule()
                Button(action: askDelete) {
                    HStack(spacing: V.S.gapMS) {
                        Image(systemName: "trash")
                            .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                            .font(V.F.icon18)
                            .foregroundStyle(V.C.critical)
                            .frame(width: V.Icon.xl, alignment: .leading)
                        Text("删除成员")
                            .font(V.F.body)
                            .foregroundStyle(V.C.critical)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: V.Hit.min)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除成员")

                Text("归档只从名册与统计里收起，不删任何历史；删除会移走 TA 的档案与名下凭证归属。指纹一旦在锁端删掉就无法远程补录，只能本人到锁前重录。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }
}
