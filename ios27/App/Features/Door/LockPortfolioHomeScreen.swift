// LockPortfolioHomeScreen.swift —— 全部锁（V8 设计语言）
//
// 与 LockPortfolioScreen 的能力对齐：30 天总览、按分组筛选、三种排序、切当前锁、改分组、设为默认。
import SwiftUI

struct LockPortfolioHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    enum Sort: String, CaseIterable, Identifiable {
        case name = "名称"
        case opens = "开门次数"
        case power = "电量"
        var id: String { rawValue }
    }

    @State private var sort: Sort = .name
    @State private var groupFilter = ""
    @State private var groupEditMac = ""
    @State private var groupDraft = ""
    @State private var showGroupEdit = false
    @State private var usage: [LockUsage] = []

    private var groups: [String] {
        Array(Set(usage.map { groupOf($0.mac) })).sorted()
    }

    private var shown: [LockUsage] {
        let list = usage.filter { groupFilter.isEmpty || groupOf($0.mac) == groupFilter }
        switch sort {
        case .name: return list.sorted { $0.name < $1.name }
        case .opens: return list.sorted { $0.opens30d > $1.opens30d }
        case .power: return list.sorted { $0.power > $1.power }
        }
    }

    private var judgement: String {
        if usage.isEmpty { return "还没有门锁" }
        return "\(usage.count) 把锁 · 30 天开了 \(usage.reduce(0) { $0 + $1.opens30d }) 次"
    }

    var body: some View {
        VPage(title: judgement, lead: "多锁统计、分组与排序。点一行把该锁设为当前锁。") {
            EmptyView()
        } content: {
            if usage.isEmpty {
                VEmpty(
                    title: "还没有门锁",
                    reason: "多锁统计要在本机至少有一把锁之后才有读数。先添加门锁。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else {
                summaryCard
                filterRow
                listCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .alert("移动到分组", isPresented: $showGroupEdit) {
            TextField("分组名（留空 = 未分组）", text: $groupDraft)
            Button("取消", role: .cancel) { }
            Button("保存") { saveGroup() }
        } message: {
            Text("分组只存本机，不写门锁。")
        }
    }

    private var summaryCard: some View {
        VCard2 {
            VCardHead(eyebrow: "30 天总览", statement: "\(usage.reduce(0) { $0 + $1.opens30d }) 次开门")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "门锁", value: "\(usage.count)", unit: "把"),
                .init(label: "告警", value: "\(usage.reduce(0) { $0 + $1.alarms30d })", unit: "条")
            ])
            .padding(.top, V8.S.gapM)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                filterChip("全部", on: groupFilter.isEmpty) { groupFilter = "" }
                ForEach(groups, id: \.self) { g in
                    filterChip(g, on: groupFilter == g) { groupFilter = g }
                }
                Menu {
                    ForEach(Sort.allCases) { option in
                        Button(option.rawValue) { sort = option }
                    }
                } label: {
                    Text("排序 · " + sort.rawValue)
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.ink1)
                        .padding(.horizontal, V8.S.gapM)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.chipOff))
                }
                .accessibilityLabel("排序方式")
            }
            .padding(.horizontal, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var listCard: some View {
        VCard2 {
            VCardHead(eyebrow: "门锁", statement: "\(shown.count) 把")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { pair in
                    row(pair.element)
                    if pair.offset != shown.count - 1 { VDotRule() }
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func row(_ item: LockUsage) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapS) {
            Button {
                DB.currentMac = item.mac
                app.overrideMac = item.mac
                Task { await app.reload(refreshStatus: true) }
            } label: {
                VDataRow(
                    tag: item.mac == app.currentMac ? "当前" : groupOf(item.mac),
                    tagTint: item.mac == app.currentMac ? V8.C.accent : V8.C.ink4,
                    title: item.name,
                    detail: item.sleeping ? "沉睡" : "固件 \(item.fw.isEmpty ? "未知" : item.fw)",
                    value: "\(item.opens30d)",
                    unit: "次"
                )
            }
            .buttonStyle(.plain)
            HStack(spacing: V8.S.gapL) {
                Button("改分组") {
                    groupEditMac = item.mac
                    groupDraft = groupOf(item.mac) == LockArchive.ungroupedLabel ? "" : groupOf(item.mac)
                    showGroupEdit = true
                }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                Button("设为默认") {
                    LockArchive.setDefaultMac(item.mac)
                }
                .font(V8.T.caption)
                .foregroundStyle(V8.C.accent)
                Spacer(minLength: 0)
                Text(item.power >= 0 ? "\(item.power)%" : "电量未知")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: V8.H.min)
    }

    private func groupOf(_ mac: String) -> String {
        let g = LockArchive.group(mac)
        return g.isEmpty ? LockArchive.ungroupedLabel : g
    }

    private func saveGroup() {
        guard !groupEditMac.isEmpty else { return }
        LockArchive.setGroup(groupEditMac, groupDraft)
        groupEditMac = ""
        reload()
    }

    private func reload() {
        usage = LockStats.usage()
    }
}
