// SecurityScreens.swift —— 安全 / 外观 / 关于。
import SwiftUI
import UIKit
import UserNotifications

// MARK: - 安全

@MainActor
struct SecurityScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var sheet: SheetKind?
    @State private var trial = TrialGuard.isOn
    /// 关掉本机密码要先问一句：这一步会把冷启动的门禁整个拆掉，
    /// 拿到手机的人可以直接看到全部凭证 —— 点错了没有第二道闸。
    @State private var confirmingDisable = false
    /// 通知授权状态。
    ///
    /// Engine 的 `NotifyAuth.status` 是**同步**读的（内部 `DispatchSemaphore.wait` 最多 2 秒），
    /// 直接写在 body 里会让这一屏每次求值都卡住主线程 —— `label` 还会再读一次，合计最多 4 秒。
    /// 这里改成用系统自带的 async 接口读一次，缓存在状态里。
    @State private var notifyStatus: UNAuthorizationStatus = .notDetermined

    private enum SheetKind: String, Identifiable {
        case passcode, duress
        var id: String { rawValue }
    }

    private var notifyLabel: String {
        switch notifyStatus {
        case .authorized: return "已开启"
        case .denied: return "已拒绝"
        case .notDetermined: return "未询问"
        case .provisional: return "临时授权"
        case .ephemeral: return "会话授权"
        @unknown default: return "未知"
        }
    }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 安全", back: { dismiss() })

            DisplayLine(text: DB.hasPasscode() ? "门里门外，\n都有边界。" : "先给自己\n一把钥匙。", size: 34)
                .padding(.top, 16)
            Text("本机密码只保护这台手机上的数据；它和门锁的密码是两回事。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SectionHead(index: "01", title: "本机")
            Button { sheet = .passcode } label: {
                ContentRow(symbol: "lock.shield",
                           title: DB.hasPasscode() ? "修改本机密码" : "设置本机密码",
                           subtitle: DB.hasPasscode() ? "冷启动与 30 秒后回前台会重新要求" : "4–8 位数字；忘了只能删 App",
                           chevron: true)
            }
            .buttonStyle(.plain)

            // 空壳里整行都不出现。
            //
            // 这一行写着「修改胁迫码 / 输入它会进入空壳模式」，而胁迫者很可能就站在旁边。
            // 看见它 = 确认这台手机设过胁迫码 = 当场逼问"你刚才是不是输了那组数字"。
            // 空壳里这一页就当一个从没设过胁迫码的普通 App。
            if !DB.isDecoy {
                Button { sheet = .duress } label: {
                    ContentRow(symbol: "eye.slash",
                               title: DB.hasDuressCode() ? "修改胁迫码" : "设置胁迫码",
                               subtitle: DB.hasDuressCode() ? "输入它会进入空壳模式" : "被胁迫时用的另一组密码",
                               chevron: true)
                }
                .buttonStyle(.plain)
            }

            // 空壳里不给「关闭本机密码」。
            //
            // 这个动作会真的清掉 `DB.setPasscode(nil)` 与 `DB.setDuressCode(nil)` ——
            // 胁迫者点两下就能拆掉冷启动门禁，并**抹掉胁迫码本身**。空壳是只读的伪装，
            // 不能成为拆掉伪装的入口。
            if DB.hasPasscode() && !DB.isDecoy {
                Button {
                    confirmingDisable = true
                } label: {
                    ContentRow(symbol: "lock.open", tone: .danger, title: "关闭本机密码",
                               subtitle: "关闭后冷启动不再询问", chevron: true)
                }
                .buttonStyle(.plain)
            }

            // 只读试验会真的改写本机的只读开关：在空壳里打开它，退出后整个 App 都不能开锁。
            if !DB.isDecoy {
                SectionHead(index: "02", title: "只读试验")
                SwitchLine(title: "只读试验模式", detail: "开锁、写凭证、改锁设置、刷固件、导入备份全部被拦下。", isOn: $trial)
                    .onChange(of: trial) { _, value in
                        TrialGuard.set(value)
                        app.trial = value
                    }
            }

            // 空壳里「只读试验」整段不摆，编号要跟着连续，不能从 01 直接跳到 03。
            SectionHead(index: DB.isDecoy ? "02" : "03", title: "状态")
            if notifyStatus == .authorized {
                ContentRow(symbol: "bell", tone: .cool, title: "通知",
                           subtitle: "已授权 · 到期与低电提醒会送达")
            } else {
                // 未授权时这一行原先只是一个死状态：写着"未授权"，却没有去授权的路。
                Button {
                    requestNotify()
                } label: {
                    ContentRow(symbol: "bell", tone: .cool, title: "通知",
                               subtitle: "未授权（\(notifyLabel)） · 点此开启", chevron: true)
                }
                .buttonStyle(.plain)
            }

            // 同样：空壳里不解释胁迫码。这段说明本身就是"这台手机有胁迫模式"的证据。
            if !DB.isDecoy {
                Text("胁迫码：用另一组数字进入「空壳」。门照样能开，但凭证、记录、成员都会显示为空。它不会发出任何提示。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(3)
                    .padding(.top, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { kind in
            switch kind {
            case .passcode: PasscodeSheet(kind: .passcode)
            case .duress: PasscodeSheet(kind: .duress)
            }
        }
        .confirmationDialog("关闭本机密码？", isPresented: $confirmingDisable, titleVisibility: .visible) {
            Button("关闭", role: .destructive) {
                // 双保险：入口在空壳里已经隐藏，这里再守一道 —— 这条路径删的是真实的
                // 冷启动密码与胁迫码，是空壳最不该拥有的能力。
                guard !DB.isDecoy else { return }
                DB.setPasscode(nil)
                // 胁迫码的**唯一入口**就是门禁。密码一关，它就再也输不进去；
                // 若留着，用户以后重新设密码时它会悄悄复活 —— 而那时多半已经忘了这串数字。
                DB.setDuressCode(nil)
                app.unlocked = !DB.hasPasscode()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(DB.hasDuressCode()
                 ? "冷启动不再询问。胁迫码也会一并清除 —— 没有门禁就输不进它，留着只会在你下次设密码时悄悄复活。凭证仍然在手机里，拿到手机的人可以直接打开。"
                 : "冷启动不再询问。凭证仍然在手机里，拿到手机的人可以直接打开。")
        }
        .task {
            await refreshNotifyStatus()
        }
    }

    private func refreshNotifyStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifyStatus = settings.authorizationStatus
    }

    private func requestNotify() {
        if notifyStatus == .denied {
            // 已被拒绝时系统不会再弹窗，只能把用户送到系统设置。
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        NotificationAuth.ensure()
        Task {
            // 系统弹窗是异步的；等一拍再回读，别让这一行停在「未询问」。
            try? await Task.sleep(for: .seconds(1))
            await refreshNotifyStatus()
        }
    }
}

// MARK: - 密码设置

@MainActor
struct PasscodeSheet: View {
    enum Kind { case passcode, duress }

    @Environment(\.dismiss) private var dismiss

    let kind: Kind

    @State private var first = ""
    @State private var second = ""
    @State private var errorLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(T.C.ink4.opacity(0.5))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            DisplayLine(text: kind == .passcode ? "设一组\n本机密码。" : "设一组\n胁迫码。", size: 30)
                .padding(.top, 18)
            Text(kind == .passcode
                 ? "4–8 位数字。它只保护这台手机上的钥匙串与台账。"
                 : "4–8 位数字，必须与正常密码不同。输入它进入空壳，不会发出任何提示。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            FieldInput(placeholder: "输入", text: $first, secure: true, keyboard: .numberPad)
                .padding(.top, 22)
            FieldInput(placeholder: "再输一次", text: $second, secure: true, keyboard: .numberPad)
                .padding(.top, 10)

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 10)
            }

            PrimaryButton(title: "保存") { save() }
                .padding(.top, 22)

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .background(T.C.canvas)
        .presentationDetents([.height(460)])
    }

    private func save() {
        // 空壳里不能改密码：这一页会写真实的 `kf_passcode` / `kf_duress`。
        // 最坏的情况不是"改了个数字" —— 而是胁迫者当场设一组他知道的密码，
        // 锁屏后再用这组密码解锁，就绕开了空壳、直接进真实界面。
        guard !DB.isDecoy else {
            errorLine = "当前无法保存，请稍后再试。"
            return
        }
        guard first == second else {
            errorLine = "两次输入不一致。"
            return
        }
        guard first.count >= 4, first.count <= 8, first.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            errorLine = "请用 4–8 位数字。"
            return
        }
        let ok: Bool
        switch kind {
        case .passcode:
            if DB.verifyDuress(first) {
                errorLine = "这组数字已经用作胁迫码了。"
                return
            }
            ok = DB.setPasscode(first)
        case .duress:
            if DB.verifyPasscode(first) {
                errorLine = "胁迫码不能和正常密码相同。"
                return
            }
            ok = DB.setDuressCode(first)
        }
        if ok {
            dismiss()
        } else {
            errorLine = "保存没成功，请再试一次。"
        }
    }
}

// MARK: - 外观

@MainActor
struct AppearanceScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var theme = SettingsStore.shared.theme
    @State private var haptics = SettingsStore.shared.haptics
    @State private var keepAwake = SettingsStore.shared.keepScreenAwake
    @State private var grid = SettingsStore.shared.quickGridCount

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 外观", back: { dismiss() })

            DisplayLine(text: "光，\n决定了一切。", size: 34)
                .padding(.top, 16)
            Text("日光只有一种 —— 陶土纸、黄铜、和一层会呼吸的自然光。深浅由你决定。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SectionHead(index: "01", title: "明暗")
            SegmentedBar(items: ["跟随系统", "浅色", "深色"], selected: Binding(
                get: { theme.isEmpty ? 0 : (theme == "light" ? 1 : 2) },
                set: {
                    theme = $0 == 0 ? "" : ($0 == 1 ? "light" : "dark")
                    SettingsStore.shared.setTheme(theme)
                }
            ))

            SectionHead(index: "02", title: "今日的托盘")
            HStack {
                Text("工具数量")
                    .type(T.F.callout)
                    .foregroundStyle(T.C.ink)
                Spacer()
                Stepper(value: $grid, in: 3 ... 6) {
                    Text("\(grid)")
                        .type(T.F.monoBig)
                        .foregroundStyle(T.C.ink)
                }
                .labelsHidden()
                .tint(T.C.brass)
                .onChange(of: grid) { _, value in SettingsStore.shared.setQuickGridCount(value) }
            }
            .padding(.vertical, 6)
            Text("改动会立刻反映在「今日」的托盘上。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)

            SectionHead(index: "03", title: "手感")
            SwitchLine(title: "触感反馈", detail: "开锁、校准、成功与失败都有对应震动。", isOn: $haptics)
                .onChange(of: haptics) { _, value in SettingsStore.shared.setHaptics(value) }
            SwitchLine(title: "开门时保持亮屏", detail: "站在门口时不至于中途息屏。", isOn: $keepAwake)
                .onChange(of: keepAwake) { _, value in SettingsStore.shared.setKeepScreenAwake(value) }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - 关于

@MainActor
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 关于", back: { dismiss() })

            VStack(alignment: .leading, spacing: 12) {
                Text("阈")
                    .type(T.F.wordmarkHero)
                    .foregroundStyle(T.C.ink)
                Kicker(text: "THRESHOLD", dot: false)
                DisplayLine(text: "一个家，\n和它的边界。", size: 30)
                    .padding(.top, 4)
            }
            .padding(.top, 22)

            SectionHead(index: "01", title: "事实")
            infoRow("版本", "1.0")
            infoRow("构建", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            // 空壳里不显示真实开锁次数：它是从原始存储直接读的终身计数，
            // 而空壳承诺「记录是空的」—— 一个四位数放在这里等于自证有历史。
            if !DB.isDecoy {
                infoRow("开锁次数", "\(Milestones.unlockTotal) 次")
            }
            infoRow("网络", "没有服务器")
            infoRow("账号", "没有账号")
            infoRow("数据", "全部在本机 · 密钥在 Keychain")

            SectionHead(index: "02", title: "说明")
            Text("阈 是一个完全离线的门锁客户端。它通过蓝牙直接和门锁说话：配对、开锁、写凭证、读记录。没有任何请求发往云端。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
            Text("协议层是既有的、经过字节级差分验证的实现；界面与交互是重新设计的。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .type(T.F.callout)
                .foregroundStyle(T.C.ink2)
            Spacer()
            Text(value)
                .type(T.F.mono)
                .foregroundStyle(T.C.ink)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(T.C.hair).frame(height: 0.5)
        }
    }
}
