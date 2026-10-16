// 390 伪装码进入的空壳界面。刻意只做"本机时钟"这类真实且与门锁无关的内容:
// 原设计是模拟天气, 但本 App 离线无网络授权, 现编一组气温/城市就是伪造数据 —— 这是本审计反复抓到的一类问题,
// 不为了"像"而造数据。空壳内不读任何 kf_ledger_/kf_kc_/凭证键, 因此被翻看时没有任何可泄露的门锁信息。
// 逃生口: 长按页脚那行小字 3 秒回锁屏, 之后必须用真密码进入 (AUDIT-B P0-3 记录的"真密码逃生"语义)。
// 2026-10-15 走查: 原先用 `DragGesture(minimumDistance: 0)` + onChanged 里比时间戳来实现这 3 秒, 静止按住时
// 收不到第二次 onChanged (Apple 对 DragGesture 的原话是 "invokes an action as the drag-event sequence changes"
// —— 事件跟着**拖动**走, 不跟着时钟走), 于是 `>= 3` 那句只在手指一直在动时才可能被再次求值:
// 手指纹丝不动 = 一次事件都不再产生 = 逃生口点不动; 只有来回蹭着按才碰巧成功。
// 换成 LongPressGesture(minimumDuration:) —— 它的契约就是"按住够久即 onEnded", 不靠位移喂。
// (刻意不给任何提示, 也不挂 VoiceOver 动作: 空壳自己不能成为破绽。另一条退路是切后台到点自动落锁, 见 LockKeeperApp.handleScenePhase。)
import SwiftUI

struct DecoyShellView: View {
    @EnvironmentObject var app: AppState
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: DS.Space.xl)
            Text("时钟")
                .vkFont(.title3, weight: .medium)
                .foregroundStyle(DS.Palette.textSub)
                .accessibilityAddTraits(.isHeader)
            Text(Self.timeStr.string(from: now))
                .vkFont(.system(.largeTitle, design: .rounded), weight: .light)
                .monospacedDigit()
                .foregroundStyle(DS.Palette.text)
            Text(Self.dateStr.string(from: now))
                .vkFont(.body)
                .foregroundStyle(DS.Palette.textSub)
            // 逃生口: 视觉上只是一行普通页脚, 长按 3 秒才回锁屏 (不给出任何提示, 否则空壳自己就是破绽)
            Text("本地时钟 · 无需联网")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub.opacity(0.7))
                .padding(.top, DS.Space.xl)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 3)
                        .onEnded { _ in escape() }
                )
                .accessibilityLabel("本地时钟, 无需联网")
            Spacer(minLength: 0)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsScreenBackground()
        .onReceive(ticker) { now = $0 }
    }

    private func escape() {
        // 回锁屏要重新过验证: 空壳本身不保留任何解锁状态
        app.decoyMode = false
        app.appUnlocked = false
    }

    private static let timeStr: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm:ss"; return f
    }()
    private static let dateStr: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale.current; f.dateStyle = .full; return f
    }()
}
