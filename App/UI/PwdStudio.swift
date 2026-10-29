// 密码工坊（添加/编辑 4 步向导）
// 2026-10-29 从 CredentialStudio.swift 拆出。703 行，后续可再按步骤拆
import SwiftUI
import UIKit
import AVFoundation

struct PwdStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// true = 由外部 NavigationStack push (不自带导航栏); false = sheet 呈现自带导航栏
    var embedded: Bool = false
    /// 编辑对象: nil = 新增
    var editAlias: Int? = nil

    // 515 分步: 0 类型与归属 / 1 码值 / 2 有效期与备注 / 3 确认
    @State private var step = 0
    @State private var kind: Int = 0            // 0 长期 / 1 临时
    @State private var owner: String? = nil
    @State private var pwd = ""
    @State private var from = Date()
    // 到期的初始值必须是**一个真窗口**：原先写成 `Date()`，于是新建临时码进到这步时
    // 生效与到期是同一分钟 (0 秒窗口)，界面显示"生效 15:37 · 到期 15:37"这种没人会要的默认。
    // 那时 519 不在这里拦，而是等按下"下一步"时**悄悄把 to 补成 from + 1 小时** —— 用户没选过的值被系统改了。
    // 那处补值本轮已删 (改成真拦, 见文件里的 navBar)，所以这里的初值就是唯一的到期默认值,
    // 全页不再有第二处替用户改时刻的地方。
    @State private var to = Date().addingTimeInterval(3600)   // 828 问号里承诺的默认值就是这个, 别两处各说一套
    @State private var note = ""
    @State private var useTemplate = true
    @State private var periodHelp = false     // 828 字段旁问号展开的说明块
    @State private var busy = false
    // 519 错误字段: 只做**当前这一步之内**的字段标题变红 + 字段下方 errorLine 同步。
    // 刻意不承诺"滚动定位到首个错误字段" —— 这一页是 VStack 直排 (form 里没有 ScrollView),
    //   没有可用的滚动容器与锚点, 那句写出来就是假话; 而步间真拦已经保证坏值出不了当前这一步,
    //   所以"停在当前步 + 红字 + 字段下方一行"就是这一版能兑现的全部, 不多许。
    @State private var errorField: String = ""
    // 301 剪贴板来源条
    @State private var clipSource = false
    @State private var showDraftBar = true
    @State private var submitted = false   // 518: 提交成功不许回存废稿
    // 521 二次输入确认: 保存前重输码值核对 (恒开; 原开关在设置-安全页, 该页已删)
    @State private var confirmPwd = ""
    private var mac: String { app.current?.mac ?? "" }
    private var editing: LedgerPwd? { editAlias.flatMap { DB.getPwd(mac, $0) } }

    private var pwdOK: Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }

    var body: some View {
        Group {
            if embedded {
                form
            } else {
                NavigationStack { form }
            }
        }
    }

    private var form: some View {
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
        }
        .onDisappear { saveDraft() }   // 518: 侧滑/push 退出也留稿
    }

    // ---------- 518 草稿续填横条 ----------
    private func draftBar(_ d: CredentialOrg.StudioDraft) -> some View {
        HStack(spacing: DS.Space.s) {
            Label("上次填到第 \(d.step + 1) 步, 继续?", systemImage: "arrow.triangle.branch")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("草稿续填: 上次填到第 \(d.step + 1) 步, 点继续可回填")   // 518 草稿续填
    }

    // ---------- 515/317 step0 类型与归属 ----------
    @ViewBuilder
    private var step0: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.xs) {
                segChip("长期密码", on: kind == 0) { kind = 0 }
                segChip("临时码", on: kind == 1) { kind = 1 }
                Spacer(minLength: 0)
            }
            .accessibilityLabel("凭证类型: " + (kind == 0 ? "长期密码" : "临时码"))
            ownerCard
        }
    }
    private func segChip(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            act()
        } label: {
            Text(t)
                .vkFont(.footnote, weight: .medium)
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                .padding(.horizontal, DS.Space.s + 2)
                .padding(.vertical, DS.Space.s)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("归属成员")
                .vkFont(.footnote, weight: .semibold)
                .foregroundStyle(errorField == "owner" ? DS.Palette.danger : DS.Palette.text)
            ForEach(DB.members()) { m in
                Button {
                    owner = m.id
                    errorField = ""
                    DS.Haptics.tick.impactOccurred()
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
                .accessibilityLabel("归属 " + m.name + (owner == m.id ? ", 已选" : ""))
            }
            if DB.members().isEmpty {
                Text("还没有成员。可先选「未归属」, 稍后在成员中心补归属。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if errorField == "owner" {
                errorLine("归属必选: 先选成员; 没有成员可先去成员中心新建再返回。")   // 317 归属必选
            }
        }
        .card()
    }

    // ---------- 301/303/173/516/519/522 step1 码值 ----------
    @ViewBuilder
    private var step1: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text("码值")
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(errorField == "value" ? DS.Palette.danger : DS.Palette.text)
                Spacer(minLength: 0)
                Text("6~8 位数字")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
            if !pwd.isEmpty {
                MaskedDigits(value: pwd, big: true)
                    .padding(.vertical, DS.Space.xs)
            }
            TextField("", text: $pwd, prompt: Text("输入 6~8 位数字"))   // 516 输入
                .keyboardType(.numberPad)
                .vkFont(.title3.monospacedDigit(), weight: .semibold)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
                .onChange(of: pwd) { _, _ in
                    if errorField == "value" { errorField = "" }
                    if clipSource { DS.Haptics.tick.impactOccurred() }
                }
            if clipSource {
                HStack(spacing: DS.Space.xs) {
                    Label("来自剪贴板 · 已识别为候选码", systemImage: "doc.on.clipboard")   // 301 来自剪贴板
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("清除") {
                        pwd = ""
                        clipSource = false
                    }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantCallout(DS.Palette.warn, .control, wash: 0.10)
                .accessibilityLabel("码值来自剪贴板, 点清除可移除")
            }
            HStack(spacing: DS.Space.s) {
                ForEach([6, 7, 8], id: \.self) { n in
                    Button("生成 \(n) 位") {
                        pwd = StudioTools.genDigits(n)
                        clipSource = false
                        DS.Haptics.tick.impactOccurred()
                    }
                    .vkFont(.caption, weight: .medium)
                    .buttonStyle(.bordered)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("本地生成 \(n) 位随机密码")   // 173 本地生成
                }
                Spacer(minLength: 0)
            }
            if !pwd.isEmpty {
                let s = StudioTools.pwdStrength(pwd)
                HStack(spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i < s.score ? (s.score <= 1 ? DS.Palette.warn : DS.Palette.ok) : DS.Palette.surfaceAlt)
                                .frame(width: 22, height: 4)
                        }
                    }
                    Text(s.hint)
                        .vkFont(.caption2)
                        .foregroundStyle(s.score <= 1 ? DS.Palette.warn : DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityLabel("密码强度 " + s.hint)
            }
            if errorField == "value" {
                errorLine("码值需 6~8 位数字: 就在上面那格码值里改, 改好再点下一步。")   // 519 码值需
            }
            let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: editAlias ?? -1) : []
            // 304 说的是"全库", 上面那个只查本锁 → 跨锁检查接上 (duplicatePwdLockNames 此前零调用)
            let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
            if !others.isEmpty {
                Label("其它 \(others.count) 把锁上也有同值: " + others.prefix(3).joined(separator: "、")
                    + (others.count > 3 ? " 等" : ""),   // 304 界面文案
                      systemImage: "lock.rectangle.stack")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dups.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    Label("本锁已有 \(dups.count) 条同值凭证", systemImage: "plus.slash.minus")   // 304 本锁已有
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("查看") {
                        // 304 查看即跳: 真把那枚同值凭证的详情打开 (toast 看不全)
                        app.pendingCredNav = "pwd:\(dups[0].alias)"
                        app.pendingCredNavMac = mac
                        app.requestRoute(.credentials)   // 2026-10-15 走查: 与全仓跨 Tab 跳转统一走 requestRoute (访客门禁那一口)
                        if !embedded { dismiss() }
                    }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantCallout(DS.Palette.warn, .control, wash: 0.10)
                .accessibilityElement(children: .combine)
            }
            if let c = pwdOK ? CredentialOrg.prefixConflict(mac, pwd, excluding: editAlias ?? -1).first : nil {
                Text("与「\(CredentialOrg.displayPwd(c))」前 4 位相同, 口头易混淆。")   // 314 位相同
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // ---------- 520/523 step2 有效期与备注 ----------
    @ViewBuilder
    private var step2: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if kind == 1 {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.xs) {
                        Text("有效期 (临时码)")
                            .vkFont(.footnote, weight: .semibold)
                            .foregroundStyle(errorField == "period" ? DS.Palette.danger : DS.Palette.text)
                        // 828 字段旁问号 (Stripe Dashboard 那一形态): 展开的是**这表单真遵守的**四条口径,
                        // 不是通用科普。刻意不做 `.popover`：弹窗锚点在这台机型上看不见也点不着，
                        // 而字段下方的内联块与它说的是同一句话, 只是永远可达 (需要眼睛确认的清单见 VERIFY-CHECKLIST)。
                        Button {
                            periodHelp.toggle()
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Image(systemName: periodHelp ? "questionmark.circle.fill" : "questionmark.circle")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(width: DS.Hit.min - DS.Space.m, height: DS.Hit.min - DS.Space.m)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("有效期的可选范围与默认值")
                        .accessibilityAddTraits(periodHelp ? [.isSelected] : [])
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                        Spacer(minLength: 0)
                    }
                    if periodHelp {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("默认 1 小时；四枚快捷档是 1 小时 / 今天内 (到今晚 23:59) / 7 天 / 30 天。")
                            Text("到期必须晚于生效，否则这条不让过。")   // 519 到期必须晚于生效
                            Text("生效与到期是写给门锁的两个时刻，门锁用它自己的钟比对 —— 锁钟不准，码会提前或延后失效。")
                            Text("改有效期要重新下发到锁才生效；只改本机台账不算。")
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DS.Space.xs)
                        .accessibilityLabel("有效期说明：默认 1 小时；四枚快捷档为 1 小时、今天内到今晚二十三点五十九、7 天、30 天。到期必须晚于生效。生效与到期是写给门锁的两个时刻，门锁用它自己的钟比对。改有效期要重新下发到锁才生效。")
                    }
                    HStack(spacing: DS.Space.xs) {
                        quickDuration("1 小时", 3600)
                        quickDuration("今天", todayEndSecs())
                        quickDuration("7 天", 7 * 86400)
                        quickDuration("30 天", 30 * 86400)
                    }
                    HStack(spacing: DS.Space.s) {
                        durationLabel(from, prefix: "生效 ")
                        durationLabel(to, prefix: "到期 ")
                        Spacer(minLength: 0)
                    }
                    if to <= from {
                        errorLine("到期需晚于生效: 点上面任一快捷档, 或把到期往后挪; 这一步不让过。")   // 519 到期需晚于生效
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("长期密码无到期点; 老旧巡检会在详情页提示「添加满 180 天」那一条 —— "   // 305 长期密码无到期点
                         + "台账只有添加时刻, 那句说的是这条加了多久, 不是这个值多久没换过。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("备注 (给谁·哪扇门·用多久)")
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                // 312 常用短语条: 点按追加到备注末尾 (不是替换), 空备注时直接填
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        Text("常用短语").vkFont(.caption2).foregroundStyle(DS.Palette.textSub)   // 312 常用短语
                        ForEach(["仅白天", "勿外传", "长期有效"], id: \.self) { p in
                            Button(p) {
                                note = note.isEmpty ? p : note + " · " + p
                                DS.Haptics.tick.impactOccurred()
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
                            .variantPlate(DS.Palette.surfaceAlt, .capsule)
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .contentShape(Rectangle())
                            .accessibilityLabel("追加短语 \(p)")
                            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 2)
                }
                TextField("如: 钟点工·大门·仅上午场", text: $note,   // 523 钟点工
                          prompt: Text("给谁 · 哪扇门 · 用多久"))
                    .vkFont(.subheadline)
                    .frame(minHeight: DS.Hit.min)
                    .autocorrectionDisabled()
                // 开关必须常驻: 旧写法用 if useTemplate 包住自己的 Toggle,
                // 一旦用户关掉, 这一行就消失了, 本次会话再也开不回来
                VariantToggle("备注自动补命名模板 (谁-哪里-何时)", isOn: $useTemplate)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
    private func quickDuration(_ t: String, _ secs: Int) -> some View {
        Button {
            from = Date()
            to = Date().addingTimeInterval(TimeInterval(secs))
            errorField = ""
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
    /// 快捷档"今天"的剩余秒数。终点取 `TimeFormat.dayEnd()` (今晚 23:59) ——
    /// 那一份实现刚从**编译失败**里修出来，理由与机检依据写在 TimeFormat.swift:87 上方，不要在这里另抄一份。
    private func todayEndSecs() -> Int {
        max(Int(TimeFormat.dayEnd().timeIntervalSinceNow), 60)
    }
    private func durationLabel(_ d: Date, prefix: String) -> some View {
        Text(prefix + d.formatted(.dateTime.month().day().hour().minute()))
            .vkFont(.footnote)
            .foregroundStyle(DS.Palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(prefix + d.formatted(.dateTime.month().day().hour().minute()))
    }

    // ---------- 306/307 确认步 ----------
    private var step3: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if let e = editing, let old = e.pwd, !old.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("新旧对照 (上旧只读 / 下新)")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    PwdDiffView(old: old, new: pwd.isEmpty ? old : pwd)
                        .card()
                    Text("改动位共 \(CredentialOrg.digitDiff(old: old, new: pwd.isEmpty ? old : pwd).count) 处 (逐位高亮, 确认后才落库)。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("即将\(editing == nil ? "添加" : "改造")的凭证")
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        StatusPill(text: kind == 0 ? "长期密码" : "临时码", systemImage: kind == 0 ? "infinity" : "clock", tone: .accent)
                        Text(CredentialOrg.ownerName(owner))
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                    }
                    MaskedDigits(value: pwd, big: true)
                    if kind == 1 {
                        Text("\(from.formatted(.dateTime.month().day().hour().minute())) ~ \(to.formatted(.dateTime.month().day().hour().minute())) 生效")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            // 2026-10-14 布局审计 R2: 两个"月日 时分"+ 尾巴"生效"在 375pt 宽 / 大字号档
                            // 估宽 371pt > 可分配 343pt，lineLimit(1) 会把尾巴切掉 —— 而那半句正是
                            // "从哪个时刻开始算"。改成允许两行并让它占满该占的竖直空间；
                            // 原有的 minimumScaleFactor 不动 (缩字号与换行谁先起作用由系统排，不在这里猜)。
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !note.isEmpty {
                        Text(note)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(2)
                    }
                }
                .card()
            }
            if busy {
                ProgressView("正在下发到门锁…")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
            } else {
                // 521 二次输入确认: 重输码值一致才放行 (与转账复核同语义; 开关在设置-安全页)
            HStack(spacing: DS.Space.xs) {
                TextField("重输一遍码值", text: $confirmPwd)   // 521 重输一遍码值
                    .keyboardType(.numberPad)
                    .vkFont(.subheadline.monospaced())
                    .autocorrectionDisabled()
                if !confirmPwd.isEmpty, confirmPwd != pwd {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .foregroundStyle(DS.Palette.danger)
                } else if !confirmPwd.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DS.Icon.sm, weight: .medium))
                        .foregroundStyle(DS.Palette.ok)
                }
            }
            .padding(DS.Space.s)
            .variantPlate(DS.Palette.surfaceAlt, .control)
                // 541 替代: 原句是下发前的乐观锁提示 ("此锁配置上次同步于 X, 建议到场核对后重试")。
                // 锁端没有配置序号字段, 所以这把尺只到本机台账 (365 队列里最后一条"已下发"的时刻),
                // 文案把这件事说穿 —— 提示不说成"锁端就是这样"。
                // 2026-10-26 精简：队列 lastApplyAt 已删。
                BusyButton(title: editing == nil ? "下发密码" : "保存改造", systemImage: "key.fill", isBusy: busy) {
                    Task { await submit() }
                }
                .disabled(confirmPwd != pwd)
            }
            Text("请将手机靠近门锁; 成功后登记到本机台账并留一档版本快照。")   // 487 请将手机靠近门锁
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 515 导航条 ----------
    private var navBar: some View {
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
                Button(step == 0 ? "下一步: 码值" : (step == 1 ? "下一步: 有效期" : "下一步: 确认")) {
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
                        app.showToast("到期要晚于生效, 请先点一枚快捷档")   // 519 到期要晚于生效
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

    private func checkClipboard() {
        guard editAlias == nil else { return }
        guard let s = UIPasteboard.general.string else { return }
        let digits = s.filter { $0.isNumber }
        if digits.count >= 6, digits.count <= 8, pwd.isEmpty {
            pwd = digits
            clipSource = true
        }
    }
    private func restoreDraft(_ d: CredentialOrg.StudioDraft) {
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
    private func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }
    private func saveDraft() {
        guard !submitted, editAlias == nil, step > 0 || !pwd.isEmpty else { return }
        CredentialOrg.saveDraft(mac, CredentialOrg.StudioDraft(
            step: step, kind: kind, pwd: pwd, permanent: kind == 0,
            fromISO: iso(from), toISO: iso(to), owner: owner,
            useTemplate: useTemplate, note: note, batch: 0,
            at: Date().timeIntervalSince1970))
    }

    // ---------- 提交 (既有协议 0A/原位改写; 178 批量另在临时码工坊) ----------
    private func submit() async {
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
            app.showToast("到期要晚于生效: 草稿里的这一档已过期, 请重选")   // 519 到期要晚于生效
            DS.Haptics.trigger.impactOccurred()
            return
        }
        busy = true
        defer { busy = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
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
            app.showToast("下发失败: " + error.localizedDescription)
        }
    }

    private func errorLine(_ s: String) -> some View {
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