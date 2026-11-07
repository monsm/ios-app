// RecoveryScreen.swift —— 「我锁在门外了」（F23）。
//
// 用户被关在门外时，最需要的不是「设置」里的一堆按钮，而是**一条有顺序、
// 每一步都写清风险、可以随时停下来的路**。
//
// 这一页把 `LockoutRecovery` 的步骤表变成界面：
//   · 有风险的那一步（键盘复位）明确标出「会清空门锁里的全部凭证」；
//   · 要用户亲自去锁上做的步骤，页面会**停下来等**；
//   · 每做完一步就地显示结果，不跳页。
import SwiftUI

@MainActor
struct RecoveryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// 用户描述的症状。决定先走哪几步。
    @State private var symptom: String = "钥匙打不开"
    @State private var steps: [LockoutRecovery.Step] = []
    @State private var done: Set<String> = []
    @State private var failures: [String: ScreenFailure] = [:]
    @State private var busy = false
    /// 要用户亲自去锁上做的那一步（页面停下来等）。
    @State private var waiting: LockoutRecovery.Step?

    private let symptoms = ["钥匙打不开", "连不上锁", "指纹/密码用不了"]

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置 / 我锁在门外了", back: { dismiss() })

            DisplayLine(text: "先别慌。", size: 36)
                .padding(.top, 16)
            Text(L("recovery.intro"))
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SectionHead(index: "01", title: "哪种情况")
            HStack(spacing: 8) {
                ForEach(symptoms, id: \.self) { s in
                    ChoiceChip(title: s, on: symptom == s, height: 36) {
                        symptom = s
                        steps = LockoutRecovery.plan(mac: app.currentMac, symptom: s)
                        done = []
                        failures = [:]
                        waiting = nil
                    }
                }
            }
            .padding(.top, 4)

            SectionHead(index: "02", title: "按这个顺序来")
            ForEach(steps) { step in
                stepCard(step)
            }

            if let waiting {
                GlassSurface() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("这一步要你到门锁上做")
                            .type(T.F.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(T.C.ink)
                        Text(waiting.detail)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("做完回来点「我做好了」，这一步就算完成。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink3)
                        PrimaryButton(title: L("recovery.done")) {
                            done.insert(waiting.rawValue)
                            self.waiting = nil
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, T.S.s)
            }

            Text("这些操作全部在本机完成，门锁那边不需要联网。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .padding(.top, T.S.m)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if steps.isEmpty {
                steps = LockoutRecovery.plan(mac: app.currentMac, symptom: symptom)
            }
        }
    }

    private func stepCard(_ step: LockoutRecovery.Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: done.contains(step.rawValue) ? "checkmark.circle" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(done.contains(step.rawValue) ? T.C.ok : T.C.ink4)
                    .accessibilityHidden(true)
                Text(step.title)
                    .type(T.F.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.ink)
                Spacer(minLength: 8)
                Text(step.risk)
                    .type(T.F.caption)
                    .foregroundStyle(step.risk == "无风险" ? T.C.ink3 : T.C.danger)
            }
            Text(step.detail)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 23)

            if let failure = failures[step.rawValue] {
                FailureCard(failure: failure)
                    .padding(.leading, 23)
            }

            if !done.contains(step.rawValue) {
                TextAction(title: step.needsUserAtLock ? "看这一步怎么做" : L("recovery.run")) {
                    Task { await run(step) }
                }
                .padding(.leading, 23)
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run(_ step: LockoutRecovery.Step) async {
        busy = true
        defer { busy = false }
        switch await LockoutRecovery.perform(step, mac: app.currentMac) {
        case .done:
            done.insert(step.rawValue)
            failures[step.rawValue] = nil
            AppToast.shared.show("这一步完成了")
        case .needsUser(let s):
            waiting = s
        case .failed(let why):
            failures[step.rawValue] = ScreenFailure(kind: .transport,
                                                    title: "这一步没做成",
                                                    detail: why,
                                                    next: "确认门锁通电、手机在旁边，再试一次。",
                                                    canRetry: true)
        }
    }
}
