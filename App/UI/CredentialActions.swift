// 凭证页 · 筛选 / 搜索 / 批量操作 / OTP 块
// 2026-10-29 从 CredentialsView.swift（1557 行）拆出。
// 是 CredentialsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension CredentialsView {
    func segChip(_ i: Int) -> some View {
        // 479 长辈模式: 只留 全部/密码/指纹 三组, 隐藏临时码组与批量/导出入口; 字号同步行本体那一档 (大字)
        let labels = MemberHub.elderMode ? ["全部", "密码", "指纹", ""] : ["全部", "密码", "指纹", "临时码"]
        let c = countForSeg(i)
        let on = seg == i
        return Button {
            seg = i
            DS.Haptics.tick.impactOccurred()
        } label: {
            HStack(spacing: DS.Space.xxs) {
                Text(labels[i]).vkFont(elderOn ? .body.weight(.medium) : .caption.weight(.medium))
                if c > 0 {
                    Text("\(c)")
                        .vkFont(elderOn ? .body.weight(.semibold) : .caption2.weight(.semibold))
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                        .padding(.horizontal, DS.Space.xs).padding(.vertical, DS.Space.xxs)
                        .background(on ? DS.Palette.onFillWash.opacity(0.24) : DS.Palette.surfaceAlt, in: Capsule())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.s)
            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
            .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.surfaceAlt), in: Capsule())
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(labels[i]) \(c) 条")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
    func countForSeg(_ i: Int) -> Int {
        let t = CredentialOrg.typeCounts(mac)
        switch i {
        case 1: return t.pwd
        case 2: return t.fp
        // 2026-10-27 截图核对修复：原先用 `listPwds.filter { $0.temp }.count` ——
        // 而「临时码」在这个 App 里是 ZOTP（锁端周期码），不是台账里带 temp 标记的密码。
        // 台账里根本没有那种标记 ⇒ 计数恒 0 ⇒ chip 上永远没有数字
        // （截图里「临时码」是唯一没数字的那个）。`typeCounts` 早就带了 otp 字段，直接用它。
        case 3: return t.otp
        default: return t.all
        }
    }

    // ---------- 主列表 ----------
    var mainList: some View {
        List {
            listBody
        }
        .listRowSpacing(DS.Space.xs)   // 批量操作行距保持宽松 (纪律: 批量行距)
    }
    /// 182 排序档的说明行: 只承诺这一档真做得到的事 (段内先后 + 落 kf_cseq_ 跨启动)。

    /// 列表内容抽成 ViewBuilder: 编辑模式与正常模式共用, 避免嵌套两个 List
    @ViewBuilder
    var listBody: some View {
        // 2026-10-28 修复：LockScreen.swift:8 承诺「输胁迫码 → 凭证与记录显示为空」，
        // 但 decoyMode 此前只拦路由与自动开锁，**没有任何视图据它清空数据** ——
        // 被胁迫时真实凭证全部可见，这句承诺是空话（安全承诺级别的假话）。
        if app.decoyMode {
            Section {
                EmptyState(systemImage: "tray",
                           title: "还没有凭证",
                           message: "配好门锁后，在这里添加密码与指纹。")
            }
        } else {
            searchSection
            if memberView {
                memberSections
            } else {
                // 2026-10-28 修复：这里原来是**两个从未被使用的局部量** ——
                // `let pwds = sortedPwds` / `let fps = sortedFps` 声明完就没了，
                // 没有 ForEach。默认 memberView = (groupMode == .owner)，而 kf_ccred_prefs 默认 0 = .type，
                // 于是默认走这一支 ⇒ **有凭证时整页空白**（空态提示又被 isEmpty 判据挡住）。
                // 用户会以为数据丢了。现在按 seg 正确分段渲染。
                let pwds = sortedPwds
                let fps = sortedFps
                // 524 类型分段：0 全部 / 1 密码 / 2 指纹 / 3 临时码
                if seg != 2, !pwds.isEmpty {
                    Section(seg == 3 ? "临时码 (\(pwds.count))" : "密码 (\(pwds.count))") {
                        ForEach(pwds) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                            .onMove { src, dst in
                                commitGroupMove(keys: pwdKeys(pwds), slot: "p", src: src, dst: dst)
                            }
                    }
                }
                // 指纹只在「全部」与「指纹」两档出现；临时码档不显示指纹
                if seg != 1, seg != 3, !fps.isEmpty {
                    Section("指纹 (\(fps.count))") {
                        ForEach(fps) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
                            .onMove { src, dst in
                                commitGroupMove(keys: fpKeys(fps), slot: "f", src: src, dst: dst)
                            }
                    }
                }
            }
            if seg == 0 { otpSection }
            // 354: 全归档不算"台账空" — 归档区那张卡就是这批条目的落点, 谎报"还没有台账"会导向重复建码
            // 2026-10-30 修复：原判据是 `memberView || (!memberView && sortedPwds.isEmpty && sortedFps.isEmpty && true)`
            // —— 前半的 `memberView ||` 让「按成员视图」下**无条件**渲染这条空态提示：
            //   有凭证时成员分组列在上面，底下却多出一句"本机还没有凭证台账"，用户会以为数据丢了。
            //   那个 `&& true` 是「归档功能已删」的残留（原意是 !allArchived，删掉后恒真）。
            // 正确判据：看**全量台账**（seqBase 不扣分段、不含归档过滤）—— 空才提示；
            // 全归档时 seqBase 仍非空 ⇒ 不提示，正是 354 的原意。两种视图共用同一条判据。
            if seqBasePwds.isEmpty && seqBaseFps.isEmpty {
                emptyHint
            }
        }
    }

    @ViewBuilder
    var searchSection: some View {
        Section {
            if search.isEmpty {
                let hist = CredentialOrg.searchHistory()
                if !hist.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("最近搜索")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.xs) {
                            ForEach(hist.prefix(5), id: \.self) { w in
                                HStack(spacing: 2) {
                                    Button(w) { search = w }
                                        .vkFont(.caption)
                                        .buttonStyle(.bordered)
                                        .accessibilityLabel("搜索 \(w)")
                                    Button { CredentialOrg.removeSearchHistory(w) } label: {
                                        Image(systemName: "xmark.circle")
                                            .font(.system(size: 12))
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("删除最近搜索 \(w)")
                                    // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                                    // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                                    .frame(minHeight: DS.Hit.min)
                                    .contentShape(Rectangle())
                                }
                            }
                        }
                    }
                }
            } else {
                let hits = filteredResults
                ForEach(hits) { hit in
                    credRow(hit)
                }
                if hits.isEmpty {
                    // 532 搜索兜底动作: 两个入口都要把"当前这次搜索的意图"真递过去, 不能只换个面。
                    // 原先「去回收站搜」只开弹窗不带词 (空搜索框 = 把人丢回原地), 「按成员重搜」只切分组视图
                    // 却弹「已按成员 X 过滤」那句回执 —— 承诺的结果没发生, 属于假回执。
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("没有找到「\(search)」")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        HStack(spacing: DS.Space.s) {
                            Button {
                                let q = search.trimmingCharacters(in: .whitespaces)
                                let m = DB.members().first { $0.name.localizedCaseInsensitiveContains(q) || $0.relation.localizedCaseInsensitiveContains(q) }
                                if let m {
                                    // 真过滤: 把搜索词换成这位成员**在搜索命中范围里出现的那一串**。
                                    // filteredResults 的 hay 里归属字段走 CredentialOrg.ownerName —— 别名显示档 (919) 下
                                    // 那一格是称呼 (relation) 而不是姓名, 所以直接塞姓名会搜不到 TA 名下凭证 (假重搜)。
                                    let term = CredentialOrg.ownerName(m.id)
                                    search = term.isEmpty ? m.name : term
                                    CredentialOrg.pushSearchHistory(search)
                                    app.showToast("已改用「\(search)」重搜, 命中的是名称/备注/别名/归属")   // 532 已改用
                                } else {
                                    app.showToast("没有匹配的成员")
                                }
                            } label: {
                                Label("按成员重搜", systemImage: "person")
                            }
                            .vkFont(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
            TextField("搜索名称 / 备注 / #别名", text: $search)   // 531 搜索名称
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("凭证搜索, 键盘 Cmd/Control+F")
                .autocorrectionDisabled()
                .onSubmit {
                    if !search.isEmpty { CredentialOrg.pushSearchHistory(search) }
                }
                .accessibilityLabel("凭证搜索")
        }
    }

    struct CredHit: Identifiable {
        var id: String
        var pwd: LedgerPwd?
        var fp: LedgerFp?
        var pinned: Bool = false
    }

    var filteredResults: [CredHit] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var hits: [CredHit] = []
        for p in DB.listPwds(mac) {
            let hay = "\(p.alias) \(p.note) \(CredentialOrg.displayPwd(p)) \(CredentialOrg.namingTemplate(p)) \(CredentialOrg.ownerName(p.owner))"
            if hay.localizedCaseInsensitiveContains(q) {
                hits.append(CredHit(id: "p\(p.alias)", pwd: p, pinned: false))
            }
        }
        for f in DB.listFps(mac) {
            let hay = "\(f.name) \(f.note) \(CredentialOrg.ownerName(f.owner))"
            if hay.localizedCaseInsensitiveContains(q) {
                hits.append(CredHit(id: "f\(f.batch)", fp: f, pinned: false))
            }
        }
        return hits.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.id < b.id
        }
    }

    // 2026-10-26 精简：queueSection（下发状态步条）已删（队列功能整套移除）。
    // ---------- 524/526/527/914/182 密码段 (三态分组头 528 + 置顶 + 组尾统计 529) ----------
    var sortedPwds: [LedgerPwd] { orderedPwds(segFilteredPwds()) }
    /// 182 拖动排序的回写基准 = **全量**显示序 (不扣分段、不套智能筛选)。
    /// 拿"屏幕上这一批"回写整表, 没显示的那批会被推到表尾 —— 分段是展示层的事, 顺序是台账层的事。
    var seqBasePwds: [LedgerPwd] { orderedPwds(DB.listPwds(mac)) }

    func segFilteredPwds() -> [LedgerPwd] {
        var pwds = DB.listPwds(mac)
        if seg == 1 || seg == 3 {
            pwds = pwds.filter { seg == 3 ? $0.temp : !$0.temp }
        }
        // 460 归档成员不参与当前显示 (与成员名册/记录过滤口径一致); 只作用展示层,
        // seqBasePwds 仍是全量 — 归档者留下的手排序不能被展示过滤改写。
        // 2026-10-15 走查 (性能): 原写法在 filter 闭包里逐条 MemberHub.ext/isArchived (每条一次全量解码);
        // 集合一次取, 闭包内 Set 查, 行为不变。
        let memberArchived = MemberHub.archivedIDs()
        let credArchived: Set<Int> = []   // 2026-10-26: 归档已删
        pwds = pwds.filter { !memberArchived.contains($0.owner ?? "") }
        // 354 已归档只从正常显示里收起; 搜索路径 (filteredResults) 特意不过滤 — 收起不是失效, 搜得到才收得回
        pwds = pwds.filter { !credArchived.contains($0.alias) }
        return pwds
    }
    /// 置顶段在前, 其余按 182 手动序 (kf_cseq_), 没有手动序才按 914 的排序维度
    /// 2026-10-30 性能：`CredentialOrg.seq(mac)` 是**一次 DB.get 解码**，原来本函数每次都调 ——
    /// 而 memberSections 对每个成员都调一次 orderedPwds/orderedFps ⇒ O(成员) 次整表解码。
    /// 现在接受可选的 order 参数，调用方一次取、多处传。
    func orderedPwds(_ pwds: [LedgerPwd], order preOrder: [Int]? = nil) -> [LedgerPwd] {
        // 526 置顶行固定顶部
        let pinned: [LedgerPwd] = []   // 2026-10-26: 星标已删，无置顶
        let rest = pwds
        var ordered = rest
        // 182/352 拖拽排序: 用户手动序优先 (seq 存的 index 数组)
        let order = preOrder ?? (CredentialOrg.seq(mac)["p"] ?? [])
        let byIdx = manualIndex(order)
        if !order.isEmpty {
            ordered = ordered.sorted { a, b in
                let ia = byIdx[a.alias, default: 9999]
                let ib = byIdx[b.alias, default: 9999]
                return ia < ib
            }
        }
        return pinned + ordered
    }
    /// 手动序数组 → "元素 → 位次" 查表。
    /// 这里刻意用 uniquingKeysWith 而不是 uniqueKeysWithValues: kf_cseq_ 是持久化数据,
    /// 旧包/半写坏的表里出现重复 alias 时, 后者会当场 trap (整个凭证页变崩溃), 前者只是取第一个位次。
    func manualIndex(_ order: [Int]) -> [Int: Int] {
        Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }


    /// 行内小提示行 (装饰, 不参与 VoiceOver 合并)
    struct HintRow: View {
        let text: String
        var body: some View {
            Text(text)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 指纹段 ----------
    var sortedFps: [LedgerFp] { orderedFps(segFilteredFps()) }
    /// 182 拖动排序的回写基准 (同密码段那一支: 全量, 不套智能筛选)
    var seqBaseFps: [LedgerFp] { orderedFps(DB.listFps(mac)) }

    func segFilteredFps() -> [LedgerFp] {
        var fps = DB.listFps(mac)
        // 460 归档成员的口令/指纹不进当前显示; seqBaseFps 保持全量 (同上)
        // 2026-10-15 走查 (性能): 同 segFilteredPwds — 集合一次取, 闭包内 Set 查。
        let memberArchived = MemberHub.archivedIDs()
        let credArchived: Set<Int> = []   // 2026-10-26: 归档已删
        fps = fps.filter { !memberArchived.contains($0.owner ?? "") }
        // 354 已归档的指纹同理 (搜索不过滤)
        fps = fps.filter { !credArchived.contains(100000 + $0.batch) }
        return fps
    }
    func orderedFps(_ fps: [LedgerFp], order preOrder: [Int]? = nil) -> [LedgerFp] {
        let pinned: [LedgerFp] = []
        let rest = fps
        // 2026-10-27 三轮：排序四档已删，恒按时间倒序（原 default 分支）
        var ordered: [LedgerFp] = rest.sorted { ($0.at) > ($1.at) }
        let order = preOrder ?? (CredentialOrg.seq(mac)["f"] ?? [])
        if !order.isEmpty {
            let byIdx = manualIndex(order)
            ordered = ordered.sorted { a, b in
                let ia = byIdx[a.batch, default: 9999]
                let ib = byIdx[b.batch, default: 9999]
                return ia < ib
            }
        }
        return pinned + ordered
    }

    // ---------- 182 组内拖动排序 ----------
    /// onMove 收到的 IndexSet / 目的下标都是**本段内**的下标,
    /// 所以先在本段里搬, 再把搬完的这一串依次回写到"整表里属于本段的那些位置"上 ——
    /// 别段的位次一格不动, 段内先后就落进了 kf_cseq_。
    /// 下标先过一道范围筛: 数组搬动用越界 IndexSet 是当场 trap, 而这一句的索引来自系统回调。
    func commitGroupMove(keys: [Int], slot: String, src: IndexSet, dst: Int) {
        let within = IndexSet(src.filter { $0 >= 0 && $0 < keys.count })
        guard !within.isEmpty else { return }
        var moved = keys
        moved.move(fromOffsets: within, toOffset: min(max(dst, 0), keys.count))
        let mine = Set(keys)
        var base = slot == "f" ? seqBaseFps.map { $0.batch } : seqBasePwds.map { $0.alias }
        var q = moved
        for i in base.indices {
            if q.isEmpty { break }
            if mine.contains(base[i]) { base[i] = q.removeFirst() }
        }
        var seq = CredentialOrg.seq(mac)
        seq[slot] = base
        CredentialOrg.setSeq(mac, seq)
        reload()
        app.showToast("组内先后已记住, 跨启动保持")   // 182 组内先后已记住
    }
    /// 两个段的取键函数 (密码取 alias, 指纹取 batch)
    func pwdKeys(_ group: [LedgerPwd]) -> [Int] { group.map { $0.alias } }
    func fpKeys(_ group: [LedgerFp]) -> [Int] { group.map { $0.batch } }


    @ViewBuilder
    var memberSections: some View {
        // 2026-10-15 走查 (性能): 原写法在 ForEach(DB.members()) 行内逐成员调 DB.listPwds/listFps
        // (M 成员 = M+1 次全量 JSON 解码) 且每条凭证行各调一次 isArchived (每次都 archived(mac)
        // 全量解码)。提到循环外算一次, 行内只做内存 filter —— 行为不变, 解码次数从 O(M×N) 降为 O(1)。
        let allPwds = DB.listPwds(mac)
        let allFps = DB.listFps(mac)
        // 2026-10-30 性能：排序表一次取 —— 原来每个成员各解一次（O(成员) 次整表解码）。
        let seqAll = CredentialOrg.seq(mac)
        let orderP = seqAll["p"] ?? []
        let orderF = seqAll["f"] ?? []
        let archPwd: Set<Int> = []
        let archFp = archPwd   // isArchived 内部: pwd 存原 alias, fp 存 100000+batch, 同一个 Set
        // 2026-10-30 性能：members() 一次取（虽然第 22 轮已有派生缓存，仍是一次多余数组拷贝）。
        let allMembers = DB.members()
        ForEach(allMembers) { m in
            // 354: 归档条目在本页任何浏览方式里都不出现 (含按成员视图); 归档区卡是唯一落点
            let pwds = orderedPwds(allPwds.filter {
                $0.owner == m.id && !archPwd.contains($0.alias)
            }, order: orderP)
            let fps = orderedFps(allFps.filter {
                $0.owner == m.id && !archFp.contains(100000 + $0.batch)
            }, order: orderF)
            if !pwds.isEmpty || !fps.isEmpty {
                Section("\(CredentialOrg.aliasDisplay && !m.relation.isEmpty ? m.relation + " · " : "")\(m.name) (\(pwds.count + fps.count))") {
                    ForEach(pwds) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                        .onMove { src, dst in
                            commitGroupMove(keys: pwdKeys(pwds), slot: "p", src: src, dst: dst)
                        }
                    ForEach(fps) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
                        .onMove { src, dst in
                            commitGroupMove(keys: fpKeys(fps), slot: "f", src: src, dst: dst)
                        }
                }
            }
        }
        let noPwd = orderedPwds(allPwds.filter { $0.owner == nil && !archPwd.contains($0.alias) }, order: orderP)
        let noFp = orderedFps(allFps.filter { $0.owner == nil && !archFp.contains(100000 + $0.batch) }, order: orderF)
        if !noPwd.isEmpty || !noFp.isEmpty {
            Section("未归属 (\(noPwd.count + noFp.count))") {
                ForEach(noPwd) { p in credRow(CredHit(id: "p\(p.alias)", pwd: p)) }
                    .onMove { src, dst in
                        commitGroupMove(keys: pwdKeys(noPwd), slot: "p", src: src, dst: dst)
                    }
                ForEach(noFp) { f in credRow(CredHit(id: "f\(f.batch)", fp: f)) }
                    .onMove { src, dst in
                        commitGroupMove(keys: fpKeys(noFp), slot: "f", src: src, dst: dst)
                    }
            }
        }
        Section {
            NavigationLink { PwdStudio(embedded: true) } label: { Label("添加密码", systemImage: "plus") }
            NavigationLink { FpStudio(embedded: true) } label: { Label("录入指纹", systemImage: "plus") }
        }
    }

    // ---------- 统一行渲染 (普通/搜索/成员/编辑模式共用; VoiceOver 合并成一条) ----------
    // 479 长辈模式在这一族行上接了**真的大字与高对比**: 字号走语义档升一级 (标题行 subheadline→title3,
    // 副行 caption→body), 对比度走"次文本色升到主文本色"那一档 (两个色都是 DS.Palette 里被 contrast.js 检过的令牌)。
    // 刻意不写 .system(size:): 那一档不参与 Dynamic Type 缩放, 字号闸门 (tools/dynamictype.js 规则 1) 也不放行。
    var elderOn: Bool { MemberHub.elderMode }
    var rowTitleFont: Font { elderOn ? .title3.weight(.semibold) : .subheadline.weight(.semibold) }
    var rowSubFont: Font { elderOn ? .body : .caption }
    var rowSubColor: Color { elderOn ? DS.Palette.text : DS.Palette.textSub }


    // ---------- 347 编辑模式: 选择圈 + 全选循环 (356) + 智能选取 (350) ----------
    var selCount: Int { selPwds.count + selFps.count }

    var editList: some View {
        List {
            Section {
                HStack(spacing: DS.Space.s) {
                    Button {
                        cycleSelect()
                        DS.Haptics.tick.impactOccurred()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cycleLabel)
                                .vkFont(.subheadline, weight: .semibold)
                            Text("下一步: \(cycleNextLabel)")   // 356 下一步
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: DS.Hit.min)
                    Spacer(minLength: 0)
                    Button {
                        // 182/352: 记住当前组内顺序 (置顶段单独记, 避免拖动段误伤置顶)。
                        // 拖动排序 (上方排序档) 与这一枚写的是同一张 kf_cseq_, 不是两套顺序。
                        // 回写取 seqBase* (全量显示序) 而不是 sortedPwds/sortedFps: 后者已经被分段与智能筛选削过,
                        // 拿削过的这一批回写整表, 没显示的那一批 (例如临时码) 的位次就被抹平到表尾。
                        var seq = CredentialOrg.seq(mac)
                        seq["p"] = seqBasePwds.map { $0.alias }
                        seq["f"] = seqBaseFps.map { $0.batch }
                        CredentialOrg.setSeq(mac, seq)
                        app.showToast("已记住当前组内顺序")   // 182/352 已记住当前组内顺序
                    } label: {
                        Label("顺序", systemImage: "arrow.up.arrow.down")
                    }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("把当前先后写成手动序, 与排序档里的拖动共用同一张顺序表")   // 182/352 把当前先后写成手动序
                }
                HStack(spacing: DS.Space.s) {
                    Text("智能选取")   // 350 智能选取
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    ForEach(["已过期", "同成员", "同类型"], id: \.self) { s in
                        Button(s) { applySmart(s) }
                            .vkFont(.caption, weight: .medium)
                            .buttonStyle(.bordered)
                            .frame(minHeight: DS.Hit.min)
                    }
                    Spacer(minLength: 0)
                }
            }
            Section("已选 (\(selCount))") {
                if selCount == 0 {
                    // 347 那句「双指下滑连续选 (双指区划由系统滚动提供)」在 iOS 上不存在: 系统没有多指选择手势,
                    // 也没有一个滚动容器替用户划出多选区。这里改成这一屏真做得到的三条路 (逐条点按 / 行右滑「选」/ 356 循环 + 350 智能选取)。
                    // 356 点按行选一条
                    // 350 点按行选一条
                    Text("点按行选一条; 行右侧滑动点「选」同样算一条。要连着选一片: 上面那枚循环键按 全选→反选→清空 走, 或用「智能选取」一次选一把 已过期/同成员/同类型。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                listBody
            }
        }
        .listRowSpacing(DS.Space.xs)
    }

    /// 354 选择位面 = 浏览位面: 归档条目既看不见, 也不许被"全选/反选/智能选取"选中 —
    /// 隐藏行一旦进破坏性批量 (353 停用 / 922 删除), 就是"看不到却被停掉"。台账级读数不走这里。
    // 2026-10-15 走查 (性能): isArchived 每条一次全量解码 ⇒ N 条 = O(N²) 解码。集合一次取, 行为不变。
    var selectablePwds: [LedgerPwd] {
        let arch: Set<Int> = []
        return DB.listPwds(mac).filter { !arch.contains($0.alias) }
    }
    var selectableFps: [LedgerFp] {
        let arch: Set<Int> = []
        return DB.listFps(mac).filter { !arch.contains(100000 + $0.batch) }
    }
    var selectableTotal: Int { selectablePwds.count + selectableFps.count }
    var cycleLabel: String {
        let total = selectableTotal
        if selCount == 0 { return "全选 (\(total) 条)" }
        if selCount == total { return "已全选 (\(total))" }
        return "已选 \(selCount) / \(total) — 反选"
    }
    var cycleNextLabel: String {
        let total = selectableTotal
        if selCount == 0 { return "反选" }
        if selCount == total { return "清空" }
        return "全选"
    }
    func cycleSelect() {
        let allP = selectablePwds.map { $0.alias }
        let allF = selectableFps.map { $0.batch }
        let total = allP.count + allF.count
        if selCount == 0 {
            selPwds = allP; selFps = allF
        } else if selCount == total {
            selPwds = []; selFps = []
        } else {
            selPwds = allP.filter { !selPwds.contains($0) }
            selFps = allF.filter { !selFps.contains($0) }
        }
    }
    // 2026-10-28 修复：原实现是**空壳** —— 注释写着「智能选择已删」，
    // 然后把 selPwds/selFps 原样写回，再弹一个「已套用 N 条」的**假 toast**。
    // 用户以为筛选了，实际一条都没变。现在三个档各自真实现。
    func applySmart(_ s: String) {
        let pwds: [Int]
        let fps: [Int]
        switch s {
        case "已过期":
            // 只选「已过期」这一态；指纹没有过期概念，不参与
            pwds = sortedPwds.filter { CredentialOrg.pwdState($0) == 2 }.map { $0.alias }
            fps = []
        case "同成员":
            // 以「当前已选中的第一条」为锚，选同归属的其余行；没有选中时按未归属处理
            let anchorOwner = selPwds.first.flatMap { a in
                sortedPwds.first { $0.alias == a }?.owner
            }
            pwds = sortedPwds.filter { $0.owner == anchorOwner }.map { $0.alias }
            let anchorFpOwner = selFps.first.flatMap { b in
                sortedFps.first { $0.batch == b }?.owner
            }
            fps = sortedFps.filter { $0.owner == anchorFpOwner }.map { $0.batch }
        default:   // "同类型"
            // 同类型 = 按当前 seg 那一类：临时码档只选 temp，密码档只选非 temp，指纹档只选指纹
            if seg == 3 {
                pwds = sortedPwds.filter { $0.temp }.map { $0.alias }
                fps = []
            } else if seg == 1 {
                pwds = sortedPwds.filter { !$0.temp }.map { $0.alias }
                fps = []
            } else if seg == 2 {
                pwds = []
                fps = sortedFps.map { $0.batch }
            } else {
                pwds = sortedPwds.map { $0.alias }
                fps = sortedFps.map { $0.batch }
            }
        }
        selPwds = pwds
        selFps = fps
        let total = pwds.count + fps.count
        if total == 0 {
            // 如实说「一条都没选到」，不要弹「已套用 0 条」那种看起来成功的话
            app.showToast("「\(s)」在这个筛选下没有可选的条目")
        } else {
            app.showToast("「\(s)」已选中 \(total) 条")
        }
        DS.Haptics.tick.impactOccurred()
    }
}
