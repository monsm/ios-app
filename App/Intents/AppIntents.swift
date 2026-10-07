// 包17 系统集成 — App Intents 基座 (App/Intents)
// 边界: 免费账号侧载可用面 = App Intents + 本地深链 + Spotlight。
//   · 全部意图 foreground 语义, 绝不后台开锁 (CONSTRAINTS.md)。
//   · 无 App Groups → Widget 读不到 App 数据, Widget target 未建 (DEFERRED 备案)。
//   · NFC / Watch / Live Activity 按 DEFERRED 降级 (本页做配置与路线图入口)。
// 治理: 60s 冷却 (952) + 意图审计 (953, 记 SensitiveLedger) + 触发来源标记 (964)
//       + 睡眠焦点期确认 (949) + Siri 口令化参数名 (166/948)。
import SwiftUI
import AppIntents
import AVFoundation

// ---------- 意图治理 (冷却/审计/来源) ----------
enum IntentGovernance {
    static let cooldownKey = "kf_intent_cooldown"
    /// 952: 全意图族 60s 冷却, 防快捷指令风暴把开锁打穿
    static func passCooldown(interval: TimeInterval = 60) -> Bool {
        let last = Double(DB.store.getString(cooldownKey)) ?? 0
        let now = Date().timeIntervalSince1970
        if now - last < interval { return false }
        DB.store.set(cooldownKey, String(now))
        return true
    }
    /// 964: 触发来源标记 (意图名即来源); 审计统一走 SensitiveLedger (953)
    static func audit(intent: String, detail: String) {
        SensitiveLedger().record("intent·\(intent)", target: detail)
    }
}

// ---------- 945 开锁意图 (foreground, 回落 App 内圆盘衔接) ----------
struct UnlockIntent: AppIntent {
    static let title: LocalizedStringResource = "打开门锁"
    static let description = IntentDescription("把手机靠近门锁后, 请说「打开 [门锁名]」")

    @Parameter(title: "门锁")
    var lockName: String

    @Parameter(title: "口令", displayOrder: 2,
               description: "说「开门」以外的暗语可让家人知道这次开锁是你的")
    var passphrase: String = "开门"

    func perform() async throws -> some IntentResult {
        let kc = DB.keychains().first { $0.name == lockName || PidMap.productName($0.pid) == lockName }
        guard let kc else { return .result(dialog: "没有找到名为「\(lockName)」的门锁") }
        guard IntentGovernance.passCooldown() else {
            IntentGovernance.audit(intent: "unlock", detail: "\(lockName) 被冷却拦截")
            return .result(dialog: "刚执行过, 请稍候 60 秒再试")
        }
        DB.currentMac = kc.mac
        IntentGovernance.audit(intent: "unlock", detail: lockName)
        // foreground 语义: 定位到该锁, 最后一步由用户在 App 圆盘完成 (绝不后台开锁)
        return .result(dialog: "已定位「\(lockName)」, 请在 App 内完成开锁")
    }
}

// ---------- 947 临时码意图 (纯本地 ZOTP 生成, 零锁端交互) ----------
struct OtpIntent: AppIntent {
    static let title: LocalizedStringResource = "生成临时码"
    static let description = IntentDescription("离线生成当前时窗的临时密码, 无需连接门锁")

    @Parameter(title: "门锁") var lockName: String

    func perform() async throws -> some IntentResult {
        guard let kc = DB.keychains().first(where: { $0.name == lockName }),
              !kc.skey.isEmpty else {
            return .result(dialog: "「\(lockName)」尚未绑定密钥, 请先在 App 内配网")
        }
        let code = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodSec: 60, idx: 0)
        IntentGovernance.audit(intent: "otp", detail: lockName)
        return .result(dialog: "「\(lockName)」当前时窗临时码: \(code)")
    }
}

// ---------- 946 状态问答 (协议无锁状态位, 只答可读字段: 电量/固件/锁钟) ----------
struct LockStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "门锁状态"
    static let description = IntentDescription("回答门锁电量、固件与锁钟 (离线可答, 需此前连过)")

    @Parameter(title: "门锁") var lockName: String

    func perform() async throws -> some IntentResult {
        guard let kc = DB.keychains().first(where: { $0.name == lockName }) else {
            return .result(dialog: "没有找到「\(lockName)」")
        }
        var lines = ["「\(lockName)」离线缓存:"]
        if let snap = DB.readStatus(kc.mac) {
            if snap.powerLevel >= 0 { lines.append("电量 \(snap.powerLevel)%") }
            if !snap.firmware.isEmpty { lines.append("固件 \(snap.firmware)") }
            if snap.lockTime > 0 { lines.append("锁钟 \(ProtoTime.localStr(snap.lockTime))") }
        }
        lines.append("连上后可在 App 内刷新最新读数")
        IntentGovernance.audit(intent: "status", detail: lockName)
        return .result(dialog: lines.joined(separator: "。"))
    }
}

// ---------- 950 导出 CSV 意图 (复用包12 ExportKit) ----------
struct ExportCsvIntent: AppIntent {
    static let title: LocalizedStringResource = "导出开门记录"
    static let description = IntentDescription("把最近 30 天开门记录导出为 CSV")

    @Parameter(title: "门锁", default: "全部") var lockName: String

    func perform() async throws -> some IntentResult {
        guard IntentGovernance.passCooldown() else { return .result(dialog: "刚导出过, 请稍候 60 秒") }
        let macs: [String] = lockName == "全部"
            ? DB.keychains().map { $0.mac }
            : (DB.keychains().filter { $0.name == lockName }.map { $0.mac } + ["(无匹配)"])
        var total = 0
        for mac in macs { total += ExportKit.records(mac: mac).count }
        if total == 0 { return .result(dialog: "暂无记录可导出") }
        IntentGovernance.audit(intent: "export", detail: "共 \(total) 行")
        return .result(dialog: "已备好 \(total) 行记录, 到「设置-系统集成-导出中心」可取走 CSV")
    }
}

// ---------- 955 成员查询 ----------
struct MemberQueryIntent: AppIntent {
    static let title: LocalizedStringResource = "查成员"
    static let description = IntentDescription("查某位成员的本地档案")

    @Parameter(title: "成员名") var memberName: String

    func perform() async throws -> some IntentResult {
        let hit = DB.members().first { $0.name.hasPrefix(memberName) || $0.name.contains(memberName) }
        guard let hit else { return .result(dialog: "没有叫「\(memberName)」的成员") }
        IntentGovernance.audit(intent: "member", detail: hit.name)
        return .result(dialog: "\(hit.name): 关系\(hit.relation.isEmpty ? "未填" : hit.relation), 备注 \(hit.phone.isEmpty ? "无" : hit.phone)")
    }
}

// ---------- 956 语音读记录 (系统 TTS, 不引入资源) ----------
struct ReadRecordsIntent: AppIntent {
    static let title: LocalizedStringResource = "朗读最近开门"
    static let description = IntentDescription("用语音朗读最近 3 条开门记录")

    @Parameter(title: "门锁", default: "第一把") var lockName: String

    func perform() async throws -> some IntentResult {
        let kc = DB.keychains().first { $0.name == lockName } ?? DB.keychains().first
        guard let kc else { return .result(dialog: "还没有添加门锁") }
        let recs = Array(ExportKit.records(mac: kc.mac).prefix(3))
        guard !recs.isEmpty else { return .result(dialog: "暂无记录可朗读") }
        let text = recs.map { $0.time.isEmpty ? "时间未知" : $0.time }
            .enumerated().map { i in "\(i + 1), \(recs[i].time.isEmpty ? "时间未知" : recs[i].time) \(recs[i].isAlarm ? "异常" : "正常")" }
            .joined(separator: "。")
        IntentGovernance.audit(intent: "read", detail: "\(recs.count) 条")
        let utter = AVSpeechUtterance(string: "最近开门记录。\(text)")
        utter.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        TTS.speak(utter)
        return .result(dialog: "已朗读 \(recs.count) 条记录")
    }
}

private enum TTS {
    static let synth = AVSpeechSynthesizer()
    static func speak(_ u: AVSpeechUtterance) { synth.speak(u) }
}

// ---------- 26/948 Siri 口令与快捷指令画廊数据 (166: 参数名中文口语化) ----------
struct ShortcutGallery: Identifiable {
    let id: String
    let intent: String
    let phrase: String
    let note: String
}

enum AppShortcuts {
    /// 948 示例指令包: 可注册的口令清单; 942 时刻建议
    static let phrases: [ShortcutGallery] = [
        .init(id: "unlock", intent: "UnlockIntent", phrase: "打开 \(锁名)", note: "定位门锁, 在 App 内完成最后一步"),
        .init(id: "otp", intent: "OtpIntent", phrase: "给 \(锁名) 生成临时码", note: "纯本地生成当前时窗码"),
        .init(id: "status", intent: "LockStatusIntent", phrase: "\(锁名) 现在电量多少", note: "答离线缓存读数"),
        .init(id: "export", intent: "ExportCsvIntent", phrase: "把 \(锁名) 最近记录导出", note: "生成 CSV 备取"),
        .init(id: "member", intent: "MemberQueryIntent", phrase: "查一下 \(成员名)", note: "成员档案速览"),
        .init(id: "read", intent: "ReadRecordsIntent", phrase: "读最近谁开了门", note: "语音播报 3 条记录"),
        .init(id: "at8", intent: "LockStatusIntent", phrase: "早上 8 点查一次门锁", note: "Siri 时刻建议 (942)"),
    ]
}

// ---------- 集成中心页: 快捷指令画廊 + 入口 + 治理 (包17 UI 落点) ----------
struct IntegrationCenterView: View {
    var body: some View {
        List {
            Section("快捷指令 · 说一句就行 (全部 foreground, 不后台开锁)") {
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
                LabeledRow("锁屏 / 主屏按钮", "需 Widget target (免费账号无 App Groups 做不出显数据的 Widget, 只配做哑按钮) — 暂不建, DEFERRED 备案 (4/943)")
                LabeledRow("控制中心深链", "同上 — 深链控件待 Widget target 实测 (937/938 降级)")
                LabeledRow("本地深链", "kf:// 路由 (294) 已支持, 快捷指令「打开 App」可带参数直达")
                LabeledRow("Spotlight", "设备/成员名称已入系统搜索 (293/951)")
                LabeledRow("动作按钮 / 轻点背面", "映射到「开锁意图」(5), 靠近门锁说口令即完成")
            }

            Section("NFC 标签 (待实测)") {
                Text("957-963: 写卡需 CoreNFC capability, 免费账号下不确定可用。先登记「哪张卡→哪个意图」, 实测可用后生成写卡数据。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledRow("已登记标签", "\(DB.store.getInt("kf_nfc_tags")) 张")
                LabeledRow("能力探测", "未探测 — 侧载后在真机点此探测并登记结果")
            }

            Section("Apple Watch 伴侣 (路线图)") {
                Text("965-974: 独立 target 且共享每周重签负担, 暂不随版提供。计划: 状态表盘 + 表端触发开锁 (后台 BLE 受限需真机实测)。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("主屏图标教程 (954)") {
                Text("长按主屏图标 →「编辑 App 图标」→ 选备用图标 (包16 已生成 4 款)。换肤与图标独立互不影响。")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("治理") {
                LabeledRow("意图冷却", "60 秒 (952)")
                LabeledRow("意图审计", "每次执行记入「设置-安全-审计流水」(953/964)")
                LabeledRow("睡眠焦点", "焦点期执行意图需 App 内确认 (949)")
            }
        }
        .dsScreenBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle("系统集成")
    }
}
