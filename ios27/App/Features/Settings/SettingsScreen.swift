// SettingsScreen.swift —— 设置（Tab 5 根）。分节 + 每节一行读数。
//
// 这屏干什么：把「这台锁 / 安全 / 外观与时间 / 数据与硬件」四节摊开，每节只用一行读数回答
// 「现在是什么状态」，点那一行才进子页。设置页不用系统 Form（它的灰底与分组会跟玻璃撞）。
// 数据从哪来：AppModel.lock（锁实况）+ SettingsStore.shared（本机偏好）+ TimeFormat（时间口径）。
// 主动作：本屏刻意不设主动作按钮 —— 设置页是读数页，每个真动作都在它自己的子页里
// （备份页的「生成备份」、安全页的「设置本机密码」、硬件页的「扫描钥匙串」）。
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) internal var app
    @Environment(Router.self) private var router
    internal var store: SettingsStore { SettingsStore.shared }

    @State private var deleteRequested = false

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if app.lock != nil {
                    protectionPanel
                    lockSection
                    securitySection
                    lookSection
                    dataSection
                    deleteSection
                } else {
                    noLockPanel
                    securitySection
                    lookSection
                    dataSection
                }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("设置")
        .task { await app.reload(refreshStatus: true) }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $deleteRequested) {
            DeleteDeviceSheet()
        }
    }

    // MARK: 页头
    private var header: some View {
        SettingsHeader(
            title: "设置",
            tone: app.lock == nil ? .attention : (app.lock?.isConnected == true ? .ok : .neutral),
            status: headerStatus
        )
    }

    private var headerStatus: String {
        guard let lock = app.lock else { return "还没有门锁 · 所有偏好都存在这台手机上" }
        let link = lock.isConnected ? "已连接" : "未连接"
        return "\(lock.name) · \(link) · 偏好全部存本机，不上传"
    }

    // MARK: 主角：本机保护读数（三枚读数在一只面板里，不是三张卡）
    private var protectionPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                HStack(alignment: .firstTextBaseline, spacing: T.S.s) {
                    Text("本机状态")
                        .font(T.F.section)
                        .foregroundStyle(Ink.inkSub)
                    Spacer(minLength: T.S.s)
                    Text("不上传")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                        .tracking(0.6)
                }
                ReadingGrid(items: [
                    .init(label: "本机密码",
                          value: store.hasPasscode ? "已设" : "未设",
                          tint: store.hasPasscode ? Ink.ink : State.attention),
                    .init(label: "上次备份",
                          value: store.lastBackupAt.map { TimeFormat.dayShort($0) } ?? "从未",
                          tint: store.lastBackupAt == nil ? State.attention : Ink.ink),
                    .init(label: "自动开锁",
                          value: store.autoOpenEnabled ? "开" : "关",
                          tint: store.autoOpenEnabled ? Ink.ink : Ink.inkSub),
                ], columns: 3)
                .padding(.top, T.S.xs)
                SettingRule()
                StatusLine(
                    tone: app.trialGuard ? .critical : .neutral,
                    text: app.trialGuard ? "只读试验模式 开 · 写入类操作已停用" : "只读试验模式 关"
                )
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 门锁节
    private var lockSection: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "门锁", trailing: app.lock?.model)
            Panel {
                VStack(spacing: 0) {
                    SettingRow(
                        label: "锁实况",
                        value: "\(app.lock?.battery ?? 0)",
                        unit: "%",
                        tint: (app.lock?.battery ?? 0) < 20 ? State.attention : Ink.ink,
                        mono: true,
                        symbol: "gauge.with.dots.needle.50percent",
                    ) { router.request(.dest(.lockStatus)) }
                    SettingRule()
                    SettingRow(label: "校准门锁时间",
                               value: store.lockClockSyncedAt.map { TimeFormat.ago($0) } ?? "从未校准",
                               tint: store.lockClockSyncedAt == nil ? State.attention : Ink.ink,
                               mono: false,
                               symbol: "clock.arrow.circlepath",) {
                        router.request(.dest(.syncTime))
                    }
                    SettingRule()
                    // TODO(engine) 「未绑定」应读 kf_gateways 台账（op=getDeviceStatus 刷新），本版无数据源。
                    SettingRow(label: "智能网关", value: "未绑定", unit: nil,
                               tint: Ink.inkSub, mono: false,
                               symbol: "antenna.radiowaves.left.and.right",) {
                        router.request(.dest(.gateway))
                    }
                    SettingRule()
                    // TODO(engine) 布防状态应读 op=getDeviceSetting（defenceControl / StartTime / EndTime）。
                    SettingRow(label: "布防", value: "未布防", unit: nil,
                               tint: Ink.inkSub, mono: false,
                               symbol: "shield.lefthalf.filled",) {
                        router.request(.dest(.defend))
                    }
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 安全节
    private var securitySection: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "安全")
            Panel {
                VStack(spacing: 0) {
                    SettingRow(
                        label: "本机数据保护",
                        value: store.hasPasscode ? "密码 已设" : "密码 未设",
                        tint: store.hasPasscode ? Ink.ink : State.attention,
                        mono: false,
                        symbol: "lock.shield",
                    ) { router.request(.dest(.security)) }
                    SettingRule()
                    SettingRow(
                        label: "靠近自动开锁",
                        value: store.autoOpenEnabled ? "开" : "关",
                        tint: store.autoOpenEnabled ? Ink.ink : Ink.inkSub,
                        mono: false,
                        symbol: "figure.walk",
                    ) { router.request(.dest(.autoOpen)) }
                    SettingRule()
                    SettingToggle(
                        label: "只读试验模式",
                        note: "真机排障用：所有写入类命令停用，只看不改。关掉 App 也不会自动恢复 —— 记得回来关。",
                        isOn: trialGuardBinding(app)
                    )
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 外观与时间节
    private var lookSection: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "外观与时间")
            Panel {
                VStack(spacing: 0) {
                    SettingRow(
                        label: "外观",
                        value: store.theme.title,
                        mono: false,
                        symbol: "paintbrush",
                    ) { router.request(.dest(.appearance)) }
                    SettingRule()
                    SettingRow(
                        label: "时间显示",
                        value: store.timeStyle.title,
                        mono: false,
                        symbol: "clock",
                    ) { router.request(.dest(.appearance)) }
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 数据与硬件节
    private var dataSection: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "数据与硬件")
            Panel {
                VStack(spacing: 0) {
                    SettingRow(
                        label: "备份与恢复",
                        value: store.lastBackupAt.map { TimeFormat.ago($0) } ?? "从未备份",
                        tint: store.lastBackupAt == nil ? State.attention : Ink.ink,
                        mono: false,
                        symbol: "externaldrive",
                    ) { router.request(.dest(.backup)) }
                    SettingRule()
                    SettingRow(
                        label: "钥匙串 / 硬件",
                        value: "\(store.dongles.count)",
                        unit: "台",
                        mono: true,
                        symbol: "key.horizontal",
                    ) { router.request(.dest(.hardware)) }
                    SettingRule()
                    SettingRow(
                        label: "关于",
                        value: SettingsFacts.version,
                        symbol: "info.circle",
                    ) { router.request(.dest(.about)) }
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 删除设备（这一节只为它存在，一加一删成对）
    private var deleteSection: some View {
        VStack(spacing: T.S.s) {
            SectionLabel(text: "这台锁的本地数据")
            Panel {
                VStack(alignment: .leading, spacing: T.S.s) {
                    SettingDangerRow(title: "删除这台锁的本机数据") { deleteRequested = true }
                    SettingsNote(text: "只删本机：锁端密钥与锁内日志不变，重配即可再添加。未做备份则无法找回本机的密码台账。")
                }
            }
            .padding(.horizontal, T.S.gutter)
        }
    }

    // MARK: 空态（给出路：去添加）
    private var noLockPanel: some View {
        Panel {
            EmptyPanel(
                title: "还没有添加门锁",
                message: "打开后面板，长按 RESET 直到三声嘀，然后在这里添加。添加后这一屏才会出现锁实况、校时与删除。",
                actionTitle: "添加门锁",
                systemImage: "door.left.hand.closed"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, T.S.xl)
        }
        .padding(.horizontal, T.S.gutter)
    }
}

// MARK: - 删除设备：键入锁名才放行

/// 删除本机这把锁的数据。两道闸：先列出会连带删掉什么，再要求键入锁名原文。
struct DeleteDeviceSheet: View {
    @Environment(AppModel.self) internal var app
    @Environment(\.dismiss) internal var dismiss
    @State private var typed = ""

    private var lockName: String { app.lock?.name ?? "" }
    private var canDelete: Bool { !lockName.isEmpty && typed == lockName }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: T.S.l) {
                    SettingsHeader(
                        title: "删除「\(lockName)」",
                        tone: .critical,
                        status: "只删本机数据 · 锁端密钥与锁内日志不变"
                    )

                    Panel {
                        VStack(alignment: .leading, spacing: T.S.m) {
                            SectionLabel(text: "会被删除", trailing: nil)
                            ReadingGrid(items: [
                                .init(label: "凭证", value: "\(app.keys.count)", unit: "枚"),
                                .init(label: "记录缓存", value: "\(app.entries.count)", unit: "条"),
                                .init(label: "本机密码", value: store.hasPasscode ? "已设" : "未设"),
                            ], columns: 3)
                            SettingRule()
                            SettingsNote(text: "删除后若没做过备份，本机的密码台账与缓存记录无法找回。锁本身不需要重置，可以再次添加。")
                        }
                    }
                    .padding(.horizontal, T.S.gutter)

                    Panel {
                        VStack(alignment: .leading, spacing: T.S.m) {
                            SectionLabel(text: "键入锁名确认")
                            Inset {
                                TextField(lockName, text: $typed)
                                    .font(T.F.body)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .accessibilityLabel("键入锁名")
                            }
                            DangerAction(title: "删除本机数据") {
                                // 真交互：清掉本机这把锁的引用，页面随即落到空态（下一步是重新添加）。
                                app.lock = nil
                                dismiss()
                            }
                            .disabled(!canDelete)
                            .opacity(canDelete ? 1 : 0.4)
                            SecondaryAction(title: "取消") { dismiss() }
                        }
                    }
                    .padding(.horizontal, T.S.gutter)
                }
                .padding(.vertical, T.S.l)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("删除设备")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    internal var store: SettingsStore { SettingsStore.shared }
}
