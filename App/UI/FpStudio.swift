// 指纹工坊 + fpDoubleSignCheck（删除双签的全局入口）
// 2026-10-29 从 CredentialStudio.swift 拆出。fpDoubleSignCheck 被 FpDetailStudio 调用，非 private 所以跨文件可见
import SwiftUI
import UIKit
import AVFoundation

// ================= 323 删除双签: 删除成员最后一枚指纹需前缀验证任一在用密码 =================
// 这一枚是 UI 入口 (内部要弹 UIAlertController + 走 confirmDestructive), 所以整条下沉主 actor。
@MainActor
func fpDoubleSignCheck(mac: String, batch: Int, confirmTitle: String, action: @escaping @MainActor () -> Void) {
    // 档案已经不在这台锁的台账里 (并发删除/切锁) ⇒ 没有任何可删的东西。原先这里直接 action()，
    // 而调用方那条异步体重读一次 DB 就静默返回 —— 界面什么都不说，人以为删掉了。
    // 现在两支都不越过「先问一句」：无档案 = 不做，有档案 = 必确认。
    guard let f = DB.getFp(mac, batch) else { return }
    let need = CredentialOrg.fpCountByOwner(mac, f.owner) == 1
    guard need, let v = DB.listPwds(mac).first(where: { $0.pwd != nil && CredentialOrg.pwdState($0) == 0 })?.pwd else {
        // 真漏 (第一百六十七批 delsweep 二次确认对账撞出)：这一支原先直接 action()。
        // 同一个按钮，「最后一枚」那一支要输入在用密码前缀才肯删，「不止最后一枚」这一支却一按就把锁端
        // 指纹删掉、零确认 —— 双签的门槛按「是不是最后一枚」分叉，把「要不要问一句」这件事问漏了。
        // 现在两支都必问，只是深浅不同：非最后一枚走全仓那一个确认入口 (后果 + 出路)，最后一枚仍要前缀验证。
        // 最后一枚但本机翻不出任何在用密码时 (双签在形式上无法完成) 也落到这一支 —— 那恰恰是最贵的一种：
        // 无密码可核对 == 删完这人既没指纹也没密码，所以后果必须单独说一句。
        let lastWarn = need
            ? "这是该成员名下最后一枚可用指纹，且本机没有在用的密码可双签；删掉后此人两种凭证都没了，只能本人到锁前重录。"   // 324 这是该成员名下最后一
            : ""
        confirmDestructive("删除指纹「\(f.name)」",
                           lastWarn + "锁端这条立即作废，不可撤销；本机移除的是名称/备注/归属这条档案（不可找回），" +
                           "开门能力只能本人到锁前重录。",   // 670 开门能力只能本人到锁
                           confirmTitle: confirmTitle) { action() }
        return
    }
    // 2026-10-26: 原实现只比对前 max(v.count/2, 2) 位 —— 6 位密码只需输对 3 位就能删掉
    // 某人的最后一枚指纹。那不是"双签"，是"双签的样子"。改成全量比对。
    // 提示文案仍不显示密码本身，只说位数。
    let maskLen = v.count
    let alert = UIAlertController(
        title: "双签验证",   // 323 双签验证
        message: "这是「" + (CredentialOrg.ownerName(f.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(f.owner)) + "」名下最后一枚可用指纹。输入任一在用密码（完整 " + String(maskLen) + " 位）完成双签。",
        preferredStyle: .alert)
    alert.addTextField { tf in
        tf.placeholder = "完整密码（" + String(maskLen) + " 位）"
        tf.keyboardType = .numberPad
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in
        let input = alert.textFields?.first?.text ?? ""
        // 全量比对（常量时间无所谓：这是本机 UI，不在网络上）
        if input == v {
            Clip.set("")
            action()
        } else {
            let fail = UIAlertController(title: "双签未通过", message: "密码不符， 删除已取消。", preferredStyle: .alert)   // 323 密码不符
            fail.addAction(UIAlertAction(title: "好", style: .cancel))
            UIApplication.topViewController()?.present(fail, animated: true)
        }
    })
    UIApplication.topViewController()?.present(alert, animated: true)
}


// ================= 指纹工坊 (41 沉浸 / 315 命名建议 / 317 归属先行 / 322 缺失提醒 / 324 冗余横条 / 319 重录继承) =================
struct FpStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    // 515 分步: 0 归属 (317 必选) / 1 沉浸录入 (41) / 2 命名备注 (315/319) / 3 回执
    @State private var step = 0
    @State private var owner: String? = nil
    @State private var presses: [LockService.FpPress] = []
    // 第八十九批: 按钮起的长任务要有句柄 (Sheets 的 StartAddFpView 是同型形状的另一份)。
    // 旧写法是裸 `Task { await start() }`：关页后 fpStart 仍转满 30 秒，然后照样 fpConfirm + 记账 + 弹提示。
    @State private var enrollTask: Task<Void, Never>? = nil
    @State private var busy = false
    @State private var error = ""
    @State private var doneBatch: UInt32?
    // 第八十七批: 录入实际发生在**哪一把锁**上必须记下来。`mac` 是 `app.current?.mac ?? ""` 的计算属性，
    // 而本流程是 sheet，期间当前锁仍可能被外部改掉 (AppIntents / kf:// 深链都会动 app.current)，
    // 服务层的 keys() 也跟随全局当前锁 —— 所以正确做法不是"猜它还一样"，而是写库前验一次、不一致就不写。
    @State private var enrolledMac: String? = nil
    @State private var name = ""
    @State private var note = ""
    @State private var replaceOld = false    // 319 重录继承: 同成员旧指纹移回收站
    /// 319 重录入口: 详情页带原归属进来 (默认 nil=全新录入)
    var prefillOwner: String? = nil
    var prefillReplace = false
    /// 2026-10-28：与 PwdStudio 同口径 —— 嵌在 NavigationLink 里时不再自带 NavigationStack，
    /// 否则会出现「导航栏叠导航栏」。默认 false（sheet 里用）。
    var embedded: Bool = false

    private var mac: String { app.current?.mac ?? "" }
    private var sameOwnerFps: [LedgerFp] {
        owner == nil ? [] : DB.listFps(mac).filter { $0.owner == owner && $0.batch != Int(doneBatch ?? 0) }
    }
    // 317 返回带值: 成员页建完档把 id 存进 pendingFpOwner, 进工坊取走即预选归属
    private func consumePendingOwner() {
        guard let v = app.pendingFpOwner, v != "request" else { return }
        owner = v
        app.pendingFpOwner = nil
    }
    // 319 详情重录: 原归属预选 + 默认勾选替换旧枚
    private func consumePrefill() {
        if let po = prefillOwner, owner == nil { owner = po }
        if prefillReplace { replaceOld = true }
    }

    var body: some View {
        Group {
            if embedded {
                core
            } else {
                NavigationStack { core }
            }
        }
        .navigationTitle("录入指纹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
        // 317/319: 进场取走带回的预选值 (成员页建完档 / 详情页重录)
        .onAppear { consumePendingOwner(); consumePrefill() }
        // 挂在**页面最外层** (不是 immersive 上) —— 挂在步骤子视图上会在录入成功切到第 2 步时
        // 误取消刚跑完的流程; 这里只应在整页被关掉时触发。
        // 2026-10-28 补：APK 在指纹录入页调 `brightness.setKeepScreenOn(true/false)`
        // （main.js 共 4 处 onEnter/onLeave）。iOS 只有 DFUView 用了 keepingScreenAwake，
        // 指纹录入页没有 —— 而 `Mascot.swift:126` 的注释还写着「调用点: StartAddFpView (录入中)」，
        // 实际零调用。录指纹要按 8 次、每次间隔，中途自动锁屏会挂起进程并断开 BLE。
        .keepingScreenAwake(step == 1)   // 只在沉浸式录入那一步开常亮
        .onDisappear { enrollTask?.cancel() }
    }

    /// 2026-10-28：从 body 抽出的内容 —— embedded 与否共用同一份。
    @ViewBuilder
    private var core: some View {
        if step == 3 {
            doneCard
        } else if step == 1 {
            immersive
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    StepDots(total: 4, index: step, labels: ["归属", "录入", "命名", "回执"])
                    if step == 0 { step0 }
                    if step == 2 { step2 }
                    navBar
                }
                .padding(DS.Space.l)
            }
            .background(DS.Gradient.screen.ignoresSafeArea())
            .axBottomAnchor()   // 870
        }
    }

    // ---------- 324 冗余横条 + 322 缺失提醒 + 317 归属先行必选 ----------
    @ViewBuilder
    private var step0: some View {
        // 324 冗余横条: 该锁仅剩 1 枚可用指纹时提示补录
        if CredentialOrg.fpCountTotal(mac) == 1 {
            Label {
                Text("这把锁只剩 1 枚可用指纹， 建议补一枚备用")   // 324 这把锁只剩
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bell.badge")
            }
            .vkFont(.caption)
            .foregroundStyle(DS.Palette.warn)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, 4)
            .variantCallout(DS.Palette.warn, .control, wash: 0.10)
        }
        // 317 归属先行: 选择器自带"空态就地新建" —— 一个成员都没有时直接弹新增, 不再把人赶去成员中心。
        FpOwnerPicker(mac: mac, owner: $owner)
            .card()
    }

    // ---------- 41 沉浸式录入 (复用 Achievement 的 hero 渐变聚焦语言 + 大圆点) ----------
    private var immersive: some View {
        HeroCard {
            VStack(spacing: DS.Space.xl) {
                Text(progressText)
                    .vkFont(.headline)
                    .foregroundStyle(DS.heroFg)
                VStack(spacing: DS.Space.s) {
                    ProgressView(value: Double(min(presses.count, 8)), total: 8)
                        .tint(DS.heroFg)
                        .frame(maxWidth: 220)
                    HStack(spacing: DS.Space.s) {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(i < presses.count ? DS.heroFg.opacity(0.95) : DS.heroFg.opacity(0.22))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text("请选好的手指按在门锁指纹头上， 抬起， 重复 8 次")   // 41 请选好的手指按在门锁
                    .vkFont(.footnote)
                    .foregroundStyle(DS.heroFg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !error.isEmpty {
                    Label {
                        Text(error).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .vkFont(.caption)
                    .foregroundStyle(DS.heroFg)
                    .multilineTextAlignment(.center)
                }
                HStack(spacing: DS.Space.s) {
                    Button {
                        presses = []
                        error = ""
                    } label: {
                        Text("重置进度")
                            .vkFont(.footnote, weight: .medium)
                            .foregroundStyle(DS.heroFg)
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        enrollTask = Task { await start() }
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            if busy {
                                ProgressView().tint(DS.heroFg).controlSize(.small)
                            } else {
                                Image(systemName: "touchid")
                                    .font(.system(size: DS.Icon.sm, weight: .semibold))
                                    .foregroundStyle(DS.heroFg)
                            }
                            Text(busy ? "录入中…" : "开始录入")
                        }
                        .vkFont(.headline)
                        .foregroundStyle(DS.heroFg)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.s + 2)
                        .background(DS.heroPlate, in: Capsule())
                        .frame(minHeight: DS.Hit.min)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
        }
        .padding(.top, DS.Space.l)
        .animation(DS.Motion.standard, value: presses.count)
    }
    private var progressText: String {
        // 与 StartAddFpView 同一套提示节奏 (APK 第 4 下起要求换到手指边缘):
        // 同一处连按会被锁判 rc=23「无法获取有效的指纹图片」而不计数 —— 换位置是能不能收满 8 次的关键。
        switch presses.count {
        case 0: return "准备就绪"
        case 1...3: return "重复此步骤 (\(presses.count)/8) — 抬起后再按"
        case 4...6: return "第 \(presses.count + 1)/8 次： 把手指的边缘按上去， 换一个位置"
        default: return "第 \(presses.count + 1)/8 次： 再换一个角度"
        }
    }

    // ---------- 315/174 命名建议轮播 + 319 重录继承 ----------
    @ViewBuilder
    private var step2: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("命名 (点按建议填入)")
                .vkFont(.footnote, weight: .semibold)
                .foregroundStyle(DS.Palette.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(suggestionPool, id: \.self) { sug in
                        Button {
                            name = sug
                            DS.Haptics.tick.impactOccurred()
                        } label: {
                            Text(sug)
                                .vkFont(.caption, weight: .medium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(name == sug ? DS.Palette.onAccent : DS.Palette.accentText)
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, 4)
                                .background(name == sug ? DS.Palette.accent : DS.Palette.accentText.opacity(0.10), in: Capsule())
                                .frame(minHeight: DS.Hit.min)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("建议名 \(sug)")
                        .accessibilityAddTraits(name == sug ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, DS.Space.xs)
            }
            TextField("自定义名称", text: $name, prompt: Text("如： 妈妈·左手食指"))
                .vkFont(.subheadline)
                .frame(minHeight: DS.Hit.min)
                .autocorrectionDisabled()
            TextField("备注", text: $note, prompt: Text("仅本机留存"))   // 179 备注
                .vkFont(.subheadline)
                .frame(minHeight: DS.Hit.min)
            // 319 重录继承: 同成员已有指纹 → 成功后旧指纹入回收站 (保留原备注/归属, 来源"重录替代")
            if !sameOwnerFps.isEmpty {
                VariantToggle("该成员已有 \(sameOwnerFps.count) 枚指纹， 录入成功后旧指纹将从本机台账移除（⚠ 本机没有回收站，不可恢复；备注/归属也不会保留）", isOn: $replaceOld)
                    .vkFont(.caption)
                    .foregroundStyle(DS.Palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
    private var suggestionPool: [String] {
        var out: [String] = []
        for extra in 0..<3 {
            let s = CredentialOrg.fpNameSuggestion(mac, owner: owner, extra: extra)
            if !out.contains(s) { out.append(s) }
        }
        return out
    }

    private var doneCard: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DS.Icon.xl))
                .foregroundStyle(DS.Palette.ok)
                .accessibilityHidden(true)
            Text("已登记为「\(name.isEmpty ? fallbackName : name)」")
                .vkFont(.headline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("请用新指纹开一次锁， 确认可用。" + (replaceOld ? " 旧指纹已从本机台账移除。" : ""))
                .vkFont(.footnote)
                .foregroundStyle(DS.Palette.textSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("完成") { dismiss() }
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            Spacer(minLength: 0)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity)
        .background(DS.Gradient.screen.ignoresSafeArea())
    }
    private var fallbackName: String { "指纹" + String(doneBatch ?? 0) }

    private var navBar: some View {
        HStack(spacing: DS.Space.s) {
            if step > 0 {
                Button("上一步") {
                    withAnimation(DS.Motion.quick) { step -= 1 }
                }
                .vkFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Palette.textSub)
                .frame(minHeight: DS.Hit.min)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            if step == 0 {
                Button("下一步： 录入") {
                    guard owner != nil || DB.members().isEmpty else {
                        app.showToast("先选归属成员")   // 317 先选归属成员
                        DS.Haptics.trigger.impactOccurred()
                        return
                    }
                    withAnimation(DS.Motion.quick) { step = 1 }
                    DS.Haptics.tick.impactOccurred()
                }
                .vkFont(.subheadline, weight: .semibold)
                .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
            if step == 2 {
                Button("保存登记") { saveAndClose() }
                    .vkFont(.subheadline, weight: .semibold)
                    .buttonStyle(PrimaryActionStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func saveAndClose() {
        guard let b = doneBatch else { return }
        // fail-closed: 录入到保存之间当前锁变了 (或压根没记下是哪把锁)，就不写库 ——
        // 把 A 锁的批次号记进 B 锁台账，比"这次白录"糟得多；此处宁可让用户重开一页。
        guard let em = enrolledMac, em == app.current?.mac else {
            error = "当前锁已改变，本次录入不写入台账，请关闭后重新录入"
            return
        }
        let finalName = name.isEmpty ? CredentialOrg.fpNameSuggestion(em, owner: owner) : name
        // 来源口径：这一行写进台账的批次号来自上面同一流程的 fpStart/fpConfirm —— 锁端已经启用过这批指纹，
        // 只是隔了第 3 步的命名才落库 (lockpair 的窗口看不到那么远，故在此写明，不是漏发命令)。
        DB.addFp(em, LedgerFp(batch: Int(b), name: finalName, at: Date().timeIntervalSince1970 * 1000,
                              note: note, src: "app", owner: owner, isAlarm: false))
        if name.isEmpty {
            app.showToast("已按建议命名「\(finalName)」, 可重命名")   // 315/174 已按建议命名
        }
        // 319 重录继承: 同成员旧指纹入回收站 (来源"重录替代") + 锁端删除入队
        if replaceOld {
            // 先把待清旧的筛成局部量再遍历: 原写法把 filter 的尾随闭包贴在 for 语句后面,
            // 编译器都怀疑人要看错 (trailing closure in this context is confusable)
            let staleFps = DB.listFps(em).filter { $0.owner == owner && $0.batch != Int(b) }
            for f in staleFps {
                // 确认口径：这一刀是用户在上一步**自己勾上**的 (录入第 2 步那条 Toggle 的文案就把后果写全了：
                // 「录入成功后将旧指纹移入回收站 (319 重录继承, 保留原备注/归属)」) ⇒ 勾选即知情同意，
                // 再弹一次确认是把同一句话问两遍。可逆性也在那里兜住：addToBin 在前、锁端删除只是入队，
                // 还原时第一百五十二批的 reclaim 会把这条还没发出去的 del_fp 一并收回。
                DB.delFp(em, f.batch)
            }
            app.showToast("旧指纹已从本机台账移除 (备注/归属保留)")
        }
        withAnimation(DS.Motion.standard) { step = 3 }
    }

    private func start() async {
        guard let kc = app.current, !busy else { return }
        busy = true
        error = ""
        // 重试必须清空: onPress 是**累加**式回填，不清就会数出"9/8"这种读数 (旧写法整批赋值不会)
        presses = []
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            // 留存口径：录入这两步**故意不写台账** —— 批次要等第 3 步命名与归属填完才落 DB.addFp，
            // 中途关页 (上面 89 批那道 cancel 检查) 就该本机一条不留。lockpair 扫到这里时读这句。
            // onPress: 沉浸页那 8 个点随每帧亮起 (旧写法等整个调用返回才赋值，录入全程恒 0 个点)
            // 窗口口径在 LockService.fpStart 里 (首帧 8s / 两次按压 16s, 对齐 APK Java 接收计时器)
            let ps = try await app.lock.fpStart(times: 8,
                                                onPress: { p in
                                                    self.presses.append(p)
                                                    DS.Haptics.tick.impactOccurred()   // 手指在锁上, 屏幕看不见
                                                })
            self.presses = ps
            // 14 会把这一批指纹真正启用: 不满 8 次按压的批次不确认
            guard presses.count >= 8 else {
                throw NSError(domain: "fp", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "只收到 \(presses.count)/8 次按压， 未写入; 请重新录入并多按几次"])
            }
            guard let batch = ps.compactMap({ $0.batchNumber }).first, batch > 0 else {
                throw NSError(domain: "fp", code: 1, userInfo: [NSLocalizedDescriptionKey: "未拿到有效指纹批次， 请重新录入"])
            }
            // 第八十九批: 关页 (enrollTask?.cancel()) 后**不越过这个不可逆点** ——
            // fpConfirm 会真正启用这批指纹并写本机台账，不该在用户已经退出后代他做。
            if Task.isCancelled {
                presses = []
                return
            }
            try await app.lock.fpConfirm(batch, validFrom: "2010-01-01 00:00:00", validTo: "2118-01-01 00:00:00")
            // 留存口径：与上面 fpStart 同一句 —— 台账要到第 3 步命名与归属填完才写 DB.addFp，这里不提前落一条无名指纹
            doneBatch = batch
            enrolledMac = kc.mac
            // 命名建议数的是**这把锁**上已有的指纹数 (315/174)，读活读的 mac 会在中途切锁时
            // 给出另一把锁的编号 —— 第八十八批把 macpin 的豁免条件收窄后自己露出来的这一处
            name = CredentialOrg.fpNameSuggestion(kc.mac, owner: owner)
            note = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(DS.Motion.standard) { step = 2 }
        } catch {
            self.error = error.localizedDescription
        }
    }
}