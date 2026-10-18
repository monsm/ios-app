//  LockFaceStyle.swift
//  门面层 (LockFace) 的装饰常量。2026-10-18 门面改造新增。
//
//  为什么单独一个文件: 门面是**装饰层**, 它的底色/渐变/倒角/投影不参与
//  tools/contrast.js 的 397 条语义对比断言, 也不进 Palette (D4)。
//  门面上的**文字**仍然只准用 DS.Palette.text / textSub —— 这一条写在 LockFaceView 里。
//
//  动效时长**不在这里**: DS.Motion 的 tier 是 private, 只有 DesignSystem.swift 内能读降级档,
//  所以 doorSwing / lightLeak / doorReveal / glyphSwap / chargeReset 都放在 DS.Motion 里。

import SwiftUI

/// 门面皮肤。几何(中缝位置/锁体直径/开门角度)在所有皮肤下**逐字相同**, 只换材质。
enum LockFaceSkin: String, CaseIterable, Identifiable, Codable {
    case wood
    case metal
    case darkGlass
    case frosted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wood: return "原木"
        case .metal: return "金属"
        case .darkGlass: return "深色玻璃"
        case .frosted: return "磨砂白"
        }
    }

    /// 倒角亮面系数 (金属倒角 conic/AngularGradient 的亮度倍率)。
    var bevelBrightness: Double {
        switch self {
        case .wood: return 1.00
        case .metal: return 1.35
        case .darkGlass: return 1.50
        case .frosted: return 0.70
        }
    }

    /// 投影强度倍率 (盘体 drop-shadow)。
    var shadowStrength: Double {
        switch self {
        case .wood: return 1.00
        case .metal: return 1.15
        case .darkGlass: return 1.30
        case .frosted: return 0.75
        }
    }

    /// 门面噪声强度。深色档整体再压一档 (深色下噪声更显眼)。
    func noiseOpacity(dark: Bool) -> Double {
        if dark { return 0.18 }
        switch self {
        case .wood: return 0.30
        case .metal: return 0.18
        case .darkGlass: return 0.12
        case .frosted: return 0.22
        }
    }
}

/// 门面的全部装饰常量。视图只读这里, 不许就地写字面量。
enum LockFaceStyle {

    // MARK: - 几何

    /// 锁体直径。**必须**由 DS.Metric.dial 映射而来 (D12):
    /// 否则用户在设置里调「圆盘大小」后回到门外会看到尺寸没变 = 假开关。
    /// 160→220 / 176→240 / 200→272, 再按屏宽封顶。
    static func plateDiameter(screenWidth: CGFloat) -> CGFloat {
        let base = DS.Metric.dial
        let mapped: CGFloat
        switch Int(base) {
        case 160: mapped = 220
        case 200: mapped = 272
        default:  mapped = 240
        }
        return min(mapped, screenWidth * 0.68)
    }

    /// 锁体中心相对屏高的位置。横屏视觉重心更靠上。
    static func plateCenterRatio(isLandscape: Bool) -> CGFloat {
        isLandscape ? 0.44 : 0.46
    }

    /// 玻璃面内缩 / 凹槽环外扩 (对应 v10 的 .face{inset:8px} 与 .groove{inset:-9px})。
    static let faceInset: CGFloat = 8
    static let grooveOutset: CGFloat = 9

    /// 门缝两侧厚度边宽度 (v10 .leaf .edge 的 16px)。
    static let edgeWidth: CGFloat = 16

    /// 中缝透光宽度 (v10 .gap 的 3px)。
    static let gapWidth: CGFloat = 3

    /// 锁体字形尺寸 (v10 .glyph svg 的 62px)。
    static let glyphSize: CGFloat = 60

    // MARK: - 开门几何

    /// 开门角度。>90° 意味着门转到视线后方, 靠透明度斜坡收尾 (见 LockLeaf)。
    static let doorAngle: Double = 106

    /// 背 facing 斜坡: 88° 之前完全不透明, 88°→106° 线性降到 0。
    /// 必须用连续函数, 不许 `angle > 90 ? 0 : 1` —— 后者会在 90° 处闪一帧。
    static func backfaceFade(angle: Double) -> Double {
        let start = 88.0, end = doorAngle
        let t = min(max((angle - start) / (end - start), 0), 1)
        return 1 - t
    }

    /// 门转动开始时刻 (相对开锁成功 t=0)。中缝透光要先亮起来, 门才转。
    static let doorTurnDelay: Double = 0.34

    /// App 层入场延迟 (与门的转动同刻开始, 再各带自己的 140ms)。
    static let appRevealDelay: Double = 0.14

    /// 中缝光在门开完之后延迟多久淡出。
    static let lightLeakFadeDelay: Double = 0.42

    // MARK: - 材质 (浅色档)

    static func surfaceColors(skin: LockFaceSkin, dark: Bool) -> [Color] {
        if dark {
            // 夜景门廊: 不是把浅色灰搬进深色 (MASTER.md §1 已判死这条)。
            //
            // ⚠️ 2026-10-18 真机截图修正: 原值 #141618/#0F1113/#0A0B0C 与画布 #070B12
            // 的对比度只有 **1.09 / 1.00** —— 门在深色模式下**根本看不见**, 用户看到的是
            // 一个锁体浮在纯黑上。设计文档里写的"夜景门廊"必须**肉眼可辨**才算数。
            // 提到 1.33 那一档: 门面比画布亮一档 (像被走廊灯照到的深色木门),
            // 既不是浅色灰搬过来, 也不会亮到破坏夜景感。
            return [Color(hex: 0x232830), Color(hex: 0x1C2128), Color(hex: 0x161A1F)]
        }
        switch skin {
        case .wood:
            return [Color(hex: 0xFBF9F5), Color(hex: 0xF6F3ED), Color(hex: 0xEDE9E1)]
        case .metal:
            return [Color(hex: 0xF2F3F4), Color(hex: 0xE4E6E8), Color(hex: 0xD3D6D9)]
        case .darkGlass:
            return [Color(hex: 0x2A2D31), Color(hex: 0x1C1F22), Color(hex: 0x101214)]
        case .frosted:
            return [Color(hex: 0xFFFFFF), Color(hex: 0xFAFAFA), Color(hex: 0xF2F2F2)]
        }
    }

    /// 锁体玻璃面: 两模式一致 (它本来就是深色玻璃)。
    static let plateGlassColors: [Color] = [
        Color(hex: 0x3A4044), Color(hex: 0x202528), Color(hex: 0x0F1214), Color(hex: 0x080A0B)
    ]

    /// 锁体金属倒角色停 (对应 v10 的 conic-gradient 八停)。
    static let bevelStops: [Color] = [
        Color(hex: 0xFEFDFB), Color(hex: 0xC3BCB1), Color(hex: 0xFBF9F5), Color(hex: 0xB6AFA4),
        Color(hex: 0xEFEBE3), Color(hex: 0xC8C1B6), Color(hex: 0xFCFDFA), Color(hex: 0xC3BCB1),
    ];

    /// 字形自上而下的料 (不是纯白贴纸)。
    static let glyphColors: [Color] = [Color(hex: 0xFFFFFF), Color(hex: 0xF4F0E9), Color(hex: 0xC6C0B5)]

    /// 镜面高光的白。**这是装饰层的"光"，不是前景文字色** ——
    /// 它落在深色玻璃面上，不参与 contrast.js 的语义对比断言。
    /// 单独抽出来有两个理由: ① swiftlint 的"写死纯白前景"名单只许减不许增;
    /// ② 夜间降亮度要按 nightDimFactor 压峰值，散写就压不到。
    static func specularTint(_ opacity: Double) -> Color {
        Color.white.opacity(opacity * (DS.isNightDim ? nightDimFactor : 1))
    }
    /// 夜间降亮度系数 (22:00-06:00 只压装饰层峰值, 文字与语义对比度不受影响)。
    static let nightDimFactor: Double = 0.72

    // MARK: - 皮肤持久化键

    /// 皮肤存在 LockMeta 里 (D12/audit-B): 不是 LockProfile (那个类型不存在)。
    static let skinKey = "skin"
}
