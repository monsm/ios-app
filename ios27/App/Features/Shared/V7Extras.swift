// V7Extras.swift —— 降级项接线用的 v7 补充控件。
//
// 来源：App/Design/V7/V7Components.swift 的令牌与卡片语言（V.C / V.F / V.S / VCard / VActionButton）。
// 这里补「表单行 / 次级按钮 / 读数 / 空态 / chip 行」这些 v7 参考图没有覆盖到的通用零件；
// 不引入旧设计系统（旧令牌一律不用），也不改 Design/ 里的现有语义。
import SwiftUI
import Foundation

/// 描边次级按钮：与 VActionButton 同高同圆角，但不着色 —— 一屏只允许一个 VActionButton。
struct VOutlineButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = V.C.text1
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: V.S.gapS) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(V.F.icon15Semibold)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(V.F.bodyStrong)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            // 同 `VActionButton`：标题随 Dynamic Type 放大，固定 50pt 会裁字。
            .padding(.vertical, V.S.gapS)
            .frame(minHeight: V.Action.height)
            .overlay {
                RoundedRectangle(cornerRadius: V.R.action, style: .continuous)
                    .strokeBorder(V.C.tabEdge, lineWidth: V.S.hair)
            }
            .contentShape(.rect)
        }
        // 2026-11-01：同 `VActionButton` —— `.plain` 在 iOS 上无按压反馈；76 处次要按钮一次覆盖。
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }
}

/// 凹槽块：卡内次级分组（刻度底 / 读数条 / 内嵌列表）。
struct VInset<Content: View>: View {
    var inset: CGFloat = V.S.gapMS
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V.C.cardAlt, in: .rect(cornerRadius: V.R.inset))
    }
}

/// 一枚读数：数值 + 单位。数值走等宽，单位走 11pt 淡色。
struct VReading: View {
    let value: String
    var unit: String? = nil
    var font: VFont = V.F.number17
    var tint: Color = V.C.text1
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapXS) {
            Text(value)
                .font(font)
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(reduceMotion || !animated ? .identity : .numericText())
            if let unit {
                Text(unit)
                    .font(V.F.unit)
                    .foregroundStyle(V.C.text3)
                    .tracking(0.6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// V7 台账行：等宽时刻在左、事件居中、状态点在右（LedgerRow 的 V7 版本）。
struct VLedgerRow: View {
    let entry: LedgerEntry
    var showDay: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: V.S.gapMS) {
            VStack(alignment: .leading, spacing: 0) {
                Text(TimeDisplay.clock(entry.at))
                    .font(V.F.stamp)
                    .foregroundStyle(V.C.text1)
                    .monospacedDigit()
                if showDay {
                    Text(TimeFormat.dayShort(entry.at))
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text3)
                        .monospacedDigit()
                }
            }
            .frame(width: showDay ? 58 : 48, alignment: .leading)

            VStack(alignment: .leading, spacing: V.S.gapXXS) {
                Text(entry.event)
                    .font(V.F.body)
                    .foregroundStyle(V.C.text1)
                if let owner = entry.owner, !owner.isEmpty {
                    Text(owner)
                        .font(V.F.unit)
                        .foregroundStyle(V.C.text2)
                }
            }

            Spacer(minLength: V.S.gapS)
            VStateDot(tone: entry.tone, word: entry.event)
        }
        .frame(minHeight: V.Hit.min + V.S.gapS)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(TimeDisplay.clock(entry.at)) \(entry.event)" +
            (entry.owner.map { "，\($0)" } ?? "")
        )
    }
}

/// 卡内读数行：左标签、右读数（等宽数字）。
///
/// 2026-11-01 改造：**改用原生 `LabeledContent`**（55 处调用一次覆盖）。
/// 为什么（对应 objective 的「原生控件优先」+「控件大小考虑实际文字占用」）：
///   · `LabeledContent` 是系统为「标签 + 值」这一对准备的容器，自带正确的
///     VoiceOver 语义（读成"型号，K1"而不是两个独立元素）；
///   · 布局上它**先给标签让位**：标签长 / 字号大时会换行，而不是把右侧数值挤出去
///     —— 旧写法 `HStack { Text; Spacer(minLength:); 值 }` 在长标签 + 大字号下
///     会让数值被压缩甚至截断；
///   · RTL、Dynamic Type、系统强调色全部自动跟随。
struct VFieldRow: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = V.C.text1
    var mono: Bool = true

    var body: some View {
        LabeledContent {
            if mono {
                VReading(value: value, unit: unit, font: V.F.number15, tint: tint, animated: false)
            } else {
                Text(value)
                    .font(V.F.bodyStrong)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            Text(label)
                .font(V.F.body)
                .foregroundStyle(V.C.text2)
        }
        .frame(minHeight: V.Metric.searchRow)
        // 进系统 List 后行内边距与卡片 gutter 对齐（非 List 容器里是 no-op）。
        .listRowInsets(EdgeInsets(top: 0, leading: V.S.cardPad, bottom: 0, trailing: V.S.cardPad))
    }
}

/// 卡内读数行：左标签、右读数（等宽数字）。
struct VValueRow: View {
    let label: String
    let value: String
    var tint: Color = V.C.text1
    var mono: Bool = true
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXXS) {
            HStack(alignment: .firstTextBaseline, spacing: V.S.gapS) {
                Text(label)
                    .font(V.F.rowDetail)
                    .foregroundStyle(V.C.text3)
                Spacer(minLength: V.S.gapS)
                Text(value)
                    .font(mono ? V.F.legendLabelStrong.monospacedDigit() : V.F.legendLabel)
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(V.F.footnote)
                    .foregroundStyle(V.C.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: V.List.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

/// 读数网格：2~3 列等宽读数。
struct VReadingGrid: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var unit: String? = nil
        var tint: Color = V.C.text1
    }

    let items: [Item]
    var columns: Int = 2

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0 ..< min($0 + columns, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                        .padding(.vertical, V.S.gapMS)
                }
                HStack(alignment: .top, spacing: V.S.gapMS) {
                    ForEach(row) { item in
                        VStack(alignment: .leading, spacing: V.S.gapXS) {
                            Text(item.label)
                                .font(V.F.unit)
                                .foregroundStyle(V.C.text3)
                                .tracking(0.6)
                            VReading(value: item.value, unit: item.unit, font: V.F.number22, tint: item.tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if row.count < columns {
                        ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

/// 卡内文本输入行（普通 / 密码两档）。
struct VTextFieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var secure: Bool = false
    var axisVertical: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: V.S.gapXS) {
            Text(label)
                .font(V.F.chipLabel)
                .foregroundStyle(V.C.text4)
            Group {
                if secure {
                    SecureField(placeholder.isEmpty ? label : placeholder, text: $text)
                } else if axisVertical {
                    TextField(placeholder.isEmpty ? label : placeholder, text: $text, axis: .vertical)
                        .lineLimit(2 ... 5)
                } else {
                    TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                }
            }
            .font(V.F.body)
            .foregroundStyle(V.C.text1)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            Rectangle().fill(V.C.hairline).frame(height: V.S.hair)
        }
        .frame(minHeight: V.List.rowMinHeight)
        .accessibilityElement(children: .contain)
    }
}

/// 小标签胶囊（分组 / 状态词）。形状 + 文字双通道，不单靠颜色。
///
/// D-04：视觉上它是 26pt 高的小胶囊，但**常被直接当作 Button 的 label**
/// （`AccessibilityScreen` 的圆盘尺寸、`TailgateScreen` 的模式选择、
/// `RecordsStudioScreen` 的成员筛选等）—— 那些地方的点击区域只有 26pt，
/// 远低于 HIG 的 44×44pt（最低 28pt）。
/// 处置：胶囊**视觉尺寸不变**（设计稿要求小），用 `.contentShape` + 透明外扩
/// 把命中区撑到 `V.Hit.min`。这样外观不动、手指够得着。
struct VTag: View {
    let text: String
    var tint: Color = V.C.text1
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(V.F.footnote)
            .foregroundStyle(filled ? V.C.onBlue : tint)
            .padding(.horizontal, V.S.gapM)
            .padding(.vertical, V.S.gapXS)
            .background(filled ? tint : Color.clear, in: Capsule())
            .overlay {
                Capsule().strokeBorder(filled ? Color.clear : V.C.tabEdge, lineWidth: V.S.hair)
            }
            // 命中区至少 44pt（D-04）：视觉仍是小胶囊，可点区域外扩且不占布局。
            .frame(minHeight: V.Hit.min)
            .contentShape(.rect)
            .accessibilityLabel(text)
    }
}

/// 卡内分隔线间距统一版：V7 的 VDivider 无内外边距，这里只包一层呼吸。
struct VRowDivider: View {
    var body: some View {
        VDivider().padding(.vertical, V.S.gapXXS)
    }
}

// MARK: - 状态三通道（形状 + 颜色 + 文字）

/// 状态点：形状随语义变（圆=正常 / 三角=注意 / 方块=危险），不靠颜色单通道。
struct VStateDot: View {
    let tone: Tone
    let word: String

    var body: some View {
        Group {
            switch tone {
            case .critical:
                RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(tone.color)
            case .attention:
                VTriangle().fill(tone.color)
            // 同 `StateDot`：穷尽列出（`Tone` 五个 case），不靠 `default` 兜。
            case .ok, .neutral, .live:
                Circle().fill(tone.color)
            }
        }
        .frame(width: V.List.stateDotSize, height: V.List.stateDotSize)
        .accessibilityLabel(word)
    }
}

struct VTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 状态条：状态点 + 文字。
struct VStatusLine: View {
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: V.S.gapS) {
            VStateDot(tone: tone, word: text)
            Text(text)
                .font(V.F.footnote)
                .foregroundStyle(tone == .neutral ? V.C.text2 : tone.color)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 分段 / chip 行。选中 = 蓝色微光底 + 白字；未选 = 透明 + 次文本。
struct VChipRow<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: V.S.gapS) {
                ForEach(items, id: \.self) { item in
                    let on = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(title(item))
                            .font(V.F.footnote)
                            .foregroundStyle(on ? V.C.text1 : V.C.text3)
                            .padding(.horizontal, V.S.gapMS)
                            .frame(minHeight: V.H.chip)
                            .background(on ? V.C.blue.opacity(0.16) : Color.clear, in: .capsule)
                            .overlay {
                                Capsule().strokeBorder(
                                    on ? V.C.blue.opacity(0.75) : V.C.hairline,
                                    lineWidth: V.S.hair
                                )
                            }
                    }
                    .buttonStyle(V8PressStyle())
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, V.S.pageGutter)
        }
        .scrollIndicators(.hidden)
    }
}

/// 空态：系统 ContentUnavailableView + 出路按钮。空态必须给出下一步。
struct VEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String
    var systemImage: String = "tray"
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            VActionButton(title: actionTitle, action: action)
                .frame(maxWidth: 240)
        }
    }
}

/// 统一加载态：菊花 + 禁用，杜绝重复触发。
struct VBusyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: V.S.gapS) {
            ProgressView().controlSize(.small)
            Text(text).font(V.F.footnote).foregroundStyle(V.C.text2)
            Spacer(minLength: 0)
        }
        .frame(minHeight: V.Metric.searchRow)
    }
}
// MARK: - List 行内嵌任意视图

extension View {
    /// 把任意视图放进系统 `List` 时，抹掉行内边距 / 分隔线 / 行背景 ——
    /// 让「卡片」在 List 里仍保持原来的样子，而滚动与边缘效果交给系统。
    ///
    /// `vGap`：**行间垂直间距**。这是 List 化最容易毁观感的一处 ——
    /// 改前是 `VStack(spacing: V.S.gap16)`，卡片间距由 VStack 统一给；
    /// 换成 List 后这个间距**消失了**（行与行紧贴），于是整页从"分块的仪表盘"
    /// 变成"一长条堆叠"，看起来七扭八歪。这里用对称的垂直内边距把原间距补回来：
    /// 每行上下各加 `vGap / 2`，相邻两行合计 = 原来的 `vGap`。
    func plainRow(vGap: CGFloat = 0) -> some View {
        self
            .padding(.vertical, vGap / 2)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// **带 gutter 的卡片行**：用于 `.listStyle(.plain)` 的页面。
    ///
    /// `.plain` 样式没有 insetGrouped 自带的左右留白，而 `plainRow()` 又把行内边距抹成 0 ——
    /// 两者一起用会让卡片**贴到屏幕左右边缘**。这里补回页面 gutter，卡片内部再靠 `VCard` 自己的
    /// `cardPad` 撑开文字，与改前的观感一致。
    ///
    /// 判据：页面是 `.listStyle(.plain)` + 卡片走 `plainRow()` ⇒ 用这个，不要用 `plainRow()`。
    /// 页面是 `.listStyle(.insetGrouped)` ⇒ 系统已经给左右留白，用 `plainRow()` 即可。
    func cardRow(gutter: CGFloat = V.S.pageGutter) -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: gutter, bottom: 0, trailing: gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// **页头行**：整宽内容（页头 / 芯片行 / 搜索框 / 提示条），但要与卡片**同一条左右基准线**。
    ///
    /// 为什么需要它：改前的 ScrollView 版里，页头和卡片都各自带 `.padding(.horizontal, pageGutter)`，
    /// 所以两者左边线对齐在 16pt。换成 List 后卡片走 `cardRow()`（16pt）、页头走 `plainRow()`（0pt），
    /// **页头会比卡片更靠边**。这里把 16pt 补回来，保持改前的对齐关系。
    ///
    /// 与 `cardRow()` 的区别只是语义：页头不是卡片，不该有"行"的视觉含义；实现上两者相同。
    func headerRow(gutter: CGFloat = V.S.pageGutter) -> some View {
        self
            .padding(.horizontal, gutter)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - CI 截图的滚动锚（-kfScroll 时根页首屏即显示底部内容）

/// `-kfScroll` 启动参数存在时，把 ScrollView 的默认锚点设为底部 ——
/// 时间线/凭证行/工具区在首屏之下，正常截图只拍得到顶部。截图管线借此看到全页。
/// 正常启动不带此参数，修饰符是透明直通。
struct UITestScrollBottom: ViewModifier {
    func body(content: Content) -> some View {
        if UITestEnv.scrollBottom.withLock({ $0 }) {
            content.defaultScrollAnchor(.bottom)
        } else {
            content
        }
    }
}
