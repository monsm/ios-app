// 包5 凭证工坊 — 四类凭证 (密码/临时码/指纹/OTP) 的添加·编辑·详情
// 收录 (按 ROADMAP 包5): 7-8/11/34/41/171-174/177-179/301/303-317/319-320/322-346/515-523
// ⚠ 降级项 (全部本地推断, 文案带"约"): 311/316/320/326/335/332/333/337; 舍弃 302/318/321 不实现。
// 纪律: 颜色只走 DS 令牌; 不新增协议命令 (178 批量走既有 0A 逐条); 新键 kf_c* 向后兼容。
import SwiftUI
import UIKit
import AVFoundation
import VisionKit
import CryptoKit
import Combine

// ================= 本地工具 (纯离线, 不碰锁端) =================
// 309 的逐位朗读原来在这里另建一台 AVSpeechSynthesizer (private `StudioTTS`)，
// 与 AppIntents 里那台各说各话 ⇒ 已收进 `App/Core/SpeechKit.swift` 的 `Speech.digits`。

enum StudioTools {
    /// 173 本地 CSPRNG 数字生成 (KeyGen 即 SecureRandom 底层)
    static func genDigits(_ n: Int) -> String { KeyGen.randomDigits(n) }
    /// 8 密码强度条: 全同位 / 顺子 / 短 → 弱 (本地推断)
    static func pwdStrength(_ v: String) -> (score: Int, hint: String) {
        guard !v.isEmpty else { return (0, "") }
        let uniq = Set(v).count
        var score = 1
        if uniq >= 4 { score += 1 }
        if v.count >= 8 { score += 1 }
        if isSequential(v) { score -= 1 }
        if uniq <= 1 { score = 0 }
        let hint = uniq <= 1 ? "全部同数字, 易被猜出" : (isSequential(v) ? "顺子 (如 123456), 建议避免" : (v.count < 6 ? "位数偏短" : "强度正常"))
        return (max(score, 0), hint)
    }
    private static func isSequential(_ v: String) -> Bool {
        let d = v.compactMap { $0.wholeNumberValue }
        guard d.count >= 4 else { return false }
        let step = d[1] - d[0]
        guard step != 0 else { return false }
        for i in 2..<d.count where d[i] - d[i - 1] != step { return false }
        return true
    }
    /// 329 一句话口令文本: "密码是 XXXX，明天 18:00 下午前有效（锁名）"
    static func oneLine(p: LedgerPwd, lockName: String, value: String?) -> String {
        let v = value ?? "****"
        guard let to = CredentialOrg.expiryDate(p) else {
            return "密码是 \(v)，长期有效（\(lockName)）"
        }
        let c = WeekCal.gregorian
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let hm = tf.string(from: to)
        let dayTxt = c.isDateInTomorrow(to) ? "明天" : (c.isDateInToday(to) ? "今天" : mdy(to))
        let tail = hm.hasPrefix("12") || hm.hasPrefix("13") || hm.hasPrefix("14") || hm.hasPrefix("15") || hm.hasPrefix("16") || hm.hasPrefix("17") || hm.hasPrefix("18") ? "下午前有效" : "前有效"
        return "密码是 \(v)，\(dayTxt) \(hm) \(tail)（\(lockName)）"
    }
    static func mdy(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M月d日"
        return f.string(from: d)
    }
    /// 341 解析失败的真实缺失点。旧写法把「空 / 协议头不对 / 不是 totp / 缺 secret / Base32 非法」
    /// 五种情况压成同一句解析失败, 用户照着那句话补全等于瞎猜 —— 现在失败原因就是**真缺的那一样**。
    enum OtpFail: String, Error {
        case blank = "粘贴框是空的"
        case scheme = "不是 otpauth:// 开头"
        case host = "协议头里的类型不是 totp (本 App 只按时间窗算码, 不认 HOTP)"
        case secret = "缺 secret 参数"
        case base32 = "secret 不是合法 Base32: 只允许 A-Z 与 2-7 (0/1/8/9 不在这个字母表里)"
    }
    /// 341 otpauth://totp 解析 (纯本地; 不联网、不落库, 落库仍走 CredentialOrg.addTotp)。
    /// 缺省补的是 RFC 6238 的默认档 (SHA1 · 30 秒 · 6 位) 与名称回退, **每一项都记进 defaulted**
    /// 交调用方在成功提示里原样透出 —— 补了值却不吭声, 就等于替用户改了他没写的那几个字段。
    static func parseOtpAuth(_ uri: String) -> Result<(name: String, secret: String, algo: String,
                                                       period: Int, digits: Int, defaulted: [String]), OtpFail> {
        let s = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .failure(.blank) }
        guard let u = URL(string: s) else { return .failure(.scheme) }
        guard u.scheme?.lowercased() == "otpauth" else { return .failure(.scheme) }
        guard u.host?.lowercased() == "totp" else { return .failure(.host) }
        var secret = "", name = "", algo = "", periodS = "", digitsS = ""
        for pair in (u.query ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch String(kv[0]).lowercased() {
            case "secret": secret = String(kv[1])
            case "issuer", "label": if name.isEmpty { name = String(kv[1]) }
            case "algorithm": algo = String(kv[1]).uppercased()
            case "period": periodS = String(kv[1])
            case "digits": digitsS = String(kv[1])
            default: break
            }
        }
        guard !secret.isEmpty else { return .failure(.secret) }
        guard base32Decode(secret) != nil else { return .failure(.base32) }
        var defaulted: [String] = []
        // 名称: 真实 uri 的账户名在**路径段** (otpauth://totp/张三?secret=…), 旧写法只读 issuer/label
        // 两个查询参数 ⇒ 大多数链接的名称会静默空掉。现在路径段 → issuer → 占位, 走到占位才记 defaulted。
        if name.isEmpty {
            let raw = u.path.replacingOccurrences(of: "/", with: "")
            let label = raw.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !label.isEmpty { name = label }
        }
        if name.isEmpty {
            name = fallbackName(secret)
            defaulted.append("名称按密钥尾段记作「\(name)」")
        }
        let knownAlgo = ["SHA1", "SHA256", "SHA512"]
        let algoOut = knownAlgo.contains(algo) ? algo : "SHA1"
        if algoOut == "SHA1" && !knownAlgo.contains(algo) {
            defaulted.append(algo.isEmpty ? "算法按默认 SHA1 (uri 没写 algorithm)" : "算法按默认 SHA1 (\(algo) 不在 SHA1/SHA256/SHA512 之内)")
        }
        var period = 30
        if let v = Int(periodS), v > 0 { period = v }
        else { defaulted.append(periodS.isEmpty ? "周期按默认 30 秒 (uri 没写 period)" : "周期按默认 30 秒 (period=\(periodS) 读不出正整数)") }
        var digits = 6
        if let v = Int(digitsS), v > 0, v <= 8 { digits = v }
        else { defaulted.append(digitsS.isEmpty ? "位数按默认 6 (uri 没写 digits)" : "位数按默认 6 (digits=\(digitsS) 不在 1~8)") }
        return .success((name, secret, algoOut, period, digits, defaulted))
    }
    /// 341 名称缺失时的回退名: 取密钥尾 4 位, 让列表里两条不至于都叫同一个占位名。
    static func fallbackName(_ secret: String) -> String {
        let clean = secret.uppercased().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: " ", with: "")
        return "口令·" + String(clean.suffix(4))
    }
    /// Base32 → 原始字节 (otpauth secret 约定)
    static func base32Decode(_ s: String) -> [UInt8]? {
        let alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let clean = s.uppercased().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: " ", with: "")
        guard !clean.isEmpty else { return nil }
        var bits = 0, value = 0
        var out: [UInt8] = []
        for ch in clean {
            guard let idx = alpha.firstIndex(of: ch) else { return nil }
            value = (value << 5) | Int(alpha.distance(from: alpha.startIndex, to: idx))
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return out
    }
    /// 343/337 独立 TOTP (HMAC-SHA1/256/512 动态截断; 锁端 ZOTP 仍走 ZOTP.generate 分钟级)
    static func totp(_ e: CredentialOrg.TOTPEntry, offset: Int) -> String {
        guard let data = base32Decode(e.secret) else { return "" }
        let per = e.period > 0 ? e.period : 30
        let counter = UInt64(max(0, Int(Date().timeIntervalSince1970) / per + offset))
        var bytes = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 { bytes[7 - i] = UInt8((counter >> (8 * i)) & 0xFF) }
        let key = SymmetricKey(data: data)
        let mac: Data
        switch e.algo.uppercased() {
        case "SHA256": mac = Data(HMAC<SHA256>.authenticationCode(for: Data(bytes), using: key))
        case "SHA512": mac = Data(HMAC<SHA512>.authenticationCode(for: Data(bytes), using: key))
        default: mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(bytes), using: key))
        }
        let off = Int(mac.last ?? 0) & 0x0F
        guard off + 4 < mac.count else { return "" }
        let bin = (Int(mac[off]) & 0x7F) << 24 | Int(mac[off + 1]) << 16 | Int(mac[off + 2]) << 8 | Int(mac[off + 3])
        // 2026-10-15 走查: `e.digits` 是落库/备份里的字段, 解码时没有任何人校验过它 ——
        // 而下一行的 `Int(pow(10, n))` 在 n ≥ 19 时会超出 Int64, `Int(Double)` 对超范围值
        // 是**直接 trap 崩进程** (不是返回 nil)。界面上只给 6/8, 但备份文件是外部输入,
        // 不能靠"上游一定写的是 6 或 8"来保命。这里按 TOTP 的实际上限夹一刀, 原语义 (>0 取原值,
        // 否则回默认 6) 一个字不改。
        let raw = e.digits > 0 ? e.digits : 6
        let n = min(raw, 8)
        return String(format: "%0\(n)d", bin % Int(pow(10, Double(n))))
    }
    struct SceneDef: Identifiable {
        let key: String
        let name: String
        let hint: String
        let hours: Int
        let note: String
        var id: String { key }
    }
    /// 325 五场景预设: 选中即套默认时长与备注占位 (179)
    static let scenes: [SceneDef] = [
        SceneDef(key: "move", name: "搬家", hint: "1 天 · 单张", hours: 24, note: "搬家公司·大门·当天"),
        SceneDef(key: "repair", name: "维修", hint: "半天 · 含复查", hours: 6, note: "维修师傅·待修项·半天"),
        SceneDef(key: "cleaning", name: "家政", hint: "4 小时 · 单场", hours: 4, note: "钟点工·上午场·4小时"),
        SceneDef(key: "guest", name: "访客", hint: "今晚 10 点前", hours: 8, note: "访客·今晚·10点前"),
        SceneDef(key: "reno", name: "装修", hint: "整月 · 长期工", hours: 720, note: "装修组·工地·整月")   // 330 装修组
    ]
}

// ================= 共享小组件 =================

/// 515 分步表单顶部进度圆点条
struct StepDots: View {
    let total: Int
    var index: Int
    var labels: [String] = []
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i <= index ? DS.Palette.accent : DS.Palette.hairline)
                    .frame(width: 7, height: 7)
            }
            Text("第 \(index + 1)/\(total) 步" + (labels.indices.contains(index) ? " · \(labels[index])" : ""))
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityLabel("表单进度 第 \(index + 1) 步, 共 \(total) 步")
    }
}

/// 370 贴近复蔽: 面部贴近听筒 (通话贴脸那套传感器) 时把已揭示的码位立刻复遮。
/// UIDevice 的 proximity 是公开 API; **只在页面在屏时开监听** (onAppear 开、onDisappear 关) ——
/// 免得在别的页面把屏幕贴脸熄掉。移开后**不自动揭开**, 要再看一次得重新点眼睛 (原句口径)。
private struct ProximityRemask: ViewModifier {
    let remask: () -> Void
    func body(content: Content) -> some View {
        content
            .onAppear { UIDevice.current.isProximityMonitoringEnabled = true }
            .onDisappear { UIDevice.current.isProximityMonitoringEnabled = false }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)) { _ in
                if UIDevice.current.proximityState { remask() }
            }
    }
}
extension View {
    func proximityRemask(_ remask: @escaping () -> Void) -> some View {
        modifier(ProximityRemask(remask: remask))
    }
}

/// 303 大号逐位回显 (默认打码, 逐位点开揭示 — 延续包7 打码语义; 11 复制按钮形变同源)
/// 38 凭证默认打码 = 本视图。2026-10-10 拍板"默认打码 + 每行独立眼形切换、不写全局偏好"——
/// 把默认值再存一个 kf_ 键就变成又一个没人读的开关，而现状正是那个口径，所以 38 不另立实现。
struct MaskedDigits: View {
    @EnvironmentObject var app: AppState
    let value: String
    var big: Bool = false
    @State private var revealed: Set<Int> = []
    // 373 揭示限时: 按 kf_speek_timedsec 立复遮期限 (0 = 不自动复遮, 与安全中心演示挡片同口径)
    @State private var clearAt: Double = 0
    // 388 首次"揭示=查看"记一次敏感台账, 防逐位点按刷屏
    @State private var ledgerLogged = false
    var body: some View {
        // 369 遮蔽样式: 与安全中心 maskStyleLabel 三档口径逐字对齐
        let style = DB.store.getString(SecKey.maskStyle)
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(value.enumerated()), id: \.offset) { i, ch in
                let on = revealed.contains(i)
                // 2026-10-13 run 59: 原写一行嵌套三元
                //   `style == "stars" ? "*" : (style == "tail4" && i >= value.count - 4) ? String(ch) : "•"`
                // 加上后面的字体三元与 a11y 三元, 整个 ForEach 体报
                //   "the compiler is unable to type-check this expression in reasonable time"。
                // 拆法: 遮蔽字符抽成纯函数, 其余重表达式各自显式标注类型 —— 逐个落地, 不再让一个表达式吞下全部。
                let mask = maskChar(style: style, index: i, count: value.count, ch: ch)
                let shown: String = on ? String(ch) : mask
                let digitFont: Font = (big ? Font.title : Font.title3).weight(.semibold).monospacedDigit()
                let a11yLabel: String = on ? "第 \(i + 1) 位" : "第 \(i + 1) 位, 点按显示"
                Button {
                    revealed.formSymmetricDifference([i])
                    if revealed.contains(i), !ledgerLogged {
                        ledgerLogged = true
                        SensitiveLedger().record("查看", target: "密码")
                    }
                    let s = DB.store.getInt(SecKey.timedReveal, 0)
                    clearAt = s > 0 ? Date().timeIntervalSince1970 + Double(s) : 0
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Text(shown)
                        .vkFont(digitFont)
                        .foregroundStyle(on ? DS.Palette.text : DS.Palette.textSub)
                        .frame(width: big ? 36 : 30)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a11yLabel)
                // 849 双击拷贝挂在每个位上: 容器的点按会被按钮吃掉, 只挂容器等于双击数值区没反应。
                // 双击时按钮自身动作会各切一次揭示, 净效果回到原样, 不影响读数。
                // 2026-10-13 run 63: 原写 `TapGesture(count: 2) { copyAll() }` —— TapGesture(count:)
                // 的初始化器不收闭包 ⇒ "extra trailing closure passed in call"。手势动作要挂在 .onEnded。
                .simultaneousGesture(TapGesture(count: 2).onEnded { copyAll() })
                // 对 VoiceOver 不承诺"双击" (VO 的双击=激活=揭示), 拷贝走转子自定义动作
                .accessibilityAction(named: "拷整条明文") { copyAll() }   // 849 拷整条明文
            }
        }
        // 849 兜住位与位之间的缝: 双击缝里也拷整条
        .onTapGesture(count: 2) { copyAll() }
        // 370 贴近复蔽: 面部贴近 → 已揭示的位立刻复遮 (与 373 到点复遮同一结局, 只是触发源不同)
        .proximityRemask {
            if !revealed.isEmpty { revealed = []; clearAt = 0 }
        }
        // 373 到点整集复遮 (revealed 清空即回打码态)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
            if clearAt > 0, now.timeIntervalSince1970 >= clearAt {
                revealed = []
                clearAt = 0
            }
        }
    }

    /// 849 双击/转子动作: 拷贝整条明文 (与详情页「复制」同一条 405 通路)
    private func copyAll() {
        ClipboardCare.copySecret(value, via: "密码明文")
        app.showToast("已复制")
    }

    /// 369 遮蔽字符 (三档口径): stars = 全星 / tail4 = 只留末四位 / 其余 = 圆点。
    /// 抽成纯函数是因为原来那行嵌套三元把 ForEach 体撑到编译器算不过来 (run 59 的类型检查超时)。
    private func maskChar(style: String, index: Int, count: Int, ch: Character) -> String {
        if style == "stars" { return "*" }
        if style == "tail4" && index >= count - 4 { return String(ch) }
        return "•"
    }
}

/// 307 保存前逐位 diff: 新旧对齐, 改动位靛蓝高亮 (306 分屏改造的下半屏)
struct PwdDiffView: View {
    let old: String
    let new: String
    var body: some View {
        let changed = CredentialOrg.digitDiff(old: old, new: new)
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(0..<max(old.count, new.count), id: \.self) { i in
                let a = i < old.count ? String(old[old.index(old.startIndex, offsetBy: i)]) : "·"
                let b = i < new.count ? String(new[new.index(new.startIndex, offsetBy: i)]) : "·"
                let ch = changed.contains(i + 1)
                HStack(spacing: DS.Space.s) {
                    Text(a)
                        .vkFont(.title3.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(width: 28)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(ch ? DS.Palette.accentText : DS.Palette.hairline)
                    Text(b)
                        .vkFont(.title3.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(ch ? DS.Palette.accentText : DS.Palette.text)
                        .frame(width: 28)
                    if ch {
                        Text("第 \(i + 1) 位")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
            if changed.isEmpty {
                Text("新旧值完全一致, 未做任何改动")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("新旧密码逐位对比, 共 \(changed.count) 位改动")
    }
}

/// 171/337 时窗进度细条 (⚠ 锁端 ZOTP 分钟级; 独立 TOTP 秒级; 末 5 秒转橙并轻震)
struct WindowBar: View {
    let totalSec: Int
    let label: String
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// 337/171 时窗倒计时的**唯一**实现: per - epoch % per (取余不是取整除)。
    /// CredentialOrg 里曾有同公式的 totpRemaining, 零调用, 已删, 免得看着像两套口径。
    private func remaining(_ d: Date) -> Int { max(0, totalSec - Int(d.timeIntervalSince1970) % max(totalSec, 1)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                Capsule().fill(remaining(now) <= 5 ? DS.Palette.warn : DS.Palette.accent)
                    .frame(height: 4)
                    .frame(width: max(CGFloat(remaining(now)) / CGFloat(max(totalSec, 1)) * geo.size.width, 0))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 4)
            .animation(DS.Motion.exit, value: remaining(now))
            HStack(spacing: DS.Space.xs) {
                Text(label)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("剩约 \(remaining(now)) 秒")
                    .vkFont(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
        }
        .onReceive(timer) { t in
            let old = remaining(now)
            now = t
            if remaining(t) <= 5 && old > 5 && remaining(t) > 0 {
                DS.Haptics.tick.impactOccurred()   // 337 末 5 秒轻震
            }
        }
        .accessibilityLabel(label + " 剩约 \(remaining(now)) 秒")
    }
}

/// 172/328 大字口述卡 (可拍照/可剪贴; 34 卡片厚度; 含码风险提示)
struct CodeBigCard: View {
    let title: String
    let code: String
    let window: String
    var note: String = ""
    var extraFoot: String = ""
    @EnvironmentObject var app: AppState
    /// 376 分享遮半: 默认遮下半段, 「完整显示」后露出全码; 每次进卡片 (完成页/sheet 重建) 都回默认遮, 不跨次保留。
    @State private var revealed = false
    var body: some View {
        VStack(spacing: DS.Space.s) {
            Text(title)
                .vkFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(revealed ? code : SecurityPolicy.halfMasked(code))
                .vkFont(.system(.largeTitle, design: .rounded).monospacedDigit(), weight: .semibold)
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
                // 370: 口述卡这一路也接贴近复蔽 (卡片在屏期间才开监听)
                .proximityRemask { revealed = false }
            Text(window)
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !note.isEmpty {
                Text(note)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(2)
            }
            HStack(spacing: DS.Space.s) {
                Button {
                    revealed.toggle()
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Label(revealed ? "再遮起来" : "完整显示",
                          systemImage: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .vkFont(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel(revealed ? "重新遮挡码值" : "完整显示码值")
                Button {
                    ClipboardCare.copySecret(revealed ? code : SecurityPolicy.halfMasked(code), via: "工作室 TOTP")   // 405
                    app.showToast(revealed ? "码值已复制" : "已复制遮半码值 (完整值先点「完整显示」)")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .vkFont(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("复制码值")
                ShareLink(item: shareText) {
                    Label("分享口述卡", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .vkFont(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("分享口述卡")
            }
            let foot = extraFoot.isEmpty ? "大字号方便对准锁键盘输入; 本卡含密码, 拍照或分享后注意保管。" : extraFoot
            Text(foot)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity)
        // 2026-10-14 材质统一: 口述卡与本页其余 13 块 .card() 同材质 (原先独此一块自带描边)。
        // 大字号密码在玻璃上仍读得清: glassEffect(.regular) 会自己压一层调暗底,
        // 而 226 降透明 / 862 增强对比下 axGlass 直接落回实底 —— 拍照那张最讲究可读的场合有退路。
        .axGlass(DS.Radius.card)
        .shadow(color: DS.Palette.accent.opacity(0.14), radius: 10, y: 5)
        .padding(.horizontal, DS.Space.gutter)
        .accessibilityElement(children: .combine)
    }
    private var shareText: String {
        // 376: 分享载荷与屏上显示同一真状态 —— 没点「完整显示」前, 分享出去的也是遮半值。
        let shown = revealed ? code : SecurityPolicy.halfMasked(code)
        return [title, "码值 \(shown)", window, "备注 \(note)"].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// 522 相机取号 (VisionKit 扫二维码/数据矩阵; 结果抽数字串, 失败回退人工输入)
struct CodeScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onResult: (String) -> Void
    var body: some View {
        NavigationStack {
            scanner
                .navigationTitle("扫一扫")   // 522 扫一扫
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onResult("")
                        dismiss()
                    }
                } }
        }
    }
    private var scanner: some View {
        // 522 相机取号: 走共享的 UIKit 扫码包装 (docs/API-VERIFY.md:44 那条退路), 不再自造形状。
        DataScannerView { results in
            for r in results {
                if let s = r.codeString {
                    let digits = s.filter { $0.isNumber }
                    onResult(digits)
                    dismiss()
                    return
                }
            }
            onResult("")
            dismiss()
        }
    }
}

// 卡片面 + 308 4 位分段 (全 App 只此一份)
extension View {
    /// 卡片面: 液态玻璃 + 34 轻厚度阴影。
    /// 2026-10-14 材质统一: 原为 surface 实底 + hairline 描边。描边一并去掉 —— 玻璃自带边缘高光,
    /// 再描 0.5pt 就是两道边; 降透明/增强对比时 axGlass 自己会落回 surface + hairlineStrong,
    /// 所以"实底无边"这条退路并没有丢。13 个 .card() 调用点全在向导页底上 (非卡中卡), 不存在玻璃叠玻璃。
    func card() -> some View {
        padding(DS.Space.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .axGlass(DS.Radius.card)
            .shadow(color: DS.Palette.accent.opacity(0.08), radius: 8, y: 4)
    }
}
extension String {
    /// 308 4 位分段
    func chunked(_ n: Int) -> [String] {
        var out: [String] = []
        var rest = Array(self)
        while !rest.isEmpty {
            out.append(String(rest.prefix(n)))
            rest = Array(rest.dropFirst(n))
        }
        return out
    }
}


// ================= 密码工坊 (301/303/304/305/306/307/308/309/173/179/314/515/516/518/519/520/522/523) =================
struct PwdStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// true = 由外部 NavigationStack push (不自带导航栏); false = sheet 呈现自带导航栏
    var embedded: Bool = false
    /// 编辑对象: nil = 新增
    var editAlias: Int? = nil

    // 515 分步: 0 类型与归属 / 1 码值 / 2 有效期与备注 / 3 确认
    @State private var step = 0
    @State private var kind: Int = 0            // 0 长期 / 1 临时
    @State private var owner: String? = nil
    @State private var pwd = ""
    @State private var from = Date()
    // 到期的初始值必须是**一个真窗口**：原先写成 `Date()`，于是新建临时码进到这步时
    // 生效与到期是同一分钟 (0 秒窗口)，界面显示"生效 15:37 · 到期 15:37"这种没人会要的默认。
    // 那时 519 不在这里拦，而是等按下"下一步"时**悄悄把 to 补成 from + 1 小时** —— 用户没选过的值被系统改了。
    // 那处补值本轮已删 (改成真拦, 见文件里的 navBar)，所以这里的初值就是唯一的到期默认值,
    // 全页不再有第二处替用户改时刻的地方。
    @State private var to = Date().addingTimeInterval(3600)   // 828 问号里承诺的默认值就是这个, 别两处各说一套
    @State private var note = ""
    @State private var useTemplate = true
    @State private var periodHelp = false     // 828 字段旁问号展开的说明块
    @State private var busy = false
    // 519 错误字段: 只做**当前这一步之内**的字段标题变红 + 字段下方 errorLine 同步。
    // 刻意不承诺"滚动定位到首个错误字段" —— 这一页是 VStack 直排 (form 里没有 ScrollView),
    //   没有可用的滚动容器与锚点, 那句写出来就是假话; 而步间真拦已经保证坏值出不了当前这一步,
    //   所以"停在当前步 + 红字 + 字段下方一行"就是这一版能兑现的全部, 不多许。
    @State private var errorField: String = ""
    @State private var showScan = false
    // 301 剪贴板来源条
    @State private var clipSource = false
    @State private var showDraftBar = true
    @State private var submitted = false   // 518: 提交成功不许回存废稿
    // 521 二次输入确认: 保存前重输码值核对 (开关 kf_scred_2nd, 默认开; 设置-安全可关)
    @State private var confirmPwd = ""
    private var mac: String { app.current?.mac ?? "" }
    private var editing: LedgerPwd? { editAlias.flatMap { DB.getPwd(mac, $0) } }

    private var pwdOK: Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }

    var body: some View {
        Group {
            if embedded {
                form
            } else {
                NavigationStack { form }
            }
        }
        .sheet(isPresented: $showScan) { CodeScanSheet { onScanResult($0) } }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            StepDots(total: 4, index: step, labels: ["类型归属", "码值", "有效期", "确认"])
            if showDraftBar, let d = CredentialOrg.draft(mac), editAlias == nil { draftBar(d) }
            if step == 0 { step0 }
            if step == 1 { step1 }
            if step == 2 { step2 }
            if step == 3 { step3 }
            navBar
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Gradient.screen.ignoresSafeArea())
        .navigationTitle(editing == nil ? "添加密码" : "改造密码 #\(editAlias ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) {
            Button("关闭") {
                saveDraft()
                if !embedded { dismiss() }
            }
        } }
        .onAppear {
            checkClipboard()
        }
        .onDisappear { saveDraft() }   // 518: 侧滑/push 退出也留稿
    }

    // ---------- 518 草稿续填横条 ----------
    private func draftBar(_ d: CredentialOrg.StudioDraft) -> some View {
        HStack(spacing: DS.Space.s) {
            Label("上次填到第 \(d.step + 1) 步, 继续?", systemImage: "arrow.triangle.branch")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.warn)
            Spacer(minLength: 0)
            Button("继续") { restoreDraft(d); showDraftBar = false }
                .vkFont(.caption, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            Button {
                CredentialOrg.clearDraft(mac)
                showDraftBar = false
            } label: {
                Text("丢弃")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .variantCallout(DS.Palette.warn, .control, wash: 0.10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("草稿续填: 上次填到第 \(d.step + 1) 步, 点继续可回填")   // 518 草稿续填
    }

    // ---------- 515/317 step0 类型与归属 ----------
    @ViewBuilder
    private var step0: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(spacing: DS.Space.xs) {
                segChip("长期密码", on: kind == 0) { kind = 0 }
                segChip("临时码", on: kind == 1) { kind = 1 }
                Spacer(minLength: 0)
            }
            .accessibilityLabel("凭证类型: " + (kind == 0 ? "长期密码" : "临时码"))
            ownerCard
        }
    }
    private func segChip(_ t: String, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            act()
        } label: {
            Text(t)
                .vkFont(.footnote, weight: .medium)
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                .padding(.horizontal, DS.Space.s + 2)
                .padding(.vertical, DS.Space.s)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("归属成员")
                .vkFont(.footnote, weight: .semibold)
                .foregroundStyle(errorField == "owner" ? DS.Palette.danger : DS.Palette.text)
            ForEach(DB.members()) { m in
                Button {
                    owner = m.id
                    errorField = ""
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Text(m.name)
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                        if owner == m.id {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: DS.Icon.sm, weight: .medium))
                                .foregroundStyle(DS.Palette.accentText)
                        }
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("归属 " + m.name + (owner == m.id ? ", 已选" : ""))
            }
            if DB.members().isEmpty {
                Text("还没有成员。可先选「未归属」, 稍后在成员中心补归属。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if errorField == "owner" {
                errorLine("归属必选: 先选成员; 没有成员可先去成员中心新建再返回。")   // 317 归属必选
            }
        }
        .card()
    }

    // ---------- 301/303/173/516/519/522 step1 码值 ----------
    @ViewBuilder
    private var step1: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text("码值")
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(errorField == "value" ? DS.Palette.danger : DS.Palette.text)
                Spacer(minLength: 0)
                Text("6~8 位数字")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
            if !pwd.isEmpty {
                MaskedDigits(value: pwd, big: true)
                    .padding(.vertical, DS.Space.xs)
            }
            TextField("", text: $pwd, prompt: Text("输入 6~8 位数字"))   // 516 输入
                .keyboardType(.numberPad)
                .vkFont(.title3.monospacedDigit(), weight: .semibold)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
                .onChange(of: pwd) { _, _ in
                    if errorField == "value" { errorField = "" }
                    if clipSource { DS.Haptics.tick.impactOccurred() }
                }
            if clipSource {
                HStack(spacing: DS.Space.xs) {
                    Label("来自剪贴板 · 已识别为候选码", systemImage: "doc.on.clipboard")   // 301 来自剪贴板
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("清除") {
                        pwd = ""
                        clipSource = false
                    }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantCallout(DS.Palette.warn, .control, wash: 0.10)
                .accessibilityLabel("码值来自剪贴板, 点清除可移除")
            }
            HStack(spacing: DS.Space.s) {
                ForEach([6, 7, 8], id: \.self) { n in
                    Button("生成 \(n) 位") {
                        pwd = StudioTools.genDigits(n)
                        clipSource = false
                        DS.Haptics.tick.impactOccurred()
                    }
                    .vkFont(.caption, weight: .medium)
                    .buttonStyle(.bordered)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("本地生成 \(n) 位随机密码")   // 173 本地生成
                }
                Spacer(minLength: 0)
            }
            if !pwd.isEmpty {
                let s = StudioTools.pwdStrength(pwd)
                HStack(spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i < s.score ? (s.score <= 1 ? DS.Palette.warn : DS.Palette.ok) : DS.Palette.surfaceAlt)
                                .frame(width: 22, height: 4)
                        }
                    }
                    Text(s.hint)
                        .vkFont(.caption2)
                        .foregroundStyle(s.score <= 1 ? DS.Palette.warn : DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityLabel("密码强度 " + s.hint)
            }
            if errorField == "value" {
                errorLine("码值需 6~8 位数字: 就在上面那格码值里改, 改好再点下一步。")   // 519 码值需
            }
            let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: editAlias ?? -1) : []
            // 304 说的是"全库", 上面那个只查本锁 → 跨锁检查接上 (duplicatePwdLockNames 此前零调用)
            let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
            if !others.isEmpty {
                Label("其它 \(others.count) 把锁上也有同值: " + others.prefix(3).joined(separator: "、")
                    + (others.count > 3 ? " 等" : ""),   // 304 界面文案
                      systemImage: "lock.rectangle.stack")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dups.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    Label("本锁已有 \(dups.count) 条同值凭证", systemImage: "plus.slash.minus")   // 304 本锁已有
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("查看") {
                        // 304 查看即跳: 真把那枚同值凭证的详情打开 (toast 看不全)
                        app.pendingCredNav = "pwd:\(dups[0].alias)"
                        app.pendingCredNavMac = mac
                        app.requestRoute(.credentials)   // 2026-10-15 走查: 与全仓跨 Tab 跳转统一走 requestRoute (访客门禁那一口)
                        if !embedded { dismiss() }
                    }
                    .vkFont(.caption, weight: .medium)
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantCallout(DS.Palette.warn, .control, wash: 0.10)
                .accessibilityElement(children: .combine)
            }
            if let c = pwdOK ? CredentialOrg.prefixConflict(mac, pwd, excluding: editAlias ?? -1).first : nil {
                Text("与「\(CredentialOrg.displayPwd(c))」前 4 位相同, 口头易混淆。")   // 314 位相同
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showScan = true
            } label: {
                Label("扫一扫取号", systemImage: "qrcode.viewfinder")   // 522 扫一扫取号
            }
            .vkFont(.caption, weight: .medium)
            .foregroundStyle(DS.Palette.accentText)
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
            .accessibilityHint("用相机识别印刷码, 结果自动填入码值字段")
        }
        .card()
    }
    func onScanResult(_ s: String) {
        if !s.isEmpty {
            pwd = s
            clipSource = false
            app.showToast("已识别 \(s.count) 位数字, 请核对位数与内容")   // 522 已识别
            DS.Haptics.trigger.impactOccurred()
        } else {
            app.showToast("未识别到数字码, 请人工输入")   // 522 未识别到数字码
        }
    }

    // ---------- 520/523 step2 有效期与备注 ----------
    @ViewBuilder
    private var step2: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if kind == 1 {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.xs) {
                        Text("有效期 (临时码)")
                            .vkFont(.footnote, weight: .semibold)
                            .foregroundStyle(errorField == "period" ? DS.Palette.danger : DS.Palette.text)
                        // 828 字段旁问号 (Stripe Dashboard 那一形态): 展开的是**这表单真遵守的**四条口径,
                        // 不是通用科普。刻意不做 `.popover`：弹窗锚点在这台机型上看不见也点不着，
                        // 而字段下方的内联块与它说的是同一句话, 只是永远可达 (需要眼睛确认的清单见 VERIFY-CHECKLIST)。
                        Button {
                            periodHelp.toggle()
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Image(systemName: periodHelp ? "questionmark.circle.fill" : "questionmark.circle")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(width: DS.Hit.min - DS.Space.m, height: DS.Hit.min - DS.Space.m)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("有效期的可选范围与默认值")
                        .accessibilityAddTraits(periodHelp ? [.isSelected] : [])
                        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                        Spacer(minLength: 0)
                    }
                    if periodHelp {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("默认 1 小时；四枚快捷档是 1 小时 / 今天内 (到今晚 23:59) / 7 天 / 30 天。")
                            Text("到期必须晚于生效，否则这条不让过。")   // 519 到期必须晚于生效
                            Text("生效与到期是写给门锁的两个时刻，门锁用它自己的钟比对 —— 锁钟不准，码会提前或延后失效。")
                            Text("改有效期要重新下发到锁才生效；只改本机台账不算。")
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DS.Space.xs)
                        .accessibilityLabel("有效期说明：默认 1 小时；四枚快捷档为 1 小时、今天内到今晚二十三点五十九、7 天、30 天。到期必须晚于生效。生效与到期是写给门锁的两个时刻，门锁用它自己的钟比对。改有效期要重新下发到锁才生效。")
                    }
                    HStack(spacing: DS.Space.xs) {
                        quickDuration("1 小时", 3600)
                        quickDuration("今天", todayEndSecs())
                        quickDuration("7 天", 7 * 86400)
                        quickDuration("30 天", 30 * 86400)
                    }
                    HStack(spacing: DS.Space.s) {
                        durationLabel(from, prefix: "生效 ")
                        durationLabel(to, prefix: "到期 ")
                        Spacer(minLength: 0)
                    }
                    if to <= from {
                        errorLine("到期需晚于生效: 点上面任一快捷档, 或把到期往后挪; 这一步不让过。")   // 519 到期需晚于生效
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("长期密码无到期点; 老旧巡检会在详情页提示「添加满 180 天」那一条 —— "   // 305 长期密码无到期点
                         + "台账只有添加时刻, 那句说的是这条加了多久, 不是这个值多久没换过。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("备注 (给谁·哪扇门·用多久)")
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                // 312 常用短语条: 点按追加到备注末尾 (不是替换), 空备注时直接填
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        Text("常用短语").vkFont(.caption2).foregroundStyle(DS.Palette.textSub)   // 312 常用短语
                        ForEach(["仅白天", "勿外传", "长期有效"], id: \.self) { p in
                            Button(p) {
                                note = note.isEmpty ? p : note + " · " + p
                                DS.Haptics.tick.impactOccurred()
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xs)
                            .variantPlate(DS.Palette.surfaceAlt, .capsule)
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .contentShape(Rectangle())
                            .accessibilityLabel("追加短语 \(p)")
                            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 2)
                }
                TextField("如: 钟点工·大门·仅上午场", text: $note,   // 523 钟点工
                          prompt: Text("给谁 · 哪扇门 · 用多久"))
                    .vkFont(.subheadline)
                    .frame(minHeight: DS.Hit.min)
                    .autocorrectionDisabled()
                // 开关必须常驻: 旧写法用 if useTemplate 包住自己的 Toggle,
                // 一旦用户关掉, 这一行就消失了, 本次会话再也开不回来
                VariantToggle("备注自动补命名模板 (谁-哪里-何时)", isOn: $useTemplate)
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
    private func quickDuration(_ t: String, _ secs: Int) -> some View {
        Button {
            from = Date()
            to = Date().addingTimeInterval(TimeInterval(secs))
            errorField = ""
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(t)
                .vkFont(.caption, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷时长 \(t)")   // 520 快捷时长
    }
    /// 快捷档"今天"的剩余秒数。终点取 `TimeFormat.dayEnd()` (今晚 23:59) ——
    /// 那一份实现刚从**编译失败**里修出来，理由与机检依据写在 TimeFormat.swift:87 上方，不要在这里另抄一份。
    private func todayEndSecs() -> Int {
        max(Int(TimeFormat.dayEnd().timeIntervalSinceNow), 60)
    }
    private func durationLabel(_ d: Date, prefix: String) -> some View {
        Text(prefix + d.formatted(.dateTime.month().day().hour().minute()))
            .vkFont(.footnote)
            .foregroundStyle(DS.Palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(prefix + d.formatted(.dateTime.month().day().hour().minute()))
    }

    // ---------- 306/307 确认步 ----------
    private var step3: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if let e = editing, let old = e.pwd, !old.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("新旧对照 (上旧只读 / 下新)")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    PwdDiffView(old: old, new: pwd.isEmpty ? old : pwd)
                        .card()
                    Text("改动位共 \(CredentialOrg.digitDiff(old: old, new: pwd.isEmpty ? old : pwd).count) 处 (逐位高亮, 确认后才落库)。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("即将\(editing == nil ? "添加" : "改造")的凭证")
                    .vkFont(.footnote, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        StatusPill(text: kind == 0 ? "长期密码" : "临时码", systemImage: kind == 0 ? "infinity" : "clock", tone: .accent)
                        Text(CredentialOrg.ownerName(owner))
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                    }
                    MaskedDigits(value: pwd, big: true)
                    if kind == 1 {
                        Text("\(from.formatted(.dateTime.month().day().hour().minute())) ~ \(to.formatted(.dateTime.month().day().hour().minute())) 生效")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            // 2026-10-14 布局审计 R2: 两个"月日 时分"+ 尾巴"生效"在 375pt 宽 / 大字号档
                            // 估宽 371pt > 可分配 343pt，lineLimit(1) 会把尾巴切掉 —— 而那半句正是
                            // "从哪个时刻开始算"。改成允许两行并让它占满该占的竖直空间；
                            // 原有的 minimumScaleFactor 不动 (缩字号与换行谁先起作用由系统排，不在这里猜)。
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !note.isEmpty {
                        Text(note)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(2)
                    }
                }
                .card()
            }
            if busy {
                ProgressView("正在下发到门锁…")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
            } else {
                // 521 二次输入确认: 重输码值一致才放行 (与转账复核同语义; 开关在设置-安全页)
                if DB.store.getBool("kf_scred_2nd", true) {
                    HStack(spacing: DS.Space.xs) {
                        TextField("重输一遍码值", text: $confirmPwd)   // 521 重输一遍码值
                            .keyboardType(.numberPad)
                            .vkFont(.subheadline.monospaced())
                            .autocorrectionDisabled()
                        if !confirmPwd.isEmpty, confirmPwd != pwd {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DS.Icon.sm, weight: .medium))
                                .foregroundStyle(DS.Palette.danger)
                        } else if !confirmPwd.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: DS.Icon.sm, weight: .medium))
                                .foregroundStyle(DS.Palette.ok)
                        }
                    }
                    .padding(DS.Space.s)
                    .variantPlate(DS.Palette.surfaceAlt, .control)
                }
                // 541 替代: 原句是下发前的乐观锁提示 ("此锁配置上次同步于 X, 建议到场核对后重试")。
                // 锁端没有配置序号字段, 所以这把尺只到本机台账 (365 队列里最后一条"已下发"的时刻),
                // 文案把这件事说穿 —— 提示不说成"锁端就是这样"。
                if let at = CredentialOrg.lastApplyAt(mac) {
                    let days = Int((Date().timeIntervalSince1970 - at / 1000) / 86400)
                    Text("此锁上次成功下发: " + (days <= 0 ? "今天" : "\(days) 天前")
                         + " (本机台账时刻, 不是锁端真值; 若中途有别人动过这把锁, 以到场核对为准)")   // 541 上次成功下发时刻口径
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("本机台账里还没有这把锁的成功下发记录 —— 这条提示只说本机台账, 不代表锁端没被配过。")   // 541 本机台账里还没有这把
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BusyButton(title: editing == nil ? "下发密码" : "保存改造", systemImage: "key.fill", isBusy: busy) {
                    Task { await submit() }
                }
                .disabled(DB.store.getBool("kf_scred_2nd", true) && confirmPwd != pwd)
            }
            Text("请将手机靠近门锁; 成功后登记到本机台账并留一档版本快照。")   // 487 请将手机靠近门锁
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 515 导航条 ----------
    private var navBar: some View {
        HStack(spacing: DS.Space.s) {
            if step > 0 {
                Button("上一步") {
                    withAnimation(DS.Motion.quick) { step -= 1 }
                }
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step < 3 {
                Button(step == 0 ? "下一步: 码值" : (step == 1 ? "下一步: 有效期" : "下一步: 确认")) {
                    if step == 0, owner == nil, !DB.members().isEmpty {
                        errorField = "owner"
                        app.showToast("先选归属成员")   // 317 先选归属成员
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    if step == 1, !pwdOK {
                        errorField = "value"
                        app.showToast("码值需 6~8 位数字")   // 519 码值需
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    // 519 步间真拦: 原先这一支是 `to = from + 1h` —— 静默把用户没选过的值改掉,
                    // 然后带着一个他自己没填的时刻进确认步, 界面上显示的仍是补出来的那个。
                    // 现在停在这一步: toast + 触感 + errorField 同步 (字段下方那行 errorLine 已经在按 to<=from 显示)。
                    if step == 2, kind == 1, to <= from {
                        errorField = "period"
                        app.showToast("到期要晚于生效, 请先点一枚快捷档")   // 519 到期要晚于生效
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    saveDraft()
                    withAnimation(DS.Motion.quick) { step += 1; errorField = "" }
                    DS.Haptics.tick.impactOccurred()
                }
                .vkFont(.subheadline, weight: .semibold)
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func checkClipboard() {
        guard editAlias == nil else { return }
        guard let s = UIPasteboard.general.string else { return }
        let digits = s.filter { $0.isNumber }
        if digits.count >= 6, digits.count <= 8, pwd.isEmpty {
            pwd = digits
            clipSource = true
        }
    }
    private func restoreDraft(_ d: CredentialOrg.StudioDraft) {
        step = d.step
        kind = d.kind
        pwd = d.pwd
        note = d.note
        useTemplate = d.useTemplate
        owner = d.owner
        if let f = CredentialOrg.parseLocal(d.fromISO) { from = f }
        if let t = CredentialOrg.parseLocal(d.toISO) { to = t }
        app.showToast("已回填草稿")   // 518 已回填草稿
    }
    private func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }
    private func saveDraft() {
        guard !submitted, editAlias == nil, step > 0 || !pwd.isEmpty else { return }
        CredentialOrg.saveDraft(mac, CredentialOrg.StudioDraft(
            step: step, kind: kind, pwd: pwd, permanent: kind == 0,
            fromISO: iso(from), toISO: iso(to), owner: owner,
            useTemplate: useTemplate, note: note, scene: "", batch: 0,
            at: Date().timeIntervalSince1970))
    }

    // ---------- 提交 (既有协议 0A/原位改写; 178 批量另在临时码工坊) ----------
    private func submit() async {
        guard let kc = app.current, !busy else { return }
        // 519 兜底拦: 步间真拦只管"点下一步"那一下, 而 518 草稿回填 (restoreDraft) 会把 step 直接放回
        // 第 4 步, 字段是上一次会话填的 —— 那几条坏值不经任何一步就坐到提交按钮前面。
        // 所以这里按步序再核一遍, 缺什么就回跳到对应那一步并写 errorField, 不带着坏值去发 0A。
        if owner == nil, !DB.members().isEmpty {
            step = 0
            errorField = "owner"
            app.showToast("先选归属成员")
            DS.Haptics.trigger.impactOccurred()
            return
        }
        guard pwdOK else {
            step = 1
            errorField = "value"
            app.showToast("码值需 6~8 位数字")   // 519 码值需
            DS.Haptics.trigger.impactOccurred()
            return
        }
        if kind == 1, to <= from {
            step = 2
            errorField = "period"
            app.showToast("到期要晚于生效: 草稿里的这一档已过期, 请重选")   // 519 到期要晚于生效
            DS.Haptics.trigger.impactOccurred()
            return
        }
        busy = true
        defer { busy = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let isTemp = kind == 1
        let fromS = isTemp ? iso(from) : "2010-01-01 00:00:00"
        let toS = isTemp ? iso(to) : "2118-01-01 00:00:00"
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            var finalNote = note
            if useTemplate, finalNote.isEmpty {
                let who = CredentialOrg.ownerName(owner).isEmpty ? "未归属" : CredentialOrg.ownerName(owner)
                finalNote = who + "-大门-" + (isTemp ? (from.formatted(.dateTime.month().day()) + "-" + to.formatted(.dateTime.month().day())) : "长期")
            }
            let alias: Int
            if let e = editing, let oldAlias = editAlias {
                alias = try await app.lock.pwdModify(alias: oldAlias, pwd: pwd, validFrom: e.from, validTo: e.to)
                if alias != oldAlias {
                    // 确认口径：不是删除动作，是**换槽**。锁端 0A 改写后把这条挪到了新槽，旧槽在锁里已经不存在；
                    // 紧跟着的 addPwd 用同一份值/时段/归属把台账补回新槽，账上没有任何东西被丢掉 ⇒ 无后果可预告，不问。
                    DB.delPwd(kc.mac, oldAlias)
                    DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: e.from, to: e.to, temp: e.temp,
                                                at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: finalNote))
                } else {
                    DB.rePwd(kc.mac, alias, pwd)
                    DB.setPwdNote(kc.mac, alias, finalNote)
                    DB.setPwdOwner(kc.mac, alias, owner)
                }
                if let p2 = DB.getPwd(kc.mac, alias) {
                    CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: p2, fp: nil, note: "改造 (保存前先做对照)")
                }
            } else {
                alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: fromS, validTo: toS)
                DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: fromS, to: toS, temp: isTemp,
                                             at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: finalNote))
                CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: DB.getPwd(kc.mac, alias), fp: nil,
                                       note: isTemp ? "新增临时码" : "新增")
            }
            CredentialOrg.clearDraft(kc.mac)
            showDraftBar = false
            submitted = true   // 518
            app.flashReceipt("已写入本机")   // 508 已写入本机
            app.showToast(isTemp ? "临时码已下发" : "密码已下发 (别名 #\(alias))")
            if !embedded { dismiss() }
        } catch {
            app.showToast("下发失败: " + error.localizedDescription)
        }
    }

    private func errorLine(_ s: String) -> some View {
        Label {
            Text(s).vkFont(.caption).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: DS.Icon.sm, weight: .medium))
        }
        .vkFont(.caption)
        .foregroundStyle(DS.Palette.danger)
        .accessibilityLabel(s)
    }
}

// ================= 临时码工坊 (325/327/328/329/330/331/333/308/172/178/520) =================
struct TempCodeStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var scene = ""
    @State private var pwd = ""
    @State private var batchCount = 1      // 178 批量临时码
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(3600)   // 同上: 默认窗口 1 小时, 与第一个快捷档一致
    @State private var owner: String? = nil
    @State private var note = ""
    @State private var showScan = false
    @State private var clipSource = false
    @State private var result: LedgerPwd?
    @State private var busy = false

    private var mac: String { app.current?.mac ?? "" }
    private var lockName: String { app.displayName }
    private var pwdOK: Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }
    private var sceneNote: String {
        StudioTools.scenes.first { $0.key == scene }?.note ?? ""
    }
    /// 327 租期重叠: 与同成员其它时间窗临时码的撞车
    private var overlaps: [LedgerPwd] {
        CredentialOrg.overlapWindows(mac, from: iso(from), to: iso(to), owner: owner, excluding: -1)
    }

    var body: some View {
        NavigationStack {
            if result == nil { addForm } else { doneCard }
        }
        .navigationTitle(result != nil && MemberHub.elderMode ? "口述卡" : "临时码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        .sheet(isPresented: $showScan) { CodeScanSheet { onScan($0) } }
    }

    // ---------- 添加 (515 单页三段, 表单体验 516/520/522/523) ----------
    private var addForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                // 325 五场景预设
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("场景预设 (选中即套默认时长与备注)")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Space.xs)], spacing: DS.Space.xs) {
                        ForEach(StudioTools.scenes) { s in
                            sceneChip(s)
                        }
                    }
                }
                .card()

                // 码值 (301 剪贴板即建 + 303 回显 + 173 生成 + 522 扫号 + 516 数字键盘)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        Text("码值 (6~8 位数字)")
                            .vkFont(.footnote, weight: .semibold)
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                        Text(pwdOK ? "✓ 位数合规" : "6~8 位数字")
                            .vkFont(.caption2)
                            .foregroundStyle(pwdOK ? DS.Palette.ok : DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    if !pwd.isEmpty {
                        MaskedDigits(value: pwd, big: true)
                    }
                    TextField("输入码值, 或点「生成」", text: $pwd, prompt: Text("输入 6~8 位数字"))   // 516 输入
                        .keyboardType(.numberPad)
                        .vkFont(.title3.monospacedDigit(), weight: .semibold)
                        .frame(minHeight: DS.Hit.min)
                        .autocorrectionDisabled()
                    if clipSource {
                        HStack(spacing: DS.Space.xs) {
                            Label("来自剪贴板 · 已识别为候选码", systemImage: "doc.on.clipboard")   // 301 来自剪贴板
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                            Spacer(minLength: 0)
                            Button("清除") { pwd = ""; clipSource = false }
                                .vkFont(.caption, weight: .medium)
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, 4)
                        .variantCallout(DS.Palette.warn, .control, wash: 0.10)
                        .accessibilityLabel("码值来自剪贴板, 点清除可移除")
                    }
                    HStack(spacing: DS.Space.xs) {
                        Button("生成") {   // 173 生成
                            pwd = StudioTools.genDigits(6)
                            clipSource = false
                        }
                        .vkFont(.caption, weight: .medium)
                        .buttonStyle(.bordered)
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("本地生成 6 位随机码")   // 173 本地生成
                        Button("扫一扫") { showScan = true }   // 522 扫一扫
                            .vkFont(.caption, weight: .medium)
                            .buttonStyle(.bordered)
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityLabel("相机识别印刷码")   // 522 相机识别印刷码
                        Spacer(minLength: 0)
                    }
                    // 178 批量临时码 (锁端无批量命令, 走既有 0A 逐条, 失败逐条报)
                    HStack(spacing: DS.Space.xs) {
                        Text("一次生成")   // 178 一次生成
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        ForEach([1, 2, 3, 5], id: \.self) { n in
                            Button(String(n)) { batchCount = n }
                                .vkFont(.caption.weight(batchCount == n ? .semibold : .medium))
                                .buttonStyle(.bordered)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("批量 \(n) 张")   // 178 批量
                        }
                        Spacer(minLength: 0)
                    }
                    // 304 全库重复拦截: 本锁 + 其它锁各查一次 (此前只查本锁却写着"全库")
                    let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: -1) : []
                    let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
                    if !others.isEmpty {
                        Label("其它 \(others.count) 把锁上也有同值: " + others.prefix(3).joined(separator: "、")
                            + (others.count > 3 ? " 等" : ""), systemImage: "lock.rectangle.stack")   // 304 界面文案
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dups.isEmpty {
                        // 304 查看即跳: 不再只给一句"建议换一组", 真把同值那条的详情打开
                        HStack(spacing: DS.Space.xs) {
                            Label("本锁已有 \(dups.count) 条同值凭证, 建议换一组", systemImage: "plus.slash.minus")   // 304 本锁已有
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("查看") {
                                app.pendingCredNav = "pwd:\(dups[0].alias)"
                                app.pendingCredNavMac = mac
                                app.requestRoute(.credentials)   // 2026-10-15 走查: 同上, 统一走 requestRoute
                                dismiss()
                            }
                            .vkFont(.caption, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .card()

                // 时段 (520 快捷 + 327 重叠 + 330 装修黄条)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("生效时段")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    HStack(spacing: DS.Space.xs) {
                        quickPill("1 小时") { from = Date(); to = Date().addingTimeInterval(3600) }
                        quickPill("今天内") { from = Date(); to = TimeFormat.dayEnd() }   // 终点单一出口 (520/828)
                        quickPill("7 天") { from = Date(); to = Date().addingTimeInterval(7 * 86400) }
                        quickPill("30 天") { from = Date(); to = Date().addingTimeInterval(30 * 86400) }
                    }
                    HStack(spacing: DS.Space.s) {
                        Text(isoShort(from, prefix: "生效 "))
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("→")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        Text(isoShort(to, prefix: "到期 "))
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    if to <= from {
                        Label("到期需晚于生效", systemImage: "exclamationmark.circle.fill")   // 519 到期需晚于生效
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.danger)
                    }
                    // 327 租期重叠检测
                    if !overlaps.isEmpty {
                        Label {
                            Text("与本成员其它 \(overlaps.count) 张码时段撞车")   // 327 与本成员其它
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    }
                    // 330 装修黄条
                    if scene == "reno" {
                        Label("长期工场景: 详情页挂「施工中」黄条, 建议 30 天内复查一次", systemImage: "paintbrush")   // 330 长期工场景
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()

                // 归属与备注 (317 归属先行 + 179 占位)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("归属与备注")
                        .vkFont(.footnote, weight: .semibold)
                        .foregroundStyle(DS.Palette.text)
                    ForEach(DB.members()) { m in
                        Button {
                            owner = m.id
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Text(m.name)
                                    .vkFont(.subheadline)
                                    .foregroundStyle(DS.Palette.text)
                                Spacer(minLength: 0)
                                if owner == m.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: DS.Icon.sm, weight: .medium))
                                        .foregroundStyle(DS.Palette.accentText)
                                }
                            }
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("归属 " + m.name + (owner == m.id ? ", 已选" : ""))
                    }
                    TextField("给谁 · 哪扇门 · 用多久 (可长按调听写)", text: $note,
                              prompt: Text(scene.isEmpty ? "如: 钟点工·大门·仅上午场" : sceneNote))
                        .vkFont(.subheadline)
                        .frame(minHeight: DS.Hit.min)
                        .autocorrectionDisabled()
                }
                .card()

                BusyButton(title: batchCount > 1 ? "下发 \(batchCount) 张" : "下发临时码",   // 178 下发
                           systemImage: "clock.badge.chevron.right", isBusy: busy) {
                    Task { await submitBatch() }
                }
                .disabled(!pwdOK || to <= from)
                Text("请将手机靠近门锁; 批量走既有 0A 逐条下发, 锁端无批量命令, 失败逐条报。")   // 178 请将手机靠近门锁
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.l)
        }
        .background(DS.Gradient.screen.ignoresSafeArea())
        .axBottomAnchor()   // 870
        .onAppear { checkClipboard() }
    }

    private func sceneChip(_ s: StudioTools.SceneDef) -> some View {
        Button {
            scene = s.key
            from = Date()
            to = Date().addingTimeInterval(TimeInterval(s.hours * 3600))
            if note.isEmpty { note = s.note }
            DS.Haptics.tick.impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .vkFont(.footnote, weight: .semibold)
                    .lineLimit(1)
                Text(s.hint)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xs + 2)
            .foregroundStyle(scene == s.key ? DS.Palette.onAccent : DS.Palette.text)
            .background(scene == s.key ? DS.Palette.accent : DS.Palette.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("场景 \(s.name): \(s.hint)")   // 325 场景
        .accessibilityAddTraits(scene == s.key ? [.isSelected] : [])
    }
    private func quickPill(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button {
            act()
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(t)
                .vkFont(.caption, weight: .medium)
                .foregroundStyle(DS.Palette.accentText)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .variantPlate(DS.Palette.accentText.opacity(0.10), .capsule)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷时长 \(t)")   // 520 快捷时长
    }

    // ---------- 完成页: 172/328 大字口述卡 + 329 一句话 + 333 首用回执 (⚠ 按时间推断标"约") ----------
    private var doneCard: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                CodeBigCard(title: "\(lockName) · 临时码", code: result?.pwd ?? pwd,
                            window: "\(isoShort(from)) ~ \(isoShort(to)) 生效",
                            note: note,
                            extraFoot: batchCount > 1 ? "批量共 \(batchCount) 张, 其余已逐张下发" : "")
                if MemberHub.elderMode {
                    // 486 代际完成页切换: 长辈模式下完成页默认形态 = 口述卡 (页标题也切到「口述卡」) + 一枚大「完成」;
                    // 329/333/再发一张 是常规形态的入口, 这一档收起来并在原地说明 —— 收了不吭声就是本仓反复犯的无声忽略。
                    Button("完成") { dismiss() }
                        .buttonStyle(PrimaryActionStyle())
                    // 329 常规模式这里还有
                    // 333 常规模式这里还有
                    // 486 常规模式这里还有
                    Text("常规模式这里还有 一句话口令 / 首用回执 / 再发一张 — 长辈模式下不显示。")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 329 一句话口令文本
                if let r = result, !MemberHub.elderMode {
                    let text = StudioTools.oneLine(p: r, lockName: lockName, value: r.pwd)
                    Button {
                        ClipboardCare.copySecret(text, via: "一句话口令")   // 405 含口令明文
                        app.showToast("一句话口令已复制")   // 329 一句话口令已复制
                    } label: {
                        VStack(spacing: DS.Space.xs) {
                            Text("生成一句话口令")   // 329 生成一句话口令
                                .vkFont(.footnote, weight: .semibold)
                                .foregroundStyle(DS.Palette.accentText)
                            Text("“" + text + "”")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min + 8)
                        .contentShape(Rectangle())
                        .padding(.vertical, DS.Space.s)
                        .variantPlate(DS.Palette.surfaceAlt, .control)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityLabel("复制一句话口令: " + text)
                    // 329 分享面板: 系统分享单 (与 405 复制同源明文, 发给家人用)
                    ShareLink(item: text) {
                        Label("分享一句话口令", systemImage: "square.and.arrow.up")   // 329 分享一句话口令
                            .vkFont(.footnote, weight: .medium)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                            .padding(.vertical, DS.Space.s)
                            .variantPlate(DS.Palette.surfaceAlt, .control)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityLabel("分享一句话口令")   // 329 分享一句话口令
                }
                // 333 首用回执 (⚠ 无 alias 字段, 按时间推断, 标"约")
                if let r = result, !MemberHub.elderMode, let t = CredentialOrg.firstUse(mac, p: r) {
                    Label {
                        Text("约在 \(isoShort(Date(timeIntervalSince1970: t))) 有人用它开过门")   // 333 约在
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.ok)
                    .frame(maxWidth: .infinity)
                    .padding(DS.Space.s)
                    .variantCallout(DS.Palette.ok, .control, wash: 0.08)
                    .padding(.horizontal, DS.Space.gutter)
                } else if result != nil, !MemberHub.elderMode {   // 原来绑了 r 却从没读过
                    Label {
                        Text("等待首次使用")   // 333 等待首次使用
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity)
                    .padding(DS.Space.s)
                    .variantPlate(DS.Palette.surfaceAlt, .control)
                    .padding(.horizontal, DS.Space.gutter)
                }
                if !MemberHub.elderMode {
                    Button("再发一张") {
                        result = nil
                        pwd = StudioTools.genDigits(6)
                        note = ""
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                }
            }
            .padding(.vertical, DS.Space.l)
        }
        .background(DS.Gradient.screen.ignoresSafeArea())
    }

    private func checkClipboard() {
        guard let s = UIPasteboard.general.string else { return }
        let digits = s.filter { $0.isNumber }
        if digits.count >= 6, digits.count <= 8, pwd.isEmpty {
            pwd = digits
            clipSource = true
        }
    }
    private func onScan(_ s: String) {
        if !s.isEmpty {
            pwd = s
            app.showToast("已识别 \(s.count) 位数字, 请核对")   // 522 已识别
            DS.Haptics.trigger.impactOccurred()
        } else {
            app.showToast("未识别到数字码, 请人工输入")   // 522 未识别到数字码
        }
    }
    private func isoShort(_ d: Date, prefix: String = "") -> String {
        prefix + d.formatted(.dateTime.month().day().hour().minute())
    }
    private func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }
    private func submitBatch() async {
        guard let kc = app.current, !busy, pwdOK else { return }
        busy = true
        defer { busy = false }
        var last: LedgerPwd?
        var failed = 0
        for i in 0..<max(batchCount, 1) {
            // 178 逐条错峰: 每张码时段顺移 30 分钟, 锁端无批量命令
            let df = from.addingTimeInterval(TimeInterval(i * 1800))
            let dt = to.addingTimeInterval(TimeInterval(i * 1800))
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            do {
                try await app.lock.ensureConnected(mac: kc.mac)
                let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: f.string(from: df), validTo: f.string(from: dt))
                let rec = LedgerPwd(alias: alias, from: f.string(from: df), to: f.string(from: dt), temp: true,
                                    at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: note)
                DB.addPwd(kc.mac, rec)
                CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: rec, fp: nil, note: "新增临时码")
                last = rec
                app.showToast("第 \(i + 1)/\(max(batchCount, 1)) 张已下发 (别名 #\(alias))")
            } catch {
                failed += 1
                app.showToast("第 \(i + 1) 张下发失败: \(error.localizedDescription)")   // 178 张下发失败
            }
        }
        if let r = last {
            result = r
            // 整条批量链都用入口捕获的 kc.mac，这一行原先落到**活读**的 mac:
            // 批量下发以十秒计，中途当前锁被改掉就会清掉另一把锁的草稿 (tools/macpin.js 抓到的)
            CredentialOrg.clearDraft(kc.mac)
            if failed > 0 { app.showToast("批量完成, \(failed) 张失败, 稍后可在凭证页重试") }
        }
    }
}


// ================= 323 删除双签: 删除成员最后一枚指纹需前缀验证任一在用密码 =================
// 这一枚是 UI 入口 (内部要弹 UIAlertController + 走 confirmDestructive), 所以整条下沉主 actor。
@MainActor
func fpDoubleSignCheck(mac: String, batch: Int, confirmTitle: String, action: @escaping @MainActor () -> Void) {
    // 档案已经不在这台锁的台账里 (并发删除/切锁) ⇒ 没有任何可删的东西。原先这里直接 action()，
    // 而调用方那条异步体重读一次 DB 就静默返回 —— 界面什么都不说，人以为删掉了。
    // 现在两支都不越过「先问一句」：无档案 = 不做，有档案 = 必确认。
    guard let f = DB.getFp(mac, batch) else { return }
    let need = CredentialOrg.fpCountByOwner(mac, f.owner) == 1
    guard need, let v = DB.listPwds(mac).first(where: { $0.pwd != nil && CredentialOrg.pwdState($0) == 0 })?.pwd else {
        // 真漏 (第一百六十七批 delsweep 二次确认对账撞出)：这一支原先直接 action()。
        // 同一个按钮，「最后一枚」那一支要输入在用密码前缀才肯删，「不止最后一枚」这一支却一按就把锁端
        // 指纹删掉、零确认 —— 双签的门槛按「是不是最后一枚」分叉，把「要不要问一句」这件事问漏了。
        // 现在两支都必问，只是深浅不同：非最后一枚走全仓那一个确认入口 (后果 + 出路)，最后一枚仍要前缀验证。
        // 最后一枚但本机翻不出任何在用密码时 (双签在形式上无法完成) 也落到这一支 —— 那恰恰是最贵的一种：
        // 无密码可核对 == 删完这人既没指纹也没密码，所以后果必须单独说一句。
        let lastWarn = need
            ? "这是该成员名下最后一枚可用指纹，且本机没有在用的密码可双签；删掉后此人两种凭证都没了，只能本人到锁前重录。"   // 324 这是该成员名下最后一
            : ""
        confirmDestructive("删除指纹「\(f.name)」",
                           lastWarn + "锁端这条立即作废，不可撤销；本机回收站 \(CredentialOrg.reclaimDays()) 天内找回的是名称/备注/归属这条档案，" +
                           "开门能力只能本人到锁前重录。",   // 670 开门能力只能本人到锁
                           confirmTitle: confirmTitle) { action() }
        return
    }
    let mask = String(v.prefix(max(v.count / 2, 2)))
    let alert = UIAlertController(
        title: "双签验证",   // 323 双签验证
        message: "这是「" + (CredentialOrg.ownerName(f.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(f.owner)) + "」名下最后一枚可用指纹。输入任一在用密码的前 " + String(mask.count) + " 位完成双签。",
        preferredStyle: .alert)
    alert.addTextField { tf in
        tf.placeholder = "在用密码前 " + String(mask.count) + " 位"
        tf.keyboardType = .numberPad
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in
        let input = alert.textFields?.first?.text ?? ""
        if input.hasPrefix(mask) {
            UIPasteboard.general.string = ""
            action()
        } else {
            let fail = UIAlertController(title: "双签未通过", message: "前缀不符, 删除已取消。", preferredStyle: .alert)   // 323 前缀不符
            fail.addAction(UIAlertAction(title: "好", style: .cancel))
            UIApplication.topViewController()?.present(fail, animated: true)
        }
    })
    UIApplication.topViewController()?.present(alert, animated: true)
}


// ================= 指纹工坊 (41 沉浸 / 315 命名建议 / 317 归属先行 / 322 缺失提醒 / 324 冗余横条 / 319 重录继承) =================
struct FpStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    // 515 分步: 0 归属 (317 必选) / 1 沉浸录入 (41) / 2 命名备注 (315/319) / 3 回执
    @State private var step = 0
    @State private var owner: String? = nil
    @State private var presses: [LockService.FpPress] = []
    // 第八十九批: 按钮起的长任务要有句柄 (Sheets 的 StartAddFpView 是同型形状的另一份)。
    // 旧写法是裸 `Task { await start() }`：关页后 fpStart 仍转满 30 秒，然后照样 fpConfirm + 记账 + 弹提示。
    @State private var enrollTask: Task<Void, Never>? = nil
    @State private var busy = false
    @State private var error = ""
    @State private var doneBatch: UInt32?
    // 第八十七批: 录入实际发生在**哪一把锁**上必须记下来。`mac` 是 `app.current?.mac ?? ""` 的计算属性，
    // 而本流程是 sheet，期间当前锁仍可能被外部改掉 (AppIntents / kf:// 深链都会动 app.current)，
    // 服务层的 keys() 也跟随全局当前锁 —— 所以正确做法不是"猜它还一样"，而是写库前验一次、不一致就不写。
    @State private var enrolledMac: String? = nil
    @State private var name = ""
    @State private var note = ""
    @State private var replaceOld = false    // 319 重录继承: 同成员旧指纹移回收站
    /// 319 重录入口: 详情页带原归属进来 (默认 nil=全新录入)
    var prefillOwner: String? = nil
    var prefillReplace = false

    private var mac: String { app.current?.mac ?? "" }
    private var sameOwnerFps: [LedgerFp] {
        owner == nil ? [] : DB.listFps(mac).filter { $0.owner == owner && $0.batch != Int(doneBatch ?? 0) }
    }
    // 317 返回带值: 成员页建完档把 id 存进 pendingFpOwner, 进工坊取走即预选归属
    private func consumePendingOwner() {
        guard let v = app.pendingFpOwner, v != "request" else { return }
        owner = v
        app.pendingFpOwner = nil
    }
    // 319 详情重录: 原归属预选 + 默认勾选替换旧枚
    private func consumePrefill() {
        if let po = prefillOwner, owner == nil { owner = po }
        if prefillReplace { replaceOld = true }
    }

    var body: some View {
        NavigationStack {
            if step == 3 {
                doneCard
            } else if step == 1 {
                immersive
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        StepDots(total: 4, index: step, labels: ["归属", "录入", "命名", "回执"])
                        if step == 0 { step0 }
                        if step == 2 { step2 }
                        navBar
                    }
                    .padding(DS.Space.l)
                }
                .background(DS.Gradient.screen.ignoresSafeArea())
                .axBottomAnchor()   // 870
            }
        }
        .navigationTitle("录入指纹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        // 317/319: 进场取走带回的预选值 (成员页建完档 / 详情页重录)
        .onAppear { consumePendingOwner(); consumePrefill() }
        // 挂在**页面最外层** (不是 immersive 上) —— 挂在步骤子视图上会在录入成功切到第 2 步时
        // 误取消刚跑完的流程; 这里只应在整页被关掉时触发。
        .onDisappear { enrollTask?.cancel() }
    }

    // ---------- 324 冗余横条 + 322 缺失提醒 + 317 归属先行必选 ----------
    @ViewBuilder
    private var step0: some View {
        // 324 冗余横条: 该锁仅剩 1 枚可用指纹时提示补录
        if CredentialOrg.fpCountTotal(mac) == 1 {
            Label {
                Text("这把锁只剩 1 枚可用指纹, 建议补一枚备用")   // 324 这把锁只剩
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bell.badge")
            }
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.warn)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 4)
            .variantCallout(DS.Palette.warn, .control, wash: 0.10)
        }
        // 317 归属先行: 选择器自带"空态就地新建" —— 一个成员都没有时直接弹新增, 不再把人赶去成员中心。
        FpOwnerPicker(mac: mac, owner: $owner)
            .card()
    }

    // ---------- 41 沉浸式录入 (复用 Achievement 的 hero 渐变聚焦语言 + 大圆点) ----------
    private var immersive: some View {
        HeroCard {
            VStack(spacing: DS.Space.xl) {
                Text(progressText)
                    .vkFont(.headline)
                    .foregroundStyle(DS.heroFg)
                VStack(spacing: DS.Space.s) {
                    ProgressView(value: Double(min(presses.count, 8)), total: 8)
                        .tint(DS.heroFg)
                        .frame(maxWidth: 220)
                    HStack(spacing: DS.Space.s) {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(i < presses.count ? DS.heroFg.opacity(0.95) : DS.heroFg.opacity(0.22))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text("请选好的手指按在门锁指纹头上, 抬起, 重复 8 次")   // 41 请选好的手指按在门锁
                    .vkFont(.footnote)
                    .foregroundStyle(DS.heroFg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !error.isEmpty {
                    Label {
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .vkFont(.caption)
                    .foregroundStyle(DS.heroFg)
                    .multilineTextAlignment(.center)
                }
                HStack(spacing: DS.Space.s) {
                    Button {
                        presses = []
                        error = ""
                    } label: {
                        Text("重置进度")
                            .vkFont(.footnote, weight: .medium)
                            .foregroundStyle(DS.heroFg)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        enrollTask = Task { await start() }
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            if busy {
                                ProgressView().tint(DS.heroFg).controlSize(.small)
                            } else {
                                Image(systemName: "touchid")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(DS.heroFg)
                            }
                            Text(busy ? "录入中…" : "开始录入")
                        }
                        .vkFont(.headline)
                        .foregroundStyle(DS.heroFg)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s + 2)
                        .background(DS.heroPlate, in: Capsule())
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(.top, DS.Space.l)
        .animation(DS.Motion.standard, value: presses.count)
    }
    private var progressText: String {
        // 与 StartAddFpView 同一套提示节奏 (APK 第 4 下起要求换到手指边缘):
        // 同一处连按会被锁判 rc=23「无法获取有效的指纹图片」而不计数 —— 换位置是能不能收满 8 次的关键。
        switch presses.count {
        case 0: return "准备就绪"
        case 1...3: return "重复此步骤 (\(presses.count)/8) — 抬起后再按"
        case 4...6: return "第 \(presses.count + 1)/8 次: 把手指的边缘按上去, 换一个位置"
        default: return "第 \(presses.count + 1)/8 次: 再换一个角度"
        }
    }

    // ---------- 315/174 命名建议轮播 + 319 重录继承 ----------
    @ViewBuilder
    private var step2: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("命名 (点按建议填入)")
                .vkFont(.footnote, weight: .semibold)
                .foregroundStyle(DS.Palette.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(suggestionPool, id: \.self) { sug in
                        Button {
                            name = sug
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Text(sug)
                                .vkFont(.caption, weight: .medium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(name == sug ? DS.Palette.onAccent : DS.Palette.accentText)
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, 4)
                                .background(name == sug ? DS.Palette.accent : DS.Palette.accentText.opacity(0.10), in: Capsule())
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("建议名 \(sug)")
                        .accessibilityAddTraits(name == sug ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, DS.Space.xs)
            }
            TextField("自定义名称", text: $name, prompt: Text("如: 妈妈·左手食指"))
                .vkFont(.subheadline)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
            TextField("备注", text: $note, prompt: Text("仅本机留存"))   // 179 备注
                .vkFont(.subheadline)
                .frame(minHeight: DS.Hit.min)
            // 319 重录继承: 同成员已有指纹 → 成功后旧指纹入回收站 (保留原备注/归属, 来源"重录替代")
            if !sameOwnerFps.isEmpty {
                VariantToggle("该成员已有 \(sameOwnerFps.count) 枚指纹, 录入成功后将旧指纹移入回收站 (重录继承, 保留原备注/归属)", isOn: $replaceOld)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
    private var suggestionPool: [String] {
        var out: [String] = []
        for extra in 0..<3 {
            let s = CredentialOrg.fpNameSuggestion(mac, owner: owner, extra: extra)
            if !out.contains(s) { out.append(s) }
        }
        return out
    }

    private var doneCard: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DS.Icon.xl))
                .foregroundStyle(DS.Palette.ok)
                .accessibilityHidden(true)
            Text("已登记为「\(name.isEmpty ? fallbackName : name)」")
                .vkFont(.headline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("请用新指纹开一次锁, 确认可用。" + (replaceOld ? " 旧指纹已移入回收站。" : ""))   // 319 旧指纹已移入回收站
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("完成") { dismiss() }
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            Spacer(minLength: 0)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity)
        .background(DS.Gradient.screen.ignoresSafeArea())
    }
    private var fallbackName: String { "指纹" + String(doneBatch ?? 0) }

    private var navBar: some View {
        HStack(spacing: DS.Space.s) {
            if step > 0 {
                Button("上一步") {
                    withAnimation(DS.Motion.quick) { step -= 1 }
                }
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step == 0 {
                Button("下一步: 录入") {
                    guard owner != nil || DB.members().isEmpty else {
                        app.showToast("先选归属成员")   // 317 先选归属成员
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    withAnimation(DS.Motion.quick) { step = 1 }
                    DS.Haptics.tick.impactOccurred()
                }
                .vkFont(.subheadline, weight: .semibold)
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
            if step == 2 {
                Button("保存登记") { saveAndClose() }
                    .vkFont(.subheadline, weight: .semibold)
                    .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func saveAndClose() {
        guard let b = doneBatch else { return }
        // fail-closed: 录入到保存之间当前锁变了 (或压根没记下是哪把锁)，就不写库 ——
        // 把 A 锁的批次号记进 B 锁台账，比"这次白录"糟得多；此处宁可让用户重开一页。
        guard let em = enrolledMac, em == app.current?.mac else {
            error = "当前锁已改变，本次录入不写入台账，请关闭后重新录入"
            return
        }
        let finalName = name.isEmpty ? CredentialOrg.fpNameSuggestion(em, owner: owner) : name
        // 来源口径：这一行写进台账的批次号来自上面同一流程的 fpStart/fpConfirm —— 锁端已经启用过这批指纹，
        // 只是隔了第 3 步的命名才落库 (lockpair 的窗口看不到那么远，故在此写明，不是漏发命令)。
        DB.addFp(em, LedgerFp(batch: Int(b), name: finalName, at: Date().timeIntervalSince1970 * 1000,
                              note: note, src: "app", owner: owner, isAlarm: false))
        if name.isEmpty {
            app.showToast("已按建议命名「\(finalName)」, 可重命名")   // 315/174 已按建议命名
        }
        // 319 重录继承: 同成员旧指纹入回收站 (来源"重录替代") + 锁端删除入队
        if replaceOld {
            // 先把待清旧的筛成局部量再遍历: 原写法把 filter 的尾随闭包贴在 for 语句后面,
            // 编译器都怀疑人要看错 (trailing closure in this context is confusable)
            let staleFps = DB.listFps(em).filter { $0.owner == owner && $0.batch != Int(b) }
            for f in staleFps {
                // 确认口径：这一刀是用户在上一步**自己勾上**的 (录入第 2 步那条 Toggle 的文案就把后果写全了：
                // 「录入成功后将旧指纹移入回收站 (319 重录继承, 保留原备注/归属)」) ⇒ 勾选即知情同意，
                // 再弹一次确认是把同一句话问两遍。可逆性也在那里兜住：addToBin 在前、锁端删除只是入队，
                // 还原时第一百五十二批的 reclaim 会把这条还没发出去的 del_fp 一并收回。
                CredentialOrg.addToBin(em, fp: f, source: .rererecord)
                DB.delFp(em, f.batch)
                CredentialOrg.enqueue(em, kind: "del_fp", title: "删除旧指纹批次 \(f.batch)", fp: f)   // 319 删除旧指纹批次
            }
            app.showToast("旧指纹已移入回收站 (备注/归属保留)")
        }
        withAnimation(DS.Motion.standard) { step = 3 }
    }

    private func start() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        error = ""
        // 重试必须清空: onPress 是**累加**式回填，不清就会数出"9/8"这种读数 (旧写法整批赋值不会)
        presses = []
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            // 留存口径：录入这两步**故意不写台账** —— 批次要等第 3 步命名与归属填完才落 DB.addFp，
            // 中途关页 (上面 89 批那道 cancel 检查) 就该本机一条不留。lockpair 扫到这里时读这句。
            // onPress: 沉浸页那 8 个点随每帧亮起 (旧写法等整个调用返回才赋值，录入全程恒 0 个点)
            // 窗口口径在 LockService.fpStart 里 (首帧 8s / 两次按压 16s, 对齐 APK Java 接收计时器)
            let ps = try await app.lock.fpStart(times: 8,
                                                onPress: { p in
                                                    self.presses.append(p)
                                                    DS.Haptics.tick.impactOccurred()   // 手指在锁上, 屏幕看不见
                                                })
            self.presses = ps
            // 14 会把这一批指纹真正启用: 不满 8 次按压的批次不确认
            guard presses.count >= 8 else {
                throw NSError(domain: "fp", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "只收到 \(presses.count)/8 次按压, 未写入; 请重新录入并多按几次"])
            }
            guard let batch = ps.compactMap({ $0.batchNumber }).first, batch > 0 else {
                throw NSError(domain: "fp", code: 1, userInfo: [NSLocalizedDescriptionKey: "未拿到有效指纹批次, 请重新录入"])
            }
            // 第八十九批: 关页 (enrollTask?.cancel()) 后**不越过这个不可逆点** ——
            // fpConfirm 会真正启用这批指纹并写本机台账，不该在用户已经退出后代他做。
            if Task.isCancelled {
                presses = []
                return
            }
            try await app.lock.fpConfirm(batch, validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00")
            // 留存口径：与上面 fpStart 同一句 —— 台账要到第 3 步命名与归属填完才写 DB.addFp，这里不提前落一条无名指纹
            doneBatch = batch
            enrolledMac = kc.mac
            // 命名建议数的是**这把锁**上已有的指纹数 (315/174)，读活读的 mac 会在中途切锁时
            // 给出另一把锁的编号 —— 第八十八批把 macpin 的豁免条件收窄后自己露出来的这一处
            name = CredentialOrg.fpNameSuggestion(kc.mac, owner: owner)
            note = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(DS.Motion.standard) { step = 2 }
        } catch {
            self.error = error.localizedDescription
        }
    }
}


// Double 台账毫秒 → 本地日期串 (凭证页同源, 局部实现)
private extension Double {
    func credDay() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: self / 1000))
    }
}

// ================= OTP 工坊 (171/337 ⚠ 时窗细条 / 340 双码 / 341 otpauth / 343 独立组 / 345 参数小字 / 346 静态备份码) =================
struct OtpStudio: View {
    @ObservedObject private var cap = ScreenCaptureWatch.shared   // 374: 当前码与下一码都是可用口令
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    // 337/171: `tick` 是**刷新驱动器**——每秒写它一次就够 (写 @State 即让本 view 重算 body,
    // 于是每行的 StudioTools.totp 重新取值)。它不再是视图身份 (原来挂在 totpRow 上的 .id(tick) 已撤, 理由写在那儿)。
    @State private var tick = Date()
    @State private var importing = false
    @State private var importUri = ""
    @State private var importErr = ""
    // 341 手工添加 (341) 的五个字段 + **独立**错误行: 不与 otpauth 导入共用 importErr ——
    // 两个入口的失败原因不是一回事, 共用一根线就会互相盖掉对方那句话。
    @State private var showManual = false
    @State private var manualName = ""
    @State private var manualSecret = ""
    @State private var manualAlgo = "SHA1"
    @State private var manualPeriod = 30
    @State private var manualDigits = 6
    @State private var manualErr = ""
    @State private var noteDraft = ""   // 346 建档时就写备注
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var mac: String { app.current?.mac ?? "" }
    /// 339 独立口令的**存档目标锁**: 空 = 跟随当前锁; 顶部选择器可换成另一把。
    /// 口令按锁存档 (kf_cotp_t_<mac>), 所以"给哪把锁录"必须能显式选 —— 否则只能靠切当前锁来换存档位。
    @State private var targetMac: String = ""
    private var otpMac: String { targetMac.isEmpty ? mac : targetMac }

    var body: some View {
        NavigationStack {
            List {
                // 339 用于哪把锁: 独立口令按锁存档, 这里显式选一次 (只多锁时出现)
                if DB.keychains().count > 1 {
                    Section("用于哪把锁") {   // 339 用于哪把锁
                        Picker("", selection: Binding(get: { otpMac }, set: { targetMac = $0 })) {
                            ForEach(DB.keychains(), id: \.mac) { kc in
                                Text(LockArchive.displayName(kc)).tag(kc.mac)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: DS.Hit.min)
                        Text("独立口令按锁存档 (kf_cotp_t_) —— 备份也按锁导出, 换一把锁就是另一组口令。")
                            .vkFont(.caption2)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // 锁端 ZOTP 时窗 (⚠ 锁端为分钟级, 细条为本地时钟推断标"约")
                if DB.otpStatus(mac)?.on == true {
                    Section("锁端 ZOTP (30 分钟时窗)") {
                        VStack(spacing: DS.Space.xs) {
                            WindowBar(totalSec: 1800, label: "337 时窗细条 · 末 5 秒转橙轻震 (⚠ 锁端分钟级, 约)")
                            Text("每 30 分钟更换; 生成前请校准门锁时间, 偏差 >180 秒锁侧校验失败。")
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // 343 独立口令组: 口令与锁协议无关, 但**按当前锁存档** —— 小字照实写, 不再说"与锁无关"就完事
                Section {
                    let list = CredentialOrg.totpEntries(otpMac)   // 339: 按选择的目标锁取组
                    if list.isEmpty {
                        Text("还没有独立口令。粘贴 otpauth:// 文本导入, 或手工添加。口令本身跟门锁协议无关 (手机自己算), 但它按当前这把锁存档 —— 换锁就是另一组。")   // 341 还没有独立口令
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(list) { e in
                        totpRow(e)
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("导入 otpauth:// 文本", systemImage: "square.and.arrow.down")   // 341 导入
                    }
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    // 341 手工添加整段: 名称 / Base32 密钥 / 算法 / 周期 / 位数, 错误行与导入那条各走各的
                    Button {
                        showManual.toggle()
                        if !showManual { manualErr = "" }
                        DS.Haptics.tick.impactOccurred()
                    } label: {
                        // 341 收起手工添加
                        // 341 手工添加
                        Label(showManual ? "收起手工添加" : "手工添加", systemImage: "keyboard")
                    }
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    if showManual { manualForm() }
                } header: {
                    Text("独立口令 (与锁协议无关 · 按当前锁存档)")
                } footer: {
                    Text("组尾实话: 这些口令不经过门锁、也不进锁端协议, 但存的键带锁的 MAC (kf_cotp_t_) —— 因为备份按锁导出。换一把锁, 这一组就换成另一把锁的那一组。")
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 346 静态备份码: 本地生成一次性静态码, 不走锁端, 随备份导出
                Section("静态备份码") {   // 346 静态备份码
                    // 2026-10-13 对抗式点击审计: 原写 `staticCodes(mac)` 而写入用 `addStaticCode(otpMac, …)`
                    // —— 读的是**当前锁**、写的是 Picker 选的**目标锁**。用户路径: OTP 与口令页 →
                    // 「用于哪把锁 (339)」Picker 改选另一把锁 → 点「生成 8 位静态码」→
                    // 新码写进目标锁, 当前列表不显示 (切回目标锁才出现), 而编号 `codes.count + 1`
                    // 还是按当前锁的数量算的 ⇒ 编号也可能重名。读取改成语入一致的 otpMac。
                    let codes = CredentialOrg.staticCodes(otpMac)
                    ForEach(codes) { c in
                        staticRow(c)
                    }
                    TextField("备注 (给谁/干什么)", text: $noteDraft, prompt: Text("仅本机留存"))
                        .vkFont(.subheadline)
                        .frame(minHeight: DS.Hit.min)
                    Button {
                        let name = "备份码 " + String(codes.count + 1)
                        CredentialOrg.addStaticCode(otpMac, CredentialOrg.StaticCode(
                            id: UUID().uuidString, name: name,
                            code: StudioTools.genDigits(8), note: noteDraft, used: false,
                            at: Date().timeIntervalSince1970))
                        noteDraft = ""
                        app.showToast("已生成 8 位静态备份码")   // 346 已生成
                    } label: {
                        Label("生成 8 位静态码", systemImage: "plus")
                    }
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                                    }
            }
            .navigationTitle("OTP 与口令")
            .variantList()
            .dsScreenBackground()
            .axBottomAnchor()   // 870
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onReceive(timer) { t in tick = t }
            .sheet(isPresented: $importing) {
                NavigationStack {
                    Form {
                        Section("粘贴 otpauth 文本") {   // 341 粘贴
                            TextField("otpauth://totp/…?secret=…", text: $importUri, axis: .vertical)
                                .vkFont(.footnote)
                                .autocorrectionDisabled()
                        }
                        if !importErr.isEmpty {
                            Section {
                                Label(importErr, systemImage: "exclamationmark.circle")
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.danger)
                            }
                        }
                        Section {
                            Button("导入") {
                                switch StudioTools.parseOtpAuth(importUri) {
                                case .success(let r):
                                    CredentialOrg.addTotp(otpMac, CredentialOrg.TOTPEntry(
                                        id: UUID().uuidString, name: r.name, secret: r.secret,
                                        algo: r.algo, period: r.period, digits: r.digits,
                                        at: Date().timeIntervalSince1970))
                                    // 341: 补了默认值就必须点名补了哪几项 —— 只报"已导入"是把替用户做的决定藏起来。
                                    let tail = r.defaulted.isEmpty ? "" : "; 这条 uri 没写, 按默认补了: " + r.defaulted.joined(separator: ", ")
                                    app.showToast("已导入「\(r.name)」(\(r.algo)·\(r.digits)位·\(r.period)s)" + tail + " (按当前锁存档)")
                                    importUri = ""
                                    importErr = ""
                                    importing = false
                                case .failure(let f):
                                    importErr = "导入失败: " + f.rawValue + "; 缺什么就补什么, 或直接关掉这里改用手工添加"   // 341 导入失败
                                }
                            }
                            .vkFont(.subheadline, weight: .medium)
                        }
                    }
                    .navigationTitle("导入 otpauth")   // 341 导入
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { importing = false }
                    } }
                }
            }
        }
    }

    // ---------- 341 手工添加整段 (名称 / Base32 密钥 / 算法 / 周期 / 位数) ----------
    /// 与导入那条走**同一份** TOTPEntry 与同一个 `CredentialOrg.addTotp` 出口, 只是字段由人填。
    /// 校验只认真实缺失点 (空密钥 / Base32 非法), 报错落在本段自己的错误行上。
    @ViewBuilder
    private func manualForm() -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            TextField("名称", text: $manualName, prompt: Text("如: 验证器·登录码 (留空按密钥尾段命名)"))
                .vkFont(.subheadline)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
            TextField("Base32 密钥", text: $manualSecret, prompt: Text("验证器里那串 A-Z 与 2-7"))
                .vkFont(.footnote.monospaced())
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Picker("算法", selection: $manualAlgo) {
                ForEach(["SHA1", "SHA256", "SHA512"], id: \.self) { a in
                    Text(a).tag(a)
                }
            }
            .vkFont(.caption)
            HStack(spacing: DS.Space.xs) {
                // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
                // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
                Picker("周期", selection: $manualPeriod) {
                    ForEach([30, 60], id: \.self) { p in
                        Text("\(p) 秒").tag(p)
                    }
                }
                // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
                // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
                Picker("位数", selection: $manualDigits) {
                    ForEach([6, 8], id: \.self) { d in
                        Text("\(d) 位").tag(d)
                    }
                }
            }
            .vkFont(.caption)
            if !manualErr.isEmpty {
                Label(manualErr, systemImage: "exclamationmark.circle.fill")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(manualErr)
            }
            Button {
                addManualTotp()
            } label: {
                Label("保存这条独立口令", systemImage: "plus.circle")
            }
            .vkFont(.subheadline, weight: .medium)
            .foregroundStyle(DS.Palette.accentText)
            .frame(minHeight: DS.Hit.min)
            Text("算法与周期按你选的这几档算 (RFC 6238 常用档); 锁端 ZOTP 仍走分钟级, 两者互不相干。")   // 337 算法与周期按你选的这
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DS.Space.xs)
    }
    private func addManualTotp() {
        let secret = manualSecret.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
        guard !secret.isEmpty else {
            manualErr = "密钥是空的: 请粘贴验证器给出的那串 Base32"   // 341 密钥是空的
            DS.Haptics.trigger.impactOccurred()
            return
        }
        guard StudioTools.base32Decode(secret) != nil else {
            manualErr = "密钥不是合法 Base32: 只允许 A-Z 与 2-7, 这里出现了字母表外的字符"   // 341 密钥不是合法
            DS.Haptics.trigger.impactOccurred()
            return
        }
        let typed = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = typed.isEmpty ? StudioTools.fallbackName(secret) : typed
        CredentialOrg.addTotp(otpMac, CredentialOrg.TOTPEntry(
            id: UUID().uuidString, name: named, secret: secret,
            algo: manualAlgo, period: manualPeriod, digits: manualDigits,
            at: Date().timeIntervalSince1970))
        manualErr = ""
        // 名称是回退来的就说回退, 参数照实报 —— 用户填的与他看到的必须是同一份。
        app.showToast((typed.isEmpty ? "已添加「\(named)」(名称按密钥尾段回退)" : "已添加「\(named)」")   // 341 已添加
            + " · \(manualAlgo)·\(manualDigits)位·\(manualPeriod)s, 按当前锁存档")   // 343 按当前锁存档
        manualName = ""
        manualSecret = ""
        showManual = false
        DS.Haptics.tick.impactOccurred()
    }

    // 340 双码并排 (当前+下一时窗, 各标剩余) / 345 参数小字
    private func totpRow(_ e: CredentialOrg.TOTPEntry) -> some View {
        let now = StudioTools.totp(e, offset: 0)
        let next = StudioTools.totp(e, offset: 1)
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(e.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                // 338 单击即复制 (拍板: **不改行的点击语义**) —— 只把码值这一块做成整块可点的复制区，
                // 行本身不当事件源；下面那个「复制」按钮保留，给 VoiceOver 和不想瞄准的人。
                Button {
                    ClipboardCare.copySecret(now, via: "独立 TOTP")   // 405 同一出口
                    app.showToast("已复制当前码")   // 338 已复制当前码
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Text(cap.recording ? "已隐去" : now)   // 374 已隐去
                            .vkFont(.title3.monospacedDigit(), weight: .semibold)
                            .foregroundStyle(DS.Palette.text)
                            .textSelection(.enabled)
                        Text("↓")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Text(cap.recording ? "已隐去" : next)   // 374 已隐去
                            .vkFont(.title3.monospacedDigit(), weight: .semibold)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .padding(.horizontal, DS.Space.xs)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制当前码 \(e.name)")
            }
            WindowBar(totalSec: max(e.period, 1), label: "当前/下一时窗并排 · " + CredentialOrg.totpParams(e))
            HStack(spacing: DS.Space.xs) {
                Button {
                    ClipboardCare.copySecret(now, via: "独立 TOTP")   // 405
                    app.showToast("已复制当前码")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .vkFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeTotp(otpMac, e.id)   // 339: 与取组的锁保持一致
                    app.showToast("已移除「\(e.name)」")
                } label: {
                    Label("移除", systemImage: "trash")
                }
                .vkFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("移除独立口令 \(e.name)")
            }
        }
        // 337: 这里**不能再挂 `.id(tick)`** (原先每秒给它换一次视图身份)。
        // 挂了之后 WindowBar 每 1 秒被当成一个全新视图重建, 它内部 `@State now` 与那条 1 秒定时器
        // 一起回到初值 ⇒ `old > 5 → 新值 ≤ 5` 这一跨越永远观测不到, 末 5 秒轻震与转橙从来就没真响过。
        // 去掉 id 后父级 `tick` 仍每秒改一次状态、body 照样每秒重算, 码值与细条刷新不受影响 (337/171)。
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.name), 当前码 \(now), 下一码 \(next), \(CredentialOrg.totpParams(e))")
    }
    private func staticRow(_ c: CredentialOrg.StaticCode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Space.s) {
                Text((c.used ? "已用 · " : "") + c.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(c.used ? DS.Palette.textSub : DS.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(c.code)
                    .vkFont(.title3.monospacedDigit(), weight: .semibold)
                    .foregroundStyle(c.used ? DS.Palette.textSub : DS.Palette.text)
                    .textSelection(.enabled)
            }
            if !c.note.isEmpty {
                Text(c.note)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: DS.Space.xs) {
                Button {
                    var n = c; n.used = true
                    CredentialOrg.saveStaticCodes(mac, CredentialOrg.staticCodes(mac).map { $0.id == c.id ? n : $0 })
                    app.showToast("已标记「\(c.name)」为已用")   // 346 已标记
                } label: {
                    Label(c.used ? "撤销已用" : "标记已用", systemImage: c.used ? "arrow.uturn.left" : "checkmark")
                }
                .vkFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeStaticCode(mac, c.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .vkFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("删除静态码 \(c.name)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}


