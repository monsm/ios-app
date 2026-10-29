// ↑ 本文件是 CredentialStudio.swift 拆分后的「共享组件」部分（2026-10-29）

// 包5 凭证工坊 — **三类**凭证 (密码/临时码/指纹) 的添加·编辑·详情
// 2026-10-26 勘误: 头注原写"四类(…/OTP)"。OTP 独立口令（TOTP/静态备份码）**从未建过页面** ——
//   StudioHome 只列三类，数据层 kf_cotp_t_ / kf_cotp_s_ 已随 OtpStudio 删除（2026-10-26 连备份白名单也一并删了）。
//   临时码（ZOTP）是**另一回事**：它由锁端种子算出、按 30 分钟窗口变，不是独立的 TOTP 种子。
// 收录 (按 ROADMAP 包5): 7-8/11/34/41/171-174/177-179/301/303-317/319-320/322-346/515-523
// ⚠ 降级项 (全部本地推断, 文案带"约"): 311/316/320/326/335/332/333/337; 舍弃 302/318/321 不实现。
// 纪律: 颜色只走 DS 令牌; 不新增协议命令 (178 批量走既有 0A 逐条); 新键 kf_c* 向后兼容。
import SwiftUI
import UIKit
import AVFoundation
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
    // 2026-10-27 四轮精简：五场景预设已删。
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
    // 388 首次"揭示=查看"记一次敏感台账, 防逐位点按刷屏
    @State private var ledgerLogged = false
    var body: some View {
        // 369 遮蔽样式: 与安全中心 maskStyleLabel 三档口径逐字对齐
        let style = ""
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
                    }
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
            if !revealed.isEmpty { revealed = [] }
        }
    }

    /// 849 双击/转子动作: 拷贝整条明文 (与详情页「复制」同一条 405 通路)
    private func copyAll() {
        Clip.set(value)
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

/// 172/328 大字口述卡 (可拍照/可剪贴; 34 卡片厚度; 含码风险提示)
struct CodeBigCard: View {
    let title: String
    let code: String
    let window: String
    var note: String = ""
    var extraFoot: String = ""
    @EnvironmentObject var app: AppState
    /// 2026-10-28 修复：注释写着「默认遮下半段，「完整显示」后露出全码」，
    /// 但 `Text(code)` 直接印的是**完整码值** —— 没有遮、也没有「完整显示」按钮。
    /// 而 SecurityPolicy.halfMasked 全仓零调用（注释还断言它「一直在生效」）。
    @State private var revealCode = false
    /// 376 分享遮半: 默认遮下半段, 「完整显示」后露出全码; 每次进卡片 (完成页/sheet 重建) 都回默认遮, 不跨次保留。
    var body: some View {
        VStack(spacing: DS.Space.s) {
            Text(title)
                .vkFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Palette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(revealCode ? code : SecurityPolicy.halfMasked(code))
                .vkFont(.system(.largeTitle, design: .rounded).monospacedDigit(), weight: .semibold)
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
                // 370: 口述卡这一路也接贴近复蔽 (卡片在屏期间才开监听)
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
                // 2026-10-28 补：与遮半配套的「完整显示」开关（注释承诺过，但从未存在）
                Button {
                    revealCode.toggle()
                    DS.Haptics.tick.impactOccurred()
                } label: {
                    Label(revealCode ? "隐藏" : "完整显示", systemImage: revealCode ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .vkFont(.caption)
                .frame(minHeight: DS.Hit.min)
                // 复制给的是**全码**：用户主动取用，遮半会让复制出来的码没法用。
                // 遮半只作用于**屏幕显示**（防旁人一眼看到）。

                Button {
                    Clip.set(code)   // 405
                    app.showToast("码值已复制")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .vkFont(.caption)
                .frame(minHeight: DS.Hit.min)
                .accessibilityLabel("复制码值")
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
        // 2026-10-27 审核修复 (AUDIT-D D-40)：这张卡含密码/动态码，可被截图外传。
        // 检测到录屏/截图时遮住（停止后自动恢复）。
        .captureShield("本卡含密码\n屏幕正在被录制或截图，已遮挡")
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

// ================= 177 扇出新增: 凭证工坊四入口 =================