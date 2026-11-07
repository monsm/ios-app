// TodayPieces.swift —— 今日页的三块新零件：
//   · LinkPill          —— 常驻的链路状态（F25）
//   · UnlockDiagnosisCard —— 开锁失败后的「下一步」（F15）
//   · UnlockReceiptCard —— 开锁成功的回执（F16）
//
// 三块都遵守同一条纪律：**给得出下一步才占这个位置**。
// 诊断卡没有可执行动作时不画按钮 —— 空按钮比没有按钮更让人困惑。
import SwiftUI

// MARK: - 链路状态

/// 常驻的链路状态。点开可以连一下或去诊断。
struct LinkPill: View {
    var phase: LinkSenseModel.Phase
    var rssi: Int?
    var busy: Bool = false
    var onTap: (() -> Void)? = nil

    private var tint: Color {
        switch phase {
        case .ready: return T.C.ok
        case .connecting: return T.C.brass
        case .down, .noKey: return T.C.ink3
        }
    }

    private var symbol: String {
        switch phase {
        case .ready: return "dot.radiowaves.left.and.right"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .down: return "antenna.radiowaves.left.and.right.slash"
        case .noKey: return "questionmark.circle"
        }
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(phase.rawValue)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                if let rssi {
                    Text("\(rssi) dBm")
                        .type(T.F.caption)
                        .monospacedDigit()
                        .foregroundStyle(T.C.ink3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(T.C.hair, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel("链路状态：\(phase.rawValue)")
        .accessibilityHint(onTap == nil ? "" : "点开可重新连接或查看诊断")
    }
}

// MARK: - 失败诊断卡

struct UnlockDiagnosisCard: View {
    var failure: ScreenFailure?
    var steps: [DiagnosisStep]
    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDiagnose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(UnlockDiagnosis.headline(failure: failure))
                    .type(T.F.title2)
                    .foregroundStyle(T.C.ink)
                Spacer(minLength: 8)
                if let onRetry {
                    TextAction(title: L("common.retry")) { onRetry() }
                }
            }

            if let f = failure, !f.detail.isEmpty {
                Text(f.detail)
                    .type(T.F.footnote)
                    .foregroundStyle(T.C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: T.S.s) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step.done ? "checkmark.circle" : step.symbol)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(step.done ? T.C.ok : T.C.ink3)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .type(T.F.footnote)
                                .fontWeight(.medium)
                                .foregroundStyle(step.done ? T.C.ink3 : T.C.ink)
                            Text(step.detail)
                                .type(T.F.caption)
                                .foregroundStyle(T.C.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        if let action = step.action {
                            if action == "去系统设置", let onOpenSettings {
                                TextAction(title: action) { onOpenSettings() }
                            } else if action == "看凭证" {
                                // 交给外层（跳到凭证页）
                                Text("看凭证")
                                    .type(T.F.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(T.C.brass)
                            }
                        }
                    }
                }
            }

            if let onDiagnose {
                TextAction(title: L("diag.timeline.title")) { onDiagnose() }
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 成功回执卡

/// 开锁成功的回执：自动上锁倒计时 + 这次用的凭证 + 看记录。
struct UnlockReceiptCard: View {
    var credential: String
    var autoLockSeconds: Int?
    var onViewLog: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: T.S.s) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(T.C.ok)
                    .accessibilityHidden(true)
                Text("门开了")
                    .type(T.F.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.ink)
                Spacer(minLength: 8)
                if let s = autoLockSeconds {
                    Text("约 \(s) 秒后自动上锁")
                        .type(T.F.caption)
                        .monospacedDigit()
                        .foregroundStyle(T.C.ink3)
                }
            }
            if !credential.isEmpty {
                Text("这次用的是 \(credential)")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
            }
            if let onViewLog {
                TextAction(title: "看这次开门记录") { onViewLog() }
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
