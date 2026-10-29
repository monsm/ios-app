// 连接感知 · 视图（信号格 / 连接胶囊 / 蓝牙未开横幅）
// 2026-10-29 从 LinkSenseKit.swift（748 行）拆出。
import SwiftUI

struct RSSIBars: View {
    var level: Int                 // 0-4
    var tint: Color = DS.Palette.accentText
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? tint : DS.Palette.hairline)
                    .frame(width: 3, height: CGFloat(i + 1) + 3)
            }
        }
        .accessibilityLabel("信号" + LinkSense.rssiLabel(level))
    }
}

struct LinkPill: View {
    var state: LinkState
    var connectMs: Int? = nil
    var rssi: Int? = nil
    var source: String = ""
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
            // 228 色觉冗余: 三态不能只靠颜色 + 链路圈的虚实来分 —— 色觉障碍下 fill/dashed 几乎同形，
            // （原还有"灰阶预览"开关 AXFlags.grayPreview，2026-10-26 随该开关一起删除。）
            // 所以补一枚语义符号 (✓ / ⏳ / ✗) 当第三通道: 形状自己就说清状态。
            Image(systemName: redundancyIcon)
                .font(.system(size: DS.Icon.xs, weight: .bold))
                .accessibilityHidden(true)   // 文案与 accessibilityLabel 已经报了状态，符号不重复朗读
            Text(text)
                .vkFont(.caption, weight: .medium)
                .lineLimit(1)
            // 98 冷热标识: 已连接时标注来源 — 预热/回连("已预热") vs 用户触发的即连, 解释快慢差异
            if state == .ready, source != "" {
                Text(source)
                    .vkFont(.caption2, weight: .medium)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs + 1)
        // 底板用压暗的黑纱而不是同色洗底: 白字压白洗底实测只有 3.09~3.31:1 (对比 tools/contrast.js E4)
        .background(DS.heroPlate, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.38), lineWidth: 0.5))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
    private var icon: String {
        switch state {
        case .ready: return "link.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        // 2026-10-27：密钥未绑定 —— 连上了但开不了。用锁图标而不是链路图标，
        // 因为问题不在"链路上"而在"没钥匙"。
        case .notReady: return "lock.slash"
        default: return "link.circle.dashed"
        }
    }
    /// 228 的第二通道: 对勾=就绪、沙漏=握手中、叉=未连接。
    /// 刻意选**跨文化都读得懂**的三个符号，而不是三个不同样式的链路图标 ——
    /// 后者的差别正是这里要冗余掉的那个差别。
    private var redundancyIcon: String {
        switch state {
        case .ready: return "checkmark"
        case .connecting: return "hourglass"
        case .notReady: return "exclamationmark"
        default: return "xmark"
        }
    }
    // 68 拟人状态文案: "门锁在线，随时可开"
    private var text: String {
        switch state {
        case .ready: return "门锁在线， 随时可开"
        case .connecting: return "正在敲门…"
        // 2026-10-27 截图核对修复：这一态原先不存在，于是蓝牙一连上就报「随时可开」，
        // 而密钥没绑定根本开不了 —— 用户点下去只会失败。
        case .notReady: return "已连接 · 密钥未绑定"
        default: return "未连接"
        }
    }
    private var tint: Color {
        switch state {
        case .ready: return DS.heroTint(Color(hex: 0xBBF7D0))
        case .connecting: return DS.heroFg.opacity(0.9)
        // 密钥未绑定用警告色（与下方黄条同色系），让"这条不是好消息"一眼可见
        case .notReady: return DS.heroTint(Color(hex: 0xFDE68A))
        default: return DS.heroFg.opacity(0.75)
        }
    }
    private var accessibilityText: String {
        text + (rssi.map { " 信号" + LinkSense.rssiLabel(LinkSense.rssiLevel($0)) } ?? "")
    }
}

struct BLEOffBanner: View {
    /// true = 本 App 没有蓝牙权限（要去设置里**允许**）；false = 系统蓝牙开关关着。
    var denied: Bool = false
    var onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: denied
                      ? "exclamationmark.shield.fill"
                      : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.warn)
                    .accessibilityHidden(true)
                Text(denied
                     ? "本 App 没有蓝牙权限 — 到设置里允许后， 才能配对与开锁"
                     : "蓝牙已关闭 — 打开系统蓝牙后， 门锁才能被唤醒")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("去开启", systemImage: "chevron.right")
                    .vkFont(.footnote, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s + 2)
            .variantCallout(DS.Palette.warn, .control, wash: 0.12)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(denied
                            ? "本 App 没有蓝牙权限， 点按前往系统设置允许"
                            : "蓝牙已关闭， 点按前往系统设置开启")
        .accessibilityHint(denied ? "到系统设置允许本 App 使用蓝牙" : "到系统设置打开蓝牙开关")
    }
}



// 2026-10-29：FailKind / StateHop 从 LinkSenseKit 搬来（纯数据定义，与视图同层）。