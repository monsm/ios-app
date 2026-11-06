// Tone.swift —— 读数的语义色调。Engine 的 Reading.Value 用它，所以名字与四个 case 必须保留。
import SwiftUI

enum Tone: Equatable {
    case neutral
    case ok
    case attention
    case critical

    var color: Color {
        switch self {
        case .neutral: return T.C.ink2
        case .ok: return T.C.ok
        case .attention: return T.C.brass
        case .critical: return T.C.danger
        }
    }
}
