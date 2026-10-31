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

    private var key: KeyItem? {
        guard let keyID else { return nil }
        return app.keys.first { $0.id == keyID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                if let key {
                    header(key)
                    codeBlock(key)
                    factsBlock(key)
                    actionsBlock(key)
                    dangerBlock(key)
                } else {
                    missingBlock
                }
            }
            .padding(.vertical, T.S.l)
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
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text(key.name)
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            HStack(spacing: T.S.s) {
                StateDot(tone: KeysState.tone(key, now: now), word: KeysState.word(key, now: now))
                Text("\(key.kind.rawValue) · \(KeysState.word(key, now: now))")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 主角：码值

    private func codeBlock(_ key: KeyItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: key.kind == .fingerprint ? "指纹" : "码值", trailing: key.code == nil ? nil : "逐位点开")
                if let code = key.code, !code.isEmpty {
                    KeysMaskedCode(value: code, size: 24, revealed: $revealed)
                        .padding(.vertical, T.S.xs)
                    HStack(spacing: T.S.s) {
                        SecondaryAction(title: "复制整条", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = code
                        }
                        SecondaryAction(title: "复遮", systemImage: "eye.slash") {
                            revealed = []
                        }
                    }
                    if code.count >= 8 {
                        segmentRow(code)
                    }
                } else if key.kind == .fingerprint {
                    Text("指纹没有码值。它在门锁上按 8 次录进去，开门时按手指就行。")
                        .font(T.F.body)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    KeysInlineNote(tone: .attention, text: "这条当时没留存明文。可在门锁键盘上核对后重填，或直接改造一次密码值。")
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func segmentRow(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: T.S.s) {
            Text("按 4 位分段转述 · 点一段只复制那一段")
                .font(T.F.unit)
                .foregroundStyle(Ink.inkFaint)
            HStack(spacing: T.S.s) {
                ForEach(Array(KeysCode.segments(code).enumerated()), id: \.offset) { pair in
                    Button {
                        UIPasteboard.general.string = pair.element
                        copiedSegment = pair.offset
                    } label: {
                        Text(pair.element)
                            .font(T.F.reading(17, weight: .medium))
                            .foregroundStyle(Ink.ink)
                            .padding(.horizontal, T.S.m)
                            .frame(minHeight: T.Hit.min)
                            .background(
                                copiedSegment == pair.offset ? Signal.wash : Ink.plateAlt,
                                in: .rect(cornerRadius: T.R.control)
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
        return Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "档案")
                FieldRow(label: "类型", value: key.kind.rawValue, mono: false)
                FieldRow(label: "归属", value: key.owner ?? "未归属", mono: false)
                ReadingGrid(items: [
                    .init(label: "到期日", value: expiry.value, unit: expiry.unit),
                    .init(label: "剩余", value: remaining.value, unit: remaining.unit, tint: remaining.tint),
                ])
                Divider().overlay(Ink.hairline)
                // 用量与开门数要读 cmd16 日志与锁内计数，本机现在拿不到 —— 如实标出来，不编数字。
                KeysInlineNote(tone: .neutral, text: "用量与近 30 天开门次数要读锁内日志（cmd16），本机还没有这条链路。")
                // 改期写的是本机台账；锁端要重发 0B 才真的改到锁上 —— 这句话放在读数区，不藏在代码里。
                KeysInlineNote(tone: .neutral, text: "改到期日只写本机台账。要让门锁也认新时段，还得重发一次 0B。")
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 真动作

    private func actionsBlock(_ key: KeyItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "能做的事")
                    .padding(.bottom, T.S.s)
                expiryMenu(key)
                KeysDivider()
                KeysActionRow(
                    title: key.disabled ? "恢复使用" : "停用这枚凭证",
                    symbol: key.disabled ? "play.circle" : "pause.circle",
                    tint: key.disabled ? Ink.ink : State.attention
                ) {
                    toggleDisabled(key)
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
        .padding(.horizontal, T.S.gutter)
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
        } label: {
            HStack(spacing: T.S.m) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: T.Icon.m, weight: .regular))
                    .foregroundStyle(Ink.inkSub)
                    .frame(width: T.Icon.xl, alignment: .leading)
                    .accessibilityHidden(true)
                Text("改到期日")
                    .font(T.F.body)
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: T.S.s)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: T.Icon.s, weight: .medium))
                    .foregroundStyle(Ink.inkFaint)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .accessibilityLabel("改到期日")
    }

    // MARK: 危险动作

    private func dangerBlock(_ key: KeyItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.s) {
                SectionLabel(text: "不可逆")
                Text("删除会同时从门锁和本机台账里移除这枚凭证，没有回收站。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                // 危险动作用语义色（State.critical），不用 signal 填充 —— 同屏的 signal 只留给主动作。
                KeysActionRow(title: "彻底删除", symbol: "trash", tint: State.critical) {
                    confirmDelete = true
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 不存在空态（凭证被删/被移走后仍可能有人跳过来）

    private var missingBlock: some View {
        Panel {
            EmptyPanel(
                title: "这枚凭证已经不在了",
                message: "它可能刚被删除或停用。回钥匙列表看看还剩哪些凭证，或再新增一枚。",
                actionTitle: "回钥匙列表",
                systemImage: "key.slash"
            ) {
                router.keysPath = []
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 写台账（值语义：改就是换一条）

    private func setExpiry(_ key: KeyItem, days: Int?) {
        let expiresAt: Int64?
        if let days {
            let cal = TimeFormat.calendar
            let base = cal.startOfDay(for: Date())
            let shifted = cal.date(byAdding: .day, value: days, to: base) ?? base
            // 到期落在当天 23:59，避免「今天到期」在中午就被判过期。
            let end = cal.date(byAdding: .second, value: 86399, to: shifted) ?? shifted
            expiresAt = Int64(end.timeIntervalSince1970 * 1000)
        } else {
            expiresAt = nil
        }
        // TODO(engine): 改期要重发 0B（写新起止时间到锁）。链路未接，这里只改本机台账。
        app.keys = KeysState.replace(KeysState.withExpiry(key, expiresAt), in: app.keys)
        now = KeysState.now()
    }

    private func toggleDisabled(_ key: KeyItem) {
        // TODO(engine): 停用 = 本地移除 + 排锁端删除（cmd 删除凭证）。链路未接，这里只翻本机状态。
        app.keys = KeysState.replace(KeysState.withDisabled(key, !key.disabled), in: app.keys)
    }

    private func deleteKey() {
        guard let key else { return }
        // TODO(engine): 彻底删除要先下发锁端删除命令，成功才摘台账。链路未接，这里只摘本机。
        app.keys.removeAll { $0.id == key.id }
        router.keysPath = []
    }
}