// ShareToAndroidHomeScreen.swift —— 分享给安卓（扫码导入）（V8 设计语言）
//
// 与 ShareToAndroidScreen 的能力对齐：把「锁身份 + 本机钥匙串里的开锁凭证 + 一次性口令」
// 做成一张二维码；缺开锁凭证时**不生成假码**，而是把缺什么、下一步做什么说清楚。
// 数据仍来自 AppModel.lock 与 AppModel.keys 里 kind == .mobile 的条目；二维码仍走 KeysQR。
//
// 与旧页的刻意差异：
//   ① 空壳模式（DB.isDecoy）下不生成二维码：app.currentKeychain 在空壳里仍返回真锁，
//      旧页会照样把真实 ekey 编成二维码摊在屏幕上 —— 与「空壳只隐藏」相反。
//   ② 页面顶部的「还不能分享」与卡片里的原因分开说：页头不再同时出现两种结论。
//   ③ 只读试验模式不影响本页：生成与分享都是本机只读动作，不往门锁写。
import SwiftUI
import UIKit

struct ShareToAndroidHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State private var qr: UIImage?
    @State private var payloadText = ""
    @State private var copied = false

    private var decoyed: Bool { DB.isDecoy }

    /// 可交付的钥匙：本机签发、未停用、未过期，且带 ekey。
    private var deliverable: KeyItem? {
        let now = KeysState.now()
        return app.keys
            .filter { $0.kind == .mobile && !$0.disabled && !KeysState.expired($0, now: now) }
            .filter { ($0.code ?? "").isEmpty == false }
            .sorted { ($0.expiresAt ?? Int64.max) > ($1.expiresAt ?? Int64.max) }
            .first
    }

    private var judgement: String {
        if decoyed { return "空壳模式下不生成配对码" }
        if app.lock == nil { return "还没有门锁" }
        if qr == nil { return "还不能分享" }
        return "可以扫码导入"
    }

    private var lead: String {
        if decoyed {
            return "空壳模式只隐藏数据，不改动数据。退出空壳后才能生成配对码。"
        }
        if app.lock == nil {
            return "分享是把这把锁的钥匙递给安卓。先添加门锁并走完配网，这里才有东西可分享。"
        }
        if qr == nil {
            return "缺一把可交付的手机钥匙。下面写清了缺什么、下一步做什么 —— 这里不放一张开不了门的码。"
        }
        return "让对方的安卓 App 扫这张码。谁扫到它，谁就能开这把锁。"
    }

    var body: some View {
        VPage(title: judgement, lead: lead) {
            EmptyView()
        } content: {
            if decoyed {
                decoyCard
            } else if app.lock == nil {
                VEmpty(
                    title: "还没有添加门锁",
                    reason: "分享是把这把锁的钥匙递给安卓。先添加门锁并走完配网，这里才有东西可分享。",
                    actionTitle: "添加门锁"
                ) { router.request(.dest(.addLock)) }
            } else if let image = qr {
                qrCard(image)
                shareCard
            } else {
                blockedCard
            }
            riskCard
        }
        .background(V8.C.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .captureShield("这张二维码是开锁钥匙\n屏幕正在被录制或截图，已遮挡")
        .onAppear(perform: build)
        .onChange(of: app.lock?.id) { _, _ in build() }
    }

    // MARK: - 生成载荷（会话级口令 + 锁身份 + 钥匙）

    private func build() {
        guard !DB.isDecoy else {
            qr = nil
            payloadText = ""
            return
        }
        guard deliverable != nil else {
            qr = nil
            payloadText = ""
            return
        }
        guard let kc = app.currentKeychain, let p = AndroidPair.payload(kc) else {
            qr = nil
            payloadText = ""
            return
        }
        payloadText = p
        qr = KeysQR.image(p)
    }

    // MARK: - 主角：二维码

    private func qrCard(_ image: UIImage) -> some View {
        VCard2 {
            VCardHead(eyebrow: "配对二维码", statement: "让对方的安卓 App 扫这张码", trailing: "一次性")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: V8.G.heroOuter)
                .frame(maxWidth: .infinity)
                .padding(.top, V8.S.gapM)
                .accessibilityLabel("这把锁的配对二维码")
            VStack(spacing: 0) {
                VDataRow(tag: "锁", tagTint: V8.C.ink4, title: app.lock?.name ?? "—", value: "")
                VDotRule()
                VDataRow(tag: "型号", tagTint: V8.C.ink4, title: app.lock?.model ?? "—", value: "")
                VDotRule()
                VDataRow(tag: "MAC", tagTint: V8.C.ink4, title: app.lock?.id ?? "—", value: "")
                VDotRule()
                VDataRow(tag: "载荷", tagTint: V8.C.ink4, title: "mac / pid / ekey", value: "")
            }
            .padding(.top, V8.S.gapL)
            Text("这串是「本机钥匙串里的那枚开锁凭证」+ 锁身份，不是上方那把手机钥匙 —— 扫完能开这把锁，但有效期与本机这把相同。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shareCard: some View {
        VCard2 {
            VCardHead(eyebrow: "交付方式", statement: copied ? "已复制配对串" : "分享或复制")
            VDivider2()
                .padding(.top, V8.S.gapM)
            ShareLink(item: payloadText,
                      preview: SharePreview("配对码", image: Image(systemName: "qrcode"))) {
                HStack(spacing: V8.S.gapS) {
                    Image(systemName: "square.and.arrow.up")
                        .font(V8.T.chipValue)
                        .accessibilityHidden(true)
                    Text("分享这段配对串")
                        .font(V8.T.tab)
                }
                .foregroundStyle(V8.C.chipOn)
                .frame(maxWidth: .infinity)
                .frame(minHeight: V8.H.min)
                .background(Capsule(style: .continuous).fill(V8.C.accent))
            }
            .accessibilityLabel("分享配对串")
            .padding(.top, V8.S.gapM)
            Button {
                Clip.set(payloadText)
                copied = true
            } label: {
                Text(copied ? "已复制" : "复制配对串")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.ink1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.chipOff))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("复制配对串")
            .padding(.top, V8.S.gapS)
            Text("这串是安卓配对码（含 mac / pid / ekey，刻意不含 skey）。当面扫、单独发给本人，不要发群里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 未就绪：说清缺什么 + 给下一步

    private var blockedCard: some View {
        VCard2 {
            VCardHead(eyebrow: "就绪度", statement: "缺一把可交付的手机钥匙", trailing: "缺 1 样")
            VDivider2()
                .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                .init(label: "锁", value: app.lock?.model ?? "—"),
                .init(label: "手机钥匙", value: "缺")
            ])
            .padding(.top, V8.S.gapM)
            Text(blockedReason)
                .font(V8.T.body)
                .foregroundStyle(V8.C.warn)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            VNavRow(title: "去签一把手机钥匙", detail: "签发后回本页重新生成") {
                router.request(.dest(.mobileKey))
            }
            .padding(.top, V8.S.gapS)
        }
    }

    private var blockedReason: String {
        let now = KeysState.now()
        let mobile = app.keys.filter { $0.kind == .mobile }
        if deliverable != nil {
            return "本机钥匙串里没有可用的开锁凭证 —— 可能是配网没走完，或钥匙串被清掉。请重新添加这把锁。"
        }
        if mobile.isEmpty {
            return "安卓端要拿到一把本机签发的手机钥匙才能开门。现在一把都没有，所以这里不放一张开不了门的码。"
        }
        if mobile.allSatisfy({ $0.disabled }) {
            return "这把锁的手机钥匙都被停用了 —— 停用的钥匙开不了门，所以这里不放码。到凭证页重新启用，或签一把新的。"
        }
        if mobile.allSatisfy({ KeysState.expired($0, now: now) }) {
            return "这把锁的手机钥匙都已过期 —— 过期的钥匙开不了门，所以这里不放码。先签一把新的，再回来。"
        }
        if mobile.allSatisfy({ ($0.code ?? "").isEmpty }) {
            return "手机钥匙记录里没有 ekey —— 本机没存下可交付的开锁凭证（可能是旧备份恢复的）。请在凭证页重新签一把。"
        }
        return "没有可交付的手机钥匙：需要一把未停用、未过期、且带 ekey 的。请到凭证页检查。"
    }

    // MARK: - 风险说明（真状态，不是装饰）

    private var riskCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "这张码等于一把钥匙", statement: "别截图存相册")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("谁扫到它，谁就能开这把锁。只当面扫，或单独发给本人；别截图存相册、别发到群里。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapFootnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var decoyCard: some View {
        VCard2(style: .well) {
            VCardHead(eyebrow: "分享给安卓", statement: "空壳模式不生成配对码")
            VDivider2()
                .padding(.top, V8.S.gapM)
            Text("空壳模式（胁迫码进入）下不生成任何配对码 —— 二维码里是本机钥匙串的真实开锁凭证，不能出现在被胁迫的屏幕上。")
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
            Text("退出空壳请在本机密码界面输入正常密码。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink4)
                .padding(.top, V8.S.gapS)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
