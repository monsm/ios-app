// CredentialDetailScreen.swift —— 一张凭证就是一张票。
import SwiftUI

@MainActor
struct CredentialDetailScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var revealed = false
    @State private var confirmingDelete = false
    @State private var editingWindow = false
    @State private var toast: String?

    private var item: Credential? {
        app.credentials.first { $0.id == router.pendingCredentialID }
    }

    var body: some View {
        ScreenScroll {
            if let item {
                content(item)
            } else {
                EmptyNote(line: "这枚凭证不在了。",
                          detail: "它可能已经被删除，或换了一把锁。",
                          action: "返回") { dismiss() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingWindow) {
            if let item { ExpirySheet(item: item) }
        }
        .confirmationDialog("删除这枚凭证？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await remove() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("锁端会同步删除，无法恢复。")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(T.C.glassStrong, in: Capsule())
                    .overlay { Capsule().strokeBorder(T.C.glassEdge, lineWidth: 0.5) }
                    .padding(.bottom, 96)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func content(_ item: Credential) -> some View {
        NavRow(kicker: "通行 / \(item.kind.title)", back: { dismiss() }) {
            AnyView(
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(T.C.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
            )
        }

        ticket(item)
            .padding(.top, 10)

        ReadingRow(items: [
            (label: "生效", value: startText(item), unit: nil),
            (label: "到期", value: When.expiryLabel(item.expiresAt), unit: nil),
            (label: "录入", value: When.ago(Int64(item.createdAt)), unit: nil),
        ])
        .padding(.top, 26)

        SectionHead(index: "01", title: "归属")
        if let ownerID = item.ownerID, let member = app.members.first(where: { $0.id == ownerID || $0.name == ownerID }) {
            Button { router.openMember(member.id) } label: {
                MemberRow(member: member)
            }
            .buttonStyle(.plain)
        } else {
            ContentRow(symbol: "person", tone: .cool, title: "未归属",
                       subtitle: "这枚凭证还没有指定成员。")
        }

        let starred = CredStarStore.isStarred(app.currentMac, id: item.id)

        SectionHead(index: "02", title: "更多")
        Button {
            _ = CredStarStore.toggle(app.currentMac, id: item.id)
            app.reloadCredentials()
        } label: {
            ContentRow(symbol: starred ? "star.fill" : "star",
                       title: starred ? "取消星标" : "加星标",
                       subtitle: "星标只在本机，用来把常用的排在前面", chevron: true)
        }
        .buttonStyle(.plain)

        // 「修改有效期」只对密码 / 临时码有意义：指纹与手机钥匙在锁里没有起止时间，
        // 点进去只会改一个不存在的字段 —— 保存后什么都不变，却看起来像成功了。
        if item.kind == .password || item.kind == .temp {
            Button { editingWindow = true } label: {
                ContentRow(symbol: "calendar", title: "修改有效期", chevron: true)
            }
            .buttonStyle(.plain)
        }

        if item.kind == .password || item.kind == .temp || item.kind == .fingerprint {
            Button { toggleDisabled(item) } label: {
                ContentRow(symbol: item.disabled ? "play.circle" : "pause.circle",
                           title: item.disabled ? "恢复使用" : "停用这枚凭证",
                           subtitle: "只改本机标记，锁端不动", chevron: true)
            }
            .buttonStyle(.plain)
        }

        Button { confirmingDelete = true } label: {
            ContentRow(symbol: "trash", tone: .danger, title: "删除", chevron: true) {
                Text("不可恢复").type(T.F.caption).foregroundStyle(T.C.danger)
            }
        }
        .buttonStyle(.plain)

        if let note = item.note.isEmpty ? nil : item.note {
            Text(note)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, 14)
        }
        // 提示只画一处：底部那条浮动胶囊。原先这里还有一份内联的，
        // 同一个 toast 在屏幕上出现两次。
    }

    private func ticket(_ item: Credential) -> some View {
        DaylightPane(height: 268, showSill: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Kicker(text: "\(item.kind.title) · \(item.ownerName ?? "未归属")", dot: false, tint: T.C.ink2)
                    Spacer()
                    Badge(text: item.disabled ? "已停用" : (item.isExpired ? "已过期" : "有效"),
                          kind: item.disabled || item.isExpired ? .calm : .brass)
                }
                Spacer()
                Text(displayCode(item))
                    .type(T.F.code)
                    .tracking(revealed ? 2 : 6)
                    .monospacedDigit()
                    .foregroundStyle(T.C.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(hint(item))
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.top, 9)
                Spacer()
                HStack(spacing: 10) {
                    if item.kind == .password || item.kind == .temp {
                        Button {
                            withAnimation(T.M.snap) { revealed.toggle() }
                        } label: {
                            chipLabel(revealed ? "隐藏" : "显示", symbol: revealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(PressStyle())

                        Button {
                            copy(item)
                        } label: {
                            chipLabel("复制", symbol: "doc.on.doc")
                        }
                        .buttonStyle(PressStyle())
                    } else if item.kind == .mobile {
                        Button {
                            copyMobile(item)
                        } label: {
                            chipLabel("复制 ekey", symbol: "doc.on.doc")
                        }
                        .buttonStyle(PressStyle())
                    } else {
                        Button {
                            // 「重新录入」要落到指纹那条链上。
                            // 原先只是 push(.credentialCreate)，而新凭证页默认停在「密码」——
                            // 点指纹的重新录入，打开的是一张密码表单。
                            router.pendingCreateKind = "fingerprint"
                            router.push(.credentialCreate)
                        } label: {
                            chipLabel("重新录入", symbol: "touchid")
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .padding(24)
        }
    }

    private func chipLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(title).type(T.F.footnote).fontWeight(.medium)
        }
        .foregroundStyle(T.C.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(T.C.glass)
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
        }
    }

    private func displayCode(_ item: Credential) -> String {
        switch item.kind {
        case .password, .temp:
            if revealed, let plain = plainCode(item) { return plain }
            return item.masked ?? "••••••"
        case .fingerprint:
            return "指纹已录入"
        case .mobile:
            return item.masked ?? "手机钥匙"
        }
    }

    private func hint(_ item: Credential) -> String {
        switch item.kind {
        case .password, .temp:
            return revealed ? "复制后 90 秒自动从剪贴板清除" : "长按或点「显示」查看"
        case .fingerprint:
            return item.batch.map { "批次 #\($0) · 存在门锁里，不在手机上" } ?? "存在门锁里"
        case .mobile:
            // 本机没有任何把手机钥匙画成二维码的入口（唯一的二维码是「交给安卓」那张
            // **配对凭证**，不是这把钥匙）。原先写「用二维码交付给对方」，指的是一张
            // 并不存在的码 —— 真正能用的交付方式就是下面这枚「复制 ekey」。
            return "ekey 已签发 · 复制后单独发给对方"
        }
    }

    private func plainCode(_ item: Credential) -> String? {
        guard let alias = item.alias else { return nil }
        return DB.ledger(app.currentMac).pwds.first { $0.alias == alias }?.pwd
    }

    private func startText(_ item: Credential) -> String {
        let formatter = DF.cached("M/d")
        let date = Date(timeIntervalSince1970: item.createdAt / 1000)
        return formatter.string(from: date)
    }

    private func copy(_ item: Credential) {
        guard let value = plainCode(item) else { return }
        Clip.set(value)
        show("已复制 · 90 秒后自动清除")
    }

    private func copyMobile(_ item: Credential) {
        guard let id = item.mobileID,
              let key = MobileKeyService.list(app.currentMac).first(where: { $0.id == id }) else { return }
        guard !key.ekey.isEmpty else {
            // 旧备份恢复的钥匙可能只剩台账、没有 ekey。`Clip.set("")` 只会清空剪贴板，
            // 原先会静默"成功" —— 复制出去的是空气。
            show("这把钥匙没有存下 ekey。先吊销，再重新签发。")
            return
        }
        Clip.set(key.ekey)
        show("ekey 已复制 · 90 秒后自动清除")
    }

    private func toggleDisabled(_ item: Credential) {
        CredentialLocalState.setDisabled(mac: app.currentMac, id: item.id, !item.disabled)
        app.reloadCredentials()
    }

    private func remove() async {
        guard let item else { return }
        switch item.kind {
        case .password, .temp:
            if let alias = item.alias {
                let result = await app.deletePassword(alias: alias)
                if case .failure(let error) = result { show(error.localizedDescription); return }
            }
        case .fingerprint:
            if let batch = item.batch {
                let result = await app.deleteFingerprint(batch: batch)
                if case .failure(let error) = result { show(error.localizedDescription); return }
            }
        case .mobile:
            if let id = item.mobileID,
               let key = MobileKeyService.list(app.currentMac).first(where: { $0.id == id }) {
                let result = await app.revokeMobileKey(key)
                if case .failure(let error) = result { show(error.localizedDescription); return }
            }
        }
        dismiss()
    }

    private func show(_ text: String) {
        withAnimation(T.M.snap) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(T.M.snap) { if toast == text { toast = nil } }
        }
    }
}

// MARK: - 改有效期

@MainActor
struct ExpirySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let item: Credential

    @State private var start: Date
    @State private var end: Date
    @State private var forever: Bool
    @State private var busy = false
    @State private var errorLine: String?

    /// 起止时间必须**从这枚凭证现在的值**起步。
    ///
    /// 原实现固定成「现在 → 七天后」，而保存会把两个日期原样下发给锁：
    /// 于是打开「修改有效期」什么都不改直接保存，
    /// 一枚设成一百年的密码就被改成七天，一枚一小时的临时码被延长成七天。
    /// 这不是「默认值」，是**把真实值覆盖掉**。
    init(item: Credential) {
        self.item = item
        let now = Date()
        let from = item.validFrom.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? now
        let to = item.expiresAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            ?? now.addingTimeInterval(7 * 86400)
        _start = State(initialValue: from)
        _end = State(initialValue: to)
        _forever = State(initialValue: item.expiresAt == nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DisplayLine(text: "给这枚钥匙\n一个期限。", size: 30)
                        .padding(.top, 8)

                    SwitchLine(title: "长期有效", detail: "不设到期时间；随时可以再改。", isOn: $forever)
                        .padding(.top, 12)

                    if !forever {
                        DatePicker("生效", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .type(T.F.footnote)
                            .padding(.vertical, 8)
                        DatePicker("到期", selection: $end,
                                   in: start.addingTimeInterval(60)...,
                                   displayedComponents: [.date, .hourAndMinute])
                            .type(T.F.footnote)
                            .padding(.vertical, 8)
                    }

                    if let errorLine {
                        Text(errorLine)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.danger)
                            .padding(.top, 8)
                    }

                    PrimaryButton(title: "保存并下发", busy: busy) {
                        Task { await save() }
                    }
                    .padding(.top, 22)
                }
                .padding(22)
            }
            .background(T.C.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard let alias = item.alias else {
            // 走到这里说明入口给错了（指纹 / 手机钥匙没有 alias）。
            errorLine = "这枚凭证没有有效期可改。"
            return
        }
        // 结束早于开始的窗口会被原样下发给锁 —— 锁可能回 rc=0，
        // 界面却把凭证显示成「已过期」，用户完全看不出是自己填反了。
        guard forever || end > start else {
            errorLine = "到期时间要在生效时间之后。"
            return
        }
        busy = true
        defer { busy = false }
        let from = forever ? "2010-01-01 00:00" : AppModel.stamp(start)
        let to = forever ? "2118-01-01 00:00" : AppModel.stamp(end)
        let result = await app.setPasswordExpiry(alias: alias, from: from, to: to)
        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            errorLine = error.localizedDescription
        }
    }
}
