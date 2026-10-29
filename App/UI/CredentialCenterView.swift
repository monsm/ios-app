// 包6 凭证中心 — 回收站 / 版本历史·diff / 月历 / 整理建议 / 下发队列 / 批量操作 sheet
// 全部本地数据层 (CredentialOrg.kf_* 表), 不新增协议命令; 需下发锁端的操作
// (还原即重新下发 504 / 批量停用 353) 保持"待下发"语义, UI 明示本地意图。
// 落点: 凭证 Tab 内的 NavigationLink 与批量操作栏; 不经过 vendor/。
import SwiftUI
import UIKit








// ================= 348 统一延期 sheet =================
struct CredExtendView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var aliases: [Int]
    var onDone: () -> Void
    /// 2026-10-29 性能：把「按 alias 查密码」从逐行 DB 调用改成一次建表。
    private var pwdByAlias: [Int: LedgerPwd] {
        Dictionary(DB.ledger(mac).pwds.map { ($0.alias, $0) }, uniquingKeysWith: { a, _ in a })
    }
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(30 * 86400)
    @State private var busy = false

    var body: some View { vkBody.destined(.credExtend) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("统一延期 (\(aliases.count) 条)") {   // 348 统一延期
                    DatePicker("生效", selection: $from, displayedComponents: .date)
                    DatePicker("延期至", selection: $to, in: from..., displayedComponents: .date)
                    Text("将一次性改写所选密码的**本机**过期字段并列出变更清单。⚠ 不会写入门锁 —— 锁端的有效期要到场后另行下发。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("变更清单") {
                    // 2026-10-29 性能：原来每行调一次 DB.getPwd（逐行全表解码）。
                    // 现在外面算一次字典，行里只查表。
                    ForEach(aliases, id: \.self) { a in
                        if let p = pwdByAlias[a] {
                            HStack(spacing: DS.Space.s) {
                                Text("#\(a)")
                                    .vkFont(.subheadline)
                                    .monospacedDigit()
                                Text(CredentialOrg.expiryLabel(p.to, verb: false) + " → " + to.formatted(.dateTime.year().month().day()))
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                Section {
                    BusyButton(title: "延期（只改本机）", isBusy: busy) {
                        Task { apply() }   // apply() 是同步方法: 那个 await 什么都没等 (UnnecessaryEffectMarker)
                    }
                }
            }
            .navigationTitle("统一延期")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { onDone() }
            } }
        }
    }

    private func apply() {
        busy = true
        let f = DF.cached("yyyy-MM-dd HH:mm:ss")
        let r = CredentialOrg.batchExtend(mac, aliases, f.string(from: from), f.string(from: to))
        busy = false
        // 2026-10-27 (D-58)：把"选中了但没找到"的条目如实报出来，不静默跳过
        let extra = r.failed.isEmpty ? "" : " · ⚠ 有 \(r.failed.count) 条已不在台账"
        app.showToast("已改写 \(r.done.count) 条本机有效期（锁端未改动）" + extra)
        _ = Milestones.recordOrganize()
        onDone()
    }
}


// ================= 353 批量停用摘要确认页 =================
struct CredDisableSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    var mac: String
    var pwdAliases: [Int]
    var fpBatches: [Int]
    var onDone: () -> Void
    /// 313 停用必填原因: 空值 = 确认按钮不可点 (不给默认值, 免得"默认原因"变成假记录)
    @State private var reason = ""
    private static let reasons: [(String, String)] = [
        ("leak", "疑似泄露"), ("rotate", "换码"), ("person", "人员变动"), ("other", "其他")]

    /// 367 影响成员及各自名下条数。**按名册顺序**出, 不用 Array(Set(...)):
    /// Set 的顺序每次启动都可能变 ⇒ 头像列会左右跳, 逐条写动态时同一批凭证还会写到不同顺序里。
    private var ownerCounts: [(id: String, pwd: Int, fp: Int)] {
        let pwds = DB.getPwdList(pwdAliases, mac)
        let fps = DB.getFpList(fpBatches, mac)
        let ids = Set(pwds.compactMap { $0.owner } + fps.compactMap { $0.owner })
        return DB.members().filter { ids.contains($0.id) }.map { m in
            (id: m.id, pwd: pwds.filter { $0.owner == m.id }.count, fp: fps.filter { $0.owner == m.id }.count)
        }
    }
    private var ownerIds: [String] { ownerCounts.map { $0.id } }

    /// 2026-10-29 性能：原来每个头像都调一次 DB.member(id)（逐行全表解码）。改成一次建表。
    /// 2026-10-30：建表结果放 @State，进页时（.task）填一次 —— 不再每次 body 求值都重建。
    @State private var memberNameByID: [String: String] = [:]
    /// 没归属的那几条: 它们不进任何人的动态, 这句话得能在界面上说出来。
    private var unownedCount: Int {
        max(0, (pwdAliases.count + fpBatches.count) - ownerCounts.reduce(0) { $0 + $1.pwd + $1.fp })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("停用摘要") {   // 353 停用摘要
                    HStack(spacing: DS.Space.s) {
                        // 影响成员头像列 (成员色点 183 风格, 纯本地) —— 名单见 ownerCounts, 顺序稳定
                        ForEach(ownerIds, id: \.self) { id in
                            if let name = memberNameByID[id] {
                                Circle()
                                    .fill(DS.Palette.accentText)
                                    .frame(width: 26, height: 26)
                                    .overlay(Text(String(name.prefix(1)))
                                        .vkFont(.caption2)
                                        // accentText 在深色模式是浅紫, 白首字母压上去几乎看不见
                                        .foregroundStyle(DS.Palette.onAccent)
                                        .lineLimit(1))
                                    .accessibilityLabel("成员 \(name)")
                            }
                        }
                        Text("影响 \(ownerIds.count) 位成员")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("密码 \(pwdAliases.count) 条 · 指纹 \(fpBatches.count) 条")
                            .vkFont(.subheadline, weight: .semibold)
                        ForEach(pwdsLines, id: \.self) { line in
                            Text(line)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        ForEach(fpLines, id: \.self) { line in
                            Text(line)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                Section {
                    Text("不可逆说明: 停用只移除**本机台账**。锁端凭证仍然有效 —— 必须到门锁键盘上手动删除才会真正失效。本机没有回收站，停用即不可在 App 内恢复，需要时只能重新录入/生成。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    // 313: 原因四选一, 没选就不许停用 (工单系统的"必填原因"口径)
                    HStack(spacing: DS.Space.xs) {
                        ForEach(Array(Self.reasons.enumerated()), id: \.offset) { _, r in
                            let on = reason == r.0
                            Button(r.1) {
                                reason = r.0
                                DS.Haptics.tick.impactOccurred()
                            }
                            .vkFont(.caption.weight(on ? .semibold : .regular))
                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.s)
                            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                            .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .contentShape(Rectangle())
                            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("停用原因\(reason.isEmpty ? ", 未选择" : "")")   // 313 停用原因
                    if reason.isEmpty {
                        Text("先选一个停用原因才能继续 — 原因只写进本机审计与运行日志，不会发给门锁。")
                            .vkFont(.caption2).foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 2026-10-27 审核修复：原「勾选写入该成员动态」开关已删 —— 它写的
                    // SensitiveLedger 随审计流水族一起移除，勾上之后一个字都不会多（假开关）。
                    // 367 的意图（按归属各写一条 vs 一条汇总）随载体消失，不再保留 UI。
                    // 353 二次点确认: 摘要页(一次) + 破坏性按钮(二次)
                    Button {
                        let label = Self.reasons.first { $0.0 == reason }?.1 ?? "其他"
                        let n = pwdAliases.count + fpBatches.count
                        // 只记条数与原因: 口令明文与指纹特征绝不进日志 (AUTOOPEN-PLAN §1 同一纪律)
                        app.lock.log("info", "停用 \(n) 条凭证 · 原因 \(label)")   // 313 停用
                        // 361: 逐条落一个回溯便签, 回收站行才答得出"这条当初为什么被停"
                        // 468 代管补记: 属主被点名「由我代管」的条, via 与单条停用同一口径补「管理员代操作」。
                        // 按条拆开各写各的 —— 没代管的条不许整批跟着沾这句 (同单条 disableVia 的判据)。
                        let proxyIDs = MemberHub.proxyNames
                        let proxyPwds = DB.getPwdList(pwdAliases, mac)
                            .filter { p in p.owner.map { proxyIDs.contains($0) } == true }.map(\.alias)
                        let proxyFps = DB.getFpList(fpBatches, mac)
                            .filter { f in f.owner.map { proxyIDs.contains($0) } == true }.map(\.batch)
                        CredentialOrg.markDisabled(mac, kind: "pwd", keys: pwdAliases.filter { !proxyPwds.contains($0) },
                                                   label: label, via: "本机批量停用")
                        CredentialOrg.markDisabled(mac, kind: "pwd", keys: proxyPwds,
                                                   label: label, via: "本机批量停用 · 管理员代操作")   // 468 本机批量停用
                        CredentialOrg.markDisabled(mac, kind: "fp", keys: fpBatches.filter { !proxyFps.contains($0) },
                                                   label: label, via: "本机批量停用")
                        CredentialOrg.markDisabled(mac, kind: "fp", keys: proxyFps,
                                                   label: label, via: "本机批量停用 · 管理员代操作")   // 468 本机批量停用
                        onDone()
                        dismiss()
                    } label: {
                        Text(reason.isEmpty ? "先选择停用原因" : "确认停用 (\(pwdAliases.count + fpBatches.count) 条)")   // 313 先选择停用原因
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(DestructiveActionStyle())
                    .disabled(reason.isEmpty)
                    .opacity(reason.isEmpty ? 0.45 : 1)
                    .accessibilityHint(reason.isEmpty
                        ? "需先选停用原因才能执行"
                        : "已展示影响成员与不可逆说明, 点按即执行停用")
                }
            }
            .navigationTitle("批量停用确认")
            .variantList()
            .dsScreenBackground()
            // 取消 = 只退出, 绝不触发 onDone (调用方 CredentialsView 的 onDone 即 finishDisable, 执行停用与入回收站)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            } }
        }
        // 进页时填一次成员名表（见 memberNameByID 注释）。
        .task {
            memberNameByID = Dictionary(DB.members().map { ($0.id, $0.name) },
                                        uniquingKeysWith: { a, _ in a })
        }
    }

    /// 2026-10-27 五轮：原实现拼的是 `#alias · countdown(p)`，倒计时已删，
    /// 只留别名 —— 停用确认页要的是"哪些条目"，不是"还剩多久"。
    private var pwdsLines: [String] {
        DB.getPwdList(pwdAliases, mac).prefix(6).map { "#\($0.alias)" }
    }
    private var fpLines: [String] {
        DB.getFpList(fpBatches, mac).prefix(6).map { "「\($0.name)」" }
    }
}
