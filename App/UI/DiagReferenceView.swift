// 诊断查阅页 (包11 收尾): 把已经存在于代码里的四张对照表 + 二维码/崩溃档案接到界面上。
// 这一页只读、不发包、不写业务数据；所有内容的唯一来源是 StatusParser / PidMap / ProtocolDict / IconSemantics / CrashGuard / FirmwareHistory / QueryTemplates。
import SwiftUI

struct DiagReferenceView: View {
    /// 159: 从日志行的 rc 点进来时带的聚焦码 —— 对照表里对应那行加箭头与主色, 不再让用户自己找
    var highlightRC: Int? = nil
    @EnvironmentObject var app: AppState
    @State private var copiedKey: String = ""
    @State private var familyQuery = ""                 // 546 族名过滤
    @State private var template = 0                   // 762 选中的查询模板
    private var famsCount: Int { DataHealth.families().count }

    var body: some View {
        Form {
            // 753 诊断摘要二维码: 只含版本号/固件/最近错误/日志 SHA256 前 6 字节, 不含密钥与明文口令
            Section("诊断摘要二维码") {   // 753 诊断摘要二维码
                let text = DiagQR.summaryText(app: app)
                if let img = DiagQR.image(for: text) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .accessibilityLabel("诊断摘要二维码")
                } else {
                    Text("二维码生成失败（本机 CoreImage 未返回图像），下面是同一段文本。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                }
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                copyRow("复制摘要文本", key: "qr", payload: text)
                Text("摘要里没有 ekey/skey/PIN 明文；日志部分只放哈希，用于比对是否同一批日志。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }

            // 758 异常退出档案
            Section("异常退出档案 · \(CrashGuard.archList().count) 条") {   // 758 异常退出档案
                if CrashGuard.pendingAbnormal {
                    Label("本次启动检测到上一次异常退出（会话标记未被正常清掉）", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Button("已知晓，清掉这条提示") { _ = CrashGuard.consumePending() }
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.accentText)
                }
                let arch = CrashGuard.archList()
                if arch.isEmpty {
                    Text("没有异常退出记录 — 每次都是正常退出或进后台。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(arch.prefix(20), id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 758 档案导出: 列表此前只有看和翻, 没有导出文本的出口
                    ShareLink(item: arch.joined(separator: "\n\n")) {
                        Label("导出全部档案文本", systemImage: "square.and.arrow.up")   // 758 导出全部档案文本
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                }
                Text("判据是启动时的会话标记位（没走到正常退出路径才算异常），不是崩溃报告：iOS 上 App 拿不到自己的崩溃栈。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }

            // 755: 本机读到过的固件观测点 (observations() 此前零调用, 记录只在写侧落库)
            Section("本机固件观测点 · 当前锁") {   // 755 本机固件观测点
                let obs = FirmwareHistory.observations(mac: app.currentMac)
                if obs.isEmpty {
                    Text("这台手机还没有读到过该锁的固件版本 —— 连上一次并读取状态后这里会出现记录。")
                        .font(.caption).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // 先转成字符串再 ForEach: 元组不能遵循 Identifiable, 单参 ForEach 用不了 (id 走 self)
                    ForEach(obs.map { $0.day + " → " + $0.fw }, id: \.self) { line in
                        Text(line).font(.caption.monospaced()).foregroundStyle(DS.Palette.text)
                    }
                    Text("只是**这台手机读到过**的日期与版本, 不是门锁的完整固件历史; 中间没连过的日子不会补。")
                        .font(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 159 错误码对照表 (rc → 人话, 源自 StatusParser)
            Section("错误码对照表 · \(StatusParser.rcMsg.count) 条") {   // 159 错误码对照表
                if let h = highlightRC {
                    Label("从日志点进来的是 rc=\(h)"
                          + (StatusParser.rcMsg[h].map { ": " + $0 } ?? " — 表里没有这一码"),
                          systemImage: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.accent)
                }
                ForEach(StatusParser.rcMsg.keys.sorted(), id: \.self) { rc in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            if rc == highlightRC {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.accent)
                            }
                            LabeledRow("rc=\(rc)", StatusParser.rcMsg[rc] ?? "")
                        }
                        // 159 第三层「处理办法」: StatusParser.rcHint 早就写好了 (:166), 此前这一页
                        // 只画 码→含义 两层, 那份"该怎么办"在查阅表里零消费 —— 只有开锁失败提示用得上。
                        // 未给建议的码返回 nil, 这里就不出这一行 (不造"暂无建议"那种空话)。
                        if let hint = StatusParser.rcHint(rc) {
                            Text("怎么办: " + hint)
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, DS.Space.l)
                        }
                    }
                }
                Text("表内容与开锁失败时提示的文案同源（StatusParser.rcMessage），不是另抄一份。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }

            // 754 协议字段字典
            Section("协议字段字典 · 状态帧 \(ProtocolDict.statusFields.count) 项") {   // 754 协议字段字典
                ForEach(ProtocolDict.statusFields) { f in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.s) {
                            Text(f.k).font(.caption.monospaced()).foregroundStyle(DS.Palette.accentText)
                            Text(f.name).font(.subheadline).foregroundStyle(DS.Palette.text)
                            if copiedKey == "f\(f.k)" {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.ok)
                            }
                        }
                        Text(f.desc)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 754 逐条长按复制 (与 740 同理用菜单不抢点按); "已复制" 反馈落在本行, 复用 copyRow 的 1.5s 槽
                    .contextMenu {
                        Button("复制本字段说明") {
                            UIPasteboard.general.string = "\(f.k) · \(f.name) · \(f.desc)"
                            let key = "f\(f.k)"
                            copiedKey = key
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedKey == key { copiedKey = "" }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                // copyable() 此前零调用: 排障时要整表贴给别人, 逐条手抄不现实
                copyRow("复制全表", key: "pd", payload: ProtocolDict.copyable())   // 754 复制全表
            }

            // 661 型号市场名映射
            Section("型号与市场名") {   // 661 型号与市场名
                ForEach(PidMap.productNames.keys.sorted(), id: \.self) { pid in
                    LabeledRow("pid \(pid)", PidMap.productName(pid))
                }
                Text("只列已确证的 pid；未收录的 pid 会显示 \"智能门锁 (pid=…)\"，不冒充知道型号。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }

            // 662 图标语义表 (防漂移)
            Section("图标语义 · \(IconSemantics.rows.count) 条") {   // 662 图标语义
                ForEach(IconSemantics.rows) { r in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: r.icon)
                            .font(.system(size: DS.Icon.md))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(width: DS.Icon.xl)
                            .accessibilityHidden(true)
                        Text(r.use).font(.subheadline).foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                        Text(r.icon).font(.caption2.monospaced()).foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // 762 白名单查询模板: 只允许选引擎里预置的四种只读查询 (QueryTemplates), 不开放自由输入
            Section("只读查询模板") {   // 762 只读查询模板
                Picker("查询", selection: $template) {
                    Text("最近 20 条日志").tag(0)
                    Text("按类型 1/2/3 (开门类)").tag(1)
                    Text("成员凭证用量").tag(2)
                    Text("最近开锁失败").tag(3)
                }
                .pickerStyle(.menu)
                let r: QueryTemplates.Result = {
                    switch template {
                    case 1: return QueryTemplates.byType([1, 2, 3])
                    case 2: return QueryTemplates.memberUsage()
                    case 3: return QueryTemplates.recentFails()
                    default: return QueryTemplates.lastNLogs(20)
                    }
                }()
                Text(r.title).font(.caption.weight(.medium)).foregroundStyle(DS.Palette.text)
                if r.lines.isEmpty {
                    Text("该查询当前无结果 —— 是没数据，不是查询失败。")
                        .font(.caption).foregroundStyle(DS.Palette.textSub)
                } else {
                    ForEach(r.lines, id: \.self) { l in
                        Text(l).font(.caption.monospaced()).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                copyRow("复制查询结果", key: "q\(template)", payload: r.title + "\n" + r.lines.joined(separator: "\n"))
                Text("数据全部来自本机只读键位。刻意不提供自由输入或 SQL：本工程没有 SQL 层，假装能查任意字段就是假功能。")
                    .font(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 546/152 键族体积 (表级用量等价视图; 762 的"可查模板"在上面那一节)
            Section {
                let fams = DataHealth.families()
                let kw = familyQuery.trimmingCharacters(in: .whitespaces).lowercased()
                ForEach(kw.isEmpty ? fams : fams.filter { $0.key.lowercased().contains(kw) }) { f in
                    HStack(spacing: DS.Space.s) {
                        Text(f.key).font(.caption.monospaced()).foregroundStyle(DS.Palette.text)
                        Spacer(minLength: DS.Space.s)
                        Text(DataHealth.human(f.bytes)).font(.caption).monospacedDigit().foregroundStyle(DS.Palette.textSub)
                    }
                    .accessibilityElement(children: .combine)
                }
                if fams.isEmpty {
                    Text("没有可统计的本地键位。").font(.caption).foregroundStyle(DS.Palette.textSub)
                }
            } header: {
                Text("键族占用一览 · \(famsCount) 族")   // 546 键族占用一览
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    TextField("按族名过滤，如 ledger / logcache", text: $familyQuery)
                        .autocorrectionDisabled()
                        .accessibilityLabel("键族过滤输入")
                    Text("口径: 值对象长度估算，非磁盘真实占用；只列 kf_ 前缀族，系统域键位不在此表内。")
                }
                .font(.caption2)
            }
        }
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
        .navigationTitle("诊断查阅")
    }

    @ViewBuilder
    private func copyRow(_ title: String, key: String, payload: String) -> some View {
        Button {
            UIPasteboard.general.string = payload
            copiedKey = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copiedKey == key { copiedKey = "" } }
        } label: {
            Label(copiedKey == key ? "已复制" : title,
                  systemImage: copiedKey == key ? "checkmark.circle.fill" : "doc.on.doc")
        }
        .font(.footnote)
        .foregroundStyle(copiedKey == key ? DS.Palette.ok : DS.Palette.accentText)
    }
}
