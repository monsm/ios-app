// 包17 系统集成 — App Intents 基座 (App/Intents)
// 边界: 免费账号侧载可用面 = App Intents + 本地深链 + Spotlight。
//   · 全部意图 foreground 语义, 绝不后台开锁 (CONSTRAINTS.md)。
//   · 无 App Groups → Widget 读不到 App 数据。927 已按拍板落成**哑按钮小组件** (Widget/ 独立 target):
//     只把 App 打到设备页, 不显示锁状态/电量, 也不在组件里执行开锁。
//   · NFC / Watch / Live Activity 按 DEFERRED 降级 (本页做配置与路线图入口)。
// 治理: 同一意图 60s 冷却 (952) + 意图审计 (953, 记 SensitiveLedger, 审计流水独立分区) + 触发来源标记 (964)
//       + 意图冷却/审计 (952/953) + Siri 口令化参数名 (166/948)。焦点期确认 (949) 已按拍板划掉: 不申请 FocusKit 授权。
import SwiftUI
import AppIntents
import AVFoundation

// ---------- 意图治理 (冷却/审计/来源) ----------
enum IntentGovernance {
    static let cooldownPrefix = "kf_intent_cd_"
    /// 952: **同一意图** 60 秒内重复触发给冷却提示。键按意图名分开 —— 原先全族共用
    /// kf_intent_cooldown: 说一句「开锁」会把你 60 秒内的「查电量」一起顶掉、反过来也一样，
    /// 那不是"同一意图冷却"而是"全族轮流通行"。旧的共用键不再写入, 留在库里也不读。
    static func passCooldown(intent: String, interval: TimeInterval = 60) -> Bool {
        let key = cooldownPrefix + intent
        let last = Double(DB.store.getString(key)) ?? 0
        let now = Date().timeIntervalSince1970
        if now - last < interval { return false }
        DB.store.set(key, String(now))
        return true
    }
    /// 964: 触发来源标记 (意图名即来源); 审计统一走 SensitiveLedger (953)
    static func audit(intent: String, detail: String) {
        SensitiveLedger().record("intent·\(intent)", target: detail)
    }
}

// ---------- 945 开锁意图 (foreground, 回落 App 内圆盘衔接) ----------
/// 「锁名 → 台账里那一把」的**唯一**规则。原先这一份逻辑在本文件里写了四遍，其中两处已经漂：
/// 导出那半只认 `name ==` (不 trim、不认型号名)，而临时码/状态那两半认型号名；
/// 朗读那半更糟 —— 名字对不上时 `?? DB.keychains().first` **静默换一把锁**，
/// 把别的锁的开门记录念给用户听，还听着像他说的那把 (§10.37)。
/// 现在的次序：去空白 → 精确锁名 → 型号名 → **只有一个**包含命中才算；
/// 多把都含这个词时宁可反问，也不替用户挑一把 (锁是安全物件，猜错方向的代价不对称)。
enum IntentLock {
    // 刻意不写 `: Equatable`：`Keychain` 只 conform `Codable, Identifiable`，
    // 带上 Equatable 会让综合失败 (而这里从不需要比较 Outcome 本身)。
    enum Outcome {
        case empty                 // 没说名字
        case unique(Keychain)
        case none                  // 一把都对不上
        case ambiguous([String])   // 多把都含这个词
    }
    static func resolve(_ raw: String) -> Outcome {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .empty }
        let all = DB.keychains()
        if let exact = all.first(where: { $0.name == q }) ?? all.first(where: { PidMap.productName($0.pid) == q }) {
            return .unique(exact)
        }
        let part = all.filter { $0.name.contains(q) }
        if part.count == 1 { return .unique(part[0]) }
        if part.isEmpty { return .none }
        return .ambiguous(part.map { $0.name.isEmpty ? PidMap.productName($0.pid) : $0.name })
    }
    /// 不是唯一命中时该对用户说的话；唯一命中返回 nil。
    /// 调用点写法：`if let miss = refusal(x) { return .result(dialog: IntentDialog(stringLiteral: miss)) }` 再 `guard case .unique`。
    static func refusal(_ raw: String) -> String? {
        switch resolve(raw) {
        case .unique: return nil
        case .empty: return "请说出门锁名称, 如「打开 主卧门锁」"
        case .none: return "没有找到叫「\(raw.trimmingCharacters(in: .whitespacesAndNewlines))」的门锁 (本机共 \(DB.keychains().count) 把；可说锁名或型号名)"
        case .ambiguous(let names): return "有几把锁的名字都含「\(raw.trimmingCharacters(in: .whitespacesAndNewlines))」：\(names.joined(separator: " / "))。请说全名，我不替您猜。"
        }
    }
}

struct UnlockIntent: AppIntent {
    static let title: LocalizedStringResource = "打开门锁"
    static let description = IntentDescription("把手机靠近门锁后, 请说「打开 [门锁名]」")
    // 166: 口令收录后触发时要前台打开 App —— 本意图语义是「把 App 打到设备页, 最后一步仍在圆盘上按住确认」(945 回落路径),
    // 声明 openAppWhenRun 让对话框「请在 App 内完成开锁」说出时屏幕上确实是 App。
    // ⚠ API-VERIFY: openAppWhenRun 全仓 grep 零先例 (本文件是首个 AppIntent 注册方), 按 AppIntent 协议标准静态属性形状书写, 未编译、未证实
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "门锁")
    var lockName: String

    // 默认值走 `default:` 参数, **不是**属性声明处的 `= 值` —— 后者会被宏合成成
    // `Parameter(wrappedValue:)`, 而该初始化器不存在 (真编译报 "extra argument 'wrappedValue' in call")。
    @Parameter(title: "口令",
               description: "说「开门」以外的暗语可让家人知道这次开锁是你的",
               default: "开门")
    var passphrase: String

    @Parameter(title: "Face ID 确认",
               description: "开启后每次开锁前先用 Face ID 确认是你; 无生物硬件的设备会拒绝执行",   // 945 开启后每次开锁前先用
               default: false)
    var faceConfirm: Bool

    func perform() async throws -> some IntentResult {
        // 意图族门禁 (fail-closed): 设了本机密码而未解锁 → 拒绝。此前六个意图没有一个调用 IntentLockGate。
        if let block = await IntentLockGate.blockedMessage() { return .result(dialog: IntentDialog(stringLiteral: block)) }
        guard IntentGovernance.passCooldown(intent: "unlock") else {
            IntentGovernance.audit(intent: "unlock", detail: "\(lockName) 被冷却拦截")
            return .result(dialog: "刚执行过, 请稍候 60 秒再试")
        }
        // 945: 可选 Face ID 门槛 (fail-closed: 无生物硬件即拒)
        if faceConfirm {
            guard AuthKit.biometricAvailable else { return .result(dialog: "本机没有可用的 Face ID / Touch ID, 未定位门锁") }   // 945 本机没有可用的
            guard await AuthKit.verifyBiometricAsync(reason: "Siri 开锁前确认是你") else {
                return .result(dialog: "Face ID 未通过, 未定位门锁")   // 945 未通过
            }
        }
        if let miss = IntentLock.refusal(lockName) { return .result(dialog: IntentDialog(stringLiteral: miss)) }
        // 走到这里必定是唯一命中 (refusal 只对没命中的三种情形说话)，但 Swift 需要这里再取一次值。
        guard case .unique(let kc) = IntentLock.resolve(lockName) else { return .result(dialog: "锁名没认出来") }
        if kc.mac == DemoKit.demoMac {
            return .result(dialog: "「\(kc.name)」是演示锁, 请在 App 内连接真实门锁后开锁")
        }
        DB.currentMac = kc.mac
        IntentGovernance.audit(intent: "unlock", detail: kc.name)
        // foreground 语义: 定位到该锁, 最后一步由用户在 App 圆盘完成 (绝不后台开锁)
        return .result(dialog: "已定位「\(kc.name)」, 请在 App 内完成开锁")
    }
}

// ---------- 意图族门禁: 锁屏可达时不得产出凭证/PII ----------
// 设了本机密码 → 要求 App 已解锁 (hostRef 只在主界面挂载时存在, 冷启直调 Siri 一律拒 = fail-closed)。
// 未设本机密码 → 本就没有门禁可绕, 放行。
enum IntentLockGate {
    // 2026-10-13 run 63: 它读 AppState.hostRef 与 appUnlocked, 两者都在 @MainActor 的 AppState 上
    // ⇒ 标 @MainActor; 6 个调用点 (都在 async 的 perform() 里) 相应加 await。
    // 2026-10-13 对抗式排查: 补一道 390 伪装会话的拦截。伪装口令进来的会话**也是** appUnlocked==true
    // (空壳界面 + 锁已解开), 于是上面那句放行后, 对 Siri 说一句「生成临时码」就把实时 ZOTP 念出来并
    // 复制进剪贴板, MemberQuery/ReadRecords 同样吐成员档案与开门记录。
    // 390 行的原话: "伪装口令进来的会话只渲染空壳, 主 TabView 与其 .task 都不执行" —— 那时屏上的人是
    // 胁迫者的常态, 口令/PII 一条都不该出。
    @MainActor
    static func blockedMessage() -> String? {
        guard DB.hasPasscode() else { return nil }
        guard AppState.hostRef?.appUnlocked == true else { return "App 已锁定, 请先解锁离线锁管家" }
        guard AppState.hostRef?.decoyMode == false else {
            return "当前处于伪装会话, 已停用这条指令"   // 390 当前处于伪装会话
        }
        return nil
    }
}

// ---------- 947 临时码意图 (纯本地 ZOTP 生成, 零锁端交互) ----------
struct OtpIntent: AppIntent {
    static let title: LocalizedStringResource = "生成临时码"
    static let description = IntentDescription("离线生成当前时窗的临时密码, 无需连接门锁")

    @Parameter(title: "门锁") var lockName: String

    func perform() async throws -> some IntentResult {
        // 最高危的一条: 返回值就是**可用的开锁口令**, 会被 Siri 念出来。无门禁 = 锁屏绕过应用锁。
        if let block = await IntentLockGate.blockedMessage() { return .result(dialog: IntentDialog(stringLiteral: block)) }
        guard IntentGovernance.passCooldown(intent: "otp") else {
            IntentGovernance.audit(intent: "otp", detail: "\(lockName) 被冷却拦截")
            return .result(dialog: "刚生成过, 请稍候 60 秒再试")
        }
        let q = lockName.trimmingCharacters(in: .whitespaces)
        if let miss = IntentLock.refusal(q) { return .result(dialog: IntentDialog(stringLiteral: miss)) }
        guard case .unique(let kc) = IntentLock.resolve(q) else { return .result(dialog: "锁名没认出来") }
        if kc.mac == DemoKit.demoMac {
            return .result(dialog: "「\(kc.name)」是演示锁, 请在 App 内连接真实门锁后生成临时码")
        }
        guard !kc.skey.isEmpty else {
            return .result(dialog: "「\(kc.name)」尚未绑定密钥, 请先在 App 内配网")
        }
        // 周期须与锁端 zotpPeriod 对齐 (03#05, 单位**分钟**, 快照缺省回落 30; periodSec 名沿用 JS 基线)
        // 旧值 60 使时窗 60 分钟, 与锁端 30 分钟窗错位 → 生成的码锁端校验必失败
        let pRaw = DB.readStatus(kc.mac)?.zotpPeriod ?? 0    // 947: 读锁端快照, 无快照回落 30
        let period = pRaw > 0 ? pRaw : 30
        let code = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodSec: period, idx: 0)
        // 空串 = 这把锁的密钥或 MAC 形状过不了生成器 (上面只查了 skey 非空，长度不对同样算不出)。
        // 以前这里会照播「当前时窗临时码: 」+ 一个看不见的空值，并且把这一次**记成成功的 otp 审计** ——
        // 语音路径上没有屏幕，用户只会听到「念完了」，以为码是对的 (§10.44)。
        guard !code.isEmpty else {
            return .result(dialog: "「\(kc.name)」的密钥或 MAC 形状不对，生成不了临时码。请在 App 内打开该锁的临时码页查看提示。")
        }
        IntentGovernance.audit(intent: "otp", detail: kc.name)
        // 947: 顺手落剪贴板 (ClipboardCare 自清/留痕同一套); 30 分钟档标失效时刻, 其它档不猜
        await MainActor.run { ClipboardCare.copySecret(code, via: "意图·临时码") }   // 947 意图
        let winNote = period == 30 ? " (已复制, 于 \(ZOTP.nextWindow()) 失效)" : " (已复制)"
        // 回显用**解析到的那把锁**而不是用户说的那个词: 现在锁名允许"唯一包含命中"，
        // 若还照原样回显说出的词，说"主卧"却给了"客厅门锁"的码，用户听不出来 (审计也记的是真锁名)。
        return .result(dialog: "「\(kc.name)」当前时窗临时码: \(code)\(winNote)")
    }
}

// ---------- 946 状态问答 (协议无锁状态位, 只答可读字段: 电量/固件/锁钟) ----------
struct LockStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "门锁状态"
    static let description = IntentDescription("回答门锁电量、固件与锁钟 (离线可答, 需此前连过)")

    @Parameter(title: "门锁") var lockName: String

    func perform() async throws -> some IntentResult {
        if let block = await IntentLockGate.blockedMessage() { return .result(dialog: IntentDialog(stringLiteral: block)) }   // 电量/固件/锁钟同属本机数据
        guard IntentGovernance.passCooldown(intent: "status") else {
            IntentGovernance.audit(intent: "status", detail: "\(lockName) 被冷却拦截")
            return .result(dialog: "刚查过, 请稍候 60 秒再问")
        }
        let q = lockName.trimmingCharacters(in: .whitespaces)
        if let miss = IntentLock.refusal(q) { return .result(dialog: IntentDialog(stringLiteral: miss)) }
        guard case .unique(let kc) = IntentLock.resolve(q) else { return .result(dialog: "锁名没认出来") }
        var lines = ["「\(kc.name)」离线缓存:"]
        if let snap = DB.readStatus(kc.mac) {
            if snap.powerLevel >= 0 { lines.append("电量 \(snap.powerLevel)%") }
            if !snap.firmware.isEmpty { lines.append("固件 \(snap.firmware)") }
            if snap.lockTime > 0 { lines.append("锁钟 \(ProtoTime.localStr(snap.lockTime))") }
        } else {
            lines.append("尚无缓存读数 (从未连过或快照已清)")
        }
        lines.append("连上后可在 App 内刷新最新读数")
        IntentGovernance.audit(intent: "status", detail: kc.name)
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: "。")))
    }
}

// ---------- 950 导出 CSV 意图 (复用包12 ExportKit) ----------
struct ExportCsvIntent: AppIntent {
    static let title: LocalizedStringResource = "导出开门记录"
    /// 原句 (#950) 要的是"导出**指定月份**"，那一半从未落地；上一版描述写的"最近 30 天"
    /// 同样是空头承诺 —— `ExportKit.records` 导的是机内缓存的**全部**记录，没有任何时间窗
    /// (缓存按「重新读取拉最近 100 条」长大，跨度可以是几个月，说 30 天会让人以为拿到的是近一月)。
    /// 现在描述与对话框都报实际范围；要按月导只在 App 内的导出中心做 (那里才有月份口径)。
    static let description = IntentDescription("把门锁在本机的缓存开门记录导出为 CSV，范围是全部缓存、不含实时读取")

    @Parameter(title: "门锁", default: "全部") var lockName: String

    func perform() async throws -> some IntentResult {
        if let block = await IntentLockGate.blockedMessage() { return .result(dialog: IntentDialog(stringLiteral: block)) }   // 导出的是开门记录 (PII)
        guard IntentGovernance.passCooldown(intent: "export") else { return .result(dialog: "刚导出过, 请稍候 60 秒") }
        let macs: [String]
        // 原先的没命中分支是 `filter { … }.map { … } + ["(无匹配)"]` —— 把中文哨兵当 mac 传下去，
        // 于是"锁名说错了"与"这把锁没有记录"被压成同一句话 (暂无记录可导出)：
        // 用户会去翻一把确实没记录的锁，而不是重说一次锁名 (§10.37)。
        if lockName.trimmingCharacters(in: .whitespacesAndNewlines) == "全部" {
            macs = DB.keychains().map { $0.mac }
        } else {
            // 走同一把尺 (原先这半只认 `name ==`，不 trim 也不认型号名：说型号名导临时码可以、导 CSV 却说没有)
            let spoken = lockName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let miss = IntentLock.refusal(spoken) { return .result(dialog: IntentDialog(stringLiteral: miss)) }
            guard case .unique(let kc) = IntentLock.resolve(spoken) else { return .result(dialog: "锁名没认出来") }
            macs = [kc.mac]
        }
        var total = 0
        for mac in macs { total += ExportKit.records(mac: mac).count }
        if total == 0 { return .result(dialog: "暂无记录可导出") }
        IntentGovernance.audit(intent: "export", detail: "共 \(total) 行")
        return .result(dialog: "已备好 \(total) 行记录 (本机缓存的全部记录), 到「设置-系统集成-导出中心」可取走 CSV")
    }
}

// ---------- 955 成员查询 ----------
struct MemberQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "查成员"
    static let description = IntentDescription("查某位成员的本地档案")

    @Parameter(title: "成员名") var memberName: String

    func perform() async throws -> some IntentResult {
        if let block = await IntentLockGate.blockedMessage() { return .result(dialog: IntentDialog(stringLiteral: block)) }   // 成员档案属 PII
        guard IntentGovernance.passCooldown(intent: "member") else {
            IntentGovernance.audit(intent: "member", detail: "\(memberName) 被冷却拦截")
            return .result(dialog: "刚查过, 请稍候 60 秒再问")
        }
        let hit = DB.members().first { $0.name.hasPrefix(memberName) || $0.name.contains(memberName) }
        guard let hit else { return .result(dialog: "没有叫「\(memberName)」的成员") }
        // 955 今日门次: 与 604/612 同一套 Attribution 归属口径 ("约"级 —— 归属不出的不计数, 绝不猜)
        let memberId = hit.id
        let counts = await MainActor.run { StatsKit.memberTodayCounts(id: memberId) }
        let today = counts.isEmpty
            ? "今天暂无可证明归属的开门"
            : "今天开门约 " + counts.map { counts.count > 1 ? "「\($0.name)」\($0.n) 次" : "\($0.n) 次" }.joined(separator: "、")
        IntentGovernance.audit(intent: "member", detail: hit.name + " · " + today)
        return .result(dialog: "\(hit.name): 关系\(hit.relation.isEmpty ? "未填" : hit.relation), 备注 \(hit.phone.isEmpty ? "无" : hit.phone)。\(today)")
    }
}

// ---------- 956 语音读记录 (系统 TTS, 不引入资源) ----------
struct ReadRecordsIntent: AppIntent {
    static let title: LocalizedStringResource = "朗读最近开门"
    static let description = IntentDescription("用语音朗读最近 3 条开门记录")

    @Parameter(title: "门锁", default: "第一把") var lockName: String

    func perform() async throws -> some IntentResult {
        if let block = await IntentLockGate.blockedMessage() { return .result(dialog: IntentDialog(stringLiteral: block)) }   // 朗读内容含开门时刻
        guard IntentGovernance.passCooldown(intent: "read") else {
            IntentGovernance.audit(intent: "read", detail: "\(lockName) 被冷却拦截")
            return .result(dialog: "刚朗读过, 请稍候 60 秒再试")
        }
        // 原来是 `DB.keychains().first { $0.name == lockName } ?? DB.keychains().first`：
        // 锁名说错 (或对不上) 时**静默改用第一把锁**，把另一把锁的记录念给用户听，听起来却像他说的那把。
        // 现在只有"没指名"(参数默认档) 才落到第一把，并且把锁名念出来；说了名字就必须对上 (§10.37)。
        let ks = DB.keychains()
        guard let first = ks.first else { return .result(dialog: "还没有添加门锁") }
        let spoken = lockName.trimmingCharacters(in: .whitespacesAndNewlines)
        let kc: Keychain
        if spoken.isEmpty || spoken == "第一把" {
            kc = first
        } else {
            if let miss = IntentLock.refusal(spoken) { return .result(dialog: IntentDialog(stringLiteral: miss)) }
            guard case .unique(let hit) = IntentLock.resolve(spoken) else { return .result(dialog: "锁名没认出来") }
            kc = hit
        }
        let recs = Array(ExportKit.records(mac: kc.mac).prefix(3))
        guard !recs.isEmpty else { return .result(dialog: "「\(kc.name)」暂无记录可朗读") }
        let text = recs.enumerated().map { idx, r in
            "\(idx + 1), \(r.time.isEmpty ? "时间未知" : r.time) \(r.isAlarm ? "异常" : "正常")"
        }.joined(separator: "。")
        IntentGovernance.audit(intent: "read", detail: "\(kc.name) · \(recs.count) 条")
        Speech.zh("「\(kc.name)」最近开门记录。" + text)     // 朗读只走 Speech 这一个出口 (原先这里另 new 了一台 synthesizer)
        return .result(dialog: "已朗读「\(kc.name)」的 \(recs.count) 条记录")
    }
}

// ---------- 26/295/948 Siri 口令与快捷指令画廊数据 (166: 参数名中文口语化) ----------
struct ShortcutGallery: Identifiable {
    let id: String
    let intent: String
    let phrase: String
    let note: String
}

enum AppShortcuts {
    /// 948 示例指令包: 可注册的口令清单; 942 时刻建议
    // 948: 画廊文案是给人看的示例口令, 不是运行时插值 —— 原先此处写了 `\(锁名)`/`\(成员名)`,
    // 这两个名字在 Swift 里是真实求值的标识符而全仓没有任何声明, 等于编译阻断 (cannot find '锁名' in scope);
    // 现在改为静态占位文案, 语义不变: 说的时候把 [你的锁名]/[成员名] 换成真名。
    static let phrases: [ShortcutGallery] = [
        .init(id: "unlock", intent: "UnlockIntent", phrase: "打开 [你的锁名]", note: "定位门锁, 在 App 内完成最后一步"),
        .init(id: "otp", intent: "OtpIntent", phrase: "给 [你的锁名] 生成临时码", note: "纯本地生成当前时窗码"),
        .init(id: "status", intent: "LockStatusIntent", phrase: "[你的锁名] 现在电量多少", note: "答离线缓存读数"),
        .init(id: "export", intent: "ExportCsvIntent", phrase: "把 [你的锁名] 最近记录导出", note: "生成 CSV 备取"),
        .init(id: "member", intent: "MemberQueryIntent", phrase: "查一下 [成员名]", note: "成员档案速览"),
        .init(id: "read", intent: "ReadRecordsIntent", phrase: "读最近谁开了门", note: "语音播报 3 条记录"),
        .init(id: "at8", intent: "LockStatusIntent", phrase: "早上 8 点查一次门锁", note: "时刻建议不做: 无 App Groups, 系统读不到本机数据, 可在「快捷指令」App 里手动定一个 8 点自动化"),   // 942 时刻建议
    ]
}

// ---------- 166 AppShortcutsProvider — 口令注册的正身 (前六个真能执行的意图在此向系统提供 App Shortcut 出口) ----------
// 166: 口令注册的正身 —— 上面 :73-:266 的六个意图定义在此经 AppShortcutsProvider 交给系统, 装完 App 后系统据此自动收录口令;
// 这一节把 UnlockIntent/OtpIntent/LockStatusIntent/ExportCsvIntent/MemberQueryIntent/ReadRecordsIntent
// 逐条注册为 AppShortcut。画廊第 7 条 at8 (定时查锁) 保持只出现在画廊 —— 定时触发由系统「快捷指令」App
// 的自动化承担, 意图本体 (LockStatusIntent) 已在上面注册, 用户在自动化里选它即可。
// 参数形状: 六条意图各自带 @Parameter (:81/:135/:179/:213/:244/:270)。其中 ExportCsv(默认「全部」)与
// ReadRecords(默认「第一把」)缺参时按声明默认档执行, 其余缺参时由 IntentLock/提示语引导用户补说锁名;
// 注册采用「不带 AppShortcutParameter」的最小形状, 口令里不带槽位, 用户说的时候带上锁名 (画廊一节顶部已写明)。
// ⚠ API-VERIFY: AppShortcutsProvider / @AppShortcutsBuilder / AppShortcut(intent:phrases:shortTitle:systemImageName:)
//   为 Apple 文档 iOS 16+ 标准形状, 全仓无先例可抄, 未编译、未证实。
// ⚠ API-VERIFY: AppShortcutParameter 的值类型需走 IntentValueQuery 供默认值, 本仓没有可照抄的先例、文档形状
//   未逐字核对, 故未纳入本轮注册 (想核实时先看本行), 未编译、未证实。
// ⚠ API-VERIFY: phrases 要求**含 App 名占位** —— 2026-10-13 run 72 由 appintentsmetadataprocessor 报
//   "Invalid Utterance. Every App Shortcut utterance should have one '${applicationName}' in it."
//   (注意: 这条不是 Swift 编译错误, 是编译**之后**的元数据导出步骤拦的 —— 编译器那一关已经过了)。
//   修法: 把写死的中文 App 名换成 Swift 侧模板 `\(.applicationName)` (系统按 CFBundleDisplayName 渲染),
//   而不是静态字面量「离线锁管家」。真机上口令是否被系统收录仍需实机核。
struct LockKeeperShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // 166 注册 UnlockIntent (:73); shortTitle 沿用意图 title; 图标抄本仓已有 SF Symbol: Widget/LockWidget.swift:52
        AppShortcut(
            intent: UnlockIntent(),
            phrases: ["用\(.applicationName)打开门锁", "\(.applicationName)定位门锁"],
            shortTitle: "打开门锁",
            systemImageName: "lock.open"
        )
        // 166 注册 OtpIntent (:131); 图标抄 App/UI/AlarmCenterView.swift:564
        AppShortcut(
            intent: OtpIntent(),
            phrases: ["用\(.applicationName)生成临时码", "\(.applicationName)临时码"],
            shortTitle: "生成临时码",
            systemImageName: "key.zarrowpath"
        )
        // 166 注册 LockStatusIntent (:175); 图标抄 App/UI/DeviceHomeView.swift:624 (状态问答主力字段是电量)
        AppShortcut(
            intent: LockStatusIntent(),
            phrases: ["用\(.applicationName)查门锁状态", "\(.applicationName)查电量"],
            shortTitle: "门锁状态",
            systemImageName: "battery.25percent"
        )
        // 166 注册 ExportCsvIntent (:205); 图标抄 App/LockKeeperApp.swift:1021
        AppShortcut(
            intent: ExportCsvIntent(),
            phrases: ["用\(.applicationName)导出开门记录", "\(.applicationName)导出记录"],
            shortTitle: "导出开门记录",
            systemImageName: "doc.on.clipboard"
        )
        // 166 注册 MemberQueryIntent (:240); 图标抄 App/UI/CredentialsView.swift:418
        AppShortcut(
            intent: MemberQueryIntent(),
            phrases: ["用\(.applicationName)查成员", "\(.applicationName)成员档案"],
            shortTitle: "查成员",
            systemImageName: "person.2"
        )
        // 166 注册 ReadRecordsIntent (:266); 图标抄 App/UI/LockOverviewView.swift:65 (朗读的是记录文本)
        AppShortcut(
            intent: ReadRecordsIntent(),
            phrases: ["用\(.applicationName)朗读最近开门", "\(.applicationName)读记录"],
            shortTitle: "朗读最近开门",
            systemImageName: "text.quote"
        )
    }
}

// ---------- 集成中心页: 快捷指令画廊 + 入口 + 治理 (包17 UI 落点) ----------
struct IntegrationCenterView: View {
    var body: some View {
        List {
            Section("快捷指令 · 说一句就行 (全部 foreground, 不后台开锁)") {
                // 166: 节顶说明与 LockKeeperShortcuts 注册同源同行 —— 口令收录由系统在装完 App 后自动完成,
                // 收录结果归系统侧判定、App 接口不回读, 所以本节文案落在「出口已提供」这一事实上;
                // 带锁名的说法同时写清 (意图参数靠说的话带上, 见 IntentLock.refusal 的引导语)。
                Text("这 6 条意图已在本版提供出口 (AppShortcutsProvider 注册, 166), 口令由系统在装完 App 后自动收录; 收录结果只有系统知道, App 读不回来, 所以这里呈现的是「出口已提供」这一事实。说的时候请带上真名, 把方括号占位换成您的锁名/成员名 (如「打开 主卧门锁」); 第 7 条「早上 8 点查一次门锁」属定时自动化, 请在系统「快捷指令」App 的自动化里设置, 动作选本 App 的「门锁状态」意图即可。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(AppShortcuts.phrases) { p in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "command")
                                .font(.system(size: DS.Icon.xs, weight: .semibold))
                                .foregroundStyle(DS.Palette.accentText)
                            Text("说「\(p.phrase)」")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        Text(p.note)
                            .font(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(2)
                    }
                    .padding(.vertical, DS.Space.xs)
                    .frame(minHeight: DS.Hit.min, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
            }

            Section("快捷入口") {
                LabeledRow("主屏 / 锁屏小组件", "927 哑按钮 (拍板 #30): 「开锁入口」组件只做一件事 —— 经 kf://device 把 App 打到设备页。不显示锁状态与电量 (免费账号无 App Groups，组件读不到本机数据)，也不在组件里开锁")
                LabeledRow("控制中心深链", "937/938 仍不提供: Widget target 已建，缺的是控制中心控件那条写法本身 —— 未编译、未真机核过，不硬接")
                LabeledRow("本地深链", "kf:// 路由: 支持 device / credentials / records / settings 四个入口, 其余地址一律忽略; 锁屏状态下先挂起, 解锁后才跳转。小组件走的也是 device 这一条")   // 294 路由
                // 293/951 这一行此前是全仓唯一"Spotlight"证据, 而索引写入方根本不存在 (无 CoreSpotlight import)。
                // 现在写入方在 App/Core/SpotlightKit.swift, 措辞按**真做了的范围**改: 索引的是锁名与凭证条目,
                // 成员名没有可落地的详情页入口因此不索引 —— 写上就是"搜得到、点不开"。
                LabeledRow("Spotlight", "锁名 + 凭证条目 (密码备注、指纹批次名) 已写入系统搜索。点结果落到设备页那把锁或凭证页那条详情; 应用锁还锁着时先挂起, 解锁后才跳转 (与深链同一个门禁)。成员名本版不索引: 成员详情没有可供系统搜索直达的入口, 挂进去只会搜到点不开。")   // 293/951 锁名
                // 55 轻点背面 (2026-10-10 拍板: 做"分步指引"那一半)。绑定动作在系统设置里，App 无法代按，
                // 所以这一行只说明"意图可以被系统挂到轻点背面"，界面不得写成"已绑定"。
                LabeledRow("动作按钮 / 轻点背面", "分步指引: ① 打开「快捷指令」App, 新建一条调用本 App「打开锁名」开锁意图的动作 ② 系统设置-辅助功能-触控-轻点背面, 选「轻点两下」 ③ 在动作列表里选刚建的那条 ④ 完成后轻点背面两下只会把 App 打到设备页, 最后一步仍在 App 圆盘上按住确认。绑定动作在系统设置里做, App 无法代按, 界面也不显示成已绑定")   // 55 动作按钮
            }

            Section("NFC 标签 (待实测)") {
                // 这一节原来是两处谎报: `kf_nfc_tags` 全仓**零写入方** (没有任何登记/写卡入口)，
                // getInt 恒回 0，却显示成"已登记标签 0 张" —— 拿缺省值冒充业务数据；
                // 而"点此探测"并没有可点的按钮。缺的东西就写缺，别留一个看起来在工作的形状。
                Text("957-963: 写卡需 CoreNFC capability, 免费账号下不确定可用；协议侧也没有 NFC 凭证管理命令 (CAPABILITY §5)。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledRow("登记与写卡入口", "尚无 — 先实测 CoreNFC 可用，再生成写卡数据")
                LabeledRow("能力探测", "未探测 — 需侧载后在真机上进行 (本项是待办, 不是已具备的能力)")
            }

            Section("Apple Watch 伴侣 (路线图)") {
                Text("965-974: 独立 target 且共享每周重签负担, 暂不随版提供。计划: 状态表盘 + 表端触发开锁 (后台 BLE 受限需真机实测)。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("主屏图标教程") {   // 954 主屏图标教程
                Text("把开锁意图放上主屏: ① 打开「快捷指令」App → 新建快捷指令 → 添加动作 → 搜「离线锁管家」→ 选「打开门锁」 ② 动作里填好锁名与暗语 ③ 长按该快捷指令卡片 →「添加到主屏」。点图标即触发开锁意图——仍只定位门锁, 最后一步在 App 圆盘按住确认, 不后台开锁。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                Text("App 图标换肤仍在设置-外观 (长按主屏图标 →「编辑 App 图标」)。包16 那四款之外, 896 又补了五款位图 (家门/警报/定位/门盾/心记), 现在一共九款可选; 四季自动对齐仍只认原来那四款, 选新五款不会被系统悄悄换掉。")   // 897 图标换肤仍在设置
                    .font(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("治理") {
                LabeledRow("意图冷却", "同一意图 60 秒 —— 六条意图各记各的键, 互不顶替")   // 952 同一意图
                LabeledRow("意图审计", "每次执行记入「设置-安全-审计流水」的独立分区「快捷指令执行」")   // 953/964 每次执行记入
                LabeledRow("睡眠焦点", "不提供: 意图执行不判定焦点状态, 也不申请 FocusKit 授权")   // 949 界面文案
            }
        }
        .dsScreenBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle("系统集成")
    }
}
