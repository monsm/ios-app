//
//  IconPicker.swift
//  App 图标选择器 (2026-10-21 从 SettingsView.swift 迁出)
//
//  这是**真实功能**: 本机换 App 图标, 且预览块底色必须与 mkicon.js 画的位图逐字相同。
//  tools/contrast.js 的 E6 检查会从本文件解析这些底色, 所以改色必须同时改两处。
//

import SwiftUI
import UIKit

    private struct IconOption: Identifiable {
        let id: String?      // nil = 默认图标
        let name: String
        let glyph: String
        let bg: [Color]
    }
    private var iconOptions: [IconOption] {
        [
            IconOption(id: nil, name: "默认", glyph: "lock.fill",
                       bg: [Color(hex: 0x5A55EC), Color(hex: 0x4338CA)]),
            IconOption(id: "AppIcon-Ring", name: "锁环", glyph: "record.circle",
                       bg: [Color(hex: 0x178040), Color(hex: 0x0F5A2C)]),
            IconOption(id: "AppIcon-Key", name: "钥匙", glyph: "key.fill",
                       bg: [Color(hex: 0x9A5B10), Color(hex: 0x713F12)]),
            IconOption(id: "AppIcon-Shield", name: "盾牌", glyph: "shield.fill",
                       bg: [Color(hex: 0x334155), Color(hex: 0x1E293B)]),
            // ---- 896 新增五款: 底色与 _audit1012/mkicon.js 画位图用的那五个值逐字相同 (两处改一处就要改两处),
            //      glyph 一律用**本仓已经在别处用过**的 SF Symbol 名 —— 新造符号名在真机上可能整个画不出来,
            //      而预览画不出白色图形只剩一块纯色方片的图标, 用户会以为 App 坏了。
            IconOption(id: "AppIcon-Home", name: "家门", glyph: "house.fill",
                       bg: [Color(hex: 0x2C5AA0), Color(hex: 0x2C5AA0)]),
            IconOption(id: "AppIcon-Bell", name: "警报", glyph: "bell.fill",
                       bg: [Color(hex: 0x9F1239), Color(hex: 0x9F1239)]),
            IconOption(id: "AppIcon-Pin", name: "定位", glyph: "location.fill",
                       bg: [Color(hex: 0x0E7490), Color(hex: 0x0E7490)]),
            IconOption(id: "AppIcon-Guard", name: "门盾", glyph: "lock.shield.fill",
                       bg: [Color(hex: 0x4B2E83), Color(hex: 0x4B2E83)]),
            IconOption(id: "AppIcon-Heart", name: "心记", glyph: "heart.fill",
                       bg: [Color(hex: 0x7C3AED), Color(hex: 0x7C3AED)]),
        ]
    }
    private var iconPickerRow: some View {
        // 896: 四款→九款之后这一排装不下了 (9×48 + 间距 ≈ 560pt, 远超 iPhone 宽度), 所以从
        // "标题在左、图排在右的一行"改成"标题在上、图排自适应换行"的两段式。
        // 用 LazyVGrid(adaptive) 而不是横向 ScrollView: 后者会把后几款藏在滚动区外,
        // 用户不知道自己有九款可选 —— 换肤这种"看一眼才想换"的界面不该先藏起来。
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("App 图标")
                .vkFont(.body)
                .foregroundStyle(DS.Palette.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: DS.Space.m)],
                      alignment: .leading, spacing: DS.Space.m) {
                ForEach(iconOptions) { opt in
                    Button { setIcon(opt.id) } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(LinearGradient(colors: opt.bg, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: opt.glyph)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundStyle(DS.heroFg)
                                )
                            if currentIcon == opt.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    // onSem 而非 .white: 角标底是 DS.Palette.ok, 它在深色档是浅绿 4ADE80,
                                    // 纯白压上去只有 1.74:1 (机检断言在 tools/contrast.js)。
                                    // 两层符号 (勾/圆盘) 谁吃第一色未实测, 已进验收单 — 两种顺序这里都可读。
                                    .foregroundStyle(DS.Palette.onSem, DS.Palette.ok)
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .accessibilityLabel(currentIcon == opt.id ? "当前图标 \(opt.name)" : "切换为\(opt.name)图标")
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .vkFont(.body)
        .foregroundStyle(DS.Palette.text)
    }
