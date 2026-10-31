// AddLockScreen.swift —— 配网（门 · 添加门锁）
//
// 这屏干什么：发现附近处于重置态的锁 → 校验 → 初始化写钥 → 命名，四步是一条真序列，
// 每步都留下一条可核对的步骤行；中途放弃就回滚，退回发现列表并常驻原因。
// 数据从哪来：BLE 广播（AppModel 尚未接 Engine，本页用可替换的 Candidate 列表）。
// 主动作：点列表里那一行开始配网；本屏唯一的 signal 填充是"开始添加"。
import SwiftUI

struct AddLockScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// 四步：发现 → 校验 → 初始化 → 命名。编号只在这里用，因为它是真序列（契约 §11）。
    private enum Phase: Equatable {
        case scanning
        case ready
        case pairing(step: Int)
        case naming
        case done
    }

    private struct Candidate: Identifiable, Equatable {
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
    @State private var candidates: [Candidate] = []
    @State private var steps: [String] = []
    @State private var banner: String?
    @State private var picked: Candidate?
    @State private var nickname = ""
    @State private var place = ""
    @State private var askConfirm = false
    @State private var echoResult: String?
    /// 中止请求：链在两帧之间检查它，命中就走回滚，而不是假装跑完。
    @State private var abortRequested = false
    /// 配网成功拿到的钥匙串（commitName 要拿它落名字）。
    @State private var pairedKeychain: Keychain?

    private static let stepTitles = ["发现", "校验", "初始化", "命名"]

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if let banner { bannerPanel(banner) }
                switch phase {
                case .scanning, .ready:
                    ladderPanel
                    scanPanel
                    listPanel
                case .pairing:
                    ladderPanel
                    chainPanel
                case .naming:
                    ladderPanel
                    namingPanel
                case .done:
                    donePanel
                }
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("添加门锁")
        .navigationBarTitleDisplayMode(.inline)
        .task { await scan() }
        .alert("开始添加这把锁？", isPresented: $askConfirm) {
            Button("取消") { picked = nil }
            Button("开始添加") { startPairing() }
        } message: {
            Text("配网会生成本机密钥并写入门锁密钥槽，App 内无法撤销。请让手机贴近门锁，中途不要离开这一页。")
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("添加门锁")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
            HStack(spacing: T.S.s) {
                StateDot(tone: headerTone, word: headerWord)
                Text(headerText)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    // 状态行最多两行：宁可换行，不要截断或缩字（缩字会把 13pt 压到 10pt，低于可读下限）
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, T.S.gutter)
    }

    private var headerTone: Tone {
        switch phase {
        case .pairing: return .live
        case .done: return .ok
        case .naming: return .attention
        default: return candidates.isEmpty ? .neutral : .ok
        }
    }

    private var headerWord: String {
        switch phase {
        case .scanning: return "扫描中"
        case .ready: return candidates.isEmpty ? "未发现" : "可配网"
        case .pairing: return "写入中"
        case .naming: return "待命名"
        case .done: return "已添加"
        }
    }

    private var headerText: String {
        switch phase {
        case .scanning: return "正在听 10 秒广播，只认重置态的锁"
        case .ready: return candidates.isEmpty ? "附近没有可配网的锁" : "点列表里那一行开始"
        case .pairing(let step): return "第 \(step) / 4 步 · 请把手机贴近门锁"
        case .naming: return "密钥已写入，最后给它起个名字"
        case .done: return "下一步：成功开一次锁，完成链路验证"
        }
    }

    // MARK: 四步梯（真序列，不是装饰进度）

    private var currentStep: Int {
        switch phase {
        case .scanning, .ready: return 0
        case .pairing(let step): return step
        case .naming, .done: return 3
        }
    }

    private var ladderPanel: some View {
        Panel {
            VStack(spacing: 0) {
                ForEach(Array(Self.stepTitles.enumerated()), id: \.offset) { index, title in
                    if index > 0 { hairline }
                    ladderRow(index: index, title: title)
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func ladderRow(index: Int, title: String) -> some View {
        let done = index < currentStep || phase == .done
        let current = index == currentStep && phase != .done
        return HStack(spacing: T.S.m) {
            Text(pad2(index + 1))
                .font(T.F.reading(13, weight: .medium))
                .foregroundStyle(done ? Ink.ink : Ink.inkFaint)
                .monospacedDigit()
                .frame(width: T.Icon.xl, alignment: .leading)
            Text(title)
                .font(T.F.body)
                .foregroundStyle(done ? Ink.ink : (current ? Ink.ink : Ink.inkFaint))
            Spacer(minLength: T.S.s)
            if done {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.s, weight: .semibold))
                    .foregroundStyle(Ink.ink)
            } else if current {
                StateDot(tone: .live, word: "进行中")
            } else {
                Text("待")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
            }
        }
        .frame(minHeight: T.Hit.min)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(index + 1) 步 \(title)，\(done ? "已完成" : (current ? "进行中" : "未开始"))")
    }

    // MARK: 扫描（进页即扫，可重扫；扫描中给加载态）

    private var scanPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "准备", trailing: "RESET 三声嘀")
                Text("1. 从后面板下方打开板盖。\n2. 长按左侧 RESET 键，直到「嘀嘀嘀」三声后松开。\n3. 保持这一页，等它出现在下面的列表里。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                hairline
                if phase == .scanning {
                    BusyRow(text: "正在搜索门锁…")
                } else {
                    SecondaryAction(title: "重新扫描", systemImage: "arrow.clockwise") {
                        Task { await scan() }
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var listPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "发现的设备", trailing: candidates.isEmpty ? nil : "\(candidates.count) 台")
                if candidates.isEmpty {
                    if phase == .scanning {
                        BusyRow(text: "10 秒内还没听到广播")
                    } else {
                        EmptyPanel(
                            title: "附近没有可配网的锁",
                            message: "先把锁做到重置态（长按 RESET 到三声嘀），手机贴到 2 米内，再点下面的重新扫描。",
                            actionTitle: "重新扫描",
                            systemImage: "dot.radiowaves.left.and.right"
                        ) {
                            Task { await scan() }
                        }
                        .padding(.vertical, T.S.xl)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, c in
                            if index > 0 { hairline }
                            candidateRow(c)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func candidateRow(_ c: Candidate) -> some View {
        Button {
            tap(c)
        } label: {
            HStack(alignment: .top, spacing: T.S.m) {
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    Text(c.name)
                        .font(T.F.bodyStrong)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    Text("\(c.mac) · \(c.model)")
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkFaint)
                    Text(c.alreadyAdded
                         ? "本机已有这把锁，点它直接去读数页"
                         : (c.inReset ? "重置态 · 可以换钥" : "不在重置态 · 请先做键盘重置"))
                        .font(T.F.unit)
                        .foregroundStyle(c.alreadyAdded || c.inReset ? Ink.inkSub : State.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: T.S.s)
                VStack(alignment: .trailing, spacing: T.S.xxs) {
                    Reading(value: "\(c.rssi)", unit: "dBm", size: 13, tint: Ink.inkSub, animated: false)
                    StateDot(tone: rowTone(c), word: rowWord(c))
                }
            }
            .frame(minHeight: T.Hit.min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(c.name)，\(c.mac)，\(rowWord(c))，信号 \(c.rssi) dBm")
        .contextMenu {
            Button {
                Task { await probe(c) }
            } label: {
                Label("连通探测", systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }

    private func rowTone(_ c: Candidate) -> Tone {
        if c.alreadyAdded { return .neutral }
        return c.inReset ? .ok : .attention
    }

    private func rowWord(_ c: Candidate) -> String {
        if c.alreadyAdded { return "已添加" }
        return c.inReset ? "可配网" : "待重置"
    }

    // MARK: 写锁链（真序列；失败/中止都回滚）

    private var chainPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "写入进度", trailing: picked?.mac)
                if let echoResult {
                    Text(echoResult)
                        .font(T.F.unit)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: T.S.s) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: T.S.s) {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                                .font(T.F.icon(T.Icon.s, weight: .semibold))
                                .foregroundStyle(Ink.ink)
                            Text(line)
                                .font(T.F.caption)
                                .foregroundStyle(Ink.inkSub)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                hairline
                Text("写入期间不要离开这一页，也不要走远。任何一步失败，本机会断开链路并清掉半成品，锁不会被改动一半就留着。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryAction(title: "中止并回滚", systemImage: "xmark") {
                    abortRequested = true
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 命名步

    private var namingPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "给锁起个名字", trailing: "必填")
                TextField("昵称（如 婆婆家·入户门）", text: $nickname)
                    .font(T.F.body)
                    .textFieldStyle(.plain)
                    .submitLabel(.next)
                    .frame(minHeight: T.Hit.min)
                hairline
                TextField("场所副标题（如 玄关 / 车库，可留空）", text: $place)
                    .font(T.F.body)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .frame(minHeight: T.Hit.min)
                hairline
                Text("昵称会出现在「门」页的页头与读数页；场所副标题用来区分同一栋楼里的几道门。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryAction(
                    title: "完成添加",
                    systemImage: "checkmark",
                    busy: false
                ) {
                    commitName()
                }
                .opacity(nickname.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 完成步（给下一步出路）

    private var donePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "已添加", trailing: picked?.mac)
                StatusLine(tone: .ok, text: "密钥已写入，锁端已应答")
                hairline
                Text("立刻做一次全量备份：本机密钥只存在这台手机上，换机或卸载前必须备份。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Text("下一步：回「门」页成功开一次锁，锁端会给这一次打上「链路已验证」标记 —— 之后才谈得上自动开锁与临时码。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                hairline
                PrimaryAction(title: "去门页开一次锁", systemImage: "door.left.hand.closed") {
                    router.request(.none)
                    router.select(.door)
                }
                SecondaryAction(title: "去读锁实况", systemImage: "gauge.with.dots.needle.50percent") {
                    router.request(.dest(.lockStatus))
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private func bannerPanel(_ text: String) -> some View {
        Panel {
            HStack(alignment: .top, spacing: T.S.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                    .font(T.F.icon(T.Icon.s, weight: .semibold))
                    .foregroundStyle(State.attention)
                VStack(alignment: .leading, spacing: T.S.xxs) {
                    Text("这一次没有配完")
                        .font(T.F.bodyStrong)
                        .foregroundStyle(Ink.ink)
                    Text(text)
                        .font(T.F.caption)
                        .foregroundStyle(Ink.inkSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 交互

    @MainActor
    private func scan() async {
        phase = .scanning
        banner = nil
        echoResult = nil
        candidates = []
        do {
            // 真链路：BLEService 扫 6 秒（allowDuplicates 让 RSSI 持续刷新），
            // 只保留广播厂商段能解析出 MAC 的设备 —— 解析不出 MAC 的连不上，列出来只会误导。
            try await BLEService.shared.startScan(allowDuplicates: true, timeoutMs: 6000)
            let found = BLEService.shared.allDiscovered()
            var list: [Candidate] = []
            for d in found {
                guard let adv = ZKProtocol.parseAdv(d.advertisHex),
                      let mac = ZKProtocol.lockMac(fromAdv: adv) else { continue }
                let model = PidMap.productNames[adv.pid] ?? "智能门锁"
                list.append(Candidate(
                    id: d.deviceId,
                    name: d.name.isEmpty ? model : d.name,
                    mac: mac,
                    model: PidMap.modelName(adv.pid),
                    rssi: d.rssi,
                    inReset: true,
                    alreadyAdded: DB.keychain(mac) != nil
                ))
            }
            candidates = list.sorted { $0.rssi > $1.rssi }
            if candidates.isEmpty {
                banner = "没搜到门锁。确认手机蓝牙已开、锁已在重置态（长按后面板 RESET 到三声嘀），再点「重新搜索」。"
            }
        } catch {
            banner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        phase = .ready
    }

    @MainActor
    private func probe(_ c: Candidate) async {
        // 真链路：cmd12 免令牌明文回声（临时连接 → 发 123456 → 拆链路），不改锁内任何东西。
        do {
            let r = try await LockService.shared.probeEcho(deviceId: c.id)
            echoResult = r.matched
                ? "回声：\(c.name) 往返 \(r.ms) ms · 回显与发出值一致"
                : "回声不匹配：\(c.name) 往返 \(r.ms) ms · rc=\(r.rc)"
        } catch {
            echoResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func tap(_ c: Candidate) {
        if c.alreadyAdded {
            banner = "这把锁已经添加过了（\(c.mac)）。不需要再配一次网，直接去读数页即可。"
            router.request(.dest(.lockStatus))
            return
        }
        guard c.inReset else {
            banner = "「\(c.name)」不在重置态。先在键盘上做物理重置（长按 RESET 到三声嘀），再回来点它。"
            return
        }
        picked = c
        askConfirm = true
    }

    private func startPairing() {
        guard let c = picked else { return }
        Task { await runChain(c) }
    }

    @MainActor
    private func runChain(_ c: Candidate) async {
        abortRequested = false
        banner = nil
        steps = []
        nickname = c.model
        phase = .pairing(step: 1)
        steps.append("01 正在连接 " + c.name + "（" + c.mac + "）")
        do {
            // 真链路：cmd23 → cmd05 → cmd08×4 → cmd21 → cmd03，全部由 LockService.pair 编排。
            // progress 回调在后台线程，跳主 actor 再追加，避免跨线程改 @State。
            let kc = try await LockService.shared.pair(deviceId: c.id, mac: c.mac) { msg in
                Task { @MainActor in self.steps.append(msg) }
            }
            pairedKeychain = kc
            steps.append("07 状态校验通过（cmd03）—— 这把锁已经是你的了")
            phase = .naming
        } catch {
            rollback((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    @MainActor
    private func rollback(_ reason: String) {
        // TODO(engine): 真实回滚还要断开链路并清掉半成品台账与 lastDevice 指针。
        steps = []
        picked = nil
        banner = reason
        phase = .ready
    }

    private func commitName() {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let mac = pairedKeychain?.mac ?? picked?.mac ?? ""
        guard !mac.isEmpty else { phase = .ready; return }
        // 落库：钥匙串改名 + 设为当前锁，然后让 AppModel 从 Engine 重载。
        if var kc = DB.keychain(mac) {
            kc.name = name
            DB.saveKeychain(kc)
        }
        DB.currentMac = mac
        banner = nil
        Task {
            await app.reload(refreshStatus: false)
            phase = .done
        }
    }

    private func pad2(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private var hairline: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: T.Stroke.hair)
    }
}