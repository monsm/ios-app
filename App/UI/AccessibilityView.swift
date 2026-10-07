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

    var body: some View {
        List {
            voSection
            visualSection
            motionSection
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
            Toggle("错误主动播报 (852)", isOn: Binding(
                get: { DB.store.getBool("kf_vo_announce", true) },
                set: { app.setUnlockOption("kf_vo_announce", $0) }))
            // 852 播报试听: 立即演示一次主动朗读
            Button("试听播报效果") {
                AXTools.announce("示例播报: 连接失败, 可能离门太远. 试试靠近门锁再试")
            }
            Text("播报仅在开启 VoiceOver 或系统「朗读」场景有感; 系统铃声静音不影响播报通道。")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("VoiceOver 播报")
        } footer: {
            Text("圆盘已支持转子上下滑切换 状态/电量/连接 播报 (846/167); 记录页时间线按自然语朗读 \"今天 14:02, 张三用指纹开了门\" (850); 凭证行按 名称-类型-状态 顺序朗读 (849); 数值/状态控件走盲文简写 (856)。")
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
            // 859 AX 档降级布局说明 (字号 ≥1.5 自动收紧, 无需开关)
            Text("字号 1.5x 起自动启用辅助布局: 卡片指标纵向堆叠、圆盘缩至 128pt (859)。")
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
            Toggle("大格模式 (230, 快捷格 2 列大格)", isOn: Binding(
                get: { AXPrefs.bigTile },
                set: { app.setUnlockOption("kf_bigtile", $0) }))
            // 163 横屏重排 → 降级说明 (TARGETED_DEVICE_FAMILY=1 仅竖屏, 不做横屏布局, 备案 DEFERRED)
            LabeledRow("横屏 (163)", "本项目锁定竖屏; 横屏自动提示并保持原布局")
                .accessibilityLabel("横屏重排已降级: 项目锁定竖屏, 不做横屏布局, 见 DEFERRED 备案")
            // 857 音效说明 (声音策略统一走系统 systemSound, 静音开关天然生效)
            LabeledRow("音效与静音 (857)", "全部音效跟随系统铃声静音开关")
        } header: {
            Text("视觉与字号")
        } footer: {
            Text("系统级适配无需开关即生效: 增强对比映射 (862, 分隔线/次文本加深一档)、智能反转保护 (863, hero 渐变降级幂等色)、降低透明度 (226, 玻璃降级实底)、减少动态效果 (227, 循环动效静止)、系统加粗跟随 (861)。")
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

    // ---------- 运动辅助 (868-877) ----------
    private var motionSection: some View {
        Section {
            Toggle("防连点开关 (872, 300ms 内忽略重复点击)", isOn: Binding(
                get: { AXPrefs.dbltapGuard },
                set: { app.setUnlockOption("kf_dbltap_guard", $0) }))
            Toggle("单手下沉 (873/60, 圆盘下移入拇指区)", isOn: Binding(
                get: { AXPrefs.onehand },
                set: { app.setUnlockOption("kf_onehand", $0) }))
            Toggle("左手模式 (229, 工具栏镜像)", isOn: Binding(
                get: { AXPrefs.lefty },
                set: { app.setUnlockOption("kf_lefty", $0) }))
            // 875 ⚠ 按住时长自定滑杆 (系统"按住持续时间"无读取 API, 0.4–1.6s, 默认 0.9s 与包1 对齐)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("按住时长 (875)")
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
            // 869 ⚠ 眼动停留自定滑杆 (系统停留时长无公开 API, 0.5–4s, 默认 2s, 扫描组聚焦停留基准)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack {
                    Text("扫描停留时长 (868/869)")
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
            }
            .fixedSize(horizontal: false, vertical: true)
            LabeledRow("命中域 (871)", "全 App 44pt + 10pt 余量; 时间线次级按钮 60pt")
            if AuthKit.biometricAvailable {
                // 877 ⚠ 验证降级大键: 设备支持 Face ID / Touch ID 时提供大字替代键路径 (AppLock 连败 3 次后自动出现)
                LabeledRow("验证降级大键 (877)", "Face ID / Touch ID 大字替代键已启用")
                Button("体验: 大字生物识别验证 (877)") {
                    AuthKit.verifyBiometric { app.showToast("生物识别验证通过 (演示)") }
                }
                .frame(minHeight: 56)
            } else {
                LabeledRow("验证降级大键 (877)", "设备无生物识别硬件, 暂不可用 (DEFERRED 备案)")
            }
        } header: {
            Text("运动与操作")
        } footer: {
            Text("868 切换控制: 设备 Tab 的 状态卡/圆盘/快捷格 为三个扫描组 (accessibilityActionDiscovery), 停留时长按上方滑杆. 226 降低透明度与 227 减少动态直接生效, 无需开关. 869 眼动停留: 系统停留时长无公开 API, 已改自定滑杆 (备案 DEFERRED).")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 输入效率 (164/530/854/870) ----------
    private var inputSection: some View {
        Section {
            Toggle("底部对齐表单 (870, 键盘弹起表单贴底)", isOn: Binding(
                get: { AXPrefs.bottomForm },
                set: { app.setUnlockOption("kf_form_bottom", $0) }))
            Text("外接键盘快捷键 (164/530): Cmd/Control + 数字 1–4 切 Tab; Cmd+R 刷新; Cmd+N 新建; Cmd+F 凭证搜索; Esc 关闭弹层. Tab/Shift-Tab 全键盘遍历 (854).")
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
            Toggle("新条目双震 (876, 帮助听障用户确认)", isOn: Binding(
                get: { AXPrefs.doubleHaptic },
                set: { app.setUnlockOption("kf_ax_doublehaptic", $0) }))
            Button("试听双震") { AXTools.newEntryHaptic() }
            Toggle("字幕式过程条 (881, 连接/开锁逐步文字)", isOn: Binding(
                get: { AXPrefs.captions },
                set: { app.setUnlockOption("kf_ax_captions", $0) }))
            Toggle("凭证大字模式 (885, OTP 大字号对照抄写)", isOn: Binding(
                get: { DB.store.getBool("kf_ax_bigotp") },
                set: { app.setUnlockOption("kf_ax_bigotp", $0) }))
            Text("闪烁安全线 (882): 全 App 循环动效 ≤3Hz, 核查表见 docs/A11Y-FREQUENCY.md. 数值控件恒等宽数字 (231). 工具栏按钮已全量补无障碍名 (232).")
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
            Text("VoiceOver 练习场 (851)")
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
            Stepper(value: Binding(
                get: { rotor },
                set: { rotor = $0 % 3 }), in: 0...100) {
                Text("转子档: " + ["状态", "电量", "连接"][rotor])
                    .lineLimit(1)
            }
            .accessibilityLabel("练习转子")
            .accessibilityValue("当前 \( ["状态", "电量", "连接"][rotor] )")
            .accessibilityHint("转子上下滑或转子选择切换档位")
            Text("扫描组演示: 停留 \(String(format: "%.1f", AXPrefs.dwellTime)) 秒自动跳到下一个控件 (868)")
                .font(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("扫描组演示, 停留 \(String(format: "%.1f", AXPrefs.dwellTime)) 秒")
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
                Button("\(page)页焦点顺序巡检 (855)") { AXTools.runFocusAudit(page: page) }
            }
        } header: {
            Text("焦点顺序巡检 (855, 开发向)")
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
            Toggle("灰度预览 (879, 检查渐变主题无色可读性)", isOn: Binding(
                get: { AXFlags.grayPreview },
                set: { app.setUnlockOption("kf_ax_gray", $0) }))
            Toggle("极限字号自检 (866, 以 200% 字号预览)", isOn: Binding(
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
            LabeledRow("盲文简写 (856)", AXTerms.br("\(mode == "light" ? "浅色" : "深色") \(ratio >= 4.5 ? "达标" : "不达标")"))
        } header: {
            Text("对比度计算器 (883)")
        } footer: {
            Text("与 tools/contrast.js 同款 WCAG 2.1 公式, 用于任意两设计令牌的快速核算.")
        }
    }
    private func tokenPicker(_ tag: String, index: Binding<Int>) -> some View {
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
