//
//  KeysPage.swift
//  凭证页 · 全新重写 (2026-10-21)
//
//  门里「钥匙」域的落地页。
//
//  ═══════════════════════════════════════════════════════════
//  与旧 CredentialsView (2478 行) 的根本区别
//  ═══════════════════════════════════════════════════════════
//
//  旧版: 4 类凭证 (密码/指纹/临时码/OTP) + 排序 + 筛选 chip +
//        智能列表 + 归档区 + 回收站 + 批量操作 + 月历 + 队列…
//        —— 一个"管理器", 打开它要先学会管理。
//
//  新版: 「谁能进」—— 一行一权
//    · 顶部: 生效中的授权 (按到期紧迫度排序)
//    · 中部: 类型分段 (全部/密码/指纹/临时码)
//    · 底部: 待处理 (到期预警/待下发)
//    · 搜索与批量收进 toolbar, 不占主版面
//
//  设计原则:
//    · 一行表达一件事: 谁 / 什么 / 何时到期
//    · 紧急的在前, 用色不用图标堆叠
//    · 危险操作 (删除/停用) 收进滑动菜单
//    · 不用 2×2 网格 (AX 5 倍字体)
//

import SwiftUI

/// 凭证页 —— 门里「钥匙」
struct KeysPage: View {
    @EnvironmentObject private var app: AppState

    @State private var seg: Int = 0          // 0 全部 / 1 密码 / 2 指纹 / 3 临时码
    @State private var search = ""
    @State private var searchActive = false
    @State private var showAdd = false

    private var mac: String { app.currentMac }

    @State private var confirmDelete: KeyRow?
    /// 写入侧改完后的重算开关。
    ///
    /// ⚠ 这个名字换掉了原来的 refreshTick —— 那个变量声明了、挂了 .id()，
    /// 但全仓没有一处给它 +1，于是"刷新"从不发生（已在本会话中清除）。
    /// 这里每一次写入都必须真的递增，否则就是同一个坑再来一次。
    @State private var refreshToken = 0

    var body: some View {
        // M5 重做: List → 卡片流 + 液态玻璃分段
        //
        // 原来用 List(.insetGrouped) + Section —— 那是系统默认长相，
        // 与 B 域"液态玻璃分组"的语言不搭。现在改成:
        //   · 顶部浮动液态玻璃分段（复用 axGlassCapsule）
        //   · 每组一张 XPanel，组内行用 XRow
        //   · 到期预警单独一张卡，放最上面
        //
        // 数据逻辑一行没动 —— 只换呈现。
        // 2026-10-23：改用 XScreen。
        //
        // 改前这段手写骨架 + 三行注释解释「为什么 14 / 28 / 8 各不相同」——
        // 那个解释是对的，但它本该写在**组件里一次**，而不是在每个页面重讲一遍。
        // 现在 XScreen 给骨架，本页只声明「有哪几块」。
        XScreen("钥匙管理") {
            if !expiringItems.isEmpty { expiringCard }
            VStack(spacing: XSpace.section) {
                // 六图改造 (2026-10-23): 加图 5 的 MetricCard 主角卡。
                // 图 5 的第一张卡永远是「44px 大数字 + 一枚环 + 彩点行」。
                // 钥匙页原来从「到期预警」直接跳到分段 + 列表，缺了「一共多少、都是哪几类」
                // 这一层 —— 用户进页面第一眼看不出总量与构成，只能一行行数。
                overviewCard
                segmentBar
                VStack(spacing: XSpace.rowGap) {
                    credentialCard
                    if rows.isEmpty { emptyCard }
                }
            }
        }
        .searchable(text: $search, isPresented: $searchActive, prompt: "搜索名称 / 备注 / 归属")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { MembersPage().environmentObject(app) } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("成员")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    XHaptics.tick.impactOccurred()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加钥匙")
            }
        }
        .confirmationDialog(
            "删除这项钥匙？",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmDelete
        ) { row in
            Button("删除", role: .destructive) { performDelete(row) }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: { row in
            // 三件事必须在按下"删除"之前说清：
            //   ① 本机会删；② 锁端也会撤销（且断网不丢）；③ **可以找回**。
            // 第三条原来漏了 —— 用户在最有顾虑的那一刻，不知道自己还有退路。
            // 第 ④ 件事: **在哪恢复**。前三件说清了"会不会丢"，但不说在哪找回，
            // 用户删完就只能自己找 —— 而回收站在「安全 → 销毁数据」里面，
            // 那不是任何人会先去看的地方。承诺可恢复就必须把路指全。
            Text("「\(row.title)」会从本机台账移除，并从门锁上撤销对应的密码/指纹。\n"
                 + "撤销命令会排队等待门锁连接，断网也不会丢。\n"
                 + "本机这条会留在回收站 \(CredentialOrg.reclaimDays()) 天，期间可以恢复"
                 + "（管理 → 安全 → 销毁数据 → 回收站）。")
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddKeyPage()
                    .environmentObject(app)
            }
        }
    }

    // ── 到期预警卡 ──
    private var expiringCard: some View {
        XPanel(tone: .warn) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                HStack(spacing: XSpace.xs) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.warn)
                    Text("\(expiringItems.count) 份即将到期")
                        .xFont(.footnote, weight: .semibold)
                        .foregroundStyle(XPalette.warn)
                    Spacer(minLength: 0)
                }
                ForEach(expiringItems.prefix(3), id: \.alias) { p in
                    HStack(spacing: XSpace.s) {
                        Text(p.note.isEmpty ? "密码 #\(p.alias)" : p.note)
                            .xFont(.subheadline)
                            .foregroundStyle(XPalette.text)
                            .lineLimit(1)
                        Spacer(minLength: XSpace.s)
                        Text(CredentialOrg.expiryLabel(p.to))
                            .xFont(.caption2)
                            .foregroundStyle(XPalette.warn)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(p.note) 即将到期, \(CredentialOrg.expiryLabel(p.to))")
                }
            }
        }
    }

    // ── 分段（规范 §7.3 形态 B，全仓唯一实现）──
    //
    // 原来是手搓的 axGlassCapsule + 选中项 accent 洗底 —— 而 §7.3/§7.10 都点名：
    // 选中块应当是 rgba(255,255,255,0.18) 的**白色**块，不是语义色洗底。
    // 语义色留给「当前状态」，不留给「你选了什么」。
    /// 图 5 MetricCard 主角卡 —— 44px 总量 + 图 2 细三环 + 彩点行。
    ///
    /// 图 5 的结构：卡头 → 44px 大数字 + 单位 → 右侧环 → sep → 彩点行 → footer 整句。
    /// 这里环用细三环（图 2）而不是单环，因为它要同时表达三类凭证的比例。
    private var overviewCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("全部凭证")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(XPalette.textTertiary.opacity(0.6))
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 10) {
                        XHeroNumber(text: String(fpCount + pwCount + tempCount), unit: "份")
                        XDataRow(label: "指纹", value: String(fpCount), unit: "枚",
                                 color: XPalette.kindFp)
                        XDataRow(label: "密码", value: String(pwCount), unit: "项",
                                 color: XPalette.kindTemp)
                        XDataRow(label: "临时码", value: String(tempCount), unit: "个",
                                 color: XPalette.kindOtp)
                    }
                    Spacer(minLength: 4)
                    XTripleThinRing(
                        size: 92,
                        values: (fpRatio, pwRatio, tempRatio),
                        colors: (XPalette.kindFp, XPalette.kindTemp, XPalette.kindOtp),
                        centerText: String(fpCount + pwCount + tempCount))
                        .accessibilityHidden(true)
                }
                .padding(.top, 8)
                XHairline().padding(.vertical, 12)
                Text("三类凭证按数量占比画成三环 —— 一眼看出这把锁主要靠哪种方式进人。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 三类凭证的数量与占比（细三环的数据源）
    private var fpCount: Int { fps.count }
    private var pwCount: Int { pwds.filter { !$0.temp }.count }
    private var allTotal: Int { max(1, fpCount + pwCount + tempCount) }
    private var fpRatio: Double { Double(fpCount) / Double(allTotal) }
    private var pwRatio: Double { Double(pwCount) / Double(allTotal) }
    private var tempRatio: Double { Double(tempCount) / Double(allTotal) }

    private var segmentBar: some View {
        XSegmented(items: Seg.allCases, title: { $0.title }, selection: Binding(
            get: { Seg(rawValue: seg) ?? .all },
            set: { seg = $0.rawValue }
        ))
    }


    private enum Seg: Int, CaseIterable {
        case all = 0, pwd = 1, fp = 2, temp = 3
        var title: String {
            switch self {
            case .all: return "全部"
            case .pwd: return "密码"
            case .fp: return "指纹"
            case .temp: return "临时码"
            }
        }
    }

    private func countFor(_ s: Seg) -> Int {
        switch s {
        case .all: return rows.count
        case .pwd: return pwdCount
        case .fp: return fps.count
        case .temp: return tempCount
        }
    }

    // ── 凭证卡 ──
    @ViewBuilder
    private var credentialCard: some View {
        if !rows.isEmpty {
            XPanel(kind: .group, padding: 0) {
                VStack(spacing: 0) {
                    // 六图改造 (2026-10-23): 「N 份生效」从 12pt 灰字 → **图 5 的 44px 读数**。
                    // 这是列表卡的标题位，但它是本页第二个重要的量（当前分段里有多少生效），
                    // 12pt 让它读起来像表格注脚。
                    HStack(alignment: .firstTextBaseline) {
                        XHeroNumber(text: String(rows.count), unit: "份生效")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, XSpace.card)
                    .padding(.top, XSpace.m)
                    .padding(.bottom, XSpace.s)

                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        keyRow(row)
                        if idx < rows.count - 1 {
                            XHairline()
                                .padding(.leading, XSpace.card + 28 + XSpace.m)
                        }
                    }
                }
            }
        }
    }

    /// 删除一份凭证 —— **本机台账与门锁两端一起撤**。
    ///
    /// ⚠ 这里原来调的是 DB.delPwd / DB.delFp，那**只删本机台账**，
    /// 锁上那条密码/指纹仍然有效。对门锁来说这是最危险的假安全感：
    /// 用户以为权限收回了，实际上拿着那张卡依然能开门。
    ///
    /// 正确路径是 CredentialOrg.batchDisable：它先删本机台账，
    /// 再把 del_pwd / del_fp 入队，等连上锁时由 LinkSenseKit 下发。
    /// 断网也不会丢 —— 队列会等下一次连接。
    /// 给指纹改名。锁端无名称字段，这个名字只存在本机台账。
    private func renameFingerprint(_ row: KeyRow) {
        let current = DB.ledger(mac).fps.first { $0.batch == row.key }?.name ?? ""
        promptText("改个名字", "只存本机 —— 门锁里没有名称字段，你在这里写的名字不会传给任何设备。",
                   placeholder: "例如：爸爸的右手食指", initial: current) { text in
            DB.renameFp(mac, row.key, text)
            XHaptics.success()
            app.showToast(text.isEmpty ? "名字已清空" : "已改名为「\(text)」")
            refresh()
        }
    }

    /// 改一条凭证的备注。密码按 alias 定位、指纹按 batch 定位。
    private func editNote(_ row: KeyRow) {
        let current: String
        if row.kindTag == "fp" {
            current = DB.ledger(mac).fps.first { $0.batch == row.key }?.note ?? ""
        } else {
            current = DB.ledger(mac).pwds.first { $0.alias == row.key }?.note ?? ""
        }
        promptText("编辑备注", "「\(row.title)」——只存本机，不上传。",
                   placeholder: "例如：给谁、什么时候用", initial: current) { text in
            if row.kindTag == "fp" {
                DB.setFpNote(mac, row.key, text)
            } else {
                DB.setPwdNote(mac, row.key, text)
            }
            XHaptics.success()
            app.showToast(text.isEmpty ? "备注已清空" : "备注已保存")
            refresh()
        }
    }

    private func performDelete(_ row: KeyRow) {
        let n: Int
        if row.kindTag == "fp" {
            n = CredentialOrg.batchDisable(mac, pwdAliases: [], fpBatches: [row.key])
        } else {
            n = CredentialOrg.batchDisable(mac, pwdAliases: [row.key], fpBatches: [])
        }
        confirmDelete = nil
        XHaptics.trigger.impactOccurred()
        // 提示必须**指向核对的地方** —— 否则"已排队"这三个字对用户是没有着落的：
        // 他不知道发出去没有、失败了没有、要去哪里看。回收站页现在有队列卡。
        //
        // ⚠ 文案必须与**真实路径**一致。回收站唯一的入口是：
        //   管理面板 → 安全 → 销毁数据 → 回收站（SecurityCenterView 的 CredentialBinView）
        // 也就是说它要经过「销毁数据」那一页 —— 原来这里只写「安全 → 回收站」，
        // 少掉中间那一跳，用户按这句话找会停在"安全"组里翻不到回收站。
        // 而这句话出现在**刚删完东西、最想找回**的那一刻，指错路的代价最高。
        app.showToast(n > 0
            ? "已删除「\(row.title)」—— 锁端撤销已排队；可在「安全 → 销毁数据 → 回收站」核对"
            : "「\(row.title)」未找到或已删除")
        refresh()
    }

    /// 写入侧改完必须让本页重算 —— rows 是计算属性，
    /// 但 View 需要一次状态变化才会重新求值。
    private func refresh() { refreshToken &+= 1 }

    // ── 空态卡 ──
    private var emptyCard: some View {
        XPanel(kind: .group, padding: 0) {
            XEmptyState(systemImage: "key.slash",
                        title: search.isEmpty ? "还没有钥匙" : "没有匹配的钥匙",
                        message: search.isEmpty ? "添加第一份授权, 之后会按类型分组显示。" : "换个关键词试试。",
                        actionTitle: search.isEmpty ? "添加钥匙" : nil,
                        action: search.isEmpty ? { showAdd = true } : nil)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 数据
    // ═══════════════════════════════════════════════════════

    private var pwds: [LedgerPwd] {
        let all = DB.listPwds(mac)
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { p in
            p.note.localizedCaseInsensitiveContains(q)
                || CredentialOrg.displayPwd(p).localizedCaseInsensitiveContains(q)
                || CredentialOrg.ownerName(p.owner).localizedCaseInsensitiveContains(q)
        }
    }

    private var fps: [LedgerFp] {
        let all = DB.listFps(mac)
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { f in
            f.name.localizedCaseInsensitiveContains(q)
                || f.note.localizedCaseInsensitiveContains(q)
                || CredentialOrg.ownerName(f.owner).localizedCaseInsensitiveContains(q)
        }
    }

    /// 即将到期 (7 天内) —— 与 Tab 角标同源
    private var expiringItems: [LedgerPwd] {
        CredentialOrg.dueSoonPwds(mac)
    }

    private struct KeyRow: Identifiable {
        let id: String
        /// 底层键：密码/临时码是 alias，指纹是 batch
        let key: Int
        /// CredentialOrg 的写入侧口径："pwd" / "fp"
        let kindTag: String
        let title: String
        let subtitle: String?
        let stateLabel: String
        let stateTone: XToneColor
        let kind: Int      // 0 pwd / 1 fp / 2 temp
        let owner: String?
    }

    private var rows: [KeyRow] {
        var out: [KeyRow] = []
        if seg == 0 || seg == 1 {
            out += pwds.filter { !$0.temp }.map { p in
                let state = CredentialOrg.pwdState(p)
                return KeyRow(
                    id: "p\(p.alias)",
                    key: p.alias,
                    kindTag: "pwd",
                    title: p.note.isEmpty ? "密码 #\(p.alias)" : p.note,
                    subtitle: subtitleFor(p),
                    stateLabel: CredentialOrg.stateLabel(state),
                    stateTone: toneFor(state),
                    kind: 0,
                    owner: p.owner)
            }
        }
        if seg == 0 || seg == 3 {
            out += pwds.filter { $0.temp }.map { p in
                let state = CredentialOrg.pwdState(p)
                return KeyRow(
                    id: "t\(p.alias)",
                    key: p.alias,
                    kindTag: "pwd",
                    title: p.note.isEmpty ? "临时码 #\(p.alias)" : p.note,
                    subtitle: subtitleFor(p),
                    stateLabel: CredentialOrg.stateLabel(state),
                    stateTone: toneFor(state),
                    kind: 2,
                    owner: p.owner)
            }
        }
        if seg == 0 || seg == 2 {
            out += fps.map { f in
                KeyRow(
                    id: "f\(f.batch)",
                    key: f.batch,
                    kindTag: "fp",
                    title: f.name.isEmpty ? "指纹 #\(f.batch)" : f.name,
                    subtitle: f.note.isEmpty ? nil : f.note,
                    stateLabel: "有效",
                    stateTone: .ok,
                    kind: 1,
                    owner: f.owner)
            }
        }
        return out
    }

    private func subtitleFor(_ p: LedgerPwd) -> String? {
        var parts: [String] = []
        if let o = p.owner, !o.isEmpty {
            let n = CredentialOrg.ownerName(o)
            if !n.isEmpty { parts.append(n) }
        }
        let exp = CredentialOrg.expiryLabel(p.to)
        if !exp.isEmpty { parts.append(exp) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// pwdState 返回 Int —— 0 进行中 / 1 已排期 / 2 已过期
    /// (见 CredentialOrg.pwdState 注释: 按时间窗推断)
    private func toneFor(_ state: Int) -> XToneColor {
        switch state {
        case 0: return .ok
        case 1: return .neutral
        case 2: return .danger
        default: return .neutral
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 视图
    // ═══════════════════════════════════════════════════════



    private var pwdCount: Int { pwds.filter { !$0.temp }.count }
    private var tempCount: Int { pwds.filter { $0.temp }.count }

    /// 副标题 + 归属合成一行
    ///
    /// 顺序: 归属在前（"妈妈 · 常驻 · 我的 iPhone"）——
    /// 扫读时先认人，再看属性。
    /// 无障碍标签：类型 + 标题 + 归属 + 状态
    private func accessibilityLine(_ row: KeyRow) -> String {
        var parts = [kindWord(row.kind), row.title]
        if let o = row.owner, !o.isEmpty, let m = DB.member(o) { parts.append("归属 " + m.name) }
        parts.append(row.stateLabel)
        return parts.joined(separator: "，")
    }

    private func detailLine(_ row: KeyRow) -> String? {
        var parts: [String] = []
        if let o = row.owner, !o.isEmpty, let m = DB.member(o) {
            parts.append(m.name)
        }
        if let sub = row.subtitle, !sub.isEmpty {
            parts.append(sub)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func keyRow(_ row: KeyRow) -> some View {
        HStack(spacing: XSpace.m) {
            // 类型徽章: 底色 + 图标随类型变色。
            // 原来三种凭证共用同一个铜色图标, 扫一眼分不出是密码还是指纹;
            // 有底色之后, 一列里按颜色就能分组读。
            ZStack {
                RoundedRectangle(cornerRadius: XRadius.min, style: .continuous)
                    .fill(kindTint(row.kind).opacity(XOpacity.badge))
                Image(systemName: iconFor(row.kind))
                    .font(.system(size: XIcon.sm, weight: .semibold))
                    .foregroundStyle(kindTint(row.kind))
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .xFont(.body)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                // 归属 + 副标题合一行 —— owner 字段一直有，但 keyRow 从没用过。
                // 凭证页最该知道"这把钥匙给了谁"，原来只能点进去看。
                if let line = detailLine(row) {
                    Text(line)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: XSpace.s)

            XStatusPill(text: row.stateLabel, tone: row.stateTone)
        }
        .padding(.vertical, XSpace.xxs)
        .contentShape(Rectangle())
        // ═══ 行级动作 ═══
        //
        // 这一页原来**完全没有行交互** —— 没有详情页、没有点击、没有滑动。
        // 凭证列表是纯只读展示，于是 CredentialOrg 里那一整套写入 API
        //（星标 / 归档 / 停用便签 / 批量）全都没有入口，42 个函数零调用。
        //
        // 在补出完整详情页之前，先用长按菜单把这些**已经实现好**的能力接上：
        // 不需要新造界面，也不假装有详情页。
        .contextMenu {
            Button {
                CredentialOrg.toggleStar(mac, row.kindTag, row.key)
                XHaptics.tick.impactOccurred()
                refresh()
            } label: {
                Label(CredentialOrg.isStarred(mac, row.kindTag, row.key) ? "取消置顶" : "置顶",
                      systemImage: CredentialOrg.isStarred(mac, row.kindTag, row.key) ? "star.slash" : "star")
            }

            Button {
                let on = !CredentialOrg.isArchived(mac, row.kindTag, row.key)
                CredentialOrg.setArchived(mac, row.kindTag, row.key, on)
                XHaptics.tick.impactOccurred()
                refresh()
            } label: {
                Label(CredentialOrg.isArchived(mac, row.kindTag, row.key) ? "取消归档" : "归档",
                      systemImage: "archivebox")
            }

            // ═══ 改名字（只对指纹） ═══
            //
            // 指纹在锁端**没有名称字段**，名字是本机台账的展示字段 ——
            // 所以改它不需要任何锁端动作，是纯本机编辑，安全。
            // （对照：改密码内容 rePwd 就**不能**这么接 —— 本地一改，
            //   记录显示新密码、锁里还是旧的，等于造一条骗人的记录。）
            if row.kindTag == "fp" {
                Button {
                    renameFingerprint(row)
                } label: {
                    Label("改个名字", systemImage: "textformat")
                }
            }

            // ═══ 编辑备注 ═══
            //
            // 创建时能写备注（AddKeyPage 与工坊都有备注框），但**创建之后改不了** ——
            // DB.setPwdNote / DB.setFpNote 写好了却零调用。打错一个字只能删了重建。
            Button {
                editNote(row)
            } label: {
                Label("编辑备注", systemImage: "text.bubble")
            }

            Button(role: .destructive) {
                confirmDelete = row
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        // ═══ 可发现性 ═══
        //
        // 这一行的六个动作全藏在长按菜单里 —— 视觉上它和一行只读文字没有区别。
        // 规范（§7.15 的选型规则 / Anti-slop 那套可发现性口径）要求：
        // **「看着就想点」的东西必须真的能点，而且要看得出能点。**
        //
        // 修法两条，都很便宜:
        //   ① 行尾给一枚极淡的 "ellipsis" —— 它是 iOS 上"这里还有更多"的既定语汇,
        //      而且不抢 XStatusPill 的位置（放在它右边 4pt）。
        //   ② VoiceOver 把这六个动作**全部**挂上。之前只挂了一个"置顶"，
        //      读屏用户根本不知道还能归档/改名/改备注。
        .overlay(alignment: .trailing) {
            Image(systemName: "ellipsis")
                .font(.system(size: XIcon.xs, weight: .semibold))
                .foregroundStyle(XPalette.textTertiary)
                .padding(.trailing, -XSpace.s)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLine(row))
        .accessibilityHint("长按可置顶、归档、改备注或删除")
        .accessibilityAction(named: "置顶或取消置顶") {
            CredentialOrg.toggleStar(mac, row.kindTag, row.key)
        }
        .accessibilityAction(named: "归档或取消归档") {
            CredentialOrg.setArchived(mac, row.kindTag, row.key,
                                      !CredentialOrg.isArchived(mac, row.kindTag, row.key))
            refresh()
        }
        .accessibilityAction(named: "编辑备注") {
            editNote(row)
        }
        .accessibilityAction(named: "删除") {
            confirmDelete = row
        }
    }

    /// 类型配色: 密码铜 / 指纹绿 / 临时码橙 —— 与 StatsKit 的 kindColor 同一套语义
    private func kindTint(_ kind: Int) -> Color {
        switch kind {
        case 0: return XPalette.accent
        case 1: return XPalette.ok
        default: return XPalette.warn
        }
    }

    private func kindWord(_ kind: Int) -> String {
        switch kind {
        case 0: return "密码"
        case 1: return "指纹"
        default: return "临时码"
        }
    }

    private func iconFor(_ kind: Int) -> String {
        switch kind {
        case 1: return "hand.raised.fill"
        case 2: return "clock.fill"
        default: return "key.fill"
        }
    }

}
