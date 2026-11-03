// MobileKeyScreen.swift —— 手机钥匙（数字钥匙）的签发与撤销。
//
// 这一屏干什么：给某位成员签一把手机钥匙（选有效期 → 分配一个未占用的 PIN → 交给对方），
// 并列出本机签过的钥匙。措辞纪律：「签发」只写本机台账，「交付」是把钥匙内容给对方 —— 两件事不混。
// 数据从哪来：AppModel.keys 里 kind == .mobile 的条目；成员来自 AppModel.members。
// 主动作：签发一把手机钥匙（唯一会真正增加一条台账的动作）。
import SwiftUI
import UIKit

struct MobileKeyScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var owner: String?
    /// 2026-11-03（全功能点排查）：本屏原来**没有忙态** —— 连点两次「签发」会真的签两把，
    /// 每把都要从锁的 PIN 池里占一个名额（池子只有 64 个）。同一处也没有撤销确认。
    @State private var busy = false
    @State private var revokeTarget: KeyItem?
    @State private var forever = true
    @State private var validTo = Date().addingTimeInterval(8 * 3600)
    @State private var errorText: String?
    /// 刚签发的那一条（用来给一次真回执，而不是一句空 toast）。
    @State private var justIssued: String?

    private var issued: [KeyItem] { app.keys.filter { $0.kind == .mobile } }

    /// 本机已签发的把数。真实的 PIN 池占用要问锁（deviceData.pins + ekey=1 的成员去重），
    /// 那条链路未接 —— 所以页头只说「本机签了几把」，不假装知道池里剩几个。
    private var issuedCount: Int { issued.count }

    /// 这把锁的 PIN 池大小 —— 签发真正会被卡住的上限（不是固定的 16）。
    /// 这把锁的 PIN 池**可签发**上限。
    /// 2026-11-04：`MobileKeyService.availablePin` 从 `pins[1]` 起分配 —— 第 0 枚是
    /// 配网 ekey 嵌的那一枚，发给手机钥匙再撤销会把它从锁里删掉（真机 rc=2 根因）。
    /// 所以可用名额是 `池子 - 1`，不是池子本身。
    private var kcPoolSize: Int {
        max(0, (app.currentKeychain?.pins.filter { !$0.isEmpty }.count ?? 1) - 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: V.S.gap16) {
                header
                if app.members.isEmpty {
                    noMemberBlock
                } else {
                    issueBlock
                }
                issuedBlock
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("手机钥匙")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if owner == nil { owner = app.members.first { !$0.archived }?.name }
        }
        .confirmationDialog("撤销这把手机钥匙？", isPresented: Binding(
            get: { revokeTarget != nil },
            set: { if !$0 { revokeTarget = nil } }
        ), titleVisibility: .visible, presenting: revokeTarget) { key in
            Button("撤销", role: .destructive) { revoke(key); revokeTarget = nil }
            Button("取消", role: .cancel) { revokeTarget = nil }
        } message: { key in
            Text("「\(CredentialOrg.ownerName(key.owner).isEmpty ? key.name : CredentialOrg.ownerName(key.owner))」这把钥匙会立刻失效，对方再也开不了门。锁端的 PIN 名额不会自动收回。")
        }
    }

    /// 见下方说明：`foreignKeyHint` 此前零调用。拿不到锁状态（没连上）时返回 nil —— 不给无依据的断言。
    private var foreignHint: String? {
        guard let kc = app.currentKeychain else { return nil }
        return MobileKeyService.foreignKeyHint(pinInfoBinding: app.lastStatus?.status.pinInfoBinding ?? 0, kc: kc)
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
                        // 2026-11-03（全维度整理）：标题交给系统导航栏（大标题），页内不再自绘。
            HStack(spacing: V.S.gapS) {
                VStateDot(tone: app.lock == nil ? .attention : (issued.isEmpty ? .neutral : .ok),
                         word: issued.isEmpty ? "还没有签发" : "已签发 \(issued.count) 把")
                Text("本机签了 \(issuedCount) 把 · 锁里 PIN 池的占用要连上锁才知道")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text2)
                Spacer(minLength: 0)
            }
            // 2026-11-01：`MobileKeyService.foreignKeyHint` 早就写好了却**从没被调用过**（全仓仅定义处）——
            // 它算的是「锁端已绑定 N 个 PIN、本机只记 M 个」的差额，提示差额可能是别人发的钥匙。
            // 删除钥匙前这条提示很重要（删错别人的钥匙 = 让别人进不了门），接上。
            if let foreignHint {
                KeysInlineNote(tone: .attention, text: foreignHint)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 主角：签发表单

    private var issueBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                VSectionLabel(text: "给谁签", trailing: owner ?? "必选")
                VStack(spacing: V.S.gapXXS) {
                    ForEach(MemberHub.sortedForPicker(app.members.filter { !$0.archived }, keys: app.keys)) { member in
                        KeysOwnerRow(
                            name: member.name,
                            keyCount: app.keys.filter { $0.owner == member.id || $0.owner == member.name }.count,   // owner 有 id / 名字两种历史口径
                            selected: owner == member.name
                        ) {
                            owner = member.name
                            errorText = nil
                        }
                    }
                }

                Divider().overlay(V.C.hairline)

                VSectionLabel(text: "有效期")
                KeysChips(items: [true, false], title: { $0 ? "永久有效" : "自定义" }, selection: $forever)
                if !forever {
                    DatePicker("到期时间", selection: $validTo, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .font(V.F.body)
                        .frame(minHeight: V.Hit.min)
                }

                if let errorText {
                    KeysInlineNote(tone: .critical, text: errorText)
                }

                VActionButton(title: busy ? "签发中…" : "签发一把手机钥匙", systemImage: "iphone.gen3.badge.key") {
                    issue()
                }
                .disabled(busy)
                if let justIssued {
                    VStatusLine(tone: .ok, text: "已签发给 \(justIssued) —— 到下面的钥匙行里点「⋯ → 复制开锁凭证」交给对方。")
                }
                Text(forever
                     ? "永久档与锁端「永久」同口径。签发只写本机台账 —— 还要点下面那把钥匙行里的「交付」交给对方。"
                     : "自定义档到期后这把钥匙自动失效，不用手动撤销。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 已签发

    private var issuedBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "本机签发的钥匙", trailing: "\(issued.count) 把")
                if issued.isEmpty {
                    // 2026-11-03（交互 QA）：原文写「长按可以复制或撤销」—— 实际交互是行尾的「⋯」菜单
                // （见 issuedRow 里的 Menu）。长按在这里什么都不会发生。
                KeysInlineNote(tone: .neutral, text: "还没有签发过。选一位成员、点上面的签发按钮 —— 签完这里会多一行，点行尾的「⋯」可以复制或撤销。")
                        .frame(minHeight: V.Hit.min)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(issued.enumerated()), id: \.offset) { pair in
                            if pair.offset > 0 { KeysDivider() }
                            issuedRow(pair.element)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    private func issuedRow(_ key: KeyItem) -> some View {
        let read = KeysState.expiryReading(key, now: KeysState.now())
        return HStack(alignment: .center, spacing: V.S.gapMS) {
            VStateDot(tone: KeysState.tone(key, now: KeysState.now()), word: KeysState.word(key, now: KeysState.now()))
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                // 2026-11-03：原来 `key.owner ?? key.name` —— owner 是成员 id，会显示成一串 UUID。
                // 解析不出名字时回落到钥匙自己的名字。
                Text(CredentialOrg.ownerName(key.owner).isEmpty ? key.name : CredentialOrg.ownerName(key.owner))
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                Text("手机钥匙 · \(KeysState.word(key, now: KeysState.now()))")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text2)
            }
            Spacer(minLength: V.S.gapS)
            VReading(value: read.value, unit: read.unit, font: V.F.number15, tint: read.tint, animated: false)
            Menu {
                Button {
                    Clip.set(key.code ?? key.id)
                } label: {
                    Label("复制开锁凭证", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    // 2026-11-03：撤销是"让对方进不了门"的动作，原来一点就执行。
                    // 改成先弹确认（带上钥匙归属与剩余有效期，让用户认得出是哪一把）。
                    revokeTarget = key
                } label: {
                    Label("撤销这把钥匙", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(V.F.icon18Medium)
                    .foregroundStyle(V.C.text2)
                    .frame(width: V.Hit.min, height: V.Hit.min)
                    .contentShape(.rect)
            }
            .accessibilityLabel("钥匙操作：复制或撤销")
        }
        .frame(minHeight: V.Hit.min + V.S.gapS)
        .accessibilityElement(children: .contain)
    }

    // MARK: 空态（没有成员时先给去处）

    private var noMemberBlock: some View {
        VCard {
            VEmptyState(
                title: "还没有成员",
                message: "手机钥匙要签给具体某个人。先去「家」建一位成员，回来就能签。",
                actionTitle: "去新建成员",
                systemImage: "person.2"
            ) {
                router.request(.dest(.memberCreate))
            }
            .padding(.vertical, V.S.gapXXL)
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 真动作

    private func issue() {
        guard !busy else { return }
        guard let owner else {
            errorText = "先选一位成员 —— 钥匙要归到某个人名下。"
            return
        }
        // 2026-11-04（错误归因 · 上限不是 16）：这条守的是**本机记录条数**，而真正卡住
        // 签发的是**锁端 PIN 池**（`MobileKeyService.availablePin` 返回 nil 时抛
        // 「PIN 池已用尽」。池子大小来自 `kc.pins.count`，不是固定 16）。
        // 而且文案说「先撤销一把不用的」—— 撤销确实会还一个名额，但用户可能根本没有
        // 16 把（这台锁池子更小）。改成如实说明两个可能，并把真实上限报出来。
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
                // 真链路：从锁 PIN 池分配 → buildEkeyShare 签 ekey → 落 kf_mobilekeys。
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
                // 真链路：cmd08 delPins 把 pin 从锁里删掉，再删本机记录。
                try await MobileKeyService.revoke(host: app, kc: kc, key: mk)
                app.reloadKeys(kc.mac)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}