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
    @State private var forever = true
    @State private var validTo = Date().addingTimeInterval(8 * 3600)
    @State private var errorText: String?
    /// 刚签发的那一条（用来给一次真回执，而不是一句空 toast）。
    @State private var justIssued: String?

    private var issued: [KeyItem] { app.keys.filter { $0.kind == .mobile } }

    /// 本机已签发的把数。真实的 PIN 池占用要问锁（deviceData.pins + ekey=1 的成员去重），
    /// 那条链路未接 —— 所以页头只说「本机签了几把」，不假装知道池里剩几个。
    private var issuedCount: Int { issued.count }

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 `List`（与门页同一配方）。
        // 「给谁签」「有效期」「已签发」三段都是**行式内容**，各走 `Section` + 系统行；
        // 空态卡与签发按钮区仍是卡片，用 `cardRow()`（`.plain` 样式没有系统左右留白，
        // cardRow 补回 pageGutter；plainRow 会让卡片贴边）。
        // 不再「ScrollView 里嵌 List」：那样要么双滚、要么手算行高，Dynamic Type 一大就裁。
        List {
            header.headerRow()
            if app.members.isEmpty {
                noMemberBlock.cardRow()
            } else {
                ownerSection
                periodSection
                issueActionCard.cardRow()
            }
            issuedSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.S.gap16, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapL, for: .scrollContent)
        .background(CanvasBackground())
        .navigationTitle("手机钥匙")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if owner == nil { owner = app.members.first { !$0.archived }?.name }
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
            Text("手机钥匙")
                .font(V.F.displayHome)
                .foregroundStyle(V.C.text1)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 主角：签发表单（拆成「给谁签」「有效期」两个 Section + 一张动作卡）

    private var ownerSection: some View {
        Section {
            ForEach(app.members.filter { !$0.archived }) { member in
                KeysOwnerRow(
                    name: member.name,
                    keyCount: app.keys.filter { $0.owner == member.id || $0.owner == member.name }.count,   // owner 有 id / 名字两种历史口径
                    selected: owner == member.name
                ) {
                    owner = member.name
                    errorText = nil
                }
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("给谁签")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Text(owner ?? "必选")
                    .font(V.F.footnote)
                    .foregroundStyle(owner == nil ? V.C.warning : V.C.text3)
            }
        }
    }

    private var periodSection: some View {
        Section {
            KeysChips(items: [true, false], title: { $0 ? "永久有效" : "自定义" }, selection: $forever)
            if !forever {
                DatePicker("到期时间", selection: $validTo, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                    .font(V.F.body)
                    .frame(minHeight: V.Hit.min)
            }
        } header: {
            Text("有效期")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
        }
    }

    /// 动作 + 回执 + 说明：这三样是「一次签发」的上下文，留在一张卡里，不摊成 List 行。
    private var issueActionCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapMS) {
                if let errorText {
                    KeysInlineNote(tone: .critical, text: errorText)
                }
                VActionButton(title: "签发一把手机钥匙", systemImage: "iphone.gen3.badge.key") {
                    issue()
                }
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
    }

    // MARK: 已签发

    /// 已签发 = 系统 `Section`：一行一把钥匙，行尾「⋯」保留，另加左滑撤销（destructive）。
    private var issuedSection: some View {
        Section {
            if issued.isEmpty {
                KeysInlineNote(tone: .neutral, text: "还没有签发过。选一位成员、点上面的签发按钮 —— 签完这里会多一行，点行尾的「⋯」可以复制或撤销。")
            } else {
                ForEach(issued) { key in
                    issuedRow(key)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                revoke(key)
                            } label: {
                                Label("撤销", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            HStack(spacing: V.S.gapS) {
                Text("本机签发的钥匙")
                    .font(V.F.section)
                    .foregroundStyle(V.C.text1)
                Spacer(minLength: 0)
                Text("\(issued.count) 把")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .monospacedDigit()
            }
            .textCase(nil)
        }
    }

    private func issuedRow(_ key: KeyItem) -> some View {
        let read = KeysState.expiryReading(key, now: KeysState.now())
        return HStack(alignment: .center, spacing: V.S.gapMS) {
            VStateDot(tone: KeysState.tone(key, now: KeysState.now()), word: KeysState.word(key, now: KeysState.now()))
            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text({
                    // 内部值出屏：key.owner 是成员 id（历史数据也可能是名字），换成可读名字；
                    // 解析不到时回落到这把钥匙自己的名字（不会出现一串十六进制）。
                    let who = CredentialOrg.ownerName(key.owner)
                    return who.isEmpty ? key.name : who
                }())
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
                    revoke(key)
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
        .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardPad, bottom: 0, trailing: V.S.cardPad))
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
    }

    // MARK: 真动作

    private func issue() {
        guard let owner else {
            errorText = "先选一位成员 —— 钥匙要归到某个人名下。"
            return
        }
        guard issuedCount < 16 else {
            errorText = "本机已签满 16 把。先撤销一把不用的，再来签新的。"
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
        Task { @MainActor in
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