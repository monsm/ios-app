//
//  AddKeyPage.swift
//  添加凭证 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力的来源: 把"密码"本身变成主角
//  ═══════════════════════════════════════════════════════════
//
//  旧版: Form + SecureField + 三个 Section, 密码藏在圆点里,
//        用户看不见自己刚设的码, 也无法核对。
//
//  新版: 数字大字盘
//    · 6~8 位密码以 48pt 等宽大字逐个浮现, 未填位是空心方框
//    · 每个数字落下时有 scale + 透明度动画
//    · 下方是系统数字键盘 (自动聚焦)
//    · 密码合法时, 整块区域从灰变铜色, 边框发光
//
//  这是"精致细腻"的关键: 让一个输入框拥有仪式感。
//

import SwiftUI
import UIKit

/// 添加凭证页
struct AddKeyPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pwd = ""
    @State private var permanent = true
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var owner: String? = nil
    @State private var useTemplate = true
    @State private var busy = false
    @State private var showTempConfirm = false

    @FocusState private var focused: Bool

    /// 6~8 位纯数字
    private var pwdOK: Bool {
        pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber }
    }

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("添加密码", style: .inline) {
                capacityCard
                passwordStage.xScrollLift()
                validitySection.xScrollLift()
                ownerSection.xScrollLift()
                actionSection.xScrollLift()
        }
        }
        // 写入进行中不允许下滑关闭：操作可能已经发到设备，
        // 关掉会让用户拿不到结果，也看不到失败原因。
        .interactiveDismissDisabled(busy)
        .onAppear { focused = true }
        .confirmationDialog("下发 10 分钟临时密码?", isPresented: $showTempConfirm) {
            Button("下发", role: .destructive) {
                Task { await submit(permanent: false, temp: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("临时密码 10 分钟后自动失效, 只能使用一次。")
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 密码舞台 (视觉主角)
    // ═══════════════════════════════════════════════════════

    /// 密码容量卡 —— 协议真实返回 pwdStock / pwdCap，
    /// 但这一页从没显示过"还剩几个坑位"，用户会录到一半才被拒。
    @ViewBuilder
    private var capacityCard: some View {
        let snap = DB.readStatus(app.currentMac)
        let cap = snap?.pwdCap ?? 0
        let left = snap?.pwdStock ?? -1
        if cap > 0, left >= 0 {
            let used = max(0, cap - left)
            let full = left == 0
            XPanel(kind: .group, tone: full ? .warn : .neutral) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "number.square")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(full ? XPalette.warn : XPalette.textSub)
                    Text(full ? "密码库存已满" : "还可录 " + String(left) + " 条")
                        .xFont(.footnote, weight: .medium)
                        .foregroundStyle(full ? XPalette.warn : XPalette.textSub)
                    Spacer(minLength: 0)
                    Text(String(used) + " / " + String(cap))
                        .xFontExact(.caption2.monospacedDigit())
                        .foregroundStyle(XPalette.textSub)
                }
            }
            .xScrollLift()
        }
    }

    private var passwordStage: some View {
        VStack(spacing: XSpace.l) {
            // 8 个数字位
            HStack(spacing: XSpace.s) {
                ForEach(0..<8, id: \.self) { i in
                    digitSlot(at: i)
                }
            }
            .padding(.vertical, XSpace.xl)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                    .fill(XPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: XRadius.card, style: .continuous)
                            .strokeBorder(
                                pwdOK ? XPalette.accent : XPalette.hairline,
                                lineWidth: pwdOK ? 2 : 1)
                    )
            )
            // 规范 6.3: 应用体卡片**零投影**。原来这层 20pt 的铜色柔光是想让
            // "密码够长"这个状态更醒目 —— 但那用不着一层投在卡片**外面**的光晕:
            // 状态已经由 2pt 描边 + 颜色双通道表达了。
            // 需要光的地方是环/仪表, 用 XGradient.glow; 卡片只许描边。
            .animation(XMotion.standard, value: pwdOK)

            // 隐藏的真输入框 (贴在屏外用系统键盘)
            TextField("", text: $pwd)
                .keyboardType(.numberPad)
                .focused($focused)
                .opacity(0.001)
                .frame(height: 1)
                .onChange(of: pwd) { _, v in
                    // 只留数字, 最多 8 位
                    let filtered = String(v.filter { $0.isNumber }.prefix(8))
                    if filtered != v { pwd = filtered; return }
                    if filtered.count == 8 { focused = false }
                    // 每一位落下的触感
                    if filtered.count > 0 { XHaptics.tick.impactOccurred() }
                }

            // 提示行（最多两行：强度 / 前缀冲突）
            VStack(alignment: .leading, spacing: XSpace.xs) {
                HStack(spacing: XSpace.xs) {
                    Image(systemName: pwdWeak ? "exclamationmark.triangle.fill"
                                            : (pwdOK ? "checkmark.circle.fill" : "info.circle"))
                        .font(.system(size: XIcon.xs, weight: .semibold))
                    Text(pwdHint)
                        .xFont(.footnote)
                }
                .foregroundStyle(pwdWeak ? XPalette.warn
                                         : (pwdOK ? XPalette.accentText : XPalette.textSub))
                if let clash = prefixClash {
                    HStack(spacing: XSpace.xs) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: XIcon.xs, weight: .semibold))
                        Text(clash)
                            .xFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(XPalette.warn)
                }
            }
            .animation(XMotion.quick, value: pwdOK)
        }
    }

    private func digitSlot(at index: Int) -> some View {
        let chars = Array(pwd)
        let filled = index < chars.count
        let ch = filled ? String(chars[index]) : ""
        // 第 6 位之后可选 (6~8 位都合法)
        let optional = index >= 6

        return ZStack {
            RoundedRectangle(cornerRadius: XRadius.min, style: .continuous)
                .fill(filled ? XPalette.accent.opacity(XOpacity.badge) : XPalette.surfaceSunken)
                .frame(width: 36, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: XRadius.min, style: .continuous)
                        .strokeBorder(
                            filled ? XPalette.accent.opacity(0.5)
                                   : (optional ? XPalette.hairline.opacity(0.5) : XPalette.hairline),
                            lineWidth: 1)
                )

            if filled {
                Text(ch)
                    .xFont(.display, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(XPalette.accentText)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.4).combined(with: .opacity),
                        removal: .opacity))
            } else if !optional {
                // 必填位: 一个小点占位
                Circle()
                    // @contrast-allow 4pt 占位小点，纯装饰；有数字时会被替换掉。
                    .fill(XPalette.textTertiary.opacity(0.4))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(minWidth: XHit.min, minHeight: XHit.min)
        .contentShape(Rectangle())
        .animation(XMotion.quick, value: filled)
        .accessibilityHidden(true)
    }

    private var pwdHint: String {
        if pwd.isEmpty { return "6~8 位数字, 在门锁键盘上输入" }
        if !pwdOK { return "还需 \(6 - pwd.count) 位" }
        // 密码已经能用了 —— 这时最该说的不是"还能再输两位"，而是"它够不够难猜"。
        // StudioTools.pwdStrength 实现完整却零调用：全同数字(111111)与顺子(123456)
        // 正是家里设门锁密码最常见的两种错误，也是试错者最先试的两种。
        let st = StudioTools.pwdStrength(pwd)
        if !st.hint.isEmpty { return st.hint }
        if pwd.count < 8 { return "已可添加, 也可以继续输入到 8 位" }
        return "已满 8 位"
    }

    /// 314 前缀混淆：同锁内其它密码前 4 位相同。
    ///
    /// 这不是安全检查，是**口头说清楚的检查** —— 家里说"1234 开头那个"，
    /// 如果有两条都是 1234 开头，谁都会拿错。
    private var prefixClash: String? {
        guard pwd.count >= 4, let kc = app.current else { return nil }
        let hits = CredentialOrg.prefixConflict(kc.mac, pwd, excluding: -1)
        guard let first = hits.first else { return nil }
        let who = first.note.isEmpty ? "密码 #\(first.alias)" : first.note
        // 不回显口令前缀：用户刚敲完，告诉他「前 4 位是 1234」没有任何新信息，
        // 却把秘密的 4 位明文留在屏幕上（肩窥即可见）。说清「与谁撞了」就够了。
        return "前 4 位与「\(who)」相同 — 口头区分时容易拿错，建议改一位"
    }

    /// 密码可用但不够难猜 —— 提示行改用警示色，否则"全部同数字"会显示成通过色。
    private var pwdWeak: Bool {
        pwdOK && !StudioTools.pwdStrength(pwd).hint.isEmpty
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 有效期
    // ═══════════════════════════════════════════════════════

    private var validitySection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "calendar")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                        .accessibilityHidden(true)
                    Text("有效期")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Spacer()
                }

            // 规范 §7.3：同一产品内只用一种分段形态。
            XSegmented(items: [true, false], title: { $0 ? "永久" : "自定义" },
                       selection: $permanent)

                if !permanent {
                    VStack(spacing: XSpace.s) {
                        DatePicker("生效", selection: $fromDate, displayedComponents: .date)
                            .xFont(.subheadline)
                        DatePicker("到期", selection: $toDate, displayedComponents: .date)
                            .xFont(.subheadline)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(XMotion.soft, value: permanent)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 归属
    // ═══════════════════════════════════════════════════════

    private var ownerSection: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "person")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                        .accessibilityHidden(true)
                    Text("归属")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Spacer()
                }

                // 成员横向胶囊
                ScrollView(.horizontal) {
                    HStack(spacing: XSpace.s) {
                        ownerChip(nil, "未归属")
                        ForEach(DB.members()) { m in
                            ownerChip(m.id, MemberHub.display(m))
                        }
                    }
                }
                .scrollIndicators(.hidden)

                XToggle("备注自动填命名模板", isOn: $useTemplate)
                    .xFont(.footnote)
            }
        }
    }

    private func ownerChip(_ id: String?, _ label: String) -> some View {
        let selected = owner == id
        // 该成员名下已有几条密码 —— 录入前该知道，避免给同一个人重复建一条
        let existing: Int = {
            guard let id else { return 0 }
            let mac = app.currentMac
            guard !mac.isEmpty else { return 0 }
            return DB.listPwds(mac).filter { $0.owner == id && !$0.temp }.count
        }()
        return Button {
            owner = id
            XHaptics.tick.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .xFont(.footnote, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? XPalette.onAccent : XPalette.text)
                if existing > 0 {
                    Text(String(existing))
                        .xFontExact(.caption2.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(selected
                                         ? XPalette.onAccent.opacity(0.8)
                                         : XPalette.textTertiary)
                }
            }
            .padding(.horizontal, XSpace.m)
            .padding(.vertical, XSpace.s)
            .background(
                Capsule().fill(selected ? XPalette.accent : XPalette.surfaceAlt)
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? .clear : XPalette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(XMotion.quick, value: selected)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(label + (existing > 0 ? "，已有 " + String(existing) + " 条密码" : ""))
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private var actionSection: some View {
        VStack(spacing: XSpace.m) {
            XBusyButton(
                title: "添加密码",
                systemImage: "key.fill",
                busy: busy,
                style: .primary
            ) {
                Task { await submit(permanent: permanent) }
            }
            .disabled(!pwdOK || busy)
            .opacity(pwdOK ? 1 : 0.5)

            Button {
                showTempConfirm = true
            } label: {
                Label("下发 10 分钟临时密码", systemImage: "timer")
            }
            .buttonStyle(XSecondaryButtonStyle())
            .disabled(!pwdOK || busy)

            Text("请将手机靠近门锁 · 添加成功后密码会登记到本机台账")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 提交
    // ═══════════════════════════════════════════════════════

    private func submit(permanent: Bool, temp: Bool = false) async {
        // 没有选中锁时明确说话 (旧版静默 return = "点了没反应")
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard !busy else { return }
        guard pwdOK else { app.showToast("请输入 6~8 位数字密码"); return }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = WeekCal.gregorian
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var from = permanent ? "2010-01-01 00:00:00" : fmt.string(from: fromDate)
        var to = permanent ? "2118-01-01 00:00:00" : fmt.string(from: toDate)

        if temp {
            // 10 分钟临时密码
            let now = Date()
            from = fmt.string(from: now)
            to = fmt.string(from: now.addingTimeInterval(600))
        }

        // 自定义区间必须 to 晚于 from
        if !permanent && !temp && toDate <= fromDate {
            app.showToast("失效时间需晚于生效时间")
            return
        }

        busy = true
        defer { busy = false }

        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: from, validTo: to)

            var note = ""
            if useTemplate {
                let who = owner.map { CredentialOrg.ownerName($0) } ?? "未归属"
                let when = permanent ? "长期"
                    : (fromDate.formatted(.dateTime.month().day()) + "-" + toDate.formatted(.dateTime.month().day()))
                let place = LockArchive.meta(kc.mac).place.trimmingCharacters(in: .whitespaces)
                note = who + (place.isEmpty ? "-" : "-" + place + "-") + when
            }

            let rec = LedgerPwd(alias: alias, from: from, to: to, temp: temp,
                                at: Date().timeIntervalSince1970 * 1000,
                                pwd: pwd, owner: owner, note: note)
            DB.addPwd(kc.mac, rec)
            CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: rec, fp: nil, note: "新增")

            XHaptics.success()
            // 录指纹那条流程会说「请用新指纹开一次锁, 确认可用」——
            // 加密码是**更常做**的动作，却只报一句"添加成功"就关掉了。
            // 没试过的密码等于不存在的密码：用户以为加好了，真到门口才发现不行。
            // 这里把同一句提醒补上，和指纹流程对齐。
            app.showToast(temp
                ? "临时密码已下发 (别名 #\(alias)) — 请用它在门锁上开一次，确认可用"
                : "添加成功 (别名 #\(alias)) — 请用这串密码开一次锁，确认可用")
            dismiss()
        } catch {
            XHaptics.failure()
            app.showToast("添加失败: " + ErrorText.human(error))
        }
    }
}
