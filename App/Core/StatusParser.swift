// 03 状态 / 16 日志 响应解析 — JS utils/status.js 移植
//   03 KLV: 01=sKeyStatus 03=rc 04=lockTime 05=zotpPeriod 06=keyboardFreeze 07=keyboardErrCount
//           08=securityLevel 11=powerLevel 14=soundVolumn 21..29=容量族 31..35=版本族
//   16 日志: rc@03, surplus@04, 每条 KLV#05 = [type 1B][len 1B][idx 4B LE][lockTime 4B LE]...
// 差分基准: golden.parse.*
import Foundation

struct LockStatus {
    var rc: Int = -1
    var sKeyStatus: Int = -1
    var powerLevel: Int = -1
    var lockTime: Int64? = nil
    var pid: Int = 0
    var pidName: String = "未知"
    var firmware: String = ""
    var keyboardFreeze: Int = 0
    var keyboardErrCount: Int = 0
    var securityLevel: Int = 0
    var verifyMode: Int = 0
    var broadcastMode: Int = 0
    var tempPwdMode: Int = 0
    var zotpPeriod: Int = 0
    var soundVolumn: Int = 0
    var pinInfoCapacity: Int = 0, pinStock: Int = 0, pinInfoBinding: Int = 0
    var pwdInfoCapacity: Int = 0, pwdStock: Int = 0, pwdInfoMaxLen: Int = 0
    var fpInfoCapacity: Int = 0, fpStock: Int = 0, fpInfoBatchNumber: Int = 0
    var verDFU: Int = 0
    var verKeyboard: Int = 0
    var eCtrlVer: String = ""
}

struct LogEntry {
    var type: Int
    var typeName: String
    var idx: UInt32
    var idxRaw: UInt32
    var lockTime: Int64
    var lockTimeStr: String
    var body: String
}

enum StatusParser {
    static func intHex(_ val: String) -> Int { Int(val.isEmpty ? "0" : val, radix: 16) ?? 0 }
    static func leHexToU32(_ val: String) -> UInt32 {
        let b = HexKit.bytes(val)
        var v: UInt32 = 0
        for i in stride(from: b.count - 1, through: 0, by: -1) { v = v &* 256 &+ UInt32(b[i]) }
        return v
    }

    static func parseStatus(_ klvs: [ZKLV]) -> LockStatus {
        var s = LockStatus()
        for k in klvs {
            let vlen = k.vlen
            switch k.key {
            case 0x04: // lockTime 4B LE 协议秒
                // JS: leHexToU32(...) || null — 上报 0 视为无效, 否则校时会把锁钟写成 2010
                let lt = leHexToU32(k.val)
                s.lockTime = lt == 0 ? nil : Int64(lt)
            case 0x03:
                s.rc = intHex(k.val)
            case 0x01:
                s.sKeyStatus = intHex(k.val)
            case 0x05: // zotpPeriod u16 LE
                s.zotpPeriod = vlen >= 2 ? Int(leHexToU32(k.val)) : intHex(k.val)
            case 0x06:
                s.keyboardFreeze = intHex(k.val)
            case 0x07:
                s.keyboardErrCount = intHex(k.val)
            case 0x08: // bit0=verifyMode bit1=broadcastMode bit2=tempPwdMode
                s.securityLevel = intHex(k.val)
                s.verifyMode = s.securityLevel & 0x01
                s.broadcastMode = (s.securityLevel >> 1) & 0x01
                s.tempPwdMode = (s.securityLevel >> 2) & 0x01
            case 0x11:
                s.powerLevel = intHex(k.val)
            case 0x14:
                s.soundVolumn = intHex(k.val)
            case 0x21: s.pinInfoCapacity = intHex(k.val)
            case 0x22: s.pinStock = intHex(k.val)
            case 0x23: s.pinInfoBinding = intHex(k.val)
            case 0x24: s.pwdInfoCapacity = intHex(k.val)
            case 0x25: s.pwdStock = intHex(k.val)
            case 0x26: s.pwdInfoMaxLen = intHex(k.val)
            case 0x27: s.fpInfoCapacity = intHex(k.val)
            case 0x28: s.fpStock = intHex(k.val)
            case 0x29: s.fpInfoBatchNumber = intHex(k.val)
            case 0x31: // 固件 3B: 反转后直读 p0.p1.p2
                let o = HexKit.reversePairs(k.val)
                if vlen == 3 && o.count == 6 {
                    let p0 = Int(o.prefix(2), radix: 16) ?? 0
                    let p1 = Int(o.dropFirst(2).prefix(2), radix: 16) ?? 0
                    let p2 = Int(o.dropFirst(4).prefix(2), radix: 16) ?? 0
                    s.firmware = "\(p2).\(p1).\(p0)"
                }
            case 0x32:
                s.verDFU = intHex(k.val)
            case 0x33:
                s.verKeyboard = vlen >= 2 ? Int(leHexToU32(k.val)) : intHex(k.val)
            case 0x34:
                s.pid = Int(leHexToU32(k.val))
                s.pidName = PidMap.modelName(s.pid)
            case 0x35: // ASCII
                if vlen > 0 {
                    var t = ""
                    for x in HexKit.bytes(k.val) { t.append(Character(UnicodeScalar(x))) }
                    s.eCtrlVer = t
                }
            default:
                break
            }
        }
        return s
    }

    // 日志类型 (App Rn 枚举; main.js resultCode 表)
    static let logTypes: [Int: String] = [
        1: "数字钥匙开门", 2: "密码开门", 3: "指纹开门", 4: "临时密码开门", 5: "NFC开门",
        6: "电量低", 7: "撬锁", 8: "重新上电", 9: "DFU 后版本", 10: "多次密码失败锁定",
        12: "授时", 13: "指纹告警", 14: "同步PIN", 15: "同步密码",
        20: "添加指纹", 21: "删除指纹", 22: "设置安全级别", 23: "状态广播开关",
        24: "设置单双验", 25: "开通临时密码", 26: "设置音量", 27: "设置beacom密钥", 224: "键盘被锁定"
    ]
    static func parseLogEntry(_ hex: String) -> LogEntry? {
        guard hex.count >= 20 else { return nil }
        let b = HexKit.bytes(hex)
        let type = Int(b[0])
        let idx = leHexToU32(String(hex.dropFirst(4).prefix(8)))
        let lockTime = Int64(leHexToU32(String(hex.dropFirst(12).prefix(8))))
        return LogEntry(type: type,
                        typeName: logTypes[type] ?? ("未知(\(type))"),
                        idx: idx, idxRaw: idx,
                        lockTime: lockTime,
                        lockTimeStr: lockTime != 0 ? ProtoTime.localStr(lockTime) : "",
                        body: String(hex.dropFirst(20)))
    }
    static func parseLogs(_ klvs: [ZKLV]) -> [LogEntry] {
        klvs.filter { $0.key == 0x05 }.compactMap { parseLogEntry($0.val) }
    }

    // 锁端返回码文案 (JS lock.js RC_MSG, 与 App resultCodeToMessage 一致)
    static let rcMsg: [Int: String] = [
        0: "成功", 1: "解密失败", 2: "无效的PIN码", 3: "命令过期", 5: "次数使用完毕",
        6: "开锁指令已绑定其他设备", 7: "执行的操作不在指定的状态", 8: "溢出", 9: "时间误差过大",
        10: "未知错误", 11: "解密失败", 12: "mac地址不正确", 13: "通讯过期", 14: "不支持的秘钥交换方式",
        15: "未知协议", 16: "参数不在范围内", 17: "丢包", 18: "不能设置重复的值", 19: "找不到指定的值",
        20: "指纹传感器错误", 21: "门锁处于反锁状态", 22: "不能重复验证", 23: "无法获取有效的指纹图片",
        24: "录入指纹超时", 25: "锁正忙，请稍后重试", 26: "门锁被撬", 27: "您的门锁处于布防状态"
    ]
    static func rcMessage(_ rc: Int) -> String { rcMsg[rc] ?? ("错误码 \(rc)") }

    // idea 84 (包1): 高频失败码的人话直读 — rcMessage 回答"是什么", 这里补"该怎么办"。
    // 纯文案层映射, 不新增/不改动任何协议命令; 未命中的码回落 rcMessage。
    static func rcHint(_ rc: Int) -> String? {
        switch rc {
        case 1, 11: return "通讯受干扰, 请靠近门锁再试一次"
        case 3: return "指令已过期, 多为锁内时钟不准 — 先到快捷操作校准时间再试"
        case 5: return "这条凭证的使用次数已用完, 请换一条或重新添加"
        case 6: return "这条开锁凭证已绑定到别的设备, 请重新下发凭证"
        case 9: return "锁内时间与手机偏差过大 — 先校准时间再试"
        case 21: return "门从里面反锁了, 先解除反锁再试"
        case 25: return "锁正忙 (可能刚有人操作过), 等两秒再试"
        case 27: return "门锁处于布防状态, 请先解除布防再开锁"
        default: return nil
        }
    }
    static func rcFriendly(_ rc: Int) -> String { rcHint(rc) ?? rcMessage(rc) }
}