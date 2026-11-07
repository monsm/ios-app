// UnlockDiagnosis.swift —— 开锁失败后的「下一步」（F15）。
//
// 开锁失败只有一句话是不够的：「连不上门锁：xxx」
// 用户要的是「**我现在该做什么**」。
//
// 这里把失败分类成几种典型症状，每一种给两三步可执行的动作，
// 并按「已经排除的」打勾 —— 用户照着做，不用猜。
import Foundation

struct DiagnosisStep: Identifiable, Equatable {
    var id: String { title }
    var symbol: String
    var title: String
    var detail: String
    /// 这一步已经确认没问题（灰掉）。
    var done: Bool = false
    /// 能不能一键做（能就带一个动作）。
    var action: String?
}

enum UnlockDiagnosis {
    /// 按症状给步骤。
    static func steps(failure: ScreenFailure?,
                      linkPhase: LinkSenseModel.Phase,
                      battery: Int,
                      safeMode: Bool,
                      muted: Bool) -> [DiagnosisStep] {
        var steps: [DiagnosisStep] = []

        // 1) 蓝牙
        steps.append(DiagnosisStep(
            symbol: "dot.radiowaves.left.and.right",
            title: "蓝牙是开的吗",
            detail: linkPhase == .noKey ? "这把锁还没在本机登记" : "门锁走的是蓝牙直连，不需要网络",
            done: linkPhase == .ready,
            action: linkPhase == .ready ? nil : "去系统设置"))

        // 2) 距离
        steps.append(DiagnosisStep(
            symbol: "figure.walk.arrival",
            title: "手机在门锁旁边吗",
            detail: "蓝牙有效距离大约两三米，金属门会让它更近",
            done: false))

        // 3) 电量
        let lowBattery = battery >= 0 && battery <= 10
        steps.append(DiagnosisStep(
            symbol: "battery.25",
            title: "门锁电量够吗",
            detail: battery < 0 ? "还没读到门锁电量" : (lowBattery ? "门锁电量只剩 \(battery)%，该换电池了" : "门锁电量 \(battery)%，正常"),
            done: !lowBattery && battery >= 0))

        // 4) 锁的状态（布防/反锁）
        steps.append(DiagnosisStep(
            symbol: "lock.shield",
            title: "门锁是不是布防或反锁了",
            detail: safeMode ? "这把锁开着双验模式，开门可能需要两种凭证" : "布防或从里面反锁时，命令不会执行",
            done: false))

        // 5) 凭证本身（只在失败与凭证有关时才提）
        if let f = failure, f.kind == .auth || f.kind == .lockRejected {
            steps.append(DiagnosisStep(
                symbol: "key",
                title: "换一枚凭证试试",
                detail: f.next ?? "锁不认这条开锁凭证",
                done: false,
                action: "看凭证"))
        }

        // 6) 可能已执行（超时）
        if let f = failure, f.mayHaveExecuted {
            steps.append(DiagnosisStep(
                symbol: "exclamationmark.triangle",
                title: "先看门锁的状态再重试",
                detail: "这条命令已经发出去了，只是没等到回执 —— 重发可能开两次门",
                done: false))
        }
        return steps
    }

    /// 一句话小结（卡片标题下那行）。
    static func headline(failure: ScreenFailure?) -> String {
        guard let f = failure else { return "没打开" }
        if f.mayHaveExecuted { return "没收到回执" }
        switch f.kind {
        case .transport: return "连不上门锁"
        case .auth: return "凭证被拒"
        case .lockRejected: return "门锁拒绝了这次开门"
        case .localStorage: return "本机数据有问题"
        case .permission: return "缺一个权限"
        case .cancelled: return "已取消"
        case .unknown: return "没打开"
        }
    }
}
