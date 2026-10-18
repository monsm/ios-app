// 848 成败提示音 + 733 告警提示音分级 — App 内提示音的唯一出口
//
// 制式沿用包15 声音策略 (DesignSystem.swift:592-594): App 音效一律走系统 systemSound，
// 铃声静音开关打开时由系统本身出无声，不读路由、不自建音量通道、不新开一路音量。
// 本文件之后，全 App 的裸 AudioServicesPlaySystemSound 调用点只剩下面那几个私有 ID 常量处
// (原有两处已接进来: 开锁成功短音 LockKeeperApp.settleUnlockSuccess / 成就收集音 Milestones.playCollectSound)。
//
// 三条开关都是**默认关** (拍板口径): 服务不盯屏的用户要的是"响一声"，
// 而在会议室里突然三声急促音是打扰 —— 所以必须用户自己开。
import AudioToolbox

enum AlertTone {
    /// 848 失败短音开关 (成功那枚沿用既有 kf_unlock_sound，两者互相独立，可只开一个)
    static var failOn: Bool { DB.store.getBool("kf_unlock_fail_sound") }
    /// 733 告警分级音总开关 (胁迫三音 / 低电单音都归它管，关掉就全部静默)
    static var alertOn: Bool { DB.store.getBool("kf_alert_tone") }
    /// ⚠ 胁迫档另有一道**独立开关**，默认关，且打开时界面必须把风险说清：
    /// 本仓 390/391 的既有不变量是"伪装与胁迫放行的反馈**与真解锁一致**，否则开关本身就是破绽"
    /// (LockKeeperApp 的 unlockAttempt 里那三段注释)。而"胁迫急促三音"恰恰要在胁迫放行的当场
    /// 发出一个与平时不同的声音 —— 按住口令的那个人就听得出来。
    /// 所以这一档不并进总开关，单独一刀、默认关、标签自曝风险；真要静默就让它一直关着。
    static var duressToneOn: Bool { DB.store.getBool("kf_duress_tone") }

    // ---------- 音色 ID ----------
    // ⚠ API-VERIFY: 下面的数字只有 1104 是本仓既有用过的 (76 成功短音)。
    //    其余三个 ID 未经真机核对：**传入不存在的 ID 时系统静默不响，不会崩也不会报错**，
    //    所以这一组的最坏结果是"开了开关却听不到"，不是安全问题。真机批次要逐个核可听性，
    //    核不响的就换成 AudioServicesPlaySystemSoundWithCompletion 探测或直接改走触感。
    // 2026-10-13 run 63: 这四个常量原来是 `Int`, 而 `AudioServicesPlaySystemSound` 要的是
    // `SystemSoundID` (aka UInt32) ⇒ 5 处调用报 "cannot convert value of type 'Int' to expected
    // argument type 'SystemSoundID' (aka 'UInt32')"。显式标注成 SystemSoundID。
    private static let idSuccess: SystemSoundID = 1104
    private static let idFailure: SystemSoundID = 1053
    private static let idDuress: SystemSoundID = 1102
    private static let idLowBattery: SystemSoundID = 1006

    /// 76/848 开锁成功短音 (开关在 设置-开锁，原 kf_unlock_sound 语义不变)
    static func unlockSuccess() {
        if DB.store.getBool("kf_unlock_sound") { AudioServicesPlaySystemSound(idSuccess) }
    }
    /// 2026-10-18 自动开锁成功音开关 (独立持久化开关, 默认开)。
    ///
    /// 为什么与 kf_unlock_sound 分开:
    ///   · 手动开锁是"我主动按的", 响一声是确认;
    ///   · 自动开锁是"我走近它自己开的", 用户可能正低头看手机, 声音是**唯一**的到场信号;
    ///   · 但也有人不希望每次路过门口都响 —— 所以给独立开关, 而不是并进手动那枚。
    /// 默认 **true**: 自动开锁没有视觉确认(手机可能在口袋里), 默认有声才是安全的;
    /// 静音偏好由系统铃声开关统一兜底 (本文件头注的既有制式)。
    static var autoUnlockOn: Bool { DB.store.getBool("kf_auto_unlock_sound", true) }

    /// 自动开锁成功短音。与 unlockSuccess() 用同一音色, 但读**独立开关**。
    static func autoUnlockSuccess() {
        if autoUnlockOn { AudioServicesPlaySystemSound(idSuccess) }
    }

    /// 848 开锁终态失败短音: 只在**走完重试链的终态失败**响 (中间静默重试不响，
    /// 否则一次开锁失败连响三声，用户会以为出了三件事)
    static func unlockFailure() {
        if failOn { AudioServicesPlaySystemSound(idFailure) }
    }

    enum Tier {
        case duress        // 733 胁迫: 急促三音
        case lowBattery    // 733 低电: 单音
    }

    /// 733 告警到达音。级别只影响**节奏**，不假装能选出"警报音色"。
    static func alert(_ tier: Tier) {
        guard alertOn else { return }
        switch tier {
        case .lowBattery:
            AudioServicesPlaySystemSound(idLowBattery)
        case .duress:
            // 独立第二道闸 (默认关)，理由见上面 duressToneOn 那段：这一声会在胁迫放行的当场响出来。
            guard duressToneOn else { return }
            // 三声间隔 140ms：短、急促、不连成一片。用 asyncAfter 而不是循环 sleep ——
            // 提示音不该占住主线程的等待预算。
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.14) {
                    AudioServicesPlaySystemSound(idDuress)
                }
            }
        }
    }

    /// 977-980 成就点亮音 (原先直接裸调 AudioServicesPlaySystemSound(1104)，接进来收敛调用点；
    /// 它不归 848/733 任何一枚开关管 —— 庆祝音的开关是 15 包那套庆祝预算，不是提示音)
    static func achievement() {
        AudioServicesPlaySystemSound(idSuccess)
    }
}
