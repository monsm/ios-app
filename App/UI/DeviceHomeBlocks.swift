// 设备页 · 渲染块（组筛选 / Hero 卡 / 异常卡 / 连接感知 / 圆盘 / 快捷格 / 最近开门）
// 2026-10-29 从 DeviceHomeView.swift（1265 行）拆出。
// 是 DeviceHomeView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension DeviceHomeView {
    var groupNameList: [String] {
        LockArchive.grouped(LockArchive.orderedDevices(app.devices)).map { $0.name }
    }
    @ViewBuilder
    var groupChips: some View {
        let names = groupNameList
        if names.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    chip("", "全部")   // 767 全部
                    ForEach(names, id: \.self) { n in chip(n, n) }
                }
                .padding(.horizontal, DS.Space.gutter)
            }
            .accessibilityLabel("按组切换门锁, 当前\(groupFilter.isEmpty ? "全部" : groupFilter)")
        }
    }
    func chip(_ name: String, _ label: String) -> some View {
        let on = groupFilter == name
        return Button {
            groupFilter = name
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(label)
                .vkFont(.subheadline, weight: .medium)
                .lineLimit(1)
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, 12)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.text)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }


    // 243 断连灰化: 连接断开时整卡去饱和, 恢复即回彩
    // 包3: 参数化到任意锁 — 当前页吃实时状态, 其余页读各锁快照 (101/763 横滑预览)
    func heroCard(for kc: Keychain, isCurrent: Bool) -> some View {
        let connected = isCurrent && bleOn
        // 113 五档电量 / 120: 低电降级档 (≤20%) 关流光边并压亮度, 动效令牌同步降 calm
        let tier = BatteryCare.tier(batteryPct(for: kc))
        return HeroCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    HStack(spacing: DS.Space.s) {
                        // 105 锁符号: 档案里选的 SF Symbol 同步到 Hero 卡
                        Image(systemName: LockArchive.symbolName(LockArchive.meta(kc.mac)))
                            .font(.system(size: DS.Icon.md, weight: .medium))
                            .foregroundStyle(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(LockArchive.displayName(kc))
                                .vkFont(.title3, weight: .semibold)
                                .foregroundStyle(DS.heroFg)
                                .lineLimit(1)
                                // 2026-10-27 截图核对修复：这个 HStack 右侧是 LinkPill（很宽的胶囊），
                                // 左侧名称只有 `.lineLimit(1)` 没有布局优先级 —— 于是被挤成「智能...」。
                                // 给名称更高的优先级，压缩时优先压右侧胶囊而不是锁名。
                                .layoutPriority(1)
                            // 774 场所副标题: 档案里填了场所就替代型号行
                            Text(LockArchive.subtitle(kc))
                                .vkFont(.footnote)
                                .foregroundStyle(DS.heroFg.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: DS.Space.xs) {
                        if isCurrent {
                            // 包2: 三态语义胶囊 (64) + 拟人文案 (68) + 冷热标识 (98) + 63 信号格 + 67 耗时
                            LinkPill(state: linkState(for: kc), connectMs: sense.connectMs, rssi: sense.lastRssi,
                                     source: sense.connectSource == "即连" ? "即连" : "已预热")
                            RSSIBars(level: LinkSense.rssiLevel(sense.lastRssi))
                                .opacity(isCurrent ? 1 : 0)
                                .accessibilityHidden(!isCurrent)
                                // 63 点一格弹出 dBm 原始数值: 三格表看不出"1 格强"与"2 格弱"的界
                                .onTapGesture { if isCurrent { showRssi.toggle() } }
                                .overlay(alignment: .top) {
                                    if isCurrent && showRssi {
                                        Text(sense.lastRssi.map { "\($0) dBm" } ?? "未读到信号")
                                            .vkFont(.caption2.monospacedDigit())
                                            .foregroundStyle(DS.heroFg)
                                            .padding(.horizontal, DS.Space.xs)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(.black.opacity(0.55)))
                                            .offset(y: -18)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .accessibilityLabel(isCurrent
                                    ? (sense.lastRssi.map { "信号 \($0) dBm, 轻点显示数值" } ?? "信号未读到")   // 63 信号
                                    : "信号")
                            // 268 状态变化历史: 长按胶囊弹出最近 5 次三态切换时间列表
                            .contextMenu {
                                Menu("最近状态变化") {   // 268 最近状态变化
                                    ForEach(Array(LinkSense.history().enumerated()), id: \.offset) { _, h in
                                        Text(h.at + " " + h.to)
                                    }
                                }
                                // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 16.5pt (< 44)。
                                // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                            }
                            // 91 回连静默小点
                            if reconnectDot {
                                Circle()
                                    .frame(width: 8, height: 8)
                                    .foregroundStyle(DS.Palette.ok)
                                    .overlay(Circle().strokeBorder(DS.heroFg.opacity(0.7), lineWidth: 1))
                                    .transition(.opacity)
                                    .accessibilityHidden(true)
                            }
                        } else {
                            HeroPill(text: "滑动到这页即连接", systemImage: "arrow.left.arrow.right",
                                     tint: DS.heroFg.opacity(0.75))
                        }
                    }
                }
                    // 电量是一级读数(它决定你还能不能开锁), 固件/锁钟是三级参考信息 —
                    // 三者同级会让人看不出重点
                    HStack(spacing: DS.Space.s) {
                    HeroStat(systemImage: battTier(for: kc).icon,
                             label: "电量",
                             value: batteryText(for: kc),
                             emphasized: true,
                             tint: battTint(for: kc))
                    // 909 指标位显隐: **电量不参与隐藏** —— 它决定"还能不能开锁"，
                    // 一个能把自己藏掉的读数就不是读数。固件/锁钟是参考信息，允许收起来腾位置。
                    if DS.HeroStats.shows("firmware") {
                        HeroStat(systemImage: "memorychip",
                                 label: "固件",
                                 value: firmwareText(for: kc),
                                 emphasized: false)
                    }
                    if DS.HeroStats.shows("lockclock") {
                        HeroStat(systemImage: "clock",
                                 label: "锁钟",
                                 value: lockClockText(for: kc),
                                 emphasized: false)
                    }
                    // 2026-10-29 补：APK `OpendevicePage` 有「钥匙有效期」横幅（`bleKeyValid`，`dState=1`
                    // 显示 createTime~expireTime，等于永久则显示"永久"）。iOS 没有云端下发的这两个字段 ——
                    // 本机 ekey 全部由 `buildEkeyOpen` 用 "2010-01-01 ~ 2118-01-01" 签发，所以如实写「永久」，
                    // 不编一个假日期；没有 ekey 时写「未生成」（与「链路验证」同一条"读不到就说读不到"的口径）。
                    HeroStat(systemImage: "key.horizontal",
                             label: "钥匙",
                             value: kc.ekey.isEmpty ? "未生成" : "永久",
                             emphasized: false)
}   // 2026-10-27 三轮：原 statsLayout 降级布局已删，恒横排
                // 790 最近活跃成员头像圈: 卡角叠放最近活跃 3 位, 点开列成员名, 选谁直接查谁的记录。
                if isCurrent {
                    HStack(spacing: DS.Space.s) {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .saturation(connected ? 1 : 0.55)
        .brightness(tier.severe ? -0.06 : 0)   // 120 低电视觉降级
        // 847 Hero 卡合并播报: 单元素合读 连接态+电量 (盲文简写 856)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder
    var attentionCard: some View {
        let notes: [(String, String, ToneColor)] = attentionItems
        if !notes.isEmpty {
            Card(tint: .warn) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Image(systemName: n.1)
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(n.2.color)
                                .accessibilityHidden(true)
                            Text(n.0)
                                .vkFont(.footnote)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
    var attentionItems: [(String, String, ToneColor)] {
        var out: [(String, String, ToneColor)] = []
        if (app.status?.sKeyStatus ?? app.snapshot?.sKeyStatus ?? 0) != 0 {
            out.append(("密钥尚未绑定，该门锁可能还没完成配网", "exclamationmark.triangle.fill", .warn))
        }
        if staleSync {
            out.append(("超过 30 天未校时，临时密码可能失效，请到快捷操作同步时间", "clock.badge.exclamationmark.fill", .warn))
        }
        // 287 低电阈值横幅 (阈值在 设置-维护提醒 可调, 默认 15%)
        if let kc = app.current {
            let p = batteryPct(for: kc)
            if p >= 0, p <= CareSchedule.battThreshold {
                out.append(("当前电量 \(p)%, 已低于提醒阈值 (\(CareSchedule.battThreshold)%) — 建议备好电池", "battery.25percent", .warn))
            }
        }
        // 2026-10-28 补入口：`CredentialOrg.dueSoonPwds` 实现了「到期前 2 小时且开了 h2 提醒」
        // 这一档（注释里明写"设备 Tab Hero 卡下插提醒行"），但全仓零调用 ——
        // 用户开了"2 小时前提醒"却永远收不到这一行。现在接上。
        // 只报条数、不点名（详情在凭证页），避免这张卡变成第二份凭证列表。
        if let kc = app.current {
            let due = CredentialOrg.dueSoonPwds(kc.mac)
            if !due.isEmpty {
                out.append(("有 \(due.count) 条凭证将在 2 小时内到期（最近一条 #\(due[0].alias)）—— 需要续期请到凭证页",
                            "clock.badge.exclamationmark.fill", .warn))
            }
        }
        // 1023 指纹头清洁: 连续 3 次指纹识别告警
        return out
    }

    // ---------- 包2 连接感知区: 69 蓝牙直通条 / 126 回连节律点阵 / 125 最后已知状态 / 535 同步回执 / 130 唤醒失败细分 ----------
    @ViewBuilder
    var linkSenseCard: some View {
        let state = sense.linkState
        let rows = senseRows(state)
        if !rows.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            Image(systemName: r.1)
                                .font(.system(size: DS.Icon.sm, weight: .semibold))
                                .foregroundStyle(rowTone(r.2))
                                .accessibilityHidden(true)
                            Text(r.0)
                                .vkFont(.footnote)
                                .foregroundStyle(r.3 ? DS.Palette.textSub : DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if r.3 {
                                Text("缓存")
                                    .vkFont(.caption2, weight: .medium)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .padding(.horizontal, 4).padding(.vertical, DS.Space.xxs)
                                    .variantPlate(DS.Palette.surfaceAlt, .capsule)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
    /// 69/126/125/535/130/270/272/273 连接感知行 —— 纯函数, 不进 ViewBuilder。
    /// 原先把 `var rows` + `if { rows.append(...) }` 直接写在 @ViewBuilder 里, 分支体是 `()` 不是 View,
    /// 编译器报 "type '()' cannot conform to 'View'"。行表是数据, 组装与渲染本就该分开。
    func senseRows(_ state: LinkState) -> [(String, String, String, Bool)] {
        var rows: [(String, String, String, Bool)] = []   // (text, icon, toneKey, cached)
        if !btReady {
            rows.append(("系统蓝牙已关闭 — 打开后会自动重连", "antenna.radiowaves.left.and.right.slash", "warn", false))   // 69 系统蓝牙已关闭
        }
        // 535 同步回执: 最近一次补发 N 项, 2 分钟内淡出
        if sense.lastReceipt > 0, Date().timeIntervalSince(sense.receiptShownAt) < 120 {
            rows.append(("已同步 \(sense.lastReceipt) 项变更", "checkmark.circle.fill", "ok", false))
        }
        // 131 会话重协商进行中: 假死巡检触发, 完成即消 (只读旗标, 无手动入口)
        if sense.revalidating {
            rows.append(("会话重协商中 — 假死巡检触发, 完成后自动消失", "arrow.triangle.2.circlepath", "accent", false))   // 131 会话重协商中
        }
        // 130 唤醒失败细分 (保守): 最近一次握手失败时给出三类归因 + 124 占用保守文案
        if state == .down, let last = lastWakeFail {
            rows.append(("唤醒失败 · \(last.name) — \(last.hint)", last.icon, "danger", false))
        }
        // 2026-10-27 四轮精简：弱信号提示已删（weakSignalHint 移除）。
        // 272 连接保持时长: 挂起过久提示重连
        if state == .ready, sense.holdMinutes >= 30 {
            rows.append(("连接已保持 \(sense.holdMinutes) 分钟 — 偏久, 可点刷新重连", "timer", "sub", false))   // 272 连接已保持
        }
        // 273 意图暂存: 断连且有排队变更时, 明示"已暂存, 回连续作"
        // 125 最后已知状态: 断连时展示最后一次读到的电量/固件并标注"缓存"
        if state == .down, let snap = DB.readStatus(app.currentMac) {
            let at = DB.statusTime(app.currentMac)
            let when = at > 0 ? " · 数据截至 " + Self.lastStamp.string(from: Date(timeIntervalSince1970: at / 1000)) : ""
            let batt = snap.powerLevel >= 0 ? String(snap.powerLevel) + "%" : "--"
            let fw = snap.firmware.isEmpty ? "未知" : snap.firmware
            rows.append(("最后已知: 电量 " + batt + " / 固件 " + fw + " (缓存" + when + ")",
                         "clock.arrow.circlepath", "sub", true))
        }
        return rows
    }
    var nextLadderText: String { "第 \(sense.reconnectAttempt) 轮 · 下一轮等 " + String(nextLadderWait) + " 秒" }
    var nextLadderWait: Int { Int(sense.nextLadderInterval()) }
    var lastWakeFail: LinkSense.FailKind? {
        // 130 细分: 取最近一条失败事件, 本地词表归三类; 124 占用细分协议未确证, 超时类走保守文案
        // 返回类型用已在用的 LinkSense.FailKind (name/hint 同形): `LinkSense.WakeReason` 早在删表那一轮就从
        // LinkSenseKit 移走了 (见 LinkSenseKit.swift:331 那句"已删"), 这三处引用是删类型时没扫调用点留下的。
        guard let ev = BleTelemetry.events.first(where: { !$0.ok }) else { return nil }
        // 124 死码改活: 旧判据 `ev.what.contains("超时")` 命中不了任何一条真实失败串 ——
        // 全仓 7 类 ok:false 事件是 预握手:未发现 / 预握手:信号弱跳过 / 预握手失败 X类 /
        // 握手失败 X类 / 回连失败第N轮 / 会话重协商失败 / 冷启动扫描失败, 一个"超时"都没有,
        // 那句占用文案从来不可达。占用归因改挂真实存在的"协议类/会话层失败"上。
        if ev.what.contains("蓝牙") {
            return LinkSense.FailKind(name: "蓝牙未开", hint: "打开系统蓝牙后会自动重连")
        }
        // 2026-10-27 审核修复：这个分支原先是空的，协议/会话失败会落进下面的兜底
        // 「不在广播范围」—— 用户看到"走到门锁旁 1 米内再试"，跑到门边也没用（锁的问题是协议层）。
        if ev.what.contains("协议类") || ev.what.contains("会话重协商失败") {
            return LinkSense.FailKind(
                name: "锁端未应答协议",
                hint: "门锁回了帧但内容对不上 — 先校准锁内时间；仍不行就重启门锁电池")
        }
        return LinkSense.FailKind(name: "不在广播范围", hint: "走到门锁旁 1 米内再试")
    }
    func rowTone(_ key: String) -> Color {
        switch key {
        case "ok": return DS.Palette.ok
        case "warn": return DS.Palette.warn
        case "danger": return DS.Palette.danger
        case "accent": return DS.Palette.accentText
        default: return DS.Palette.textSub
        }
    }
    @ViewBuilder
    var unlockDial: some View {
        // 868 切换控制扫描组: 圆盘为独立扫描组 (调用处 `unlockDial` 后面那两行
        // `.accessibilityElement(children: .contain)` + `accessibilityLabel("开锁圆盘组")`), 外接开关可以按组逐项聚焦。⚠ 2026-10-15 走查修正: 这里原先写着"停留时长按 869 自定滑杆" —— 那枚滑杆
        // (`kf_ax_dwell`) 全仓**没有行为消费者**，只被辅助页的滑杆自己与练习区演示文字读 (判据见
        // 聚焦节奏实际由系统 VoiceOver/切换控制决定。
        VStack(spacing: DS.Space.m) {
            UnlockDial(state: app.unlockState,
                       phase: app.phase,
                       connected: bleOn,
                       bleReady: btReady,
                       failStreak: app.failStreak,
                       retryText: retryText,
                       batteryText: app.current.map { batteryText(for: $0) } ?? "未知",
                       rssi: LinkSense.rssiFor(app.currentMac),
                       action: { dialAction() },
                       cancelAction: { app.cancelUnlock(notify: true) })
            // 包15 字幕式过程条 (881): 连接/开锁过程逐字文案条给听障用户 (设置-辅助可关)
            CaptionStepBar(phase: app.phase, unlockState: app.unlockState)
                .transition(.opacity)
            // 39 自动上锁倒计时 (协议 cmd24 档位的本地回放, 不虚构门磁): 开锁成功后提醒关手
            if let left = autoLockLeft {
                Label("约 \(left) 秒后自动上锁 · 请确认门已关好", systemImage: "timer")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityLabel("自动上锁倒计时 \(left) 秒, 请确认门已关好")
            }
            if !btReady {
                Text("打开系统蓝牙后即可开锁")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            } else if !bleOn {
                Text("未连接时点击会自动唤醒门锁蓝牙")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
            // 88 临时码备援: BLE 反复失败时, 已开通的临时码可在锁键盘直接输入 (纯提示, 不涉协议)
            if app.failStreak >= 2, DB.otpStatus(app.currentMac)?.on == true {
                Label("蓝牙连不稳? 已开通的临时码可直接在门锁键盘输入开门", systemImage: "keyboard")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            // 1003 安慰式报错: 一次失败轻声安慰, 三次后给可勾排查清单 (87)
            if app.failStreak > 0 {
                VStack(spacing: DS.Space.xs) {
                    Text(app.failStreak < 3 ? "再试一次, 别着急" : "连着几次没成, 逐项自查一遍:")
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.failStreak >= 3 {
                        checklist
                    }
                }
                .transition(.opacity)
            }
            // 83: 自动重试 (2s/5s) 用尽进入终态失败 → 圆盘下方主按钮手动再试
            // (超时失败不涨 failStreak, 所以钩在 .failed 上, 不能挂进上面 failStreak 块)
            if case .failed = app.unlockState {
                Button("再试一次") { dialAction() }
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.accentText)
                    .padding(.horizontal, DS.Space.xl)
                    .frame(minHeight: DS.Hit.min)
                    .variantPlate(DS.Palette.accentText.opacity(0.12), .capsule)
                    .buttonStyle(PressableButtonStyle())
            }
        }
        .axOnehand()   // 873/60 单手下沉: 圆盘区整体下移入拇指区
                       // (挂在整个圆盘区 VStack 上 —— 原先误挂在一个条件分支后（if AXPrefs.captions，该开关已于 2026-10-26 删除）,
                       //  那是把修饰符接在 if 语句上, 编译器按隐式成员解析报 "cannot be used on type 'View'")
        .padding(.vertical, DS.Space.l)
        .animation(DS.Motion.soft, value: app.failStreak)
        .animation(DS.Motion.soft, value: autoLockLeft)
        // 267 换锁二次确认: 横滑换锁后第一次点圆盘 → 放大的锁名胶囊提示, 再点才执行
        .overlay {
            if confirmPulse {
                VStack(spacing: DS.Space.xs) {
                    Text("即将开锁")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(app.displayName)
                        .vkFont(.headline)
                        .foregroundStyle(DS.Palette.accentText)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s)
                        // 2026-10-18 表面预算: **玻璃不叠玻璃** (MASTER.md §3.1 的 0 预算)。
                        // 外层卡片已经是 axGlass, 内层胶囊再上玻璃就是两层材质叠一起 ——
                        // 观感上只是更糊, 信息上什么也没增加。改成实底 + accent 描边:
                        // 那圈 1.5pt 是"还没执行, 再点才开锁"的告警边, 属于信息不是装饰, 保留。
                        .variantPlate(DS.Palette.surfaceAlt, .capsule)
                        .overlay(Capsule().strokeBorder(DS.Palette.accent, lineWidth: 1.5))
                        .scaleEffect(confirmPulse ? 1.06 : 1)
                    Text("再点一次圆盘开始开锁")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                }
                .padding(DS.Space.l)
                .axGlass(DS.Radius.card)
                .transition(.scale(scale: 1.12).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("换锁确认: 即将对 \(app.displayName) 开锁, 再点一次圆盘确认")
            }
        }
    }
    func dialAction() {
        if confirmMac != nil {
            // 首点: 只亮胶囊, 不发指令 (244 去重窗口之外的软闸)
            DS.Haptics.tick.impactOccurred()
            confirmMac = nil
            withAnimation(DS.Motion.standard) { confirmPulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.4))
                withAnimation(DS.Motion.exit) { confirmPulse = false }
            }
            return
        }
        app.requestUnlock()
    }
    // 39 倒计时: 秒数来自本地布防记忆 (kf_tailgate_, 档位+1=秒), 没设过按厂商默认 6 秒
    func startAutoLockCountdown() {
        let interval = DB.tailgate(app.currentMac)?.interval ?? 5
        let total = max(2, interval + 1)
        autoLockLeft = total
        Task { @MainActor in
            for left in stride(from: total, through: 1, by: -1) {
                autoLockLeft = left
                try? await Task.sleep(for: .seconds(1))
                if autoLockLeft != left { return }   // 期间重新开锁/切锁 → 让位新的倒计时
            }
            withAnimation(DS.Motion.exit) { autoLockLeft = nil }
        }
    }

    // 87 排查清单: 查蓝牙 / 走近 / 查电量, 逐项可勾
    @ViewBuilder
    var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checkTexts.enumerated()), id: \.offset) { i, txt in
                Button { checks[i].toggle() } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: checks[i] ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(checks[i] ? DS.Palette.ok : DS.Palette.textSub)
                        Text(txt)
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(txt)
                .accessibilityAddTraits(checks[i] ? [.isSelected] : [])
            }
        }
    }
    @ViewBuilder
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
    @State var showModuleOrder = false
    @State var orderTick = 0
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
