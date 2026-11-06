// MobileKeysScreen.swift —— 签发 / 吊销手机钥匙，以及交付用的二维码。
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

@MainActor
struct MobileKeysScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var memberID: String?
    @State private var forever = false
    @State private var days = 7
    @State private var busy = false
    @State private var errorLine: String?
    @State private var flash: String?
    @State private var sharing = false
    /// 待吊销的那把。非 nil 即弹确认 —— 吊销会**立刻**删掉锁端 PIN，
    /// 对方手机里的钥匙当场失效且无法撤销，不该被一次误触触发。
    @State private var revokeTarget: MobileKey?

    private var keys: [MobileKey] { MobileKeyService.list(app.currentMac) }
    private var members: [MemberCard] { app.members.filter { !$0.archived } }

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行 / 手机钥匙", back: { dismiss() })

            DisplayLine(text: keys.isEmpty ? "把钥匙\n发到手机里。" : "\(keys.count) 把钥匙\n已经发出。", size: 36)
                .padding(.top, 16)
            Text("手机钥匙是一枚带有效期的 ekey。它只能开这一把锁；吊销会把对应的 PIN 从锁里删掉。签发后点「复制」，把 ekey 单独发给对方。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .padding(.top, 8)

            SectionHead(index: "01", title: "签发一把")
            issueCard

            SectionHead(index: "02", title: "已发出", trailing: "\(keys.count)")
            if keys.isEmpty {
                EmptyNote(line: "还没有发出过。", detail: "选一位成员，给它一把只在约定时间内有效的钥匙。")
            } else {
                ForEach(keys) { key in
                    keyRow(key)
                }
            }

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            }

            if let flash {
                Text(flash)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.brass)
                    .padding(.top, 14)
            }

            Button {
                sharing = true
            } label: {
                ContentRow(symbol: "qrcode", tone: .cool,
                           title: "把这把锁交给安卓",
                           subtitle: "生成一张只含 ekey 的二维码，不含母钥", chevron: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $sharing) { HandoffSheet() }
        .confirmationDialog("吊销这把手机钥匙？", isPresented: confirmRevoke, titleVisibility: .visible) {
            Button("吊销", role: .destructive) {
                guard let key = revokeTarget else { return }
                revokeTarget = nil
                Task { await revoke(key) }
            }
            Button("取消", role: .cancel) { revokeTarget = nil }
        } message: {
            Text("锁端会删掉这枚 PIN，对方手机里的钥匙立即失效，且无法恢复 —— 只能重新签发、重新交付。")
        }
        .onAppear {
            if memberID == nil { memberID = members.first?.id }
        }
    }

    private var confirmRevoke: Binding<Bool> {
        Binding(get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } })
    }

    private var issueCard: some View {
        GlassSurface(radius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("发给谁")
                    .type(T.F.kicker)
                    .foregroundStyle(T.C.ink3)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(members) { member in
                            Button { memberID = member.id } label: {
                                Text(member.name)
                                    .type(T.F.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(memberID == member.id ? .white : T.C.ink)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(memberID == member.id ? T.C.brass : T.C.glass, in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(memberID == member.id ? .clear : T.C.glassEdge, lineWidth: 0.5)
                                    }
                            }
                            .buttonStyle(PressStyle())
                        }
                        if members.isEmpty {
                            Text("先在「通行 → 成员」里建一位成员。")
                                .type(T.F.caption)
                                .foregroundStyle(T.C.ink3)
                        }
                    }
                }

                Text("有效多久")
                    .type(T.F.kicker)
                    .foregroundStyle(T.C.ink3)
                HStack(spacing: 8) {
                    ForEach([1, 7, 30], id: \.self) { d in
                        Button { days = d; forever = false } label: {
                            Text("\(d) 天")
                                .type(T.F.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(!forever && days == d ? .white : T.C.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(!forever && days == d ? T.C.brass : T.C.glass, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(!forever && days == d ? .clear : T.C.glassEdge, lineWidth: 0.5)
                                }
                        }
                        .buttonStyle(PressStyle())
                    }
                    Button { forever = true } label: {
                        Text("永久")
                            .type(T.F.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(forever ? .white : T.C.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(forever ? T.C.brass : T.C.glass, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(forever ? .clear : T.C.glassEdge, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(PressStyle())
                }

                PrimaryButton(title: "签发", busy: busy) {
                    Task { await issue() }
                }
                .disabled(memberID == nil)
            }
        }
    }

    private func keyRow(_ key: MobileKey) -> some View {
        HStack(spacing: 14) {
            GlyphTile(symbol: "iphone", kind: .brass, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.memberName.isEmpty ? "手机钥匙" : key.memberName)
                    .type(T.F.body)
                    .fontWeight(.medium)
                    .foregroundStyle(T.C.ink)
                Text(key.forever ? "永久有效" : validUntilText(key))
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button {
                    copy(key)
                } label: {
                    Text("复制")
                        .type(T.F.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(T.C.brass)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(T.C.brassWash, in: Capsule())
                }
                .buttonStyle(PressStyle())

                Button {
                    revokeTarget = key
                } label: {
                    Text("吊销")
                        .type(T.F.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(T.C.danger)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(T.C.dangerWash, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.vertical, 12)
    }

    /// 交付入口。签发只落本机记录 —— 没有这一步，页面上写着"发到手机里"，
    /// 却没有任何把 ekey 交给对方的途径（唯一的二维码是「交给安卓」的配对凭证，不是这把钥匙）。
    private func copy(_ key: MobileKey) {
        guard !key.ekey.isEmpty else {
            errorLine = "这把钥匙没有存下 ekey（可能是旧备份恢复的）。先吊销，再重新签发。"
            flash = nil
            return
        }
        errorLine = nil
        Clip.set(key.ekey)
        flash = "ekey 已复制 · 90 秒后自动清除"
    }

    /// 到期读法。引擎存的是 `yyyy-MM-dd HH:mm:ss` 的机器串 ——
    /// 直接印出来是「到 2026-11-13 12:00:00 失效」，像日志而不是给人看的话。
    private func validUntilText(_ key: MobileKey) -> String {
        guard let ms = AppModel.millis(key.validTo), ms < When.permanentCutoff else { return "永久有效" }
        if ms <= Int64(Date().timeIntervalSince1970 * 1000) { return "已过期" }
        let date = DF.cached("M 月 d 日 HH:mm").string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
        return "\(date) 失效"
    }

    private func issue() async {
        guard let memberID, let member = DB.member(memberID) else {
            errorLine = "先选一位成员。"
            return
        }
        busy = true
        defer { busy = false }
        errorLine = nil
        flash = nil
        let now = Date()
        let to = now.addingTimeInterval(Double(days) * 86400)
        let result = await app.issueMobileKey(member: member, forever: forever,
                                              from: AppModel.stampSeconds(now),
                                              to: AppModel.stampSeconds(to))
        if case .failure(let error) = result {
            errorLine = error.localizedDescription
        } else {
            flash = "已签发。点行尾「复制」，把 ekey 单独发给对方。"
        }
    }

    private func revoke(_ key: MobileKey) async {
        errorLine = nil
        flash = nil
        let result = await app.revokeMobileKey(key)
        if case .failure(let error) = result {
            errorLine = error.localizedDescription
        } else {
            flash = "已吊销，锁端的那枚 PIN 也删掉了。"
        }
    }
}

// MARK: - 二维码交付

@MainActor
struct HandoffSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    private var payload: String? {
        // 空壳模式绝不给 ekey。
        //
        // `DB.keychainForUnlock(_:)` 是**不过滤**的读法（兄弟方法 `DB.keychain(_:)` 才过滤），
        // 而 `AndroidPair.payload` 装的是这把锁的**配对开锁凭证** ——
        // 在胁迫者面前扫一下这张码就能开门，那就不是伪装，是交出去了。
        guard !DB.isDecoy else { return nil }
        guard let kc = DB.keychainForUnlock(app.currentMac) else { return nil }
        return AndroidPair.payload(kc)
    }

    // 原先这里有个 `blockedReason`，空壳时返回「空壳模式不提供交付码 —— 先退出空壳再来」。
    // 胁迫者正盯着这一屏：这句话等于当场告诉他这是假界面。已删除，失败原因只在下方
    // EmptyNote 里给一条中性说法。

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(T.C.ink4.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            DisplayLine(text: "扫一下，\n就能进门。", size: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)

            Text("这张码只包含这一把锁的 ekey，不包含母钥。对方用安卓 App 扫一次即可。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Text("注意：它不是上面那把手机钥匙，而是本机钥匙串里的配对凭证 —— 扫完能开这把锁，但有效期与本机这把相同。")
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            if let payload, let image = Self.qr(payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 230, height: 230)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.top, 22)
                Text(payload)
                    .type(T.F.mono)
                    .foregroundStyle(T.C.ink3)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            } else {
                // 不解释「为什么」——原因可能是空壳，也可能是钥匙串不完整；
                // 前者一旦说破，胁迫者就知道这是假界面。只给中性说法。
                EmptyNote(line: "暂时生成不了。",
                          detail: "先确认这把锁已经配对，并且钥匙串完整。")
            }

            Spacer()
            GhostButton(title: "关闭", symbol: nil) { dismiss() }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .background(T.C.canvas)
        .presentationDetents([.large])
    }

    static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 9, y: 9))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
