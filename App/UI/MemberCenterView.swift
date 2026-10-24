// 包13 成员·家庭协作 — 成员中心 (入口在 设置-成员管理 右上「成员中心」)
// 五块: 档案 (260/457/458/916/265/461/463/266/666) · 关联 (261/459/473/476/791/464/465) ·
//       流转 (467/468/474/472/460-795/462/263/469/470) · 家庭场景 (479-486/475) ·
//       聚合视图 (788/789/793/794/630/264-466/792/798)。
// 纪律: 颜色只走 DS 令牌; 触达 ≥44pt; "访客" 虚拟分组只在本地展示层 (MemberHub.visitorId),
// 绝不写入锁端凭证表; 推断类数据 (活跃度/摘录) 一律带"约"。
import SwiftUI
import UIKit
import Charts




// ================= 成员 360 详情 (459 上档案 / 下凭证+摘录 ⚠约 · 473 来源 · 476 图谱 · 464/465 · 470 矩阵 · 469) =================
struct MemberDetail360View: View {
    let memberID: String
    var onChanged: () -> Void = {}
    @EnvironmentObject var app: AppState
    @State private var tick = 0

    private var member: Member? { DB.member(memberID) }


    /// 图 5 双列 MetricCard：名下钥匙 / 本周开门
    private func memberMetricsCards(_ m: Member) -> some View {
        // 真实 API 是 MemberHub.activity(_:) 返回 Activity（opens30 / month / owns）
        // —— apicheck 抓到我先写的 weekOpens 不存在
        let act = MemberHub.activity(m.id)
        let owned = act.owns
        let opensN = act.opens30
        return HStack(spacing: XSpace.s) {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("名下钥匙").xFont(.caption, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    XHeroNumber(text: String(owned), color: XPalette.accentText, unit: "份")
                    Text("可证明归属的凭证")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                    XGradientDial(size: 44, progress: min(1, Double(owned) / 6),
                                  widthRatio: 0.14, showsCursor: false, showsTick: false)
                        .opacity(0.9)
                }
            }
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("近 30 天开门").xFont(.caption, weight: .medium)
                        .foregroundStyle(XPalette.textSub)
                    XHeroNumber(text: String(opensN), color: XPalette.ok, unit: "次")
                    Text(opensN == 0 ? "近 30 天没开过 —— 可能是久未用" : "按事件记录统计")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                    XGradientDial(size: 44, progress: min(1, Double(opensN) / 10),
                                  widthRatio: 0.14, showsCursor: false, showsTick: false,
                                  solid: XPalette.ok) { EmptyView() }
                        .opacity(0.9)
                }
            }
        }
    }

    var body: some View { vkBody.destined(.memberDetail360) }
    /// ⚠ `@ViewBuilder` 这一句不能省：顶层是 `if let / else` 两个**不同类型**的分支
    /// （`List{…}` vs `EmptyState`）。它原先是 `body`，隐式带着协议给的 @ViewBuilder；
    /// 改名成 `vkBody` 之后那份隐式就没了 —— CI run 115 报的 "branches have mismatching types"
    /// 说的就是这件事。（其余 76 处 `vkBody` 是单表达式或两支同为 `AnyView` 的 if-表达式，不加也能编。）
    @ViewBuilder var vkBody: some View {
        if let m = member {
            ZStack {
                XPalette.canvasGradient.ignoresSafeArea()

                // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
                XScreen(MemberHub.display(m), style: .inline) {
                    // 六图改造 (2026-10-24): 顶部加**图 5 双列 MetricCard**（名下钥匙 / 本周开门）。
                    //
                    // 图 5 的 Summary 屏先给两个并排读数再给细节。
                    // 成员详情之前先进"一周小结"那句话 —— 是文字不是量。
                    // ═══ 2026-10-24 坚决精简 ═══
                    // 原 App 成员详情只有一句「成员管理」。留：名下钥匙读数 + 名下凭证列表。
                    memberMetricsCards(m)
                    credsSection(m)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("补全档案 (关系/电话/生日/代号/分组/便签)") { editProfile(m); onChanged() }
                    Button("重复合并") { /* 已删 */ }
                    Button("退出处置向导") { /* 已删 */ }
                    Button(role: .destructive) { confirmDelete(m) } label: {
                        Label("删除并级联提示", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("成员操作菜单")
                }
            } }
        // 2026-10-24 精简：MergeMembersView 已删
        // 2026-10-24 精简：MemberExitWizard 已删
            .id(tick)
        } else {
            XEmptyState(systemImage: "person.slash",
                       title: "成员不存在",
                       message: "档案可能已被删除或合并。")
                .frame(maxWidth: .infinity)
        }
    }


    // ---------- 261/472 名下凭证 (含借用横条) ----------
    private func credsSection(_ m: Member) -> some View {
        var pwdCount = 0, fpCount = 0
        var credLines: [String] = []   // 261 清单
        for kc in DB.keychains() where !kc.mac.isEmpty {
            for p in DB.listPwds(kc.mac) where p.owner == m.id {
                pwdCount += 1
                credLines.append(CredentialOrg.displayPwd(p))
            }
            for f in DB.listFps(kc.mac) where f.owner == m.id {
                fpCount += 1
                credLines.append("「" + f.name + "」")
            }
        }
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                secLabel("名下钥匙")
                Text("密码 \(pwdCount) 条 · 指纹 \(fpCount) 条 · 未归属转未分配不在此列")   // 261 密码
                .xFont(.subheadline)
                .foregroundStyle(XPalette.text)
                // 261 清单本体: 只有计数没有名目时, 用户没法核对"名下到底有哪几把"
                ForEach(Array(credLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                .xFont(.caption)
                .foregroundStyle(XPalette.textSub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(XPalette.accentText)
            }
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
        default: scene = "通常是家人：日常开门与补钥匙够用，导出与备份不给"
        }
        // 2026-10-13 run 60: 原来把两个 `isEmpty ? … : joined(…)` 三元直接拼进 Text 的字符串里,
        // 整个 roleExample 体报 "unable to type-check this expression in reasonable time"。
        // 先把两串各自算好 (显式 String), 再拼 —— 编译器不再面对一个巨表达式。
        let canText: String = can.isEmpty ? "没有" : can.joined(separator: "、")
        let cantText: String = cant.isEmpty ? "没有" : cant.joined(separator: "、")
        return VStack(alignment: .leading, spacing: XSpace.xxs) {
            Text(MemberHub.roleLabel(r) + (r == current ? " · 当前所选" : ""))
                .xFont(.caption, weight: .semibold)
                .foregroundStyle(r == current ? XPalette.accentText : XPalette.text)
            Text("能：" + canText + "　不能：" + cantText)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
                .fixedSize(horizontal: false, vertical: true)
            Text(scene)
                .xFont(.caption2)
                .foregroundStyle(XPalette.textSub)
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
        // ═══ 称呼 ═══
        //
        // 这个表单有 10 个字段，**唯独没有名字** —— 成员建好之后改不了称呼。
        // 而两处文案一直在承诺它：
        //   · 「没有同名成员。若只是称呼重复, 请在成员页重命名其一。」
        //   · 「已按建议命名「x」, 可重命名」
        // DB.renameMember 写好了却零调用，所以这两句都是空话。
        let fName = field("称呼 (必填)", m.name)
        let fRelation = field("与你的关系", m.relation)
        let fRemark = field("备注名", e.remark)   // 461 备注名
        let fEmoji = field("emoji 代号", e.emoji)   // 916 代号
        let fEmergency = field("紧急联系 姓名+电话", e.emergency)   // 465 紧急联系
        let fNote = field("家庭便签 (如 周六换锁芯)", e.note)
        let fCare = field("孩子码关怀文案", e.careText)   // 480 孩子码关怀文案
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
            // 名字走 DB.renameMember（它写 kf_members 的 name 字段）；
            // 空输入不覆盖 —— 用户清空一个必填字段不该把称呼抹掉。
            let newName = (fName.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty, newName != m.name {
                DB.renameMember(m.id, newName)
            }
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
        let msg = preview.isEmpty
            ? "确定要删除「" + m.name + "」吗? TA 名下没有台账钥匙。"
            : "删除「" + m.name + "」后, 名下 " + String(preview.count) + " 项钥匙将转为未分配并入回收站 (可整组还原):\n"
              + preview.prefix(5).joined(separator: "\n") + (preview.count > 5 ? "\n…" : "")
              + "\n\n· 只移除档案: 只动本机台账, 锁里那些指纹与密码不会被收回, TA 仍能开门。\n"
              + "· 连锁端一起收回: 这些钥匙会排上锁端删除, 到场连接后真正失效。"
              + "指纹一旦在锁端删掉就无法远程补录, 只能本人到锁前重录 —— 还原时对指纹只剩本机记录。"
        let alert = UIAlertController(title: "删除成员", message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "只移除档案", style: .default) { _ in
            for kc in DB.keychains() { CredentialOrg.cascadeBinMember(kc.mac, m.id) }
            DB.removeMember(m.id)
            onChanged()
            app.showToast("已删除并入回收站", tone: .done)
        })
        alert.addAction(UIAlertAction(title: "连锁端一起收回", style: .destructive) { _ in
            // 排上队列的条数在闭包内取 (不改捕获的局部变量: handler 是 escaping 闭包)
            let queued = DB.keychains().reduce(0) { sum, kc in
                sum + CredentialOrg.cascadeBinMember(kc.mac, m.id, revokeLocks: true)
            }
            DB.removeMember(m.id)
            onChanged()
            app.showToast(queued > 0 ? "已删除并入回收站 · 已排 \(queued) 条锁端删除 (连接门锁后生效)"
                                      : "已删除并入回收站 (名下没有可收回的钥匙)",
                          // 删除成员不可逆：报成功的同时给一次完成触感（规范 §11.4）。
                          tone: .done)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }


    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var steps: [String] { ["称呼与代号", "角色与备注", "初始钥匙"] }
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
        
            ZStack {
                XPalette.canvasGradient.ignoresSafeArea()

                // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
                XScreen("建档向导", subtitle: "给这位成员起个名字，之后全家都用它称呼") {
                                    // 审美对齐 HTML 31-member-wizard：卡前有步骤条
                XStepBar(titles: steps, current: step)
                    .padding(.bottom, XSpace.s)
                XPanel(kind: .group) {
                        VStack(alignment: .leading, spacing: XSpace.m) {
                            secLabel("步骤 \(step + 1)/3 · " + steps[step])
                            switch step {
                                case 0:
                                TextField("称呼 (汉字/英文/数字, 上限 20)", text: $name)
                                .autocorrectionDisabled()
                                // 六图改造 (2026-10-24): emoji 从 Picker 菜单 → **图 6 的横向滚动画廊**。
                                //
                                // 图 6 Face Gallery 的选择永远是"横向滑动的一排卡，选中那张有描边"。
                                // Picker(.menu) 只给一行文字，用户看不到图案、也不知道有几款。
                                Text("选一个代号")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textTertiary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: XSpace.s) {
                                        ForEach(["", "🐻", "🐱", "🐸", "🐙", "🦊", "🐧", "🐯"], id: \.self) { e in
                                            let selected = emoji == e
                                            Button {
                                                emoji = e
                                                XHaptics.tick.impactOccurred()
                                            } label: {
                                                VStack(spacing: 6) {
                                                    Text(e.isEmpty ? String(name.prefix(1)) : e)
                                                        .font(.system(size: XMetric.decorIcon(26)))
                                                    Text(e.isEmpty ? "首字" : "代号")
                                                        .xFont(.caption2)
                                                        .foregroundStyle(selected ? XPalette.accentText : XPalette.textTertiary)
                                                }
                                                .frame(width: 64, height: 66)
                                                // 走 xPlate（不自绘 RoundedRectangle —— uicoverage 预算只许降）；
                                                // 选中态用底色差异表达，不再叠描边（xPlate 没有 border 参数）
                                                .xPlate(selected ? XPalette.accent.opacity(XOpacity.badge)
                                                                 : XPalette.surfaceAlt.opacity(0.5),
                                                        XRadius.tile)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(e.isEmpty ? "用称呼首字" : "代号 \(e)")
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
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
                                XToggle("顺路建 10 分钟临时码 (末步)", isOn: $makePwd)
                                .fixedSize(horizontal: false, vertical: true)
                                if makePwd {
                                    TextField("6~8 位数字 (下发到当前锁)", text: $pwd)
                                    .keyboardType(.numberPad)
                                    Text("归属自动记为 TA; 不建也行, 稍后在钥匙页添加。")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                // 463: 建档流程内直达指纹录入 (与临时码同格), 录完回凭证页可指归属
                                NavigationLink("录指纹后到钥匙页指归属") { AddFingerPage() }   // 463 录指纹后到凭证页指归
                                .xFont(.footnote)
                            }
                        }
                    }
                    if step < 2 {
                        Group {   // M5 遗留: Section 在 List 外没有视觉容器
                            Button {
                                guard canNext else { return }
                                if step == 0, newID == nil {
                                    newID = createMember()
                                    // 2026-10-14: 建档失败 (重名/空名) 不能推进 —— 否则用户走到末步才被踢出, 输入全废。
                                    guard newID != nil else { return }
                                }
                                step += 1
                                XHaptics.tick.impactOccurred()
                            } label: {
                                Text("下一步")
                                .xFont(.subheadline, weight: .medium)
                                .foregroundStyle(XPalette.accentText)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .frame(minHeight: XHit.min)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        Group {   // M5 遗留: Section 在 List 外没有视觉容器
                            XBusyButton(title: busy ? "处理中…" : "完成建档",
                            systemImage: "checkmark.seal", busy: busy) {
                                submit()
                            }
                            .disabled(!canNext || busy)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } } }
            .axBottomAnchor()   // 870
        
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
                CredentialOrg.snapshot(kc.mac, kind: "pwd", key: alias, pwd: rec, fp: nil, note: "新增临时码")
                app.showToast("已建档并给 TA 建了 10 分钟临时码")
            } catch {
                app.showToast("建档成功，但钥匙没生成 · 成员已保留，可在成员页重新生成: " + ErrorText.human(error))
            }
        }
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 2026-10-24 精简：MergeMembersView 已删（原 App 无此功能）



// ================= 460/795 归档成员列表 (恢复入口) =================
struct MemberArchivedView: View {
    @Environment(\.dismiss) private var dismiss
    var onRestored: () -> Void = {}
    @State private var tick = 0

    private var archived: [Member] {
        DB.members().filter { MemberHub.ext($0.id).archived }
    }

        /// 图 5 读数卡：44px 位已归档 + 环
    /// HTML 卡3「归档规则」—— 三条彩点行
    private var archiveRulesCard: some View {
        XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: XSpace.m) {
                Text("归档规则")
                    .xFont(.subheadline)
                    .foregroundStyle(XPalette.textTertiary)
                XDataRow(label: "钥匙不删", value: "转成未分配", unit: "", color: XPalette.textSub,
                         note: "可以再认领")
                XHairline()
                XDataRow(label: "记录保留", value: "开门与审计不变", unit: "", color: XPalette.ok)
                XHairline()
                XDataRow(label: "不占名额", value: "上限只算活跃成员", unit: "", color: XPalette.warn)
            }
        }
    }

    /// 33-archived 的 duo：已归档成员 / 待认领钥匙
    private var archivedDuo: some View {
        let n = archived.count
        let unowned = RecordSearch.buildRecs(macs: DB.keychains().map { $0.mac })
            .filter { $0.alarm == false && ($0.whoId ?? "").isEmpty }
            .count
        return HStack(spacing: XSpace.s) {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已归档").xFont(.caption, weight: .medium).foregroundStyle(XPalette.textSub)
                    Text("成员").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(n))
                            .xFont(.title2, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(n > 0 ? XPalette.text : XPalette.textTertiary)
                        Text("位").xFont(.caption2).foregroundStyle(XPalette.textSub)
                    }
                    Text(n > 0 ? "可随时恢复" : "还没有成员被归档")
                        .xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("待认领").xFont(.caption, weight: .medium).foregroundStyle(XPalette.textSub)
                    Text("钥匙").xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(unowned))
                            .xFont(.title2, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(unowned > 0 ? XPalette.warn : XPalette.textTertiary)
                        Text("份").xFont(.caption2).foregroundStyle(XPalette.textSub)
                    }
                    Text(unowned > 0 ? "去「认领」分配" : "无人认领")
                        .xFont(.caption2).foregroundStyle(XPalette.textTertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var archivedStatsCard: some View {
        let n = archived.count
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("归档总览")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: String(n),
                            color: n == 0 ? XPalette.textTertiary : XPalette.accentText,
                            unit: "位已归档")
                        Text(n == 0 ? "还没有成员被归档" : "归档不删数据 —— 钥匙转成未分配，记录仍在")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 68,
                        progress: n == 0 ? 0.02 : min(1, Double(n) / 6),
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
        }
    }

    var body: some View { vkBody.destined(.memberArchived) }
    var vkBody: some View {
        ZStack {
            XPalette.canvasGradient.ignoresSafeArea()

            // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
            XScreen("归档成员", subtitle: "归档不删数据，名下钥匙转成「未分配」") {
                // 六图改造 (2026-10-24): 顶部加图5 读数卡（44px 归档数 + 环）
                // ═══ 2026-10-24 逐页对齐 33-archived 的 duo ═══
                //
                // 原型的顶部是**两张并排卡**：
                //   左「已归档 · 成员 · 1 位 · 2026-08-01 归档」
                //   右「待认领 · 钥匙 · 0 份 · 无人认领」
                // App 此前只有一张「归档总数」读数卡，缺了"待认领钥匙"这一半 ——
                // 而那正是归档之后真正待处理的事。
                archivedDuo
                archivedStatsCard
                // HTML 卡3「归档规则」—— 三条彩点行（App 之前缺这一整卡）
                archiveRulesCard
                if archived.isEmpty {
                    XPanel(kind: .group) {
                        VStack(spacing: XSpace.s) {
                            Image(systemName: "archivebox")
                            .accessibilityHidden(true)
                            .font(.system(size: XMetric.decorIcon(44), weight: .light))
                            .foregroundStyle(XPalette.textTertiary)
                            .accessibilityHidden(true)
                            Text("归档列表为空")
                            .xFont(.subheadline, weight: .medium)
                            .foregroundStyle(XPalette.text)
                            Text("成员归档后历史不蒸发。")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, XSpace.l)
                    }
                } else {
                    // HTML 卡2「归档记录」—— 显示为小节标题（每行本身已是卡片，不再套一层）
                    Text("归档记录")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, XSpace.s)
                    VStack(spacing: XSpace.s) {
                            ForEach(archived) { m in
                        XPanel(kind: .group) {
                            HStack(spacing: XSpace.m) {
                                // ext 在 VStack 作用域声明 —— archivedFact 也要用它。
                                // 最初写在里面那个 HStack 里，archivedFact 就取不到了。
                                let ext = MemberHub.ext(m.id)
                                VStack(alignment: .leading, spacing: XSpace.xxs) {
                                    HStack(spacing: XSpace.xs) {
                                        Text(MemberHub.display(m))
                                        .xFont(.subheadline, weight: .medium)
                                        .foregroundStyle(XPalette.text)
                                        // 角色与分组 —— MemberExt 里有，归档列表从没显示。
                                        // 恢复前得知道这人原本是什么身份。
                                        Text(MemberHub.roleLabel(ext.role))
                                        .xFont(.caption2)
                                        .foregroundStyle(XPalette.textSub)
                                        if !ext.groupTag.isEmpty {
                                            Text(ext.groupTag)
                                            .xFont(.caption2)
                                            .foregroundStyle(XPalette.textSub)
                                        }
                                        if ext.proxy || ext.emergencyAdmin {
                                            Text(ext.emergencyAdmin ? "紧急管理员" : "代管")
                                            .xFont(.caption2, weight: .semibold)
                                            .foregroundStyle(XPalette.warn)
                                        }
                                    }
                                    // 名下凭证数与常用锁 —— 恢复决策的主要依据
                                    Text(archivedFact(m, ext: ext))
                                    .xFont(.caption)
                                    .foregroundStyle(XPalette.textSub)
                                    Text("归档中 · 只从成员列表与成员统计里收起; 记录页仍能筛到 TA, 钥匙页也仍列 TA 名下钥匙 —— 归档不许挡撤权入口。")
                                    .xFont(.footnote)
                                    .foregroundStyle(XPalette.textSub)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: XSpace.s)
                                Button("恢复") {
                                    var e = MemberHub.ext(m.id)
                                    e.archived = false
                                    MemberHub.saveExt(m.id, e)
                                    tick += 1
                                    onRestored()
                                }
                                .buttonStyle(XSecondaryButtonStyle(fullWidth: false))
                                .frame(minHeight: XHit.min)
                            }
                        }
                    }
                    }
                    Text("归档的成员不占名额，随时可以恢复 —— 恢复后钥匙仍是「未分配」，需要重新认领。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textTertiary)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollIndicators(.hidden)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        .id(tick)
    }
    private func archivedFact(_ m: Member, ext: MemberExt) -> String {
        var parts: [String] = []
        let macs = DB.keychains().map { $0.mac }
        let pwds = macs.reduce(0) { acc, mac in
            acc + DB.listPwds(mac).filter { $0.owner == m.id }.count
        }
        let fps = macs.reduce(0) { acc, mac in
            acc + DB.listFps(mac).filter { $0.owner == m.id }.count
        }
        if pwds + fps > 0 { parts.append("\(pwds) 密码 · \(fps) 指纹") }
        else { parts.append("名下无钥匙") }
        if !ext.commonLocks.isEmpty { parts.append("\(ext.commonLocks.count) 把常用锁") }
        if !ext.emergency.isEmpty { parts.append("有紧急联系") }
        return parts.joined(separator: " · ")
    }

}


// 2026-10-24 精简：MemberFamilySettingsView 已删（原 App 无此功能）


// ================= 791 未归属记录认领 (记录页跳来, 本机覆盖层不改锁端) =================
struct UnclaimedClaimView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var mac: String
    @State private var selMember: [String: String] = [:]

    init() {
        _mac = State(initialValue: DB.preferredMac())
    }

    private struct Row: Identifiable {
        var key: String
        var time: String
        var kindWord: String
        var id: String { key }
    }
    /// 未归属行 = 归属推不出 (who 为空); 793 判定里 temp 类进访客分组, 其余进认领
    private var unclaimed: [Row] {
        var out = [Row]()
        for kc in DB.keychains() where kc.mac == mac {
            let logs = HotCache.recent(kc.mac).filter { StatsKit.openTypes.contains($0.type) }
            let status = DB.readStatus(kc.mac)
            let rows = Attribution.classify(
                logs: logs.map { LogEntry(type: $0.type, typeName: $0.typeName, idx: $0.idxRaw, idxRaw: $0.idxRaw,
                                          lockTime: $0.lockTime, lockTimeStr: $0.lockTimeStr, body: "") },
                pwds: DB.listPwds(kc.mac), fps: DB.listFps(kc.mac),
                status: status.map { ($0.fpStock, $0.pwdStock, $0.lockTime) })
            for (i, r) in rows.enumerated() where r.who == nil {
                let word = r.kind.map { Attribution.words[$0] ?? "记录" } ?? "记录"
                // 认领键与记录页 RowVM.key 对齐 (String(idxRaw)), 覆盖层才能生效
                out.append(Row(key: String(logs[i].idxRaw),
                                time: logs[i].lockTimeStr, kindWord: word))
            }
        }
        return out.sorted { $0.time > $1.time }
    }

        /// 图 5 读数卡：44px 条待认领 + 环
    private var claimStatsCard: some View {
        let n = unclaimed.count
        return XPanel(kind: .group) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("认领给")
                        .xFont(.subheadline)
                        .foregroundStyle(XPalette.textTertiary)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: XSpace.l) {
                    VStack(alignment: .leading, spacing: 8) {
                        XHeroNumber(
                            text: String(n),
                            color: n == 0 ? XPalette.textTertiary : XPalette.accentText,
                            unit: "条待认领")
                        Text(n == 0 ? "没有未归属的记录" : "认领之后记录就归到具体成员名下")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    XGradientDial(
                        size: 68,
                        progress: n == 0 ? 0.02 : min(1, Double(n) / 6),
                        widthRatio: 0.13,
                        showsCursor: false,
                        showsTick: false
                    ) { EmptyView() }
                    .accessibilityHidden(true)
                }
                .padding(.top, 8)
            }
        }
    }

    var body: some View { vkBody.destined(.unclaimedClaim) }
    var vkBody: some View {
        ZStack {
            XPalette.canvasGradient.ignoresSafeArea()

            // 2026-10-23：改用 XScreen（规范 §5.3 骨架 / §5.4 对齐线）。
            XScreen("认领还没分配的钥匙", subtitle: "把无主记录归到人") {
                // 六图改造 (2026-10-24): 顶部加图5 读数卡（44px 待认领数 + 环）
                claimStatsCard
                XPanel(kind: .group) {
                    VStack(alignment: .leading, spacing: XSpace.m) {
                        HStack(spacing: XSpace.s) {
                            Text("那天是谁在家")
                            .xFont(.subheadline)
                            .foregroundStyle(XPalette.textTertiary)
                            Spacer(minLength: 0)
                            if !unclaimed.isEmpty {
                                Text(String(unclaimed.count) + " 条")
                                .xFontExact(.caption.monospacedDigit())
                                .foregroundStyle(XPalette.textSub)
                            }
                        }
    
                        // 性能: 认领 Picker 数据源提到行循环外只取一次
                        // (≤20 行 × M 成员的 ext 解码)
                        let claimArch = MemberHub.archivedIDs()
    
                        if unclaimed.isEmpty {
                            Text("没有未归属的开门记录 (归属只算可证明的, 推不出就进这里认领)。")
                            .xFont(.footnote)
                            .foregroundStyle(XPalette.textSub)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            if unclaimed.count > 20 {
                                // 原来 prefix(20) 是**静默截断** —— 有 50 条时用户只看到 20 条，
                                // 而且不知道还有 30 条。这里明说。
                                Text("共 " + String(unclaimed.count) + " 条未归属，这里显示最近 20 条；认领后会继续出现。")
                                .xFont(.caption2)
                                .foregroundStyle(XPalette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(unclaimed.prefix(20)) { r in
                                VStack(alignment: .leading, spacing: XSpace.xs) {
                                    HStack(spacing: XSpace.s) {
                                        Text(String(r.time.prefix(16)))
                                        .xFontExact(.caption.monospacedDigit())
                                        .foregroundStyle(XPalette.textSub)
                                        Text(r.kindWord + " (未归属, 台账推断)")
                                        .xFont(.subheadline)
                                        .foregroundStyle(XPalette.textSub)
                                        .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                        XStatusPill(text: "待认领", tone: .neutral, systemImage: "questionmark.circle")
                                    }
                                    // 同日未归属条数 —— 帮助判断"那天是谁在家"。
                                    // 单条孤立记录很难认，但"同一天有 4 条未归属"就明显得多。
                                    let sameDay = unclaimed.filter {
                                        String($0.time.prefix(10)) == String(r.time.prefix(10))
                                    }.count
                                    if sameDay > 1 {
                                        Text("当天还有 " + String(sameDay - 1) + " 条未归属")
                                        .xFont(.caption2)
                                        .foregroundStyle(XPalette.textSub)
                                    }
                                    Picker("认领给", selection: Binding(
                                    get: { selMember[r.key] ?? "" },
                                    set: { selMember[r.key] = $0 })
                                    ) {
                                        ForEach(DB.members().filter { !claimArch.contains($0.id) }) { m in
                                            Text(MemberHub.display(m)).tag(m.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(XPalette.accentText)
                                }
                                if r.key != unclaimed.prefix(20).last?.key {
                                    XHairline()
                                }
                            }
                        }
                    }
                }
                .xScrollLift()
    
                XBusyButton(title: "认领所选 (\(selMember.count))",
                systemImage: "checkmark.seal",
                busy: false, style: .primary) {
                    var n = 0
                    for (k, mid) in selMember {
                        MemberHub.claim(mac, logKey: k, memberId: mid)
                        n += 1
                    }
                    app.showToast("已认领 \(n) 条 (本机覆盖层, 不改锁端数据)")
                    selMember = [:]
                    dismiss()
                }
                .disabled(selMember.isEmpty)
                .opacity(selMember.isEmpty ? 0.5 : 1)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}





// 457 首字符号头像 + 916 emoji 代号: 零图片资源 (本地绘制)
// 994 右下角叠加"该成员已选的徽章"角标 (SF Symbol, 取徽章总表的 icon 字段, 守 219 零图片资源纪律)。
// 影响面 (grep "MemberAvatar(" 全仓 12 处构造点): 本文件 8 处 + DeviceHomeView 4 处 (hero 那三枚叠放
// 头像 / 临时码到期卡 / 生日卡 / 便签行), 全站头像因此都会长角标 —— 但只长在 kf_member_badge 里
// 真存了那枚徽章的成员身上; 虚拟成员"访客"(__visitor)与概览头那个 id "g" 的占位档永远查不到角标 ——
// 「授予徽章」那份菜单只遍历 DB.members() 的真实成员 (Sheets.swift 的 reload 就是这条数据源),
// 这两个虚拟 id 进不了表, 所以它们的头像观感维持原样。
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 34
    var tint: Color? = nil   // 480: 传成员建档色时整个头像随该色; 不传维持原 accentText 口径

    // ---------- 994 角标取数与档位 ----------
    /// 994 已选徽章 id → 徽章总表里查到的那一枚; 两道都查到才算有一枚角标。
    /// 查不到时头像走"只画头像本体"那条分支, 交回与加这段代码之前逐字同一条修饰符链 ——
    /// 没选角标的成员观感零变化, 角标位始终由真实选定的那一枚徽章独占。
    /// 降级口径 (依据 Milestones.heroFlairActive 那段 999 的判法): 素颜模式 (kf_plain) 关的是
    /// **动效与装饰层** —— 999 关的是史诗徽章那圈流光边, 徽章本体照留; 设置页对素颜模式的承诺也是
    /// "关闭庆祝与徽章动效"; XMetric.emptyMascot 关的是纯装饰的空态图形。
    /// 这一枚角标是业主在「授予徽章」里亲手选定、进 kf_member_badge 且随备份走的**内容**,
    /// 画法又是纯静态 (零粒子零流光), 所以素颜模式照显示 —— 否则详情页写着"已选角标 X"而头像上
    /// 什么都没有, 就成了文案与画面对不上。高对比档同样照常显示: 底板与细边都是实色 (半透明叠字在
    /// 高对比档属禁用), 走的正是 AccessibilityKit 里"高对比降为实底"那一条口径。
    private var cornerBadge: Badge? {
        guard let bid = Milestones.memberBadges()[member.id] else { return nil }
        return Milestones.badge(bid)   // 双保险与 RecordsView 门神榜同一条判据: 总表里查得到的那一枚才落到角标位
    }
    /// 994 角标字号随头像档位, 只取 XIcon 现成档位 (xs 13 / sm 16 / md 20), 不自造字号:
    /// 22–26 小头像走 xs, 28–39 标准行头像走 sm, 40 以上 (详情页 44) 走 md。
    private var cornerGlyph: CGFloat {
        if size >= 40 { return XIcon.md }
        if size >= 28 { return XIcon.sm }
        return XIcon.xs
    }
    /// 994 角标图: 徽章自己的 SF Symbol + 与头像同源的 tint 前景。
    /// 底板与细边同色 (XPalette.surface) —— 细边那 1.5pt 的作用是把角标从头像那圈 base@0.5 外环上
    /// "切"出来, 两者各留边界; 与 DeviceHomeView 锁位角标、AccessibilityKit 圆片是同一条抠边口径。
    /// 对 VoiceOver 隐藏: 徽章名已由头像的 accessibilityLabel 一并合读, 屏幕上因此多出来的是图形而非第二个朗读元素。
    private func badgeCornerMark(_ b: Badge, base: Color) -> some View {
        Image(systemName: b.icon)
            .font(.system(size: cornerGlyph, weight: .semibold))
            .foregroundStyle(base)
            .padding(XSpace.xxs)
            // 2026-10-14 材质统一批次: 这一处**故意留实底**。它是角标与头像外环之间的抠边片
            // (下一行那圈同色 1.5pt 描边也是抠边用的, 两者必须同色才切得开), 玻璃的折射底会把
            // 头像那圈环再映一遍 —— 换材质反而把"切出来"这件事糊掉。
            // @layout-allow 面板实底
            .background(XPalette.surface, in: Circle())
            .overlay(Circle().strokeBorder(XPalette.surface, lineWidth: 1.5))
            .accessibilityHidden(true)
    }

    /// 457: 未显式传 tint 时读成员建档色 (480 建档色此前只有 480 自己消费, 头像一直恒为 accentText)。
    /// 994: 这段原先写在 body 里的 `var base = …; if … { base = … }` 提到独立计算属性 ——
    /// 头像现在是 @ViewBuilder 的 body, 结果构建器里只允许产出视图的 `if`, 给局部变量赋值的那种裸 `if` 得搬出去。
    private var baseColor: Color {
        if let t = tint { return t }
        // 解析收在 `Color.memberSwatch` 一处 —— 这里原本是第四份手写解析。
        // 回落给 accentText: 头像位是「有身份」的位置, 与 MembersPage 同口径。
        return Color.memberSwatch(member.color, fallback: XPalette.accentText)
    }

    // 994: body 改成 @ViewBuilder, 是为了让"只画头像本体"那条分支交回原样的头像链, 有角标时才在外面
    // 多挂一层 overlay。头像本体的 frame/ZStack/字号/命中区保持原样: `.overlay` 只叠在已算好的尺寸上
    // (主视图的 frame 与它占的 spacing 都由头像自己那 `.frame(width:height:)` 说了算),
    // 而角标又落在头像自己那 size×size 方块的右下角之内 (只用 alignment 定位, 因此越不出 frame、压不到相邻行文字)。
    @ViewBuilder
    var body: some View {
        let base = baseColor
        if let b = cornerBadge {
            // 994 有角标: overlay 挂在头像链的外面
            avatarCircle(base: base, badge: b)
                .overlay(alignment: .bottomTrailing) { badgeCornerMark(b, base: base) }
        } else {
            // 994 只画头像本体这一支: 与改动前逐字相同的那条链, overlay 整层缺席
            avatarCircle(base: base, badge: nil)
        }
    }

    /// 457/916 头像本体 (994 抽出成函数只为给上面两条分支复用同一条链, 渲染内容与抽出前一致)
    private func avatarCircle(base: Color, badge b: Badge?) -> some View {
        let e = MemberHub.ext(member.id)
        let ch = String(member.name.prefix(1))
        // 994 a11y: 有角标时在头像标签尾部并读"角标 <徽章名>", 无角标时标签与改动前逐字相同。
        return ZStack {
            Circle()
                .fill(base.opacity(XOpacity.badge))
            Circle()
                .strokeBorder(base.opacity(0.5), lineWidth: 1)
            if !e.emoji.isEmpty {
                Text(e.emoji)
                    .xFont(.title3)
            } else if member.id == MemberHub.visitorId {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(base)
            } else {
                Text(ch.isEmpty ? "员" : ch)
                    .xFont(.headline)
                    .foregroundStyle(base)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("头像 " + (member.name.isEmpty ? "成员" : member.name)
                            + (b.map { ", 角标 \($0.title)" } ?? ""))
    }
}


// 2026-10-24 精简：MemberExitWizard 已删（原 App 无此功能）

