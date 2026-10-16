import SwiftUI
struct ComposedOnlyView: View { var body: some View { Text("x") } }
struct SheetPresentedView: View { var body: some View { Text("y") } }
struct LinkedView: View { var body: some View { Text("z") } }
struct FullScreenView: View { var body: some View { Text("f") } }
struct NavDestView: View { var body: some View { Text("n") } }
struct PopoverView: View { var body: some View { Text("p") } }
struct TabbedView: View { var body: some View { Text("t") } }
struct BindingSheetView: View { var body: some View { Text("b") } }
struct CommentOnlyView: View { var body: some View { Text("c") } }
struct PropTabView: View { var body: some View { Text("pt") } }
struct HostView: View {
  @State private var on = false
  @ViewBuilder private var tabContentProp: some View { PropTabView() }
  var body: some View {
    TabView {
      Tab("一", value: 1) { TabbedView() }
      Tab("二", value: 2) { tabContentProp }
    }
    .sheet(isPresented: Binding(get: { on }, set: { v in on = v })) {
      BindingSheetView()          // 目的地 (参数含括号的 sheet)
    }
    .sheet(isPresented: $on) {
      SheetPresentedView()        // 目的地 (sheet)
    }
    .fullScreenCover(isPresented: $on) { FullScreenView() }
    .navigationDestination(for: String.self) { _ in NavDestView() }
    .popover(isPresented: $on) { PopoverView() }
    .background(
      NavigationLink("l") { LinkedView() }   // 目的地 (NavigationLink trailing)
    )
    // 反控 4：注释里的实例化不算目的地（旧实现会把这一句当真的呈现）
    // CommentOnlyView()
    .overlay { ComposedOnlyView() }          // 只是构件, 不是目的地
    .sheet(isPresented: $on) { SystemishNotDeclaredHereView() }  // 外部类型, 不算目的地
  }
}
