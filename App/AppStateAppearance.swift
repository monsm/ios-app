// AppState · 外观变更（主题 / 品牌色 / 密度 / 圆角 / 行高 / 时间线间距 / 主控卡指标 / 动效档 / 最近开门条数 / 自定义强调色 / 恢复默认）
// 2026-10-29 从 LockKeeperApp.swift（1138 行）拆出。
import SwiftUI

extension AppState {
    // ---------- 外观变更 (包16: idea 21/30/31/202/910) ----------
    // 21 主题切换 crossfade: 统一入口 = 写存储键 → withAnimation 播 crossfade → 种子驱动 RootView .id 重建
    private func applyAppearance(_ mutate: () -> Void) {
        mutate()
        withAnimation(DS.Motion.soft) { appearanceSeed &+= 1 }
    }
    /// 外观模式: ""/light/dark/black
    func setTheme(_ key: String) {
        applyAppearance {
            DB.store.set("kf_theme", key)
            themeSeed = key
        }
    }
    /// 品牌主题: indigo/forest/amber
    func setAccent(_ key: String) {
        applyAppearance { DB.store.set("kf_accent", key) }
    }
    /// 布局密度: ""(标准)/compact/relaxed
    func setDensity(_ key: String) {
        applyAppearance { DB.store.set("kf_density", key) }
    }
    /// 900 全局圆角档位: ""(标准)/soft/plump
    func setRadius(_ key: String) {
        applyAppearance { DB.store.set("kf_radius", key) }
    }
    /// 901 凭证行高: ""(标准)/tall
    func setRowHeight(_ key: String) {
        applyAppearance { DB.store.set("kf_row_h", key) }
    }
    /// 907 时间线行距: ""(标准)/tight/loose
    func setTimelineGap(_ key: String) {
        applyAppearance { DB.store.set("kf_tl_gap", key) }
    }
    /// 909 Hero 参考指标位 (电量不参与)
    func setHeroStats(_ ids: [String]) {
        applyAppearance { DS.HeroStats.setVisible(ids) }
    }
    /// 899 动效强度: calm/standard/lively (系统"减弱动态"会在令牌层把任何档压到 calm)
    func setMotionTier(_ key: String) {
        applyAppearance { DB.store.set("kf_motion", key) }
    }
    /// 最近开门条数 (idea 910): 3/5/10
    func setRecentCount(_ n: Int) {
        applyAppearance { DB.store.set("kf_recent_count", n) }
    }
    /// 包1 开锁偏好 (76 提示音 / 62 围栏 / 249 圆盘尺寸 / 按住确认 / 自动重试):
    /// 区分两类 —— 参与布局/外观求值的走整树重建 (让圆盘/密度即时生效)，纯行为类只发轻量信号。
    ///
    /// 2026-10-14 修"设置页拨开关就跳回顶部": 旧实现**一律**走 applyAppearance ⇒ 每次拨开关都给
    /// `.id(app.appearanceSeed)` 换身份，整棵子树被销毁重建 (该语义见 rootCore 与 390 那条注释)：
    ///   · 设置页 List 的滚动位置直接回到顶部 (UITableView 的 contentOffset 随视图树一起销毁);
    ///   · `.task` 整段重放、coldStartScan 再起一轮、onLaunch 再跑一遍 (390 那条已用 launchBootstrapped 兜住)。
    /// 而这批键没有一处参与配色/密度/圆角/行高/动效求值 (逐个 grep 过读取点: 全在"用时求值" ——
    /// 开锁流程 / 提示音播放 / 通知排程 / 语音播报)，根本不需要整树重建。
    /// 改为只 bump `prefSeed`：视图体照常重算 ⇒ Toggle 的 get 重读 ⇒ 视觉翻转，
    /// 而**视图身份不变** ⇒ 滚动位置、键盘焦点、动画上下文全部保留。
    static let behaviorKeys: Set<String> = [
        "kf_hold_confirm", "kf_fence", "kf_tap_direct",
        "kf_auto_retry",
        // 2026-10-15 走查 §7.4-10: 无障碍那批键此前全部走 applyAppearance ⇒ 换身份 ⇒ 整树重建
        // = **拨一次开关被弹回设置页顶部**。并入条件是逐键查出来的：**全部**读取点都必须落在
        // "会因 AppState 的 @Published 变化而重算 body"的位置。
        //   · 根上 `.dynamicTypeSize(...)` 挂在 `.id(app.appearanceSeed)` **之外**、RootView.body 之内，
        //     而 RootView 观察 app ⇒ prefSeed 一样让它们重算，"根层修饰符"不构成否决；
        //   · UnlockDial 自己不观察 app，但 `kf_hold_confirm` / `kf_fence` 早就在里面以同一形状
        //     （计算属性喂 body）被读 ⇒ `kf_dial_size` / `kf_gesture_mode` / `kf_ax_hold` 同一条级联。
        //
        // 2026-10-26 精简：原名单里 8 枚键连同它们的读取属性与消费代码一起删除（无写点 ⇒ 恒默认值），
        // 因此从本名单移除：kf_ax_captions / kf_ax_doublehaptic / kf_ax_gray / kf_onehand /
        // kf_font_scale / kf_form_bottom / kf_lefty / kf_vo_announce。
        "kf_ax_bigotp", "kf_ax_bigpreview", "kf_ax_hold", "kf_bigtile",
        "kf_dial_size", "kf_gesture_mode"
    ]
    func setUnlockOption(_ key: String, _ v: Any) {
        DB.store.set(key, v)
        if Self.behaviorKeys.contains(key) { prefSeed &+= 1 }
        else { applyAppearance {} }
    }
    /// 894 恢复带外观段的备份后重取外观。
    /// 为什么必须由 UI 层显式调：themeSeed / appearanceSeed 是 AppState 的内存镜像，
    /// 备份导入走的是 Store 落盘，不会自动改这两个值 —— 不刷就会"包里是深色、屏幕还是浅色"，
    /// 要等冷启动才生效 (那就是"恢复了但看着没恢复"的那类投诉)。
    func reloadAppearance() {
        themeSeed = DB.store.getString("kf_theme")
        applyAppearance {}
    }
    /// 905/1047 快捷格池子或"常用排前"变了：只需要重建一次树让新次序生效，
    /// 不涉及配色，所以走同一条外观通道 (它本来就是"重建全树"的通道，名字里的 appearance 是历史包袱)。
    func bumpAppearanceForLayout() { applyAppearance {} }
    /// 892 自定义强调色 (0 = 取消, 回到六套预设)。走外观通道：Palette.themed 是在 UIColor provider 里读的，
    /// 不重建树的话"选了色但界面不动"，要等下一次冷启动才生效。
    func setCustomAccent(_ hex: UInt32) {
        applyAppearance { DS.CustomAccent.set(hex) }
    }
    /// 恢复默认外观 (idea 202): 只重置外观偏好, 不触碰任何门锁数据。
    /// 清单必须与"外观"节里出现的键一一对应 —— 包16 加圆角/高对比时这里同步补上。
    /// (902 数字字体在役: kf_digit_font 只圈定 MetricTile/HeroStat 两处落点 (DesignSystem.digitDesign),
    ///  不是全 App 总闸 —— 原版 §84 那种总闸才要动 58 处散点, 撤的是它; 这一档是后来按实圈定重做的。
    ///  键在役, 就必须进这张重置清单, 否则"恢复默认"会漏掉它, 而确认弹窗写的是"将外观重置为默认值"。)
    func resetAppearance() {
        applyAppearance {
            DB.store.set("kf_theme", "")
            DB.store.remove("kf_accent")
            DB.store.remove("kf_density")
            DB.store.remove("kf_radius")
            DB.store.remove("kf_hc")
            DB.store.remove("kf_week_start")
            DB.store.remove("kf_row_h")
            DB.store.remove("kf_tl_gap")
            DB.store.remove("kf_hero_stats")
            DB.store.remove("kf_accent_custom")   // 892
            DB.store.remove("kf_hero_tex")
            // kf_motion 的默认档是 "standard"，remove 就等于回到默认 (不是关掉动效)
            DB.store.remove("kf_motion")
            DB.store.remove("kf_digit_font")   // 902
            themeSeed = ""
        }
    }

    /// 启动结算: 异常退出卡(758) / 保留期到期卡(752) / 自动归档(223) / 关怀与凭证巡检 / 启动自检与月度备份排程
}
