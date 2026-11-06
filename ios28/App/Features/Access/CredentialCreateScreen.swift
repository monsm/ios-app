// CredentialCreateScreen.swift —— 新凭证。
//
// 一次只问一件事：类型 → 值 → 期限 → 归属。指纹是另一条链（真的是在锁上按 8 次）。
import SwiftUI

@MainActor
struct CredentialCreateScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Kind: Int, CaseIterable { case password, temp, fingerprint }

    @State private var kind: Kind = .password
    @State private var name = ""
    @State private var value = ""
    @State private var ownerID: String?
    @State private var duration = 1
    @State private var busy = false
    @State private var errorLine: String?
    @State private var presses = 0
    @State private var enrollHint = ""

    private let durations: [(title: String, hours: Double)] = [
        ("1 小时", 1), ("1 天", 24), ("7 天", 168), ("30 天", 720),
    ]

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "通行 / 新凭证", back: { dismiss() })

            DisplayLine(text: headline, size: 34)
                .padding(.top, 16)
            Text("凭证只存在这把锁里，不会上传。")
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

            if let errorLine {
                Text(errorLine)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.danger)
                    .padding(.top, 14)
            }

            PrimaryButton(title: submitTitle, busy: busy) {
                Task { await submit() }
            }
            .padding(.top, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: kind) { _, newValue in
            errorLine = nil
            if newValue == .temp, value.isEmpty { value = String(format: "%06d", Int.random(in: 0 ... 999_999)) }
        }
        .onAppear {
            if value.isEmpty, kind == .password {
                value = Self.randomPassword()
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
                FieldInput(placeholder: kind == .password ? "最多 8 位" : "6 位数字",
                           text: $value,
                           keyboard: kind == .password ? .default : .numberPad)
                Button {
                    value = kind == .password ? Self.randomPassword() : String(format: "%06d", Int.random(in: 0 ... 999_999))
                } label: {
                    Image(systemName: "dice")
                        .font(.system(size: 17))
                        .foregroundStyle(T.C.brass)
                        .frame(width: 48, height: 48)
                        .background(T.C.glass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(T.C.glassEdge, lineWidth: 0.5)
                        }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("随机生成")
            }

            if kind == .password {
                Text(passwordHint)
                    .type(T.F.caption)
                    .foregroundStyle(value.count > 8 ? T.C.danger : T.C.ink3)
                    .onChange(of: value) { _, newValue in
                        if newValue.count > 8 { value = String(newValue.prefix(8)) }
                    }
            } else {
                Text("门锁键盘可以直接输入，不需要联网。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
        }
    }

    private var passwordHint: String {
        if value.count > 8 { return "门锁最多接受 8 位，超出的部分会被拒绝。" }
        if value.count < 4 { return "至少 4 位。数字越散越好记也越难猜。" }
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
                Button {
                    duration = index
                } label: {
                    Text(durations[index].title)
                        .type(T.F.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(duration == index ? .white : T.C.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            duration == index ? T.C.brass : T.C.glass,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(duration == index ? .clear : T.C.glassEdge, lineWidth: 0.5)
                        }
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: - 归属

    private var ownerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { ownerID = nil } label: {
                    Text("未归属")
                        .type(T.F.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(ownerID == nil ? .white : T.C.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(ownerID == nil ? T.C.brass : T.C.glass, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(ownerID == nil ? .clear : T.C.glassEdge, lineWidth: 0.5)
                        }
                }
                .buttonStyle(PressStyle())

                ForEach(app.members.filter { !$0.archived }) { member in
                    Button { ownerID = member.id } label: {
                        Text(member.name)
                            .type(T.F.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(ownerID == member.id ? .white : T.C.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(ownerID == member.id ? T.C.brass : T.C.glass, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(ownerID == member.id ? .clear : T.C.glassEdge, lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    // MARK: - 提交

    private func submit() async {
        errorLine = nil
        switch kind {
        case .password:
            guard value.count >= 4 else { errorLine = "密码至少 4 位。"; return }
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
            case .success: dismiss()
            case .failure(let error): errorLine = error.localizedDescription
            }
        case .temp:
            guard value.count == 6 else { errorLine = "临时码是 6 位数字。"; return }
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
            case .success: dismiss()
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

    static func randomPassword() -> String {
        let letters = Array("23456789abcdefghjkmnpqrstuvwxyz")
        return String((0 ..< 6).map { _ in letters.randomElement() ?? "a" })
    }

    static func weak(_ value: String) -> Bool {
        let digits = value.compactMap { $0.wholeNumberValue }
        if Set(value).count == 1 { return true }
        if digits.count == value.count, digits.count > 2 {
            let steps = zip(digits, digits.dropFirst()).map { $1 - $0 }
            if steps.allSatisfy({ $0 == 1 }) || steps.allSatisfy({ $0 == -1 }) { return true }
        }
        return false
    }
}
