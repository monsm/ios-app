// AddLockHomeScreen.swift —— 配网 / 添加门锁（V8 设计语言）
//
// 与 AddLockScreen 的能力对齐：发现附近处于重置态的锁 → 校验 → 初始化写钥 → 命名，
// 四步是一条真序列，每步都留下一条可核对的步骤行；中途放弃就回滚，退回发现列表并常驻原因。
// 只改渲染层：扫描仍走 BLEService.scanWindow，配网仍走 LockService.pair，命名仍落
// DB.saveKeychain + LockArchive.meta 的 place。
//
// 与旧页的刻意差异：
//   ① 空壳模式（胁迫码）整页停用 —— 配网会真的生成密钥写进锁的密钥槽，
//      而空壳下 keychain(mac) 恒为 nil，旧页会把已添加的锁标成「可配网」。
//   ② 只读试验模式下明确禁止「开始配网」（引擎 assertReadOnly 会拦死写命令）。
import SwiftUI

struct AddLockHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// 四步：发现 → 校验 → 初始化 → 命名。编号只在这里用，因为它是真序列。
    private enum Phase: Equatable {
        case scanning
        case ready
        case pairing(step: Int)
        case naming
        case done
    }

    private struct CandidateItem: Identifiable, Equatable {
        let id: String
        let name: String
        let mac: String
        let model: String
        let rssi: Int
        /// 广播里的 resetStatus 位：只有重置态的锁才能换钥。
        let inReset: Bool
        let alreadyAdded: Bool
    }

    @State private var phase: Phase = .scanning
    @State private var candidates: [CandidateItem] = []
    @State private var steps: [String] = []
    @State private var banner: String?
    @State private var picked: CandidateItem?
    @State private var nickname = ""
    @State private var place = ""
    @State private var askConfirm = false
    @State private var echoResult: String?
    /// 配网链的 Task 句柄。「中止并回滚」直接 cancel 它。
    @State private var pairTask: Task<Void, Never>?
    /// 配网成功拿到的钥匙串（commitName 要拿它落名字）。
    @State private var pairedKeychain: Keychain?

    private static let stepTitles = ["发现", "校验", "初始化", "命名"]

    private var decoyed: Bool { DB.isDecoy }
    private var readOnly: Bool { app.trialGuard }

    private var currentStep: Int {
        switch phase {
        case .scanning, .ready: return 0
        case .pairing(let step): return step
        case .naming, .done: return 3
        }
    }

    private var judgement: String {
        if decoyed { return "空壳模式不提供配网" }
        switch phase {
        case .scanning: return "正在听附近的锁"
        case .ready: return candidates.isEmpty ? "附近没有可配网的锁" : "发现 \(candidates.count) 把可配网的锁"
        case .pairing(let step): return "第 \(step) / 4 步 · 请把手机贴近门锁"
        case .naming: return "密钥已写入，还差一个名字"
        case .done: return "已添加，下一步验证链路"
        }
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。配网会真的改锁端密钥槽，所以这里不提供。"
        }
        return "配网会生成本机密钥并写进门锁密钥槽；中途离开这一页会按已中止处理并回滚。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            if decoyed {
                EmptyView()
            } else {
                stepChips
            }
        } content: {
            if decoyed {
                decoyCard
            } else {
                if let banner {
                    // 2026-11-05（截图审查 · 流程不合理）：
                    // 「此设备不支持所需的蓝牙功能」这种**硬失败**，下面的按钮却是「重试」——
                    // 一句话说「换一把锁」，按钮说「再来一次」，用户会一直点一个不可能成功的按钮。
                    // 与 BLEService 的状态文案对齐：不可用类（不支持）不给重试，只说明真正的出路。
                    let terminal = banner.contains("不支持")
                    VFailure(
                        what: "这一次没有配完",
                        why: banner,
                        next: terminal
                            ? "这台设备没有可用的蓝牙（模拟器或硬件不支持）。换一台真机再来；锁没有被改动。"
                            : "锁没有被改动一半就留着。按准备步骤重来，或换一把锁。",
                        retry: terminal ? nil : { Task { await scan() } }
                    )
                }
                switch phase {
                case .scanning, .ready:
                    prepareCard
                    listSection
                case .pairing:
                    ladderCard
                    chainCard
                case .naming:
                    ladderCard
                    namingCard
                case .done:
                    doneCard
                }
            }
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await scan() }
        .onDisappear {
            guard pairTask != nil else { return }
            pairTask?.cancel()
            pairTask = nil
        }
        .v8Confirm(
            isPresented: $askConfirm,
            title: "开始添加这把锁？",
            consequence: "配网会生成本机密钥并写入门锁密钥槽，App 内无法撤销。请让手机贴近门锁，中途不要离开这一页。",
            confirmTitle: "开始添加",
            isDestructive: true
        ) {
            startPairing()
        }
    }

    // MARK: - 四步芯片

    private var stepChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: V8.S.gapChip) {
                ForEach(Array(Self.stepTitles.enumerated()), id: \.offset) { index, title in
                    VChip2(
                        icon: .ring(stepFraction(index), stepTint(index)),
                        label: "第 \(index + 1) 步",
                        value: stepWord(index) + " · " + title
                    )
                }
            }
            .padding(.leading, V8.S.gutterCard)
            .padding(.trailing, V8.S.gutterCard)
        }
        .scrollClipDisabled()
    }

    private func stepFraction(_ index: Int) -> Double {
        if phase == .done || index < currentStep { return 1 }
        if index == currentStep { return 0.5 }
        return 0.02
    }

    private func stepTint(_ index: Int) -> Color {
        if phase == .done || index < currentStep { return V8.C.ok }
        if index == currentStep { return V8.C.accent }
        return V8.C.ink4
    }

    private func stepWord(_ index: Int) -> String {
        if phase == .done || index < currentStep { return "已完成" }
        if index == currentStep { return "进行中" }
        return "待"
    }

    // MARK: - 准备与发现

    private var prepareCard: some View {
        VCard2 {
            VCardHead(eyebrow: "准备", statement: "RESET 三声嘀", trailing: "2 米内")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("1. 从后面板下方打开板盖。\n2. 长按左侧 RESET 键，直到「嘀嘀嘀」三声后松开。\n3. 保持这一页，等它出现在下面的列表里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .lineSpacing(V8.L.footnote - V8.T.footnote.size)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            if readOnly {
                Text("只读试验模式已开启：可以扫描，但不能开始配网。到「设置 → 安全 → 只读试验模式」关掉再试。")
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if phase == .scanning {
                VBusy(text: "正在搜索门锁…")
                    .padding(.top, V8.S.gapM)
            } else {
                VNavRow(title: "重新扫描", detail: "再听 10 秒广播，只认重置态的锁") {
                    Task { await scan() }
                }
                .padding(.top, V8.S.gapS)
            }
        }
    }

    @ViewBuilder
    private var listSection: some View {
        if phase == .scanning {
            VCard2 {
                VBusy(text: "10 秒内还没听到广播")
            }
        } else if candidates.isEmpty {
            VEmpty(
                title: "重新扫描附近",
                reason: "先把锁做到重置态（长按 RESET 到三声嘀），手机贴到 2 米内，再点下面的重新扫描。",
                actionTitle: "重新扫描"
            ) {
                Task { await scan() }
            }
        } else {
            VCard2 {
                VCardHead(eyebrow: "发现的设备", statement: "点一行开始配网", trailing: "\(candidates.count) 台")
                VDivider2()
                    .padding(.top, V8.S.gapM)
                VStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, c in
                        if index > 0 { VDivider2() }
                        candidateRow(c)
                    }
                }
            }
        }
    }

    private func candidateRow(_ c: CandidateItem) -> some View {
        Button {
            tap(c)
        } label: {
            VStack(alignment: .leading, spacing: V8.S.gapXS) {
                HStack(spacing: V8.S.gapS) {
                    Text(c.name)
                        .font(V8.T.value)
                        .foregroundStyle(V8.C.ink1)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(c.rssi) dBm")
                        .font(V8.T.caption)
                        .foregroundStyle(V8.C.ink4)
                        .monospacedDigit()
                }
                Text(DB.shortMac(c.mac) + " · " + c.model)
                    .font(V8.T.caption)
                    .foregroundStyle(V8.C.ink4)
                Text(c.alreadyAdded
                     ? "本机已有这把锁，点它直接去读数页"
                     : (c.inReset ? "重置态 · 可以换钥" : "不在重置态 · 请先做键盘重置"))
                    .font(V8.T.caption)
                    .foregroundStyle(c.alreadyAdded || c.inReset ? V8.C.ink3 : V8.C.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: V8.H.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.name + "，编号 " + DB.shortMac(c.mac) + "，" + rowWord(c) + "，信号 \(c.rssi) dBm")
        .contextMenu {
            Button {
                Task { await probe(c) }
            } label: {
                Label("连通探测", systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }

    private func rowWord(_ c: CandidateItem) -> String {
        if c.alreadyAdded { return "已添加" }
        return c.inReset ? "可配网" : "待重置"
    }

    // MARK: - 四步梯

    private var ladderCard: some View {
        VCard2 {
            VCardHead(eyebrow: "四步梯", statement: "每一步都留下可核对的一行")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStack(spacing: 0) {
                ForEach(Array(Self.stepTitles.enumerated()), id: \.offset) { index, title in
                    if index > 0 { VDotRule() }
                    VDataRow(
                        tag: DF.pad2(index + 1),
                        tagTint: stepTint(index),
                        title: title,
                        value: stepWord(index)
                    )
                }
            }
            .padding(.top, V8.S.gapS)
        }
    }

    // MARK: - 写入进度

    private var chainCard: some View {
        VCard2 {
            VCardHead(eyebrow: "写入进度", statement: "请把手机贴近门锁", trailing: picked.map { DB.shortMac($0.mac) })
            VDivider2()
                .padding(.top, V8.S.gapM)
            if let echoResult {
                Text(echoResult)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.ink3)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: V8.S.gapS) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: V8.S.gapS) {
                        Image(systemName: "checkmark")
                            .font(V8.T.caption)
                            .foregroundStyle(V8.C.ok)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(V8.T.footnote)
                            .foregroundStyle(V8.C.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, V8.S.gapM)
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("写入期间不要离开这一页，也不要走远。任何一步失败，本机会断开链路并清掉半成品，锁不会被改动一半就留着。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                pairTask?.cancel()
                pairTask = nil
                rollback("已中止：链路已断开，锁没有被改一半就留着。")
            } label: {
                Text("中止并回滚")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("中止配网并回滚")
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 命名

    private var namingCard: some View {
        VCard2 {
            VCardHead(eyebrow: "给锁起个名字", statement: "必填", trailing: "最后一步")
            VDivider2()
                .padding(.top, V8.S.gapM)
            TextField("昵称（如 婆婆家·入户门）", text: $nickname)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .submitLabel(.next)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            TextField("场所副标题（如 玄关 / 车库，可留空）", text: $place)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .submitLabel(.done)
                .frame(minHeight: V8.H.min)
                .padding(.horizontal, V8.S.gapM)
                .background(V8.C.well, in: .rect(cornerRadius: V8.R.inset))
                .padding(.top, V8.S.gapM)
            if let duplicateNameHint {
                Text(duplicateNameHint)
                    .font(V8.T.footnote)
                    .foregroundStyle(V8.C.warn)
                    .padding(.top, V8.S.gapM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("昵称会出现在门页的页头与读数页；场所副标题用来区分同一栋楼里的几道门。")
                .font(V8.T.caption)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                commitName()
            } label: {
                Text("完成添加")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.chipOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .buttonStyle(.plain)
            .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(nickname.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            .padding(.top, V8.S.gapM)
        }
    }

    // MARK: - 完成

    private var doneCard: some View {
        VCard2 {
            VCardHead(eyebrow: "已添加", statement: "密钥已写入，锁端已应答", trailing: picked.map { DB.shortMac($0.mac) })
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("立刻做一次全量备份：本机密钥只存在这台手机上，换机或卸载前必须备份。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("下一步：回门页成功开一次锁，锁端会给这一次打上「链路已验证」标记 —— 之后才谈得上自动开锁与临时码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "去门页开一次锁", detail: "锁端会为这次成功开锁打上链路已验证标记") {
                router.request(.none)
                router.select(.door)
            }
            .padding(.top, V8.S.gapM)
            VNavRow(title: "去读锁实况", detail: "看电量、固件与链路") {
                router.request(.dest(.lockStatus))
            }
        }
    }

    // MARK: - 空壳

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "添加门锁", statement: "空壳模式不配网")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下不扫描、不配网。配网会真的生成本机密钥并写进锁的密钥槽，这一步没有撤销入口。")
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

    // MARK: - 交互

    @MainActor
    private func scan() async {
        guard !decoyed else { return }
        phase = .scanning
        banner = nil
        echoResult = nil
        candidates = []
        do {
            // 真链路：BLEService 扫 6 秒（allowDuplicates 让 RSSI 持续刷新），
            // 只保留广播厂商段能解析出 MAC 的设备 —— 解析不出 MAC 的连不上。
            let found = try await BLEService.shared.scanWindow(allowDuplicates: true, timeoutMs: 6000)
            var list: [CandidateItem] = []
            for d in found {
                guard let adv = ZKProtocol.parseAdv(d.advertisHex),
                      let mac = ZKProtocol.lockMac(fromAdv: adv) else { continue }
                let model = PidMap.productNames[adv.pid] ?? "智能门锁"
                list.append(CandidateItem(
                    id: d.deviceId,
                    name: d.name.isEmpty ? model : d.name,
                    mac: mac,
                    model: PidMap.modelName(adv.pid),
                    rssi: d.rssi,
                    inReset: adv.resetStatus != 0,
                    alreadyAdded: DB.keychain(mac) != nil
                ))
            }
            candidates = list.sorted { $0.rssi > $1.rssi }
            if candidates.isEmpty {
                banner = "没搜到门锁。确认手机蓝牙已开、锁已在重置态（长按后面板 RESET 到三声嘀），再点「重新扫描」。"
            }
        } catch {
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        phase = .ready
    }

    @MainActor
    private func probe(_ c: CandidateItem) async {
        // 真链路：免令牌明文回声（临时连接 → 发固定值 → 拆链路），不改锁内任何东西。
        do {
            let r = try await LockService.shared.probeEcho(deviceId: c.id)
            echoResult = r.matched
                ? "回声：" + c.name + " 往返 \(r.ms) ms · 回显与发出值一致"
                : "回声不匹配：" + c.name + " 往返 \(r.ms) ms · 回执码 \(r.rc)"
        } catch {
            echoResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func tap(_ c: CandidateItem) {
        if decoyed { return }
        if c.alreadyAdded {
            banner = "这把锁已经添加过了（" + DB.shortMac(c.mac) + "）。不需要再配一次网，直接去读数页即可。"
            router.request(.dest(.lockStatus))
            return
        }
        guard c.inReset else {
            banner = "「" + c.name + "」不在重置态。先在键盘上做物理重置（长按 RESET 到三声嘀），再回来点它。"
            return
        }
        guard !readOnly else {
            banner = "只读试验模式已开启：配网写入门锁的命令全部被拦下。到「设置 → 安全 → 只读试验模式」关掉再试。"
            return
        }
        picked = c
        askConfirm = true
    }

    private func startPairing() {
        guard let c = picked else { return }
        pairTask = Task { await runChain(c) }
    }

    @MainActor
    private func runChain(_ c: CandidateItem) async {
        banner = nil
        steps = []
        nickname = c.model
        phase = .pairing(step: 1)
        steps.append("01 正在连接 " + c.name + "（" + DB.shortMac(c.mac) + "）")
        do {
            // 真链路：LockService.pair 编排完整配网链。
            // progress 回调在后台线程，跳主 actor 再追加，避免跨线程改 @State。
            let kc = try await LockService.shared.pair(deviceId: c.id, mac: c.mac) { msg in
                Task { @MainActor in self.steps.append(self.cleanStep(msg)) }
            }
            if Task.isCancelled { rollback("已中止：配网没有跑完，锁未被改动。"); return }
            pairedKeychain = kc
            steps.append("状态校验通过 —— 这把锁已经是你的了")
            phase = .naming
        } catch {
            if Task.isCancelled { rollback("已中止：配网没有跑完，锁未被改动。"); return }
            rollback((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @MainActor
    private func rollback(_ reason: String) {
        // 文案写「链路已断开」，就必须真的断开 —— 否则再点一次配网会撞上「已有连接」。
        // 不清未完成的配网记录（DB.clearPendingPair 的注释写明那份记录是续配依据）。
        LockService.shared.disconnect()
        steps = []
        picked = nil
        banner = reason
        phase = .ready
    }

    /// 进度文案来自引擎，里面带协议命令号；用户界面不显示命令号。
    private func cleanStep(_ text: String) -> String {
        var s = text
        if let range = s.range(of: " \\(cmd [0-9A-Fa-f]+\\)", options: .regularExpression) {
            s.removeSubrange(range)
        }
        s = s.replacingOccurrences(of: "cmd [0-9A-Fa-f]+ ", with: "", options: .regularExpression)
        return s
    }

    /// 已有同名锁时的提醒（不拦）。比对的是显示名，与门页切换芯片同一口径。
    private var duplicateNameHint: String? {
        let n = nickname.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        let selfMac = DB.normalizeMac(picked?.mac ?? pairedKeychain?.mac ?? "")
        let others = DB.keychains().filter {
            DB.normalizeMac($0.mac) != selfMac && LockArchive.displayName($0) == n
        }
        guard let first = others.first else { return nil }
        let place = LockArchive.meta(first.mac).place
        return "已经有另一把锁叫「" + n + "」" + (place.isEmpty ? "" : "（" + place + "）") + "了 —— 门页的切换芯片只显示昵称，两把同名会分不出来。建议在地点副标题里写清是哪一个。"
    }

    private func commitName() {
        guard !decoyed else {
            banner = "空壳模式下不写入钥匙串 —— 先退出空壳再来配网。"
            return
        }
        let name = nickname.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let mac = pairedKeychain?.mac ?? picked?.mac ?? ""
        guard !mac.isEmpty else {
            phase = .ready
            return
        }
        // 落库：钥匙串改名 + 设为当前锁，然后让 AppModel 从 Engine 重载。
        if var kc = DB.keychain(mac) {
            kc.name = name
            DB.saveKeychain(kc)
        }
        // 场所副标题与锁档案页同口径：写进 LockArchive.meta 的 place。
        let trimmedPlace = place.trimmingCharacters(in: .whitespaces)
        if !trimmedPlace.isEmpty {
            var m = LockArchive.meta(mac)
            m.place = trimmedPlace
            LockArchive.save(mac, m)
        }
        DB.currentMac = mac
        banner = nil
        Task {
            await app.reload(refreshStatus: false)
            phase = .done
        }
    }
}
