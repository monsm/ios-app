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

// 2026-10-28 合并双实现：`AddPwdView`（单页表单，183 行）与 `StartAddFpView`（单页表单，203 行）
// 已被 `PwdStudio`（4 步向导，703 行）与 `FpStudio`（4 步向导，378 行）取代 ——
// 用户拍板「向导更完整」。所有 6 处调用点已改为向导版：
//   AddPwdView  → PwdStudio(embedded: true)   [QuickPool / CredentialsView ×2]
//   StartAddFpView → FpStudio(embedded: true)  [QuickPool / CredentialsView / MemberCenterView]
// 向导版多了：分步校验、草稿续填、确认密码、备注、重录继承、沉浸式录入页。

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
                            .layoutPriority(1)   // 2026-10-27：同 DeviceHomeView，防被右侧宽内容挤压
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
        // 2026-10-28 补 C 模式：APK 的判据链是
        //   0 == verifyMode                    → "A模式"
        //   1 == verifyMode                    → "B模式"
        //   1 == verifyMode && 0 == broadcastMode → "C模式"（覆盖前一条）
        // iOS 此前只做前两条，于是 KX 进 C 级后仍显示 B —— 用户解释不了"为什么收不到通知"。
        // broadcastMode 早已在 StatusParser.swift:77 解析，只是零消费。
        if s.verifyMode == 1 && s.broadcastMode == 0 { return "C模式" }
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
    /// 2026-10-28 补：`LockArchive.setDefaultMac` 全仓零调用 —— 而 `defaultMac` 有 2 处消费
    /// （冷启动落点 `AppState.loadDevices(preferDefault:)` + 设备排序首位）。
    /// 于是「启动默认锁」这个功能**永远设不了**，用户只能靠"上次停留"。
    @State private var isDefaultLock = false
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
            // 2026-10-28 补入口：「设为启动默认锁」—— `setDefaultMac` 此前零调用。
            Section {
                VariantToggle("设为启动默认锁", isOn: $isDefaultLock)
            } footer: {
                Text("开启后，冷启动（杀进程再打开）会直接落在这把锁；关掉则维持「上次停留的那把」。"
                     + " 只在本机生效，不写入门锁。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
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
            isDefaultLock = LockArchive.defaultMac == kc.mac
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
        // 2026-10-28：默认锁与档案一起保存（`setDefaultMac` 会同时把它排到手工顺序首位，
        // 避免"顺序表说 A 在前、默认锁说 B 在前"两个真相）。
        if isDefaultLock {
            LockArchive.setDefaultMac(kc.mac)
        } else if LockArchive.defaultMac == kc.mac {
            LockArchive.setDefaultMac("")   // 关掉 = 清除，回到"上次停留"
        }
        app.loadDevices()
        app.showToast("档案已保存")
        dismiss()
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
                        // 2026-10-28 补：APK `GwstatePage`（网关状态页）有三条使用须知，iOS 全文没有 ——
                        // 用户不知道网关该放多远、能做什么不能做什么，容易以为「买了网关就能远程开门」。
                        // 第 2 条原文是「绑定到和门锁相同账号下即可」—— 那是云端账号口径；
                        // iOS 纯离线没有账号，这里改写成等价的本地事实（IoT 凭据随配网一起写入网关）。
                        Text("1. 建议距离门锁不超过五米，不能有障碍物阻隔。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("2. 无需和门锁配对；配网时 IoT 凭据会随 WiFi 一起写入网关。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("3. 只能接收门锁状态和通知，无法远程操作门锁。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section {
                        TextField("WiFi 名称 (2.4GHz)", text: $ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                        SecureField("WiFi 密码", text: $pwd)
                            .submitLabel(.done)
                    } header: {
                        Text("配置 WiFi")
                    } footer: {
                        // 2026-10-28：APK 用原生的 WifiNamePlugin.getWifiInfo 自动预填当前 SSID；
                        // iOS 读 WiFi 名需要 `com.apple.developer.networking.wifi-info` entitlement + 定位权限，
                        // 本工程两者都没有（也不该为一个配网表单去申请定位）。所以这里如实说明要手输，
                        // 而不是让用户以为是 App 忘了填。
                        Text("iOS 不允许 App 读取当前 WiFi 名，请手动输入（只支持 2.4GHz）。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        // 2026-10-28 补：APK 的「更换其他 WiFi」走 NativeSettings.open("wifi") 直达系统 WiFi 面板；
                        // iOS **没有**任何公开 API 能直达 WiFi 设置（openSettingsURLString 只到本 App 设置页）。
                        // 所以这里只能如实告诉用户要自己离开 App 去系统设置，而不是放一个点了没反应的按钮。
                        Text("需要换 WiFi 时，请先到「设置 → Wi-Fi」连上目标网络，再回来点「开始配网」。")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
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
        // 2026-10-28 修复（**安全级假承诺**）：与 MemberCenterView.confirmDelete 同一问题 ——
        // 「并入回收站（可整组还原）」与「排上锁端删除」两句都无实现（无回收站、无队列）。
        // 两个按钮行为完全相同，只留一个，并如实说明锁端凭证仍需手动删除。
        let msg = preview.isEmpty
            ? "确定要删除「\(m.name)」吗？TA 名下没有台账凭证。本机记录删除后不可恢复。"
            : "删除「\(m.name)」后, 名下 \(preview.count) 条凭证将从**本机台账移除**"
              + "（本机没有回收站，删除后不可恢复）:\n"
              + preview.prefix(5).joined(separator: "\n")
              + (preview.count > 5 ? "\n…" : "")
              + "\n\n⚠ 锁端凭证不受影响 —— 这些密码/指纹在门锁上**仍然有效**，"
              + "必须到门锁键盘上手动删除才会真正失效。指纹一旦在锁端删掉就无法远程补录，只能本人到锁前重录。"
        let alert = UIAlertController(title: "删除成员", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "移除档案（锁端需另删）", style: .destructive) { _ in
            for kc in DB.keychains() {
                CredentialOrg.cascadeBinMember(kc.mac, m.id)
            }
            DB.removeMember(m.id)
            _ = Milestones.recordOrganize()
            reload()
            app.showToast("已删除 · ⚠ 锁端凭证仍在，需要时请到门锁上手动删除")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
}

