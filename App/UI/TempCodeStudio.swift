// 临时码工坊（ZOTP）
// 2026-10-29 从 CredentialStudio.swift 拆出
import SwiftUI
import UIKit
import AVFoundation

struct TempCodeStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var pwd = ""
    @State private var batchCount = 1      // 178 批量临时码
    @State private var batchFailed = 0          // 178 批量里失败几张（完成卡如实报）
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(3600)   // 同上: 默认窗口 1 小时, 与第一个快捷档一致
    @State private var owner: String? = nil
    @State private var note = ""
    @State private var clipSource = false
    @State private var result: LedgerPwd?
    @State private var busy = false

    private var mac: String { app.current?.mac ?? "" }
    private var lockName: String { app.displayName }
    private var pwdOK: Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }
    /// 327 租期重叠: 与同成员其它时间窗临时码的撞车
    private var overlaps: [LedgerPwd] {
        CredentialOrg.overlapWindows(mac, from: iso(from), to: iso(to), owner: owner, excluding: -1)
    }

    var body: some View {
        NavigationStack {
            if result == nil { addForm } else { doneCard }
        }
        .navigationTitle("临时码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
    }

    // ---------- 添加 (515 单页三段, 表单体验 516/520/522/523) ----------
    private var addForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                // 2026-10-27 四轮精简：五场景预设已删。

                // 码值 (301 剪贴板即建 + 303 回显 + 173 生成 + 522 扫号 + 516 数字键盘)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        Text("码值 (6~8 位数字)")
                            .vkFont(.footnote, weight: .semibold)
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                        Text(pwdOK ? "✓ 位数合规" : "6~8 位数字")
                            .vkFont(.caption2)
                            .foregroundStyle(pwdOK ? DS.Palette.ok : DS.Palette.textSub)
                            .lineLimit(1)
                        // 2026-10-29 补：`CredentialOrg.weakReason` 零调用 —— 位数合规只说明长度对，
                        // 111111 / 123456 这种仍然能过。这里把三条弱口令判据的结果如实提示（不评"强度分"）。
                        if pwdOK, let weak = CredentialOrg.weakReason(pwd) {
                            Text("⚠ \(weak)，建议换一个")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !pwd.isEmpty {
                        MaskedDigits(value: pwd, big: true)
                    }
                    TextField("输入码值， 或点「生成」", text: $pwd, prompt: Text("输入 6~8 位数字"))   // 516 输入
                        .keyboardType(.numberPad)
                        .vkFont(.title3.monospacedDigit(), weight: .semibold)
                        .frame(minHeight: DS.Hit.min)
                        .autocorrectionDisabled()
                    if clipSource {
                        HStack(spacing: DS.Space.xs) {
                            Label("来自剪贴板 · 已识别为候选码", systemImage: "doc.on.clipboard")   // 301 来自剪贴板
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                            Spacer(minLength: 0)
                            Button("清除") { pwd = ""; clipSource = false }
                                .vkFont(.caption, weight: .medium)
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, 4)
                        .variantCallout(DS.Palette.warn, .control, wash: 0.10)
                        .accessibilityLabel("码值来自剪贴板， 点清除可移除")
                    }
                    HStack(spacing: DS.Space.xs) {
                        Button("生成") {   // 173 生成
                            pwd = StudioTools.genDigits(6)
                            clipSource = false
                        }
                        .vkFont(.caption, weight: .medium)
                        .buttonStyle(.bordered)
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("本地生成 6 位随机码")   // 173 本地生成
                        Spacer(minLength: 0)
                    }
                    // 178 批量临时码 (锁端无批量命令, 走既有 0A 逐条, 失败逐条报)
                    HStack(spacing: DS.Space.xs) {
                        Text("一次生成")   // 178 一次生成
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        ForEach([1, 2, 3, 5], id: \.self) { n in
                            Button(String(n)) { batchCount = n }
                                .vkFont(.caption.weight(batchCount == n ? .semibold : .medium))
                                .buttonStyle(.bordered)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("批量 \(n) 张")   // 178 批量
                        }
                        Spacer(minLength: 0)
                    }
                    // 304 全库重复拦截: 本锁 + 其它锁各查一次 (此前只查本锁却写着"全库")
                    let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: -1) : []
                    let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
                    if !others.isEmpty {
                        Label("其它 \(others.count) 把锁上也有同值： " + others.prefix(3).joined(separator: "、")
                            + (others.count > 3 ? " 等" : ""), systemImage: "lock.rectangle.stack")   // 304 界面文案
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dups.isEmpty {
                        // 304 查看即跳: 不再只给一句"建议换一组", 真把同值那条的详情打开
                        HStack(spacing: DS.Space.xs) {
                            Label("本锁已有 \(dups.count) 条同值凭证， 建议换一组", systemImage: "plus.slash.minus")   // 304 本锁已有
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("查看") {
                                app.pendingCredNav = "pwd:\(dups[0].alias)"
                                app.pendingCredNavMac = mac
                                app.requestRoute(.credentials)   // 2026-10-15 走查: 同上, 统一走 requestRoute
                                dismiss()
                            }
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .card()

                // 时段 (520 快捷 + 327 重叠 + 330 装修黄条)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("生效时段")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    HStack(spacing: DS.Space.xs) {
                        quickPill("1 小时") { from = Date(); to = Date().addingTimeInterval(3600) }
                        quickPill("今天内") { from = Date(); to = TimeFormat.dayEnd() }   // 终点单一出口 (520/828)
                        // 2026-10-30 修复（日历日）：「7 天/30 天」的语义是**日历日**，
                        // 原实现用 24 小时×7/30 —— 夏令时切换日会差一小时（§10.33 同款）。
                        // 走 WeekCal.shifted（日历日唯一出口）。
                        quickPill("7 天") { from = Date(); to = WeekCal.shifted(from, days: 7) }
                        quickPill("30 天") { from = Date(); to = WeekCal.shifted(from, days: 30) }
                    }
                    HStack(spacing: DS.Space.s) {
                        Text(isoShort(from, prefix: "生效 "))
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("→")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        Text(isoShort(to, prefix: "到期 "))
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    if to <= from {
                        Label("到期需晚于生效", systemImage: "exclamationmark.circle.fill")   // 519 到期需晚于生效
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.danger)
                    }
                    // 327 租期重叠检测
                    if !overlaps.isEmpty {
                        Label {
                            Text("与本成员其它 \(overlaps.count) 张码时段撞车")   // 327 与本成员其它
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    }
                    // 330 装修黄条
                }
                .card()

                // 归属与备注 (317 归属先行 + 179 占位)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("归属与备注")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    ForEach(DB.members()) { m in
                        Button {
                            owner = m.id
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Text(m.name)
                                    .vkFont(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                Spacer(minLength: 0)
                                if owner == m.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: DS.Icon.sm, weight: .medium))
                                        .foregroundStyle(DS.Palette.accentText)
                                }
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("归属 " + m.name + (owner == m.id ? "， 已选" : ""))   // 2026-10-30：半角逗号统一为全角「， 」
                    }
                    TextField("给谁 · 哪扇门 · 用多久 (可长按调听写)", text: $note,
                              prompt: Text("如： 钟点工·大门·仅上午场"))
                        .vkFont(.subheadline)
                        .frame(minHeight: DS.Hit.min)
                        .autocorrectionDisabled()
                }
                .card()

                BusyButton(title: batchCount > 1 ? "下发 \(batchCount) 张" : "下发临时码",   // 178 下发
                           systemImage: "timer", isBusy: busy) {
                    Task { await submitBatch() }
                }
                .disabled(!pwdOK || to <= from)
                Text("请将手机靠近门锁。门锁只能一条一条接收，批量会逐条下发、失败逐条报。")   // 178 请将手机靠近门锁
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.l)
        }
        .background(DS.Gradient.screen.ignoresSafeArea())
        .axBottomAnchor()   // 870
        .onAppear { checkClipboard() }
    }

    private func quickPill(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button {
            act()
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(t)
                .vkFont(.caption, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷时长 \(t)")   // 520 快捷时长
    }

    // ---------- 完成页: 172/328 大字口述卡 + 329 一句话 ----------
    // 2026-10-30 修正：原注释还写「333 首用回执」，doneCard 里没有任何回执元素，已删。
    private var doneCard: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                CodeBigCard(title: "\(lockName) · 临时码", code: result?.pwd ?? pwd,
                            // 2026-10-30 修复（第 150 轮）：批量每张错峰 30 分钟，完成卡显示的码取自 result（可能是第 i 张），
                            // 窗口却一直用入口的 from/to —— 屏幕上的窗口与这张码的真实窗口不符。优先用台账里那条的窗口。
                            window: result.map { "\($0.from) ~ \($0.to) 生效" } ?? "\(isoShort(from)) ~ \(isoShort(to)) 生效"
                            note: note,
                            // 2026-10-30 修复（第 116 轮，**假回执**）：原文无条件写「其余已逐张下发」，即使 failed>0 也照写。
                            extraFoot: batchCount > 1
                                ? "批量共 \(batchCount) 张： 成功 \(batchCount - batchFailed) 张 · 失败 \(batchFailed) 张"
                                  + (batchFailed > 0 ? "（失败的请重新下发）" : "")
                                : "")
                if MemberHub.elderMode {
                    // 486 代际完成页切换: 长辈模式下完成页默认形态 = 口述卡 (页标题也切到「口述卡」) + 一枚大「完成」;
                    // 486 代际完成页切换: 长辈模式下完成页默认形态 = 口述卡 (页标题也切到「口述卡」) + 一枚大「完成」。
                    Button("完成") { dismiss() }
                        .buttonStyle(PrimaryActionStyle())
                }
                // 329 一句话口令文本
                if let r = result, !MemberHub.elderMode {
                    let text = StudioTools.oneLine(p: r, lockName: lockName, value: r.pwd)
                    Button {
                        Clip.set(text)   // 405 含口令明文
                        app.showToast("一句话口令已复制")   // 329 一句话口令已复制
                    } label: {
                        VStack(spacing: DS.Space.xs) {
                            Text("生成一句话口令")   // 329 生成一句话口令
                                .vkFont(.footnote, weight: .semibold)
                                .foregroundStyle(DS.Palette.accentText)
                            Text("“" + text + "”")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min + 8)
                        .contentShape(Rectangle())
                        .padding(.vertical, DS.Space.s)
                        .variantPlate(DS.Palette.surfaceAlt, .control)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityLabel("复制一句话口令： " + text)
                    // 329 分享面板: 系统分享单 (与 405 复制同源明文, 发给家人用)
                    ShareLink(item: text) {
                        Label("分享一句话口令", systemImage: "square.and.arrow.up")   // 329 分享一句话口令
                            .vkFont(.footnote, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                            .padding(.vertical, DS.Space.s)
                            .variantPlate(DS.Palette.surfaceAlt, .control)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityLabel("分享一句话口令")   // 329 分享一句话口令
                }
                if !MemberHub.elderMode {
                    Button {
                        result = nil
                        pwd = StudioTools.genDigits(6)
                        note = ""
                    } label: {
                        Label("再发一张", systemImage: "paperplane")
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                }
            }
            .padding(.vertical, DS.Space.l)
        }
        .background(DS.Gradient.screen.ignoresSafeArea())
    }

    private func checkClipboard() {
        guard let s = UIPasteboard.general.string else { return }
        let digits = s.filter { $0.isNumber }
        if digits.count >= 6, digits.count <= 8, pwd.isEmpty {
            pwd = digits
            clipSource = true
        }
    }
    private func isoShort(_ d: Date, prefix: String = "") -> String {
        prefix + d.formatted(.dateTime.month().day().hour().minute())
    }
    private func iso(_ d: Date) -> String {
        let f = DF.stamp
        return f.string(from: d)
    }
    private func submitBatch() async {
        guard let kc = app.current, !busy, pwdOK else { return }
        busy = true
        defer { busy = false }
        var last: LedgerPwd?
        var failed = 0
        batchFailed = 0
        for i in 0..<max(batchCount, 1) {
            // 178 逐条错峰: 每张码时段顺移 30 分钟, 锁端无批量命令
            let df = from.addingTimeInterval(TimeInterval(i * 1800))
            let dt = to.addingTimeInterval(TimeInterval(i * 1800))
            let f = DF.stamp
            do {
                try await app.lock.ensureConnected(mac: kc.mac)
                let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: f.string(from: df), validTo: f.string(from: dt))
                let rec = LedgerPwd(alias: alias, from: f.string(from: df), to: f.string(from: dt), temp: true,
                                    at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: note)
                DB.addPwd(kc.mac, rec)
                last = rec
                app.showToast("第 \(i + 1)/\(max(batchCount, 1)) 张已下发 (别名 #\(alias))")
            } catch {
                failed += 1
                batchFailed = failed
                app.showToast("第 \(i + 1) 张下发失败： \(error.localizedDescription)")   // 178 张下发失败
            }
        }
        if let r = last {
            result = r
            // 2026-10-30 删除（第 120 轮）：这里原来调 `CredentialOrg.clearDraft(kc.mac)` ——
            // 但**本页从不写草稿**（全文件无 saveDraft），而草稿键 `kf_cdraft_<mac>` 与 PwdStudio 共用，
            // 等于「在临时码页下发成功后，把密码工坊里没填完的草稿清掉」。删掉这一行。
            if failed > 0 { app.showToast("批量完成， \(failed) 张失败 —— 本页可直接重新下发， 无需换页") }   // 2026-10-30：原写「可在凭证页重试」，而下发队列已删、凭证页没有重试入口
        }
    }
}