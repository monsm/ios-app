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
final class StudioTTS {
    static let synth = AVSpeechSynthesizer()
    /// 309 逐位中文播报 (电话转述时让对方同步记录)
    static func speakDigits(_ s: String) {
        let zh = s.map { ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"][Int($0) ?? 0] }
        let u = AVSpeechUtterance(string: "密码逐位: " + zh.joined(separator: "、") + "。")
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.35
        synth.speak(u)
    }
}

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
        let c = Calendar.current
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
    /// 341 otpauth://totp 解析 (纯本地; 缺 secret → nil, 逐字段缺失由 UI 提示)
    static func parseOtpAuth(_ uri: String) -> (name: String, secret: String, algo: String, period: Int, digits: Int)? {
        guard let u = URL(string: uri), u.scheme?.lowercased() == "otpauth", u.host?.lowercased() == "totp" else { return nil }
        var secret = "", name = "", algo = "SHA1", period = 30, digits = 6
        for pair in (u.query ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch String(kv[0]).lowercased() {
            case "secret": secret = String(kv[1])
            case "issuer", "label": if name.isEmpty { name = String(kv[1]) }
            case "algorithm": algo = String(kv[1]).uppercased()
            case "period": period = Int(String(kv[1])) ?? 30
            case "digits": digits = Int(String(kv[1])) ?? 6
            default: break
            }
        }
        guard !secret.isEmpty else { return nil }
        return (name.isEmpty ? "导入口令" : name, secret, algo, period, digits)
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
        default: mac = Data(HMAC<SHA1>.authenticationCode(for: Data(bytes), using: key))
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

/// 303 大号逐位回显 (默认打码, 逐位点开揭示 — 延续包7 打码语义; 11 复制按钮形变同源)
struct MaskedDigits: View {
    let value: String
    var big: Bool = false
    @State private var revealed: Set<Int> = []
    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(value.enumerated()), id: \.offset) { i, ch in
                let on = revealed.contains(i)
                Button {
                    revealed.formSymmetricDifference([i])
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Text(on ? String(ch) : "•")
                        .font(big ? .title.weight(.semibold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(on ? DS.Palette.text : DS.Palette.textSub)
                        .frame(width: big ? 36 : 30)
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(on ? "第 \(i + 1) 位" : "第 \(i + 1) 位, 点按显示")
            }
        }
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
    var body: some View {
        VStack(spacing: DS.Space.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(code)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
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
                    UIPasteboard.general.string = code
                    app.showToast("码值已复制")
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
        [title, "码值 \(code)", window, "备注 \(note)"].filter { !$0.isEmpty }.joined(separator: "\n")
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
        DataScannerView { session in
            session.recognitionLanguages = ["zh-Hans", "en"]
            session.supportedDataTypes = [.qr, .dataMatrix]
        } results: { results in
            for r in results {
                if let item = r.data.item, let s = item.string {
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
    @State private var to = Date()
    @State private var note = ""
    @State private var useTemplate = true
    @State private var busy = false
    // 519 错误字段定位 (步间拦截保证不错位; 深字段靠红框+人话原因)
    @State private var errorField: String = ""
    @State private var showScan = false
    // 301 剪贴板来源条
    @State private var clipSource = false
    @State private var showDraftBar = true
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
                errorLine("码值需 6~8 位数字 (519 红框定位到本字段)。")
            }
            let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: editAlias ?? -1) : []
            if !dups.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    Label("已有 \(dups.count) 条同值凭证 (304)", systemImage: "plus.slash.minus")
                        .font(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    Spacer(minLength: 0)
                    Button("查看") {
                        app.showToast("同值: " + dups.map { CredentialOrg.displayPwd($0) }.prefix(3).joined(separator: ", ") + " (304 全库重复拦截, 建议换值或合并归属)")
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
                    Text("有效期 (临时码)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.text)
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
                        errorLine("到期需晚于生效 (519 定位到有效期字段)。")
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("长期密码无到期点; 老旧巡检 (305) 会在详情页提示超 180 天建议换码。")
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
                TextField("如: 钟点工·大门·仅上午场 (523 可长按调听写)", text: $note,
                          prompt: Text("给谁 · 哪扇门 · 用多久"))
                    .font(.subheadline)
                    .frame(minHeight: DS.Hit.min)
                    .autocorrectionDisabled()
                if useTemplate {
                    Toggle("备注自动补命名模板 (918 谁-哪里-何时)", isOn: $useTemplate)
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    private func todayEndSecs() -> Int {
        let end = Calendar.current.date(bySetting: .hourAndMinute(23, 59), of: Date()) ?? Date().addingTimeInterval(86400)
        return max(Int(end.timeIntervalSinceNow), 60)
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
                BusyButton(title: editing == nil ? "下发密码" : "保存改造", systemImage: "key.fill", isBusy: busy) {
                    Task { await submit() }
                }
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
                    if step == 2, kind == 1, to <= from {
                        to = from.addingTimeInterval(3600)
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
        guard editAlias == nil, step > 0 || !pwd.isEmpty else { return }
        CredentialOrg.saveDraft(mac, CredentialOrg.StudioDraft(
            step: step, kind: kind, pwd: pwd, permanent: kind == 0,
            fromISO: iso(from), toISO: iso(to), owner: owner,
            useTemplate: useTemplate, note: note, scene: "", batch: 0,
            at: Date().timeIntervalSince1970))
    }

    // ---------- 提交 (既有协议 0A/原位改写; 178 批量另在临时码工坊) ----------
    private func submit() async {
        guard let kc = app.current, !busy else { return }
        guard pwdOK else {
            step = 1
            errorField = "value"
            app.showToast("码值需 6~8 位数字 (519)")
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
    @State private var to = Date()
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
        .navigationTitle("临时码")
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
                    // 304 全库重复拦截
                    let dups = pwdOK ? CredentialOrg.duplicatePwdValues(mac, pwd, excluding: -1) : []
                    if !dups.isEmpty {
                        Label("已有 \(dups.count) 条同值凭证 (304), 建议换一组", systemImage: "plus.slash.minus")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
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
                        quickPill("今天内") { from = Date(); to = todayEnd() }
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
                // 329 一句话口令文本
                if let r = result {
                    let text = StudioTools.oneLine(p: r, lockName: lockName, value: r.pwd)
                    Button {
                        UIPasteboard.general.string = text
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
                }
                // 333 首用回执 (⚠ 无 alias 字段, 按时间推断, 标"约")
                if let r = result, let t = CredentialOrg.firstUse(mac, r) {
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
                } else if let r = result {
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
                Button("再发一张") {
                    result = nil
                    pwd = StudioTools.genDigits(6)
                    note = ""
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
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
    private func todayEnd() -> Date {
        Calendar.current.date(bySetting: .hourAndMinute(23, 59), of: Date()) ?? Date().addingTimeInterval(86400)
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
            CredentialOrg.clearDraft(mac)
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
    private var mac: String { app.current?.mac ?? "" }
    private var p: LedgerPwd? { DB.getPwd(mac, alias) }

    var body: some View {
        if let p = p {
            NavigationStack {
                List {
                    // 305 老旧巡检: 超 180 天未修改建议换码 (⚠ 台账时间推断, 标"约")
                    if CredentialOrg.isStalePwd(p) {
                        Section {
                            HStack(spacing: DS.Space.s) {
                                Label("已约 \(CredentialOrg.pwdAgeDays(p) ?? 0) 天未修改, 建议换码 (305, 约)",
                                      systemImage: "clock.arrow.circlepath")
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
                    Section("码值 (默认打码, 点位揭示)") {
                        if let v = p.pwd {
                            MaskedDigits(value: v, big: true)
                        } else {
                            Text("当时未留存明文, 可在锁上核对后回填")
                                .font(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let v = p.pwd {
                            HStack(spacing: DS.Space.xs) {
                                Button("复制 (11)") {
                                    UIPasteboard.general.string = v
                                    app.showToast("已复制")
                                }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .frame(minHeight: DS.Hit.min)
                                Button("读出 (309)") { StudioTTS.speakDigits(v) }
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
                                            UIPasteboard.general.string = c
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
                    // 331 提前失效滑杆: 本地意图, 到点后巡检行提示停用, 不改协议
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
                                    Text("临近失效的列表行将挂渐进色条 (约)")
                                        .font(.caption2)
                                        .foregroundStyle(DS.Palette.textSub)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                Slider(value: Binding(
                                    get: { Double(CredentialOrg.earlyExpireMin(mac, p.alias)) },
                                    set: { CredentialOrg.setEarlyExpireMin(mac, p.alias, Int($0)) }
                                ), in: 0...120, step: 5)
                                .tint(DS.Palette.accent)
                                .frame(minHeight: DS.Hit.min)
                                .accessibilityLabel("提前失效分钟数滑杆 (331)")
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
                    // 335 线性用量刻度 (⚠ 锁端无计次, 本地 type4 计数, 标"约")
                    if p.temp {
                        Section("用量 (335, 约)") {
                            let u = CredentialOrg.usageCount(mac, p)
                            HStack(spacing: DS.Space.s) {
                                HStack(spacing: 3) {
                                    ForEach(0..<8, id: \.self) { i in
                                        Capsule()
                                            .fill(i < min(u, 8) ? DS.Palette.accent : DS.Palette.surfaceAlt)
                                            .frame(width: 14, height: 5)
                                    }
                                }
                                Text(u > 0 ? "已用约 \(u) 次 (本地计次, 锁端无计次字段)" : "未用 (本地计次, 约)")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                            }
                            .accessibilityLabel("用量刻度, 已用约 \(u) 次 (326/335, 锁端无计次, 约)")
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
                        row("状态", CredentialOrg.stateLabel(CredentialOrg.pwdState(p)) + " · " + CredentialOrg.countdown(p))
                        row("归属", CredentialOrg.ownerName(p.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(p.owner))
                        row("备注", p.note.isEmpty ? "无" : p.note)
                    }
                    // 311 同码引用卡 (⚠ 按时间窗推断, 标"约")
                    Section("用它开过的门 (311, 约)") {
                        let n = CredentialOrg.openCountInWindow(mac, p)
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
                DB.delPwd(kc.mac, p.alias)
                DB.addPwd(kc.mac, LedgerPwd(alias: alias, from: fromS, to: toS, temp: true,
                                            at: Date().timeIntervalSince1970 * 1000, pwd: v, owner: p.owner, note: p.note))
            } else {
                DB.setPwdPeriod(kc.mac, p.alias, fromS, toS)
            }
            CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: DB.getPwd(kc.mac, alias), fp: nil, note: "原码续期 7 天 (332, 约)")
            app.showToast("已沿用原值续期 7 天 (332, 锁端留存未确证)")
        } catch {
            CredentialOrg.enqueue(mac, kind: "period", title: "续期 7 天 密码 #\(p.alias) (332)", pwd: p, newFrom: fromS, newTo: toS)
            app.showToast("锁未连接, 续期已记入待下发队列 (365)")
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .leading) {
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
    guard let f = DB.getFp(mac, batch) else {
        action()
        return
    }
    let need = CredentialOrg.fpCountByOwner(mac, f.owner) == 1
    guard need, let v = DB.listPwds(mac).first(where: { $0.pwd != nil && CredentialOrg.pwdState($0) == 0 })?.pwd else {
        action()
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
    @State private var busy = false
    @State private var error = ""
    @State private var doneBatch: UInt32?
    @State private var name = ""
    @State private var note = ""
    @State private var replaceOld = false    // 319 重录继承: 同成员旧指纹移回收站

    private var mac: String { app.current?.mac ?? "" }
    private var sameOwnerFps: [LedgerFp] {
        owner == nil ? [] : DB.listFps(mac).filter { $0.owner == owner && $0.batch != Int(doneBatch ?? 0) }
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
            }
        }
        .navigationTitle("录入指纹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
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
                .accessibilityLabel("归属 " + m.name + " " + (cnt == 0 ? "无指纹" : "\(cnt) 枚") + (owner == m.id ? ", 已选" : ""))
            }
            if DB.members().isEmpty {
                Text("还没有成员 (317 归属先行必选)。请先到成员中心新建成员再返回, 或跳过归属稍后在台账补。")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .foregroundStyle(.white)
                VStack(spacing: DS.Space.s) {
                    ProgressView(value: Double(min(presses.count, 8)), total: 8)
                        .tint(.white)
                        .frame(maxWidth: 220)
                    HStack(spacing: DS.Space.s) {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(i < presses.count ? .white.opacity(0.95) : .white.opacity(0.22))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text("请选好的手指按在门锁指纹头上, 抬起, 重复 8 次 (41 全屏聚焦)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !error.isEmpty {
                    Label {
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                }
                HStack(spacing: DS.Space.s) {
                    Button {
                        presses = []
                        error = ""
                    } label: {
                        Text("重置进度")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await start() }
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            if busy {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "touchid")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text(busy ? "录入中…" : "开始录入")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s + 2)
                        .background(.white.opacity(0.16), in: Capsule())
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
        let finalName = name.isEmpty ? CredentialOrg.fpNameSuggestion(mac, owner: owner) : name
        DB.addFp(mac, LedgerFp(batch: Int(b), name: finalName, at: Date().timeIntervalSince1970 * 1000,
                               note: note, src: "app", owner: owner, isAlarm: false))
        if name.isEmpty {
            app.showToast("已按建议命名「\(finalName)」 (315/174), 可重命名")
        }
        // 319 重录继承: 同成员旧指纹入回收站 (来源"重录替代") + 锁端删除入队
        if replaceOld {
            for f in sameOwnerFps {
                CredentialOrg.addToBin(mac, fp: f, source: .rererecord)
                DB.delFp(mac, f.batch)
                CredentialOrg.enqueue(mac, kind: "del_fp", title: "删除旧指纹批次 \(f.batch) (319 重录替代)")
            }
            app.showToast("旧指纹已移入回收站 (319, 备注/归属保留)")
        }
        withAnimation(DS.Motion.standard) { step = 3 }
    }

    private func start() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        error = ""
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let ps = try await app.lock.fpStart(times: 8, timeoutMs: 30000)
            self.presses = ps
            guard let batch = ps.compactMap({ $0.batchNumber }).first, batch > 0 else {
                throw NSError(domain: "fp", code: 1, userInfo: [NSLocalizedDescriptionKey: "未拿到有效指纹批次, 请重新录入"])
            }
            try await app.lock.fpConfirm(batch, validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00")
            doneBatch = batch
            name = CredentialOrg.fpNameSuggestion(mac, owner: owner)
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
            }
        } else {
            EmptyState(systemImage: "touchid", title: "指纹不存在", message: "这条指纹可能已被删除或移入回收站。")
        }
    }
    private func fpRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .leading) {
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
            CredentialOrg.addToBin(mac, fp: f, source: .manual)
            DB.delFp(mac, f.batch)
            app.flashReceipt("已写入本机 (508)")
            app.showToast("指纹已删除, 回收站 30 天可找回")
        } catch {
            app.showToast("删除失败: " + error.localizedDescription)
        }
    }
}

// Double 台账毫秒 → 本地日期串 (凭证页同源, 局部实现)
private extension Double {
    func credDay() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: self / 1000))
    }
}

// ================= OTP 工坊 (171/337 ⚠ 时窗细条 / 340 双码 / 341 otpauth / 343 独立组 / 345 参数小字 / 346 静态备份码) =================
struct OtpStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tick = Date()
    @State private var importing = false
    @State private var importUri = ""
    @State private var importErr = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var mac: String { app.current?.mac ?? "" }

    var body: some View {
        NavigationStack {
            List {
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
                // 343 独立口令组: 与锁无关的纯手机 TOTP
                Section("独立口令 (343, 与锁无关)") {
                    let list = CredentialOrg.totpEntries(mac)
                    if list.isEmpty {
                        Text("还没有独立口令。粘贴 otpauth:// 文本导入, 或手工添加 (341)。")
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
                }
                // 346 静态备份码: 本地生成一次性静态码, 不走锁端, 随备份导出
                Section("静态备份码 (346)") {
                    let codes = CredentialOrg.staticCodes(mac)
                    ForEach(codes) { c in
                        staticRow(c)
                    }
                    Button {
                        let name = "备份码 " + String(codes.count + 1)
                        CredentialOrg.addStaticCode(mac, CredentialOrg.StaticCode(
                            id: UUID().uuidString, name: name,
                            code: StudioTools.genDigits(8), note: "", used: false,
                            at: Date().timeIntervalSince1970))
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
                                if let r = StudioTools.parseOtpAuth(importUri) {
                                    CredentialOrg.addTotp(mac, CredentialOrg.TOTPEntry(
                                        id: UUID().uuidString, name: r.name, secret: r.secret,
                                        algo: r.algo, period: r.period, digits: r.digits,
                                        at: Date().timeIntervalSince1970))
                                    app.showToast("已导入「\(r.name)」 (\(r.algo)·\(r.digits)位·\(r.period)s)")
                                    importUri = ""
                                    importErr = ""
                                    importing = false
                                } else {
                                    importErr = "解析失败: 需 otpauth://totp 且含 secret (缺密钥/算法/周期请补全, 341 逐字段提示)"
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
                Text(now)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DS.Palette.text)
                    .textSelection(.enabled)
                Text("↓")
                    .font(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                Text(next)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DS.Palette.textSub)
            }
            WindowBar(totalSec: max(e.period, 1), label: "340 当前/下一时窗并排 · " + CredentialOrg.totpParams(e))
            HStack(spacing: DS.Space.xs) {
                Button {
                    UIPasteboard.general.string = now
                    app.showToast("已复制当前码")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .frame(minHeight: DS.Hit.min)
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    CredentialOrg.removeTotp(mac, e.id)
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
        .id(tick)   // 每秒重算码值与细条
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

