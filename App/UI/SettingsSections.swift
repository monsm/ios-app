// 设置页 · 各 Section（时间制式 / 开锁 / 自动开锁 / 家人与钥匙 / 工具 / 应用锁 / 关于）
// 2026-10-29 从 SettingsView.swift（1013 行）拆出。
// 是 SettingsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var timeSection: some View {
        Section {
            Picker("时间制式", selection: Binding(
                get: { TimeFormat.style },
                set: { app.setUnlockOption(TimeFormat.styleKey, $0) })) {
                Text("跟随系统").tag("")
                Text("24 小时制").tag("24")
                Text("12 小时制").tag("12")
            }
            VariantToggle("显示秒", isOn: Binding(   // 651 显示秒
                get: { TimeFormat.showSeconds },
                set: { app.setUnlockOption(TimeFormat.secsKey, $0) }))
            VariantToggle("记录行加第二行完整日期", isOn: Binding(   // 648 记录行加第二行完整日
                get: { TimeFormat.twoLine },
                set: { app.setUnlockOption(TimeFormat.twoLineKey, $0) }))
        } footer: {
            Text("秒只在日志原文真的带秒时出现，缺位的行不补 “:00”——那等于假装这条记录精确到秒。\n"
                 + "制式不做时区换算：锁端键盘上写的是几点，这里就显示几点。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
        }
    }
    @ViewBuilder
    var unlockSection: some View {
        // 2026-10-30 性能：`UnlockPrefs.mode` 在本块里被读 3 次（Picker 的 get、disabled 判据、提示条件），
        // 每次都要查一次 UserDefaults。一次读出来共用。
        let gestureMode = UnlockPrefs.mode
        return Section {
            VariantToggle("按住确认开锁", isOn: Binding(
                get: { DB.store.getBool("kf_hold_confirm", true) },
                set: { app.setUnlockOption("kf_hold_confirm", $0) }))
            VariantToggle("误触围栏", isOn: Binding(
                get: { DB.store.getBool("kf_fence") },
                set: { app.setUnlockOption("kf_fence", $0) }))
            // 52/58 开锁手势三档 (第九十八批, 2026-10-10 拍板"手势族全做"后补回)。
            // 默认档 hold 与拍板前的行为**逐字一致**; 另两档是**替代**按住确认的确认方式，互斥而非叠加。
            Picker("开锁手势", selection: Binding(
                get: { gestureMode },
                set: { app.setUnlockOption("kf_gesture_mode", $0) })) {
                Text("按住确认 (默认)").tag("hold")
                        // 2026-10-28 删除：这两档**从未实现** —— `UnlockPrefs.modes = ["hold"]`，
                        // 而 `mode` 的实现是 `modes.contains(v) ? v : "hold"` ⇒ 选什么都回弹到 hold；
                        // `triple` / `charge` 在后台零出现（UnlockDial 没有任何对应手势处理）。
                        // 留着等于给用户两个永远选不上、选了也不生效的假选项。
            }
                        // 2026-10-28：原说明文字讲的是两个不存在的档位，随档位一起删。
            // 53 双击直开: 这是防误触的**减配** (绕过按住确认)，所以默认关、只在按住确认档可开、
            // 标签自己写明「绕过确认」 —— 一个把安全降级说得像便捷特性的开关，本仓不写。
            VariantToggle("双击直开 (绕过按住确认)", isOn: Binding(
                get: { DB.store.getBool("kf_tap_direct") },
                set: { app.setUnlockOption("kf_tap_direct", $0) }))
                .disabled(gestureMode != "hold")
            if gestureMode != "hold" {
                Text("三连点/旋转充能档已自带确认动作，双击直开只在「按住确认」档提供。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            VariantToggle("失败自动重试", isOn: Binding(
                get: { DB.store.getBool("kf_auto_retry", true) },
                set: { app.setUnlockOption("kf_auto_retry", $0) }))
            Picker("圆盘尺寸", selection: Binding(
                get: { DB.store.getInt("kf_dial_size", 176) },
                set: { app.setUnlockOption("kf_dial_size", $0) })) {
                Text("小").tag(160)   // 160 界面文案
                Text("标准").tag(176)   // 176 标准
                Text("大").tag(200)   // 200 界面文案
            }
            .pickerStyle(.menu)
        } header: {
            Text("开锁")
        } footer: {
            // 2026-10-27：把原「安全」节的悬空说明并进来 —— 验证模式与开锁动作是一回事，
            // 拆成两节只会让人在「安全」里找不到能点的东西。
            Text("单次 / 双重验证（A / B 模式）：决定开一道锁还是两道。这是**锁端策略**，切换入口在「设备页 → 管理这把锁 → 能力 → 安全模式 A/B」（两个方向都能切，放宽方向会二次确认）。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            Text("按住圆盘时长 (默认 0.9s，可在上方「外观」里 0.4–1.6s 自定) 或上滑触发开锁；关闭「按住确认」后退回轻点直开 (适合单手与 VoiceOver)。误触围栏开启后需先从圆盘边缘拖到中心再执行开锁手势。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder
    var autoOpenSection: some View {
        if !mac.isEmpty {
            AutoOpenSection(mac: mac)
        }
    }
    @ViewBuilder
    var familySection: some View {
        Section {
            memberFamilyRows
        } header: {
            Text("家人与钥匙")
        } footer: {
            Text("「访客」是本地虚拟分组， 不占锁端槽位; 活跃度与摘录均按台账推断 (约)。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        credCareSection
    }
    @ViewBuilder
    var memberFamilyRows: some View {
        Button { showMembers = true } label: { Label("成员管理（含成员中心）", systemImage: "person.2") }
        // 包9 手机钥匙 (41/43/44 的成员侧): 与「蓝牙钥匙串」并列 ——
        // 前者是把钥匙写进随身硬件, 后者是把 ekey 发给成员的手机, 归属对象不同, 不能合并成一条。
        NavigationLink {
            MobileKeyView()
        } label: {
            Label("手机钥匙", systemImage: "iphone.gen3")
        }
        // 2026-10-28 补：`HardwareService` 的蓝牙钥匙串（ZKBBV1）整套能力早就写好了 ——
        // 5 个服务方法 + 4 个 CRUD + 备份集成都齐，但**零 UI 入口**。
        // 而上面「手机钥匙」的 footer 还在对用户说「与「蓝牙钥匙串」不同：钥匙串是随身硬件」，
        // 用户会去找那个入口 —— 找不到。现在补上（与手机钥匙并列，两者归属对象不同：
        // 一个写进实体硬件，一个发给成员手机，不能合并）。
        NavigationLink {
            DongleView()
        } label: {
            Label("蓝牙钥匙串", systemImage: "key.horizontal")
        }
        // 2026-10-14 走查: 「添加另一把锁」原先挂在本节末尾 —— 它讲的是"再加一把锁", 属于门锁本身,
        // 与"谁能开门"（家人与钥匙）不是同一件事; 而且本节的 footer 正在解释成员分组, 摆一个添加设备
        // 在下面读起来像"给这个成员再加一把锁"。已挪进 lockSection 的「门锁」节 (与「删除设备」同处,
        // 一加一删成对), 空态那一支本来就带「添加设备」按钮。
    }
    @ViewBuilder
    var credCareSection: some View {
        // 2026-10-30 性能：`CredentialOrg.quota(mac)` 与 `aliasDisplay` 各被读 2 次（标签 + Binding.get）。
        // 一次读出来共用。
        let quota = CredentialOrg.quota(mac)
        let aliasOn = CredentialOrg.aliasDisplay
        return Section {
            // 2026-10-14 走查: 原标签「历史版本配额 N 版/凭证」的量纲读不出来 —— "版/凭证" 是
            // "每凭证几版" 还是 "总共几版"? 同一节下面的「回收站保留 N 天」是单值, 两个 Stepper
            // 单位不同却并列, 更容易读岔。改成一句能直接念出来的话。
            Stepper("每个凭证保留 \(quota) 个历史版本", value: Binding(   // 491 历史版本配额
                get: { quota },
                set: { DB.store.set("kf_ccred_quota", $0) }), in: 3...30, step: 1)
                .fixedSize(horizontal: false, vertical: true)
            // 2026-10-26 精简：回收站保留天数设置已删（回收站整套移除）。
            // 2026-10-14: 去掉标签里的内部规格编号 "(919: …)"。它把一行标签撑成两行、把右侧开关挤到
            // 第二行居中，而用户看到的是一串跟自己无关的编号 —— 本仓"乱源治理"清过 1037 处同类，这一处漏了。
            // 语义说明挪进本节 footer，标签回归一行 (截图里折行撑歪开关就是这条)。
            VariantToggle("成员别名显示", isOn: Binding(
                get: { aliasOn },
                set: { DB.store.set("kf_calias_display", $0) }))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("凭证整理")
        } footer: {
            Text("「成员别名显示」开着时， 有备注名的成员优先显示备注 (如「老妈」), 否则显示称呼。\n版本快照只在本机留存; 需锁端生效的操作必须到场连接后另行执行，本 App 不排队。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder
    var toolsSection: some View {
        Section("工具") {
            Button { showBackup = true } label: { Label("备份与恢复", systemImage: "externaldrive") }
            // 2026-10-28 补：`GatewayView` 此前**只有搜索索引能到达** ——
            // `showGateway` 的唯一写点是 `s.gateway` 那条 SearchHit（SettingsView:251），
            // 设置列表里没有可见行。用户不搜「智能网关」就永远看不到配网/状态/重启三个能力。
            Button { showGateway = true } label: { Label("智能网关", systemImage: "antenna.radiowaves.left.and.right") }
            // 2026-10-29 布局整理：「分享给安卓」原先挂在「门锁」段（"这一把锁的凭证"）。
            // 但它实际做的是**跨平台数据交换**（把 ekey 编成二维码给安卓端扫），
            // 与「备份与恢复」「智能网关」同族，所以移到工具段。
            if let kc = app.current {
                Button { shareLock = kc } label: { Label("分享给安卓 (扫码开锁)", systemImage: "qrcode") }
            }
            // 2026-10-28 补：通知权限状态此前**无处可看**（`NotifyAuthBox` 零调用）。
            // 到期提醒是这个 App 唯一的主动提醒出口，权限关了却没人告诉用户，等于静默失效。
            if notifyOff {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Label("通知权限", systemImage: "bell.slash")
                        Spacer(minLength: 0)
                        Text(notifyLabel + " · 到期提醒不会送达")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.danger)
                    }
                }
            }
            // 2026-10-28 补入口：`TrialGuard.set(true)` 全仓零调用 —— 这道只读护栏
            // 永远打不开（`LockService` 里的 assertReadOnly 判据一直在，但没人能开）。
            // 而设置页搜索索引 :236 还写着「只读试验模式 (真机排障只看不改)」—— 搜得到、开不了。
            // 按 TrialGuardKit 的设计取舍放在「工具」这一段（低频/实验室入口）。
            Button {
                if TrialGuard.isOn {
                    TrialGuard.set(false)
                    app.showToast("只读试验模式已关闭")
                } else {
                    confirmDestructive("开启只读试验模式", TrialGuard.warning, confirmTitle: "开启") {
                        TrialGuard.set(true)
                        app.showToast("只读试验模式已开启：写入类操作全部停用")
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Label("只读试验模式", systemImage: "eye.slash")
                    Spacer(minLength: 0)
                    Text(TrialGuard.isOn ? "已开启" : "关闭")
                        .vkFont(.caption)
                        .foregroundStyle(TrialGuard.isOn ? DS.Palette.danger : DS.Palette.textSub)
                }
            }
        }
    }
    @ViewBuilder
    var applockSection: some View {
        // 2026-10-30 性能：`DB.hasPasscode()` / `DB.hasDuressCode()` 在本块里各被读 2 次，
        // 每次都是一份 SecureStore 查询。一次读出来，header/footer/按钮三处共用。
        let hasPasscode = DB.hasPasscode()
        let hasDuress = DB.hasDuressCode()
        return Section {
            if hasPasscode {
                Button { setPasscode() } label: {
                    Label("更改本机密码", systemImage: "lock.rotation")
                }
                Button { setDuressCode() } label: {
                    Label(hasDuress ? "更改胁迫码" : "设置胁迫码", systemImage: "exclamationmark.shield")
                }
                Button(role: .destructive) { disablePasscode() } label: {
                    Label("关闭本机密码", systemImage: "lock.slash")
                }
            } else {
                Button { setPasscode() } label: {
                    Label("设置本机密码", systemImage: "lock.fill")
                }
                note("4 位以上数字。设置后，**冷启动** App 需要输入它才能进入。")
            }
        } header: {
            Text("应用锁")
        } footer: {
            Text(hasDuress
                 ? "冷启动需输密码。胁迫码已设置：被胁迫时输入它会进入空壳模式 —— 门能开，但凭证与记录显示为空。"
                 : "冷启动需输密码。可另设一个胁迫码：被胁迫时输入它，App 进入空壳模式（门能开、数据看不见），不报警不暴露。")
        }
    }
    @ViewBuilder
    var aboutSection: some View {
        Section {
            // 机械计数器 (idea 1006): 累计开锁次数
            HStack(spacing: DS.Space.s) {
                Text("累计开锁").foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.m)
                MechCounter(value: Milestones.unlockTotal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累计开锁 \(Milestones.unlockTotal) 次")
            // 279 版本信息行: 原句列的"SQLite 版本"在本工程不存在 (库体是 UserDefaults + Keychain,
            // 见 §217 那条 ⛔ 不适用)，所以这里给的是**真实存在**的四项而不是照抄原句。
            HStack(spacing: DS.Space.s) {
                Text("构建与主题").foregroundStyle(DS.Palette.text)
                Spacer(minLength: DS.Space.m)
                // 2026-10-13 run 63: 原来把 infoDictionary 取值 + 三段拼接全内联进 Text, 报 type-check 超时。
                let buildVer = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
                let themeCount = DS.Palette.themeTable.count
                Text("build " + buildVer + " · " + String(themeCount) + " 套主题")   // 279 套主题
                    .vkFont(.footnote.monospacedDigit())
                    .foregroundStyle(DS.Palette.textSub)
            }
            .accessibilityElement(children: .combine)
            // 版本彩蛋 (idea 298): 连点 10 次展示构建信息
            Button {
                versionTaps += 1
                if versionTaps >= 10, !eggShown {
                    eggShown = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Text("当前版本").foregroundStyle(DS.Palette.text)
                    Spacer(minLength: DS.Space.m)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(DS.Palette.textSub)
                        .monospacedDigit()
                }
            }
            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
            if eggShown {
                LabeledRow("构建", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
                LabeledRow("遥测", "无 · 全程离线")
                // 2026-10-29：APK `page-testlockrom` / `page-romlist` 两页都被 `showTest=!1` 关着，
                // iOS 的 `LockService.probeEcho` 也零调用 —— 把两边合成一个隐藏诊断页，
                // 挂在同一个彩蛋下面（连点版本号 10 次），不占正常用户版面。
                NavigationLink { ProtocolTestView() } label: {
                Label("协议测试（回声探测 / 附近设备）", systemImage: "waveform.path.ecg")
            }
            }
        } footer: {
            Text(aboutFooterText)
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            // VoiceOver 致意 (idea 1049): 累计 30 天后一句静默致谢
        }
    }
}
