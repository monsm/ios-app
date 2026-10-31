// MemberCreateScreen.swift —— 建档向导（四步真序列：01 称呼 → 02 角色 → 03 档案 → 04 初始凭证）。
//
// 这屏干什么：把一个新成员从"没有"走到"能在锁里开门"。四步是真序列，编号 01/02/03/04 是流程本身的刻度。
// 数据从哪来：Engine 的 DB.addMember 落 kf_members；档案扩展走 MemberHub.saveExt（kf_member_ext）；
//   第四步的临时码写本机凭证台账（锁端下发链路见 TODO(engine)）。
// 主动作：下一步 / 完成建档（同屏只有一个 signal 填充）。
import SwiftUI
import UIKit

struct MemberCreateScreen: View {
    // @State 一律 internal：向导四步视图住在 MemberCreateParts.swift 的 extension 里，
    // 跨文件要能读写。private 在另一文件不可见，编译器报 inaccessible ——
    // 这类错只在那个分支被实例化时才暴露，很容易漏到 CI 才红。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    @State var step: Int = 0
    @State var name = ""
    @State var emoji = ""
    @State var role: MemberCard.Role = .member
    @State var remark = ""
    @State var relation = ""
    @State var groupTag = ""
    @State var emergency = ""
    @State var makeCode = false
    @State var code = ""
    @State var newID: String?
    @State var errorLine: String?

    private var roster: HouseholdRoster { HouseholdRoster.shared }

    static let steps: [(no: String, title: String, hint: String)] = [
        ("01", "称呼与代号", "名字会出现在每一条台账上，所以先定称呼。"),
        ("02", "角色与备注", "角色决定这台手机上 TA 能做什么；备注只影响记录怎么显示。"),
        ("03", "档案", "关系、分组、紧急联系 —— 这一档纯本机，不上锁。"),
        ("04", "初始凭证", "顺路建一张 10 分钟临时码，或稍后到「钥匙」页再配。"),
    ]

    internal var current: (no: String, title: String, hint: String) { Self.steps[step] }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var nameOK: Bool {
        let n = trimmedName
        guard !n.isEmpty, n.count <= 20 else { return false }
        return n.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private var nameTaken: Bool {
        app.members.contains { $0.name == trimmedName && $0.id != newID }
    }

    internal var codeOK: Bool {
        code.count >= 6 && code.count <= 8 && code.allSatisfy { $0.isNumber }
    }

    private var atLimit: Bool { app.members.count >= HHStats.memberLimit }

    private var canAdvance: Bool {
        switch step {
        case 0: return nameOK && !nameTaken && !atLimit
        case 3: return !makeCode || codeOK
        default: return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: T.S.l) {
                header
                stepScale
                stepPanel
                if let errorLine {
                    errorBlock(errorLine)
                }
                if step == 3 { codePanel }
                actionPanel
                cancelNote
            }
            .padding(.vertical, T.S.l)
        }
        .background(CanvasBackground())
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("新建成员")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { cancel() }
                    .accessibilityLabel("取消建档")
            }
        }
        .animation(reduceMotion ? nil : T.M.move, value: step)
    }

    // MARK: 页头（大标题 + 一行状态）
    private var header: some View {
        HHPageHeader(
            title: "新建成员",
            overline: "建档向导 · 四步",
            tone: atLimit ? .attention : .ok,
            status: atLimit
                ? "已到本机成员上限 15 位 —— 先归档一位再建新人"
                : "当前步骤：" + current.title
        )
    }

    // MARK: 刻度
    private var stepScale: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                HHCreationStepScale(steps: Self.steps.map { $0.no }, current: step)
                Text(current.hint)
                    .font(T.F.caption)
                    .foregroundStyle(Ink.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    // MARK: 当前步的输入
    private var stepPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: T.S.m) {
                SectionLabel(text: current.no + " · " + current.title, trailing: step == 3 ? "可选" : "必填")
                stepBody
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    @ViewBuilder
    private var stepBody: some View {
        if step == 0 {
            HHTextField(label: "称呼", text: $name, placeholder: "汉字 / 英文 / 数字，上限 20 字")
            if !name.isEmpty && !nameOK {
                HHFieldNote(text: "称呼只接受汉字、英文、数字，且不超过 20 字。")
            } else if nameTaken {
                HHFieldNote(text: "已经有同名成员了 —— 换个称呼，或到那位成员的 360 里用「合并」把两个名字并成一个。")
            }
            HHEmojiPicker(emoji: $emoji)
        } else if step == 1 {
            VStack(spacing: 0) {
                ForEach(MemberCard.Role.allCases.indices, id: \.self) { index in
                    if index > 0 { HHRule() }
                    HHRoleOptionRow(
                        role: MemberCard.Role.allCases[index],
                        selected: role == MemberCard.Role.allCases[index]
                    ) {
                        role = MemberCard.Role.allCases[index]
                    }
                }
            }
            HHTextField(label: "备注名", text: $remark, placeholder: "记录条目显示「称呼（备注）」")
        } else if step == 2 {
            HHTextField(label: "与你的关系", text: $relation, placeholder: "母亲 / 妹妹 / 钟点工")
            HHTextField(label: "分组标签", text: $groupTag, placeholder: "家人 / 访客 / 服务人员")
            HHTextField(label: "紧急联系", text: $emergency, placeholder: "姓名 + 电话")
        } else {
            HHToggleRow(
                title: "顺路建 10 分钟临时码",
                detail: "下发到当前门锁，归属自动记为 TA。不建也行。",
                isOn: makeCode
            ) {
                makeCode.toggle()
            }
        }
    }

    // MARK: 第四步：临时码
    private var codePanel: some View {
        HHCodePanel(makeCode: $makeCode, code: $code, codeOK: codeOK, expiryText: expiryText)
    }

    internal var expiryText: String {
        let at = Int64(Date().timeIntervalSince1970 * 1000) + 600_000
        return TimeFormat.clock(at)
    }

    // MARK: 步进（同屏唯一 signal 填充）
    private var actionPanel: some View {
        VStack(spacing: T.S.s) {
            if step < 3 {
                PrimaryAction(title: "下一步", systemImage: "arrow.right", busy: false) { advance() }
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.5)
            } else {
                PrimaryAction(title: "完成建档", systemImage: "checkmark.seal", busy: false) { finish() }
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.5)
            }
            if step > 0 {
                SecondaryAction(title: "上一步", systemImage: "arrow.left") { step -= 1 }
            }
        }
        .padding(.horizontal, T.S.gutter)
    }

    private var cancelNote: some View {
        Text("第一步按「下一步」时才会真正建号；中途取消不会留下半个人（已建的号会在取消时一并撤回）。")
            .font(T.F.unit)
            .foregroundStyle(Ink.inkFaint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, T.S.l)
    }

    private func errorBlock(_ text: String) -> some View {
        HStack(spacing: T.S.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)   // 装饰性图标：语义由相邻文字承载
                .font(T.F.icon(T.Icon.s))
                .foregroundStyle(State.critical)
            Text(text)
                .font(T.F.caption)
                .foregroundStyle(State.critical)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, T.S.gutter)
        .accessibilityElement(children: .combine)
    }

    // MARK: 真动作
    private func advance() {
        guard canAdvance else { return }
        if step == 0 {
            guard create() else { return }
        }
        if step == 1 { writeProfile() }
        if step == 2 { writeProfile() }
        errorLine = nil
        step += 1
    }

    private func create() -> Bool {
        // 已经建过号（用户退回过第 1 步）就不再建第二个 —— 否则同一个人会在名册里出现两次。
        if newID != nil { return true }
        guard !atLimit else {
            errorLine = "已到本机成员上限 15 位。先归档一位，再回来建新人。"
            return false
        }
        guard nameOK else {
            errorLine = "称呼只接受汉字、英文、数字，且不超过 20 字。"
            return false
        }
        guard !nameTaken else {
            errorLine = "已经有同名成员了 —— 换个称呼，或到那位成员的 360 里合并。"
            return false
        }
        // 真建档走 Engine：DB.addMember 落 kf_members 并分配成员色；重名由它自己拒。
        guard let created = DB.addMember(trimmedName) else {
            errorLine = "已经有同名成员了 —— 换个称呼，或到那位成员的 360 里合并。"
            return false
        }
        app.members.append(MemberCard(id: created.id, name: created.name, role: role, keyCount: 0,
                                      lastActiveAt: nil, archived: false))
        newID = created.id
        roster.focusMember = created.id
        roster.update(created.id) { $0.emoji = emoji }
        roster.mirrorRole(created.id, role)
        return true
    }

    /// 第二 / 三步的选择当场写进档案 —— 不在末步一次性补写（旧实现那里丢过用户选的档位）。
    private func writeProfile() {
        guard let id = newID, let i = app.members.firstIndex(where: { $0.id == id }) else { return }
        app.members[i] = app.members[i].hh(role: role)
        roster.update(id) { e in
            e.emoji = emoji
            e.remark = remark.trimmingCharacters(in: .whitespaces)
            e.relation = relation.trimmingCharacters(in: .whitespaces)
            e.groupTag = groupTag.trimmingCharacters(in: .whitespaces)
            e.emergency = emergency.trimmingCharacters(in: .whitespaces)
        }
    }

    private func finish() {
        guard canAdvance, let id = newID else { return }
        writeProfile()
        let memberName = trimmedName
        // 建码要先有锁：没有门锁时如实说明「已建档、码未建」，不假装成功。
        let hasLock = app.lock != nil
        if makeCode && codeOK && hasLock {
            let expires = Int64(Date().timeIntervalSince1970 * 1000) + 600_000
            app.keys.append(KeyItem(id: "k-" + String(expires), kind: .temp, name: "向导临时码 · " + memberName,
                                    owner: memberName, code: code, expiresAt: expires, disabled: false))
            if let i = app.members.firstIndex(where: { $0.id == id }) {
                let m = app.members[i]
                app.members[i] = MemberCard(id: m.id, name: m.name, role: m.role, keyCount: m.keyCount + 1,
                                            lastActiveAt: m.lastActiveAt, archived: m.archived)
            }
        } else if makeCode && codeOK && !hasLock {
            // 已建档但没锁可下发：如实说明，不假装建了码。
            errorLine = "已建档，但临时码没建：本机还没有添加门锁。先到「门」页添加门锁，再回来补一枚。"
            return
        }
        roster.focusMember = id
        router.request(.dest(.memberDetail))
    }

    private func cancel() {
        if let id = newID {
            app.members.removeAll { $0.id == id }
            DB.removeMember(id)
            roster.forget(id)
            if roster.dutyID() == id { roster.setDuty(nil) }
            roster.focusMember = nil
        }
        router.request(.tab(.household))
    }
}
