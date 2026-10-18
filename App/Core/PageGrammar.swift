//  PageGrammar.swift
//  页面骨架语法 —— 2026-10-18 全量重构新增。
//
//  ## 为什么需要它
//
//  重构前: 28 个文件各自实现页面头, 形态互不相同 ——
//    · CredentialsView 自己写 headerToolbar (3 行 9 个控件, 首屏 12+ 入口)
//    · 其余 27 个靠系统 navigationTitle + 各自 .toolbar
//  结果是同一件事 (排序/筛选/更多) 在不同页面长在不同位置、有不同层级。
//  这是"每个页面都乱"的根因 —— **不是控件不好看, 是没有统一的归类规则**。
//
//  ## 三条归类规则 (全 App 强制)
//
//  ### 1. 一屏只允许一个主操作
//     主操作 = 这个页面存在的理由 (凭证页=添加凭证, 记录页=重新读取, 备份页=生成备份)。
//     主操作用 PrimaryActionStyle, 且**同屏只能有一个**。
//
//  ### 2. 次级操作 <= 2 个, 以图标常驻
//     只放"高频且必须一眼可见"的: 搜索、选择。
//     超过 2 个就进溢出菜单 —— **不许再挤第三行**。
//
//  ### 3. 其余全部进「⋯」溢出菜单, 按语义分组
//     菜单分组顺序固定: 视图 / 整理 / 数据 / 危险。
//     危险操作 (删除/清空/销毁) 一律用 .destructive 且排最后。
//
//  ## 用法
//
//      KfPage(title: "凭证", subtitle: "共 3 条") {
//          // 内容
//      } primary: {
//          KfPrimaryAction("添加凭证", systemImage: "plus") { add() }
//      } secondary: {
//          KfIconAction("magnifyingglass", label: "搜索") { search() }
//          KfIconAction("checkmark.circle", label: "选择") { select() }
//      } overflow: {
//          KfMenuSection("视图") {
//              KfMenuItem("排序: \(sortKey.label)", systemImage: "arrow.up.arrow.down") { cycleSort() }
//              KfMenuItem("月历到期视图", systemImage: "calendar") { toggleCalendar() }
//          }
//          KfMenuSection("整理") {
//              KfMenuItem("整理建议", systemImage: "rectangle.3.offgrid") { organize() }
//          }
//      }

import SwiftUI

// MARK: - 页面骨架

/// 一屏的骨架: 标题 / 主操作 / 次级操作 / 溢出菜单 / 内容。
///
/// **所有新增页面必须用它** —— 这是"归类整理"能落地的唯一方式:
/// 语法本身规定了什么能常驻、什么必须进菜单, 而不是靠每个页面自觉。
struct KfPage<Content: View, Primary: View, Secondary: View, Overflow: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary
    @ViewBuilder let overflow: () -> Overflow

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                // 标题区: 大标题 + 一行状态 (D15: 34pt semibold)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(title)
                        .vkFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    if let subtitle {
                        Text(subtitle)
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.gutter)
                .padding(.top, DS.Space.s)

                content()
            }
            .padding(.bottom, DS.Space.xxl)
        }
        .dsScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 次级操作: 最多 2 个, 图标常驻 (规则 2)
            ToolbarItem(placement: .topBarTrailing) { secondary() }
            // 溢出菜单: 其余全部进这里 (规则 3)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    overflow()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: DS.Icon.md, weight: .semibold))
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多操作")
            }
        }
        // 主操作: 底部固定, 同屏唯一 (规则 1)
        .safeAreaInset(edge: .bottom) {
            primary()
                .padding(.horizontal, DS.Space.gutter)
                .padding(.bottom, DS.Space.s)
        }
    }
}

// MARK: - 语法件

/// 主操作按钮 (底部固定, 同屏唯一)。
struct KfPrimaryAction: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).vkFont(.headline, weight: .semibold)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Hit.min + DS.Space.s)
        }
        .buttonStyle(PrimaryActionStyle())
    }
}

/// 次级操作图标 (toolbar 里常驻, 最多 2 个)。
struct KfIconAction: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    init(_ systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.label = label; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Icon.md, weight: .semibold))
                .frame(width: DS.Hit.min, height: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// 溢出菜单的一个分组标题 + 内容。
struct KfMenuSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }

    var body: some View {
        Section(title) { content() }
    }
}

/// 溢出菜单的一项。
struct KfMenuItem: View {
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.role = role; self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
}
