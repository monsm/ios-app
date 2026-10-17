// 设备页模块显隐 (乱源治理第 3 批)
//
// 拍板口径 (2026-10-30): **默认一块都不隐**，这一批只把"能不能关"做出来 —— 面板里全部默认"显示"。
// 也就是说这一批改的是能力，不是观感默认值; 谁要用自己的节奏筛掉哪些，由他自己拨。
//
// 必留的五块刻意不进面板:
//   · 设备切换器 102/101 —— 藏了就没有"当前这把锁"是谁的概念。
//   · 176pt 开锁圆盘 —— 全 App 唯一主操作，藏它等于把 App 变成台账浏览器。
//   · 三个可排序槽 (状态卡 / 快捷格 / 最近开门) —— 904 已经在管它们的次序，再叠一层显隐会让"槽位固定"这句话失效。
//   · 异常卡 attentionCard —— 它本来就只在真有问题时出现; 能把它关掉，等于让用户自己把警告闭嘴。
//   · 换机迁移向导 —— 一次性流程，不是常驻版面。
//
// 存储: 单键 CSV (与 kf_dev_order 同族)。白名单过滤 + 去重, 认不出的 id 一律丢掉 ——
// 与 QuickPool.idsKey 同一口径: 改名或删模块都不会把用户已有的一整串设置打空。
import Foundation

nonisolated enum DevModule: String, CaseIterable, Identifiable {
    case groupChips      // 767 按组切换 chips
    case statusIcons     // 764 多锁状态图标行 (家庭 App 房间行)
    case linkSense       // 包2: 69 蓝牙直通条 / 126 回连节律 / 125 最后已知状态 / 535 同步回执 / 130 唤醒失败细分
    case nightCheck      // 976 安心夜打卡
    case familyCare      // 包13: 485 生日 / 480 孩子码 / 475 家庭便签
    case privacyNote     // 隐私脚注

    var id: String { rawValue }

    /// 面板上的那一行标题
    var title: String {
        switch self {
        case .groupChips: return "按组切换"
        case .statusIcons: return "多锁状态图标行"
        case .linkSense: return "连接感知区"
        case .nightCheck: return "安心夜打卡"
        case .familyCare: return "家庭关怀行"
        case .privacyNote: return "隐私脚注"
        }
    }

    /// 关掉会少什么 —— 说清代价, 不写"隐藏某区块"这种让用户猜的话
    var cost: String {
        switch self {
        case .groupChips:
            return "多锁时少一排按组切换; 胶囊排照常能换锁。"
        case .statusIcons:
            return "少一眼看清哪把锁有事; 逐把点进胶囊仍能看到状态。"
        case .linkSense:
            return "少蓝牙直通条、回连节律、最后已知状态与同步回执。自动回连与巡检照常跑, 只是不在这里显示。"
        case .nightCheck:
            return "22 点后的手动安心确认不再出现在本页; 设置里的这一档也照常可拨。"
        case .familyCare:
            return "生日 / 孩子码 / 家庭便签不再出现在本页; 三处功能各在自己的页面可达。"
        case .privacyNote:
            return "本页底部的数据说明文字不再显示 (数据面本身不变)。"
        }
    }
}

nonisolated enum DevModuleStore {
    static let key = "kf_dev_hidden"

    /// 读被关掉的那些 (白名单过滤; 空 = 全部显示 = 默认态)
    static var hidden: Set<String> {
        let raw = DB.store.getString(key)
        if raw.isEmpty { return [] }
        let ok = Set(DevModule.allCases.map { $0.rawValue })
        return Set(raw.split(separator: ",").map(String.init).filter { ok.contains($0) })
    }

    static func setHidden(_ m: DevModule, _ off: Bool) {
        var cur = hidden
        if off { cur.insert(m.rawValue) } else { cur.remove(m.rawValue) }
        // 与默认等价 (一个都没关) 就删键, 不给备份留一份等价副本 —— QuickPool.setSelected 同口径
        if cur.isEmpty { DB.store.remove(key) }
        else { DB.store.set(key, DevModule.allCases.map { $0.rawValue }.filter { cur.contains($0) }.joined(separator: ",")) }
    }

    /// 恢复默认 = 全部显示
    static func reset() { DB.store.remove(key) }
}
