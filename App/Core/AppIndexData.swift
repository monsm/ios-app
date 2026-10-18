//  AppIndexData.swift
//  由 tools/gen-appindex.js 从 docs/preview/uiux-v3.data.js 生成，**不要手改**。
//
//  为什么必须生成而不是手写: v10 原型就是内联了一份 76 项数组, 结果与数据类型漂移,
//  两边都不再是事实来源 (D7)。这份文件的唯一来源是 window.SCREENS + Destination 枚举。
//  改了数据之后重跑: node tools/gen-appindex.js

import Foundation

/// App Index 的一行 (一个目的地)。
struct AppIndexItem: Identifiable, Hashable {
    let id: String          // Destination 枚举名
    let title: String       // 中文标题
    let group: String       // 分组名
    let keywords: [String]  // 搜索同义词
}

/// App Index 的一组。
struct AppIndexGroup: Identifiable, Hashable {
    let name: String
    let items: [AppIndexItem]
    var id: String { name }
}

enum AppIndexData {
    static let groups: [AppIndexGroup] = [
        AppIndexGroup(name: "锁", items: [
            AppIndexItem(id: "addDevice", title: "添加门锁", group: "锁", keywords: ["添加门锁","锁","第一次用","或者添第二把锁"]),
            AppIndexItem(id: "autoCal", title: "自动开锁校准", group: "锁", keywords: ["自动开锁校准","锁","每个人家门口的信号都不同","阈值必须能调"]),
            AppIndexItem(id: "deviceHome", title: "锁", group: "锁", keywords: ["锁","能不能开：这一屏只回答这一件事"]),
            AppIndexItem(id: "deviceInfo", title: "设备信息", group: "锁", keywords: ["设备信息","锁","排查时第一眼要看的事实"]),
            AppIndexItem(id: "deviceManage", title: "设备管理", group: "锁", keywords: ["设备管理","锁","锁多了以后","顺序与分组决定找得快不快"]),
            AppIndexItem(id: "firmware", title: "固件", group: "锁", keywords: ["固件","锁","有没有更新","更新会改什么"]),
            AppIndexItem(id: "focusUnlock", title: "专注开锁", group: "锁", keywords: ["专注开锁","锁","在走廊","夜里","单手时"]),
            AppIndexItem(id: "gateway", title: "网关", group: "锁", keywords: ["网关","锁","要远程开门时","网关是前提"]),
            AppIndexItem(id: "keychainHW", title: "钥匙硬件", group: "锁", keywords: ["钥匙硬件","锁","实体钥匙也要能被管理","挂失","补配"]),
            AppIndexItem(id: "linkPrefs", title: "连接偏好", group: "锁", keywords: ["连接偏好","锁","连接行为要可预期","也要可关闭"]),
            AppIndexItem(id: "lockCompare", title: "锁对比", group: "锁", keywords: ["锁对比","锁","排查“为什么这台更慢”时","需要并排看"]),
            AppIndexItem(id: "lockOverview", title: "多锁总览", group: "锁", keywords: ["多锁总览","锁","有多把锁时","一屏看清谁在线","谁该处理"]),
            AppIndexItem(id: "lockProfile", title: "这把锁", group: "锁", keywords: ["这把锁","锁","它是谁","装在哪","叫什么名字"]),
            AppIndexItem(id: "syncTime", title: "时间同步", group: "锁", keywords: ["时间同步","锁","日志时间对不上时","先校准时钟"]),
            AppIndexItem(id: "unlockGate", title: "开锁前置检查", group: "锁", keywords: ["开锁前置检查","锁","开不了时","先告诉用户缺什么","而不是转圈"]),
        ]),
        AppIndexGroup(name: "凭证", items: [
            AppIndexItem(id: "addPwd", title: "添加密码", group: "凭证", keywords: ["添加密码","凭证","新增一条能开门的密码"]),
            AppIndexItem(id: "credBin", title: "回收站", group: "凭证", keywords: ["回收站","凭证","删错了还能救回来"]),
            AppIndexItem(id: "credCenter", title: "凭证中心", group: "凭证", keywords: ["凭证中心","凭证","所有凭证的单一入口"]),
            AppIndexItem(id: "credentials", title: "凭证与钥匙", group: "凭证", keywords: ["凭证与钥匙","凭证","谁能开这把门：这是锁的属性","不是独立世界"]),
            AppIndexItem(id: "credExtend", title: "延长临时码", group: "凭证", keywords: ["延长临时码","凭证","访客还没走","权限要能顺延"]),
            AppIndexItem(id: "credHistoryList", title: "凭证变更总表", group: "凭证", keywords: ["凭证变更总表","凭证","一次看完全部改动","而不是逐条翻"]),
            AppIndexItem(id: "credHistory", title: "凭证历史", group: "凭证", keywords: ["凭证历史","凭证","这条密码什么时候改过","谁改的"]),
            AppIndexItem(id: "credOrganize", title: "整理建议", group: "凭证", keywords: ["整理建议","凭证","凭证会自己长出来","需要定期收"]),
            AppIndexItem(id: "credQueue", title: "待补拉队列", group: "凭证", keywords: ["待补拉队列","凭证","网络/链路失败时","改动不能悄悄丢"]),
            AppIndexItem(id: "credTransfer", title: "凭证迁移", group: "凭证", keywords: ["凭证迁移","凭证","换机时把钥匙带走","而不是重新配"]),
            AppIndexItem(id: "shareToAndroid", title: "分享给安卓", group: "凭证", keywords: ["分享给安卓","凭证","家里另一台手机不该被系统排除在外"]),
            AppIndexItem(id: "startAddFp", title: "添加指纹", group: "凭证", keywords: ["添加指纹","凭证","把一个人的手指变成一把钥匙"]),
        ]),
        AppIndexGroup(name: "成员", items: [
            AppIndexItem(id: "borrowSheet", title: "借用钥匙", group: "成员", keywords: ["借用钥匙","成员","借一次","而不是送一把"]),
            AppIndexItem(id: "memberArchived", title: "已归档成员", group: "成员", keywords: ["已归档成员","成员","离开的人不该还在列表里","但记录要留"]),
            AppIndexItem(id: "memberCenter", title: "成员中心", group: "成员", keywords: ["成员中心","成员","把“人”和“钥匙”放在一起看"]),
            AppIndexItem(id: "memberDetail360", title: "成员 360", group: "成员", keywords: ["成员 360","成员","关于这个人","所有相关事实在一页"]),
            AppIndexItem(id: "memberFamilySettings", title: "家庭设置", group: "成员", keywords: ["家庭设置","成员","这个家作为一个整体","怎么被称呼与提醒"]),
            AppIndexItem(id: "memberStacked", title: "成员叠放视图", group: "成员", keywords: ["成员叠放视图","成员","权限多起来后","用层叠看清谁能做什么"]),
            AppIndexItem(id: "members", title: "家人与访客", group: "成员", keywords: ["家人与访客","成员","谁能进这个家","各自有什么权限"]),
            AppIndexItem(id: "memberWizard", title: "添加成员", group: "成员", keywords: ["添加成员","成员","不要在添加时就要求一串技术决定"]),
            AppIndexItem(id: "mergeMembers", title: "合并成员", group: "成员", keywords: ["合并成员","成员","同一个人被录了两次","要能收拢"]),
            AppIndexItem(id: "unclaimedClaim", title: "认领指纹", group: "成员", keywords: ["认领指纹","成员","有人录了指纹但没说是谁","需要认领"]),
        ]),
        AppIndexGroup(name: "记录", items: [
            AppIndexItem(id: "alarmCenter", title: "告警中心", group: "记录", keywords: ["告警中心","记录","真正需要注意的事","不该混在流水里"]),
            AppIndexItem(id: "exportCenter", title: "导出中心", group: "记录", keywords: ["导出中心","记录","把记录带走","用于报修或留档"]),
            AppIndexItem(id: "gratitude", title: "感谢与致谢", group: "记录", keywords: ["感谢与致谢","记录","把人和事的来处写清楚"]),
            AppIndexItem(id: "recordsSampleGuide", title: "记录样例说明", group: "记录", keywords: ["记录样例说明","记录","没有记录时","解释记录会长什么样"]),
            AppIndexItem(id: "records", title: "记录", group: "记录", keywords: ["记录","发生过什么：时间","谁","结果"]),
            AppIndexItem(id: "stats", title: "统计", group: "记录", keywords: ["统计","记录","用趋势回答“这个月正常吗”"]),
            AppIndexItem(id: "yearReport", title: "年度报告", group: "记录", keywords: ["年度报告","记录","一年结束","给自己看的一页总结"]),
        ]),
        AppIndexGroup(name: "安全", items: [
            AppIndexItem(id: "accessibility", title: "无障碍", group: "安全", keywords: ["无障碍","安全","每个人都能开门","包括看不清","听不见"]),
            AppIndexItem(id: "butlerCertificate", title: "管家证书", group: "安全", keywords: ["管家证书","安全","长期帮忙的人需要稳定授权","也要能随时收回"]),
            AppIndexItem(id: "defend", title: "尾随防护", group: "安全", keywords: ["尾随防护","安全","有人跟着进门时","给自己一个提醒"]),
            AppIndexItem(id: "houseCleaningPreset", title: "保洁预设", group: "安全", keywords: ["保洁预设","安全","给保洁开门","不该给一把长期钥匙"]),
            AppIndexItem(id: "safemodeIntro", title: "安全模式说明", group: "安全", keywords: ["安全模式说明","安全","出了问题时","App 会怎么保护你"]),
            AppIndexItem(id: "securityAudit", title: "安全审计", group: "安全", keywords: ["安全审计","安全","把“感觉安全”换成可核对的事实"]),
            AppIndexItem(id: "securityCenter", title: "安全中心", group: "安全", keywords: ["安全中心","安全","这个家现在的安全状态","以及下一步做什么"]),
            AppIndexItem(id: "securityDestroy", title: "远程销毁", group: "安全", keywords: ["远程销毁","安全","最坏情况下","把本机凭证清干净"]),
            AppIndexItem(id: "securityPeek", title: "防偷窥", group: "安全", keywords: ["防偷窥","安全","在公共场合输入密码时","别让旁人看到"]),
            AppIndexItem(id: "tailgate", title: "门未关提醒", group: "安全", keywords: ["门未关提醒","安全","门没关严","是这个家最常见的风险"]),
        ]),
        AppIndexGroup(name: "数据", items: [
            AppIndexItem(id: "backupStudio", title: "备份工作台", group: "数据", keywords: ["备份工作台","数据","备份不是一次按钮","是一份可验证的包"]),
            AppIndexItem(id: "backup", title: "备份与恢复", group: "数据", keywords: ["备份与恢复","数据","换手机","丢手机时","钥匙不能丢"]),
            AppIndexItem(id: "exportWizard", title: "导出向导", group: "数据", keywords: ["导出向导","数据","把数据交出去时","范围要说清楚"]),
            AppIndexItem(id: "localFiles", title: "本机文件", group: "数据", keywords: ["本机文件","数据","文件都在哪","占了多少空间"]),
            AppIndexItem(id: "messages", title: "消息", group: "数据", keywords: ["消息","数据","App 想告诉你的非紧急事项"]),
            AppIndexItem(id: "migrationWizard", title: "换机向导", group: "数据", keywords: ["换机向导","数据","换手机时","按步骤走不会漏"]),
            AppIndexItem(id: "restoreWizard", title: "恢复向导", group: "数据", keywords: ["恢复向导","数据","恢复是破坏性动作","必须先看清会覆盖什么"]),
            AppIndexItem(id: "webDAVStudio", title: "WebDAV 备份", group: "数据", keywords: ["WebDAV 备份","数据","不想用第三方云","就把包放到自己的盘"]),
        ]),
        AppIndexGroup(name: "关怀", items: [
            AppIndexItem(id: "achievements", title: "成就", group: "关怀", keywords: ["成就","关怀","长期使用需要一点正反馈","但不喧宾夺主"]),
            AppIndexItem(id: "batterySwapGuide", title: "换电池指南", group: "关怀", keywords: ["换电池指南","关怀","用户第一次换电池时","不该靠猜"]),
            AppIndexItem(id: "capsuleCompose", title: "胶囊编辑", group: "关怀", keywords: ["胶囊编辑","关怀","把此刻的心情留在 App 里"]),
            AppIndexItem(id: "careReminders", title: "关怀提醒", group: "关怀", keywords: ["关怀提醒","关怀","技术之外","家人之间的小事"]),
            AppIndexItem(id: "changeBatch", title: "更新批次", group: "关怀", keywords: ["更新批次","关怀","用户要知道升级带来了什么","而不是看提交记录"]),
            AppIndexItem(id: "changelog", title: "更新日志", group: "关怀", keywords: ["更新日志","关怀","完整的历史","供排查与回溯"]),
            AppIndexItem(id: "demoLabs", title: "实验室", group: "关怀", keywords: ["实验室","关怀","把试验功能收在一处","默认关闭"]),
            AppIndexItem(id: "integrationCenter", title: "集成", group: "关怀", keywords: ["集成","关怀","把开锁接进系统能力","而不是再造一个入口"]),
            AppIndexItem(id: "maintenance", title: "保养", group: "关怀", keywords: ["保养","关怀","锁也需要被照顾","尤其是电池与锁芯"]),
            AppIndexItem(id: "maintSettings", title: "保养设置", group: "关怀", keywords: ["保养设置","关怀","不同家庭的节奏不同"]),
        ]),
        AppIndexGroup(name: "诊断", items: [
            AppIndexItem(id: "diagnostics", title: "诊断", group: "诊断", keywords: ["诊断","出问题时","先看事实","不看猜测"]),
            AppIndexItem(id: "diagReference", title: "协议参考", group: "诊断", keywords: ["协议参考","诊断","排查时要能对照协议","而不是背"]),
            AppIndexItem(id: "symptomGuide", title: "症状指南", group: "诊断", keywords: ["症状指南","诊断","用户描述的是现象","不是错误码"]),
        ]),
        AppIndexGroup(name: "设置", items: [
            AppIndexItem(id: "settings", title: "设置", group: "设置", keywords: ["设置","这把锁怎么行为：连接","数据","安全"]),
        ]),
    ]

    /// 全部条目 (扁平)。
    static var all: [AppIndexItem] { groups.flatMap(\.items) }

    /// 分组 -> Route。用于 App Index 的跳转 (本仓无统一目的地路由, 只能跳到 Tab)。
    static func route(forGroup group: String) -> Route {
        switch group {
        case "记录": return .records
        case "凭证", "成员": return .credentials
        case "安全", "数据", "诊断", "设置": return .settings
        default: return .device
        }
    }
    /// 搜索: 标题 / 分组 / 同义词任一命中。空串返回全部。
    static func search(_ term: String) -> [AppIndexGroup] {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return groups }
        return groups.compactMap { g in
            let hit = g.items.filter { it in
                it.title.lowercased().contains(t)
                    || it.group.lowercased().contains(t)
                    || it.keywords.contains { $0.lowercased().contains(t) }
            }
            return hit.isEmpty ? nil : AppIndexGroup(name: g.name, items: hit)
        }
    }
}
