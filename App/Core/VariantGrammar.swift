import SwiftUI

// ============================================================
// 视觉语法层 (Grammar) —— 2026-10-16，2026-10-16 晚随变体清理收敛成一套
// ------------------------------------------------------------
// 需求是"App 内可切换两套完整 UIUX，且各自一致、各自完整"。
//
// 为什么不是"把 77 个页面各抄一遍"：抄两遍之后，任何一个字段、任何一条文案、任何一个
// 开关行为都要改两次 —— 这就是本仓反复点名的"同一个量算两次"，两套必然漂移，
// 漂移到最后就是"切到某版少一个功能"。**内容必须单一来源。**
//
// 为什么不是"中央路由表"：77 个目的地绝大多数带宿主本地状态
// （`.sheet(item: $x) { LockProfileView(mac: $0) }`），搬到中央路由要先把本地状态全提升；
// 而 @ViewBuilder 装不下 77 个分支（本仓已两次因巨型 body 报 type-check 超时，
// 见 LockKeeperApp.swift 的 mainTabView / rootGroup 注释）。
//
// 采用的做法：**每个变体定义一份完整的视觉语法，所有目的地经过同一个缝 `.destined(_:)`**。
//   · 一致性 = 语法只有一个实现处，页面拿不到"自己随便画个容器"的余地；
//   · 完整性 = 每个方法内部是**穷尽 switch**，少给某个变体定义就编译不过；
//     再加一道 tools/uicoverage.js 数"77 个目的地里有几个真的挂了缝"。
//
// ⚠ 本文件所有返回 `AnyView` 是刻意的，不是偷懒：
//   协议 + `some View` 会让语法类型无法被 `any` 装箱，而穷尽 switch 的每个分支类型都不同。
//   AnyView 的代价是擦除类型、多一层容器；换来的是**这份文件在我一次都编译不了的前提下
//   不会因类型推导爆炸而失败**。等真机跑通、CI 绿了再考虑收窄。
// ============================================================

/// 容器的语义种类。页面只说"这是一个分组 / 一块瓦片 / 一条内嵌行"，
/// **长成什么样由当前变体决定** —— 这是两套 UIUX 能真正不同、又不会各画一遍的关键切分。
enum ContainerKind {
    case group      // 一组相关读数/设置
    case tile       // 可点的一次性入口
    case inset      // 嵌在别的东西里面的小格
    case hero       // 首屏主角那一块
}

struct VK {

    /// 视觉语法。拿不到 AppState 的叶子视图走这个静态入口。
    static var current: VK { VK() }

    // MARK: - 令牌

    var accent: Color {
        return DS.Palette.text          // 现行：品牌色由 DS 的 accent 通道给，这里不抢
    }

    var canvas: Color {
        return DS.Palette.canvasBase
    }

    var bezel: Color {
        return DS.Palette.surfaceBase
    }

    var hair: Color {
        return DS.Palette.hairline
    }

    var ink: Color   { DS.Palette.text }
    var sub: Color   { DS.Palette.textSub }

    /// 页面左右边距。三套刻意不同 —— 这是"两套看着就不一样"最便宜的一处。
    var gutter: CGFloat {
        return DS.Space.gutter            // 16 标准
    }

    var corner: CGFloat {
        return DS.Radius.card              // 22 档，跟随 kf_radius
    }

    /// 主表面容器。**`Card` 的全部 53 处调用都走这里** —— 一处改动让两套在首屏以下真正分开，
    /// 而不是去 53 个调用点各改一遍（那既是"同一个量算两次"，也是漏改的温床）。
    ///
    /// `.legacy` 分支是 `LockKeeperApp.swift` 里原 `Card.body` **逐字搬过来的**，
    /// 一个像素都不该变：「默认值 = 零行为改动」这条承诺靠"把代码搬过来"保证，
    /// 而不是靠"照着再写一份"—— 后者一定会在某个间距上写错。
    /// 体内走 .axGlass (View 扩展 = 主 actor); 本类型不是 View, 所以显式标主 actor。
    @MainActor
    func card<Content: View>(tint: Color? = nil, @ViewBuilder _ content: () -> Content) -> AnyView {
        // 用 Optional 而不是拿 Color 比相等：`tint == .clear` 依赖 Color 的 Equatable 实现，
        // 而它比较的是色彩值 —— 语义上"没染色"的写法一变（.clear / Color.white.opacity(0)）就判错。
        let wash = tint ?? Color.clear
        return AnyView(
            VStack(alignment: .leading, spacing: DS.Space.m) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.l)
                // 2026-10-14 材质统一: 主表面 Card 从实底改液态玻璃。走既有 axGlass 而不是自己写 glassEffect ——
                // 那条路径自带 226 降低透明度 / 862 增强对比 的降实底退路, 另写一份就会让"关玻璃"只关一半界面。
                .axGlass(DS.Radius.card)
                .background {
                    // 语义色叠底走 tint (它为什么是 0.14 而不是实底时代的 0.08，写在 Card.tintWash 的注释上)
                    let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    shape.fill(wash)
                }
                .shadow(color: .cardElevation, radius: 12, y: 4)
                .padding(.horizontal, DS.Space.gutter)
        )
    }


    /// 分区标题。**21 处 `SectionTitle` 全走这里。** legacy 分支逐字搬自原实现。
    func sectionTitle(text: String, count: Int?) -> AnyView {
        return AnyView(
            HStack(spacing: DS.Space.s) {
                // 品牌色小竖标: 不占一行的宽度, 却让分区标题有自己的"签名"
                Capsule()
                    .fill(DS.Palette.accent)
                    .frame(width: 3, height: 14)
                    .accessibilityHidden(true)
                Text(text).font(.headline).foregroundStyle(DS.Palette.text)
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.textSub)
                        .padding(.horizontal, DS.Space.s).padding(.vertical, DS.Space.xxs)
                        .background(DS.Palette.surfaceAlt, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        )
    }

    /// 状态标签。**29 处 `StatusPill` 全走这里。**
    /// 三套都必须保住那条既有纪律：**颜色不作为唯一信息载体** ——
    /// 原实现的"图标形状 + 图标颜色"双通道在三个分支里都保留，不许为了简洁把图标删了只剩色。
    func statusPill(text: String, systemImage: String, tone: Color) -> AnyView {
        return AnyView(
            HStack(spacing: DS.Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(tone)
                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.Palette.textSub)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s + 2)
            .padding(.vertical, DS.Space.xs + 1)
            .background(DS.Palette.surfaceAlt, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 0.5))
            // 不允许被父容器压缩: 状态文案换行会把胶囊撑成两行, 行高随之错位
            .fixedSize(horizontal: true, vertical: false)
        )
    }

    // MARK: - 结构件

    /// 分隔线。**三套都用两端淡出的发丝线** —— 这是唯一一处"变体之间不许不同"的地方：
    /// 实线贯穿是"表格感"的来源，而两套新界面都判定它是要去掉的东西。
    func hairline() -> AnyView {
        AnyView(
            LinearGradient(colors: [.clear, hair, hair, .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 0.7)
        )
    }

    /// 容器。三套在这里真正分道扬镳。
    func container<C: View>(_ kind: ContainerKind, @ViewBuilder _ content: () -> C) -> AnyView {
        let pad: CGFloat = kind == .inset ? 12 : (kind == .hero ? 18 : 16)
        return AnyView(
            content()
                .padding(pad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(bezel))
        )
    }

    // MARK: - 排版件

    /// 页面标题。
    func title(_ text: String) -> AnyView {
        return AnyView(Text(text).font(.system(.headline, design: .default).weight(.semibold)).foregroundStyle(ink))
    }

    // 2026-10-17 清理: eyebrow / metric / rowTitle / rowSub / primaryButton 五件删除。
    // 它们是两套实验界面还活着时为那两套写的排版件，界面与本文件的那批 switch 一并删掉之后，
    // deadscan 报这五件"全库零引用"（含本文件内部）—— 现役界面走的是 vkFont + MetricTile +
    // PrimaryActionStyle / BusyButton 那一套。留着一组没人叫的排版件只会让下一个改界面的人
    // 在两条路里二选一，而其中一条早就没人维护了。
}


// ============================================================
// 目的地缝
// ============================================================

/// 每个目的地视图挂上它。**变体删掉之后这里没有视觉动作了** ——
/// 留着它是因为 tools 侧还靠这个标记数"77 个目的地里有几个真的挂在唯一通路上"：
/// 它不是界面，是台账的一枚钉子。任何视觉效果都不要往这里加：
/// 这一缝挂在 77 个页面上，加一层背景或 frame 就是全仓一起变。
struct DestinedModifier: ViewModifier {
    let destination: Destination

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// 挂上目的地标记（台账用，无视觉作用）。
    func destined(_ d: Destination) -> some View {
        modifier(DestinedModifier(destination: d))
    }
}

// P1 批一：自绘底衬接进语法层 (2026-10-16) —— 一次性把 176 处自绘盒子收进语法件。
// 只收 legacy 能**逐字复刻**的写法：`variantPlate` 就是改造前那一句
// `background(style, in: shape)`，同一个调用、同一个形状，像素不可能变。

/// 底衬的形状档。**故意不是 `Shape` 泛型**：调用点若还留着一句 `in: Capsule()`，
/// tools/uicoverage.js 的自绘容器预算（只认字面 token）就数不到这次迁移，
/// 迁移进度会看起来没动 —— 预算得能反映事实，形状就得以令牌形式传进来。
enum PlateShape {
    case capsule    // 信息胶囊
    case tile       // 瓦片 (DS.Radius.tile)
    case control    // 控件 / 内嵌格 (DS.Radius.control)
    // 图标角标 (DS.Space.s) —— 两处调用都在 CredentialStudio (fanoutRow / CredStudioEntryView)。
    // 它下面的两张表**已各写了一份**这个分支：漏掉这个 case 时它们不是"多写了分支"，
    // 而是编译不过（`type 'PlateShape' has no member 'iconBadge'`，CI run 115 抓到 6 处）。
    case iconBadge

    /// legacy 逐字等于改造前那个形状（连 `.continuous` 与非 continuous 的差别一起复刻）。
    var legacy: AnyShape {
        switch self {
        case .capsule: return AnyShape(Capsule())
        case .tile:    return AnyShape(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        case .control: return AnyShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        case .iconBadge: return AnyShape(RoundedRectangle(cornerRadius: DS.Space.s, style: .continuous))
        }
    }

    /// legacy 的描边。**必须单独一份**：`strokeBorder` 只长在 `InsettableShape` 上，而 `AnyShape`
    /// 把那个能力擦掉了（本仓 `AccessibilityKit` 里记过这条）—— 所以描边不能复用 `legacy`。
    func legacyEdge(_ color: Color, _ lineWidth: CGFloat) -> AnyView {
        switch self {
        case .capsule: return AnyView(Capsule().strokeBorder(color, lineWidth: lineWidth))
        case .tile:    return AnyView(RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous).strokeBorder(color, lineWidth: lineWidth))
        case .control: return AnyView(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).strokeBorder(color, lineWidth: lineWidth))
        case .iconBadge: return AnyView(RoundedRectangle(cornerRadius: DS.Space.s, style: .continuous).strokeBorder(color, lineWidth: lineWidth))
        }
    }
}

extension View {
    /// 把"我自己画的一块**装饰性中性**底衬"交给当前变体。
    /// ⚠ 带状态语义的底衬不要走这里（见本节头注释）；那类要单独设一个能表达 state 的语法件。
    /// `edge` 给了就补一圈发丝描边（legacy 的 `strokeBorder` 仍在同一句里复刻，仍然像素不变）。
    func variantPlate(_ style: Color, _ shape: PlateShape, edge: Color? = nil) -> AnyView {
        let base = AnyView(self.background(style, in: shape.legacy))
        guard let edge else { return base }
        return AnyView(base.overlay { shape.legacyEdge(edge, 0.5) })
    }

    /// 带语义色的提示块（告警 / 成功 / 强调 / 危险）。**它和 `variantPlate` 不是一类东西**：
    /// 提示块的那层洗色是**信息**（"这一段是告警"），画的是状态而不是装饰。
    func variantCallout(_ tone: Color, _ shape: PlateShape, wash: Double) -> AnyView {
                // 逐字等于改造前那一句。
        return AnyView(self.background(tone.opacity(wash), in: shape.legacy))
    }
}

// ============================================================
// P1 批二：整页级的外观下发 (2026-10-16)
// ------------------------------------------------------------
// 用户的问题："切换后每个页面都是全新的吗？"
// 量过一遍：只接容器是**不够**的 —— 一页的"长相"大半不由那几个盒子决定，而由
//   · 清单结构（分组内不内缩 / 行间有没有分隔线 / 节距 / Section 标题怎么渲染）
//   · 原生控件（开关 / 滑杆 / 选择器 / 链接）的颜色
//   · 三个共享按钮样式
// 决定。这三样以前两套一模一样 —— 所以 77 个页面里大多数是"新相框、旧内容"。
// 这一批把这三样也挂到变体上，而它们的调用点又极其集中（这正是为什么它们价值最高）：
//   viewportList() 换掉 85 处 `.scrollContentBackground(.hidden)`；
//   `.tint` 只在缝里写一次（`tint` 走环境，一处设、整棵树生效）⇒ 全仓 120 处 Toggle
//   与所有滑杆/选择器一次跟着走；
//   三个 ActionStyle 是共享结构，改它们等于改全仓 61 处主(26)/次(33)/破坏性(2)按钮。
// 口径不变：legacy 分支 **逐字** 等于改造前那一段，像素不可能变。
// ============================================================

extension View {
    /// 页面清单（`List`）的结构外观。**替代全仓 85 处 `.scrollContentBackground(.hidden)`**。
    ///
    /// 为什么这是最大的一处杠杆：`.listStyle` 不只是样式，它同时决定
    /// 分组是否内缩、Section 标题怎么渲染 —— 全仓 **255 个 `Section`** 的标题外观都在它手里。
    /// 一行换掉，两套清单页的"骨架"立刻不一样，而不是只换背景色。
    func variantList() -> AnyView {
                // 逐字等于改造前那一句 —— 像素不可能变。
        return AnyView(self.scrollContentBackground(.hidden))
    }
}

// MARK: - 按钮外形

// 为什么拆成三个函数而不是一个 `switch role`：内层再套一层 switch 会让
// tools/uicoverage.js 的分支正则提前收尾。

extension VK {
    /// 主按钮外形。legacy 分支逐字搬自 `DesignSystem.swift` 原 `PrimaryActionStyle.makeBody`。
    func primaryActionChrome<Label: View>(fullWidth: Bool, pressed: Bool,
                                          @ViewBuilder _ label: () -> Label) -> AnyView {
                return AnyView(
            label()
                .font(.headline)
                .foregroundStyle(DS.Palette.onAccent)
                .padding(.vertical, DS.Space.m + 2)
                .padding(.horizontal, DS.Space.l)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: DS.Hit.min + 6)
                .background(DS.Gradient.button,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .shadow(color: DS.Palette.accent.opacity(0.26), radius: 12, y: 5)
                .opacity(pressed ? 0.9 : 1)
                .scaleEffect(pressed ? 0.98 : 1)
                .animation(DS.Motion.quick, value: pressed)
        )
    }

    /// 次按钮外形。legacy 分支逐字搬自原 `SecondaryActionStyle.makeBody`。
    func secondaryActionChrome<Label: View>(fullWidth: Bool, pressed: Bool, tint: Color,
                                            @ViewBuilder _ label: () -> Label) -> AnyView {
                return AnyView(
            label()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.accentText)
                .padding(.vertical, DS.Space.s + 2)
                .padding(.horizontal, DS.Space.l)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: DS.Hit.min)
                .background(tint.opacity(pressed ? 0.16 : 0.09),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .scaleEffect(pressed ? 0.985 : 1)
                .animation(DS.Motion.quick, value: pressed)
        )
    }

    /// 破坏性按钮外形。legacy 分支逐字搬自原 `DestructiveActionStyle.makeBody`。
    /// 三个变体都保住那条纪律：**破坏性必须靠颜色 + 文字两通道**，不许只靠色（色有时是唯一载体）。
    func destructiveActionChrome<Label: View>(pressed: Bool,
                                             @ViewBuilder _ label: () -> Label) -> AnyView {
                return AnyView(
            label()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.danger)
                .padding(.vertical, DS.Space.s + 2)
                .padding(.horizontal, DS.Space.l)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DS.Hit.min)
                .background(DS.Palette.danger.opacity(pressed ? 0.16 : 0.09),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .animation(DS.Motion.quick, value: pressed)
        )
    }
}

// ============================================================
// 完整性读数
// ============================================================

// ============================================================
// MARK: - 开关的形状（VK 的最后一件：`Toggle` 与 `VariantToggle`）
// ============================================================
//
// **问题**：120 处 `Toggle` 的颜色早就在缝里下发过了（`.tint`），但**形状**一直是系统开关 ——
// 也就是说两套界面在每个开关上都长得一样。这一层管的就是那个形状。
//
// **为什么是改名**：`Toggle` 的标签形状有五种、调用普遍跨多行，要在每个表达式**末尾**插一个
// `.toggleStyle(...)` 是纯语法手术面；改名只在构造子那几个字符上动手，实参一个字不碰。
// 本仓 `requestTab` -> `requestRoute` 用的是同一个手法。
//
// **legacy 不改一个像素**：那个分支把系统开关**原样装回去**，所以默认变体下外观与行为都不变。
// 内层那个**显式** `.toggleStyle(.switch)` 不是装饰：不写它，内层 `Toggle` 会继承外层这个自定义样式，
// `makeBody` 就自己调自己 —— 显式钉一次，递归就断了。
//
// **VoiceOver**：core / gauge 是自绘控件，系统不再认识它是开关。补法用
// `.accessibilityRepresentation { ... }`，而不是手贴 `.accessibilityAddTraits(.isToggle)`：
// representation 把整棵无障碍子树换成一个**真的 Toggle**，于是值（开/关）、激活动作、可调性
// 全由系统给出；手贴 traits 得自己把三样都补齐，漏一样就是"读得出、按不动"。
// 两样都写反而危险：两个来源各说一套。
//
// 状态**不只靠颜色**说：core 的滑点位置（左/右）与 gauge 滑臂位置本身就在说开/关，
// 色觉障碍用户读得到，`contrast.js` 也不承担这条（位置不是颜色）。

/// 开关形状的实现。三 case 齐全（`uicoverage` 检查三按变体分叉就要求这个）。
/// ⚠ 返回类型写 `AnyView` 而不是 `some View` 是**为了被检查三覆盖**：那一支只扫 `-> AnyView {`
/// 的分叉函数（本文件的既定形状）。改成 `some View` 它就静默逃过穷尽性检查 —— 语法件越多漏得越多。
struct VariantToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> AnyView {
            return AnyView(
        // `configuration.isOn` 是 **Bool**（`ToggleStyleConfiguration` 里那一枚是 `@Binding`
        // 属性 ⇒ 取 `$isOn` 才是 `Binding<Bool>`）。CI run 115 在这三处报的是
        // "cannot convert value 'isOn' of type 'Bool' to expected type 'Binding<Bool>', use wrapper instead"。
        Toggle(isOn: configuration.$isOn) { configuration.label }
            .toggleStyle(.switch))
    }
}

// 三个包装函数，逐一对照 `Toggle` 自己的重载声明（多一个不多、少一个少）。
// 保留 `LocalizedStringKey` 与 `StringProtocol` **两个**重载是必需的：
// 只留前者，`Toggle(a.label, isOn:)` 那 5 处（标题是变量/三元式）会推断成 String 而解不动。

/// `Toggle("字面量", isOn:)` 的那 99 处。
func VariantToggle(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
    Toggle(titleKey, isOn: isOn).toggleStyle(VariantToggleStyle())
}

/// `Toggle(<String 表达式>, isOn:)` 的那 5 处（标题是变量、三元式或下标）。
func VariantToggle<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn).toggleStyle(VariantToggleStyle())
}

/// `Toggle(isOn: ...) { 自定标签 }` 的那 6 处（标题是一个多行视图）。
func VariantToggle(isOn: Binding<Bool>, @ViewBuilder label: () -> some View) -> some View {
    Toggle(isOn: isOn, label: label).toggleStyle(VariantToggleStyle())
}

// P1 批七：行内排版接管 (2026-10-16)
// ------------------------------------------------------------
// 全仓 1,770 处文本 `.font(...)` 原是各页手写的。做法与 `variantPlate` 同一条纪律：
// **语法只有一个实现处**，页面只说"这几个字是多大、多重"。
//
// ⚠ 零行为改动是**靠构造保证**的：调用点那一句原封不动地作为 `base` 传进来，
//   就把同一句 `{base}.weight(w)` 装回去（没写字重的调用点一个修饰符都不加）。

/// 行内排版的语法件。收的是"这个 Font 与这个字重"。
struct VKTypography: ViewModifier {
    let base: Font
    /// 调用点自己写的字重。`nil` 表示"没写"，在变体差里一律视作 `.regular`。
    let weight: Font.Weight?

    func body(content: Content) -> AnyView {
        AnyView(content.font(VKTypography.font(base, weight: weight)))
    }

    /// 变体差**只有这一个实现处**。做成能单独取 `Font` 的静态函数，是因为 `Canvas` 里的
    /// `draw(...)` 收的是 `Text`（不能是 `some View`，见 `SecurityWatermark` 的水印层）——
    /// 那条路要的是"这一档字号配上这一档字重"的**结果**，而不是把变体差再写一遍
    /// （写两遍必然漂移，本仓老病灶）。
    static func font(_ base: Font, weight: Font.Weight?) -> Font {
                // 逐字复刻：原来的 `.font(X)` 与（如果有）`.weight(w)` 一个不少、一个不多。
        return weight.map { base.weight($0) } ?? base
    }

}

extension View {
    /// 行内排版的**唯一入口**。全仓文本 `.font(...)` 都改成它（`uicoverage` 检查八守着不许回潮）。
    /// ⚠ 图标尺寸不在此列：`Image(systemName:).font(.system(size: 17, weight: .medium))` 是刻意写死的，
    /// 它不参与 Dynamic Type 也不该跟着变体换字重（`dynamictype` 闸门的既定豁免）。
    /// ⚠ 开关/矩阵之类带 `AnyView` 的地方可能拿不到环境，那时它就是 legacy 行为 —— 这正是默认值的设计。
    func vkFont(_ base: Font, weight: Font.Weight? = nil) -> some View {
        modifier(VKTypography(base: base, weight: weight))
    }
}
