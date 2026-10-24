// 设备 Tab — 门锁总控页。
// 层级: 设备身份 → 连接与电量 → 需要处理的异常 → 开锁主控 → 快捷操作 → 最近开门。
// 开锁是全App最高频动作, 因此占据最大视觉权重并置于拇指可达区中部。
import SwiftUI
import UIKit


// ================= 校时页 (App synctime) =================
struct SyncTimeView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var result = ""
    @State private var failed = false

    private var resultTone: XToneColor { failed ? .danger : .ok }

    /// 锁钟与手机钟的偏差（秒）。nil = 拿不到锁钟
    ///
    /// 这是本页唯一有信息量的数字 —— 校准的意义就是消掉它。
    /// 原来只显示两行时间文字，用户无法判断"差多少"。
    private var skewSeconds: Int64? {
        guard let lt = app.status?.lockTime, lt > 0 else { return nil }
        let lockUnix = Int64(ZKProtocol.protoSecondsToUnix(lt))
        return Int64(Date().timeIntervalSince1970) - lockUnix
    }

    var body: some View { vkBody.destined(.syncTime) }
    var vkBody: some View {
        XScreen("同步时间", subtitle: "锁钟偏差 · 写入手机时间") {
            if app.current != nil {
                // HTML 卡1「偏差范围」—— App 之前缺这一张
                rangeCard
                skewCard
                clockCard
            } else {
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        secLabel("同步时间")
                        Text("请先在设备页选择一把门锁")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                    }
                }
                .xScrollLift()
            }
            actionCard
        }
    }

    /// HTML 卡1「偏差范围」—— 允许的偏差区间与当前是否落在区间内
    private var rangeCard: some View {
        let skew = skewSeconds
        let absSkew = abs(skew ?? 0)
        let inRange = skew != nil && absSkew <= 5
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("偏差范围")
                HStack(alignment: .top, spacing: XSpace.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("允许区间").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text("±5 秒").xFont(.footnote, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        Text(inRange ? "在区间内" : (skew == nil ? "未读到" : "超出区间"))
                            .xFont(.footnote, weight: .semibold)
                            .foregroundStyle(inRange ? XPalette.ok : XPalette.warn)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("偏差在 ±5 秒内视为准 —— 超过 180 秒锁侧校验会失败。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── 偏差卡（核心信息）──
    //
    // 用一根居中刻度条表示偏差: 中心 = 0 秒，左右各代表偏快/偏慢。
    // 阈值: |skew| <= 5 视为准（绿）；<= 60 提醒（黄）；否则警告（红）。
    // 超过 300 秒时刻度条封顶，但文字仍显示真实值。
    private var skewCard: some View {
        let skew = skewSeconds
        let absSkew = abs(skew ?? 0)
        let tone: Color = skew == nil ? XPalette.textTertiary
            : (absSkew <= 5 ? XPalette.ok : (absSkew <= 60 ? XPalette.warn : XPalette.danger))
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("锁钟偏差")

                // 六图改造 (2026-10-23): 偏差数字提到 **44px 主角档 + 光晕**（图 1 语言）。
                //
                // 这一页唯一有信息量的数字就是"差多少秒"，校准的全部意义就是消掉它。
                // 之前是 19pt title2，与卡片标题同级 —— 用户在页面上要"找"这个数。
                // 图 1 Health Age 的 -4.7 是 44px 起 + 同色辉光，一屏只有它这么大。
                HStack(alignment: .firstTextBaseline, spacing: XSpace.xs) {
                    XHeroNumber(
                        text: skewText(skew),
                        size: DSFont.hero,
                        color: tone,
                        glow: skew != nil)
                    Text(skewWord(skew))
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                    Spacer(minLength: 0)
                }
                // 一个"−12 秒"的裸数字对上读屏是没有上下文的。
                // 把标签、数值、方向合成一句完整的话。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(skew == nil
                    ? "锁钟偏差，尚未读到"
                    : "锁钟偏差 \(skewText(skew))，\(skewWord(skew))")

                if let s = skew {
                    skewBar(s)
                } else {
                    Text("还没有读到锁钟 —— 靠近门锁后下拉刷新")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                }

                Text("校准会把手机时间写进锁内 (cmd 0E)。偏差为正是锁慢，为负是锁快。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .xScrollLift()
    }

    /// 偏差刻度条：中心 0，向左偏快、向右偏慢。
    /// 用设计系统的 XSkewBar（形状定义在 Components 里，
    /// 不在页面里手搓 Rectangle + cornerRadius）。
    ///
    /// 注：这一段注释此前被复制粘贴了三次，属于编辑残留，已合并。
    private func skewBar(_ skew: Int64) -> some View {
        let absSkew = abs(skew)
        let tone: Color = absSkew <= 5 ? XPalette.ok
            : (absSkew <= 60 ? XPalette.warn : XPalette.danger)
        return XSkewBar(value: skew, tone: tone)
    }

    private func skewText(_ skew: Int64?) -> String {
        guard let s = skew else { return "—" }
        if s == 0 { return "0 秒" }
        return (s > 0 ? "+" : "") + String(s) + " 秒"
    }

    private func skewWord(_ skew: Int64?) -> String {
        guard let s = skew else { return "" }
        let absS = abs(s)
        if absS <= 5 { return "准" }
        if absS < 60 { return s > 0 ? "锁慢" : "锁快" }
        if absS < 3600 { return (s > 0 ? "锁慢 " : "锁快 ") + String(absS / 60) + " 分" }
        return (s > 0 ? "锁慢 " : "锁快 ") + String(absS / 3600) + " 小时"
    }

    // ── 两侧时钟对照 ──
    private var clockCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("对照")
                LabeledRow("锁内时钟",
                           app.status?.lockTime.map { ProtoTime.localStr($0) } ?? "—")
                LabeledRow("手机时间",
                           DateFormatter.localizedString(from: Date(),
                                                         dateStyle: .medium,
                                                         timeStyle: .medium))
            }
        }
        .xScrollLift()
    }

    // ── 动作卡 ──
    private var actionCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("写入")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                XBusyButton(title: "将手机时间同步到锁内",
                            systemImage: "clock.arrow.circlepath",
                            busy: busy) {
                    Task { await run() }
                }
                .disabled(app.current == nil)
                if !result.isEmpty {
                    Label(result, systemImage: failed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .xFont(.footnote)
                        .foregroundStyle(resultTone.color)
                }
                Text("请将手机靠近门锁 · 请确保手机时间准确")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .xScrollLift()
    }

    private func run() async {
        busy = true
        defer { busy = false }
        failed = false
        result = ""
        // 第八十八批: 校时页原先不先绑锁就直接 syncTime (服务层按自己的 curMac 取钥)，
        // 于是"在这个锁的页面点校时，19/0E 命令发向上次连过的那把锁"。入口钉住 + 非空才走。
        let m = app.currentMac
        guard !m.isEmpty else {
            failed = true; result = "未选择门锁"
            app.showToast("未选择门锁")
            return          // defer 会复位
        }
        do {
            try await app.lock.ensureConnected(mac: m)
            // 留存口径：校时这一步本机不落任何数 —— 记录的时间戳本来就来自锁端回包 (lockTimeStr)。
            try await app.lock.syncTime()
            result = "同步成功"
            XHaptics.success()
            app.showToast("时间已同步")
        } catch {
            failed = true
            result = "同步失败：" + error.localizedDescription
        }
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 标签 / 值 的读数行 —— 形状即规范的 §7.7 **MetricRow**。
///
/// 规范把这一行写成**两个数**, 并点名批评过把它们合成一个的写法:
///   · **视觉行高 20pt** —— 14pt 字 / 行高 1.33。参考图里这是紧凑文本行, 不是 44pt 的行。
///   · **触摸区 44pt** —— 只有需要点击时才存在, 且可重叠。
///
/// 本行**不可点**（它是读数, 不是入口）, 所以只执行第一个数:
/// `minHeight: 20`。写 44 会让三行读数占 132pt, 而它本该占 60pt ——
/// 那正是规范 §7.7 记的那个返工项。
struct LabeledRow: View {
    var label: String
    var value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: XSpace.s) {
            // 668: 这类"中文标签 + 英文缩写/数字"的行最容易看出中西文挤在一起, 统一走排版加距 (不插字符)
            cjkSpaced(label).foregroundStyle(XPalette.textSub)
            Spacer(minLength: XSpace.m)
            cjkSpaced(value)
                // 规范 §4.3: 数字 tabular-nums, 否则值变化时整行宽度跳动。
                .monospacedDigit()
                .foregroundStyle(XPalette.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(2) // MAC/时间等长值换行而不是溢出
                .fixedSize(horizontal: false, vertical: true)
        }
        .xFont(.subheadline)
        // 视觉行高 20（规范 §7.7 实测 19.6）。触摸区另计 —— 本行不可点, 不补 44。
        .frame(minHeight: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

