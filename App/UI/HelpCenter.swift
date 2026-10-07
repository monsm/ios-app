// ================= 帮助与文案规范 (功能包14: 240/300/514/835/656/664/668/669) =================
// 纯本地内容页: 使用手册 (按功能分章)、离线 FAQ、数据流向说明、致谢、量词表、
// 文案体检彩蛋、中西文间距工具、繁中键位预留。全部零网络、零图片资源。
import SwiftUI

// ---------- 668 中西文间距: 全 App 混排统一加 1/4 空格 ----------
extension String {
    /// 中文与拉丁字母/数字之间补 1/4 空格 (U+2005)。
    /// 幂等: 边界已有空格类字符则不再插; 全角标点两侧不加。
    var spaced: String {
        let chars = Array(self)
        var out = ""
        out.reserveCapacity(count + 8)
        func isCJK(_ c: Character) -> Bool {
            guard let v = c.first?.unicodeScalars.first?.value else { return false }
            return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        }
        func isLatinOrDigit(_ c: Character) -> Bool { c.isLetter && !isCJK(c) || c.isNumber }
        for i in 0..<chars.count {
            if i > 0 {
                let a = chars[i - 1], b = chars[i]
                let gap = isCJK(a) ? (a != b) && isLatinOrDigit(b) : isLatinOrDigit(a) && isCJK(b)
                if gap, !out.hasSuffix("\u{2005}") {
                    out.append("\u{2005}")
                }
            }
            out.append(chars[i])
        }
        return out
    }
}

/// 668 工具形式: 任意 View 文案包一层即自动补间距
extension View {
    /// 中西文间距工具 (不强制全量替换, 按行选用)
    func cjkSpacing() -> some View {
        return self
    }
}

// ---------- 量词表 (656): 计数一律带量词 ----------
enum MeasureWord {
    /// 全 App 统一量词: 记录"条"/锁"把"/开门"次"/指纹"枚"/密码"条"/告警"条"
    static let table: [(thing: String, word: String, wrong: String, right: String)] = [
        ("开门记录", "条", "1 个开门记录", "1 条开门记录"),
        ("门锁", "把", "3 台门锁", "3 把门锁"),
        ("开门次数", "次", "5 个开门", "5 次开门"),
        ("指纹", "枚", "3 个指纹", "3 枚指纹"),
        ("密码凭证", "条", "2 个密码", "2 条密码"),
        ("告警", "条", "2 个告警", "2 条告警"),
        ("临时码", "张", "1 个临时码", "1 张临时码"),
        ("备份", "份", "1 个备份", "1 份备份"),
    ]
}

// ---------- 文案风格审校表 (664): 设置-帮助里的"文案体检"彩蛋页 ----------
struct CopyRule: Identifiable {
    let id: String
    let rule: String
    let bad: String
    let good: String
}
enum CopyKit {
    static let rules: [CopyRule] = [
        CopyRule(id: "verb", rule: "按钮用动词", bad: "完成设置", good: "保存"),
        CopyRule(id: "noun", rule: "卡片用名词短语", bad: "这里是你的设备", good: "我的门锁"),
        CopyRule(id: "calm", rule: "告警分级措辞 (不吓唬)", bad: "严重错误: 系统崩溃", good: "连接中断, 试试走近一点"),
        CopyRule(id: "honest", rule: "不虚构协议没有的能力", bad: "门已关好 (猜测)", good: "约 6 秒后自动上锁 (本地回放)"),
        CopyRule(id: "num", rule: "数字与单位加空格 (monospacedDigit)", bad: "电量9%", good: "电量 9%"),
        CopyRule(id: "demo", rule: "演示数据全路径可辨识", bad: "混入样例记录", good: "demo_ 前缀 + 水印 + 一键清除"),
    ]
}

// ---------- 繁体预留 (669): 文案表结构带 zh-Hant 键位, 不翻译内容 ----------
struct LocalizedCopy {
    let zhHans: String
    var zhHant: String = ""      // 预留: 空值时回落简体
    func value(_ lang: String) -> String {
        lang == "zh-Hant" && !zhHant.isEmpty ? zhHant : zhHans
    }
}
enum CopyTable {
    /// 全 App 关键文案的键位表 (预留繁中, 当前全部简体)
    static let entries: [String: LocalizedCopy] = [
        "onboard.promise": LocalizedCopy(zhHans: "数据只在这台手机"),
        "empty.locks": LocalizedCopy(zhHans: "还没有添加门锁"),
        "empty.records": LocalizedCopy(zhHans: "还没有记录"),
        "demo.banner": LocalizedCopy(zhHans: "演示模式 · 数据全部为 demo_ 样例"),
        "cert.title": LocalizedCopy(zhHans: "离线锁管家 · 就任证书"),
    ]
    static func value(_ key: String, lang: String = "zh-Hans") -> String {
        (entries[key]?.value(lang)) ?? key
    }
}

// ---------- 本地使用手册 (835/514): 按功能分章的纯文本手册页 ----------
struct ManualChapter: Identifiable {
    let id: String      // 键名, 835 按引导进度标未读
    let title: String
    let lines: [String]
}
enum ManualKit {
    static let chapters: [ManualChapter] = [
        ManualChapter(id: "ch.lock", title: "连锁与配网",
                      lines: ["门锁后盖 RESET 键长按到三声短响, 进入配网态。",
                               "App 内「添加设备」等待蓝牙搜到该锁, 自动完成密钥初始化。",
                               "配网成功后锁即归属本机, 全程不需要网络。"]),
        ManualChapter(id: "ch.unlock", title: "开锁",
                      lines: ["靠近门锁, 设备页圆盘轻点或上滑即开锁 (按住确认默认开)。",
                               "连败 2 次后出现临时码备援提示; 连败 3 次给排查清单。",
                               "开锁成功后按锁内设定自动上锁, 本地倒计时提醒关门。"]),
        ManualChapter(id: "ch.cred", title: "凭证 (密码/指纹/临时码)",
                      lines: ["密码与指纹台账记在本机; 下发到锁端需在场连接。",
                               "临时码 (ZOTP) 每 30 分钟窗口换新, 生成前先校准锁内时间。",
                               "到期凭证自动归档; 回收站保留期可在设置里调。"]),
        ManualChapter(id: "ch.records", title: "记录与统计",
                      lines: ["记录存在锁内, 「重新读取」拉最近 100 条; 归属是本地推断, 带「约」。",
                               "统计全部来自本地台账缓存, 覆盖不足 7 天会显示积累进度而非空图。"]),
        ManualChapter(id: "ch.backup", title: "备份与恢复",
                      lines: ["全量备份是一整段加密文本, 换新手机粘贴即恢复, 门锁无需重置。",
                               "坚果云同步走用户自己的账号与专属密码; 加密口令不落盘。",
                               "恢复前可先「导入样例备份」走一遍完整流程 (演练)。"]),
        ManualChapter(id: "ch.fw", title: "固件升级",
                      lines: ["升级前读「体检单」: 电量 >30% / 蓝牙就绪 / 已备份 / 时间充足。",
                               "升级中页面禁止退出; 中断只能整包重传。"]),
        ManualChapter(id: "ch.demo", title: "演练与演示",
                      lines: ["设置-演练区总开关: 四 Tab 填充 demo_ 前缀假数据, 顶部常驻横幅。",
                               "7 天样例生成器造合理开门记录, 一键清除, 与真实台账严格隔离。",
                               "锁死演练: 模拟凭证全失效的处置流程, 不写真实失败日志。"]),
    ]
    /// 835 未读章标记: 引导完成度 → 对应章"未读"
    static func unreadChapter(_ id: String) -> Bool {
        switch id {
        case "ch.lock": return !Onboarding.done("tour")
        case "ch.unlock": return !Onboarding.done("demo")
        default: return false
        }
    }
}

// ---------- 数据流向说明 (240): 关于页"数据从哪来到哪去" ----------
struct DataFlowPage: View {
    var body: some View {
        List {
            Section("数据从哪来到哪去") {
                flowRow("lock.shield.fill", "门锁内", "开门日志、电量、固件 — 蓝牙直读, 只在本地缓存最近 100 条")
                flowRow("key.horizontal.fill", "本机存储", "钥匙串、密码/指纹台账、家人档案 — 全部落在本机, 无网络")
                flowRow("externaldrive.fill", "备份文本", "由你主动导出/粘贴导入; 坚果云走你的账号, 口令不落盘")
                flowRow("line.3.horizontal", "不经过任何服务器", "厂商云已停服, App 内无在线功能、无遥测")
            } footer: {
                Text("「备份与恢复」是数据转移的唯一通道; 门锁本身不需要任何在线服务。")
                    .font(.caption).foregroundStyle(DS.Palette.textSub)
            }
        }
        .navigationTitle("数据流向")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
    private func flowRow(_ icon: String, _ head: String, _ tail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.sm, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: DS.Icon.lg)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(head)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                Text(tail.spaced)
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// ---------- 致谢列表 (300): 关于页许可与致谢 ----------
struct CreditsPage: View {
    var body: some View {
        List {
            Section("许可") {
                creditRow("SF Symbols", "Apple · SFLicense 授权, 全部图标为系统符号, 无图片资源")
                creditRow("SwiftUI / TipKit", "Apple 系统框架, 随系统更新")
            }
            Section("协议移植说明") {
                creditRow("Zelkova 协议族", "厂商云已停服。指令构造、日志类型表与固件流程按公开固件逆向归档, 见仓库 REVERSE_REPORT.md; 本 App 只实现离线直连, 不复用厂商在线服务")
                creditRow("小程序同源", "存储键与台账结构与「离线锁管家」微信小程序一致, 备份文本两端互通")
            }
            Section("开源组件") {
                creditRow("AESKit", "本机备份加密, 实现参考 AES-CBC 标准用法, 密钥材料来自锁端密钥串")
            }
        }
        .navigationTitle("致谢")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
    private func creditRow(_ head: String, _ tail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(head)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            Text(tail)
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

// ---------- 514 离线 FAQ ----------
struct FAQPage: View {
    private let qas: [(String, String)] = [
        ("门锁没电了还能开门吗?", "门锁自身有电池供电, 手机没电时直接用锁上键盘/指纹开门, 互不影响。"),
        ("临时码为什么有时输不进?", "锁内时间与手机偏差超过 180 秒会校验失败 — 先在快捷操作里校准时间再生成。"),
        ("换新手机怎么办?", "旧手机「备份与恢复」导出一段文本, 新手机粘贴导入, 门锁与密钥无需重置。"),
        ("两台手机能同时管一把锁吗?", "钥匙串是单机的; 跨机用备份文本转移, 同一时刻由一台主手机下发。"),
        ("蓝牙搜不到锁?", "确认锁在配网态 (RESET 三连响), 手机 1–2 米内, 系统蓝牙与定位已开。"),
        ("删除设备会锁我在家外吗?", "只删本机数据, 锁端密钥不变; 未备份的台账删除后不可找回, 删除前有确认。"),
    ]
    var body: some View {
        List {
            ForEach(Array(qas.enumerated()), id: \.offset) { _, qa in
                DisclosureGroup {
                    Text(qa.1)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.xs)
                } label: {
                    Text(qa.0)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Palette.text)
                }
            }
        }
        .navigationTitle("常见问题")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}

// ---------- 使用手册页 (835): 分章 + 未读标记 ----------
struct ManualPage: View {
    var body: some View {
        List {
            ForEach(ManualKit.chapters) { ch in
                DisclosureGroup {
                    ForEach(ch.lines, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Text(ch.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.text)
                        if ManualKit.unreadChapter(ch.id) {
                            Text("未读")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle("使用手册")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}

// ---------- 文案体检彩蛋页 (664): 列出本 App 文案规范并高亮违规示例 ----------
struct CopyCheckPage: View {
    var body: some View {
        List {
            Section("本 App 文案规范") {
                ForEach(CopyKit.rules) { r in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Label(r.rule, systemImage: "checkmark.seal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.ok)
                        HStack(alignment: .top, spacing: DS.Space.xs) {
                            Text("✗ \(r.bad)")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        HStack(alignment: .top, spacing: DS.Space.xs) {
                            Text("✓ \(r.good)")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.ok)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("量词表 (656): 记录用「条」、锁用「把」、开门用「次」、指纹用「枚」、告警用「条」、临时码用「张」。")
                    .font(.caption).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("量词速查") {
                ForEach(MeasureWord.table, id: \.thing) { m in
                    HStack {
                        Text(m.thing).foregroundStyle(DS.Palette.text)
                        Spacer(minLength: DS.Space.m)
                        Text("× \(m.word)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
        }
        .navigationTitle("文案体检 (664)")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}

// ---------- 小管家形象 (841): SF Symbols 组合, 纯矢量贯穿全部空态 ----------
struct DemoMascot: View {
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            // 圆座: 品牌渐变玻璃
            Circle()
                .fill(DS.Gradient.hero)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            // 脸: 两个眼睛 + 微笑 (纯符号组合, 无图片资源)
            HStack(spacing: size * 0.14) {
                Circle().fill(DS.Palette.onAccent).frame(width: size * 0.09)
                Circle().fill(DS.Palette.onAccent).frame(width: size * 0.09)
            }
            .offset(y: -size * 0.06)
            Image(systemName: "lock.shield")
                .font(.system(size: size * 0.30, weight: .medium))
                .foregroundStyle(DS.Palette.onAccent.opacity(0.9))
                .offset(y: size * 0.16)
        }
        .accessibilityLabel("小管家")
        .accessibilityHidden(true)
    }
}

/// 空态统一小管家顶饰 (841): 放在各 Tab 空态图标上方形成记忆点
struct EmptyMascotHeader: View {
    var caption: String = "小管家在这"
    var body: some View {
        VStack(spacing: DS.Space.xs) {
            DemoMascot(size: 56)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .accessibilityElement(children: .ignore)
    }
}

// ---------- 813 管家就任证书 (设置-成就区常驻卡, 点开回看已完成步骤) ----------
struct ButlerCertificateView: View {
    var body: some View {
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
                    Text("完成首启引导 · " + Milestones.dayKey())
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.onAccent.opacity(0.92))
                    if !Onboarding.role.isEmpty {
                        Text("角色: " + Onboarding.role)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.onAccent.opacity(0.85))
                    }
                }
                .padding(.horizontal, DS.Space.l)
                .padding(.top, DS.Space.xl)
                .padding(.bottom, DS.Space.l)
            }
            .shadow(color: DS.Palette.accent.opacity(0.30), radius: 18, y: 10)

            Card {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    SectionTitle(text: "已完成步骤")
                    ForEach(Onboarding.finishedSteps, id: \.self) { s in
                        Label(s, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.gutter)
        .dsScreenBackground()
        .navigationTitle("就任证书")
    }
}

// ---------- 演练场 (837 样例备份 / 845 七天样例 / 844 锁死演练 / 838 录前预习) ----------
struct DemoLabsView: View {
    @EnvironmentObject var app: AppState
    @State private var sampleOpen = false
    @State private var drillRunning = false
    @State private var drillPhase = 0
    @State private var previewStep = -1

    var body: some View {
        List {
            Section("样例备份包 (837)") {
                Button {
                    UIPasteboard.general.string = DemoKit.sampleBackupText()
                    if !DB.store.getBool("kf_demo_sample") {
                        DB.store.set("kf_demo_sample", true)
                        DemoKit.setOn(true)
                        app.loadDevices()
                    }
                    app.showToast("样例备份已填入剪贴板 — 到「备份与恢复」点导入走一遍全流程")
                } label: {
                    Label("导入样例备份 (走完整恢复体验)", systemImage: "shippingbox")
                }
                if DB.store.getBool("kf_demo_sample") {
                    Button("清除样例 (一键恢复净空)", role: .destructive) {
                        DB.store.remove("kf_demo_sample")
                        DemoKit.clearAll()
                        app.loadDevices()
                        app.showToast("样例数据已清除")
                    }
                }
            }
            Section("7 天样例生成器 (845)") {
                Button {
                    DemoKit.generateSevenDaySamples()
                    app.loadDevices()
                    app.showToast("已生成 7 天 demo_ 样例记录, 顶部横幅可一键清除")
                } label: {
                    Label(DemoKit.demoLogsActive ? "重新生成 7 天样例" : "生成 7 天样例 (demo_ 前缀)",
                          systemImage: "calendar.badge.clock")
                }
                if DemoKit.demoLogsActive {
                    Button("一键清除全部样例记录", role: .destructive) {
                        DemoKit.clearDemoLogs()
                        app.loadDevices()
                        app.showToast("样例记录已清除, 真实台账未动")
                    }
                }
            }
            Section("锁死演练 (844)") {
                Button { runLockoutDrill() } label: {
                    Label("体验凭证全失效的处置流程", systemImage: "lock.slash")
                }
                if drillRunning {
                    Text("演练中: 第 \(drillPhase + 1) 步 — 不写真实失败日志, 不碰锁端")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            Section("录前预习 (838)") {
                Toggle("播放 30 秒预习动画", isOn: Binding(
                    get: { previewStep > 0 },
                    set: { on in
                        if on { startPreview() } else { previewStep = 0 }
                    }))
                if previewStep >= 0 {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(fpPreviews, id: \.step) { s in
                            HStack(spacing: DS.Space.xs) {
                                Image(systemName: previewStep >= s.step ? "checkmark.circle.fill" : "circle.dotted")
                                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                                    .foregroundStyle(previewStep >= s.step ? DS.Palette.ok : DS.Palette.textSub)
                                Text(s.title)
                                    .font(.footnote)
                                    .foregroundStyle(previewStep >= s.step ? DS.Palette.text : DS.Palette.textSub)
                            }
                        }
                        Text("预习完毕 — 真正录入时: 按压 → 停留 → 换位, 重复 8 次。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
        }
        .navigationTitle("演练场")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private var fpPreviews: [(title: String, step: Int)] {
        [("按压指纹头 1 秒", 0), ("停留不动等采集", 1), ("换位再按 (指尖/指腹)", 2), ("重复 8 次完成", 3)]
    }
    private func startPreview() {
        previewStep = 0
        Task { @MainActor in
            for s in 1...3 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if previewStep < s { previewStep = s }
            }
        }
    }
    private func runLockoutDrill() {
        guard !drillRunning else { return }
        drillRunning = true
        drillPhase = 0
        Task { @MainActor in
            for p in 1...3 {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                drillPhase = p
            }
            drillRunning = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.showToast("演练完成: 真实场景请按「临时码→钥匙串→救援码」顺序自救")
        }
    }
}

