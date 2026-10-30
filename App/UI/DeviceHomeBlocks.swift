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
            .accessibilityLabel("按组切换门锁， 当前\(groupFilter.isEmpty ? "全部" : groupFilter)")
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
                heroIdentityRow(kc, isCurrent: isCurrent)
                heroStatsRow(kc)
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

    /// Hero 卡身份行：锁符号 + 名称/场所 + 三态胶囊 / 信号格 / 回连小点。
    @ViewBuilder
    private func heroIdentityRow(_ kc: Keychain, isCurrent: Bool) -> some View {
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
                        // 2026-10-30 补（第 107 轮，**无障碍**）：同上 —— 点信号格弹 dBm，
                        // 而 `.onTapGesture` 读屏激活不了。补默认动作 + 按钮特征。
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { if isCurrent { showRssi.toggle() } }
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
    }

    /// Hero 卡指标行：电量（恒显）+ 固件 / 锁钟（可按 909 隐藏）+ 钥匙有效期。
    @ViewBuilder
    private func heroStatsRow(_ kc: Keychain) -> some View {
        // 2026-10-30 修复（第 163 轮，**4 格挤到看不见字**）：原来是 `HStack` 把 4 个 HeroStat 硬排一行 ——
        // 每格还要吃 `padding(.horizontal, Space.m)`，窄屏上值的可用宽度只剩几十点，
        // `lineLimit(1)` + `minimumScaleFactor(0.7)` 把「锁钟」「固件」这类长值压到几乎看不见。
        // 改成 2 列网格（与 `quickActions` 的注释「4 格一屏」口径一致：2×2）。
        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s), GridItem(.flexible(), spacing: DS.Space.s)],
                  spacing: DS.Space.s) {
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
            rows.append(("会话重协商中 — 假死巡检触发， 完成后自动消失", "arrow.triangle.2.circlepath", "accent", false))   // 131 会话重协商中
        }
        // 130 唤醒失败细分 (保守): 最近一次握手失败时给出三类归因 + 124 占用保守文案
        if state == .down, let last = lastWakeFail {
            rows.append(("唤醒失败 · \(last.name) — \(last.hint)", last.icon, "danger", false))
        }
        // 2026-10-27 四轮精简：弱信号提示已删（weakSignalHint 移除）。
        // 272 连接保持时长: 挂起过久提示重连
        if state == .ready, sense.holdMinutes >= 30 {
            rows.append(("连接已保持 \(sense.holdMinutes) 分钟 — 偏久， 可点刷新重连", "timer", "sub", false))   // 272 连接已保持
        }
        // 273 意图暂存: 断连且有排队变更时, 明示"已暂存, 回连续作"
        // 125 最后已知状态: 断连时展示最后一次读到的电量/固件并标注"缓存"
        if state == .down, let snap = DB.readStatus(app.currentMac) {
            let at = DB.statusTime(app.currentMac)
            let when = at > 0 ? " · 数据截至 " + Self.lastStamp.string(from: Date(timeIntervalSince1970: at / 1000)) : ""
            let batt = snap.powerLevel >= 0 ? String(snap.powerLevel) + "%" : "--"
            let fw = snap.firmware.isEmpty ? "未知" : snap.firmware
            rows.append(("最后已知： 电量 " + batt + " / 固件 " + fw + " (缓存" + when + ")",
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
                    .accessibilityLabel("自动上锁倒计时 \(left) 秒， 请确认门已关好")
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
                    Text(app.failStreak < 3 ? "再试一次， 别着急" : "连着几次没成， 逐项自查一遍：")
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
                .accessibilityLabel("换锁确认： 即将对 \(app.displayName) 开锁， 再点一次圆盘确认")
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
        let interval = DB.tailgate(app.currentMac)?.interval ?? 6   // 2026-10-30：注释写「厂商默认 6 秒」、TailgateView 初值也是 6，这里却兜 5 —— 同一默认值两处不同
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
}
