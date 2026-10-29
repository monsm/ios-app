// 密码详情
// 2026-10-29 从 CredentialStudio.swift 拆出
import SwiftUI
import UIKit
import AVFoundation

struct PwdDetailStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let alias: Int
    @State private var renewing = false
    @State private var copiedFlash = false   // 11 复制按钮形变
    private var mac: String { app.current?.mac ?? "" }
    private var p: LedgerPwd? { DB.getPwd(mac, alias) }

    var body: some View {
        if let p = p {
            NavigationStack {
                List {
                    // 2026-10-29 补（**后台有实现、前台零调用**）：`CredentialOrg.disableMarkText`
                    // 返回「停用原因 X · MM-dd HH:mm · via」。停用过的凭证在详情页看不到原因，
                    // 用户只看到列表里一条灰行、不知道为什么。这里补一行如实回显（没标记就不显示，不编）。
                    if let mark = CredentialOrg.disableMarkText(mac, kind: "pwd", key: p.alias) {
                        Section {
                            Label {
                                Text(mark).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "pause.circle.fill")
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                    }
                    // 331 提前失效到点: 顶部提醒条 (本地提示, **不自动下发停用**)
                    if p.temp, CredentialOrg.isEarlyExpired(mac, p, Date()) {
                        Section {
                            Label {
                                Text("已过本机设定的提前失效时刻 — 这一条只是提示: 没有向门锁发过任何停用或改期命令, "   // 331 已过本机设定的提前失
                                     + "门锁在它自己那份到期时刻之前照样能开门。要真停用, 得走列表里的停用或改期。")
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "bell.z.fill")
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.06))
                    }
                    Section("码值 (默认打码, 点位揭示)") {
                        if let v = p.pwd {
                                MaskedDigits(value: v, big: true)
                        } else {
                            Text("当时未留存明文, 可在锁上核对后回填")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let v = p.pwd {
                            HStack(spacing: DS.Space.xs) {
                                Button {
                                    Clip.set(v)   // 405
                                    app.showToast("已复制")
                                    // 11 形变: 按下 1.2 秒内按钮变成"已复制 + 对勾", 给一次按下确认
                                    withAnimation(DS.Motion.standard) { copiedFlash = true }
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.2))
                                        withAnimation(DS.Motion.standard) { copiedFlash = false }
                                    }
                                } label: {
                                    Label(copiedFlash ? "已复制" : "复制",   // 11 复制
                                          systemImage: copiedFlash ? "checkmark" : "doc.on.doc")
                                        .vkFont(.caption, weight: .medium)
                                }
                                .buttonStyle(.bordered)
                                .frame(minHeight: DS.Hit.min)
                                    .vkFont(.caption, weight: .medium)
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: DS.Hit.min)
                                    .accessibilityHint("逐位语音播报, 便于电话转述")
                                Spacer(minLength: 0)
                            }
                            // 308 4 位分段转述: 点任一块只复制该块
                            if v.count >= 8 {
                                HStack(spacing: DS.Space.s) {
                                    ForEach(Array(v.chunked(4).enumerated()), id: \.offset) { i, c in
                                        Button {
                                            Clip.set(c)   // 405 分段也是口令明文的一部分
                                            app.showToast("已复制第 \(i * 4 + 1)~\(min(i * 4 + 4, v.count)) 位")
                                        } label: {
                                            Text(c)
                                                .vkFont(.title3.monospacedDigit(), weight: .semibold)
                                                .foregroundStyle(DS.Palette.text)
                                                .frame(minHeight: DS.Hit.min)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("分段 \(i + 1): \(c), 点按只复制该段")   // 308 分段
                                    }
                                }
                            }
                        }
                    }
                    // 359/930 到期预警五档: 与列表侧同键 (kf_calert_) —— 读写都经 CredentialOrg.alert/saveAlert,
                    // 详情页不另存 @State (防双源漂移)。930 替代落地后 h2 档也排通知了,
                    // 列表提醒行不动 —— 前台那条行仍然有用, 只是不再是 h2 的唯一出口。
                    if CredentialOrg.expiryDate(p) == nil {
                        Section("到期预警") {   // 359 到期预警
                            Text("长期有效密码无到期点, 三档预警不适用。")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Section("到期预警") {   // 359 到期预警
                            VariantToggle("到期前 7 天提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).day },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.day = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            VariantToggle("到期前 3 天提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).d3 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.d3 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            VariantToggle("到期前 1 天提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).d1 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.d1 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            VariantToggle("到期前 24 小时提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).h24 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.h24 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            VariantToggle("到期前 2 小时提醒 (通知 + 列表提醒行)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).h2 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.h2 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            Text("五档 (7/3/1 天 · 24/2 小时) 都排本地通知, 另有一条「到期时」通知自动跟着走; "
                                 + "2 小时档同时还在凭证列表插提醒行。近 7 天到期条数会显示在凭证 Tab 角标上。"   // 930 小时档同时还在凭证列
                                 + "开关只存本机, 与锁端无关。")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // 331 提前失效滑杆: 本地意图, 不改协议; 到点**只在本页**提示 (顶部提醒条 + 状态行标注),
                    // 不自动下发停用。副文案原先承诺"临近失效的列表行将挂渐进色条" —— 列表侧没做, 已撤。
                    if p.temp {
                        Section("提前失效") {   // 331 提前失效
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                HStack(spacing: DS.Space.s) {
                                    Text("提前 \(CredentialOrg.earlyExpireMin(mac, p.alias)) 分钟失效")
                                        .vkFont(.subheadline)
                                        .foregroundStyle(DS.Palette.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                    Text("只在本页提示, 不改锁端")
                                        .vkFont(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .accessibilityLabel("这一档只影响本页的提示: 列表行没有色条, 也不会向门锁下发停用")
                                }
                                Slider(value: Binding(
                                    get: { Double(CredentialOrg.earlyExpireMin(mac, p.alias)) },
                                    set: { CredentialOrg.setEarlyExpireMin(mac, p.alias, Int($0)) }
                                ), in: 0...120, step: 5)
                                .tint(DS.Palette.accent)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("提前失效分钟数滑杆")   // 331 提前失效分钟数滑杆
                                Text("实话: 这枚滑杆在本机只存一个分钟数 —— 列表行没有渐进色条, 门锁那侧的到期时刻一个字都没改。"
                                     + "到点本页挂提醒条并在状态行标注, 要不要真停用仍由你决定。")   // 331 到点本页挂提醒条并在
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    // 330 装修黄条: 备注含「装修/工地」→ 详情页"施工中"角标
                    if p.temp, p.note.contains("装修") || p.note.contains("工地") {
                        Section {
                            HStack(spacing: DS.Space.s) {
                                Label("施工中", systemImage: "paintbrush.fill")   // 330 施工中
                                Spacer(minLength: 0)
                                StatusPill(text: "长期工", systemImage: "clock", tone: .warn)
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.08))
                    }
                    // 2026-10-27 四轮精简：用量刻度已删。
                    // 332 原码续期 (⚠ 过期码是否留存锁端未确证: 本地沿用原值改期 + 入队兜底, 标"约")
                    if p.temp, CredentialOrg.pwdState(p) == 2, p.pwd != nil {
                        Section {
                            Button {
                                Task { await renewExpired(p) }
                            } label: {
                                Label("续期 7 天 (原值沿用 · 锁端留存未确证)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                        }
                    }
                    Section("时段与归属") {
                        // 331: 状态行同步标注本机的提前失效档 (没设提前量时 earlyExpiryNote 回空串, 不说空话)
                        row("状态", CredentialOrg.stateLabel(CredentialOrg.pwdState(p)) + CredentialOrg.earlyExpiryNote(mac, p))
                        row("归属", CredentialOrg.ownerName(p.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(p.owner))
                        row("备注", p.note.isEmpty ? "无" : p.note)
                        // 2026-10-28 补入口：`CredentialOrg.pwdAgeDays` 早就实现了（按台账 `at` 算天数），
                        // 但全仓零调用 —— 用户看不到"这条密码用了多久"，也就无从判断该不该换。
                        // 未留存明文的老条目没有 at，返回 nil，此时不出这一行（不编造）。
                        if let age = CredentialOrg.pwdAgeDays(p) {
                            row("已用", age == 0 ? "今天新建" : "\(age) 天")
                        }
                    }
                    // 311 同码引用卡 (⚠ 按时间窗推断, 标"约")
                    Section("用它开过的门 (约)") {
                        let n = CredentialOrg.openCountInWindow(mac, p: p)
                        // 2026-10-28 补真入口：`CredentialOrg.recentUseCount` 实现了「近 N 天使用次数」
                        // （按时间窗命中开门日志推断，日志缺失返回 nil），但全仓零调用 —— 上次只接了
                        // pwdAgeDays，把它漏了。这条与上面那个「时间窗内次数」是两个口径：
                        // 上面看的是这条凭证的**有效期窗口**，这里看的是**最近 30 天**（"最近还在用吗"）。
                        if let recent = CredentialOrg.recentUseCount(mac, pwdAlias: p.alias) {
                            Label {
                                Text("近 30 天约 \(recent) 次")
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .accessibilityHidden(true)
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        }
                        if n > 0 {
                            Label {
                                Text("时间窗内约 \(n) 次开门 (按时间推断, 无 alias 字段)")
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "door.left.hand.open")
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        } else {
                            Text("暂无记录 (⚠ 按时间窗推断, 无数据不编造)")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    Section {
                        NavigationLink {
                            PwdStudio(embedded: true, editAlias: p.alias)
                        } label: {
                            Label("改造密码 (分屏对照 · 逐位高亮)", systemImage: "pencil")
                        }
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    }
                }
                .navigationTitle(CredentialOrg.displayPwd(p))
                .variantList()
                .dsScreenBackground()
                .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                } }
        // 2026-10-27 四轮精简：口述卡 sheet 已删。
            }
        } else {
            EmptyState(systemImage: "key.slash", title: "凭证不存在", message: "这条凭证可能已被删除（本机没有回收站，删除不可恢复）。")
        }
    }
    /// 332 原码续期 (⚠ 降级): 沿用原密码值改期 7 天, 走既有 0A 原位改写; 锁端未连则入队, 不新增协议
    private func renewExpired(_ p: LedgerPwd) async {
        guard let kc = app.current, let v = p.pwd, !renewing else { return }
        renewing = true
        defer { renewing = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fromS = f.string(from: Date())
        let toS = f.string(from: Date().addingTimeInterval(7 * 86400))
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let alias = try await app.lock.pwdModify(alias: p.alias, pwd: v, validFrom: fromS, validTo: toS)
            if alias != p.alias {
                // 确认口径：同 PwdStudio 编辑分支那条 —— 332 原码续期走锁端 0A 原位改写，返回新槽号时旧槽在锁里已不存在，
                //   下一行 addPwd 用同一个密码值把台账补到新槽，是换槽不是删除，所以不问。
                DB.delPwd(kc.mac, p.alias)
                DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: fromS, to: toS, temp: true,
                                            at: Date().timeIntervalSince1970 * 1000, pwd: v, owner: p.owner, note: p.note))
            } else {
                DB.setPwdPeriod(kc.mac, p.alias, fromS, toS)
            }
            app.showToast("已沿用原值续期 7 天")   // 332 已沿用原值续期
        } catch {
            // 用函数入口捕获的 kc.mac，不用**活读**的 `mac` 计算属性：两次 await 之间当前锁可能被
            // AppIntent / kf:// 深链改掉，那样成功路径写 A 锁、失败入队却指向 B 锁。
            app.showToast("锁未连接 —— 续期只在页面内生效，未写入门锁")   // 365 锁未连接
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(k)
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            Text(v)
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}