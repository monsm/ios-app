// ================= 首启引导 (功能包14: 550/801/802/803/804/809/811/813) =================
// 首启五步: 承诺页 → 三卡导览 → 角色选择 → 权限说明 → 演示锁试玩 → 自检清单 → 就任证书。
// 进度逐键存档 (kf_first_tour_done 族, 804): 杀 App 重开从上一步继续, 不重放。
import SwiftUI
// import CoreLocation 随 2026-10-15 撤掉定位授权申请一并去掉 (本文件已无任何 CL 符号)
import UserNotifications

// ---------- 引导进度存档 (804): 每一步独立打点, 重开继续 ----------
enum Onboarding {
    static let kTourDone = "kf_first_tour_done"

    static func done(_ step: String) -> Bool { DB.store.getBool("kf_onb_" + step) }
    static func mark(_ step: String) { DB.store.set("kf_onb_" + step, true) }
    static var allDone: Bool { DB.store.getBool(kTourDone) }
    static func finishTour() { DB.store.set(kTourDone, true) }
    /// 853 引导三卡的文字**唯一出处** —— 界面 (tourCard) 与"听完整讲解"的串讲稿共用这一份。
    /// 原句要的是"把各卡要点串成一段连续音频": 串讲若另写一份稿子, 界面改了字它就会各说各话。
    static let tourSpec: [(icon: String, title: String, body: String)] = [
        ("dot.radiowaves.left.and.right", "连锁", "蓝牙直连门锁, 无网关无云。添加设备只需长按门锁 RESET 键一次。"),
        ("key.horizontal", "录凭证", "密码与指纹台账记在本机; 给家人发临时码, 到期自动归档。"),
        ("lock.open", "开门", "靠近门锁, 在圆盘上轻点或上滑即开; 失败有排查清单兜底。"),
    ]
    /// 805 重看入口用: 已完成的步骤清单。
    /// 旧写法 `dropFirst(5)` 从 "kf_onb_promise" 只削掉 "kf_on" —— 证书页列出来的是 "b_promise"
    /// 这类带残头的英文键名, 而且 "kf_onb_ceremony" (813 的展示旗标) 也会混进"已完成步骤"。
    /// 改为按 Step 枚举取中文标题: 只有真步骤会被列出, 名字与页面所见一致 (813 就消费这份)。
    static var finishedSteps: [String] {
        Step.allCases.filter { done($0.key) }.map { $0.title }
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

    init(onExit: @escaping () -> Void = {}) {
        self.onExit = onExit
        _step = State(initialValue: Onboarding.nextStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 814 进度点: 顶部 1-7 圆点标出当前阶段与下一步 (七步枚举 allCases, 与第 x/7 文字同口径)
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
            backRow
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
        // 810 的两条收尾: 换页就停 (念着第一张却看着第三张 = 串台), 关引导也停。
        .onChange(of: page) { _, _ in Speech.stop() }
        .onDisappear { Speech.stop() }
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

    // ---------- 上一步 (2026-10-16 拍板 §7.11-C 方案③, 第二十批) ----------
    // 口径: 只在**还没落库的步骤之间**可退。`.role` 这一页自己不写库 —— 写发生在点「下一步」那一刻:
    //   `advance()` 的 `.role` 分支调 `applyRoleDefaults`, 由它把角色默认成员建进台账 (全文件唯一一处成员写入)。
    //   ⚠ 这段注释刻意不写那句"某存储方法"的字面量: 台账里 `grep -c` 的那把尺子数的是**行**,
    //   注释里复述一遍就把期望值从 1 顶成 3 了 (§7.5-12: 判据命令要能原样跑出写下时的数)。
    // 过了 `.role` 只剩两种"回退": ① 退回导览却留着已建的成员 (中间态, 得额外披露一句才不骗人);
    //   ② 回退时把成员删掉 (不可逆, 还牵扯他名下凭证与回收站)。拍板取第三种: **按钮就地禁用并说明原因** ——
    //   代价是"上一步"对后半程不可用, 这是**接受下来的代价, 不是漏做**, 别在下一批顺手改成①或②。
    // 禁用要看得见于人: 本仓 `PrimaryActionStyle` / `SecondaryActionStyle` 都不读 `isEnabled`,
    //   裸 `.disabled(true)` 按下去零变化 = 又一个"看起来在工作的死形状" ⇒ 照「写入中…」那条先例把标签一起改掉。
    // 第一步 (.promise) 没有"上一步"可回 ⇒ 整行不出现, 不留一枚恒灰的按钮。
    private var canGoBack: Bool {
        step.rawValue > Onboarding.Step.promise.rawValue && step.rawValue <= Onboarding.Step.role.rawValue
    }
    @ViewBuilder
    private var backRow: some View {
        if step != .promise {
            Button(canGoBack ? "上一步" : "上一步 · 已不可回退") {
                withAnimation(DS.Motion.standard) {
                    step = Onboarding.Step(rawValue: step.rawValue - 1) ?? .promise
                }
            }
            .buttonStyle(SecondaryActionStyle())
            .disabled(!canGoBack)
            .padding(.horizontal, DS.Space.gutter)
            if !canGoBack {
                Text("「你的角色」那一步已经把成员档案写进了这台手机, 再往前退会牵动那份档案 (删它更不可逆), 所以这里不再给上一步。想整轮重来请用设置页的「重看新手引导」。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.vertical, DS.Space.xs)
            }
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
            // 2026-10-15 走查: 就任证书上那行日期此前取的是"看的那天的 dayKey()" —— 没有任何完成时刻落盘,
            // 于是设置里回看证书, 日期每天变。这一刻就是完成时刻, 顺手钉下来 (旧用户没这一键, 证书那行
            // 会退回不报日期 —— 报一个没存过的日期比不报更贵)。
            DB.store.set("kf_onb_ceremony_at", Milestones.dayKey())
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
        // 2026-10-15 走查: 这一支原先有 `let loc = CLLocationManager(); loc.requestWhenInUseAuthorization()`。
        // 撤掉它，三个理由同在一处：① 802 原句只要求**蓝牙**的前置说明卡（"用 dot.radiowaves 解释蓝牙用途,
        // 再触发系统权限弹窗"），没有定位这一项；② 本页自己就写着「为『到家自动开锁』这类到位置身功能预留；
        // **当前版本不读取你的坐标**」，一边说不读坐标一边弹授权框，是界面与代码各说一套；
        // ③ 920 那条安装位置字段已判舍弃，全仓没有任何消费位置读数。
        // 原先报的"loc 出函数即释放 ⇒ 弹窗可能不弹"这条确实成立，但**修法是删掉这次申请，
        // 不是把它 retain 住** —— 那只会让一个没有功能承接的系统弹窗更稳定地弹给用户。
        let center = UNUserNotificationCenter.current()
        // 只申请，不缓存答案 (第九十四批删掉 `DB.store.set("kf_onb_notify", granted)`):
        // 全仓零读取方，而通知授权用户随时能在系统设置里改 —— 存下来的那一份**必然会说谎**，
        // 将来谁接了它显示"已授权"就是错信息。要显当前状态就该现问 getNotificationSettings。
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        // 2026-10-15 走查·CI 补刀: 这里原先剩一句 `_ = loc` —— 它是旧写法里"别让 loc 变未使用"的消警告句,
        // 上面删掉那次定位申请时把它留下了 ⇒ 编译报 "cannot find 'loc' in scope" (run 99 抓出)。
    }

    // ---------- 550 首启承诺页 ----------
    private var promisePage: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            // 841 小管家记忆点: 第一眼就见到它 (组件面全仓消费点: 各引导空态卡顶饰 + 这一处首见)。
            // 素颜模式 (kf_plain / DS.Metric.emptyMascot) 与空态同一闸, 不再单开"隐藏插画"开关。
            if DS.Metric.emptyMascot {
                HStack(spacing: DS.Space.s) {
                    DemoMascot(size: 44)
                    Text("小管家陪你走第一步")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("小管家欢迎页")
            }
            Text("数据只在这台手机")
                .font(.title2.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            Text("本 App 默认全程离线: 门锁密钥、密码台账、家人档案保存在本机加密存储, 无账号、不依赖厂商服务器。厂商云已停服, 你不需要它。唯一会联网的地方是你主动开启的 WebDAV 备份通道 (自选网盘, 默认关闭)。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            promiseRow("wifi.slash", "默认无联网", "全部门锁功能离线可用; WebDAV 备份通道由你主动配置, 默认关")
            promiseRow("lock.shield", "本机密钥", "钥匙串只写本地存储, 导入导出由你保管")
            promiseRow("envelope.open", "备份自留", "换新手机用「备份与恢复」, 默认全程本机, 也可选你自配的 WebDAV")
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
        let spec = Onboarding.tourSpec   // 853: 与"听完整讲解"共用一份 (不再各写一遍)
        let t = spec[i]
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: t.0)
                    .font(.system(size: DS.Icon.xl, weight: .medium))
                    .foregroundStyle(DS.heroFg)
                    .frame(width: 64, height: 64)
                    .background(DS.heroGradientSafe, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    app.requestRoute(.device)
                    app.pendingAddDevice = true   // 801: 设备页挂载后直接弹添加设备 (直达扫描)
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
                .accessibilityHint("结束引导, 直接进设备页并弹出添加设备")
            }
            HStack(spacing: DS.Space.s) {
                Spacer(minLength: 0)
                // 810 逐卡朗读 (Voice Dream Reader 那一形态): 念的就是这张卡自己那两行字 ——
                // 取自同一个 `spec` 数组, 不另写一份口播稿, 否则界面与朗读会各自漂移。
                // 再点一次是**重念这一张**: Speech.zh 开口前先停上一句, 所以不会出现两句叠在一起
                // (那正是收掉两台各自 new 的 synthesizer 之前会发生的事)。
                Button {
                    _ = Speech.zh(t.1 + "。" + t.2)
                } label: {
                    Label("朗读这张卡", systemImage: "speaker.wave.2.circle.fill")   // 810 朗读这张卡
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint("用系统本地语音念出本卡说明, 服务不开 VoiceOver 也想听一遍的用户")
                // 853 听完整讲解: 把三卡要点串成一段连续音频 (稿子取自同一个 tourSpec)。
                // 与 810 的差别: 810 是"念这一张", 这里是一次念完三张 —— 原句要的就是"串讲"。
                Button {
                    _ = Speech.zh(Onboarding.tourSpec.map { $0.title + "。" + $0.body }.joined(separator: " "))
                } label: {
                    Label("听完整讲解", systemImage: "play.circle.fill")   // 853 听完整讲解
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DS.Palette.accentText)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint("把三步引导连起来一次念完")
            }
        }
        .padding(DS.Space.l)
        // 2026-10-14 材质统一: 引导页主面板与全 App 的 Card 同材质
        .axGlass(DS.Radius.card)
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
                    .foregroundStyle(rolePick == key ? DS.heroFg : DS.Palette.textSub)
                    .frame(width: 40, height: 40)
                    .background(rolePick == key ? AnyShapeStyle(DS.heroGradientSafe) : AnyShapeStyle(DS.Palette.surfaceAlt),
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
            // 2026-10-14 材质统一: 角色卡上玻璃。下面那圈描边留着 —— 它画的是"选中/未选中"状态,
            // 不是装饰边 (accent 1.5 vs hairline 0.5); 卡里那枚图标底板仍是 surfaceAlt, 属玻璃上的盘子。
            .axGlass(DS.Radius.card)
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
                    // 原句写的是"iOS 规则: 蓝牙扫描需要定位授权" —— 那是 Android 6~11 的规则，iOS 上
                    // BLE 扫描不要定位授权。留着这句有两个害处：① 用户以为拒定位就不能开锁；
                    // ② 掩盖了真实状态 —— 本仓目前没有任何一处读坐标 (见 project.yml 那条 ⚠)。
                    Text("为「到家自动开锁」这类到位置身功能预留；当前版本不读取你的坐标。拒绝这一项，蓝牙扫描与照常开锁不受影响。")
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
            // 2026-10-15 走查: 这句原先写着"数据全是 demo_ 前缀, 玩完随手清除" —— 可这一页从头到尾
            // 没有一处 `DemoKit.setOn(true)` (全仓 setOn(true) 只有成就页 / 帮助页 / 设置页那三处),
            // 试玩的是下面那枚**本地模拟圆盘** (demoState / demoPhase, 一行台账都不写)。
            // 803 原句要的也正是"圆盘进入假数据试玩态", 缺的是文案的说法而不是功能: 改成如实描述。
            Text("这一屏是一把本地模拟的演示锁: 圆盘可以转、状态会变, 不碰蓝牙、不写台账。")
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            demoDial
            // 2026-10-15 走查: 这两颗都只在**真开着演示模式**时才出现 —— 本页自己从不打开它。
            // 原先「清除演示数据」无条件常驻, 而没开过演示时它清的是本来就不存在的东西,
            // setOn(false) + loadDevices() 之后屏上零变化、零提示 = 又是一个"点了没反应"。
            if DemoKit.isOn {
                HStack(spacing: DS.Space.s) {
                    Button("清除演示数据") {
                        DemoKit.setOn(false)
                        app.loadDevices()
                        app.showToast("已清除全部演示数据")   // 与设置页那枚演示开关同一句回执
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                    // 2026-10-15 走查: 这句提示原本挂在装着**两枚**按钮的 HStack 上 —— 读屏点另一枚
                    // 也念"清除后…", 那是把另一颗按钮说成了它自己。挪回它说的那一颗。
                    .accessibilityHint("清除后演示锁从设备列表消失, 真实台账不受影响")
                    Button("去设备页看它") {
                        // 引导期间主 TabView 根本不在层级树里 (见 LockKeeperApp 的 rootGroup 那条 if),
                        // 只写 tabSelection 是切了一个还没建出来的 Tab —— 点了屏幕毫无变化。
                        // 收尾照 320 那颗"去连接真锁"同一条路: 先结束引导 (allDone 翻真 → root 换形态), 再落 Tab。
                        Onboarding.finishTour()
                        app.requestRoute(.device)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                }
            }
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

    // ---------- 811 首启自检清单: 蓝牙权限 / 存储空间 / 加密库 三项本地体检 (绿勾=真实探测) ----------
    private var checklistPage: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("出门前自查一遍")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            checkRow("蓝牙权限", ok: BLEService.shared.isPoweredOn, detail: btStatus)
            let storage = DiagHealth.checkStorage()
            checkRow(storage.name, ok: storage.ok, detail: storage.detail)
            let key = String(repeating: "ab", count: 16)
            let probe = "00112233445566778899aabbccddeeff"   // 16 字节整块, 零填充解密只对此回环相等
            let cryptoOK = AESKit.decryptHex(AESKit.encryptHex(probe, keyHex: key), keyHex: key) == probe
            checkRow("加密库", ok: cryptoOK, detail: cryptoOK ? "AES-128 加解密回环通过" : "回环失败 — 请反馈")
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
    }
    private var btStatus: String {
        // 计算属性每帧求值: 避免 @State 快照导致清单详情不随系统蓝牙状态变化 (811)
        let on = BLEService.shared.isPoweredOn
        return on ? "已开启" : "未开启 — 可在系统设置中打开"
    }
    private func checkRow(_ text: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DS.Icon.sm, weight: .semibold))
                .foregroundStyle(ok ? DS.Palette.ok : DS.Palette.textSub)
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
        .accessibilityElement(children: .combine)
    }
    // ---------- 813 管家就任证书: 玻璃证书卡, 进入成就体系时刻卡 ----------
    private var certificatePage: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.heroGradientSafe)
                VStack(spacing: DS.Space.s) {
                    Image(systemName: "rosette")
                        .font(.system(size: DS.Icon.xl, weight: .medium))
                        .foregroundStyle(DS.heroFg)
                        .padding(.top, DS.Space.xl)
                    Text("离线锁管家 · 就任证书")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DS.heroFg)
                    Text(onboardingSub)
                        .font(.footnote)
                        .foregroundStyle(DS.heroFg.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.s) {
                        Label("完成首启引导", systemImage: "checkmark.seal")
                        Label(Milestones.dayKey(), systemImage: "calendar")
                    }
                    .font(.caption2)
                    .foregroundStyle(DS.heroFg.opacity(0.85))
                    .padding(.bottom, DS.Space.l)
                }
                .padding(.horizontal, DS.Space.l)
            }
            .shadow(color: DS.Palette.accent.opacity(0.30), radius: 18, y: 10)
            .padding(.horizontal, DS.Space.l)
            .transition(.scale(scale: 0.94).combined(with: .opacity))

            Button("重看新手引导") {
                // 2026-10-15 走查: 这一枚原先只调 `replayAll()` —— 清了持久化的逐步打点, 却把
                // 当前页 (证书页) 原地留着: 用户按下去看不出任何变化, 而已完成的打点被悄悄抹掉。
                // 设置页那两枚同名按钮都做全了 (replayAll + 落点 + toast), 这一枚漏了两半。
                // 这里就在引导流程内, 不碰 onboardingFinished (人还在引导里), 而是把本地 step 送回第一屏。
                Onboarding.replayAll()
                step = .promise
                app.showToast("已从头重看, 之前的逐步打点已清空")
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
