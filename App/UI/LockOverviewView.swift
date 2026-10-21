// 全部锁总览与对比 (包3) — 768 待维护清单 / 776 活跃度条形榜 / 778 告警率对比列 /
// 779 成员×锁交叉矩阵 / 784 固件版本对照表 / 773 凭证容量水位 / 787 对比结论一句话 / 769 绑定时间标注。
// 数据源全部是既有本地表 (日志缓存/台账/快照/钥匙串), 统计逻辑在 App/Core/LockStats.swift。
import SwiftUI

/// 768/778 下钻目标: 用 Identifiable 包一层 mac 给 .sheet(item:) 用
private struct AlarmTarget: Identifiable {
    let mac: String
    var id: String { mac }
}

