// ShareToAndroidScreen.swift —— 分享给安卓（扫码导入）。
//
// 这一屏干什么：把要交给安卓端的东西做成一张二维码：锁身份 + 本机签发的那把手机钥匙 + 一次性口令。
// 缺开锁凭证时**不生成假码**，而是把缺什么、下一步做什么说清楚（这是凭证分享的既定口径）。
// 数据从哪来：AppModel.lock（锁身份）+ AppModel.keys 里 kind == .mobile 的条目（本机签发的钥匙）。
// 主动作：有钥匙时是「分享二维码」；没钥匙时是「去签一把手机钥匙」—— 同一个位置，只有一个主动作。
import SwiftUI
import UIKit
import Foundation
import CoreImage.CIFilterBuiltins

struct ShareToAndroidScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    /// 二维码显示边长：由间距令牌推导（8 × 32），不写裸数值。
    private var qrMaxSide: CGFloat { T.S.xxl * 8 }

    @State private var qr: UIImage?
    @State private var payloadText = ""
    @State private var passphrase = ""
    @State private var copied = false

    /// 可交付的钥匙：本机签发、未停用、未过期。
    private var deliverable: KeyItem? {
        let now = KeysState.now()
        return app.keys
            .filter { $0.kind == .mobile && !$0.disabled && !KeysState.expired($0, now: now) }
            .filter { ($0.code ?? "").isEmpty == false }
            .sorted { ($0.expiresAt ?? Int64.max) > ($1.expiresAt ?? Int64.max) }
            .first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                if app.lock == nil {
                    noLockBlock
                } else if let key = deliverable, let image = qr {
                    qrBlock(image, key)
                    shareBlock
                } else {
                    blockedBlock
                }
                riskBlock
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("分享给安卓")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: build)
        .onChange(of: deliverable?.id) { _, _ in build() }
    }

    // MARK: 生成载荷（会话级口令 + 锁身份 + 钥匙）

    private func build() {
        guard let lock = app.lock, let key = deliverable else {
            qr = nil
            payloadText = ""
            return
        }
        if passphrase.isEmpty {
            passphrase = KeysCode.digits(8)
        }
        // TODO(engine): 真实信封是 CredPackage{v,mac,lockName,pwds,fps,at} 用口令做 AES 加密后的密文。
        // 加密引擎未接 —— 这里拼的是**明文配对串**，页面上如实写「未经加密，只能当面交给本人」。
        payloadText = [
            "OLK1",
            lock.id,
            lock.model,
            key.id,
            key.code ?? "",
            passphrase,
            "\(KeysState.now())",
        ].joined(separator: "|")
        qr = KeysQR.image(payloadText)
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: T.S.xs) {
            Text("分享给安卓")
                .font(T.F.display())
                .foregroundStyle(Ink.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: T.S.s) {
                StateDot(tone: qr == nil ? .attention : .ok,
                         word: qr == nil ? "还不能分享" : "可以扫码导入")
                Text(qr == nil ? "本机还没有可交付的钥匙" : "让对方的安卓 App 扫这张码")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: 主角：二维码

    private func qrBlock(_ image: UIImage, _ key: KeyItem) -> some View {
        Panel {
            VStack(spacing: T.S.m) {
                Image(uiImage: image)
                    .interpolation(.none)          // 二维码放大必须硬边，插值会糊掉模块
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: qrMaxSide)
                    .accessibilityLabel("这把锁的配对二维码")
                ReadingGrid(items: [
                    .init(label: "锁", value: app.lock?.model ?? "—"),
                    .init(label: "给谁", value: key.owner ?? "未归属"),
                    .init(label: "口令", value: String(repeating: "•", count: passphrase.count)),
                    .init(label: "有效期", value: KeysState.expiryReading(key, now: KeysState.now()).value,
                          unit: KeysState.expiryReading(key, now: KeysState.now()).unit),
                ])
                Text("扫完这台安卓就能开这把锁 —— 不用再走一次配网。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var shareBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                // SharePreview 的 image 必须是 Image（要 Transferable），挂不了无障碍修饰符 ——
                // 它是分享卡缩略图（系统渲染），语义由 title "配对码" 承载，本来就不进 VoiceOver 焦点。
                ShareLink(item: payloadText,
                          preview: SharePreview("配对码", image: Image(systemName: "qrcode"))) {
                    HStack(spacing: T.S.s) {
                        Image(systemName: "square.and.arrow.up")
                            .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                            .font(T.F.icon(T.Icon.m, weight: .medium))
                        Text("分享这段配对串")
                            .font(T.F.bodyStrong)
                    }
                    .foregroundStyle(Signal.on)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: T.Hit.min + T.S.s)
                    .background(Signal.base, in: .rect(cornerRadius: T.R.control))
                }
                .accessibilityLabel("分享配对串")
                SecondaryAction(
                    title: copied ? "已复制" : "复制配对串",
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                ) {
                    UIPasteboard.general.string = payloadText
                    copied = true
                }
                Text("这串还没加密（加密信封要等引擎接上）。当面扫、单独发给本人，不要发群里。")
                    .font(T.F.unit)
                    .foregroundStyle(Ink.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 未就绪：说清缺什么 + 给下一步

    private var blockedBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: "就绪度", trailing: "缺 1 样")
                ReadingGrid(items: [
                    .init(label: "锁", value: app.lock?.model ?? "—"),
                    .init(label: "手机钥匙", value: "缺", tint: State.attention),
                ])
                Divider().overlay(Ink.hairline)
                KeysInlineNote(tone: .attention, text: "安卓端要拿到一把本机签发的手机钥匙才能开门。现在一把都没有，所以这里不放一张开不了门的码。")
                KeysInlineNote(tone: .neutral, text: "手机钥匙 = 锁里一个 PIN 签出的开锁凭证。签完回到这一页，码就出来了。")
                PrimaryAction(title: "去签一把手机钥匙", systemImage: "iphone.gen3.badge.key") {
                    router.request(.dest(.mobileKey))
                }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 风险说明（真状态，不是装饰）

    private var riskBlock: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.s) {
                SectionLabel(text: "这张码等于一把钥匙")
                Text("谁扫到它，谁就能开这把锁。只当面扫，或单独发给本人；别截图存相册、别发到群里。")
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var noLockBlock: some View {
        Panel {
            EmptyPanel(
                title: "还没有添加门锁",
                message: "分享是把这把锁的钥匙递给安卓。先添加门锁并走完配网，这里才有东西可分享。",
                actionTitle: "添加门锁",
                systemImage: "door.left.hand.closed"
            ) {
                router.request(.dest(.addLock))
            }
            .padding(.vertical, T.S.xxl)
        }
        .padding(.horizontal, T.S.gutter)
    }
}

// MARK: - 二维码渲染（系统 CoreImage，无第三方依赖）

enum KeysQR {
    static func image(_ text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 10
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // 静区与白底烘进图里：扫码规范要求四周留白，深色模式下也必须白底黑码 ——
        // 这不是配色选择，是「能不能扫出来」。所以白只存在于这一张位图里，不进颜色令牌。
        // （HIG 审计把 CIColor(red:1,green:1,blue:1) 标为硬编码颜色 —— 这里是位图素材，
        //  不是界面颜色，不能走 Ink.plate：深色模式下 Ink.plate 是深灰，扫不出来。）
        let quiet: CGFloat = scale * 4
        let canvas = scaled.extent.insetBy(dx: -quiet, dy: -quiet)
        let paper = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: canvas)
        let composed = scaled.composited(over: paper)
        guard let cg = CIContext().createCGImage(composed, from: canvas) else { return nil }
        return UIImage(cgImage: cg)
    }
}