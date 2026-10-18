//  AppIndexView.swift
//  77 项目录。**是 sheet, 不占 Tab 位** (D1/D7)。2026-10-18 门面改造新增。
//
//  三处触达 (PART2 §4.1): 四 Tab 根右上「全部」按钮 (已接) / 长按 Tab / 下拉搜索。
//  数据来自 AppIndexData (从 uiux-v3.data.js 生成), 这里**不许**写死数组。

import SwiftUI

struct AppIndexView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var expanded: Set<String> = []

    private var shown: [AppIndexGroup] { AppIndexData.search(query) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    ForEach(shown) { group in
                        groupSection(group)
                    }
                    if shown.isEmpty {
                        ContentUnavailableView("没有匹配的功能",
                                               systemImage: "magnifyingglass",
                                               description: Text("换个说法试试"))
                            .padding(.top, DS.Space.xxl)
                    }
                }
                .padding(.horizontal, DS.Space.gutter)
                .padding(.vertical, DS.Space.l)
            }
            .background(DS.Palette.canvas)
            .navigationTitle("全部功能")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "搜索 \(AppIndexData.all.count) 项")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .frame(minHeight: DS.Hit.min)
                }
            }
        }
        .onAppear {
            if expanded.isEmpty { expanded = Set(AppIndexData.groups.map(\.name)) }
        }
        .onChange(of: query) { _, newValue in
            if !newValue.isEmpty { expanded = Set(shown.map(\.name)) }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: AppIndexGroup) -> some View {
        let isOpen = expanded.contains(group.name)
        VStack(spacing: 0) {
            Button {
                withAnimation(DS.Motion.soft) {
                    if isOpen { expanded.remove(group.name) } else { expanded.insert(group.name) }
                }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Text(group.name)
                        .vkFont(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Text("\(group.items.count)")
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.textSub)
                        .monospacedDigit()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSub)
                }
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        itemRow(item)
                    }
                }
                .padding(.leading, DS.Space.s)
            }
        }
        .padding(DS.Space.l)
        .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Radius.card))
    }

    @ViewBuilder
    private func itemRow(_ item: AppIndexItem) -> some View {
        Button {
            jump(item)
        } label: {
            HStack(spacing: DS.Space.s) {
                Text(item.title)
                    .vkFont(.body)
                    .foregroundStyle(DS.Palette.text)
                Spacer(minLength: 0)
                // 不画 chevron: 点它不会进到那一页, 只跳 Tab —— 画箭头会骗人。
                Text(AppIndexData.route(forGroup: item.group).title)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub.opacity(0.6))
            }
            .frame(minHeight: DS.Metric.rowMinH)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 跳转。**本仓没有统一的目的地路由层** —— 76 个目的地各自维护
    /// `@State private var showXxx` (如 SettingsView.swift:9-14), `destined()` 只是台账标记。
    /// 所以这里做的是**跳到该目的地所属的 Tab**, 而不是假装能直达任意页。
    private func jump(_ item: AppIndexItem) {
        let route = AppIndexData.route(forGroup: item.group)
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)   // 等 sheet 收起
            app.requestRoute(route)
        }
    }
}
