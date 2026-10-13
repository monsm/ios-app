# API-VERIFY — 本仓用过的 Apple API 逐个撞官方文档的记录

> 为什么要有这份文件：**本机没有 Xcode、没有模拟器，CI 自 run 44 起连红四场**（最后一次编译通过
> 是 run 43 / 2026-10-07），所以 2026-10-07 之后写的每一行 Swift 都没有被编译器看过。
> 而这段时间里最贵的缺陷全是同一类——**臆造 API**。形状闸门（`tools/swiftshape.js`）抓不住参数名写错、
> case 名安错类型这类问题，只有编译器抓得住。在等到一次真编译之前，唯一可行的替代是拿官方文档当第二双眼睛。
>
> 手法（两轮，都可复现）：
> 1. **撞页面**：`https://developer.apple.com/tutorials/data/documentation/<Module>/<Type>/<member>.json`
>    返回 200 且 `metadata.platforms` 里没有 `deprecated` / `unavailable` ⇒ 该成员在当前 SDK 存在。
> 2. **列父页成员**：撞不到就把父类型页 JSON 里的 `references` + `topicSections` + `primaryContentSections`
>    全列出来查名字。**这一步才能把"slug 猜错"与"API 真的不存在"分开**——`SwiftUI/View` 那一页只列出
>    19 个成员（Apple 文档分页），拿它当"全名单"会误判 `contentShape` 不存在，而它其实全仓用了 200 多处。
>
> 读这份表的方式：`存在` = 两轮里至少有一轮正面命中；`不存在` = 父页成员名单里没有它（这才是判失败的证据）；
> `文档未列全` = 撞不到但本仓在 run 43 之前就这么写并且编译通过 ⇒ 判"文档覆盖不全"，不是判"API 不存在"。

| 用法（本仓写法） | 官方页 | 结论 | 备注 |
|---|---|---|---|
| `Section(isExpanded:content:header:)`（设备管理页 104 分组头可收起） | `SwiftUI/Section/init(isExpanded:content:header:)` 200 | 存在 | 同一页还列出 `init(_:isExpanded:content:)`；标题必须是纯 `Text` 才有折叠箭头 |
| `.onMove { src, dst in }`（766 拖动排序，全仓第一处） | `SwiftUI/DynamicViewContent` 成员名单**含 onMove** | 存在 | 挂在 `DynamicViewContent`（`ForEach` 遵从它）上，**不在 `SwiftUI/View` 名单里**——挂在逐行上会让每行都收到同一份 IndexSet，所以写在 `ForEach` 上 |
| `.safeAreaInset(edge: .bottom) { … }` | `SwiftUI/View/safeAreaInset(edge:alignment:spacing:content:)` 200 | 存在 | `alignment`/`spacing` 都有默认值，只传 `edge:content:` 合法 |
| `.accessibilityElement(children: .combine/.contain)` | `SwiftUI/View/accessibilityElement(children:)` 200 | 存在 | 多选行用 `.contain`：`.combine` 会把那枚勾选按钮从 VoiceOver 里抹掉 |
| `.accessibilityAddTraits(on ? [.isSelected] : [])` | `SwiftUI/View/accessibilityAddTraits(_:)` 200 | 存在 | |
| `.onTapGesture(count:perform:)` / 无参版 | `SwiftUI/View/onTapGesture(count:perform:)` 200 | 存在 | |
| `.truncationMode(.tail)` | `SwiftUI/View/truncationMode(_:)` 200 | 存在 | 非拉丁长名截断的唯一可控出口 |
| `.buttonStyle(_:)` / `.pickerStyle(_:)` | 各自 200 | 存在 | |
| `Binding(...).constant(...)` | `SwiftUI/Binding/constant(_:)` 200 | 存在 | `\.editMode` 也在（`SwiftUI/EnvironmentValues/editMode` 200，无 deprecated 标记）⇒ 设备管理的「排序」模式注入 `editMode` 是合法写法 |
| `Button("删除设备", role: .destructive) { }` | `SwiftUI/Button/init(_:role:action:)` 200 | 存在 | 全仓 36 处，其中 4 处在 run 43 绿的那版 SettingsView 里 |
| `ToolbarItem(placement: .navigationBarTrailing)` | `SwiftUI/ToolbarItem/init(placement:content:)` + `ToolbarItemPlacement/navigationBarTrailing` 均 200 | 存在 | |
| `Calendar.date(bySettingHour:minute:second:of:)`（`TimeFormat.dayEnd()` 用） | `Foundation/Calendar` 的引用里含 `date(bySettingHour:minute:second:of:matchingPolicy:repeatedTimePolicy:direction:)` | 存在 | 后三个参数有默认值。**它替代的就是下面那条臆造写法** |
| `Calendar.date(bySetting: .hourAndMinute(23, 59), of:)` | `Foundation/Calendar/Component` 成员名单里含 hour/minute 的只有 **`.hour` 与 `.minute`** | **不存在** | 已修（`TimeFormat.swift:87` 上方记着）。`.hourAndMinute` 是 `DatePicker(displayedComponents:)` 那一侧的名字，且 enum case 不能带参数。凭证工坊两处表单各抄了同一份错误 |
| `Character.wholeNumberValue`（`Speech.digits` 用） | `Swift/Character` 成员名单含它 | 存在 | 注意模块是 `Swift` 不是 `Foundation` |
| `AVSpeechUtterance(string:)` / `AVSpeechSynthesisVoice(language:)` / `synth.isSpeaking` / `synth.stopSpeaking()` | `AVFAudio/…` 四个页面（`stopSpeaking` 在父页成员名单里） | 存在 | 模块是 **AVFAudio**；按 `AVKit` 撞会 404 |
| `UIAlertController.addTextField { tf in … }` | `UIKit/UIAlertController` 成员名单含 addTextField | 存在 | 全仓 30+ 处在用 |
| `.contentShape(Rectangle())` | `SwiftUI/View` 页只列 19 个成员，未列它 | 文档未列全 | run 43 之前就这么写且编译通过 ⇒ 判文档分页覆盖不全，不判 API 不存在 |
| `.chartYAxis(.hidden)` | 撞不到：`Charts/View/chartYAxis(_:)`、`Charts/AxisMark(s)Visibility`、`SwiftUI/View/chartYAxis()` 全 404 | **弃用这一写法** | 608 那批小图本来要隐藏 y 轴。**撞不到不等于不存在** (Charts 那棵树的 slug 规律没摸清：`Charts/BarMark` 是 200，`Charts/View/...` 却不是)，但在没有编译器的机器上"不确定就别写"是唯一稳的取向 ⇒ 留下默认 y 轴 (反而多一档读数)，代码注释指着这一行 |
| `ChartProxy.position(forX:)` / `position(forY:)`（640 把数值标签排到像素上） | `Charts/chartproxy/position(forx:)` 与 `…(fory:)` 都 200；`metadata.platforms` iOS 16.0、`deprecated:false`、`unavailable:false` | 存在 | 声明逐字是 `func position<P>(forX value: P) -> CGFloat? where P : Plottable`，摘要写明 **returned position is relative to the plot** ⇒ 必须再加 `geo[proxy.plotAreaFrame]` 的 minX/minY 才是画布坐标。父页 `Charts/chartproxy` 一次列出 37 个成员（`value(atX:as:)`/`plotAreaFrame`/`positionRange(forY:)` 都在），而猜出来的 `plotscale` 404 且名单里没有它 —— 这一条就是"列父页成员"这一步的价值 |
| `View.accessibilityElement(children: .ignore)`（621 刷选轨道） | `SwiftUI/View/accessibilityelement(children:)` 200，`SwiftUI/accessibilitychildbehavior/ignore` 200，两者 iOS 13.0 起、无废弃标记 | 存在 | 纯手势控件在读屏下什么都做不了；`.ignore` + label + hint 把"这条轨道拖动才生效，读屏请走 638 点选单日"写在控件上，而不是让 VoiceOver 撞上轨道后沉默 |
| `MeshGradient(width:height:points:colors:background:smoothsColors:colorSpace:)`（32 想做） | 该 init 页 200，但 `points` 的元素类型（`MeshGradient.Point` 的构造器）在 JSON 里取不到 | **待定** | 这就是 DEFERRED 把 32 停在"等一次真编译"门后的具体原因：参数表没确认前写下去就是下一个 `.hourAndMinute` | 指针检查:忽略 (MeshGradient 是 Apple 类型, 本行是有意写出的 API 全名, 不是本仓指针)
| `Calendar.identifier`（第一百五十九批，写 `WeekCal.gregorian` 前撞的） | `Foundation/calendar/identifier-swift.property` 200；iOS 8.0 起、无 deprecated/unavailable | 存在，但**只读** | 逐字声明是 `var identifier: Calendar.Identifier { get }` ⇒ `var c = Calendar.current; c.identifier = .gregorian` 这种"只换历法"的写法**编译不过**。这就是 `WeekCal.gregorian` 必须走 `init(identifier:)` 再逐个照抄旋钮的原因，不是风格选择 |
| `Calendar.firstWeekday` / `minimumDaysInFirstWeek` / `timeZone` / `locale` | 四页均 200，声明分别 `var firstWeekday: Int { get set }`、`var minimumDaysInFirstWeek: Int { get set }`、`var timeZone: TimeZone { get set }`、`var locale: Locale? { get set }`；iOS 8.0 起无废弃 | 存在且可写 | 四个旋钮都能显式赋值 ⇒ `gregorian` 能"只钉历法、其余原样跟随系统"。`locale` 是可空的 `Locale?`，照抄 `Calendar.current.locale` 不需要解包 |
| `Calendar.init(identifier:)` 的**默认值** | 页面 200，`primaryContentSections` 只有 `declarations` 与 `parameters` 两节，没有任何 discussion/默认值说明 | **文档未承诺** | 所以裸写 `Calendar(identifier: .gregorian)` 去算"周几"是不可靠的：它按哪个时区切日没有约定，与隔壁用当前时区算出的"几点"可能落在两个日子里（674 就是这么修的）。需要公历时一律走 `WeekCal.gregorian`，它把这四个旋钮显式抄齐 |
| `DataScannerView { session in session.supportedDataTypes = [.qr, .dataMatrix] } results: { … }`（`CredentialStudio.swift:356-358`，522 相机取号，也是 411 扫码接收侧要复用的那一个） | 撞页面 404：`tutorials/data/documentation/visionkit/datascannerview.json` 取不到；`documentation/visionkit.json` 的成员清单里**没有任何 Scanner/CodeReader 符号**；在线检索只命中 UIKit 那个 `DataScannerViewController`（其可识别类型是"机器可读码/文本"这一档，不是 `.qr`/`.dataMatrix` 这种码制名） | **待定，且高度可疑** | 三处可疑：① SwiftUI 侧是否真有这个 `init(sessionHandler:results:)`；② `supportedDataTypes` 的取值枚举名对不对（`.qr`/`.dataMatrix` 像是 `VNCodeObjectType` 那一族的名字）；③ 回调用的是 `r.data.item?.string`，与文档里 `DataScannerItem` 的形状没对上。按本仓既有裁定（`.chartYAxis(.hidden)` 那次）：**撞不到又高度可疑 = 不要靠猜改**。这条挂在 CI 第一道 `error:` 上定位最省 —— 一旦报错就把整块换成 UIKit `DataScannerViewController` 包 `UIViewControllerRepresentable`，或按 522 原句"失败回退人工输入"把扫码做成可选路径。**在编译器看过之前，不许有人凭记忆重写它** |

| `TabView.contextMenu(forSelectionType:tabBar:primaryAction:)`（26 Tab 长按快捷菜单，`App/LockKeeperApp.swift` RootView 的 TabView 上） | 本批现场撞页 **404**：`tutorials/data/documentation/swiftui/view/contextmenu(forselectiontype:tabbar:primaryaction:).json`；父页 `documentation/swiftui/view.json` 按本文件开头那条已知局限（Apple 文档分页，只列 19 个成员）**不能当全名单用** | **未证实（既不是"存在"也不是"不存在"）** | 全仓零先例。首编译若报 "incorrect argument labels"，退路两条，按代价从小到大：① 改成 `contextMenu(forSelectionType:) { } primaryAction: { }` 这一形（参数标签顺序可能就是这样）；② 把同样的动作挂到各 Tab 内容视图的 `.contextMenu`（长按页内元素而不是 Tab 栏项），语义降一档但形状本仓有先例。菜单内容本身不受影响——每一项都只调 `requestTab` / `pendingCredPanel` / `pendingRecordsDay` / `pendingDiag` 这些既有落点口 |
| `CSSearchableItemAttributeSet(contentType:)` 与 `CSSearchableIndex.default()` 一族（293/951，`App/Core/SpotlightKit.swift`） | 本批现场撞页 **404**：`.../corespotlight/csssearchableitemattributeset/init(contenttype:).json`；改撞类页 `.../corespotlight/csssearchableitemattributeset.json` 返回的是 **SPA 的 HTML 壳而不是 JSON**（即该 slug 也不对） | **未证实** | 旧形 `init(itemContentType: String)`（拿 `UTType.item.identifier` 解出来的字符串）是本仓唯一可退的写法，退过去语义不变。`deleteSearchableItems(withDomainIdentifiers:completionHandler:)` 与 `indexSearchableItems(_:completionHandler:)` 本批**没有单独撞页**，与上面同一条 ⚠ 一起等首编译定位。索引内容只读台账、失败只写维护回执，编不过就整文件停用（`SpotlightKit.reindexNow()` 的两个调用点摘掉即可，不影响别处） |
| `AppShortcutsProvider` / `@AppShortcutsBuilder static var appShortcuts` / `AppShortcut(intent:phrases:shortTitle:systemImageName:)` / `AppIntent.openAppWhenRun`（166，`App/Intents/AppIntents.swift:341-387`） | 落地那一批称撞过 iOS 16+ 标准形状页 | **本批未复算 ⇒ 仍按未证实处理** | 记这条的人（我）没有逐字重跑撞页，所以不把它写成"存在"。首编译关注三点：① `phrases` 用中文字面量「离线锁管家」而不含 `\(.applicationName)` 时系统收不收录；② `openAppWhenRun` 在 `AppIntent` 里是不是 `static var { get }`；③ 六条意图都带 `@Parameter`，本轮刻意按"不带 `AppShortcutParameter` 注册"做，若编译器要求补参数声明，就得连带补 `IntentValueQuery`（那条本仓零先例，风险最高） |
| `@Environment(\.horizontalSizeClass)` 与 `containerRelativeFrame(_:count:span:spacing:alignment:)`（643，`App/UI/StatsView.swift:22 / :383`） | 落地那一批称两页均 200、并逐字抄回签名（后者 iOS 17 起、无 deprecated） | **本批未复算 ⇒ 仍按未证实处理** | 643 的**可达性**这一半是查实的、不依赖编译器：`project.yml:65 TARGETED_DEVICE_FAMILY "1"` + `:38-39` 只列 `UIInterfaceOrientationPortrait`，全仓无 `UISupportedInterfaceOrientations` 的 plist 覆盖、无运行时放宽方向的代码 ⇒ 水平档恒 compact，分栏分支当前走不到。所以这两条即使编译通过，也要等放开 iPad 族或横屏那一批才看得到效果；`containerRelativeFrame` 在 `List` 行内把"容器"算成哪一层宽度，只能真机用眼睛判 |
| `DataScannerView { session in … } results: { … }` 的**第三个**调用点（710 扫码核对，`App/UI/ReportVerifyView.swift:29`） | 见上面那行原有的裁定（撞不到 + 高度可疑） | **待定，沿用原裁定** | 新增的这一处是**逐字复用**既有两处形状（含 `fired` 闸与 `cancellationAction`），没有发明新写法 ⇒ 首编译若报错，三处一起换 UIKit `DataScannerViewController` 包 `UIViewControllerRepresentable`，不要只改一处。核对逻辑（`ReportVerify`）与扫码 UI 无耦合，扫码那半挂掉时校验二维码与本机重算仍然可用 |

## 这张表怎么继续用
新增一个不熟的 Apple API 时：先撞页面，撞不到就列父页成员，**两种都空才敢说"不存在"**；
然后把结论补进本表（连同它替代了哪条错写法）。`tools/swiftshape.js` 管形状，这张表管名字，
两者都不替代编译器——真正的判定仍然只有 run 43 那种绿掉的 `build-for-testing` 能给。
