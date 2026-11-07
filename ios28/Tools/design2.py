import io, sys


def apply(path, pairs):
    raw = io.open(path, 'rb').read()
    crlf = b'\r\n' in raw
    s = raw.decode('utf-8').replace('\r\n', '\n')
    for i, item in enumerate(pairs):
        old, new = item[0], item[1]
        want = item[2] if len(item) > 2 else 1
        n = s.count(old)
        if n != want:
            print('FAIL count=%d(want %d) pair#%d %s :: %r' % (n, want, i, path, old[:70]))
            sys.exit(1)
        s = s.replace(old, new)
    io.open(path, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode('utf-8'))
    print('ok', path, len(pairs), 'edits')


# ---------- 记录行 / 日头 ----------
apply('App/Features/Shared/EventRow.swift', [
 # 告警行：左侧一条 2pt 朱红竖条 + 点带光晕
 ('''    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.isAlarm ? T.C.danger : T.C.canvas)
                .overlay {
                    Circle().strokeBorder(dotColor, lineWidth: 1.5)
                }
                .frame(width: 9, height: 9)
                .padding(.top, 7)''',
  '''    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.isAlarm ? T.C.danger : T.C.canvas)
                .overlay {
                    Circle().strokeBorder(dotColor, lineWidth: 1.5)
                }
                // 开门的点带一圈极淡的黄铜光晕；告警带朱红光晕。
                .shadow(color: dotColor.opacity(event.isOpen || event.isAlarm ? 0.55 : 0), radius: 5)
                .frame(width: 9, height: 9)
                .padding(.top, 7)'''),
 ('''        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }''',
  '''        .padding(.vertical, 11)
        // 告警行：左边一条 2pt 朱红竖条 —— 一眼能在长列表里挑出来，不靠颜色也靠形状。
        .padding(.leading, event.isAlarm ? 10 : 0)
        .overlay(alignment: .leading) {
            if event.isAlarm {
                Capsule()
                    .fill(T.C.danger)
                    .frame(width: 2)
                    .padding(.vertical, 9)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }'''),
 # 日头：黄铜点 + 渐隐细线 + 当天条数
 ('''    var body: some View {
        HStack(spacing: 10) {
            Text((title ?? When.dayTitle(time)).uppercased())
                .type(T.F.kicker)
                .foregroundStyle(T.C.ink3)
            Rectangle()
                .fill(T.C.hair)
                .frame(height: 0.5)
        }
        .padding(.top, 22)
        .padding(.bottom, 2)
    }''',
  '''    /// 当天条数（右侧）。nil = 不显示。
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(T.C.brass)
                .frame(width: 4, height: 4)
                .shadow(color: T.C.brass.opacity(0.6), radius: 4)
                .accessibilityHidden(true)
            Text((title ?? When.dayTitle(time)).uppercased())
                .type(T.F.kicker)
                .tracking(1.4)
                .foregroundStyle(T.C.ink2)
            Rectangle()
                .fill(
                    LinearGradient(colors: [T.C.hairStrong, T.C.hair.opacity(0.15)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 0.5)
            if let count {
                Text("\\(count)")
                    .type(T.F.kicker)
                    .monospacedDigit()
                    .foregroundStyle(T.C.ink3)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 2)
    }'''),
])

# ---------- 记录页：日头带条数 + 行入场 ----------
apply('App/Features/Log/LogScreen.swift', [
 ('''                    ForEach(groups) { group in
                    DayHead(time: group.time, title: group.title)''',
  '''                    ForEach(groups) { group in
                    DayHead(time: group.time, title: group.title, count: group.items.count)'''),
])

# ---------- 今日：入场节奏 + Hero 视差 ----------
apply('App/Features/Today/TodayScreen.swift', [
 ('''                twoColumns(wide, leading: {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        hero
                        if receipt { receiptCard }
                    }
                }, trailing: {''',
  '''                twoColumns(wide, leading: {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .entrance(0, rise: 8)
                        hero
                            .entrance(1, rise: 18)
                            .scrollParallax(depth: 0.94)
                        if receipt { receiptCard.entrance(2, rise: 10) }
                    }
                }, trailing: {'''),
 ('''                        if settings.homeSections.contains("readings") { readings }
                        if settings.homeSections.contains("tray") { tray }
                        if settings.homeSections.contains("recent") { recent }''',
  '''                        if settings.homeSections.contains("readings") { readings.entrance(2, rise: 12) }
                        if settings.homeSections.contains("tray") { tray.entrance(3, rise: 12) }
                        if settings.homeSections.contains("recent") { recent.entrance(4, rise: 12) }'''),
])

# ---------- 门禁：入场编排 + 按键触感 + 错误抖动 ----------
apply('App/Features/Shared/GateScreen.swift', [
 ('''    @State private var cooling = AppLock.shared.cooldownRemaining()''',
  '''    @State private var cooling = AppLock.shared.cooldownRemaining()
    /// 错误抖动计数器（每次输入失败 +1）。
    @State private var shakeCount: CGFloat = 0'''),
 ('''                Text("阈")
                    .type(T.F.wordmark)
                    .foregroundStyle(T.C.ink)
                Kicker(text: "THRESHOLD · 本机密码", dot: false, tint: T.C.ink3)''',
  '''                Text("阈")
                    .type(T.F.wordmark)
                    .foregroundStyle(T.C.ink)
                    .entrance(0, rise: 6)
                Kicker(text: "THRESHOLD · 本机密码", dot: false, tint: T.C.ink3)
                    .entrance(1, rise: 4)'''),
 ('''            DisplayLine(text: message ?? "先确认是你。", size: 30)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)''',
  '''            DisplayLine(text: message ?? "先确认是你。", size: 30)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .entrance(2, rise: 8)
                // 输错时横抖一下（配一次错误触感）—— 不用红字训人。
                .shake(shakeCount)'''),
 ('''            keypad

            PrimaryButton(title: "解锁", enabled: canSubmit) {''',
  '''            keypad
                .entrance(3, rise: 16)

            PrimaryButton(title: "解锁", enabled: canSubmit) {'''),
 ('''                                    .frame(width: 74, height: 60)
                                    .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.keyRadius, style: .continuous),
                                                 tint: GlassMetrics.tint, interactive: true)''',
  '''                                    .frame(width: 74, height: 60)
                                    .liquidGlass(in: RoundedRectangle(cornerRadius: GlassMetrics.keyRadius, style: .continuous),
                                                 tint: GlassMetrics.tint, interactive: true)
                                    // 键位依次亮起：row*3+col 的延迟，从左上到右下。
                                    .entrance(row * 3 + (keys[row].firstIndex(of: key) ?? 0),
                                              rise: 8, delayStep: 0.028)'''),
 ('''    private func tap(_ key: String) {
        guard cooling == 0 else { return }''',
  '''    private func tap(_ key: String) {
        guard cooling == 0 else { return }
        Haptics.impact(.light)'''),
 ('''        case .wrong(let remaining):
            input = ""
            message = remaining > 0 ? "再试一次。" : "密码不对。"
            if remaining > 0 { cooling = remaining }
            Haptics.notify(.error)''',
  '''        case .wrong(let remaining):
            input = ""
            message = remaining > 0 ? "再试一次。" : "密码不对。"
            if remaining > 0 { cooling = remaining }
            Haptics.notify(.error)
            withAnimation(.linear(duration: 0.42)) { shakeCount += 1 }'''),
])

# ---------- 凭证行：种类色 + 卡片化 ----------
apply('App/Features/Access/AccessScreen.swift', [
 ('''            ContentRow(symbol: item.kind.symbol,
                       tone: item.isExpiringSoon || item.isExpired ? .danger : .brass,
                       title: item.name,
                       subtitle: subtitle(item),
                       chevron: true) {''',
  '''            ContentRow(symbol: item.kind.symbol,
                       // 临期/过期的图标砖走危险色；其余按种类给一点色差
                       // （密码=黄铜、临时码=冷、指纹=黄铜、手机钥匙=冷）。
                       tone: item.isExpiringSoon || item.isExpired ? .danger
                             : (item.kind == .temp || item.kind == .mobile ? .cool : .brass),
                       title: item.name,
                       subtitle: subtitle(item),
                       chevron: true) {'''),
])
print('done')
