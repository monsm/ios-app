// KeyDetailScreen.swift —— 单枚凭证的档案页。
//
// 这一屏干什么：把一枚凭证的全部事实摆成读数（类型 / 归属 / 到期 / 状态），
// 码值默认打码、逐位点开；下面是三个真动作（改到期 / 停用启用 / 彻底删除）与「改造密码值」入口。
// 数据从哪来：AppModel.keys；定位靠 Router 的挂起上下文 .key(id:)，页面 onAppear 消费。
// 主动作：改到期日（Menu）—— 它是这一页唯一会改写台账的动作；删除是危险动作，不进主动作位。
import SwiftUI
import UIKit

struct KeyDetailScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var keyID: String?
    @State private var revealed: Set<Int> = []
    @State private var now: Int64 = KeysState.now()
    @State private var confirmDelete = false
    @State private var copiedSegment: Int?
    @State private var actionError: String?
    @State private var showReEnroll = false

    private var key: KeyItem? {
        guard let keyID else { return nil }
        return app.keys.first { $0.id == keyID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                if let key {
                    header(key)
                    codeBlock(key)
                    factsBlock(key)
                    earlyExpireCard(key)
                    actionsBlock(key)
                    dangerBlock(key)
                } else {
                    missingBlock
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("凭证详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            now = KeysState.now()
            consumeRoute()
        }
        .onDisappear { revealed = [] }
        .sheet(isPresented: $showReEnroll) {
            if let key, key.kind == .fingerprint {
                FingerprintReEnrollSheet(key: key)
            }
        }
        .confirmationDialog("彻底删除这枚凭证？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteKey() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后这枚凭证在锁内立即失效，本机台账也不再保留。要再开门得重新下发一次。")
        }
    }

    // MARK: 消费路由上下文（.key(id:) 是唯一漏斗带过来的定位）

    private func consumeRoute() {
        let context = router.consume()
        switch context {
        case .key(let id):
            keyID = id
        case .dest(.keyDetail):
            if keyID == nil { keyID = app.keys.first?.id }
        default:
            if keyID == nil { keyID = app.keys.first?.id }
        }
    }

    // MARK: 页头

    private func header(_ key: KeyItem) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text(key.name)
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: KeysState.tone(key, now: now), word: KeysState.word(key, now: now))
                Text("\(key.kind.rawValue) · \(KeysState.word(key, now: now))")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 主角：码值

    private func codeBlock(_ key: KeyItem) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: key.kind == .fingerprint ? "指纹" : "码值", trailing: key.code == nil ? nil : "逐位点开")
                if let code = key.code, !code.isEmpty {
                    KeysMaskedCode(value: code, size: 24, revealed: $revealed)
                        .padding(.vertical, V.S.gapXS)
                    HStack(spacing: V.S.gapS) {
                        VOutlineButton(title: "复制整条", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = code
                        }
                        VOutlineButton(title: "复遮", systemImage: "eye.slash") {
                            revealed = []
                        }
                    }
                    if code.count >= 8 {
                        segmentRow(code)
                    }
                } else if key.kind == .fingerprint {
                    Text("指纹没有码值。它在门锁上按 8 次录进去，开门时按手指就行。")
                        .font(V.F.body)
                        .foregroundStyle(V.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    KeysInlineNote(tone: .attention, text: "这条当时没留存明文。可在门锁键盘上核对后重填，或直接改造一次密码值。")
                }
            }
        }
        .captureShield("这枚凭证含码值\n屏幕正在被录制或截图，已遮挡")
        .padding(.horizontal, V.S.pageGutter)
    }

    private func segmentRow(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("按 4 位分段转述 · 点一段只复制那一段")
                .font(V.F.unit)
                .foregroundStyle(V.C.text3)
            HStack(spacing: V.S.gapS) {
                ForEach(Array(KeysCode.segments(code).enumerated()), id: \.offset) { pair in
                    Button {
                        UIPasteboard.general.string = pair.element
                        copiedSegment = pair.offset
                    } label: {
                        Text(pair.element)
                            .font(V.F.number17)
                            .foregroundStyle(V.C.text1)
                            .padding(.horizontal, V.S.gapMS)
                            .frame(minHeight: V.Hit.min)
                            .background(
                                copiedSegment == pair.offset ? V.C.blue.opacity(0.16) : V.C.cardAlt,
                                in: .rect(cornerRadius: V.R.control)
                            )
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("第 \(pair.offset + 1) 段 \(pair.element)，点按只复制这一段")
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 读数区

    private func factsBlock(_ key: KeyItem) -> some View {
        let expiry = KeysState.expiryLine(key)
        let remaining = KeysState.expiryReading(key, now: now)
        return VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "档案")
                VFieldRow(label: "类型", value: key.kind.rawValue, mono: false)
                VFieldRow(label: "归属", value: key.owner ?? "未归属", mono: false)
                VReadingGrid(items: [
                    .init(label: "到期日", value: expiry.value, unit: expiry.unit),
                    .init(label: "剩余", value: remaining.value, unit: remaining.unit, tint: remaining.tint),
                ])
                Divider().overlay(V.C.hairline)
                KeysInlineNote(tone: .neutral, text: "改到期日走 cmd0B 真下发到锁，回执成功才改本机台账 —— 不再只是本机备注。")
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 真动作

    private func actionsBlock(_ key: KeyItem) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 0) {
                VSectionLabel(text: "能做的事")
                    .padding(.bottom, V.S.gapS)
                expiryMenu(key)
                KeysDivider()
                KeysActionRow(
                    title: key.disabled ? "恢复使用" : "停用这枚凭证",
                    symbol: key.disabled ? "play.circle" : "pause.circle",
                    tint: key.disabled ? V.C.text1 : V.C.warning
                ) {
                    toggleDisabled(key)
                }
                if key.disabled {
                    KeysInlineNote(tone: .neutral, text: "停用只是本机状态：锁端凭证仍然有效，恢复使用即回到可用。要真正作废请用下面的「彻底删除」。")
                }
                if key.kind == .fingerprint {
                    KeysDivider()
                    KeysActionRow(title: "重录一枚替换它", symbol: "touchid") {
                        showReEnroll = true
                    }
                }
                if key.kind == .password || key.kind == .temp {
                    KeysDivider()
                    KeysActionRow(title: "改造密码值", symbol: "pencil") {
                        router.request(.dest(.keyCreate))
                        router.pending = .key(id: key.id)
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    /// 改到期：四档快捷 + 永久。都是真写台账（AppModel.keys），不是摆样子。
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
            if let actionError {
                Text(actionError).font(V.F.footnote).foregroundStyle(V.C.critical)
            }
        } label: {
            HStack(spacing: V.S.gapMS) {
                Image(systemName: "calendar.badge.clock")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon18)
                    .foregroundStyle(V.C.text2)
                    .frame(width: V.Icon.xl, alignment: .leading)
                    .accessibilityHidden(true)
                Text("改到期日")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: V.S.gapS)
                Image(systemName: "chevron.up.chevron.down")
                    .font(V.F.icon15Medium)
                    .foregroundStyle(V.C.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
        }
        .accessibilityLabel("改到期日")
    }

    // MARK: 危险动作

    private func dangerBlock(_ key: KeyItem) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "不可逆")
                Text("删除会同时从门锁和本机台账里移除这枚凭证，没有回收站。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                // 危险动作用语义色（State.critical），不用 signal 填充 —— 同屏的 signal 只留给主动作。
                KeysActionRow(title: "彻底删除", symbol: "trash", tint: V.C.critical) {
                    confirmDelete = true
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 不存在空态（凭证被删/被移走后仍可能有人跳过来）

    private var missingBlock: some View {
        VCard {
            VEmptyState(
                title: "这枚凭证已经不在了",
                message: "它可能刚被删除或停用。回钥匙列表看看还剩哪些凭证，或再新增一枚。",
                actionTitle: "回钥匙列表",
                systemImage: "key.slash"
            ) {
                router.keysPath = []
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 写台账（值语义：改就是换一条）

    private func setExpiry(_ key: KeyItem, days: Int?) {
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

    /// 停用 / 恢复使用：只改本机停用位（可恢复），**不发任何锁端删除命令**。
    /// 旧实现调 deletePassword/deleteFingerprint —— 用户点「停用」，锁端凭证直接消失且不可逆。
    private func toggleDisabled(_ key: KeyItem) {
        actionError = nil
        let mac = app.currentMac
        CredentialLocalState.setDisabled(mac: mac, id: key.id, !key.disabled)
        app.reloadKeys(mac)
    }

    /// 临时码 / 密码的「提前失效」滑杆：只在本机台账提示，不改锁端有效期（锁端仍按 0B 的 to）。
    @ViewBuilder
    private func earlyExpireCard(_ key: KeyItem) -> some View {
        if let alias = alias(of: key), key.kind == .temp || key.kind == .password {
            VCard {
                VStack(alignment: .leading, spacing: V.S.gapS) {
                    VSectionLabel(text: "提前失效提示", trailing: "\(CredentialOrg.earlyExpireMin(app.currentMac, alias)) 分钟")
                    Slider(
                        value: Binding(
                            get: { Double(CredentialOrg.earlyExpireMin(app.currentMac, alias)) },
                            set: { CredentialOrg.setEarlyExpireMin(app.currentMac, alias, Int($0.rounded())) }
                        ),
                        in: 0 ... 120,
                        step: 5
                    )
                    .tint(V.C.blue)
                    .accessibilityLabel("提前失效分钟数")
                    .accessibilityValue("\(CredentialOrg.earlyExpireMin(app.currentMac, alias)) 分钟")
                    Text("只在本机把到期提示提前 N 分钟（0 = 不提前）。锁端有效期不变 —— 这枚凭证在锁上仍然有效到原本的到期时刻。")
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pwd = DB.ledger(app.currentMac).pwds.first(where: { $0.alias == alias }),
                       CredentialOrg.earlyExpireMin(app.currentMac, alias) > 0 {
                        Text(CredentialOrg.earlyExpiryNote(app.currentMac, pwd))
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
    }

    private func deleteKey() {
        guard let key else { return }
        actionError = nil
        Task { @MainActor in
            let r: Result<Void, Error>
            if key.kind == .fingerprint, let batch = fpBatch(of: key) {
                r = await app.deleteFingerprint(batch: batch)
            } else if let alias = alias(of: key) {
                r = await app.deletePassword(alias: alias)
            } else {
                // 手机钥匙：本机台账撤销（锁端 pin 由 MobileKey 页的 revoke 走 cmd08）。
                app.keys.removeAll { $0.id == key.id }
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

// MARK: - 指纹重录替换（原 FpDetailStudio.swift:12,65-72）

/// 重录一枚指纹并替换旧批次：先走 cmd13/14 录新的，成功后才删旧批次。
/// 失败时旧批次保留 —— 不出现「旧的删了、新的没录上」这种把人关在门外的中间态。
struct FingerprintReEnrollSheet: View {
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
            ScrollView {
                VStack(alignment: .leading, spacing: V.S.gap16) {
                    SettingsHeader(
                        title: "重录指纹",
                        tone: error == nil ? .neutral : .attention,
                        status: error ?? (busy ? "请按 8 次指纹头 · 已按 \(fpCount)/8" : "录新的，成功后替换「\(key.name)」")
                    )
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapMS) {
                            VTextFieldRow(label: "指纹名称", text: $name, placeholder: key.name)
                            VFieldRow(label: "归属", value: key.owner ?? "未归属", mono: false)
                            if busy {
                                VBusyRow(text: "指纹录入中 · 已按 \(fpCount)/8 — 请把手指按在指纹头上再抬起")
                            }
                            VActionButton(title: busy ? "录入中…" : "开始重录", systemImage: "touchid") {
                                start()
                            }
                            .disabled(busy)
                            VOutlineButton(title: "取消") { dismiss() }
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)
                    SettingsNote(text: "重录会先下发新指纹；成功后才删除旧批次。失败时旧指纹原样保留，不会把人关在门外。")
                        .padding(.horizontal, V.S.pageGutter)
                }
                .padding(.vertical, V.S.gap16)
            }
            .background(CanvasBackground())
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("重录指纹")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name = key.name
                owner = key.owner
            }
        }
    }

    private func start() {
        guard !busy, let old = batch else {
            error = "这枚凭证没有指纹批次号"
            return
        }
        busy = true
        fpCount = 0
        error = nil
        Task { @MainActor in
            ScreenCare.keepingAwake(true)
            let result = await app.enrollFingerprint(
                name: name.isEmpty ? key.name : name,
                owner: owner,
                note: "重录替换 #\(old)"
            ) { n in
                fpCount = n
            }
            ScreenCare.keepingAwake(false)
            busy = false
            switch result {
            case .success(let newBatch):
                if newBatch != old {
                    let deleted = await app.deleteFingerprint(batch: old)
                    if case .failure(let e) = deleted {
                        error = "新指纹已录好，但旧批次删除失败：\(e.localizedDescription)"
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
