// 手机钥匙（数字钥匙）页 —— 原版 APK 的 page-addblekey / page-delblekey 在 iOS 侧的对应实现。
//
// 一个页面两件事：给成员发一把手机钥匙 + 列出已发的并撤销。
// 原版是两个页面（addblekey / delblekey）且靠服务端成员表判断 pin 占用；
// 本机离线，只能看到「本机发过的」，这一点在页面上如实写出来，不用文案糊过去。
import SwiftUI

struct MobileKeyView: View {
    @EnvironmentObject var app: AppState

    @State private var keys: [MobileKey] = []
    @State private var members: [Member] = []
    @State private var memberID: String = ""
    @State private var forever = true
    @State private var validTo = Date().addingTimeInterval(8 * 3600)  // APK 默认 now+8h
    @State private var busy = false

    private var kc: Keychain? { app.current }

    var body: some View { vkBody.destined(.mobileKey) }
    var vkBody: some View {
        Form {
            if let kc {
                introSection(kc)
                if members.isEmpty {
                    Section {
                        Text("还没有成员。先去「家人与访客」建一个成员，再回来发钥匙。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                    } header: {
                        Text("先建成员")
                    }
                } else {
                    issueSection(kc)
                }
                issuedSection(kc)
            } else {
                Section {
                    Text("未选择门锁").vkFont(.footnote).foregroundStyle(DS.Palette.textSub)
                }
            }
        }
        .navigationTitle("手机钥匙")
        .variantList()
        .dsScreenBackground()
        .onAppear(perform: reload)
    }

    // MARK: - 说明

    private func introSection(_ kc: Keychain) -> some View {
        Section {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "iphone.gen3.badge.key").font(.system(size: DS.Icon.sm))
                    .foregroundStyle(DS.Palette.accentText).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("PIN 池 \(kc.pins.count) 个 · 本机已发 \(keys.count) 把")
                        .vkFont(.subheadline, weight: .medium)
                    if let hint = MobileKeyService.foreignKeyHint(app, kc: kc) {
                        Text(hint).vkFont(.caption).foregroundStyle(DS.Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: DS.Hit.min)
        } header: {
            Text("手机钥匙")
        } footer: {
            Text("手机钥匙 = 用锁 PIN 池里的一个 pin 签出的 ekey，发给成员的手机用。"
                 + "与「蓝牙钥匙串」不同：钥匙串是随身硬件（走 41/43/44），手机钥匙是成员手机里的凭证。"
                 + "本机离线，只能看到自己发过的钥匙 —— 别人发的不会出现在下面。")
                .vkFont(.caption)
        }
    }

    // MARK: - 发放

    private func issueSection(_ kc: Keychain) -> some View {
        Section {
            Picker("归属成员", selection: $memberID) {
                Text("请选择").tag("")
                ForEach(members) { m in Text(m.name).tag(m.id) }
            }
            VariantToggle("永久有效", isOn: $forever)
            if !forever {
                DatePicker("到期时间", selection: $validTo, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
            }
            BusyButton(title: "发一把手机钥匙", systemImage: "key.horizontal", isBusy: busy) {
                Task { await issue(kc) }
            }
            .disabled(memberID.isEmpty || busy)
            if memberID.isEmpty {
                Text("请先选择归属成员。").vkFont(.caption).foregroundStyle(DS.Palette.textSub)
            }
        } header: {
            Text("发新钥匙")
        } footer: {
            Text(forever
                 ? "永久档的有效期到 2118-01-01（与锁端「永久」同口径）。"
                 : "自定义档到期后这把钥匙自动失效，无需手动撤销。")
                .vkFont(.caption)
        }
    }

    // MARK: - 已发

    private func issuedSection(_ kc: Keychain) -> some View {
        Section {
            if keys.isEmpty {
                Text("还没有发过手机钥匙。").vkFont(.footnote).foregroundStyle(DS.Palette.textSub)
            } else {
                ForEach(keys) { k in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: k.forever ? "infinity" : "clock")
                                .font(.system(size: DS.Icon.xs))
                                .foregroundStyle(k.forever ? DS.Palette.ok : DS.Palette.textSub)
                                .accessibilityHidden(true)
                            Text(k.memberName).vkFont(.subheadline, weight: .medium)
                            Spacer(minLength: 0)
                            Text("pin \(k.pin)").vkFont(.caption).monospacedDigit()
                                .foregroundStyle(DS.Palette.textSub)
                        }
                        Text(MobileKeyService.validityLabel(k))
                            .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                        Text("发放于 \(dateText(k.at))")
                            .vkFont(.caption2).foregroundStyle(DS.Palette.textSub)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            confirmRevoke(kc, k)
                        } label: { Label("撤销", systemImage: "trash") }
                    }
                }
            }
        } header: {
            Text("已发的钥匙（\(keys.count)）")
        } footer: {
            Text("撤销会同时把这个 pin 从锁里删掉（cmd08 delPins）—— 只删本地记录的话，"
                 + "旧 pin 签出的 ekey 仍然能开门。")
                .vkFont(.caption)
        }
    }

    // MARK: - 动作

    private func reload() {
        guard let kc else { return }
        keys = MobileKeyService.list(kc.mac)
        members = DB.members().filter { $0.id != MemberHub.visitorId }
        if memberID.isEmpty, let f = members.first { memberID = f.id }
    }

    private func issue(_ kc: Keychain) async {
        guard !busy, let m = members.first(where: { $0.id == memberID }) else { return }
        busy = true
        defer { busy = false }
        let fmt = DateFormatter()
        // 这个串会**落盘**（kf_mkey_ 的 validFrom/validTo），必须钉公元历：
        // 非公历系统历法下 "yyyy" 会给出异 era 年份，与 MobileKeyService 里的
        // "2118-01-01 00:00:00" 永久判据对不上。
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        do {
            _ = try await MobileKeyService.issue(app,
                                                 kc: kc,
                                                 member: m,
                                                 forever: forever,
                                                 validFrom: fmt.string(from: Date()),
                                                 validTo: fmt.string(from: validTo))
            app.showToast("已给「\(m.name)」发一把手机钥匙")
            reload()
        } catch {
            app.showToast("发放失败: \(error.localizedDescription)")
        }
    }

    private func confirmRevoke(_ kc: Keychain, _ k: MobileKey) {
        confirmDestructive("撤销手机钥匙",
                          "「\(k.memberName)」的这把钥匙将立即失效，同时把 pin \(k.pin) 从锁里删除。"
                          + "如果该成员还有别的凭证（密码/指纹），那些不受影响。",
                          confirmTitle: "撤销") {
            Task { await revoke(kc, k) }
        }
    }

    private func revoke(_ kc: Keychain, _ k: MobileKey) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await MobileKeyService.revoke(app, kc: kc, key: k)
            app.showToast("已撤销")
            reload()
        } catch {
            app.showToast("撤销失败: \(error.localizedDescription)")
        }
    }

    private func dateText(_ ms: Double) -> String {
        // 必须钉公元历：非公历系统历法（佛历/回历）下 "MM-dd" 会算出异 era 的年份。
        // 仓里同类写法统一用 en_US_POSIX（见 swiftlint 的「日期格式没钉历法」那条）。
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}
