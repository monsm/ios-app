// SecurityHomeScreen.swift —— 安全（V8 设计语言）
//
// 与 SecurityScreen 的能力对齐：本机密码（设 / 改 / 关，4 位以上纯数字）、胁迫码（设 / 改 / 关）、
// 生物识别、锁端安全入口（安全模式 / 布防）、失败自动重试、只读试验模式。
// 只改渲染层：密码仍走 DB.setPasscode / DB.setDuressCode / DB.verifyPasscode，
// 表单仍是 SettingsParts 的 PasscodeSheet / VerifyPasscodeSheet（全仓唯一校验链，复制一份就会漂）。
//
// 两处刻意差异：
//   ① 旧页四个 sheet 是四条独立的 sheet(isPresented:)，两个布尔同时为真时 SwiftUI 会静默丢弃一个。
//      这里收成一个 SecuritySheet? 单一入口（sheet(item:)），同一时刻只能有一个模态；
//      「确认对话框 → 验证框」仍按旧页的排队法：先记 pendingVerify，等对话框真的落回 false 再呈现。
//   ② 空壳模式下整页只读：改密码 / 关密码 / 关胁迫码都会改写真实的 kf_passcode / kf_duress，
//      而空壳的纪律是只隐藏、不破坏；旧页在空壳里照样能一键关掉真实本机密码。
import SwiftUI
import LocalAuthentication

struct SecurityHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var store: SettingsStore { SettingsStore.shared }

    /// 同一时刻只允许一个模态：四个入口合并成一个枚举。
    private enum SecuritySheet: String, Identifiable {
        case passcode
        case duress
        case verifyPass
        case verifyDuress

        var id: String { rawValue }
    }

    @State private var sheet: SecuritySheet?
    @State private var confirmDisablePass = false
    @State private var confirmDisableDuress = false
    /// 待呈现的验证框。对话框关闭后才消费 —— 避免「对话框还没退场就弹 sheet」被 SwiftUI 丢弃。
    @State private var pendingVerify: SecuritySheet?

    private var decoyed: Bool { DB.isDecoy }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下安全设置只读" }
        if app.trialGuard { return "只读试验模式已开" }
        if !store.hasPasscode { return "这台手机现在没有任何屏障" }
        return "本机密码已设 · 冷启动要求输密码"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。安全设置可以看，但这一屏不写入 —— 退出空壳后再改。"
        }
        if !store.hasPasscode {
            return "下一步：设一个 4 位以上纯数字密码。之后冷启动要先输它，看密码明文与导出备份也要先输它。"
        }
        return "4 位以上纯数字。密码只存这台手机（摘要落本机安全存储），不上传、不写进锁。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            // 芯片行整排删除后，头部只留标题与导语（本页没有「别处看不到」的数字可报）。
            EmptyView()
        } content: {
            if decoyed {
                decoyCard
            } else {
                // 2026-11-05（用户指令：减少文字、图形化变多）：本页在做完冗余清理后
                // 只剩文字卡。这里加一枚**保护项环** —— 4 项全是真实开关
                //（本机密码 / 胁迫码 / 生物识别 / 非只读试验），不是编出来的健康分。
                protectionCard
                passcodeCard
                if !store.hasPasscode && store.hasDuressCode {
                    duressOrphanCard
                }
                if store.hasPasscode {
                    duressCard
                } else {
                    unsetCard
                }
                biometricCard
                lockSideCard
                unlockCard
                trialCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { route in
            switch route {
            case .passcode:
                PasscodeSheet(kind: .passcode)
            case .duress:
                PasscodeSheet(kind: .duress)
            case .verifyPass:
                VerifyPasscodeSheet(
                    title: "关闭本机密码",
                    note: "关闭前先验证当前本机密码。"
                ) { DB.setPasscode(nil) }
            case .verifyDuress:
                VerifyPasscodeSheet(
                    title: "关闭胁迫码",
                    note: "关闭前先验证当前本机密码。"
                ) { _ = DB.setDuressCode(nil) }
            }
        }
        .v8Confirm(
            isPresented: $confirmDisablePass,
            title: "关闭本机密码？",
            consequence: "关闭后冷启动不再需要密码，任何拿到这台手机的人都能直接打开 App。锁内凭证与门锁数据不受影响。这一步可以撤销：随时可以重新设置本机密码。",
            confirmTitle: "继续验证"
        ) {
            pendingVerify = .verifyPass
        }
        .v8Confirm(
            isPresented: $confirmDisableDuress,
            title: "关闭胁迫码？",
            consequence: "关闭后，被胁迫时输错密码不会进入空壳模式 —— 门会打不开，数据照常显示。这一步可以撤销：随时可以重新设置胁迫码。",
            confirmTitle: "继续验证"
        ) {
            pendingVerify = .verifyDuress
        }
        .onChange(of: confirmDisablePass) { _, open in
            if !open { consumePendingVerify() }
        }
        .onChange(of: confirmDisableDuress) { _, open in
            if !open { consumePendingVerify() }
        }
    }

    /// 对话框退场后消费待呈现的验证框。
    private func consumePendingVerify() {
        guard let pending = pendingVerify else { return }
        pendingVerify = nil
        sheet = pending
    }

    // MARK: - 芯片行

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "安全", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，这一屏既不显示也不改写本机安全设置 —— 改密码、关密码、关胁迫码都会直接改写真实的密码摘要与胁迫码记录，一次误触就能把真实屏障拆掉。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 0 保护项环

    /// 已开启的保护项数（4 项，全部是真实开关）。
    private var protectionOn: Int {
        var n = 0
        if store.hasPasscode { n += 1 }
        if store.hasDuressCode { n += 1 }
        if store.bioUnlock && biometricHardwareAvailable && !store.hasDuressCode { n += 1 }
        if !app.trialGuard { n += 1 }   // 只读试验是排障手段；关着才算正常保护
        return n
    }

    private var protectionCard: some View {
        VCard2 {
            HStack(alignment: .center, spacing: V8.S.gapL) {
                VHeroRing(
                    fraction: Double(protectionOn) / 4.0,
                    center: "\(protectionOn)",
                    label: "/ 4 项",
                    size: V8.G.segCompactOuter * 2.2,
                    tint: protectionOn >= 3 ? V8.C.ok : (protectionOn >= 2 ? V8.C.warn : V8.C.danger)
                )
                VStack(alignment: .leading, spacing: V8.S.gapXS) {
                    Text("保护项")
                        .font(V8.T.label)
                        .foregroundStyle(V8.C.ink4)
                    Text(protectionOn >= 3 ? "该开的都开了" : "还有没开的")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("保护项 \(protectionOn) / 4 项")
    }

    // MARK: - 卡 1 本机数据保护

    private var passcodeCard: some View {
        VCard2 {
            VCardHead(eyebrow: "本机数据保护", statement: store.hasPasscode ? "冷启动要求输入密码" : "冷启动免输")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "本机密码", tagTint: V8.C.ink4, title: store.hasPasscode ? "已设" : "未设", value: "")
                VDotRule()
                VDataRow(tag: "胁迫码", tagTint: V8.C.ink4, title: store.hasDuressCode ? "已设" : "未设", value: "")
                VDotRule()
                VDataRow(tag: "冷启动", tagTint: V8.C.ink4, title: store.hasPasscode ? "要求" : "免输", value: "")
            }
            .padding(.top, V8.S.gapS)
            Text("4 位以上纯数字。密码只存这台手机（摘要落本机安全存储），不上传、不写进锁。它同时是查看密码明文与导出备份的前置屏障。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                sheet = .passcode
            } label: {
                Text(store.hasPasscode ? "更改本机密码" : "设置本机密码")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, V8.S.gapM)
            .accessibilityLabel(store.hasPasscode ? "更改本机密码" : "设置本机密码")
            if store.hasPasscode {
                Button(role: .destructive) {
                    confirmDisablePass = true
                } label: {
                    Text("关闭本机密码")
                        .font(V8.T.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: V8.H.min)
                }
                .padding(.top, V8.S.gapS)
                .accessibilityLabel("关闭本机密码")
            }
        }
    }

    // MARK: - 卡 2 胁迫码

    private var duressCard: some View {
        VCard2 {
            VCardHead(eyebrow: "胁迫码", statement: store.hasDuressCode ? "已设" : "未设")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text(store.hasDuressCode
                 ? "被胁迫时输入胁迫码：门照样能开，但凭证与记录显示为空 —— 不报警、不暴露。"
                 : "另设一个与真密码不同的数字。输入它时 App 进入空壳模式：门能开，数据看不见。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                sheet = .duress
            } label: {
                Text(store.hasDuressCode ? "更改胁迫码" : "设置胁迫码")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .overlay(
                        RoundedRectangle(cornerRadius: V8.R.capsule(V8.H.min), style: .continuous)
                            .strokeBorder(V8.C.line, lineWidth: V8.E.hair)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, V8.S.gapM)
            .accessibilityLabel(store.hasDuressCode ? "更改胁迫码" : "设置胁迫码")
            if store.hasDuressCode {
                Button(role: .destructive) {
                    confirmDisableDuress = true
                } label: {
                    Text("关闭胁迫码")
                        .font(V8.T.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: V8.H.min)
                }
                .padding(.top, V8.S.gapS)
                .accessibilityLabel("关闭胁迫码")
            }
        }
    }

    // MARK: - 卡 2'' 失效组合（本机密码没了但胁迫码还在）

    private var duressOrphanCard: some View {
        VFailure(
            what: "本机密码没了，但胁迫码还留着",
            why: "胁迫码只在冷启动输入框里才用得上；本机密码为空时冷启动直接进 App，这串胁迫码永远不会被触发 —— 你以为有张安全网，其实没有。",
            next: "下一步：重新设置本机密码，或先把这条用不上的胁迫码关掉。"
        )
    }

    // MARK: - 卡 2' 未设密码时的出路

    private var unsetCard: some View {
        VCard2(style: .well) {
            // 2026-11-05（对抗审查 · 设计冗余）：这句「这台手机现在没有任何屏障」正是本页的
            // 判断句（页标题），卡头又原样说了一遍。卡头改成说**这张卡要做什么**。
            VCardHead(eyebrow: "未设密码", statement: "下一步：设一个本机密码")
            Text("下一步：设一个 4 位以上纯数字密码。之后冷启动要先输它，看密码明文与导出备份也要先输它 —— 手机丢了，锁内凭证也不会被人直接读走。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "先看看锁端安全设置", detail: "安全模式在锁实况、布防在布防页") {
                router.request(.dest(.lockStatus))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 3 生物识别

    /// 生物识别硬件是否真的可用（与 LockKeeperApp 里的 canUseBiometrics() 同判据）。
    private var biometricHardwareAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
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

    private var biometricCard: some View {
        VCard2 {
            VCardHead(eyebrow: "生物识别", statement: biometricName)
            VDivider2()
                .padding(.top, V8.S.gapM)
            VDataRow(tag: "硬件", tagTint: V8.C.ink4, title: biometricName, value: "")
                .padding(.top, V8.S.gapS)
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                Toggle(isOn: settingsBinding(\.bioUnlock)) {
                    Text("允许面容 / 指纹解锁")
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                }
                .frame(minHeight: V8.H.min)
                .disabled(store.hasDuressCode || !biometricHardwareAvailable)
                .opacity((store.hasDuressCode || !biometricHardwareAvailable) ? 0.45 : 1)
                Text(store.hasDuressCode
                     ? "已设胁迫码时本开关自动停用 —— 刷脸会暴露「这不是伪装模式」。"
                     : (biometricHardwareAvailable
                        ? "冷启动时可用 Face ID / Touch ID 解锁；失败仍可输本机密码。"
                        : "这台设备没有可用的面容 / 指纹（未录入或硬件不支持）—— 打开本开关也不会生效。"))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 4 锁端安全（这两项不在本页改，只给入口）

    private var defendText: String {
        DefendKit.isActive(DB.defend(app.currentMac)) ? "布防中" : "未布防"
    }

    private var lockSideCard: some View {
        VCard2 {
            VCardHead(eyebrow: "锁端安全", statement: app.lock?.model ?? "还没有门锁")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VNavRow(title: "安全模式", detail: "A 模式单验、B 模式双验 —— 切换要连上锁并回读确认", value: "在锁实况改") {
                    router.request(.dest(.lockStatus))
                }
                VDotRule()
                VNavRow(title: "布防", detail: "布防时段内，靠近自动开锁会被自动否决；防拆事件也会关掉自动开锁", value: defendText) {
                    router.request(.dest(.defend))
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 卡 5 开锁确认

    private var unlockCard: some View {
        VCard2 {
            VCardHead(eyebrow: "开锁确认", statement: "怎么算一次确认")
            VDivider2()
                .padding(.top, V8.S.gapM)
            toggleRow("失败自动重试", detail: "一次没开成时自动重试两次（2 秒 / 5 秒退避）。超时不重试 —— 免得在门口反复广播。", isOn: settingsBinding(\.autoRetry))
            Text("只改「失败后怎么处理」，不改锁端策略。安全模式（A / B）是锁端的事，改它要连上锁并回读确认。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 卡 6 只读试验模式

    private var trialCard: some View {
        VCard2 {
            VCardHead(eyebrow: "排障", statement: app.trialGuard ? "只读试验模式已开" : "只读试验模式关闭")
            VDivider2()
                .padding(.top, V8.S.gapM)
            toggleRow("只读试验模式", detail: "开启后下发到门锁的写命令全部停用：只能读状态，不能改锁、不能下发凭证。用来在真机上排障而不会把锁改坏。", isOn: trialGuardBinding(app))
            // 2026-11-05（截图审查）：卡头已经写着「只读试验模式已开 / 关闭」，这行又重复一遍状态。
            // 只留卡头没有的那半句：本机台账仍然可编辑。
            Text(app.trialGuard ? "本机台账仍可编辑 —— 只有往锁端下发的写命令被拦。" : "往锁端下发的写命令可用。")
                .font(V8.T.footnote)
                .foregroundStyle(app.trialGuard ? V8.C.danger : V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 行构件

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: V8.H.min)
            Text(detail)
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, V8.S.gapS)
    }
}
