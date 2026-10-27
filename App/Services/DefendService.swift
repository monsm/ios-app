// 布防下发/回读（cmd25 SETDEFENCE）—— 补齐 iOS 侧缺失的入口。
//
// 为什么单独一个文件而不是塞回 LockService：布防是**有本地配置记忆**的动作（DefendCfg 落 kf_defend_<mac>），
// 它同时被自动开锁的 F4 门读。把「下发 + 落盘 + 回读」三件事收在一处，才能保证不会出现
// 「锁端在布防、本机 F4 还在放行自动开锁」这种两边不一致。
import Foundation

@MainActor
enum DefendService {
    /// 目标：让锁端与本地配置同时等于 (mode, startSec, endSec)。
    ///
    /// - 参数 startSec/endSec 用**秒**（UI 直觉）；内部经 DefendKit.protoSec 换成协议半秒。
    /// - 撤防（.off）时时间字段发 0，与 APK 的 `currentIdx=3 → control=0, 时间全 0` 一致。
    /// - 失败时**不写本地**：宁可让用户重试，也不要造出一个"本机以为布防了"的假状态
    ///   —— 因为 F4 否决门读的就是本地配置，写早了会让自动开锁被误否决。
    static func apply(_ app: AppState,
                      mode: DefendMode,
                      startSec: Int = 0,
                      endSec: Int = 0) async throws {
        guard let kc = app.current else { throw BLEErrorX.msg("未选择门锁") }

        if let bad = DefendKit.validate(mode: mode, startSec: startSec, endSec: endSec) {
            throw BLEErrorX.msg(bad)
        }

        let control = mode.rawValue
        // 2026-10-27 审核说明 (AUDIT-A F-40)：.once（不定期布防）这里发 0/0，
        // 而 APK 发的是**绝对时间**（到点自动撤防）。这不是 bug，是 UI 层没有对应输入 ——
        // DefendView 的 once 模式只有一个「执行布防」按钮，没有起止时间选择器，
        // 所以本机无从得知「到几点撤防」。
        // 已在 DefendView:179 如实告知用户「直到你手动撤防」—— 两种姿态的差异是可见的。
        // 若以后要支持定时撤防，需先加 DatePicker，再把协议秒（基准 2010-01-01）填进这两格。
        let startProto = mode == .period ? DefendKit.protoSec(startSec) : 0
        let endProto = mode == .period ? DefendKit.protoSec(endSec) : 0

        try await app.lock.ensureConnected(mac: kc.mac)
        try await app.lock.setDefence(control: control, startSec: startProto, endSec: endProto)

        // 下发成功才落盘 —— 这一条与 tailgate 的写法同口径（失败不写本地，避免两个真相）。
        DB.saveDefend(kc.mac, DefendCfg(control: control,
                                        startSec: startProto,
                                        endSec: endProto,
                                        at: Date().timeIntervalSince1970 * 1000))
    }

    /// 只读当前配置（给首页卡与设置行）。
    static func current(_ app: AppState) -> DefendCfg? {
        guard let kc = app.current else { return nil }
        return DB.defend(kc.mac)
    }

    /// 能力门禁：布防只有 KX / V1_Pro 家族能用（APK 的 canDefend 白名单同源）。
    static func allowed(_ app: AppState) -> Bool {
        guard let kc = app.current else { return false }
        return PidMap.canDefend(kc.pid)
    }
}
