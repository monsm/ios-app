// 凭证页 · OTP（临时密码）内联卡与生成/停用
// 2026-10-29 从 CredentialActions.swift 再拆出（原 CredentialsView 的 OTP 段）。
import SwiftUI

extension CredentialsView {
    var otpSection: some View {
        Section("临时密码 (ZOTP)") {
            VariantToggle("开通临时密码", isOn: Binding(
                get: { DB.otpStatus(mac)?.on ?? false },
                set: { on in
                    guard busyKey == nil else { return }
                    // 同上: 开关按下的一刻钉住锁，Task 里用 m 而不是再活读一次
                    let m = mac
                    guard !m.isEmpty else { app.showToast("未选择门锁"); return }
                    busyKey = "otp"
                    Task {
                        defer { busyKey = nil }
                        do {
                            // 第八十八批: 这条命令面原先不先绑锁就直接发 (services 层按自己的 curMac 取钥,
                            // LockService.swift:285-288 / :93)，于是"用户点的是这把锁，19 命令发到上次连过的那把"。
                            // 补 ensureConnected 把目标钉成 m —— 与仓内其它命令面的写法同构。
                            try await app.lock.ensureConnected(mac: m)
                            try await app.lock.setZotp(on)
                            DB.saveOtpStatus(m, OtpStatus(on: on, at: Date().timeIntervalSince1970 * 1000))
                            app.showToast(on ? "临时密码已开启" : "已关闭")
                        } catch {
                            app.showToast("操作失败: \(error.localizedDescription)")
                        }
                    }
                }))
                .disabled(isBusy)
            if DB.otpStatus(mac)?.on == true {
                otpGenRow
                Label {
                    Text("每 30 分钟更换一次; 生成前请先校准门锁时间 (偏差 >180 秒会导致锁侧校验失败)。")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                }
                .vkFont(.caption)
                .foregroundStyle(DS.Palette.textSub)
            } else {
            }
        }
    }


    @ViewBuilder
    var otpGenRow: some View {
        HStack(spacing: DS.Space.s) {
            // 374: 采集进行中不把码排出来, 大字模式也拿不到明文 (刻意只换文本, 不整页遮黑)
                // 2026-10-27 截图核对修复：`otpPwd` 初始是空串，直接 `Text("")` 会渲染成
                // 一个**空的灰胶囊**（外层有背景样式）—— 截图里那个位置看起来像加载失败。
                // 现在空值显示六位占位点，语义是"还没生成"而不是"坏了"。
                Text(otpPwd.isEmpty ? "······" : otpPwd)
                // 885 大字模式: 开关 (kf_ax_bigotp) 或双击切换, 等宽数字防跳 (231)
                .vkFont((DB.store.getBool("kf_ax_bigotp") || otpBig) ? .largeTitle.weight(.semibold).monospacedDigit() : .title3.weight(.semibold).monospacedDigit())
                // 342 换码微动效: 值换掉时逐位滚过去 (与 207 电量数字滚动同一个 contentTransition(.numericText()))。
                // 触感沿用 genOtp() 末尾那一次成功反馈，**不再叠第二次** —— 一次生成两下震动只会让人分不清是哪件事。
                // 动效节操仍由 DS.Motion 那一档决定：系统"减弱动态效果"下走 calm (0.10s easeOut)，不做无响应的滑动。
                .contentTransition(.numericText())
                .animation(DS.Motion.quick, value: otpPwd)
                .foregroundStyle(DS.Palette.text)
                .textSelection(.enabled)
                .onTapGesture(count: 2) { otpBig.toggle() }
                .accessibilityLabel("临时码, 双击切大字号")
                // 375 防窥挡片：**只有用户主动打开才盖住**（`otpShieldOn` 默认 false）。
                // 2026-10-29 修复「生成临时码后被挡住看不见」：原实现用 `if !otpPeek` 而 otpPeek 默认 false，
                // 等于挡片常驻；生成完也不揭开。现在默认不盖，长按才临时揭开，松手复位。
                .overlay(alignment: .leading) {
                    if otpShieldOn && !otpReveal {
                        RoundedRectangle(cornerRadius: DS.Radius.control)
                            .fill(.ultraThinMaterial)
                            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 50, pressing: { p in
                                if !p { withAnimation(DS.Motion.standard) { otpReveal = false } }
                            }, perform: {
                                withAnimation(DS.Motion.standard) { otpReveal = true }
                            })
                            .onTapGesture(count: 2) { otpBig.toggle() }
                    }
                }
                // 防窥挡片的开关放在长按菜单里：不占版面，也不会误触。
                .contextMenu {
                    VariantToggle("防窥挡片（盖住临时码）", isOn: $otpShieldOn)
                }
            Spacer(minLength: DS.Space.m)
            Button {
                genOtp()
            } label: {
                Text("生成")
                    .frame(minHeight: DS.Hit.min)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
            Button {
                Clip.set(otpPwd)   // 405
                app.showToast("已复制")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: DS.Icon.md))
                    .frame(width: DS.Hit.min, height: DS.Hit.min)
                    .contentShape(Rectangle())
            }
            .disabled(otpPwd == "******")
            .accessibilityLabel("复制临时密码")
            .accessibilityHint("把当前临时密码复制到剪贴板")
        }
        // 2026-10-27 截图核对修复：原先只判 `!otpWin.isEmpty`，而 `otpWin` 只在生成时赋值、
        // **从不随窗口过期清空** —— 昨天生成过一次，今天打开页面仍显示昨天的失效时间
        // （截图里显示「于 19:00 失效」而当时 6:49）。现在同时判"是否已过当前窗口"。
        if !otpWin.isEmpty, otpWin == ZOTP.nextWindow() {
            Text("于 \(otpWin) 失效, 失效前仅可使用一次")
                .vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    /// 返回值 = 是否真生成 (首张按钮拿它决定回执; 各失败支自己弹原因, 不静默)。
    @discardableResult
    func genOtp() -> Bool {
        guard busyKey == nil else { return false }
        guard let kc = app.current, kc.skey.count == 32 else { app.showToast("缺少该锁钥匙串"); return false }
        let win = ZOTP.nextWindow()
        let cur = DB.otpIdx(mac)
        let idx = (cur?.invalidTime == win) ? (cur?.idx ?? -1) + 1 : 0
        if idx > 99 {
            app.showToast("当前窗口已达 100 个上限, 请到下一个 30 分钟窗口再生成")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        // 周期必须取**锁端上报**的 zotpPeriod (03#05, 单位分钟), 缺省才回落 30。
        // 2026-10-17 对拍发现: 这里写死 30, 而锁端若是别的窗口, 页面算出的六位码锁端必判错
        // (读快照生成、反而能用)
        let pRaw = DB.readStatus(kc.mac)?.zotpPeriod ?? 0
        let period = pRaw > 0 ? pRaw : 30
        let pwd = ZOTP.generate(macHex: kc.mac, skeyHex: kc.skey, periodMin: period, idx: idx)   // period 单位=分钟（来自锁端 KLV#05 zotpPeriod）
        // `generate` 只在算得出码时才返回值 (钥匙串长度、MAC 形状任一不过就返回空串，见 ZOTP.swift)。
        // 空串不许当「生成成功」：原先会一路把空值写进 otpPwd、复制进剪贴板、再震一下「成功」，
        // 屏幕上是一个看不见的码，而 idx 也已经被记进窗口 —— 用户只知道「没开门」。
        // 这道 guard 必须排在 saveOtpIdx 之前：失败的这一次不许占用窗口内的 100 个名额。
        guard !pwd.isEmpty else {
            app.showToast("这把锁的 MAC 不是整 6 字节十六进制, 已中止生成 (临时码要用它反序拼料)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        DB.saveOtpIdx(mac, OtpIdx(idx: idx, invalidTime: win))
        otpPwd = pwd
        otpReveal = true   // 刚生成的码必须立刻可见（防窥挡片开着也不挡这一次）
        otpWin = win
        Clip.set(pwd)   // 405
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }

    var emptyHint: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("本机还没有凭证台账。用「添加密码」或「录入指纹」开始。")
                    .vkFont(.footnote)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                // 包14/815 空态双按钮: 主"添加密码" + 次"看看它如何工作"
                HStack(spacing: DS.Space.s) {
                    NavigationLink { PwdStudio(embedded: true) } label: {
                        Text("添加第一条密码")
                            .vkFont(.subheadline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionStyle(fullWidth: false))
                }
                .padding(.top, DS.Space.xs)
                // 2026-10-29 补（**后台有动作、前台无入口**）：`genFirstOtp()` 全仓零调用，
                // 它上方还孤悬一个 `@ViewBuilder`（说明这块视图被删过、只剩动作函数）。
                // 空台账时用户只被引导「添加密码或录入指纹」—— 而 APK `page-otpgenerate` 是独立入口，
                // 这里补一个等价入口：需锁在场，走现有 genOtp 通路（与 otpSection 的「生成」同一个）。
                Button {
                    genFirstOtp()
                } label: {
                    Text(isBusy ? "生成中…" : "发第一张临时码")
                        .vkFont(.subheadline, weight: .semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionStyle(fullWidth: false))
                .disabled(isBusy)
                .padding(.top, DS.Space.xs)
            }
            .padding(.vertical, 2)
        }
    }

    /// 821 临时码零库存: 已开通但一张没发 → "酒店前台发门卡"比喻 + 首张按钮。
    /// 这一块原先嵌在"整册空"的 emptyHint 里 ⇒ 台账里有密码但没发过临时码时它永远不出现;
    /// 提出来挂列表固定位 (listBody), 空台账时也只由这一块渲染一次。
    /// 821 空台账场景"发第一张临时码": 走现有 genOtp 通路, 需锁在场。
    /// busyKey 只占"连接中"这一段 —— genOtp 自带 busyKey==nil 门槛, 不先还回去第一张永远不生成
    /// (原先连完直接调 genOtp, 被自己的占用挡下, 回执却报成功)。
    func genFirstOtp() {
        guard busyKey == nil else { return }
        busyKey = "otp"
        Task {
            defer { busyKey = nil }
            do {
                try await app.lock.ensureConnected(mac: mac)
                busyKey = nil   // 还回连接占用再生成; genOtp 同步完成, 生成段无需再占
                if genOtp() {
                    app.showToast("第一张临时码已生成, 可让客人直接在锁键盘输入")
                }
            } catch { app.showToast("需在场连接锁端: \(error.localizedDescription)") }
        }
    }

    /// 354 归档区: 归档 = 收起不删 — 与停用 (锁端待处理) / 彻底删除 (670) 是三个不同档, 这里只碰展示层。
    /// 单条与全部两种还原都在这里; 搜索路径里归档条目仍可见, 它的还原入口在条目长按菜单的「移出归档」。

    // ---------- 506 误删撤销条: 删除后底部浮出 5 秒 "已删除 · 撤销", 撤销则原位还原不入回收站 ----------
    // 833: 第一次浮出时多附一句防误删说明 (HintOnce 之后不再出现)。
    // 第一百五十二批把这片的措辞改成**跟着真实路径走**：撤销要收回的东西不止回收站那一格 ——
    // 停用那条路还排着一条"待下发的锁端删除"并写着 361 停用便签；彻底删除那条路锁端已经真删了，
    // 本机恢复≠锁上还有。所以话术由 `CredentialOrg.undoRemove` 一份生成，界面不再各写一遍。
    // 2026-10-26 精简：stopUndoTimer 已删（undoBar 移除后无撤销条可停）。

    // ---------- 动作 ----------
    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    func shortDate(_ ts: Double) -> String {
        Self.shortDateFormatter.string(from: Date(timeIntervalSince1970: ts / 1000))
    }

    func viewPwd(_ p: LedgerPwd) {
        guard let pwd = p.pwd else { app.showToast("当时未留存明文"); return }
        // 2026-10-27 审核修复 (AUDIT-D D-39)：**明文密码不再进 Toast**。
        // Toast 的问题：可截图、录屏、旁人一眼看到、且不随页面关闭而消失（有停留时间）、
        // 还会进无障碍朗读。而 `viewPwd` 是「看一眼明文」这个动作 —— 看完就该没了。
        // 改成系统 alert：用户点「知道了」即消失，不留在屏幕上。
        let alert = UIAlertController(title: "密码 #\(p.alias)",
                                      message: pwd + "\n\n请勿外传；关闭后不再显示。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    func modifyPwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        let alert = UIAlertController(title: "修改密码 (#\(p.alias))", message: "修改后旧密码立即作废, 需使用新密码开锁。", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "新密码 6~8 位数字"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        // 旧密码即刻作废 = 破坏性, 按钮必须显式标红, 不能伪装成普通确认
        alert.addAction(UIAlertAction(title: "作废旧密码", style: .destructive) { _ in
            let np = alert.textFields?.first?.text ?? ""
            guard np.count >= 6, np.count <= 8, np.allSatisfy({ $0.isNumber }) else { app.showToast("需 6~8 位数字"); return }
            // 在用户按下"作废旧密码"的那一刻就把目标锁钉住 (含非空校验)，Task 里一律用 m
            let m = mac
            guard !m.isEmpty else { app.showToast("未选择门锁"); return }
            busyKey = "pwd:\(p.alias)"
            Task {
                defer { busyKey = nil }
                do {
                    try await app.lock.ensureConnected(mac: m)
                    let aliasOut = try await app.lock.pwdModify(alias: p.alias, pwd: np, validFrom: p.from, validTo: p.to)
                    DB.rePwd(m, p.alias, np)
                    if aliasOut != p.alias {
                        DB.addPwd(m, LedgerPwd(alias: aliasOut, from: p.from, to: p.to, temp: p.temp, at: Date().timeIntervalSince1970 * 1000, pwd: np, owner: p.owner, note: p.note))
                        // 确认口径：换槽 (上面按钮的破坏性项「作废旧密码」已经问过并要 6~8 位新码)，
                        //   锁端返回新槽号后旧槽已不存在，addPwd 紧跟着把台账补到新槽 ⇒ 无删除后果可预告。
                        DB.delPwd(m, p.alias)
                    }
                    // 487 保存自动快照: 改值即留一档 (值/时段/备注)
                    let finalAlias = aliasOut == p.alias ? p.alias : aliasOut
                    showToastOrganized("已修改, 旧密码已作废")
                } catch { app.showToast("修改失败: \(error.localizedDescription)") }
            }
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    func resetPwdPeriod(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        // 重发 0B 会覆盖锁内有效期, 与「删除」同级别, 先知会再执行
        confirmDestructive("修改有效期", "将按原有效期重新下发到门锁 (\(periodText(p)))。确定继续吗？", confirmTitle: "重新下发") {
            Task { await self.doResetPwdPeriod(p) }
        }
    }
    func doResetPwdPeriod(_ p: LedgerPwd) async {
        guard busyKey == nil else { return }
        // 第八十七批: 入口一次性钉住目标锁。原先 `mac` (活读 app.current) 在这条链上被读 3 次 ——
        // 两次 await 之间当前锁若被 AppIntent / kf:// 深链改掉，命令发向 A 锁而台账写进 B 锁；
        // 而 current 变 nil 时 `?? ""` 会静默写出一条"没有锁"的台账。同口径见 doDeletePwd/doDeleteFp/
        // modifyPwd/OTP 开关/SettingsView.doClearPwd 与 CredentialStudio.FpStudio.saveAndClose。
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "pwd:\(p.alias)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.pwdExpire(p.alias, p.from, p.to)
            DB.setPwdPeriod(m, p.alias, p.from, p.to)
            app.showToast("已更新有效期")
        } catch { app.showToast("更新失败: \(error.localizedDescription)") }
    }

    func periodText(_ p: LedgerPwd) -> String {
        if p.to.hasPrefix("2118") { return "长期有效" }
        return "到 \(p.to.prefix(16).replacingOccurrences(of: "T", with: " ")) 失效"
    }

    /// 468 代管: 这条凭证的属主在成员档案上被标了「由我代管」时, 361 的停用便签补一句 管理员代操作。
    /// 判据读 MemberHub.proxyNames (与成员页同一张 kf_member_ext), 只在归属可证明时补, 无归属不猜。
    /// 便签的回显点在回收站那一行 (CredentialCenterView 的 disableMarkText), 所以这句标注是给人看得见的。
    func disableVia(owner: String?) -> String {
        guard let o = owner, !o.isEmpty, MemberHub.proxyNames.contains(o) else { return "本机单条停用" }
        return "本机单条停用 · 管理员代操作"   // 468 本机单条停用
    }

    /// 364/180/360 停用: 本地移除 + 回收站 (7 天恢复窗口), 锁端删除入队 (本地意图, UI 明示)
    func disablePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("停用密码 #\(p.alias)",
                          // 天数口径：这个 7 天是 **364 的一键恢复窗口**，出处 `CredentialOrg.withinRecoverWindow`
                          //   里写死的 `7 * 86400`，与 497 那个 7~90 天可调的回收站保留期不是同一件事 (所以不读 reclaimDays)。
                          "停用只移除本机台账（没有回收站，不可恢复）；锁端凭证仍然有效，必须到门锁键盘上手动删除才会真正失效。",
                          confirmTitle: "停用") {
            DB.delPwd(mac, p.alias)
            // 361: 单条停用没有 313 的四选一, 便签如实记"未填", 不编一个原因充数 (要不要补必填见 NEXT-DECISIONS 组5)
            CredentialOrg.markDisabled(mac, kind: "pwd", keys: [p.alias], label: "未填", via: disableVia(owner: p.owner))
            showToastOrganized("已停用, 7 天内可恢复")   // 364 已停用
        }
    }
    func disableFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("停用指纹「\(f.name)」",
                          // 天数口径：同停用密码那一支 —— 7 天是 364 一键恢复窗口 (`withinRecoverWindow` 写死)，
                          //   不是 497 那个可调的回收站保留期。
                          "停用只移除本机台账（没有回收站，不可恢复）；锁端指纹仍然有效，必须到门锁上手动删除才会真正失效。",
                          confirmTitle: "停用") {
            DB.delFp(mac, f.batch)
            CredentialOrg.markDisabled(mac, kind: "fp", keys: [f.batch], label: "未填", via: disableVia(owner: f.owner))   // 361 同上, 如实记未填; 468 代管时补标注
            showToastOrganized("已停用, 7 天内可恢复")   // 364 已停用
        }
    }

    /// 彻底删除: 锁端删除 + 本地删前快照 (494 双通道), 670 后果文案具体化
    func deletePwd(_ p: LedgerPwd) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除密码 #\(p.alias)",
                           // 「30 天」原先写死：回收站保留期是设置页那枚 7~90 天的 Stepper (497)，
                           // 用户调过之后这句就把安全网说大了 —— 而它恰恰出现在按下去就不可逆的那一刻。
                           "删除后该密码在锁内立即失效, 本机台账移除 (本机记录直接移除不可找回, 密码值需重新生成下发才有效)。确定继续？",
                           confirmTitle: "彻底删除") {
            Task { await self.doDeletePwd(p) }
        }
    }
    func doDeletePwd(_ p: LedgerPwd) async {
        guard busyKey == nil else { return }
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "pwd:\(p.alias)"
        defer { busyKey = nil }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.pwdDelete(p.alias)
            // 确认口径：彻底删除 (670) —— 确认入口在外层的 `deletePwd` (confirmDestructive，±4 行窗口看不到那么远)，
            //   那一问的正文写的就是这一行做的事；锁端 pwdDelete 已直发，台账与回收站同一条 p，
            //   回收站 reclaimDays 天 (497) + 504 还原排重新下发 + 506 撤销条。
            DB.delPwd(m, p.alias)
            showToastOrganized("已彻底删除")
        } catch { app.showToast("删除失败: \(error.localizedDescription)") }
    }

    func deleteFp(_ f: LedgerFp) {
        guard busyKey == nil else { return }
        confirmDestructive("彻底删除指纹「\(f.name)」",
                           "删除后果: 该指纹在锁内立即失效且无法远程补录 — 需成员本人到锁前重新录入 8 次指压。本机记录直接移除、不可找回。确定继续？",
                           confirmTitle: "彻底删除") {
            Task { await self.doDeleteFp(f) }
        }
    }
    func doDeleteFp(_ f: LedgerFp) async {
        guard busyKey == nil else { return }
        let m = mac
        guard !m.isEmpty else { app.showToast("未选择门锁"); return }
        busyKey = "fp:\(f.batch)"
        defer { busyKey = nil }
        // 2026-10-13 对抗式排查: UInt32(越界 Int) 是 trap ⇒ 先安全转换
        guard let b = f.batchU32 else {
            app.showToast("指纹「\(f.name)」批次号越界 (\(f.batch))，已中止 — 台账或备份来源可能损坏")
            return
        }
        do {
            try await app.lock.ensureConnected(mac: m)
            try await app.lock.fpDelete(b)
            // 确认口径：同上面密码那一支 —— 确认在外层 `deleteFp`，只是指纹侧的后果写得更硬
            //   (无法远程补录，本人重录 8 次指压)；回收站那条回来的仍是档案，开门能力要重录 (670)。
            DB.delFp(m, f.batch)
            showToastOrganized("已彻底删除")
        } catch { app.showToast("删除失败: \(error.localizedDescription)") }
    }

    func renameFp(_ f: LedgerFp) {
        let alert = UIAlertController(title: "重命名指纹", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "如: 主人大拇指"; $0.text = f.name }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            let name = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            var np = f
            np.name = name
            DB.renameFp(mac, f.batch, name)
            refreshTick += 1
        })
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    func editNote(pwd: LedgerPwd? = nil, fp: LedgerFp? = nil) {
        let alert = UIAlertController(title: "凭证备注", message: "仅本机留存, 随全量备份换机", preferredStyle: .alert)
        alert.addTextField { $0.text = pwd?.note ?? fp?.note ?? "" }
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            if let p = pwd {
                var np = p; np.note = ""
                DB.setPwdNote(mac, p.alias, "")
            }
            if let f = fp {
                var nf = f; nf.note = ""
                DB.setFpNote(mac, f.batch, "")
            }
            _ = Milestones.recordOrganize()
            refreshTick += 1
        })
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let note = (alert.textFields?.first?.text ?? "")
            if let p = pwd {
                var np = p; np.note = note
                DB.setPwdNote(mac, p.alias, note)
            }
            if let f = fp {
                var nf = f; nf.note = note
                DB.setFpNote(mac, f.batch, note)
            }
            _ = Milestones.recordOrganize()
            refreshTick += 1
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 1007 维护致谢: 整理动作计数, 每 10 次附一句致谢
    /// 1007 整理动作计数 (致谢文案已随徽章引擎删除, 这里只记数 + 刷新)
    func showToastOrganized(_ base: String) {
        Milestones.recordOrganize()
        app.showToast(base)
        refreshTick += 1
    }
    @ViewBuilder
    func ownerMenu(isPwd: Bool, key: Int) -> some View {
        ForEach(DB.members()) { m in
            Button(m.name) {
                if isPwd { DB.setPwdOwner(mac, key, m.id) } else { DB.setFpOwner(mac, key, m.id) }
                _ = Milestones.recordOrganize()
                refreshTick += 1
            }
        }
        Button("解除归属", role: .destructive) {
            if isPwd { DB.setPwdOwner(mac, key, nil) } else { DB.setFpOwner(mac, key, nil) }
            refreshTick += 1
        }
    }

    /// 359/930 到期预警五档: 7 / 3 / 1 天 + 24 / 2 小时**全部排本地通知** (930 替代落地后
    /// 2 小时档不再只是列表提醒行), 另有一条"到期时"通知自动跟着走, 不单设开关。
    func toggleAlerts(_ p: LedgerPwd) {
        let a = CredentialOrg.alert(mac, p)
        let sheet = UIAlertController(title: "到期预警 #\(p.alias)",   // 359/930 到期预警
                                     message: "长期有效密码无到期点, 不适用。",
                                     preferredStyle: .actionSheet)
        func addTier(_ title: String, current: Bool, toggle: @escaping () -> Void) {
            sheet.addAction(UIAlertAction(title: (current ? "○ " : "◉ ") + title, style: .default, handler: { _ in toggle() }))
        }
        addTier("到期前 7 天提醒", current: a.day) {
            var n = a; n.day.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.day ? "已开 7 天档" : "已关 7 天档")
        }
        addTier("到期前 3 天提醒", current: a.d3) {
            var n = a; n.d3.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.d3 ? "已开 3 天档" : "已关 3 天档")
        }
        addTier("到期前 1 天提醒", current: a.d1) {
            var n = a; n.d1.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.d1 ? "已开 1 天档" : "已关 1 天档")
        }
        addTier("到期前 24 小时提醒", current: a.h24) {
            var n = a; n.h24.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)
            app.showToast(n.h24 ? "已开 24 小时档" : "已关 24 小时档")
        }
        addTier("到期前 2 小时提醒", current: a.h2) {
            var n = a; n.h2.toggle()
            CredentialOrg.saveAlert(mac, p, n)
            CredentialOrg.scheduleAlerts(mac, p, n)   // 930: 2 小时档现在也排通知 (列表提醒行照旧)
            app.showToast(n.h2 ? "已开 2 小时档" : "已关 2 小时档")
        }
        if p.to.hasPrefix("2118") {
            let off = UIAlertAction(title: "了解", style: .cancel)
            sheet.addAction(off)
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        UIApplication.topViewController()?.present(sheet, animated: true)
    }
}
