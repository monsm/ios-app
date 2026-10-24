// 「分享给安卓」—— 把当前这把锁的开锁凭证渲染成二维码, 供安卓 App 扫码导入。
//
// 为什么要有这一页: 安卓那端是极简版 (只有"点一下开锁"和"靠近自动开锁"), 它不该再走一遍配网 ——
// 配网要 skey/PIN 与锁面对面重置, 而这两件事 iOS 端早就做完了。二维码只是把**结果**递过去。
import CoreImage.CIFilterBuiltins
import SwiftUI

struct ShareToAndroidView: View {
    @Environment(\.dismiss) private var dismiss
    let kc: Keychain

    @State private var qr: UIImage?
    @State private var payload = ""
    @State private var failed = ""

    private var title: String { AndroidPair.displayName(kc) }
    private var macText: String {
        // 显示序 (AA:BB:CC:DD:EE:FF) 只用于给人核对, 载荷里是去冒号的小写
        let m = kc.mac.lowercased()
        guard m.count == 12 else { return m }
        return stride(from: 0, to: 12, by: 2).map { String(m.dropFirst($0).prefix(2)) }.joined(separator: ":").uppercased()
    }

    var body: some View {
        NavigationStack {
        // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
        XScreen("分享给安卓", subtitle: "这把锁的开锁二维码") {
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)          // 二维码放大必须硬边, 插值会糊掉模块
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .padding(XSpace.m)
                    // 二维码的静区必须是白的, 且**不要圆角**: 这一块刻意不跟随明暗主题,
                    // 否则深色下扫不出来; 圆角会切掉三个定位角上的静区, 反而更难认。
                    // glass-audit:allow QR 不是界面表面 —— 它是给摄像头读的图形,
                    //   白底是 ISO/IEC 18004 的静区要求, 不是"页面用了白卡"。
                    .background(XPalette.qrQuietZone)
                    .accessibilityLabel("这把锁的开锁二维码")

                VStack(spacing: 2) {
                    Text(title)
                        .xFont(.headline)
                        .foregroundStyle(XPalette.text)
                    Text(macText)
                        .xFont(.caption)
                        .foregroundStyle(XPalette.textSub)
                }

                Text("在安卓 App 里点「扫码添加」扫这张码。导入之后, 点一下开锁和靠近开锁都不再需要它。")
                    .xFont(.footnote)
                    .foregroundStyle(XPalette.textSub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Label {
                    Text("这张码等于一把钥匙: 只当面给自己人扫, 不要发群里、不要截图外传。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.shield.fill").accessibilityHidden(true)
                }
                .xFont(.footnote)
                .foregroundStyle(XPalette.warn)
                .padding(XSpace.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .xCallout(XPalette.warn, .control, wash: 0.10)

                // HTML 对齐 (2026-10-24): 补「关于这个码」卡 —— 有效期 / 作用 两列 + 说明。
                // parity 工具指出这一整卡在 App 里缺失。
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        Text("关于这个码")
                            .xFont(.subheadline)
                            .foregroundStyle(XPalette.textTertiary)
                        HStack(alignment: .top, spacing: XSpace.s) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("有效期")
                                    .xFont(.caption2)
                                    .foregroundStyle(XPalette.textTertiary)
                                Text("一次性")
                                    .xFont(.footnote, weight: .semibold)
                                    .foregroundStyle(XPalette.ok)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("作用")
                                    .xFont(.caption2)
                                    .foregroundStyle(XPalette.textTertiary)
                                Text("导入钥匙")
                                    .xFont(.footnote, weight: .semibold)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("二维码里是这把锁的配对信息，扫一次就失效，重新生成会作废旧码。")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ShareLink(item: Image(uiImage: qr),
                          preview: SharePreview(title + " 的开锁二维码", image: Image(uiImage: qr))) {
                    Label("分享二维码", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(XPrimaryButtonStyle(fullWidth: true))
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: XIcon.xl))
                    .foregroundStyle(XPalette.textSub)
                    .accessibilityHidden(true)
                Text(failed.isEmpty ? "正在生成…" : failed)
                    .xFont(.footnote)
                    .foregroundStyle(failed.isEmpty ? XPalette.textSub : XPalette.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        }
        .onAppear(perform: build)
        .destined(.shareToAndroid)
    }

    private func build() {
        guard qr == nil else { return }
        guard let p = AndroidPair.payload(kc) else {
            // 没有 ekey 也没有可用的 PIN/skey = 这把锁本机签不出开锁凭证, 如实说, 不生成一张假码
            failed = "这把锁在本机没有可用的开锁钥匙 (ekey 与 PIN 都缺), 无法分享。请先在本机开一次锁, 或重新配网。"
            return
        }
        payload = p
        guard let img = Self.qrImage(p) else {
            failed = "二维码生成失败 (文本过长或系统滤镜不可用), 请重试。"
            return
        }
        qr = img
    }

    /// CIQRCodeGenerator + 整数倍放大。纠错档用 M: 屏幕对屏幕扫, 不需要 H 那种密度,
    /// 而 M 能让同样内容少几个模块、暗光下更好认。
    private static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
