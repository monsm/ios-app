// MobileKeyHomeScreen.swift —— 手机钥匙（V8 设计语言）
//
// 与 MobileKeyScreen 的能力对齐：签发给某位成员（永久/自定义有效期）、列出本机签发的钥匙、
// 复制开锁凭证、撤销（带确认）。措辞纪律不变：「签发」只写本机台账，「交付」是把钥匙内容给对方。
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

    private var issued: [KeyItem] { app.keys.filter { $0.kind == .mobile } }
    private var issuedCount: Int { issued.count }

    private var kcPoolSize: Int {
        max(0, (app.currentKeychain?.pins.filter { !$0.isEmpty }.count ?? 1) - 1)
    }

    private var foreignHint: String? {
        guard let kc = app.currentKeychain else { return nil }
        return MobileKeyService.foreignKeyHint(pinInfoBinding: app.lastStatus?.status.pinInfoBinding ?? 0, kc: kc)
    }

    private var judgement: String {
        if app.members.isEmpty { return "还没有成员" }
        if issued.isEmpty { return "还没有签发过" }
        return "已签发 \(issuedCount) 把"
    }

    private var lead: String {
        if app.members.isEmpty {
            return "手机钥匙要签给具体某个人。先去「家」建一位成员，回来就能签。"
        }
        return "本机签了 \(issuedCount) 把。锁里 PIN 池的占用要连上锁才知道 —— 这里不假装知道剩几个。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if let foreignHint {
                VFailure(what: "锁端与本机的钥匙数对不上", why: foreignHint,
                         next: "删除前先确认这不是别人的钥匙 —— 删错等于让别人进不了门。")
            }
            if app.members.isEmpty {
                VEmpty(
                    title: "还没有成员",
                    reason: "手机钥匙要签给具体某个人。先去「家」建一位成员，回来就能签。",
                    actionTitle: "去新建成员"
                ) { router.request(.dest(.memberCreate)) }
            } else {
                issueCard
            }
            issuedCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if owner == nil { owner = app.members.first { !$0.archived }?.name }
        }
        .v8Confirm(
            isPresented: $confirmRevoke,
            title: "撤销这把手机钥匙？",
            consequence: "这把钥匙会立刻失效，对方再也开不了门。锁端的 PIN 名额不会自动收回 —— 想换人请重新签发一把。",
            confirmTitle: "撤销"
        ) {
            if let key = revokeTarget { revoke(key) }
            revokeTarget = nil
        }
    }

    // MARK: - 签发表单

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

    // MARK: - 真动作（与 MobileKeyScreen 同口径）

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
    }
}
