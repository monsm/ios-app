// 设置页 · 外观（主题 / 品牌色 / 圆角 / 密度 / 行高 / 数字字体 / 主控卡 / 快捷格 / 长辈模式 等 21 个控件）
// 2026-10-29 从 SettingsView.swift（1013 行）拆出。
// 是 SettingsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension SettingsView {
    var appearanceSection: some View {
        Section {
            // 外观模式 (idea 30): 跟随系统/浅色/深色/纯黑 — 纯黑为 OLED 省电与夜间的极暗档
            Picker("主题", selection: Binding(
                get: { DB.store.getString("kf_theme") },
                set: { app.setTheme($0) })) {
                Text("跟随系统").tag("")
                Text("浅色").tag("light")
                Text("深色").tag("dark")
                Text("纯黑 (AMOLED)").tag("black")
            }
            .pickerStyle(.menu)
            // 31 三套品牌色换肤 (原句"三套"): accent/accentText/渐变全 App 即时切换, 已由 886 扩到六套
            Picker("品牌色", selection: Binding(
                get: {
                    let v = DB.store.getString("kf_accent")
                    return v.isEmpty ? "indigo" : v
                },
                set: { app.setAccent($0) })) {
                ForEach(DS.accentThemes) { t in
                    HStack(spacing: DS.Space.s) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(t.preview)
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                        Text(t.name)
                    }
                    .tag(t.key)
                }
            }
            .pickerStyle(.menu)
            // 圆角档位 (900): 只动卡片/控件/格子三档，胶囊不参与
            Picker("圆角", selection: Binding(
                get: { DB.store.getString("kf_radius") },
                set: { app.setRadius($0) })) {
                Text("标准").tag("")
                Text("偏硬朗 (小)").tag("soft")
                Text("偏柔和 (大)").tag("plump")
            }
            .pickerStyle(.menu)
            // Hero 卡纹理 (889): 纯矢量三层之一，默认"无纹理"= 与旧版一致
            .pickerStyle(.menu)
            note("只换主控卡的底纹，不影响内容与读数。")
            // 动效档位 (899): 管的是全 App 动效令牌，不是"只换 Tab 那一下" —— 文案照实写
            Picker("动效强度", selection: Binding(
                get: { DB.store.getString("kf_motion").isEmpty ? "standard" : DB.store.getString("kf_motion") },
                set: { app.setMotionTier($0) })) {
                Text("克制").tag("calm")
                Text("标准").tag("standard")
                Text("活泼").tag("lively")
            }
            .pickerStyle(.menu)
            // 布局密度 (包16): 只缩放间距令牌, 字号与触达不动
            Picker("布局密度", selection: Binding(
                get: { DB.store.getString("kf_density") },
                set: { app.setDensity($0) })) {
                Text("标准").tag("")
                Text("紧凑").tag("compact")
                Text("宽松").tag("relaxed")
            }
            .pickerStyle(.menu)
            note("只改间距，字号与按钮大小不变。")
            // 凭证行高 (901): 两档 = 紧凑(隐藏副行, 只留名称与状态) / 舒适(加高, 带副行)。
            // 只加行最小高度，不动字号 —— 压矮会裁多行备注，那不是紧凑
            Picker("凭证行高", selection: Binding(
                get: { DB.store.getString("kf_row_h") },
                set: { app.setRowHeight($0) })) {
                Text("紧凑 (只留名称与状态)").tag("")
                Text("舒适 (加高)")   .tag("tall")
            }
            .pickerStyle(.menu)
            // 时间线行距 (907): 叠在上面的布局密度之上，两档体系是相乘不是各写一套
            Picker("时间线行距", selection: Binding(
                get: { DB.store.getString("kf_tl_gap") },
                set: { app.setTimelineGap($0) })) {
                Text("紧凑").tag("tight")
                Text("标准").tag("")
                Text("宽松").tag("loose")
            }
            .pickerStyle(.menu)
            // 902 数字字体两档: 单一令牌 DS.Metric.digitDesign, 落点只有主控卡读数与指标块两处。
            // 标签写明射程 —— 全仓 58 处散点读数不跟着换 (§84 撤掉的就是那种"总闸"假象),
            // 这里切的正是 902 原句"Hero 卡电量数字圆体/默认体可选"的那两处。
            Picker("主控读数数字字体", selection: Binding(   // 902 主控读数数字字体
                get: { DB.store.getString("kf_digit_font") },
                set: { app.setUnlockOption("kf_digit_font", $0) })) {
                Text("圆体 (默认)").tag("")
                Text("系统默认体").tag("plain")
            }
            .pickerStyle(.menu)
            note("只换主控卡上电量那几个数字的字体。")
            // Hero 参考指标位 (909): 电量刻意不给开关 (它决定还能不能开锁)
            VariantToggle("主控卡显示固件位", isOn: Binding(
                get: { DS.HeroStats.shows("firmware") },
                set: { v in app.setHeroStats(DS.HeroStats.all.filter { $0 != "firmware" || v }) }))
            VariantToggle("主控卡显示锁钟位", isOn: Binding(
                get: { DS.HeroStats.shows("lockclock") },
                set: { v in app.setHeroStats(DS.HeroStats.all.filter { $0 != "lockclock" || v }) }))
            note("主控卡上那几个小位要显示哪几个；电量不给关。")
            // 2026-10-27 四轮精简：素颜模式已删。
            // 最近开门条数 (idea 910): 设备页时间线长度
            Picker("最近开门条数", selection: Binding(
                get: { DB.store.getInt("kf_recent_count", 5) },
                set: { app.setRecentCount($0) })) {
                Text("3 条").tag(3)
                Text("5 条").tag(5)
                Text("10 条").tag(10)
            }
            .pickerStyle(.menu)
            // 892 自定义强调色 (ColorPicker 管线)。存的是"色相来源"，上屏的每一档都要过亮度带，
            // 所以选到近白/近黄这类压不住白字的颜色时，主卡不会变白糊一片 —— 是被压暗后的同色系。
            ColorPicker("自定义强调色 (会盖过上面六套)",
                        selection: Binding(
                            get: { Color(hex: DS.CustomAccent.rgb == 0 ? 0x4F46E5 : DS.CustomAccent.rgb) },
                            set: { c in
                                let hex = DS.CustomAccent.rgb(from: c)
                                app.setCustomAccent(hex)
                            }),
                        supportsOpacity: false)
            if DS.CustomAccent.isActive {
                Button { app.setCustomAccent(0) } label: {
                    Label("取消自定义，回到六套预设", systemImage: "arrow.uturn.backward")
                }
                    .vkFont(.footnote).foregroundStyle(DS.Palette.accentText)
                Text("自定义色只影响强调色、主控卡与按钮渐变；文字与语义色仍走系统令牌。选到很亮的颜色时会被压暗到能看清白字的范围，观感接近同色系的深色版。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 2026-10-27 四轮精简：儿童友好外观预设入口已删。
            // 记录页开场过滤策略 (908): 盖在 192"按锁记住上次过滤"之上的一层开场规则。
            // 措辞刻意避开"清除/删除"—— 三种策略都**不删**已存的会话过滤，只是决定进页面时从哪开始。
            Picker("记录页开场过滤", selection: Binding(
                get: { QueryFilters.policy },
                set: { QueryFilters.setPolicy($0) })) {
                Text("记住每把锁上次的过滤").tag("")
                Text("每次都从全部开始").tag("fresh")
                Text("每次默认只看告警").tag("alarm")
            }
            .pickerStyle(.menu)
            Text("这只改变进入记录页时的**起点**；你手动改过的过滤仍会按锁留着，切回上一项就还在。不会删任何记录。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 905 快捷格"十一选六" (921 加了"再开一次") + 1047 常用动作排前。
            // 放在"外观"这一节里是有意的：它改的是设备页那一圈格子的组成与次序，属于布局个性化；
            // 但要注意它改完是**立即生效**的 (走 bumpAppearanceForLayout 重建一次树)，
            // 不需要重进 App。
            ForEach(QuickPool.all) { a in
                VariantToggle(a.label, isOn: Binding(
                    get: { QuickPool.selected.contains(a) },
                    set: { on in
                        var ids = QuickPool.selected.map { $0.id }
                        if on { if !ids.contains(a.id) { ids.append(a.id) } }
                        else { ids.removeAll { $0 == a.id } }
                        // 一格都不留 = 快捷区整体消失，那是把"自定义"变成"自残"：兜回默认六格
                        QuickPool.setSelected(ids.isEmpty ? QuickPool.defaultIds : ids)
                        app.bumpAppearanceForLayout()
                    }))
            }
            Text("也可以直接在设备页长按任一快捷格打开这份编辑。")   // 905 也可以直接在设备页长
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
            VariantToggle("常用动作排到前面", isOn: Binding(   // 1047 常用动作排到前面
                get: { QuickPool.smartFirst },
                set: { v in
                    QuickPool.setSmartFirst(v)
                    if !v { QuickPool.clearCounts() }   // 关掉就把计数清空: 不留"统计还在偷偷跑"
                    app.showToast(v ? "开始按点击次数排序（只存本机）" : "已停止记录并清空计数")
                    app.bumpAppearanceForLayout()
                }))
            Text("没动过这个开关时: 本机静默记点击次数, 满 30 天后首格自动推荐最常用的一格; 关掉 = 停止记录并清空计数, 排序回到你手选的次序。")
                .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            if QuickPool.smartFirst {
                let c = QuickPool.counts
                Text(c.isEmpty ? "还没攒到点击记录：去设备页点几次快捷格。"
                               : "已记录: " + QuickPool.all.filter { c[$0.id] != nil }
                                   .map { "\($0.label) \(c[$0.id]!) 次" }.joined(separator: " · "))
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 恢复默认外观 (idea 202): 带确认弹窗, 只重置外观偏好
            // ---------- 2026-10-26 补的 4 枚开关 ----------
            // 这四枚的读取与消费代码本来就都在（长按进度条 / 快捷格列数 / 双击防抖 / 低电阈值），
            // 但**全仓没有写点** —— 键永远等于默认值，等于开关不存在。补在这里让它们真能用。
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Picker("长按确认时长", selection: Binding(
                    get: { AXPrefs.holdDuration },
                    set: { app.setUnlockOption("kf_ax_hold", String(format: "%.1f", $0)) })) {
                    ForEach([0.4, 0.6, 0.9, 1.2, 1.6], id: \.self) { s in
                        Text(String(format: "%.1f 秒", s)).tag(s)
                    }
                }
                .pickerStyle(.menu)
                // 520 行那句"可在辅助功能里 0.4–1.6s 自定"长期是空承诺（没有那个页），现在成真。
                Text("按住圆盘多久算确认。关掉「按住确认」后此项不生效。")
                    .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
            }
            // 2026-10-28 补：`MemberHub.setElderMode` 全仓零调用 —— 而 `MemberHub.elderMode` 有 6 处 UI 消费
            // （凭证页分段从 4 段降到 3 段、完成页切「口述卡」、隐藏部分次要入口）。
            // 于是「长辈模式」永远开不了，那 6 处分支是**永远走不到的死路**。
            VariantToggle("长辈模式 (分段更少 / 大字 / 口述卡)", isOn: Binding(
                get: { MemberHub.elderMode },
                set: { on in
                    MemberHub.setElderMode(on)
                    app.bumpAppearanceForLayout()
                    app.showToast(on ? "长辈模式已开启：凭证页分段精简为 3 档" : "长辈模式已关闭")
                }))
            VariantToggle("大格模式 (快捷格 2 列)", isOn: Binding(
                get: { AXPrefs.bigTile },
                set: { app.setUnlockOption("kf_bigtile", $0) }))
            VariantToggle("双击防抖 (0.3 秒内忽略重复触发)", isOn: Binding(
                get: { AXPrefs.dbltapGuard },
                set: { app.setUnlockOption("kf_dbltap_guard", $0) }))
            Picker("低电提醒阈值", selection: Binding(
                get: { CareSchedule.battThreshold },
                set: { app.setUnlockOption("kf_batt_threshold", $0) })) {
                // 只给 10/15/20：CareSchedule.battThreshold 的白名单就是这三个（其它值会被夹回 15）。
                // 多给档位等于给一个"选了不生效"的选项。
                ForEach([10, 15, 20], id: \.self) { v in
                    Text("\(v)%").tag(v)
                }
            }
            .pickerStyle(.menu)
            Button { app.resetAppearance() } label: {
                Label("恢复默认外观", systemImage: "arrow.uturn.backward.circle")
            }
        } header: {
            Text("外观")
        } footer: {
            Text("主题、品牌色（六套）、密度、圆角、高对比、周起始日、行高与行距、指标位、纹理、动效强度、节日色、每日一句话都在本机生效，即时可见，不上传。高对比与系统「辅助功能-增加对比度」是并联关系，任一开着都加强；系统「减弱动态效果」会把动效强度压到克制档。素颜模式一键关闭庆祝与徽章动效；纯黑适合 OLED 夜间。")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
