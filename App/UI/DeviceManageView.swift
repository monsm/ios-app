// 设备管理页 (104 房间分组 / 107 多选批处理 / 766 排序置顶 / 767 分组场景)
// 原句落点: 104「设备管理支持自定义分组, 分组头可收起」、107「设备管理进入多选模式批量隐藏或调整分组」、
// 766「设置 Tab 设备管理拖动排序, 最常用锁置顶并同步设备 Tab 翻页顺序」。
// 这里只写"锁之间的关系": 顺序 (kf_lock_order) 与组名 (kf_lockmeta_.grp) 与隐藏旗标 (kf_lock_hidden_)。
// 一条都不碰协议、不碰凭证、不碰日志。
// 2026-10-15 走查: 这一段原先写着"三者都只在本机, BackupBundle 是 typed schema 没有这些字段, 所以换机恢复后
// 顺序与分组要重设" —— 那是 D-36 之前的旧账, 与本页页脚自相矛盾。**页脚才是真的**: BackupKit 的 Globals
// 里带 order/groups/folded/hidden 四键 (BackupKit 内 collectDeviceOrg), 所以这四样随全量备份包走;
// 只留在本机的只有锁档案的场所副标题 / 备注 / 符号色标。
import SwiftUI
import UIKit

struct DeviceManageView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    // 快照而不是每次 body 重算: 拖动/批量之后要立刻看见结果, 而 orderedDevices 读的是偏好盘
    @State private var locks: [Keychain] = []
    // 288 页头电量条带的数据: 与总览页同一个 LockStats.usage() 口径 (u.power 只作快照兜底,
    // 采样最新值由 BatteryStripCard 内部 displayPct 统一取)。跟随本页"快照"风格在 reload()
    // 顺路刷新 —— 拖动/批量的高频 body 重算里不重复解析日志。
    @State private var stripUsages: [LockUsage] = []
    // 28 分组折叠记忆: 存的是**组名**而不是段下标 —— 下标会因为新建/改名一个分组而整体错位,
    // 那等于把用户收起的状态撒到别的组头上。跨会话保留, 键 kf_group_folded。
    @State private var collapsed: Set<String> = Set(DB.store.get([String].self, "kf_group_folded") ?? [])
    @State private var multiSelect = false         // 107 多选模式
    @State private var sel = Set<String>()
    @State private var sorting = false             // 766 拖动排序模式 (打开系统编辑态才出拖动手柄)

    var body: some View { vkBody.destined(.deviceManage) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section {
                    // 288 电量总览条带 (本包拍板落点: 设备管理页头)。复用总览页同一份 BatteryStripCard
                    // (App/UI/DeviceStripCard.swift) —— 全仓仅一个实现, 低电靠左/升序/每锁一格的口径都由
                    // 组件自己维持, 两页拿同一 LockStats.usage() 口径的数据传入即逐格同现。
                    // 行形状收口: listRowInsets(EdgeInsets()) 抵掉列表默认内缩, Card 自带 gutter
                    // (同制式 SettingsView:303); 分隔线隐藏让卡浮在画布上 (同制式 RecordsView:1641)。
                    if !locks.isEmpty {
                        BatteryStripCard(usages: stripUsages)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                    Text("点一行 = 置顶并设为启动默认锁；要精细调序就点右上角「排序」, 出现行尾手柄后拖动。"   // 271/766 点一行
                         + "分好组后, 设备 Tab 上方会出现按组切换的胶囊, 切换胶囊菜单里也按组分区。")   // 767 分好组后
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if locks.isEmpty {
                    Section {
                        Text("台账里还没有门锁 — 先在设备页添加一台。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } else {
                    // 分组段 (104): 只有一组 (即谁都没分组) 时不套 Section 标题, 免得给一个假分组
                    ForEach(groups) { g in
                        if groups.count > 1 {
                            // 2026-10-13 run 59: 原来给这节写了 `} footer: {` —— 但
                            // `Section(isExpanded:content:header:)` 这一重载**没有 footer 参数**,
                            // 加了报 "extra trailing closure passed in call"。
                            // 折叠 (104) 必须走 isExpanded 重载, 所以把那句说明并进内容尾部。
                            Section(isExpanded: expandBinding(g.name)) {
                                rows(g.locks)
                                if g.name == LockArchive.ungroupedLabel {
                                    Text("「未分组」不是一个组, 只是还没归类的兜底段。")   // 104 未分组
                                        .vkFont(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                }
                            } header: {
                                // 标题必须是纯 Text: Section(isExpanded:) 的折叠箭头由列表自己画,
                                // 套一层 HStack 就没那枚箭头了 (104 的"分组头可收起"会静默变成"分组头")
                                Text("\(g.name) · \(g.locks.count)")
                            }
                        } else {
                            rows(g.locks)
                        }
                    }
                    Section {
                        Button("按添加时间排序") { sortByPairedAt() }   // 769 按添加时间排序
                        Button("恢复绑定先后 (清掉手工排序与置顶)", role: .destructive) {
                            // 2026-10-15 走查: 这一颗一键就把手工排出来的顺序与置顶抹掉, 没有撤销条
                            // (`clearManualOrder` 就是 remove 那个键), 而它上面那颗"按添加时间排序"是可再排的
                            // —— 同一段里不可逆的那一颗反而问得最少。补一次确认, 与本页其余破坏性动作同口径。
                            confirmDestructive("恢复绑定先后",
                                               "会清掉手工拖出来的排序与置顶, 改回按绑定时间的先后。没有撤销, 要重排得再拖一次。门锁、凭证与日志都不受影响。",
                                               confirmTitle: "恢复") { resetOrder() }
                        }
                    } footer: {
                        Text("顺序、分组、分组折叠与隐藏会随全量备份包走 (D-36)：换机恢复后不用重排；"
                             + "锁档案里的场所副标题 / 备注 / 符号色标仍只存本机。不写门锁, 也不影响凭证与日志。")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
            }
            .navigationTitle("设备管理")
            .variantList()
            .dsScreenBackground()
            .environment(\.editMode, .constant(sorting ? .active : .inactive))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("完成") { close() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(multiSelect ? "退出多选" : "多选") {   // 107 多选
                        multiSelect.toggle()
                        sel.removeAll()
                        if multiSelect { sorting = false }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(sorting ? "结束排序" : "排序") {   // 766 排序
                        sorting.toggle()
                        if sorting { multiSelect = false; sel.removeAll() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if multiSelect && !sel.isEmpty { batchBar } }
            .onAppear { reload() }
        }
    }

    // ---------- 数据 ----------
    private var groups: [LockGroup] { LockArchive.grouped(locks) }
    private func reload() {
        locks = LockArchive.orderedDevices(app.devices)
        stripUsages = LockStats.usage()   // 288: 条带数据与 locks 同一时机刷新
    }
    private func expandBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(name) },
            set: { on in
                if on { collapsed.remove(name) } else { collapsed.insert(name) }
                DB.store.setCodable("kf_group_folded", collapsed.sorted())   // 28 折叠记忆
            }
        )
    }
    /// 顺序落库的唯一出口: 写表 → 首位同步成启动默认锁 (271/766 的同一条不变量) → 重载快照。
    /// 为什么每次改顺序都要动 kf_default_mac: 页眉写的是"第一行就是启动默认锁",
    /// 让首位与默认锁各走各的, 那句话当场就成了假话 —— 不如把不变量收在这一个出口里。
    private func persist(_ verb: String) {
        LockArchive.setOrder(locks.map { $0.mac })
        if let head = locks.first { LockArchive.setDefaultMac(head.mac) }
        reload()
        let hn = locks.first.map { LockArchive.displayName($0) } ?? ""
        app.showToast(verb + " · 首位「" + hn + "」即启动默认锁")
    }

    @ViewBuilder
    private func rows(_ slice: [Keychain]) -> some View {
        ForEach(slice) { kc in
            row(kc)
        }
        // onMove 挂在 ForEach 上而不是逐行: 挂在行上每行都会收到同一份 IndexSet, 拖一次会重复搬 N 次。
        // 传进来的 IndexSet/Int 是**这一段 (slice) 内部**的下标, 所以回写走 reordered 而不是整表 move。
        .onMove { src, dst in
            var moved = slice
            moved.move(fromOffsets: src, toOffset: dst)
            locks = LockArchive.reordered(locks, newGroupOrder: moved)
            persist("顺序已更新")
        }
    }

    private func row(_ kc: Keychain) -> some View {
        let name = LockArchive.displayName(kc)
        let isDef = kc.mac == LockArchive.defaultMac
        let hidden = LockArchive.isHidden(kc.mac)
        let g = LockArchive.group(kc.mac)
        return HStack(spacing: DS.Space.s) {
            if multiSelect {
                Button {
                    if sel.contains(kc.mac) { sel.remove(kc.mac) } else { sel.insert(kc.mac) }
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Image(systemName: sel.contains(kc.mac) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: DS.Icon.md))
                        .foregroundStyle(sel.contains(kc.mac) ? DS.Palette.accent : DS.Palette.hairlineStrong)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sel.contains(kc.mac) ? "已选中 \(name)" : "选中 \(name)")
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    Circle().fill(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .vkFont(.subheadline, weight: .medium)
                        .lineLimit(1)
                    if isDef {
                        Text("首位 · 启动默认")
                            .vkFont(.caption2, weight: .medium)
                            .foregroundStyle(DS.Palette.onAccent)
                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xxs)
                            .variantPlate(DS.Palette.accent, .capsule)
                    }
                }
                HStack(spacing: DS.Space.xs) {
                    Text(subtitle(kc))
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    if hidden {
                        Label("已隐藏", systemImage: "eye.slash")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.warn)   // 114/108: 提示色, 不是错误色
                    }
                    if LockArchive.isSleeping(kc.mac) {
                        Label("沉睡", systemImage: "moon.zzz.fill")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Spacer(minLength: 0)
                }
                Text(LockArchive.boundLabel(kc.pairedAt))   // 769 每锁行显示"绑定于 …"小字
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
            Spacer(minLength: 0)
            // 71 每行右侧迷你信号格 (本包落点: 设备管理页锁行)。RSSI 走 LinkSense.rssiFor ——
            // 只有真扫到过才渲染: rssiLevel(nil) 归 0, 若照样画就成一排全灰格子, 把"从未扫描"
            // 冒充成"信号为零"即虚构数据 (入口判 nil 的制式同 LockOverviewView:267 的过滤)。
            // 本页每行恰对应一把锁 (一个 Keychain), 分组头走 Section header 不经过这里, 挂点无错位。
            // 尺寸收 mini: 档位短词 caption2 + RSSIBars 四格约 18pt, 行内 Spacer(minLength:0) 先让位,
            // 名称与副标题本就 lineLimit(1), 长名压缩时优先保信号格宽度。
            if let rssi = LinkSense.rssiFor(kc.mac) {
                let lvl = LinkSense.rssiLevel(rssi)
                HStack(spacing: DS.Space.xs) {
                    Text(LinkSense.rssiLabel(lvl))
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                    RSSIBars(level: lvl, tint: lvl >= 3 ? DS.Palette.ok : DS.Palette.warn)
                }
                .accessibilityElement(children: .combine)
                // 制式抄 LockOverviewView:297; 锁名由整行 combine 统一读出, 这一枚只报信号档位
                .accessibilityLabel("信号 " + LinkSense.rssiLabel(lvl))
            }
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        // 多选模式下点整行 = 勾选; 平时点整行 = 置顶 (最常用的一下就到顶)
        .onTapGesture {
            if multiSelect {
                if sel.contains(kc.mac) { sel.remove(kc.mac) } else { sel.insert(kc.mac) }
            } else {
                pin(kc.mac)
            }
        }
        .contextMenu { menu(kc, hidden: hidden, groupName: g) }
        // 多选时必须 .contain: `.combine` 会把整行并成一个元素, 那枚勾选按钮就从 VoiceOver 里消失了 ——
        // 而这正是多选模式唯一的入口。平时 (非多选) 才合并成一行好读。
        .accessibilityElement(children: multiSelect ? .contain : .combine)
        .accessibilityHint(multiSelect ? "点按切换选中" : "点按置顶并设为启动默认锁")
    }

    private func subtitle(_ kc: Keychain) -> String {
        let m = LockArchive.meta(kc.mac)
        let place = m.place.isEmpty ? PidMap.productName(kc.pid) : m.place
        let grp = m.grp.isEmpty ? "" : " · " + m.grp
        return place + grp
    }

    @ViewBuilder
    private func menu(_ kc: Keychain, hidden: Bool, groupName: String) -> some View {
        Button { pin(kc.mac) } label: { Label("置顶并设为启动默认锁", systemImage: "arrow.up.to.line") }
        Button {
            LockArchive.setHidden(kc.mac, !hidden)
            // 108 已取消隐藏
            // 108 已隐藏这把锁
            app.showToast(hidden ? "已取消隐藏" : "已隐藏这把锁: 只在胶囊的已隐藏区可达")
        } label: {
            // 108 取消隐藏
            // 108 在翻页里隐藏
            Label(hidden ? "取消隐藏" : "在翻页里隐藏",
                  systemImage: hidden ? "eye" : "eye.slash")
        }
        Divider()
        Section("移入分组") {   // 104/767 移入分组
            ForEach(LockArchive.groupPresets, id: \.self) { p in
                Button {
                    LockArchive.setGroup(kc.mac, p)
                    reload()
                    app.showToast("已归入「" + p + "」")
                } label: {
                    if p == groupName { Label(p, systemImage: "checkmark") } else { Text(p) }
                }
                // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Button("自定义组名…") { promptGroup(kc.mac, current: groupName) }
            if !groupName.isEmpty {
                Button("移出分组", role: .destructive) {
                    LockArchive.setGroup(kc.mac, "")
                    reload()
                    app.showToast("已移出分组")
                }
            }
        }
    }

    private func promptGroup(_ mac: String, current: String) {
        let alert = UIAlertController(title: "自定义组名",   // 104 自定义组名
                                      message: "例如 大门 / 卧室 / 出租屋。最多 12 字, 组名会出现在设备页的切换胶囊上。",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "组名"; tf.text = current; tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let v = alert.textFields?.first?.text ?? ""
            LockArchive.setGroup(mac, v)
            reload()
            app.showToast(v.trimmingCharacters(in: .whitespaces).isEmpty ? "已移出分组" : "组名已更新")   // 104 组名已更新
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 置顶 = 首位 + 启动默认锁。规则收在 LockArchive.pinToFront 一处 (271 与 766 说的是同一件事),
    /// 页面这里只负责刷快照与说一句话。
    private func pin(_ mac: String) {
        LockArchive.pinToFront(mac, app.devices)
        reload()
        let hn = LockArchive.displayName(app.devices.first { $0.mac == mac } ?? Keychain(mac: mac, skey: ""))
        app.showToast("已置顶「" + hn + "」· 即启动默认锁")   // 271/766 即启动默认锁
    }
    /// 按给定的 mac 序列重排快照 (重复的 mac 只认第一次出现, 所以调用方可以直接拼 "选中的 + 全部")。
    private func reorder(_ macs: [String], _ verb: String) {
        let byMac = Dictionary(locks.map { ($0.mac, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let head = macs.compactMap { m -> Keychain? in
            guard !seen.contains(m), let kc = byMac[m] else { return nil }
            seen.insert(m)
            return kc
        }
        locks = head + locks.filter { !seen.contains($0.mac) }
        persist(verb)
    }

    // ---------- 107 批量工具条 ----------
    private var batchBar: some View {
        let n = sel.count
        return HStack(spacing: DS.Space.m) {
            Text("已选 \(n) 把")
                .vkFont(.footnote, weight: .medium)
                .foregroundStyle(DS.Palette.text)
            Spacer(minLength: 0)
            Button { batchHidden(true) } label: { Label("隐藏", systemImage: "eye.slash") }
                .vkFont(.footnote)
            Button { batchHidden(false) } label: { Label("显示", systemImage: "eye") }
                .vkFont(.footnote)
            Menu {
                ForEach(LockArchive.groupPresets, id: \.self) { p in
                    Button(p) { batchGroup(p) }
                }
                Button("自定义组名…") { promptGroupBatch() }
            } label: {
                Label("分组", systemImage: "rectangle.3.group").vkFont(.footnote)
            }
            Button("置顶") { batchPin() }
                .vkFont(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.gutter)
        .padding(.vertical, DS.Space.s)
        .background(.bar)
        .overlay(Rectangle().fill(DS.Palette.hairline).frame(height: 0.5), alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("批量处理已选 \(n) 把锁")   // 107 批量处理已选
    }
    private func batchHidden(_ on: Bool) {
        for m in sel { LockArchive.setHidden(m, on) }
        app.showToast("已" + (on ? "隐藏" : "显示") + " \(sel.count) 把锁")   // 107 把锁
        endBatch()
    }
    private func batchGroup(_ name: String) {
        for m in sel { LockArchive.setGroup(m, name) }
        app.showToast("已把 \(sel.count) 把锁归入「" + name + "」")   // 104/107 界面文案
        endBatch()
    }
    private func promptGroupBatch() {
        let alert = UIAlertController(title: "批量分组名",   // 107 批量分组名
                                      message: "选中的锁一起改到这个名字下。最多 12 字。",
                                      preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = "组名"; tf.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let v = alert.textFields?.first?.text ?? ""
            for m in sel { LockArchive.setGroup(m, v) }
            app.showToast("已把 \(sel.count) 把锁归入该组")   // 107 已把
            endBatch()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
    /// 批量置顶: 按当前列表次序把选中的几把依次提到前面 (选中的整体在前, 内部次序不变)。
    private func batchPin() {
        let chosen = locks.filter { sel.contains($0.mac) }.map { $0.mac }
        guard !chosen.isEmpty else { return }
        reorder(chosen + locks.map { $0.mac }, "已把 \(chosen.count) 把锁置顶")
    }
    private func endBatch() {
        sel.removeAll()
        reload()
    }
    /// 769 按添加时间: 最老绑定的排最上 (未记录绑定时间的垫底)。和拖动/置顶走同一条 persist 出口,
    /// 首位同步为启动默认锁的不变量对它同样成立 —— 排序结果与"第一行就是启动默认锁"不打架。
    private func sortByPairedAt() {
        locks = locks.sorted { a, b in
            let ae = a.pairedAt.isEmpty, be = b.pairedAt.isEmpty
            if ae != be { return !ae }
            return a.pairedAt < b.pairedAt
        }
        persist("已按添加时间排序")
    }
    private func resetOrder() {
        LockArchive.clearManualOrder()
        reload()
        // 说清楚清掉的是什么、留下的是什么: 手工顺序没了, 启动默认锁与设备页的低电置顶都还在。
        app.showToast("已恢复绑定先后排序 (启动默认锁仍在首位, 设备页仍按低电置顶)")
    }
    private func close() {
        // 顺序/分组/隐藏的落库都发生在动作当场, 这里只负责收页:
        // 设备页 sheet 的 onDismiss 会重算翻页序列与图标行。
        dismiss()
    }
}
