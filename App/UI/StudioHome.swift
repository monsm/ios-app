// 凭证工坊入口（三类凭证）
// 2026-10-29 从 CredentialStudio.swift（2424 行）拆出
import SwiftUI
import UIKit
import AVFoundation

struct StudioHome: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// embedded = 由外部 NavigationStack push (宿主已提供导航栏); 非 embedded 时自带导航栏
    var embedded: Bool = true
    @State private var showAddPwd = false
    @State private var showTemp = false
    @State private var showFp = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }
    private var content: some View {
        List {
            Group {
                Section("三类凭证") {   // 177 四类凭证
                    fanoutRow("key.fill", "密码", "剪贴板即建 · 逐位回显 · 重复拦截 · 生成器",
                              label: "添加密码") { showAddPwd = true }
                    fanoutRow("clock.badge.chevron.right", "临时码",
                              "五场景 · 重叠检测 · 装修黄条 · 批量",
                              label: "添加临时码") { showTemp = true }
                    fanoutRow("touchid", "指纹",
                              "归属先行 · 沉浸式录入 · 删除双签",
                              label: "录入指纹") { showFp = true }
                }
                Section {
                    Text("密码与指纹需现场靠近门锁下发; 临时码与 OTP 为本地台账管理, 锁端语义未定义的一次性/周期按时间窗推断 (标\"约\")。")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("凭证工坊")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                if !embedded {
                    Button("关闭") { dismiss() }
                }
            } }
            .sheet(isPresented: $showAddPwd) { PwdStudio(embedded: false) }
            .sheet(isPresented: $showTemp) { TempCodeStudio() }
            .sheet(isPresented: $showFp) { FpStudio() }
        }
    }
    private func fanoutRow(_ icon: String, _ title: String, _ sub: String, label: String,
                           _ act: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            act()
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(width: DS.Icon.md + 8, height: DS.Icon.md + 8)
                    .variantPlate(DS.Palette.accentText.opacity(0.12), .iconBadge)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .vkFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                        .lineLimit(1)
                    Text(sub)
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label + " " + sub)
    }
}