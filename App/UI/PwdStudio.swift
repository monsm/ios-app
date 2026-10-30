// 密码工坊（添加/编辑 4 步向导）
// 2026-10-29 从 CredentialStudio.swift 拆出。703 行，后续可再按步骤拆
import SwiftUI
import UIKit
import AVFoundation

struct PwdStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    /// true = 由外部 NavigationStack push (不自带导航栏); false = sheet 呈现自带导航栏
    var embedded: Bool = false
    /// 编辑对象: nil = 新增
    var editAlias: Int? = nil

    // 515 分步: 0 类型与归属 / 1 码值 / 2 有效期与备注 / 3 确认
    @State var step = 0
    @State var kind: Int = 0            // 0 长期 / 1 临时
    @State var owner: String? = nil
    @State var pwd = ""
    @State var from = Date()
    // 到期的初始值必须是**一个真窗口**：原先写成 `Date()`，于是新建临时码进到这步时
    // 生效与到期是同一分钟 (0 秒窗口)，界面显示"生效 15:37 · 到期 15:37"这种没人会要的默认。
    // 那时 519 不在这里拦，而是等按下"下一步"时**悄悄把 to 补成 from + 1 小时** —— 用户没选过的值被系统改了。
    // 那处补值本轮已删 (改成真拦, 见文件里的 navBar)，所以这里的初值就是唯一的到期默认值,
    // 全页不再有第二处替用户改时刻的地方。
    @State var to = Date().addingTimeInterval(3600)   // 828 问号里承诺的默认值就是这个, 别两处各说一套
    @State var note = ""
    @State var useTemplate = true
    @State var periodHelp = false     // 828 字段旁问号展开的说明块
    @State var busy = false
    // 519 错误字段: 只做**当前这一步之内**的字段标题变红 + 字段下方 errorLine 同步。
    // 刻意不承诺"滚动定位到首个错误字段" —— 这一页是 VStack 直排 (form 里没有 ScrollView),
    //   没有可用的滚动容器与锚点, 那句写出来就是假话; 而步间真拦已经保证坏值出不了当前这一步,
    //   所以"停在当前步 + 红字 + 字段下方一行"就是这一版能兑现的全部, 不多许。
    @State var errorField: String = ""
    // 301 剪贴板来源条
    @State var clipSource = false
    @State var showDraftBar = true
    @State var submitted = false   // 518: 提交成功不许回存废稿
    // 521 二次输入确认: 保存前重输码值核对 (恒开; 原开关在设置-安全页, 该页已删)
    @State var confirmPwd = ""
    var mac: String { app.current?.mac ?? "" }
    var editing: LedgerPwd? { editAlias.flatMap { DB.getPwd(mac, $0) } }

    var pwdOK: Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }

    var body: some View {
        Group {
            if embedded {
                form
            } else {
                NavigationStack { form }
            }
        }
    }

    var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            StepDots(total: 4, index: step, labels: ["类型归属", "码值", "有效期", "确认"])
            if showDraftBar, let d = CredentialOrg.draft(mac), editAlias == nil { draftBar(d) }
            if step == 0 { step0 }
            if step == 1 { step1 }
            if step == 2 { step2 }
            if step == 3 { step3 }
            navBar
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Gradient.screen.ignoresSafeArea())
        .navigationTitle(editing == nil ? "添加密码" : "改造密码 #\(editAlias ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
            Button("关闭") {
                saveDraft()
                if !embedded { dismiss() }
            }
        } }
        .onAppear {
            checkClipboard()
            // 2026-10-30 修复（第 115 轮，**改造模式静默丢改动**）：本页从不把 `editing` 回填到 @State ——
            // 于是「改造密码」时第 0 步默认「长期密码」、第 2 步不显示有效期，提交时又用 `e.from`/`e.to` 原窗口，
            // 用户在第 0/2 步做的任何改动都被忽略（而界面上看着是改成功了）。
            if let e = editing {
                kind = e.temp ? 1 : 0
                owner = e.owner
                pwd = e.pwd ?? ""
                if let d = DF.stamp.date(from: e.from) { from = d }
                if let d = DF.stamp.date(from: e.to) { to = d }
                note = e.note
            }
        }
        .onDisappear { saveDraft() }   // 518: 侧滑/push 退出也留稿
    }

    // ---------- 518 草稿续填横条 ----------
    func draftBar(_ d: CredentialOrg.StudioDraft) -> some View {
        HStack(spacing: DS.Space.s) {
            Label("上次填到第 \(d.step + 1) 步， 继续?", systemImage: "arrow.triangle.branch")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.warn)
            Spacer(minLength: 0)
            Button("继续") { restoreDraft(d); showDraftBar = false }
                .vkFont(.caption, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            Button {
                CredentialOrg.clearDraft(mac)
                showDraftBar = false
            } label: {
                Text("丢弃")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .variantCallout(DS.Palette.warn, .control, wash: 0.10)
        // 2026-10-30 修复（第 116 轮，**无障碍**）：原来是 `children: .combine` —— 会把「继续」与「丢弃」
        // 两个 Button 合并成**一个**无障碍元素，读屏只剩一句朗读，两个动作都激活不了。
        // 改成 `.contain`：容器仍读那句说明，两个按钮各自可聚焦可点。
        .accessibilityElement(children: .contain)
        .accessibilityLabel("草稿续填： 上次填到第 \(d.step + 1) 步， 点继续可回填")   // 518 草稿续填
    }

    // ---------- 515/317 step0 类型与归属 ----------
    @ViewBuilder

    // ---------- 515 导航条 ----------
    var navBar: some View {
        HStack(spacing: DS.Space.s) {
            if step > 0 {
                Button("上一步") {
                    withAnimation(DS.Motion.quick) { step -= 1 }
                }
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step < 3 {
                Button(step == 0 ? "下一步： 码值" : (step == 1 ? "下一步： 有效期" : "下一步： 确认")) {
                    if step == 0, owner == nil, !DB.members().isEmpty {
                        errorField = "owner"
                        app.showToast("先选归属成员")   // 317 先选归属成员
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    if step == 1, !pwdOK {
                        errorField = "value"
                        app.showToast("码值需 6~8 位数字")   // 519 码值需
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    // 519 步间真拦: 原先这一支是 `to = from + 1h` —— 静默把用户没选过的值改掉,
                    // 然后带着一个他自己没填的时刻进确认步, 界面上显示的仍是补出来的那个。
                    // 现在停在这一步: toast + 触感 + errorField 同步 (字段下方那行 errorLine 已经在按 to<=from 显示)。
                    if step == 2, kind == 1, to <= from {
                        errorField = "period"
                        app.showToast("到期要晚于生效， 请先点一枚快捷档")   // 519 到期要晚于生效
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    saveDraft()
                    withAnimation(DS.Motion.quick) { step += 1; errorField = "" }
                    DS.Haptics.tick.impactOccurred()
                }
                .vkFont(.subheadline, weight: .semibold)
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
    }

    func checkClipboard() {
        guard editAlias == nil else { return }
        guard let s = UIPasteboard.general.string else { return }
        let digits = s.filter { $0.isNumber }
        if digits.count >= 6, digits.count <= 8, pwd.isEmpty {
            pwd = digits
            clipSource = true
        }
    }
    func restoreDraft(_ d: CredentialOrg.StudioDraft) {
        step = d.step
        kind = d.kind
        pwd = d.pwd
        note = d.note
        useTemplate = d.useTemplate
        owner = d.owner
        if let f = CredentialOrg.parseLocal(d.fromISO) { from = f }
        if let t = CredentialOrg.parseLocal(d.toISO) { to = t }
        app.showToast("已回填草稿")   // 518 已回填草稿
    }
    func iso(_ d: Date) -> String {
        let f = DF.stamp
        return f.string(from: d)
    }
    func saveDraft() {
        guard !submitted, editAlias == nil, step > 0 || !pwd.isEmpty else { return }
        CredentialOrg.saveDraft(mac, CredentialOrg.StudioDraft(
            step: step, kind: kind, pwd: pwd, permanent: kind == 0,
            fromISO: iso(from), toISO: iso(to), owner: owner,
            useTemplate: useTemplate, note: note, batch: 0,
            at: Date().timeIntervalSince1970))
    }

    // ---------- 提交 (既有协议 0A/原位改写; 178 批量另在临时码工坊) ----------
    func submit() async {
        guard let kc = app.current, !busy else { return }
        // 519 兜底拦: 步间真拦只管"点下一步"那一下, 而 518 草稿回填 (restoreDraft) 会把 step 直接放回
        // 第 4 步, 字段是上一次会话填的 —— 那几条坏值不经任何一步就坐到提交按钮前面。
        // 所以这里按步序再核一遍, 缺什么就回跳到对应那一步并写 errorField, 不带着坏值去发 0A。
        if owner == nil, !DB.members().isEmpty {
            step = 0
            errorField = "owner"
            app.showToast("先选归属成员")
            DS.Haptics.trigger.impactOccurred()
            return
        }
        guard pwdOK else {
            step = 1
            errorField = "value"
            app.showToast("码值需 6~8 位数字")   // 519 码值需
            DS.Haptics.trigger.impactOccurred()
            return
        }
        if kind == 1, to <= from {
            step = 2
            errorField = "period"
            app.showToast("到期要晚于生效： 草稿里的这一档已过期， 请重选")   // 519 到期要晚于生效
            DS.Haptics.trigger.impactOccurred()
            return
        }
        busy = true
        defer { busy = false }
        let f = DF.stamp
        let isTemp = kind == 1
        let fromS = isTemp ? iso(from) : "2010-01-01 00:00:00"
        let toS = isTemp ? iso(to) : "2118-01-01 00:00:00"
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            var finalNote = note
            if useTemplate, finalNote.isEmpty {
                let who = CredentialOrg.ownerName(owner).isEmpty ? "未归属" : CredentialOrg.ownerName(owner)
                finalNote = who + "-大门-" + (isTemp ? (from.formatted(.dateTime.month().day()) + "-" + to.formatted(.dateTime.month().day())) : "长期")
            }
            let alias: Int
            if let e = editing, let oldAlias = editAlias {
                alias = try await app.lock.pwdModify(alias: oldAlias, pwd: pwd, validFrom: e.from, validTo: e.to)
                if alias != oldAlias {
                    // 确认口径：不是删除动作，是**换槽**。锁端 0A 改写后把这条挪到了新槽，旧槽在锁里已经不存在；
                    // 紧跟着的 addPwd 用同一份值/时段/归属把台账补回新槽，账上没有任何东西被丢掉 ⇒ 无后果可预告，不问。
                    DB.delPwd(kc.mac, oldAlias)
                    DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: e.from, to: e.to, temp: e.temp,
                                                at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: finalNote))
                } else {
                    DB.rePwd(kc.mac, alias, pwd)
                    DB.setPwdNote(kc.mac, alias, finalNote)
                    DB.setPwdOwner(kc.mac, alias, owner)
                }
            } else {
                alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: fromS, validTo: toS)
                DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: fromS, to: toS, temp: isTemp,
                                             at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: finalNote))
            }
            CredentialOrg.clearDraft(kc.mac)
            showDraftBar = false
            submitted = true   // 518
            app.flashReceipt("已写入本机")   // 508 已写入本机
            app.showToast(isTemp ? "临时码已下发" : "密码已下发 (别名 #\(alias))")
            if !embedded { dismiss() }
        } catch {
            app.showToast("下发失败： " + error.localizedDescription)
        }
    }

    func errorLine(_ s: String) -> some View {
        Label {
            Text(s).vkFont(.caption).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: DS.Icon.sm, weight: .medium))
        }
        .vkFont(.caption)
        .foregroundStyle(DS.Palette.danger)
        .accessibilityLabel(s)
    }
}
