// KeyDetailHomeScreen.swift —— 单枚凭证的档案页（V8 设计语言）
//
// 与 KeyDetailScreen 的能力对齐：码值打码与整条/分段复制、档案读数（类型 / 归属 / 已使用 /
// 到期日 / 剩余）、提前失效提示、改到期日、停用或恢复、重录指纹、改造密码值、彻底删除。
// 只改渲染层：写台账仍走 app.setPasswordExpiry / app.deletePassword / app.deleteFingerprint /
// CredentialLocalState.setDisabled / CredentialOrg.setEarlyExpireMin。
//
// 与旧页的刻意差异：
//   ① 旧页把 KeyItem.code（投影层已经是圆点串）当码值 ——「逐位点开」揭开的还是圆点，
//      「复制整条」复制出去的也是圆点。新页从台账取真实码值，只用于复制，屏幕上永不出现明文。
//   ② 空壳模式（DB.isDecoy）整页只读：不显示任何凭证字段，也拒绝全部写入 —— 旧页的改期/删除
//      会先改锁端，再被 saveLedger 静默拒写，留下两边不一致。
//   ③ 只读试验模式（app.trialGuard）在页内写明：哪些动作被拦、哪些仍可用。
import SwiftUI

struct KeyDetailHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var keyID: String?
    @State private var now: Int64 = KeysState.now()
    @State private var confirmDelete = false
    @State private var confirmDisable = false
    @State private var actionError: String?
    @State private var outcome: String?
    @State private var showReEnroll = false
    @State private var copiedSegment: Int?

    private var key: KeyItem? {
        guard let keyID else { return nil }
        return app.keys.first { $0.id == keyID }
    }

    private var decoyed: Bool { DB.isDecoy }

    // MARK: - 判断句与副文

    private var judgement: String {
        if decoyed { return "空壳模式下不显示凭证" }
        guard let key else { return "这枚凭证已经不在了" }
        return key.name
    }

    private var lead: String? {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。退出空壳后才能看这枚凭证。"
        }
        guard let key else {
            return nil
        }
        return key.kind.rawValue + " · " + KeysState.word(key, now: now) + "。码值只以圆点显示，复制时不显示在屏幕上。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if key != nil && !decoyed {
                chipRow
            }
        } content: {
            if decoyed {
                decoyCard
            } else if let key {
                codeCard(key)
                factsCard(key)
                earlyCard(key)
                actionsCard(key)
                dangerCard(key)
                if app.trialGuard {
                    trialCard
                }
            } else {
                missingCard
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .onAppear {
            now = KeysState.now()
            consumeRoute()
        }
        .onDisappear { copiedSegment = nil }
        .sheet(isPresented: $showReEnroll) {
            if let key, key.kind == .fingerprint {
                KeyDetailReEnrollSheet(key: key)
                    .v8Sheet()
            }
        }
        .v8Confirm(
            isPresented: $confirmDelete,
            title: "彻底删除这枚凭证？",
            consequence: "删除后这枚凭证在锁内立即失效，本机台账也不再保留。没有回收站，不能撤销 —— 要再开门得重新下发一次。",
            confirmTitle: "删除"
        ) {
            deleteKey()
        }
        .v8Confirm(
            isPresented: $confirmDisable,
            title: "停用这枚凭证？",
            consequence: "停用只改本机的停用位：锁端凭证仍然有效、仍能开门，随时可以在本页「恢复使用」。要真正作废请用「彻底删除」。",
            confirmTitle: "停用",
            isDestructive: false
        ) {
            if let key { toggleDisabled(key) }
        }
    }

    // MARK: - 芯片行

    private var chipRow: some View {
        VHScroll {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .glyph(kindSymbol), label: "类型", value: key?.kind.rawValue ?? "—")
                VChip2(icon: .ring(statusFraction, statusTint), label: "状态", value: statusWord)
                VChip2(icon: .glyph("person.fill"), label: "归属", value: ownerText)
                VChip2(icon: .ring(expiryFraction, expiryTint), label: "到期", value: expiryShort)
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private var statusWord: String {
        guard let key else { return "—" }
        return KeysState.word(key, now: now)
    }

    private var kindSymbol: String {
        switch key?.kind {
        case .password: return "key.fill"
        case .fingerprint: return "touchid"
        case .temp: return "clock.fill"
        case .mobile: return "iphone"
        case nil: return "key.fill"
        }
    }

    private var ownerText: String {
        guard let key else { return "—" }
        let name = CredentialOrg.ownerName(key.owner)
        return name.isEmpty ? "未归属" : name
    }

    private var statusTint: Color {
        guard let key else { return V8.C.ink4 }
        if key.disabled { return V8.C.ink3 }
        if KeysState.expired(key, now: now) { return V8.C.danger }
        guard let days = KeysState.daysLeft(key, now: now) else { return V8.C.ok }
        return days <= 3 ? V8.C.warn : V8.C.ok
    }

    private var statusFraction: Double {
        guard let key else { return 0.02 }
        if key.disabled { return 0.35 }
        if KeysState.expired(key, now: now) { return 0.06 }
        guard let days = KeysState.daysLeft(key, now: now) else { return 1 }
        if days <= 3 { return 0.35 }
        return 0.85
    }

    private var expiryTint: Color {
        guard let key else { return V8.C.ink4 }
        guard let days = KeysState.daysLeft(key, now: now) else { return V8.C.ink2 }
        if days < 0 { return V8.C.danger }
        return days <= 3 ? V8.C.warn : V8.C.ink2
    }

    private var expiryFraction: Double {
        guard let key, let days = KeysState.daysLeft(key, now: now) else { return 1 }
        if days < 0 { return 0.02 }
        if days <= 3 { return 0.3 }
        if days <= 30 { return 0.6 }
        return 0.9
    }

    private var expiryShort: String {
        guard let key else { return "—" }
        if key.disabled { return "已停用" }
        guard let days = KeysState.daysLeft(key, now: now) else { return "永久" }
        if days < 0 { return "已过期" }
        return KeysState.daysWord(days)
    }

    // MARK: - 卡 1 码值

    private func codeCard(_ key: KeyItem) -> some View {
        VCard2 {
            VCardHead(
                eyebrow: key.kind == .fingerprint ? "指纹" : "码值",
                statement: codeStatement(key),
                trailing: key.code == nil ? nil : "逐段复制"
            )
            VDivider2()
                .padding(.top, V8.S.gapM)
            if key.kind == .fingerprint {
                Text("指纹没有码值。它在门锁上按 8 次录进去，开门时按手指就行。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else if key.code == nil {
                Text("这条当时没留存明文。可在门锁键盘上核对后重填，或直接改造一次密码值。")
                    .font(V8.T.body)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                maskedCode(key)
                    .padding(.top, V8.S.gapM)
                HStack(spacing: V8.S.gapS) {
                    codeButton("复制整条") { copyWhole(key) }
                    Text(copyHint)
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                    Spacer(minLength: 0)
                }
                .padding(.top, V8.S.gapS)
                if let plain = plainCode(key), plain.count >= 8 {
                    segmentGrid(key, plain: plain)
                        .padding(.top, V8.S.gapL)
                }
            }
            if let outcome, key.kind != .fingerprint {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ok)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .captureShield("这枚凭证含码值\n屏幕正在被录制或截图，已遮挡")
    }

    private func codeStatement(_ key: KeyItem) -> String {
        if key.kind == .fingerprint { return "按指纹开门" }
        if key.code == nil { return "没有留存明文" }
        return "码值默认打码"
    }

    private var copyHint: String {
        "复制后 90 秒自动从剪贴板清空"
    }

    /// 屏幕上只画圆点。长度按投影里的码值长度（不足 4 位按 4 位）。
    private func maskedCode(_ key: KeyItem) -> some View {
        let count = max(4, (key.code ?? "").count)
        return Text(String(repeating: "•", count: count))
            .font(V8.T.heroL)
            .monospacedDigit()
            .foregroundStyle(V8.C.ink1)
            .tracking(V8.G.heroNumberTracking)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel("码值已打码，" + String(count) + " 位")
    }

    private func segmentGrid(_ key: KeyItem, plain: String) -> some View {
        let parts = KeysCode.segments(plain)
        return VStack(alignment: .leading, spacing: V8.S.gapS) {
            Text("按 4 位分段转述 · 点一段只复制那一段")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: V8.S.gapXXL * 2.6), spacing: V8.S.gapS)],
                      alignment: .leading, spacing: V8.S.gapS) {
                ForEach(Array(parts.enumerated()), id: \.offset) { pair in
                    Button {
                        Clip.set(pair.element)
                        copiedSegment = pair.offset
                        outcome = "已复制第 " + String(pair.offset + 1) + " 段"
                    } label: {
                        Text(String(repeating: "•", count: pair.element.count))
                            .font(V8.T.value)
                            .foregroundStyle(copiedSegment == pair.offset ? V8.C.ink1 : V8.C.ink3)
                            .padding(.horizontal, V8.S.gapM)
                            .frame(minHeight: V8.H.min)
                            .background(
                                copiedSegment == pair.offset ? V8.C.accentTrack : V8.C.well,
                                in: .rect(cornerRadius: V8.R.inset)
                            )
                    }
                    .buttonStyle(V8PressStyle())
                    .accessibilityLabel("第 " + String(pair.offset + 1) + " 段，点按只复制这一段")
                }
            }
        }
    }

    private func codeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(V8.C.chipOff))
        }
        .buttonStyle(V8PressStyle())
        .accessibilityLabel(title)
    }

    /// 真实码值只从台账取，只用于复制 —— 绝不进任何 Text。
    private func plainCode(_ key: KeyItem) -> String? {
        guard let alias = alias(of: key) else {
            return key.kind == .mobile ? key.code : nil
        }
        return DB.listPwds(app.currentMac).first { $0.alias == alias }?.pwd
    }

    private func copyWhole(_ key: KeyItem) {
        guard let code = plainCode(key), !code.isEmpty else {
            actionError = "这条没有可用于复制的码值 —— 请在门锁键盘上核对后重填，或改造一次密码值。"
            return
        }
        Clip.set(code)
        actionError = nil
        outcome = "已复制完整码值"
    }

    // MARK: - 卡 2 档案

    private func factsCard(_ key: KeyItem) -> some View {
        VCard2 {
            VCardHead(eyebrow: "档案", statement: factsStatement(key))
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "类型", tagTint: V8.C.ink4, title: key.kind.rawValue, value: "")
                VDotRule()
                VDataRow(tag: "归属", tagTint: V8.C.ink4, title: ownerText, value: "")
                if let age = CredentialOrg.pwdAgeDays(key.createdAt) {
                    VDotRule()
                    VDataRow(tag: "已使用", tagTint: V8.C.ink4, title: String(age) + " 天", value: "")
                }
            }
            .padding(.top, V8.S.gapS)
            VStatPair2(items: [
                .init(label: "到期日", value: expiryDateText(key), unit: expiryDateUnit(key)),
                .init(label: "剩余", value: remainingText(key), unit: remainingUnit(key))
            ])
            .padding(.top, V8.S.gapL)
            VDivider2()
                .padding(.top, V8.S.gapL)
            Text("改到期日会真下发到锁，回执成功才改本机台账 —— 不再只是本机备注。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func factsStatement(_ key: KeyItem) -> String {
        let name = CredentialOrg.ownerName(key.owner)
        if name.isEmpty { return "未归属" }
        return "归 " + name
    }

    private func expiryDateText(_ key: KeyItem) -> String {
        KeysState.expiryLine(key).value
    }

    private func expiryDateUnit(_ key: KeyItem) -> String? {
        KeysState.expiryLine(key).unit
    }

    private func remainingText(_ key: KeyItem) -> String {
        if key.disabled { return "—" }
        guard let days = KeysState.daysLeft(key, now: now) else { return "永久" }
        if days < 0 { return "过期" }
        if days == 0 { return "今天" }
        if days == 1 { return "明天" }
        return String(days)
    }

    private func remainingUnit(_ key: KeyItem) -> String? {
        guard !key.disabled, let days = KeysState.daysLeft(key, now: now), days > 1 else { return nil }
        return "天"
    }

    // MARK: - 卡 3 提前失效

    @ViewBuilder
    private func earlyCard(_ key: KeyItem) -> some View {
        if let alias = alias(of: key), key.kind == .temp || key.kind == .password {
            VCard2 {
                VCardHead(
                    eyebrow: "提前失效提示",
                    statement: "本机提前 " + String(CredentialOrg.earlyExpireMin(app.currentMac, alias)) + " 分钟",
                    trailing: "0 = 不提前"
                )
                VDivider2()
                    .padding(.top, V8.S.gapM)
                Slider(
                    value: Binding(
                        get: { Double(CredentialOrg.earlyExpireMin(app.currentMac, alias)) },
                        set: { CredentialOrg.setEarlyExpireMin(app.currentMac, alias, Int($0.rounded())) }
                    ),
                    in: 0 ... 120,
                    step: 5
                )
                .tint(V8.C.accent)
                .accessibilityLabel("提前失效分钟数")
                .accessibilityValue(String(CredentialOrg.earlyExpireMin(app.currentMac, alias)) + " 分钟")
                .padding(.top, V8.S.gapS)
                Text("只在本机把到期提示提前 N 分钟（0 = 不提前）。锁端有效期不变 —— 这枚凭证在锁上仍然有效到原本的到期时刻。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapFootnote)
                    .fixedSize(horizontal: false, vertical: true)
                if let pwd = DB.ledger(app.currentMac).pwds.first(where: { $0.alias == alias }),
                   CredentialOrg.earlyExpireMin(app.currentMac, alias) > 0 {
                    Text(CredentialOrg.earlyExpiryNote(app.currentMac, pwd))
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink2)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 卡 4 能做的事

    private func actionsCard(_ key: KeyItem) -> some View {
        VCard2 {
            VCardHead(eyebrow: "能做的事", statement: actionStatement(key))
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                if key.kind == .password || key.kind == .temp {
                    expiryMenu(key)
                    VDotRule()
                }
                VNavRow(
                    title: key.disabled ? "恢复使用" : "停用这枚凭证",
                    detail: key.disabled ? "恢复后锁端凭证仍按原有效期可用" : "只改本机停用位，锁端凭证仍然有效"
                ) {
                    if key.disabled {
                        toggleDisabled(key)
                    } else {
                        confirmDisable = true
                    }
                }
                if key.disabled {
                    Text("停用只是本机状态：锁端凭证仍然有效，恢复使用即回到可用。要真正作废请用下面的「彻底删除」。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if key.kind == .fingerprint {
                    VDotRule()
                    VNavRow(title: "重录一枚替换它", detail: "先录新的，成功后才删旧批次") {
                        showReEnroll = true
                    }
                }
                if key.kind == .password || key.kind == .temp {
                    VDotRule()
                    VNavRow(title: "改造密码值", detail: "先建新码，成功后再删旧码") {
                        router.request(.dest(.keyCreate))
                        router.pending = .key(id: key.id)
                    }
                }
            }
            .padding(.top, V8.S.gapS)
            if let actionError {
                VFailure(
                    what: "这一步没有完成",
                    why: actionError,
                    next: "按上面的原因处理后重试；本机台账没有改动。"
                )
                .padding(.top, V8.S.gapM)
            }
        }
    }

    private func actionStatement(_ key: KeyItem) -> String {
        if key.disabled { return "已停用" }
        if key.kind == .fingerprint { return "可停用或重录" }
        return "可改期或改码"
    }

    private func expiryMenu(_ key: KeyItem) -> some View {
        Menu {
            Button("延到明天") { setExpiry(key, days: 1) }
            Button("延到 3 天后") { setExpiry(key, days: 3) }
            Button("延到 7 天后") { setExpiry(key, days: 7) }
            Button("延到 30 天后") { setExpiry(key, days: 30) }
            Button("改为永久有效") { setExpiry(key, days: nil) }
            if key.expiresAt != nil {
                Button("提前到今天结束") { setExpiry(key, days: 0) }
            }
        } label: {
            HStack(spacing: V8.S.gapS) {
                Text("改到期日")
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                Spacer(minLength: 0)
                Text(KeysState.word(key, now: now))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(V8.T.micro)
                    .foregroundStyle(V8.C.ink4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("改到期日")
    }

    // MARK: - 卡 5 不可逆

    private func dangerCard(_ key: KeyItem) -> some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "不可逆", statement: "删除没有回收站")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("删除会同时从门锁和本机台账里移除这枚凭证，没有回收站。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                confirmDelete = true
            } label: {
                Text("彻底删除")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(V8PressStyle())
            .accessibilityLabel("彻底删除这枚凭证")
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 只读试验模式 / 空壳 / 缺页

    private var trialCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "只读试验模式", statement: "写入类命令已停用")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("现在改到期日、重录指纹、彻底删除都会被护栏拦下 —— 它们要往门锁写。停用或恢复与提前失效提示只改本机，仍可用。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "凭证详情", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，凭证名称、归属、码值与到期日都不显示，也不允许任何写入。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingCard: some View {
        VEmpty(
            title: "回到凭证列表",
            reason: "它可能刚被删除或停用。回钥匙列表看看还剩哪些凭证，或再新增一枚。",
            actionTitle: "回钥匙列表"
        ) {
            router.keysPath = []
        }
    }

    // MARK: - 消费路由上下文

    private func consumeRoute() {
        if let context = router.consume(if: { if case .key = $0 { return true }; return false }),
           case .key(let id) = context {
            keyID = id
            return
        }
        if keyID == nil { keyID = app.keys.first?.id }
    }

    // MARK: - 写台账（值语义：改就是换一条）

    private func setExpiry(_ key: KeyItem, days: Int?) {
        guard !DB.isDecoy else {
            actionError = DecoyCopy.blocked("改台账")
            return
        }
        guard !app.trialGuard else {
            actionError = TrialCopy.refused("改到期日要往门锁写")
            return
        }
        guard key.kind == .password || key.kind == .temp, let alias = alias(of: key) else {
            actionError = "只有密码/临时码有到期日"
            return
        }
        let cal = TimeFormat.calendar
        let start = cal.startOfDay(for: Date())
        let df = DF.cached("yyyy-MM-dd HH:mm")
        let from = df.string(from: Date())
        let to: String
        if let days {
            let shifted = cal.date(byAdding: .day, value: days, to: start) ?? start
            let end = cal.date(byAdding: .second, value: 86399, to: shifted) ?? shifted
            to = df.string(from: end)
        } else {
            to = "2118-12-31 23:59"
        }
        actionError = nil
        Task { @MainActor in
            let r = await app.setPasswordExpiry(alias: alias, from: from, to: to)
            if case .failure(let e) = r {
                actionError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            }
            now = KeysState.now()
        }
    }

    /// 停用 / 恢复使用：只改本机停用位（可恢复），不发任何锁端删除命令。
    private func toggleDisabled(_ key: KeyItem) {
        guard !DB.isDecoy else {
            actionError = DecoyCopy.blocked("改本机状态")
            return
        }
        actionError = nil
        let mac = app.currentMac
        CredentialLocalState.setDisabled(mac: mac, id: key.id, !key.disabled)
        app.reloadKeys(mac)
    }

    private func deleteKey() {
        guard !DB.isDecoy else {
            actionError = DecoyCopy.blocked("删除凭证")
            return
        }
        guard !app.trialGuard else {
            actionError = TrialCopy.refused("删除要往门锁写")
            return
        }
        guard let key else { return }
        actionError = nil
        Task { @MainActor in
            let r: Result<Void, Error>
            if key.kind == .fingerprint, let batch = fpBatch(of: key) {
                r = await app.deleteFingerprint(batch: batch)
            } else if let alias = alias(of: key) {
                r = await app.deletePassword(alias: alias)
            } else if key.kind == .mobile, let kc = app.currentKeychain,
                      let mk = MobileKeyService.list(kc.mac).first(where: { "mkey:\($0.id)" == key.id }) {
                do {
                    try await MobileKeyService.revoke(host: app, kc: kc, key: mk)
                    app.reloadKeys(kc.mac)
                    r = .success(())
                } catch {
                    r = .failure(error)
                }
            } else {
                app.keys.removeAll { $0.id == key.id }
                AppToast.shared.show("已从本机列表移除；锁端凭证未变，仍可开门（这条没有可下发的撤销命令）。", tone: .warn)
                r = .success(())
            }
            if case .failure(let e) = r {
                actionError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            } else {
                router.keysPath = []
            }
        }
    }

    private func alias(of key: KeyItem) -> Int? {
        guard key.id.hasPrefix("pwd:") else { return nil }
        return Int(key.id.dropFirst(4))
    }

    private func fpBatch(of key: KeyItem) -> Int? {
        guard key.id.hasPrefix("fp:") else { return nil }
        return Int(key.id.dropFirst(3))
    }
}

// MARK: - 指纹重录替换（V8 渲染层；逻辑与旧页 FingerprintReEnrollSheet 一致）

/// 重录一枚指纹并替换旧批次：先录新的，成功后才删旧批次。
/// 失败时旧批次保留 —— 不出现「旧的删了、新的没录上」这种把人关在门外的中间态。
struct KeyDetailReEnrollSheet: View {
    let key: KeyItem

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var owner: String?
    @State private var busy = false
    @State private var fpCount = 0
    @State private var error: String?

    private var batch: Int? {
        guard key.id.hasPrefix("fp:") else { return nil }
        return Int(key.id.dropFirst(3))
    }

    var body: some View {
        NavigationStack {
            VPage(title: "重录指纹", lead: statusText) {
                EmptyView()
            } content: {
                VCard2 {
                    VCardHead(eyebrow: "指纹名称", statement: name.isEmpty ? key.name : name)
                    VDivider2()
                        .padding(.top, V8.S.gapM)
                    VTextField(placeholder: key.name, text: $name)
                        .padding(.top, V8.S.gapM)
                    Text("归属：" + ownerText)
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .padding(.top, V8.S.gapS)
                        .fixedSize(horizontal: false, vertical: true)
                    if busy {
                        VBusy(text: "指纹录入中 · 已按 " + String(fpCount) + "/8 — 请把手指按在指纹头上再抬起")
                            .padding(.top, V8.S.gapS)
                    }
                    if let error {
                        VFailure(what: "重录没有完成", why: error, next: "旧指纹原样保留；按提示处理后重试。")
                            .padding(.top, V8.S.gapS)
                    }
                    V8ActionButton(title: busy ? "录入中…" : "开始重录", style: .primary, busy: busy) {
                        start()
                    }
                    .disabled(busy)
                    .padding(.top, V8.S.gapM)
                    V8ActionButton(title: "取消", style: .secondary) {
                        dismiss()
                    }
                    .padding(.top, V8.S.gapS)
                }
                VCard2(style: .well) {
                    Text("重录会先下发新指纹；成功后才删除旧批次。失败时旧指纹原样保留，不会把人关在门外。")
                        .font(V8.T.footnote)
                        .foregroundStyle(V8.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(V8.C.bg.ignoresSafeArea())
            .onAppear {
                name = key.name
                owner = key.owner
            }
        }
    }

    private var ownerText: String {
        let name = CredentialOrg.ownerName(key.owner)
        return name.isEmpty ? "未归属" : name
    }

    private var statusText: String {
        if let error { return error }
        if busy { return "请按 8 次指纹头 · 已按 " + String(fpCount) + "/8" }
        return "录新的，成功后替换「" + key.name + "」"
    }

    private func start() {
        guard !busy else { return }
        guard !app.trialGuard else {
            error = TrialCopy.refused("重录指纹要往门锁写")
            return
        }
        guard let old = batch else {
            error = key.id.hasPrefix("fp:")
                ? "这枚指纹的批次号解析失败（台账记录可能已损坏）—— 请到凭证页重新录入一次。"
                : "这不是指纹凭证，没有批次号可替换。"
            return
        }
        busy = true
        fpCount = 0
        error = nil
        Task { @MainActor in
            ScreenCare.keepingAwake(true)
            defer { ScreenCare.keepingAwake(false) }
            let result = await app.enrollFingerprint(
                name: name.isEmpty ? key.name : name,
                owner: owner,
                note: "重录替换 #" + String(old)
            ) { n in
                fpCount = n
            }
            busy = false
            switch result {
            case .success(let newBatch):
                if newBatch != old {
                    let deleted = await app.deleteFingerprint(batch: old)
                    if case .failure(let e) = deleted {
                        error = "新指纹已录好，但旧批次删除失败：" + e.localizedDescription
                        return
                    }
                }
                AppToast.shared.show("指纹已重录并替换", tone: .ok)
                dismiss()
            case .failure(let e):
                error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            }
        }
    }
}
