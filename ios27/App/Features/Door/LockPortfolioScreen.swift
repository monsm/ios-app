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
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                header
                if usage.isEmpty {
                    emptyCard
                } else {
                    summaryCard
                    filterRow
                    listCard
                }
            }
            .padding(.top, V.Page.topSpace)
            .padding(.bottom, V.Tab.contentInset)
        }
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
        .padding(.horizontal, V.S.pageGutterA)
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
        .padding(.horizontal, V.S.cardGutter)
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
        .padding(.horizontal, V.S.cardGutter)
    }

    private var groups: [String] {
        Array(Set(usage.map { groupOf($0.mac) })).sorted()
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.gapS) {
                Button { groupFilter = "" } label: {
                    VTag(text: "全部", tint: groupFilter.isEmpty ? V.C.blue : V.C.text3, filled: groupFilter.isEmpty)
                }
                .buttonStyle(.plain)
                ForEach(groups, id: \.self) { g in
                    Button { groupFilter = g } label: {
                        VTag(text: g, tint: groupFilter == g ? V.C.blue : V.C.text3, filled: groupFilter == g)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Menu {
                    ForEach(Sort.allCases) { option in
                        Button(option.rawValue) { sort = option }
                    }
                } label: {
                    VTag(text: "排序 · " + sort.rawValue, tint: V.C.text1)
                }
            }
            .padding(.horizontal, V.S.cardGutter)
        }
        .scrollIndicators(.hidden)
    }

    private var shown: [LockUsage] {
        let list = usage.filter { groupFilter.isEmpty || groupOf($0.mac) == groupFilter }
        switch sort {
        case .name: return list.sorted { $0.name < $1.name }
        case .opens: return list.sorted { $0.opens30d > $1.opens30d }
        case .power: return list.sorted { $0.power > $1.power }
        }
    }

    private var listCard: some View {
        VCard {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { VDivider() }
                    row(pair.element)
                }
            }
        }
        .padding(.horizontal, V.S.cardGutter)
    }

    private func row(_ item: LockUsage) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Button {
                DB.currentMac = item.mac
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
                Button("改分组") {
                    groupEditMac = item.mac
                    groupDraft = groupOf(item.mac) == LockArchive.ungroupedLabel ? "" : groupOf(item.mac)
                    showGroupEdit = true
                }
                .font(V.F.footnote).foregroundStyle(V.C.blue)
                Button("设为默认") {
                    LockArchive.setDefaultMac(item.mac)
                }
                .font(V.F.footnote).foregroundStyle(V.C.blue)
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: V.List.rowMinHeight)
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
