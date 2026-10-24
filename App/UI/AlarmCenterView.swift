// 包9 告警中心 (723-724/726-743/745-747) — 跨锁告警流 + 四级色标 + 处置留痕 + 回放刻度
// 头注释写成 `723-743` 时把 725 也算了进来，而 725 (胁迫全屏确认卡) 判 ❌: 协议日志类型表
// (CAPABILITY §3) 根本没有胁迫类告警，这个文件里没有它的任何实现。**区间列举不许盖住判 ❌ 的编号** ——
// 覆盖表 (tools/featuremap.js) 就是按这行把头注释里的区间展开的，于是一个没做的编号被记成"有标注"。
// 它的替代"高危告警确认卡"(用真实存在的防撬 7/试错锁定 10/224) 同样未建, 记在 docs/DECISION-NEEDED.md。
// 纪律: 告警类型只用 CAPABILITY §3 真实存在的 5 种; 处置/测试标记走 RecordSearch.dispositions 本地留痕;
//       颜色只经 DS 令牌 (danger 派生 .opacity, 形状冗余); 归属推断标"约";
//       742 响应时长分布占位"积累中" (依赖处置时间积累), 737 试错累计 keyboardErrCount 语义标"?"。
import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════
// 2026-10-24 删除旧页面 struct AlarmCenterView（原 12-867 行）
//
// 它被 AlarmsPage（2026-10-21 全新重写）取代；QuickPool 快捷格落点改到 AlarmsPage
// 之后全仓零引用。留着就是「同一功能点两套实现」，用户看到哪套取决于入口引用哪套。
//
// 保留下方两个扩展：toneColor 被 BackupPage/CarePage/DevicePage/ExportCenter/
// FirmwarePage/KeysPage/SecurityPage 共 8 处使用；atLabel 被 AutoOpen/ExportCenter 使用。
// （replayHour/setReplayHour 原本只有旧页自己用，随之删除。）
// ═══════════════════════════════════════════════════════════════════════


extension RecordSearch {
    /// 724 四级色标 → DS 令牌映射 (紧急 danger / 严重 danger 降饱和 / 提示 warn)
    static func toneColor(for type: Int) -> Color {
        switch AlarmMeta.level(type) {
        case 3: return XPalette.danger
        case 2: return XPalette.danger.opacity(0.72)
        case 1: return type == 6 ? XPalette.warn : XPalette.textSub
        default: return XPalette.textSub
        }
    }
    // replayHour / setReplayHour 随旧页面一起删除（零外部引用）
    // 745 的 testMarkedKeys 已移入 RecordSearch.swift 核心 (StatsKit/LockStats 统计层要从 Core 调, 不再挂在 UI 扩展上)
}

extension RecordSearch.Disposition {
    func atLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.string(from: Date(timeIntervalSince1970: at))
    }
}
