// 反控 3: 这页从没被 sheet 端出来过 => 不在本闸门范围（Tab 根上换 Tab 本来就该只写值）。
import SwiftUI
struct OkPlainTab: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Button("去设备页") { app.tabSelection = 0 }
    }
}
