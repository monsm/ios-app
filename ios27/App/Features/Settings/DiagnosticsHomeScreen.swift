// DiagnosticsHomeScreen.swift —— 诊断（V8 设计语言 · 02 分册 IA 归并后的宿主页）
//
// 本页是 §3.5 P5 归并的宿主：开发者 / 诊断项沉到这一页，不出现在普通用户的浏览路径上。吸收的段与来源：
//   ·「协议测试」段（← protocolTest / ProtocolTestHomeScreen）：附近设备扫描（8 秒窗口）、
//     回声探测（免令牌、不改锁、不写台账）、结果单槽、边界说明。
//   ·「God 模式」段（← godMode / GodModeHomeScreen）：锁身份（密钥只显示指纹）、锁端全量实时读数、
//     凭证台账对账、锁端凭证变更流水、修池（唯一写动作，二次确认）、录屏遮挡。
// 能力守恒：BLEService.scanWindow / ZKProtocol.parseAdv / lockMac / PidMap.productNames、LockService.probeEcho、
// app.lockLink.getStatus / getLogs / repairPool、DB.readStatus / listPwds / listFps、DiagSnapshot.fingerprint /
// ekeyPinMasked 全部逐条搬入；判定语义与文案因果原样保留。
//
// 与旧页的刻意差异：
//   ① 协议测试段只说人话，协议返回码不上屏（rc= 改为「回声一致 / 不匹配 / 回帧异常」）。
//   ② God 模式段在空壳模式下不渲染任何档案字段（app.currentKeychain 在空壳下仍返回真锁）。
//   ③ 只读试验模式：协议测试段可用（回声在放行表），修池禁用并说明。
import SwiftUI

struct DiagnosticsHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var judgement: String {
        if decoyed { return "空壳模式下不显示诊断读数" }
        return "协议测试 · God 模式"
    }

    private var lead: String {
        if decoyed { return "空壳模式只隐藏数据，不改动数据。这一页不显示锁端读数，也不提供探测与修池。" }
        return "只读为主：附近设备扫描与回声探测不改锁内任何东西；唯一的写动作是 God 模式段里的「修池」，会二次确认。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if decoyed {
                godDecoyCard
            } else {
                protocolSection
                godSection
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .captureShield("这里是锁端全量读数与凭证台账\n屏幕正在被录制或截图，已遮挡")
    }

    // MARK: - 段 1 协议测试（← protocolTest）

    private var protocolSection: some View {
        VStack(alignment: .leading, spacing: V8.S.gapCard) {
            scanCard
            if devices.isEmpty {
                VEmpty(
                    title: "没有扫到设备",
                    reason: "确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。扫描只读广播，不连接、不发命令。",
                    actionTitle: "重新扫描"
                ) { Task { await scan() } }
            } else {
                listCard
            }
            noteCard
            errorCard
        }
    }

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let pid: Int
        let mac: String
        let rssi: Int
        let dfu: Bool
    }

    @State private var devices: [Candidate] = []
    @State private var scanning = false
    @State private var probing: String?
    @State private var result: String?
    @State private var resultDevice: String?
    @State private var error: String?

    // MARK: - 扫描

    private var scanCard: some View {
        VCard2 {
            // 2026-11-05（对抗审查 · 设计冗余）：卡头 trailing 原来也报「N 台」，
            // 而紧邻的「扫描结果」卡标题就是「N 台按信号排序」—— 同一个数字挨着出现两次。
            // 数量由结果卡承载，扫描卡只说扫描本身的状态。
            VCardHead(eyebrow: "附近设备", statement: scanning ? "正在扫描 8 秒" : "扫描窗口 8 秒")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if scanning {
                VBusy(text: "正在扫描 8 秒 · 把要测的设备放在手机旁")
                    .padding(.top, V8.S.gapM)
            } else {
                Button { Task { await scan() } } label: {
                    Text("重新扫描")
                        .font(V8.T.tab)
                        .foregroundStyle(V8.C.chipOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: V8.H.min)
                        .background(Capsule(style: .continuous).fill(V8.C.accent))
                }
                .buttonStyle(.plain)
                .padding(.top, V8.S.gapM)
            }
            Text("门锁被连上后会停止广播；先断开再扫。扫描只读广播，不连接、不发命令。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    // MARK: - 扫描结果

    private var listCard: some View {
        VCard2 {
            VCardHead(eyebrow: "扫描结果", statement: devices.isEmpty ? "还没有设备" : "\(devices.count) 台按信号排序")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if devices.isEmpty {
                Text("没有扫到设备。确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(devices.enumerated()), id: \.element.id) { pair in
                        if pair.offset > 0 {
                            VDotRule()
                                .padding(.vertical, V8.S.gapS)
                        }
                        deviceBlock(pair.element)
                    }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    private func deviceBlock(_ d: Candidate) -> some View {
        VStack(alignment: .leading, spacing: V8.S.gapXS) {
            HStack(alignment: .firstTextBaseline, spacing: V8.S.gapS) {
                Text(d.name)
                    .font(V8.T.value)
                    .foregroundStyle(V8.C.ink1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(d.rssi) dBm")
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                    .monospacedDigit()
            }
            Text("pid \(d.pid) · \(d.mac.isEmpty ? "无 MAC" : d.mac)\(d.dfu ? " · DFU" : "")")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .fixedSize(horizontal: false, vertical: true)
            Button { probe(d) } label: {
                Text(probing == d.id ? "探测中…" : "发送回声探测")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .padding(.horizontal, V8.S.gapL)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(probing == d.id ? V8.C.chipOff : V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(probing != nil)
            .padding(.top, V8.S.gapXS)
            if let result, resultDevice == d.id, probing == nil {
                Text(result)
                    .font(V8.T.footnote)
                    .foregroundStyle(result.hasPrefix("回声一致") ? V8.C.ok : V8.C.danger)
                    .padding(.top, V8.S.gapXS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: V8.H.min)
    }
    // MARK: - 边界

    private var noteCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "边界", statement: "这一页只读")
            Text("回声探测不需要令牌、不改锁内任何东西、不写本机台账 —— 对还没配对的设备也发得出去。本页不提供任何写命令（配对 / 改密 / 删指纹等都不在）。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("只读试验模式下这一页仍然可用：回声探测本来就属于放行的只读操作。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 失败态

    @ViewBuilder
    private var errorCard: some View {
        if let error {
            VFailure(
                what: "扫描没有完成",
                why: error,
                next: "确认蓝牙已开、设备在广播；门锁被连上后会停止广播，先断开再扫。"
            ) { Task { await scan() } }
        }
    }

    @MainActor
    private func scan() async {
        guard !scanning else { return }
        scanning = true
        error = nil
        devices = []
        do {
            // 扫满 8 秒窗口再取快照（旧实现 startScan 后立刻读，列表恒空）。
            let found = try await BLEService.shared.scanWindow(allowDuplicates: true, timeoutMs: 8000)
            var out: [Candidate] = []
            for d in found {
                guard let adv = ZKProtocol.parseAdv(d.advertisHex) else { continue }
                let mac = ZKProtocol.lockMac(fromAdv: adv) ?? ""
                out.append(Candidate(id: d.deviceId,
                                     name: d.name.isEmpty ? (PidMap.productNames[adv.pid] ?? "未知设备") : d.name,
                                     pid: adv.pid, mac: mac, rssi: d.rssi, dfu: adv.dfuState != 0))
            }
            devices = out.sorted { $0.rssi > $1.rssi }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        scanning = false
    }

    @MainActor
    private func probe(_ d: Candidate) {
        guard probing == nil else { return }
        probing = d.id
        result = nil
        resultDevice = nil
        Task { @MainActor in
            do {
                let r = try await LockService.shared.probeEcho(deviceId: d.id)
                result = r.matched
                    ? "回声一致 · \(r.ms) ms"
                    : (r.ok ? "回声不匹配 · \(r.ms) ms" : "设备回帧异常 · \(r.ms) ms")
            } catch {
                result = "探测失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            resultDevice = d.id
            probing = nil
        }
    }

    @State private var status: StatusSnapshotData?
    @State private var busy = false
    @State private var errorText: String?
    @State private var outcome: String?
    @State private var askRepair = false
    @State private var logs: [LogEntry] = []

    private var mac: String { app.currentMac }
    private var kc: Keychain? { app.currentKeychain }

    // MARK: - 芯片行

    private var godChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                VChip2(icon: .ring(status.map { $0.powerLevel >= 0 ? Double($0.powerLevel) / 100 : 0.02 } ?? 0.02,
                                   status == nil ? V8.C.ink4 : ((status?.powerLevel ?? -1) < 20 ? V8.C.warn : V8.C.ok)),
                       label: "电量", value: status.map { $0.powerLevel >= 0 ? "\($0.powerLevel)%" : "未读到" } ?? "未读到")
                VChip2(icon: .glyph("key"), label: "PIN 池",
                       value: kc.map { "\($0.pins.filter { !$0.isEmpty }.count) 枚" } ?? "—")
                VChip2(icon: .glyph("lock.doc"), label: "凭证变更", value: "\(logs.count) 条")
                VChip2(icon: .glyph("shield"), label: "模式", value: readOnly ? "只读试验" : "可写")
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }


    // MARK: - 段 2 God 模式（← godMode）

    private var godSection: some View {
        VStack(alignment: .leading, spacing: V8.S.gapCard) {
            godChipRow
            if kc == nil {
                VEmpty(
                    title: "没有已配对的锁",
                    reason: "这一段读的是锁端全量状态与凭证台账。先在「门」页添加门锁，或从备份恢复。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else if let kc {
                if let errorText {
                    VFailure(
                        what: "读数没有拿全",
                        why: errorText,
                        next: "走近门锁、确认蓝牙开着，再点下面的「重新读取」。已读到的部分仍显示在下面。"
                    ) { Task { await refresh() } }
                }
                identityCard(kc)
                statusCard(kc)
                ledgerCard(kc)
                if !logs.isEmpty {
                    changeLogCard
                }
                repairCard(kc)
                outcomeCard
            }
        }
        .task { await refresh() }
        .v8Confirm(
            isPresented: $askRepair,
            title: "重写这把锁的 PIN 表？",
            consequence: "把锁内 PIN 表整体重置为新的 64 枚，通信密钥保持不变 —— 别人手机里的钥匙不会因换钥变砖。但锁内已有的旧 PIN（含别的手机钥匙）会全部失效，且这个动作不能撤销。靠近门锁再执行。",
            confirmTitle: "重写 PIN 表（保留通信密钥）",
            isDestructive: true
        ) {
            Task { await repair() }
        }
    }
    // MARK: - 锁身份（本机侧）

    private func identityCard(_ kc: Keychain) -> some View {
        VCard2 {
            VCardHead(eyebrow: "锁身份", statement: LockArchive.displayName(kc))
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: DB.normalizeMac(kc.mac), value: "")
                VDotRule()
                VDataRow(tag: "配对", tagTint: V8.C.ink4, title: DF.localMinute(fromISO: kc.pairedAt), value: "")
                VDotRule()
                VDataRow(tag: "skey", tagTint: V8.C.ink4, title: "通信密钥指纹", value: DiagSnapshot.fingerprint(kc.skey))
                VDotRule()
                VDataRow(tag: "ekey", tagTint: V8.C.ink4, title: "开锁密钥指纹", value: DiagSnapshot.fingerprint(kc.ekey))
                VDotRule()
                VDataRow(tag: "PIN", tagTint: V8.C.ink4, title: "存的 ekey 嵌的 PIN", value: DiagSnapshot.ekeyPinMasked(kc))
            }
            .padding(.top, V8.S.gapS)
            Text("密钥只显示指纹（前 4 + 后 4 位）；要贴给别人的排障信息里也不会出现明文。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 锁端实时读数

    private func statusCard(_ kc: Keychain) -> some View {
        VCard2 {
            VCardHead(eyebrow: "锁端实时读数", statement: status == nil ? "还没读到" : "已同步到本机", trailing: status == nil ? nil : "全量")
            VDivider2()
                .padding(.top, V8.S.gapM)
            if let st = status {
                VStack(spacing: 0) {
                    VDataRow(tag: "固件", tagTint: V8.C.ink4, title: "锁端固件", value: st.firmware.isEmpty ? "未上报" : st.firmware)
                    VDotRule()
                    VDataRow(tag: "电量", tagTint: V8.C.ink4, title: "电池剩余", value: st.powerLevel >= 0 ? "\(st.powerLevel)" : "未读到", unit: st.powerLevel >= 0 ? "%" : nil)
                    VDotRule()
                    VDataRow(tag: "锁钟", tagTint: V8.C.ink4, title: "锁内时间", value: st.lockTime > 0 ? TimeFormat.clock(ZKProtocol.protoSecondsToMs(st.lockTime)) : "未读到")
                    VDotRule()
                    VDataRow(tag: "安全", tagTint: V8.C.ink4, title: securityText(st), value: "")
                    VDotRule()
                    VDataRow(tag: "PIN", tagTint: V8.C.ink4, title: "已用 / 容量", value: usedOfCap(cap: st.pinCap, stock: st.pinStock, local: kc.pins.filter { !$0.isEmpty }.count))
                    VDotRule()
                    VDataRow(tag: "密码", tagTint: V8.C.ink4, title: "已用 / 容量", value: usedOfCap(cap: st.pwdCap, stock: st.pwdStock, local: DB.listPwds(kc.mac).count))
                    VDotRule()
                    VDataRow(tag: "指纹", tagTint: V8.C.ink4, title: "已用 / 容量", value: usedOfCap(cap: st.fpCap, stock: st.fpStock, local: DB.listFps(kc.mac).count))
                    VDotRule()
                    VDataRow(tag: "密钥", tagTint: V8.C.ink4, title: "通信密钥状态", value: sKeyStatusWord(st.sKeyStatus))
                    VDotRule()
                    VDataRow(tag: "动态码", tagTint: V8.C.ink4, title: "更换周期", value: st.zotpPeriod.map { "\($0)" } ?? "未上报", unit: st.zotpPeriod == nil ? nil : "分钟")
                }
                .padding(.top, V8.S.gapS)
            } else {
                Text(busy ? "读取中…" : "还没读到 —— 连上锁后自动读。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VNavRow(title: "重新读取", detail: "读锁端状态与最近一页变更流水") {
                Task { await refresh() }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private func securityText(_ st: StatusSnapshotData) -> String {
        "验签" + (st.verifyMode == 1 ? "开" : "关") + " · 广播" + (st.broadcastMode == 1 ? "开" : "关") + " · 临时码" + (st.tempPwdMode == 1 ? "开" : "关")
    }

    /// 「已用 / 容量」的统一写法。容量未上报时报本机条数并说明容量没读到 —— 不能写死「已用 0」。
    private func usedOfCap(cap: Int?, stock: Int, local: Int) -> String {
        guard stock >= 0 else { return "未读到" }
        guard let c = cap, c > 0 else { return "本机 \(local) 条 · 容量未读" }
        return "\(max(c - stock, 0)) / \(c)"
    }

    private func sKeyStatusWord(_ v: Int) -> String {
        switch v {
        case 0: return "未设置"
        case 3: return "已就绪"
        default: return "状态 \(v)"
        }
    }

    // MARK: - 凭证台账

    private func ledgerCard(_ kc: Keychain) -> some View {
        VCard2 {
            VCardHead(eyebrow: "凭证台账", statement: "本机与锁端对账")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                VDataRow(tag: "本机", tagTint: V8.C.ink4, title: "PIN 池", value: "\(kc.pins.filter { !$0.isEmpty }.count) 枚（声明 \(kc.pins.count)）")
                VDotRule()
                VDataRow(tag: "本机", tagTint: V8.C.ink4, title: "密码", value: "\(DB.listPwds(kc.mac).count) 条")
                VDotRule()
                VDataRow(tag: "本机", tagTint: V8.C.ink4, title: "指纹", value: "\(DB.listFps(kc.mac).count) 枚")
                if let st = status {
                    VDotRule()
                    VDataRow(tag: "对账", tagTint: V8.C.ink4, title: "锁端已用 vs 本机池",
                             value: "\(max((st.pinCap ?? 0) - st.pinStock, 0)) vs \(kc.pins.filter { !$0.isEmpty }.count)")
                }
            }
            .padding(.top, V8.S.gapS)
            if let st = status {
                let used = max((st.pinCap ?? 0) - st.pinStock, 0)
                let local = kc.pins.filter { !$0.isEmpty }.count
                Text(used == local
                     ? "数量一致（但两批都满池时数量恒等，不能证明是同一批 —— 真正的判据是开锁时锁端是否拒收这枚 PIN）。"
                     : "数量不一致 —— 现在签发的凭证必被锁端拒绝，需要修池或重新导入。")
                    .font(V8.T.footnote)
                    .foregroundStyle(used == local ? V8.C.ink3 : V8.C.danger)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 凭证变更流水

    private var changeLogCard: some View {
        VCard2 {
            VCardHead(eyebrow: "锁端凭证变更", statement: "别的手机或网关做的也算", trailing: "\(logs.count) 条")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("锁端自己记录的凭证操作 —— 这是「对不上」时的第一手证据。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(logs.prefix(20).enumerated()), id: \.offset) { pair in
                    if pair.offset > 0 { VDotRule() }
                    VStack(alignment: .leading, spacing: V8.S.gapXS) {
                        HStack(spacing: V8.S.gapS) {
                            Text(pair.element.lockTimeStr)
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.ink4)
                                .monospacedDigit()
                            Text(pair.element.typeName)
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.ink1)
                            Spacer(minLength: 0)
                        }
                        if let diff = pair.element.diffDescription {
                            Text(diff)
                                .font(V8.T.caption)
                                .foregroundStyle(V8.C.ink3)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, V8.S.gapXS)
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 修池（唯一写动作）

    private func repairCard(_ kc: Keychain) -> some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "修复", statement: readOnly ? "只读试验模式已开启" : "保留通信密钥，只重写 PIN 表")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("开锁一直被拒、且本机 PIN 池与锁端对不上时，用「修池」：保留通信密钥、只重写 PIN 表，然后自动重签开锁凭证。不用重置锁，但要连上锁才能下发 —— 请在门锁旁边执行。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button { askRepair = true } label: {
                Text("修池（重写 PIN 表 · 保通信密钥）")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(busy || mac.isEmpty || readOnly)
            .opacity((busy || mac.isEmpty || readOnly) ? 0.45 : 1)
            .padding(.top, V8.S.gapM)
            if readOnly {
                Text(TrialCopy.blocked("修池这一写操作"))
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapS)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var outcomeCard: some View {
        if let outcome {
            VCard2(style: .well) {
                Text(outcome)
                    .font(V8.T.footnote)
                    .foregroundStyle(outcome.hasPrefix("修池完成") ? V8.C.ok : V8.C.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 动作

    // MARK: - 空壳

    private var godDecoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "God 模式", statement: "空壳模式不渲染")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下，本页不显示锁身份、锁端读数与凭证台账，也不提供修池 —— 这些字段在空壳下仍是真实值，显示出来等于把锁的底牌摊开。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.body - V8.T.body.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 动作

    @MainActor
    private func refresh() async {
        guard !decoyed, let kc else { return }
        busy = true
        errorText = nil
        do {
            _ = try await app.lockLink.getStatus(mac: kc.mac)
        } catch {
            errorText = "读状态失败：" + ((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
        status = DB.readStatus(kc.mac)
        do {
            let page = try await app.lockLink.getLogs(orderType: 0, startIdx: 0, pageSize: 20)
            logs = page.logs.filter { [14, 15, 20, 21].contains($0.type) }
        } catch {
            errorText = "读日志失败：" + ((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
        busy = false
    }

    @MainActor
    private func repair() async {
        guard !decoyed, !readOnly, let kc else { return }
        busy = true
        errorText = nil
        outcome = nil
        do {
            _ = try await app.lockLink.repairPool(m: DB.normalizeMac(kc.mac)) { _ in }
            outcome = "修池完成 —— 开锁凭证已重签，请再按一次开锁"
        } catch {
            outcome = "修池失败：" + ((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
        busy = false
        await refresh()
    }
}


