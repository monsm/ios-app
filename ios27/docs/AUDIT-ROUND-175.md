# AUDIT-ROUND-175 · 第 175 轮：地毯式逻辑扫描（6 类模式），抓到 3 处

> 新 objective：地毯式找逻辑 bug 或不合理。本轮先做**可机械判定**的六类模式，
> 每类都跑全仓，命中的逐条读代码确认 —— 不靠"看起来像"。

## 1. 扫了哪些模式

| # | 模式 | 命中 | 结论 |
|---|---|---|---|
| A | `if` / `else` 分支体完全相同（复制粘贴 bug） | **0** | ✅ |
| B | 连续 `else if` 使用同一条件 | **0** | ✅ |
| C | 强制解包 `!` / `try!` / `as!` / `Int(...)!` | **0** | ✅ |
| D | 空 `catch {}`（吞错误） | **0** | ✅ |
| E | 空 `Button {}`（点了没反应） | 13 | ✅ 全是对话框「取消」+ 1 处 Preview |
| F | 数组下标算术无边界守卫 | 10 | ✅ 10/10 都有循环边界或 `contains` 守卫 |

## 2. 抓到的第 1 处：**配网页的「场所副标题」输入框从不落库**

```swift
// AddLockScreen
@State private var place = ""                     // 39 行：声明
TextField("场所副标题（如 玄关 / 车库，可留空）", text: $place)   // 355 行：绑定
// commitName()（534 行）只写了 kc.name —— place 从未被读取
```

全仓 grep `place`：本文件里只出现在这两行。**用户填了等于白填，而且界面上看不出没保存。**

修法：`commitName()` 里与「锁档案」页的保存口径一致，写进 `LockArchive.meta.place`：

```swift
let trimmedPlace = place.trimmingCharacters(in: .whitespaces)
if !trimmedPlace.isEmpty {
    var m = LockArchive.meta(mac)
    m.place = trimmedPlace
    LockArchive.save(mac, m)
}
```

## 3. 抓到的第 2 处：`ShareToAndroidScreen.passphrase` 是死状态

```swift
@State private var passphrase = ""   // 全仓仅此一行
```

声明了、没有任何绑定、没有读取 —— 删掉。

## 4. 抓到的第 3 处：一条**过期的注释**在骗人

```swift
// RecordsModels.swift:8（旧）
// 拉取链路（cmd16 翻页）仍待 Engine 接线，见 RecordsScreen.read() 的 TODO(engine)。
```

实际上 `RecordsScreen.read()` 早就接了：`read() → app.readLogs() → cmd16 翻页`，
而且 `read()` 里**根本没有 TODO(engine)**。

危害：下一个人读到这句会以为"台账还没接线"，于是重复实现或绕开。改成事实：

```swift
// 拉取链路已接线：`RecordsScreen.read()` → `AppModel.readLogs()` → cmd16 翻页（最多 20 页 × 5 条）。
// 本文件只负责**解析与合并缓存**，不碰蓝牙。
```

## 5. 排除的 4 类（读了代码，不是"没命中"）

| 疑点 | 实情 |
|---|---|
| `Dial.swift:99` `Double(i)/Double(tickCount)` | `tickCount` 是常量 > 0 |
| `V7Components:555` `CGFloat(values.count - 1)` | 上面一行 `guard values.count >= 2 else { return }` |
| `KeysScreen` 多处 `Double(x)/Double(total)` | `let total = max(app.keys.count, 1)` |
| `KeyGen:56` / `ZOTP:55` 的 `[i-1]` / `[i+1]` | 都在 `1..<16` / `while i+1 < bytes.count` 的循环里 |

## 6. 方法论

**"地毯式"不等于"全都读一遍"，而是"每种模式都跑一遍，命中的逐个读"。**

| 层 | 做什么 |
|---|---|
| 机械层 | 用固定图案扫全仓（本轮 6 类） |
| 人工层 | **只读命中的那几行**，判断真假 |
| 记录层 | 把"排除的疑点"也写下来（第 5 节） |

第三层最容易被省掉。省掉的后果是：下一个做地毯扫描的人会把同样 4 个疑点再查一遍。

另外一条：**"写了但没读"是一个极高产的模式。**
本轮 3 处里 2 处都是它（`place` 只写不读、`passphrase` 只声明）——
与上一段的 `readAt`、`PressStyle` 是同一个家族的缺陷。
