import SwiftUI
import RealityKit

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 刃 (d-blade) —— 几何构造
// ═══════════════════════════════════════════════════════════════════════
//
// 60 × 300 mm 的非对称锁体。左缘一根直线，右缘一段 R500 的外凸弧 ——
// 整块体的形，只有这一道弧。剩下都收进 22 mm 的厚度里：
// 一圈压边、一道竖向分缝、一处指腹的凹陷。
//
// 这一层只负责**算顶点**，不碰 RealityKit。
// 纯数学，可被单元测试；MeshDescriptor 的组装在下一层。
//
// 源自 docs/redesign/locks/d-blade.js 的 three.js 实现，
// 算法逐行对应（insetPolygon / bladeOutline / slabTriangles / funnel）。
//
// 单位: mm。X 向右, Y 向上, Z 指向观察者，正面基准面 z = 0。
enum BladeGeometry {
    // ── 尺寸 ──
    static let width: Float = 60
    static let height: Float = 300
    static let arcRadius: Float = 500
    static let depth: Float = 22
    static let arcSegments = 56

    static var halfHeight: Float { height / 2 }
    static var left: Float { -width / 2 }
    /// 弧心: 让弧在 y = 0 处正好落在 x = +30
    static var arcCenterX: Float { width / 2 - arcRadius }

    static let deckInset: Float = 3
    static let seamX: Float = -12
    static let seamHalf: Float = 0.35

    // ── 点 ──
    struct P3 {
        var x: Float
        var y: Float
        var z: Float
    }

    struct P2 {
        var x: Float
        var y: Float
    }

    // ── 2D 工具 ────────────────────────────────────────────────────

    /// 两条线段求交。平行返回 nil。
    static func lineIntersect(_ a: P2, _ b: P2, _ c: P2, _ d: P2) -> P2? {
        let rx = b.x - a.x, ry = b.y - a.y
        let sx = d.x - c.x, sy = d.y - c.y
        let den = rx * sy - ry * sx
        if abs(den) < 1e-9 { return nil }
        let t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / den
        return P2(x: a.x + rx * t, y: a.y + ry * t)
    }

    /// 逆时针多边形向内偏移 d（斜接）。
    ///
    /// 每一段的左手法线即向内方向 —— 逆时针多边形的这个性质
    /// 让「内缩」退化成一次法线平移 + 相邻段求交。
    static func insetPolygon(_ poly: [P2], _ d: Float) -> [P2] {
        if d == 0 { return poly }
        let n = poly.count
        guard n >= 3 else { return poly }

        var normals = [P2]()
        normals.reserveCapacity(n)
        for i in 0..<n {
            let a = poly[i]
            let b = poly[(i + 1) % n]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            normals.append(P2(x: -dy / len, y: dx / len))
        }

        var out = [P2]()
        out.reserveCapacity(n)
        for i in 0..<n {
            let prev = (i - 1 + n) % n
            let next = (i + 1) % n
            let A = poly[prev], B = poly[i], C = poly[next]
            let n1 = normals[prev], n2 = normals[i]
            let e1a = P2(x: A.x + n1.x * d, y: A.y + n1.y * d)
            let e1b = P2(x: B.x + n1.x * d, y: B.y + n1.y * d)
            let e2a = P2(x: B.x + n2.x * d, y: B.y + n2.y * d)
            let e2b = P2(x: C.x + n2.x * d, y: C.y + n2.y * d)
            if let ip = lineIntersect(e1a, e1b, e2a, e2b) {
                let dx = ip.x - B.x, dy = ip.y - B.y
                if (dx * dx + dy * dy).squareRoot() < d * 8 {
                    out.append(ip)
                } else {
                    out.append(P2(x: (e1b.x + e2a.x) / 2, y: (e1b.y + e2a.y) / 2))
                }
            } else {
                out.append(P2(x: (e1b.x + e2a.x) / 2, y: (e1b.y + e2a.y) / 2))
            }
        }
        return out
    }

    // ── 轮廓 ──────────────────────────────────────────────────────

    /// 整块锁体轮廓（内缩 inset）: 左直线 + 上下短边 + 右侧 R500 弧
    static func bladeOutline(inset: Float) -> [P2] {
        let xL = left + inset
        let yT = halfHeight - inset
        let r = arcRadius - inset
        guard r > 0 else { return [] }
        let tMax = (yT / r).clampedAsin

        var pts = [P2]()
        pts.reserveCapacity(arcSegments + 3)
        pts.append(P2(x: xL, y: -yT))
        for i in 0...arcSegments {
            let th = -tMax + (2 * tMax * Float(i)) / Float(arcSegments)
            pts.append(P2(x: arcCenterX + r * cos(th), y: r * sin(th)))
        }
        pts.append(P2(x: xL, y: yT))
        return pts
    }

    static var deckY: Float { halfHeight - deckInset }
    static var deckXLeft: Float { left + deckInset }
    static var seamLeftEdge: Float { seamX - seamHalf }
    static var seamRightEdge: Float { seamX + seamHalf }

    /// 压边左侧窄条 —— 守住直线边
    static func deckLeftPolygon() -> [P2] {
        [
            P2(x: deckXLeft, y: -deckY),
            P2(x: seamLeftEdge, y: -deckY),
            P2(x: seamLeftEdge, y: deckY),
            P2(x: deckXLeft, y: deckY),
        ]
    }

    /// 压边右侧大面 —— 跟着 R500 走
    static func deckRightPolygon() -> [P2] {
        let yT = deckY
        let r = arcRadius - deckInset
        guard r > 0 else { return [] }
        let tMax = (yT / r).clampedAsin
        var pts = [P2]()
        pts.reserveCapacity(arcSegments + 3)
        pts.append(P2(x: seamRightEdge, y: -yT))
        for i in 0...arcSegments {
            let th = -tMax + (2 * tMax * Float(i)) / Float(arcSegments)
            pts.append(P2(x: arcCenterX + r * cos(th), y: r * sin(th)))
        }
        pts.append(P2(x: seamRightEdge, y: yT))
        return pts
    }

    // ── 拉伸 ──────────────────────────────────────────────────────

    /// 带前后倒角的平板: 从一个 2D 轮廓拉出实体。
    ///
    /// rings = 每道倒角一个内缩环。侧面在相邻环之间生成四边形（拆两个三角形），
    /// 端盖用扇形三角化（中心 = 各顶点均值）。
    static func slabTriangles(_ poly: [P2],
                               zBack: Float, zFront: Float,
                               chBack: Float, chFront: Float) -> [P3] {
        guard poly.count >= 3 else { return [] }

        var rings: [(d: Float, z: Float)] = [(chBack, zBack)]
        if chBack > 0 { rings.append((0, zBack + chBack)) }
        if chFront > 0 { rings.append((0, zFront - chFront)) }
        rings.append((chFront, zFront))

        let ringPts: [[P3]] = rings.map { r in
            insetPolygon(poly, r.d).map { P3(x: $0.x, y: $0.y, z: r.z) }
        }

        var tris = [P3]()
        if ringPts.count >= 2 {
            for k in 0..<(ringPts.count - 1) {
                let A = ringPts[k], B = ringPts[k + 1]
                let n = min(A.count, B.count)
                guard n >= 3 else { continue }
                for i in 0..<n {
                    let j = (i + 1) % n
                    tris.append(A[i]); tris.append(A[j]); tris.append(B[j])
                    tris.append(A[i]); tris.append(B[j]); tris.append(B[i])
                }
            }
        }

        if let first = ringPts.first { capFan(first, flip: true, into: &tris) }
        if let last = ringPts.last { capFan(last, flip: false, into: &tris) }
        return tris
    }

    /// 扇形三角化
    private static func capFan(_ pts: [P3], flip: Bool, into out: inout [P3]) {
        guard pts.count >= 3 else { return }
        var cx: Float = 0, cy: Float = 0
        for p in pts { cx += p.x; cy += p.y }
        cx /= Float(pts.count)
        cy /= Float(pts.count)
        let center = P3(x: cx, y: cy, z: pts[0].z)

        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            if flip {
                out.append(center); out.append(b); out.append(a)
            } else {
                out.append(center); out.append(a); out.append(b)
            }
        }
    }

    // ── 超椭圆（指纹浅碟轮廓）─────────────────────────────────

    /// 超椭圆参数方程: |x/a|^n + |y/b|^n = 1
    /// n = 2 是椭圆；n 越大越接近圆角矩形。刃用 2.8。
    static func superEllipse(a: Float, b: Float, n: Float, t: Float) -> P2 {
        let ct = cos(t), st = sin(t)
        let sx: Float = ct >= 0 ? 1 : -1
        let sy: Float = st >= 0 ? 1 : -1
        let x = sx * pow(abs(ct), 2 / n) * a
        let y = sy * pow(abs(st), 2 / n) * b
        return P2(x: x, y: y)
    }

    /// 一圈超椭圆点
    static func superRing(a: Float, b: Float, n: Float,
                          scale: Float, segments: Int) -> [P2] {
        var pts = [P2]()
        pts.reserveCapacity(segments + 1)
        for i in 0...segments {
            let t = (2 * Float.pi * Float(i)) / Float(segments)
            pts.append(superEllipse(a: a * scale, b: b * scale, n: n, t: t))
        }
        return pts
    }

    /// 环形放样（funnel）: 若干环沿 z 走，环间生成侧面，底面封口。
    /// 用于指纹的「槽口 + 浅碟」两级凹陷。
    static func funnelTriangles(_ rings: [(pts: [P2], z: Float)],
                                floorZ: Float?) -> [P3] {
        var tris = [P3]()
        guard rings.count >= 2 else { return tris }

        let ringPts: [[P3]] = rings.map { r in
            r.pts.map { P3(x: $0.x, y: $0.y, z: r.z) }
        }

        for k in 0..<(ringPts.count - 1) {
            let A = ringPts[k], B = ringPts[k + 1]
            let n = min(A.count, B.count)
            guard n >= 2 else { continue }
            for i in 0..<(n - 1) {
                tris.append(A[i]); tris.append(A[i + 1]); tris.append(B[i + 1])
                tris.append(A[i]); tris.append(B[i + 1]); tris.append(B[i])
            }
        }

        if let fz = floorZ, let last = ringPts.last, last.count >= 3 {
            var cx: Float = 0, cy: Float = 0
            for p in last { cx += p.x; cy += p.y }
            cx /= Float(last.count)
            cy /= Float(last.count)
            let c = P3(x: cx, y: cy, z: fz)
            for i in 0..<(last.count - 1) {
                tris.append(c); tris.append(last[i]); tris.append(last[i + 1])
            }
        }

        return tris
    }
}

extension Float {
    /// asin 的安全版: 输入超界时钳到 [-1, 1]，避免 NaN
    var clampedAsin: Float {
        asin(Swift.min(Swift.max(self, -1), 1))
    }
}
