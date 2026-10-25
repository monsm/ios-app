// 小管家形象 (841) + 成员中心「给家人开门禁」四步图文的数据源。
//
// 本文件原为 HelpCenter.swift (帮助与文案规范, 673 行): 使用手册整本 / 离线 FAQ /
// 症状排查 / 就任证书 / 演练场 / 文案体检彩蛋。这些页面已随大删波 3 移除 (用户决策:
// 「没锁交互的不影响核心功能的就剥离删掉」)。留下的两件都有真实消费方, 不是文档:
//   · DemoMascot / EmptyMascotHeader —— 空态与引导页的实际图形 (Onboarding:275、DesignSystem:1074)
//   · ManualKit.chapters —— MemberCenterView 的「四步图文」直接读 ch.family 那一章,
//     所以这张表只剩一章: 帮助手册整本删了, 但成员页仍在用它, 删表就等于删成员页的教程。
import SwiftUI

// ---------- 小管家形象 (841): SF Symbols 组合, 纯矢量贯穿全部空态 ----------
struct DemoMascot: View {
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            // 圆座: 品牌渐变玻璃
            Circle()
                .fill(DS.heroGradientSafe)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(DS.heroFg.opacity(0.25), lineWidth: 1))
            // 脸: 两个眼睛 + 微笑 (纯符号组合, 无图片资源)
            HStack(spacing: size * 0.14) {
                Circle().fill(DS.heroFg).frame(width: size * 0.09)
                Circle().fill(DS.heroFg).frame(width: size * 0.09)
            }
            .offset(y: -size * 0.06)
            Image(systemName: "lock.shield")
                .font(.system(size: size * 0.30, weight: .medium))
                .foregroundStyle(DS.heroFg.opacity(0.9))
                .offset(y: size * 0.16)
        }
        .accessibilityLabel("小管家")
        .accessibilityHidden(true)
    }
}

/// 空态统一小管家顶饰 (841): 放在各 Tab 空态图标上方形成记忆点
struct EmptyMascotHeader: View {
    var caption: String = "小管家在这"
    var body: some View {
        VStack(spacing: DS.Space.xs) {
            DemoMascot(size: 56)
            Text(caption)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
        }
        .accessibilityElement(children: .ignore)
    }
}

// ---------- 成员中心「给家人开门禁」四步 (973) ----------
// 原先整本说明书住在这里, 帮助页删掉后只留成员页真正读的那一章。
// 手表那半步做不到 (本 App 无 watch target, 协议也不能让手表替锁开门),
// 章里最后一段就把这句写在明面上 —— 做不到就说不做。
struct ManualChapter: Identifiable {
    var id: String
    var title: String
    var lines: [String]
}

enum ManualKit {
    static let chapters: [ManualChapter] = [
        ManualChapter(id: "ch.family", title: "给家人开门禁（四步）",
                      lines: ["第一步 建档：「成员中心」里加称呼与关系，需要就选角色。",   // 458/843 第一步
                              "第二步 给凭证：在 Ta 名下录指纹或密码，到场连接后下发到锁。",   // 177/306 第二步
                              "第三步 限时段：给这条密码设生效与到期；给访客用临时码，到点自动作废。",   // 520/806 第三步
                              "第四步 收回：停用凭证或把人归档；锁端的删除要连接执行，本机台账同步标记。",   // 353/460 第四步
                              "关于手表：本 App 没有 watch target，Apple Watch 也替不了这把锁开门 (协议与工程里都没有那条路)。"
                               + "创意原文那句「给家人配手表」在这里做不到，这一章给的是四步做得完的。"]),   // 973 创意原文那句
    ]
}
