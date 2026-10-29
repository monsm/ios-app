// 成员管理
// 2026-10-29 从 Sheets.swift 拆出。FieldSpec 是 MembersView 的嵌套类型，随宿主一起走
import SwiftUI

struct MembersView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var newName = ""
    @FocusState private var nameFocused: Bool
    @State private var showCenter = false
    @State private var welcome: Member?   // 995 入伙欢迎卡
    /// 成员列表直接持有, 写库后重查赋值;
    /// 不用 .id(tick) 重建整个 List —— 那会连带丢掉滚动位置、键盘焦点和动画上下文。
    @State private var members: [Member] = []

    var body: some View { vkBody.destined(.members) }
    var vkBody: some View {
        NavigationStack {
            List {
                Section {
                    Text("添加成员后，就可以给成员添加密码，指纹和手机钥匙")
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.m) {
                        TextField("姓名 (仅限汉字, 英文和数字)", text: $newName)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(add)
                        Button("添加", action: add)
                            .buttonStyle(SecondaryActionStyle(fullWidth: false))
                            .disabled(newName.isEmpty)
                    }
                }
                Section("成员 (\(members.count))") {
                    if members.isEmpty {
                        EmptyState(systemImage: "person.2.slash",
                                   title: "还没有成员",
                                   message: "添加后就能把密码和指纹归属到人。",
                                   actionTitle: "添加成员") {
                            nameFocused = true
                        }
                    }
                    ForEach(members) { m in memberRow(m) }
                }
            }
            .navigationTitle("成员管理")
            .variantList()
            .dsScreenBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } }
                // 包13: 成员中心入口 (788 总表 / 360 详情 / 家庭场景 / 聚合视图)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCenter = true
                    } label: {
                        Image(systemName: "person.2.badge.gearshape")
                            .accessibilityLabel("成员中心 (家庭协作)")
                    }
                }
            }
            .sheet(isPresented: $showCenter) {
                MemberCenterView()
            }
        }
    }

    /// 732: 号码只留数字与 +; 清洗后不足 3 位视为无效号码, 不给呼叫入口 (不弹错误页)
    private static func telURL(_ raw: String) -> URL? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel://" + digits)
    }

    private func memberRow(_ m: Member) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
                Text(m.name).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
            }
            if !m.relation.isEmpty || !m.phone.isEmpty {
                Text([m.relation, m.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button(role: .destructive) { confirmRemove(m) } label: { Label("删除", systemImage: "trash") }
        }
        .contextMenu {
            // 732 一键呼叫成员: 号码只保留数字与 + (去空格/括号/连字符), 空号不给入口
            if let tel = Self.telURL(m.phone) {
                Button { UIApplication.shared.open(tel) } label: { Label("呼叫 \(m.name)", systemImage: "phone.fill") }
            }
            Button { rename(m) } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button { info(m) } label: {
                Label("补全信息", systemImage: "person.text.rectangle")
            }
        }
        // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 命中高仅约 14.5pt (< 44)。
        // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
    }


    private func rename(_ m: Member) {
        prompt(title: "重命名", message: nil,
               fields: [FieldSpec(placeholder: "姓名", text: m.name)],
               confirmTitle: "保存") { vals in
            guard let n = vals.first?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return }
            guard n.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                app.showToast("请输入仅含汉字/英文/数字的非空姓名")
                return
            }
            DB.renameMember(m.id, n)
            reload()
        }
    }

    private func info(_ m: Member) {
        prompt(title: "补全信息 (只填空缺)", message: nil,
               fields: [FieldSpec(placeholder: "与你的关系", text: m.relation),
                        FieldSpec(placeholder: "电话 (换机恢复第二匹配键)", text: m.phone, keyboard: .phonePad),
                        FieldSpec(placeholder: "生日 MM-dd (用于提醒)", text: "")],
               confirmTitle: "保存") { vals in
            DB.setMemberInfo(m.id, ["relation": vals.first ?? "", "phone": vals.count > 1 ? vals[1] : ""])
            let bday = vals.count > 2 ? vals[2].trimmingCharacters(in: .whitespaces) : ""
            reload()
        }
    }

    private func reload() { members = DB.members() }

    private func add() {
        if let m = DB.addMember(newName) {
            newName = ""
            nameFocused = false
            reload()
            welcome = m            // 995: 欢迎卡引导首录凭证, 不再只丢一句 toast
        } else {
            app.showToast("姓名为空或已存在")
        }
    }

    // ---- 输入型弹窗: 重命名/补全信息共用一份, 不再各写一个 UIAlertController ----
    struct FieldSpec {
        let placeholder: String
        var text: String = ""
        var keyboard: UIKeyboardType = .default
    }

    private func prompt(title: String,
                        message: String?,
                        fields: [FieldSpec],
                        confirmTitle: String,
                        onConfirm: @escaping ([String]) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for f in fields {
            alert.addTextField { tf in
                tf.placeholder = f.placeholder
                tf.text = f.text
                tf.keyboardType = f.keyboard
                tf.clearButtonMode = .whileEditing
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in
            onConfirm(alert.textFields?.map { $0.text ?? "" } ?? [])
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 501 级联预告: 删除成员前列出名下将一并入回收站的凭证清单 (跨锁合计)
    /// D-152a (2026-10-11 拍板 方案③): 与成员页同一形状 —— 三按钮, 默认「只移除档案」,
    /// 撤权那一支排 629/353 同一条队列; 指纹不可远程补录 (670) 的代价写在正文里。
    private func confirmRemove(_ m: Member) {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        // 2026-10-28 修复（**安全级假承诺**）：与 MemberCenterView.confirmDelete 同一问题 ——
        // 「并入回收站（可整组还原）」与「排上锁端删除」两句都无实现（无回收站、无队列）。
        // 两个按钮行为完全相同，只留一个，并如实说明锁端凭证仍需手动删除。
        let msg = preview.isEmpty
            ? "确定要删除「\(m.name)」吗？TA 名下没有台账凭证。本机记录删除后不可恢复。"
            : "删除「\(m.name)」后, 名下 \(preview.count) 条凭证将从**本机台账移除**"
              + "（本机没有回收站，删除后不可恢复）:\n"
              + preview.prefix(5).joined(separator: "\n")
              + (preview.count > 5 ? "\n…" : "")
              + "\n\n⚠ 锁端凭证不受影响 —— 这些密码/指纹在门锁上**仍然有效**，"
              + "必须到门锁键盘上手动删除才会真正失效。指纹一旦在锁端删掉就无法远程补录，只能本人到锁前重录。"
        let alert = UIAlertController(title: "删除成员", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "移除档案（锁端需另删）", style: .destructive) { _ in
            for kc in DB.keychains() {
                CredentialOrg.cascadeBinMember(kc.mac, m.id)
            }
            DB.removeMember(m.id)
            _ = Milestones.recordOrganize()
            reload()
            app.showToast("已删除 · ⚠ 锁端凭证仍在，需要时请到门锁上手动删除")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
}