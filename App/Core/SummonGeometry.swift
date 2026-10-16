import SwiftUI
import CoreGraphics

// ============================================================
// 拖拽召唤的纯几何 (2026-10-16，P5)
// ------------------------------------------------------------
// 为什么这一层必须单独一个文件、而且是**纯函数**：
//   拖拽召唤是本仓第一批碰到 `matchedGeometryEffect` / `DragGesture(velocity:)` / 弹簧交接的代码，
//   而本机没有 Xcode —— 一旦错了只能等 CI 红，且红在哪一行都说不清（这三个 API 全仓 0 先例）。
//   所以把「哪里有光点 / 拖多远算越界 / 松手会落在哪 / 落在谁身上」全部抽成不碰视图的算术，
//   由 `tools/summonshadow.js` 用另一门语言逐行对拍（照 `tools/autoopenshadow.js` 的形状）。
//   视图里只剩「把拖拽位移喂进来、把结果画出去」。
//
// 常数来源是 `design-system/aurora-lock/CORE.md` §2 —— **不是这里现编的**：
//   原型取景基准 400 × 860；HOME (200, 521)；RIDE Δ(130, −263) / scale 0.42；
//   LIMIT 196；橡皮筋 c = 0.55；动量投影 d = 0.99 / 钳位 LIMIT×1.4；CHARGE 1100ms。
//   本文件存**比例**而不是绝对值：iOS 侧要换成安全区相对（CORE.md §2 原文），
//   存绝对值就会在 iPhone SE 与 iPad 上各错一次。
// ============================================================

enum SummonGeometry {

    // ---------- 基准画布与常数（比例形式，改一处必须重跑 tools/summonshadow.js）----------

    /// 原型的机身逻辑尺寸。**只用来把绝对值换成比例**，视图里不该再读它。
    static let canvas = CGSize(width: 400, height: 860)

    /// HOME（锁核待机位）比例。
    static let homeRatio = CGPoint(x: 200.0 / canvas.width, y: 521.0 / canvas.height)

    /// RIDE（浮层骑乘位）相对 HOME 的比例位移 + 缩放。
    static let rideRatio = CGVector(dx: 130.0 / canvas.width, dy: -263.0 / canvas.height)
    static let rideScale: CGFloat = 0.42

    /// 三光点的轨道位比例。顺序 = `CoreHomeView` 里三行的顺序（顶角在上）。
    static let dotRatios: [(route: Route, point: CGPoint)] = [
        (.records,     CGPoint(x: 200.0 / canvas.width, y: 345.0 / canvas.height)),
        (.credentials, CGPoint(x: 74.0 / canvas.width,  y: 425.0 / canvas.height)),
        (.settings,    CGPoint(x: 326.0 / canvas.width, y: 425.0 / canvas.height)),
    ]

    /// 拖拽半径。原值 196 是对 400pt 宽量的；换成**短边**的同一比例，
    /// 于是横屏/大屏上"能拖多远"与光点轨道保持同一个视觉关系。
    static let limitRatio: CGFloat = 196.0 / canvas.width

    /// 橡皮筋系数与动量衰减率（CORE.md §2）。
    static let rubberC: CGFloat = 0.55
    static let projectD: CGFloat = 0.99
    /// 投影落点的钳位：LIMIT × 1.4。
    static let projectClamp: CGFloat = 1.4

    /// 命中半径：光点直径 54pt 的一半 + 一点手抖余量，按同一比例换算。
    static let hitRatio: CGFloat = 34.0 / canvas.width

    // ---------- 换算 ----------

    /// 一次布局的全部绝对值。视图只读它，自己不算任何比例。
    struct Layout {
        var home: CGPoint
        var ride: CGPoint
        var dots: [(route: Route, point: CGPoint)]
        var limit: CGFloat
        var hit: CGFloat
        /// 该画布下光点半径（画出来用，不是判据）。
        var dotRadius: CGFloat
    }

    /// `size` 取**可用区域**（不含安全区的画布），`dotRadius` 由调用方给当前视觉半径。
    static func layout(in size: CGSize, dotRadius: CGFloat = 27) -> Layout {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let scale = min(w, h)
        let home = CGPoint(x: homeRatio.x * w, y: homeRatio.y * h)
        let ride = CGPoint(x: home.x + rideRatio.dx * w, y: home.y + rideRatio.dy * h)
        return Layout(
            home: home,
            ride: ride,
            dots: dotRatios.map { (route: $0.route, point: CGPoint(x: $0.point.x * w, y: $0.point.y * h)) },
            limit: limitRatio * scale,
            hit: hitRatio * scale,
            dotRadius: dotRadius
        )
    }

    // ---------- 纯算术 ----------

    /// 越界后的橡皮筋：`over·dim·c/(dim + c·over)`（CORE.md §2）。
    /// **不是硬停** —— 硬停会让"还能再拖一点"这个反馈整块消失。
    static func rubberBand(_ over: CGFloat, dim: CGFloat, c: CGFloat = SummonGeometry.rubberC) -> CGFloat {
        guard over > 0, dim > 0 else { return max(0, over) }
        return over * dim * c / (dim + c * over)
    }

    /// 把手指位移换算成锁核的实际位移：界内 **1:1 跟手**，界外按半径方向走橡皮筋。
    /// 返回的模长永远 ≤ limit（橡皮筋的构造保证，不是靠再钳一次）。
    static func dragOffset(_ raw: CGVector, limit: CGFloat) -> CGVector {
        let d = hypot(raw.dx, raw.dy)
        guard limit > 0, d > limit else { return raw }
        let pulled = limit + rubberBand(d - limit, dim: limit)
        let k = pulled / d
        return CGVector(dx: raw.dx * k, dy: raw.dy * k)
    }

    /// 动量投影：Apple `project()` 的**指数衰减**式（不是 `v²/2a`）。
    /// `v` 是松手瞬间的速度（pt/s），返回还会滑多远（pt）。
    static func project(_ v: CGFloat, d: CGFloat = SummonGeometry.projectD) -> CGFloat {
        guard d > 0, d < 1 else { return 0 }
        return (v / 1000) * d / (1 - d)
    }

    /// 松手后的落点位移 = 当前位移 + 投影位移，整体钳到 `limit × clamp`。
    static func projectedOffset(_ offset: CGVector,
                                velocity: CGVector,
                                limit: CGFloat,
                                clamp: CGFloat = SummonGeometry.projectClamp) -> CGVector {
        let raw = CGVector(dx: offset.dx + project(velocity.dx),
                           dy: offset.dy + project(velocity.dy))
        let cap = limit * clamp
        let d = hypot(raw.dx, raw.dy)
        guard cap > 0, d > cap else { return raw }
        let k = cap / d
        return CGVector(dx: raw.dx * k, dy: raw.dy * k)
    }

    /// 命中判据：**用投影落点**（不是手指抬起的位置）离光点多近 ⇒ 召唤它。
    /// 这正是"朝光点甩一下就过去"的来源；拿抬手位置判，甩的动作永远差一截。
    static func summon(projected: CGPoint,
                       dots: [(route: Route, point: CGPoint)],
                       radius: CGFloat) -> Route? {
        var best: (route: Route, distance: CGFloat)?
        for d in dots {
            let r = hypot(projected.x - d.point.x, projected.y - d.point.y)
            if r <= radius, best == nil || r < best!.distance { best = (d.route, r) }
        }
        return best?.route
    }

    /// 该不该给释放速率：**只有手势本身带动量时才交接**（CORE.md §4 的规则）。
    /// 阈值按 LIMIT 的比例给：慢慢拖到底再松手，速度远不到这个量级。
    static func hasMomentum(_ velocity: CGVector, limit: CGFloat) -> Bool {
        hypot(velocity.dx, velocity.dy) > max(limit * 1.2, 1)
    }
}
