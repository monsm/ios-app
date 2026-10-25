// 全站唯一的一份本地朗读出口 (810 逐卡朗读 / 309 密码逐位)。
// 为什么必须只有一个：这之前有**两份各自 new 的 AVSpeechSynthesizer** ——
// `App/UI/CredentialStudio.swift` 里的 StudioTTS。
// 两个实例可以同时在说话 (念密码念到一半来一条记录朗读就叠在一起)，
// 而"停掉上一句"这种最基本的动作在两份实例上各做一半 —— 那是两份真相源，不是两个功能。
// 全程走系统本地语音，不联网、不采集、不录音 (CONSTRAINTS 的离线口径)。
import AVFoundation

enum Speech {
    /// 唯一的合成器实例 —— 由一把锁持有, 而不是裸 static let。
    /// AVSpeechSynthesizer 不是 Sendable, 裸 static let 在 Swift 6 下判"非隔离全局共享可变状态";
    /// 而它**确实是**共享可变状态 (isSpeaking / speak / stop 必须看同一份, 否则两句话会叠音)。
    /// 上锁 = 让原语保证互斥, 不是把检查关掉。朗读是低频动作, 一次锁的开销在听感上不可测。
    private static let synth = Locked(AVSpeechSynthesizer())

    /// 中文朗读。`rate` 默认 0.5：系统档位里 0.5 是"清楚但不赶"的一档，逐位报码那种要更慢。
    /// 开口前先 stop 掉上一句 —— 老人跟着抄一串叠音的密码，比不念更糟。
    @discardableResult
    static func zh(_ text: String, rate: Float = 0.5) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let u = AVSpeechUtterance(string: t)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = rate
        synth.withLock { s in
            if s.isSpeaking { s.stopSpeaking(at: .immediate) }
            s.speak(u)
        }
        return true
    }

    /// 309 逐位中文报码 (让对方同步抄写)。非数字一律跳过而不是念成"某"—— 念错了比不念更难查。
    static func digits(_ s: String) {
        let zhDigits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let spelled = s.compactMap { ch -> String? in
            guard let d = ch.wholeNumberValue, d >= 0, d <= 9 else { return nil }
            return zhDigits[d]
        }
        guard !spelled.isEmpty else { return }
        _ = zh("密码逐位: " + spelled.joined(separator: "、") + "。", rate: 0.35)
    }

    /// 收页时调用: 引导卡关了却还在念下一张的内容, 比不念更让人摸不着头脑。
    /// (没有留 `isSpeaking` 这种读点 —— 全仓没有读者, 而 AVFoundation 自己也随时能问。)
    static func stop() {
        synth.withLock { s in if s.isSpeaking { s.stopSpeaking(at: .immediate) } }
    }
}
