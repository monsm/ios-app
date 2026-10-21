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
        ScrollView {
            VStack(spacing: XSpace.l) {
                heroCard
                if !on || editing { formCard } else { manageCard }
                explainCard
            }
            .padding(.horizontal, XSpace.gutter)
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas)
        .navigationTitle("应用锁")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("关闭应用锁？", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("关闭", role: .destructive) { turnOff() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("关闭后，本机凭证明文不再需要验证即可查看，毁灭类操作也无法再复核口令。")
        }
    }

    // ── ① 状态 ─────────────────────────────────────────────
    private var heroCard: some View {
        XPanel(kind: .hero) {
            HStack(spacing: XSpace.m) {
                Image(systemName: on ? "lock.shield.fill" : "lock.open")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(on ? XPalette.ok : XPalette.warn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(on ? "应用锁已开启" : "应用锁未开启")
                        .xFont(.system(.headline, weight: .semibold))
                        .foregroundStyle(XPalette.text)
                    Text(on ? "打开本 App 需要口令；凭证明文默认收起"
                             : "现在任何人都能直接打开本 App 查看凭证明文")
                        .xFont(.system(.footnote))
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(on ? "应用锁已开启" : "应用锁未开启，任何人可直接查看凭证明文")
    }

    // ── ② 设置表单 ─────────────────────────────────────────
    private var formCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel(on ? "修改口令" : "设置口令")
                SecureField("口令（至少 \(minLen) 位）", text: $pw)
                    .textContentType(.newPassword)
                    .xFont(.system(.body))
                    .padding(XSpace.m)
                    .xPlate(XPalette.surfaceSunken, XRadius.control)
                SecureField("再输一遍", text: $pw2)
                    .textContentType(.newPassword)
                    .xFont(.system(.body))
                    .padding(XSpace.m)
                    .xPlate(XPalette.surfaceSunken, XRadius.control)

                if let e = errorText {
                    Label(e, systemImage: "exclamationmark.circle.fill")
                        .xFont(.system(.footnote))
                        .foregroundStyle(XPalette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !pw2.isEmpty && pw != pw2 {
                    Label("两遍输入不一致", systemImage: "exclamationmark.circle.fill")
                        .xFont(.system(.footnote))
                        .foregroundStyle(XPalette.warn)
                }

                HStack(spacing: XSpace.s) {
                    Button(action: save) {
                        Text(on ? "保存新口令" : "启用应用锁")
                            .xFont(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(XPalette.onAccent)
                            .frame(maxWidth: .infinity, minHeight: XHit.min)
                            .xPlate(canSave ? XPalette.accent : XPalette.surfaceAlt, .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityHint(canSave ? "" : "需要至少 \(minLen) 位且两遍一致")

                    if editing {
                        Button("取消") { editing = false; pw = ""; pw2 = ""; errorText = nil }
                            .xFont(.system(.subheadline))
                            .foregroundStyle(XPalette.textSub)
                    }
                }
                Text("口令只保存摘要，不存明文。忘记后只能重装或从备份恢复。")
                    .xFont(.system(.caption2))
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
                    row(icon: "lock.open", title: "关闭应用锁", detail: "关闭后本机凭证不再受保护", tone: XPalette.danger)
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
                Text(title).xFont(.system(.body)).foregroundStyle(XPalette.text)
                Text(detail).xFont(.system(.caption)).foregroundStyle(XPalette.textSub)
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
                bullet("打开 App 需要口令；离机时别人拿不到凭证明文")
                bullet("毁灭类操作（彻底销毁、离职清除）要用它复核一次")
                bullet("口令摘要进备份；换机恢复后仍然认同一个口令")
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
                .xFont(.system(.footnote))
                .foregroundStyle(XPalette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func secLabel(_ s: String) -> some View {
        Text(s)
            .xFont(.system(.caption, weight: .semibold))
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
