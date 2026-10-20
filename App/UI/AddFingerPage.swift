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

            ScrollView {
                VStack(spacing: XSpace.xl) {
                    if doneBatch != nil {
                        successStage
                    } else {
                        ownerPicker
                        fingerprintStage
                        if !error.isEmpty { errorBanner }
                        actionArea
                    }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
        }
        .navigationTitle("录入指纹")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            owner = prefillOwner
            breathe = true
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
                    .animation(.easeOut(duration: 0.6), value: ripple)

                // 中心指纹
                Image(systemName: "touchid")
                    .font(.system(size: 96, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: presses.isEmpty
                                ? [XPalette.textTertiary, XPalette.textTertiary.opacity(0.6)]
                                : [XPalette.accent, XPalette.accent.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom))
                    .scaleEffect(breathe ? 1.03 : 0.97)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)
                    .shadow(color: presses.isEmpty ? .clear : XPalette.accent.opacity(0.4),
                            radius: presses.isEmpty ? 0 : 20)

                // 计数
                VStack {
                    Spacer()
                    Text("\(min(presses.count, total)) / \(total)")
                        .vkFont(.title3, weight: .semibold)
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
                    .vkFont(.headline)
                    .foregroundStyle(XPalette.text)
                    .contentTransition(.opacity)
                    .animation(XMotion.soft, value: presses.count)

                Text("将手指按在门锁指纹头上, 重复 8 次")
                    .vkFont(.footnote)
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

    private var ownerPicker: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                HStack(spacing: XSpace.s) {
                    Image(systemName: "person")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                        .accessibilityHidden(true)
                    Text("这枚指纹属于谁")
                        .vkFont(.subheadline, weight: .medium)
                        .foregroundStyle(XPalette.text)
                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: XSpace.s) {
                        ownerChip(nil, "未归属")
                        ForEach(DB.members()) { m in
                            ownerChip(m.id, MemberHub.display(m))
                        }
                    }
                }
            }
        }
    }

    private func ownerChip(_ id: String?, _ label: String) -> some View {
        let selected = owner == id
        return Button {
            owner = id
            XHaptics.tick.impactOccurred()
        } label: {
            Text(label)
                .vkFont(.footnote, weight: selected ? .semibold : .regular)
                .foregroundStyle(selected ? XPalette.onAccent : XPalette.text)
                .padding(.horizontal, XSpace.m)
                .padding(.vertical, XSpace.s)
                .background(Capsule().fill(selected ? XPalette.accent : XPalette.surfaceAlt))
                .overlay(Capsule().strokeBorder(selected ? .clear : XPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(XMotion.quick, value: selected)
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 动作
    // ═══════════════════════════════════════════════════════

    private var actionArea: some View {
        VStack(spacing: XSpace.m) {
            if busy {
                Text("正在与门锁通信…")
                    .vkFont(.footnote)
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
                    .vkFont(.caption2)
                    .foregroundStyle(XPalette.warn)
            }
        }
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: XSpace.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: XIcon.sm, weight: .semibold))
                .foregroundStyle(XPalette.danger)
                .accessibilityHidden(true)
            Text(error)
                .vkFont(.footnote)
                .foregroundStyle(XPalette.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(XSpace.card)
        .background(XPalette.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: XRadius.control, style: .continuous))
    }

    // ═══════════════════════════════════════════════════════
    // MARK: - 成功
    // ═══════════════════════════════════════════════════════

    private var successStage: some View {
        VStack(spacing: XSpace.l) {
            ZStack {
                Circle()
                    .fill(XPalette.ok.opacity(0.12))
                    .frame(width: 180, height: 180)
                Image(systemName: "checkmark")
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(XPalette.ok)
            }
            .transition(.scale(scale: 0.8).combined(with: .opacity))

            Text("添加成功")
                .vkFont(.title2, weight: .semibold)
                .foregroundStyle(XPalette.text)

            Text("请用这枚新指纹开一次锁, 确认它能用")
                .vkFont(.footnote)
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
                DS.Haptics.tick.impactOccurred()
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
            self.error = error.localizedDescription
            XHaptics.failure()
        }
    }
}
