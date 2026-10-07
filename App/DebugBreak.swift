#if DEBUG
// break-ui 原则: 改数据不改组件 — 从数据边界注入一份"最坏数据集",
// 让同一份数据同时打穿多行 (超长名 / 尾部差异值 / 无时间日志 / 存量 -1 / 告警行),
// 用来检验布局与截断是否崩。仅 DEBUG 可用, 带一键清除, 绝不进 Release。
import Foundation

enum BreakFixture {
    static let mac = "DEADBEEF0001"
    // 成员名带固定标记, clear() 好精准清掉, 不连累真实成员
    static let memberName = "【最坏数据】Đặng Thị Ngọc Hân (财务·first.last+billing-notifications@example.com)"

    /// 注入一台最坏数据门锁: 名字极长、固件未知、一条无时间戳日志 + 一条告警日志、
    /// 一条带超长备注的密码、一个尾部差异巨大的成员名。
    static func seed() {
        let kc = Keychain(mac: mac,
                           pid: 0,
                           pidName: "",
                           name: "Aleksandra Wiśniewska-Kowalczyk 的入户门锁",
                           skey: "0000", bkey: "0000",
                           fw: "", pairedAt: "")
        DB.saveKeychain(kc)

        _ = DB.addMember(memberName)

        var led = Ledger()
        led.pwds = [LedgerPwd(alias: 1,
                              from: "2010-01-01 00:00:00",
                              to: "2118-01-01 00:00:00",
                              temp: false,
                              at: 0,
                              pwd: "123456",
                              owner: nil,
                              note: "这串备注故意写得很长, 用来检验换行会不会撑爆列表行高度 一二三四五六七八九十 一二三四五六七八九十 一二三四五六七八九十")]
        DB.saveLedger(mac, led)

        DB.writeLogs(mac, [
            // 无时间戳 + 告警类型: 时间轴要能容得下空时间且用形状标出告警
            LogEntry(type: 7, typeName: "防拆告警(门体未关好)", idx: 0, idxRaw: 0,
                     lockTime: 0, lockTimeStr: "", body: ""),
            LogEntry(type: 1, typeName: "密码开门", idx: 0, idxRaw: 1,
                     lockTime: 0, lockTimeStr: "2026-10-06 08:12:00", body: "")
        ])
    }

    static func isSeeded() -> Bool {
        DB.keychains().contains { $0.mac == mac }
    }

    static func clear() {
        DB.removeDevice(mac)
        if let m = DB.members().first(where: { $0.name == memberName }) {
            DB.removeMember(m.id)
        }
    }
}
#endif