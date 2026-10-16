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
        case .core:   return DS.Palette.coreA
        case .gauge:  return DS.Palette.gaugeAmber
        }
    }

    var canvas: Color {
        switch variant {
        case .legacy: return DS.Palette.canvasBase
        case .core:   return DS.Palette.coreCanvas
        case .gauge:  return DS.Palette.gaugeCanvas
        }
    }

    var bezel: Color {
        switch variant {
        case .legacy: return DS.Palette.surfaceBase
        case .core:   return DS.Palette.surfaceBase.opacity(0.55)   // 锁核：半透玻璃，让极光透过来
        case .gauge:  return DS.Palette.gaugeBezel           // 仪表：凹槽
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

    /// **平铺档**（CORE.md §3）：三光点摊成三行带字条目那一档。
    /// 触发条件是系统减弱动态 **且** 降低透明度 —— 两者同时开时，靠“位移/淡入淡出”说话的
    /// 导航已经完全传不出信息，必须换成静态带字的形式。
    /// 把判据写在这里而不是散在各视图里：它是**一个**开关（CORE.md §6.3 的“降档不许换容器语法”
    /// 能立住，就靠它只有一个读点）。
    static var flatTier: Bool { AXFlags.reduceMotion && AXFlags.reduceTransparency }

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
                    .foregroundStyle(variant == .gauge ? DS.Palette.gaugeOnAmber
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
            DS.Palette.coreCanvas
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
            RadialGradient(colors: [.clear, DS.Palette.coreCanvas.opacity(0.72)],
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
            DS.Palette.gaugeCanvas
            RadialGradient(colors: [DS.Palette.gaugeAmber.opacity(0.20),
                                    DS.Palette.gaugeAmber.opacity(0.05), .clear],
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
            // 控件色：`tint` 走环境，所以这**一行**同时改掉全仓 120 处 Toggle、滑杆、选择器、链接的
            // 高亮色（显式自设 tint 的调用点不受影响 —— 显式优先）。
            // 这一行是"整页都变了"的一半：另一半是各页自己调 `.variantList()` 换清单骨架。
            .tint(vk.accent)
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
// P1 批一：自绘底衬接进语法层 (2026-10-16)
// ------------------------------------------------------------
// uicoverage 检查五数出 176 处"自己画盒子"。它们**不是同一个东西**，不能一把梭：
//   · 装饰性中性底衬（信息胶囊 / 静态分组块 / 只读信息格）→ 该由变体决定长什么样；
//   · 带状态语义的底衬（开关轨道 / 进度空槽 / 选中态 / 校验提示条）→ 变体**不许动它**：
//     core 把它的底去掉，就等于把"开着还是关着"这个信息去掉 —— 那是功能缺陷，不是风格。
// 这一批只收前者，而且只收 legacy 能**逐字复刻**的写法：
// `variantPlate` 的 legacy 分支就是改造前那一句 `background(style, in: shape)` ——
// 同一个调用、同一个形状，像素不可能变。「默认值 = 零行为改动」这条承诺靠这个构造兑现，
// 而不是靠"照着重写一遍"（后者一定会在某个圆角上写错）。
// 一次只收一批，收完把 fixtures/uicoverage/budget.json 的基线降到新数（只许降）。
// ============================================================

/// 底衬的形状档。**故意不是 `Shape` 泛型**：调用点若还留着一句 `in: Capsule()`，
/// tools/uicoverage.js 的自绘容器预算（只认字面 token）就数不到这次迁移，
/// 迁移进度会看起来没动 —— 预算得能反映事实，形状就得以令牌形式传进来。
enum PlateShape {
    case capsule    // 信息胶囊
    case tile       // 瓦片 (DS.Radius.tile)
    case control    // 控件 / 内嵌格 (DS.Radius.control)

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
        switch VK.current.variant {
        case .legacy:
            let base = AnyView(self.background(style, in: shape.legacy))
            guard let edge else { return base }
            return AnyView(base.overlay { shape.legacyEdge(edge, 0.5) })
        case .core:
            // 零卡片定理：装饰性底衬整块去掉，内容原样留下 —— 与 VK.container 的 core 分支同一套语法
            // （分组层级由字号台阶和两端淡出的发丝线承担，不由盒子承担）。
            // 连描边一起去掉：只剩一圈线的容器仍然是"盒子"。
            // 这不是"凑数分支"："不画底"就是这套界面对装饰性底衬的完整定义。
            return AnyView(self)
        case .gauge:
            // 仪器窗格：中性底衬换成凹槽 bezel + 小倒角，与 VK.container 的 gauge 分支同源。
            let base = AnyView(self.background(RoundedRectangle(cornerRadius: VK.current.corner, style: .continuous).fill(VK.current.bezel)))
            guard let edge else { return base }
            return AnyView(base.overlay(RoundedRectangle(cornerRadius: VK.current.corner, style: .continuous).strokeBorder(edge, lineWidth: 0.7)))
        }
    }

    /// 带语义色的提示块（告警 / 成功 / 强调 / 危险）。**它和 `variantPlate` 不是一类东西**：
    /// `variantPlate` 收的是装饰性底衬，core 里整块去掉是对的；而提示块的那层洗色是**信息**
    /// （"这一段是告警"），core 去掉它就等于把这个信息去掉 —— 所以这里换的不是"去底"，是**换载体**：
    /// 洗底 → 左侧一根染色的线（与 `VK.card` 的 core 分支同一条纪律：盒子没了，语义色还在，而且更显式）。
    func variantCallout(_ tone: Color, _ shape: PlateShape, wash: Double) -> AnyView {
        switch VK.current.variant {
        case .legacy:
            // 逐字等于改造前那一句。
            return AnyView(self.background(tone.opacity(wash), in: shape.legacy))
        case .core:
            return AnyView(self
                .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: 2) }
                .padding(.leading, DS.Space.s))
        case .gauge:
            // 仪表：凹槽窗格 + 同一根 tone 色侧线。不靠整块洗色传达语义。
            return AnyView(self
                .background(RoundedRectangle(cornerRadius: VK.current.corner, style: .continuous).fill(VK.current.bezel))
                .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: 2) }
                .overlay(RoundedRectangle(cornerRadius: VK.current.corner, style: .continuous).strokeBorder(VK.current.hair.opacity(0.8), lineWidth: 0.7)))
        }
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
        switch VK.current.variant {
        case .legacy:
            // 逐字等于改造前那一句 —— 像素不可能变。
            return AnyView(self.scrollContentBackground(.hidden))
        case .core:
            // 零卡片定理：清单退成"只有字和线"的一张平面 —— 不内缩、不画行分隔线、节距拉开。
            // `.plain` 下 Section 标题也不再是 iOS 的分组样式，这正是这套要的"少一层盒子"。
            return AnyView(self
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .listSectionSpacing(CGFloat(30)))
        case .gauge:
            // 仪表：整幅分组的机加工盘面（`.grouped` 比 iOS 默认的 `.insetGrouped` 更满、更方），
            // 分隔线保留但染成发丝色、节距收紧 —— "一块块窗格"的读法。
            return AnyView(self
                .scrollContentBackground(.hidden)
                .listStyle(.grouped)
                .listRowSeparatorTint(DS.Palette.hairline)
                .listSectionSpacing(CGFloat(12)))
        }
    }
}

// MARK: - 按钮外形

// 为什么拆成三个函数而不是一个 `switch role`：
// 内层再套一层 switch 会让 tools/uicoverage.js 检查三的分支正则提前收尾（它会看见 `case .primary:`
// 当成 `case .legacy:` 的结束），于是**每个分支都被判成空壳**。三个函数各自只有一个 `switch variant`，
// 既能被检查三管到，也不会互相干扰。这是工具约束，不是审美选择。

extension VK {
    /// 主按钮外形。legacy 分支逐字搬自 `DesignSystem.swift` 原 `PrimaryActionStyle.makeBody`。
    func primaryActionChrome<Label: View>(fullWidth: Bool, pressed: Bool,
                                          @ViewBuilder _ label: () -> Label) -> AnyView {
        switch variant {
        case .legacy:
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
        case .core:
            // 零卡片定理：**不画实底胶囊** —— 主动作是一条被点亮的粗底线。
            // 该套里唯一的胶囊留给首页那枚核，按钮不再是"块"，是"一句话加一根线"。
            return AnyView(
                label()
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.vertical, DS.Space.m)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .frame(minHeight: DS.Hit.min + 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(accent).frame(height: 1.5) }
                    .opacity(pressed ? 0.55 : 1)
                    .animation(DS.Motion.quick, value: pressed)
            )
        case .gauge:
            // 仪表：一块上光的琥珀压板（磷光读数色）+ 机加工描边，字距拉开、等宽排版。
            return AnyView(
                label()
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(DS.Palette.gaugeOnAmber)
                    .padding(.vertical, DS.Space.m + 2)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .frame(minHeight: DS.Hit.min + 6)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [DS.Palette.gaugeAmber, DS.Palette.gaugeDeep],
                                             startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 0.6))
                    .opacity(pressed ? 0.88 : 1)
                    .scaleEffect(pressed ? 0.99 : 1)
                    .animation(DS.Motion.quick, value: pressed)
            )
        }
    }

    /// 次按钮外形。legacy 分支逐字搬自原 `SecondaryActionStyle.makeBody`。
    func secondaryActionChrome<Label: View>(fullWidth: Bool, pressed: Bool, tint: Color,
                                            @ViewBuilder _ label: () -> Label) -> AnyView {
        switch variant {
        case .legacy:
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
        case .core:
            // 零卡片：没有底色，只有一根发丝线收住这一行。
            return AnyView(
                label()
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(sub)
                    .padding(.vertical, DS.Space.s + 2)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .frame(minHeight: DS.Hit.min)
                    .overlay(alignment: .bottom) { Rectangle().fill(hair).frame(height: 0.7) }
                    .opacity(pressed ? 0.6 : 1)
                    .animation(DS.Motion.quick, value: pressed)
            )
        case .gauge:
            // 仪表：凹槽窗格底 + 细描边。与 VK.container 的 gauge 分支同源。
            return AnyView(
                label()
                    .font(.system(.subheadline, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(ink)
                    .padding(.vertical, DS.Space.s + 2)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .frame(minHeight: DS.Hit.min)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(bezel))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(DS.Palette.hairline, lineWidth: 0.6))
                    .opacity(pressed ? 0.85 : 1)
                    .animation(DS.Motion.quick, value: pressed)
            )
        }
    }

    /// 破坏性按钮外形。legacy 分支逐字搬自原 `DestructiveActionStyle.makeBody`。
    /// 三个变体都保住那条纪律：**破坏性必须靠颜色 + 文字两通道**，不许只靠色（色有时是唯一载体）。
    func destructiveActionChrome<Label: View>(pressed: Bool,
                                             @ViewBuilder _ label: () -> Label) -> AnyView {
        switch variant {
        case .legacy:
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
        case .core:
            return AnyView(
                label()
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(DS.Palette.danger)
                    .padding(.vertical, DS.Space.s + 2)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.danger).frame(height: 0.7) }
                    .opacity(pressed ? 0.6 : 1)
                    .animation(DS.Motion.quick, value: pressed)
            )
        case .gauge:
            return AnyView(
                label()
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(DS.Palette.danger)
                    .padding(.vertical, DS.Space.s + 2)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Hit.min)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(bezel))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(DS.Palette.danger.opacity(0.55), lineWidth: 0.8))
                    .opacity(pressed ? 0.85 : 1)
                    .animation(DS.Motion.quick, value: pressed)
            )
        }
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

/// core / gauge 的自绘开关面。`legacy` 不走这里。
private struct VariantToggleFace: View {
    @Binding var isOn: Bool
    let label: AnyView
    let gauge: Bool

    var body: some View {
        HStack(spacing: DS.Space.m) {
            label
            Spacer(minLength: DS.Space.m)
            track
        }
        .frame(minHeight: DS.Hit.min)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .animation(DS.Motion.quick, value: isOn)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { label }.toggleStyle(.switch)
        }
    }

    /// core：**没有轨道盒子**，只有一根 34pt 的线 + 一个沿线滑动的 9pt 点。
    /// 这是零卡片定理在控件上的同一条纪律 —— 状态由位置 + 染色两个通道给。
    /// gauge：凹槽窗格 + 机加工滑臂（窗格在这里不是装饰，是仪器基底，同 `variantCallout`）。
    @ViewBuilder
    private var track: some View {
        if gauge {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(VK.current.bezel)
                    // 凹槽**填充**与盘面只差 ~1.14:1 —— 这是"面不是控件"，故意不追 3:1；
                    // 控件的边界由这根 0.7pt 的描边承担（textSub 对盘面 5.63:1）。
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(DS.Palette.textSub, lineWidth: 0.7))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isOn ? DS.Palette.gaugeAmber : DS.Palette.textSub)
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 2)
            }
            .frame(width: 46, height: 22)
            .frame(height: DS.Hit.min)
            .contentShape(Rectangle())
        } else {
            ZStack(alignment: isOn ? .trailing : .leading) {
                // OFF 不能用 hairline（浅档 1.20:1）: 一根几乎看不见的线上挂一个几乎看不见的点,
                // "左还是右"读不出来。换成 textSub（≥4.96:1）—— WCAG 1.4.11 要 3:1,
                // 断言在 contrast.js G 节，量过再改。
                Rectangle()
                    .fill(isOn ? VK.current.accent : DS.Palette.textSub)
                    .frame(height: 1)
                Circle()
                    .fill(isOn ? VK.current.accent : DS.Palette.textSub)
                    .frame(width: 9, height: 9)
            }
            .frame(width: 34, height: DS.Hit.min)
            .contentShape(Rectangle())
        }
    }
}

/// 开关形状的实现。三 case 齐全（`uicoverage` 检查三按变体分叉就要求这个）。
/// ⚠ 返回类型写 `AnyView` 而不是 `some View` 是**为了被检查三覆盖**：那一支只扫 `-> AnyView {`
/// 的分叉函数（本文件的既定形状）。改成 `some View` 它就静默逃过穷尽性检查 —— 语法件越多漏得越多。
struct VariantToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> AnyView {
        switch VK.current.variant {
        case .legacy:
            return AnyView(
                Toggle(isOn: configuration.isOn) { configuration.label }
                    .toggleStyle(.switch))
        case .core:
            return AnyView(VariantToggleFace(isOn: configuration.isOn,
                                             label: AnyView(configuration.label),
                                             gauge: false))
        case .gauge:
            return AnyView(VariantToggleFace(isOn: configuration.isOn,
                                             label: AnyView(configuration.label),
                                             gauge: true))
        }
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

// ============================================================
// P1 批七：行内排版接管 (2026-10-16)
// ------------------------------------------------------------
// 「两套不同」的最后一块欠账不在容器上，在**行里那几个字怎么排**：
//   全仓 1,770 处文本 `.font(...)` 是各页手写的，两套变体在它们身上长得一模一样 ——
//   `CORE.md` §13.4 那条「还不算全新」说的就是这个。
//
// 为什么不是"给每页改一遍字号"：那是把同一套排版改两遍，两套必然漂移（本仓老病灶）。
// 做法与 `variantPlate` 同一条纪律：**语法只有一个实现处**，页面只说"这几个字是多大、多重"。
//
// ⚠ legacy 分支是**靠构造保证**的零行为改动，不是"照着再写一份"：
//   调用点那一句原封不动地作为 `base` 传进来，legacy 就把同一句 `{base}.weight(w)` 装回去
//   （没写字重的调用点一个修饰符都不加）。批一~批六都是这么做的，因为"照着重写"
//   一定会在某个圆角/某个字重上写错，而本机没有编译器替我盯。
//
// 变体差（都是**字重与字族**差，不动字号、不动字距）：
//   · core  —— 字重整体降一档（`nil` 视作 `.regular` ⇒ 设成 `.light`）：这一套的层级由
//              **字号对比**承担（`CORE.md` 公理 1：58pt/200 的超细 vs 9.5px 加宽标签），
//              字重必须让位，否则同一页会退化成"到处都半粗"的模板感。
//              下限 `.light`：再往下中文正文开始发虚。
//   · gauge —— 字重整体升一档（`nil` 视作 `.regular` ⇒ `.medium`）**并且整族等宽化**
//              （`base.monospaced()`）：仪表是机加工读数，笔画更实、字宽更齐。
//              ⚠ 封顶 `.semibold` 是硬约束：中文界面里 `.bold` 在 PingFang SC 上**没有 700 那一档**，
//              会静默回退成 Semibold（本仓 `dynamictype` 闸门规则 3 记过这条）。
//
// 为什么不管字距：字距在本仓是**显式写在调用点**的（`.tracking(...)` 那 28 处，全在两套新界面里）。
//   语法层再加一份就会叠成两倍。谁要接管字距，谁得先把那 28 处收上来 —— 那是下一批，
//   而这一批把"字号/字重/字族"这三件收了。
// ============================================================

/// 行内排版的语法件。收的是"这个 Font 与这个字重"，**长成什么样由当前变体决定**。
/// 读环境里的变体而不是 `VK.current`：`.font(...)` 有 1700+ 处调用点，
/// 逐处一次存储读取会把"零行为改动"变成"每帧几百次 DB 读取"（理由见 `UIVariantKey`）。
struct VKTypography: ViewModifier {
    let base: Font
    /// 调用点自己写的字重。`nil` 表示"没写"，在变体差里一律视作 `.regular`。
    let weight: Font.Weight?
    @Environment(\.uiVariant) private var variant

    func body(content: Content) -> AnyView {
        switch variant {
        case .legacy:
            // 逐字复刻：原来的 `.font(X)` 与（如果有）`.weight(w)` 一个不少、一个不多。
            return AnyView(weight.map { content.font(base.weight($0)) } ?? content.font(base))
        case .core:
            return AnyView(content.font(base.weight(VKTypography.down(weight ?? .regular))))
        case .gauge:
            return AnyView(content.font(base.monospaced().weight(VKTypography.up(weight ?? .regular))))
        }
    }

    /// 降一档，下限 `.light`。
    static func down(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .black: return .heavy
        case .heavy: return .bold
        case .bold: return .semibold
        case .semibold: return .medium
        case .medium: return .regular
        case .regular: return .light
        default: return .light          // .light/.thin/.ultraLight 已经够轻，不再往下降
        }
    }

    /// 升一档，上限 `.semibold`（`.bold` 在 PingFang SC 上会静默回退，所以封顶）。
    static func up(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .ultraLight: return .thin
        case .thin: return .light
        case .light: return .regular
        case .regular: return .medium
        default: return .semibold       // .medium 及以上一律封顶
        }
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
