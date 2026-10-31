// SecurityScreen.swift —— 安全：本机数据保护 + 锁端安全入口。
//
// 这屏干什么：设 / 改 / 关本机密码（4 位以上纯数字），它是冷启动、看密码明文、导出备份的前置屏障；
// 再给两条锁端安全入口（安全模式在「锁实况」、布防在「布防」页）与只读试验模式。
// 数据从哪来：SettingsStore.shared（本机密码位）+ AppModel.trialGuard + Router（跳锁端页面）。
// 主动作：唯一 signal 填充是「设置本机密码」/「更改本机密码」—— 同一位置、同一个动作，换词不换位。
import SwiftUI
import LocalAuthentication

struct SecurityScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    private var store: SettingsStore { SettingsStore.shared }

    @State private var showPasscode = false
    @State private var showDuress = false
    @State private var showDisableConfirm = false
    @State private var showDisableDuressConfirm = false
    @State private var showVerifyPass = false
    @State private var showVerifyDuress = false

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                SettingsHeader(title: "安全", tone: tone, status: status)
                passcodePanel
                biometricPanel
                if store.hasPasscode {
                    duressPanel
                } else {
                    unsetPanel
                }
                lockSidePanel
                unlockConfirmPanel
                trialPanel
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("安全")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPasscode) { PasscodeSheet(kind: .passcode) }
        .sheet(isPresented: $showDuress) { PasscodeSheet(kind: .duress) }
        .sheet(isPresented: $showVerifyPass) {
            VerifyPasscodeSheet(
                title: "关闭本机密码",
                note: "关闭前先验证当前本机密码。"
            ) { DB.setPasscode(nil) }
        }
        .sheet(isPresented: $showVerifyDuress) {
            VerifyPasscodeSheet(
                title: "关闭胁迫码",
                note: "关闭前先验证当前本机密码。"
            ) { _ = DB.setDuressCode(nil) }
        }
        .confirmationDialog("关闭胁迫码？", isPresented: $showDisableDuressConfirm, titleVisibility: .visible) {
            Button("继续验证", role: .destructive) { showVerifyDuress = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("关闭后，被胁迫时输错密码不会进入空壳模式 —— 门会打不开，数据照常显示。")
        }
        .confirmationDialog("关闭本机密码？", isPresented: $showDisableConfirm, titleVisibility: .visible) {
            Button("继续验证", role: .destructive) { showVerifyPass = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("关闭后冷启动不再需要密码。锁内凭证与门锁数据不受影响，但任何拿到这台手机的人都能直接打开 App。")
        }
    }

    // MARK: 页头
    private var tone: Tone {
        if app.trialGuard { return .critical }
        return store.hasPasscode ? .ok : .attention
    }

    private var status: String {
        var parts: [String] = [store.hasPasscode ? "本机密码 已设" : "本机密码 未设 · 冷启动无屏障"]
        if store.hasDuressCode { parts.append("胁迫码 已设") }
        if app.trialGuard { parts.append("只读试验模式 开") }
        return parts.joined(separator: " · ")
    }

    // MARK: 主角：本机数据保护
    private var passcodePanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "本机数据保护")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    VReadingGrid(items: [
                        .init(label: "本机密码", value: store.hasPasscode ? "已设" : "未设",
                              tint: store.hasPasscode ? V.C.text1 : V.C.warning),
                        .init(label: "胁迫码", value: store.hasDuressCode ? "已设" : "未设",
                              tint: V.C.text1),
                        .init(label: "冷启动", value: store.hasPasscode ? "要求" : "免输",
                              tint: V.C.text1),
                    ], columns: 3)
                    .padding(.top, V.S.gapXS)
                    SettingRule()
                    SettingsNote(text: "4 位以上纯数字。密码只存这台手机（摘要落本机安全存储），不上传、不写进锁。它同时是查看密码明文与导出备份的前置屏障。")
                    if store.hasPasscode {
                        VActionButton(title: "更改本机密码", systemImage: "lock.rotation") {
                            showPasscode = true
                        }
                        SettingDangerRow(title: "关闭本机密码") { showDisableConfirm = true }
                    } else {
                        VActionButton(title: "设置本机密码", systemImage: "lock.fill") {
                            showPasscode = true
                        }
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 生物识别（Face ID / Touch ID）
    private var biometricPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "生物识别")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    VFieldRow(label: "硬件", value: biometricName, mono: false)
                    SettingRule()
                    SettingToggle(
                        label: "允许面容 / 指纹解锁",
                        note: store.hasDuressCode
                            ? "已设胁迫码时本开关自动停用 —— 刷脸会暴露「这不是伪装模式」。"
                            : "冷启动时可用 Face ID / Touch ID 解锁；失败仍可输本机密码。",
                        isOn: settingsBinding(\.bioUnlock)
                    )
                    .disabled(store.hasDuressCode)
                    .opacity(store.hasDuressCode ? 0.45 : 1)
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    private var biometricName: String {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch ctx.biometryType {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            default: return "生物识别"
            }
        }
        return "不可用（未录入或设备不支持）"
    }

    // MARK: 胁迫码（只在已设本机密码时可设 —— 它替代的是同一个输入框）
    private var duressPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "胁迫码")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    VFieldRow(label: "当前状态", value: store.hasDuressCode ? "已设" : "未设",
                             tint: store.hasDuressCode ? V.C.text1 : V.C.text2, mono: false)
                    SettingRule()
                    SettingsNote(text: store.hasDuressCode
                                 ? "被胁迫时输入胁迫码：门照样能开，但凭证与记录显示为空 —— 不报警、不暴露。"
                                 : "另设一个与真密码不同的数字。输入它时 App 进入空壳模式：门能开，数据看不见。")
                    if store.hasDuressCode {
                        VOutlineButton(title: "更改胁迫码", systemImage: "exclamationmark.shield") {
                            showDuress = true
                        }
                        SettingDangerRow(title: "关闭胁迫码") { showDisableDuressConfirm = true }
                    } else {
                        VOutlineButton(title: "设置胁迫码", systemImage: "exclamationmark.shield") {
                            showDuress = true
                        }
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 未设密码时的出路（空态必须写下一步，不是「暂无」）
    private var unsetPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                Text("这台手机现在没有任何屏障")
                    .font(V.F.bodyStrong)
                    .foregroundStyle(V.C.text1)
                SettingsNote(text: "下一步：设一个 4 位以上纯数字密码。之后冷启动要先输它，看密码明文与导出备份也要先输它 —— 手机丢了，锁内凭证也不会被人直接读走。")
                VOutlineButton(title: "先看看锁端安全设置", systemImage: "shield.lefthalf.filled") {
                    router.request(.dest(.lockStatus))
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 锁端安全（这两项不在本页改，只给入口 —— 改锁端策略必须到场连接）
    private var lockSidePanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "锁端安全", trailing: app.lock?.model)
            VCard {
                VStack(spacing: 0) {
                    SettingRow(
                        label: "安全模式",
                        value: "在锁实况改",
                        tint: V.C.text2,
                        mono: false,
                        symbol: "lock.rectangle.on.rectangle",
                        note: "A 模式单验、B 模式双验。这是锁端策略：切换要连上锁，且切完要回读确认真的生效。"
                    ) { router.request(.dest(.lockStatus)) }
                    SettingRule()
                    // TODO(engine) 布防状态应读 op=getDeviceSetting（defenceControl / StartTime / EndTime）。
                    SettingRow(
                        label: "布防",
                        value: "未布防",
                        tint: V.C.text2,
                        mono: false,
                        symbol: "shield.lefthalf.filled",
                        note: "布防时段内，靠近自动开锁会被自动否决；防拆事件也会关掉自动开锁。"
                    ) { router.request(.dest(.defend)) }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 开锁确认（防误触。这是"怎么算一次确认"的偏好，不是装饰开关）
    private var unlockConfirmPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "开锁确认")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingToggle(
                        label: "按住确认开锁",
                        note: "按住刻度盘才算确认。关掉后退回轻点直开 —— 单手时更省力，但误触也会开门。",
                        isOn: settingsBinding(\.holdConfirm)
                    )
                    SettingRule()
                    SettingToggle(
                        label: "失败自动重试",
                        note: "一次没开成时自动重试两次（2 秒 / 5 秒退避）。超时不重试 —— 免得在门口反复广播。",
                        isOn: settingsBinding(\.autoRetry)
                    )
                    SettingRule()
                    SettingToggle(
                        label: "误触围栏",
                        note: "开启后要先把手指从圆盘边缘拖到中心解锁围栏，开锁手势才响应 —— 防口袋里误触。",
                        isOn: settingsBinding(\.fence)
                    )
                    SettingRule()
                    SettingToggle(
                        label: "双击直开",
                        note: "按住档下，双击圆盘绕过按住确认直接开。方便，但误触风险也更高；默认关。",
                        isOn: settingsBinding(\.tapDirect)
                    )
                    SettingRule()
                    SettingsNote(text: "这几项只管「怎么算确认」，不改锁端策略。安全模式（A / B）是锁端的事，改它要连上锁并回读确认。")
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    // MARK: 只读试验模式（真交互：改 AppModel 状态，门页与设置页同步可见）
    private var trialPanel: some View {
        VStack(spacing: V.S.gapS) {
            VSectionLabel(text: "排障")
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapMS) {
                    SettingToggle(
                        label: "只读试验模式",
                        note: "开启后所有写入类命令停用：只能读状态，不能改锁、不能下发凭证。用来在真机上排障而不会把锁改坏。",
                        isOn: trialGuardBinding(app)
                    )
                    SettingRule()
                    VStatusLine(
                        tone: app.trialGuard ? .critical : .neutral,
                        text: app.trialGuard ? "已开启 · 写入类操作全部停用" : "关闭 · 写入类操作可用"
                    )
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }
}