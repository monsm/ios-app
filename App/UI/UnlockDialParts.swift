// 开锁圆盘 · 私有子视图（脉冲环 / 三段进度条）
// 2026-10-29 从 UnlockDial.swift（692 行）拆出。private 已提升为 internal，跨文件可见。
import SwiftUI

struct UnlockPulseRing: View {
    var diameter: CGFloat = 176
    /// 66 信号强度驱动呼吸速率: 越近呼吸越快 (可达即有反馈), 无缓存 RSSI 用 1.1s 基准。
    /// 只在忙态挂载, 因此速率变化不会被当成"卡住"的信号。
    var rssi: Int? = nil
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var breathe = false

    /// 呼吸周期: RSSI -50 → 0.7s, -95 → 1.8s, 线性内插并夹在 [0.7, 1.8]
    var period: Double {
        guard let r = rssi else { return 1.1 }
        let clamped = min(-50.0, max(-95.0, Double(r)))
        let k = (clamped + 95.0) / 45.0          // 0 = 最远, 1 = 最近
        return 1.8 - 1.1 * k
    }

    var body: some View {
        Circle()
            .strokeBorder(DS.Palette.accent.opacity(0.45), lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathe ? 1.0 : 0.86)
            .opacity(breathe ? 0 : 0.9)
            .allowsHitTesting(false)
            .transaction { $0.animation = nil }
            .onAppear { start() }
            .onChange(of: rssi) { _, _ in start() }
    }

    func start() {
        guard !reduceMotion else { return }
        breathe = false
        withAnimation(.easeOut(duration: period).repeatForever(autoreverses: false)) { breathe = true }
    }
}

// ================= 待机流光 (idea 75) =================
// 已连接空闲时一圈靛蓝流光沿外沿慢速环绕, 断开即停 (调用方只在就绪空闲态挂载);
// reduceMotion 下**整条不挂** —— 待机氛围属于纯装饰动效。
// 2026-10-15 走查: 原来只在 `.onAppear` 里 `guard !reduceMotion` 挡住动画, 视图本身照样在树上 ——
// `angle` 停在初值 0, 于是装饰档在"减少动效"下反而变成一段**冻住的靛蓝弧**常亮在盘外沿。
// 注释写的是"不出现", 代码给的是"出现但不动": 这一族的判据是**该不该在树上**, 不是动画开没开。

// ================= 65 雷达波纹 (Find My 查找) =================
// 只在**握手中**挂载: `.connecting` 起、进就绪即停 (调用方按状态决定在不在树上，本视图不判状态)。
// 与 UnlockPulseRing 的差别不是"再画一圈"，而是**同时两圈、相位错开** —— 单圈呼吸读起来是"在忙"，
// 两圈外扩才读成"在喊它"。reduceMotion 下不出现 (装饰档，同 75 流光)。
// 2026-10-15 走查: 相位错开原先是**没落地的**。两圈共用同一枚 `on`, 而 `onAppear` 对同一个属性连发两次
// `withAnimation` —— 后发的那次 (不带 delay) 覆盖了前一次 (带 .delay(0.55)) 的动画事务, 两圈同起同落,
// 视觉上就是一根加粗的单环, 正是上面那句要避开的"在忙"。相位要按**每圈自己的态**驱动才成立。
// 顺带同 75 那条: reduceMotion 的降级落在"挂不挂"这一层, 不是在 onAppear 里挡动画 —— 挡了动画两圈就 static 地留在盘上。


// ================= 73 成功涟漪 (Apple Pay 完成动画) / 1009 涟漪结界 =================
// 1009 原案"上锁成功后的涟漪结界"判 ❌: 协议根本没有上锁命令与状态位 (CAPABILITY §5)，涟漪没有真实触发点。
// 拍板口径是"改挂协议确证的事件，动效不变" —— 挂的就是下面这条 73 的**指令确认瞬间**，
// 所以 1009 不再有独立实现，也不该有: 为一个没有触发事件的动效造触发点，就是凭空发明状态。
// IDEA-BANK 原句是"**指令确认瞬间**扩散一圈靛蓝渐变涟漪"，落点在 176pt 圆盘 —— 与已有的
// `shock` 不是同一个东西: shock 是 `.success`(开门**结果**回来)后的绿圈冲击波。两者时刻不同、
// 语义不同 (发出指令已确认 vs 锁真的开了)，所以各留各的: 这里走靛蓝、只在 .opening 触发一次。



// ================= 三段进度细条 (idea 80/89) =================
// 握手 / 鉴权 / 执行 三段填充; 握手超 4 秒由靛蓝转橙 (idea 89)。
struct PhaseBar: View {
    var phase: Int      // 0 无 · 1 握手 · 2 鉴权 · 3 执行
    var slow: Bool
    var width: CGFloat

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i <= phase ? tint : DS.Palette.hairline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
            }
        }
        .frame(width: width)
        .animation(DS.Motion.quick, value: phase)
        .animation(DS.Motion.quick, value: slow)
        .accessibilityHidden(true)
    }
    var tint: Color { slow ? DS.Palette.warn : DS.Palette.accentText }
}