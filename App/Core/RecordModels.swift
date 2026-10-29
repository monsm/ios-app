// 记录模型 · Rec / OutWin / Holiday / Query / Disposition / SameCount / Merged
// 2026-10-29 从 RecordSearch.swift（804 行）拆出。
import Foundation

struct Rec: Identifiable {
    var key: String        // 行 key (锁日志 idxRaw)
    var mac: String        // 归属锁 (全部锁模式下定位)
    var lockName: String   // 770 锁名前缀标签
    var type: Int
    var typeName: String
    // 2026-10-27 审核说明 (AUDIT-A F-27)：`idxRaw` / 窗口语义是**本仓新增** ——
    // vendor 完全没有这个概念（它的日志是"拉一页显示一页"）。
    // 本仓要支持"按序号定位、跨页合并、缺口标注"，所以引入了 idx 窗口。
    // 不存在与 vendor 对齐的问题；差异在于本仓多做了一层可寻址性。
    var idxRaw: UInt32
    var lockTime: Int64
    var timeStr: String    // "yyyy-MM-dd HH:mm:ss"
    var whoId: String? = nil  // 可证明归属成员 id (791 认领在 UI 层叠加); 失败/保养行无可证明归属 → 留默认 nil
    var whoName: String?   // 可证明归属才填 (显示名), 否则 nil
    var kind: String?      // fp/pwd/temp/key (开门类才有)
    var provable: String?  // temp/unique
    var cred: String       // 568 凭证维度标签 (归所有凭证历史用)
    var alarm: Bool
    var care: Bool         // 手机侧保养/换电事件 (1028)
    var failMsg: String    // 92 手机侧失败原因 (非空 = kf_fevents_ 行)
    var id: String { mac + "#" + key }
}

