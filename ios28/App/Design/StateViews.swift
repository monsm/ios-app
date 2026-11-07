// StateViews.swift —— 状态渲染层（F37/F38/F39/F41/F42/F43/F32/F34）。
//
// 这一层只负责「把一个 ScreenState 画出来」，不负责取数据。
// 页面写 `StateSection(state: ..., empty: ...)`，不用再各写各的 if/switch。
//
// 画法纪律：
//   · 骨架屏按**真实布局**画（占位块的形状贴着内容），不用居中转圈。
//   · 陈旧数据不藏起来 —— 显示「上次读取 N 前」+ 一键刷新，但**照常可读**。
//   · 失败卡永远给得出下一步；给不出就别占这个位置。
import SwiftUI

// MARK: - 骨架

/// 骨架块。尺寸由调用方给 —— 它贴着真实内容的形状走。
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 6
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(T.C.hair)
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(T.C.glassEdge.opacity(0.5))
                    .offset(x: shimmer ? 60 : -60)
                    .blur(radius: 6)
            }
            .clipped()
            .opacity(shimmer ? 0.9 : 0.55)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shimmer)
            .onAppear { shimmer = true }
            .accessibilityHidden(true)
    }
}

/// 一屏的骨架：读数三格 + 两行列表。
struct ScreenSkeleton: View {
    var rows: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: T.S.m) {
            HStack(spacing: 0) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 34, height: 9, radius: 4)
                        SkeletonBlock(width: 52, height: 18, radius: 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, T.S.m)
            ForEach(0 ..< rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(width: 40, height: 40, radius: 18)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 120, height: 12, radius: 6)
                        SkeletonBlock(width: 80, height: 10, radius: 5)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, T.S.m)
    }
}

// MARK: - 陈旧徽标

/// 「上次读取 N 前」+ 一键刷新。数据照常可读 —— 只是别让它冒充实时。
struct StaleBadge: View {
    var at: Int64
    var refresh: (() -> Void)? = nil
    var busy: Bool = false

    private var text: String {
        let stamp = When.ago(at)
        return stamp.isEmpty ? "数据可能是旧的" : "上次读取 · \(stamp)"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(T.C.ink3)
                .accessibilityHidden(true)
            Text(text)
                .type(T.F.caption)
                .foregroundStyle(T.C.ink3)
            if let refresh {
                Button(action: refresh) {
                    Text(busy ? L("common.loading") : L("common.refresh"))
                        .type(T.F.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(T.C.brass)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityHint("重新从门锁读取")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(T.C.hair, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 失败卡

/// 失败描述。**永远给得出下一步**；给不出时 detail 也要说清楚为什么。
struct FailureCard: View {
    var failure: ScreenFailure
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: failure.mayHaveExecuted ? "exclamationmark.triangle" : "exclamationmark.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(failure.mayHaveExecuted ? T.C.danger : T.C.danger)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.title)
                        .type(T.F.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(T.C.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !failure.detail.isEmpty {
                        Text(failure.detail)
                            .type(T.F.caption)
                            .foregroundStyle(T.C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let next = failure.next {
                Text(next)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.leading, 23)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry, failure.canRetry {
                TextAction(title: L("common.retry")) { retry() }
                    .padding(.leading, 23)
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 部分成功：主体成功了，但有一步没成。**必须单独呈现** ——
/// 混进「成功」里，用户会以为整件事都成了。
struct PartialSuccessCard: View {
    var title: String
    var failure: ScreenFailure
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(T.C.ok)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .type(T.F.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(T.C.ink)
                    Text(failure.title)
                        .type(T.F.caption)
                        .foregroundStyle(T.C.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let next = failure.next {
                Text(next)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .padding(.leading, 23)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry, failure.canRetry {
                TextAction(title: L("common.retry")) { retry() }
                    .padding(.leading, 23)
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 权限提示

/// 权限缺失：页内说明 + 跳系统设置。不用弹窗砸用户。
struct PermissionNotice: View {
    var symbol: String = "hand.raised"
    var title: String
    var detail: String
    var openSettings: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(T.C.brass)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .type(T.F.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.ink)
                Text(detail)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let openSettings {
                    TextAction(title: "去系统设置") { openSettings() }
                }
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 进度

/// 长任务进度。**不知道百分比就不画百分比** —— 只写「在跑」和第几步。
struct ProgressMeter: View {
    var progress: TaskProgress
    var cancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(T.C.brass)
                Text(progress.title)
                    .type(T.F.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.ink)
                Spacer(minLength: 8)
                if progress.cancellable, let cancel {
                    TextAction(title: L("common.cancel")) { cancel() }
                }
            }
            if !progress.detail.isEmpty {
                Text(progress.detail)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let step = progress.stepText {
                Text(step)
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
            if let f = progress.fraction {
                ProgressView(value: min(max(f, 0), 1))
                    .tint(T.C.brass)
            }
        }
        .padding(.vertical, T.S.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.title)
    }
}

// MARK: - 空态母题

/// 空态的矢量母题：一个「光从窗口进来」的抽象形。
/// 每个域一个变体，让空屏也认得出这是哪一块。
enum EmptyMotif: String {
    case door
    case key
    case clock
    case person
    case lock

    var tint: Color {
        switch self {
        case .door: return T.C.brass
        case .key: return T.C.ink2
        case .clock: return T.C.ink2
        case .person: return T.C.ink2
        case .lock: return T.C.ink2
        }
    }
}

struct EmptyMotifView: View {
    var motif: EmptyMotif = .door
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            // 一道光：斜的矩形，模糊，当作「窗缝里的日光」。
            Rectangle()
                .fill(LinearGradient(colors: [.clear, motif.tint.opacity(0.35), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.28, height: size * 1.2)
                .rotationEffect(.degrees(18))
                .blur(radius: 6)
            // 门槛：一条实线。
            Rectangle()
                .fill(motif.tint.opacity(0.5))
                .frame(width: size * 0.86, height: 1)
                .offset(y: size * 0.34)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 统一状态渲染

/// 把一个 ScreenState 画出来。页面只声明状态，不写分支。
///
/// `EmptyContent` 单独一个泛型参数：空态与有数据态的视图类型通常不同
/// （空态是一段文字 + 一个动作，有数据态是一张表），硬合成一个类型会把调用处
/// 逼成 `AnyView`。不传空态时用 `EmptyView`。
struct StateSection<Value, Content: View, EmptyContent: View>: View {
    var state: ScreenState<Value>
    /// 空态时画什么。
    var empty: EmptyContent
    var skeleton: ScreenSkeleton?
    var refresh: (() -> Void)? = nil
    var busy: Bool = false
    @ViewBuilder var content: (Value) -> Content

    init(state: ScreenState<Value>,
         empty: EmptyContent,
         skeleton: ScreenSkeleton? = nil,
         refresh: (() -> Void)? = nil,
         busy: Bool = false,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.state = state
        self.empty = empty
        self.skeleton = skeleton
        self.refresh = refresh
        self.busy = busy
        self.content = content
    }

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            skeleton ?? ScreenSkeleton()
        case .data(let v):
            content(v)
        case .stale(let v, let at):
            VStack(alignment: .leading, spacing: T.S.s) {
                StaleBadge(at: at, refresh: refresh, busy: busy)
                content(v)
            }
        case .empty:
            empty
        case .failed(let f):
            FailureCard(failure: f, retry: refresh)
        case .partlyDone(let v, let f):
            VStack(alignment: .leading, spacing: T.S.s) {
                PartialSuccessCard(title: "已完成一部分", failure: f, retry: refresh)
                content(v)
            }
        }
    }
}

extension StateSection where EmptyContent == EmptyView {
    /// 这一屏没有「空」这个概念（例如状态页永远有内容）。
    init(state: ScreenState<Value>,
         skeleton: ScreenSkeleton? = nil,
         refresh: (() -> Void)? = nil,
         busy: Bool = false,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.init(state: state, empty: EmptyView(), skeleton: skeleton,
                  refresh: refresh, busy: busy, content: content)
    }
}
