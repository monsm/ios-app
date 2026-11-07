// Copy.swift —— 通用短句的**唯一**出处。
//
// 纪律（见 docs/UI-CONVENTIONS.md §4）：同一句话只在一个地方定义。
// 带业务语义的长句留在页面里；这四个字/一句话的短句集中在这里。
enum Copy {
    // 四个通用动词的**出处是 L10n 表**（common.retry / common.cancel / common.close / common.done）——
    // 这里只做语义别名，不再各写一份字面量。
    static let retry = L("common.retry")
    static let cancel = L("common.cancel")
    static let close = L("common.close")
    static let done = L("common.done")

    // 读日志（全量读取的口径）
    static let readFullLogs = "读全量日志"
    static let readingLogs = "正在读门锁记录…"

    // 空壳/写入拒绝：两句中性话，全 App 统一（不出现「空壳」二字）
    static let decoyWrite = "当前无法保存，请稍后再试"
    static let decoyRead = "当前无法读取，请稍后再试"
}
