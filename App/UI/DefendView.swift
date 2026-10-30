// 布防页（cmd25）—— 原版 APK 的 page-defend / page-defendhome 在 iOS 侧的对应实现。
//
// 与原版的三点差异，都写在这里而不是留给读者猜：
//   1. 原版把「外出 / 在家」做成两套视觉（两个入口卡 + 两张背景图）；协议里只有 control 一个自由度，
//      所以本机收成三档：撤防 / 不定期 / 时段 —— 视觉差异不承载语义，语义只落在 control 上。
//   2. 原版时段用「一天内秒数 / 2」编码（半秒）；本页 UI 用分钟选择器，落盘前经 DefendKit.protoSec 换算，
//      换算只有一个出口，避免某个入口忘了 ×2。
//   3. 原版有 ROM 版本门槛提示「请先升级门锁ROM」；本机用 PidMap.canDefend 判，不支持就直接不出这个入口
//      （设置页 NavigationLink 已经判过一次，这里再判一次是为了防深链/程序化入口绕过）。
import SwiftUI

struct DefendView: View {
    @EnvironmentObject var app: AppState

    @State private var mode: DefendMode = .off
    @State private var startMinute: Int = 22 * 60      // 默认 22:00 起
    @State private var endMinute: Int = 6 * 60 + 60    // 默认 07:00 止（跨午夜口径由 defendActive 处理）
    @State private var busy = false
    @State private var loaded = false

    var body: some View { vkBody.destined(.defend) }
    var vkBody: some View {
        Form {
            if !DefendService.allowed(app) {
                Section {
                    Text("这把锁的固件不支持布防（或型号不在布防白名单里）。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                } header: {
                    Text("不可用")
                }
            } else {
                statusSection
                modeSection
                if mode == .period { periodSection }
                actionSection
            }
        }
        .navigationTitle("布防")
        .variantList()
        .dsScreenBackground()
        .onAppear(perform: loadFromStore)
    }

    // MARK: - 现状

    private var statusSection: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                Image(systemName: DefendKit.isActive(DefendService.current(app))
                      ? "shield.lefthalf.filled" : "shield")
                    .font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DefendKit.isActive(DefendService.current(app))
                                     ? DS.Palette.ok : DS.Palette.textSub)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(DefendKit.summary(DefendService.current(app)))
                        .vkFont(.subheadline, weight: .medium)
                    Text("布防期间，自动开锁会被布防规则一票否决；已在布防时段内时，靠近门锁不会自动开门。")   // 2026-10-30：用户文案不写内部编号 F4
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
        } header: {
            Text("当前状态")
        }
    }

    // MARK: - 三档

    private var modeSection: some View {
        Section {
            ForEach(DefendMode.allCases) { m in
                Button {
                    mode = m
                } label: {
                    HStack(alignment: .top, spacing: DS.Space.s) {
                        Image(systemName: mode == m ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(mode == m ? DS.Palette.accentText : DS.Palette.textSub)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(m.title).vkFont(.subheadline, weight: .medium)
                            Text(m.subtitle)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("布防方式")
        }
    }

    // MARK: - 时段

    private var periodSection: some View {
        Section {
            Picker("开始", selection: $startMinute) {
                ForEach(0..<96, id: \.self) { i in
                    Text(minuteLabel(i * 15)).tag(i * 15)
                }
            }
            Picker("结束", selection: $endMinute) {
                ForEach(0..<96, id: \.self) { i in
                    Text(minuteLabel(i * 15)).tag(i * 15)
                }
            }
            if let bad = DefendKit.validate(mode: .period,
                                            startSec: startMinute * 60,
                                            endSec: endMinute * 60) {
                Text(bad)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.danger)
            } else if endMinute < startMinute {
                Text("跨午夜时段：\(minuteLabel(startMinute)) 到次日 \(minuteLabel(endMinute))。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
        } header: {
            Text("时段（每 15 分钟一档）")
        } footer: {
            Text("时段外门锁正常开锁，时段内进入布防。跨午夜指开始时间晚于结束时间。")
                .vkFont(.caption)
        }
    }

    // MARK: - 执行

    private var actionSection: some View {
        Section {
            BusyButton(title: actionTitle, systemImage: "shield.lefthalf.filled", isBusy: busy) {
                confirm()
            }
            .disabled(mode == .period && DefendKit.validate(mode: .period,
                                                           startSec: startMinute * 60,
                                                           endSec: endMinute * 60) != nil)
        }
    }

    private var actionTitle: String {
        switch mode {
        case .off: return "执行撤防"
        case .once: return "执行布防"
        case .period: return "保存时段并布防"
        }
    }

    // MARK: - 动作

    private func loadFromStore() {
        guard !loaded, let cfg = DefendService.current(app) else { loaded = true; return }
        mode = DefendMode(rawValue: cfg.control) ?? .off
        if mode == .period {
            let s = DefendKit.secFromProto(cfg.startSec)
            let e = DefendKit.secFromProto(cfg.endSec)
            startMinute = (s / 900) * 15
            endMinute = (e / 900) * 15
        }
        loaded = true
    }

    private func confirm() {
        guard !busy else { return }
        var detail = ""
        switch mode {
        case .off:
            detail = "退出布防后，门锁恢复正常开锁，自动开锁也会恢复。"
        case .once:
            detail = "门锁将进入不定期布防，直到你手动撤防。布防期间自动开锁会被否决。"
        case .period:
            detail = "时段 \(minuteLabel(startMinute)) – \(minuteLabel(endMinute)) 内布防；"
                   + "时段内自动开锁会被布防规则一票否决。"
        }
        let title = mode == .off ? "确认撤防" : "确认布防"
        confirmDestructive(title, detail, confirmTitle: title) {
            Task { await run() }
        }
    }

    private func run() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await DefendService.apply(app,
                                          mode: mode,
                                          startSec: mode == .period ? startMinute * 60 : 0,
                                          endSec: mode == .period ? endMinute * 60 : 0)
            // 回读校验与 cmd20 同口径：rc=0 只说明锁收了命令。布防状态以锁端状态帧为准，
            // 但锁端状态帧不带布防字段（DefendCfg 是本机记忆 + 锁端 control 的合成），
            // 所以这里只做"重新读一次锁状态"确认链路还活着，不宣称读到了布防。
            await app.refreshStatusQuietly(manual: true)
            app.showToast(mode == .off ? "已撤防" : "布防成功")
        } catch {
            app.showToast("布防失败： \(error.localizedDescription)")
        }
    }

    private func minuteLabel(_ m: Int) -> String {
        String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }
}
