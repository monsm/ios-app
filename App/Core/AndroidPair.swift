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
        if !kc.ekey.isEmpty { return kc.ekey }
        guard let pin = kc.pins.first, !pin.isEmpty, !kc.skey.isEmpty else { return nil }
        let e = ZKCmdBuilder.buildEkeyOpen(kc.skey.lowercased(), kc.mac.lowercased(), pin)
        return e.isEmpty ? nil : e
    }

    /// 二维码正文: `KFA1:{...}`。字段名压到 1 个字母是为了让二维码稀疏一点 (手机摄像头在
    /// 暗光/斜角下更好认), 不是为了省字节。
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
