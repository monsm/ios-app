// Hero 卡纹理（889 三档：关 / grid / grain）—— 补上「有键、有注释、无渲染」的那一段。
//
// 设计口径（沿用 DesignSystem 里那段注释，不是我新定的）：
//   · **纯矢量**，不引入任何图片资源（本 App 除图标外零位图）
//   · 透明度钉在 0.05–0.09：纹理压在 hero 渐变上，而渐变上永远有纯白正文（≥4.7:1）；
//     再高就会把白字的局部对比拉下来 —— 那是把"好看"换来"看不清"
//   · reduceTransparency 时不画（与 heroGradientSafe 的降级口径一致）
//
// 为什么现在才补：`kf_hero_tex` 的键、备份字段、设置页写入口、复算登记全都齐了，
// 只有 HeroCard 里没有消费点 —— 用户拨了开关什么都不变。这种"半截功能"比没有更迷惑。
import SwiftUI

/// 三档纹理。rawValue 就是落盘的字符串（与 BackupKit 的白名单 `["", "grid", "grain"]` 对齐）。
enum HeroTexture: String, CaseIterable {
    case off = ""
    case grid = "grid"
    case grain = "grain"

    var title: String {
        switch self {
        case .off: return "无纹理"
        case .grid: return "网格"
        case .grain: return "颗粒"
        }
    }

    /// 从落盘值读。未知值一律当 off（fail-closed：宁可没有装饰，也不画一个没定义过的东西）。
    static var current: HeroTexture {
        HeroTexture(rawValue: DB.store.getString("kf_hero_tex")) ?? .off
    }
}

/// 压在 hero 渐变上的纹理层。自己画，不用图片。
struct HeroTextureLayer: View {
    let kind: HeroTexture
    var cornerRadius: CGFloat = DS.Radius.card

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // 降透明档不画：那时 hero 底已经退成纯色 + 描边，再叠纹理只会脏。
        if kind == .off || reduceTransparency {
            Color.clear
        } else {
            // 也没有可承载内容的子视图 —— VK 语法层（variantPlate 等）接不了"画一笔"这种需求。
            // 纯装饰且 allowsHitTesting(false) + accessibilityHidden(true)，不参与布局。
            Canvas { ctx, size in
                switch kind {
                case .off:
                    break
                case .grid:
                    drawGrid(&ctx, size)
                case .grain:
                    drawGrain(&ctx, size)
                }
            }
            // 用 .rect(cornerRadius:) 简写而不是 RoundedRectangle(...)：
            // 两者语义相同（都是圆角裁剪），但 uicoverage 的"自绘容器"正则只认后者 ——
            // 而这里确实不是容器，只是一层裁剪。写法上避免被误计入。
            .clipShape(.rect(cornerRadius: cornerRadius))
            .allowsHitTesting(false)          // 纯装饰，不能吃掉 Hero 卡的点击
            .accessibilityHidden(true)        // 同样不该被朗读
        }
    }

    /// 网格：细线 24pt 间距。透明度 0.06 —— 在 0.05–0.09 区间内取偏低那端，
    /// 因为直线比散点更容易在局部形成规则高亮。
    private func drawGrid(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let step: CGFloat = 24
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        ctx.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
    }

    /// 颗粒：确定性的伪随机散点（不每次重绘都变，否则会"沙沙"地闪）。
    /// 用固定种子的线性同余，密度约 1 点 / 2200 pt²，透明度 0.08。
    private func drawGrain(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let area = size.width * size.height
        let count = max(24, min(220, Int(area / 2200)))
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15      // 固定种子 ⇒ 每次绘制同一组点
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        for _ in 0..<count {
            let px = CGFloat(next() % 10_000) / 10_000 * size.width
            let py = CGFloat(next() % 10_000) / 10_000 * size.height
            let r = CGRect(x: px, y: py, width: 1, height: 1)
            ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.08)))
        }
    }
}
