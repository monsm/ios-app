// 指纹归属选择器 —— 两个录指纹入口 (凭证页的 StartAddFpView / 工坊的 FpStudio 第 0 步) 共用一份。
//
// 2026-10-17 用户口径: 「添加指纹的时候应该先选归属, 无归属可选直接跳到新增归属」。
// 旧实现在"一个成员都没有"时只给一句"请先到成员中心新建成员再返回"并**关掉本页** ——
// 那是一次死路: 用户被踢出去、建完还得自己找回来, 而指纹录入本来就在这一步等着。
// 现在: 空态直接弹"新增归属", 建完即选中, 不离开本页。
import SwiftUI

struct FpOwnerPicker: View {
    /// 归属是**按锁**统计的 (同一成员在两把锁上各有几枚指纹), 所以要把 mac 带进来。
    let mac: String
    @Binding var owner: String?
    @EnvironmentObject var app: AppState
    @State private var adding = false
    @State private var newName = ""

    private var members: [Member] { DB.members() }

    var body: some View {
        VStack(alignment: .leading, spacing: XSpace.xs) {
            Text("先选归属, 再录入")   // 317 先选归属
                .xFont(.footnote, weight: .semibold)
                .foregroundStyle(XPalette.text)
            ForEach(members) { m in
                row(m)
            }
            if members.isEmpty {
                Text("这把锁还没有成员 — 直接建一个, 这枚指纹就记在他名下。")   // 317 还没有成员
                    .xFont(.caption)
                    .foregroundStyle(XPalette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                adding = true
            } label: {
                Label(members.isEmpty ? "新增归属" : "新增一位成员", systemImage: "person.badge.plus")
            }
            .xFont(.caption, weight: .medium)
            .foregroundStyle(XPalette.accentText)
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
        // 空态直接跳"新增归属": 这就是用户要的那一下 —— 没有可选项时不要再让人去别处绕一圈。
        .onAppear {
            if members.isEmpty && owner == nil { adding = true }
        }
        .alert("新增归属", isPresented: $adding) {
            TextField("成员名称", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("创建") { create() }
            Button("取消", role: .cancel) { newName = "" }
        } message: {
            Text("姓名可用汉字 / 英文 / 数字, 上限 20 字。建完会自动选中。")
        }
    }

    @ViewBuilder
    private func row(_ m: Member) -> some View {
        let cnt = CredentialOrg.fpCountByOwner(mac, m.id)
        // 拆成显式局部量: 整条拼接写在 ViewBuilder 里会让编译器 "unable to type-check … in reasonable time"
        let cntTag: String = cnt == 0 ? "无指纹" : "\(cnt) 枚"
        let selTag: String = owner == m.id ? ", 已选" : ""
        Button {
            owner = m.id
            XHaptics.tick.impactOccurred()
        } label: {
            HStack(spacing: XSpace.xs) {
                Circle()
                    .fill(memberColor(m.color))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(m.name)
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.text)
                Spacer(minLength: 0)
                Text(cntTag)
                    .xFont(.caption2)
                    .foregroundStyle(cnt == 0 ? XPalette.warn : XPalette.textSub)
                    .lineLimit(1)
                if owner == m.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: XIcon.sm, weight: .medium))
                        .foregroundStyle(XPalette.accentText)
                }
            }
            .frame(minHeight: XHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("归属 " + m.name + " " + cntTag + selTag)
    }

    /// 成员色是 "#RRGGBB" 字符串 (与成员中心头像同源); 解析失败回落到次级文本色, 不假装有颜色。
    private func memberColor(_ hex: String) -> Color {
        guard hex.hasPrefix("#"), let v = UInt32(hex.dropFirst(), radix: 16) else { return XPalette.textSub }
        return Color(hex: v)
    }

    private func create() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        // 与成员中心 createMember 同一条校验: 否则能建出"之后改不动"的名字 (重命名强制字母数字)
        guard !n.isEmpty, n.count <= 20, n.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            app.showToast("姓名需为汉字/英文/数字, 上限 20 字")
            return
        }
        guard let m = DB.addMember(n) else {
            app.showToast("姓名为空或已存在 (可用合并把两个名字并成一个)")
            return
        }
        owner = m.id
        newName = ""
        XHaptics.tick.impactOccurred()
    }
}
