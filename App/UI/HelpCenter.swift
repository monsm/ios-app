// ================= 帮助与文案规范 (功能包14: 240/300/514/835/656/664/668/669) =================
// 纯本地内容页: 使用手册 (按功能分章)、离线 FAQ、数据流向说明、致谢、量词表、
// 文案体检彩蛋、繁中键位预留。全部零网络、零图片资源。 (668 中西文间距工具已删, 见下方说明)
import SwiftUI
import Foundation

// ---------- 668 中西文间距 (排版实现见下方 cjkSpaced) ----------

// 668 中西文间距 —— 改走排版 (kerning) 路线。
// 原先此处是 `func cjkSpacing() -> some View { return self }`：名字承诺"包一层即补间距"，实现原样返回，
// 谁调都是假生效（全库零调用），已删。同文件的 `String.spaced` 走的是**插 U+2005 字符**的路子，
// 且只有一个调用点：插入不可见字符会让复制、导出、搜索命中都拿到脏文本（拿数据换观感），一并换掉。
private func isCJK668(_ c: Character) -> Bool {
    guard let v = c.unicodeScalars.first?.value else { return false }
    let u = UInt32(v)
    return (0x3000...0x303F).contains(u) || (0x3400...0x4DBF).contains(u)
        || (0x4E00...0x9FFF).contains(u) || (0xF900...0xFAFF).contains(u) || (0xFF00...0xFF60).contains(u)
}
private func isLatin668(_ c: Character) -> Bool {
    (c.isLetter && !isCJK668(c)) || c.isNumber
}

/// 汉字与紧邻拉丁/数字之间加字距：只在边界字符上加 kerning，段内不跟着被拉开，且不插入任何字符。
/// 用于以"中文 + 英文缩写/数字"混排为主的短标签（LabeledRow 一类）；长段落不必用（成本按字符数线性增长）。
func cjkSpaced(_ s: String, gap: CGFloat = 0.09) -> Text {
    let chars = Array(s)
    var hasBoundary = false
    if chars.count > 1 {
        for i in 0..<(chars.count - 1) {
            let a = chars[i], b = chars[i + 1]
            if (isCJK668(a) && isLatin668(b)) || (isLatin668(a) && isCJK668(b)) { hasBoundary = true; break }
        }
    }
    guard hasBoundary else { return Text(s) }        // 纯中文/纯拉丁 → 零成本快路
    var out = Text("")
    for i in chars.indices {
        let c = chars[i]
        var k: CGFloat = 0
        if i + 1 < chars.count {
            let b = chars[i + 1]
            if (isCJK668(c) && isLatin668(b)) || (isLatin668(c) && isCJK668(b)) { k = gap }
        }
        out = out + Text(String(c)).kerning(k)
    }
    return out
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
        ManualChapter(id: "ch.family", title: "给家人开门禁（四步）",
                      lines: ["第一步 建档：「成员中心」里加称呼与关系，需要就选角色。",   // 458/843 第一步
                              "第二步 给凭证：在 Ta 名下录指纹或密码，到场连接后下发到锁。",   // 177/306 第二步
                              "第三步 限时段：给这条密码设生效与到期；给访客用临时码，到点自动作废。",   // 520/806 第三步
                              "第四步 收回：停用凭证或把人归档；锁端的删除要连接执行，本机台账同步标记。",   // 353/460 第四步
                              "关于手表：本 App 没有 watch target，Apple Watch 也替不了这把锁开门 (协议与工程里都没有那条路)。"
                               + "创意原文那句「给家人配手表」在这里做不到，这一章给的是四步做得完的。"]),   // 973 创意原文那句
        ManualChapter(id: "ch.records", title: "记录与统计",
                      lines: ["记录存在锁内, 「重新读取」拉最近 100 条; 归属是本地推断, 带「约」。",
                               "统计全部来自本地台账缓存, 覆盖不足 7 天会显示积累进度而非空图。"]),
        ManualChapter(id: "ch.backup", title: "备份与恢复",
                      lines: ["全量备份是一整段加密文本, 换新手机粘贴即恢复, 门锁无需重置。",
                               "坚果云同步走用户自己的账号与专属密码; 加密口令不落盘。",
                               "演练入口: 「设置-演练场」的导入样例备份会真走恢复管线 (含自动还原点), 样例可一键清除。"]),   // 837 演练入口
        // 286 替代: 原句是"锁详情页解释广播间隔档位与省电关系, 协议可读则回显当前值" ——
        // 协议 §1/§2 没有读取广播参数的字段, 所以"回显当前值"这句承诺撤掉, 只留静态科普,
        // 落点从锁详情页挪到帮助手册 (与 744 同一条落法: 讲原理的地方是静态页, 不是读数页)。
        ManualChapter(id: "ch.radio", title: "蓝牙广播与省电",   // 286 蓝牙广播与省电
                      lines: ["门锁靠定时广播让手机「看得见」它; 广播间隔越长越省电, 但从进页到连上要多等一会儿。",
                              "档位由锁本身 (出厂/固件) 定, 协议没有读取广播参数的字段 —— 这里只讲原理, 不显示「当前档位」。",
                              "要改档位按随锁说明书或厂商工具走; 本 App 不猜, 也不回显一个读不到的读数。"]),
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
            Section {
                flowRow("lock.shield.fill", "门锁内", "开门日志、电量、固件 — 蓝牙直读, 只在本地缓存最近 100 条")
                flowRow("key.horizontal.fill", "本机存储", "钥匙串、密码/指纹台账、家人档案 — 全部落在本机, 无网络")
                flowRow("externaldrive.fill", "备份文本", "由你主动导出/粘贴导入; 坚果云走你的账号, 口令不落盘")
                flowRow("line.3.horizontal", "不经过任何服务器", "厂商云已停服, App 无在线功能、无遥测 — 唯一会联网的是你主动配置的 WebDAV 备份")
            } header: {
                Text("数据从哪来到哪去")
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
                cjkSpaced(tail)
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
        // 删掉"与定位已开": iOS 上 BLE 扫描不需要定位授权 (那是 Android 的规则)，把定位写成搜到锁的前提，
        // 会让用户去翻一个跟故障无关的开关 (与首启权限页同一处错话，同批改掉)。
        ("蓝牙搜不到锁?", "确认锁在配网态 (RESET 三连响), 手机 1–2 米内, 系统蓝牙已开。"),
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

// ---------- 282 症状向导 (走 SymptomGuide 判断树, 纯本地、零网络) ----------
// 此前 SymptomGuide 三棵树写完就没人调用: 判断树本身没问题, 缺的是走树的界面。
struct SymptomGuideView: View {
    /// 829: 从失败横幅直达某一棵树; 缺省 nil = 先让用户选类别。
    /// @State 只在首次出现时取初值, 所以注入必须走 `_treeKey` —— 直接赋值那行会被忽略。
    init(initial: String? = nil) {
        _treeKey = State(initialValue: initial)
    }
    @State private var treeKey: String?
    @State private var node = "q1"
    @State private var trail: [String] = []

    // 用 struct 而不是标签元组: 单参 ForEach 要求元素 Identifiable, 元组不能遵循协议
    private struct Tree: Identifiable {
        let id: String
        let title: String
        let sub: String
        let steps: [String: SymptomGuide.Step]
    }
    private static let trees: [Tree] = [
        Tree(id: "lockOpen", title: "开不了锁", sub: "蓝牙开着, 门锁没反应", steps: SymptomGuide.lockOpen),
        Tree(id: "bleConnect", title: "连不上或总断", sub: "搜不到、配对失败、反复超时", steps: SymptomGuide.bleConnect),
        Tree(id: "records", title: "记录读不到", sub: "明明开了门, 记录页是空的", steps: SymptomGuide.records)
    ]

    private var steps: [String: SymptomGuide.Step]? {
        guard let k = treeKey else { return nil }
        return Self.trees.first { $0.id == k }?.steps
    }
    private var current: SymptomGuide.Step? { steps?[node] }

    private func answer(_ yes: Bool) {
        guard let step = current else { return }
        let nexts = yes ? step.yesNext : step.noNext
        // 分支指向空 = 树没写完; 停在当前问题而不是跳到一个凭空的节点
        guard let nxt = nexts.first else { return }
        trail.append(step.question + " → " + (yes ? "是" : "否"))
        node = nxt
    }

    var body: some View {
        List {
            if treeKey == nil {
                Section("你遇到的是哪一类?") {   // 282 你遇到的是哪一类
                    ForEach(Self.trees) { t in
                        Button {
                            treeKey = t.id; node = "q1"; trail = []
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(t.title).font(.subheadline.weight(.medium)).foregroundStyle(DS.Palette.text)
                                Text(t.sub).font(.caption).foregroundStyle(DS.Palette.textSub)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(t.title), \(t.sub)")
                    }
                }
                Section {
                    Text("全程只在本机做问答, 不联网、不读你的门锁数据。结论只给下一步动作, 不给诊断书。")
                        .font(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let step = current {
                if let concl = step.conclusion {
                    Section("结论") {
                        Text(concl)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if !trail.isEmpty {
                            ForEach(Array(trail.enumerated()), id: \.offset) { _, t in
                                Text(t).font(.caption).foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Section {
                        Button("重来一遍") { node = "q1"; trail = [] }
                            .font(.subheadline).foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .leading)
                        Button("换一类问题") { treeKey = nil; node = "q1"; trail = [] }
                            .font(.subheadline).foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .leading)
                    }
                } else {
                    Section("第 \(trail.count + 1) 问") {
                        Text(step.question)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, DS.Space.xxs)
                        HStack(spacing: DS.Space.m) {
                            Button("是") { answer(true) }
                                .buttonStyle(PrimaryActionStyle())
                            Button("否") { answer(false) }
                                .buttonStyle(.bordered)
                        }
                    }
                    if !trail.isEmpty {
                        Section("已经答过") {
                            ForEach(Array(trail.enumerated()), id: \.offset) { _, t in
                                Text(t).font(.caption).foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Section {
                        Button("重头开始") { node = "q1"; trail = [] }
                            .font(.caption).foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .leading)
                    }
                }
            } else {
                // 走到这里只可能是树里的 id 拼错 (代码问题, 不是用户问题), 如实说明而不是白屏
                Section("这一步在判断树里找不到") {
                    Text("节点 \(node) 不在树内 —— 属内置内容缺陷, 可先「换一类问题」绕开。")
                        .font(.caption).foregroundStyle(DS.Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("换一类问题") { treeKey = nil; node = "q1"; trail = [] }
                        .font(.subheadline).foregroundStyle(DS.Palette.accentText)
                        .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .leading)
                }
            }
        }
        .navigationTitle("按症状排查")
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
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, DS.Space.xxs)
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
            Section {
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
            } header: {
                Text("本 App 文案规范")
            } footer: {
                Text("量词表: 记录用「条」、锁用「把」、开门用「次」、指纹用「枚」、告警用「条」、临时码用「张」。")   // 656 量词表
                    .font(.caption).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("量词速查") {
                ForEach(MeasureWord.table, id: \.thing) { m in
                    HStack(spacing: DS.Space.s) {
                        Text(m.thing).foregroundStyle(DS.Palette.text)
                        Spacer(minLength: DS.Space.m)
                        Text("× \(m.word)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
            Section {
                Text("本页只列规范, 不自动改文案; 违规示例是给人看的对照, 不是扫描结果。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 669: CopyTable/LocalizedCopy 此前零调用 —— 键位表写完没地方看。
            // 如实标注"未翻译", 不假称支持繁中 (结构预留 ≠ 功能已就绪)。
            Section("关键文案键位 · \(CopyTable.entries.count) 条") {   // 669 关键文案键位
                ForEach(CopyTable.entries.keys.sorted(), id: \.self) { k in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(k).font(.caption.monospaced()).foregroundStyle(DS.Palette.accentText)
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Text(CopyTable.value(k))
                                .font(.subheadline).foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.Space.s)
                            Text((CopyTable.entries[k]?.zhHant.isEmpty ?? true) ? "简" : "繁")
                                .font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("「简」= 该键位只有简体值, 取繁中时按 LocalizedCopy 回落到简体。这一版没有翻译内容, 只保证将来加译不动结构。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("文案体检")   // 664 文案体检
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
                .fill(DS.heroGradientSafe)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(DS.heroFg.opacity(0.25), lineWidth: 1))
            // 脸: 两个眼睛 + 微笑 (纯符号组合, 无图片资源)
            HStack(spacing: size * 0.14) {
                Circle().fill(DS.heroFg).frame(width: size * 0.09)
                Circle().fill(DS.heroFg).frame(width: size * 0.09)
            }
            .offset(y: -size * 0.06)
            Image(systemName: "lock.shield")
                .font(.system(size: size * 0.30, weight: .medium))
                .foregroundStyle(DS.heroFg.opacity(0.9))
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
                    .fill(DS.heroGradientSafe)
                VStack(spacing: DS.Space.s) {
                    Image(systemName: "rosette")
                        .font(.system(size: DS.Icon.xl, weight: .medium))
                        .foregroundStyle(DS.heroFg)
                        .padding(.top, DS.Space.xl)
                    Text("离线锁管家 · 就任证书")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DS.heroFg)
                    Text("完成首启引导 · " + Milestones.dayKey())
                        .font(.footnote)
                        .foregroundStyle(DS.heroFg.opacity(0.92))
                    if !Onboarding.role.isEmpty {
                        Text("角色: " + Onboarding.role)
                            .font(.caption)
                            .foregroundStyle(DS.heroFg.opacity(0.85))
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
    @State private var drillCool = 0    // 844 冷却倒计时剩余秒 (演练演示值, 不碰锁端)
    @State private var previewStep = -1
    @State private var previewTask: Task<Void, Never>? = nil   // 838: 30 秒预习的可取消句柄 (关掉开关要真停)

    var body: some View {
        List {
            Section("样例备份包") {   // 837 样例备份包
                // 837 原句 = "导入样例备份**走完整恢复流程**, 完毕一键清除"。
                // 旧按钮把文本塞进剪贴板就宣称"走完整恢复体验" —— 恢复一步没跑, 是假文案。
                // 现在真走 BackupStudio 同一条管线: 解码 (453 文件头) → 424 升级链 →
                // 421 自动还原点 → 418 合并策略入库 → markImported。导入的是 demo_ 样例锁,
                // 「清除样例」一键净身; 顺手开演示模式, 让常驻横幅如实亮出"这是样例"。
                Button {
                    runSampleRestore()
                } label: {
                    Label("导入样例备份 (真走恢复管线)", systemImage: "shippingbox")
                }
                Text("与真实备份同一条恢复路径 (含 421 自动还原点); 样例全部 demo_ 前缀, 一键清除后净空。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 剪贴板路线保留为**次选**, 并如实命名 —— 它确实只填剪贴板, 不跑恢复
                Button {
                    UIPasteboard.general.string = DemoKit.sampleBackupText()
                    app.showToast("样例备份文本已填入剪贴板 — 到「备份与恢复」粘贴导入")
                } label: {
                    Label("复制样例备份文本到剪贴板 (不自动导入)", systemImage: "doc.on.doc")
                }
                if DB.store.getBool("kf_demo_sample") {
                    Button("清除样例 (一键恢复净空)", role: .destructive) {
                        DB.store.remove("kf_demo_sample")
                        // 确认口径：一键净空只清 demo_ 前缀的样例数据 (DemoKit.clearAll = demoMac 那把假锁 + demo 成员 +
                        //   demo_ 日志)，真锁真记录一律不碰；原句 845 要的正是「一键」，再套一层确认会把教程入口问成拦路。
                        DemoKit.clearAll()
                        app.loadDevices()
                        app.showToast("样例数据已清除")
                    }
                }
            }
            Section("7 天样例生成器") {   // 845 天样例生成器
                // demoLogsCount 此前零调用: 生成完只报"已生成", 看不到当前到底躺着几条
                LabeledRow("当前样例条数", "\(DemoKit.demoLogsCount()) 条 · 只算 demo_ 前缀")   // 845 当前样例条数
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
            Section("锁死演练") {   // 844 锁死演练
                Button { runLockoutDrill() } label: {
                    Label("体验凭证全失效的处置流程", systemImage: "lock.slash")
                }
                if drillRunning {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("演练中: 第 \(min(drillPhase + 1, 3)) 步 (共 3 步) — 不写真实失败日志, 不碰锁端")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        if drillCool > 0 {
                            // 844: 冷却倒计时界面 — 与锁屏页 389 同款读秒文案 (演示压缩为 12 秒)
                            Label("冷却中, \(drillCool) 秒后可再试", systemImage: "hourglass")
                                .font(.footnote.weight(.medium).monospacedDigit())
                                .foregroundStyle(DS.Palette.danger)
                        } else if drillPhase >= 3 {
                            Text("冷却结束 — 真实场景请按「临时码→钥匙串→救援码」顺序自救。")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.accentText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
            Section("录前预习") {   // 838 录前预习
                // 838 原句 = "30 秒分步预习动画, 高亮三阶段后再开始"。旧实现各档 3 秒 (共 9 秒)
                // 且预习完没有进真正录入的出口 —— 现在每档 10 秒 (共 30 秒), 走完出现"开始真正录入"。
                // 并写明它只点亮清单, 不碰指纹硬件、不搬任何数据。
                Toggle("三档节奏预习 (每档 10 秒, 共约 30 秒)", isOn: Binding(
                    get: { previewStep > 0 },
                    set: { on in
                        if on { startPreview() } else { previewTask?.cancel(); previewStep = 0 }
                    }))
                Text("预习只点亮下面这张节奏清单 —— 不触碰指纹硬件, 不写入任何凭证数据。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
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
                        // 838: "预习后再开始" — 走完 30 秒给真入口 (与凭证页同一录入页)
                        if previewStep >= 3 {
                            NavigationLink { StartAddFpView(embedded: true) } label: {
                                Label("按这个节奏开始真正录入", systemImage: "touchid")
                                    .font(.footnote.weight(.medium))
                            }
                        }
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
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            for s in 1...3 {
                // 838: 每档 10 秒 (共 30 秒); 取消即停, 关掉开关不诈尸
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                if previewStep < s { previewStep = s }
            }
        }
    }
    /// 837 样例备份包 = 真走恢复管线 (旧版只填剪贴板却宣称"走完整恢复体验", 已改实话):
    /// 解码 → 424 升级链 → restore (内含 421 自动还原点 + 418 合并策略) → 打横幅旗标 → 重载设备。
    /// 样例 bundle 由本机 DemoKit 现生成, 无口令、无远端, 失败面只剩"编码/解码不成"一种, 兜底回剪贴板。
    private func runSampleRestore() {
        let text = DemoKit.sampleBackupText()
        guard !text.isEmpty,
              let raw = try? JSONDecoder().decode(BackupBundle.self, from: Data(text.utf8)) else {
            UIPasteboard.general.string = text
            app.showToast("样例文本解码失败 — 已改填入剪贴板, 可到「备份与恢复」手动导入")   // 453 样例文本解码失败
            return
        }
        let b = BackupStudio.upgradeChain(raw)
        let r = BackupStudio.restore(b, strategy: .merge, zones: BZones())
        // 横幅纪律 (836): 样例上屏必须让"这是演示数据"全程可见 — 开演示模式旗标, 顶部横幅随之常驻
        DB.store.set("kf_demo_sample", true)
        DemoKit.setOn(true)
        DemoKit.beginDrillBackup()   // 842: 样例恢复走完就是"演练备份"状态 —— 设置页由此给出「转正式备份」出口
        BackupStudio.markImported()
        app.loadDevices()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        app.showToast("样例恢复走完: 新增 \(r.imported) · 覆盖 \(r.overwritten) · 跳过 \(r.skipped), 全部 demo_ 样例可一键清除")
    }
    private func runLockoutDrill() {
        guard !drillRunning else { return }
        drillRunning = true
        drillPhase = 0
        drillCool = 0
        Task { @MainActor in
            for p in 1...2 {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                drillPhase = p
            }
            // 844: 第 3 步 = 冷却倒计时界面 (镜像锁屏页 389 的「冷却中, N 秒后可再试」读秒;
            // 真实为锁端冻结时长, 演练压缩为 12 秒)。全程不写真实失败日志、不碰锁端。
            drillPhase = 3
            for c in stride(from: 12, through: 1, by: -1) {
                drillCool = c
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            drillCool = 0
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // "冷却结束"句停留 2 秒再收尾, 否则同帧被收走看不见
            drillRunning = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.showToast("演练完成: 真实场景请按「临时码→钥匙串→救援码」顺序自救")
        }
    }
}

