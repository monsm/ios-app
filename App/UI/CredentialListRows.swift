// 凭证页 · 列表行渲染（行 / 标题 / 副标题 / 续期文案 / 行菜单 / 归属徽标 / 选择态）
// 2026-10-29 从 CredentialsView.swift（1773 行）拆出。
// 这些是 CredentialsView 的 extension —— 原 private 成员已提升为 internal，跨文件可见。
import SwiftUI

extension CredentialsView {
    @ViewBuilder
    func credRow(_ hit: CredHit) -> some View {
        let p = hit.pwd
        let f = hit.fp
        // 331 同行一个时刻: 胶囊与副行倒计时同帧同判据, 不留两处各自取 Date()
        let now = Date()
        // 901 紧凑档 (kf_row_h 非 tall): 隐藏副标题只留名称与状态 (IDEA-BANK 901 的"RSS 紧凑行")
        let compactRow = DB.store.getString("kf_row_h") != "tall"
        return credRowContent(hit, p: p, f: f, now: now, compactRow: compactRow)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titleOf(hit))
        .accessibilityActions {
            if let v = hit.pwd?.pwd {
                Button("拷贝密码明文") {   // 849 拷贝密码明文
                    Clip.set(v)
                    app.showToast("已复制")
                }
            }
        }
        .contextMenu { credMenu(hit) }
        .overlay(alignment: .topLeading) {
            if editMode { selectionCircle(hit) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard editMode else { return }
            toggleSel(hit)
        }
        // 849 非编辑态双击整行 = 拷贝该条密码明文 (与详情页同一条 405 通路);
        // 编辑态整行单击已归勾选, 双击里再判一次 editMode, 两种模式不抢手势
        .onTapGesture(count: 2) {
            if !editMode, let v = hit.pwd?.pwd {
                Clip.set(v)
                app.showToast("已复制")
            }
        }
        .swipeActions(edge: .trailing) {
            if editMode {
                Button { toggleSel(hit) } label: {
                    Label(isSelected(hit) ? "取消选" : "选", systemImage: isSelected(hit) ? "xmark.circle" : "checkmark.circle")
                }
                .tint(DS.Palette.accent)
            }
        }
        // 182 原先这里挂着一枚 onLongPressGesture, 弹的是「长按可停用/删除; 编辑模式里用顺序按钮调整组内先后」——
        // 既不是拖动 (假热区), 又会把拖动排序要用的那次长按抢走。排序真做到之后这一句整块撤掉:
        // 停用/删除走右侧滑动或长按菜单 (contextMenu 由系统提供), 组内先后走上方的排序档 (182)。
        // 901 行高二档 (kf_row_h): minHeight 而不是固定 height —— 固定高度会裁掉多行备注
        .frame(minHeight: DS.Metric.rowMinH, alignment: .topLeading)
        .disabled(isBusy)
    }

    /// 凭证行的内容层（标题 / 状态胶囊 / 归属徽标 / 副行 / 推断名）。
    @ViewBuilder
    private func credRowContent(_ hit: CredHit, p: LedgerPwd?, f: LedgerFp?, now: Date, compactRow: Bool) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.xs) {
        HStack(spacing: DS.Space.s) {
            Text(titleOf(hit))
                .vkFont(rowTitleFont)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let p {
                if CredentialOrg.pwdState(p) == 2 {
                    StatusPill(text: "已过期", systemImage: "clock.badge.xmark", tone: .danger)
                } else if CredentialOrg.isEarlyExpired(mac, p, now) {
                    // 331 本机提前线已过、锁端未到期: 只提示, 锁到锁端到期照常开门
                    StatusPill(text: "提前失效", systemImage: "hourglass", tone: .warn)
                } else if CredentialOrg.pwdState(p) == 1 {
                    StatusPill(text: "已排期", systemImage: "calendar.badge.clock", tone: .accent)
                }
            }
            if let f, f.isAlarm == true {
                StatusPill(text: "预警指纹", systemImage: "bell.badge", tone: .warn)
            }
            if let o = p?.owner ?? f?.owner, !o.isEmpty {
                ownerBadge(CredentialOrg.ownerName(o))
            }
            Spacer(minLength: 0)
            if hit.pinned {
                Image(systemName: "star.fill")
                    .font(.system(size: DS.Icon.sm, weight: .medium))
                    .foregroundStyle(DS.Palette.accentText)
                    .accessibilityLabel("已置顶")
            }
            if busyKey == ("p" + String(hit.id.dropFirst())) {
                ProgressView().controlSize(.mini)
            }
        }
        let sub = subOf(hit, now)
        if !sub.isEmpty && !compactRow {
            Text(sub)
                .vkFont(rowSubFont)
                .foregroundStyle(rowSubColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        // 918 命名模板: 主标题下挂 "谁-哪里-何时" 推断名 (锁端无名称字段, 本地展示);
        // 901 紧凑档同副行一起收起 —— "只留名称与状态"里没有它
        if !compactRow, let p, CredentialOrg.aliasDisplay, CredentialOrg.namingTemplate(p) != titleOf(hit) {
            Text(CredentialOrg.namingTemplate(p))
                .vkFont(rowSubFont)
                .foregroundStyle(rowSubColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityHidden(true)
        }
    }
    }

    func titleOf(_ hit: CredHit) -> String {
        if let p = hit.pwd { return CredentialOrg.displayPwd(p) }
        if let f = hit.fp { return f.name }
        return ""
    }

    func subOf(_ hit: CredHit, _ now: Date) -> String {
        if let p = hit.pwd {
            return [
                p.temp ? "一次性" : "",
                p.at > 0 ? "添加于 " + shortDate(p.at) : "",
                "",
                !p.note.isEmpty ? "备注 \(p.note)" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if let f = hit.fp {
            return [
                f.at > 0 ? "登记于 " + shortDate(f.at) : "已登记在门锁内",
                f.at > 0 ? "" : "",
                f.src == "app" ? "本机录入" : "",
                !f.note.isEmpty ? "备注 \(f.note)" : ""
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return ""
    }

    /// 368 催办语: 称呼用备注或成员名, 到期日按本机时区读法; 没有称呼就说"您好", 不编造姓名。
    func renewText(_ p: LedgerPwd, _ to: Date) -> String {
        let who = p.note.isEmpty ? (p.owner.flatMap { DB.member($0)?.name } ?? "") : p.note
        let greet = who.isEmpty ? "您好" : "您好，\(who)"
        let day = to.formatted(.dateTime.year().month().day())
        let hour = to.formatted(.dateTime.hour().minute())
        return "\(greet)，您那条进门凭证将在 \(day) \(hour) 到期。"
            + "如果还需要用，麻烦提前说一声，我给您延一下或重新发一张。"
    }

    @ViewBuilder
    func credMenu(_ hit: CredHit) -> some View {
        if let p = hit.pwd {
            Button("查看密码内容") { viewPwd(p) }
            Button("密码详情") { pwdDetailItem = p }   // 305/308/309 密码详情
            Button("修改密码内容") { modifyPwd(p) }
            Button("修改有效期") { Task { resetPwdPeriod(p) } }
            Button("添加备注") { editNote(pwd: p) }
            Menu("归属到成员") { ownerMenu(isPwd: true, key: p.alias) }
            Divider()
            Button("三档预警") { toggleAlerts(p) }   // 359 三档预警
            // 368 延期催办文本: 只对"有到期时间且 7 天内到期"的条目出现, 产出可直接发给住客的礼貌催办语。
            // 文本里**绝不含口令本身** (要复制到聊天工具, 含码等于把门卡发出去)。
            if let d = CredentialOrg.expiryDate(p), d.timeIntervalSinceNow > 0, d.timeIntervalSinceNow < 7 * 86_400 {
                Button("生成延期提醒文本") {   // 368 生成延期提醒文本
                    Clip.set(renewText(p, d))
                    app.showToast("催办文本已复制到剪贴板 (不含口令)")
                }
            }
                    // 2026-10-26 精简：版本历史入口已删。
            Divider()
            Button("停用 (本地, 锁端待处理)", role: .destructive) { disablePwd(p) }
            Button("彻底删除", role: .destructive) { deletePwd(p) }   // 670 彻底删除
        }
        if let f = hit.fp {
            Button("指纹详情") { fpDetailItem = f }   // 316/320/323 指纹详情
            Button("重命名") { renameFp(f) }
            Button(f.isAlarm == true ? "取消预警指纹" : "设为预警指纹") {
                DB.setFpAlarm(mac, f.batch, f.isAlarm != true)
                app.showToast(f.isAlarm == true ? "已取消预警指纹" : "已设为预警指纹")
            }
            Button("添加备注") { editNote(fp: f) }
            Menu("归属到成员") { ownerMenu(isPwd: false, key: f.batch) }
                    // 2026-10-26 精简：版本历史入口已删。
                    // 2026-10-28 删除：这枚「置顶 / 取消置顶」是**空动作** —— `Button { }`，
                    // 点了一点反应都没有，而 `CredHit.pinned` 全仓无一处写非默认值。
                    // 置顶功能从未实现过（与同段的「版本历史」「归档」一样是被删功能的残壳）。
                    // 2026-10-26 精简：归档/移出归档入口已删（归档功能整套移除）。
            Divider()
            Button("停用 (本地, 锁端待处理)", role: .destructive) { disableFp(f) }
            Button("彻底删除", role: .destructive) { deleteFp(f) }   // 670 彻底删除
        }
    }

    // 成员归属徽章: 用 accentText (文字级对比度 6:1), 不用品牌填充色
    @ViewBuilder
    func ownerBadge(_ name: String) -> some View {
        Text(name)
            .vkFont(.caption, weight: .medium)
            .lineLimit(1)
            .foregroundStyle(DS.Palette.accentText)
            .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xxs)
            .variantPlate(DS.Palette.accentText.opacity(0.12), .capsule)
    }
    @ViewBuilder
    func selectionCircle(_ hit: CredHit) -> some View {
        let on = isSelected(hit)
        return Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: DS.Icon.md, weight: .medium))
            .foregroundStyle(on ? DS.Palette.accent : DS.Palette.textSub)
            .padding(.leading, 6)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .accessibilityLabel(on ? "已选中" : "未选中")
    }
    func isSelected(_ hit: CredHit) -> Bool {
        if let p = hit.pwd { return selPwds.contains(p.alias) }
        if let f = hit.fp { return selFps.contains(f.batch) }
        return false
    }
    func toggleSel(_ hit: CredHit) {
        if let p = hit.pwd {
            if let i = selPwds.firstIndex(of: p.alias) { selPwds.remove(at: i) } else { selPwds.append(p.alias) }
        } else if let f = hit.fp {
            if let i = selFps.firstIndex(of: f.batch) { selFps.remove(at: i) } else { selFps.append(f.batch) }
        }
    }
}
