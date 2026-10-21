import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 入户门（07 竖条阵列）
// ═══════════════════════════════════════════════════════════════════════
//
// 1050 × 2300 × 88 mm。外框 130mm，内部 40 条竖条，奇偶凸出 26/14mm。
//
// ═══ 为什么门用 2D 贴图而不是 RealityKit 3D ═══
//
// 门是**背景**，锁才是主角。理由有三：
//
// 1. **性能**: 门有 40 条竖条 + 外框 + 门芯，3D 化要 50+ 个实体。
//    而它占屏幕 85%，是纯粹的背景板 —— 花这些预算不值。
//
// 2. **可读性**: 2D 贴图可以精确控制每条竖条的明暗对比，
//    3D 里这些对比会被光照随机化，反而不如贴图可控。
//
// 3. **真实比例的必要性**: 锁只有门宽的 5.7%。
//    如果门是 3D 的，用户转到侧面会看到门的厚度，
//    但锁在门面上的投影位置必须精确 —— 2D 贴图天然对齐，
//    3D 反而要算两次投影。
//
// **锁仍然是真 3D（XLockBlade）** —— 主角值得那个预算。
//
// ═══ 真实尺寸常量（与 docs/redesign/locks/d-blade.js 一致）═══
struct GateMetrics {
    // 门
    static let doorW: CGFloat = 1050     // mm
    static let doorH: CGFloat = 2300
    static let doorT: CGFloat = 88
    static let stile: CGFloat = 130      // 外框
    static let slatCount = 40
    // 锁
    static let lockW: CGFloat = 60
    static let lockH: CGFloat = 300
    static let backset: CGFloat = 60     // 锁芯中心到门边
    static let handleY: CGFloat = 1080   // 把手离地
    // 比例
    static var lockToDoorWidth: CGFloat { lockW / doorW }   // 5.7%

    /// 锁中心距门顶（mm）
    static var lockTopFromDoorTop: CGFloat {
        doorH - handleY - lockH / 2
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - 门面（2D 贴图）
// ═══════════════════════════════════════════════════════════════════════
struct GateFaceTexture {
    /// 生成门面图片。分辨率按门的高宽比，1024 高。
    ///
    /// 与 HTML 原型 drawDoorFace() 逐行对应 —— 除了抗锯齿与字体渲染
    /// 由 Core Graphics 接管（那部分无法 100% 一致，1-2px 级差异）。
    static func image(tint: UIColor) -> UIImage {
        let H: CGFloat = 1024
        let W = (H * GateMetrics.doorW / GateMetrics.doorH).rounded()
        let size = CGSize(width: W, height: H)
        let ppm = H / GateMetrics.doorH        // px per mm

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let c = ctx.cgContext

            // ── 门框暗底 ──
            c.setFillColor(UIColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1).cgColor)
            c.fill(CGRect(origin: .zero, size: size))

            // ── 门板（留 3mm 边）──
            let inset = 3 * ppm
            let board = CGRect(x: inset, y: inset,
                               width: W - inset * 2, height: H - inset * 2)
            // 木色渐变（左上偏亮，右下偏暗）
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.243, green: 0.188, blue: 0.141, alpha: 1).cgColor,
                UIColor(red: 0.180, green: 0.141, blue: 0.102, alpha: 1).cgColor,
                UIColor(red: 0.129, green: 0.102, blue: 0.075, alpha: 1).cgColor,
            ] as CFArray
            if let grad = CGGradient(colorsSpace: space, colors: colors,
                                     locations: [0, 0.5, 1]) {
                c.saveGState()
                c.addRect(board)
                c.clip()
                c.drawLinearGradient(grad,
                                     start: CGPoint(x: 0, y: 0),
                                     end: CGPoint(x: W, y: H),
                                     options: [])
                c.restoreGState()
            }

            // ── 外框 130mm ──
            let st = GateMetrics.stile * ppm
            c.setFillColor(UIColor(white: 0, alpha: 0.32).cgColor)
            c.fill(CGRect(x: board.minX, y: board.minY, width: board.width, height: st))
            c.fill(CGRect(x: board.minX, y: board.maxY - st, width: board.width, height: st))
            c.fill(CGRect(x: board.minX, y: board.minY, width: st, height: board.height))
            c.fill(CGRect(x: board.maxX - st, y: board.minY, width: st, height: board.height))

            // 外框内缘高光
            c.setStrokeColor(UIColor(red: 1, green: 0.92, blue: 0.82, alpha: 0.10).cgColor)
            c.setLineWidth(1)
            c.stroke(CGRect(x: board.minX + st, y: board.minY + st,
                            width: board.width - st * 2, height: board.height - st * 2))

            // ── 40 条竖条（奇偶凸出 26/14mm，所以明暗交替）──
            let innerW = board.width - st * 2
            let innerH = board.height - st * 2
            let pitch = innerW / CGFloat(GateMetrics.slatCount)
            let barW = pitch * 0.62
            for i in 0..<GateMetrics.slatCount {
                let bx = board.minX + st + CGFloat(i) * pitch + (pitch - barW) / 2
                let bright = (i % 2 == 0)
                // 条身
                c.setFillColor(bright
                               ? UIColor(red: 1, green: 0.94, blue: 0.86, alpha: 0.075).cgColor
                               : UIColor(white: 0, alpha: 0.14).cgColor)
                c.fill(CGRect(x: bx, y: board.minY + st, width: barW, height: innerH))
                // 条左缘高光（模拟凸出的受光面）
                c.setFillColor(bright
                               ? UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 0.10).cgColor
                               : UIColor(white: 0, alpha: 0.18).cgColor)
                c.fill(CGRect(x: bx, y: board.minY + st,
                              width: max(1, barW * 0.16), height: innerH))
            }

            // ── 状态光 （门缝里透出的一线）──
            c.setFillColor(tint.withAlphaComponent(0.16).cgColor)
            let glowH = max(2, 4 * ppm)
            c.fill(CGRect(x: board.minX + st, y: board.midY - glowH / 2,
                          width: board.width - st * 2, height: glowH))

            // 门面与门框之间的缝（4 边细黑线）
            c.setStrokeColor(UIColor(white: 0, alpha: 0.55).cgColor)
            c.setLineWidth(2)
            c.stroke(board)
        }
    }
}
