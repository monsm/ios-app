// GodModeScreen.swift —— **god 模式**：把引擎已有、界面没有的能力收进一页。
//
// 2026-11-03（用户：「加入更全面的最深层次 god 模式管理锁一切可以管理的数据」）：
//   · 引擎层已有：cmd03 全量状态、双侧快照（DiagSnapshot）、修池（repairPool，保 skey 重写 PIN 表）、
//     cmd16 凭证变更日志（type 14/15/20/21 已解码 track/alias/批次）；
//   · 界面层此前只有「交互流水」一个入口，快照/修池/日志明细**都没有 UI** —— 有引擎没界面等于没有。
//
// 本页**只读为主**：默认只展示读数；唯一写动作是「修池」（破坏性，二级确认 + 明确后果文案）。
// 排版：仪器面板语言 —— 分区标题 + 行式读数，数字等宽，不做装饰。
import SwiftUI

struct GodModeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @State private var status: StatusSnapshotData?
    @State private var busy = false
    @State private var message: String?
    @State private var askRepair = false
    @State private var logs: [LogEntry] = []

    private var mac: String { app.currentMac }
    private var kc: Keychain? { app.currentKeychain }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V.S.gap16) {
                if let kc {
                    identityPanel(kc)
                    liveStatusPanel
                    credentialPanel(kc)
                    if !logs.isEmpty { changeLogPanel }
                    repairPanel(kc)
                } else {
                    VCard {
                        VStack(alignment: .leading, spacing: V.S.gapS) {
                            Text("没有已配对的锁")
                                .font(V.F.rowTitle).foregroundStyle(V.C.text1)
                            Text("先在「门」页添加门锁，或从备份恢复。")
                                .font(V.F.footnote).foregroundStyle(V.C.text3)
                        }
                    }
                    .padding(.horizontal, V.S.pageGutter)
                }
            }
            .padding(.vertical, V.S.gap16)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("God 模式")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .confirmationDialog("重写这把锁的 PIN 表？", isPresented: $askRepair, titleVisibility: .visible) {
            Button("重写 PIN 表（保留通信密钥）", role: .destructive) { Task { await repair() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("把锁内 PIN 表整体重置为新的 64 枚，通信密钥 skey 不变 —— 别人手机里的钥匙不会因换钥变砖。但锁内已有的旧 PIN（含别的手机钥匙）会全部失效。靠近门锁再执行。")
        }
    }

    // MARK: 锁身份（本机侧）

    private func identityPanel(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "锁身份")
                VFieldRow(label: "MAC", value: DB.normalizeMac(kc.mac))
                VFieldRow(label: "名称", value: LockArchive.displayName(kc), mono: false)
                VFieldRow(label: "配对时间", value: kc.pairedAt, mono: false)
                VFieldRow(label: "skey 指纹", value: DiagSnapshot.fingerprint(kc.skey))
                VFieldRow(label: "ekey 指纹", value: DiagSnapshot.fingerprint(kc.ekey))
                VFieldRow(label: "存的 ekey 嵌的 PIN", value: DiagSnapshot.ekeyPin(kc), mono: false)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 锁端实时读数（cmd03 全量）

    private var liveStatusPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "锁端实时读数 (cmd03)")
                if let st = status {
                    VFieldRow(label: "固件", value: st.firmware.isEmpty ? "未上报" : st.firmware)
                    VFieldRow(label: "电量", value: st.powerLevel >= 0 ? "\(st.powerLevel)%" : "未读到")
                    VFieldRow(label: "锁内时间", value: st.lockTime > 0 ? TimeFormat.clock(ZKProtocol.protoSecondsToMs(st.lockTime)) : "未读到")
                    VFieldRow(label: "安全模式", value: "verify=\(st.verifyMode) broadcast=\(st.broadcastMode) tempPwd=\(st.tempPwdMode)", mono: false)
                    VFieldRow(label: "PIN 容量/剩余", value: "\(st.pinCap ?? -1)/\(st.pinStock)")
                    VFieldRow(label: "→ 锁端已用 PIN", value: String(max((st.pinCap ?? 0) - st.pinStock, 0)))
                    VFieldRow(label: "密码容量/剩余", value: "\(st.pwdCap ?? -1)/\(st.pwdStock)")
                    VFieldRow(label: "指纹容量/剩余", value: "\(st.fpCap ?? -1)/\(st.fpStock)")
                    VFieldRow(label: "sKeyStatus", value: String(st.sKeyStatus))
                    VFieldRow(label: "ZOTP 周期", value: "\(st.zotpPeriod) 分钟")
                } else {
                    Text(busy ? "读取中…" : "还没读到 —— 连上锁后自动读。")
                        .font(V.F.footnote).foregroundStyle(V.C.text3)
                }
                if let message { Text(message).font(V.F.footnote).foregroundStyle(V.C.warning) }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 凭证台账（本机 vs 锁端计数）

    private func credentialPanel(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "凭证台账")
                VFieldRow(label: "本机 PIN 池", value: "\(kc.pins.filter { !$0.isEmpty }.count) 枚（声明 \(kc.pins.count)）", mono: false)
                VFieldRow(label: "本机密码", value: "\(DB.listPwds(kc.mac).count) 条", mono: false)
                VFieldRow(label: "本机指纹", value: "\(DB.listFps(kc.mac).count) 枚", mono: false)
                if let st = status {
                    let used = max((st.pinCap ?? 0) - st.pinStock, 0)
                    let local = kc.pins.filter { !$0.isEmpty }.count
                    VFieldRow(label: "锁端已用 vs 本机池", value: "\(used) vs \(local)", mono: false)
                    // 数量相等不能证明同批（两边都满池时恒等）—— 唯一的裁判是"开锁回 rc"。
                    Text(used == local
                         ? "数量一致（但两批都满池时恒等——真正的判据是开锁 rc=2 与否）"
                         : "**数量不一致** —— 现签凭证必被拒，需要修池或重导")
                        .font(V.F.footnote)
                        .foregroundStyle(used == local ? V.C.text3 : V.C.critical)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 凭证变更流水（cmd16 type 14/15/20/21 解码）

    @ViewBuilder
    private var changeLogPanel: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "锁端凭证变更（cmd16 解码）")
                Text("锁端自己记录的凭证操作 —— 含**别的手机/网关**做的。这是「对不上」时的第一手证据。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(logs.prefix(20).enumerated()), id: \.offset) { pair in
                    VStack(alignment: .leading, spacing: V.S.gapXXS) {
                        HStack {
                            Text(pair.element.lockTimeStr).font(V.F.stamp).foregroundStyle(V.C.text2).monospacedDigit()
                            Text(pair.element.typeName).font(V.F.stamp).foregroundStyle(V.C.text1)
                            Spacer(minLength: 0)
                        }
                        if let diff = pair.element.diffDescription {
                            Text(diff).font(V.F.stamp).foregroundStyle(V.C.text3).monospacedDigit()
                        }
                    }
                    .padding(.vertical, V.S.gapXXS)
                    if pair.offset > 0 { VRowDivider() }
                }
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 修池（唯一写动作）

    private func repairPanel(_ kc: Keychain) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "修复")
                Text("开锁永远 rc=2 且本机池与锁端无法对应时，用「修池」：保 skey 只重写 PIN 表，然后自动重签开锁凭证。不用重置锁，也不用走到锁跟前。")
                    .font(V.F.footnote).foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "修池（重写 PIN 表 · 保通信密钥）", systemImage: "wrench.and.screwdriver.fill") {
                    askRepair = true
                }
                .disabled(busy || mac.isEmpty)
            }
        }
        .padding(.horizontal, V.S.pageGutter)
    }

    // MARK: 动作

    @MainActor
    private func refresh() async {
        guard let kc else { return }
        busy = true
        // cmd03 快照落盘（DB.readStatus 的数据源），供面板与双侧快照用。
        // 失败要说出原因（feedback 闸门）：读不到 ≠ 没有，可能是没连上。
        do {
            _ = try await app.lockLink.getStatus(mac: kc.mac)
        } catch {
            message = "读状态失败：\((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
        }
        status = DB.readStatus(kc.mac)
        // 拉最近一页日志（cmd16），筛出凭证变更类。
        do {
            let page = try await app.lockLink.getLogs(orderType: 0, startIdx: 0, pageSize: 20)
            logs = page.logs.filter { [14, 15, 20, 21].contains($0.type) }
        } catch {
            message = "读日志失败：\((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
        }
        busy = false
    }

    @MainActor
    private func repair() async {
        guard let kc else { return }
        busy = true
        message = nil
        do {
            _ = try await app.lockLink.repairPool(m: DB.normalizeMac(kc.mac)) { _ in }
            message = "修池完成 —— 开锁凭证已重签，请再按一次开锁"
        } catch {
            message = "修池失败：\((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
        }
        busy = false
        await refresh()
    }
}
