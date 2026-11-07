// WriteConsoleSheet.swift —— 写面命令台（调试/诊断）。
//
// 目的：把锁的写面命令逐条手动触发，由用户在真机上自己决定何时发。
// **引擎零改动**：这里只调用既有的 ZKCmdBuilder / LockService.exec / HardwareService 公开入口，
// 与 App 正常路径下发的是同一批构造器产出的同一批帧。
//
// 覆盖：05 · 08 · 0A · 0B · 13 · 14 · 15 · 18 · 19 · 20 · 21 · 22 · 24 · 25 ·
//       钥匙串 41 / 43 / 44 · 网关 30 / 31 / 32 / 35 / 38。
// 每条都要二次确认；05 会擦写锁内密钥域，破坏性单独标注。
import SwiftUI

@MainActor
struct WriteConsoleSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    // 参数区（各命令按需取用；留空用默认值，见各行说明）
    @State private var alias = ""
    @State private var batch = ""
    @State private var pwd = ""
    @State private var pins = ""
    @State private var bkey = ""
    @State private var n1 = ""
    @State private var n2 = ""
    @State private var n3 = ""
    @State private var ssid = ""
    @State private var wifiPwd = ""

    @State private var busy = false
    @State private var result: String?
    @State private var pending: ConsoleCmd?

    private struct ConsoleCmd: Identifiable {
        let id: String
        let title: String
        let detail: String
        let destructive: Bool
        let run: () async -> String
    }

    private var kc: Keychain? { DB.keychainForUnlock(app.currentMac) }
    private var dongle: Dongle? { DB.dongles().first }
    private var gateway: Gateway? { DB.gateways().first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("写面命令台")
                        .type(T.F.title2)
                        .foregroundStyle(T.C.ink)
                        .padding(.top, 16)
                    Text("这些命令会真的改锁或硬件。05 换钥会二次擦写锁内密钥域、可能让本机现有钥匙立刻作废；其余后果见各行说明。每条都要二次确认 —— 由你决定何时发。")
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink2)
                        .lineSpacing(3)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.trial {
                        Text("只读试验模式开着 —— 引擎会拦下所有写命令（预期行为）。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.danger)
                            .padding(.top, 6)
                    }
                    if kc == nil {
                        Text("还没有已配对的锁 —— 锁端命令会失败。")
                            .type(T.F.caption)
                            .foregroundStyle(T.C.danger)
                            .padding(.top, 6)
                    }

                    SectionHead(index: "01", title: "参数")
                    FieldInput(placeholder: "alias（0A 删除 / 0B 用，数字）", text: $alias)
                    FieldInput(placeholder: "批号（14/15 用，数字）", text: $batch)
                        .padding(.top, 8)
                    FieldInput(placeholder: "密码（0A 添加，≤8 位）", text: $pwd)
                        .padding(.top, 8)
                    FieldInput(placeholder: "PIN 列表（08 用，8 位 hex，逗号分隔）", text: $pins)
                        .padding(.top, 8)
                    FieldInput(placeholder: "bkey（21 用，32 位 hex）", text: $bkey)
                        .padding(.top, 8)
                    FieldInput(placeholder: "n1（18=0/1 · 19=0/1 · 20=0/1 · 22=参数 · 24=档位1-6 · 25=布防控制）", text: $n1)
                        .padding(.top, 8)
                    FieldInput(placeholder: "n2（25 用：起始协议秒）", text: $n2)
                        .padding(.top, 8)
                    FieldInput(placeholder: "n3（25 用：结束协议秒）", text: $n3)
                        .padding(.top, 8)
                    FieldInput(placeholder: "SSID（31 网关配网用）", text: $ssid)
                        .padding(.top, 8)
                    FieldInput(placeholder: "WiFi 密码（31 用）", text: $wifiPwd, secure: true)
                        .padding(.top, 8)

                    SectionHead(index: "02", title: "锁端写面")
                    ForEach(lockCmds) { cmd in
                        consoleRow(cmd)
                    }

                    SectionHead(index: "03", title: "钥匙串 / 网关")
                    ForEach(hwCmds) { cmd in
                        consoleRow(cmd)
                    }

                    if let result {
                        SectionHead(index: "04", title: "最近结果")
                        Text(result)
                            .type(T.F.mono)
                            .foregroundStyle(T.C.ink2)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .background(T.C.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        // iOS 27：以「待发的那条命令」为状态。
        .itemConfirmationDialog(pending?.title ?? "", item: $pending, titleVisibility: .visible) { cmd in
            Button("发送", role: cmd.destructive ? .destructive : nil) {
                pending = nil
                Task { await fire(cmd) }
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: { cmd in
            Text(cmd.detail)
        }
        .presentationDetents([.large])
    }

    private func consoleRow(_ cmd: ConsoleCmd) -> some View {
        Button {
            pending = cmd
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(cmd.title)
                    .type(T.F.callout)
                    .foregroundStyle(T.C.ink)
                Text(cmd.detail)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
    }

    private func fire(_ cmd: ConsoleCmd) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let text = await cmd.run()
        result = cmd.title + "\n" + text
    }

    // MARK: - 发送助手（引擎既有入口，逻辑零改动）

    private func sendLock(_ cmd: ZKCmd) async -> String {
        guard let kc else { return "没有已配对的锁" }
        do {
            try await LockService.shared.ensureConnected(mac: kc.mac)
            let r = try await LockService.shared.exec(cmd)
            return "rc=\(r.rc)（\(StatusParser.rcMessage(r.rc))）\n\(LockService.klvShape(r.frame))"
        } catch {
            return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private var aliasInt: Int { Int(alias.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var batchInt: Int { Int(batch.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var n1Int: Int { Int(n1.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var n2Int: Int { Int(n2.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var n3Int: Int { Int(n3.trimmingCharacters(in: .whitespaces)) ?? 0 }

    /// 永久窗口（与 App 正常路径同口径：2010-01-01 ~ 2118-01-01）。
    private let foreverFrom = "2010-01-01 00:00:00"
    private let foreverTo = "2118-01-01 00:00:00"

    private var pinList: [String] {
        pins.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { $0.count == 8 && $0.allSatisfy(\.isHexDigit) }
    }

    // MARK: - 命令清单

    private var lockCmds: [ConsoleCmd] {
        [
            ConsoleCmd(
                id: "05",
                title: "05 换钥 exchange",
                detail: "用本机 skey 重新发一次交换（KLV#03=当前 skey）。会二次擦写锁内密钥域 —— 锁若拒绝（rc≠0）则未执行；rc=0 后本机保存的钥匙可能立即作废，重发不可逆。",
                destructive: true
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd05Exchange(kc.skey))
            },
            ConsoleCmd(
                id: "08",
                title: "08 同步 PIN 批量",
                detail: "把「PIN 列表」里的 8 位 hex 逐枚加入锁池（不删除）。格式不对的条目会被忽略；>20 枚构造器会拒发。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                guard !pinList.isEmpty else { return "PIN 列表为空（需要 8 位 hex，逗号分隔）" }
                guard let cmd = ZKCmdBuilder.cmd08SyncPinsBatch(kc.mac, kc.skey, pinList) else {
                    return "帧构造失败（addPins > 20）"
                }
                return await sendLock(cmd)
            },
            ConsoleCmd(
                id: "0A",
                title: "0A 同步密码（添加）",
                detail: "用「alias / 密码」把一条密码加进锁（永久窗口）。alias 留空 = 0；密码 ≤8 位、留空则只做删除。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                do {
                    let cmd = try ZKCmdBuilder.cmd0ASyncPwd(kc.mac, kc.skey, delAlias: aliasInt,
                                                           addPwd: pwd,
                                                           validFrom: foreverFrom, validTo: foreverTo)
                    return await sendLock(cmd)
                } catch {
                    return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            },
            ConsoleCmd(
                id: "0B",
                title: "0B 密码有效期",
                detail: "改「alias」那条密码的有效期（永久窗口）。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd0BSyncPwdExpire(kc.mac, kc.skey, aliasInt, foreverFrom, foreverTo))
            },
            ConsoleCmd(
                id: "13",
                title: "13 录指纹（开始）",
                detail: "让锁进入录指纹状态（8 次按压 / 15 秒超时）—— 之后要在锁上真的按手指，再用 14 确认。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd13AddFp(kc.mac, kc.skey))
            },
            ConsoleCmd(
                id: "14",
                title: "14 指纹确认",
                detail: "用「批号」确认刚录的指纹（永久窗口）。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                // UInt32(负值) 在 Swift 里是 trap —— 输入框恶意/手滑输入负数会当场崩进程，钳制。
                return await sendLock(ZKCmdBuilder.cmd14FpConfirm(kc.mac, kc.skey, UInt32(clamping: batchInt), foreverFrom, foreverTo))
            },
            ConsoleCmd(
                id: "15",
                title: "15 删指纹",
                detail: "用「批号」从锁里删除那枚指纹 —— 删了要把手指重新录一遍才能用。",
                destructive: true
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd15DeleteFp(kc.mac, kc.skey, UInt32(clamping: batchInt)))
            },
            ConsoleCmd(
                id: "18",
                title: "18 音量",
                detail: "n1=0 有声 / 1 静音。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd18Volume(kc.mac, kc.skey, n1Int != 0))
            },
            ConsoleCmd(
                id: "19",
                title: "19 动态码开关",
                detail: "n1=1 开启 / 0 关闭锁端动态码（会重置周期计时，见厂商固件行为）。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd19OpenZotp(kc.mac, kc.skey, n1Int != 0))
            },
            ConsoleCmd(
                id: "20",
                title: "20 验证模式",
                detail: "n1=1 双验（密码+指纹）/ 0 单验。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd20ValidationMode(kc.mac, kc.skey, n1Int != 0))
            },
            ConsoleCmd(
                id: "21",
                title: "21 设置 bkey",
                detail: "把「bkey」（32 位 hex）写进锁 —— 写错会让现有钥匙全体失效，只在明确要用时发。",
                destructive: true
            ) {
                guard let kc else { return "没有已配对的锁" }
                let h = bkey.trimmingCharacters(in: .whitespaces).lowercased()
                guard h.count == 32, h.allSatisfy(\.isHexDigit) else { return "bkey 需要 32 位 hex" }
                return await sendLock(ZKCmdBuilder.cmd21SetBkey(kc.mac, kc.skey, h))
            },
            ConsoleCmd(
                id: "22",
                title: "22 DFU 使能",
                detail: "n1=参数（默认 0）。真机 DFU 走 Nordic 独立通道，这条是协议面构造器 —— 发错可能把锁带进 DFU 态。",
                destructive: true
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd22EnableDfu(kc.mac, kc.skey, n1Int))
            },
            ConsoleCmd(
                id: "24",
                title: "24 自动上锁",
                detail: "n1 = 档位（1–6）。",
                destructive: false
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd24AutoLock(kc.mac, kc.skey, n1Int))
            },
            ConsoleCmd(
                id: "25",
                title: "25 布防",
                detail: "n1=控制（1 本次 / 2 时段）· n2/n3=起止协议秒。布防期间开锁会被锁拒绝。",
                destructive: true
            ) {
                guard let kc else { return "没有已配对的锁" }
                return await sendLock(ZKCmdBuilder.cmd25Defence(kc.mac, kc.skey, n1Int, n2Int, n3Int))
            },
        ]
    }

    private var hwCmds: [ConsoleCmd] {
        [
            ConsoleCmd(
                id: "41",
                title: "41 钥匙串写钥",
                detail: "把当前锁的钥匙写进钥匙串（用钥匙串的主 PIN 现签）—— 需要钥匙串在旁有电。",
                destructive: false
            ) {
                guard let kc, let dongle else { return "缺少已配对的锁或已登记的钥匙串" }
                do {
                    try await HardwareService.shared.writeDongleKey(
                        dongleMac: dongle.mac, lock: kc,
                        trackId: UInt32.random(in: 1 ... 0x7fff_ffff))
                    return "已写入（\(dongle.mac)）"
                } catch {
                    return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            },
            ConsoleCmd(
                id: "43",
                title: "43 钥匙串状态（无引擎入口）",
                detail: "HardwareService 未暴露 cmd43 的公开入口 —— 钥匙串页的「读取状态」走的是 cmd44 的状态帧。此处只作说明，不发帧。",
                destructive: false
            ) {
                "未发送：引擎没有 cmd43 入口（见说明）"
            },
            ConsoleCmd(
                id: "44",
                title: "44 钥匙串查钥",
                detail: "查钥匙串里有没有当前锁的钥匙 —— 需要钥匙串在旁有电。",
                destructive: false
            ) {
                guard let kc, let dongle else { return "缺少已配对的锁或已登记的钥匙串" }
                do {
                    let keys = try await HardwareService.shared.dongleKeys(dongleMac: dongle.mac, lockMac: kc.mac)
                    return keys.isEmpty ? "钥匙串里没有这把锁的钥匙" : "找到：\(keys.joined(separator: " · "))"
                } catch {
                    return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            },
            ConsoleCmd(
                id: "30",
                title: "30 网关名称（无引擎入口）",
                detail: "引擎没有 cmd30 的公开方法 —— 只作说明，不发帧。",
                destructive: false
            ) {
                "未发送：引擎没有 cmd30 入口（见说明）"
            },
            ConsoleCmd(
                id: "31",
                title: "31 网关配网",
                detail: "用上面的「SSID / WiFi 密码」让网关连 WiFi —— 会真的改网关网络。",
                destructive: false
            ) {
                guard !ssid.trimmingCharacters(in: .whitespaces).isEmpty else { return "SSID 为空" }
                do {
                    let gw = try await HardwareService.shared.provisionGateway(
                        ssid: ssid, password: wifiPwd) { _ in }
                    return "已连上 \(gw.ssid)（\(gw.wifiIP)）"
                } catch {
                    return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            },
            ConsoleCmd(
                id: "32",
                title: "32 网关 IoT（无引擎入口）",
                detail: "引擎没有 cmd32 的公开方法（云端绑定能力本仓不做）—— 只作说明，不发帧。",
                destructive: false
            ) {
                "未发送：引擎没有 cmd32 入口（见说明）"
            },
            ConsoleCmd(
                id: "35",
                title: "35 网关重启",
                detail: "让网关重启一次。",
                destructive: false
            ) {
                guard let gateway else { return "没有已登记的网关" }
                do {
                    try await HardwareService.shared.rebootGateway(mac: gateway.mac)
                    return "重启命令已下发（\(gateway.mac)）"
                } catch {
                    return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            },
            ConsoleCmd(
                id: "38",
                title: "38 网关状态",
                detail: "读一次网关状态帧（只读）。",
                destructive: false
            ) {
                guard let gateway else { return "没有已登记的网关" }
                do {
                    let st = try await HardwareService.shared.readGatewayState(mac: gateway.mac)
                    let ssidText = st.ssid.isEmpty ? "—" : st.ssid
                    let ipText = st.wifiIP.isEmpty ? "—" : st.wifiIP
                    return "已读回：SSID \(ssidText) · IP \(ipText) · netState=\(st.netState) · ROM \(st.romVer)"
                } catch {
                    return "失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            },
        ]
    }
}
