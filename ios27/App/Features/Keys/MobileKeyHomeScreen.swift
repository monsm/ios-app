// MobileKeyHomeScreen.swift —— 手机钥匙（V8 设计语言）
//
// 02 §3.2 M15 归并后的宿主页：mobileKey（签发 / 列表 / 撤销）+ shareToAndroid（分享给安卓，二维码与交付）
// 是「同一对象的签发与交付」，所以交付入口放在签发卡内（同一屏，不再两张独立卡、两个路由）。
// 措辞纪律不变：「签发」只写本机台账，「交付」是把钥匙内容给对方。
//
// 能力守恒（shareToAndroid 并入部分）：AndroidPair.payload 真链路、KeysQR 出图、5 种未就绪原因逐条说清、
// captureShield 截图遮挡、ShareLink / Clip.set 交付、空壳不生成码、风险卡。
import SwiftUI
import UIKit

struct MobileKeyHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var owner: String?
    @State private var busy = false
    @State private var revokeTarget: KeyItem?
    @State private var forever = true
    @State private var validTo = Date().addingTimeInterval(8 * 3600)
    @State private var errorText: String?
    @State private var justIssued: String?
    @State private var confirmRevoke = false
    // —— shareToAndroid 并入段的状态
    @State private var qr: UIImage?
    @State private var payloadText = ""
    @State private var copied = false

    private var issued: [KeyItem] { app.keys.filter { $0.kind == .mobile } }
    private var issuedCount: Int { issued.count }
    private var decoyed: Bool { DB.isDecoy }

    private var kcPoolSize: Int {
        max(0, (app.currentKeychain?.pins.filter { !$0.isEmpty }.count ?? 1) - 1)
    }

    private var foreignHint: String? {
        guard let kc = app.currentKeychain else { return nil }
        return MobileKeyService.foreignKeyHint(pinInfoBinding: app.lastStatus?.status.pinInfoBinding ?? 0, kc: kc)
    }

    /// 可交付的钥匙：本机签发、未停用、未过期，且带 ekey（原 ShareToAndroid 页的判据，原样保留）。
    private var deliverable: KeyItem? {
        let now = KeysState.now()
        return app.keys
            .filter { $0.kind == .mobile && !$0.disabled && !KeysState.expired($0, now: now) }
            .filter { ($0.code ?? "").isEmpty == false }
            .sorted { ($0.expiresAt ?? Int64.max) > ($1.expiresAt ?? Int64.max) }
            .first
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示手机钥匙" }
        if app.members.isEmpty { return "还没有成员" }
        if issued.isEmpty { return "还没有签发过" }
        return "已签发 \(issuedCount) 把"
    }

    private var lead: String? {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。钥匙列表与配对码都不显示。"
        }
        if app.members.isEmpty {
            return nil
        }
        return "本机签了 \(issuedCount) 把。锁里 PIN 池的占用要连上锁才知道 —— 这里不假装知道剩几个。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if decoyed {
                decoyCard
            } else {
                if let foreignHint {
                    VFailure(what: "锁端与本机的钥匙数对不上", why: foreignHint,
                             next: "删除前先确认这不是别人的钥匙 —— 删错等于让别人进不了门。")
                }
                if app.members.isEmpty {
                    VEmpty(
                        title: "新建一位成员",
                        reason: "手机钥匙要签给具体某个人。先去「家」建一位成员，回来就能签。",
                        actionTitle: "去新建成员"
                    ) { router.request(.dest(.memberCreate)) }
                } else {
                    issueCard
                }
                issuedCard
                shareSection
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if owner == nil { owner = app.members.first { !$0.archived }?.name }
            buildPayload()
        }
        .onChange(of: app.lock?.id) { _, _ in buildPayload() }
        .onChange(of: issuedCount) { _, _ in buildPayload() }
        .v8Confirm(
            isPresented: $confirmRevoke,
            title: "撤销这把手机钥匙？",
            consequence: "这把钥匙会立刻失效，对方再也开不了门。锁端的 PIN 名额不会自动收回 —— 想换人请重新签发一把。",
            confirmTitle: "撤销"
        ) {
            if let key = revokeTarget { revoke(key) }
            revokeTarget = nil
        }
    }    // MARK: - 签发表单

    private var issueCard: some View {
        VCard2 {
            VCardHead(eyebrow: "给谁签", statement: owner ?? "必选")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(MemberHub.sortedForPicker(app.members.filter { !$0.archived }, keys: app.keys)) { member in
                    Button {
                        owner = member.name
                        errorText = nil
                    } label: {
                        VDataRow(
                            tag: member.role.rawValue,
                            tagTint: member.role == .owner ? V8.C.accent : V8.C.ink4,
                            title: member.name,
                            detail: owner == member.name ? "已选" : nil,
                            value: "\(app.keys.filter { CredentialOrg.ownerMatches($0.owner, memberID: member.id, memberName: member.name) }.count)",
                            unit: "枚"
                        )
                    }
                    .buttonStyle(.plain)
                    if member.id != MemberHub.sortedForPicker(app.members.filter { !$0.archived }, keys: app.keys).last?.id {
                        VDotRule()
                    }
                }
            }
            .padding(.top, V8.S.gapS)

            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("有效期")
                .font(V8.T.label)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
            HStack(spacing: V8.S.gapChip) {
                validityChip("永久有效", on: forever) { forever = true }
                validityChip("自定义", on: !forever) { forever = false }
            }
            .padding(.top, V8.S.gapS)
            if !forever {
                DatePicker("到期时间", selection: $validTo, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                    .font(V8.T.body)
                    .frame(minHeight: V8.H.min)
                    .padding(.top, V8.S.gapS)
            }
            if let errorText {
                VFailure(what: "签发没有完成", why: errorText, next: "按上面的提示处理后重试；已签发的钥匙不受影响。")
                    .padding(.top, V8.S.gapM)
            }
            if let justIssued {
                Text("已签发给 \(justIssued) —— 到下面的钥匙行里点「⋯ → 复制开锁凭证」交给对方。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ok)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                issue()
            } label: {
                Text(busy ? "签发中…" : "签发一把手机钥匙")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(busy || app.currentKeychain == nil)
            .opacity((busy || app.currentKeychain == nil) ? 0.45 : 1)
            .padding(.top, V8.S.gapM)
            if app.currentKeychain == nil {
                Text("还没有添加门锁 —— 先在「门」页添加一把锁，再回来签发手机钥匙。")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(forever
                 ? "永久档与锁端「永久」同口径。签发只写本机台账 —— 还要在下面那把钥匙行里「复制开锁凭证」交给对方。"
                 : "自定义档到期后这把钥匙自动失效，不用手动撤销。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func validityChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(V8.T.tab)
                .foregroundStyle(on ? V8.C.chipOn : V8.C.ink1)
                .padding(.horizontal, V8.S.gapM)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(on ? V8.C.accent : V8.C.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 已签发

    private var issuedCard: some View {
        VCard2 {
            VCardHead(eyebrow: "本机签发的钥匙", statement: "\(issuedCount) 把")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if issued.isEmpty {
                Text("还没有签发过。选一位成员、点上面的签发按钮 —— 签完这里会多一行，点行尾的「⋯」可以复制或撤销。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(issued) { key in
                        HStack(spacing: V8.S.gapS) {
                            VDataRow(
                                tag: "手机钥匙",
                                tagTint: V8.D.mobile,
                                title: CredentialOrg.ownerName(key.owner).isEmpty ? key.name : CredentialOrg.ownerName(key.owner),
                                detail: KeysState.word(key, now: KeysState.now()),
                                value: ""
                            )
                            Menu {
                                Button { Clip.set(key.code ?? key.id) } label: {
                                    Label("复制开锁凭证", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    revokeTarget = key
                                    confirmRevoke = true
                                } label: {
                                    Label("撤销这把钥匙", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(V8.T.chipValue)
                                    .foregroundStyle(V8.C.ink3)
                                    .frame(width: V8.H.min, height: V8.H.min)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("钥匙操作：复制或撤销")
                        }
                        if key.id != issued.last?.id { VDotRule() }
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    // MARK: - 真动作（与旧 MobileKeyScreen 同口径，一行不少）

    private func issue() {
        guard !busy else { return }
        guard let owner else {
            errorText = "先选一位成员 —— 钥匙要归到某个人名下。"
            return
        }
        let hardCap = max(kcPoolSize, issuedCount)
        guard issuedCount < hardCap else {
            errorText = "本机已签 \(issuedCount) 把，达到这把锁的 PIN 池上限（\(kcPoolSize) 个）。先撤销一把不用的，再来签新的。"
            return
        }
        guard let kc = app.currentKeychain else {
            errorText = "还没有添加门锁"
            return
        }
        guard let member = DB.members().first(where: { $0.name == owner }) else {
            errorText = "找不到这位成员"
            return
        }
        let df = DF.cached("yyyy-MM-dd HH:mm")
        let fromText = df.string(from: Date())
        let toText = df.string(from: validTo)
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                _ = try await MobileKeyService.issue(kc: kc, member: member,
                                                     forever: forever,
                                                     validFrom: fromText, validTo: toText)
                app.reloadKeys(kc.mac)
                justIssued = owner
                errorText = nil
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func revoke(_ key: KeyItem) {
        guard let kc = app.currentKeychain else { return }
        guard let mk = MobileKeyService.list(kc.mac).first(where: { "mkey:\($0.id)" == key.id }) else {
            app.keys.removeAll { $0.id == key.id }
            return
        }
        Task { @MainActor in
            do {
                try await MobileKeyService.revoke(host: app, kc: kc, key: mk)
                app.reloadKeys(kc.mac)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }    // MARK: - 分享给安卓（原 shareToAndroid 页整段并入：同一对象的「交付」）

    /// 02 §3.2 M15：签发与交付是同一对象的两面。这一段不是链接，是原页的能力整体搬家 ——
    /// AndroidPair.payload / KeysQR / captureShield / 5 种未就绪原因 / 风险卡一个不少。
    /// captureShield 原来挂在整页上；并入后挂在这一段（Group）上：遮挡范围是含二维码的交付段。
    private var shareSection: some View {
        Group {
            if app.lock == nil {
                VEmpty(
                    title: "添加一把门锁",
                    reason: "分享是把这把锁的钥匙递给安卓。先添加门锁并走完配网，这里才有东西可分享。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else if let image = qr {
                qrCard(image)
                shareCard
            } else {
                blockedCard
            }
            riskCard
        }
        .captureShield("这张二维码是开锁钥匙\n屏幕正在被录制或截图，已遮挡")
    }

    /// 生成载荷（会话级口令 + 锁身份 + 钥匙）。空壳与缺钥匙时都不生成假码。
    private func buildPayload() {
        guard !DB.isDecoy else {
            qr = nil
            payloadText = ""
            return
        }
        guard deliverable != nil else {
            qr = nil
            payloadText = ""
            return
        }
        guard let kc = app.currentKeychain, let p = AndroidPair.payload(kc) else {
            qr = nil
            payloadText = ""
            return
        }
        payloadText = p
        qr = KeysQR.image(p)
    }

    private func qrCard(_ image: UIImage) -> some View {
        VCard2 {
            VCardHead(eyebrow: "分享给安卓 · 配对二维码", statement: "让对方的安卓 App 扫这张码", trailing: "一次性")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: V8.G.heroOuter)
                .frame(maxWidth: .infinity)
                .padding(.top, V8.S.gapM)
                .accessibilityLabel("这把锁的配对二维码")
            VStack(spacing: 0) {
                VDataRow(tag: "锁", tagTint: V8.C.ink4, title: app.lock?.name ?? "—", value: "")
                VDotRule()
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: app.lock?.model ?? "—", value: "")
                VDotRule()
                VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: app.lock?.id ?? "—", value: "")
                VDotRule()
                VDataRow(tag: "载荷", tagTint: V8.C.ink4, title: "mac / pid / ekey", value: "")
            }
            .padding(.top, V8.S.gapL)
            Text("这串是「本机钥匙串里的那枚开锁凭证」+ 锁身份，不是上面那把手机钥匙 —— 扫完能开这把锁，但有效期与本机这把相同。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shareCard: some View {
        VCard2 {
            VCardHead(eyebrow: "交付方式", statement: copied ? "已复制配对串" : "分享或复制")
            VDivider2()
                .padding(.top, V8.S.gapM)
            ShareLink(item: payloadText,
                      preview: SharePreview("配对码", image: Image(systemName: "qrcode"))) {
                HStack(spacing: V8.S.gapS) {
                    Image(systemName: "square.and.arrow.up")
                        .font(V8.T.chipValue)
                        .accessibilityHidden(true)
                    Text("分享这段配对串")
                        .font(V8.T.tab)
                }
                .foregroundStyle(V8.C.chipOn)
                .frame(maxWidth: .infinity)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .accessibilityLabel("分享配对串")
            .padding(.top, V8.S.gapM)
            Button {
                Clip.set(payloadText)
                copied = true
            } label: {
                Text(copied ? "已复制" : "复制配对串")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制配对串")
            .padding(.top, V8.S.gapS)
            Text("这串是安卓配对码（含 mac / pid / ekey，刻意不含 skey）。当面扫、单独发给本人，不要发群里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 未就绪：说清缺什么 + 给下一步。5 种原因逐条保留（原页 blockedReason 一字未减）。
    private var blockedCard: some View {
        VCard2 {
            VCardHead(eyebrow: "分享给安卓 · 就绪度", statement: "缺一把可交付的手机钥匙", trailing: "缺 1 样")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "锁", value: app.lock?.model ?? "—"),
                .init(label: "手机钥匙", value: "缺")
            ])
            .padding(.top, V8.S.gapM)
            Text(blockedReason)
                .font(V8.T.body)
                .foregroundStyle(V8.C.warn)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("在上面签一把手机钥匙，这一段就会变成可扫码 —— 签发与交付在这里是同一件事。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var blockedReason: String {
        let now = KeysState.now()
        let mobile = app.keys.filter { $0.kind == .mobile }
        if deliverable != nil {
            return "本机钥匙串里没有可用的开锁凭证 —— 可能是配网没走完，或钥匙串被清掉。请重新添加这把锁。"
        }
        if mobile.isEmpty {
            return "安卓端要拿到一把本机签发的手机钥匙才能开门。现在一把都没有，所以这里不放一张开不了门的码。"
        }
        if mobile.allSatisfy({ $0.disabled }) {
            return "这把锁的手机钥匙都被停用了 —— 停用的钥匙开不了门，所以这里不放码。到凭证页重新启用，或签一把新的。"
        }
        if mobile.allSatisfy({ KeysState.expired($0, now: now) }) {
            return "这把锁的手机钥匙都已过期 —— 过期的钥匙开不了门，所以这里不放码。先签一把新的，再回来。"
        }
        if mobile.allSatisfy({ ($0.code ?? "").isEmpty }) {
            return "手机钥匙记录里没有 ekey —— 本机没存下可交付的开锁凭证（可能是旧备份恢复的）。请在凭证页重新签一把。"
        }
        return "没有可交付的手机钥匙：需要一把未停用、未过期、且带 ekey 的。请到凭证页检查。"
    }

    private var riskCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "这张码等于一把钥匙", statement: "别截图存相册")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("谁扫到它，谁就能开这把锁。只当面扫，或单独发给本人；别截图存相册、别发到群里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 空壳（钥匙列表与配对码两段共用）

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "手机钥匙", statement: "空壳模式只读")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，钥匙列表不显示，也不生成配对码 —— 二维码里是本机钥匙串的真实开锁凭证，不能出现在被胁迫的屏幕上。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
