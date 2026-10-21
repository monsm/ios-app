// 全站唯一的一份本地朗读出口 (810 逐卡朗读 / 309 密码逐位 / Siri 那一条"读最近记录")。
// 为什么必须只有一个：这之前有**两份各自 new 的 AVSpeechSynthesizer** ——
// `App/Intents/AppIntents.swift` 里的 private enum TTS 与 `App/UI/CredentialStudio.swift` 里的 StudioTTS。
// 两个实例可以同时在说话 (念密码念到一半来一条记录朗读就叠在一起)，
// 而"停掉上一句"这种最基本的动作在两份实例上各做一半 —— 那是两份真相源，不是两个功能。
// 全程走系统本地语音，不联网、不采集、不录音 (CONSTRAINTS 的离线口径)。
import AVFoundation

