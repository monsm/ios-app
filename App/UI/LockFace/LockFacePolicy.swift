//  LockFacePolicy.swift
//  门面入口策略: 什么时候展示门、门用什么皮肤。2026-10-18 门面改造新增。
//
//  这是纯函数层, 不持有任何状态, 便于单测与复核。
//  关键规则 (PART1 §7):
//    · 冷启动展示门; 回前台间隔 < 300s 不重演
//    · 深链 / 小组件 / Siri / AppIntents **一律不展示** (点通知还要推门 = 荒谬)
//    · 首启引导未完成不展示 (一把锁都没有的人对着一扇门会莫名其妙)
//    · 设置里 kf_start_at_door = false 时永不展示 (高级用户开关, 默认 true)

import Foundation

enum LockFacePolicy {

    /// 回前台重演门的间隔阈值 (秒)。**两端同值** —— Android 若将来做类似能力也用 300。
    static let revealAfter: TimeInterval = 300

    /// 高级用户开关: 关掉后永不展示门, 直接进主界面。
    static var startAtDoor: Bool {
        DB.store.getBool("kf_start_at_door", true)
    }

    /// 冷启动 / 回前台时是否展示门。
    /// - Parameters:
    ///   - launchedFresh: 本次是冷启动 (不是从后台回来)
    ///   - awaySeconds: 在后台待了多久 (冷启动传 nil)
    ///   - hasLocks: 本机是否至少有一把锁
    ///   - onboardingDone: 首启引导是否完成
    ///   - cameFromDeepLink: 本次是否由深链/小组件/AppIntent 唤起
    static func shouldPresent(launchedFresh: Bool,
                               awaySeconds: TimeInterval?,
                               hasLocks: Bool,
                               onboardingDone: Bool,
                               cameFromDeepLink: Bool) -> Bool {
        guard startAtDoor else { return false }
        guard hasLocks else { return false }          // 还没有锁 -> 门没有意义
        guard onboardingDone else { return false }    // 引导是全屏的, 门不参与
        guard !cameFromDeepLink else { return false } // 深链直达, 不演仪式
        if launchedFresh { return true }
        guard let away = awaySeconds else { return true }
        return away >= revealAfter
    }

    /// 读当前锁的皮肤。载体是 LockMeta (不是 LockProfile —— 那个类型不存在)。
    /// 读不到就用 .wood (默认), 不抛错: 皮肤是装饰, 缺省不该挡住开门。
    static func skin(for mac: String?) -> LockFaceSkin {
        guard let mac, !mac.isEmpty else { return .wood }
        let raw = LockArchive.meta(mac).skin
        return LockFaceSkin(rawValue: raw) ?? .wood
    }

    /// 写皮肤。走 LockArchive.save, 保留其余字段不变。
    static func setSkin(_ skin: LockFaceSkin, for mac: String) {
        var m = LockArchive.meta(mac)
        m.skin = skin.rawValue
        LockArchive.save(mac, m)
    }
}
