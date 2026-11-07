// Modern.swift —— iOS 26 / iOS 27 新能力的统一入口（含**可用的**降级路径）。
//
// 纪律（本仓新增）：
//   · 每个新 API 只在这里出现一次，页面里不写 availability 判断；
//   · 每条分支都要有**能用的**降级路径 —— 不是「不崩」，是「照样能用」；
//   · 新系统上必须**真的生效**（不是写一句兼容判断就算数）。
//
// 本 App 的最低部署版本是 **iOS 26**：DAYLIGHT 的材质体系（Liquid Glass）就是 iOS 26 的
// 能力，工具链（Xcode 27.1）也不再接受更低的部署目标。
// 因此**分工**是：
//   · iOS 26 的能力 = 基线，直接用，不写分支（写分支只会得到「unnecessary check」告警）；
//   · iOS 27 的能力 = 分支 + **可用的**降级路径。
import SwiftUI

// MARK: - 玻璃组（iOS 26）

/// 一组相邻的玻璃件放进**同一个**渲染容器。
///
/// 为什么必须：玻璃采样的是**背后的真实内容**，而玻璃本身不是内容 ——
/// 不在一个容器里的两片相邻玻璃会各折各的，接缝处会花。
/// 系统自己的 Tab 栏、键盘就是这么做的。
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) { content() }
    }
}

// MARK: - 玻璃变形（iOS 26）

extension View {
    /// 给这层玻璃一个稳定身份：视图层级变化时，它会**morph** 成另一片玻璃。
    ///
    /// 必须和 `GlassEffectContainer` + `@Namespace` 一起用；
    /// 变形过渡挂在**被插入/移除的那一片**上（`glassMorphTransition`），不是常驻容器上。
    func glassMorphID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        self.glassEffectID(id, in: namespace)
    }

    /// 玻璃出现/消失时的过渡。
    ///
    /// `.matchedGeometry` 用于**近处**的两片玻璃（相邻、间距在容器内）；
    /// `.materialize` 用于远处插入/移除（淡入淡出 + 材质动画，不做几何匹配）。
    func glassMorphTransition(_ transition: GlassEffectTransition) -> some View {
        self.glassEffectTransition(transition)
    }
}

// MARK: - 系统玻璃按钮（iOS 26）

extension View {
    /// iOS 26+：用**系统**的玻璃按钮样式。
    ///
    /// 为什么用系统的而不是自绘：系统的按钮玻璃自带按压反馈、焦点环、
    /// 「减少透明度 / 增强对比度」下的正确退化，以及 VoiceOver 的按钮语义。
    /// 自绘玻璃只解决了视觉，没解决这些。
    ///
    /// - Parameter prominent: 主行动用 `.glassProminent`（实心强调玻璃）。
    /// - Parameter tint: 需要指定染色时用可配置样式（`Glass.regular.tint(_:)`）。
    @ViewBuilder
    func systemGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if prominent {
            self
                .buttonStyle(.glassProminent)
                .tint(tint ?? T.C.brass)
        } else if let tint {
            self.buttonStyle(.glass(.regular.tint(tint)))
        } else {
            self.buttonStyle(.glass)
        }
    }
}

// MARK: - 背景延展（iOS 26）

extension View {
    /// iOS 26+：背景在安全区边缘外**延展**（分屏 / 侧边栏时背景不被裁成一块）。
    ///
    /// 更早系统：背景照旧只铺到安全区内 —— 不延展，但也不裁内容。
    func extendBackground() -> some View {
        self.backgroundExtensionEffect()
    }
}

// MARK: - 滚动边缘（iOS 26）

extension View {
    /// 滚动到边缘时的**柔化**效果（iOS 26+）。
    ///
    /// 本 App 的浮岛 Tab 栏是**浮在内容之上**的：内容从它底下滚过时，
    /// 系统会自动在底边加一层柔化 —— 这正是浮动栏该有的样子。
    /// 更早系统没有这个效果，内容直接穿过栏（栏本身是玻璃，仍然可读）。
    func softScrollEdge(_ edges: Edge.Set) -> some View {
        self.scrollEdgeEffectStyle(.soft, for: edges)
    }
}

// MARK: - 标签栏（iOS 26 / iOS 27）

extension View {
    /// iOS 26+：向下滚动时收起标签栏。
    ///
    /// 更早系统：标签栏常驻 —— 少一个动效，不少功能。
    func minimizeTabBarOnScrollDown() -> some View {
        self.tabBarMinimizeBehavior(.onScrollDown)
    }
}

// MARK: - 导航过渡（iOS 26）

extension View {
    /// iOS 26+：把这块标记为导航过渡的**源** ——
    /// 弹层不再「凭空出现」，而是从这个按钮身上放大出来。
    ///
    /// 更早系统：普通视图（弹层照旧淡入）。
    func zoomTransitionSource(id: String, namespace: Namespace.ID) -> some View {
        self.navigationTransitionSource(id: id, namespace: namespace)
    }

    /// iOS 26+：把这块标记为导航过渡的**落点**（与源配对）。
    func zoomTransitionDestination(id: String, namespace: Namespace.ID) -> some View {
        self.navigationTransitionDestination(id: id, namespace: namespace)
    }
}

// MARK: - 工具栏（iOS 26 / iOS 27）

extension View {
    /// iOS 27+：工具栏的**溢出菜单**。
    ///
    /// 系统把这些动作放进导航栏的溢出菜单 —— 无论工具栏处于什么形态、
    /// 平台或可定制程度，它们**永远**待在溢出里，不会与主行动抢位置。
    /// 更早系统：内容由调用方放进工具栏末尾的下拉菜单（见 `overflowMenuFallback`）。
    @ViewBuilder
    func toolbarOverflowCompat(@ViewBuilder content: @escaping () -> some View) -> some View {
        if #available(iOS 27.0, *) {
            self.toolbarOverflowMenu { content() }
        } else {
            self
        }
    }
}

extension ToolbarContent {
    /// iOS 26 的降级：工具栏末尾的下拉菜单（内容与 iOS 27 的溢出菜单一致）。
    static func overflowMenuFallback(@ViewBuilder content: @escaping () -> some View) -> AnyToolbarContent {
        AnyToolbarContent(ToolbarItem(placement: .topBarTrailing) {
            Menu {
                content()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多操作")
        })
    }
}

extension ToolbarItemPlacement {
    /// iOS 27+：钉在后缘的放置位（空间再紧也留在原处）。
    /// 更早系统：普通的后缘放置位。
    static var thresholdPinnedTrailing: ToolbarItemPlacement {
        if #available(iOS 27.0, *) {
            return .topBarPinnedTrailing
        }
        return .topBarTrailing
    }
}

// MARK: - 轻扫容器（iOS 27）

extension View {
    /// iOS 27+：让容器里的行支持轻扫操作，并协调「一次只展开一行」。
    ///
    /// 没有它，`swipeActions` 挂在自绘容器（ScrollView / LazyVStack）的行上**什么也不会发生**。
    /// 更早系统没有轻扫这一说，页面另有长按菜单兜底。
    @ViewBuilder
    func iOS27SwipeContainer() -> some View {
        if #available(iOS 27.0, *) {
            self.swipeActionsContainer()
        } else {
            self
        }
    }
}

// MARK: - 轻扫操作（iOS 27）

extension View {
    /// 轻扫操作。
    ///
    /// iOS 27 起，`swipeActions` 不再只认 `List` 的行 —— 任何容器里的行都能用，
    /// 但**容器**必须挂 `swipeActionsContainer()`（见 `ScreenScroll`），
    /// 否则轻扫什么也不会发生。
    ///
    /// iOS 27 还加了带回调的重载：操作露出/收起时通知一次（可用来压暗那一行）。
    /// 更早系统只有「按钮」这一个重载 —— 回调那一路自动跳过。
    ///
    /// - Parameter onPresentationChanged: `true` = 操作已露出，`false` = 已收起。
    @ViewBuilder
    func swipeActionsCompat(edge: HorizontalEdge,
                            allowsFullSwipe: Bool = true,
                            onPresentationChanged: ((Bool) -> Void)? = nil,
                            @ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 27.0, *) {
            self.swipeActions(edge: edge,
                              allowsFullSwipe: allowsFullSwipe,
                              content: content,
                              onPresentationChanged: { onPresentationChanged?($0) })
        } else {
            self.swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, content: content)
        }
    }
}

// MARK: - 基于数据的弹窗（iOS 27）

extension View {
    /// 以**数据**驱动的提醒（iOS 27+：`alert(_:item:actions:message:)`）。
    ///
    /// iOS 27 之前，提醒与确认框都要**两个状态**：一个 Bool 说「弹不弹」，
    /// 一个可选值说「弹的是哪一个」—— 两者可能对不上（这是不可能状态）。
    /// iOS 27 起只留一个可选值：非空即弹出，关闭时系统自动把它清回 nil。
    ///
    /// 更早系统的降级：用 `isPresented` + `presenting` 复刻同一套语义
    /// （Bool 由 item 是否为 nil 推导，关闭时同样清空）—— 行为一致，只是仍要两段样板。
    @ViewBuilder
    func itemAlert<T, A: View, M: View>(_ title: String,
                                       item: Binding<T?>,
                                       @ViewBuilder actions: @escaping (T) -> A,
                                       @ViewBuilder message: @escaping (T) -> M) -> some View {
        if #available(iOS 27.0, *) {
            self.alert(Text(title), item: item, actions: actions, message: message)
        } else {
            self.alert(Text(title),
                       isPresented: Binding(
                           get: { item.wrappedValue != nil },
                           set: { if !$0 { item.wrappedValue = nil } }),
                       presenting: item.wrappedValue) { value in
                actions(value)
            } message: { value in
                message(value)
            }
        }
    }

    /// 以**数据**驱动的确认框（无说明文字）。
    @ViewBuilder
    func itemConfirmationDialog<T, A: View>(_ title: String,
                                            item: Binding<T?>,
                                            titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: @escaping (T) -> A) -> some View {
        if #available(iOS 27.0, *) {
            self.confirmationDialog(Text(title), item: item, titleVisibility: titleVisibility,
                                    actions: actions)
        } else {
            self.confirmationDialog(Text(title),
                                    isPresented: Binding(
                                        get: { item.wrappedValue != nil },
                                        set: { if !$0 { item.wrappedValue = nil } }),
                                    presenting: item.wrappedValue,
                                    titleVisibility: titleVisibility) { value in
                actions(value)
            }
        }
    }

    /// 以**数据**驱动的确认框（iOS 27+：`confirmationDialog(_:item:titleVisibility:actions:)`）。
    @ViewBuilder
    func itemConfirmationDialog<T, A: View, M: View>(_ title: String,
                                                    item: Binding<T?>,
                                                    titleVisibility: Visibility = .automatic,
                                                    @ViewBuilder actions: @escaping (T) -> A,
                                                    @ViewBuilder message: @escaping (T) -> M) -> some View {
        if #available(iOS 27.0, *) {
            self.confirmationDialog(Text(title), item: item, titleVisibility: titleVisibility,
                                    actions: actions, message: message)
        } else {
            self.confirmationDialog(Text(title),
                                    isPresented: Binding(
                                        get: { item.wrappedValue != nil },
                                        set: { if !$0 { item.wrappedValue = nil } }),
                                    presenting: item.wrappedValue,
                                    titleVisibility: titleVisibility) { value in
                actions(value)
            } message: { value in
                message(value)
            }
        }
    }
}
