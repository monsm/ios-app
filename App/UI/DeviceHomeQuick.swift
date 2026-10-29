// 设备页 · 快捷格 / 最近开门 / 模块排序
// 2026-10-29 从 DeviceHomeBlocks.swift（763 行）拆出。
import SwiftUI

extension DeviceHomeView {
    var quickActions: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionTitle(text: "快捷操作")
                .padding(.horizontal, DS.Space.gutter)
            // 230 大格模式: 2 列大格 (长辈友好, 设置-辅助可切); 229 左手模式镜像工具条侧
            let cols = AXPrefs.bigTile ? 2 : 3
            GlassEffectContainer(spacing: DS.Space.s) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: cols),
                          spacing: DS.Space.s) {
                    // 905: 格子来自池子 (默认选中就是原来的六格，观感不变; 921 加了"再开一次")；
                    // 1047: 顺序由 QuickPool.ordered() 决定 —— 默认关还跟一条 30 天规则:
                    //        从未手动调整过且满 30 天 → 只把最常用的一格提到首格, 其余保序。
                    // 仍走 quickLink 这一个渲染器：它带着 .axGlass / .contentShape / 按压态 / 朗读标签，
                    // 在网格里另抄一份 label 就等于把这四样悄悄丢了 (第七十八批差点犯的那条)。
                    ForEach(tiles) { a in
                        if a.id == "again" {
                            // 921: 这一格是 Button 不是 NavigationLink —— 它不推开新页, 而是跨 Tab 定位
                            againTile
                                .contextMenu {
                                    // 2026-10-28 界面审核修复：这里原本是空的 Button 动作 ——
                                    // 「编辑快捷操作格」点了什么都不发生。而上方注释还写着"面板内改动即时生效"，
                                    // 说明面板本该存在，只是调用被删空了。
                                    // 现在接到模块排序与显隐面板（同一张面板，快捷格顺序也在里面调）。
                                    Button {
                                        DS.Haptics.tick.impactOccurred()
                                        showModuleOrder = true
                                    } label: {
                                        Label("编辑快捷操作格", systemImage: "square.grid.2x2")   // 905 编辑快捷操作格
                                    }
                                }
                        } else {
                            quickLink(icon: a.icon, label: a.label,
                                      onTap: {
                                          // 1047: 静默记一次本机点击 (手动关过开关即停记, 见 QuickPool.recordingOn)
                                          QuickPool.recordTap(a.id)
                                      }
                            ) { quickDestination(a.id) }
                            // 905: 长按任一格 → 编辑面板。走系统 contextMenu 而不是自挂长按手势:
                            // 与 NavigationLink 的点击零冲突 (同 740 "长按走菜单"的先例), 面板内改动即时生效。
                            .contextMenu {
                                // 2026-10-28 界面审核修复：这里原本是空的 Button 动作 ——
                                // 「编辑快捷操作格」点了什么都不发生。而上方注释还写着"面板内改动即时生效"，
                                // 说明面板本该存在，只是调用被删空了。
                                // 现在接到模块排序与显隐面板（同一张面板，快捷格顺序也在里面调）。
                                Button {
                                    DS.Haptics.tick.impactOccurred()
                                    showModuleOrder = true
                                } label: {
                                    Label("编辑快捷操作格", systemImage: "square.grid.2x2")   // 905 编辑快捷操作格
                                }
                            }
                        }
                    }
                    // 812 延迟添加指纹: 这把锁一枚指纹都没有时，格尾多一枚**虚线待添加**格。
                    // 点它直接开真正的录入表单 (quickDestination addFp = 与"添加指纹"大格同一个
                    // 嵌入视图, 不是第二份校验逻辑); 旧版只弹 toast 指点去凭证 Tab, 等于把用户支走。
                    if DB.listFps(app.currentMac).isEmpty {
                        NavigationLink {
                            quickDestination("addFp")
                        } label: {
                            VStack(spacing: DS.Space.xs) {
                                Image(systemName: "hand.raised.dotted")
                                    .font(.system(size: DS.Icon.md))
                                    .foregroundStyle(DS.Palette.textSub)
                                Text("待添加指纹")
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.m)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                                    .strokeBorder(DS.Palette.hairline,
                                                  style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            )
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("这把锁还没有指纹，轻点直接添加")   // 812 这把锁还没有指纹
                    }
                }
            }
        }
    }
    /// 905/1047: `onTap` 是给 1047 记频次用的**可选**回调。
    /// 用 simultaneousGesture 而不是把 NavigationLink 换成 Button：换掉就会丢导航，
    /// 而 simultaneousGesture 让点击既走导航又能记账。传 nil 时一个手势都不加。
    func quickLink<Content: View>(icon: String, label: String,
                                          onTap: (() -> Void)? = nil,
                                          @ViewBuilder content: () -> Content) -> some View {
        // 2026-10-17 真机勘误「首页快捷操作点了没反应」: 记账原先是挂在 NavigationLink 的 **label**
        // 上的 simultaneousGesture(TapGesture) —— 同一次点击被两个手势系统抢 (label 的 Tap 与
        // NavigationLink 自身的激活), 结果就是"次数记上了、页面没进去"。label 现在零手势,
        // 记账挪到**目的地出现时**, 语义也更准 (用过这一格 = 进过它的页面)。
        NavigationLink {
            content().onAppear { onTap?() }
        } label: {
            quickTileBody(icon: icon, label: label)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
    /// 格子的图标 + 文字本体 (quickLink 与被 921 换成的按钮格共用, 免得两份样式漂移)
    @ViewBuilder
    func quickTileBody(icon: String, label: String) -> some View {
        let big = AXPrefs.bigTile   // 230 大格: 图标与字号随加大
        VStack(spacing: DS.Space.s) {
            // 图标坐进主色 12% 的圆角底座: 四个入口有了统一的"图标 + 玻璃砖"节奏
            Image(systemName: icon)
                .font(.system(size: big ? DS.Icon.lg : DS.Icon.md, weight: .semibold))
                .foregroundStyle(DS.Palette.accentText)
                .frame(width: big ? 48 : 40, height: big ? 48 : 40)
                .background(DS.Palette.accentText.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(label)
                .vkFont(big ? .callout : .caption)
                .foregroundStyle(DS.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: DS.Hit.min + DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        // 2026-10-18 表面预算 (MASTER.md §3.1): 快捷格是 **4 格一屏的网格**,
        // 每格都上玻璃 = 同屏 4 层玻璃面, 直接把「同屏 ≤3」顶穿。
        // 改成实底 + hairline 描边: 4 格之间仍有清晰的块面节奏, 但不再叠材质。
        // 用语法层的 variantPlate (它同时管底衬 + 可选发丝描边), 而不是自己写 background/overlay:
        // ① 自绘预算只认字面 token, 走语法层才不会被计成"新写的盒子";
        // ② `.overlay(.rect(...))` 里 `.rect` 会被推断成 ShapeStyle 而报
        //    "type 'ShapeStyle' has no member 'rect'" —— 这是 CI run 39107518727 抓到的真实编译错误。
        .variantPlate(DS.Palette.surface, .tile, edge: DS.Palette.hairline)
        .contentShape(Rectangle())
    }

    /// 921「再开一次」格: 目标 = QuickPool.repeatTarget (星标密码 > 星标指纹 > 高频推断)。
    /// 星标集为空且推不出一条时, 点按给"先去点亮星标"的指路 toast —— 不猜、不假装能开。
    @ViewBuilder
    var againTile: some View {
        let target = QuickPool.repeatTarget(app.currentMac)
        Button {
            QuickPool.recordTap("again")
            if let t = target {
                app.pendingCredNav = t.nav
                app.pendingCredNavMac = app.currentMac
                app.requestRoute(.credentials)   // 2026-10-14 走查: 原为直写 tabSelection, 访客态会绕过 377 门禁
                app.showToast("已跳到凭证页定位「" + t.name + "」")   // 921 界面文案
            } else {
                app.showToast("还没有星标凭证 —— 先在凭证页给最常用的那条点亮星标")   // 921 还没有星标凭证
            }
        } label: {
            quickTileBody(icon: "arrow.counterclockwise", label: "再开一次")
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("再开一次")   // 921 再开一次
        .accessibilityHint(target.map { "跳到凭证页定位 " + $0.name } ?? "还没有星标凭证, 先去凭证页点亮星标")
    }




    /// 559 落地: 「最近开门」行上可证明的成员 → 记录 Tab 并按该成员过滤。
    /// 复用 582 的 pendingRecordsMember → landMember 链路 (记录页消费后清空, 不残留过滤)。
    // 【保留未接 2026-10-29】「最近开门」行点成员 → 跳记录页按 TA 过滤（配套 provableMemberId/mergedLine）
    func openMemberRecords(_ id: String) {
        app.pendingRecordsMember = id
        app.requestRoute(.records)
    }


    // ---------- 派生数据 (包3: 参数化到任意锁 — 当前页吃实时, 其余页读快照) ----------
    /// 826 聚光教练标: nil = 不显示; 0/1/2 = 当前焦点序号 (只在首进设备 Tab 时出现一次)
    // 904 模块排序: 排序表开关 + 改完强制重算 (顺序存在 DB 里)
    /// 904 三模块的当前顺序 (槽位固定, 默认 = 现状, 所以默认渲染逐字节不变)。
    /// 存的是**顺序串** (kf_dev_order = "hero,quick,recent"), 非法/缺失一律回落默认。
    var devOrder: [String] {
        let _ = orderTick
        let raw = DB.store.getString("kf_dev_order")
        let ids = raw.isEmpty ? [] : raw.split(separator: ",").map(String.init)
        return (ids.count == 3 && Set(ids) == Set(["hero", "quick", "recent"])) ? ids : ["hero", "quick", "recent"]
    }
    func moduleName(_ id: String) -> String {
        switch id {
        case "quick": return "快捷操作格"
        case "recent": return "最近开门"
        default: return "状态卡 (Hero)"
        }
    }
    func moveModule(_ i: Int, _ d: Int) {
        var o = devOrder
        let j = i + d
        guard o.indices.contains(i), o.indices.contains(j) else { return }
        o.swapAt(i, j)
        DB.store.set("kf_dev_order", o.joined(separator: ","))
        orderTick += 1
    }
    /// 904: 把模块放进某个槽位 (868 的扫描组标签随模块走, 不因换槽丢掉)
    @ViewBuilder
    func moduleSlot(_ id: String, delay: Int) -> some View {
        switch id {
        case "quick":
            quickActions
                .accessibilityElement(children: .contain)
                .accessibilityLabel("快捷操作格组")   // 868 快捷操作格组
        // 2026-10-28 修复：原来这个 switch 只判 "quick"，
        // devOrder 默认是 ["hero","quick","recent"] ⇒ hero 与 recent **都落 default 画成 heroCard**，
        // 同屏两张几乎相同的身份卡，而「最近开门」模块根本不存在。
        // 现在三个槽各有各的渲染器。
        case "hero":
            if let kc = app.current {
                heroCard(for: kc, isCurrent: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("状态卡组")
            }
        case "recent":
            recentModule
        default:
            EmptyView()
        }
    }

    /// 2026-10-28 新增：「最近开门」模块（devOrder 的第三个槽）。
    /// 数据来自 `app.recentRecords()` —— 那个方法早就实现了（含成员归属推断与告警标红），
    /// 但全仓零调用；`kf_recent_count`（设置-外观「最近开门条数」3/5/10）也因此一直空转。
    @ViewBuilder
    var recentModule: some View {
        let rows = app.recentRecords()
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionTitle(text: "最近开门")
                .padding(.horizontal, DS.Space.gutter)
            Card {
                if rows.isEmpty {
                    Text("还没有开门记录。连上锁后到「记录」页拉取一次。")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                                Image(systemName: r.warn ? "exclamationmark.triangle.fill" : "door.left.hand.open")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(r.warn ? DS.Palette.danger : DS.Palette.textSub)
                                    .accessibilityHidden(true)
                                Text(r.text)
                                    .vkFont(.footnote)
                                    .foregroundStyle(DS.Palette.text)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                // 2026-10-29 补（**后台有实现、前台一直零调用**）：`openMemberRecords` 就是给这行用的 ——
                                // `recentRecords()` 已带出 `whoId`（只在归属**可证明**时才带），这里接成可点：
                                // 点成员行 → 记录页按 TA 过滤。不可证明的行不响应（不猜、不弹"未知成员"）。
                                .contentShape(Rectangle())
                                .onTapGesture { if let id = r.whoId { openMemberRecords(id) } }
                                .accessibilityHint(r.whoId == nil ? "这条记录的归属推断不出来，不能按成员筛选" : "查看这位成员的全部记录")
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }
}
