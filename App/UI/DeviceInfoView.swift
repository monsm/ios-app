// 锁信息名片（诊断；**进页会自动校时：偏差 >2s 才写锁**，见 reload() L262-269）
// 2026-10-30 修正（第 117 轮）：原头注写「只读诊断」与实现不符。
// 2026-10-29 从 Sheets.swift 拆出。BattSpark 是同文件私有类型，随宿主一起走
import SwiftUI

struct DeviceInfoView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
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
                    BusyButton(title: "重新读取", systemImage: "arrow.clockwise", isBusy: busy) {
                        Task { await reload() }
                    }
                } footer: {
                    Text("静音模式、安全模式 A/B、校时、防尾随与固件升级都在「设备页 → 管理这把锁」里；布防在设备页圆盘下方那一行。")   // 2026-10-30：布防已移出锁设置，原句把它也算进来是错的
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
            Text("锁钟偏差较大时临时密码与时间窗凭证会失效， 可到快捷操作「校准时间」。Boot / 键盘版本只在锁上报时出现，这两行缺失表示该固件不报这两支，不是读取失败。")
        }
    }

    // 运行状态: 数值旁标注采样时间 (291), 容量读协议容量族 (773)
    @ViewBuilder
    private var statusSection: some View {
        // 2026-10-29 补：`LinkSense.envConclusion` 零调用 —— 它算的是「近一次扫描见到多少台 BLE
        // 设备」，用来解释「为什么这台锁有时连不上」。放在锁信息名片里（诊断语义最贴的地方）。
        Section("连接环境") {
            Label {
                Text(LinkSense.envConclusion())
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.textSub)
        }
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
        return "电量走势： \(sp.count) 个采样点 · 跨 \(days) 天 · 最低 \(lo)% / 最高 \(hi)%"   // 45 电量走势
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
                Text("耗材提醒： 电量 \(p289)%, 建议备一枚\(meta.batteryModel.isEmpty ? "对应型号" : meta.batteryModel)电池。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("电池档案")
        } footer: {
            Text("记录电池型号与换电日期， 换电池时心里有数 (仅本机台账， 不写入门锁)。")
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
        return "已验证 · " + DF.localShort(Date(timeIntervalSince1970: t))
    }
    private var driftText: String {
        guard let d = clockDrift else { return "—" }
        if d == 0 { return "与手机一致" }
        return (d > 0 ? "+" : "") + "\(d) 秒"
    }
    private var batteryDateText: String {
        guard meta.batteryChangedAt > 0 else { return "点击记录" }
        return DF.localDate(Date(timeIntervalSince1970: meta.batteryChangedAt))
    }
    private var sampleText: String {
        // 291 采样时间: 快照与电量采样取最新
        let at = max(LockStats.snapAt(kc?.mac ?? ""), BatteryCare.latest(kc?.mac ?? "")?.t ?? 0)
        return at > 0 ? LockStats.sampleTimeText(at) : "尚未读取过快照"
    }
    /// 45: 电量趋势的诚实占位 — 采样埋点已开, 曲线等数据积累
    private var trendText: String {
        let n = BatteryCare.samples(kc?.mac ?? "").count
        return n == 0 ? "电量趋势： 尚无采样， 每次连接自动记录" : "电量趋势： 已积累 \(n) 个采样点， 曲线待数据更满"
    }
    /// 1019 固件服役天数 (从本机首次读到该版本起算)
    private var fwAgeText: String {
        guard let kc else { return "—" }
        var fw = kc.fw
        if let f = status?.firmware, !f.isEmpty { fw = f }
        guard let s = BatteryCare.fwSince(kc.mac, fw: fw) else { return "首次读到后起算" }
        let days = Int(Date().timeIntervalSince1970 * 1000 - s.at) / 86_400_000
        return days > 365 ? "\(days) 天 · 已超一年， 建议读读发行说明" : "\(days) 天"
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
            // 2026-10-30 修复（第 138 轮）：`ensureConnected` 与 `getStatus` 两次 await 之间若用户切了锁，
            // 本页 body 的 kc 已是新锁、`status` 却是旧锁读数 —— 同一屏混两把锁的数据。不一致就丢弃。
            guard app.currentMac == kc.mac else { return }
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
                    app.lock.log("info", "自动校时完成： 校前偏差 \(res.before)s, 校后偏差 \(res.after)s")
                    status = try await app.lock.getStatus()
            // 2026-10-30 修复（第 138 轮）：`ensureConnected` 与 `getStatus` 两次 await 之间若用户切了锁，
            // 本页 body 的 kc 已是新锁、`status` 却是旧锁读数 —— 同一屏混两把锁的数据。不一致就丢弃。
            guard app.currentMac == kc.mac else { return }
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