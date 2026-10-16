import SwiftUI

// ============================================================
// 变体语法层 (Variant Grammar) —— 2026-10-16
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
    let variant: UIVariant

    /// 当前变体的语法。读 `app.uiVariant` 的调用方应显式传进来；
    /// 这个静态入口是给拿不到 AppState 的叶子视图兜底用的（存储是唯一真源）。
    static var current: VK { VK(variant: UIVariant.current) }

    // MARK: - 令牌

    var accent: Color {
        switch variant {
        case .legacy: return DS.Palette.text          // 现行：品牌色由 DS 的 accent 通道给，这里不抢
        case .core:   return DS.VariantPalette.coreA
        case .gauge:  return DS.VariantPalette.gaugeAmber
        }
    }

    var canvas: Color {
        switch variant {
        case .legacy: return DS.Palette.canvasBase
        case .core:   return DS.VariantPalette.coreCanvas
        case .gauge:  return DS.VariantPalette.gaugeCanvas
        }
    }

    var bezel: Color {
        switch variant {
        case .legacy: return DS.Palette.surfaceBase
        case .core:   return DS.Palette.surfaceBase.opacity(0.55)   // 锁核：半透玻璃，让极光透过来
        case .gauge:  return DS.VariantPalette.gaugeBezel           // 仪表：凹槽
        }
    }

    var hair: Color {
        switch variant {
        case .legacy: return DS.Palette.hairline
        case .core:   return DS.Palette.hairline                    // 零卡片定理：靠线分层
        case .gauge:  return DS.Palette.hairline
        }
    }

    var ink: Color   { DS.Palette.text }
    var sub: Color   { DS.Palette.textSub }
    var faint: Color { DS.Palette.textSub.opacity(0.82) }

    /// 页面左右边距。三套刻意不同 —— 这是"两套看着就不一样"最便宜的一处。
    var gutter: CGFloat {
        switch variant {
        case .legacy: return DS.Space.gutter            // 16 标准
        case .core:   return 30                          // 锁核要呼吸，主角才立得住
        case .gauge:  return 22                          // 仪表盘面：比标准紧，比锁核松
        }
    }

    var corner: CGFloat {
        switch variant {
        case .legacy: return DS.Radius.card              // 22 档，跟随 kf_radius
        case .core:   return 0                            // 零卡片定理：容器不靠圆角，见 container()
        case .gauge:  return 14                           // 机加工窗格的倒角，小且确定
        }
    }

    /// 主表面容器。**`Card` 的全部 53 处调用都走这里** —— 一处改动让两套在首屏以下真正分开，
    /// 而不是去 53 个调用点各改一遍（那既是"同一个量算两次"，也是漏改的温床）。
    ///
    /// `.legacy` 分支是 `LockKeeperApp.swift` 里原 `Card.body` **逐字搬过来的**，
    /// 一个像素都不该变：「默认值 = 零行为改动」这条承诺靠"把代码搬过来"保证，
    /// 而不是靠"照着再写一份"—— 后者一定会在某个间距上写错。
    func card<Content: View>(tint: Color? = nil, @ViewBuilder _ content: () -> Content) -> AnyView {
        // 用 Optional 而不是拿 Color 比相等：`tint == .clear` 依赖 Color 的 Equatable 实现，
        // 而它比较的是色彩值 —— 语义上"没染色"的写法一变（.clear / Color.white.opacity(0)）就判错。
        let wash = tint ?? Color.clear
        switch variant {
        case .legacy:
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
        case .core:
            // 零卡片定理：不画任何盒子，分组靠**一根两端淡出的发丝线**分开。
            // 语义色（低电/告警）不丢 —— 从"整张卡洗一层色"改成**把那根线本身染成告警色**：
            // 盒子没了，"这一组是告警色"还在，而且比 14% 洗底更显式。
            return AnyView(
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    rule(tint: tint)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.l)
                .padding(.horizontal, gutter)
            )
        case .gauge:
            // 仪表语法：凹槽窗台 —— 下凹的底 + 顶亮边 + 细描边。是仪器上的一块窗格，不是浮起来的卡片，
            // 所以**没有投影**（阴影靠假装浮起，凹槽是往里陷的；两者不能混用）。
            return AnyView(
                VStack(alignment: .leading, spacing: DS.Space.m) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.l)
                    .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(bezel))
                    .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(wash))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(hair.opacity(0.85), lineWidth: 0.7)
                    )
                    .padding(.horizontal, max(0, gutter - DS.Space.l))
            )
        }
    }

    /// core 那根分组线：默认是发丝色，带语义色时整根染过去。
    @ViewBuilder private func rule(tint: Color?) -> some View {
        let c = tint ?? hair
        LinearGradient(colors: [.clear, c, c, .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 0.7)
            .padding(.bottom, DS.Space.m)
            .accessibilityHidden(true)
    }

    /// 分区标题。**21 处 `SectionTitle` 全走这里。** legacy 分支逐字搬自原实现。
    func sectionTitle(text: String, count: Int?) -> AnyView {
        switch variant {
        case .legacy:
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
        case .core:
            // 锁核的分区语法：大写加宽字距的小字 + 一根拖到行尾的发丝线。
            // 品牌竖标换掉是有意的 —— 它是"给标题加个装饰件"，而这套的层级只由字号台阶与线承担。
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(text.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(faint)
                    if let count {
                        Text("\(count)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                    }
                    hairline().frame(height: 0.7)   // 剩下的行宽由线吃掉
                }
                .accessibilityElement(children: .combine)
            )
        case .gauge:
            // 仪表的分区语法：铭牌感 —— 小字大写 + 一条短的刻线，不拖满整行。
            return AnyView(
                HStack(spacing: DS.Space.s) {
                    Text(text.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.8)
                        .foregroundStyle(sub)
                    Rectangle().fill(hair).frame(width: 22, height: 0.7)
                    if let count {
                        Text("\(count)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(accent)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            )
        }
    }

    /// 状态标签。**29 处 `StatusPill` 全走这里。**
    /// 三套都必须保住那条既有纪律：**颜色不作为唯一信息载体** ——
    /// 原实现的"图标形状 + 图标颜色"双通道在三个分支里都保留，不许为了简洁把图标删了只剩色。
    func statusPill(text: String, systemImage: String, tone: Color) -> AnyView {
        switch variant {
        case .legacy:
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
        case .core:
            // 零卡片：不画胶囊底。语义靠"染色的图标形状 + 文字"两通道，色不是唯一载体。
            return AnyView(
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: systemImage)
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(tone)
                    Text(text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(sub)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            )
        case .gauge:
            // 仪表的指示灯语法：一颗灯 + 一块铭牌。灯不亮时也必须读得出状态，
            // 所以保留图标形状这一通道，不用色块代替文字。
            return AnyView(
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: systemImage)
                        .font(.system(size: DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(tone)
                    Text(text.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(sub)
                        .lineLimit(1)
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.vertical, DS.Space.xs)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(hair, lineWidth: 0.6))
                .fixedSize(horizontal: true, vertical: false)
            )
        }
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
        switch variant {
        case .legacy:
            return AnyView(
                content()
                    .padding(pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(bezel))
            )
        case .core:
            // 零卡片定理：不画任何圆角矩形。分组靠"上发丝线 + 字号台阶 + 留白"分开。
            return AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    if kind == .group { hairline().padding(.bottom, 2) }
                    content()
                }
                .padding(.vertical, kind == .inset ? 8 : pad)
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        case .gauge:
            // 仪表语法：凹槽 bezel + 顶亮边 + 细描边。是"仪器窗格"不是"卡片"。
            return AnyView(
                content()
                    .padding(pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(bezel))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(hair.opacity(0.8), lineWidth: 0.7)
                    )
            )
        }
    }

    // MARK: - 排版件

    /// 页面标题。
    func title(_ text: String) -> AnyView {
        switch variant {
        case .legacy:
            return AnyView(Text(text).font(.system(.headline, design: .default).weight(.semibold)).foregroundStyle(ink))
        case .core:
            return AnyView(Text(text)
                .font(.system(.title2, design: .default).weight(.semibold))
                .tracking(-0.75)
                .foregroundStyle(ink))
        case .gauge:
            return AnyView(Text(text)
                .font(.system(.caption, design: .default).weight(.semibold))
                .tracking(1.8)
                .foregroundStyle(sub))
        }
    }

    /// 分组小标签（大写加宽字距那一档）。
    func eyebrow(_ text: String) -> AnyView {
        AnyView(Text(text)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .tracking(1.6)
            .foregroundStyle(faint))
    }

    /// 大读数。**只有 gauge 允许把数字放到最大** —— 它是这套的主角。
    /// core 的主角是那枚核，所以它的读数退到次级；legacy 保持现行排版。
    /// ⚠ legacy 这一支刻意**不**复用 HeroStat：它的初始化器要 `systemImage/label/value`
    ///   (DesignSystem.swift:883)，而语法层这里只有"值 + 单位 + 来源"三样，凑不出图标名。
    ///   为了少写四行而硬套 HeroStat，就会变成"同一个组件两个调用形状"——不如直接排。
    func metric(value: String, unit: String, source: String) -> AnyView {
        switch variant {
        case .legacy:
            return AnyView(
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(unit).font(.caption2).foregroundStyle(sub)
                    }
                    .foregroundStyle(ink)
                    Text(source).font(.system(.caption2, design: .default)).foregroundStyle(faint)
                })
        case .core:
            return AnyView(
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value).font(.system(.largeTitle, design: .default).weight(.regular)).tracking(-1.2).monospacedDigit()
                        Text(unit).font(.system(.callout, design: .default)).foregroundStyle(sub)
                    }
                    .foregroundStyle(ink)
                    Text(source).font(.system(.caption2, design: .monospaced)).tracking(0.6).foregroundStyle(faint)
                })
        case .gauge:
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value)
                            .font(.system(.largeTitle, design: .monospaced).weight(.light))
                            .tracking(-3.2)
                            .monospacedDigit()
                        Text(unit).font(.system(.title3, design: .monospaced)).foregroundStyle(sub)
                    }
                    .foregroundStyle(accent)
                    // 来源必须跟着读数走：没有出处的数字就是断言。仪表这套尤其吃这一条。
                    Text(source).font(.system(.caption2, design: .monospaced)).tracking(1.2).foregroundStyle(faint)
                })
        }
    }

    func rowTitle(_ text: String) -> AnyView {
        AnyView(Text(text).font(.system(.body, design: .default).weight(.medium)).foregroundStyle(ink))
    }

    func rowSub(_ text: String) -> AnyView {
        AnyView(Text(text).font(.system(.footnote, design: .default)).foregroundStyle(faint))
    }

    // MARK: - 控件

    func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> AnyView {
        let shape: AnyView
        switch variant {
        case .legacy:
            shape = AnyView(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        case .core:
            shape = AnyView(Capsule())                      // 唯一的胶囊：主动作，不是容器
        case .gauge:
            shape = AnyView(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        return AnyView(
            Button(action: action) {
                Text(title)
                    .font(.system(.body, design: .default).weight(.semibold))
                    .tracking(variant == .gauge ? 1.2 : 0.4)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(shape.fill(enabled ? accent : DS.Palette.hairline))
                    // 不许写 Color.white —— swiftlint 那条"写死纯白前景"的闸门抓的就是这个，
                    // 而且它的名单是上限、只能减不能加。走主题表的 onAccent：
                    // 浅档白字、深档墨字，且 contrast.js 已断言它对主按钮渐变两端 ≥4.5:1。
                    .foregroundStyle(variant == .gauge ? DS.VariantPalette.gaugeOnAmber
                                                       : DS.Palette.themed("onAccent"))
                    .opacity(enabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        )
    }
}

// ============================================================
// 两套变体各自的"场"（页面底色）
// ============================================================

/// core：极光场。三团漂移光 + 一层压暗的 veil。
///
/// ⚠ 不透明度 0.414 是**算出来的上限**，不是审美取值：
///   `contrast-check.js` 反解出深色零余量上限 0.482，取 86% = 0.414 留余量；
///   再亮，压在它上面的文字就跌破 4.5:1。改这个数必须回去重跑那把尺子。
///
/// 降级：reduceMotion 关掉漂移（场还在，只是不动）；reduceTransparency / AMOLED /
/// 智能反转 三档一律退回纯色 —— 与 `dsScreenBackground` 现行那三档判据同源，不另立标准。
struct CoreAuroraBackground: View {
    @State private var drift = false

    // 三团的色相取自原型 (#4338CA 靛 / #0891B2 青 / #6D28D9 紫)。
    // 自我批评保留在这里：这组紫蓝弥散正是"AI/开发者工具"的品类默认模板，
    // 两轮独立评审认定深色首页构图是这组里最有辨识度的部分才留下；换色要连带重解对比度上限。
    private static let blobs: [(color: Color, x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (Color.adaptive(0x4338CA, 0x4338CA), 0.22, 0.10, 0.85),
        (Color.adaptive(0x0E7490, 0x0891B2), 0.86, 0.38, 0.70),
        (Color.adaptive(0x6D28D9, 0x6D28D9), 0.45, 0.88, 0.95)
    ]

    var body: some View {
        let calm = AXFlags.reduceMotion
        ZStack {
            DS.VariantPalette.coreCanvas
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ForEach(0..<CoreAuroraBackground.blobs.count, id: \.self) { i in
                    let b = CoreAuroraBackground.blobs[i]
                    let dx: CGFloat = calm ? 0 : (drift ? 0.09 : -0.06)
                    let dy: CGFloat = calm ? 0 : (drift ? 0.11 : -0.05)
                    RadialGradient(colors: [b.color.opacity(0.85), b.color.opacity(0.28), .clear],
                                   center: .center, startRadius: 0,
                                   endRadius: max(w, h) * b.size * 0.5)
                        .frame(width: w * b.size, height: h * b.size * 0.7)
                        .position(x: w * b.x + w * dx, y: h * b.y + h * dy)
                        .blur(radius: 52)
                }
            }
            // veil: 中心透明、四周压暗，让文字有可用的最坏背景
            RadialGradient(colors: [.clear, DS.VariantPalette.coreCanvas.opacity(0.72)],
                           center: .init(x: 0.5, y: 0.62), startRadius: 90, endRadius: 620)
        }
        .opacity(0.414)
        .ignoresSafeArea()
        .onAppear {
            guard !AXFlags.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 23).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }
}

/// gauge：夜门厅的一盏顶光。不是渐变矩形，是一盏灯照在盘面上。
/// 同样三档降级（AMOLED / 反转 / 降透明）退回纯色，理由与 legacy 那三档完全同源。
struct GaugeLampBackground: View {
    var body: some View {
        ZStack {
            DS.VariantPalette.gaugeCanvas
            RadialGradient(colors: [DS.VariantPalette.gaugeAmber.opacity(0.20),
                                    DS.VariantPalette.gaugeAmber.opacity(0.05), .clear],
                           center: .init(x: 0.5, y: -0.06), startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// ============================================================
// 目的地缝
// ============================================================

/// 每个目的地视图挂上它，就同时拿到三件事：
///   1. 当前变体的页面底色与边距 —— 一致性由这里下发，不由各页自己写；
///   2. 一次**到达记账**（VisitLedger）—— 完整性由真机点出来的数据证明；
///   3. 一个可被 tools/uicoverage.js 数的标记 —— 没挂缝的目的地会被点名。
struct DestinedModifier: ViewModifier {
    let destination: Destination

    /// 刻意**不**用 `@EnvironmentObject var app: AppState` 取变体。
    /// 缝要挂到 77 个页面上，其中不乏由第三方容器 / Widget 扩展 / Intent 回调路径呈现的叶子视图 ——
    /// 那些环境里不一定注入了 AppState，而 `@EnvironmentObject` 缺失是**运行时崩溃**，
    /// 不是编译错误，也不是我这轮能验出来的东西。
    /// 存储键 `kf_ui_variant` 本来就是唯一真源（setUIVariant 先写存储再镜像），
    /// 这里直接读它，少一层依赖就少一类崩法。
    func body(content: Content) -> some View {
        let v = UIVariant.current
        // legacy 必须**逐字不变**。它是默认值，也是用户此刻正在用的那套界面 ——
        // "默认值 = 零行为改动"这条承诺，一旦因为缝里加了 frame/background 就作废了。
        // 我第一版就犯了这条：`.frame(maxWidth:.infinity, alignment:.leading)` 会把
        // 现行页面里居中的根内容改成左对齐。所以 legacy 分支只记账，不加任何修饰。
        // 记账照做：完整性台账要的就是"这一站被到达过"，与变体无关。
        if v == .legacy {
            return content.onAppear { VisitLedger.note(destination, variant: v) }
                .eraseToAnyView()
        }
        let vk = VK(variant: v)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(vk.canvas.ignoresSafeArea())
            .onAppear { VisitLedger.note(destination, variant: v) }
            .eraseToAnyView()
    }
}

private extension View {
    /// DestinedModifier 的两条分支返回类型不同，必须擦成同一个。
    /// 这里 AnyView 是必需的，不是偷懒：不擦就得把 body 写成 `@ViewBuilder` 的两分支，
    /// 而两条分支的类型不同正是我们要的（legacy 完全不加修饰）。
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

extension View {
    /// 挂上目的地缝。**这是两套 UIUX 唯一的分叉下发点**，页面内部不许再自己挑底色/边距/容器。
    func destined(_ d: Destination) -> some View {
        modifier(DestinedModifier(destination: d))
    }
}

// ============================================================
// 完整性读数
// ============================================================

/// 当前变体的到达读数。放在设置页"外观"节里，紧挨着变体切换器 ——
/// 因为这两个东西必须一起看：切到一套新界面之后，**还差哪几站**是这套界面的真实状态。
///
/// 为什么不是把 77/77 写进文档当结论：静态闸门只能证明"每个目的地都挂了缝"，
/// 证明不了"真机上真的走得通"。这一行把后者变成可核对的数字与清单。
struct VariantCoverageRow: View {
    @EnvironmentObject private var app: AppState
    @State private var tick = 0

    private var cov: (done: Int, total: Int) { VisitLedger.coverage(app.uiVariant) }
    private var missing: [Destination] { VisitLedger.missing(app.uiVariant) }

    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("这套已到达")
                Spacer()
                Text("\(cov.done) / \(cov.total)")
                    .monospacedDigit()
                    .foregroundStyle(cov.done >= cov.total ? DS.Palette.ok : DS.Palette.warn)
            }
            .font(.callout)
            if !missing.isEmpty {
                DisclosureGroup("未到达 \(missing.count) 站") {
                    // 只列名字，不做成按钮：这一列是"还差哪几站"的**证据**，
                    // 给它们配一个跳过去的动作会假装"点了就算测过"，而缺的往往是入口本身。
                    ForEach(missing.prefix(40)) { d in
                        Text(d.rawValue).font(.footnote)
                    }
                    if missing.count > 40 {
                        Text("其余 \(missing.count - 40) 站见诊断页").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("全部到达过").font(.footnote).foregroundStyle(.secondary)
            }
            Button("清空这套的到达记录") {
                VisitLedger.clearVariant(app.uiVariant)
                tick &+= 1
            }
            .font(.footnote)
        }
    }
}


/// 本机记录"每个变体各自到达过哪些目的地"。
///
/// 为什么是运行时而不是静态分析：77 个目的地绝大多数由宿主视图的本地 @State 呈现
/// （`.sheet(item:)` / `NavigationLink` 带闭包），静态可达性分析要么做不准、要么得把
/// 全部状态提升 —— 两条路在没有编译器的情况下都是盲写。
/// 运行时记账的代价是要真机点一遍，但它给出的是**事实**而不是推断，
/// 而且一次点完就能精确列出"这一版还差哪几站"。
enum VisitLedger {
    private static let key = "kf_visit_ledger"

    struct Row: Codable, Equatable {
        let variant: String     // UIVariant.rawValue
        let dest: String        // Destination.rawValue (= View 类型名)
        let at: Double          // epoch 秒
    }

    private static var cache: [Row] = []
    private static var loaded = false

    private static func load() -> [Row] {
        if loaded { return cache }
        cache = DB.store.get([Row].self, key) ?? []
        loaded = true
        return cache
    }

    /// 记账。同一个 (变体, 目的地) 只留首次时间，避免每次 onAppear 都写盘。
    static func note(_ d: Destination, variant: UIVariant) {
        var rows = load()
        let v = variant.rawValue
        if rows.contains(where: { $0.variant == v && $0.dest == d.rawValue }) { return }
        rows.append(Row(variant: v, dest: d.rawValue, at: Date().timeIntervalSince1970))
        cache = rows
        DB.store.setCodable(key, rows)
    }

    /// 某个变体到达过的目的地集合。
    static func reached(_ variant: UIVariant) -> Set<String> {
        Set(load().filter { $0.variant == variant.rawValue }.map { $0.dest })
    }

    /// 还差哪几站。按 Destination 声明序返回，便于逐条施工。
    static func missing(_ variant: UIVariant) -> [Destination] {
        let got = reached(variant)
        return Destination.allCases.filter { !got.contains($0.rawValue) }
    }

    static func coverage(_ variant: UIVariant) -> (done: Int, total: Int) {
        (reached(variant).count, Destination.allCases.count)
    }

    /// 清空**当前这一套**的到达记录，另一套不动。
    /// 分变体清是必需的：两套共用一张表，"清空"如果全清，就等于把另一套已经走通的证据一起抹了。
    static func clearVariant(_ v: UIVariant) {
        cache = load().filter { $0.variant != v.rawValue }
        loaded = true
        DB.store.setCodable(key, cache)
    }

    static func clear() {
        cache = []
        loaded = true
        DB.store.remove(key)
    }
}
