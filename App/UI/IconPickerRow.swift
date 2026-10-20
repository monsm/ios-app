//
//  IconPickerRow.swift
//  图标选择器页面包装 (2026-10-21)
//

import SwiftUI

/// App 图标选择页 —— 包一层 List 让 IconPicker 的 row 有容器
struct IconPickerRow: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List {
            Section {
                IconPicker()
                    .environmentObject(app)
            } footer: {
                Text("预览块底色与生成的图标位图逐字相同。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(XPalette.canvas)
        .navigationTitle("App 图标")
        .navigationBarTitleDisplayMode(.inline)
    }
}
