// LockSettingsScreen.swift —— 锁设置（门 · 这一把锁的策略页，含原「防尾随」页）。
//
// 这屏干什么：只放**锁端策略** —— 静音、临时密码开关、防尾随 2–6 秒档（吸收原「防尾随」页）、
//   安全模式入口、清空全部密码。
// 不放在这里的（2026-11-02 合并，见 _audit/ui-ia.md §5.1）：
//   · 电量 / 固件 / 锁钟偏差 → 归「锁实况」（本页原先各有一份，与那一页重复）；
//   · 容量族 / Boot / 键盘版本 → 归「锁信息名片」；安全模式的切换控件 → 归「锁实况」。
// 数据从哪来：AppModel.lock / DB.readStatus / LockService.getStatus（进页静默读一次）；
//   写入一律 ensureConnected → 成功才回写本机键（失败不假装成功）。
// 主动作：本屏没有强主色按钮 —— 每个策略都是独立写动作；「清空全部密码」单独红色危险区。
import SwiftUI

struct LockSettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var status: LockStatus?
    @State private var otpOn = false
    @State private var muted = false
    @State private var autoLock = 6
    @State private var busy = false
    @State private var outcome: String?
    @State private var clearConfirm = false
    @State private var clearTyped = ""
    @State private var tailgateLoaded = false
    /// 防尾随档位是否正在下发。
    @State private var tailgateSaving = false

    private var mac: String { app.lock?.id ?? "" }

    var body: some View {
        // 全换系统（2026-11-02）：整页容器是系统 `List`（与门页同一配方）。
        // 策略卡片用 `plainRow()` 保持原样；「更多」入口清单是**行式内容**，改走 `Section` + `VListRow`。
        // 不再「ScrollView 里嵌 List」：那样要么双滚、要么手算行高，Dynamic Type 一大就裁。
        List {
            header.headerRow()
            if app.lock == nil {
                noLockCard.cardRow()
            } else {
                policyCard.cardRow()
                tempCodeCard.cardRow()
                entriesSection
                readCard.cardRow()
                dangerCard.cardRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, V.Page.topSpace, for: .scrollContent)
        .contentMargins(.bottom, V.S.gapM, for: .scrollContent)
        .background(V.C.bg.ignoresSafeArea())
        .navigationTitle("锁设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("清空全部密码？", isPresented: $clearConfirm) {
            Button("取消", role: .cancel) { clearTyped = "" }
            Button("清空密码", role: .destructive) {
                if clearTyped == "清空" { Task { await runClearPwd() } }
            }
        } message: {
            Text("会把这把锁里的所有密码作废（指纹保留），本机密码台账同时清空。这一步不可撤销，请键入「清空」两个字确认。")
        }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            Text("锁设置")
                .font(V.F.displayA)
                .foregroundStyle(V.C.text1)
            Text(app.lock.map { "\($0.name) · \($0.model)" } ?? "还没有门锁")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text3)
        }
        // 页头走 headerRow()（它自带 .padding(.horizontal, pageGutter)）——
        // 这里原来的 pageGutterA 必须删掉，否则 16+16=32pt。
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var noLockCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapM) {
                Text("还没有门锁可设置")
                    .font(V.F.displayB)
                    .foregroundStyle(V.C.text1)
                Text("锁设置改的是具体一把锁的锁端策略：先添加并配对门锁，再回这一页。")
                    .font(V.F.body)
                    .foregroundStyle(V.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VActionButton(title: "添加门锁", systemImage: "plus") {
                    router.request(.dest(.addLock))
                }
            }
        }
    }

    // MARK: - 读取（本页只剩策略，读数归「锁实况 / 锁信息名片」）

    /// 一条只读回执：告诉用户「读到没有 / 在跟谁通信」，不再把电量固件摊一遍。
    private var readCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                HStack(spacing: V.S.gapS) {
                    if busy {
                        ProgressView().controlSize(.small).tint(V.C.blue)
                        Text("正在与门锁通信…")
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                    } else if let outcome {
                        Text(outcome)
                            .font(V.F.footnote)
                            .foregroundStyle(V.C.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("策略页只改锁端设置；电量 / 固件 / 锁钟在「锁实况」。")
                            .font(V.F.unit)
                            .foregroundStyle(V.C.text3)
                    }
                    Spacer(minLength: 0)
                }
                VOutlineButton(title: "重新读取锁状态", systemImage: "arrow.clockwise") {
                    Task { await load(force: true) }
                }
                .disabled(busy)
            }
        }
    }

    // MARK: - 临时码开关（cmd19）

    private var tempCodeCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "临时密码")
                Text("开通后，锁端按周期接受 ZOTP 动态临时密码；关闭则所有动态码立即失效。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                // ui-ia 4.1 R15：cmd19 的写入口只保留一处（动态密码页）。
                // 原来这里和 ZotpScreen:80 各有一个开关，改同一个锁端位 —— 两个入口两套回执，
                // 用户在一页关掉、到另一页看还显示「已开通」就会以为没生效。这里改只读 + 跳转。
                VValueRow(label: "开通状态", value: otpOn ? "已开通" : "已关闭",
                          note: otpOn ? "锁端会接受 ZOTP 动态码" : "关闭状态下生成的码不会被锁接受")
                VOutlineButton(title: "去「动态密码」页开关并生成", systemImage: "clock.badge.questionmark") {
                    router.request(.dest(.zotp))
                }
            }
        }
    }

    // MARK: - 锁端策略：静音 / 防尾随（吸收原「防尾随」页）/ 安全模式入口

    private var policyCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "锁端策略")
                // ui-ia 4.1 R14：cmd18 的写入口只保留一处（锁实况页 :303）。
                // 原来这里与 LockStatusScreen 各有一个静音开关，改同一个锁端位 —— 两处各自刷新，
                // 在 A 页切完到 B 页仍显示旧值（LockStatusScreen 读 app.lock.muted 投影）。
                // 这里改只读 + 跳转，写入口收敛到锁实况。
                VValueRow(label: "静音", value: muted ? "开" : "关",
                          note: muted ? "键盘与开锁不提示音" : "正常提示音")
                VOutlineButton(title: "去「锁实况」切换静音", systemImage: "speaker.slash") {
                    router.request(.dest(.lockStatus))
                }
                VRowDivider()
                tailgateSection
                VRowDivider()
                // 安全模式文案的唯一来源是 Reading.lockMode（内部就是 LockMode.text，传的是快照值）。
                VValueRow(label: "安全模式", value: Reading.lockMode(mac).text, note: "A 模式单验、B 模式双验；切换要连上锁并回读确认。")
                VOutlineButton(title: "去「锁实况」切换安全模式", systemImage: "lock.rotation") {
                    router.request(.dest(.lockStatus))
                }
            }
        }
    }

    /// 防尾随 / 自动上锁：2–6 秒档原地选 + 一键下发（原「防尾随」页的全部能力，不再单开一页）。
    @ViewBuilder
    private var tailgateSection: some View {
        VStack(alignment: .leading, spacing: V.S.gapS) {
            Text("防尾随 / 自动上锁")
                .font(V.F.bodyStrong)
                .foregroundStyle(V.C.text1)
            Text("电控开锁后等待几秒自动上锁。档位 2–6 秒；等太久就是尾随者能挤进门的那几秒。")
                .font(V.F.footnote)
                .foregroundStyle(V.C.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: V.S.gapS) {
                ForEach(2 ... 6, id: \.self) { value in
                    Button {
                        autoLock = value
                    } label: {
                        VTag(text: "\(value) 秒",
                             tint: autoLock == value ? V.C.blue : V.C.text3,
                             filled: autoLock == value)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(autoLock == value ? [.isButton, .isSelected] : .isButton)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, V.S.gapXS)
            VOutlineButton(title: tailgateSaving ? "正在下发…" : "设为 \(autoLock) 秒自动上锁",
                           systemImage: "timer") {
                Task { await saveTailgate() }
            }
            .disabled(tailgateSaving || busy || !canTailgate)
            if !canTailgate {
                Text("这把锁的型号或固件不支持防尾随（V1 Pro 需固件 1.0.3 以上）。")
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canTailgate: Bool {
        guard let kc = app.currentKeychain else { return false }
        return PidMap.canTailgate(kc.pid, fw: kc.fw)
    }

    /// 防尾随下发：ensureConnected → cmd24 → 成功才落本机键（失败如实说）。
    private func saveTailgate() async {
        // E-07：await 期间换锁会把 kf_tailgate_ 写到另一把锁。
        let mac = self.mac
        let seconds = autoLock
        guard !mac.isEmpty, !tailgateSaving else { return }
        tailgateSaving = true
        outcome = nil
        defer { tailgateSaving = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.setAutoLock(seconds)
            DB.saveTailgate(mac, TailgateCfg(interval: seconds, at: Date().timeIntervalSince1970 * 1000))
            outcome = "设置成功：开锁后 \(seconds) 秒自动上锁"
        } catch {
            outcome = "设置失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - 入口（行式内容 → 系统 Section；整页已是 List，不再套第二层）

    private var entriesSection: some View {
        Section {
            VListRow(title: "锁信息名片", detail: "固件 / 容量 / 电量采样 / 链路验证", systemImage: "info.circle", tint: V.C.miniBlue) {
                router.request(.dest(.deviceInfo))
            }
            VListRow(title: "电池档案", detail: "电量采样 / 五档 / 电池型号与换电日期", systemImage: "battery.75percent", tint: V.C.rewardGreen) {
                router.request(.dest(.batteryProfile))
            }
            VListRow(title: "锁档案", detail: "昵称 / 符号 / 色标 / 分组 / 解锁 PIN", systemImage: "lock.rectangle", tint: V.C.purple) {
                router.request(.dest(.lockProfile))
            }
            VListRow(title: "全部锁", detail: "多锁统计 / 分组 / 排序", systemImage: "square.stack.3d.up", tint: V.C.miniBlue) {
                router.request(.dest(.lockPortfolio))
            }
            // 「校时」已并入「锁实况」：这里指向锁实况（`.dest(.syncTime)` 现在也重定向到它，
            // 但入口名留着「校时」会让用户以为还是单独一页）。
            VListRow(title: "锁实况 · 校时 / 安全模式", detail: "锁钟偏差、同步时间、A / B 模式", systemImage: "clock.arrow.circlepath", tint: V.C.rewardBlue) {
                router.request(.dest(.lockStatus))
            }
            VListRow(title: "固件升级", detail: "本地固件包 · Nordic DFU", systemImage: "arrow.up.circle", tint: V.C.coral) {
                router.request(.dest(.dfu))
            }
        } header: {
            Text("更多")
                .font(V.F.section)
                .foregroundStyle(V.C.text1)
        }
    }

    // MARK: - 危险区：清空全部密码（0A delAlias=FFFF）

    private var dangerCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: V.S.gapS) {
                VCardHeader(title: "危险操作", showsChevron: false)
                Text("清空全部密码会把锁里所有密码作废（指纹保留），并同时清空本机密码台账。清空后需要重新逐条添加。")
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VTextFieldRow(label: "键入「清空」确认", text: $clearTyped, placeholder: "清空")
                VOutlineButton(title: "清空全部密码", systemImage: "delete.left", tint: V.C.red) {
                    clearConfirm = true
                }
                .disabled(clearTyped != "清空" || busy || !canClearPwd)
                .opacity(clearTyped == "清空" ? 1 : 0.45)
                if !canClearPwd {
                    Text("这把锁的型号不支持清空密码。").font(V.F.footnote).foregroundStyle(V.C.text3)
                }
            }
        }
    }

    private var canClearPwd: Bool {
        guard let kc = app.currentKeychain else { return false }
        return PidMap.canClearPwd(kc.pid)
    }

    // MARK: - 读

    private func load(force: Bool = false) async {
        guard !mac.isEmpty, !busy else { return }
        otpOn = DB.otpStatus(mac)?.on ?? false
        muted = DB.store.getBool("kf_muted_" + mac)
        if !tailgateLoaded {
            autoLock = DB.tailgate(mac)?.interval ?? 6
            tailgateLoaded = true
        }
        guard force || status == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let st = try await LockService.shared.getStatus(mac: mac)
            status = st
            DB.writeStatus(mac, st)
            muted = st.soundVolumn > 0 || muted
            outcome = "已读取锁实况"
        } catch {
            outcome = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }


    private func runClearPwd() async {
        let mac = self.mac   // E-07：await 期间换锁不能把清空动作落到另一把锁的台账
        guard !mac.isEmpty, !busy else { return }
        busy = true
        outcome = nil
        defer { busy = false }
        do {
            try await LockService.shared.ensureConnected(mac: mac)
            try await LockService.shared.pwdClear()
            var l = DB.ledger(mac)
            l.pwds = []
            DB.saveLedger(mac, l)
            app.reloadKeys(mac)
            clearTyped = ""
            outcome = "已清空全部密码（指纹保留）"
            AppToast.shared.show("已清空全部密码", tone: .ok)
        } catch {
            outcome = "清空失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("LockSettingsScreen") {
    NavigationStack { LockSettingsScreen() }
        .environment(AppModel())
        .environment(Router())
}
