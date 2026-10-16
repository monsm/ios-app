import SwiftUI
struct EmptyVK {
    func title(_ t: String) -> AnyView {
        switch variant {
        case .legacy: return AnyView(Text(t))
        case .core: return AnyView(Text(t))
        case .gauge: return AnyView(EmptyView())
        }
    }
}
