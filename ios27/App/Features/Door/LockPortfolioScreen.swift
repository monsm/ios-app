// LockPortfolioScreen.swift —— 全部锁：多锁统计 / 分组 / 排序。
//
// 来源：原 App/Core/LockStats.swift（LockStats.usage 多锁统计）+ App/UI/LockProfileView.swift 的分组/排序/默认锁。
// 这屏干什么：把本机所有门锁按分组摆开，显示 30 天开门/告警/电量/固件读数，可切换排序、切当前锁、改分组与默认锁。
// 数据从哪来：LockStats.usage() / LockArchive.grouped(DB.keychains())。
// 主动作：点行把该锁设为当前锁（编辑其余页面都跟着它）。
import SwiftUI

struct LockPortfolioScreen: View {
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

    var body: some View {
        // 2026-11-02（R4 全换系统）：纯 ScrollView 换系统 List；锁列表单独成 Section（一把锁一行）。
        // 分组筛选已是 Picker(.segmented)（第 2 轮改的），原样保留，只作为整块行放进来。
        List {
            header.headerRow()
            if usage.isEmpty {
                emptyCard.cardRow()
            } else {
                summaryCard.cardRow()
                filterRow.headerRow()   // 筛选行是整宽内容（不是卡片）
                Section {
                    ForEach(shown, id: \.mac) { item in
                        row(item)
                    }
                } header: {
                    Text("门锁 · \(shown.count) 把")
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("全部锁")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .alert("移动到分组", isPresented: $showGroupEdit) {
            TextField("分组名（留空 = 未分组）", text: $groupDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { saveGroup() }
        } message: {
            Text("分组只存本机，不写门锁。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("全部锁")
                .font(V.F.displayA).foregroundStyle(V.C.text1)
            Text("多锁统计、分组与排序")
                .font(V.F.footnote).foregroundStyle(V.C.text3)
        }
    }

    private var emptyCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁").font(V.F.displayB).foregroundStyle(V.C.text1)
                Text("多锁统计要在本机至少有一把锁之后才有读数。先添加门锁。")
                    .font(V.F.body).foregroundStyle(V.C.text2)
                VActionButton(title: "添加门锁", systemImage: "plus") { router.request(.dest(.addLock)) }
            }
        }
    }

    private var summaryCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "30 天总览")
                VStatPair(items: [
                    ("门锁", "\(usage.count) 把"),
                    ("开门", "\(usage.reduce(0) { $0 + $1.opens30d }) 次"),
                    ("告警", "\(usage.reduce(0) { $0 + $1.alarms30d }) 条")
                ])
            }
        }
    }

    private var groups: [String] {
        Array(Set(usage.map { groupOf($0.mac) })).sorted()
    }

    /// 分组筛选是**单选**（`groupFilter` 一个 String，空 = 全部）⇒ 交给系统 `Picker(.segmented)`。
    /// 档位数（含「全部」）超过 4 个时分段控件会被压扁（`SettingsParts.swift` 里已写明这条判据），
    /// 那时回落到横向 chip 行 —— 两套都保留，但**默认走系统控件**。
    @ViewBuilder
    private var filterRow: some View {
        HStack(spacing: V.S.gapS) {
            if groupOptions.count <= 4 {
                Picker("分组", selection: $groupFilter) {
                    ForEach(groupOptions, id: \.self) { g in
                        Text(g.isEmpty ? "全部" : g).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // 分段控件是弹性宽度：给它整行剩余空间，否则会和后面的 Spacer 各抢一半、
                // 把「全部 / 分组名」压成省略号。
                .frame(maxWidth: .infinity)
                .accessibilityLabel("按分组筛选")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: V.S.gapS) {
                        ForEach(groupOptions, id: \.self) { g in
                            Button { groupFilter = g } label: {
                                VTag(text: g.isEmpty ? "全部" : g,
                                     tint: groupFilter == g ? V.C.blue : V.C.text3,
                                     filled: groupFilter == g)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(groupFilter == g ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                Spacer(minLength: 0)
            }
            // 排序仍是 Menu（系统控件），只是把 label 从自绘 VTag 换成带图标的 Label。
            Menu {
                ForEach(Sort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        if option == sort {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                Label("排序 · " + sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text1)
                    .frame(minHeight: V.Hit.min)
                    .contentShape(.rect)
            }
            .accessibilityLabel("排序方式，当前 \(sort.rawValue)")
        }
    }

    /// 分组筛选的全部选项：第一个是空串（= 全部），后面是真实分组名。
    private var groupOptions: [String] {
        [""] + groups
    }

    private var shown: [LockUsage] {
        let list = usage.filter { groupFilter.isEmpty || groupOf($0.mac) == groupFilter }
        switch sort {
        case .name: return list.sorted { $0.name < $1.name }
        case .opens: return list.sorted { $0.opens30d > $1.opens30d }
        case .power: return list.sorted { $0.power > $1.power }
        }
    }

    private func row(_ item: LockUsage) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Button {
                DB.currentMac = item.mac
                app.overrideMac = item.mac
                Task { await app.reload(refreshStatus: true) }
            } label: {
                HStack(spacing: V.S.gapS) {
                    Circle()
                        .fill(item.sleeping ? V.C.text3 : V.C.rewardGreen)
                        .frame(width: V.List.dotSize, height: V.List.dotSize)
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        HStack(spacing: V.S.gapS) {
                            Text(item.name).font(V.F.rowTitle).foregroundStyle(V.C.text1)
                            if item.mac == app.currentMac {
                                VTag(text: "当前", tint: V.C.blue, filled: true)
                            }
                            if item.sleeping { VTag(text: "沉睡", tint: V.C.text3) }
                        }
                        Text("\(groupOf(item.mac)) · 固件 \(item.fw.isEmpty ? "未知" : item.fw)")
                            .font(V.F.rowDetail).foregroundStyle(V.C.text3).lineLimit(1)
                    }
                    Spacer(minLength: V.S.gapS)
                    VStack(alignment: .trailing, spacing: V.S.gapXXS) {
                        Text("\(item.opens30d) 次").font(V.F.rowTitle).foregroundStyle(V.C.text1).monospacedDigit()
                        Text(item.power >= 0 ? "\(item.power)%" : "电量未知")
                            .font(V.F.rowDetail)
                            .foregroundStyle((0 ... 20).contains(item.power) ? V.C.coral : V.C.text3)
                    }
                }
                .frame(minHeight: V.List.rowMinHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            HStack(spacing: V.S.gapS) {
                // 两个行内动作合成一个系统 Menu：同屏按钮数从 2 降到 1，
                // 菜单项自带系统点击区与 VoiceOver 的「菜单」语义，不再自绘两个小号蓝字按钮。
                Menu {
                    Button {
                        groupEditMac = item.mac
                        groupDraft = groupOf(item.mac) == LockArchive.ungroupedLabel ? "" : groupOf(item.mac)
                        showGroupEdit = true
                    } label: {
                        Label("改分组", systemImage: "folder.badge.gearshape")
                    }
                    Button {
                        LockArchive.setDefaultMac(item.mac)
                    } label: {
                        Label("设为默认", systemImage: "pin")
                    }
                } label: {
                    Label("更多操作", systemImage: "ellipsis.circle")
                        .font(V.F.footnote)
                        .foregroundStyle(V.C.blue)
                        .frame(minHeight: V.Hit.min)
                        .contentShape(.rect)
                }
                .accessibilityLabel("\(item.name) 的更多操作")
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: V.List.rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // List 行：保留「更多操作」Menu，同时把两个动作也放上滑动动作
        // （原实现只能点 ⋯ 菜单，行上没有快捷手势）。
        .listRowInsets(EdgeInsets(top: V.S.gapS, leading: V.S.cardGutter,
                                  bottom: V.S.gapS, trailing: V.S.cardGutter))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                LockArchive.setDefaultMac(item.mac)
                AppToast.shared.show("已把「\(item.name)」设为默认锁", tone: .ok)
            } label: {
                Label("设为默认", systemImage: "pin")
            }
            .tint(V.C.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                groupEditMac = item.mac
                groupDraft = groupOf(item.mac) == LockArchive.ungroupedLabel ? "" : groupOf(item.mac)
                showGroupEdit = true
            } label: {
                Label("改分组", systemImage: "folder.badge.gearshape")
            }
            .tint(V.C.coral)
        }
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

#Preview("LockPortfolioScreen") {
    NavigationStack { LockPortfolioScreen() }
        .environment(AppModel())
        .environment(Router())
}
