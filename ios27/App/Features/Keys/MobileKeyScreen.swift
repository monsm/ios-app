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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if owner == nil { owner = app.members.first { !$0.archived }?.name }
        }
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
                    ForEach(app.members.filter { !$0.archived }) { member in
                        KeysOwnerRow(
                            name: member.name,
                            keyCount: app.keys.filter { $0.owner == member.name }.count,
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
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 已签发

    private var issuedBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VSectionLabel(text: "本机签发的钥匙", trailing: "\(issued.count) 把")
                if issued.isEmpty {
                    KeysInlineNote(tone: .neutral, text: "还没有签发过。选一位成员、点上面的签发按钮 —— 签完这里会多一行，长按可以复制或撤销。")
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
                Text(key.owner ?? key.name)
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
                    UIPasteboard.general.string = key.code ?? key.id
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