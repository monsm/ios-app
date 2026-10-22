//
//  AddFingerPage.swift
//  录入指纹 · 全新重写 (2026-10-21)
//
//  ═══════════════════════════════════════════════════════════
//  视觉冲击力: 一枚会呼吸的指纹
//  ═══════════════════════════════════════════════════════════
//
//  旧版: ProgressView + 8 个小圆点 + 一行文字
//
//  新版: 中央一枚 180pt 指纹符号
//    · 待机: 细描边, 缓慢呼吸 (2.6s 循环)
//    · 按压中: 每收到一次按压, 指纹从中心亮起一圈涟漪
//    · 进度: 8 道同心圆弧, 每完成一次点亮一道
//    · 完成: 整枚指纹变铜色 + 光晕脉冲 + 成功触感
//
//  这是"按在锁上, 看不到屏幕"的场景 —— 所以触感与视觉必须同时给。
//

import SwiftUI
import UIKit

/// 录入指纹页
struct AddFingerPage: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var prefillOwner: String? = nil

    @State private var presses: [LockService.FpPress] = []
    @State private var enrollTask: Task<Void, Never>? = nil
    @State private var busy = false
    @State private var error = ""
    @State private var doneBatch: UInt32? = nil
    @State private var owner: String? = nil

    @State private var breathe = false
    @State private var ripple = false

    private let total = 8

    private var progress: CGFloat {
        CGFloat(min(presses.count, total)) / CGFloat(total)
    }

    var body: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        // 改前是手写 ScrollView + VStack(section) + 各自的 padding 与 background。
        XScreen("录入指纹", style: .inline) {
                if doneBatch != nil {
                    successStage.xScrollLift()
                } else {
                    capacityCard
                    ownerPicker.xScrollLift()
                    fingerprintStage.xScrollLift()
                    if !error.isEmpty { errorBanner.xScrollLift() }
                    actionArea.xScrollLift()
                }
        }
        }
        .onAppear {
            owner = prefillOwner
            // 减弱动态效果时不做呼吸循环 (HIG motion: 动效必须可关)
            if !reduceMotion { breathe = true }
        }
        .onDisappear {
            // 关页即取消: 不替用户做锁端写入
            enrollTask?.cancel()
            enrollTask = nil
        }
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 指纹舞台 (视觉主角)
    // ═══════════════════════════════════════════════════════

    private var fingerprintStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                // 外圈: 8 道进度弧
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .trim(from: CGFloat(i) / CGFloat(total) + 0.008,
                              to: CGFloat(i + 1) / CGFloat(total) - 0.008)
                        .stroke(
                            i < presses.count ? XPalette.accent : XPalette.hairline,
                            style: StrokeStyle(lineWidth: i < presses.count ? 5 : 2, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(XMotion.standard.delay(Double(i) * 0.03), value: presses.count)
                }

                // 涟漪 (每次按压扩散一次)
                Circle()
                    .stroke(XPalette.accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(ripple ? 1.35 : 1.0)
                    .opacity(ripple ? 0 : 0.8)
                    .animation(XMotion.standard, value: ripple)

                // 中心指纹
                //
                // 呼吸动画走 XBreathing 一处实现 —— 它自带 .transaction 切断隐式继承。
                // 此前这里是一段手写 repeatForever：与外层 .animation 抢 scaleEffect，
                // 表现为呼吸偶发顿挫（本仓 DESIGN-SPEC §2.5 记的就是这个坑）。
                XBreathing(scale: 1.03) {
                    Image(systemName: "touchid")
                        .font(.system(size: XMetric.decorIcon(96), weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(
                                colors: presses.isEmpty
                                    ? [XPalette.textTertiary, XPalette.textTertiary.opacity(0.6)]
                                    : [XPalette.accent, XPalette.accent.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom))
                }
                // 按下时「亮起来」用**辉光**，不用投影（规范 §6.3 注脚：黑底上唯一允许的阴影
                // 只有设备样机与全屏 Sheet 边缘；§7.8 也把环/指示物的亮规定为辉光）。
                // 辉光是径向渐变，投影是偏移的暗色 —— 在纯黑上后者只会把边缘糊脏。
                .background {
                    if !presses.isEmpty {
                        Circle()
                            .fill(XGradient.glow(XPalette.accent))
                            .frame(width: 220, height: 220)
                            .blur(radius: 24)
                            .allowsHitTesting(false)
                    }
                }

                // 计数
                VStack {
                    Spacer()
                    Text("\(min(presses.count, total)) / \(total)")
                        .xFont(.title3, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(presses.isEmpty ? XPalette.textSub : XPalette.accentText)
                        .offset(y: 120)
                }
                .frame(height: 200)
            }
            .frame(height: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("指纹录入进度")
            .accessibilityValue("\(min(presses.count, total)) / \(total) 次")

            VStack(spacing: XSpace.xs) {
                Text(progressText)
                    .xFont(.headline)
                    .foregroundStyle(XPalette.text)
                    .contentTransition(.opacity)
                    .animation(XMotion.soft, value: presses.count)

                Text("将手指按在门锁指纹头上, 重复 8 次")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var progressText: String {
        if presses.isEmpty { return "等待第一次按压" }
        if presses.count < total { return "还差 \(total - presses.count) 次" }
        return "已采集, 正在写入…"
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 归属
    // ═══════════════════════════════════════════════════════

    /// 指纹容量卡 —— 协议真实返回 fpStock / fpInfoCapacity，
    /// 录入前必须知道"还剩几个坑位"，否则录到一半才报满。
    @ViewBuilder
    private var capacityCard: some View {
        let mac = app.currentMac
        let snap = DB.readStatus(mac)
        let cap = snap?.fpCap ?? 0
        let left = snap?.fpStock ?? -1
        if cap > 0, left >= 0 {
            let used = max(0, cap - left)
            let full = left == 0
            XPanel(kind: .group, tone: full ? .warn : .neutral) {
                VStack(alignment: .leading, spacing: XSpace.xs) {
                    HStack(spacing: XSpace.s) {
                        Image(systemName: "touchid")
                            .font(.system(size: XIcon.sm, weight: .medium))
                            .foregroundStyle(full ? XPalette.warn : XPalette.textSub)
                        Text(full ? "指纹库存已满" : "还可录 " + String(left) + " 枚")
                            .xFont(.footnote, weight: .medium)
                            .foregroundStyle(full ? XPalette.warn : XPalette.textSub)
                        Spacer(minLength: 0)
                        Text(String(used) + " / " + String(cap))
                            .xFontExact(.caption2.monospacedDigit())
                            .foregroundStyle(XPalette.textSub)
                    }
                }
            }
            .xScrollLift()
        }
    }

    private var ownerPicker: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "person")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                        .accessibilityHidden(true)
                    Text("这枚指纹属于谁")
                        .xFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Spacer()
                }

                ScrollView(.horizontal) {
                    HStack(spacing: XSpace.s) {
                        ownerChip(nil, "未归属")
                        ForEach(DB.members()) { m in
                            ownerChip(m.id, MemberHub.display(m))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func ownerChip(_ id: String?, _ label: String) -> some View {
        let selected = owner == id
        // 该成员名下已有几枚指纹 —— 录入前该知道，
        // 避免同一个人重复录同一根手指（这页最常见的误操作）。
        let existing: Int = {
            guard let id else { return 0 }
            let mac = app.currentMac
            guard !mac.isEmpty else { return 0 }
            return DB.listFps(mac).filter { $0.owner == id }.count
        }()
        return Button {
            owner = id
            XHaptics.tick.impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .xFont(.footnote, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? XPalette.onAccent : XPalette.text)
                if existing > 0 {
                    Text(String(existing))
                        .xFontExact(.caption2.monospacedDigit(), weight: .semibold)
                        .foregroundStyle(selected
                                         ? XPalette.onAccent.opacity(0.8)
                                         : XPalette.textTertiary)
                }
            }
            .padding(.horizontal, XSpace.m)
            .padding(.vertical, XSpace.s)
            .background(Capsule().fill(selected ? XPalette.accent : XPalette.surfaceAlt))
            .overlay {
                Capsule().strokeBorder(selected ? .clear : XPalette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(XMotion.quick, value: selected)
        .accessibilityLabel(label
                            + (existing > 0 ? "，已有 " + String(existing) + " 枚指纹" : ""))
    }
    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private var actionArea: some View {
        VStack(spacing: XSpace.m) {
            if busy {
                Text("正在与门锁通信…")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
            }

            XBusyButton(
                title: busy ? "录入中…" : "开始录入",
                systemImage: "touchid",
                busy: busy,
                style: .primary
            ) {
                enrollTask = Task { await start() }
            }
            .disabled(busy || owner == nil)
            .opacity(owner == nil ? 0.5 : 1)

            if owner == nil {
                Text("请先选择归属再录入")
                    .xFont(.caption2)
                    .foregroundStyle(XPalette.warn)
            }
        }
    }

    // 行内错误条统一走 XInlineError（此前这里、钥匙工坊、网关页各写了一遍，三处尺寸都不同）
    private var errorBanner: some View {
        // J5 / §7.20.3：错误态要给「怎么办」。这里「怎么办」就是**再录一次** ——
        // 指纹录入失败绝大多数是手指没放稳或中途抬起，重试是有意义的动作。
        XInlineError(message: error, retry: {
            enrollTask = Task { await start() }
        }, retryTitle: "重新录入")
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 成功
    // ═══════════════════════════════════════════════════════

    private var successStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                Circle()
                    .fill(XPalette.ok.opacity(XOpacity.badge))
                    .frame(width: 180, height: 180)
                Image(systemName: "checkmark")
                    .font(.system(size: XMetric.decorIcon(76), weight: .light))
                    .foregroundStyle(XPalette.ok)
            }
            // 180pt 的圆环从 80% 放大，是本页位移最大的动画 ——
            // reduceMotion 下只保留淡入，不做缩放。
            .transition(reduceMotion ? .opacity
                                    : .scale(scale: 0.8).combined(with: .opacity))

            Text("添加成功")
                .xFont(.title2, weight: .semibold)
                .foregroundStyle(XPalette.text)

            Text("请用这枚新指纹开一次锁, 确认它能用")
                .xFont(.footnote)
                .foregroundStyle(XPalette.textSub)
                .multilineTextAlignment(.center)

            Button("完成") { dismiss() }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: false))
        }
        .padding(.top, XSpace.xxl)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 核心逻辑 (与旧实现逐字等价)
    // ═══════════════════════════════════════════════════════

    private func start() async {
        guard let kc = app.current else { app.showToast("请先选择门锁"); return }
        guard let owner else { error = "请先选择归属再录入"; return }
        guard !busy else { return }

        busy = true
        error = ""
        presses = []
        defer { busy = false }

        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            let ps = try await app.lock.fpStart(times: total, onPress: { p in
                self.presses.append(p)
                // 手指在锁上时看不到屏幕: 每次按压给轻触感 + 涟漪
                XHaptics.tick.impactOccurred()
                self.ripple = false
                DispatchQueue.main.async { self.ripple = true }
            })
            self.presses = ps
            self.ripple = false

            guard presses.count >= total else {
                throw NSError(domain: "fp", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "只收到 \(presses.count)/\(total) 次按压, 未写入; 请重新录入"
                ])
            }
            guard let batch = presses.compactMap({ $0.batchNumber }).first, batch > 0 else {
                throw NSError(domain: "fp", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "未拿到有效指纹批次, 请重新录入"
                ])
            }
            // 不可逆点前检查取消
            if Task.isCancelled {
                presses = []
                return
            }

            try await app.lock.fpConfirm(batch,
                                         validFrom: "2010-01-01 00:00:00",
                                         validTo: "2118-01-01 00:00:00")

            // 自动命名: 指纹N
            let existing = DB.listFps(kc.mac).compactMap { f -> Int? in
                guard let m = f.name.range(of: "指纹(\\d+)", options: .regularExpression) else { return nil }
                return Int(f.name[m].dropFirst(2))
            }
            let n = (existing.max() ?? 0) + 1
            DB.addFp(kc.mac, LedgerFp(
                batch: Int(batch), name: "指纹\(n)",
                at: Date().timeIntervalSince1970 * 1000,
                note: "", src: "app", owner: owner, isAlarm: false))

            XHaptics.success()
            doneBatch = UInt32(batch)
        } catch {
            // J5：错误面必须说人话。原来这里直抛 error.localizedDescription ——
        // 蓝牙层给的是 "write failed" / "response timeout" 这类工程术语，
        // 既没说什么坏了、也没说怎么办（`ErrorText` 就是为这个写的，19 处在用，这三处漏了）。
        self.error = ErrorText.human(error)
            XHaptics.failure()
        }
    }
}
