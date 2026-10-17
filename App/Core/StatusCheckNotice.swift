// 963 每晚状态确认提醒 — 本地通知 (全离线，不走推送)
//
// 与 1031 夜间免扰的冲突是**结构性的**：免扰时段是 22–08 (CareSchedule.isQuietHour)，
// 而"每晚十点确认一下"正想落在 22:00。这里不假装两者相容，只给三条能兑现的口径：
//   ① 开着免扰且选的时点落在免扰段内 → **根本不排**这条 (排了就会在用户说自己安静的时间里响)；
//   ② App 在前台时由既有 willPresent 闸门 (BackupStudioKit.swift:1493) 再挡一次；
//   ③ 关掉免扰才真能在 22:00 收到 —— 设置页把这句说明白，不留一个看起来在工作的开关。
// 默认关 (拍板口径)：一条每天定时弹的通知，不开就永远不响，开了才生效。
import UserNotifications

nonisolated enum StatusCheckNotice {
    static let notifID = "kf.status.checkin"

    static var on: Bool { DB.store.getBool("kf_status_checkin") }        // 默认关
    /// 时点只认这三档，别的值一律回落到 22:00 (键被老版本或导入写成垃圾时不能排出一条怪时间的通知)
    static var hour: Int {
        let v = DB.store.getInt("kf_status_checkin_hour", 22)
        return [20, 21, 22].contains(v) ? v : 22
    }

    /// 该时点是否落在 1031 免扰段 (22–08) 内
    static func insideQuiet(_ h: Int) -> Bool { h >= 22 || h < 8 }

    /// 按当前开关重排。启动时、开关改动时、免扰改动时都调它。
    /// 排期是"整条替换"语义：先撤旧的再按新条件决定，避免关掉开关后通知还在第二天弹。
    /// 返回值给 UI 用：true = 这条**真的排上了**；false = 没排 (关着 / 没锁 / 被免扰挡下)。
    /// 不返回这一位，设置页就只能说一句"已排期"—— 而那正是它没做到的事。
    @discardableResult
    static func sync() -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notifID])
        guard on else { return false }
        guard !DB.keychains().isEmpty else { return false }   // 一台锁都没有就没什么可确认的
        if CareSchedule.quietOn && insideQuiet(hour) { return false }  // 免扰优先，不排 (口径见文件头)
        var comp = DateComponents()
        comp.hour = hour
        comp.minute = 0
        let c = UNMutableNotificationContent()
        c.title = "确认一下门锁状态"
        c.body = bodyText()
        c.sound = .default
        // 点按落点由 BackupStudioKit 的 didReceive 分派 (与月度备份/保养族同一条口)。
        // 用带 completionHandler 的那一形而不是 async 版: sync() 要从 UI 的 setter 里直接调,
        // 为一枚开关铺一层 Task 只会让"点了就排上"这件事多一个失败面。
        center.add(UNNotificationRequest(identifier: notifID, content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comp,
                                                                                repeats: true)),
                   withCompletionHandler: nil)
        return true
    }

    /// 正文只用台账里数得出来的数：锁数 + 今天真正连上过几把。
    /// 写"读数是本机缓存"是因为这条通知不联网、不连锁，它不可能知道此刻锁的真实状态。
    private static func bodyText() -> String {
        let locks = DB.keychains()
        let today = StatsKit.dayKey(Date())
        let touched = locks.filter {
            let at = LockArchive.meta($0.mac).lastConnectedAt
            return at > 0 && StatsKit.dayKey(Date(timeIntervalSince1970: at)) == today
        }.count
        if touched == 0 {
            return "台账里 \(locks.count) 把锁，今天还没连上过。到场打开设备页看一眼 (读数是本机缓存，不是实时)。"
        }
        return "台账里 \(locks.count) 把锁，今天连上过 \(touched) 把。打开设备页核对状态 (读数是本机缓存，不是实时)。"
    }

    /// 授权：沿用 CareSchedule 那一份请求 (同一个系统弹窗不该请求两次)
    static func requestAuthAndSync() async {
        guard on else { sync(); return }
        if await CareSchedule.requestAuth() { sync() }
    }
}
