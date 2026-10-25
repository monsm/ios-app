// 功能页集合: 添加设备/配网 · 添加密码 · 录指纹 · 设备信息 · 固件 DFU · 钥匙串硬件 · 网关 · 成员 · 动态 · 备份
// 通用约定:
//   1) 破坏性/不可逆动作 (删记录、写硬件、升级固件) 一律先确认, 走全局 confirmDestructive 或 confirmationDialog;
//   2) 纯 VStack 页面套 ScrollView, 大字号下不溢出;
//   3) 装饰性图标 .accessibilityHidden(true), 状态不靠颜色单通道传达。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ================= 添加设备 (devicetypelist + adddevice + devicereset 合流) =================
// 包3 升级: 251 发现列表 (按信号排序/实时刷新) · 253 四步进度 (发现/校验/初始化/命名) ·
// 255 MAC 去重拦截 · 256 失败回滚 · 257 手输 MAC 兜底 · 258 首连验证引导 · 774 命名步带场所副标题
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
    @State private var manualMac = ""            // 257 手输 MAC 兜底
    @State private var locating = false
    @State private var dupMac: (name: String, mac: String)?   // 255 去重拦截
    @State private var probingId: String?        // APK 对照 page-romlist: 正在做连通探测的那一行

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
                        if flow == .pairing { rollback(reason: "") }   // 中途关闭也走清理
                        dismiss()
                    }
                }
            }
            // 255 重复绑定拦截: 不进配网流程, 直接给出跳转既有锁的出口
            .confirmationDialog("这把锁已经添加过", isPresented: Binding(get: { dupMac != nil },
                                                                       set: { if !$0 { dupMac = nil } }),
                                titleVisibility: .visible) {
                Button("跳转到已有锁") {
                    if let dup = dupMac {
                        app.loadDevices()
                        app.select(dup.mac)
                        app.requestRoute(.device)
                    }
                    dismiss()
                }
                Button("取消", role: .cancel) { }
            } message: {
                if let dup = dupMac {
                    Text("「\(dup.name)」(\(dup.mac)) 已在本机台账中, 无需重新配网。重新配网会换掉门锁密钥, 旧手机钥匙将失效。")
                }
            }
        }
    }

    private var scanView: some View {
        List {
            if !pairError.isEmpty {
                // 256: 回滚完成后错误必须可见, 不能无声吞掉
                // 829 (2026-10-11 拍板, D-150a 方案①): 失败面 = 页内常驻横幅 + 直达说明书症状树。
                // 排查内容不再在本页抄第四遍 —— 单一来源 = DiagKit.SymptomGuide.bleConnect (282 判断树),
                // 与 DFU 失败页 (142/1037) 同一先例: 横幅常驻, 出口就挂在横幅旁边, 不新造形状。
                Section {
                    Label {
                        Text(pairError).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    NavigationLink {
                        SymptomGuideView(initial: "bleConnect")
                    } label: {
                        Label("看三步排查", systemImage: "stethoscope")   // 829 看三步排查
                            .vkFont(.footnote)
                            .frame(minHeight: DS.Hit.min)
                    }
                } footer: {
                    Text("配不上先别反复重试: 点上面一步一问答, 结论只给下一步动作, 全程只在本机问答。")
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
                    deviceRow(d)
                }
            } header: {
                Text("发现的设备")
            } footer: {
                Text("长按任意一行可发一条免令牌明文回声，看这台设备答不答话 —— 它不改锁内任何东西，也不影响配对；点行本身仍是开始配对。")
            }
            // 257 手输 MAC 兜底: 扫不到时的手动定位 (服务换机场景)
            Section {
                TextField("锁的 MAC (如 AA:BB:CC:DD:EE:FF)", text: $manualMac)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await locateManual() } }
                Button {
                    Task { await locateManual() }
                } label: {
                    HStack(spacing: DS.Space.s) {
                        ProgressView().controlSize(.small).opacity(locating ? 1 : 0)
                        Text("按 MAC 定位门锁")
                    }
                    .frame(minHeight: DS.Hit.min)
                }
                .disabled(locating || manualMac.isEmpty)
            } header: {
                Text("扫不到? 手动定位")
            } footer: {
                Text("MAC 印在锁内面板或说明书上。定位到锁后仍需锁处于重置态才能配网。")
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

    private func deviceRow(_ d: BLEAdvDevice) -> some View {
        let adv = ZKProtocol.parseAdv(d.advertisHex)
        let inReset = (adv?.resetStatus ?? 0) == 1
        let isLock = adv.map { PidMap.isLock($0.pid) } ?? false
        let canPair = inReset && isLock
        // 续配入口 (2026-10-17 真机): 05 换钥回 rc=0 之后锁内 skey 已经是新的, 锁**不再广播重置位** ——
        // 而本机此时正好留着一份尾链没走完的记录 (pendingPair)。若这一行因为 !inReset 不可点, 用户
        // 就只剩"再跑一趟键盘重置"一条路, 而截图里那句"再点一次配网会接着配完"就成空头支票。
        // 判据是**本机有没有这份记录**, 不是锁的广播位。
        let pendMac = adv.flatMap { ZKProtocol.lockMac(fromAdv: $0) }
        let canResume = isLock && (pendMac.map { DB.pendingPair($0) != nil } ?? false)
        return Button {
            if canPair || canResume { confirmPair(d, adv) }
            else if adv == nil { app.showToast("广播未识别 — 非门锁设备, 或系统缓存了不完整广播") }
            else if !inReset { app.showToast("该锁不在重置态 — 请先做键盘物理重置") }
            else { app.showToast("未识别的设备型号") }
        } label: {
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.xs) {
                        Text(d.name)
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        // 251: 信号强度是"该先点哪把锁"的排序依据, 标出来
                        Text("\(d.rssi) dBm")
                            .vkFont(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Text("\(adv?.macDisplay ?? "—") · \(adv.map { PidMap.modelName($0.pid) } ?? "未知")")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        // 型号是判断"是不是我的锁"的关键信息, 不做 lineLimit(1) 截断
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if canResume {
                        Text("本机已留存密钥 — 点它接着配完, 不必再重置")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    } else if !inReset {
                        Text("需先在键盘上物理重置")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                }
                Spacer(minLength: DS.Space.s)
                if adv == nil {
                    StatusPill(text: "未识别", systemImage: "questionmark.circle", tone: .neutral)
                } else if canPair {
                    StatusPill(text: "可配网", systemImage: "checkmark.circle.fill", tone: .ok)
                } else if canResume {
                    StatusPill(text: "待续配", systemImage: "arrow.clockwise", tone: .warn)
                } else if !inReset {
                    StatusPill(text: "已配对", systemImage: "lock.fill", tone: .neutral)
                } else {
                    StatusPill(text: "非门锁", systemImage: "questionmark.circle", tone: .neutral)
                }
            }
            .frame(minHeight: DS.Hit.min)
            .contentShape(Rectangle()) // 整行可点
        }
        .accessibilityLabel("\(d.name)，\(d.rssi) dBm，\(canPair ? "可配网" : (adv == nil ? "未识别广播" : (canResume ? "待续配，本机已留存密钥" : "已配对，需先重置")))")
        // APK 对照 (page-romlist): 原版在扫描列表里先对每台设备发一次回声 (cmd12) 再进锁页。
        // 本机放在长按菜单里 —— 行本身就是"点它开始配对"的入口, 再塞一个按钮会把两件事做成同形。
        .contextMenu {
            Button {
                Task { await probeEcho(d) }
            } label: {
                Label(probingId == d.deviceId ? "正在探测…" : "连通探测",
                      systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(probingId != nil)
        }
    }

    // 写硬件类动作一律先确认: 配网会生成本机密钥并写入门锁, App 内无法撤销
    private func confirmPair(_ d: BLEAdvDevice, _ adv: ZKProtocol.AdvData?) {
        // MAC 一律取**显示序** (ZKProtocol.lockMac) —— 2026-10-17 真机: 这里原先用 adv.macRaw,
        // 而包络里还会 reversePairs 一次 ⇒ 锁收到的 0x88 TargetMAC 正好是反的, 05 之后的每一步
        // 都回 rc=12「mac地址不正确」(锁什么都没写, 只是拒绝), 且台账里会多一份永远对不上号的幽灵记录。
        guard flow == .scan, let adv, let mac = ZKProtocol.lockMac(fromAdv: adv) else { return }
        let display = adv.macDisplay ?? "—"
        // 255 MAC 去重拦截: 本地已有该锁 → 不进配网, 引导跳转
        if let existing = DB.keychain(mac) {
            dupMac = (LockArchive.displayName(existing), display)
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

    // 257 手输 MAC: 归一化 → 定向扫描 → 命中后走同一条配网链
    private func locateManual() async {
        let m = DB.normalizeMac(manualMac)
        guard m.count == 12, m.allSatisfy({ $0.isHexDigit }) else {
            app.showToast("MAC 需为 12 位十六进制 (冒号可省略)")
            return
        }
        guard !locating else { return }
        locating = true
        defer { locating = false }
        do {
            _ = try await LockService.shared.scanForMAC(m, timeoutMs: 8000)
            if let hit = BLEService.shared.allDiscovered().first(where: { d in
                guard let a = ZKProtocol.parseAdv(d.advertisHex), let raw = a.macRaw else { return false }
                return raw == m
            }) {
                let adv = ZKProtocol.parseAdv(hit.advertisHex)
                if adv?.resetStatus != 1 {
                    app.showToast("找到了, 但该锁不在重置态 — 请先长按 RESET 重置")
                } else {
                    confirmPair(hit, adv)
                }
            } else {
                app.showToast("已扫到信号但广播不完整, 请靠近门锁再试")
            }
        } catch {
            app.showToast("8 秒内未发现该 MAC — 请确认锁已通电并靠近手机")
        }
    }

    // APK 对照 page-romlist「固件列表」: 发一条免令牌明文回声, 看这台设备答不答话。
    // 不改锁内任何东西, 也不写本机台账 (读 03 状态会落快照/电量/固件观测三处); 不改配对状态。
    @MainActor
    private func probeEcho(_ d: BLEAdvDevice) async {
        guard probingId == nil else { return }
        probingId = d.deviceId
        defer { probingId = nil }
        do {
            let r = try await LockService.shared.probeEcho(deviceId: d.deviceId)
            if r.ok {
                let e = r.echoHex.isEmpty ? "无回显" : r.echoHex
                app.showToast("\(d.name) 回声往返 \(r.ms) ms · 回显 \(e)"
                             + (r.matched ? " (与发出值一致)" : " (与发出的 123456 不同 — 记下来, 不一定就是链路故障)"))
            } else {
                app.showToast("\(d.name) 回声 rc=\(r.rc): \(StatusParser.rcMessage(r.rc))")
            }
        } catch {
            app.showToast("探测失败: \(error.localizedDescription)")
        }
    }

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
            rollback(reason: error.localizedDescription)
        }
    }
    private func rollback(reason: String) {
        LockService.shared.disconnect()
        // pair 只在末步才写台账; 中途失败至多留 bleId 缓存/lastDevice 指针, 全部清掉
        if !pairTargetMac.isEmpty { DB.removeKeychain(pairTargetMac) }
        DB.lastDevice = ""
        pairSteps.removeAll()
        pairError = reason
        pairedKC = nil
        flow = .scan
        step = 0
    }
    private var pairTargetMac: String { pairedKC?.mac ?? "" }

    private func defaultName(for kc: Keychain) -> String {
        let model = kc.pidName.isEmpty ? PidMap.productName(kc.pid) : kc.pidName
        // 同型号自动编号 (不含本锁): 第 2 把同型号锁命名为 "智能门锁 V1 · 2"
        let siblings = DB.keychains().filter { $0.pid == kc.pid && $0.mac != kc.mac }.count
        return siblings > 0 ? "\(model) · \(siblings + 1)" : model
    }
}

// ================= 添加密码 (addpwd + 10 分钟临时码) =================
struct AddPwdView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 内容是否已嵌入外部导航容器。
    /// 默认 false: 现存调用点 (CredentialsView / DeviceHomeView) 全部是 NavigationLink push,
    /// 此时再包一层 NavigationStack 会出现双导航栏; 若改用 sheet 呈现请传 false 以自带导航栏。
    var embedded: Bool = false
    @State private var pwd = ""
    @State private var permanent = true
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var busy = false
    // 包6: 归属先选 (台账 owner) + 918 命名模板 (谁-哪里-何时 占位建议进备注)
    @State private var owner: String? = nil
    @State private var useTemplate = true

    private var pwdOK: Bool {
        pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber }
    }

    private var content: some View {
        Form {
            // 带 footer 的 Section 必须用 content/header/footer 三段式重载,
            // 不存在 Section("标题") { } footer: { } 这种写法
            Section {
                // 密码属敏感输入: 明文 TextField 会进系统文字替换/预测缓存, 截屏与旁观也可读
                // (对照本页网关口令 :1973 用 SecureField) → 统一 SecureField + 可见性切换由系统提供
                SecureField("密码 (6~8 位数字)", text: $pwd)
                    .keyboardType(.numberPad)
            } header: {
                Text("门锁密码")
            } footer: {
                // 说明放 footer: Section header 是小号灰字, 承载整句说明可读性差
                Text("给门锁添加密码后，成员就可通过在门锁键盘上输入该密码进行开锁。")
            }
            Section("有效期") {
                Picker("类型", selection: $permanent) {
                    Text("永久有效").tag(true)
                    Text("自定义").tag(false)
                }
                .pickerStyle(.segmented)
                if !permanent {
                    DatePicker("生效日期", selection: $fromDate, displayedComponents: .date)
                    DatePicker("到期日期", selection: $toDate, displayedComponents: .date)
                    // 359 到期待用
                    // 360 到期待用
                    Text("到期待用: 凭证页可开三档预警, 过期进「已过期」分组不消失。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("归属 (台账本地, 锁端无归属字段)") {
                Picker("归属成员", selection: $owner) {
                    Text("未归属").tag(nil as String?)
                    ForEach(DB.members()) { m in
                        Text(m.name).tag(m.id as String?)
                    }
                }
                .pickerStyle(.inline)
                // 2026-10-15 走查: 这一枚原先包在 `if useTemplate` 里 ⇒ 关掉它的那一按顺手把自己从屏上摘掉,
                // 想再打开只能退出这一页重进 (@State 回到默认 true)。自我隐藏的开关是"点了找不到"的一种:
                // 控制项要一直在那儿, 尤其是它默认开着、用户随时可能改主意的时候。
                VariantToggle("备注自动填命名模板 (谁-哪里-何时)", isOn: $useTemplate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                BusyButton(title: "添加密码", systemImage: "key.fill", isBusy: busy) {
                    Task { await submit(permanent: permanent) }
                }
                Button {
                    confirmTemp()
                } label: {
                    Text("下发 10 分钟临时密码")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.Hit.min)
                }
                .buttonStyle(SecondaryActionStyle())
                .disabled(busy)
            } footer: {
                Text("请将手机靠近门锁 · 添加成功后密码会登记到本机台账")
            }
        }
        .navigationTitle("添加密码")
        .variantList()
        .dsScreenBackground()
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(busy ? "写入中…" : "关闭") { dismiss() }.disabled(busy) } } .interactiveDismissDisabled(busy)   // 2026-10-15 走查: 写锁在飞时不给退出入口
    }

    var body: some View { vkBody.destined(.addPwd) }
    var vkBody: some View {
        // AnyView 擦平两分支类型差异: embedded 与否只在最外层容器上不同
        if embedded {
            AnyView(content)
        } else {
            AnyView(NavigationStack { content })
        }
    }

    /// 临时密码以明文下发且只存在于门锁 10 分钟, 属敏感且不可撤销的动作
    private func confirmTemp() {
        guard pwdOK else { app.showToast("请输入6~8位数字密码"); return }
        guard app.current != nil else { app.showToast("请先选择门锁"); return }
        confirmDestructive("下发临时密码",
                          // 2026-10-15 走查(第七批更正): 这句原文写「临时密码无法在 App 内提前作废」—— 假的。
                          // 密码列表里的单条删除与批量删除都走 `app.lock.pwdDelete(p.alias)`，两处都不排除 `p.temp`
                          // ⇒ 在 App 里删这条就是向锁端发删除，能提前收回。改成说清楚"锁端 10 分钟自己失效 + 要提前收回删这条"。
                          "将把密码「\(String(repeating: "·", count: pwd.count))」以明文下发给门锁「\(app.displayName)」，锁端 10 分钟后自动失效；要提前收回，就在密码列表里删除这条（会一并向锁端发删除）。确定下发吗？",
                          confirmTitle: "下发") {
            Task { await self.submitTemp() }
        }
    }

    private func submit(permanent: Bool) async {
        // 2026-10-15 走查: 没有选中锁时原先**静默 return**, 而同页另一条路径 ("请先选择门锁") 与
        // 钥匙串那页 ("请先配对门锁") 都会说一句话 —— 同一页两种收法, 用户看到的就是"按钮点了没反应"。
        // busy 那一半仍保持静默: 忙碌时按钮自己就写着"处理中…"并禁用。
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard !busy else { return }
        guard pwdOK else { app.showToast("请输入6~8位数字密码"); return }
        busy = true
        defer { busy = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let from = permanent ? "2010-01-01 00:00:00" : f.string(from: fromDate)
        let to = permanent ? "2118-01-01 00:00:00" : f.string(from: toDate)
        // 自定义区间必须 to 晚于 from: 两个日期选择器的默认值同为 Date(), 用户不改日期直接提交
        // 就会下发一条"当刻即过期"的密码, 而流程仍提示"添加成功" (锁端收下后立即失效, 无从察觉)
        if !permanent, toDate <= fromDate {
            app.showToast("失效时间需晚于生效时间")
            return
        }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
            var note = ""
            if useTemplate {
                // 918 命名模板 "谁-哪里-何时": 锁端无名称字段, 台账本地占位建议
                let who = owner.map { CredentialOrg.ownerName($0) } ?? "未归属"
                let when = permanent ? "长期" : (fromDate.formatted(.dateTime.month().day()) + "-" + toDate.formatted(.dateTime.month().day()))
                // 2026-10-15 走查: "哪里"取锁档案里的场所 (这一页上方就在写 meta.place)，不再写死"大门"；
                // 场所是空的就**省略这一段** —— 拼出一个用户没填过的位置，比少一段更假。
                let where_ = LockArchive.meta(kc.mac).place.trimmingCharacters(in: .whitespaces)
                note = who + (where_.isEmpty ? "-" : "-" + where_ + "-") + when
            }
            let rec = LedgerPwd(alias: alias, from: from, to: to, temp: false,
                                at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: note)
            DB.addPwd(kc.mac, rec)
            CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: rec, fp: nil, note: "新增")   // 487 首档快照
            app.showToast("添加成功 (别名 #\(alias))")
            dismiss()
        } catch {
            app.showToast("添加失败: \(error.localizedDescription)")
        }
    }

    private func submitTemp() async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 同 submit, 别再静默吞掉这一次点击
        guard !busy else { return }
        guard pwdOK else { app.showToast("请输入6~8位数字密码"); return }
        busy = true
        defer { busy = false }
        let from = Date()
        let to = from.addingTimeInterval(600) // 10 分钟
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: f.string(from: from), validTo: f.string(from: to))
            var note = ""
            if useTemplate {
                let who = owner.map { CredentialOrg.ownerName($0) } ?? "未归属"
                // 同上: 临时码这一支的"哪里"也取场所，不再写死。
                let where_ = LockArchive.meta(kc.mac).place.trimmingCharacters(in: .whitespaces)
                note = who + (where_.isEmpty ? "-" : "-" + where_ + "-") + "10分钟"
            }
            let rec = LedgerPwd(alias: alias, from: f.string(from: from), to: f.string(from: to), temp: true,
                                at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: owner, note: note)
            DB.addPwd(kc.mac, rec)
            CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: rec, fp: nil, note: "新增临时码")   // 487 首档
            app.showToast("临时密码已下发 (10 分钟有效)")
            dismiss()
        } catch {
            app.showToast("下发失败: \(error.localizedDescription)")
        }
    }
}

// ================= 录指纹 (startaddfp: cmd13 8 次按压 + cmd14 确认) =================
struct StartAddFpView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// 内容是否已嵌入外部导航容器。默认 false (现存调用点全是 NavigationLink push, 见 AddPwdView 同名参数)
    var embedded: Bool = false
    var prefillOwner: String? = nil   // 322 预填直达: 从"有 N 位成员还没有指纹"那枚链接带进来的归属
    @State private var presses: [LockService.FpPress] = []
    // 第八十九批: 录入这种"按钮起的长任务"要有句柄。原先是裸 `Task { await start() }` ——
    // 关页后 fpStart 仍会转满 30 秒，然后照样 fpConfirm、写台账、弹"已录入"，
    // 而用户早就走了 (这不是"多点一下"的问题，是后台替用户做了一次锁端写入)。
    @State private var enrollTask: Task<Void, Never>? = nil
    @State private var busy = false
    @State private var error = ""
    @State private var doneBatch: UInt32?
    /// 2026-10-17 用户口径: 录指纹**先选归属**。此前这一页直接开录, 记出来的指纹恒为"未归属",
    /// 事后只能到台账里一条条补 —— 而归属本来就是录入前就知道的事。
    @State private var owner: String? = nil

    private var content: some View {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                if doneBatch != nil {
                    VStack(spacing: DS.Space.l) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DS.Icon.xl))
                            .foregroundStyle(DS.Palette.ok)
                            .accessibilityHidden(true)
                        Text("添加成功")
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                        Text("请用新添加的指纹开一次锁, 确保指纹可用")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .multilineTextAlignment(.center)
                        Button("完成") { dismiss() }
                            .buttonStyle(PrimaryActionStyle(fullWidth: false))
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    VStack(spacing: DS.Space.xl) {
                        // 先选归属; 这把锁还没有成员时, 选择器会直接弹"新增归属"。
                        FpOwnerPicker(mac: app.current?.mac ?? "", owner: $owner)
                            .card()
                        ProgressView(value: Double(min(presses.count, 8)), total: 8)
                            .padding(.horizontal, DS.Space.gutter)
                            .accessibilityLabel("指纹录入进度")
                            .accessibilityValue("\(min(presses.count, 8)) / 8 次")
                        Text(progressText)
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                            .contentTransition(.opacity)
                            .animation(DS.Motion.soft, value: presses.count)
                        Text("最舒适的姿势，将手指按在门锁指纹头上，重复 8 次")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: DS.Space.s) {
                            ForEach(0..<8, id: \.self) { i in
                                Circle()
                                    .fill(i < presses.count ? DS.Palette.accent : DS.Palette.surfaceAlt)
                                    .overlay(Circle().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
                                    // 14pt 为刻意值: 8 个进度点需在窄屏一行排下, 刻意不入令牌
                                    .frame(width: 14, height: 14)
                            }
                        }
                        .animation(DS.Motion.standard, value: presses.count)
                        .accessibilityHidden(true)
                        if !error.isEmpty {
                            Label {
                                Text(error).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.danger)
                            .multilineTextAlignment(.center)
                        }
                        BusyButton(title: "开始录入", systemImage: "touchid", isBusy: busy,
                                   disabled: owner == nil) {
                            enrollTask = Task { await start() }
                        }
                        if owner == nil {
                            Text("先在上面选一位归属, 才开始录入")   // 317 先选归属
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.l)
        }
        .animation(DS.Motion.standard, value: doneBatch)
        .navigationTitle("录入指纹")
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
    }

    var body: some View { vkBody.destined(.startAddFp) }
    var vkBody: some View {
        // 原先两个分支各套一层 AnyView (只为绕过 if/else 的类型差)，这里换成 Group + @ViewBuilder，
        // 好把 .onDisappear 挂在**页面最外层** —— 挂在 content 上会因步骤切换误取消刚完成的流程。
        Group {
            if embedded {
                content
            } else {
                NavigationStack { content }
            }
        }
        .onAppear { if owner == nil { owner = prefillOwner } }   // 322 预填直达
        .onDisappear { enrollTask?.cancel() }
        // APK 对照 (StartaddfpPage.setKeepScreenOn): 录入期间不许自动锁屏 —— 用户手指按在锁上时
        // 屏一黑本进程就被挂起, 蓝牙录入链会在中途断掉, 而屏上还停在"重复此步骤 (n/8)"。
        .keepingScreenAwake(busy)
    }

    private var progressText: String {
        // 提示随次数走 (APK StartaddfpPage 同一做法: 第 4 下起改口"请将手指边缘按在指纹头上再抬起")。
        // 为什么必须换位置: 同一处连按 8 次, 锁会回 rc=23「无法获取有效的指纹图片」——
        // 那一下**不计数**, 于是屏上永远停在 6/8 附近, 最后锁的 15s 窗口一过就退出录入。
        switch presses.count {
        case 0: return "请将手指按在指纹头上再抬起"
        case 1...3: return "重复此步骤 (\(presses.count)/8) — 抬起后再按"
        case 4...6: return "第 \(presses.count + 1)/8 次: 把手指的边缘按上去, 换一个位置"
        default: return "第 \(presses.count + 1)/8 次: 再换一个角度"
        }
    }

    private func start() async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 同上, 静默 return 看着像按钮坏了
        guard let owner else { error = "请先选择归属再录入"; return }
        guard !busy else { return }
        busy = true
        error = ""
        // 重试必须清空: onPress 是**累加**式回填，不清就会出现"9/8"这种读数 (旧写法整批赋值天然不会)
        presses = []
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            // onPress 每来一帧就填一次: 旧写法要等整个 fpStart 返回才赋值，
            // 期间"重复此步骤 (0/8)"的进度文案恒停在 0/8 (§4 遗留项)
            // 窗口口径在 LockService.fpStart 里 (首帧 8s / 两次按压 16s, 对齐 APK Java 接收计时器)
            let ps = try await app.lock.fpStart(times: 8,
                                                onPress: { p in
                                                    self.presses.append(p)
                                                    // 手指在锁上时用户看不到屏幕: 每次按压给一声轻触感, 免得"按了像没按"
                                                    DS.Haptics.tick.impactOccurred()
                                                })
            self.presses = ps
            // 14 会把这一批指纹真正启用: 不满 8 次按压的批次不确认 (否则启用的是一枚残缺指纹)
            guard presses.count >= 8 else {
                throw NSError(domain: "fp", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "只收到 \(presses.count)/8 次按压, 未写入; 请重新录入并多按几次"])
            }
            guard let batch = presses.compactMap({ $0.batchNumber }).first, batch > 0 else {
                throw NSError(domain: "fp", code: 1, userInfo: [NSLocalizedDescriptionKey: "未拿到有效指纹批次, 请重新录入"])
            }
            // 第八十九批: 句柄取消后**不越过这个不可逆点**。fpConfirm 会真正把这批指纹启用并写本机台账；
            // 用户已经关页就走"按压已作废"的路径，不替他做锁端写入，也不弹"已录入"。
            if Task.isCancelled {
                presses = []
                return
            }
            try await app.lock.fpConfirm(batch, validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00")
            // 自动命名: 指纹N (取台账内最大编号 + 1)
            let existing = DB.listFps(kc.mac).compactMap { f -> Int? in
                guard let m = f.name.range(of: "指纹(\\d+)", options: .regularExpression) else { return nil }
                return Int(f.name[m].dropFirst(2))
            }
            let n = (existing.max() ?? 0) + 1
            DB.addFp(kc.mac, LedgerFp(batch: Int(batch), name: "指纹\(n)", at: Date().timeIntervalSince1970 * 1000,
                                      note: "", src: "app", owner: owner, isAlarm: false))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            doneBatch = UInt32(batch)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ================= 设备信息 (deviceinfo 页 → 包3/110 信息名片) =================
// 名片化: 型号/固件/MAC/绑定时间/验证标记/锁钟偏差一页看全 (110),
// 电量/存量带采样时间标注 (291), 容量水位读协议容量族 (773), 电池档案可记型号与换电日 (290)。
struct DeviceInfoView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var status: LockStatus?
    @State private var busy = false
    @State private var clockDrift: Int? = nil   // 47 锁钟偏差 (秒; nil = 未读到锁钟)

    var body: some View { vkBody.destined(.deviceInfo) }
    var vkBody: some View {
        NavigationStack {
            List {
                infoCardSection
                statusSection
                batterySection
                Section {
                    NavigationLink { LockProfileView() } label: {
                        Label("编辑锁档案 (符号/色标/备注)", systemImage: "pencil.and.outline")
                    }
                    BusyButton(title: "重新读取", systemImage: "arrow.clockwise", isBusy: busy) {
                        Task { await reload() }
                    }
                } footer: {
                    Text("静音模式可在设置页切换; 安全模式切换请在门锁键盘或联系管理员操作。")
                }
            }
            .navigationTitle("锁信息名片")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        }
        .task { await reload() }
    }

    private var kc: Keychain? { app.current }

    // 110 名片: 关于这把锁的静态身份信息
    private var infoCardSection: some View {
        Section {
            if let kc {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: LockArchive.symbolName(LockArchive.meta(kc.mac)))
                        .font(.system(size: DS.Icon.lg, weight: .medium))
                        .foregroundStyle(LockArchive.swatchColor(LockArchive.meta(kc.mac).colorKey))
                        .frame(width: DS.Hit.min, height: DS.Hit.min)
                        .background(DS.Palette.surfaceAlt, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(app.displayName)
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        // 774 场所副标题
                        Text(LockArchive.subtitle(kc))
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .accessibilityElement(children: .combine)
                LabeledRow("型号", PidMap.productName(kc.pid))
                LabeledRow("固件版本", firmwareText)
                // APK 对照 page-rominfo「固件信息」的 Boot版本 / 键盘版本 (03 状态 KLV#32 / KLV#33)。
                // 只在锁真报了这两支时才出现 —— 老固件不报时这里没有行, 那不是"读失败", 也不拿 0 冒充版本号。
                if let v = status?.verDFU, v > 0 { LabeledRow("Boot 版本", "\(v)") }
                if let v = status?.verKeyboard, v > 0 { LabeledRow("键盘版本", "\(v)") }
                LabeledRow("固件服役", fwAgeText)   // 1019
                LabeledRow("MAC", kc.mac)
                LabeledRow("绑定于", boundText)
                // 258 首连验证标记
                LabeledRow("链路验证", verifiedText)
                // 47 锁钟偏差指示 (Flighty 式): 校时与临时码有效性的第一判据
                LabeledRow("锁钟偏差", driftText)
            }
        } footer: {
            Text("锁钟偏差较大时临时密码与时间窗凭证会失效, 可到快捷操作「校准时间」。Boot / 键盘版本只在锁上报时出现，这两行缺失表示该固件不报这两支，不是读取失败。")
        }
    }

    // 运行状态: 数值旁标注采样时间 (291), 容量读协议容量族 (773)
    private var statusSection: some View {
        Section("运行状态") {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                LabeledRow("门锁电量", pctText)
                Text(sampleText)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                // 45 电量 sparkline: 采样 ≥2 个点画真走势; 不足时退回诚实占位文案 (不画假线不插值)
                let sp = battSamples
                if sp.count >= 2 {
                    BattSpark(samples: sp)
                    Text(battTrendCaption(sp))
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                } else {
                    Text(trendText)
                        .vkFont(.caption2)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .accessibilityElement(children: .combine)
            LabeledRow("安全模式", modeText)
            LabeledRow("锁内时间", status?.lockTime.map { ProtoTime.localStr($0) } ?? "—")
            capacityRow(title: "密码", used: pwdUsed, cap: pwdCap, stock: status?.pwdStock ?? app.snapshot?.pwdStock ?? -1)
            capacityRow(title: "指纹", used: fpUsed, cap: fpCap, stock: status?.fpStock ?? app.snapshot?.fpStock ?? -1)
        }
    }

    /// 45: 采样表就是 sparkline 的唯一数据源 (每次读 03 追加, 90 天截断)
    private var battSamples: [BattSample] { BatteryCare.samples(kc?.mac ?? "") }
    /// 45: 图下那行写全可核事实 —— 点数/跨度天数/最低最高, 不写"预计""续航"一类协议没有的词
    private func battTrendCaption(_ sp: [BattSample]) -> String {
        let lo = sp.map(\.pct).min() ?? 0
        let hi = sp.map(\.pct).max() ?? 0
        let days = sp.count >= 2 ? max(Int((sp[sp.count - 1].t - sp[0].t) / 86_400_000) + 1, 1) : 1
        return "电量走势: \(sp.count) 个采样点 · 跨 \(days) 天 · 最低 \(lo)% / 最高 \(hi)%"   // 45 电量走势
    }

    // 290 电池档案: 型号与换电日期 (表单可编辑, 纯本地台账)
    private var batterySection: some View {
        Section {
            Button { editBatteryModel() } label: {
                LabeledRow("电池型号", meta.batteryModel.isEmpty ? "点击记录" : meta.batteryModel)
            }
            .foregroundStyle(DS.Palette.text)
            Button { editBatteryDate() } label: {
                LabeledRow("上次换电", batteryDateText)
            }
            .foregroundStyle(DS.Palette.text)
            // 289 耗材备件提醒: 电量偏低时提示备一枚电池 (包4: 读数同 pctText 走采样)
            let p289 = BatteryCare.displayPct(kc?.mac ?? "",
                                              snapshot: status?.powerLevel ?? app.snapshot?.powerLevel ?? -1)
            if p289 >= 0, p289 <= 25 {
                Text("耗材提醒: 电量 \(p289)%, 建议备一枚\(meta.batteryModel.isEmpty ? "对应型号" : meta.batteryModel)电池。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink { MaintenanceView() } label: {
                Label("维护与保养 (周期/换电/提醒)", systemImage: "checklist")
                    .frame(minHeight: DS.Hit.min)
            }
        } header: {
            Text("电池档案")
        } footer: {
            Text("记录电池型号与换电日期, 换电池时心里有数 (仅本机台账, 不写入门锁)。")
        }
    }

    private var meta: LockMeta { LockArchive.meta(kc?.mac ?? "") }
    private var firmwareText: String {
        if let fw = status?.firmware, !fw.isEmpty { return fw }
        let fw = kc?.fw ?? ""
        return fw.isEmpty ? "未知" : fw
    }
    private var boundText: String {
        let raw = String((kc?.pairedAt ?? "").prefix(16)).replacingOccurrences(of: "T", with: " ")
        return raw.isEmpty ? "—" : raw
    }
    private var verifiedText: String {
        guard let kc else { return "—" }
        let t = LockArchive.meta(kc.mac).verifiedAt
        guard t > 0 else { return "待验证 (成功开一次锁即打标)" }
        return "已验证 · " + DateFormatter.localizedString(from: Date(timeIntervalSince1970: t),
                                                           dateStyle: .short, timeStyle: .short)
    }
    private var driftText: String {
        guard let d = clockDrift else { return "—" }
        if d == 0 { return "与手机一致" }
        return (d > 0 ? "+" : "") + "\(d) 秒"
    }
    private var batteryDateText: String {
        guard meta.batteryChangedAt > 0 else { return "点击记录" }
        return DateFormatter.localizedString(from: Date(timeIntervalSince1970: meta.batteryChangedAt),
                                             dateStyle: .medium, timeStyle: .none)
    }
    private var sampleText: String {
        // 291 采样时间: 快照与电量采样取最新
        let at = max(LockStats.snapAt(kc?.mac ?? ""), BatteryCare.latest(kc?.mac ?? "")?.t ?? 0)
        return at > 0 ? LockStats.sampleTimeText(at) : "尚未读取过快照"
    }
    /// 45: 电量趋势的诚实占位 — 采样埋点已开, 曲线等数据积累
    private var trendText: String {
        let n = BatteryCare.samples(kc?.mac ?? "").count
        return n == 0 ? "电量趋势: 尚无采样, 每次连接自动记录" : "电量趋势: 已积累 \(n) 个采样点, 曲线待数据更满"
    }
    /// 1019 固件服役天数 (从本机首次读到该版本起算)
    private var fwAgeText: String {
        guard let kc else { return "—" }
        var fw = kc.fw
        if let f = status?.firmware, !f.isEmpty { fw = f }
        guard let s = BatteryCare.fwSince(kc.mac, fw: fw) else { return "首次读到后起算" }
        let days = Int(Date().timeIntervalSince1970 * 1000 - s.at) / 86_400_000
        return days > 365 ? "\(days) 天 · 已超一年, 建议读读发行说明" : "\(days) 天"
    }

    /// 未读到时统一显示 "—", 不把 -1 当数值直接印给用户
    private func stockText(_ v: Int) -> String { v < 0 ? "—" : "\(v)" }
    // 773 容量水位: 优先锁侧真值 (容量-剩余), 容量未读时降级台账计数
    private var pwdUsed: Int {
        if let cap = app.snapshot?.pwdCap, cap > 0 { return max(cap - (status?.pwdStock ?? app.snapshot?.pwdStock ?? 0), 0) }
        return DB.ledger(kc?.mac ?? "").pwds.count
    }
    private var fpUsed: Int {
        if let cap = app.snapshot?.fpCap, cap > 0 { return max(cap - (status?.fpStock ?? app.snapshot?.fpStock ?? 0), 0) }
        return DB.ledger(kc?.mac ?? "").fps.count
    }
    private var pwdCap: Int? { app.snapshot?.pwdCap.flatMap { $0 > 0 ? $0 : nil } }
    private var fpCap: Int? { app.snapshot?.fpCap.flatMap { $0 > 0 ? $0 : nil } }

    @ViewBuilder
    private func capacityRow(title: String, used: Int, cap: Int?, stock: Int) -> some View {
        if let cap {
            LabeledRow("\(title)容量", "\(used) / \(cap)")
        } else {
            LabeledRow("\(title)存量", stockText(stock) + " · 容量未读")
        }
    }

    private var pctText: String {
        // 包4: 统一取采样最新值 (读 03 即记录), 快照兜底 — 未读到不印 -1
        let p = BatteryCare.displayPct(kc?.mac ?? "", snapshot: status?.powerLevel ?? app.snapshot?.powerLevel ?? -1)
        return p < 0 ? "—" : (p > 80 ? ">80%" : "\(p)%")
    }
    private var modeText: String {
        guard let s = status else { return "—" }
        return s.verifyMode == 0 ? "A模式" : "B模式"
    }

    private func reload() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            status = try await app.lock.getStatus()
            // 47: 状态读回瞬间锁钟与手机时钟的差 (协议秒基准换算)
            if let lt = status?.lockTime {
                clockDrift = Int(lt - ZKProtocol.nowProtoSeconds())
            }
            // APK 逻辑对齐 (2026-10-17 全量盘点): 原 APK 的 RominfoPage.ionViewDidLoad 里**进页就
            // `syncTime()`** (new St(En.getNowTimeString(), mac) → Dt → 0E), 本机此前只有手动入口。
            // 锁钟是所有有效期窗口 (0A/0B/14) 与临时码的判据 —— 进页自动对齐, 漂移 > 2s 才真写
            // (APK 无条件写; 我们只在真漂移时写, 终态一致: 锁钟 == 手机钟)。
            if let drift = clockDrift, abs(drift) > 2 {
                app.lock.log("info", "设备信息页自动校时 (偏差 \(drift)s, APK RominfoPage 进页同步口径)")
                if let res = try? await app.lock.syncTime() {
                    app.lock.log("info", "自动校时完成: 校前偏差 \(res.before)s, 校后偏差 \(res.after)s")
                    status = try await app.lock.getStatus()
                    if let lt = status?.lockTime { clockDrift = Int(lt - ZKProtocol.nowProtoSeconds()) }
                }
            }
        } catch { app.showToast(error.localizedDescription) }
    }

    // 290 编辑入口 (与 MembersView.prompt 同款 UIAlertController 表单)
    private func editBatteryModel() {
        let alert = UIAlertController(title: "电池型号", message: "如 CR123A × 2", preferredStyle: .alert)
        alert.addTextField { $0.text = meta.batteryModel; $0.placeholder = "型号" }
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            var m = meta; m.batteryModel = ""; LockArchive.save(kc?.mac ?? "", m)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            var m = meta; m.batteryModel = alert.textFields?.first?.text ?? ""
            LockArchive.save(kc?.mac ?? "", m)
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }
    private func editBatteryDate() {
        let alert = UIAlertController(title: "上次换电", message: "将把换电日期记为今天", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            var m = meta; m.batteryChangedAt = 0; LockArchive.save(kc?.mac ?? "", m)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "记为今天", style: .default) { _ in
            var m = meta; m.batteryChangedAt = Date().timeIntervalSince1970
            LockArchive.save(kc?.mac ?? "", m)
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }
}

// ---------- 45 电量 sparkline (Canvas 纯几何: 只连真采样点, 不插值不编造) ----------
/// Robinhood 式小图: 横轴 = 采样序号 (采样本身间隔不均, 序号制下每点等距, 不假装是等时采样),
/// 纵轴 = 本段 min/max 归一。精确读数由图下那行 (点数/跨度/最低/最高) 给出 —— 图形只管"一眼看趋势"。
private struct BattSpark: View {
    let samples: [BattSample]

    var body: some View {
        let pts = samples.map(\.pct)
        let lo = pts.min() ?? 0
        let hi = pts.max() ?? 0
        let span = max(hi - lo, 1)
        Canvas { ctx, size in
            let ih = max(size.height - 4, 1)
            func y(_ v: Int) -> CGFloat { 2 + ih - ih * CGFloat(v - lo) / CGFloat(span) }
            var path = Path()
            for (i, v) in pts.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(max(pts.count - 1, 1))
                if i == 0 { path.move(to: CGPoint(x: x, y: y(v))) }
                else { path.addLine(to: CGPoint(x: x, y: y(v))) }
            }
            ctx.stroke(path, with: .color(DS.Palette.accent), lineWidth: 1.5)
            // 末点 (最新值) 一个小实点: "线往哪走"与"现在在哪"是两个问题
            if let v = pts.last {
                let d: CGFloat = 5
                ctx.fill(Path(ellipseIn: CGRect(x: size.width - d / 2, y: y(v) - d / 2, width: d, height: d)),
                         with: .color(DS.Palette.accent))
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)   // 事实由下方 battTrendCaption 那行统一播报 (合成元素)
    }
}

// ================= 锁档案 (包3: 105 符号与色标 · 106 昵称+备注 · 774 场所副标题 · 290 电池档案) =================
struct LockProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var place = ""
    @State private var grp = ""      // 104/767 分组名 (与设备管理页同一字段)
    @State private var note = ""
    @State private var symbol = ""
    @State private var colorKey = ""
    @State private var batteryModel = ""
    @State private var batteryHasDate = false
    @State private var batteryDate = Date()
    @State private var loaded = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View { vkBody.destined(.lockProfile) }
    var vkBody: some View {
        Form {
            // 预览: 与 Hero 卡同构的身份行, 编辑即所见
            Section {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: symbol.isEmpty ? "lock.fill" : symbol)
                        .font(.system(size: DS.Icon.lg, weight: .medium))
                        .foregroundStyle(LockArchive.swatchColor(colorKey))
                        .frame(width: 52, height: 52)
                        .background(DS.Palette.surfaceAlt, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(trimmed.isEmpty ? "未命名" : trimmed)
                            .vkFont(.headline)
                            .foregroundStyle(DS.Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(place.trimmingCharacters(in: .whitespaces).isEmpty ? "未填场所" : place)
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("预览: \(trimmed.isEmpty ? "未命名" : trimmed)")
            } footer: {
                Text("符号与色标同步用于 Hero 卡、切换胶囊与记录行的时间线标签。")   // 105 符号与色标同步用于
            }
            Section("身份") {
                TextField("昵称 (如 婆婆家·入户门)", text: $name)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                // 920 安装位置字段 = 这一行 (原句的"玄关/车库"就是这里的占位例子)。
                // 它同时是 Hero 卡副标题与"全部锁总览"的行副标题; **Widget 那一半做不到** ——
                // 免费账号无 App Groups，组件读不到本机档案 (CONSTRAINTS ❌ 表)，所以那里只显示静态文案。
                TextField("场所副标题 (如 玄关 / 车库)", text: $place)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                // 104/767 分组名: 与"设备管理"页写的是同一个字段 (kf_lockmeta_.grp), 两处都能改、改完都生效。
                // 设备页上方会出现按组切换的胶囊; 建议名 (家用/仓库/办公) 在设备管理页的右键菜单里一键选。
                TextField("分组名 (如 家用 / 仓库 / 办公, 留空 = 未分组)", text: $grp)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                // 106 备注: 备忘录标题正文的双字段案
                TextField("备注 (换电历史/安装细节/门锁脾气…)", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                // 108 手动隐藏这把锁: 只影响设备 Tab 的横滑翻页与胶囊主列表。
                // 判据刻意与"沉睡 (超 30 天未连接)"分开 —— 隐藏是用户明确说过的，沉睡是推断出来的。
                VariantToggle("在翻页里隐藏这把锁", isOn: Binding(   // 108 在翻页里隐藏这把锁
                    get: { LockArchive.isHidden(app.currentMac) },
                    set: { LockArchive.setHidden(app.currentMac, $0) }))
                Text("隐藏后它退出左右横滑，只在切换胶囊的「已隐藏」区里可达；回到这里取消即恢复。\n"
                     + "这是本机的视图设置：不写门锁，也不影响凭证、日志与备份。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("符号") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 4),
                          spacing: DS.Space.s) {
                    ForEach(LockArchive.symbols) { s in
                        Button {
                            symbol = s.name
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            VStack(spacing: DS.Space.xxs) {
                                Image(systemName: s.name)
                                    .font(.system(size: DS.Icon.md, weight: .medium))
                                    .foregroundStyle(symbol == s.name ? DS.Palette.accentText : DS.Palette.textSub)
                                    .frame(width: 46, height: 46)
                                    .background(symbol == s.name ? DS.Palette.accentText.opacity(0.12) : DS.Palette.surfaceAlt,
                                                in: Circle())
                                Text(s.label)
                                    .vkFont(.caption2)
                                    .foregroundStyle(DS.Palette.textSub)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("符号 \(s.label)")
                        .accessibilityAddTraits(symbol == s.name ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
            Section("色标") {
                HStack(spacing: DS.Space.m) {
                    ForEach(LockArchive.swatches) { s in
                        Button {
                            colorKey = s.key
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Circle()
                                .fill(LockArchive.swatchColor(s.key))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if colorKey == s.key {
                                        Circle().strokeBorder(DS.Palette.text, lineWidth: 2)
                                    } else {
                                        Circle().strokeBorder(DS.Palette.hairline, lineWidth: 0.5)
                                    }
                                }
                                // 色块 34pt 视觉 + 44pt 命中区分离
                                .frame(width: DS.Hit.min, height: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("色标 \(s.name)")
                        .accessibilityAddTraits(colorKey == s.key ? [.isSelected] : [])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Section("电池档案") {
                TextField("电池型号 (如 CR123A × 2)", text: $batteryModel)
                VariantToggle("记录换电日期", isOn: $batteryHasDate)
                if batteryHasDate {
                    DatePicker("换电日期", selection: $batteryDate, displayedComponents: .date)
                }
            }
            Section {
                BusyButton(title: "保存档案", systemImage: "checkmark", isBusy: false, disabled: trimmed.isEmpty) {
                    save()
                }
            } footer: {
                Text("昵称不能为空。档案只存本机, 不写入门锁。")
            }
        }
        .navigationTitle("锁档案")
        .variantList()
        .dsScreenBackground()
        .onAppear {
            guard !loaded, let kc = app.current else { return }
            loaded = true
            name = kc.name
            let m = LockArchive.meta(kc.mac)
            place = m.place; note = m.note
            grp = m.grp
            symbol = m.symbol; colorKey = m.colorKey
            batteryModel = m.batteryModel
            batteryHasDate = m.batteryChangedAt > 0
            if m.batteryChangedAt > 0 { batteryDate = Date(timeIntervalSince1970: m.batteryChangedAt) }
        }
    }

    private func save() {
        let n = trimmed
        guard !n.isEmpty, let kc = app.current else { app.showToast("昵称不能为空"); return }
        var kc2 = kc
        kc2.name = n
        DB.saveKeychain(kc2)
        var m = LockArchive.meta(kc.mac)
        m.place = place.trimmingCharacters(in: .whitespaces)
        m.grp = LockArchive.normalizedGroup(grp)
        m.note = note
        m.symbol = symbol
        m.colorKey = colorKey
        m.batteryModel = batteryModel.trimmingCharacters(in: .whitespaces)
        m.batteryChangedAt = batteryHasDate ? batteryDate.timeIntervalSince1970 : 0
        LockArchive.save(kc.mac, m)
        app.loadDevices()
        app.showToast("档案已保存")
        dismiss()
    }
}

// ================= 固件更新 (checkfirmwareupdate: 导入 zip → cmd22 → Nordic DFU) =================
// 包4 全流程: 体检单+三勾 (137/1027/1035) → 版本并排 (143) → 三段进度+剩余时间 (138/139) →
// 141 断点续传的**替代** = 整包重传 (DFU 协议无续传定义, CAPABILITY §6): 下面三处就是替代方案本身
// —— 中断提示 (:1331) / 失败安抚页 (:1618) / 「重新升级 (整包重传)」按钮 (:1650)，
// 配合三段进度 (138/139) 压低重传成本。界面上不出现"续传/接着传"这种词。
// 禁退保护 (140) → 完成自动校验 (148) / 失败安抚页 (142/1037); 本地清单 (513/145) 与历史 (147)。
// DFUKit 为只读依赖 — 分段/速率/校验编排全部在视图层完成, 不改协议命令集。
struct FirmwareView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bleSvc = BLEService.shared
    @State private var fw: FirmwarePackage?
    @State private var showPicker = false
    @State private var running = false
    @State private var failed = false
    @State private var failReason = ""   // 2026-10-15 走查: 单锁失败原先只置 failed, 原因被丢掉 (队列那侧有逐把 note, 单锁反倒没有)
    @State private var showUpgradeConfirm = false
    @State private var showQueueConfirm = false   // 144 队列也要过同一道确认 (原先它直接开刷)
    @State private var stage = 0              // 138: 0 准备 / 1 传输 / 2 校验
    @State private var pct = 0.0
    @State private var remainText = ""        // 139 剩余时间
    @State private var tickBackup = false     // 1035 已生成升级前备份
    @State private var tickTime = false       // 1027 时间充足
    @State private var showLeave = false      // 140 禁退确认
    @State private var verifyText = ""        // 148
    @State private var verified = false
    // 139 速率估算状态 (%/秒, EMA 平滑)
    @State private var lastProg: (pct: Double, at: TimeInterval)? = nil
    @State private var rate: Double = 0

    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    private func sizeText(_ n: Int) -> String { Self.bytes.string(fromByteCount: Int64(n)) }

    private var mac: String { app.current?.mac ?? "" }
    private var curFw: String {
        let live = app.current?.fw ?? ""
        return live.isEmpty ? (app.snapshot?.firmware ?? "") : live
    }
    // 137/1027 体检单: 电量与蓝牙自动判定, 备份/时间两项由用户勾选确认
    private var battPct: Int {
        if let s = BatteryCare.latest(mac)?.pct, s >= 0 { return s }
        return app.snapshot?.powerLevel ?? -1
    }
    private var battOk: Bool { battPct > 30 }
    private var checklistOk: Bool { battOk && bleSvc.isPoweredOn && tickBackup && tickTime }
    private var lastBackupText: String {
        let hist = DB.store.get([Double].self, "kf_backup_hist") ?? []
        guard let last = hist.last else { return "从未备份" }
        let d = Int(Date().timeIntervalSince1970 * 1000 - last) / 86_400_000
        return d <= 0 ? "今天备过" : "\(d) 天前"
    }
    /// 143 版本并排结论
    private var compareTag: (text: String, tone: ToneColor)? {
        guard let v = fw?.version else { return nil }
        if curFw.isEmpty { return ("可选升级", .neutral) }
        if FirmwareKit.versionLt(curFw, v) { return ("推荐升级", .ok) }
        if FirmwareKit.versionLt(v, curFw) { return ("低于当前版本", .warn) }
        return ("与当前版本相同", .neutral)
    }

    /// 内容是否已经嵌在外部导航容器里。2026-10-15 走查 §7.4-16: 本页自带 NavigationStack, 而设备页快捷格
    /// 的 `quickDestination` 是 **push** 进来它的 (外面那层栏已经在) ⇒ 不传 true 就叠出两层导航栏。
    /// 形状照同文件上方 `AddPwdView` / `StartAddFpView` 的 embedded 抄 —— 作者已有的解法, 不另造第三套。
    var embedded: Bool = false

    @ViewBuilder
    private var content: some View {
            List {
                if running {
                    progressSection       // 138/139/140
                } else if failed {
                    failureSection        // 142/1037
                } else {
                    currentSection
                    firstGlanceSection    // 825 首检一眼 (版本三处真相摊开)
                    if fw != nil { compareSection }   // 143
                    noticeSection
                    packageSection        // 513/145
                    preflightSection      // 137/1027/1035
                    resultSection         // 148
                    historySection        // 147
                }
            }
            .navigationTitle("检查固件更新")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if running {
                        // 140 禁退保护: 升级中点关闭需二次确认
                        Button("升级中…") { showLeave = true }
                            .foregroundStyle(DS.Palette.warn)
                            .accessibilityLabel("升级进行中, 点按可确认离开")
                    } else {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            // 140 禁退保护: 升级中禁用下滑手势关闭
            .interactiveDismissDisabled(running)
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [UTType.zip], allowsMultipleSelection: false) {
                importZip($0)
            }
            .confirmationDialog("升级门锁固件", isPresented: $showUpgradeConfirm, titleVisibility: .visible) {
                Button("开始升级", role: .destructive) { Task { await upgrade() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("升级过程门锁会重启并进入 DFU 模式，期间无法开门。若中途失败必须重新升级直到成功。")
            }
            // 144 队列与单锁同一道确认 (形状逐字照抄上面那段): 一次点下去要刷 N 把, 更该先问一句
            .confirmationDialog("排队逐把升级", isPresented: $showQueueConfirm, titleVisibility: .visible) {
                Button("开始升级 \(queueSel.count) 把", role: .destructive) { Task { await runQueue() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("每把都会重启并进入 DFU 模式，期间无法开门；一把失败不中断其余各把。上面那张体检单是按单把估的电量与时间，\(queueSel.count) 把请把这个时长乘以 \(queueSel.count)。")
            }
            .confirmationDialog("升级进行中", isPresented: $showLeave, titleVisibility: .visible) {
                Button("继续等待", role: .cancel) { }
                Button("仍要离开 (传输会中断)", role: .destructive) { DFURunner.cancelActive(); dismiss() }
            } message: {
                Text("固件传输中断后没有断点续传, 需要整包重传。建议等传输结束后再离开。")
            }
    }

    var body: some View { vkBody.destined(.firmware) }
    var vkBody: some View {
        // AnyView 擦平两分支类型差异 (与 AddPwdView 同一写法): 两支只差最外层那一只容器
        let base = embedded ? AnyView(content) : AnyView(NavigationStack { content })
        // APK 对照 (CheckfirmwareupdatePage.setKeepScreenOn): 传输/校验期间不许自动锁屏 ——
        // 屏一黑本进程就被系统挂起, DFU 的 32 字节分包写会当场断掉, 而屏上还停在"正在传输"。
        return base.keepingScreenAwake(running)
    }

    // ---------- 当前固件 (1019 服役天数) ----------
    private var currentSection: some View {
        Section("当前固件") {
            LabeledRow("门锁", app.displayName)
            LabeledRow("锁内版本", curFw.isEmpty ? "未知" : "v" + curFw)
            LabeledRow("固件服役", fwAgeText)
        }
    }
    /// 1019: 从本机首次读到该版本起算 (诚实口径), 超一年提示看说明
    private var fwAgeText: String {
        guard let s = BatteryCare.fwSince(mac, fw: curFw) else { return "首次读到后起算" }
        let days = Int(Date().timeIntervalSince1970 * 1000 - s.at) / 86_400_000
        return days > 365 ? "\(days) 天 · 已超一年, 建议读读发行说明" : "\(days) 天"
    }

    // ---------- 143 版本并排对比 ----------
    private var compareSection: some View {
        let tag = compareTag
        return Section {
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("当前")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(curFw.isEmpty ? "未知" : "v" + curFw)
                        .vkFont(.subheadline, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSub)
                    .accessibilityHidden(true)
                VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                    Text("目标")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                    Text(fw?.version.map { "v" + $0 } ?? "未知")
                        .vkFont(.subheadline, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前版本 \(curFw.isEmpty ? "未知" : curFw), 目标版本 \(fw?.version ?? "未知")")
            if let tag {
                StatusPill(text: tag.text,
                           systemImage: tag.tone == .ok ? "checkmark.seal" : (tag.tone == .warn ? "exclamationmark.triangle" : "info.circle"),
                           tone: tag.tone)
            }
        } header: {
            Text("版本对比")
        }
    }

    // ---------- 升级须知 + 1036 已知问题清单 ----------
    private var noticeSection: some View {
        Section("升级须知") {
            Text("• 更新过程中请不要使用门锁\n• 手机与门锁距离保持在 1 米内\n• 更新失败必须重新更新，直到更新成功")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("已知问题与规避") {
                Text("• 升级后门锁重启, 时间窗凭证失效 — 校准时间即可恢复\n• 升级中门锁广播名变为 ZkDFU、MAC 尾字节 +1, 属正常现象\n• 电量低于 30% 时升级失败率高, 体检单会拦截")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .vkFont(.footnote)
        }
    }

    // ---------- 825 固件首检引导 (Apple Support 那一形态) ----------
    // 创意原句两半：「首次进入显示当前版本占位」+「比对出厂版本清单按钮」。两半分开处理：
    //  · 占位这一半是真做得到的 —— 读不到当前版本时明写"没读到"，并说清为什么 (没连过锁 = 没发过 03 状态查询)。
    //  · 「出厂版本清单」**本机没有这张表**：全仓版本真相只有三处 —— 锁侧 03 快照回的 firmware 字段、
    //    本机每次读到过的版本历史 (FirmwareHistory)、导入过的包名 (kf_fwlib)。所以这里把这三处一次摊开，
    //    而不是凭空造一张厂商对照表：点进去只有一句假话的那种按钮，本仓宁可不放。
    @ViewBuilder
    private var firstGlanceSection: some View {
        let obs = FirmwareHistory.observations(mac: mac)
        let lib = BatteryCare.fwlib
        Section {
            LabeledRow("锁上读到的版本", curFw.isEmpty ? "没读到 · 先连一次锁" : curFw)
            LabeledRow("本机读到过的版本",
                       obs.isEmpty ? "还没有观测记录"
                       : obs.prefix(3).map { $0.fw + "(" + $0.day + ")" }.joined(separator: " · "))
            LabeledRow("导入过的固件包",
                       lib.isEmpty ? "本机还没有包" : "\(lib.count) 个 · 最近 \(lib.first?.version ?? "未知")")
        } header: {
            Text("进这一页先对一眼")   // 825 进这一页先对一眼
        } footer: {
            Text("没有「出厂版本对照表」可点：厂商云已停服，本机只有上面这三处版本真相。"   // 513/145 没有
                 + "要升级就带自己的包来，比对以锁上读到的那一个为准。")
                .vkFont(.caption2)
        }
    }

    // ---------- 513/145 固件更新包 + 本地清单 ----------
    private var packageSection: some View {
        let lib = BatteryCare.fwlib
        return Section {
            if fw == nil {
                EmptyState(systemImage: "shippingbox",
                           title: "尚未选择固件包",
                           message: "导入厂商提供的 .zip 更新包后即可开始升级。",
                           actionTitle: "选择固件包") { showPicker = true }
            } else {
                Button("选择固件更新包 (.zip)") { showPicker = true }
                    .frame(minHeight: DS.Hit.min)
                if let fw {
                    LabeledRow("包版本", fw.version ?? "未知")
                    LabeledRow("固件", "\(sizeText(fw.binSize)) + init \(sizeText(fw.datSize))")
                    LabeledRow("来源", fw.sourceName)
                }
            }
            // 513/145: 厂商云停服后唯一来源是本机文件 — 清单列明"无网络可执行"的范围
            if !lib.isEmpty {
                DisclosureGroup("本地固件包清单 (\(lib.count))") {
                    ForEach(lib) { item in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(item.name)
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("v\(item.version) · \(sizeText(item.size)) · \(dateShort(item.at))")
                                .vkFont(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .vkFont(.footnote)
            }
        } header: {
            Text("固件更新包")
        } footer: {
            if !lib.isEmpty {
                Text("清单只记出处, 升级时仍需重新选择文件 (包体不落库)。")
            }
        }
    }

    // ---------- 137/1027/1035 升级前体检单 ----------
    private var preflightSection: some View {
        Section {
            checkRow(icon: "battery.50percent", ok: battOk,
                     title: "锁电量 > 30%",
                     detail: battPct < 0 ? "未读到电量 — 请先连接门锁刷新" : "当前 \(battPct)%")
            checkRow(icon: "antenna.radiowaves.left.and.right", ok: bleSvc.isPoweredOn,
                     title: "手机蓝牙已开启",
                     detail: bleSvc.isPoweredOn ? "蓝牙正常" : "请打开系统蓝牙")
            Button { tickBackup.toggle() } label: {
                checkRow(icon: "externaldrive.badge.checkmark", ok: tickBackup,
                         title: "已生成升级前备份",   // 1035
                         detail: "上次备份 \(lastBackupText) · 生成入口在 设置-备份与恢复")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("已生成升级前备份")
            .accessibilityAddTraits(tickBackup ? [.isSelected] : [])
            Button { tickTime.toggle() } label: {
                checkRow(icon: "clock", ok: tickTime,
                         title: "时间充足 (约 10 分钟)",   // 1027
                         detail: "传输 + 重启 + 校验, 全程请守在门边")
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("时间充足")
            .accessibilityAddTraits(tickTime ? [.isSelected] : [])
            // 144 批量排队升级: 同型号的多把锁勾选后**逐把串行**升级 (DFU 期间手机与锁都是独占态,
            // 并行既抢 BLE 又抢 bootloader 会话); 队列只做外层编排, 单锁那条链一字未改。
            let peers = app.devices.filter { $0.pid == app.current?.pid && $0.mac != app.current?.mac }
            if !peers.isEmpty {
                Section("批量排队升级") {   // 144 批量排队升级
                    ForEach(peers, id: \.mac) { kc in
                        VariantToggle(LockArchive.displayName(kc), isOn: Binding(
                            get: { queueSel.contains(kc.mac) },
                            set: { on in if on { queueSel.insert(kc.mac) } else { queueSel.remove(kc.mac) } }))
                            .frame(minHeight: DS.Hit.min)
                    }
                    if !queueSel.isEmpty {
                        BusyButton(title: "排队逐把升级 (\(queueSel.count) 把)",
                                   systemImage: "square.stack.3d.up", isBusy: running,
                                   disabled: fw == nil || !checklistOk) {
                            // 2026-10-15 走查: 这颗原先既不查体检单也不弹确认, 一点就直接开刷 N 把 ——
                            // 而下面单锁那颗两样都有 (1442 那张 confirmationDialog)。DFU 是不可逆动作
                            // (锁重启进 bootloader、期间不能开门、断了只能整包重传), 门槛按"几把"分叉
                            // 是反着的: 一次点击覆盖的锁越多, 该问的那一句越不能省。
                            // 如实写下这一道闸**没覆盖到**的: checklistOk 里的电量/时间两项都是按
                            // app.current 那一把估的 (battOk 读当前锁), 队列里其余各把的电量这页读不到
                            // —— 逐把连一次再决定要等一次真机窗口, 不在这里假装已经做了。
                            showQueueConfirm = true
                        }
                    }
                    if !queueNote.isEmpty {
                        Text(queueNote).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(queueOutcomes.enumerated()), id: \.offset) { _, o in
                        Text((o.ok ? "✓ " : "✗ ") + o.name + " · " + o.note)
                            .vkFont(.caption2)
                            .foregroundStyle(o.ok ? DS.Palette.ok : DS.Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("同型号锁才可共用同一个固件包; 队列一把失败不中断, 结果逐把列出。")
                        .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            BusyButton(title: "开始升级",
                       systemImage: "arrow.down.circle.fill",
                       isBusy: false,
                       disabled: fw == nil || !checklistOk) {
                showUpgradeConfirm = true
            }
        } header: {
            Text("升级前体检")
        } footer: {
            Text("体检单全绿才能开始 — 电量与蓝牙自动判定, 备份与时间两项由你确认。协议里没有门磁状态位 (CAPABILITY §5)，门开没开只能你自己看，原案的「门已关」这一项本机做不了。请在门锁敞开时进行更新。")
        }
    }
    private func checkRow(icon: String, ok: Bool, title: String, detail: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DS.Icon.sm, weight: .semibold))
                .foregroundStyle(ok ? DS.Palette.ok : DS.Palette.textSub)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.text)
                Text(detail)
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Hit.min)
        .accessibilityElement(children: .combine)
    }

    // ---------- 138/139/140 升级中 ----------
    private var progressSection: some View {
        Section("升级中") {
            HStack(spacing: DS.Space.xs) {
                stageSeg("准备", 0)
                stageSeg("传输", 1)
                stageSeg("校验", 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("升级阶段: \(stage == 0 ? "准备" : stage == 1 ? "传输" : "校验")")
            ProgressView(value: min(pct, 100), total: 100)
                .accessibilityLabel("传输进度 \(Int(pct))%")
            HStack(spacing: DS.Space.s) {
                Text("\(Int(pct))%")
                    .vkFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Palette.textSub)
                Spacer(minLength: DS.Space.s)
                if !remainText.isEmpty {
                    Text(remainText)
                        .vkFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DS.Palette.accentText)
                }
            }
            if !verifyText.isEmpty {
                Text(verifyText)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("升级中请勿离开本页、请勿使用门锁", systemImage: "lock.shield")
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func stageSeg(_ label: String, _ i: Int) -> some View {
        let tone: ToneColor = stage > i ? .ok : (stage == i ? .accent : .neutral)
        return HStack(spacing: DS.Space.xxs) {
            Circle().fill(tone.color).frame(width: 8, height: 8)
            Text(label)
                .vkFont(.caption)
                .foregroundStyle(stage >= i ? DS.Palette.text : DS.Palette.textSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xs)
        .variantPlate(DS.Palette.surfaceAlt, .capsule)
    }

    // ---------- 148 结果 ----------
    @ViewBuilder
    private var resultSection: some View {
        if !verifyText.isEmpty {
            Section("升级结果") {
                Label {
                    Text(verifyText).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: verified ? "checkmark.circle.fill" : "questionmark.circle")
                        .accessibilityHidden(true)
                }
                .vkFont(.footnote)
                .foregroundStyle(verified ? DS.Palette.ok : DS.Palette.textSub)
            }
        }
    }

    // ---------- 147 升级历史 ----------
    @ViewBuilder
    private var historySection: some View {
        let hist = BatteryCare.dfuHist
        if !hist.isEmpty {
            Section("升级历史") {
                ForEach(hist) { r in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.system(size: DS.Icon.sm))
                            .foregroundStyle(r.ok ? DS.Palette.ok : DS.Palette.danger)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("\(r.name) · \(r.ok ? "成功" : "失败")")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(fromToText(r) + " · " + dateShort(r.at)
                                 + (r.ms.map { " · 耗时 " + Self.durText($0) } ?? ""))
                                .vkFont(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func fromToText(_ r: DFURecord) -> String {
        let f = r.from.isEmpty ? "?" : r.from
        let t = r.to.isEmpty ? "?" : r.to
        return "v\(f) → v\(t)"
    }
    /// 147 耗时文案: <60 秒报秒, 否则分+秒; 旧记录没这个字段就整段不显示 (r.ms == nil)
    private static func durText(_ ms: Double) -> String {
        // 2026-10-14: 旧写法先四舍五入再判单位 => "60 秒" / "1 分 60 秒" 非法读数 (59.6s / 119.6s)。
        // 先取整成总秒数, 再拆分。
        let s = Int((ms / 1000).rounded())
        if s < 60 { return "\(s) 秒" }
        return "\(s / 60) 分 \(s % 60) 秒"
    }

    // ---------- 142/1037 失败安抚页 ----------
    @ViewBuilder
    private var failureSection: some View {
        Section("升级失败") {
            // 2026-10-15 走查: 失败原因原先被丢掉 —— catch 里只置 failed, 这一屏只剩四条通用排查;
            // 同一条 DFU 链的队列版 (queueOutcomes) 每条都带 note, 单锁反倒不说。补上实际那一句。
            if !failReason.isEmpty {
                Label("本次失败: " + failReason, systemImage: "xmark.octagon")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label("门锁没有损坏", systemImage: "lock.shield")
                    .vkFont(.headline)
                    .foregroundStyle(DS.Palette.text)
                Text("传输中断后没有断点续传, 重新执行一次完整升级即可。若门锁仍显示 DFU 或白灯, 属升级模式的正常表现, 重传成功后会自动恢复。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Label("锁电量是否 > 30% — 低电是升级失败首因", systemImage: "1.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Label("与门锁距离是否在 1 米内", systemImage: "2.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Label("手机蓝牙是否被其他连接占用", systemImage: "3.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Label("等 1 分钟让门锁退出升级模式, 再重试", systemImage: "4.circle")
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            BusyButton(title: "重新升级 (整包重传)",
                       systemImage: "arrow.clockwise",
                       isBusy: false,
                       disabled: !checklistOk) {
                showUpgradeConfirm = true
            }
            Button {
                failed = false
                showPicker = true
            } label: {
                Label("重新选择固件包", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
            }
            .buttonStyle(SecondaryActionStyle())
            Button("返回正常使用") { dismiss() }
                .buttonStyle(SecondaryActionStyle())
        }
    }

    // ---------- 动作 ----------
    private func importZip(_ result: Result<[URL], Error>) {
        guard running == false, let url = try? result.get().first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try FirmwareKit.parse(zipData: [UInt8](data), fileName: url.lastPathComponent)
            fw = parsed
            failed = false
            verified = false
            verifyText = ""
            BatteryCare.addFWLib(name: url.lastPathComponent, version: parsed.version, size: data.count)   // 513/145
            app.showToast("固件包已解析" + (parsed.version.map { " · v\($0)" } ?? ""))
        } catch {
            app.showToast("固件包无法识别: \(error.localizedDescription)")
        }
    }

    // 144 批量排队升级的状态
    @State private var queueSel: Set<String> = []
    @State private var queueNote = ""
    @State private var queueOutcomes: [DFURunner.QueueOutcome] = []

    /// 144: 排队逐把升级 (同型号锁共用同一个固件包; 串行, 一把失败不中断)
    private func runQueue() async {
        guard let fw, !running, !queueSel.isEmpty else { return }
        running = true
        queueOutcomes = []
        queueNote = ""
        defer { running = false }
        // 2026-10-15 走查: 队列原先只跑传输 —— 既不写 147 升级历史, 也不做 148 版本复核回写,
        // 而单锁那条链 (upgrade()) 两样都有。少后一样的后果不是"台账少一行"这么轻: 刷成功的锁
        // 在台账里固件版本仍是旧值, 下次选中它打开这一页就判成"低于当前版本 / 推荐升级"。
        let targets = app.devices.filter { queueSel.contains($0.mac) }.sorted { $0.mac < $1.mac }
        guard !targets.isEmpty else { queueNote = "队列里选的那些锁已经不在了"; return }
        // onStep 只给序号与显示名、不给 mac; runUpgradeQueue 串行且每把恰好 append 一条 outcome,
        // 所以 outcomes[i] 与 targets[i] 同下标 (下面用 zip 走, 不靠下标硬取)。起点按下标记,
        // 用来算每一把自己那一刻的 at 与 ms —— 串行意味着"下一把的起点"就是"这一把的终点"。
        var startAt: [Int: Double] = [:]
        let outcomes = await DFURunner.runUpgradeQueue(
            lock: app.lock, macs: targets.map { $0.mac }, firmware: fw,
            onStep: { i, n, name in
                startAt[i - 1] = Date().timeIntervalSince1970
                queueNote = "第 \(i)/\(n) 把: \(name)"
            },
            onProgress: { p in
                switch p {
                case .switchingDfu, .connecting: stage = 0
                case .starting: stage = 1
                case .uploading(let v):
                    stage = 1
                    updateRate(Double(v))
                case .validating: stage = 2
                case .completed: stage = 2; pct = 100
                default: break
                }
            })
        queueOutcomes = outcomes
        let endAt = Date().timeIntervalSince1970
        var ok = 0
        for (i, pair) in zip(outcomes, targets).enumerated() {
            let (o, kc) = pair
            let t0 = startAt[i] ?? endAt
            let t1 = i + 1 < outcomes.count ? (startAt[i + 1] ?? endAt) : endAt
            if o.ok { ok += 1 }
            // name 取固件包名、at 取毫秒、ok=false 也照样记一笔 —— 三条都与单锁那段同口径,
            // 两处各写一套迟早对不上 (本仓 §10 反复实撞过这一族)。
            BatteryCare.addDFURecord(DFURecord(mac: o.mac, name: fw.sourceName,
                                               from: kc.fw, to: fw.version ?? "",
                                               at: t0 * 1000, ok: o.ok,
                                               ms: max(0, t1 - t0) * 1000))
        }
        queueNote = "队列结束: 成功 \(ok) / 共 \(outcomes.count) 把"
        if ok == outcomes.count { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        // 148: 逐把复核, 沿用单锁那段的同一判据 —— 只有真读回版本且与包版本一致才回写台账。
        // verifyText 是单锁的显示位, 跑完这里留的是最后一把的复核结论; 上面那行队列汇总不受它影响。
        for pair in zip(outcomes, targets) where pair.0.ok {
            await verifyAfterUpgrade(pair.1, fw)
        }
    }

    private func upgrade() async {
        guard let fw, let kc = app.current, !running else { return }
        running = true
        failed = false
        failReason = ""
        verified = false
        verifyText = ""
        stage = 0
        pct = 0
        remainText = ""
        rate = 0
        lastProg = nil
        defer { running = false }
        let startedAt = Date().timeIntervalSince1970   // 147 计时起点: 连接 + 升级 + 校验全算进去
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await DFURunner.runUpgrade(lock: app.lock, mac: kc.mac, pid: kc.pid, firmware: fw) { p in
                // 138 三段进度: DFUKit 进度枚举 → 准备/传输/校验 (视图层映射, 不改 DFUKit)
                switch p {
                case .switchingDfu, .connecting: stage = 0
                case .starting: stage = 1
                case .uploading(let v):
                    stage = 1
                    updateRate(Double(v))
                case .validating: stage = 2
                case .completed: stage = 2; pct = 100
                default: break
                }
            }
            BatteryCare.addDFURecord(DFURecord(mac: kc.mac, name: fw.sourceName,
                                               from: curFw, to: fw.version ?? "",
                                               at: Date().timeIntervalSince1970 * 1000, ok: true,
                                               ms: (Date().timeIntervalSince1970 - startedAt) * 1000))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await verifyAfterUpgrade(kc, fw)   // 148
        } catch {
            failed = true
            failReason = error.localizedDescription
            BatteryCare.addDFURecord(DFURecord(mac: kc.mac, name: fw.sourceName,
                                               from: curFw, to: fw.version ?? "",
                                               at: Date().timeIntervalSince1970 * 1000, ok: false,
                                               ms: (Date().timeIntervalSince1970 - startedAt) * 1000))
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// 139 剩余时间: 传输速率 EMA (只估传输段 — 校验段通常 <10 秒, 不值得估)
    private func updateRate(_ v: Double) {
        pct = v
        let now = Date().timeIntervalSince1970
        defer { lastProg = (v, now) }
        guard let last = lastProg, v > last.pct else { return }
        // 单位口径：秒 —— `lastProg` 的第二个元素就是上面那行 `Date().timeIntervalSince1970`，同一把尺。
        let dt = now - last.at
        guard dt > 0.2 else { return }
        let inst = (v - last.pct) / dt
        rate = rate == 0 ? inst : rate * 0.7 + inst * 0.3
        guard v > 3, rate > 0.01 else { remainText = ""; return }
        let sec = Int((100 - v) / rate)
        remainText = sec >= 90 ? "约剩 \(Int(ceil(Double(sec) / 60))) 分钟" : "约剩 \(max(sec, 1)) 秒"
    }

    /// 148 完成自动校验: 等门锁重启后重连读版本, 与包版本比对; 通过则回写钥匙串固件字段
    private func verifyAfterUpgrade(_ kc: Keychain, _ fw: FirmwarePackage) async {
        verifyText = "升级已提交 — 门锁重启中, 自动校验版本…"
        try? await Task.sleep(for: .seconds(9))
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let st = try await app.lock.getStatus(mac: kc.mac)
            if let v = fw.version, !st.firmware.isEmpty {
                if FirmwareKit.versionLt(st.firmware, v) || FirmwareKit.versionLt(v, st.firmware) {
                    verifyText = "锁内版本 v\(st.firmware) 与包版本 v\(v) 不一致, 请到锁信息名片复核"
                } else {
                    verified = true
                    verifyText = "校验通过 · 锁内已是 v\(st.firmware)"
                    var kc2 = kc
                    kc2.fw = st.firmware
                    DB.saveKeychain(kc2)
                    app.loadDevices()
                }
            } else {
                verifyText = "已读到状态但版本为空, 请到锁信息名片复核"
            }
        } catch {
            verifyText = "门锁还在重启, 暂未读回版本 — 升级已提交, 稍后到锁信息名片复核即可"
        }
    }

    private func dateShort(_ tsMs: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: tsMs / 1000))
    }
}

// ================= 蓝牙钥匙串硬件 (addkeychain) =================
struct KeychainHWView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var dongles: [Dongle] = []
    @State private var busy = false

    var body: some View { vkBody.destined(.keychainHW) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section("蓝牙钥匙串") {
                    Text("钥匙串是一个随身蓝牙硬件，可写入多把门锁的数字钥匙。持有人靠近门锁时即可开门，无需手机。")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await scan() }
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            // 常驻菊花 + 透明度过渡, 避免文字被推着走
                            ProgressView().controlSize(.small).opacity(busy ? 1 : 0)
                            Text(busy ? "搜索中…" : "搜索钥匙串")
                        }
                        .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(busy)
                }
                Section("我的钥匙串") {
                    if dongles.isEmpty {
                        EmptyState(systemImage: "key.slash",
                                   title: "还没有钥匙串",
                                   message: "上电后点上方「搜索钥匙串」即可添加。",
                                   actionTitle: "搜索钥匙串") {
                            Task { await scan() }
                        }
                    }
                    ForEach(dongles) { d in dongleRow(d) }
                        .disabled(busy)
                }
                if app.current == nil {
                    Section {
                        Label {
                            Text("尚未配对门锁 — 写入钥匙前需先配对门锁。")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                        }
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.warn)
                    }
                }
            }
            .navigationTitle("蓝牙钥匙串")
            .variantList()
            .dsScreenBackground()
            .task { reload() }
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(busy ? "写入中…" : "关闭") { dismiss() }.disabled(busy) } } .interactiveDismissDisabled(busy)   // 2026-10-15 走查: 写锁在飞时不给退出入口
        }
    }

    private func dongleRow(_ d: Dongle) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(d.name.isEmpty ? "钥匙串" : d.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                if !d.lastKeyLock.isEmpty {
                    StatusPill(text: "已配钥匙", systemImage: "checkmark.circle.fill", tone: .ok)
                }
                Spacer(minLength: 0)
            }
            Text(dongleDisplay(d.mac))
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            if let st = d.stat {
                // 电量/钥匙存量/固件是三条独立读数, 用 MetricTile 横排比挤在 caption 里层级更清楚
                HStack(spacing: DS.Space.s) {
                    MetricTile(systemImage: "battery.100",
                               label: "电量",
                               value: st.power < 0 ? "—" : "\(st.power)%",
                               tone: st.power < 0 ? .neutral : (st.power <= 20 ? .warn : .ok))
                    MetricTile(systemImage: "key",
                               label: "钥匙",
                               // -1 = 该字段没读到。两侧是**各自独立**解析的 (KLV#24 与 #25 各默认 -1,
                               // HardwareService.parseKCStatus), 所以"读到了存量、没读到上限"是正常回字 ——
                               // 原先只挡 count 那侧, 屏上就印出 "3 / -1" 这种把缺失当读数的数。
                               value: st.ekeyCount < 0 ? "—"
                                    : (st.ekeyAmount < 0 ? "\(st.ekeyCount) / —" : "\(st.ekeyCount) / \(st.ekeyAmount)"),
                               emphasized: false)
                    MetricTile(systemImage: "cpu",
                               label: "固件",
                               value: st.firmware.isEmpty ? "—" : st.firmware)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { removeRecord(d) } label: { Label("删除记录", systemImage: "trash") }
        }
        .contextMenu {
            Button("读取状态") { Task { await readStatus(d) } }
            Menu("给当前门锁写入钥匙") {
                // 内层菜单项不重复外层标题, 加省略号表示会再弹确认框
                Button("写入…") { confirmWriteKey(d) }
            }
            Button("查询全部钥匙") { Task { await listKeys(d) } }
            Button("删除本锁钥匙") { confirmDeleteKey(d) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    private func dongleDisplay(_ hex: String) -> String {
        let b = HexKit.bytes(hex).reversed()
        return b.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func reload() { dongles = DB.dongles() }

    // ---- 写硬件类动作一律先确认: 钥匙串上的钥匙不可撤销 ----
    private func confirmWriteKey(_ d: Dongle) {
        guard !busy else { return }
        let lockName = app.displayName
        confirmDestructive("写入钥匙",
                          "将把「\(lockName)」的门锁密钥写入钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」。写入后该钥匙串无需手机即可开这道门，且无法在 App 内撤销。确定写入吗？",
                          confirmTitle: "确认写入") {
            Task { await self.writeKey(d) }
        }
    }

    private func confirmDeleteKey(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除本锁钥匙",
                          "将清除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」中「\(app.displayName)」的钥匙。删除后该钥匙串将无法再开这道门。确定删除吗？",
                          confirmTitle: "删除") {
            Task { await self.deleteKey(d) }
        }
    }

    private func removeRecord(_ d: Dongle) {
        guard !busy else { return }
        confirmDestructive("删除记录",
                          "将从本机删除钥匙串「\(d.name.isEmpty ? "钥匙串" : d.name)」(\(dongleDisplay(d.mac))) 的记录，硬件本身不受影响。确定删除吗？",
                          confirmTitle: "删除") {
            DB.removeDongle(d.mac)
            reload()
        }
    }

    private func scan() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.scanForDongle() }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func readStatus(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { _ = try await HardwareService.shared.readDongleState(mac: d.mac) }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func writeKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 下面那句"请先配对门锁"会说, 上面这句却静默 = 同一条链两种收法
        guard !busy else { return }
        guard !kc.skey.isEmpty, kc.pid != 0 else { app.showToast("请先配对门锁"); return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.writeDongleKey(dongleMac: d.mac, lock: kc, trackId: KeyGen.genTrackId())
            app.showToast("设置成功: 该钥匙串现已开启「\(app.displayName)」")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }

    private func deleteKey(_ d: Dongle) async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }   // 2026-10-15 走查: 与 writeKey 同一条口径
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await HardwareService.shared.deleteDongleKey(dongleMac: d.mac, lock: kc)
            app.showToast("已删除该门锁的钥匙")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }

    private func listKeys(_ d: Dongle) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let macs = try await HardwareService.shared.dongleKeys(dongleMac: d.mac, lockMac: nil)
            app.showToast(macs.isEmpty ? "没有查询到钥匙" : "共 \(macs.count) 把钥匙")
        } catch { app.showToast("失败: \(error.localizedDescription)") }
        reload()
    }
}

// ================= 网关 (addgw + gwstate 合流) =================
struct GatewayView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var ssid = ""
    @State private var pwd = ""
    @State private var running = false
    @State private var steps: [String] = []
    @State private var error = ""
    @State private var gateways: [Gateway] = []

    var body: some View { vkBody.destined(.gateway) }
    var vkBody: some View {
        NavigationStack {
            List {
                if !confirmed {
                    Section("准备网关") {
                        Text("接通电源，重置网关，待网关指示灯闪烁橙色后点击下一步。").vkFont(.footnote)
                        VariantToggle("橙色灯闪烁中", isOn: $confirmed)
                        Text("长捅网关的重置孔，保持5s左右，至指示灯变为橙色，即重置成功。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                } else {
                    Section("配置 WiFi") {
                        TextField("WiFi 名称 (2.4GHz)", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                        SecureField("WiFi 密码", text: $pwd)
                            .submitLabel(.done)
                    }
                    Section {
                        BusyButton(title: "开始配网", systemImage: "wifi", isBusy: running, disabled: ssid.isEmpty || pwd.isEmpty) {
                            confirmProvision()
                        }
                    }
                    if !steps.isEmpty {
                        Section("配网进度") {
                            ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                                Label {
                                    Text(s).fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.ok)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            if !error.isEmpty {
                                Text(error)
                                    .vkFont(.caption)
                                    .foregroundStyle(DS.Palette.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .animation(DS.Motion.standard, value: steps)
                    }
                }
                gatewayList
            }
            .navigationTitle("智能网关")
            .variantList()
            .dsScreenBackground()
            // sheet 呈现时必须自带退出入口, 否则用户出不去
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(running ? "写入中…" : "关闭") { dismiss() }.disabled(running) } } .interactiveDismissDisabled(running)   // 2026-10-15 走查: 写锁在飞时不给退出入口
            .task { reload() }
        }
    }

    private var gatewayList: some View {
        Section("我的网关") {
            if gateways.isEmpty {
                EmptyState(systemImage: "antenna.radiowaves.left.and.right.slash",
                           title: "还没有添加网关",
                           message: "先在上方重置网关并勾选指示灯状态，再回来配网。")
            }
            ForEach(gateways) { g in gatewayRow(g) }
                .disabled(running)
        }
    }

    private func gatewayRow(_ g: Gateway) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                Text(g.name.isEmpty ? "智能网关" : g.name)
                    .vkFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Palette.text)
                StatusPill(text: g.netState == 1 ? "已联网" : "未联网",
                           systemImage: g.netState == 1 ? "wifi" : "wifi.slash",
                           tone: g.netState == 1 ? .ok : .neutral)
                Spacer(minLength: 0)
            }
            // 版本/网络两条独立读数, 用 MetricTile 横排比挤在一行 caption 里层级更清楚
            HStack(spacing: DS.Space.s) {
                MetricTile(systemImage: "cpu",
                           label: "ROM",
                           value: g.romVer.isEmpty ? "—" : g.romVer)
                MetricTile(systemImage: "wifi",
                           label: "WiFi",
                           value: g.ssid.isEmpty ? "—" : g.ssid,
                           tone: g.netState == 1 ? .ok : .neutral)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { removeGateway(g) } label: { Label("删除", systemImage: "trash") }
            Button { confirmReboot(g) } label: { Label("重启", systemImage: "arrow.clockwise") }.tint(DS.Palette.accent)
        }
        .contextMenu {
            Button("刷新状态") { Task { await refresh(g) } }
            Button("重启网关") { confirmReboot(g) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }

    private func removeGateway(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("删除网关",
                          "将从本机删除网关「\(g.name.isEmpty ? "智能网关" : g.name)」的记录。删除后若不再配网将无法找回。确定删除吗？",
                          confirmTitle: "删除") {
            DB.removeGateway(g.mac)
            reload()
        }
    }

    private func reload() { gateways = DB.gateways() }

    // 配网会向网关硬件写入 WiFi 凭据, 配错需重新重置网关才能再配
    private func confirmProvision() {
        guard !running, !ssid.isEmpty, !pwd.isEmpty else { return }
        confirmDestructive("写入网关",
                          "将把 WiFi「\(ssid)」写入网关硬件。写入过程网关会重启并清空原有网络配置，若网络不通需要重新重置网关才能再次配网。确定开始配网吗？",
                          confirmTitle: "开始配网") {
            Task { await self.provision() }
        }
    }

    // 重启会让网关短暂离线, 断电/断网期间无法远程唤醒
    private func confirmReboot(_ g: Gateway) {
        guard !running else { return }
        confirmDestructive("重启网关",
                          "将重启「\(g.name.isEmpty ? "智能网关" : g.name)」。网关会短暂离线，此期间无法远程开锁。确定重启吗？",
                          confirmTitle: "重启") {
            Task { await self.reboot(g) }
        }
    }

    private func provision() async {
        guard !running else { return }
        running = true
        steps.removeAll()
        error = ""
        defer { running = false }
        do {
            let sentWifi = ssid
            _ = try await HardwareService.shared.provisionGateway(ssid: ssid, password: pwd) { s in steps.append(s) }
            ssid = ""; pwd = ""
            confirmed = false
            // 2026-10-15 走查: 成功这一支原先只清空表单 + 退回第一步, 而"配网进度"那段只在
            // confirmed == true 的那一支里渲染 —— 于是连服务回调最后那句"添加成功!"也一起没了,
            // 成功与"点了没反应"完全同形 (失败反倒看得见, error 走的是另一支)。补一句结论,
            // 并把话说准: 到这里为止被网关 errCode 0 认下的是"WiFi 写入", 联网状态得等它自己上报。
            app.showToast("配网指令已被网关接受 · 正在用「\(sentWifi)」重连, 联网状态稍后在下方列表复核")
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    // refresh / reboot 与 provision 互斥: 同一时间只允许一条网关指令在飞
    private func refresh(_ g: Gateway) async {
        guard !running else { return }
        running = true
        defer { running = false }
        do { _ = try await HardwareService.shared.readGatewayState(mac: g.mac) }
        catch { app.showToast(error.localizedDescription) }
        reload()
    }

    private func reboot(_ g: Gateway) async {
        guard !running else { return }
        running = true
        defer { running = false }
        do {
            try await HardwareService.shared.rebootGateway(mac: g.mac)
            app.showToast("重启成功")
        } catch { app.showToast("重启失败: \(error.localizedDescription)") }
        reload()
    }
}

// ================= 成员管理 (manage/addmember/modifyname) =================
struct MembersView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @FocusState private var nameFocused: Bool
    @State private var showCenter = false
    @State private var welcome: Member?   // 995 入伙欢迎卡
    /// 成员列表直接持有, 写库后重查赋值;
    /// 不用 .id(tick) 重建整个 List —— 那会连带丢掉滚动位置、键盘焦点和动画上下文。
    @State private var members: [Member] = []

    var body: some View { vkBody.destined(.members) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section {
                    Text("添加成员后，就可以给成员添加密码，指纹和手机钥匙")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.m) {
                        TextField("姓名 (仅限汉字, 英文和数字)", text: $newName)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(add)
                        Button("添加", action: add)
                            .buttonStyle(SecondaryActionStyle(fullWidth: false))
                            .disabled(newName.isEmpty)
                    }
                }
                // 997 家庭共创目标: 本月全家备份进度
                Section {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack(spacing: DS.Space.s) {
                            Text("全家本月备份")
                                .vkFont(.subheadline, weight: .medium)
                                .foregroundStyle(DS.Palette.text)
                            Spacer(minLength: 0)
                            Text("\(Milestones.backupThisMonth) / 4 次")
                                .vkFont(.caption)
                                .monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        ProgressView(value: Double(min(Milestones.backupThisMonth, 4)), total: 4)
                            .tint(DS.Palette.accent)
                    }
                } footer: {
                    Text("每月全家一起备份 4 次, 备份卫士徽章就稳了。")
                }
                Section("成员 (\(members.count))") {
                    if members.isEmpty {
                        EmptyState(systemImage: "person.2.slash",
                                   title: "还没有成员",
                                   message: "添加后就能把密码和指纹归属到人。",
                                   actionTitle: "添加成员") {
                            nameFocused = true
                        }
                    }
                    ForEach(members) { m in memberRow(m) }
                }
            }
            .navigationTitle("成员管理")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } }
                // 包13: 成员中心入口 (788 总表 / 360 详情 / 家庭场景 / 聚合视图)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCenter = true
                    } label: {
                        Image(systemName: "person.2.badge.gearshape")
                            .accessibilityLabel("成员中心 (家庭协作)")
                    }
                }
            }
            .sheet(isPresented: $showCenter) {
                MemberCenterView()
            }
            .sheet(item: $welcome) { m in
                MemberWelcomeCard(member: m)   // 995 入伙欢迎卡
            }
            .task { reload() }
        }
    }

    /// 732: 号码只留数字与 +; 清洗后不足 3 位视为无效号码, 不给呼叫入口 (不弹错误页)
    private static func telURL(_ raw: String) -> URL? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel://" + digits)
    }

    private func memberRow(_ m: Member) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
                Text(m.name).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
            }
            if !m.relation.isEmpty || !m.phone.isEmpty {
                Text([m.relation, m.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { confirmRemove(m) } label: { Label("删除", systemImage: "trash") }
        }
        .contextMenu {
            // 732 一键呼叫成员: 号码只保留数字与 + (去空格/括号/连字符), 空号不给入口
            if let tel = Self.telURL(m.phone) {
                Button { UIApplication.shared.open(tel) } label: { Label("呼叫 \(m.name)", systemImage: "phone.fill") }
            }
            Button("重命名") { rename(m) }
            Button("补全信息") { info(m) }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }


    private func rename(_ m: Member) {
        prompt(title: "重命名", message: nil,
               fields: [FieldSpec(placeholder: "姓名", text: m.name)],
               confirmTitle: "保存") { vals in
            guard let n = vals.first?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return }
            guard n.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                app.showToast("请输入仅含汉字/英文/数字的非空姓名")
                return
            }
            DB.renameMember(m.id, n)
            reload()
        }
    }

    private func info(_ m: Member) {
        prompt(title: "补全信息 (只填空缺)", message: nil,
               fields: [FieldSpec(placeholder: "与你的关系", text: m.relation),
                        FieldSpec(placeholder: "电话 (换机恢复第二匹配键)", text: m.phone, keyboard: .phonePad),
                        FieldSpec(placeholder: "生日 MM-dd (用于提醒)", text: "")],
               confirmTitle: "保存") { vals in
            DB.setMemberInfo(m.id, ["relation": vals.first ?? "", "phone": vals.count > 1 ? vals[1] : ""])
            let bday = vals.count > 2 ? vals[2].trimmingCharacters(in: .whitespaces) : ""
            reload()
        }
    }

    private func reload() { members = DB.members() }

    private func add() {
        if let m = DB.addMember(newName) {
            newName = ""
            nameFocused = false
            reload()
            welcome = m            // 995: 欢迎卡引导首录凭证, 不再只丢一句 toast
        } else {
            app.showToast("姓名为空或已存在")
        }
    }

    // ---- 输入型弹窗: 重命名/补全信息共用一份, 不再各写一个 UIAlertController ----
    struct FieldSpec {
        let placeholder: String
        var text: String = ""
        var keyboard: UIKeyboardType = .default
    }

    private func prompt(title: String,
                        message: String?,
                        fields: [FieldSpec],
                        confirmTitle: String,
                        onConfirm: @escaping ([String]) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for f in fields {
            alert.addTextField { tf in
                tf.placeholder = f.placeholder
                tf.text = f.text
                tf.keyboardType = f.keyboard
                tf.clearButtonMode = .whileEditing
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in
            onConfirm(alert.textFields?.map { $0.text ?? "" } ?? [])
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 501 级联预告: 删除成员前列出名下将一并入回收站的凭证清单 (跨锁合计)
    /// D-152a (2026-10-11 拍板 方案③): 与成员页同一形状 —— 三按钮, 默认「只移除档案」,
    /// 撤权那一支排 629/353 同一条队列; 指纹不可远程补录 (670) 的代价写在正文里。
    private func confirmRemove(_ m: Member) {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        let msg = preview.isEmpty
            ? "确定要删除「\(m.name)」吗？TA 名下没有台账凭证。"
            // 单行字面量里不能有裸换行 (Swift 语法错): 原文的换行全部写成 \n 转义
            : "删除「\(m.name)」后, 名下 \(preview.count) 条凭证将转为未分配并入回收站 (可整组还原):\n"
              + preview.prefix(5).joined(separator: "\n")
              + (preview.count > 5 ? "\n…" : "")
              + "\n· 只移除档案: 只动本机台账, 锁里的指纹与密码不会被收回, TA 仍能开门。"
              + "\n· 连锁端一起收回: 这些凭证会排上锁端删除, 到场连接后真正失效。指纹一旦在锁端删掉就无法远程补录, 只能本人到锁前重录 —— 还原时对指纹只剩本机记录。"
        let alert = UIAlertController(title: "删除成员", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "只移除档案", style: .default) { _ in
            // 凭证随成员入回收站 (整组同戳), 成员档案移除并解除归属; 锁端不动
            for kc in DB.keychains() {
                CredentialOrg.cascadeBinMember(kc.mac, m.id)
            }
            DB.removeMember(m.id)
            _ = Milestones.recordOrganize()
            reload()
        })
        alert.addAction(UIAlertAction(title: "连锁端一起收回", style: .destructive) { _ in
            // 排上队列的条数在闭包内取 (不改捕获的局部变量: handler 是 escaping 闭包)
            let queued = DB.keychains().reduce(0) { sum, kc in
                sum + CredentialOrg.cascadeBinMember(kc.mac, m.id, revokeLocks: true)
            }
            DB.removeMember(m.id)
            _ = Milestones.recordOrganize()
            reload()
            app.showToast(queued > 0 ? "已删除并入回收站 · 已排 \(queued) 条锁端删除 (连接门锁后生效)"
                                      : "已删除并入回收站 (名下没有可收回的凭证)")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
}

/// 995 入伙欢迎卡: 三步指路 + 一个去凭证页的动作; 不替用户动任何数据。
private struct MemberWelcomeCard: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let member: Member
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("欢迎 \(member.name) 入伙")   // 995 欢迎
                .vkFont(.headline)
            Text("下一步: ① 去凭证页给 TA 录一条凭证 ② 在凭证详情把「归属」改成 \(member.name) ③ 归属后「各就各位」与「入伙」徽章一起点亮")
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s) {
                Button("去凭证页") { dismiss(); app.requestRoute(.credentials) }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                Spacer(minLength: 0)
                Button("知道了") { dismiss() }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
            }
        }
        .padding(DS.Space.l)
        .presentationDetents([.height(260)])
    }
}

// ================= 动态 (message 页离线等价: 全部门锁日志汇总) =================
struct MessagesView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddDevice = false

    struct Row: Identifiable {
        var id: String
        var text: String
        var sub: String
        var warn: Bool
    }

    var body: some View { vkBody.destined(.messages) }
    var vkBody: some View {
        NavigationStack {
            List {
                if rows.isEmpty { emptyHint }
                ForEach(rows) { rowItem($0) }
            }
            .navigationTitle("动态")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showAddDevice) { AddDeviceView() }
        }
    }

    // 行内容与空态各自独立成子视图: 整体写在一个 body 里会让类型检查器
    // 在 NavigationStack + List + ForEach 三层嵌套下超时
    @ViewBuilder
    private var emptyHint: some View {
        EmptyState(systemImage: "bell.slash",
                   title: "还没有动态",
                   message: "连接门锁读取记录后，这里会汇总全部门锁的开门与告警事件。",
                   actionTitle: "去添加门锁") {
            showAddDevice = true
        }
    }

    private func rowItem(_ r: Row) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: r.warn ? "exclamationmark.triangle.fill" : "circle.fill")
                .font(.system(size: DS.Icon.xs))
                .foregroundStyle(r.warn ? DS.Palette.warn : DS.Palette.accentText)
                // 与 caption 首行基线对齐
                .padding(.top, DS.Space.xs)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(r.text)
                    .vkFont(.subheadline)
                    .foregroundStyle(DS.Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.sub)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(r.warn ? "告警：" + r.text + "，" + r.sub : r.text + "，" + r.sub)
    }

    private var rows: [Row] {
        var out = [Row]()
        for kc in DB.keychains() {
            let devName = kc.name.isEmpty ? PidMap.productName(kc.pid) + " …" + kc.mac.suffix(4) : kc.name
            for l in DB.readLogs(kc.mac) {
                // 第一百五十七批：这里也曾自己写 `7 || 13 || 224`，5 类告警只圈 3 类 ⇒
                // 低电量与试错锁定在这一屏既不变色、VoiceOver 也不念"告警："前缀，
                // 而同一条记录在告警中心/统计/导出里都算告警。口径只认 StatsKit.alarmTypes。
                let warn = StatsKit.alarmTypes.contains(l.type)
                out.append(Row(id: kc.mac + "#\(l.idxRaw)", text: l.typeName,
                               sub: "\(l.lockTimeStr) · \(devName)", warn: warn))
            }
        }
        return out.sorted { $0.sub > $1.sub }
    }
}