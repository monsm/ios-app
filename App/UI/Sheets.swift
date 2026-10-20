// 功能页集合: 添加设备/配网 · 添加密码 · 录指纹 · 设备信息 · 固件 DFU · 钥匙串硬件 · 网关 · 成员 · 动态 · 备份
// 通用约定:
//   1) 破坏性/不可逆动作 (删记录、写硬件、升级固件) 一律先确认, 走全局 confirmDestructive 或 confirmationDialog;
//   2) 纯 VStack 页面套 ScrollView, 大字号下不溢出;
//   3) 装饰性图标 .accessibilityHidden(true), 状态不靠颜色单通道传达。
import SwiftUI
import UIKit
import UniformTypeIdentifiers







// ================= 固件更新 (checkfirmwareupdate: 导入 zip → cmd22 → Nordic DFU) =================
// 包4 全流程: 体检单+三勾 (137/1027/1035) → 版本并排 (143) → 三段进度+剩余时间 (138/139) →
// 141 断点续传的**替代** = 整包重传 (DFU 协议无续传定义, CAPABILITY §6): 下面三处就是替代方案本身
// —— 中断提示 (:1331) / 失败安抚页 (:1618) / 「重新升级 (整包重传)」按钮 (:1650)，
// 配合三段进度 (138/139) 压低重传成本。界面上不出现"续传/接着传"这种词。
// 禁退保护 (140) → 完成自动校验 (148) / 失败安抚页 (142/1037); 本地清单 (513/145) 与历史 (147)。
// DFUKit 为只读依赖 — 分段/速率/校验编排全部在视图层完成, 不改协议命令集。
struct FirmwareView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bleSvc = BLEService.shared
    @State private var fw: FirmwarePackage?
    @State private var showPicker = false
    @State private var running = false
    @State private var failed = false
    @State private var failReason = ""   // 2026-10-15 走查: 单锁失败原先只置 failed, 原因被丢掉 (队列那侧有逐把 note, 单锁反倒没有)
    @State private var showUpgradeConfirm = false
    @State private var showQueueConfirm = false   // 144 队列也要过同一道确认 (原先它直接开刷)
    @State private var stage = 0              // 138: 0 准备 / 1 传输 / 2 校验
    @State private var pct = 0.0
    @State private var remainText = ""        // 139 剩余时间
    @State private var tickBackup = false     // 1035 已生成升级前备份
    @State private var tickTime = false       // 1027 时间充足
    @State private var showLeave = false      // 140 禁退确认
    @State private var verifyText = ""        // 148
    @State private var verified = false
    // 139 速率估算状态 (%/秒, EMA 平滑)
    @State private var lastProg: (pct: Double, at: TimeInterval)? = nil
    @State private var rate: Double = 0

    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    private func sizeText(_ n: Int) -> String { Self.bytes.string(fromByteCount: Int64(n)) }

    private var mac: String { app.current?.mac ?? "" }
    private var curFw: String {
        let live = app.current?.fw ?? ""
        return live.isEmpty ? (app.snapshot?.firmware ?? "") : live
    }
    // 137/1027 体检单: 电量与蓝牙自动判定, 备份/时间两项由用户勾选确认
    private var battPct: Int {
        if let s = BatteryCare.latest(mac)?.pct, s >= 0 { return s }
        return app.snapshot?.powerLevel ?? -1
    }
    private var battOk: Bool { battPct > 30 }
    private var checklistOk: Bool { battOk && bleSvc.isPoweredOn && tickBackup && tickTime }
    private var lastBackupText: String {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        guard let last = hist.last else { return "从未备份" }
        let d = Int(Date().timeIntervalSince1970 * 1000 - last) / 86_400_000
        return d <= 0 ? "今天备过" : "\(d) 天前"
    }
    /// 143 版本并排结论
    private var compareTag: (text: String, tone: ToneColor)? {
        guard let v = fw?.version else { return nil }
        if curFw.isEmpty { return ("可选升级", .neutral) }
        if FirmwareKit.versionLt(curFw, v) { return ("推荐升级", .ok) }
        if FirmwareKit.versionLt(v, curFw) { return ("低于当前版本", .warn) }
        return ("与当前版本相同", .neutral)
    }

    /// 内容是否已经嵌在外部导航容器里。2026-10-15 走查 §7.4-16: 本页自带 NavigationStack, 而设备页快捷格
    /// 的 `quickDestination` 是 **push** 进来它的 (外面那层栏已经在) ⇒ 不传 true 就叠出两层导航栏。
    /// 形状照同文件上方 `AddPwdView` / `StartAddFpView` 的 embedded 抄 —— 作者已有的解法, 不另造第三套。
    var embedded: Bool = false

    @ViewBuilder
    private var content: some View {
            List {
                if running {
                    progressSection       // 138/139/140
                } else if failed {
                    failureSection        // 142/1037
                } else {
                    currentSection
                    firstGlanceSection    // 825 首检一眼 (版本三处真相摊开)
                    if fw != nil { compareSection }   // 143
                    noticeSection
                    packageSection        // 513/145
                    preflightSection      // 137/1027/1035
                    resultSection         // 148
                    historySection        // 147
                }
            }
            .navigationTitle("检查固件更新")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if running {
                        // 140 禁退保护: 升级中点关闭需二次确认
                        Button("升级中…") { showLeave = true }
                            .foregroundStyle(DS.Palette.warn)
                            .accessibilityLabel("升级进行中, 点按可确认离开")
                    } else {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            // 140 禁退保护: 升级中禁用下滑手势关闭
            .interactiveDismissDisabled(running)
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [UTType.zip], allowsMultipleSelection: false) {
                importZip($0)
            }
            .confirmationDialog("升级门锁固件", isPresented: $showUpgradeConfirm, titleVisibility: .visible) {
                Button("开始升级", role: .destructive) { Task { await upgrade() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("升级过程门锁会重启并进入 DFU 模式，期间无法开门。若中途失败必须重新升级直到成功。")
            }
            // 144 队列与单锁同一道确认 (形状逐字照抄上面那段): 一次点下去要刷 N 把, 更该先问一句
            .confirmationDialog("排队逐把升级", isPresented: $showQueueConfirm, titleVisibility: .visible) {
                Button("开始升级 \(queueSel.count) 把", role: .destructive) { Task { await runQueue() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("每把都会重启并进入 DFU 模式，期间无法开门；一把失败不中断其余各把。上面那张体检单是按单把估的电量与时间，\(queueSel.count) 把请把这个时长乘以 \(queueSel.count)。")
            }
            .confirmationDialog("升级进行中", isPresented: $showLeave, titleVisibility: .visible) {
                Button("继续等待", role: .cancel) { }
                Button("仍要离开 (传输会中断)", role: .destructive) { DFURunner.cancelActive(); dismiss() }
            } message: {
                Text("固件传输中断后没有断点续传, 需要整包重传。建议等传输结束后再离开。")
            }
    }

    var body: some View { vkBody.destined(.firmware) }
    var vkBody: some View {
        // AnyView 擦平两分支类型差异 (与 AddPwdView 同一写法): 两支只差最外层那一只容器
        let base = embedded ? AnyView(content) : AnyView(NavigationStack { content })
        // APK 对照 (CheckfirmwareupdatePage.setKeepScreenOn): 传输/校验期间不许自动锁屏 ——
        // 屏一黑本进程就被系统挂起, DFU 的 32 字节分包写会当场断掉, 而屏上还停在"正在传输"。
        return base.keepingScreenAwake(running)
    }

    // ---------- 当前固件 (1019 服役天数) ----------
    private var currentSection: some View {
        Section("当前固件") {
            LabeledRow("门锁", app.displayName)
            LabeledRow("锁内版本", curFw.isEmpty ? "未知" : "v" + curFw)
            LabeledRow("固件服役", fwAgeText)
        }
    }
    /// 1019: 从本机首次读到该版本起算 (诚实口径), 超一年提示看说明
    private var fwAgeText: String {
        guard let s = BatteryCare.fwSince(mac, fw: curFw) else { return "首次读到后起算" }
        let days = Int(Date().timeIntervalSince1970 * 1000 - s.at) / 86_400_000
        return days > 365 ? "\(days) 天 · 已超一年, 建议读读发行说明" : "\(days) 天"
    }

    // ---------- 143 版本并排对比 ----------
    private var compareSection: some View {
        let tag = compareTag
        return Section {
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("当前")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(curFw.isEmpty ? "未知" : "v" + curFw)
                        .vkFont(.subheadline, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
                VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                    Text("目标")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(fw?.version.map { "v" + $0 } ?? "未知")
                        .vkFont(.subheadline, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前版本 \(curFw.isEmpty ? "未知" : curFw), 目标版本 \(fw?.version ?? "未知")")
            if let tag {
                StatusPill(text: tag.text,
                           systemImage: tag.tone == .ok ? "checkmark.seal" : (tag.tone == .warn ? "exclamationmark.triangle" : "info.circle"),
                           tone: tag.tone)
            }
        } header: {
            Text("版本对比")
        }
    }

    // ---------- 升级须知 + 1036 已知问题清单 ----------
    private var noticeSection: some View {
        Section("升级须知") {
            Text("• 更新过程中请不要使用门锁\n• 手机与门锁距离保持在 1 米内\n• 更新失败必须重新更新，直到更新成功")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("已知问题与规避") {
                Text("• 升级后门锁重启, 时间窗凭证失效 — 校准时间即可恢复\n• 升级中门锁广播名变为 ZkDFU、MAC 尾字节 +1, 属正常现象\n• 电量低于 30% 时升级失败率高, 体检单会拦截")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .vkFont(.footnote)
        }
    }

    // ---------- 825 固件首检引导 (Apple Support 那一形态) ----------
    // 创意原句两半：「首次进入显示当前版本占位」+「比对出厂版本清单按钮」。两半分开处理：
    //  · 占位这一半是真做得到的 —— 读不到当前版本时明写"没读到"，并说清为什么 (没连过锁 = 没发过 03 状态查询)。
    //  · 「出厂版本清单」**本机没有这张表**：全仓版本真相只有三处 —— 锁侧 03 快照回的 firmware 字段、
    //    本机每次读到过的版本历史 (FirmwareHistory)、导入过的包名 (kf_fwlib)。所以这里把这三处一次摊开，
    //    而不是凭空造一张厂商对照表：点进去只有一句假话的那种按钮，本仓宁可不放。
    @ViewBuilder
    private var firstGlanceSection: some View {
        let obs = FirmwareHistory.observations(mac: mac)
        let lib = BatteryCare.fwlib
        Section {
            LabeledRow("锁上读到的版本", curFw.isEmpty ? "没读到 · 先连一次锁" : curFw)
            LabeledRow("本机读到过的版本",
                       obs.isEmpty ? "还没有观测记录"
                       : obs.prefix(3).map { $0.fw + "(" + $0.day + ")" }.joined(separator: " · "))
            LabeledRow("导入过的固件包",
                       lib.isEmpty ? "本机还没有包" : "\(lib.count) 个 · 最近 \(lib.first?.version ?? "未知")")
        } header: {
            Text("进这一页先对一眼")   // 825 进这一页先对一眼
        } footer: {
            Text("没有「出厂版本对照表」可点：厂商云已停服，本机只有上面这三处版本真相。"   // 513/145 没有
                 + "要升级就带自己的包来，比对以锁上读到的那一个为准。")
                .vkFont(.caption2)
        }
    }

    // ---------- 513/145 固件更新包 + 本地清单 ----------
    private var packageSection: some View {
        let lib = BatteryCare.fwlib
        return Section {
            if fw == nil {
                EmptyState(systemImage: "shippingbox",
                           title: "尚未选择固件包",
                           message: "导入厂商提供的 .zip 更新包后即可开始升级。",
                           actionTitle: "选择固件包") { showPicker = true }
            } else {
                Button("选择固件更新包 (.zip)") { showPicker = true }
                    .frame(minHeight: DS.Hit.min)
                if let fw {
                    LabeledRow("包版本", fw.version ?? "未知")
                    LabeledRow("固件", "\(sizeText(fw.binSize)) + init \(sizeText(fw.datSize))")
                    LabeledRow("来源", fw.sourceName)
                }
            }
            // 513/145: 厂商云停服后唯一来源是本机文件 — 清单列明"无网络可执行"的范围
            if !lib.isEmpty {
                DisclosureGroup("本地固件包清单 (\(lib.count))") {
                    ForEach(lib) { item in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(item.name)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("v\(item.version) · \(sizeText(item.size)) · \(dateShort(item.at))")
                                .vkFont(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .vkFont(.footnote)
            }
        } header: {
            Text("固件更新包")
        } footer: {
            if !lib.isEmpty {
                Text("清单只记出处, 升级时仍需重新选择文件 (包体不落库)。")
            }
        }
    }

    // ---------- 137/1027/1035 升级前体检单 ----------
    private var preflightSection: some View {
        Section {
            checkRow(icon: "battery.50percent", ok: battOk,
                     title: "锁电量 > 30%",
                     detail: battPct < 0 ? "未读到电量 — 请先连接门锁刷新" : "当前 \(battPct)%")
            checkRow(icon: "antenna.radiowaves.left.and.right", ok: bleSvc.isPoweredOn,
                     title: "手机蓝牙已开启",
                     detail: bleSvc.isPoweredOn ? "蓝牙正常" : "请打开系统蓝牙")
            Button { tickBackup.toggle() } label: {
                checkRow(icon: "externaldrive.badge.checkmark", ok: tickBackup,
                         title: "已生成升级前备份",   // 1035
                         detail: "上次备份 \(lastBackupText) · 生成入口在 设置-备份与恢复")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("已生成升级前备份")
            .accessibilityAddTraits(tickBackup ? [.isSelected] : [])
            Button { tickTime.toggle() } label: {
                checkRow(icon: "clock", ok: tickTime,
                         title: "时间充足 (约 10 分钟)",   // 1027
                         detail: "传输 + 重启 + 校验, 全程请守在门边")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("时间充足")
            .accessibilityAddTraits(tickTime ? [.isSelected] : [])
            // 144 批量排队升级: 同型号的多把锁勾选后**逐把串行**升级 (DFU 期间手机与锁都是独占态,
            // 并行既抢 BLE 又抢 bootloader 会话); 队列只做外层编排, 单锁那条链一字未改。
            let peers = app.devices.filter { $0.pid == app.current?.pid && $0.mac != app.current?.mac }
            if !peers.isEmpty {
                Section("批量排队升级") {   // 144 批量排队升级
                    ForEach(peers, id: \.mac) { kc in
                        VariantToggle(LockArchive.displayName(kc), isOn: Binding(
                            get: { queueSel.contains(kc.mac) },
                            set: { on in if on { queueSel.insert(kc.mac) } else { queueSel.remove(kc.mac) } }))
                            .frame(minHeight: DS.Hit.min)
                    }
                    if !queueSel.isEmpty {
                        BusyButton(title: "排队逐把升级 (\(queueSel.count) 把)",
                                   systemImage: "square.stack.3d.up", isBusy: running,
                                   disabled: fw == nil || !checklistOk) {
                            // 2026-10-15 走查: 这颗原先既不查体检单也不弹确认, 一点就直接开刷 N 把 ——
                            // 而下面单锁那颗两样都有 (1442 那张 confirmationDialog)。DFU 是不可逆动作
                            // (锁重启进 bootloader、期间不能开门、断了只能整包重传), 门槛按"几把"分叉
                            // 是反着的: 一次点击覆盖的锁越多, 该问的那一句越不能省。
                            // 如实写下这一道闸**没覆盖到**的: checklistOk 里的电量/时间两项都是按
                            // app.current 那一把估的 (battOk 读当前锁), 队列里其余各把的电量这页读不到
                            // —— 逐把连一次再决定要等一次真机窗口, 不在这里假装已经做了。
                            showQueueConfirm = true
                        }
                    }
                    if !queueNote.isEmpty {
                        Text(queueNote).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(queueOutcomes.enumerated()), id: \.offset) { _, o in
                        Text((o.ok ? "✓ " : "✗ ") + o.name + " · " + o.note)
                            .vkFont(.caption2)
                            .foregroundStyle(o.ok ? DS.Palette.ok : DS.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("同型号锁才可共用同一个固件包; 队列一把失败不中断, 结果逐把列出。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            BusyButton(title: "开始升级",
                       systemImage: "arrow.down.circle.fill",
                       isBusy: false,
                       disabled: fw == nil || !checklistOk) {
                showUpgradeConfirm = true
            }
        } header: {
            Text("升级前体检")
        } footer: {
            Text("体检单全绿才能开始 — 电量与蓝牙自动判定, 备份与时间两项由你确认。协议里没有门磁状态位 (CAPABILITY §5)，门开没开只能你自己看，原案的「门已关」这一项本机做不了。请在门锁敞开时进行更新。")
        }
    }
    private func checkRow(icon: String, ok: Bool, title: String, detail: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DS.Icon.sm, weight: .semibold))
                .foregroundStyle(ok ? DS.Palette.ok : DS.Palette.textSub)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.text)
                Text(detail)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
        .accessibilityElement(children: .combine)
    }

    // ---------- 138/139/140 升级中 ----------
    private var progressSection: some View {
        Section("升级中") {
            HStack(spacing: DS.Space.xs) {
                stageSeg("准备", 0)
                stageSeg("传输", 1)
                stageSeg("校验", 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("升级阶段: \(stage == 0 ? "准备" : stage == 1 ? "传输" : "校验")")
            ProgressView(value: min(pct, 100), total: 100)
                .accessibilityLabel("传输进度 \(Int(pct))%")
            HStack(spacing: DS.Space.s) {
                Text("\(Int(pct))%")
                    .vkFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textSub)
                Spacer(minLength: DS.Space.s)
                if !remainText.isEmpty {
                    Text(remainText)
                        .vkFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.accentText)
                }
            }
            if !verifyText.isEmpty {
                Text(verifyText)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("升级中请勿离开本页、请勿使用门锁", systemImage: "lock.shield")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func stageSeg(_ label: String, _ i: Int) -> some View {
        let tone: ToneColor = stage > i ? .ok : (stage == i ? .accent : .neutral)
        return HStack(spacing: DS.Space.xxs) {
            Circle().fill(tone.color).frame(width: 8, height: 8)
            Text(label)
                .vkFont(.caption)
                .foregroundStyle(stage >= i ? DS.Palette.text : DS.Palette.textSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xs)
        .variantPlate(DS.Palette.surfaceAlt, .capsule)
    }

    // ---------- 148 结果 ----------
    @ViewBuilder
    private var resultSection: some View {
        if !verifyText.isEmpty {
            Section("升级结果") {
                Label {
                    Text(verifyText).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: verified ? "checkmark.circle.fill" : "questionmark.circle")
                        .accessibilityHidden(true)
                }
                .vkFont(.footnote)
                .foregroundStyle(verified ? DS.Palette.ok : DS.Palette.textSub)
            }
        }
    }

    // ---------- 147 升级历史 ----------
    @ViewBuilder
    private var historySection: some View {
        let hist = BatteryCare.dfuHist
        if !hist.isEmpty {
            Section("升级历史") {
                ForEach(hist) { r in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(r.ok ? DS.Palette.ok : DS.Palette.danger)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("\(r.name) · \(r.ok ? "成功" : "失败")")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(fromToText(r) + " · " + dateShort(r.at)
                                 + (r.ms.map { " · 耗时 " + Self.durText($0) } ?? ""))
                                .vkFont(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func fromToText(_ r: DFURecord) -> String {
        let f = r.from.isEmpty ? "?" : r.from
        let t = r.to.isEmpty ? "?" : r.to
        return "v\(f) → v\(t)"
    }
    /// 147 耗时文案: <60 秒报秒, 否则分+秒; 旧记录没这个字段就整段不显示 (r.ms == nil)
    private static func durText(_ ms: Double) -> String {
        // 2026-10-14: 旧写法先四舍五入再判单位 => "60 秒" / "1 分 60 秒" 非法读数 (59.6s / 119.6s)。
        // 先取整成总秒数, 再拆分。
        let s = Int((ms / 1000).rounded())
        if s < 60 { return "\(s) 秒" }
        return "\(s / 60) 分 \(s % 60) 秒"
    }

    // ---------- 142/1037 失败安抚页 ----------
    @ViewBuilder
    private var failureSection: some View {
        Section("升级失败") {
            // 2026-10-15 走查: 失败原因原先被丢掉 —— catch 里只置 failed, 这一屏只剩四条通用排查;
            // 同一条 DFU 链的队列版 (queueOutcomes) 每条都带 note, 单锁反倒不说。补上实际那一句。
            if !failReason.isEmpty {
                Label("本次失败: " + failReason, systemImage: "xmark.octagon")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label("门锁没有损坏", systemImage: "lock.shield")
                    .vkFont(.headline)
                    .foregroundStyle(DS.Palette.text)
                Text("传输中断后没有断点续传, 重新执行一次完整升级即可。若门锁仍显示 DFU 或白灯, 属升级模式的正常表现, 重传成功后会自动恢复。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Label("锁电量是否 > 30% — 低电是升级失败首因", systemImage: "1.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Label("与门锁距离是否在 1 米内", systemImage: "2.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Label("手机蓝牙是否被其他连接占用", systemImage: "3.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Label("等 1 分钟让门锁退出升级模式, 再重试", systemImage: "4.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            BusyButton(title: "重新升级 (整包重传)",
                       systemImage: "arrow.clockwise",
                       isBusy: false,
                       disabled: !checklistOk) {
                showUpgradeConfirm = true
            }
            Button {
                failed = false
                showPicker = true
            } label: {
                Label("重新选择固件包", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
            }
            .buttonStyle(SecondaryActionStyle())
            Button("返回正常使用") { dismiss() }
                .buttonStyle(SecondaryActionStyle())
        }
    }

    // ---------- 动作 ----------
    private func importZip(_ result: Result<[URL], Error>) {
        guard running == false, let url = try? result.get().first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try FirmwareKit.parse(zipData: [UInt8](data), fileName: url.lastPathComponent)
            fw = parsed
            failed = false
            verified = false
            verifyText = ""
            BatteryCare.addFWLib(name: url.lastPathComponent, version: parsed.version, size: data.count)   // 513/145
            app.showToast("固件包已解析" + (parsed.version.map { " · v\($0)" } ?? ""))
        } catch {
            app.showToast("固件包无法识别: \(error.localizedDescription)")
        }
    }

    // 144 批量排队升级的状态
    @State private var queueSel: Set<String> = []
    @State private var queueNote = ""
    @State private var queueOutcomes: [DFURunner.QueueOutcome] = []

    /// 144: 排队逐把升级 (同型号锁共用同一个固件包; 串行, 一把失败不中断)
    private func runQueue() async {
        guard let fw, !running, !queueSel.isEmpty else { return }
        running = true
        queueOutcomes = []
        queueNote = ""
        defer { running = false }
        // 2026-10-15 走查: 队列原先只跑传输 —— 既不写 147 升级历史, 也不做 148 版本复核回写,
        // 而单锁那条链 (upgrade()) 两样都有。少后一样的后果不是"台账少一行"这么轻: 刷成功的锁
        // 在台账里固件版本仍是旧值, 下次选中它打开这一页就判成"低于当前版本 / 推荐升级"。
        let targets = app.devices.filter { queueSel.contains($0.mac) }.sorted { $0.mac < $1.mac }
        guard !targets.isEmpty else { queueNote = "队列里选的那些锁已经不在了"; return }
        // onStep 只给序号与显示名、不给 mac; runUpgradeQueue 串行且每把恰好 append 一条 outcome,
        // 所以 outcomes[i] 与 targets[i] 同下标 (下面用 zip 走, 不靠下标硬取)。起点按下标记,
        // 用来算每一把自己那一刻的 at 与 ms —— 串行意味着"下一把的起点"就是"这一把的终点"。
        var startAt: [Int: Double] = [:]
        let outcomes = await DFURunner.runUpgradeQueue(
            lock: app.lock, macs: targets.map { $0.mac }, firmware: fw,
            onStep: { i, n, name in
                startAt[i - 1] = Date().timeIntervalSince1970
                queueNote = "第 \(i)/\(n) 把: \(name)"
            },
            onProgress: { p in
                switch p {
                case .switchingDfu, .connecting: stage = 0
                case .starting: stage = 1
                case .uploading(let v):
                    stage = 1
                    updateRate(Double(v))
                case .validating: stage = 2
                case .completed: stage = 2; pct = 100
                default: break
                }
            })
        queueOutcomes = outcomes
        let endAt = Date().timeIntervalSince1970
        var ok = 0
        for (i, pair) in zip(outcomes, targets).enumerated() {
            let (o, kc) = pair
            let t0 = startAt[i] ?? endAt
            let t1 = i + 1 < outcomes.count ? (startAt[i + 1] ?? endAt) : endAt
            if o.ok { ok += 1 }
            // name 取固件包名、at 取毫秒、ok=false 也照样记一笔 —— 三条都与单锁那段同口径,
            // 两处各写一套迟早对不上 (本仓 §10 反复实撞过这一族)。
            BatteryCare.addDFURecord(DFURecord(mac: o.mac, name: fw.sourceName,
                                               from: kc.fw, to: fw.version ?? "",
                                               at: t0 * 1000, ok: o.ok,
                                               ms: max(0, t1 - t0) * 1000))
        }
        queueNote = "队列结束: 成功 \(ok) / 共 \(outcomes.count) 把"
        if ok == outcomes.count { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        // 148: 逐把复核, 沿用单锁那段的同一判据 —— 只有真读回版本且与包版本一致才回写台账。
        // verifyText 是单锁的显示位, 跑完这里留的是最后一把的复核结论; 上面那行队列汇总不受它影响。
        for pair in zip(outcomes, targets) where pair.0.ok {
            await verifyAfterUpgrade(pair.1, fw)
        }
    }

    private func upgrade() async {
        guard let fw, let kc = app.current, !running else { return }
        running = true
        failed = false
        failReason = ""
        verified = false
        verifyText = ""
        stage = 0
        pct = 0
        remainText = ""
        rate = 0
        lastProg = nil
        defer { running = false }
        let startedAt = Date().timeIntervalSince1970   // 147 计时起点: 连接 + 升级 + 校验全算进去
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await DFURunner.runUpgrade(lock: app.lock, mac: kc.mac, pid: kc.pid, firmware: fw) { p in
                // 138 三段进度: DFUKit 进度枚举 → 准备/传输/校验 (视图层映射, 不改 DFUKit)
                switch p {
                case .switchingDfu, .connecting: stage = 0
                case .starting: stage = 1
                case .uploading(let v):
                    stage = 1
                    updateRate(Double(v))
                case .validating: stage = 2
                case .completed: stage = 2; pct = 100
                default: break
                }
            }
            BatteryCare.addDFURecord(DFURecord(mac: kc.mac, name: fw.sourceName,
                                               from: curFw, to: fw.version ?? "",
                                               at: Date().timeIntervalSince1970 * 1000, ok: true,
                                               ms: (Date().timeIntervalSince1970 - startedAt) * 1000))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await verifyAfterUpgrade(kc, fw)   // 148
        } catch {
            failed = true
            failReason = error.localizedDescription
            BatteryCare.addDFURecord(DFURecord(mac: kc.mac, name: fw.sourceName,
                                               from: curFw, to: fw.version ?? "",
                                               at: Date().timeIntervalSince1970 * 1000, ok: false,
                                               ms: (Date().timeIntervalSince1970 - startedAt) * 1000))
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// 139 剩余时间: 传输速率 EMA (只估传输段 — 校验段通常 <10 秒, 不值得估)
    private func updateRate(_ v: Double) {
        pct = v
        let now = Date().timeIntervalSince1970
        defer { lastProg = (v, now) }
        guard let last = lastProg, v > last.pct else { return }
        // 单位口径：秒 —— `lastProg` 的第二个元素就是上面那行 `Date().timeIntervalSince1970`，同一把尺。
        let dt = now - last.at
        guard dt > 0.2 else { return }
        let inst = (v - last.pct) / dt
        rate = rate == 0 ? inst : rate * 0.7 + inst * 0.3
        guard v > 3, rate > 0.01 else { remainText = ""; return }
        let sec = Int((100 - v) / rate)
        remainText = sec >= 90 ? "约剩 \(Int(ceil(Double(sec) / 60))) 分钟" : "约剩 \(max(sec, 1)) 秒"
    }

    /// 148 完成自动校验: 等门锁重启后重连读版本, 与包版本比对; 通过则回写钥匙串固件字段
    private func verifyAfterUpgrade(_ kc: Keychain, _ fw: FirmwarePackage) async {
        verifyText = "升级已提交 — 门锁重启中, 自动校验版本…"
        try? await Task.sleep(for: .seconds(9))
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let st = try await app.lock.getStatus(mac: kc.mac)
            if let v = fw.version, !st.firmware.isEmpty {
                if FirmwareKit.versionLt(st.firmware, v) || FirmwareKit.versionLt(v, st.firmware) {
                    verifyText = "锁内版本 v\(st.firmware) 与包版本 v\(v) 不一致, 请到锁信息名片复核"
                } else {
                    verified = true
                    verifyText = "校验通过 · 锁内已是 v\(st.firmware)"
                    var kc2 = kc
                    kc2.fw = st.firmware
                    DB.saveKeychain(kc2)
                    app.loadDevices()
                }
            } else {
                verifyText = "已读到状态但版本为空, 请到锁信息名片复核"
            }
        } catch {
            verifyText = "门锁还在重启, 暂未读回版本 — 升级已提交, 稍后到锁信息名片复核即可"
        }
    }

    private func dateShort(_ tsMs: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: tsMs / 1000))
    }
}

// ================= 蓝牙钥匙串硬件 (addkeychain) =================
struct KeychainHWView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var dongles: [Dongle] = []
    @State private var busy = false

    var body: some View { vkBody.destined(.keychainHW) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section("蓝牙钥匙串") {
                    Text("钥匙串是一个随身蓝牙硬件，可写入多把门锁的数字钥匙。持有人靠近门锁时即可开门，无需手机。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await scan() }
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            // 常驻菊花 + 透明度过渡, 避免文字被推着走
                            ProgressView().controlSize(.small).opacity(busy ? 1 : 0)
                            Text(busy ? "搜索中…" : "搜索钥匙串")
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(busy)
                }
                Section("我的钥匙串") {
                    if dongles.isEmpty {
                        EmptyState(systemImage: "key.slash",
                                   title: "还没有钥匙串",
                                   message: "上电后点上方「搜索钥匙串」即可添加。",
                                   actionTitle: "搜索钥匙串") {
                            Task { await scan() }
                        }
                    }
                    ForEach(dongles) { d in dongleRow(d) }
                        .disabled(busy)
                }
                if app.current == nil {
                    Section {
                        Label {
                            Text("尚未配对门锁 — 写入钥匙前需先配对门锁。")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    }
                }
            }
            .navigationTitle("蓝牙钥匙串")
            .variantList()
            .dsScreenBackground()
            .task { reload() }
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(busy ? "写入中…" : "关闭") { dismiss() }.disabled(busy) } } .interactiveDismissDisabled(busy)   // 2026-10-15 走查: 写锁在飞时不给退出入口
        }
    }

    private func dongleRow(_ d: Dongle) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(d.name.isEmpty ? "钥匙串" : d.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                if !d.lastKeyLock.isEmpty {
                    StatusPill(text: "已配钥匙", systemImage: "checkmark.circle.fill", tone: .ok)
                }
                Spacer(minLength: 0)
            }
            Text(dongleDisplay(d.mac))
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            if let st = d.stat {
                // 电量/钥匙存量/固件是三条独立读数, 用 MetricTile 横排比挤在 caption 里层级更清楚
                HStack(spacing: DS.Space.s) {
                    MetricTile(systemImage: "battery.100",
                               label: "电量",
                               value: st.power < 0 ? "—" : "\(st.power)%",
                               tone: st.power < 0 ? .neutral : (st.power <= 20 ? .warn : .ok))
                    MetricTile(systemImage: "key",
                               label: "钥匙",
                               // -1 = 该字段没读到。两侧是**各自独立**解析的 (KLV#24 与 #25 各默认 -1,
                               // HardwareService.parseKCStatus), 所以"读到了存量、没读到上限"是正常回字 ——
                               // 原先只挡 count 那侧, 屏上就印出 "3 / -1" 这种把缺失当读数的数。
                               value: st.ekeyCount < 0 ? "—"
                                    : (st.ekeyAmount < 0 ? "\(st.ekeyCount) / —" : "\(st.ekeyCount) / \(st.ekeyAmount)"),
                               emphasized: false)
                    MetricTile(systemImage: "cpu",
                               label: "固件",
                               value: st.firmware.isEmpty ? "—" : st.firmware)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { removeRecord(d) } label: { Label("删除记录", systemImage: "trash") }
        }
        .contextMenu {
            Button("读取状态") { Task { await readStatus(d) } }
            Menu("给当前门锁写入钥匙") {
                // 内层菜单项不重复外层标题, 加省略号表示会再弹确认框
                Button("写入…") { confirmWriteKey(d) }
            }
            Button("查询全部钥匙") { Task { await listKeys(d) } }
            Button("删除本锁钥匙") { confirmDeleteKey(d) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    private func dongleDisplay(_ hex: String) -> String {
        let b = HexKit.bytes(hex).reversed()
        return b.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func reload() { dongles = DB.dongles() }

    // ---- 写硬件类动作一律先确认: 钥匙串上的钥匙不可撤销 ----
    private func confirmWriteKey(_ d: Dongle) {
        guard !busy else { return }
        let lockName = app.displayName
        confirmDestructive("写入钥匙",
                          "将把「\(lockName)」的门锁密钥写入钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」。写入后该钥匙串无需手机即可开这道门，且无法在 App 内撤销。确定写入吗？",
                          confirmTitle: "确认写入") {
            Task { await self.writeKey(d) }
        }
    }

    private func confirmDeleteKey(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除本锁钥匙",
                          "将清除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」中「\(app.displayName)」的钥匙。删除后该钥匙串将无法再开这道门。确定删除吗？",
                          confirmTitle: "删除") {
            Task { await self.deleteKey(d) }
        }
    }

    private func removeRecord(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除记录",
                          "将从本机删除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」(\(dongleDisplay(d.mac))) 的记录，硬件本身不受影响。确定删除吗？",
                          confirmTitle: "删除") {
            DB.removeDongle(d.mac)
            reload()
        }
    }

    private func scan() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.scanForDongle() }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func readStatus(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.readDongleState(mac: d.mac) }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func writeKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 下面那句"请先配对门锁"会说, 上面这句却静默 = 同一条链两种收法
        guard !busy else { return }
        guard !kc.skey.isEmpty, kc.pid != 0 else { app.showToast("请先配对门锁"); return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc, trackId: KeyGen.genTrackId())
            app.showToast("设置成功: 该钥匙串现已开启「\(app.displayName)」")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }

    private func deleteKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 与 writeKey 同一条口径
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
            app.showToast("已删除该门锁的钥匙")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }

    private func listKeys(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let macs = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            app.showToast(macs.isEmpty ? "没有查询到钥匙" : "共 \(macs.count) 把钥匙")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }
}

// ================= 网关 (addgw + gwstate 合流) =================
struct GatewayView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var ssid = ""
    @State private var pwd = ""
    @State private var running = false
    @State private var steps: [String] = []
    @State private var error = ""
    @State private var gateways: [Gateway] = []

    var body: some View { vkBody.destined(.gateway) }
    var vkBody: some View {
        NavigationStack {
            List {
                if !confirmed {
                    Section("准备网关") {
                        Text("接通电源，重置网关，待网关指示灯闪烁橙色后点击下一步。").vkFont(.footnote)
                        VariantToggle("橙色灯闪烁中", isOn: $confirmed)
                        Text("长捅网关的重置孔，保持5s左右，至指示灯变为橙色，即重置成功。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } else {
                    Section("配置 WiFi") {
                        TextField("WiFi 名称 (2.4GHz)", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                        SecureField("WiFi 密码", text: $pwd)
                            .submitLabel(.done)
                    }
                    Section {
                        BusyButton(title: "开始配网", systemImage: "wifi", isBusy: running, disabled: ssid.isEmpty || pwd.isEmpty) {
                            confirmProvision()
                        }
                    }
                    if !steps.isEmpty {
                        Section("配网进度") {
                            ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                                Label {
                                    Text(s).fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.ok)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            if !error.isEmpty {
                                Text(error)
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .animation(DS.Motion.standard, value: steps)
                    }
                }
                gatewayList
            }
            .navigationTitle("智能网关")
            .variantList()
            .dsScreenBackground()
            // sheet 呈现时必须自带退出入口, 否则用户出不去
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(running ? "写入中…" : "关闭") { dismiss() }.disabled(running) } } .interactiveDismissDisabled(running)   // 2026-10-15 走查: 写锁在飞时不给退出入口
            .task { reload() }
        }
    }

    private var gatewayList: some View {
        Section("我的网关") {
            if gateways.isEmpty {
                EmptyState(systemImage: "antenna.radiowaves.left.and.right.slash",
                           title: "还没有添加网关",
                           message: "先在上方重置网关并勾选指示灯状态，再回来配网。")
            }
            ForEach(gateways) { g in gatewayRow(g) }
                .disabled(running)
        }
    }

    private func gatewayRow(_ g: Gateway) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(g.name.isEmpty ? "智能网关" : g.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                StatusPill(text: g.netState == 1 ? "已联网" : "未联网",
                           systemImage: g.netState == 1 ? "wifi" : "wifi.slash",
                           tone: g.netState == 1 ? .ok : .neutral)
                Spacer(minLength: 0)
            }
            // 版本/网络两条独立读数, 用 MetricTile 横排比挤在一行 caption 里层级更清楚
            HStack(spacing: DS.Space.s) {
                MetricTile(systemImage: "cpu",
                           label: "ROM",
                           value: g.romVer.isEmpty ? "—" : g.romVer)
                MetricTile(systemImage: "wifi",
                           label: "WiFi",
                           value: g.ssid.isEmpty ? "—" : g.ssid,
                           tone: g.netState == 1 ? .ok : .neutral)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { removeGateway(g) } label: { Label("删除", systemImage: "trash") }
            Button { confirmReboot(g) } label: { Label("重启", systemImage: "arrow.clockwise") }.tint(DS.Palette.accent)
        }
        .contextMenu {
            Button("刷新状态") { Task { await refresh(g) } }
            Button("重启网关") { confirmReboot(g) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    private func removeGateway(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("删除网关",
                          "将从本机删除网关「\(g.name.isEmpty ? "智能网关" : g.name)」的记录。删除后若不再配网将无法找回。确定删除吗？",
                          confirmTitle: "删除") {
            DB.removeGateway(g.mac)
            reload()
        }
    }

    private func reload() { gateways = DB.gateways() }

    // 配网会向网关硬件写入 WiFi 凭据, 配错需重新重置网关才能再配
    private func confirmProvision() {
        guard !running, !ssid.isEmpty, !pwd.isEmpty else { return }
        confirmDestructive("写入网关",
                          "将把 WiFi「\(ssid)」写入网关硬件。写入过程网关会重启并清空原有网络配置，若网络不通需要重新重置网关才能再次配网。确定开始配网吗？",
                          confirmTitle: "开始配网") {
            Task { await self.provision() }
        }
    }

    // 重启会让网关短暂离线, 断电/断网期间无法远程唤醒
    private func confirmReboot(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("重启网关",
                          "将重启「\(g.name.isEmpty ? "智能网关" : g.name)」。网关会短暂离线，此期间无法远程开锁。确定重启吗？",
                          confirmTitle: "重启") {
            Task { await self.reboot(g) }
        }
    }

    private func provision() async {
        guard !running else { return }
        running = true
        steps.removeAll()
        error = ""
        defer { running = false }
        do {
            let sentWifi = ssid
            _ = try await HardwareService.shared.provisionGateway(ssid: ssid, password: pwd) { s in steps.append(s) }
            ssid = ""; pwd = ""
            confirmed = false
            // 2026-10-15 走查: 成功这一支原先只清空表单 + 退回第一步, 而"配网进度"那段只在
            // confirmed == true 的那一支里渲染 —— 于是连服务回调最后那句"添加成功!"也一起没了,
            // 成功与"点了没反应"完全同形 (失败反倒看得见, error 走的是另一支)。补一句结论,
            // 并把话说准: 到这里为止被网关 errCode 0 认下的是"WiFi 写入", 联网状态得等它自己上报。
            app.showToast("配网指令已被网关接受 · 正在用「\(sentWifi)」重连, 联网状态稍后在下方列表复核")
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    // refresh / reboot 与 provision 互斥: 同一时间只允许一条网关指令在飞
    private func refresh(_ g: Gateway) async {
        guard !running else { return }
        running = true
        defer { running = false }
        do { _ = try await HardwareService.shared.readGatewayState(mac: g.mac) }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func reboot(_ g: Gateway) async {
        guard !running else { return }
        running = true
        defer { running = false }
        do {
            try await HardwareService.shared.rebootGateway(mac: g.mac)
            app.showToast("重启成功")
        } catch { app.showToast("重启失败: \(error.localizedDescription)") }
        reload()
    }
}


