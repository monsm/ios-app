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
        HStack(spacing: XSpace.xs) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i <= index ? XPalette.accent : XPalette.hairline)
                    .frame(width: 7, height: 7)
            }
            Text("第 \(index + 1)/\(total) 步" + (labels.indices.contains(index) ? " · \(labels[index])" : ""))
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
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
        HStack(spacing: XSpace.xs) {
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
                    XHaptics.tick.impactOccurred()
                } label: {
                    Text(shown)
                        .xFont(digitFont)
                        .foregroundStyle(on ? XPalette.text : XPalette.textSub)
                        .frame(width: big ? 36 : 30)
                        .frame(minHeight: XHit.min)
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
                Capsule().fill(remaining(now) <= 5 ? XPalette.warn : XPalette.accent)
                    .frame(height: 4)
                    .frame(width: max(CGFloat(remaining(now)) / CGFloat(max(totalSec, 1)) * geo.size.width, 0))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 4)
            .animation(XMotion.exit, value: remaining(now))
            HStack(spacing: XSpace.xs) {
                Text(label)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("剩约 \(remaining(now)) 秒")
                    .xFont(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
            }
        }
        .onReceive(timer) { t in
            let old = remaining(now)
            now = t
            if remaining(t) <= 5 && old > 5 && remaining(t) > 0 {
                XHaptics.tick.impactOccurred()   // 337 末 5 秒轻震
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
        VStack(spacing: XSpace.s) {
            Text(title)
                .xFont(.subheadline, weight: .semibold)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(revealed ? code : SecurityPolicy.halfMasked(code))
                .xFont(.system(.largeTitle, design: .rounded).monospacedDigit(), weight: .semibold)
                .foregroundStyle(XPalette.text)
                .textSelection(.enabled)
                // 370: 口述卡这一路也接贴近复蔽 (卡片在屏期间才开监听)
                .proximityRemask { revealed = false }
            Text(window)
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !note.isEmpty {
                Text(note)
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(2)
            }
            HStack(spacing: XSpace.s) {
                Button {
                    revealed.toggle()
                    XHaptics.tick.impactOccurred()
                } label: {
                    Label(revealed ? "再遮起来" : "完整显示",
                          systemImage: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .xFont(.caption)
                .frame(minHeight: XHit.min)
                .accessibilityLabel(revealed ? "重新遮挡码值" : "完整显示码值")
                Button {
                    ClipboardCare.copySecret(revealed ? code : SecurityPolicy.halfMasked(code), via: "工作室 TOTP")   // 405
                    app.showToast(revealed ? "码值已复制" : "已复制遮半码值 (完整值先点「完整显示」)")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .xFont(.caption)
                .frame(minHeight: XHit.min)
                .accessibilityLabel("复制码值")
                ShareLink(item: shareText) {
                    Label("分享口述卡", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .xFont(.caption)
                .frame(minHeight: XHit.min)
                .accessibilityLabel("分享口述卡")
            }
            let foot = extraFoot.isEmpty ? "大字号方便对准锁键盘输入; 本卡含密码, 拍照或分享后注意保管。" : extraFoot
            Text(foot)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(XSpace.l)
        .frame(maxWidth: .infinity)
        // 2026-10-14 材质统一: 口述卡与本页其余 13 块 .card() 同材质 (原先独此一块自带描边)。
        // 大字号密码在玻璃上仍读得清: glassEffect(.regular) 会自己压一层调暗底,
        // 而 226 降透明 / 862 增强对比下 axGlass 直接落回实底 —— 拍照那张最讲究可读的场合有退路。
        .axGlass(XRadius.card)
        .shadow(color: XPalette.accent.opacity(0.14), radius: 10, y: 5)
        .padding(.horizontal, XSpace.gutter)
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
        padding(XSpace.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .axGlass(XRadius.card)
            .shadow(color: XPalette.accent.opacity(0.08), radius: 8, y: 4)
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
            VStack(alignment: .leading, spacing: XSpace.l) {
                // 容量提示 —— 临时码与常驻密码**共用同一份库存**（协议 0x25 pwdStock），
                // 原来这页完全不显示还剩几个坑位，用户会填完表单才被锁端拒绝。
                if let snap = DB.readStatus(mac), let cap = snap.pwdCap, cap > 0 {
                    let left = snap.pwdStock
                    let used = max(0, cap - left)
                    Label {
                        Text(left == 0
                             ? "密码库存已满 — 临时码也占同一个池子，请先删一条"
                             : "还可建 " + String(left) + " 个 · 已用 " + String(used) + " / " + String(cap))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "number.square")
                    }
                    .xFont(.caption)
                    .foregroundStyle(left == 0 ? XPalette.warn : XPalette.textSub)
                    .padding(.horizontal, XSpace.s)
                    .padding(.vertical, 4)
                    .xCallout(left == 0 ? XPalette.warn : XPalette.hairline, .control, wash: left == 0 ? 0.10 : 0.06)
                }

                // 325 五场景预设
                VStack(alignment: .leading, spacing: XSpace.xs) {
                    Text("场景预设 (选中即套默认时长与备注)")
                        .xFont(.footnote, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: XSpace.xs)], spacing: XSpace.xs) {
                        ForEach(StudioTools.scenes) { s in
                            sceneChip(s)
                        }
                    }
                }
                .card()

                // 码值 (301 剪贴板即建 + 303 回显 + 173 生成 + 522 扫号 + 516 数字键盘)
                VStack(alignment: .leading, spacing: XSpace.xs) {
                    HStack(spacing: XSpace.s) {
                        Text("码值 (6~8 位数字)")
                            .xFont(.footnote, weight: .semibold)
                            .foregroundStyle(XPalette.text)
                        Spacer(minLength: 0)
                        Text(pwdOK ? "✓ 位数合规" : "6~8 位数字")
                            .xFont(.caption2)
                            .foregroundStyle(pwdOK ? XPalette.ok : XPalette.textSub)
                            .lineLimit(1)
                    }
                    if !pwd.isEmpty {
                        MaskedDigits(value: pwd, big: true)
                    }
                    TextField("输入码值, 或点「生成」", text: $pwd, prompt: Text("输入 6~8 位数字"))   // 516 输入
                        .keyboardType(.numberPad)
                        .xFont(.title3.monospacedDigit(), weight: .semibold)
                        .frame(minHeight: XHit.min)
                        .autocorrectionDisabled()
                    if clipSource {
                        HStack(spacing: XSpace.xs) {
                            Label("来自剪贴板 · 已识别为候选码", systemImage: "doc.on.clipboard")   // 301 来自剪贴板
                                .xFont(.caption)
                                .foregroundStyle(XPalette.warn)
                            Spacer(minLength: 0)
                            Button("清除") { pwd = ""; clipSource = false }
                                .xFont(.caption, weight: .medium)
                                .foregroundStyle(XPalette.accentText)
                                .frame(minHeight: XHit.min)
                                .contentShape(Rectangle())
                        }
                        .padding(.horizontal, XSpace.s)
                        .padding(.vertical, 4)
                        .xCallout(XPalette.warn, .control, wash: 0.10)
                        .accessibilityLabel("码值来自剪贴板, 点清除可移除")
                    }
                    HStack(spacing: XSpace.xs) {
                        Button("生成") {   // 173 生成
                            pwd = StudioTools.genDigits(6)
                            clipSource = false
                        }
                        .xFont(.caption, weight: .medium)
                        .buttonStyle(.bordered)
                        .frame(minHeight: XHit.min)
                        .accessibilityLabel("本地生成 6 位随机码")   // 173 本地生成
                        Button("扫一扫") { showScan = true }   // 522 扫一扫
                            .xFont(.caption, weight: .medium)
                            .buttonStyle(.bordered)
                            .frame(minHeight: XHit.min)
                            .accessibilityLabel("相机识别印刷码")   // 522 相机识别印刷码
                        Spacer(minLength: 0)
                    }
                    // 178 批量临时码 (锁端无批量命令, 走既有 0A 逐条, 失败逐条报)
                    HStack(spacing: XSpace.xs) {
                        Text("一次生成")   // 178 一次生成
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                        ForEach([1, 2, 3, 5], id: \.self) { n in
                            Button(String(n)) { batchCount = n }
                                .xFont(.caption.weight(batchCount == n ? .semibold : .medium))
                                .buttonStyle(.bordered)
                                .frame(minHeight: XHit.min)
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
                            .xFont(.caption)
                            .foregroundStyle(XPalette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dups.isEmpty {
                        // 304 查看即跳: 不再只给一句"建议换一组", 真把同值那条的详情打开
                        HStack(spacing: XSpace.xs) {
                            Label("本锁已有 \(dups.count) 条同值凭证, 建议换一组", systemImage: "plus.slash.minus")   // 304 本锁已有
                                .xFont(.caption)
                                .foregroundStyle(XPalette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("查看") {
                                app.pendingCredNav = "pwd:\(dups[0].alias)"
                                app.pendingCredNavMac = mac
                                app.requestRoute(.credentials)   // 2026-10-15 走查: 同上, 统一走 requestRoute
                                dismiss()
                            }
                            .xFont(.caption, weight: .medium)
                            .foregroundStyle(XPalette.accentText)
                            .frame(minHeight: XHit.min)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .card()

                // 时段 (520 快捷 + 327 重叠 + 330 装修黄条)
                VStack(alignment: .leading, spacing: XSpace.xs) {
                    Text("生效时段")
                        .xFont(.footnote, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                    HStack(spacing: XSpace.xs) {
                        quickPill("1 小时") { from = Date(); to = Date().addingTimeInterval(3600) }
                        quickPill("今天内") { from = Date(); to = TimeFormat.dayEnd() }   // 终点单一出口 (520/828)
                        quickPill("7 天") { from = Date(); to = Date().addingTimeInterval(7 * 86400) }
                        quickPill("30 天") { from = Date(); to = Date().addingTimeInterval(30 * 86400) }
                    }
                    HStack(spacing: XSpace.s) {
                        Text(isoShort(from, prefix: "生效 "))
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("→")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                        Text(isoShort(to, prefix: "到期 "))
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    if to <= from {
                        Label("到期需晚于生效", systemImage: "exclamationmark.circle.fill")   // 519 到期需晚于生效
                            .xFont(.caption)
                            .foregroundStyle(XPalette.danger)
                    }
                    // 327 租期重叠检测
                    if !overlaps.isEmpty {
                        Label {
                            Text("与本成员其它 \(overlaps.count) 张码时段撞车")   // 327 与本成员其它
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .xFont(.caption)
                        .foregroundStyle(XPalette.warn)
                    }
                    // 330 装修黄条
                    if scene == "reno" {
                        Label("长期工场景: 详情页挂「施工中」黄条, 建议 30 天内复查一次", systemImage: "paintbrush")   // 330 长期工场景
                            .xFont(.caption)
                            .foregroundStyle(XPalette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()

                // 归属与备注 (317 归属先行 + 179 占位)
                VStack(alignment: .leading, spacing: XSpace.xs) {
                    Text("归属与备注")
                        .xFont(.footnote, weight: .semibold)
                        .foregroundStyle(XPalette.text)
                    ForEach(DB.members()) { m in
                        Button {
                            owner = m.id
                        } label: {
                            HStack(spacing: XSpace.s) {
                                Text(m.name)
                                    .xFont(.subheadline)
                                    .foregroundStyle(XPalette.text)
                                Spacer(minLength: 0)
                                if owner == m.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: XIcon.sm, weight: .medium))
                                        .foregroundStyle(XPalette.accentText)
                                }
                            }
                            .frame(minHeight: XHit.min)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("归属 " + m.name + (owner == m.id ? ", 已选" : ""))
                    }
                    TextField("给谁 · 哪扇门 · 用多久 (可长按调听写)", text: $note,
                              prompt: Text(scene.isEmpty ? "如: 钟点工·大门·仅上午场" : sceneNote))
                        .xFont(.subheadline)
                        .frame(minHeight: XHit.min)
                        .autocorrectionDisabled()
                }
                .card()

                XBusyButton(title: batchCount > 1 ? "下发 \(batchCount) 张" : "下发临时码",   // 178 下发
                           systemImage: "clock.badge.chevron.right", busy: busy) {
                    Task { await submitBatch() }
                }
                .disabled(!pwdOK || to <= from)
                Text("请将手机靠近门锁; 批量走既有 0A 逐条下发, 锁端无批量命令, 失败逐条报。")   // 178 请将手机靠近门锁
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(XSpace.l)
        }
        .background(XPalette.canvas.ignoresSafeArea())
        .axBottomAnchor()   // 870
        .onAppear { checkClipboard() }
    }

    private func sceneChip(_ s: StudioTools.SceneDef) -> some View {
        Button {
            scene = s.key
            from = Date()
            to = Date().addingTimeInterval(TimeInterval(s.hours * 3600))
            if note.isEmpty { note = s.note }
            XHaptics.tick.impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .xFont(.footnote, weight: .semibold)
                    .lineLimit(1)
                Text(s.hint)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, XSpace.s)
            .padding(.vertical, XSpace.xs + 2)
            .foregroundStyle(scene == s.key ? XPalette.onAccent : XPalette.text)
            .background(scene == s.key ? XPalette.accent : XPalette.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("场景 \(s.name): \(s.hint)")   // 325 场景
        .accessibilityAddTraits(scene == s.key ? [.isSelected] : [])
    }
    private func quickPill(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button {
            act()
            XHaptics.tick.impactOccurred()
        } label: {
            Text(t)
                .xFont(.caption, weight: .medium)
                .foregroundStyle(XPalette.accentText)
                .padding(.horizontal, XSpace.s)
                .padding(.vertical, 4)
                .xPlate(XPalette.accentText.opacity(0.10), .capsule)
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷时长 \(t)")   // 520 快捷时长
    }

    // ---------- 完成页: 172/328 大字口述卡 + 329 一句话 + 333 首用回执 (⚠ 按时间推断标"约") ----------
    private var doneCard: some View {
        ScrollView {
            VStack(spacing: XSpace.l) {
                CodeBigCard(title: "\(lockName) · 临时码", code: result?.pwd ?? pwd,
                            window: "\(isoShort(from)) ~ \(isoShort(to)) 生效",
                            note: note,
                            extraFoot: batchCount > 1 ? "批量共 \(batchCount) 张, 其余已逐张下发" : "")
                if MemberHub.elderMode {
                    // 486 代际完成页切换: 长辈模式下完成页默认形态 = 口述卡 (页标题也切到「口述卡」) + 一枚大「完成」;
                    // 329/333/再发一张 是常规形态的入口, 这一档收起来并在原地说明 —— 收了不吭声就是本仓反复犯的无声忽略。
                    Button("完成") { dismiss() }
                        .buttonStyle(XPrimaryButtonStyle())
                    // 329 常规模式这里还有
                    // 333 常规模式这里还有
                    // 486 常规模式这里还有
                    Text("常规模式这里还有 一句话口令 / 首用回执 / 再发一张 — 长辈模式下不显示。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
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
                        VStack(spacing: XSpace.xs) {
                            Text("生成一句话口令")   // 329 生成一句话口令
                                .xFont(.footnote, weight: .semibold)
                                .foregroundStyle(XPalette.accentText)
                            Text("“" + text + "”")
                                .xFont(.caption)
                                .foregroundStyle(XPalette.textSub)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: XHit.min + 8)
                        .contentShape(Rectangle())
                        .padding(.vertical, XSpace.s)
                        .xPlate(XPalette.surfaceAlt, .control)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, XSpace.gutter)
                    .accessibilityLabel("复制一句话口令: " + text)
                    // 329 分享面板: 系统分享单 (与 405 复制同源明文, 发给家人用)
                    ShareLink(item: text) {
                        Label("分享一句话口令", systemImage: "square.and.arrow.up")   // 329 分享一句话口令
                            .xFont(.footnote, weight: .medium)
                            .foregroundStyle(XPalette.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: XHit.min)
                            .padding(.vertical, XSpace.s)
                            .xPlate(XPalette.surfaceAlt, .control)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, XSpace.gutter)
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
                    .xFont(.caption)
                    .foregroundStyle(XPalette.ok)
                    .frame(maxWidth: .infinity)
                    .padding(XSpace.s)
                    .xCallout(XPalette.ok, .control, wash: 0.08)
                    .padding(.horizontal, XSpace.gutter)
                } else if result != nil, !MemberHub.elderMode {   // 原来绑了 r 却从没读过
                    Label {
                        Text("等待首次使用")   // 333 等待首次使用
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
                    .frame(maxWidth: .infinity)
                    .padding(XSpace.s)
                    .xPlate(XPalette.surfaceAlt, .control)
                    .padding(.horizontal, XSpace.gutter)
                }
                if !MemberHub.elderMode {
                    Button("再发一张") {
                        result = nil
                        pwd = StudioTools.genDigits(6)
                        note = ""
                    }
                    .buttonStyle(XSecondaryButtonStyle(fullWidth: false))
                }
            }
            .padding(.vertical, XSpace.l)
        }
        .background(XPalette.canvas.ignoresSafeArea())
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
            XHaptics.trigger.impactOccurred()
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
                app.showToast("第 \(i + 1)/\(max(batchCount, 1)) 张已写入门锁 (编号 #\(alias))")
            } catch {
                failed += 1
                app.showToast("第 \(i + 1) 张写入失败: \(error.localizedDescription)")   // 178 张下发失败
            }
        }
        if let r = last {
            result = r
            // 整条批量链都用入口捕获的 kc.mac，这一行原先落到**活读**的 mac:
            // 批量下发以十秒计，中途当前锁被改掉就会清掉另一把锁的草稿 (tools/macpin.js 抓到的)
            CredentialOrg.clearDraft(kc.mac)
            if failed > 0 { app.showToast("批量完成, \(failed) 张失败, 稍后可在钥匙页重试") }
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
                    VStack(alignment: .leading, spacing: XSpace.l) {
                        StepDots(total: 4, index: step, labels: ["归属", "录入", "命名", "回执"])
                        if step == 0 { step0 }
                        if step == 2 { step2 }
                        navBar
                    }
                    .padding(XSpace.l)
                }
                .background(XPalette.canvas.ignoresSafeArea())
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
            .xFont(.caption)
            .foregroundStyle(XPalette.warn)
            .padding(.horizontal, XSpace.s)
            .padding(.vertical, 4)
            .xCallout(XPalette.warn, .control, wash: 0.10)
        }
        // 317 归属先行: 选择器自带"空态就地新建" —— 一个成员都没有时直接弹新增, 不再把人赶去成员中心。
        // 完整容量 —— 原来只有"仅剩 1 枚"这一个极端提示，
        // 用户看不到锁里总共能录几枚、还剩几枚。
        // 数据来自 StatusSnapshotData.fpCap / fpStock（协议 0x28 真实返回）
        // 与 AddFingerPage 的容量卡同口径。
        if let snap = DB.readStatus(mac), let cap = snap.fpCap, cap > 0 {
            let left = snap.fpStock
            let used = max(0, cap - left)
            Label {
                Text(left == 0
                     ? "指纹库存已满 — 新增前请先删一枚"
                     : "还可录 " + String(left) + " 枚 · 已用 " + String(used) + " / " + String(cap))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "touchid")
            }
            .xFont(.caption)
            .foregroundStyle(left == 0 ? XPalette.warn : XPalette.textSub)
            .padding(.horizontal, XSpace.s)
            .padding(.vertical, 4)
            .xCallout(XPalette.hairline, .control, wash: 0.06)
        }
        FpOwnerPicker(mac: mac, owner: $owner)
            .card()
    }

    // ---------- 41 沉浸式录入 (复用 Achievement 的 hero 渐变聚焦语言 + 大圆点) ----------
    private var immersive: some View {
        XHeroCard {
            VStack(spacing: XSpace.xl) {
                Text(progressText)
                    .xFont(.headline)
                    .foregroundStyle(XPalette.onAccent)
                VStack(spacing: XSpace.s) {
                    ProgressView(value: Double(min(presses.count, 8)), total: 8)
                        .tint(XPalette.onAccent)
                        .frame(maxWidth: 220)
                    HStack(spacing: XSpace.s) {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(i < presses.count ? XPalette.onAccent.opacity(0.95) : XPalette.onAccent.opacity(0.22))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text("请选好的手指按在门锁指纹头上, 抬起, 重复 8 次")   // 41 请选好的手指按在门锁
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.onAccent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !error.isEmpty {
                    Label {
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .xFont(.caption)
                    .foregroundStyle(XPalette.onAccent)
                    .multilineTextAlignment(.center)
                }
                HStack(spacing: XSpace.s) {
                    Button {
                        presses = []
                        error = ""
                    } label: {
                        Text("重置进度")
                            .xFont(.footnote, weight: .medium)
                            .foregroundStyle(XPalette.onAccent)
                            .frame(minHeight: XHit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        enrollTask = Task { await start() }
                    } label: {
                        HStack(spacing: XSpace.xs) {
                            if busy {
                                ProgressView().tint(XPalette.onAccent).controlSize(.small)
                            } else {
                                Image(systemName: "touchid")
                                    .font(.system(size: XIcon.sm, weight: .semibold))
                                    .foregroundStyle(XPalette.onAccent)
                            }
                            Text(busy ? "录入中…" : "开始录入")
                        }
                        .xFont(.headline)
                        .foregroundStyle(XPalette.onAccent)
                        .padding(.horizontal, XSpace.l)
                        .padding(.vertical, XSpace.s + 2)
                        .background(XPalette.surfaceSunken, in: Capsule())
                        .frame(minHeight: XHit.min)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(.top, XSpace.l)
        .animation(XMotion.standard, value: presses.count)
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
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text("命名 (点按建议填入)")
                .xFont(.footnote, weight: .semibold)
                .foregroundStyle(XPalette.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XSpace.xs) {
                    ForEach(suggestionPool, id: \.self) { sug in
                        Button {
                            name = sug
                            XHaptics.tick.impactOccurred()
                        } label: {
                            Text(sug)
                                .xFont(.caption, weight: .medium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(name == sug ? XPalette.onAccent : XPalette.accentText)
                                .padding(.horizontal, XSpace.s)
                                .padding(.vertical, 4)
                                .background(name == sug ? XPalette.accent : XPalette.accentText.opacity(XOpacity.wash), in: Capsule())
                                .frame(minHeight: XHit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("建议名 \(sug)")
                        .accessibilityAddTraits(name == sug ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, XSpace.xs)
            }
            TextField("自定义名称", text: $name, prompt: Text("如: 妈妈·左手食指"))
                .xFont(.subheadline)
                .frame(minHeight: XHit.min)
                .autocorrectionDisabled()
            TextField("备注", text: $note, prompt: Text("仅本机留存"))   // 179 备注
                .xFont(.subheadline)
                .frame(minHeight: XHit.min)
            // 319 重录继承: 同成员已有指纹 → 成功后旧指纹入回收站 (保留原备注/归属, 来源"重录替代")
            if !sameOwnerFps.isEmpty {
                XToggle("该成员已有 \(sameOwnerFps.count) 枚指纹, 录入成功后将旧指纹移入回收站 (重录继承, 保留原备注/归属)", isOn: $replaceOld)
                    .xFont(.caption)
                    .foregroundStyle(XPalette.textSub)
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
        VStack(spacing: XSpace.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: XIcon.xl))
                .foregroundStyle(XPalette.ok)
                .accessibilityHidden(true)
            Text("已登记为「\(name.isEmpty ? fallbackName : name)」")
                .xFont(.headline)
                .foregroundStyle(XPalette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("请用新指纹开一次锁, 确认可用。" + (replaceOld ? " 旧指纹已移入回收站。" : ""))   // 319 旧指纹已移入回收站
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("完成") { dismiss() }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
            Spacer(minLength: 0)
        }
        .padding(XSpace.l)
        .frame(maxWidth: .infinity)
        .background(XPalette.canvas.ignoresSafeArea())
    }
    private var fallbackName: String { "指纹" + String(doneBatch ?? 0) }

    private var navBar: some View {
        HStack(spacing: XSpace.s) {
            if step > 0 {
                Button("上一步") {
                    withAnimation(XMotion.quick) { step -= 1 }
                }
                .xFont(.subheadline, weight: .medium)
                .foregroundStyle(XPalette.textSub)
                .frame(minHeight: XHit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step == 0 {
                Button("下一步: 录入") {
                    guard owner != nil || DB.members().isEmpty else {
                        app.showToast("先选这把钥匙属于谁")   // 317 先选归属成员
                        XHaptics.trigger.impactOccurred()
                        return
                    }
                    withAnimation(XMotion.quick) { step = 1 }
                    XHaptics.tick.impactOccurred()
                }
                .xFont(.subheadline, weight: .semibold)
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
            }
            if step == 2 {
                Button("保存登记") { saveAndClose() }
                    .xFont(.subheadline, weight: .semibold)
                    .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
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
            app.showToast("旧指纹已移入回收站 (备注和归属信息保留)")
        }
        withAnimation(XMotion.standard) { step = 3 }
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
                                                    XHaptics.tick.impactOccurred()   // 手指在锁上, 屏幕看不见
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
            withAnimation(XMotion.standard) { step = 2 }
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
            ZStack {
                XPalette.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: XSpace.l) {
                        targetLockCard.xScrollLift()
                        zotpCard.xScrollLift()
                        totpGroup
                        staticCard.xScrollLift()
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.vertical, XSpace.l)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("OTP 与口令")
            .navigationBarTitleDisplayMode(.inline)
            .axBottomAnchor()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onReceive(timer) { t in tick = t }
            .sheet(isPresented: $importing) { importSheet }
        }
    }

    @ViewBuilder
    private var targetLockCard: some View {
        if DB.keychains().count > 1 {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("用于哪把锁")
                    Picker("", selection: Binding(get: { otpMac }, set: { targetMac = $0 })) {
                        ForEach(DB.keychains(), id: \.mac) { kc in
                            Text(LockArchive.displayName(kc)).tag(kc.mac)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: XHit.min)
                    .tint(XPalette.accentText)
                    Text("独立口令按锁存档 (kf_cotp_t_) —— 备份也按锁导出, 换一把锁就是另一组口令。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var zotpCard: some View {
        if DB.otpStatus(mac)?.on == true {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("锁端 ZOTP (30 分钟时窗)")
                    WindowBar(totalSec: 1800, label: "337 时窗细条 · 末 5 秒转橙轻震 (⚠ 锁端分钟级, 约)")
                    Text("每 30 分钟更换; 生成前请校准门锁时间, 偏差 >180 秒锁侧校验失败。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var totpGroup: some View {
        let list = CredentialOrg.totpEntries(otpMac)
        if list.isEmpty {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("独立口令")
                    XEmptyState(systemImage: "clock.badge.questionmark",
                                title: "还没有独立口令",
                                message: "粘贴 otpauth:// 文本导入, 或手工添加。口令本身跟门锁协议无关, 但它按当前这把锁存档。")
                }
            }
        } else {
            ForEach(list) { e in
                totpCard(e)
            }
        }
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("导入与添加")
                Button {
                    importing = true
                } label: {
                    Label("导入 otpauth:// 文本", systemImage: "square.and.arrow.down")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: XHit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    showManual.toggle()
                    if !showManual { manualErr = "" }
                    XHaptics.tick.impactOccurred()
                } label: {
                    Label(showManual ? "收起手工添加" : "手工添加", systemImage: "keyboard")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: XHit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showManual { manualForm() }
                Text("组尾实话: 这些口令不经过门锁、也不进锁端协议, 但存的键带锁的 MAC (kf_cotp_t_) —— 因为备份按锁导出。")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var staticCard: some View {
        let codes = CredentialOrg.staticCodes(otpMac)
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("静态备份码")
                if codes.isEmpty {
                    Text("还没有静态码。它不走锁端、不随时间变化, 适合抄在纸上应急。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(codes) { c in
                        staticRow(c)
                    }
                }
                TextField("备注 (给谁/干什么)", text: $noteDraft, prompt: Text("仅本机留存"))
                    .xFont(.subheadline)
                    .frame(minHeight: XHit.min)
                    .padding(XSpace.s)
                    .background(XPalette.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
                Button {
                    let name = "备份码 " + String(codes.count + 1)
                    CredentialOrg.addStaticCode(otpMac, CredentialOrg.StaticCode(
                        id: UUID().uuidString, name: name,
                        code: StudioTools.genDigits(8), note: noteDraft, used: false,
                        at: Date().timeIntervalSince1970))
                    noteDraft = ""
                    app.showToast("已生成 8 位静态备份码")
                } label: {
                    Label("生成 8 位静态码", systemImage: "plus")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: XHit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func totpCard(_ e: CredentialOrg.TOTPEntry) -> some View {
        let nowCode = StudioTools.totp(e, offset: 0)
        let nextCode = StudioTools.totp(e, offset: 1)
        return VStack(spacing: XSpace.s) {
            Button {
                ClipboardCare.copySecret(nowCode, via: "独立 TOTP")
                XHaptics.tick.impactOccurred()
                app.showToast("已复制当前码")
            } label: {
                XCodeRing(code: nowCode,
                          nextCode: nextCode,
                          label: e.name,
                          period: e.period > 0 ? e.period : 30,
                          now: tick,
                          masked: cap.recording)
            }
            .buttonStyle(.plain)
            .accessibilityHint("轻点复制当前码")
            HStack(spacing: XSpace.s) {
                Button {
                    ClipboardCare.copySecret(nowCode, via: "独立 TOTP")
                    app.showToast("已复制当前码")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .xFont(.caption, weight: .medium)
                }
                .buttonStyle(XSecondaryButtonStyle(fullWidth: false))
                .frame(minHeight: XHit.min)
                Text(CredentialOrg.totpParams(e))
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeTotp(otpMac, e.id)
                    app.showToast("已移除「\(e.name)」")
                } label: {
                    Label("移除", systemImage: "trash")
                        .xFont(.caption, weight: .medium)
                }
                .buttonStyle(XDestructiveButtonStyle(fullWidth: false))
                .frame(minHeight: XHit.min)
                .accessibilityLabel("移除独立口令 \(e.name)")
            }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            ZStack {
                XPalette.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: XSpace.l) {
                        XPanel(kind: .group) {
                            VStack(alignment: .leading, spacing: XSpace.m) {
                                secLabel("粘贴 otpauth 文本")
                                TextField("otpauth://totp/…?secret=…", text: $importUri, axis: .vertical)
                                    .xFont(.footnote)
                                    .autocorrectionDisabled()
                                    .lineLimit(3...6)
                                    .padding(XSpace.s)
                                    .background(XPalette.surfaceSunken,
                                                in: RoundedRectangle(cornerRadius: XRadius.min, style: .continuous))
                            }
                        }
                        .xScrollLift()
                        if !importErr.isEmpty {
                            XPanel(kind: .group) {
                                Label(importErr, systemImage: "exclamationmark.circle")
                                    .xFont(.caption)
                                    .foregroundStyle(XPalette.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        XBusyButton(title: "导入", systemImage: "square.and.arrow.down", busy: false) {
                            switch StudioTools.parseOtpAuth(importUri) {
                            case .success(let r):
                                CredentialOrg.addTotp(otpMac, CredentialOrg.TOTPEntry(
                                    id: UUID().uuidString, name: r.name, secret: r.secret,
                                    algo: r.algo, period: r.period, digits: r.digits,
                                    at: Date().timeIntervalSince1970))
                                let tail = r.defaulted.isEmpty ? "" : "; 按默认补了: " + r.defaulted.joined(separator: "/")
                                app.showToast("已导入「\(r.name)」" + tail)
                                importUri = ""
                                importErr = ""
                                importing = false
                            case .failure(let f):
                                importErr = "导入失败: " + f.rawValue
                            }
                        }
                    }
                    .padding(.horizontal, XSpace.gutter)
                    .padding(.vertical, XSpace.l)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("导入 otpauth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { importing = false }
            } }
        }
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---------- 341 手工添加整段 (名称 / Base32 密钥 / 算法 / 周期 / 位数) ----------
    /// 与导入那条走**同一份** TOTPEntry 与同一个 `CredentialOrg.addTotp` 出口, 只是字段由人填。
    /// 校验只认真实缺失点 (空密钥 / Base32 非法), 报错落在本段自己的错误行上。
    @ViewBuilder
    private func manualForm() -> some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            TextField("名称", text: $manualName, prompt: Text("如: 验证器·登录码 (留空按密钥尾段命名)"))
                .xFont(.subheadline)
                .frame(minHeight: XHit.min)
                .autocorrectionDisabled()
            TextField("Base32 密钥", text: $manualSecret, prompt: Text("验证器里那串 A-Z 与 2-7"))
                .xFont(.footnote.monospaced())
                .frame(minHeight: XHit.min)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            // @layout-allow 触达托管 Picker: 控件本体高度由系统渲染, 我们撑 frame 只会多出一片点不动的死区。
            // 上机复测: 用拇指点这一行的上下边缘, 看打不打得开 (打得开=系统已给够 44, 这条可以销)
            Picker("算法", selection: $manualAlgo) {
                ForEach(["SHA1", "SHA256", "SHA512"], id: \.self) { a in
                    Text(a).tag(a)
                }
            }
            .xFont(.caption)
            HStack(spacing: XSpace.xs) {
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
            .xFont(.caption)
            if !manualErr.isEmpty {
                Label(manualErr, systemImage: "exclamationmark.circle.fill")
                    .xFont(.caption)
                    .foregroundStyle(XPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(manualErr)
            }
            Button {
                addManualTotp()
            } label: {
                Label("保存这条独立口令", systemImage: "plus.circle")
            }
            .xFont(.subheadline, weight: .medium)
            .foregroundStyle(XPalette.accentText)
            .frame(minHeight: XHit.min)
            Text("算法与周期按你选的这几档算 (RFC 6238 常用档); 锁端 ZOTP 仍走分钟级, 两者互不相干。")   // 337 算法与周期按你选的这
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, XSpace.xs)
    }
    private func addManualTotp() {
        let secret = manualSecret.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
        guard !secret.isEmpty else {
            manualErr = "密钥是空的: 请粘贴验证器给出的那串 Base32"   // 341 密钥是空的
            XHaptics.trigger.impactOccurred()
            return
        }
        guard StudioTools.base32Decode(secret) != nil else {
            manualErr = "密钥不是合法 Base32: 只允许 A-Z 与 2-7, 这里出现了字母表外的字符"   // 341 密钥不是合法
            XHaptics.trigger.impactOccurred()
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
        XHaptics.tick.impactOccurred()
    }

    // 340 双码并排 (当前+下一时窗, 各标剩余) / 345 参数小字
    private func totpRow(_ e: CredentialOrg.TOTPEntry) -> some View {
        let now = StudioTools.totp(e, offset: 0)
        let next = StudioTools.totp(e, offset: 1)
        return VStack(alignment: .leading, spacing: XSpace.xs) {
            HStack(spacing: XSpace.s) {
                Text(e.name)
                    .xFont(.subheadline, weight: .semibold)
                    .foregroundStyle(XPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                // 338 单击即复制 (拍板: **不改行的点击语义**) —— 只把码值这一块做成整块可点的复制区，
                // 行本身不当事件源；下面那个「复制」按钮保留，给 VoiceOver 和不想瞄准的人。
                Button {
                    ClipboardCare.copySecret(now, via: "独立 TOTP")   // 405 同一出口
                    app.showToast("已复制当前码")   // 338 已复制当前码
                } label: {
                    HStack(spacing: XSpace.xs) {
                        Text(cap.recording ? "已隐去" : now)   // 374 已隐去
                            .xFont(.title3.monospacedDigit(), weight: .semibold)
                            .foregroundStyle(XPalette.text)
                            .textSelection(.enabled)
                        Text("↓")
                            .xFont(.caption)
                            .foregroundStyle(XPalette.textSub)
                        Text(cap.recording ? "已隐去" : next)   // 374 已隐去
                            .xFont(.title3.monospacedDigit(), weight: .semibold)
                            .foregroundStyle(XPalette.textSub)
                    }
                    .padding(.horizontal, XSpace.xs)
                    .frame(minHeight: XHit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制当前码 \(e.name)")
            }
            WindowBar(totalSec: max(e.period, 1), label: "当前/下一时窗并排 · " + CredentialOrg.totpParams(e))
            HStack(spacing: XSpace.xs) {
                Button {
                    ClipboardCare.copySecret(now, via: "独立 TOTP")   // 405
                    app.showToast("已复制当前码")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .xFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: XHit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeTotp(otpMac, e.id)   // 339: 与取组的锁保持一致
                    app.showToast("已移除「\(e.name)」")
                } label: {
                    Label("移除", systemImage: "trash")
                }
                .xFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: XHit.min)
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
            HStack(spacing: XSpace.s) {
                Text((c.used ? "已用 · " : "") + c.name)
                    .xFont(.subheadline, weight: .semibold)
                    .foregroundStyle(c.used ? XPalette.textSub : XPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(c.code)
                    .xFont(.title3.monospacedDigit(), weight: .semibold)
                    .foregroundStyle(c.used ? XPalette.textSub : XPalette.text)
                    .textSelection(.enabled)
            }
            if !c.note.isEmpty {
                Text(c.note)
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: XSpace.xs) {
                Button {
                    var n = c; n.used = true
                    CredentialOrg.saveStaticCodes(mac, CredentialOrg.staticCodes(mac).map { $0.id == c.id ? n : $0 })
                    app.showToast("已标记「\(c.name)」为已用")   // 346 已标记
                } label: {
                    Label(c.used ? "撤销已用" : "标记已用", systemImage: c.used ? "arrow.uturn.left" : "checkmark")
                }
                .xFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: XHit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeStaticCode(mac, c.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .xFont(.caption, weight: .medium)
                .buttonStyle(.bordered)
                .frame(minHeight: XHit.min)
                .accessibilityLabel("删除静态码 \(c.name)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}


