// 添加设备 / 配网
// 2026-10-29 从 Sheets.swift 拆出（原文件 5 个不相关页面挤在 1466 行里）
import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    private enum Flow { case scan, pairing, naming, done }
    @State private var flow: Flow = .scan
    @State private var step = 0                  // 253: 0 发现 · 1 校验 · 2 初始化 · 3 命名
    @State private var devices: [BLEAdvDevice] = []
    @State private var scanning = false
    @State private var pairSteps: [String] = []
    @State private var pairError = ""
    @State private var pairedKC: Keychain?
    @State private var nickname = ""
    @State private var place = ""
    /// 2026-10-29 补：APK `page-devicetypelist`（设备类型列表）允许手选型号。
    /// iOS 默认从蓝牙广播自动识别（`pairedKC.pid`），这里给一个**修正**通道：
    /// 识别不到、或广播里的 pid 是老固件的错值时才用得上。0 = 自动（不覆盖）。
    @State private var pidChoice = 0

    var body: some View { vkBody.destined(.addDevice) }
    var vkBody: some View {
        NavigationStack {
            Group {
                switch flow {
                case .scan: scanView
                case .pairing: pairProgress
                case .naming: namingView
                case .done: doneView
                }
            }
            // 状态切换: 入场弹簧(0.95 起步+淡入), 不从 scale(0) 凭空出现
            .animation(DS.Motion.standard, value: flow)
            .navigationTitle("添加设备")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var scanView: some View {
        List {
            if !pairError.isEmpty {
                // 256: 回滚完成后错误必须可见, 不能无声吞掉
                // 829 (2026-10-11 拍板, D-150a 方案①): 失败面 = 页内常驻横幅 + 直达说明书症状树。
                // 排查只给一句能当场做的事; 原先这里挂「看三步排查」指到帮助页的症状问答树,
                // 那套问答随大删波 3 移除 (用户决策), 所以横幅不再指向一个不存在的页面。
                Section {
                    Label {
                        Text(pairError).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                } footer: {
                    Text("配不上先别反复重试: 先确认锁已上电、手机蓝牙开着, 再回设备页重连一次。")
                }
            }
            Section("操作指引") {
                Text("1. 从后面板下方打开板盖").vkFont(.footnote)
                Text("2. 长按后面板左侧 RESET 按键，直到\"嘀嘀嘀\"三声后松开").vkFont(.footnote)
                Text("3. 保持当前页面，等待完成添加").vkFont(.footnote)
            }
            Section {
                // 807 信号格配对引导 (拍板 2026-10-10: 只给信号与提示，**不自动推进配对**)。
                // 理由写在这: 配对是在重置态换密钥的不可逆写锁操作，把"信号够了"当成"用户想开始了"
                // 是替用户做决定 —— 满格时也只是把话说到"现在点它可以了"。
                HStack(spacing: DS.Space.s) {
                    RSSIBars(level: LinkSense.rssiLevel(LinkSense.shared.lastRssi))
                    Text(LinkSense.rssiLevel(LinkSense.shared.lastRssi) >= 3
                         ? "信号已够，点下面列表里的锁即可开始"   // 807 信号已够
                         : "请再靠近门锁：信号越满广播越完整，配对越不容易中途断")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.Hit.min)
                .accessibilityElement(children: .combine)
                Button {
                    Task { await scan() }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        // 菊花常驻 + 透明度过渡: 插拔会导致文字整体位移
                        ProgressView().controlSize(.small).opacity(scanning ? 1 : 0)
                        Text(scanning ? "正在搜索门锁…" : "重新扫描")
                    }
                    .frame(minHeight: DS.Hit.min)
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(scanning)
            } footer: {
                Text("列表按信号强弱实时排序, 点选可配网的锁即开始添加。")
            }
            // 253 四步进度 (发现/校验/初始化/命名) — 扫描中处于第 0 步
            Section {
                stepBar(current: 0)
                    .padding(.vertical, DS.Space.xs)
            }
            Section {
                if devices.isEmpty {
                    EmptyState(systemImage: "dot.radiowaves.left.and.right",
                               title: "还没扫到设备",
                               message: "附近所有蓝牙设备都会出现在这里并标注状态；已配对但未重置的门锁也会显示。若列表始终为空，请确认手机蓝牙已开启、且与门锁距离在 2 米内。",
                               actionTitle: "开始扫描") {
                        Task { await scan() }
                    }
                }
                ForEach(devices) { d in
                    Button { Task { await confirmPair(d, ZKProtocol.parseAdv(d.advertisHex)) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name.isEmpty ? "未知设备" : d.name)
                                .vkFont(.subheadline, weight: .medium)
                            Text(d.deviceId)
                                .vkFont(.caption2)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: DS.Hit.min)
                    }
                }
            } header: {
                Text("发现的设备")
            } footer: {
                Text("点任意一行开始配对；锁需处于重置态才能配网。")
            }
        }
        .variantList()
        .dsScreenBackground()
        .task { await scan() }   // 251: 进页即扫, 发现列表实时滚动
    }

    // 253 四步进度条: 发现 → 校验 → 初始化 → 命名
    private func stepBar(current: Int) -> some View {
        let steps = [("dot.radiowaves.left.and.right", "发现"),
                     ("checkmark.shield", "校验"),
                     ("gearshape", "初始化"),
                     ("textformat", "命名")]
        return HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: i < current ? "checkmark.circle.fill" : (i == current ? s.0 : "circle"))
                        .font(.system(size: DS.Icon.sm, weight: .semibold))
                        .foregroundStyle(i <= current ? DS.Palette.accentText : DS.Palette.textSub)
                    Text(s.1)
                        .vkFont(.caption)
                        .foregroundStyle(i <= current ? DS.Palette.text : DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("第\(i + 1)步 \(s.1)\(i < current ? ", 已完成" : (i == current ? ", 进行中" : ""))")
                if i < steps.count - 1 {
                    Rectangle().fill(i < current ? DS.Palette.accentText : DS.Palette.hairline)
                        .frame(height: 1.5)
                        .frame(maxWidth: 22)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, DS.Space.s)
        .padding(.horizontal, DS.Space.m)
        // 2026-10-14 材质统一批次: 四步进度条**保持实底**。它在配网 List 的 Section 里,
        // 行组已经是一层玻璃面 —— 行内再上玻璃就是玻璃叠玻璃, 接缝正好压在步骤字底下。
        // @layout-allow 面板实底
        // @layout-allow VK豁免 控件可识别性: 四步进度条的实底，它自己的注释就写着"保持实底"
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
        .animation(DS.Motion.soft, value: current)
    }


    // 写硬件类动作一律先确认: 配网会生成本机密钥并写入门锁, App 内无法撤销
    private func confirmPair(_ d: BLEAdvDevice, _ adv: ZKProtocol.AdvData?) {
        // MAC 一律取**显示序** (ZKProtocol.lockMac) —— 2026-10-17 真机: 这里原先用 adv.macRaw,
        // 而包络里还会 reversePairs 一次 ⇒ 锁收到的 0x88 TargetMAC 正好是反的, 05 之后的每一步
        // 都回 rc=12「mac地址不正确」(锁什么都没写, 只是拒绝), 且台账里会多一份永远对不上号的幽灵记录。
        guard flow == .scan else { return }
        // 2026-10-28 修复：原先这里 `let adv` 是必填，而唯一调用点传的是 **nil** ——
        // 于是整个配网流程永远在第一步静默返回（无确认框、无进度、无报错）。
        // 现在调用点从 `d.advertisHex` 解析出 AdvData；解析失败要说清，不能静默。
        guard let adv = ZKProtocol.parseAdv(d.advertisHex),
              let mac = ZKProtocol.lockMac(fromAdv: adv) else {
            app.showToast("这条广播解析不出门锁信息（可能不是门锁设备），请靠近门锁重试")
            return
        }
        let display = adv.macDisplay ?? "—"
        // 255 MAC 去重拦截: 本地已有该锁 → 不进配网, 引导跳转
        if let dupLock = DB.keychain(mac) {
            // 2026-10-28：原先这里直接 return（静默）—— 用户点了行什么都不会发生。
            // 注释早就写着"引导跳转"，但跳转没写。现在如实说清并把人带到设备页。
            app.showToast("这把锁已经添加过了（\(dupLock.mac.isEmpty ? mac : dupLock.mac)），请到设备页切换")
            app.requestRoute(.device)
            return
        }
        let model = PidMap.modelName(adv.pid)
        // 续配: 锁在 05 换钥之后就不再广播重置位了 (截图里那句"再点一次配网会接着配完"就是这个状态),
        // 所以这一支**不看 inReset**, 只看本机有没有那份没走完的记录 —— 文案也必须说清
        // "不会再换钥", 因为它与"添加"最危险的那一步 (擦锁内密钥域) 完全是两回事。
        if DB.pendingPair(mac) != nil {
            confirmDestructive("继续配网",
                              "本机留有一份「\(d.name)」（\(display) · \(model)）未走完的配网密钥。这次会跳过换钥, 直接把 PIN 池与 bkey 写完 —— 不重新生成密钥, 也不必再做键盘重置。请贴近门锁后继续。",
                              confirmTitle: "继续配网") {
                Task { await self.pair(d, mac) }
            }
            return
        }
        confirmDestructive("添加门锁",
                          "将配对「\(d.name)」（\(display) · \(model)）。配网会生成本机密钥并写入门锁密钥槽，App 内无法撤销，请确认手机已贴近门锁。确定添加吗？",
                          confirmTitle: "开始添加") {
            Task { await self.pair(d, mac) }
        }
    }


    // APK 对照 page-romlist「固件列表」: 发一条免令牌明文回声, 看这台设备答不答话。
    // 不改锁内任何东西, 也不写本机台账 (读 03 状态会落快照/电量/固件观测三处); 不改配对状态。
    @MainActor

    private var pairProgress: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                ProgressView().scaleEffect(1.4)
                    .accessibilityLabel("正在添加设备")
                // 253 四步进度: 配网链映射到 校验(1) → 初始化(2)
                stepBar(current: max(step, 1))
                Text("正在添加设备")
                    .vkFont(.headline)
                    .foregroundStyle(DS.Palette.text)
                Text("请勿断开蓝牙并将手机靠近门锁")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                // 步骤区限高内滚: 步骤再多也不会把页面顶出屏幕
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        ForEach(Array(pairSteps.enumerated()), id: \.offset) { _, s in
                            Label {
                                Text(s).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.ok)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if !pairError.isEmpty {
                            Text(pairError)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.m)
                }
                // 240pt 为刻意上限 (约 6 行步骤), 刻意不入令牌: 令牌只有间距刻度, 没有版面高度刻度
                .frame(maxHeight: 240)
                .variantPlate(DS.Palette.surfaceAlt, .tile)
                // 新步骤逐条浮现 (空间一致性: 从上方推进)
                .animation(DS.Motion.standard, value: pairSteps)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
        }
    }

    // 命名步 (253 第 4 步): 昵称 + 场所副标题 (774), 备注等完整档案进设置-锁档案
    private var namingView: some View {
        Form {
            Section {
                stepBar(current: 3)
                    .padding(.vertical, DS.Space.xs)
            }
            Section {
                TextField("昵称 (如 婆婆家·入户门)", text: $nickname)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                TextField("场所副标题 (如 玄关 / 车库)", text: $place)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            } header: {
                Text("给锁起个名字")
            } footer: {
                Text("昵称会显示在 Hero 卡与切换胶囊上; 场所副标题可留空。符号与色标可在「锁档案」里选。")
            }
            Section {
                Picker("型号", selection: $pidChoice) {
                    Text("自动识别（推荐）").tag(0)
                    ForEach(PidMap.names.sorted(by: { $0.key < $1.key }), id: \.key) { pid, name in
                        Text(name).tag(pid)
                    }
                }
            } header: {
                Text("门锁型号")
            } footer: {
                Text("默认从蓝牙广播自动识别。识别不到或识别错时可手动指定 —— 型号决定哪些功能可用（布防、清空密码、固件升级都以它为准）。")
            }
            Section {
                BusyButton(title: "完成添加", systemImage: "checkmark", isBusy: false, disabled: nickname.isEmpty) {
                    saveNaming()
                }
            } footer: {
                Text("添加成功后请立刻做一次全量备份, 并成功开一次锁完成「链路已验证」标记。")
            }
        }
        .variantList()
        .dsScreenBackground()
    }

    private func saveNaming() {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, var kc = pairedKC else { return }
        kc.name = name
        // 2026-10-29：手选了型号就以手选为准（0 = 自动，保留配网时从广播读到的 pid）
        if pidChoice != 0 {
            kc.pid = pidChoice
            kc.pidName = PidMap.names[pidChoice] ?? kc.pidName
        }
        DB.saveKeychain(kc)
        var meta = LockArchive.meta(kc.mac)
        meta.place = place.trimmingCharacters(in: .whitespaces)
        LockArchive.save(kc.mac, meta)
        app.loadDevices()
        app.select(kc.mac)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flow = .done
    }

    private var doneView: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DS.Icon.xl))
                    .foregroundStyle(DS.Palette.ok)
                    .accessibilityHidden(true)
                Text("添加成功")
                    .vkFont(.headline)
                    .foregroundStyle(DS.Palette.text)
                Text("已生成本机密钥并写入门锁。请立刻做一次全量备份, 钥匙串只存于本机。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // 258 首连验证引导: 添加完成 → 引导首次开锁跑通全链路
                Label("下一步: 到设备页成功开一次锁, 完成「链路已验证」标记", systemImage: "checkmark.seal")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("完成") { dismiss() }
                    .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
            .padding(DS.Space.l)
        }
    }

    // 2026-10-13 对抗式排查: 补 @MainActor。原写非隔离 async func —— 非隔离 async 被 @MainActor
    // 上下文 await 时函数体跑到全局执行器, 于是本函数里的 `scanning`(@State) 与
    // BLEService.shared.stopScan() 都在后台线程上跑, @State 后台写 = 运行期未定义。
    @MainActor
    private func scan() async {
        guard !scanning, flow == .scan else { return }
        scanning = true
        pairError = ""
        devices.removeAll()
        do {
            // allowDuplicates=true: iOS 对近期连过的设备默认回"缓存广播", 厂商数据可能为空,
            // 导致 parseAdv 失败。开启后每次广播包都带完整厂商段 (UI 按 deviceId 去重, 无副作用)。
            try await BLEService.shared.startScan(allowDuplicates: true, timeoutMs: 10000)
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline, !Task.isCancelled {
                // 251 发现列表: 全量展示 + 评分排序 + 信号强度排序,
                // 不在列表层硬过滤 resetStatus — 硬过滤会把"已配对未重置"的锁整个藏掉。
                devices = BLEService.shared.allDiscovered()
                    .map { d -> (dev: BLEAdvDevice, score: Int) in (d, scoreAdv(d)) }
                    .sorted { a, b in
                        // 2026-10-13 run 63: 原来是三重嵌套三元的一行比较, 加上上面的 map 闭包,
                        // 整个赋值表达式报 type-check 超时。拆成多行 if 更好读也更好算。
                        if a.score != b.score { return a.score > b.score }
                        if a.dev.rssi != b.dev.rssi { return a.dev.rssi > b.dev.rssi }
                        return a.dev.name < b.dev.name
                    }
                    .map { $0.dev }
                // 旧写法 `try?` 把 CancellationError 一起吞了 → 关页/切流程后循环照样跑到 10s 到点
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { break }
            }
        } catch {
            app.showToast(error.localizedDescription)
        }
        // 扫描必须收口: 本函数与 DFUKit:516 不同, 此前没有任何 stopScan 调用点,
        // allowDuplicates 扫描会在离页后继续回调与占radio (对照 BLEService 的 scanTimer 只在超时才停)。
        BLEService.shared.stopScan()
        scanning = false
    }

    /// 251 发现列表评分 (从 scan() 的 map 闭包里拆出: 闭包 + 三重嵌套三元的 sorted 一起报 type-check 超时)
    private func scoreAdv(_ d: BLEAdvDevice) -> Int {
        let adv = ZKProtocol.parseAdv(d.advertisHex)
        let svcHit = d.serviceUUIDs.contains {
            $0.uppercased().contains("6E400001") || $0.uppercased().contains("FE90")
        }
        let nameHit = d.name.range(of: "ZK|KX|JZ|JINGZAO|ZELKOVA|LOCK|SMART",
                                   options: [.regularExpression, .caseInsensitive]) != nil
        return (svcHit ? 2 : 0) + (nameHit ? 2 : 0) + (adv != nil ? 4 : 0)
    }

    private func pair(_ d: BLEAdvDevice, _ mac: String) async {
        guard flow == .scan else { return }
        flow = .pairing
        step = 1
        pairSteps.removeAll()
        pairError = ""
        do {
            let kc = try await LockService.shared.pair(deviceId: d.deviceId, mac: mac) { progress in
                pairSteps.append(progress)
                // 253: 配网 7 步链映射到四步进度的 校验(1-3 步)/初始化(4-7 步)
                if progress.hasPrefix("步骤") {
                    let numStr = progress.dropFirst(3).prefix(while: { $0.isNumber })
                    if let n = Int(numStr), n >= 4 { step = 2 }
                }
            }
            LockService.shared.disconnect()   // 配网会话即用即断; 命名保存后按需重连
            pairedKC = kc
            nickname = defaultName(for: kc)
            flow = .naming
            step = 3
        } catch {
            // 256 失败回滚: 清理半成品 (台账/指针/连接), 回到发现页并显示原因
            pairError = error.localizedDescription
        }
    }
    private var pairTargetMac: String { pairedKC?.mac ?? "" }

    private func defaultName(for kc: Keychain) -> String {
        let model = kc.pidName.isEmpty ? PidMap.productName(kc.pid) : kc.pidName
        // 同型号自动编号 (不含本锁): 第 2 把同型号锁命名为 "智能门锁 V1 · 2"
        let siblings = DB.keychains().filter { $0.pid == kc.pid && $0.mac != kc.mac }.count
        return siblings > 0 ? "\(model) · \(siblings + 1)" : model
    }
}