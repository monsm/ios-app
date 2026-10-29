// 凭证工坊入口（三类凭证）
// 2026-10-29 从 CredentialStudio.swift（2424 行）拆出
import SwiftUI
import UIKit
import AVFoundation

struct StudioHome: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    /// embedded = 由外部 NavigationStack push (宿主已提供导航栏); 非 embedded 时自带导航栏
    var embedded: Bool = true
    /// 2026-10-29 修「首次进入点任一项立刻退出、再点才生效」：
    /// 原来三个 `.sheet(isPresented:)` 挂在 `List` 里的 `Group` 上 —— `Group` 在 List 内是**行**，
    /// 于是每个 sheet 的 presenting 宿主是一个列表行；第一次点开时 List 重算把那一行回收，
    /// sheet 立刻被拆掉（用户看到的"闪一下就退出"），第二次因为行已在稳定布局里才成功。
    /// 现在收成**一个 `.sheet(item:)` 并挂到 List 本身**（稳定祖先），不再有宿主被回收的问题。
    private enum Sheet: String, Identifiable {
        case pwd, temp, fp
        var id: String { rawValue }
    }
    @State private var sheet: Sheet?

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
        // 只有 List 装内容；标题 / 列表样式 / 工具栏 / sheet 全部挂在 **List 外层** ——
        // 挂进 List 的行级容器会让 sheet 的宿主随行回收，见上面 Sheet enum 的注释。
        List {
            Section("三类凭证") {
                fanoutRow("key.fill", "密码", "剪贴板即建 · 逐位回显 · 重复拦截 · 生成器",
                          label: "添加密码") { sheet = .pwd }
                fanoutRow("timer", "临时码",
                          "五场景 · 重叠检测 · 装修黄条 · 批量",
                          label: "添加临时码") { sheet = .temp }
                fanoutRow("touchid", "指纹",
                          "归属先行 · 沉浸式录入 · 删除双签",
                          label: "录入指纹") { sheet = .fp }
            }
            Section {
                Text("密码与指纹需现场靠近门锁下发; 临时码与 OTP 为本地台账管理， 锁端语义未定义的一次性/周期按时间窗推断 (标\"约\")。")
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
        .sheet(item: $sheet) { which in
            switch which {
            case .pwd:  PwdStudio(embedded: false)
            case .temp: TempCodeStudio()
            case .fp:   FpStudio()
            }
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