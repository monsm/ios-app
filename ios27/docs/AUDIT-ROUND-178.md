# AUDIT-ROUND-178 · 第 178 轮：把「对项目枚举用 `default`」的 5 处补成穷尽

> CI：**`bab117d` 已验证绿**（build_ok=1 errors=0 warnings=0）；`23d9a46` 待回执。

## 1. 本轮扫的 4 类

| # | 模式 | 命中 | 结论 |
|---|---|---|---|
| A | 同一键读写**值类型**不一致（Int 写 / getString 读） | **0** | ✅（上一轮修完 `kf_logsync_` 后归零）|
| B | 同一键 + 同一 getter 但**默认值**不一致 | 5 | 全是假红：`BackupKit` 用 `has(key) ? get(key) : nil` 守卫；`kf_bk_base` 是"显示用默认"与"逻辑用默认"的区别 |
| C | 日期字符串用 `<`/`>` 直接比较 | **0** | ✅ |
| D | **对项目枚举 `switch` 却写 `default`** | 10 | 4 个是系统枚举（`CBManagerState`/`LABiometryType`/`ScenePhase`，必须 default）；**5 个项目枚举已改穷尽**；1 处重复分支已合并 |

## 2. 为什么要改：`default` 会静默吞掉新增 case

本仓自己的纪律是「枚举分支用 `switch` 而不是三元，因为 `switch` 有穷尽检查」。
但**`switch` + `default` 把这个好处又还回去了** —— 新增一个 case 时编译器不会报错，
它会安静地落进 `default`，用上一个 case 的语义。

### 改了哪几处

| 文件 | 枚举 | 原来 | 现在 |
|---|---|---|---|
| `Primitives.swift` | `Tone`（5 case） | `default: Circle()` | `case .ok, .neutral, .live: Circle()` |
| `V7Extras.swift` | `Tone`（5 case） | 同上 | 同上 |
| `AddLockScreen.swift` | `Phase`（5 case） | `default: candidates.isEmpty ? .neutral : .ok` | `case .scanning, .ready:` |
| `DFUScreen.swift`（tone） | `Phase`（5 case） | `default: app.lock == nil ? .neutral : .attention` | `case .idle, .ready:` |
| `DFUScreen.swift`（word） | `Phase`（5 case） | `default: pkg == nil ? "待选择固件包" : "包已就绪"` | `case .idle, .ready:` |

**语义完全不变** —— 只是把"这些 case 归为一类"从隐含变成显式。

## 3. 顺带合并一处重复分支

```swift
// KeyDetailScreen.consumeRoute（旧）
switch context {
case .key(let id):            keyID = id
case .dest(.keyDetail):       if keyID == nil { keyID = app.keys.first?.id }
default:                      if keyID == nil { keyID = app.keys.first?.id }   // ← 与上一支完全相同
}
```

两个分支体一模一样 —— 复制粘贴留下的。而且 `default` 会把**任何其它路由**也吞进来、
默默选中第一枚凭证。合并成一个 `default`，注释写清"除了明确指定 id，其余都回落到第一枚"。

## 4. 明确不改的 4 处（系统枚举）

| 位置 | 枚举 | 为什么不改 |
|---|---|---|
| `BLEService.swift:124` | `CBManagerState` | 系统枚举，Swift 要求 `default`（应写 `@unknown default`） |
| `SecurityScreen.swift:168` | `LABiometryType` | 同上 |
| `LockKeeperApp.swift:114` | `ScenePhase` | 同上，且 `.inactive` 是有意忽略 |
| `RecordsScreen.swift:897` | `Dest?` | `default: break` 是"其余路由与我无关"的正确写法 |

## 5. 方法论

**`switch` 的价值有一半在 `default` 之外 —— 写了 `default` 就只剩语法糖。**

| 写法 | 新增 case 时 |
|---|---|
| 三元 / `if-else` | 静默走 else |
| `switch` + `default` | **静默走 default**（与三元同） |
| **`switch` 穷尽** | **编译报错，强制决定** |

所以判据是：**对"自己定义的枚举"永远不要写 `default`；只对系统枚举写**（且优先 `@unknown default`）。
