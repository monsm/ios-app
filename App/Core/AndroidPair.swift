// 给安卓端的「扫码即用」载荷。
//
// 只带开锁必需的三个字段: mac / pid / ekey。
// 刻意**不带 skey**: 04 开锁只需要 ekey, 01 会话令牌是明文索取 —— 带 skey 等于把整把锁的母钥
// 塞进二维码, 一旦截图外传就再也收不回来。ekey 是配网时按 PIN 签出来的开锁凭证, 丢了可以换 PIN 重签,
// 两者的失窃后果不是一个量级。
import Foundation

enum AndroidPair {
    /// 前缀只为"扫错码"时能立刻判掉, 不是安全边界 (真正的边界是 ekey 本身)。
    static let prefix = "KFA1:"

    /// 这把锁的开锁凭证: 优先用配网时签好的 ekey; 没有就按 skey+PIN 现签一次 (与 unlock() 同一条算式,
    /// 同一组默认有效期, 所以签出来的与配网那次逐字节一致)。
    static func ekey(for kc: Keychain) -> String? {
        // 2026-10-27 审核说明 (AUDIT-A F-42)：`AndroidPair.ekey` 的回退路径（ekey 为空时
        // 用 skey+pin 现签一个）与文件头「逐字节一致」的承诺不完全符 ——
        // 现签的那条路走的是 buildEkeyOpen，而 vendor 二维码通道发的是它自己的格式。
        // 实测两端都能解析（字段名匹配），但不是逐字节。要严格互操作得改格式。
        if !kc.ekey.isEmpty { return kc.ekey }
        // 2026-10-27 审核说明 (AUDIT-A F-20)：`buildEkeyOpen` 的默认 TrackId 与有效期与 vendor 一致，
        // 但本文件原先的注释声称"与 iOS 逐字节一致"—— 实际只有**默认参数相同**，
        // 而二维码通道（KFA1:）不带 trackid/有效期字段，所以安卓侧签出来的 ekey 用的是默认值。
        // 这不是 bug（vendor 的二维码通道也不带那两个字段），但注释不该说"逐字节"。
        guard let pin = kc.pins.first, !pin.isEmpty, !kc.skey.isEmpty else { return nil }
        let e = ZKCmdBuilder.buildEkeyOpen(kc.skey.lowercased(), kc.mac.lowercased(), pin)
        return e.isEmpty ? nil : e
    }

    /// 二维码正文: `KFA1:{...}`。字段名压到 1 个字母是为了让二维码稀疏一点 (手机摄像头在
    /// 暗光/斜角下更好认), 不是为了省字节。
        // 2026-10-27 审核说明 (AUDIT-A F-43)：这里用 `.sortedKeys` 序列化，
        // 而 vendor 侧**没有对应的序列化器**（它的二维码载荷是手工拼的固定字段序）。
        // 两端不逐字节一致，但都能被对方解析（字段名匹配，不依赖顺序）。
        // 若将来要严格互操作，得改成手工拼串对齐 vendor 的字段序。
    static func payload(_ kc: Keychain) -> String? {
        guard let e = ekey(for: kc) else { return nil }
        let name = kc.name.isEmpty ? LockArchive.displayName(kc) : kc.name
        let dict: [String: Any] = [
            "v": 1,
            "n": name,
            "m": kc.mac.lowercased(),
            "p": kc.pid,
            "e": e.lowercased(),
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return nil }
        return prefix + s
    }

    /// 安卓端把这张码存下来之后, 本机不再需要它 —— 但用户可能想再给第二台手机扫, 所以入口常驻。
    static func displayName(_ kc: Keychain) -> String {
        kc.name.isEmpty ? LockArchive.displayName(kc) : kc.name
    }
}
