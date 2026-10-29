// 密码工坊 · 四步向导（归属 / 码值 / 有效期 / 确认）
// 2026-10-29 从 PwdStudio.swift（709 行）拆出。
// 是 PwdStudio 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension PwdStudio {
    var step0: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.xs) {
                segChip("长期密码", on: kind == 0) { kind = 0 }
                segChip("临时码", on: kind == 1) { kind = 1 }
                Spacer(minLength: 0)
            }
            .accessibilityLabel("凭证类型： " + (kind == 0 ? "长期密码" : "临时码"))
            ownerCard
        }
    }
    func segChip(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
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
    var ownerCard: some View {
        // 2026-10-30 性能：`DB.members()` 原来在本块里调 2 次（ForEach + isEmpty 判据）。
        // 虽然第 22 轮给 members() 加了派生缓存，但这里仍是一次多余的数组拷贝 + 缓存查表。一次取共用。
        let allMembers = DB.members()
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("归属成员")
                .vkFont(.footnote, weight: .semibold)
                .foregroundStyle(errorField == "owner" ? DS.Palette.danger : DS.Palette.text)
            ForEach(allMembers) { m in
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
            if allMembers.isEmpty {
                Text("还没有成员。可先选「未归属」, 稍后在成员中心补归属。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if errorField == "owner" {
                errorLine("归属必选： 先选成员; 没有成员可先去成员中心新建再返回。")   // 317 归属必选
            }
        }
        .card()
    }

    // ---------- 301/303/173/516/519/522 step1 码值 ----------
    @ViewBuilder
    var step1: some View {
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
                .accessibilityLabel("码值来自剪贴板， 点清除可移除")
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
                errorLine("码值需 6~8 位数字： 就在上面那格码值里改， 改好再点下一步。")   // 519 码值需
            }
            let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: editAlias ?? -1) : []
            // 304 说的是"全库", 上面那个只查本锁 → 跨锁检查接上 (duplicatePwdLockNames 此前零调用)
            let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
            if !others.isEmpty {
                Label("其它 \(others.count) 把锁上也有同值： " + others.prefix(3).joined(separator: "、")
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
                Text("与「\(CredentialOrg.displayPwd(c))」前 4 位相同， 口头易混淆。")   // 314 位相同
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // ---------- 520/523 step2 有效期与备注 ----------
    @ViewBuilder
    var step2: some View {
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
                        errorLine("到期需晚于生效： 点上面任一快捷档， 或把到期往后挪; 这一步不让过。")   // 519 到期需晚于生效
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("长期密码无到期点; 老旧巡检会在详情页提示「添加满 180 天」那一条 —— "   // 305 长期密码无到期点
                         + "台账只有添加时刻， 那句说的是这条加了多久， 不是这个值多久没换过。")
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
                TextField("如： 钟点工·大门·仅上午场", text: $note,   // 523 钟点工
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
    func quickDuration(_ t: String, _ secs: Int) -> some View {
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
    func todayEndSecs() -> Int {
        max(Int(TimeFormat.dayEnd().timeIntervalSinceNow), 60)
    }
    func durationLabel(_ d: Date, prefix: String) -> some View {
        Text(prefix + d.formatted(.dateTime.month().day().hour().minute()))
            .vkFont(.footnote)
            .foregroundStyle(DS.Palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(prefix + d.formatted(.dateTime.month().day().hour().minute()))
    }

    // ---------- 306/307 确认步 ----------
    var step3: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if let e = editing, let old = e.pwd, !old.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("新旧对照 (上旧只读 / 下新)")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    PwdDiffView(old: old, new: pwd.isEmpty ? old : pwd)
                        .card()
                    Text("改动位共 \(CredentialOrg.digitDiff(old: old, new: pwd.isEmpty ? old : pwd).count) 处 (逐位高亮， 确认后才落库)。")
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
}
