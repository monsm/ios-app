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
        let n = e.digits > 0 ? e.digits : 6
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
        SceneDef(key: "reno", name: "装修", hint: "整月 · 长期工", hours: 720, note: "装修组·工地·整月 (330 施工中)")
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
                .font(.caption)
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
                        .font(digitFont)
                        .foregroundStyle(on ? DS.Palette.text : DS.Palette.textSub)
                        .frame(width: big ? 36 : 30)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(a11yLabel)
                // 849 双击拷贝挂在每个位上: 容器的点按会被按钮吃掉, 只挂容器等于双击数值区没反应。
                // 双击时按钮自身动作会各切一次揭示, 净效果回到原样, 不影响读数。
                .simultaneousGesture(TapGesture(count: 2) { copyAll() })
                // 对 VoiceOver 不承诺"双击" (VO 的双击=激活=揭示), 拷贝走转子自定义动作
                .accessibilityAction(named: "拷整条明文 (849)") { copyAll() }
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
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DS.Palette.textSub)
                        .frame(width: 28)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(ch ? DS.Palette.accentText : DS.Palette.hairline)
                    Text(b)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(ch ? DS.Palette.accentText : DS.Palette.text)
                        .frame(width: 28)
                    if ch {
                        Text("第 \(i + 1) 位")
                            .font(.caption2)
                            .foregroundStyle(DS.Palette.accentText)
                    }
                }
            }
            if changed.isEmpty {
                Text("新旧值完全一致, 未做任何改动")
                    .font(.caption)
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
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("剩约 \(remaining(now)) 秒")
                    .font(.caption2)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(revealed ? code : SecurityPolicy.halfMasked(code))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
                // 370: 口述卡这一路也接贴近复蔽 (卡片在屏期间才开监听)
                .proximityRemask { revealed = false }
            Text(window)
                .font(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !note.isEmpty {
                Text(note)
                    .font(.caption)
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
                .font(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel(revealed ? "重新遮挡码值" : "完整显示码值")
                Button {
                    ClipboardCare.copySecret(revealed ? code : SecurityPolicy.halfMasked(code), via: "工作室 TOTP")   // 405
                    app.showToast(revealed ? "码值已复制" : "已复制遮半码值 (完整值先点「完整显示」)")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("复制码值")
                ShareLink(item: shareText) {
                    Label("分享口述卡", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("分享口述卡")
            }
            let foot = extraFoot.isEmpty ? "172/328 大字号方便对准锁键盘输入; 本卡含密码, 拍照或分享后注意保管。" : extraFoot
            Text(foot)
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
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
                .navigationTitle("扫一扫 (522)")
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
    /// 卡片面: surface + hairline 描边 + 34 轻厚度阴影
    func card() -> some View {
        padding(DS.Space.m + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
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

// ================= 177 扇出新增: 凭证工坊四入口 =================
struct StudioHome: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// embedded = 由外部 NavigationStack push (宿主已提供导航栏); 非 embedded 时自带导航栏
    var embedded: Bool = true
    @State private var showAddPwd = false
    @State private var showTemp = false
    @State private var showFp = false
    @State private var showOtp = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
    }
    private var content: some View {
        List {
            Group {
                Section("四类凭证 (177 扇出)") {
                    fanoutRow("key.fill", "密码", "301 剪贴板即建 · 303 逐位回显 · 304 重复拦截 · 173 生成器",
                              label: "添加密码") { showAddPwd = true }
                    fanoutRow("clock.badge.chevron.right", "临时码",
                              "325 五场景 · 327 重叠检测 · 330 装修黄条 · 178 批量",
                              label: "添加临时码") { showTemp = true }
                    fanoutRow("touchid", "指纹",
                              "317 归属先行 · 41 沉浸式录入 · 323 删除双签",
                              label: "录入指纹") { showFp = true }
                    fanoutRow("number.square", "OTP 与口令",
                              "337 时窗细条 · 341 otpauth · 346 静态备份码",
                              label: "OTP 与口令") { showOtp = true }
                }
                Section {
                    Text("密码与指纹需现场靠近门锁下发; 临时码与 OTP 为本地台账管理, 锁端语义未定义的一次性/周期按时间窗推断 (标\"约\")。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("凭证工坊")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                if !embedded {
                    Button("关闭") { dismiss() }
                }
            } }
            .sheet(isPresented: $showAddPwd) { PwdStudio(embedded: false) }
            .sheet(isPresented: $showTemp) { TempCodeStudio() }
            .sheet(isPresented: $showFp) { FpStudio() }
            .sheet(isPresented: $showOtp) { OtpStudio() }
        }
    }
    private func fanoutRow(_ icon: String, _ title: String, _ sub: String, label: String,
                           _ act: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.tick.impactOccurred()
            act()
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.md, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(width: DS.Icon.md + 8, height: DS.Icon.md + 8)
                    .background(DS.Palette.accentText.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Space.s, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                        .lineLimit(1)
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label + " " + sub)
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
                .font(.caption)
                .foregroundStyle(DS.Palette.warn)
            Spacer(minLength: 0)
            Button("继续") { restoreDraft(d); showDraftBar = false }
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            Button {
                CredentialOrg.clearDraft(mac)
                showDraftBar = false
            } label: {
                Text("丢弃")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .background(DS.Palette.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("草稿续填 (518): 上次填到第 \(d.step + 1) 步, 点继续可回填")
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
                .font(.footnote.weight(.medium))
                .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSub)
                .padding(.horizontal, DS.Space.s + 2)
                .padding(.vertical, 6)
                .background(on ? DS.Palette.accent : DS.Palette.surfaceAlt, in: Capsule())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("归属成员 (317 归属先行, 台账本地)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(errorField == "owner" ? DS.Palette.danger : DS.Palette.text)
            ForEach(DB.members()) { m in
                Button {
                    owner = m.id
                    errorField = ""
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    HStack {
                        Text(m.name)
                            .font(.subheadline)
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
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if errorField == "owner" {
                errorLine("归属必选 (317 归属先行): 先选成员; 没有成员可先去成员中心新建再返回。")
            }
        }
        .card()
    }

    // ---------- 301/303/173/516/519/522 step1 码值 ----------
    @ViewBuilder
    private var step1: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text("码值")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(errorField == "value" ? DS.Palette.danger : DS.Palette.text)
                Spacer(minLength: 0)
                Text("6~8 位数字")
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
            }
            if !pwd.isEmpty {
                MaskedDigits(value: pwd, big: true)
                    .padding(.vertical, DS.Space.xs)
            }
            TextField("", text: $pwd, prompt: Text("输入 6~8 位数字 (516 纯数字键盘)"))
                .keyboardType(.numberPad)
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
                .onChange(of: pwd) { _, _ in
                    if errorField == "value" { errorField = "" }
                    if clipSource { DS.Haptics.tick.impactOccurred() }
                }
            if clipSource {
                HStack(spacing: DS.Space.xs) {
                    Label("来自剪贴板 · 已识别为候选码 (301)", systemImage: "doc.on.clipboard")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("清除") {
                        pwd = ""
                        clipSource = false
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .background(DS.Palette.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .accessibilityLabel("码值来自剪贴板, 点清除可移除")
            }
            HStack(spacing: DS.Space.s) {
                ForEach([6, 7, 8], id: \.self) { n in
                    Button("生成 \(n) 位") {
                        pwd = StudioTools.genDigits(n)
                        clipSource = false
                        DS.Haptics.tick.impactOccurred()
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .frame(minHeight: DS.Hit.min)
                    .accessibilityLabel("本地生成 \(n) 位随机密码 (173)")
                }
                Spacer(minLength: 0)
            }
            if !pwd.isEmpty {
                let s = StudioTools.pwdStrength(pwd)
                HStack(spacing: DS.Space.xs) {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(i < s.score ? (s.score <= 1 ? DS.Palette.warn : DS.Palette.ok) : DS.Palette.surfaceAlt)
                                .frame(width: 22, height: 4)
                        }
                    }
                    Text(s.hint)
                        .font(.caption2)
                        .foregroundStyle(s.score <= 1 ? DS.Palette.warn : DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityLabel("密码强度 " + s.hint)
            }
            if errorField == "value" {
                errorLine("码值需 6~8 位数字 (519): 就在上面那格码值里改, 改好再点下一步。")
            }
            let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: editAlias ?? -1) : []
            // 304 说的是"全库", 上面那个只查本锁 → 跨锁检查接上 (duplicatePwdLockNames 此前零调用)
            let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
            if !others.isEmpty {
                Label("其它 \(others.count) 把锁上也有同值: " + others.prefix(3).joined(separator: "、")
                    + (others.count > 3 ? " 等" : "") + " (304 全库)",
                      systemImage: "lock.rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dups.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    Label("本锁已有 \(dups.count) 条同值凭证 (304)", systemImage: "plus.slash.minus")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("查看") {
                        // 304 查看即跳: 真把那枚同值凭证的详情打开 (toast 看不全)
                        app.pendingCredNav = "pwd:\(dups[0].alias)"
                        app.pendingCredNavMac = mac
                        app.tabSelection = 1
                        if !embedded { dismiss() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .background(DS.Palette.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if let c = pwdOK ? CredentialOrg.prefixConflict(mac, pwd, excluding: editAlias ?? -1).first : nil {
                Text("与「\(CredentialOrg.displayPwd(c))」前 4 位相同, 口头易混淆 (314)。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showScan = true
            } label: {
                Label("扫一扫取号 (522, 识别失败请人工输入)", systemImage: "qrcode.viewfinder")
            }
            .font(.caption.weight(.medium))
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
            app.showToast("已识别 \(s.count) 位数字, 请核对位数与内容 (522)")
            DS.Haptics.trigger.impactOccurred()
        } else {
            app.showToast("未识别到数字码, 请人工输入 (522 回退)")
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
                            .font(.footnote.weight(.semibold))
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
                        Spacer(minLength: 0)
                    }
                    if periodHelp {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("默认 1 小时；四枚快捷档是 1 小时 / 今天内 (到今晚 23:59) / 7 天 / 30 天。")
                            Text("到期必须晚于生效，否则这条不让过 (519)。")
                            Text("生效与到期是写给门锁的两个时刻，门锁用它自己的钟比对 —— 锁钟不准，码会提前或延后失效。")
                            Text("改有效期要重新下发到锁才生效；只改本机台账不算。")
                        }
                        .font(.caption)
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
                        errorLine("到期需晚于生效 (519): 点上面任一快捷档, 或把到期往后挪; 这一步不让过。")
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("长期密码无到期点; 老旧巡检 (305) 会在详情页提示「添加满 180 天」那一条 —— "
                         + "台账只有添加时刻, 那句说的是这条加了多久, 不是这个值多久没换过。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("备注 (179 占位规范: 给谁·哪扇门·用多久)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                // 312 常用短语条: 点按追加到备注末尾 (不是替换), 空备注时直接填
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.xs) {
                        Text("常用短语 (312)").font(.caption2).foregroundStyle(DS.Palette.textSub)
                        ForEach(["仅白天", "勿外传", "长期有效"], id: \.self) { p in
                            Button(p) {
                                note = note.isEmpty ? p : note + " · " + p
                                DS.Haptics.tick.impactOccurred()
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Palette.accentText)
                            .padding(.horizontal, DS.Space.s).padding(.vertical, 5)
                            .background(DS.Palette.surfaceAlt, in: Capsule())
                            .frame(minHeight: DS.Hit.min - DS.Space.xs)
                            .contentShape(Rectangle())
                            .accessibilityLabel("追加短语 \(p)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                TextField("如: 钟点工·大门·仅上午场 (523 可长按调听写)", text: $note,
                          prompt: Text("给谁 · 哪扇门 · 用多久"))
                    .font(.subheadline)
                    .frame(minHeight: DS.Hit.min)
                    .autocorrectionDisabled()
                // 开关必须常驻: 旧写法用 if useTemplate 包住自己的 Toggle,
                // 一旦用户关掉, 这一行就消失了, 本次会话再也开不回来
                Toggle("备注自动补命名模板 (918 谁-哪里-何时)", isOn: $useTemplate)
                    .font(.footnote)
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
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷时长 \(t) (520)")
    }
    /// 快捷档"今天"的剩余秒数。终点取 `TimeFormat.dayEnd()` (今晚 23:59) ——
    /// 那一份实现刚从**编译失败**里修出来，理由与机检依据写在 TimeFormat.swift:87 上方，不要在这里另抄一份。
    private func todayEndSecs() -> Int {
        max(Int(TimeFormat.dayEnd().timeIntervalSinceNow), 60)
    }
    private func durationLabel(_ d: Date, prefix: String) -> some View {
        Text(prefix + d.formatted(.dateTime.month().day().hour().minute()))
            .font(.footnote)
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
                    Text("306 新旧对照 (上旧只读 / 下新)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    PwdDiffView(old: old, new: pwd.isEmpty ? old : pwd)
                        .card()
                    Text("改动位共 \(CredentialOrg.digitDiff(old: old, new: pwd.isEmpty ? old : pwd).count) 处 (307, 逐位高亮, 确认后才落库)。")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("即将\(editing == nil ? "添加" : "改造")的凭证")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.s) {
                        StatusPill(text: kind == 0 ? "长期密码" : "临时码", systemImage: kind == 0 ? "infinity" : "clock", tone: .accent)
                        Text(CredentialOrg.ownerName(owner))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                    }
                    MaskedDigits(value: pwd, big: true)
                    if kind == 1 {
                        Text("\(from.formatted(.dateTime.month().day().hour().minute())) ~ \(to.formatted(.dateTime.month().day().hour().minute())) 生效")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(2)
                    }
                }
                .card()
            }
            if busy {
                ProgressView("正在下发到门锁…")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
            } else {
                // 521 二次输入确认: 重输码值一致才放行 (与转账复核同语义; 开关在设置-安全页)
                if DB.store.getBool("kf_scred_2nd", true) {
                    HStack(spacing: DS.Space.xs) {
                        TextField("重输一遍码值 (521)", text: $confirmPwd)
                            .keyboardType(.numberPad)
                            .font(.subheadline.monospaced())
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
                    .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                }
                // 541 替代: 原句是下发前的乐观锁提示 ("此锁配置上次同步于 X, 建议到场核对后重试")。
                // 锁端没有配置序号字段, 所以这把尺只到本机台账 (365 队列里最后一条"已下发"的时刻),
                // 文案把这件事说穿 —— 提示不说成"锁端就是这样"。
                if let at = CredentialOrg.lastApplyAt(mac) {
                    let days = Int((Date().timeIntervalSince1970 - at / 1000) / 86400)
                    Text("此锁上次成功下发: " + (days <= 0 ? "今天" : "\(days) 天前")
                         + " (541 · 本机台账时刻, 不是锁端真值; 若中途有别人动过这把锁, 以到场核对为准)")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("本机台账里还没有这把锁的成功下发记录 (541) —— 这条提示只说本机台账, 不代表锁端没被配过。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                BusyButton(title: editing == nil ? "下发密码" : "保存改造", systemImage: "key.fill", isBusy: busy) {
                    Task { await submit() }
                }
                .disabled(DB.store.getBool("kf_scred_2nd", true) && confirmPwd != pwd)
            }
            Text("请将手机靠近门锁; 成功后登记到本机台账并留一档版本快照 (487)。")
                .font(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ---------- 515 导航条 ----------
    private var navBar: some View {
        HStack {
            if step > 0 {
                Button("上一步") {
                    withAnimation(DS.Motion.quick) { step -= 1 }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step < 3 {
                Button(step == 0 ? "下一步: 码值" : (step == 1 ? "下一步: 有效期" : "下一步: 确认")) {
                    if step == 0, owner == nil, !DB.members().isEmpty {
                        errorField = "owner"
                        app.showToast("先选归属成员 (317 归属先行)")
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    if step == 1, !pwdOK {
                        errorField = "value"
                        app.showToast("码值需 6~8 位数字 (519)")
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    // 519 步间真拦: 原先这一支是 `to = from + 1h` —— 静默把用户没选过的值改掉,
                    // 然后带着一个他自己没填的时刻进确认步, 界面上显示的仍是补出来的那个。
                    // 现在停在这一步: toast + 触感 + errorField 同步 (字段下方那行 errorLine 已经在按 to<=from 显示)。
                    if step == 2, kind == 1, to <= from {
                        errorField = "period"
                        app.showToast("到期要晚于生效, 请先点一枚快捷档 (519)")
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    saveDraft()
                    withAnimation(DS.Motion.quick) { step += 1; errorField = "" }
                    DS.Haptics.tick.impactOccurred()
                }
                .font(.subheadline.weight(.semibold))
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
        app.showToast("已回填草稿 (518)")
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
            app.showToast("先选归属成员 (317 归属先行, 519 拦在提交前)")
            DS.Haptics.trigger.impactOccurred()
            return
        }
        guard pwdOK else {
            step = 1
            errorField = "value"
            app.showToast("码值需 6~8 位数字 (519 拦在提交前)")
            DS.Haptics.trigger.impactOccurred()
            return
        }
        if kind == 1, to <= from {
            step = 2
            errorField = "period"
            app.showToast("到期要晚于生效 (519 拦在提交前): 草稿里的这一档已过期, 请重选")
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
                    CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: p2, fp: nil, note: "改造 (306/307 保存前 diff)")
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
            app.flashReceipt("已写入本机 (508)")
            app.showToast(isTemp ? "临时码已下发" : "密码已下发 (别名 #\(alias))")
            if !embedded { dismiss() }
        } catch {
            app.showToast("下发失败: " + error.localizedDescription)
        }
    }

    private func errorLine(_ s: String) -> some View {
        Label {
            Text(s).font(.caption).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: DS.Icon.sm, weight: .medium))
        }
        .font(.caption)
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
                    Text("场景预设 (325, 选中即套默认时长与备注)")
                        .font(.footnote.weight(.semibold))
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
                    HStack {
                        Text("码值 (6~8 位数字)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                        Text(pwdOK ? "✓ 位数合规" : "6~8 位数字")
                            .font(.caption2)
                            .foregroundStyle(pwdOK ? DS.Palette.ok : DS.Palette.textSub)
                            .lineLimit(1)
                    }
                    if !pwd.isEmpty {
                        MaskedDigits(value: pwd, big: true)
                    }
                    TextField("输入码值, 或点「生成」", text: $pwd, prompt: Text("输入 6~8 位数字 (516)"))
                        .keyboardType(.numberPad)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(minHeight: DS.Hit.min)
                        .autocorrectionDisabled()
                    if clipSource {
                        HStack(spacing: DS.Space.xs) {
                            Label("来自剪贴板 · 已识别为候选码 (301)", systemImage: "doc.on.clipboard")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.warn)
                            Spacer(minLength: 0)
                            Button("清除") { pwd = ""; clipSource = false }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, 4)
                        .background(DS.Palette.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                        .accessibilityLabel("码值来自剪贴板, 点清除可移除")
                    }
                    HStack(spacing: DS.Space.xs) {
                        Button("生成 (173)") {
                            pwd = StudioTools.genDigits(6)
                            clipSource = false
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.bordered)
                        .frame(minHeight: DS.Hit.min)
                        .accessibilityLabel("本地生成 6 位随机码 (173)")
                        Button("扫一扫 (522)") { showScan = true }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .frame(minHeight: DS.Hit.min)
                            .accessibilityLabel("相机识别印刷码 (522)")
                        Spacer(minLength: 0)
                    }
                    // 178 批量临时码 (锁端无批量命令, 走既有 0A 逐条, 失败逐条报)
                    HStack(spacing: DS.Space.xs) {
                        Text("一次生成 (178)")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        ForEach([1, 2, 3, 5], id: \.self) { n in
                            Button(String(n)) { batchCount = n }
                                .font(.caption.weight(batchCount == n ? .semibold : .medium))
                                .buttonStyle(.bordered)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("批量 \(n) 张 (178)")
                        }
                        Spacer(minLength: 0)
                    }
                    // 304 全库重复拦截: 本锁 + 其它锁各查一次 (此前只查本锁却写着"全库")
                    let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: -1) : []
                    let others = pwdOK ? CredentialOrg.duplicatePwdLockNames(pwd, excludingMac: mac) : []
                    if !others.isEmpty {
                        Label("其它 \(others.count) 把锁上也有同值: " + others.prefix(3).joined(separator: "、")
                            + (others.count > 3 ? " 等" : "") + " (304 全库)", systemImage: "lock.rectangle.stack")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !dups.isEmpty {
                        // 304 查看即跳: 不再只给一句"建议换一组", 真把同值那条的详情打开
                        HStack(spacing: DS.Space.xs) {
                            Label("本锁已有 \(dups.count) 条同值凭证 (304), 建议换一组", systemImage: "plus.slash.minus")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("查看") {
                                app.pendingCredNav = "pwd:\(dups[0].alias)"
                                app.pendingCredNavMac = mac
                                app.tabSelection = 1
                                dismiss()
                            }
                            .font(.caption.weight(.medium))
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
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    HStack(spacing: DS.Space.xs) {
                        quickPill("1 小时") { from = Date(); to = Date().addingTimeInterval(3600) }
                        quickPill("今天内") { from = Date(); to = TimeFormat.dayEnd() }   // 终点单一出口 (520/828)
                        quickPill("7 天") { from = Date(); to = Date().addingTimeInterval(7 * 86400) }
                        quickPill("30 天") { from = Date(); to = Date().addingTimeInterval(30 * 86400) }
                    }
                    HStack(spacing: DS.Space.s) {
                        Text(isoShort(from, prefix: "生效 "))
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("→")
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                        Text(isoShort(to, prefix: "到期 "))
                            .font(.footnote)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    if to <= from {
                        Label("到期需晚于生效 (519)", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.danger)
                    }
                    // 327 租期重叠检测
                    if !overlaps.isEmpty {
                        Label {
                            Text("与本成员其它 \(overlaps.count) 张码时段撞车 (327, 重叠段建议错开)")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    }
                    // 330 装修黄条
                    if scene == "reno" {
                        Label("长期工场景: 详情页挂「施工中」黄条 (330), 建议 30 天内复查一次", systemImage: "paintbrush")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()

                // 归属与备注 (317 归属先行 + 179 占位)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("归属与备注")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    ForEach(DB.members()) { m in
                        Button {
                            owner = m.id
                        } label: {
                            HStack {
                                Text(m.name)
                                    .font(.subheadline)
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
                    TextField("给谁 · 哪扇门 · 用多久 (179, 可长按调听写 523)", text: $note,
                              prompt: Text(scene.isEmpty ? "如: 钟点工·大门·仅上午场" : sceneNote))
                        .font(.subheadline)
                        .frame(minHeight: DS.Hit.min)
                        .autocorrectionDisabled()
                }
                .card()

                BusyButton(title: batchCount > 1 ? "下发 \(batchCount) 张 (178)" : "下发临时码",
                           systemImage: "clock.badge.chevron.right", isBusy: busy) {
                    Task { await submitBatch() }
                }
                .disabled(!pwdOK || to <= from)
                Text("请将手机靠近门锁; 批量 (178) 走既有 0A 逐条下发, 锁端无批量命令, 失败逐条报。")
                    .font(.caption2)
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
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(s.hint)
                    .font(.caption2)
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
        .accessibilityLabel("场景 \(s.name): \(s.hint) (325)")
        .accessibilityAddTraits(scene == s.key ? [.isSelected] : [])
    }
    private func quickPill(_ t: String, _ act: @escaping () -> Void) -> some View {
        Button {
            act()
            DS.Haptics.tick.impactOccurred()
        } label: {
            Text(t)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, 4)
                .background(DS.Palette.accentText.opacity(0.10), in: Capsule())
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷时长 \(t) (520)")
    }

    // ---------- 完成页: 172/328 大字口述卡 + 329 一句话 + 333 首用回执 (⚠ 按时间推断标"约") ----------
    private var doneCard: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                CodeBigCard(title: "\(lockName) · 临时码", code: result?.pwd ?? pwd,
                            window: "\(isoShort(from)) ~ \(isoShort(to)) 生效",
                            note: note,
                            extraFoot: batchCount > 1 ? "批量共 \(batchCount) 张, 其余已逐张下发 (178, 逐条 0A)" : "")
                if MemberHub.elderMode {
                    // 486 代际完成页切换: 长辈模式下完成页默认形态 = 口述卡 (页标题也切到「口述卡」) + 一枚大「完成」;
                    // 329/333/再发一张 是常规形态的入口, 这一档收起来并在原地说明 —— 收了不吭声就是本仓反复犯的无声忽略。
                    Button("完成") { dismiss() }
                        .buttonStyle(PrimaryActionStyle())
                    Text("常规模式这里还有 一句话口令 (329) / 首用回执 (333) / 再发一张 — 长辈模式下不显示 (486)。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 329 一句话口令文本
                if let r = result, !MemberHub.elderMode {
                    let text = StudioTools.oneLine(p: r, lockName: lockName, value: r.pwd)
                    Button {
                        ClipboardCare.copySecret(text, via: "一句话口令")   // 405 含口令明文
                        app.showToast("一句话口令已复制 (329)")
                    } label: {
                        VStack(spacing: DS.Space.xs) {
                            Text("生成一句话口令 (329)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DS.Palette.accentText)
                            Text("“" + text + "”")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min + 8)
                        .contentShape(Rectangle())
                        .padding(.vertical, DS.Space.s)
                        .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityLabel("复制一句话口令: " + text)
                    // 329 分享面板: 系统分享单 (与 405 复制同源明文, 发给家人用)
                    ShareLink(item: text) {
                        Label("分享一句话口令 (329)", systemImage: "square.and.arrow.up")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                            .padding(.vertical, DS.Space.s)
                            .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.Space.gutter)
                    .accessibilityLabel("分享一句话口令 (329)")
                }
                // 333 首用回执 (⚠ 无 alias 字段, 按时间推断, 标"约")
                if let r = result, !MemberHub.elderMode, let t = CredentialOrg.firstUse(mac, p: r) {
                    Label {
                        Text("约在 \(isoShort(Date(timeIntervalSince1970: t))) 有人用它开过门 (333, 按时间窗推断约)")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.ok)
                    .frame(maxWidth: .infinity)
                    .padding(DS.Space.s)
                    .background(DS.Palette.ok.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                    .padding(.horizontal, DS.Space.gutter)
                } else if let r = result, !MemberHub.elderMode {
                    Label {
                        Text("等待首次使用 (333, 「记录」出现首用条目即约回执)")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .frame(maxWidth: .infinity)
                    .padding(DS.Space.s)
                    .background(DS.Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
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
            app.showToast("已识别 \(s.count) 位数字, 请核对 (522)")
            DS.Haptics.trigger.impactOccurred()
        } else {
            app.showToast("未识别到数字码, 请人工输入 (522 回退)")
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
                app.showToast("第 \(i + 1) 张下发失败: \(error.localizedDescription) (178 逐条)")
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

// ================= 密码详情 (305/308/309/311/306; 打码默认延续包7) =================
struct PwdDetailStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let alias: Int
    @State private var showEdit = false
    @State private var showCard = false
    @State private var renewing = false
    @State private var copiedFlash = false   // 11 复制按钮形变
    @ObservedObject private var cap = ScreenCaptureWatch.shared   // 374 录屏遮罩 + 336 截图计数
    // 336 用的"本页打开时刻"。写成带初值的 `let`：它不进成员初始化器，
    // 所以 `PwdDetailStudio(alias:)` 这些既有调用点一个字都不用改。
    let openedAt = Date().timeIntervalSince1970
    private var mac: String { app.current?.mac ?? "" }
    private var p: LedgerPwd? { DB.getPwd(mac, alias) }

    var body: some View {
        if let p = p {
            NavigationStack {
                List {
                    // 331 提前失效到点: 顶部提醒条 (本地提示, **不自动下发停用**)
                    if p.temp, CredentialOrg.isEarlyExpired(mac, p, Date()) {
                        Section {
                            Label {
                                Text("已过本机设定的提前失效时刻 (331) — 这一条只是提示: 没有向门锁发过任何停用或改期命令, "
                                     + "门锁在它自己那份到期时刻之前照样能开门。要真停用, 得走列表里的停用或改期。")
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "bell.z.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.06))
                    }
                    // 305 老旧巡检: 台账只有**添加**时刻 (Store.rePwd / setPwdPeriod 都不回写 at),
                    // 所以这句只能说"这条加了多久"; "换没换过值"改查 487 快照有没有改值留档 (见
                    // CredentialOrg.hasReRecordSnapshot), 两支各说各的实话, 不写成"多少天没换码"。
                    // 不新增持久化字段去记改值时刻 (swiftshape R3 的合成 Codable 雷区)。
                    if CredentialOrg.isStalePwd(p) {
                        Section {
                            let ageDays = CredentialOrg.pwdAgeDays(p) ?? 0
                            // 两支文案分别对应"快照里查到过改值留档"与"查不到", 都不说"多少天没换码"
                            let reChanged = CredentialOrg.hasReRecordSnapshot(mac, p)
                            let staleNotice = reChanged ? "添加于约 \(ageDays) 天前 (台账只记添加时刻); 本机快照里查到过改值留档, 仍建议换一枚新码 (305, 约)" : "添加于约 \(ageDays) 天前, 台账无改值时刻、本机快照里也没查到换码留档 (305, 约)"
                            HStack(spacing: DS.Space.s) {
                                Label(staleNotice, systemImage: "clock.arrow.circlepath")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel(staleNotice)
                                Spacer(minLength: 0)
                                Button("换码") { showEdit = true }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: DS.Hit.min)
                                    .accessibilityLabel("改造该密码 (306)")
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.06))
                    }
                    // 336 截图警示 (银行 App 水印那一形态的本地替代 —— 本仓零位图资产, 打不了水印):
                    // 监的是 `UIApplication.userDidTakeScreenshotNotification` (公开 API, 见 docs/API-VERIFY.md)。
                    // 比的是"本页打开之后有没有发生过一次截图"，**不说"你的密码已被拍走"**：
                    // 截图 API 只报"发生过", 不保证拍到的就是这一屏 (可能拍完才切过来)。
                    if p.pwd != nil && cap.screenshotAt > openedAt {
                        Section {
                            HStack(spacing: DS.Space.s) {
                                Label(ScreenCaptureWatch.shotNotice, systemImage: "camera.viewfinder")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button("换码") { showEdit = true }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: DS.Hit.min)
                                    .accessibilityLabel("改造该密码 (306)")
                            }
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.06))
                    }
                    Section("码值 (默认打码, 点位揭示)") {
                        if let v = p.pwd {
                            // 374: 采集进行中连"点一下揭示"都不给 —— 遮的是明文那一格, 不整页替换,
                            // 整页黑掉会让人以为 App 坏了, 反而看不出是录屏在挡
                            if cap.recording {
                                Label(ScreenCaptureWatch.notice, systemImage: "record.circle")
                                    .font(.caption)
                                    .foregroundStyle(DS.Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                MaskedDigits(value: v, big: true)
                            }
                        } else {
                            Text("当时未留存明文, 可在锁上核对后回填")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let v = p.pwd {
                            HStack(spacing: DS.Space.xs) {
                                Button {
                                    ClipboardCare.copySecret(v, via: "密码明文")   // 405
                                    app.showToast("已复制")
                                    // 11 形变: 按下 1.2 秒内按钮变成"已复制 + 对勾", 给一次按下确认
                                    withAnimation(DS.Motion.standard) { copiedFlash = true }
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(1.2))
                                        withAnimation(DS.Motion.standard) { copiedFlash = false }
                                    }
                                } label: {
                                    Label(copiedFlash ? "已复制" : "复制 (11)",
                                          systemImage: copiedFlash ? "checkmark" : "doc.on.doc")
                                        .font(.caption.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                                .frame(minHeight: DS.Hit.min)
                                Button("读出 (309)") { Speech.digits(v) }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: DS.Hit.min)
                                    .accessibilityHint("逐位语音播报, 便于电话转述")
                                Spacer(minLength: 0)
                            }
                            // 308 4 位分段转述: 点任一块只复制该块
                            if v.count >= 8 {
                                HStack(spacing: DS.Space.s) {
                                    ForEach(Array(v.chunked(4).enumerated()), id: \.offset) { i, c in
                                        Button {
                                            ClipboardCare.copySecret(c, via: "密码分段")   // 405 分段也是口令明文的一部分
                                            app.showToast("已复制第 \(i * 4 + 1)~\(min(i * 4 + 4, v.count)) 位")
                                        } label: {
                                            Text(c)
                                                .font(.title3.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(DS.Palette.text)
                                                .frame(minHeight: DS.Hit.min)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("分段 \(i + 1): \(c), 点按只复制该段 (308)")
                                    }
                                }
                            }
                        }
                    }
                    // 359/930 到期预警五档: 与列表侧同键 (kf_calert_) —— 读写都经 CredentialOrg.alert/saveAlert,
                    // 详情页不另存 @State (防双源漂移)。930 替代落地后 h2 档也排通知了,
                    // 列表提醒行不动 —— 前台那条行仍然有用, 只是不再是 h2 的唯一出口。
                    if CredentialOrg.expiryDate(p) == nil {
                        Section("到期预警 (359)") {
                            Text("长期有效密码无到期点, 三档预警不适用。")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Section("到期预警 (359)") {
                            Toggle("到期前 7 天提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).day },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.day = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            Toggle("到期前 3 天提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).d3 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.d3 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            Toggle("到期前 1 天提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).d1 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.d1 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            Toggle("到期前 24 小时提醒 (通知)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).h24 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.h24 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            Toggle("到期前 2 小时提醒 (通知 + 列表提醒行)", isOn: Binding(
                                get: { CredentialOrg.alert(mac, p).h2 },
                                set: { v in
                                    var a = CredentialOrg.alert(mac, p)
                                    a.h2 = v
                                    CredentialOrg.saveAlert(mac, p, a)
                                    CredentialOrg.scheduleAlerts(mac, p, a)
                                }))
                            Text("五档 (7/3/1 天 · 24/2 小时) 都排本地通知, 另有一条「到期时」通知自动跟着走; "
                                 + "2 小时档同时还在凭证列表插提醒行。近 7 天到期条数会显示在凭证 Tab 角标上 (930)。"
                                 + "开关只存本机, 与锁端无关。")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // 331 提前失效滑杆: 本地意图, 不改协议; 到点**只在本页**提示 (顶部提醒条 + 状态行标注),
                    // 不自动下发停用。副文案原先承诺"临近失效的列表行将挂渐进色条" —— 列表侧没做, 已撤。
                    if p.temp {
                        Section("提前失效 (331, 本地意图)") {
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                HStack {
                                    Text("提前 \(CredentialOrg.earlyExpireMin(mac, p.alias)) 分钟失效")
                                        .font(.subheadline)
                                        .foregroundStyle(DS.Palette.text)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                    Text("只在本页提示, 不改锁端")
                                        .font(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .accessibilityLabel("这一档只影响本页的提示: 列表行没有色条, 也不会向门锁下发停用")
                                }
                                Slider(value: Binding(
                                    get: { Double(CredentialOrg.earlyExpireMin(mac, p.alias)) },
                                    set: { CredentialOrg.setEarlyExpireMin(mac, p.alias, Int($0)) }
                                ), in: 0...120, step: 5)
                                .tint(DS.Palette.accent)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("提前失效分钟数滑杆 (331)")
                                Text("实话: 这枚滑杆在本机只存一个分钟数 —— 列表行没有渐进色条, 门锁那侧的到期时刻一个字都没改。"
                                     + "到点本页挂提醒条并在状态行标注, 要不要真停用仍由你决定 (331)。")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    // 330 装修黄条: 备注含「装修/工地」→ 详情页"施工中"角标
                    if p.temp, p.note.contains("装修") || p.note.contains("工地") {
                        Section {
                            HStack(spacing: DS.Space.s) {
                                Label("施工中 (330 装修黄条)", systemImage: "paintbrush.fill")
                                Spacer(minLength: 0)
                                StatusPill(text: "长期工", systemImage: "clock", tone: .warn)
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.08))
                    }
                    // 335 线性用量刻度 (⚠ 锁端无计次字段, 数的是本地开门日志落在这条时间窗里的条数)
                    if p.temp {
                        Section("用量 (335, 约)") {
                            let u = CredentialOrg.usageCount(mac, p: p)
                            HStack(spacing: DS.Space.s) {
                                HStack(spacing: 3) {
                                    ForEach(0..<8, id: \.self) { i in
                                        Capsule()
                                            .fill(i < min(u, 8) ? DS.Palette.accent : DS.Palette.surfaceAlt)
                                            .frame(width: 14, height: 5)
                                    }
                                }
                                Text(u > 0 ? "约 \(u) 条 (按本地开门日志时间窗推断, 锁端无计次字段)" : "无 (按本地开门日志时间窗推断)")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .accessibilityLabel("用量刻度, 按本地开门日志时间窗推断约 \(u) 条 (326/335, 锁端无计次字段)")
                        }
                    }
                    // 332 原码续期 (⚠ 过期码是否留存锁端未确证: 本地沿用原值改期 + 入队兜底, 标"约")
                    if p.temp, CredentialOrg.pwdState(p) == 2, p.pwd != nil {
                        Section {
                            Button {
                                Task { await renewExpired(p) }
                            } label: {
                                Label("续期 7 天 (332, 原值沿用 · 锁端留存未确证, 约)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                        }
                    }
                    Section("时段与归属") {
                        // 331: 状态行同步标注本机的提前失效档 (没设提前量时 earlyExpiryNote 回空串, 不说空话)
                        row("状态", CredentialOrg.stateLabel(CredentialOrg.pwdState(p)) + " · "
                            + CredentialOrg.countdown(p) + CredentialOrg.earlyExpiryNote(mac, p))
                        row("归属", CredentialOrg.ownerName(p.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(p.owner))
                        row("备注", p.note.isEmpty ? "无" : p.note)
                    }
                    // 311 同码引用卡 (⚠ 按时间窗推断, 标"约")
                    Section("用它开过的门 (311, 约)") {
                        let n = CredentialOrg.openCountInWindow(mac, p: p)
                        if n > 0 {
                            Label {
                                Text("时间窗内约 \(n) 次开门 (按时间推断, 无 alias 字段)")
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "door.left.hand.open")
                            }
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        } else {
                            Text("暂无记录 (⚠ 311 按时间窗推断, 无数据不编造)")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                    Section {
                        NavigationLink {
                            PwdStudio(embedded: true, editAlias: p.alias)
                        } label: {
                            Label("改造密码 (306 分屏 / 307 逐位 diff)", systemImage: "pencil")
                        }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                        if p.pwd != nil {
                            Button {
                                showCard = true
                            } label: {
                                Label("生成口述卡 (172/328)", systemImage: "rectangle.portrait")
                            }
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                        }
                    }
                }
                .navigationTitle(CredentialOrg.displayPwd(p))
                .scrollContentBackground(.hidden)
                .dsScreenBackground()
                .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                } }
                .sheet(isPresented: $showEdit) {
                    NavigationStack {
                        PwdStudio(embedded: true, editAlias: p.alias)
                    }
                }
                .sheet(isPresented: $showCard) {
                    if let v = p.pwd {
                        NavigationStack {
                            ScrollView {
                                CodeBigCard(title: "\(app.displayName) · " + CredentialOrg.displayPwd(p),
                                            code: v,
                                            window: p.temp ? "\(isoText(p.from)) ~ \(isoText(p.to)) 生效" : "长期有效",
                                            note: p.note)
                                Spacer(minLength: 0)
                            }
                            .dsScreenBackground()
                            .navigationTitle("口述卡")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                                Button("关闭") { showCard = false }
                            } }
                        }
                    }
                }
            }
        } else {
            EmptyState(systemImage: "key.slash", title: "凭证不存在", message: "这条凭证可能已被删除或移入回收站。")
        }
    }
    private func isoText(_ s: String) -> String {
        CredentialOrg.parseLocal(s)?.formatted(.dateTime.month().day().hour().minute()) ?? s.prefix(16).description
    }
    /// 332 原码续期 (⚠ 降级): 沿用原密码值改期 7 天, 走既有 0A 原位改写; 锁端未连则入队, 不新增协议
    private func renewExpired(_ p: LedgerPwd) async {
        guard let kc = app.current, let v = p.pwd, !renewing else { return }
        renewing = true
        defer { renewing = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fromS = f.string(from: Date())
        let toS = f.string(from: Date().addingTimeInterval(7 * 86400))
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let alias = try await app.lock.pwdModify(alias: p.alias, pwd: v, validFrom: fromS, validTo: toS)
            if alias != p.alias {
                // 确认口径：同 PwdStudio 编辑分支那条 —— 332 原码续期走锁端 0A 原位改写，返回新槽号时旧槽在锁里已不存在，
                //   下一行 addPwd 用同一个密码值把台账补到新槽，是换槽不是删除，所以不问。
                DB.delPwd(kc.mac, p.alias)
                DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: fromS, to: toS, temp: true,
                                            at: Date().timeIntervalSince1970 * 1000, pwd: v, owner: p.owner, note: p.note))
            } else {
                DB.setPwdPeriod(kc.mac, p.alias, fromS, toS)
            }
            CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: DB.getPwd(kc.mac, alias), fp: nil, note: "原码续期 7 天 (332, 约)")
            app.showToast("已沿用原值续期 7 天 (332, 锁端留存未确证)")
        } catch {
            // 用函数入口捕获的 kc.mac，不用**活读**的 `mac` 计算属性：两次 await 之间当前锁可能被
            // AppIntent / kf:// 深链改掉，那样成功路径写 A 锁、失败入队却指向 B 锁。
            CredentialOrg.enqueue(kc.mac, kind: "period", title: "续期 7 天 密码 #\(p.alias) (332)", pwd: p, newFrom: fromS, newTo: toS)
            app.showToast("锁未连接, 续期已记入待下发队列 (365)")
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            Text(v)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// ================= 323 删除双签: 删除成员最后一枚指纹需前缀验证任一在用密码 =================
func fpDoubleSignCheck(mac: String, batch: Int, confirmTitle: String, action: @escaping () -> Void) {
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
            ? "这是该成员名下最后一枚可用指纹，且本机没有在用的密码可双签；删掉后此人两种凭证都没了，只能本人到锁前重录 (324)。"
            : ""
        confirmDestructive("删除指纹「\(f.name)」",
                           lastWarn + "锁端这条立即作废，不可撤销；本机回收站 \(CredentialOrg.reclaimDays()) 天内找回的是名称/备注/归属这条档案，" +
                           "开门能力只能本人到锁前重录 (670)。",
                           confirmTitle: confirmTitle) { action() }
        return
    }
    let mask = String(v.prefix(max(v.count / 2, 2)))
    let alert = UIAlertController(
        title: "双签验证 (323)",
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
            let fail = UIAlertController(title: "双签未通过", message: "前缀不符, 删除已取消 (323)。", preferredStyle: .alert)
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
                Text("这把锁只剩 1 枚可用指纹, 建议补一枚备用 (324)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bell.badge")
            }
            .font(.caption)
            .foregroundStyle(DS.Palette.warn)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 4)
            .background(DS.Palette.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("先选归属, 再录入 (317 归属先行)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            ForEach(DB.members()) { m in
                let cnt = CredentialOrg.fpCountByOwner(mac, m.id)
                // 317 归属行可读标签: 拆成显式 String 局部量 —— 原先整条拼接写在 ViewBuilder 里会
                // 让编译器 "unable to type-check this expression in reasonable time"。
                let cntTag: String = cnt == 0 ? "无指纹" : "\(cnt) 枚"
                let selTag: String = owner == m.id ? ", 已选" : ""
                Button {
                    owner = m.id
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Text(m.name)
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                        if cnt == 0 {
                            Label("无指纹", systemImage: "person.badge.shield.slash")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.warn)
                                .lineLimit(1)
                        } else {
                            Text("\(cnt) 枚")
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
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
                .accessibilityLabel("归属 " + m.name + " " + cntTag + selTag)
            }
            if DB.members().isEmpty {
                Text("还没有成员 (317 归属先行必选)。请先到成员中心新建成员再返回, 或跳过归属稍后在台账补。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    // 317 无成员直达: 走 817 同一条道 (成员中心到达即弹建档向导), 建完值经 pendingFpOwner 带回
                    app.pendingFpOwner = "request"
                    app.pendingMemberAdd = true
                    app.tabSelection = 3
                    app.showToast("在「家人与钥匙」里新建成员 (317)")
                    dismiss()
                } label: {
                    Label("去新建成员 (317)", systemImage: "person.badge.plus")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Palette.accentText)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
        }
        .card()
    }

    // ---------- 41 沉浸式录入 (复用 Achievement 的 hero 渐变聚焦语言 + 大圆点) ----------
    private var immersive: some View {
        HeroCard {
            VStack(spacing: DS.Space.xl) {
                Text(progressText)
                    .font(.headline)
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
                Text("请选好的手指按在门锁指纹头上, 抬起, 重复 8 次 (41 全屏聚焦)")
                    .font(.footnote)
                    .foregroundStyle(DS.heroFg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !error.isEmpty {
                    Label {
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(DS.heroFg)
                    .multilineTextAlignment(.center)
                }
                HStack(spacing: DS.Space.s) {
                    Button {
                        presses = []
                        error = ""
                    } label: {
                        Text("重置进度")
                            .font(.footnote.weight(.medium))
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
                        .font(.headline)
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
        if presses.isEmpty { return "准备就绪" }
        if presses.count < 8 { return "重复此步骤 (\(presses.count)/8)" }
        return "正在确认…"
    }

    // ---------- 315/174 命名建议轮播 + 319 重录继承 ----------
    @ViewBuilder
    private var step2: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("命名 (315 建议轮播, 点按填入)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(suggestionPool, id: \.self) { sug in
                        Button {
                            name = sug
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Text(sug)
                                .font(.caption.weight(.medium))
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
                .font(.subheadline)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
            TextField("备注 (179 给谁·哪扇门·用多久)", text: $note, prompt: Text("仅本机留存"))
                .font(.subheadline)
                .frame(minHeight: DS.Hit.min)
            // 319 重录继承: 同成员已有指纹 → 成功后旧指纹入回收站 (保留原备注/归属, 来源"重录替代")
            if !sameOwnerFps.isEmpty {
                Toggle("该成员已有 \(sameOwnerFps.count) 枚指纹, 录入成功后将旧指纹移入回收站 (319 重录继承, 保留原备注/归属)", isOn: $replaceOld)
                    .font(.caption)
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
                .font(.headline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("请用新指纹开一次锁, 确认可用。" + (replaceOld ? " 旧指纹已移入回收站 (319, 来源标注「重录替代」)。" : ""))
                .font(.footnote)
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
        HStack {
            if step > 0 {
                Button("上一步") {
                    withAnimation(DS.Motion.quick) { step -= 1 }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step == 0 {
                Button("下一步: 录入") {
                    guard owner != nil || DB.members().isEmpty else {
                        app.showToast("先选归属成员 (317 归属先行)")
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    withAnimation(DS.Motion.quick) { step = 1 }
                    DS.Haptics.tick.impactOccurred()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
            if step == 2 {
                Button("保存登记") { saveAndClose() }
                    .font(.subheadline.weight(.semibold))
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
            app.showToast("已按建议命名「\(finalName)」 (315/174), 可重命名")
        }
        // 319 重录继承: 同成员旧指纹入回收站 (来源"重录替代") + 锁端删除入队
        if replaceOld {
            for f in DB.listFps(em).filter { $0.owner == owner && $0.batch != Int(b) } {
                // 确认口径：这一刀是用户在上一步**自己勾上**的 (录入第 2 步那条 Toggle 的文案就把后果写全了：
                // 「录入成功后将旧指纹移入回收站 (319 重录继承, 保留原备注/归属)」) ⇒ 勾选即知情同意，
                // 再弹一次确认是把同一句话问两遍。可逆性也在那里兜住：addToBin 在前、锁端删除只是入队，
                // 还原时第一百五十二批的 reclaim 会把这条还没发出去的 del_fp 一并收回。
                CredentialOrg.addToBin(em, fp: f, source: .rererecord)
                DB.delFp(em, f.batch)
                CredentialOrg.enqueue(em, kind: "del_fp", title: "删除旧指纹批次 \(f.batch) (319 重录替代)")
            }
            app.showToast("旧指纹已移入回收站 (319, 备注/归属保留)")
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
            let ps = try await app.lock.fpStart(times: 8, timeoutMs: 30000,
                                                onPress: { p in self.presses.append(p) })
            self.presses = ps
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

// ================= 指纹详情 (316/320 ⚠ 台账推断; 323 双签; 324 冗余) =================
struct FpDetailStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let batch: Int
    @State private var busy = false
    @State private var showRelink = false   // 319 重录入口 sheet
    private var mac: String { app.current?.mac ?? "" }
    private var f: LedgerFp? { DB.getFp(mac, batch) }

    var body: some View {
        if let f = f {
            NavigationStack {
                List {
                    // 324 冗余横条: 该成员名下仅剩此枚 → 提示补备用
                    if CredentialOrg.fpCountByOwner(mac, f.owner) == 1 {
                        Section {
                            Label("该成员名下仅剩 1 枚指纹, 建议补一枚备用 (324)", systemImage: "bell.badge")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.06))
                    }
                    // 316 档案三行统计 (⚠ 台账推断+积累, 标"约")
                    Section("档案 (316, 约)") {
                        fpRow("登记", f.at > 0 ? "登记于 " + f.at.credDay() : "已登记在门锁内")
                        let useN = CredentialOrg.fpUseCount30d(mac)
                        if useN > 0 {
                            fpRow("近 30 天指纹开门", "约 \(useN) 次 (日志无指纹身份字段, 整锁推断)")
                        }
                        // 320 误识档案 (⚠ 锁端 type13 语义待实测, 只展示本地日志计数标"约")
                        let alarmN = CredentialOrg.fpAlarmLogCount(mac)
                        fpRow("指纹告警日志", alarmN > 0 ? "约 \(alarmN) 条 (type13, 语义待实测)" : "无 (type13)")
                    }
                    Section {
                        fpRow("名称", f.name)
                        fpRow("归属", CredentialOrg.ownerName(f.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(f.owner))
                        fpRow("备注", f.note.isEmpty ? "无" : f.note)
                        fpRow("来源", f.src == "app" ? "本机录入" : "锁端发现")
                        fpRow("预警", f.isAlarm == true ? "预警指纹" : "普通")
                    }
                    Section {
                        // 319 重录入口: 卡里直接重录, 归属/替换旧枚自动带过去
                        Button { showRelink = true } label: {
                            Label("重录一枚替换它 (319)", systemImage: "arrow.clockwise")
                        }
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    }
                    Section {
                        // 323 删除双签: 最后一枚需密码前缀验证
                        if busy {
                            ProgressView("删除中…")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .frame(minHeight: DS.Hit.min)
                        } else {
                            Button(role: .destructive) {
                                fpDoubleSignCheck(mac: mac, batch: batch, confirmTitle: "彻底删除") {
                                    Task { await delete() }
                                }
                            } label: {
                                Label("彻底删除 (323 最后一枚需双签)", systemImage: "trash")
                            }
                            .font(.subheadline)
                            .foregroundStyle(DS.Palette.danger)
                        }
                    }
                }
                .navigationTitle(f.name)
                .scrollContentBackground(.hidden)
                .dsScreenBackground()
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
                .sheet(isPresented: $showRelink) {
                    FpStudio(prefillOwner: f.owner, prefillReplace: true)   // 319
                }
            }
        } else {
            EmptyState(systemImage: "touchid", title: "指纹不存在", message: "这条指纹可能已被删除或移入回收站。")
        }
    }
    private func fpRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            Text(v)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
    private func delete() async {
        guard let kc = app.current, let f else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await app.lock.fpDelete(UInt32(f.batch))
            // 同上: 锁端删的是入口捕获的那把锁，本机台账与回收站也必须记在同一把锁上
            // 确认口径：删除入口那一把按钮先过 fpDoubleSignCheck —— 最后一枚要前缀双签，
            // 其余也要走一遍确认，两支都不存在「一按就删」(第一百六十七批补的正是后半支)。
            CredentialOrg.addToBin(kc.mac, fp: f, source: .manual)
            DB.delFp(kc.mac, f.batch)
            app.flashReceipt("已写入本机 (508)")
            // 原来这句写死「回收站 30 天可找回」：30 天是 `kf_cbin_reclaim_days` 可调项 (写死就会在
            // 用户改成 7/90 天时说谎)，更要命的是「可找回」对指纹只成立一半 —— 回来的名称/备注/归属
            // 是档案，锁端那条模板已经删了，开门能力必须本人重录 (回收站页 670 早就把这句写明了)。
            app.showToast("指纹已删除：\(CredentialOrg.reclaimDays()) 天内可找回的只是这条档案，开门要本人到锁前重录 (670)")
        } catch {
            app.showToast("删除失败: " + error.localizedDescription)
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
                    Section("用于哪把锁 (339)") {
                        Picker("", selection: Binding(get: { otpMac }, set: { targetMac = $0 })) {
                            ForEach(DB.keychains(), id: \.mac) { kc in
                                Text(LockArchive.displayName(kc)).tag(kc.mac)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minHeight: DS.Hit.min)
                        Text("独立口令按锁存档 (kf_cotp_t_) —— 备份也按锁导出, 换一把锁就是另一组口令。")
                            .font(.caption2)
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
                                .font(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // 343 独立口令组: 口令与锁协议无关, 但**按当前锁存档** —— 小字照实写, 不再说"与锁无关"就完事
                Section {
                    let list = CredentialOrg.totpEntries(otpMac)   // 339: 按选择的目标锁取组
                    if list.isEmpty {
                        Text("还没有独立口令。粘贴 otpauth:// 文本导入, 或手工添加 (341)。口令本身跟门锁协议无关 (手机自己算), 但它按当前这把锁存档 —— 换锁就是另一组。")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(list) { e in
                        totpRow(e)
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("导入 otpauth:// 文本 (341)", systemImage: "square.and.arrow.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    // 341 手工添加整段: 名称 / Base32 密钥 / 算法 / 周期 / 位数, 错误行与导入那条各走各的
                    Button {
                        showManual.toggle()
                        if !showManual { manualErr = "" }
                        DS.Haptics.tick.impactOccurred()
                    } label: {
                        Label(showManual ? "收起手工添加 (341)" : "手工添加 (341)", systemImage: "keyboard")
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                    if showManual { manualForm() }
                } header: {
                    Text("独立口令 (343, 与锁协议无关 · 按当前锁存档)")
                } footer: {
                    Text("组尾实话: 这些口令不经过门锁、也不进锁端协议, 但存的键带锁的 MAC (kf_cotp_t_) —— 因为备份按锁导出。换一把锁, 这一组就换成另一把锁的那一组。")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 346 静态备份码: 本地生成一次性静态码, 不走锁端, 随备份导出
                Section("静态备份码 (346)") {
                    let codes = CredentialOrg.staticCodes(mac)
                    ForEach(codes) { c in
                        staticRow(c)
                    }
                    TextField("备注 (346 给谁/干什么)", text: $noteDraft, prompt: Text("仅本机留存"))
                        .font(.subheadline)
                        .frame(minHeight: DS.Hit.min)
                    Button {
                        let name = "备份码 " + String(codes.count + 1)
                        CredentialOrg.addStaticCode(otpMac, CredentialOrg.StaticCode(
                            id: UUID().uuidString, name: name,
                            code: StudioTools.genDigits(8), note: noteDraft, used: false,
                            at: Date().timeIntervalSince1970))
                        noteDraft = ""
                        app.showToast("已生成 8 位静态备份码 (346, 本地)")
                    } label: {
                        Label("生成 8 位静态码", systemImage: "plus")
                    }
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.accentText)
                                    }
            }
            .navigationTitle("OTP 与口令")
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .axBottomAnchor()   // 870
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onReceive(timer) { t in tick = t }
            .sheet(isPresented: $importing) {
                NavigationStack {
                    Form {
                        Section("粘贴 otpauth 文本 (341, 纯本地解析)") {
                            TextField("otpauth://totp/…?secret=…", text: $importUri, axis: .vertical)
                                .font(.footnote)
                                .autocorrectionDisabled()
                        }
                        if !importErr.isEmpty {
                            Section {
                                Label(importErr, systemImage: "exclamationmark.circle")
                                    .font(.caption)
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
                                    app.showToast("已导入「\(r.name)」(\(r.algo)·\(r.digits)位·\(r.period)s)" + tail + " (按当前锁存档, 343)")
                                    importUri = ""
                                    importErr = ""
                                    importing = false
                                case .failure(let f):
                                    importErr = "导入失败 (341): " + f.rawValue + "; 缺什么就补什么, 或直接关掉这里改用手工添加"
                                }
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                    .navigationTitle("导入 otpauth (341)")
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
                .font(.subheadline)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
            TextField("Base32 密钥", text: $manualSecret, prompt: Text("验证器里那串 A-Z 与 2-7"))
                .font(.footnote.monospaced())
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            Picker("算法", selection: $manualAlgo) {
                ForEach(["SHA1", "SHA256", "SHA512"], id: \.self) { a in
                    Text(a).tag(a)
                }
            }
            .font(.caption)
            HStack(spacing: DS.Space.xs) {
                Picker("周期", selection: $manualPeriod) {
                    ForEach([30, 60], id: \.self) { p in
                        Text("\(p) 秒").tag(p)
                    }
                }
                Picker("位数", selection: $manualDigits) {
                    ForEach([6, 8], id: \.self) { d in
                        Text("\(d) 位").tag(d)
                    }
                }
            }
            .font(.caption)
            if !manualErr.isEmpty {
                Label(manualErr, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(manualErr)
            }
            Button {
                addManualTotp()
            } label: {
                Label("保存这条独立口令", systemImage: "plus.circle")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(DS.Palette.accentText)
            .frame(minHeight: DS.Hit.min)
            Text("算法与周期按你选的这几档算 (RFC 6238 常用档); 锁端 ZOTP 仍走分钟级, 两者互不相干 (337)。")
                .font(.caption2)
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
            manualErr = "密钥是空的: 请粘贴验证器给出的那串 Base32 (341 手工添加)"
            DS.Haptics.trigger.impactOccurred()
            return
        }
        guard StudioTools.base32Decode(secret) != nil else {
            manualErr = "密钥不是合法 Base32: 只允许 A-Z 与 2-7, 这里出现了字母表外的字符 (341 手工添加)"
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
        app.showToast((typed.isEmpty ? "已添加「\(named)」(名称按密钥尾段回退, 341)" : "已添加「\(named)」(341)")
            + " · \(manualAlgo)·\(manualDigits)位·\(manualPeriod)s, 按当前锁存档 (343)")
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                // 338 单击即复制 (拍板: **不改行的点击语义**) —— 只把码值这一块做成整块可点的复制区，
                // 行本身不当事件源；下面那个「复制」按钮保留，给 VoiceOver 和不想瞄准的人。
                Button {
                    ClipboardCare.copySecret(now, via: "独立 TOTP")   // 405 同一出口
                    app.showToast("已复制当前码 (338)")
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Text(cap.recording ? "已隐去 (374)" : now)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DS.Palette.text)
                            .textSelection(.enabled)
                        Text("↓")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                        Text(cap.recording ? "已隐去 (374)" : next)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    .padding(.horizontal, DS.Space.xs)
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制当前码 \(e.name)")
            }
            WindowBar(totalSec: max(e.period, 1), label: "340 当前/下一时窗并排 · " + CredentialOrg.totpParams(e))
            HStack(spacing: DS.Space.xs) {
                Button {
                    ClipboardCare.copySecret(now, via: "独立 TOTP")   // 405
                    app.showToast("已复制当前码")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeTotp(otpMac, e.id)   // 339: 与取组的锁保持一致
                    app.showToast("已移除「\(e.name)」")
                } label: {
                    Label("移除", systemImage: "trash")
                }
                .font(.caption.weight(.medium))
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
            HStack {
                Text((c.used ? "已用 · " : "") + c.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(c.used ? DS.Palette.textSub : DS.Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(c.code)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(c.used ? DS.Palette.textSub : DS.Palette.text)
                    .textSelection(.enabled)
            }
            if !c.note.isEmpty {
                Text(c.note)
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: DS.Space.xs) {
                Button {
                    var n = c; n.used = true
                    CredentialOrg.saveStaticCodes(mac, CredentialOrg.staticCodes(mac).map { $0.id == c.id ? n : $0 })
                    app.showToast("已标记「\(c.name)」为已用 (346)")
                } label: {
                    Label(c.used ? "撤销已用" : "标记已用", systemImage: c.used ? "arrow.uturn.left" : "checkmark")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeStaticCode(mac, c.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("删除静态码 \(c.name)")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// ================= 工坊入口: 凭证 Tab "凭证工坊" 一行 (177 扇出) =================
struct CredStudioEntryView: View {
    var body: some View {
        NavigationLink {
            StudioHome(embedded: true)
        } label: {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.accentText)
                    .frame(width: DS.Icon.md + 8, height: DS.Icon.md + 8)
                    .background(DS.Palette.accentText.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Space.s, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("凭证工坊")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
                    Text("添加·改造·口述卡·OTP 独立口令 (包5)")
                        .font(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("凭证工坊, 四类凭证的添加·编辑·详情")
    }
}

