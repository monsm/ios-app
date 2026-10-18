//  LockLeaf.swift
//  单扇门: 几何 / 旋转 / 背面透明度斜坡 / 门缝厚度边。2026-10-18 门面改造新增。
//
//  坑 (PART1 §11 坑 1): SwiftUI 的 rotation3DEffect **不会**自动隐藏背面
//  (CSS 的 backface-visibility:hidden 没有等价物)。106° 意味着最后 18° 会露出镜像背面,
//  所以必须叠一条与角度联动的透明度斜坡, 且**必须用连续函数** ——
//  `angle > 90 ? 0 : 1` 会在 90° 处闪一帧。

import SwiftUI

struct LockLeaf: View {
    /// 0…1 开门进度 (0=关, 1=全开)。由 LockFaceView 的时间轴驱动。
    let openProgress: Double
    let isRight: Bool
    let skin: LockFaceSkin

    /// 透视强度。**没有预设值**: 按 PART1 §11 坑 2 的两条判据在真机上调
    /// (A 残留宽度 5-16pt / B 45° 时梯形畸变 <8% 门高)。
    /// 这里给一个可运行的起点, 验收时必须按判据改。
    private let perspective: CGFloat = 0.35

    private var angle: Double {
        let a = LockFaceStyle.doorAngle * openProgress
        return isRight ? -a : a
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 2   // 每扇门内部承载整面门宽, 再靠偏移拼合
            ZStack(alignment: isRight ? .trailing : .leading) {
                DoorSurface(skin: skin, isRightLeaf: isRight)
                    .frame(width: w, height: geo.size.height)
                    .offset(x: isRight ? 0 : 0)
                edge
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: isRight ? .trailing : .leading,
                perspective: perspective
            )
            .opacity(LockFaceStyle.backfaceFade(angle: abs(angle)))
            .allowsHitTesting(false)
        }
    }

    // MARK: - 门缝厚度边 (左扇吃暗 / 右扇吃亮, 不对称是刻意的)

    private var edge: some View {
        HStack(spacing: 0) {
            if isRight {
                // 右扇的左缘: 白 92% 起 1.3pt, 再 34% 到 16%
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.92), location: 0),
                        .init(color: Color.white.opacity(0.34), location: 0.08),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: LockFaceStyle.edgeWidth)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                // 左扇的右缘: 深棕 52% 起 1pt, 再 20% / 6% 渐隐
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x1A0F03).opacity(0.52), location: 0),
                        .init(color: Color(hex: 0x281808).opacity(0.20), location: 0.14),
                        .init(color: Color(hex: 0x281808).opacity(0.06), location: 0.30),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .trailing, endPoint: .leading
                )
                .frame(width: LockFaceStyle.edgeWidth)
            }
        }
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
