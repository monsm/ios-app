// 包6 凭证中心 — 回收站 / 版本历史·diff / 月历 / 整理建议 / 下发队列 / 批量操作 sheet
// 全部本地数据层 (CredentialOrg.kf_* 表), 不新增协议命令; 需下发锁端的操作
// (还原即重新下发 504 / 批量停用 353) 保持"待下发"语义, UI 明示本地意图。
// 落点: 凭证 Tab 内的 NavigationLink 与批量操作栏; 不经过 vendor/。
import SwiftUI
import UIKit

// ================= 入口 (从凭证 Tab 进入, 按 section 路由) =================
struct CredCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    var section: String   // "bin" / "histAll" / "queue" / "organize"

    var body: some View {
        NavigationStack {
            List {
                centerRow(icon: "trash", title: "回收站", sub: "\(CredentialOrg.bin(mac).count) 条 · 保留 \(CredentialOrg.reclaimDays()) 天") {   // 497 保留
                    CredBinView(mac: mac)
                }
                centerRow(icon: "clock.arrow.circlepath", title: "版本历史", sub: "保存自动快照 + 恢复即新版本") {   // 487/496 保存自动快照
                    CredHistoryListView(mac: mac)
                }
                centerRow(icon: "rectangle.3.offgrid", title: "整理建议中心", sub: "\(CredentialOrg.advice(mac).count) 条待办") {   // 358/505 条待办
                    // 358: 建议行落地后要直达凭证列表 (预勾选已就位), 把整张凭证中心也一起收掉 ——
                    // 只 pop 一层会停在"凭证中心", 用户还得再点一次关闭才看得到多选
                    CredOrganizeView(mac: mac, onClose: { dismiss() })
                }
                centerRow(icon: "arrow.down.circle", title: "待下发队列", sub: "\(CredentialOrg.pendingQueue(mac).count) 项 · 到场补发") {   // 365 到场补发
                    CredQueueView(mac: mac)
                }
            }
            .navigationTitle("凭证中心")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            } }
        }
    }

    private func centerRow<Content: View>(icon: String, title: String, sub: String, @ViewBuilder dest: () -> Content) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(width: DS.Icon.xl, height: DS.Icon.xl)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
    }
}

// ================= 497-506 回收站 =================
struct CredBinView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var initialQuery: String = ""
    @State private var source: Int = -1       // 498 来源过滤: -1 全部
    @State private var query = ""
    @State private var pendingPurge: CredBinEntry?

    /// 532 搜索兜底动作: 凭证页那枚「去回收站搜 (503)」把当前搜索词一起递进来, 打开的就是已过滤的那一屏。
    /// 原先这一步只有 `showBin = true` —— 词没传, 落地是个空搜索框, 用户还得自己再打一遍 (兜底动作没兜到底)。
    /// 走 init + State(initialValue:) 而不是 onAppear 里补写: 交接只发生这一次, 之后搜索框归这一页自己。
    init(mac: String, initialQuery: String = "") {
        self.mac = mac
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        List {
            // 500 容量头行: 条数 + 下次自动清理日期
            let header = CredentialOrg.binHeader(mac)
            Section {
                HStack(spacing: DS.Space.s) {
                    Text("\(header.count) 条")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    if let d = header.nextClean {
                        Text("下次自动清理 " + d.formatted(.dateTime.month().day()))
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                // 498 来源过滤分段
                let names = ["全部", "手动删除", "批量清理", "过期清理", "重录替代"]
                HStack(spacing: DS.Space.xs) {
                    ForEach(0..<names.count, id: \.self) { i in
                        let v = i - 1
                        let on = source == v
                        Button(names[i]) {
                            source = v
                            DS.Haptics.tick.impactOccurred()
                        }
                        .font(.caption.weight(on ? .semibold : .regular))
                        .padding(.horizontal, DS.Space.s).padding(.vertical, 4)
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                        .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
                        .frame(minHeight: DS.Hit.min - DS.Space.xs)
                        .contentShape(Rectangle())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("来源过滤: \(names[source + 1])")
                TextField("搜索已删项", text: $query)   // 503 界面文案
                    .autocorrectionDisabled()
                    .accessibilityLabel("回收站搜索")
                if !initialQuery.isEmpty {
                    // 532: 词是凭证页递过来的就说一句, 不然这一屏看着像"谁替我打了字"
                    Text("这词是从凭证页的搜索带进来的, 要改要清都在这里。")   // 532/503 这词是从凭证页的搜索
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 362 复活提示: 只在真有同类开门时出现, 且把"推断"与局限写在同一屏里
            if !resurrectHints.isEmpty {
                Section("删除后仍出现同类开门") {   // 362 删除后仍出现同类开门
                    ForEach(resurrectHints) { h in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("「\(h.text)」之后仍有 \(h.n) 次\(h.kindName)开门")
                                .font(.footnote)
                                .foregroundStyle(DS.Palette.text)
                            Text("协议没有\"读取锁内凭证清单\"的命令, 这是按凭证类型的推断; 且比较用的是锁自己记的时间, 锁钟未校准时会有偏差。要确认请在锁键盘上试该凭证或逐条删除。")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section("已删 (\(rows.count))") {
                if rows.isEmpty {
                    Text(query.isEmpty ? "回收站是空的。删除的凭证会在这里保留 \(CredentialOrg.reclaimDays()) 天。" : "没有匹配「\(query)」的已删项。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows) { e in
                    binRow(e)
                }
            }
            if rows.count > 1 {
                Section {
                    Button("整组还原") {   // 501 整组还原
                        var n = 0
                        for e in rows { _ = CredentialOrg.restoreBin(mac, entry: e, asCopy: false); n += 1 }
                        app.showToast("已整组还原 \(n) 条")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                }
            }
            Section {
                Button("清空回收站", role: .destructive) {   // 502 清空回收站
                    pendingPurge = nil
                    purgeAll()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DS.Hit.min)
            } footer: {
                Text("彻底删除不可找回。保留期可在 设置-安全-凭证整理 调整。")   // 497 彻底删除不可找回
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .navigationTitle("回收站")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    /// 362 复活提示条目 (由本机类型级推断换算成可读行)
    private struct ResurrectHint: Identifiable {
        let text: String
        let kindName: String
        let n: Int
        var id: String { text + kindName }
    }
    private var resurrectHints: [ResurrectHint] {
        RecordSearch.resurrectionHints(mac: mac).map { h in
            let name: String
            switch h.kind {
            case "pwd": name = "密码"
            case "temp": name = "临时码"
            case "fp": name = "指纹"
            default: name = "同类凭证"
            }
            return ResurrectHint(text: h.text, kindName: name, n: h.n)
        }
    }

    private var rows: [CredBinEntry] {
        var list = CredentialOrg.bin(mac)
        if source >= 0 { list = list.filter { $0.source == source } }
        if !query.isEmpty {
            list = list.filter {
                let hay = "\($0.pwd.map { "密码 #\($0.alias)" } ?? "") \($0.fp?.name ?? "") \($0.pwd?.note ?? "")"
                return hay.localizedCaseInsensitiveContains(query)
            }
        }
        return list
    }

    @ViewBuilder
    private func binRow(_ e: CredBinEntry) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(e.text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                StatusPill(text: e.sourceName, systemImage: "archivebox", tone: .neutral)
                Spacer(minLength: 0)
                let daysLeft = daysLeftOf(e)
                Text(daysLeft >= 0 ? "剩 \(daysLeft) 天" : "已过期")
                    .font(.caption2)
                    .foregroundStyle(daysLeft <= 3 ? DS.Palette.warn : DS.Palette.textSub)
                    .lineLimit(1)
            }
            if let p = e.pwd {
                Text("到 \(p.to.prefix(16)) · 归属 \(CredentialOrg.ownerName(p.owner).isEmpty ? "无" : CredentialOrg.ownerName(p.owner))")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 361 停用原因回溯: 台账里已无此条, 便签是"为什么被停"的唯一留存 (非本 App 停用则不显示)
                if let t = CredentialOrg.disableMarkText(mac, kind: "pwd", key: p.alias) {
                    Text(t)
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let f = e.fp,
                      let t = CredentialOrg.disableMarkText(mac, kind: "fp", key: f.batch) {
                Text(t)
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: DS.Space.s) {
                // 364 恢复窗口期: 7 天内可一键恢复; 超期按钮说明"需重新下发"
                let inWindow = CredentialOrg.withinRecoverWindow(mac, entry: e)
                Button(inWindow ? "一键恢复" : "恢复 (需重新下发)") {
                    restore(e)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(inWindow ? DS.Palette.accentText : DS.Palette.textSub)
                .buttonStyle(.bordered)
                .disabled(!inWindow && e.pwd != nil)   // 指纹无锁端窗口概念, 始终可还原台账
                Button("副本") {
                    app.showToast(CredentialOrg.restoreBin(mac, entry: e, asCopy: true))   // 499 界面文案
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("彻底删除") { pendingPurge = e }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.danger)
                    .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingPurge = e } label: { Label("彻底删除", systemImage: "xmark.bin") }
        }
        .confirmationDialog("彻底删除?", isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }), titleVisibility: .visible) {   // 502 彻底删除
            Button("输入确认", role: .destructive) {
                if let x = pendingPurge {
                    // 502 门槛统一: 这一枚原先按下即 purgeBin —— 同一个「彻底删除」在单条与清空两条路上
                    // 一套有生物识别、一套没有 (§10.39 修过的正是这种分叉)。现在两条都走 guardedPurge。
                    CredentialOrg.guardedPurge(mac, ids: [x.id],
                                               reason: "彻底删除这条回收站凭证",   // 502 彻底删除这条回收站凭
                                               onDeniedPresentFallback: { commit in
                        confirmDestructive("彻底删除", "生物识别未通过，或这台设备没有可用的生物识别。仍要彻底删除这一条? 指纹删掉后只能到锁前重录。", confirmTitle: "删除") {
                            commit()
                        }
                    },
                                               onDone: { app.showToast("已彻底删除 (指纹无法再录入; 密码值可再生成)") })
                }
                pendingPurge = nil
            }
            Button("取消", role: .cancel) { pendingPurge = nil }
        } message: {
            Text("彻底删除不可找回。若删的是指纹, 成员需到锁前重新录入。")
        }
    }

    private func daysLeftOf(_ e: CredBinEntry) -> Int {
        let keep = Double(CredentialOrg.reclaimDays()) * 86400
        // 单位口径：秒 —— `e.at` 是 `CredBinEntry.at` (秒)，`keep` 也是秒数的保留窗口；这条算"还剩几天可一键恢复"。
        return Int((e.at + keep - CredentialOrg.nowSec) / 86400)
    }

    private func restore(_ e: CredBinEntry) {
        // 504 还原即重新下发 —— 第一百五十四批把这一步搬进 `CredentialOrg.restoreBin`：
        // 那时它还写在这个调用点的弹窗里，而 `restoreBin` 一共有三个调用方 (单条 / 批量 / 还原为副本)，
        // 另两条把密码放回台账却从不排下发 ⇒ 界面"已还原"，锁里没这条。
        // 现在排队与"排没排、为什么没排"都由 restoreBin 的返回值说清，这里不再各写一遍。
        app.showToast(CredentialOrg.restoreBin(mac, entry: e, asCopy: false))
    }

    private func purgeAll() {
        let entries = CredentialOrg.bin(mac)
        guard !entries.isEmpty else { return }
        let n = entries.count
        // 502 门槛统一: 与单条那枚同走 guardedPurge。这里原先自己现造 LAContext 直接 evaluatePolicy —
        // 没先问 canEvaluate、也没有"无生物可刷"的 biometryNotAvailable 分支；同一个「彻底删除」
        // 两条路深浅各说各话正是漏问的开始 (§10.39 修过的就是这种分叉)。
        CredentialOrg.guardedPurge(mac, ids: entries.map(\.id),
                                   reason: "彻底删除回收站 \(n) 条",
                                   onDeniedPresentFallback: { commit in
            confirmDestructive("彻底清空回收站", "生物识别未通过，或这台设备没有可用的生物识别。仍要彻底清空 \(n) 条已删凭证? 不可找回 (指纹需到锁前重新录入)。", confirmTitle: "清空") {
                commit()
            }
        },
                                   onDone: {
                                       app.showToast("已清空回收站")   // 505 已清空回收站
                                       _ = Milestones.recordOrganize()
                                   })
    }
}

// ================= 487-496 版本历史 =================
/// 全锁凭证的历史索引 (每凭证一个入口), 供 "版本历史与整理" 页路由
struct CredHistoryListView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var body: some View {
        List {
            let pwds = DB.listPwds(mac).filter { !CredentialOrg.history(mac, "pwd", $0.alias).isEmpty }
            let fps = DB.listFps(mac).filter { !CredentialOrg.history(mac, "fp", $0.batch).isEmpty }
            Section("有快照的凭证 (\(pwds.count + fps.count))") {
                ForEach(pwds) { p in
                    NavigationLink {
                        CredHistoryView(mac: mac, kind: "pwd", key: p.alias)
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            Text(CredentialOrg.displayPwd(p))
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(CredentialOrg.history(mac, "pwd", p.alias).count) 版")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                }
                ForEach(fps) { f in
                    NavigationLink {
                        CredHistoryView(mac: mac, kind: "fp", key: f.batch)
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            Text("指纹「\(f.name)」")
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(CredentialOrg.history(mac, "fp", f.batch).count) 版")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                }
                if pwds.isEmpty && fps.isEmpty {
                    // 487 还没有快照
                    // 491 还没有快照
                    Text("还没有快照。改动密码值 / 备注 / 归属 / 改期时会自动留档, 每凭证保留 \(CredentialOrg.quota(mac)) 版。")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("版本历史")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }
}

/// 单凭证历史页: 摘要句流 (490) + 修订着色 diff (489) + 星标版 (495) + 恢复即新版本 (496) + 只读回看 (493)
struct CredHistoryView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var kind: String
    var key: Int
    @State private var preview: Int? = nil     // 493 只读回看选中的版本
    @State private var diffFrom: Int? = nil    // 489 对比基线版本
    /// 星标等"只写库"的操作不会触发 body 重算 → 图标不变, 用户以为没生效 (495)
    @State private var storeTick = 0

    private var title: String {
        if kind == "pwd" { return CredentialOrg.displayPwd(DB.getPwd(mac, key) ?? LedgerPwd(alias: key, from: "2010-01-01 00:00:00", to: "2118-01-01 00:00:00", temp: false, at: 0, note: "")) }
        if let f = DB.getFp(mac, key) { return "指纹「\(f.name)」" }
        return kind == "pwd" ? "密码 #\(key)" : "指纹批次 \(key)"
    }

    var body: some View {
        List {
            if let pv = preview {
                previewSection(pv)
            }
            Section {
                ForEach(snaps) { s in
                    snapRow(s)
                }
            } header: {
                Text("历史 (\(snaps.count + reloadTick - reloadTick), 保留 \(CredentialOrg.quota(mac)) 版)")
            } footer: {
                Text("488 自动还原点 (批量操作前) 置顶加标记; 495 星标版不受配额淘汰; 496 恢复不覆盖, 生成「恢复自 vX」新档。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .navigationTitle(title)
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private var snaps: [CredSnapshot] {
        // 488 自动还原点置顶
        let list = CredentialOrg.history(mac, kind, key)
        return list.sorted { a, b in
            if a.auto != b.auto { return b.auto }
            return b.version > a.version
        }
    }

    @ViewBuilder
    private func snapRow(_ s: CredSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                if s.auto {
                    StatusPill(text: "自动还原点", systemImage: "flag.fill", tone: .accent)
                }
                Text("v\(s.version) · \(s.note)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button {
                    var next = CredentialOrg.history(mac, kind, key)
                    for i in next.indices where next[i].version == s.version { next[i].starred.toggle() }
                    CredentialOrg.saveHistory(mac, kind, key, next)
                    storeTick += 1
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Image(systemName: s.starred ? "star.fill" : "star")
                        .font(.system(size: DS.Icon.md, weight: .medium))
                        .foregroundStyle(s.starred ? DS.Palette.warn : DS.Palette.textSub)
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(s.starred ? "取消星标版本" : "星标此版本")   // 495 星标此版本
            }
            Text(s.relTime)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
            // 489 基线可见: 钉住基线时把"在跟谁比"写在行上, 不设就不写 (默认与上一版比)
            if let base = diffFrom, base != s.version {
                Text("对比基线已钉在 v\(base)")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
            // 489 修订着色: 与上一版逐字段对齐, 删除红/新增绿/修改黄
            if let up = prevOf(s) {
                ForEach(CredentialOrg.diff(up, s).filter { $0.kind != "same" }) { d in
                    HStack(spacing: DS.Space.xs) {
                        Text(d.label)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                        Text(diffText(d))
                            .font(.caption)
                            .foregroundStyle(d.kind == "del" ? DS.Palette.danger : (d.kind == "add" ? DS.Palette.ok : DS.Palette.warn))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: DS.Space.s) {
                // 489 基线可清除: 原先"看差异"只能设不能清, 点过一次之后每一行都永久跟那一版比,
                // 而界面上没有任何地方说明基线被钉住了, 也没有回退口 (同类 storeTick 的问题早前已修)。
                // 现在同一颗按钮兼作开关: 已选中此版 → 再点即清除基线, 回到"与上一版比"。
                Button(diffFrom == s.version ? "取消基线" : "看差异") {
                    diffFrom = (diffFrom == s.version) ? nil : s.version
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .accessibilityLabel(diffFrom == s.version ? "取消对比基线 v\(s.version), 改回与上一版比较"
                                                           : "以此版 v\(s.version) 为对比基线")
                Button(preview == s.version ? "退出预览" : "回看此版") {   // 493 回看此版
                    preview = (preview == s.version) ? nil : s.version
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("恢复到 v\(s.version)") {
                    // 496 恢复即新版本: 不覆盖, 新增 "恢复自 vX" 快照
                    // 第一百五十四批: 恢复只改本机台账 ⇒ 密码跟着排一次 504 重新下发，
                    // 提示语带"锁端那条要重新下发才生效"那半句，不再单说"已恢复"。
                    let extra = CredentialOrg.restore(mac, kind: kind, key: key, from: s)
                    app.showToast("已恢复 v\(s.version), 生成新版本" + extra)   // 496 已恢复
                    reloadCenter()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func diffText(_ d: CredentialOrg.Diff) -> String {
        switch d.kind {
        case "del": return "删去 " + d.old
        case "add": return "新增 " + d.neu
        default: return d.old + " → " + d.neu
        }
    }
    private func prevOf(_ s: CredSnapshot) -> CredSnapshot? {
        // 489 对比基线: 钉住别的版本就跟那一版比；基线正好是本行时退回"上一版"。
        // 第八十五批补这半边: 原先 target 直接取 diffFrom, 于是点"看差异"钉在正在看的这一行
        // 会得到 diff(自己, 自己) = 全 same = 界面整块空白, 看着像功能坏了。
        let pinned = diffFrom.flatMap { $0 == s.version ? nil : $0 }
        let target = pinned ?? s.version - 1
        return CredentialOrg.history(mac, kind, key).first { $0.version == target }
    }
    @ViewBuilder
    private func previewSection(_ v: Int) -> some View {
        let s = CredentialOrg.history(mac, kind, key).first { $0.version == v }
        if let s {
            Section("只读预览 v\(v)") {   // 493 只读预览
                Text(CredentialOrg.summaryText(of: s))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Text("顶栏「回到此版」= 按此版生成新档, 不覆盖历史。")   // 496 顶栏
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
    }
    /// 496 恢复生成新档后让列表重查 (通过 @State 计数驱动 body 重算)
    @State private var reloadTick = 0
    private func reloadCenter() { reloadTick += 1 }
}

// ================= 363 月历到期视图 =================
struct CredCalendarView: View {
    var mac: String
    var onPick: (Date) -> Void
    @State private var ym: Date = Date()
    @State private var picked: Date?

    var body: some View {
        // 912: 月历的 lead 计算走 WeekCal —— 与上面 weekdayHeaders 的轮转必须同源，否则整体错一天
        let cal = WeekCal.calendar
        let year = cal.component(.year, from: ym)
        let month = cal.component(.month, from: ym)
        let dl = CredentialOrg.monthDeadlines(mac, year: year, month: month)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Button("‹") { move(-1) }
                        .font(.title3.weight(.semibold))
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("上个月")
                    Spacer(minLength: 0)
                    Text("\(String(year)) 年 \(month) 月")
                        .font(.headline)
                        .foregroundStyle(DS.Palette.text)
                    Spacer(minLength: 0)
                    Button("›") { move(1) }
                        .font(.title3.weight(.semibold))
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("下个月")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: DS.Space.xs) {
                    ForEach(weekdayHeaders, id: \.self) { w in
                        Text(w)
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .frame(maxWidth: .infinity)
                    }
                    let cells = monthCells(year: year, month: month, ym: ym, cal: cal)
                    ForEach(0..<cells.count, id: \.self) { i in
                        if let d = cells[i] {
                            dayCell(year: year, month: month, day: d, count: dl[cal.date(from: DateComponents(year: year, month: month, day: d))!] ?? 0)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                if let p = picked {
                    let items = CredentialOrg.dayDeadlines(mac, p)
                    if !items.isEmpty {
                        Section("\(p.formatted(.dateTime.month().day())) 到期 (\(items.count))") {
                            ForEach(items) { x in
                                HStack(spacing: DS.Space.s) {
                                    Text(CredentialOrg.displayPwd(x))
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                    Text("到 " + x.to.prefix(10))
                                        .font(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                }
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                Spacer(minLength: DS.Space.l)
            }
            .padding(DS.Space.gutter)
        }
        .dsScreenBackground()
        .onAppear { picked = nil }
    }

    private var weekdayHeaders: [String] {
        // 912: 表头必须与月历 lead 用**同一个** firstWeekday 轮转。
        // 原来是硬写 ["日","一",…] 的周日开头 —— 它只是恰好等于 zh_CN 的默认值;
        // 一旦周起点可变而表头不动，格子就会整体错位一天 (周一的日期排在"日"下面)。
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let fw = WeekCal.calendar.firstWeekday      // Calendar 约定 1...7，越界也要夹回来而不是 trap
        let start = min(max(fw - 1, 0), 6)
        return Array(names[start...] + names[..<start])
    }

    @ViewBuilder
    private func dayCell(year: Int, month: Int, day: Int, count: Int) -> some View {
        let d = WeekCal.gregorian.date(from: DateComponents(year: year, month: month, day: day))!
        let isToday = WeekCal.gregorian.isDateInToday(d)
        let isPicked = picked.map { WeekCal.gregorian.isDate($0, inSameDayAs: d) } ?? false
        Button {
            picked = isPicked ? nil : d
            if !isPicked { onPick(d) }
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        // warn 是语义填充色, 走"填充上的前景"令牌 (浅档白字/深档墨字, 机检 E1)
                        .foregroundStyle(DS.Palette.onSem)
                        .padding(.horizontal, DS.Space.xs).padding(.vertical, DS.Space.xxs)
                        .background(DS.Palette.warn, in: Capsule())
                        .lineLimit(1)
                }
                Text("\(day)")
                    .font(.subheadline)
                    .foregroundStyle(isToday ? DS.Palette.accentText : DS.Palette.text)
                    .frame(minWidth: 14)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Hit.min)
            .background(isPicked ? DS.Palette.accentText.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(year) 年 \(month) 月 \(day) 日, 当日到期 \(count) 条")
    }
    /// 363 月历格: 前置空位 + 1...天数, 补齐到整周。
    /// 抽成函数是因为 `while` 循环不能出现在 ViewBuilder 里
    /// (会报 "closure containing control flow statement cannot be used with result builder 'ViewBuilder'")。
    private func monthCells(year: Int, month: Int, ym: Date, cal: Calendar) -> [Int?] {
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = cal.range(of: .day, in: .month, for: ym)?.count else { return [] }
        let lead = (cal.firstWeekday + 6 - cal.component(.weekday, from: first)) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead)
        // 2026-10-13 run 59: 原写 `cells.append(contentsOf: 1...days)` —— cells 的元素是 `Int?`,
        // 而 `1...days` 的元素是 `Int`, 报 "no exact matches in call to instance method 'append'"
        // (候选要求 Element == Int)。逐个升成 Optional 再拼。
        cells.append(contentsOf: (1...days).map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
    private func move(_ delta: Int) {
        ym = WeekCal.gregorian.date(byAdding: .month, value: delta, to: ym) ?? ym
    }
}

// ================= 358/505 整理建议中心 =================
struct CredOrganizeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    /// 调用方 (CredentialCenterView:26 整理建议中心) 未传 → 旧写法直接编译不过; 默认空闭包 = 由父页 body 重算刷新
    var onDone: () -> Void = {}
    /// 358 预勾选落地时用来收掉整张凭证中心 sheet; 未传 (独立预览等场景) 就只 pop 本层
    var onClose: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                let adv = CredentialOrg.advice(mac)
                Section("整理建议") {   // 358 整理建议
                    if adv.isEmpty {
                        Label {
                            Text("没有待整理的项, 台账很干净。")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.seal").accessibilityHidden(true)
                        }
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.ok)
                    }
                    ForEach(adv) { a in
                        if a.action == "bin" {
                            NavigationLink {
                                CredBinView(mac: mac)
                            } label: { adviceRow(a) }
                        } else {
                            Button { apply(a) } label: { adviceRow(a) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                Section("说明") {
                    // 505 回收站
                    // 358 回收站
                    // 471 回收站
                    Text("「回收站 N 条」直达回收站; 过期/重复值/无归属点按后带预勾选回凭证列表多选, 底部批量条停用或移交; 成员级建议直接执行。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("整理建议")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("完成") { onDone() }
            } }
        }
    }

    @ViewBuilder
    private func adviceRow(_ a: CredentialOrg.Advice) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: a.icon)
                .font(.system(size: DS.Icon.md, weight: .medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: DS.Icon.xl, height: DS.Icon.xl)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Palette.text)
                Text(a.sub)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func apply(_ a: CredentialOrg.Advice) {
        // 471 的成员级建议: 智能选取 (350) 没有"按成员"这一集合, 所以不能沿用"用智能选取套用"那句指引。
        // 这条直接执行停用: 口径与建议生成完全同源 (temp + owner + 已过期, 354: 双方同去归档),
        // 走 batchDisable 这一条既有批量路径 (删除 + 回收站 + 锁端删除入队), 不另拼一份。
        if a.action == "memberExpired" {
            let owner = String(a.id.dropFirst("memberExpired:".count))
            let aliases = DB.listPwds(mac)
                .filter { $0.temp && $0.owner == owner && CredentialOrg.pwdState($0) == 2
                          && !CredentialOrg.isArchived(mac, "pwd", $0.alias) }
                .map { $0.alias }
            let n = CredentialOrg.batchDisable(mac, pwdAliases: aliases, fpBatches: [])
            app.showToast(n > 0 ? "已停用 \(n) 张过期码并收进回收站" : "没有可停用的过期码")   // 471 已停用
            onDone()
            return
        }
        // 358: 「点击进入对应多选」—— 其余建议按各自集合算出 alias 表, 交凭证页多选预勾选 (会话态深链)。
        // 原先只 toast 一句"回列表点选择再用智能选取", 是把三步手动路推回给用户, 不是"进入多选"。
        // 集合口径与建议生成 (:752-770) 同源: 过期=pwdState 2 / 重复值=同值组去重后的全体 / 无归属=owner 空。
        // 354: 预勾选与智能选取同一口径 —— 归档条不进预勾 (勾了也看不见, 等于"看不到却被停掉")
        let selectable = DB.listPwds(mac).filter { !CredentialOrg.isArchived(mac, "pwd", $0.alias) }
        let ids: [Int]
        switch a.action {
        case "expired":
            ids = selectable.filter { CredentialOrg.pwdState($0) == 2 }.map { $0.alias }
        case "dups":
            var byValue: [String: [Int]] = [:]
            for p in selectable where p.pwd != nil { byValue[p.pwd!, default: []].append(p.alias) }
            ids = byValue.values.filter { $0.count > 1 }.flatMap { $0 }
        case "noowner":
            ids = selectable.filter { $0.owner == nil }.map { $0.alias }
        default:
            ids = []
        }
        guard !ids.isEmpty else {
            app.showToast("这条建议当前没有可勾选的条目")
            onDone()
            return
        }
        app.pendingCredSelect = ids
        app.showToast("已勾好 \(ids.count) 条, 回列表继续")   // 358 已勾好
        onDone()
        // 有 onClose 就整张 sheet 收起直达列表; 没有则退回上一层 (独立进入时的兜底)
        if let c = onClose { c() } else { dismiss() }
    }
}

// ================= 365 待下发队列 (本地容错步条) =================
struct CredQueueView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    @State private var busy: Int? = nil
    /// 「全部重试」互斥: 旧写法连点会开出多个并发 Task, 对同一队列重复下发删除/延期命令
    @State private var retryAllRunning = false

    var body: some View {
        List {
            let q = CredentialOrg.pendingQueue(mac)
            if q.isEmpty {
                Section {
                    Label {
                        Text("没有待处理项。停用/删除/延期操作在锁端未连接时会自动记入这里。")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "tray").accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                }
            }
            // 538 按锁排队: 队列头显示目标锁名与剩余项数 — 多锁各自队列不串台
            Section("未完成 (\(q.count)) · 目标锁 \(lockName) · 到场连接后逐条重试") {
                ForEach(q) { item in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.s) {
                            StatusPill(text: stateText(item), systemImage: item.state == 2 ? "exclamationmark.triangle" : "arrow.down.circle", tone: tone(item))
                            Text(item.title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if busy == item.id {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        // 365 三步步条: 待下发 → 已下发 → 锁端确认 (rc@#03); 失败态可重试
                        HStack(spacing: DS.Space.xs) {
                            step("待下发", item.state != 0 ? 2 : 1)
                            step("已下发", item.state == 1 ? 1 : 2)
                            step("锁端确认", item.state == 1 ? 1 : 0)
                            Spacer(minLength: 0)
                            Button("重试") { retry(item) }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .disabled(busy != nil)
                        }
                        if item.attempt > 0 {
                            Text("第 \(item.attempt) 次尝试 · \(itemTime(item.lastAt))")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button("全部重试 (按序)") {
                    guard !retryAllRunning else { return }
                    retryAllRunning = true
                    Task {
                        defer { retryAllRunning = false }
                        for item in q {
                            busy = item.id
                            do {
                                try await app.lock.ensureConnected(mac: mac)
                                // 2026-10-13 对抗式排查: 把 sendQueued 的归位提示拼进 note
                                // (原先 `_ = ` 丢掉, 凭证页那处反而拼了 —— 两处口径不一致)
                                let extra = try await applyItem(item)
                                CredentialOrg.markQueue(mac, id: item.id, state: .done,
                                                         note: item.title + " · 锁端确认" + extra)
                            } catch {
                                CredentialOrg.markQueue(mac, id: item.id, state: .failed, note: item.title + " · 失败: " + error.localizedDescription)
                            }
                            busy = nil
                        }
                        app.showToast("已逐条重试 \(q.count) 项")
                    }
                }
                .disabled(retryAllRunning)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(retryAllRunning ? DS.Palette.textSub : DS.Palette.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DS.Hit.min)
            }
        }
        .navigationTitle("待下发队列")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            } }
    }

    private var lockName: String {
        app.devices.first { $0.mac == mac }.map { LockArchive.displayName($0) } ?? String(mac.prefix(6))
    }
    private func stateText(_ i: CredQueueItem) -> String {
        switch i.state {
        case 1: return "已下发"
        case 2: return "失败"
        default: return "待下发"
        }
    }
    private func tone(_ i: CredQueueItem) -> ToneColor {
        switch i.state {
        case 1: return .ok
        case 2: return .danger
        default: return .warn
        }
    }
    /// 步条小段: 0 灰 / 1 当前黄 / 2 完成绿 (颜色 + 数字双通道, 不只靠颜色)
    private func step(_ label: String, _ level: Int) -> some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: level == 0 ? "circle" : (level == 1 ? "circle.inset.filled" : "checkmark.circle.fill"))
                .font(.system(size: 11))
                .foregroundStyle(level == 0 ? DS.Palette.textSub : (level == 1 ? DS.Palette.warn : DS.Palette.ok))
            Text(label)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .accessibilityElement(children: .combine)
    }
    private func retry(_ item: CredQueueItem) {
        guard busy == nil else { return }
        // 第八十八批: 入口一次性钉住锁 (含非空校验)。原先 Task 里连读三次活读的 `mac` ——
        // ensureConnected 一次、成功回写一次、失败回写一次；两次 await 之间当前锁可被 AppIntent /
        // kf:// 深链改掉，于是"命令发给 A 锁、队列状态记到 B 锁"。current 变 nil 时 `?? ""`
        // 还会把队列状态写到空 mac 上 (等于把这条待办弄丢)。
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busy = item.id
        Task {
            defer { busy = nil }
            do {
                try await app.lock.ensureConnected(mac: m)
                // 第一百五十四批: 这条 switch 曾有独立一份，且**没带**"缺别名就中止"的修正 ——
                // `item.pwd?.alias ?? 0` 会向锁发"删 0 号槽"，删掉的是别人的密码，
                // 回包后还被标成"锁端确认"。三份实现现在收进 CredentialOrg.sendQueued 一处。
                let extra = try await CredentialOrg.sendQueued(m, app.lock, item)
                CredentialOrg.markQueue(m, id: item.id, state: .done, note: item.title + " · 锁端确认" + extra)
                app.showToast("\(item.title) 已下发")
            } catch {
                CredentialOrg.markQueue(m, id: item.id, state: .failed, note: item.title + " · 失败: " + error.localizedDescription)
                app.showToast("重试失败: \(error.localizedDescription)")
            }
        }
    }
    /// 365 队列项下发: 唯一实现收在 CredentialOrg.sendQueued (第一百五十四批),
    /// 这里只做"发一条"的最小包装 —— 原先这一行引用的 applyItem 在全仓从未定义过。
    /// 2026-10-13 对抗式排查: 原写 `_ = try await CredentialOrg.sendQueued(...)` ——
    /// sendQueued 的返回值 (锁端把凭证落到新别名时的归位提示) 被**丢掉**, 而凭证页 :791 那一处
    /// 是 `let extra = try await ...` 并拼进了队列提示。同一件事两处口径不一致 ⇒ 凭证中心
    /// 少提示"锁端落到别名 #N"。改成把 extra 交回调用方。
    private func applyItem(_ item: CredQueueItem) async throws -> String {
        try await CredentialOrg.sendQueued(mac, app.lock, item)
    }
    private func itemTime(_ t: Double) -> String {
        guard t > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}

// ================= 348 统一延期 sheet =================
struct CredExtendView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var aliases: [Int]
    var onDone: () -> Void
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(30 * 86400)
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("统一延期 (\(aliases.count) 条, 348)") {
                    DatePicker("生效", selection: $from, displayedComponents: .date)
                    DatePicker("延期至", selection: $to, in: from..., displayedComponents: .date)
                    Text("将一次性改写所选密码的过期字段并列出变更清单; 锁端改期记为「待下发」。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("变更清单") {
                    ForEach(aliases, id: \.self) { a in
                        if let p = DB.getPwd(mac, a) {
                            HStack(spacing: DS.Space.s) {
                                Text("#\(a)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                Text(p.to.prefix(10) + " → " + to.formatted(.dateTime.year().month().day()))
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                Section {
                    BusyButton(title: "延期并登记待下发", isBusy: busy) {
                        Task { await apply() }
                    }
                }
            }
            .navigationTitle("统一延期")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { onDone() }
            } }
        }
    }

    private func apply() {
        busy = true
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let out = CredentialOrg.batchExtend(mac, aliases, f.string(from: from), f.string(from: to))
        busy = false
        app.showToast("已改写 \(out.count) 条有效期, 锁端改期待下发")   // 348 已改写
        _ = Milestones.recordOrganize()
        onDone()
    }
}

// ================= 349 批量移交 sheet =================
struct CredTransferView: View {
    @EnvironmentObject var app: AppState
    var mac: String
    var pwdAliases: [Int]
    var fpBatches: [Int]
    var onDone: () -> Void
    @State private var target: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("批量移交 (\(pwdAliases.count + fpBatches.count) 条, 349)") {
                    Picker("移交给", selection: $target) {
                        Text("解除归属").tag(nil as String?)
                        ForEach(DB.members()) { m in
                            Text(m.name).tag(m.id as String?)
                        }
                    }
                    .pickerStyle(.inline)
                    Text("批量改归属并各写一条本地记录; 锁端无归属字段, 移交只作用于本机台账。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Button("确认移交") {
                        let n = CredentialOrg.batchTransfer(mac, pwdAliases: pwdAliases, fpBatches: fpBatches, to: target)
                        app.showToast("已移交 \(n) 条" + (target.map { " → " + (DB.member($0)?.name ?? "") } ?? " → 无归属"))
                        _ = Milestones.recordOrganize()
                        onDone()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DS.Hit.min)
                }
            }
            .navigationTitle("批量移交")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { onDone() }
            } }
        }
    }
}

// ================= 353 批量停用摘要确认页 =================
struct CredDisableSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    var pwdAliases: [Int]
    var fpBatches: [Int]
    var onDone: () -> Void
    /// 313 停用必填原因: 空值 = 确认按钮不可点 (不给默认值, 免得"默认原因"变成假记录)
    @State private var reason = ""
    /// 367 写入成员动态: 默认关 —— 默认往别人的档案页写一条东西, 等于未经确认改数据
    @State private var writeToFeed = false
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
    /// 没归属的那几条: 它们不进任何人的动态, 这句话得能在界面上说出来。
    private var unownedCount: Int {
        max(0, (pwdAliases.count + fpBatches.count) - ownerCounts.reduce(0) { $0 + $1.pwd + $1.fp })
    }
    /// 367 勾选行文案。「另有 0 条无归属」是把界面写成噪音, 所以只在真有的时候才出现那一半。
    private var feedToggleLabel: String {
        let head = "写入该成员动态 (367 · 影响 \(ownerIds.count) 位成员, 各写自己名下的条数)"
        return unownedCount > 0 ? head + "; 另有 \(unownedCount) 条无归属, 不进任何人的动态" : head
    }

    var body: some View {
        NavigationStack {
            List {
                Section("停用摘要") {   // 353 停用摘要
                    HStack(spacing: DS.Space.s) {
                        // 影响成员头像列 (成员色点 183 风格, 纯本地) —— 名单见 ownerCounts, 顺序稳定
                        ForEach(ownerIds, id: \.self) { id in
                            if let m = DB.member(id) {
                                Circle()
                                    .fill(DS.Palette.accentText)
                                    .frame(width: 26, height: 26)
                                    .overlay(Text(String(m.name.prefix(1)))
                                        .font(.caption2)
                                        // accentText 在深色模式是浅紫, 白首字母压上去几乎看不见
                                        .foregroundStyle(DS.Palette.onAccent)
                                        .lineLimit(1))
                                    .accessibilityLabel("成员 \(m.name)")
                            }
                        }
                        Text("影响 \(ownerIds.count) 位成员")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("密码 \(pwdAliases.count) 条 · 指纹 \(fpBatches.count) 条")
                            .font(.subheadline.weight(.semibold))
                        ForEach(pwdsLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        ForEach(fpLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                Section {
                    Text("不可逆说明: 停用后本机台账移除, 锁端删除记为「待下发」— 7 天内可一键恢复, 超期需重新录入/生成。")   // 364 不可逆说明
                        .font(.caption)
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
                            .font(.caption.weight(on ? .semibold : .regular))
                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.s)
                            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                            .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .contentShape(Rectangle())
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("停用原因\(reason.isEmpty ? ", 未选择" : "")")   // 313 停用原因
                    if reason.isEmpty {
                        Text("先选一个停用原因才能继续 — 原因只写进本机审计与运行日志，不会发给门锁。")
                            .font(.caption2).foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 367: 原句就是「勾选写入该成员动态」。勾上之后按归属各写一条 (每人只看到自己名下的条数),
                    // 不勾则维持改动前那一条汇总流水 —— 两种形态各写各的, 绝不双写:
                    // 同一件事在敏感流水里出现两行, 388 那个视图就会把一次停用数成两次。
                    if !ownerIds.isEmpty {
                        Toggle(feedToggleLabel, isOn: $writeToFeed)
                            .font(.footnote)
                    }
                    // 353 二次点确认: 摘要页(一次) + 破坏性按钮(二次)
                    Button {
                        let label = Self.reasons.first { $0.0 == reason }?.1 ?? "其他"
                        let n = pwdAliases.count + fpBatches.count
                        // 只记条数与原因: 口令明文与指纹特征绝不进日志 (AUTOOPEN-PLAN §1 同一纪律)
                        app.lock.log("info", "停用 \(n) 条凭证 · 原因 \(label)")   // 313 停用
                        if writeToFeed {
                            for o in ownerCounts {
                                SensitiveLedger().record("停用·\(label)", target: "密码 \(o.pwd) / 指纹 \(o.fp)", member: o.id)
                            }
                        } else {
                            SensitiveLedger().record("停用·\(label)", target: "密码 \(pwdAliases.count) / 指纹 \(fpBatches.count)")
                        }
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
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
            }
            .navigationTitle("批量停用确认")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            // 取消 = 只退出, 绝不触发 onDone (调用方 CredentialsView 的 onDone 即 finishDisable, 执行停用与入回收站)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            } }
        }
    }

    private var pwdsLines: [String] {
        DB.getPwdList(pwdAliases, mac).prefix(6).map { "#\($0.alias) · \(CredentialOrg.countdown($0))" }
    }
    private var fpLines: [String] {
        DB.getFpList(fpBatches, mac).prefix(6).map { "「\($0.name)」" }
    }
}
