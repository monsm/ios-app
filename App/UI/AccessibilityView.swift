// ================= 设置-辅助功能 (包15) =================
// 五块: VoiceOver / 视觉适配 / 运动辅助 / 输入效率 / 听觉与认知。
// 851 VoiceOver 练习场: 本页内置 — 逐个控件演示 轻扫/双击/转子, 不触碰真实门锁指令。
// 降级备案: 869/875 自定滑杆 (无系统读取 API), 163 横屏锁定提示, 877 设备生物识别门控 — 见 docs/DEFERRED.md 包15 节。
import SwiftUI
import UIKit

struct AccessibilityView: View {
    @EnvironmentObject var app: AppState
    @State private var calcA = 0
    @State private var calcB = 5
    @State private var calcMode = "light"

    var body: some View { vkBody.destined(.accessibility) }
    var vkBody: some View {
        List {
            voSection
            visualSection
            motionSection
            assistiveTouchSection
            inputSection
            soundSection
            practiceSection
            DevFeatureAuditSection()
            DevGrayscaleSection()
            DevContrastSection(calcA: $calcA, calcB: $calcB, mode: $calcMode)
        }
        .navigationTitle("辅助功能")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .axBottomAnchor()
    }

    // ---------- VoiceOver (846-857) ----------
    private var voSection: some View {
        Section {
            Toggle("错误主动播报", isOn: Binding(   // 852 错误主动播报
                get: { DB.store.getBool("kf_vo_announce", true) },
                set: { app.setUnlockOption("kf_vo_announce", $0) }))
            // 852 播报试听: 立即演示一次主动朗读
            Button("试听播报效果") {
                // 2026-10-15 走查: `AXTools.announce` 第一行就是 `guard kf_vo_announce` —— 这一档关着的时候,
                // 这枚「试听」按下去什么都不发生也不说一句, 看着就是按钮坏了。试听的意义正是"先听听看要不要开",
                // 所以关掉时要如实说这一档是关的, 而不是替用户把它打开。
                guard DB.store.getBool("kf_vo_announce", true) else {
                    app.showToast("「主动播报」这一档现在是关的 · 打开后才能试听")
                    return
                }
                AXTools.announce("示例播报: 连接失败, 可能离门太远. 试试靠近门锁再试")
            }
            Text("播报仅在开启 VoiceOver 或系统「朗读」场景有感; 系统铃声静音不影响播报通道。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("VoiceOver 播报")
        } footer: {
            // 846/167 圆盘已支持转子上下滑
            // 850 圆盘已支持转子上下滑
            // 849 圆盘已支持转子上下滑
            // 856 圆盘已支持转子上下滑
            Text("圆盘已支持转子上下滑切换 状态/电量/连接 播报; 记录页时间线按自然语朗读 \"今天 14:02, 张三用指纹开了门\"; 凭证行按 名称-类型-状态 顺序朗读; 数值/状态控件走盲文简写。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 视觉适配 (858-867/226-227/878-883) ----------
    private var visualSection: some View {
        Section {
            // 858 App 内字号五档: 相对系统正文倍率, 与系统 Dynamic Type 叠加取大 (AccessibilityKit 注释)
            Picker("App 字号", selection: Binding(
                get: { DB.store.getString("kf_font_scale", "1.0") },
                set: { app.setUnlockOption("kf_font_scale", $0) })) {                Text("0.8x").tag("0.8")
                Text("标准").tag("1.0")
                Text("1.25x").tag("1.25")
                Text("1.5x").tag("1.5")
                Text("1.75x").tag("1.75")
            }
            .pickerStyle(.segmented)
            // 859 AX 档降级布局说明 (只写已实现的: 圆盘缩小; 原先还承诺"指标纵向堆叠", 代码未做, 已删)
            // 2026-10-15 走查: 这句把基准值写死成 176pt，而圆盘直径是 kf_dial_size **三档可调**
            // (160/176/200，默认 176；唯一读点是 `DS.Metric.dial`，被 `UnlockDial` 的
            // `AXFlags.axStackLayout ? 128 : DS.Metric.dial` 取用) —— 选了 200 的用户被界面告知
            // 一个他从来没见过的基础值。基准改从同一个源取，只有"缩到 128"那一侧是代码写死的常量。
            Text("字号 1.5x 起自动收紧: 开锁圆盘从 \(Int(DS.Metric.dial))pt 缩至 128pt, 大字号下仍能完成按住手势。")   // 859 字号
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 878 形状冗余三态: 全 App 状态已恒为 形状+图标+颜色 双通道, 此处演示
            HStack(spacing: DS.Space.s) {
                shapeChip(icon: "checkmark.circle.fill", tone: .ok, text: "成功")
                shapeChip(icon: "exclamationmark.triangle.fill", tone: .warn, text: "警告")
                shapeChip(icon: "xmark.octagon.fill", tone: .danger, text: "失败")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("形状冗余演示: 成功 对勾, 警告 叹号, 失败 叉, 除颜色外恒有形状加图标双通道")
            Toggle("大格模式 (快捷格 2 列大格)", isOn: Binding(
                get: { AXPrefs.bigTile },
                set: { app.setUnlockOption("kf_bigtile", $0) }))
            // 163 横屏重排 → 降级说明 (TARGETED_DEVICE_FAMILY=1 仅竖屏, 不做横屏布局, 备案 DEFERRED)。
            // 口径修正: 竖屏锁定下根本不会出现横屏场景, 旧文案"横屏自动提示"承诺了一个触发不了的机制。
            LabeledRow("横屏", "本项目锁定竖屏, 不会出现横屏场景; 横屏布局与横屏提示都不存在 (DEFERRED 备案)")   // 163 横屏
                .accessibilityLabel("横屏重排未做: 项目锁定竖屏, 没有横屏布局与提示, 见 DEFERRED 备案")
            // 857 音效说明 (声音策略统一走系统 systemSound, 静音开关天然生效)
            LabeledRow("音效与静音", "全部音效跟随系统铃声静音开关")   // 857 音效与静音
        } header: {
            Text("视觉与字号")
        } footer: {
            // 861 口径 (2026-10-13 更新): 此前全仓无一处读 legibilityWeight/isBoldTextEnabled, 如实写"未接线";
            // 现在根视图按 AXFlags.boldText 设 legibilityWeight, 这一条与上面四条一样是"无需开关即生效"。
            // 226 系统级适配无需开关即
            // 227 系统级适配无需开关即
            Text("系统级适配无需开关即生效: 增强对比映射 (分隔线/次文本加深一档、玻璃卡降实底)、智能反转保护 (hero 渐变降级幂等色)、降低透明度、减少动态效果、系统加粗跟随 (根视图按系统开关设 legibilityWeight, 凭证名与开关标签随之加粗)。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func shapeChip(icon: String, tone: ToneColor, text: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.xs, weight: .semibold))
                .foregroundStyle(tone.color)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.textSub)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .background(DS.Palette.surfaceAlt, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Palette.hairlineStrong, lineWidth: 0.5))
        .fixedSize()
    }

    // ---------- 874 辅助触控说明 (iOS AssistiveTouch 自定手势) ----------
    /// 874: 辅助触控的"自定手势"只能由用户在系统里录一次, App 无法代设 —— 所以这一节是**说明页**,
    /// 把"在哪一步选哪个动作"写全, 不假装一键接好 (原句要的正是说明页)。
    private static let assistiveSteps: [String] = [
        "设置 → 辅助功能 → 触控 → 辅助触控 → 打开",
        "自定顶层菜单 → 选一枚图标 → 动作选「快捷指令」→ 选本 App 的「打开门锁」",
        "以后点小白点 → 点那枚图标 → 确认后进 App 完成开锁 (仍在 App 内过应用锁与蓝牙)",
    ]
    private var assistiveTouchSection: some View {
        Section {
            Text("辅助触控 (小白点) 的自定手势需要你在系统里录一次, App 无法代设。映射开锁的步骤:")
                .font(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Self.assistiveSteps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: DS.Space.s) {
                    Text("\(i + 1)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.onAccent)
                        .frame(width: 18, height: 18)
                        .background(DS.Palette.accent, in: Circle())
                        .accessibilityHidden(true)
                    Text(s)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Hit.min)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("第 \(i + 1) 步: \(s)")
            }
            Text("更省事的替代: 直接用快捷指令口令「用离线锁管家打开门锁」, 或把 App 图标放进辅助触控的顶层菜单。")   // 166 更省事的替代
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("辅助触控映射")   // 874 辅助触控映射
        }
    }

    // ---------- 运动辅助 (868-877) ----------
    private var motionSection: some View {
        Section {
            // 872/229 消费方现状 (2026-10-13): 两个都已接线 ——
            // 872 在 PressableButtonStyle 的 300ms 去重闸里, 229 在 barSide/快捷格/HeroCard 三处。
            // 872 已接线 (2026-10-13): 去重闸落在 LockKeeperApp 的 PressableButtonStyle 里
            // (PrimitiveButtonStyle 外包一层 + 内层真 Button, 见那边的注释), 所以按原口径换回真开关。
            Toggle("防连点 (300ms 内重复点击忽略)", isOn: Binding(
                get: { AXPrefs.dbltapGuard },
                set: { DB.store.set("kf_dbltap_guard", $0) }))
            // 229 左手模式: 消费方三处 —— DeviceHomeView 的 barSide (工具条两侧对调)、快捷格顺序 reversed、
            // 以及 HeroCard 卡面本体 (DesignSystem 里按 AXPrefs.lefty 切 layoutDirection 镜像)，
            // 所以这一档是真开关。(2026-10-14: 删去"872 仍无消费方"半句 —— 与本节开头矛盾, 872 已接线。)
            Toggle("左手模式", isOn: Binding(   // 229 左手模式
                get: { AXPrefs.lefty },
                set: { app.setUnlockOption("kf_lefty", $0) }))
            Toggle("单手下沉", isOn: Binding(   // 873/60 单手下沉
                get: { AXPrefs.onehand },
                set: { app.setUnlockOption("kf_onehand", $0) }))
            // 875 ⚠ 按住时长自定滑杆 (系统"按住持续时间"无读取 API, 0.4–1.6s, 默认 0.9s 与包1 对齐)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.s) {
                    Text("按住时长")   // 875 按住时长
                    Spacer()
                    Text(String(format: "%.1f 秒", AXPrefs.holdDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSub)
                }
                Slider(value: Binding(
                    get: { AXPrefs.holdDuration },
                    set: { app.setUnlockOption("kf_ax_hold", String($0)) }),
                       in: 0.4...1.6, step: 0.1)
                    .accessibilityLabel("按住开锁时长")
                    .accessibilityValue(String(format: "%.1f 秒", AXPrefs.holdDuration))
            }
            .fixedSize(horizontal: false, vertical: true)
            // 869 ⚠ 眼动停留自定滑杆 (系统停留时长无公开 API, 0.5–4s, 默认 2s)。
            // 口径如实: 这个值的当前消费只有本页练习区的演示文字 —— 2026-10-15 走查修正过一次说法:
            // **868 的扫描组本身是挂了的** (设备页把 状态卡 / 圆盘 / 快捷格 各自成组, `children: .contain` + 组名标签),
            // 缺的是"App 侧按这枚停留时长驱动聚焦"的那一步 —— 真正逐项聚焦的节奏仍由系统 VoiceOver/切换控制自己的设置决定
            // (接线后此滑杆才成为行为源)。两处说法要与这段一致: `DeviceHomeView` 的 `unlockDial` 上方注释。
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.s) {
                    Text("扫描停留时长")   // 868/869 扫描停留时长
                    Spacer()
                    Text(String(format: "%.1f 秒", AXPrefs.dwellTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DS.Palette.textSub)
                }
                Slider(value: Binding(
                    get: { AXPrefs.dwellTime },
                    set: { app.setUnlockOption("kf_ax_dwell", String($0)) }),
                       in: 0.5...4.0, step: 0.1)
                    .accessibilityLabel("切换控制扫描停留时长")
                    .accessibilityValue(String(format: "%.1f 秒", AXPrefs.dwellTime))
                Text("当前只驱动下方练习区的演示文字; 系统逐项聚焦节奏请以 VoiceOver/切换控制设置为准。")   // 868 当前只驱动下方练习区
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            // 871 口径修正: 60pt 扩容只有时间线认领行一处 (RecordsView 内联), 不是"全 App";
            // 44pt 是 DS.Hit.min 全 App 下限 — 两句分开写，谁在骗人就一眼看得见。
            LabeledRow("命中域", "可点控件全 App 下限 44pt (DS.Hit.min); 时间线认领区另行加余量到 60pt")   // 871 命中域
            if AuthKit.biometricAvailable {
                // 877 ⚠ 验证降级大键: 设备支持 Face ID / Touch ID 时提供大字替代键路径 (AppLock 连败 3 次后自动出现)
                LabeledRow("验证降级大键", "Face ID / Touch ID 大字替代键已启用")   // 877 验证降级大键
                Button("体验: 大字生物识别验证") {   // 877 体验
                    AuthKit.verifyBiometric { app.showToast("生物识别验证通过 (演示)") }
                }
                .frame(minHeight: 56)
            } else {
                LabeledRow("验证降级大键", "设备无生物识别硬件, 暂不可用 (DEFERRED 备案)")   // 877 验证降级大键
            }
        } header: {
            Text("运动与操作")
        } footer: {
            // 2026-10-15 走查: 这句页脚原先有三个断言, 回源后**全部不成立**：
            //   ①「尚未把 状态卡/圆盘/快捷格 挂成独立扫描组」与 ②「设备页仅有占位注释」—— 设备页有 6 处
            //      `.accessibilityElement(children: .contain)`（判据: `grep -n 'accessibilityElement(children: .contain)' App/UI/DeviceHomeView.swift | grep -v ':[[:space:]]*//' | wc -l` ⇒ 6），其中 `开锁圆盘组`/`快捷操作格组`/`状态卡组` 三枚组名标签正是这三样；
            //   ③「accessibilityActionDiscovery 全仓零使用」—— 全仓该串的**唯一命中就是这句文案自己**
            //      (一条关于"没有"的陈述，靠自己成为那"一个")。API 名从用户可见文案里撤掉，真要说的事写实:
            //      App 没有"按这枚停留时长自动聚焦"的实现。判据: `grep -rn 'accessibilityLabel("开锁圆盘组")' App --include=*.swift` 有命中 = 已分组。
            Text("切换控制: 设备页已把 状态卡/圆盘/快捷格 各自成组, 外接开关可按组逐项聚焦; 聚焦节奏由系统自己的设置决定, App 没有按这枚停留时长自动聚焦的实现 —— 接线前这滑杆只喂下方练习区的文字. 降低透明度与减少动态直接生效, 无需开关. 眼动停留: 系统停留时长无公开 API, 已改成本机自定滑杆.")   // 868 页脚
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 输入效率 (164/530/854/870) ----------
    private var inputSection: some View {
        Section {
            Toggle("底部对齐表单 (键盘弹起表单贴底)", isOn: Binding(
                get: { AXPrefs.bottomForm },
                set: { app.setUnlockOption("kf_form_bottom", $0) }))
            Text("外接键盘快捷键 (按代码调用点列, 没接的不写): Cmd + 数字 1–4 切 Tab (App 入口); Cmd+R 刷新 (设备页/记录页); Cmd+F 凭证搜索; 本机密码弹层里 Return = 解锁. 全键盘 Tab/Shift-Tab 遍历由系统「全键盘控制」提供, 不是 App 自建.")   // 854 外接键盘快捷键
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("键盘与输入")
        }
    }

    // ---------- 听觉与认知 (876/881/882/885/231/232) ----------
    private var soundSection: some View {
        Section {
            Toggle("新条目双震", isOn: Binding(   // 876 新条目双震
                get: { AXPrefs.doubleHaptic },
                set: { app.setUnlockOption("kf_ax_doublehaptic", $0) }))
            // 同一处毛病: `newEntryHaptic` 第一行 guard `kf_ax_doublehaptic`, 关档时按下去零反馈。
            Button("试听双震") {
                guard AXPrefs.doubleHaptic else {
                    app.showToast("「新条目双震」这一档现在是关的 · 打开后才能试听")
                    return
                }
                AXTools.newEntryHaptic()
            }
            Toggle("字幕式过程条 (连接/开锁逐步文字)", isOn: Binding(
                get: { AXPrefs.captions },
                set: { app.setUnlockOption("kf_ax_captions", $0) }))
            Toggle("凭证大字模式 (OTP 大字号对照抄写)", isOn: Binding(
                get: { DB.store.getBool("kf_ax_bigotp") },
                set: { app.setUnlockOption("kf_ax_bigotp", $0) }))
            // 882 闪烁安全线
            // 231 闪烁安全线
            Text("闪烁安全线: 全 App 循环动效 ≤3Hz, 核查表见 docs/A11Y-FREQUENCY.md. 数值控件恒等宽数字. 设置页开关均为系统 Toggle (标题写明用途, 开/关态由系统播报, 不另写重复值); 图标型工具栏按钮逐枚挂无障碍名.")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("听觉与认知")
        }
    }

    // ---------- 851 VoiceOver 练习场 ----------
    private var practiceSection: some View {
        Section {
            VOPracticeField()
        } header: {
            Text("VoiceOver 练习场")   // 851 练习场
        } footer: {
            Text("用 轻扫聚焦 / 双击执行 / 转子上下滑 逐个体验下面三个演示控件, 安全不触发任何门锁指令.")
        }
    }
}

/// 851 练习场: 双击按钮 + 转子可调节 + 停留扫描演示, 全演示数据
struct VOPracticeField: View {
    @State private var taps = 0
    @State private var rotor = 0
    @State private var dwell = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Button("双击我 (当前 \(taps) 次)") {
                taps += 1
                DS.Haptics.tick.impactOccurred()
            }
            .accessibilityLabel("练习按钮, 双击执行")
            .accessibilityValue("\(taps) 次")
            .accessibilityHint("双击执行轻震动反馈")
            // @layout-allow 触达托管 Stepper: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Stepper(value: Binding(
                get: { rotor },
                set: { rotor = $0 % 3 }), in: 0...100) {
                Text("转子档: " + ["状态", "电量", "连接"][rotor])
                    .lineLimit(1)
            }
            .accessibilityLabel("练习转子")
            .accessibilityValue("当前 \( ["状态", "电量", "连接"][rotor] )")
            .accessibilityHint("转子上下滑或转子选择切换档位")
            // 2026-10-15 走查: 这句尾巴原先写「本 App 的扫描组还没接线」—— 假的。设备页确实把
            // 圆盘/快捷格/状态卡各自分了组 (`children: .contain` + 组名标签)，没接的只是"按这枚时长自动聚焦"那一步。
            // 判这半句真假要用: `grep -rn 'accessibilityLabel("开锁圆盘组")' App --include=*.swift` 有命中就是已分组。
            Text("练习区提示: 这里的「停留 \(String(format: "%.1f", AXPrefs.dwellTime)) 秒」是本 App 滑杆生成的演示文字 —— 逐项聚焦由系统 VoiceOver/切换控制执行, 节奏以系统设置为准; 本 App 只做了分组 (圆盘/快捷格/状态卡), 没有按这枚时长自动聚焦。")   // 868/869 练习区提示
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("练习区提示, 停留 \(String(format: "%.1f", AXPrefs.dwellTime)) 秒为演示文字, 实际节奏由系统决定")
        }
        .padding(.vertical, DS.Space.xs)
    }
}

// ---------- 开发自检区 (855/866/879/883) ----------
/// 855 焦点顺序巡检 + 866 极限字号自检 + 879 灰度预览
private struct DevFeatureAuditSection: View {
    var body: some View {
        Section {
            ForEach(Array(AXTools.focusReport.keys.enumerated()), id: \.offset) { _, page in
                Button("\(page)页焦点顺序巡检") { AXTools.runFocusAudit(page: page) }   // 855 页焦点顺序巡检
            }
        } header: {
            Text("焦点顺序巡检")   // 855 焦点顺序巡检
        } footer: {
            Text("打印并按 VoiceOver 顺序朗读当前页控件序列, 用于走查焦点是否成环、有无跳变.")
        }
    }
}

private struct DevGrayscaleSection: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Section {
            // 879 灰度预览自检: 全 App 去饱和渲染 (RootView 消费 AXFlags.grayPreview)
            // 879 灰度预览 / 866 极限字号: 写键 + 外观种子重建, 立即全局生效; 检查完关回
            Toggle("灰度预览", isOn: Binding(   // 879 灰度预览
                get: { AXFlags.grayPreview },
                set: { app.setUnlockOption("kf_ax_gray", $0) }))
            Toggle("极限字号自检 (以 200% 字号预览)", isOn: Binding(
                get: { AXFlags.bigPreview },
                set: { app.setUnlockOption("kf_ax_bigpreview", $0) }))
        } header: {
            Text("渲染自检 (开发向)")
        } footer: {
            Text("灰度预览与 200% 字号预览均为自测开关, 检查后请关回, 不留存.")
        }
    }
}

/// 883 对比度计算器: 选任意两令牌算 WCAG 比值 (与 tools/contrast.js 同款公式)
private struct DevContrastSection: View {
    @Binding var calcA: Int
    @Binding var calcB: Int
    @Binding var mode: String
    var body: some View {
        Section {
            HStack(spacing: DS.Space.s) {
                tokenPicker("前景", index: $calcA)
                tokenPicker("背景", index: $calcB)
                Picker("模式", selection: $mode) {
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
            }
            .frame(minHeight: DS.Hit.min)
            let ratio = AXTools.contrastRatio(hexOf(calcA), hexOf(calcB))
            LabeledRow("对比度", String(format: "%.2f:1 (正文需 ≥4.5)", ratio))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("对比度 \(String(format: "%.2f", ratio)), 正文需达到 4.5")
                .accessibilityValue(ratio >= 4.5 ? "达标" : "不达标")
            LabeledRow("盲文简写", AXTerms.br("\(mode == "light" ? "浅色" : "深色") \(ratio >= 4.5 ? "达标" : "不达标")"))   // 856 盲文简写
        } header: {
            Text("对比度计算器")   // 883 对比度计算器
        } footer: {
            Text("与 tools/contrast.js 同款 WCAG 2.1 公式, 用于任意两设计令牌的快速核算.")
        }
        // 883 全量清单: 文字 5 档 × 底色 3 档 = 15 对, 同公式同阈值
        Section {
            ForEach(0..<15, id: \.self) { i in
                let f = [4, 5, 6, 7, 8][i / 3]
                let b = [0, 1, 2][i % 3]
                let r = AXTools.contrastRatio(hexOf(f), hexOf(b))
                LabeledRow(AXTools.calcTokens[f].name + " / " + AXTools.calcTokens[b].name,
                           String(format: "%.2f:1", r) + (r >= 4.5 ? " 达标" : " 不达标"))
            }
        } header: {
            Text("全部对比值清单")   // 883 全部对比值清单
        } footer: {
            Text("当前模式 (\(mode == "light" ? "浅色" : "深色")) 实测; 正文级阈值 4.5:1.")
        }
    }
    private func tokenPicker(_ tag: String, index: Binding<Int>) -> some View {
        // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
        // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
        Picker(tag, selection: index) {
            ForEach(AXTools.calcTokens.indices, id: \.self) { i in
                Text(AXTools.calcTokens[i].name).tag(i)
            }
        }
        .pickerStyle(.menu)
    }
    private func hexOf(_ i: Int) -> UInt32 {
        let t = AXTools.calcTokens[i]
        return mode == "light" ? t.light : t.dark
    }
}

// ---------- 881 字幕式过程条: 连接/开锁 验证/执行/完成 三步文字字幕 ----------
struct CaptionStepBar: View {
    var phase: Int
    var unlockState: AppState.UnlockState

    var body: some View {
        // 非过程态不显示, 听障用户可逐字跟读"现在进行到哪一步"
        if unlockState == .connecting || unlockState == .opening || unlockState == .success {
            captionRow
        }
    }
    private var captionRow: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(0..<3, id: \.self) { i in
                captionStep(i)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(captionText)
    }
    @ViewBuilder
    private func captionStep(_ i: Int) -> some View {
        let done = (phase > i + 1) || unlockState == .success
        let active = phase == i + 1 && !done
        HStack(spacing: DS.Space.xs) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "ellipsis.circle" : "circle"))
                .font(.system(size: DS.Icon.xs, weight: .semibold))
            Text(captionName(i))
                .lineLimit(1)
        }
        .foregroundStyle(done ? DS.Palette.ok : (active ? DS.Palette.accentText : DS.Palette.textSub))
        .opacity(done || active ? 1 : 0.55)
        .accessibilityHidden(true)   // 组合朗读已含全部三步, 单步不重复
    }
    private func captionName(_ i: Int) -> String { ["验证", "执行", "完成"][i] }
    private var captionText: String {
        let done = phase > 0 ? "验证" : ""
        return "过程字幕: " + done + (phase > 1 ? " 执行, " : "") + (unlockState == .success ? " 完成" : (phase > 1 ? "执行中" : "进行中"))
    }
}
