// ================= 首启引导 (功能包14: 550/801/802/803/804/809/811/813) =================
// 首启五步: 承诺页 → 三卡导览 → 角色选择 → 权限说明 → 演示锁试玩 → 自检清单 → 就任证书。
// 进度逐键存档 (kf_first_tour_done 族, 804): 杀 App 重开从上一步继续, 不重放。
import SwiftUI
import CoreLocation
import UserNotifications

// ---------- 引导进度存档 (804): 每一步独立打点, 重开继续 ----------
enum Onboarding {
    static let kTourDone = "kf_first_tour_done"

    static func done(_ step: String) -> Bool { DB.store.getBool("kf_onb_" + step) }
    static func mark(_ step: String) { DB.store.set("kf_onb_" + step, true) }
    static var allDone: Bool { DB.store.getBool(kTourDone) }
    static func finishTour() { DB.store.set(kTourDone, true) }
    /// 805 重看入口用: 已完成的步骤清单
    static var finishedSteps: [String] {
        DB.store.keys().filter { $0.hasPrefix("kf_onb_") && DB.store.getBool($0) }
            .map { String($0.dropFirst(5)) }
    }
    /// 当前应停在哪一步 (从第一个未完成开始)
    static var nextStep: Step {
        for s in Step.allCases where !done(s.key) { return s }
        return .certificate
    }

    enum Step: Int, CaseIterable, Identifiable {
        case promise, tour, role, permission, demo, checklist, certificate
        var id: Int { rawValue }
        var key: String {
            switch self {
            case .promise: return "promise"
            case .tour: return "tour"
            case .role: return "role"
            case .permission: return "permission"
            case .demo: return "demo"
            case .checklist: return "checklist"
            case .certificate: return "certificate"
            }
        }
        var title: String {
            switch self {
            case .promise: return "开始之前"
            case .tour: return "三卡导览"
            case .role: return "你的角色"
            case .permission: return "为什么需要这些权限"
            case .demo: return "演示锁试玩"
            case .checklist: return "首启自检清单"
            case .certificate: return "就任证书"
            }
        }
    }

    // ---------- 809 角色化引导: 家庭主 / 租客 / 物业, 决定默认成员名与后续话术 ----------
    static let roleKey = "kf_onb_role"
    static var role: String { DB.store.getString(roleKey) }
    static func setRole(_ r: String) { DB.store.set(roleKey, r) }
    /// 角色默认成员名: 选完即建档, 后续引导话术与记录归属围绕它展开
    @MainActor
    static func applyRoleDefaults(_ r: String) {
        setRole(r)
        let names: [String: [String]] = [
            "family": ["我", "爸妈"],
            "renter": ["我"],
            "property": ["访客"],
        ]
        for n in names[r] ?? [] where !DB.members().contains(where: { $0.name == n }) {
            DB.addMember(n)
        }
    }
    static func roleHint() -> String {
        switch role {
        case "family": return "按家庭管: 给家人录指纹/发密码, 关注低电与保养"
        case "renter": return "按租客管: 临时密码为主, 退租时一键清台"
        case "property": return "按物业管: 多把锁总览对比, 访客临时码高频"
        default: return ""
        }
    }
}

// ---------- 首启全页容器: RootView 判定 kf_first_tour_done 后呈现 ----------
struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    var onExit: () -> Void = {}
    @State private var step: Onboarding.Step
    @State private var page = 0            // 801 三卡横滑页
    @State private var demoState: AppState.UnlockState = .idle
    @State private var demoPhase = 0
    @State private var checks: [Bool] = [false, false, false]
    @State private var btStatus: String = ""

    init(onExit: @escaping () -> Void = {}) {
        self.onExit = onExit
        _step = State(initialValue: Onboarding.nextStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 814 进度点: 顶部 1-6 圆点标出当前阶段与下一步
            stepDots
            TabView(selection: $page) {
                switch step {
                case .promise:
                    promisePage.tag(0)
                case .tour:
                    tourPages.tag(0)
                case .role:
                    rolePage.tag(0)
                case .permission:
                    permissionPage.tag(0)
                case .demo:
                    demoPage.tag(0)
                case .checklist:
                    checklistPage.tag(0)
                case .certificate:
                    certificatePage.tag(0)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            advanceButton
            // 804/805: 随时可跳过, 打点保留, 证书页"重看"入口可在设置-帮助找回
            if step != .certificate {
                Button("跳过引导") {
                    Onboarding.finishTour()
                    onExit()
                }
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
            }
        }
        .dsScreenBackground()
        .onAppear { refreshBtStatus() }
    }

    private var stepDots: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(Onboarding.Step.allCases.enumerated()), id: \.offset) { i, s in
                Circle()
                    .fill(s == step ? DS.Palette.accent : DS.Palette.hairline)
                    .frame(width: s == step ? 9 : 7, height: s == step ? 9 : 7)
            }
            Spacer(minLength: 0)
            Text("第 \(step.rawValue + 1)/7 步 · \(step.title)")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s)
    }

    private var advanceButton: some View {
        Button(buttonTitle) { advance() }
            .buttonStyle(PrimaryActionStyle())
            .padding(.horizontal, DS.Space.gutter)
            .padding(.vertical, DS.Space.m)
    }
    private var buttonTitle: String {
        switch step {
        case .certificate: return "完成"
        default: return "下一步"
        }
    }

    private func advance() {
        switch step {
        case .promise:
            Onboarding.mark("promise")
        case .tour:
            Onboarding.mark("tour")
        case .role:
            Onboarding.applyRoleDefaults(rolePick)
            Onboarding.mark("role")
        case .permission:
            Onboarding.mark("permission")
            requestSystemPermissions()
        case .demo:
            Onboarding.mark("demo")
        case .checklist:
            Onboarding.mark("checklist")
            Onboarding.finishTour()
        case .certificate:
            Onboarding.mark("certificate")
        }
        if step == .certificate {
            app.enqueueMoment(Moment(id: "m14.cert", icon: "rosette",
                                     title: "管家就任证书",
                                     subtitle: Onboarding.roleHint().isEmpty ? "首启引导全部完成" : Onboarding.roleHint(),
                                     celebrate: true))
            DB.store.set("kf_onb_ceremony", true)
            onExit()
            return
        }
        withAnimation(DS.Motion.standard) {
            step = Onboarding.Step(rawValue: step.rawValue + 1) ?? .certificate
        }
    }

    @State private var rolePick = "family"
    // 802 权限前置: 系统弹窗在 App 内"申请前"触发, 说明卡先行
    private func requestSystemPermissions() {
        let loc = CLLocationManager()
        loc.requestWhenInUseAuthorization()
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DB.store.set("kf_onb_notify", granted)
        }
        _ = loc
    }

    // ---------- 550 首启承诺页 ----------
    private var promisePage: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("数据只在这台手机")
                .font(.title2.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            Text("本 App 全程离线: 门锁密钥、密码台账、家人档案保存在本机加密存储, 不上传任何服务器, 无账号、无网络依赖。厂商云已停服, 你不需要它。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            promiseRow("wifi.slash", "无网络", "没有任何在线功能, 断网照常管理门锁")
            promiseRow("lock.shield", "本机密钥", "钥匙串只写本地存储, 导入导出由你保管")
            promiseRow("envelope.open", "备份自留", "换新手机用「备份与恢复」, 不经过云端服务")
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
    }
    private func promiseRow(_ icon: String, _ head: String, _ tail: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.md, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: 40, height: 40)
                .background(DS.Palette.accentText.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(head)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text(tail)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    // ---------- 801 三卡导览: 连锁→录凭证→开门 横滑页卡 ----------
    private var tourPages: some View {
        VStack(spacing: DS.Space.m) {
            TabView(selection: Binding(get: { page }, set: { page = $0 })) {
                ForEach(0..<3, id: \.self) { i in
                    tourCard(i)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            HStack(spacing: DS.Space.xs) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == page ? DS.Palette.accent : DS.Palette.hairline)
                        .frame(width: 7, height: 7)
                }
                Spacer(minLength: 0)
                Text("连锁 → 录凭证 → 开门")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
    private func tourCard(_ i: Int) -> some View {
        let spec: [(String, String, String)] = [
            ("dot.radiowaves.left.and.right", "连锁", "蓝牙直连门锁, 无网关无云。添加设备只需长按门锁 RESET 键一次。"),
            ("key.horizontal", "录凭证", "密码与指纹台账记在本机; 给家人发临时码, 到期自动归档。"),
            ("lock.open", "开门", "靠近门锁, 在圆盘上轻点或上滑即开; 失败有排查清单兜底。"),
        ]
        let t = spec[i]
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: t.0)
                    .font(.system(size: DS.Icon.xl, weight: .medium))
                    .foregroundStyle(DS.Palette.onAccent)
                    .frame(width: 64, height: 64)
                    .background(DS.Gradient.hero, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("第 \(i + 1) 步 · \(t.1)")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Text(t.2)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if i == 2 {
                Button("去连接真锁") {
                    Onboarding.finishTour()
                    app.tabSelection = 0
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
                .accessibilityHint("结束引导, 直接进设备页添加门锁")
            }
        }
        .padding(DS.Space.l)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.gutter)
    }

    // ---------- 809 角色化引导 ----------
    private var rolePage: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("你以什么身份管这把锁?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            roleCard("family", "family.fill", "家庭主", "给家人录指纹、发密码, 关怀与提醒围绕全家")
            roleCard("renter", "person.crop.square", "租客", "以临时密码为主, 退租时一键清空台账")
            roleCard("property", "building.2", "物业", "多把锁总览对比, 访客临时码高频流转")
            Text(Onboarding.role == rolePick ? Onboarding.roleHint() : "选择后默认成员与引导话术随之调整, 随时可在设置中重看。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
    }
    private func roleCard(_ key: String, _ icon: String, _ name: String, _ desc: String) -> some View {
        Button {
            withAnimation(DS.Motion.quick) { rolePick = key }
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .medium))
                    .foregroundStyle(rolePick == key ? DS.Palette.onAccent : DS.Palette.textSub)
                    .frame(width: 40, height: 40)
                    .background(rolePick == key ? AnyShapeStyle(DS.Gradient.hero) : AnyShapeStyle(DS.Palette.surfaceAlt),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if rolePick == key {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(DS.Palette.ok)
                }
            }
            .padding(DS.Space.m)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(rolePick == key ? DS.Palette.accent : DS.Palette.hairline,
                                  lineWidth: rolePick == key ? 1.5 : 0.5)
            )
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(name)角色")
        .accessibilityAddTraits(rolePick == key ? [.isSelected] : [])
    }

    // ---------- 802 权限前置说明 ----------
    private var permissionPage: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: DS.Icon.xl, weight: .medium))
                    .foregroundStyle(DS.Palette.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("蓝牙")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Text("用于靠近门锁时直连开锁与读取记录 — 全程点对点, 不经过任何服务器。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: DS.Space.s) {
                Image(systemName: "bell.badge")
                    .font(.system(size: DS.Icon.xl, weight: .medium))
                    .foregroundStyle(DS.Palette.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地通知")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Text("低电量、保养与临时码到期提醒 — 全部由本机排程, 不依赖推送服务。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: DS.Space.s) {
                Image(systemName: "location")
                    .font(.system(size: DS.Icon.xl, weight: .medium))
                    .foregroundStyle(DS.Palette.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("定位")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Text("iOS 规则: 蓝牙扫描需要定位授权。位置数据只在 App 内使用, 不上传。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text("拒绝任何一项 App 都能用, 只是对应功能降级 (如不弹本地提醒)。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.xl)
    }

    // ---------- 803 演示锁试玩: 假锁完整走"添加→看状态→假装开锁", 全程标"演示" ----------
    private var demoPage: some View {
        VStack(spacing: DS.Space.m) {
            Label("演示 · 不碰真实门锁", systemImage: "theatermasks")
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.warn)
            Text("这把演示锁可以完整走一遍: 看状态 → 假装开锁。数据全是 demo_ 前缀, 玩完随手清除。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            demoDial
            HStack(spacing: DS.Space.s) {
                Button("清除演示数据") {
                    DemoKit.setOn(false)
                    app.loadDevices()
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
                if DemoKit.isOn {
                    Button("去设备页看它") {
                        app.tabSelection = 0
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                }
            }
            .accessibilityHint("清除后演示锁从设备列表消失, 真实台账不受影响")
        }
        .padding(DS.Space.l)
    }
    private var demoDial: some View {
        UnlockDial(state: demoState,
                   phase: demoPhase,
                   connected: true,
                   bleReady: true,
                   failStreak: 0,
                   retryText: nil,
                   action: {
                       demoPhase = 1
                       demoState = .connecting
                       Task { @MainActor in
                           try? await Task.sleep(nanoseconds: 500_000_000)
                           demoPhase = 2
                           demoState = .opening
                           try? await Task.sleep(nanoseconds: 800_000_000)
                           demoPhase = 0
                           demoState = .success
                           UINotificationFeedbackGenerator().notificationOccurred(.success)
                           Task { @MainActor in
                               try? await Task.sleep(nanoseconds: 2_000_000_000)
                               demoState = .idle
                           }
                       }
                   },
                   cancelAction: { demoState = .idle; demoPhase = 0 })
    }

    // ---------- 811 首启自检清单: 蓝牙开 / 设备已配网 / 固件可读 三项可勾选打点 ----------
    private var checklistPage: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("出门前自查一遍")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            checkRow("手机蓝牙已开启", detail: btStatus, checked: 0)
            checkRow("门锁已配网 (完成添加设备)", detail: DB.keychains().isEmpty ? "尚未添加" : "\(DB.keychains().count) 把已配", checked: 1)
            checkRow("固件版本可读", detail: DB.keychains().first { !$0.fw.isEmpty }.map { "v" + $0.fw } ?? "待连接后显示", checked: 2)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
    }
    private var btStatus: String {
        let on = BLEService.shared.isPoweredOn
        return on ? "已开启" : "未开启 — 可在系统设置中打开"
    }
    private func checkRow(_ text: String, detail: String, checked: Int) -> some View {
        Button {
            checks[checked].toggle()
            DS.Haptics.tick.impactOccurred()
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: checks[checked] ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(checks[checked] ? DS.Palette.ok : DS.Palette.textSub)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(checks[checked] ? [.isSelected] : [])
    }
    private func refreshBtStatus() {
        btStatus = ""
    }

    // ---------- 813 管家就任证书: 玻璃证书卡, 进入成就体系时刻卡 ----------
    private var certificatePage: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Gradient.hero)
                VStack(spacing: DS.Space.s) {
                    Image(systemName: "rosette")
                        .font(.system(size: DS.Icon.xl, weight: .medium))
                        .foregroundStyle(DS.Palette.onAccent)
                        .padding(.top, DS.Space.xl)
                    Text("离线锁管家 · 就任证书")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DS.Palette.onAccent)
                    Text(onboardingSub)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.onAccent.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.s) {
                        Label("完成首启引导", systemImage: "checkmark.seal")
                        Label(Milestones.dayKey(), systemImage: "calendar")
                    }
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.onAccent.opacity(0.85))
                    .padding(.bottom, DS.Space.l)
                }
                .padding(.horizontal, DS.Space.l)
            }
            .shadow(color: DS.Palette.accent.opacity(0.30), radius: 18, y: 10)
            .padding(.horizontal, DS.Space.l)
            .transition(.scale(scale: 0.94).combined(with: .opacity))

            Button("重看新手引导") {
                Onboarding.replayAll()
            }
            .buttonStyle(SecondaryActionStyle())
            .padding(.horizontal, DS.Space.gutter)
            .accessibilityHint("清除引导打点, 下次启动重新走一遍首启流程")
        }
        .frame(maxHeight: .infinity)
    }
    private var onboardingSub: String {
        let role = Onboarding.role
        return role.isEmpty ? "你已备好连锁、凭证与开门的全部功课。" : "以「" + role + "」身份完成首启, 数据只在这台手机。"
    }
}

extension Onboarding {
    /// 805 重看: 清全部打点 (证书除外), 下次冷启动重新走
    @MainActor
    static func replayAll() {
        for s in Step.allCases where s != .certificate {
            DB.store.remove("kf_onb_" + s.key)
        }
        DB.store.remove(kTourDone)
    }
}
