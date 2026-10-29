// 成员详情 / 建档向导 / 合并 / 归档 / 分组
// 2026-10-29 从 MemberCenterView.swift（1169 行）拆出 —— 都是顶层 struct，非 private。
import SwiftUI


// ================= 成员 360 详情 (459 上档案 / 下凭证+摘录 ⚠约 · 473 来源 · 476 图谱 · 464/465 · 470 矩阵 · 469) =================
struct MemberDetail360View: View {
    let memberID: String
    var onChanged: () -> Void = {}
    @EnvironmentObject var app: AppState
    @State private var tick = 0
    @State private var showMerge = false

    private var member: Member? { DB.member(memberID) }

    var body: some View { vkBody.destined(.memberDetail360) }
    /// ⚠ `@ViewBuilder` 这一句不能省：顶层是 `if let / else` 两个**不同类型**的分支
    /// （`List{…}` vs `EmptyState`）。它原先是 `body`，隐式带着协议给的 @ViewBuilder；
    /// 改名成 `vkBody` 之后那份隐式就没了 —— CI run 115 报的 "branches have mismatching types"
    /// 说的就是这件事。（其余 76 处 `vkBody` 是单表达式或两支同为 `AnyView` 的 if-表达式，不加也能编。）
    @ViewBuilder var vkBody: some View {
        if let m = member {
            List {
                if let line = MemberHub.weekSentence(m.id) {
                    Section { Label(line, systemImage: "calendar.badge.clock")
                        .vkFont(.footnote).foregroundStyle(DS.Palette.text)
                        .fixedSize(horizontal: false, vertical: true) }
                }
                // 467「待确认移交」区已撤 (2026-10-09 拍板): 移交实际由凭证页 `CredentialOrg.batchTransfer`
                // 直接改本机台账, 队列没有发起方 → 这个区永远只显示"暂无"。留着就是假开关那一族。
                credsSection(m)
                permSection(m)
                excerptSection(m)
            }
            .navigationTitle(MemberHub.display(m))
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("补全档案 (关系/电话/生日/代号/分组/便签)") { editProfile(m); onChanged() }
                    Button("重复合并") { showMerge = true }   // 462 重复合并
                    Button(role: .destructive) { confirmDelete(m) } label: {
                        Label("删除并级联提示", systemImage: "trash")   // 263 删除并级联提示
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("成员操作菜单")
                }
            } }
            .sheet(isPresented: $showMerge) { MergeMembersView(primary: m) { tick += 1; onChanged() } }
            .id(tick)
        } else {
            EmptyState(systemImage: "person.slash",
                       title: "成员不存在",
                       message: "档案可能已被删除或合并。")
                .frame(maxWidth: .infinity)
        }
    }


    // 2026-10-29 补（**后台有实现、前台零调用**）：`MemberHub.recentExcerpts` 一直在 ——
    // 成员 360 页看不到「这个人最近开过哪把锁」。补一个板块，只读本机缓存的开锁类日志。
    @ViewBuilder
    private func excerptSection(_ m: Member) -> some View {
        let items = MemberHub.recentExcerpts(m.id, 8)
        Section {
            if items.isEmpty {
                Text("还没有这位成员的开锁记录（或记录页还没拉取过日志）。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.time)
                            .vkFont(.caption.monospacedDigit())
                            .foregroundStyle(DS.Palette.textSub)
                        Text(e.text)
                            .vkFont(.footnote)
                            .foregroundStyle(DS.Palette.text)
                    }
                }
            }
        } header: {
            Text("最近开锁（\(items.count) 条）")
        } footer: {
            Text("只取本机缓存的开锁类日志，按时间倒序。要看全部请到记录页按 TA 筛选。")
        }
    }

    // ---------- 261/472 名下凭证 (含借用横条) ----------
    private func credsSection(_ m: Member) -> some View {
        var pwdCount = 0, fpCount = 0
        var borrowLines: [String] = []
        var credLines: [String] = []   // 261 清单: 借用中的走 borrowLines, 同一凭证不在本段出现两次
        for kc in DB.keychains() where !kc.mac.isEmpty {
            for p in DB.listPwds(kc.mac) where p.owner == m.id {
                pwdCount += 1
                if let b = MemberHub.borrows(kc.mac)["p" + String(p.alias)] {
                    borrowLines.append(CredentialOrg.displayPwd(p) + " · 借给 " + b.by + " (还 " + b.due + ")")
                } else {
                    credLines.append(CredentialOrg.displayPwd(p))
                }
            }
            for f in DB.listFps(kc.mac) where f.owner == m.id {
                fpCount += 1
                if let b = MemberHub.borrows(kc.mac)["f" + String(f.batch)] {
                    borrowLines.append("「" + f.name + "」 · 借给 " + b.by + " (还 " + b.due + ")")
                } else {
                    credLines.append("「" + f.name + "」")
                }
            }
        }
        return Section {
            Text("密码 \(pwdCount) 条 · 指纹 \(fpCount) 条 · 未归属转未分配不在此列")   // 261 密码
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.text)
            // 261 清单本体: 只有计数没有名目时, 用户没法核对"名下到底有哪几把"
            ForEach(Array(credLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            ForEach(borrowLines, id: \.self) { line in
                HStack(spacing: DS.Space.s) {
                    StatusPill(text: "借用中", systemImage: "person.2.badge.gearshape", tone: .warn)   // 472 借用中
                    Text(line)
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.textSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
                    // 2026-10-26 精简：借用登记入口已删。
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(DS.Palette.accentText)
        } header: {
            Text("名下凭证")   // 261 名下凭证
        }
    }






    // ---------- 470 权限矩阵 + 469 紧急管理员 + 843 角色与示例内嵌 ----------
    private func permSection(_ m: Member) -> some View {
        let role = MemberHub.ext(m.id).role
        let matrix = MemberHub.permRows(role)          // 470 的表定义在 MemberHub (全仓唯一一份)
        let admins = MemberHub.emergencyAdmins()       // 469 读点: 一次解表, 下面那行点名与会议摘要共用
        return Section {
            // 843 (家庭共享设置那一形态): 角色选择器就放在它驱动的那台矩阵**正上方** ——
            // 选一下当场看得见哪几行亮/灭，不用翻去另一页对照一份会漂移的说明表。
            // 创意原句写的是"查看者/管理员"，本仓那三档是 458 的主理人/成员/访客，
            // 示例文字与矩阵行都由 MemberHub.permRows(role) 现算，不另写一份权限说明 (两处各写一遍迟早互相打脸)。
            Picker("角色", selection: Binding(   // 458/843 角色
                get: { role },
                set: { v in
                    var e = MemberHub.ext(m.id)
                    e.role = v
                    MemberHub.saveExt(m.id, e)
                    onChanged()
                })) {
                Text("主理人").tag("main")
                Text("成员").tag("member")
                Text("访客").tag("guest")
            }
            ForEach(["main", "member", "guest"], id: \.self) { r in
                roleExample(r, current: role)
            }
            ForEach(matrix, id: \.name) { row in
                LabeledContent(row.name) {
                    StatusPill(text: row.allowed ? "允许" : "禁用",
                               systemImage: row.allowed ? "checkmark.circle" : "xmark.circle",
                               tone: row.allowed ? .ok : .neutral)
                }
            }
            Text("矩阵管的是本机 UI: 「管凭证」这一行决定这一档给不给代管开关 (上方「家庭场景」那一节), "   // 470 矩阵管的是本机
                 + "「成员管理」这一行决定能不能被指成紧急管理员 (就在下面)。不给的那一枚会就地写明为什么少。"
                 + "边界: 锁端没有角色字段, 备份包也不带角色 —— 这三档不改任何发往门锁的字节; "
                 + "角色与代管会被写进成员名册那张 vcf 的备注行。")   // 415 角色与代管会被写进成
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            // 469 的真读点之一: 这一页把"谁被指成了紧急管理员"写在明面上。
            // 原先这个位只有 Toggle 的 set、全仓零读取方, 界面却承诺"救援码说明与其绑定" —— 那句已按实情收窄。
            LabeledContent("紧急管理员") {   // 469 紧急管理员
                Text(admins.isEmpty ? "未指定" : admins.map { MemberHub.display($0) }.joined(separator: "、"))
                    .vkFont(.subheadline)
                    .foregroundStyle(admins.isEmpty ? DS.Palette.textSub : DS.Palette.accentText)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if MemberHub.permAllows(role, "成员管理") {
                VariantToggle("把 Ta 设为紧急管理员 (本机点名档)", isOn: Binding(
                    get: { MemberHub.ext(m.id).emergencyAdmin },
                    set: { v in
                        var ext = MemberHub.ext(m.id); ext.emergencyAdmin = v
                        MemberHub.saveExt(m.id, ext)
                        onChanged()
                    }))
                .fixedSize(horizontal: false, vertical: true)
                Text("这一档的作用是把人点出来: 上面那一行会写上 Ta 的名字, 免得只剩一个人管钥匙。"
                     + "救援码本身仍在 设置-安全 里生成, 那段说明目前不读这份名单 —— 两者今天没有绑定关系。")
                    .vkFont(.caption2)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("角色是「" + MemberHub.roleLabel(role) + "」: 矩阵里「成员管理」这一行是禁用, 所以这一档不给指成紧急管理员 (收的就是本机 UI)。要给它, 先把角色改成主理人。")
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("权限与应急")   // 470/469 权限与应急
        }
    }
    /// 843 角色示例行：能/不能两串**由 MemberHub.permRows 现算**，只有场景句是写死的文案
    /// (场景讲的是"这种人通常是谁"，不是权限位 —— 权限位改了这里会跟着变，不会两边各说一套)。
    /// "访客名下仍可以有临时码"这句刻意保留：那是**锁端**的事，470 只管本机 UI，两者最容易被读混。
    private func roleExample(_ r: String, current: String) -> some View {
        let can = MemberHub.permCan(r)
        let cant = MemberHub.permCannot(r)
        let scene: String
        switch r {
        case "main": scene = "通常是房子主人：这台机器上的所有事都归 Ta"
        case "guest": scene = "通常是访客/钟点工：名下仍可以有临时码 (那是锁端的事)，本机这边不给代管、也不给指成紧急管理员"   // 470 通常是访客
        default: scene = "通常是家人：日常开门与补凭证够用，导出与备份不给"
        }
        // 2026-10-13 run 60: 原来把两个 `isEmpty ? … : joined(…)` 三元直接拼进 Text 的字符串里,
        // 整个 roleExample 体报 "unable to type-check this expression in reasonable time"。
        // 先把两串各自算好 (显式 String), 再拼 —— 编译器不再面对一个巨表达式。
        let canText: String = can.isEmpty ? "没有" : can.joined(separator: "、")
        let cantText: String = cant.isEmpty ? "没有" : cant.joined(separator: "、")
        return VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(MemberHub.roleLabel(r) + (r == current ? " · 当前所选" : ""))
                .vkFont(.caption, weight: .semibold)
                .foregroundStyle(r == current ? DS.Palette.accentText : DS.Palette.text)
            Text("能：" + canText + "　不能：" + cantText)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Text(scene)
                .vkFont(.caption2)
                .foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // ---------- 补全档案 (265/461/458/457-916/464/465/475/480/484/630) ----------
    private func editProfile(_ m: Member) {
        let e = MemberHub.ext(m.id)
        // 843: 角色不再在这里填英文代码 —— 它有了正上方的单选 (主理人/成员/访客)，两处能改一个值就是两个真相源。
        // 旧写法还留着一个真隐患: 手打 "Main"/"管理员" 这类值不报错，只会被 MemberHub.permRows 静默当成"成员"。
        let alert = UIAlertController(title: "补全档案", message: "角色改到下方「权限与应急」里单选，这里不再填英文代码。", preferredStyle: .alert)   // 470/843 角色改到下方
        func field(_ ph: String, _ initial: String, _ kb: UIKeyboardType = .default) -> UITextField {
            // 2026-10-13 run 60: 参数原名 `init` —— 它是 Swift 的关键字 (初始化器), 于是 `$0.text = init`
            // 里的 `init` 被解析成"类型的初始化器"而不是这个参数 ⇒ 报
            //   "'init' is a member of the type; use 'type(of: ...)' to initialize a new object…"
            //   "cannot reference 'mutating' method as function value" 等 4 条。
            // 改名 `initial`; 调用点全是位置传参 (`field("关系", m.relation)`), 不受影响。
            alert.addTextField { $0.placeholder = ph; $0.text = initial; $0.keyboardType = kb; $0.clearButtonMode = .whileEditing }
            return alert.textFields?.last ?? UITextField()
        }
        let fRelation = field("与你的关系", m.relation)
        let fRemark = field("备注名", e.remark)   // 461 备注名
        let fEmoji = field("emoji 代号", e.emoji)   // 916 代号
        let fEmergency = field("紧急联系 姓名+电话", e.emergency)   // 465 紧急联系
        let fCare = field("孩子码关怀文案", e.careText)   // 480 孩子码关怀文案
        let fNote = field("家庭便签 (如 周六换锁芯)", e.note)
        let fWelcome = field("访客欢迎语", e.welcome)   // 484 访客欢迎语
        let fGroup = field("分组标签 家人/访客/服务人员", e.groupTag)   // 630 分组标签
        let fCommon = field("常用锁 (mac 或名称, 逗号分隔; 多锁时排前)",
                            e.commonLocks.joined(separator: ", "))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            var next = e
            // role 不在这里改 (见上) —— 保存时保持 e.role 原值, 只改其余字段
            next.emoji = fEmoji.text ?? ""
            next.remark = fRemark.text ?? ""
            next.emergency = fEmergency.text ?? ""
            next.note = fNote.text ?? ""
            next.careText = fCare.text ?? ""
            next.welcome = fWelcome.text ?? ""
            next.groupTag = fGroup.text ?? ""
            next.commonLocks = (fCommon.text ?? "")
                .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            MemberHub.saveExt(m.id, next)
            DB.setMemberInfo(m.id, ["relation": fRelation.text ?? ""])
            onChanged()
            app.showToast("档案已保存")
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    // ---------- 263 删除级联提示 (走既有 501 回收站机制) ----------
    // D-152a (2026-10-11 拍板 方案③): 弹窗当场选「只移除档案 / 连锁端一起收回」, 默认第一项。
    // 撤权那一支走的还是 629/353 那条现成队列 (CredentialOrg.enqueue del_pwd/del_fp), 没有新数据面;
    // 指纹不可远程补录 (670) 这句话与选项写在同一屏 —— 它是这个选择唯一的真代价。
    private func confirmDelete(_ m: Member) {
        let preview = CredentialOrg.memberCredentialPreview(m.id)
        // 2026-10-28 修复（**安全级假承诺**）：原文案写「转入未分配并入回收站（可整组还原）」
        // 与「这些凭证会排上锁端删除, 到场连接后真正失效」—— 两句都不成立：
        //   · `cascadeBinMember` 只做 `DB.delPwd/delFp`，**没有回收站**、没有「转为未分配」；
        //   · `revokeLocks` 形参被 `_ = revokeLocks` 直接丢弃，**没有任何队列**，锁端永远不动；
        //   · 两个按钮的实际行为因此**完全相同** —— 保留「连锁端一起收回」只会让人以为更彻底。
        // 现在只留一个按钮，并把真实后果说清楚。
        let msg = preview.isEmpty
            ? "确定要删除「" + m.name + "」吗? TA 名下没有台账凭证。本机记录删除后不可恢复。"
            : "删除「" + m.name + "」后, 名下 " + String(preview.count) + " 条凭证将从**本机台账移除**"
              + "（本机没有回收站，删除后不可恢复）:\n"
              + preview.prefix(5).joined(separator: "\n") + (preview.count > 5 ? "\n…" : "")
              + "\n\n⚠ 锁端凭证不受影响 —— 这些密码/指纹在门锁上**仍然有效**，"
              + "必须到门锁键盘上手动删除才会真正失效。指纹一旦在锁端删掉就无法远程补录，只能本人到锁前重录。"
        let alert = UIAlertController(title: "删除成员", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "移除档案（锁端需另删）", style: .destructive) { _ in
            for kc in DB.keychains() { CredentialOrg.cascadeBinMember(kc.mac, m.id) }
            DB.removeMember(m.id)
            onChanged()
            app.showToast("已删除 · ⚠ 锁端凭证仍在，需要时请到门锁上手动删除")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }
}

// ================= 463 建档向导 (称呼 → 角色 → 初始凭证 三小步, 末步顺路建临时码) =================
struct MemberWizardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
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
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
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
    @Environment(\.dismiss) private var dismiss
    let primary: Member
    var onDone: () -> Void = {}
    @State private var secondaryID: String?

    private var secondaryCandidates: [Member] {
        DB.members().filter { $0.id != primary.id && $0.name == primary.name }
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
                            Text(m.name + " · 名下 " + String(MemberHub.activity(m.id).owns) + " 条").tag(m.id as String?)
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
    @Environment(\.dismiss) private var dismiss
    var onRestored: () -> Void = {}
    @State private var tick = 0

    private var archived: [Member] {
        DB.members().filter { MemberHub.ext($0.id).archived }
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
    @Environment(\.dismiss) private var dismiss
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







