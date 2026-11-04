# AUDIT-ROUND-164 · 第 164 轮：**软废弃 API** 全量扫描（0 告警 ≠ 用的是新 API）

> 本轮加载了新增的 `swiftui-pro` skill，它的 `references/api.md` 给了一条关键提醒：
>
> > Many older SwiftUI declarations use `deprecated: 100000.0` … **Xcode stays quiet,
> > so a warning-free build does not establish that the code uses current API.**
>
> 这解释了为什么本仓 CI 一直 `warnings=0`，却仍可能用着过时写法。以下是逐条扫描结果。

## 1. 已修复：`.toolbar(.hidden, for:)` → `.toolbarVisibility(...)`

4 个 Tab 根页都用了旧写法：

| 文件 | 行 |
|---|---|
| `DoorScreen.swift` | 68 |
| `KeysScreen.swift` | 92 |
| `RecordsScreen.swift` | 121 |
| `SettingsScreen.swift` | 69 |

```swift
// 旧（iOS 18 起软废弃）
.toolbar(.hidden, for: .navigationBar)
// 新
.toolbarVisibility(.hidden, for: .navigationBar)
```

## 2. 全量扫描结果（16 条规则）

| 规则 | 命中 | 判定 |
|---|---|---|
| `foregroundColor(` | **0** | ✅ 全部 `foregroundStyle` |
| `accentColor(` | **0** | ✅ |
| `cornerRadius(` | **0** | ✅ 全部 `clipShape(.rect(cornerRadius:))` |
| `tabItem(` | **0** | ✅（本仓没有 `TabView`，见 §4） |
| `onChange` 单参数 | **0** | ✅ 19 处**全部**是 `{ old, new in }` 双参数形式 |
| `GeometryReader` | 1 | 判定不改（见 §3） |
| `navigationBarHidden(` | **0** | ✅ |
| `statusBarHidden(` | **0** | ✅ |
| `autocapitalization(` | **0** | ✅ 全部 `textInputAutocapitalization` |
| `disableAutocorrection(` | **0** | ✅ 全部 `autocorrectionDisabled` |
| `coordinateSpace(name:)` | **0** | ✅ |
| `Color.cgColor` | **0** | ✅ |
| `UIImpactFeedbackGenerator` 家族 | **0** | ✅ 全部走 `sensoryFeedback` |
| 手写 `EnvironmentKey` | **0** | ✅ |
| `.toolbar(.hidden/.visible` | **4 → 0** | ✅ 本轮修复 |
| `.toolbarBackground(.visible` | **0** | ✅ |

## 3. 两个「不改」的判断

**（a）`VMiniBars` 的 `GeometryReader`**

`swiftui-pro` 说优先用 `containerRelativeFrame()` / `visualEffect()` / `Layout` 替代。
但这里它只做一件事：读宽度算 24 格的槽宽，且外层已 `frame(height: V.Mini.gridH)` 固定高度 ——
**没有 GeometryReader 的典型问题**（撑满父级 / 打乱布局）。
改用 `Canvas` 需要重做 5pt 辉光（`GraphicsContext` 的 shadow filter），收益低、风险中。不改。

> 另外 `api.md` 明确写了：「Reading reserved regions on iOS 27.1+ is a valid exception:
> locating the fold or cameras requires a GeometryProxy … **Do not flag that usage**.」
> 本轮 `Shell.swift` 新加的 `onGeometryChange` 属于这一类（量栏高），是**允许的**。

**（b）`ZotpScreen:109` 的 `onTapGesture(count: 2)`**

`accessibility.md` 说「除非确实需要点击次数，否则别用 `onTapGesture`」。这里**正是**需要点击次数
（双击切换字号），属允许范围；且有 `accessibilityHint("…双击切换字号")`，
另有一条全局 `AXSettings.bigOTP` 作为 VoiceOver 可达的等价路径。不改。

## 4. 顺带确认：本仓没有 `TabView`

`tabItem(` 命中 0 是因为**整个 App 用的是自定义浮动 Tab 栏**（`VFloatingTabBar`），不是 `TabView`。
这是一个**有意的设计选择**（268pt 居中的胶囊，不是系统全宽标签栏）。
换成 `TabView` 会改变整个 App 的骨架与 Router 结构 —— 不在"原生化"的合理范围内，记录为**设计取舍**。

## 5. 方法论

**`warnings=0` 只证明"没有硬废弃"，不证明"用的是现代 API"。**

| 废弃类型 | Xcode 表现 | 怎么发现 |
|---|---|---|
| 硬废弃 | 编译告警 | CI 的 `warnings=` 字段 |
| **软废弃（`deprecated: 100000.0`）** | **完全安静** | **只能靠规则清单逐条扫** |

所以「CI 零告警」这条守了很久的纪律，覆盖不到这一类。本轮补上的正是这个盲区。
