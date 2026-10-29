// 成员 · 建档向导 / 合并 / 归档 / 分组
// 2026-10-29 从 MemberDetail.swift（709 行）拆出 —— 都是顶层 struct。
import SwiftUI


// ================= 463 建档向导 (称呼 → 角色 → 初始凭证 三小步, 末步顺路建临时码) =================
struct MemberWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    var onDone: () -> Void = {}
    @State private var step = 0
    @State private var name = ""
    @State private var role = "member"
    @State private var emoji = ""
    @State private var remark = ""
    @State private var pwd = ""
    @State private var makePwd = false
    @State private var busy = false
    @State private var newID: String?

    private var steps: [String] { ["称呼与代号", "角色与备注", "初始凭证"] }
    private var canNext: Bool {
        switch step {
        case 0: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: return true
        default: return !makePwd || pwdOK()
        }
    }
    private func pwdOK() -> Bool { pwd.count >= 6 && pwd.count <= 8 && pwd.allSatisfy { $0.isNumber } }
    /// 458 向导里的角色副标题: 这一档相对"成员"档多/少哪几项, 全部由 MemberHub.permRows 现算
    /// (470 那张表只有一处定义; 原先这里手写三份"备份/成员管理"式说明, 改了表就说明就漂了)。
    /// 只列差集: iPhone 的选择器行里全列五项会被截断, 而差集才是选角色时真正要看的那一句。
    private func rolePickHint(_ r: String) -> String {
        let mine = MemberHub.permRows(r).filter { $0.allowed }.map { $0.name }
        let base = MemberHub.permRows("member").filter { $0.allowed }.map { $0.name }
        if r == "member" { return mine.joined(separator: "/") }
        let mineSet = Set(mine)
        let baseSet = Set(base)
        let more = mine.filter { !baseSet.contains($0) }
        let less = base.filter { !mineSet.contains($0) }
        if !more.isEmpty { return "比成员多 " + more.joined(separator: "/") }
        if !less.isEmpty { return "比成员少 " + less.joined(separator: "/") }
        return "与成员同"
    }

    var body: some View { vkBody.destined(.memberWizard) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("步骤 \(step + 1)/3 · " + steps[step]) {
                    switch step {
                    case 0:
                        TextField("称呼 (汉字/英文/数字, 上限 20)", text: $name)
                            .autocorrectionDisabled()
                        Picker("emoji 代号", selection: $emoji) {   // 916 代号
                            ForEach(["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"], id: \.self) { e in
                                Text(e.isEmpty ? "默认首字" : e).tag(e)
                            }
                        }
                        .pickerStyle(.menu)
                    case 1:
                        Picker("角色", selection: $role) {   // 458/470 角色
                            // 副标题现算, 不手写第二份"这档能干什么" —— 那张表只有 MemberHub.permRows 一处定义
                            ForEach(MemberHub.roles, id: \.self) { r in
                                Text(MemberHub.roleLabel(r) + " (" + rolePickHint(r) + ")").tag(r)
                            }
                        }
                        .pickerStyle(.inline)
                        TextField("备注名 (记录条目显示 称呼（备注）)", text: $remark)
                            .autocorrectionDisabled()
                    default:
                        VariantToggle("顺路建 10 分钟临时码 (末步)", isOn: $makePwd)
                            .fixedSize(horizontal: false, vertical: true)
                        if makePwd {
                            TextField("6~8 位数字 (下发到当前锁)", text: $pwd)
                                .keyboardType(.numberPad)
                            Text("归属自动记为 TA; 不建也行, 稍后在凭证页添加。")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // 463: 建档流程内直达指纹录入 (与临时码同格), 录完回凭证页可指归属
                        NavigationLink("录指纹后到凭证页指归属") { FpStudio(embedded: true) }   // 463 录指纹后到凭证页指归
                            .vkFont(.footnote)
                    }
                }
                if step < 2 {
                    Section {
                        Button {
                            guard canNext else { return }
                            if step == 0, newID == nil {
                                newID = createMember()
                                // 2026-10-14: 建档失败 (重名/空名) 不能推进 —— 否则用户走到末步才被踢出, 输入全废。
                                guard newID != nil else { return }
                            }
                            step += 1
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Text("下一步")
                                .vkFont(.subheadline, weight: .medium)
                                .foregroundStyle(DS.Palette.accentText)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .frame(minHeight: DS.Hit.min)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    Section {
                        BusyButton(title: busy ? "处理中…" : "完成建档",
                                    systemImage: "checkmark.seal", isBusy: busy) {
                            submit()
                        }
                        .disabled(!canNext || busy)
                    }
                }
            }
            .navigationTitle("建档向导")   // 463 建档向导
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
            .axBottomAnchor()   // 870
        }
    }

    private func createMember() -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        // 2026-10-14: 与重命名 (rename) 同口径 —— 否则能建出"之后改不动"的名字 (重命名强制字母数字)。
        guard !n.isEmpty, n.count <= 20, n.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            app.showToast("姓名需为汉字/英文/数字, 上限 20 字")
            return nil
        }
        guard let m = DB.addMember(n) else {
            app.showToast("姓名为空或已存在 (可用合并把两个名字并成一个)")
            return nil
        }
        var e = MemberHub.ext(m.id)
        e.emoji = emoji
        e.role = role
        e.remark = remark
        MemberHub.saveExt(m.id, e)
        if app.pendingFpOwner == "request" { app.pendingFpOwner = m.id }   // 317: 建完交回
        return m.id
    }

    private func submit() {
        // 2026-10-28 补：APK 有成员上限 —— `presentMemberAddPage` 判 `16 != memberList.length`，
        // 超出时明确拒绝：「已添加15个成员，无法再添加」（数组含一个"自己"占位，实际上限 15）。
        // iOS 此前零判据，用户可以一直加下去，而锁端槽位装不下。
        // 已在编辑既有成员（newID != nil）时不拦 —— 那不是新增。
        if newID == nil, DB.members().count >= 15 {
            app.showToast("已添加 15 个成员，无法再添加（锁端槽位上限）")
            dismiss()
            return
        }
        guard let id = newID ?? createMember() else { dismiss(); return }
        guard makePwd, pwdOK() else {
            onDone()
            dismiss()
            // 2026-10-14: 勾了"建临时码"但码非法时, 旧实现只报"已添加", 用户以为码建好了。
            app.showToast(makePwd ? "已添加「\(name)」— 临时码未建 (需 6~8 位纯数字)"
                                  : "已添加「\(name)」")
            return
        }
        busy = true
        Task {
            defer {
                busy = false
                onDone()
                dismiss()
            }
            guard let kc = app.current else {
                app.showToast("已建档; 建码需先选一把锁")
                return
            }
            do {
                try await app.lock.ensureConnected(mac: kc.mac)
                let f = DF.cached("yyyy-MM-dd HH:mm:ss")
                let from = f.string(from: Date())
                let to = f.string(from: Date().addingTimeInterval(600))
                let alias = try await app.lock.pwdAdd(pwd: pwd, validFrom: from, validTo: to)
                let rec = LedgerPwd(alias: alias, from: from, to: to, temp: true,
                                     at: Date().timeIntervalSince1970 * 1000, pwd: pwd, owner: id,
                                     note: "向导建码 · " + name)
                DB.addPwd(kc.mac, rec)
                app.showToast("已建档并给 TA 建了 10 分钟临时码")
            } catch {
                app.showToast("建档成功, 建码失败: " + error.localizedDescription)
            }
        }
    }
}

// ================= 462 重复合并 (同名检测 + 手动迁移凭证归属) =================
struct MergeMembersView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    let primary: Member
    var onDone: () -> Void = {}
    @State private var secondaryID: String?

    private var secondaryCandidates: [Member] {
        DB.members().filter { $0.id != primary.id && $0.name == primary.name }
    }

    /// 2026-10-29 性能：副档选择器每行要显示"名下 N 条"。
    /// 原来每行调一次 `MemberHub.activity(m.id)` —— 那是「遍历全部锁 × 读全部日志 × Attribution 分类」，
    /// 3 个候选就是 3 次全量扫描。现在一次算完（复用 activityBundle，它本来就是为这个场景加的）。
    private var ownsTable: [String: Int] {
        let bundle = MemberHub.activityBundle(secondaryCandidates.map { $0.id })
        return bundle.table.mapValues { $0.owns }
    }

    var body: some View { vkBody.destined(.mergeMembers) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("主档 (保留)") {
                    HStack(spacing: DS.Space.s) {
                        MemberAvatar(member: primary, size: 28)
                        Text(MemberHub.display(primary))
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.text)
                        Spacer(minLength: 0)
                    }
                }
                Section("副档 (凭证将迁移至主档, 档案删除)") {
                    Picker("选择副档", selection: $secondaryID) {
                        Text("请选择").tag(nil as String?)
                        ForEach(secondaryCandidates) { m in
                            // 2026-10-29 性能：原来每个候选都调一次 MemberHub.activity（= 全锁重读日志 + 分类）。
                            // 一次建表，行内只查字典。
                            Text(m.name + " · 名下 " + String(ownsTable[m.id] ?? 0) + " 条").tag(m.id as String?)
                        }
                    }
                    .pickerStyle(.inline)
                    if secondaryID == nil {
                        Text("没有同名成员。若只是称呼重复, 请在成员页重命名其一。")
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    Button { doMerge() } label: {
                        Text("执行合并")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(secondaryID == nil)
                }
            }
            .navigationTitle("重复合并")   // 462 重复合并
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }

    private func doMerge() {
        guard let sid = secondaryID else { return }
        var moved = 0
        for kc in DB.keychains() {
            for p in DB.listPwds(kc.mac) where p.owner == sid {
                DB.setPwdOwner(kc.mac, p.alias, primary.id); moved += 1
            }
            for f in DB.listFps(kc.mac) where f.owner == sid {
                DB.setFpOwner(kc.mac, f.batch, primary.id); moved += 1
            }
        }
        MemberHub.reassignClaims(from: sid, to: primary.id)   // 462
        DB.removeMember(sid)
        onDone()
        app.showToast("已合并, 迁移 \(moved) 条凭证至「" + primary.name + "」")
        dismiss()
    }
}



// ================= 460/795 归档成员列表 (恢复入口) =================
struct MemberArchivedView: View {
    @Environment(\.dismiss) var dismiss
    var onRestored: () -> Void = {}
    @State private var tick = 0

    private var archived: [Member] {
        // 2026-10-29 性能：逐成员 ext() = 逐成员整表解码。
        let extTable = MemberHub.allExt()
        return DB.members().filter { MemberHub.ext($0.id, in: extTable).archived }
    }

    var body: some View { vkBody.destined(.memberArchived) }
    var vkBody: some View {
        NavigationStack {
            List {
                ForEach(archived) { m in
                    LabeledContent {
                        Button("恢复") {
                            var e = MemberHub.ext(m.id)
                            e.archived = false
                            MemberHub.saveExt(m.id, e)
                            tick += 1
                            onRestored()
                        }
                        .buttonStyle(SecondaryActionStyle(fullWidth: false))
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Rectangle())
                    } label: {
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(MemberHub.display(m))
                                .vkFont(.subheadline)
                                .foregroundStyle(DS.Palette.text)
                            Text("归档中 · 只从成员列表与成员统计里收起; 记录页仍能筛到 TA, "
                                 + "凭证页也仍列 TA 名下凭证 —— 归档不许挡撤权入口。")   // 460/795 凭证页也仍列
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if archived.isEmpty {
                    Text("归档列表为空 — 成员归档后历史不蒸发。")   // 795 归档列表为空
                        .vkFont(.footnote)
                        .foregroundStyle(DS.Palette.textSub)
                }
            }
            .navigationTitle("归档成员")   // 460/795 归档成员
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("完成") { dismiss() } } }
            .id(tick)
        }
    }
}

// ================= 630 分组标签编辑 =================
struct MemberGroupSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    var onSaved: () -> Void = {}
    @State private var tags: [String: String] = [:]

    private let options = ["", "家人", "访客", "服务人员"]

    var body: some View {
        NavigationStack {
            Form {
                Section("成员分组标签") {   // 630 成员分组标签
                    ForEach(DB.members(), id: \.id) { m in
                        Picker(MemberHub.display(m), selection: Binding(
                            get: { tags[m.id] ?? MemberHub.ext(m.id).groupTag },
                            set: { tags[m.id] = $0 })
                        ) {
                            ForEach(options, id: \.self) { o in
                                Text(o.isEmpty ? "无分组" : o).tag(o)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section {
                    Button {
                        for (mid, t) in tags {
                            var e = MemberHub.ext(mid)
                            e.groupTag = t
                            MemberHub.saveExt(mid, e)
                        }
                        onSaved()
                        app.showToast("分组已保存")
                        dismiss()
                    } label: {
                        Text("保存分组")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.Hit.min)
                    }
                    .buttonStyle(PrimaryActionStyle())
                }
            }
            .navigationTitle("分组标签")   // 630 分组标签
            .navigationBarTitleDisplayMode(.inline)
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
        }
    }
}
