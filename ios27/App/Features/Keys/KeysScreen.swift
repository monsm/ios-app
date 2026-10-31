// KeysScreen.swift —— 钥匙（Tab 2 根）。
//
// 这一屏干什么：把这把锁的全部凭证摊成一本台账（状态点 + 名称 + 归属 + 剩余天数），
// 并按类型分段；页面底部是唯一主动作「新增凭证」与三条次级入口（月历 / 手机钥匙 / 分享给安卓）。
// 数据从哪来：AppModel.keys（[KeyItem]）。真实台账由 Engine/Store 提供，这里只读。
// 主动作：新增凭证 → .dest(.keyCreate)（工坊里分四步下发，本页不直接改锁）。
import SwiftUI

struct KeysScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) internal var router
    @State private var filter: KeysFilter = .all
    @State internal var now: Int64 = KeysState.now()

    private var filtered: [KeyItem] {
        app.keys.filter { filter.matches($0) }
    }

    private var validCount: Int {
        app.keys.filter { !$0.disabled && !KeysState.expired($0, now: now) }.count
    }

    /// 最近一条要到期（不含已过期/已停用）的天数，用于页头那一行状态。
    private var nearestDays: Int? {
        app.keys
            .filter { !$0.disabled && !KeysState.expired($0, now: now) }
            .compactMap { KeysState.daysLeft($0, now: now) }
            .min()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if app.lock == nil {
                    noLockBlock
                } else if app.keys.isEmpty {
                    emptyBlock
                } else {
                    ChipRow(items: KeysFilter.allCases, title: { chipTitle($0) }, selection: $filter)
                    ledgerBlock
                }
                shortcutsBlock
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("钥匙")
        .task { await app.reload(refreshStatus: false) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.keyCreate))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增凭证")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.request(.dest(.keyCalendar))
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("到期月历")
            }
        }
        .onAppear {
            now = KeysState.now()
            routeFromContext()
        }
    }

    /// 别的 Tab 用 .key(id:) 跳过来时，Router 只切 Tab 不 push —— 这里接住，推进详情。
    private func routeFromContext() {
        guard case .key(let id) = router.pending else { return }
        KeysRoute.openDetail(id, router: router)
    }

    // MARK: 页头：大标题 + 一行状态（形状 + 颜色 + 文字三通道）

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("钥匙")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: T.S.s) {
                StateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerTone: Tone {
        if app.lock == nil { return .neutral }
        if app.keys.isEmpty { return .neutral }
        if let days = nearestDays, days <= 3 { return .attention }
        return .ok
    }

    private var headerWord: String {
        switch headerTone {
        case .attention: return "有凭证即将到期"
        case .ok: return "凭证可用"
        default: return app.keys.isEmpty ? "还没有凭证" : "未添加门锁"
        }
    }

    private var headerText: String {
        guard app.lock != nil else { return "先添加门锁，凭证要挂在一把具体的锁上" }
        guard !app.keys.isEmpty else { return "这把锁还没有任何凭证" }
        var line = "\(validCount) 枚有效 · 共 \(app.keys.count) 枚"
        if let days = nearestDays {
            line += days == 0 ? " · 今天有到期" : " · \(days) 天后到期"
        }
        return line
    }

    private func chipTitle(_ item: KeysFilter) -> String {
        let count = app.keys.filter { item.matches($0) }.count
        return "\(item.title) \(count)"
    }

    // MARK: 主角：凭证台账（一屏只有一个 Panel 列表）

    private var ledgerBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.s) {
                SectionLabel(text: filter == .all ? "全部凭证" : filter.title, trailing: "\(filtered.count) 枚")
                if filtered.isEmpty {
                    KeysInlineNote(tone: .neutral, text: emptyFilterText)
                        .frame(minHeight: T.Hit.min)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { pair in
                            if pair.offset > 0 {
                                KeysDivider()
                            }
                            rowButton(pair.element)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var emptyFilterText: String {
        switch filter {
        case .all: return "还没有凭证。用下面的「新增凭证」加一枚密码，家人就能用密码开门了。"
        case .password: return "还没有密码。新增凭证里第一步选「密码」就能加一枚 6~8 位数字。"
        case .fingerprint: return "还没有指纹。指纹要在门锁上按 8 次录入，进「新增凭证」选「指纹」。"
        case .temp: return "还没有临时码。给保洁、装修工发一张限期码，到期自动失效。"
        case .mobile: return "还没有手机钥匙。用手机开门要先签一把钥匙，进「手机钥匙」页。"
        }
    }

    private func rowButton(_ key: KeyItem) -> some View {
        Button {
            KeysRoute.openDetail(key.id, router: router)
        } label: {
            KeysRow(key: key, now: now)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开凭证详情")
    }

    // MARK: 唯一主动作

    // 主动作放在导航栏，不放在列表中间 —— 这是 iOS 的做法：
    // 整条填充色的按钮夹在两块面板之间是 Web 的形态，iOS 里主动作属于工具栏，
    // 或者最多在滚动到列表末尾时出现一次。列表本身保持连续可扫读。
    private var primaryBlock: some View {
        EmptyView()
    }

    // MARK: 空态（必须给出路）

    private var noLockBlock: some View {
        Panel {
            EmptyPanel(
                title: "还没有添加门锁",
                message: "凭证是挂在某一把具体的锁上的。先把锁恢复出厂（长按 RESET 到三声嘀），再回来添加。",
                actionTitle: "添加门锁",
                systemImage: "door.left.hand.closed"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var emptyBlock: some View {
        Panel {
            EmptyPanel(
                title: "这把锁还没有凭证",
                message: "先加一枚密码 —— 家人不用带钥匙，报一串数字就能开门。之后可以再录指纹、发临时码。",
                actionTitle: "新增凭证",
                systemImage: "key.horizontal"
            ) {
                router.request(.dest(.keyCreate))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 次级入口（三条，各自说清去处）

    private var shortcutsBlock: some View {
        Panel {
            VStack(spacing: 0) {
                KeysShortcutRow(title: "到期月历", detail: "看这个月哪天有凭证到期", symbol: "calendar") {
                    router.request(.dest(.keyCalendar))
                }
                KeysDivider()
                KeysShortcutRow(title: "手机钥匙", detail: "给家人的手机签一把钥匙", symbol: "iphone.gen3") {
                    router.request(.dest(.mobileKey))
                }
                KeysDivider()
                KeysShortcutRow(title: "分享给安卓", detail: "扫码把开锁凭证导到安卓手机", symbol: "qrcode") {
                    router.request(.dest(.shareToAndroid))
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }
}