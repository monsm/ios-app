// 记录页 · 工具栏 / 列表壳 / 复制与导出
// 2026-10-29 从 RecordsView.swift（672 行）拆出。
import SwiftUI

extension RecordsView {
    @ToolbarContentBuilder
    var recordsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            // 读取中把刷新按钮换成进度圈, 状态一目了然
            if running {
                ProgressView()
                    .accessibilityLabel("正在读取门锁记录")
            } else {
                Button { Task { await fetch() } } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("重新读取门锁记录")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                if app.current != nil {
                    Button { copyLastWeekDigest() } label: { Label("复制上周小结", systemImage: "doc.on.clipboard") }   // 698 复制上周小结
                    Button { showRangePick = true } label: { Label("选区导出", systemImage: "checklist") }   // 716 选区导出
                    Button { showActiveCreds = true } label: { Label("活跃凭证排序 (约)", systemImage: "list.number") }
                    Button { showOutWin = true } label: { Label("越界开门清单 (约)", systemImage: "clock.badge.exclamationmark") }
                    // 2026-10-28 修复：`showAlarmKinds` 原来只有 sheet 绑定、**零 true 写点** ——
                    // AlarmKindsSheet 是完整可用的功能（告警类型多选），却没有任何入口能打开它。
                    Button { showAlarmKinds = true } label: { Label("告警类型筛选", systemImage: "line.3.horizontal.decrease.circle") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多")
        }
    }

    var body: some View { vkBody.destined(.records) }
    var vkBody: some View {
        recordsChrome
    }

    /// 记录页二选一 (无锁占位 / 主体列表) —— 从 recordsCore 拆出: 该表达式报 type-check 超时
    @ViewBuilder
    var recordsGroup: some View {
        if app.current == nil {
            noLockPlaceholder
        } else {
            mainList
        }
    }

    /// 记录页核心内容 (Group + 页面级修饰符) —— 从巨型 body 拆出: 原表达式报 type-check 超时
    @ViewBuilder
    var recordsCore: some View {
        // 2026-10-28 修复：同凭证页 —— LockScreen 承诺「记录显示为空」，
        // 但 decoyMode 不驱动任何视图清空。这里补上空壳态。
        if app.decoyMode {
            List {
                Section {
                    EmptyState(systemImage: "list.bullet.rectangle",
                               title: "还没有记录",
                               message: "连上锁后点右上角「重新读取」从锁内拉取开门记录。")
                }
            }
        } else {
        // 2026-10-13 run 69: 原来这里是 `Group { if… }` —— Group 包一层再叠修饰符仍报 type-check 超时;
        // 改成 @ViewBuilder 计算属性 (无 Group 包装), 分支类型由构建器收成 _ConditionalContent。
        recordsGroup
        .navigationTitle("记录")
        // 192: 过滤组合按锁留存 (清空全部过滤时自动删键, 不留脏值)
        // 2026-10-15 走查: 只存"与开场值不同"的组合。唯一的理由是 onRecordsAppear 里那次
        // **按 908 策略的重取** —— fresh/alarm 两档下 load() 返回的是**派生值** (空白 / 仅告警),
        // 原样存回去会把用户真存着的那份覆盖掉, fresh 档更会直接删键
        // (save 里 `self == QueryFilters()` 走 remove)。
        // 换锁那一路不必在这里补: 父层的 `RecordsView().id(app.currentMac)` 会让整页重建,
        // @State 连同 filters 一起重读 (见 LockKeeperApp 里 credentialsTabContent 那段注释)。
        .onChange(of: filters) { _, new in
            let mac = DB.preferredMac()
            guard !mac.isEmpty, new != QueryFilters.load(mac: mac) else { return }
            new.save(mac: mac)
        }
        .variantList()
        .dsScreenBackground()
        .toolbar {
            recordsToolbar
        }
        .onAppear { onRecordsAppear() }
        // 2026-10-30 删除（第 114 轮）：这里原本挂着一个**空的** `.onChange(of: app.currentMac) { _, _ in }`，
        // 上面那句注释描述着「从设备页/矩阵点另一把锁回来时 allRows 还是旧锁的」这个问题 ——
        // 但**处理体是空的**，等于声明了一个修复却什么都没做（「文档虚构能力」那一族）。
        //
        // 而这个问题**本身并不存在**：`RootTabs.swift:344` 是 `RecordsView().id(app.currentMac)`，
        // 换锁时整页连同 @State 一起重建，`allRows` 从空开始、`onRecordsAppear` 重新读新锁缓存。
        // 所以正确的做法不是补处理体，而是把这个空壳与它那句误导注释一起删掉。
        // （`RecordsChrome.swift:75-76` 早就写着「换锁那一路不必在这里补」—— 两处注释互相矛盾，留了半年。）
        .onChange(of: app.pendingSearch) { _, q in
            guard let q else { return }
            landSearch(q)
        }
        .onChange(of: app.pendingRecordKey) { _, k in
            guard let k else { return }
            landRecordKey(k)
        }
        .onChange(of: app.pendingRecordsDay) { _, d in
            guard let d else { return }
            landDay(d)
        }
        .onChange(of: app.pendingFlashKey) { _, k in
            guard let k else { return }
            landFlash(k)
        }
        .onChange(of: app.pendingRecordsFilter) { _, f in
            guard let f else { return }
            sel = f
            applyFilter()
        }
        .onChange(of: app.pendingRecordsMember) { _, m in
            // 582 图表下钻: 统计页已随本轮删减移除, 这条落点保留给其它来源。
            // 所以点成员条跳过来什么也没发生。落点在 landMember —— 与点成员 chip 走同一条过滤链。
            guard let m else { return }
            landMember(m)
        }
        .onChange(of: scope) { _, s in
            sel = ""
            searchText = ""
            parsedTags = []
            highlightTokens = []
            filters = QueryFilters()
            reversed = false
            applyFilter()
        }
        .onChange(of: filters) { applyFilter() }
        .onChange(of: reversed) { applyFilter() }
        .onChange(of: searchText) { _, t in
            // 解析预览标签是纯字符串活，立刻更新（用户要看到"识别成了什么"）。
            let q = RecordSearch.parse(t)
            parsedTags = q.parsedTags
            highlightTokens = q.must
            // 562 边输入边更新 —— 但全量重建加 180ms 防抖：原来每敲一个字都重建一次
            // （buildRecs + Attribution.classify + groupByDay + fillGaps），快速输入 10 个字就是 10 次。
            searchDebounce?.cancel()
            searchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                applyFilter()
            }
        }
        .onDisappear { searchDebounce?.cancel() }
        }
    }

    /// 记录页外层 (导航栈 + 弹窗/弹框) —— 同上, 继续拆
    @ViewBuilder
    var recordsChrome: some View {
        NavigationStack {
            recordsCore
        }
        // 2026-10-28 删除：原「行备注弹窗」(noteTarget alert) 是死 alert —— 全仓只有 = nil 写点。
        // 2026-10-28 删除：`noteTarget` 是**死 alert** —— 全仓只有 `= nil` 写点，
        // 这个弹窗永远不会呈现。备注编辑走详情卡里的 noteSection（RecordOverlay 单一写侧）。
        .sheet(isPresented: $showRangePick) { rangePickSheet }
        .sheet(isPresented: $showActiveCreds) { ActiveCredsSheet() }
        // 565 告警类型多选: 选中集直接写回 filters (走既有 onChange(of: filters) → applyFilter)
        .sheet(isPresented: $showAlarmKinds) { AlarmKindsSheet(sel: $filters.alarmKinds) }
        .sheet(isPresented: $showOutWin) { OutWinSheet() }
        .sheet(item: $detailRec) { rec in
            // 186/188 备注与标旗在详情卡里改, 关闭时要让时间线重算 (沿用 735 的 alarmTick 刷新机制)
            // 580/584: 把**当前显示顺序**交给详情卡，上下条与邻近横滑才走在用户刚才看到的那份结果里
            RecDetailSheet(rec: rec, siblings: displayedRecs, scopeAll: scope == 1)
                .onDisappear {
                    // 583: 详情关了才滚+闪 (见 flashOnClose)
                    if !flashOnClose.isEmpty {
                        let k = flashOnClose
                        flashOnClose = ""
                        flashRow(k)
                    }
                }
        }
    }
}
