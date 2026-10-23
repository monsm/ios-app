import SwiftUI

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 应用锁
// ═══════════════════════════════════════════════════════════════════════
//
// 这个页面补的是一个**整块不可达的安全功能**：
//
//   · \`DB.hasPasscode()\` / \`verifyPasscode()\` 被大量代码依赖
//     （LockGuard 的 sudo 复核、销毁前的口令确认、安全页的总体评分）
//   · 但设置口令的 \`DB.setPasscode()\` **全仓零调用**
//   · \`kf_applock\` 这个开关被 5 处读取，**从未被写过**
//
// 结果：应用锁永远「未开启」——
//   安全页恒报「应用锁未开启」、毁灭动作因复核不了口令而永久停在门口、
//   凭证明文没有本机保护。除非从备份里恢复出一份带口令的包，否则开不了。
//
// 这不是"功能简陋"，是**开关本身不存在**。
//
// ═══ 设计 ═══
// 用途：operate。进来只有两件事——开，或关。
//   · 没开：说清楚它保护什么，给一个动作
//   · 已开：给"改口令"和"关闭"两条，关闭必须二次确认
//   · 口令最少 6 位；两遍输入不一致当场提示，不等到保存
struct AppLockSetupView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var on = DB.hasPasscode()
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var editing = false
    @State private var confirmOff = false
    @State private var errorText: String?

    private let minLen = 6

    /// 保存按钮可用性 —— 两遍一致、长度够
    private var canSave: Bool {
        pw.count >= minLen && pw == pw2
    }

    var body: some View {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("应用锁", style: .inline) {
            heroCard
            if !on || editing { formCard } else { manageCard }
            explainCard
        }
        .confirmationDialog("关闭应用锁？", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("关闭", role: .destructive) { turnOff() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("关闭后，谁拿起这台手机都能直接看到你保存的密码。彻底销毁这类操作也不会再要求你输一次口令。")
        }
    }

    // ── ① 状态 ─────────────────────────────────────────────
    /// 六图改造 (2026-10-23): HERO 改**图 5 的「44px 数字 + 环」**。
    ///
    /// 应用锁只有开/关两个状态，但"开没开"这件事值得做成一个**读数**而不是一行字：
    /// 图 5 的第一张卡永远是「一个量 + 一枚环」。这里量是「1/1 或 0/1 已启用」，
    /// 环在开启时满格转绿 —— 与安全页、防窥页保持同一套语言。
        /// HTML 对齐 (2026-10-24): 补「保护项」卡 —— HTML 41-applock 有，App 缺。
    private var protectionItemsCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("保护项")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                XDataRow(label: "打开 App 要口令", value: on ? "已开" : "未开", unit: "",
                         color: on ? XPalette.ok : XPalette.warn)
                XDataRow(label: "保存的密码默认不显示", value: on ? "已开" : "未开", unit: "",
                         color: on ? XPalette.ok : XPalette.warn)
                XDataRow(label: "切到后台立即变糊", value: on ? "已开" : "未开", unit: "",
                         color: on ? XPalette.ok : XPalette.warn)
            }
        }
    }

private var heroCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("应用锁")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: on ? "1" : "0",
                            color: on ? XPalette.ok : XPalette.warn,
                            unit: "已启用")
                        Text(on ? "每次打开 App 都要输口令；保存的密码默认不显示"
                                 : "现在谁拿起这台手机，都能直接看到你保存的密码")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 76,
                        progress: on ? 1 : 0.02,
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false,
                        gradient: on ? XGradient.dialOK : XGradient.dial
                    ) {
                        Image(systemName: on ? "lock.shield.fill" : "lock.open")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(on ? XPalette.ok : XPalette.warn)
                    }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(on ? "应用锁已开启" : "应用锁未开启，谁都能直接看到保存的密码")
    }

    // ── ② 设置表单 ─────────────────────────────────────────
    private var formCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel(on ? "修改口令" : "设置口令")
                SecureField("口令（至少 \(minLen) 位）", text: $pw)
                    .textContentType(.newPassword)
                    .xFont(.body)
                    .padding(XSpace.m)
                    .xPlate(XPalette.surfaceSunken, XRadius.control)
                SecureField("再输一遍", text: $pw2)
                    .textContentType(.newPassword)
                    .xFont(.body)
                    .padding(XSpace.m)
                    .xPlate(XPalette.surfaceSunken, XRadius.control)

                if let e = errorText {
                    Label(e, systemImage: "exclamationmark.circle.fill")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !pw2.isEmpty && pw != pw2 {
                    Label("两遍输入不一致", systemImage: "exclamationmark.circle.fill")
                        .xFont(.footnote)
                        .foregroundStyle(XPalette.warn)
                }

                HStack(spacing: XSpace.s) {
                    Button(action: save) {
                        Text(on ? "保存新口令" : "启用应用锁")
                            .xFont(.subheadline, weight: .semibold)
                            .foregroundStyle(XPalette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: XHit.min)
                            .xPlate(canSave ? XPalette.accent : XPalette.surfaceAlt, .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityHint(canSave ? "" : "需要至少 \(minLen) 位且两遍一致")

                    if editing {
                        Button("取消") { editing = false; pw = ""; pw2 = ""; errorText = nil }
                            .xFont(.subheadline)
                            .foregroundStyle(XPalette.textSub)
                    }
                }
                Text("我们只保存口令的一串校验值，不保存口令本身 —— 所以忘记后谁也找不回来，只能重装或从备份恢复。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── ③ 已开启时的管理 ───────────────────────────────────
    private var manageCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("管理")
                Button {
                    pw = ""; pw2 = ""; errorText = nil; editing = true
                } label: {
                    row(icon: "key.fill", title: "修改口令", detail: "换一个新的访问口令", tone: XPalette.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改应用锁口令")

                XHairline(inset: 0)

                Button { confirmOff = true } label: {
                    row(icon: "lock.open", title: "关闭应用锁", detail: "关闭后，这台手机里的密码不再受保护", tone: XPalette.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭应用锁")
            }
        }
    }

    private func row(icon: String, title: String, detail: String, tone: Color) -> some View {
        HStack(spacing: XSpace.m) {
            Image(systemName: icon)
                .font(.system(size: XIcon.sm, weight: .medium))
                .foregroundStyle(tone)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).xFont(.body).foregroundStyle(XPalette.text)
                Text(detail).xFont(.caption).foregroundStyle(XPalette.textSub)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: XHit.min)
        .contentShape(Rectangle())
    }

    // ── ④ 说明 ─────────────────────────────────────────────
    private var explainCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.s) {
                secLabel("它保护什么")
                bullet("要输口令才能打开 App；手机离手时别人看不到你的密码")
                bullet("彻底销毁、离职清除这类动作，会要求你再输一次它")
                bullet("口令的校验值会一起备份；换机恢复后仍然是同一个口令")
            }
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: XIcon.xs, weight: .semibold))
                .foregroundStyle(XPalette.ok)
                .accessibilityHidden(true)
            Text(s)
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func secLabel(_ s: String) -> some View {
        Text(s)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── 动作 ───────────────────────────────────────────────
    private func save() {
        guard canSave else { return }
        DB.setPasscode(pw)
        // 开关与口令必须同时成立：只写口令不写开关，
        // 安全页仍会报「未开启」；只写开关不写口令，verifyPasscode 永远失败。
        DB.store.set("kf_applock", true)
        on = true
        editing = false
        pw = ""; pw2 = ""; errorText = nil
        XHaptics.success()
        app.showToast("应用锁已开启")
    }

    private func turnOff() {
        DB.setPasscode(nil)
        DB.store.set("kf_applock", false)
        on = false
        pw = ""; pw2 = ""; editing = false
        XHaptics.trigger.impactOccurred()
        app.showToast("应用锁已关闭")
    }
}
