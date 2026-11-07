// CredentialCreateScreen.swift —— 新凭证。
//
// 一次只问一件事：类型 → 值 → 期限 → 归属。指纹是另一条链（真的是在锁上按 8 次）。
import SwiftUI

@MainActor
struct CredentialCreateScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    enum Kind: Int, CaseIterable {
        case password, temp, fingerprint

        /// 跨页传递用的稳定名字（`Router.pendingCreateKind`）。
        var rawName: String {
            switch self {
            case .password: return "password"
            case .temp: return "temp"
            case .fingerprint: return "fingerprint"
            }
        }
    }

    @State private var kind: Kind = .password
    @State private var name = ""
    @State private var value = ""
    @State private var ownerID: String?
    @State private var duration = 1
    @State private var busy = false
    @State private var errorLine: String?
    @State private var presses = 0
    @State private var enrollHint = ""
    /// F43：部分成功（新码写进去了、旧码没删掉）—— 单独呈现，不混进「成功」。
    @State private var partialResult: ScreenFailure?

    private let durations: [(title: String, hours: Double)] = [
        ("1 小时", 1), ("1 天", 24), ("7 天", 168), ("30 天", 720),
    ]

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行 / 新凭证", back: { dismiss() })

            DisplayLine(text: headline, size: 34)
                .padding(.top, 16)
            Text("凭证会写进这把锁；本机台账也留一份，用来显示、提醒和加密备份。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .padding(.top, 8)

            SegmentedBar(items: ["密码", "临时码", "指纹"], selected: Binding(
                get: { kind.rawValue },
                set: { kind = Kind(rawValue: $0) ?? .password }
            ))
            .padding(.top, 20)

            SectionHead(index: "01", title: "它叫什么")
            FieldInput(placeholder: kind == .fingerprint ? "例如：妈妈的右手拇指" : "例如：前门密码", text: $name)
                .onChange(of: name) { _, newValue in
                    if newValue.count > 24 { name = String(newValue.prefix(24)) }
                }

            SectionHead(index: "02", title: kind == .fingerprint ? "在锁上录入" : "值")
            if kind == .fingerprint {
                fingerprintBlock
            } else {
                valueBlock
            }

            if kind == .temp {
                SectionHead(index: "03", title: "有效多久")
                durationPicker
            }

            SectionHead(index: kind == .temp ? "04" : "03", title: "归谁")
            ownerPicker

            if let partialResult {
                PartialSuccessCard(title: "新凭证已经写进门锁了", failure: partialResult)
                    .padding(.top, 14)
                PrimaryButton(title: "知道了") { dismiss() }
                    .padding(.top, 14)
            }
            if let errorLine {
                    NoticeLine(text: errorLine)
            }

            PrimaryButton(title: submitTitle, busy: busy) {
                Task { await submit() }
            }
            .padding(.top, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: kind) { oldValue, newValue in
            errorLine = nil
            guard oldValue != newValue else { return }
            // 换类型就换一串**新**码。
            //
            // 原先只在「值是空的」时候补一枚 —— 而 `.onAppear` 已经把密码预填满了，
            // 于是「临时码」会原样沿用你刚设的永久密码：两把钥匙同一个数字，
            // 「限时」就完全没有意义了（临时码和密码在键盘上打出来一模一样）。
            if newValue == .fingerprint {
                value = ""
            } else {
                value = PinGenerator.generate(length: 6)
            }
        }
        .onAppear {
            // 从别处跳进来时可能指定了类型（例如指纹详情的「重新录入」）。
            if let raw = router.pendingCreateKind {
                kind = Kind.allCases.first { $0.rawName == raw } ?? kind
                router.pendingCreateKind = nil
            }
            // 从成员详情「新建一枚归给 TA 的凭证」进来时，归属要预选好；
            // 否则用户建完还得自己再找一次这位成员，而本版没有改归属的界面。
            if let owner = router.pendingCreateOwnerID {
                ownerID = owner
                router.pendingCreateOwnerID = nil
            }
            if value.isEmpty, kind == .password {
                value = PinGenerator.generate(length: 6)
            }
        }
    }

    private var headline: String {
        switch kind {
        case .password: return "给门\n加一把钥匙。"
        case .temp: return "让 TA\n只进这一次。"
        case .fingerprint: return "把指纹\n留在锁上。"
        }
    }

    private var submitTitle: String {
        switch kind {
        case .password: return "写入密码"
        case .temp: return "生成临时码"
        case .fingerprint: return presses > 0 ? "继续录入（\(presses)/8）" : "开始录入"
        }
    }

    // MARK: - 值

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FieldInput(placeholder: kind == .password ? "6–8 位数字" : "6 位数字",
                           text: $value,
                           keyboard: .numberPad)
                .onChange(of: value) { _, newValue in
                    let digits = newValue.filter { $0.isASCII && $0.isNumber }
                    let capped = String(digits.prefix(kind == .temp ? 6 : 8))
                    if capped != newValue { value = capped }
                }
                Button {
                    value = PinGenerator.generate(length: 6)
                } label: {
                    Image(systemName: "dice")
                        .font(.system(size: 17))
                        .foregroundStyle(T.C.brass)
                        .frame(width: 48, height: 48)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.controlRadius, style: .continuous),
                                     tint: GlassMetrics.tint, interactive: true)
                        // 48pt 的玻璃里只有 17pt 的图标；不补命中区，边缘一圈点不动。
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("随机生成")
            }

            if kind == .password {
                Text(passwordHint)
                    .type(T.F.caption)
                    .foregroundStyle(value.count < 6 || value.count > 8 ? T.C.danger : T.C.ink3)
            } else {
                Text("门锁键盘可以直接输入，不需要联网。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
            // F19：弱模式提醒。123456 这种码「随机」出来也等于没随机 ——
            // 门锁键盘只有数字，密码空间小，人更会挑好记的。
            if value.count >= 4, let weak = PinGenerator.hint(value) {
                Text("这串码\(weak) · 要换一个吗")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 2)
            }
        }
    }

    /// 门锁的键盘只有数字：密码与临时码都必须是数字串。
    /// 位数下限 6、上限 8 —— 与上一版真机验证过的口径一致；
    /// 锁端自己声明的上限（`pwdInfoMaxLen`）由 Engine 在下发前再拦一道。
    private var passwordHint: String {
        if value.count < 6 { return "至少 6 位数字。" }
        if value.count > 8 { return "这把锁最多接受 8 位。" }
        if Self.weak(value) { return "这串太顺了（重复或连号），换一个更稳。" }
        return "\(value.count) / 8 位 · 只在写入时下发一次"
    }

    // MARK: - 指纹

    private var fingerprintBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(T.C.hair, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: Double(presses) / 8.0)
                        .stroke(T.C.brass, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "touchid")
                        .font(.system(size: 26))
                        .foregroundStyle(T.C.brass)
                }
                .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presses == 0 ? "准备好了再开始" : "已记录 \(presses) / 8 次")
                        .type(T.F.body)
                        .fontWeight(.medium)
                        .foregroundStyle(T.C.ink)
                    Text(enrollHint.isEmpty ? "开始后，按提示在门锁上连续按 8 次同一个手指。" : enrollHint)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 期限

    private var durationPicker: some View {
        HStack(spacing: 8) {
            ForEach(durations.indices, id: \.self) { index in
                ChoiceChip(title: durations[index].title,
                           on: duration == index,
                           fillWidth: true) {
                    duration = index
                }
            }
        }
    }

    // MARK: - 归属

    private var ownerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChoiceChip(title: "未归属", on: ownerID == nil) {
                    ownerID = nil
                }

                ForEach(app.members.filter { !$0.archived }) { member in
                    ChoiceChip(title: member.name, on: ownerID == member.id) {
                        ownerID = member.id
                    }
                }
            }
        }
    }

    // MARK: - 提交

    private func submit() async {
        // 连点两次「写入密码」会下发两条 0A：锁里多出一条，台账只记一条。
        guard !busy else { return }
        errorLine = nil
        switch kind {
        case .password:
            guard Self.isNumeric(value), (6 ... 8).contains(value.count) else {
                errorLine = "密码是 6–8 位数字。"
                return
            }
            busy = true
            defer { busy = false }
            let now = Date()
            let to = TimeFormat.calendar.date(byAdding: .year, value: 100, to: now) ?? now
            let result = await app.addPassword(value,
                                               from: AppModel.stamp(now),
                                               to: AppModel.stamp(to),
                                               owner: ownerID,
                                               note: name.isEmpty ? nil : name)
            switch result {
            case .success:
                // 部分成功时**不直接关页**：旧码还在锁里，用户得知道。
                if let partial = app.lastPartial { partialResult = partial } else { dismiss() }
            case .failure(let error): errorLine = error.localizedDescription
            }
        case .temp:
            guard Self.isNumeric(value), value.count == 6 else {
                errorLine = "临时码是 6 位数字。"
                return
            }
            busy = true
            defer { busy = false }
            let now = Date()
            let to = now.addingTimeInterval(durations[duration].hours * 3600)
            let result = await app.addTempCode(value,
                                               from: AppModel.stamp(now),
                                               to: AppModel.stamp(to),
                                               owner: ownerID,
                                               note: name.isEmpty ? "临时码" : name)
            switch result {
            case .success:
                if let partial = app.lastPartial { partialResult = partial } else { dismiss() }
            case .failure(let error): errorLine = error.localizedDescription
            }
        case .fingerprint:
            await enroll()
        }
    }

    private func enroll() async {
        busy = true
        defer { busy = false }
        let result = await app.enrollFingerprint(name: name, owner: ownerID, note: "") { n in
            presses = n
            enrollHint = n >= 8 ? "收齐了，正在确认…" : "很好，再按一次"
        }
        switch result {
        case .success: dismiss()
        case .failure(let error):
            errorLine = error.localizedDescription
            presses = 0
            enrollHint = ""
        }
    }

    // MARK: - 小工具

    /// 半角数字串才算数（iOS 的 `isNumber` 把全角数字也算数字，而锁的键盘打不出全角）。
    static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// 「太顺」的判断只看数字串：全同位、或连号（1234 / 4321）。
    static func weak(_ value: String) -> Bool {
        let digits = value.compactMap { $0.wholeNumberValue }
        if digits.count != value.count { return true }
        if Set(value).count == 1 { return true }
        if digits.count > 2 {
            let steps = zip(digits, digits.dropFirst()).map { $1 - $0 }
            if steps.allSatisfy({ $0 == 1 }) || steps.allSatisfy({ $0 == -1 }) { return true }
        }
        return false
    }
}
