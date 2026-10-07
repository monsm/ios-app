// 包6 凭证中心 — 回收站 / 版本历史·diff / 月历 / 整理建议 / 下发队列 / 批量操作 sheet
// 全部本地数据层 (CredentialOrg.kf_* 表), 不新增协议命令; 需下发锁端的操作
// (还原即重新下发 504 / 批量停用 353) 保持"待下发"语义, UI 明示本地意图。
// 落点: 凭证 Tab 内的 NavigationLink 与批量操作栏; 不经过 vendor/。
import SwiftUI
import UIKit
import LocalAuthentication

// ================= 入口 (从凭证 Tab 进入, 按 section 路由) =================
struct CredCenterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    var section: String   // "bin" / "histAll" / "queue" / "organize"

    var body: some View {
        NavigationStack {
            List {
                centerRow(icon: "trash", title: "回收站", sub: "\(CredentialOrg.bin(mac).count) 条 · 保留 \(CredentialOrg.reclaimDays()) 天 (497)") {
                    CredBinView(mac: mac)
                }
                centerRow(icon: "clock.arrow.circlepath", title: "版本历史", sub: "保存自动快照 + 恢复即新版本 (487/496)") {
                    CredHistoryListView(mac: mac)
                }
                centerRow(icon: "rectangle.3.offgrid", title: "整理建议中心", sub: "\(CredentialOrg.advice(mac).count) 条待办 (358/505)") {
                    CredOrganizeView(mac: mac)
                }
                centerRow(icon: "arrow.down.circle", title: "待下发队列", sub: "\(CredentialOrg.pendingQueue(mac).count) 项 · 到场补发 (365)") {
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
    @State private var source: Int = -1       // 498 来源过滤: -1 全部
    @State private var query = ""
    @State private var pendingPurge: CredBinEntry?

    var body: some View {
        List {
            // 500 容量头行: 条数 + 下次自动清理日期
            let header = CredentialOrg.binHeader(mac)
            Section {
                HStack {
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
                TextField("搜索已删项 (503)", text: $query)
                    .autocorrectionDisabled()
                    .accessibilityLabel("回收站搜索")
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
                    Button("整组还原 (501, 可整组找回)") {
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
                Button("清空回收站 (502 双验)", role: .destructive) {
                    pendingPurge = nil
                    purgeAll()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DS.Hit.min)
            } footer: {
                Text("彻底删除不可找回。保留期可在 设置-安全-凭证整理 调整 (497)。")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .navigationTitle("回收站")
        .scrollContentBackground(.hidden)
        .dsScreenBackground()
    }

    private var rows: [CredBinEntry] {
        var list = CredentialOrg.bin(mac)
        if source >= 0 { list = list.filter { $0.source == source } }
        if !query.isEmpty {
            list = list.filter {
                let hay = "\($0.pwd?.alias.map { "密码 #\($0)" } ?? "") \($0.fp?.name ?? "") \($0.pwd?.note ?? "")"
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
                    app.showToast(CredentialOrg.restoreBin(mac, entry: e, asCopy: true) + " (499)")
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
        .confirmationDialog("彻底删除? (502 双验)", isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }), titleVisibility: .visible) {
            Button("输入确认", role: .destructive) {
                if let x = pendingPurge {
                    CredentialOrg.purgeBin(mac, id: x.id)
                    app.showToast("已彻底删除 (指纹无法再录入; 密码值可再生成)")
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
        return Int((e.at + keep - CredentialOrg.nowSec) / 86400)
    }

    private func restore(_ e: CredBinEntry) {
        // 504 还原即重新下发: 在用 (未过期) 密码还原后询问"立即重新下发"
        var msg = CredentialOrg.restoreBin(mac, entry: e, asCopy: false)
        if let p = e.pwd, CredentialOrg.expiryDate(p).map({ $0.timeIntervalSinceNow > 0 }) == true {
            let alert = UIAlertController(title: "重新下发到锁? (504)",
                                         message: "「\(e.text)」仍在有效期, 还原后锁端该密码已删除, 需重新下发一次才可用。",
                                         preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "立即重新下发", style: .default) { _ in
                CredentialOrg.enqueue(mac, kind: "restore", title: "重新下发 \(e.text)")
                app.showToast("已加入待下发队列, 到场连接锁后点「重试」")
            })
            alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
            UIApplication.topViewController()?.present(alert, animated: true)
            msg += " · 已询问重新下发"
        }
        app.showToast(msg)
    }

    private func purgeAll() {
        let n = CredentialOrg.bin(mac).count
        guard n > 0 else { return }
        // 502 双验: 先生物识别 (无生物则走双确认弹窗), 二次确认后清空
        let ev = LAContext()
        ev.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "彻底删除回收站 \(n) 条") { ok, _ in
            DispatchQueue.main.async {
                if ok {
                    doPurgeAll()
                } else {
                    confirmDestructive("彻底清空回收站", "生物识别未通过。仍要彻底清空 \(n) 条已删凭证? 不可找回 (指纹需到锁前重新录入)。", confirmTitle: "清空") {
                        doPurgeAll()
                    }
                }
            }
        }
    }
    private func doPurgeAll() {
        CredentialOrg.saveBin(mac, [])
        app.showToast("已清空回收站 (505 计入整理)")
        _ = Milestones.recordOrganize()
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
                        HStack {
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
                        HStack {
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
                    Text("还没有快照。改动密码值 / 备注 / 归属 / 改期时会自动留档 (487), 每凭证保留 \(CredentialOrg.quota(mac)) 版 (491)。")
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

    private var title: String {
        if kind == "pwd" { return CredentialOrg.displayPwd(DB.getPwd(mac, key) ?? LedgerPwd(alias: key, from: "2010-01-01 00:00:00", to: "2118-01-01 00:00:00", temp: false, at: 0)) }
        if let f = DB.getFp(mac, key) { return "指纹「\(f.name)」" }
        return kind == "pwd" ? "密码 #\(key)" : "指纹批次 \(key)"
    }

    var body: some View {
        List {
            if let pv = preview {
                previewSection(pv)
            }
            Section("历史 (\(snaps.count + reloadTick - reloadTick), 保留 \(CredentialOrg.quota(mac)) 版)") {
                ForEach(snaps) { s in
                    snapRow(s)
                }
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
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Image(systemName: s.starred ? "star.fill" : "star")
                        .font(.system(size: DS.Icon.md, weight: .medium))
                        .foregroundStyle(s.starred ? DS.Palette.warn : DS.Palette.textSub)
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(s.starred ? "取消星标版本" : "星标此版本 (495)")
            }
            Text(s.relTime)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
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
                Button("看差异") { diffFrom = s.version }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                Button(preview == s.version ? "退出预览" : "回看此版 (493)") {
                    preview = (preview == s.version) ? nil : s.version
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("恢复到 v\(s.version)") {
                    // 496 恢复即新版本: 不覆盖, 新增 "恢复自 vX" 快照
                    CredentialOrg.restore(mac, kind: kind, key: key, from: s)
                    app.showToast("已恢复 v\(s.version), 生成新版本 (496)")
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
        // 489 对比基线: 选中 "看差异" 的版本与它比, 否则与上一版比
        let target = diffFrom ?? s.version - 1
        return CredentialOrg.history(mac, kind, key).first { $0.version == target }
    }
    @ViewBuilder
    private func previewSection(_ v: Int) -> some View {
        let s = CredentialOrg.history(mac, kind, key).first { $0.version == v }
        if let s {
            Section("只读预览 v\(v) (493)") {
                Text(CredentialOrg.summaryText(of: s))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Text("顶栏「回到此版」= 按此版生成新档 (496), 不覆盖历史。")
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
        let cal = Calendar.current
        let year = cal.component(.year, from: ym)
        let month = cal.component(.month, from: ym)
        let dl = CredentialOrg.monthDeadlines(mac, year: year, month: month)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack {
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
                    let first = cal.date(from: DateComponents(year: year, month: month, day: 1))!
                    let lead = (cal.firstWeekday + 6 - cal.component(.weekday, from: first)) % 7
                    let days = cal.range(of: .day, in: .month, for: ym)!.count
                    var cells: [Int?] = Array(repeating: nil, count: lead)
                    cells.append(contentsOf: 1...days)
                    while cells.count % 7 != 0 { cells.append(nil) }
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
                                HStack {
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

    private var weekdayHeaders: [String] { ["日", "一", "二", "三", "四", "五", "六"] }

    @ViewBuilder
    private func dayCell(year: Int, month: Int, day: Int, count: Int) -> some View {
        let d = Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
        let isToday = Calendar.current.isDateInToday(d)
        let isPicked = picked.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false
        Button {
            picked = isPicked ? nil : d
            if !isPicked { onPick(d) }
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
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
    private func move(_ delta: Int) {
        ym = Calendar.current.date(byAdding: .month, value: delta, to: ym) ?? ym
    }
}

// ================= 358/505 整理建议中心 =================
struct CredOrganizeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                let adv = CredentialOrg.advice(mac)
                Section("整理建议 (358)") {
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
                    Text("「回收站 N 条」直达回收站 (505); 其余建议回凭证列表点「选择」, 再用「智能选取 · 已过期/同类型」套用对应集合 (350)。")
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
        app.showToast("回凭证列表点「选择」, 用「智能选取」套用「\(a.title)」对应集合 (350)")
        onDone()
    }
}

// ================= 365 待下发队列 (本地容错步条) =================
struct CredQueueView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var mac: String
    @State private var busy: Int? = nil

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
                            Text("第 \(item.attempt) 次尝试 · \(ItemTime(item.lastAt))")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button("全部重试 (按序)") {
                    Task {
                        for item in q {
                            busy = item.id
                            do {
                                try await app.lock.ensureConnected(mac: mac)
                                try await applyItem(item)
                                CredentialOrg.markQueue(mac, id: item.id, state: .done, note: item.title + " · 锁端确认")
                            } catch {
                                CredentialOrg.markQueue(mac, id: item.id, state: .failed, note: item.title + " · 失败: " + error.localizedDescription)
                            }
                            busy = nil
                        }
                        app.showToast("已逐条重试 \(q.count) 项")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
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
        HStack(spacing: 3) {
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
        busy = item.id
        Task {
            defer { busy = nil }
            do {
                try await app.lock.ensureConnected(mac: mac)
                try await applyItem(item)
                CredentialOrg.markQueue(mac, id: item.id, state: .done, note: item.title + " · 锁端确认")
                app.showToast("\(item.title) 已下发")
            } catch {
                CredentialOrg.markQueue(mac, id: item.id, state: .failed, note: item.title + " · 失败: " + error.localizedDescription)
                app.showToast("重试失败: \(error.localizedDescription)")
            }
        }
    }
    private func applyItem(_ item: CredQueueItem) async throws {
        switch item.kind {
        case "del_pwd":
            try await app.lock.pwdDelete(item.pwd?.alias ?? 0)
        case "del_fp":
            try await app.lock.fpDelete(UInt32(item.fp?.batch ?? 0))
        case "period":
            if let p = item.pwd, !item.newFrom.isEmpty {
                try await app.lock.pwdExpire(p.alias, item.newFrom, item.newTo)
            }
        case "restore":
            if let p = item.pwd, let v = p.pwd { _ = try await app.lock.pwdAdd(pwd: v, validFrom: p.from, validTo: p.to) }
        default:
            break
        }
    }
    private func ItemTime(_ t: Double) -> String {
        guard t > 0 else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
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
                            HStack {
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
        app.showToast("已改写 \(out.count) 条有效期, 锁端改期待下发 (348)")
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

    var body: some View {
        NavigationStack {
            List {
                Section("停用摘要 (353)") {
                    HStack(spacing: DS.Space.s) {
                        // 影响成员头像列 (成员色点 183 风格, 纯本地)
                        let ownerIds = Array(Set(
                            DB.getPwdList(pwdAliases, mac).compactMap { $0.owner } +
                            DB.getFpList(fpBatches, mac).compactMap { $0.owner }
                        ))
                        ForEach(ownerIds, id: \.self) { id in
                            if let m = DB.member(id) {
                                Circle()
                                    .fill(DS.Palette.accentText)
                                    .frame(width: 26, height: 26)
                                    .overlay(Text(String(m.name.prefix(1)))
                                        .font(.caption2)
                                        .foregroundStyle(.white)
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
                    Text("不可逆说明: 停用后本机台账移除, 锁端删除记为「待下发」— 7 天内可一键恢复 (364), 超期需重新录入/生成。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    // 353 二次点确认: 摘要页(一次) + 破坏性按钮(二次)
                    Button {
                        onDone()
                        dismiss()
                    } label: {
                        Text("确认停用 (\(pwdAliases.count + fpBatches.count) 条)")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(DestructiveActionStyle())
                    .accessibilityHint("已展示影响成员与不可逆说明, 点按即执行停用")
                }
            }
            .navigationTitle("批量停用确认")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    onDone()
                    dismiss()
                }
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
