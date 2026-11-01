# AUDIT-ROUND-180 · 第 180 轮：死掉的 `resultAnimation` 与它漂掉的取值

> CI：**`38a9f13` 已验证绿**；`3ccfc9a`（12/24 制式）待回执。

## 1. 判据：把 `SettingsStore` 的 52 个属性逐个查"有没有人读"

起因是上一轮那类"设置只有一半生效"。做法：

```
列出 SettingsModel.swift 里的 4 空格缩进 var  →  52 个
对每个名字统计「除本文件外的 \.name 引用数」      →  只有 1 个为 0
```

唯一零引用的叫 `resultAnimation` —— 但一查，它其实是 `MotionTier` 上的计算属性（缩进相同被骗了）。
**不过顺着它挖出了真问题。**

## 2. 缺陷：映射写了、没人用、而且已经和线上不一致

```swift
// SettingsModel.swift（旧）
var resultAnimation: Animation? {
    switch self {
    case .calm:     return nil
    case .standard: return V.M.snap      // ← 线上实际用的是 .move
    case .lively:   return V.M.settle
    }
}
```

而真正的消费点在 `LockKeeperApp`，写的是内联嵌套三元：

```swift
.animation(reduceMotion ? nil : (settings.motion == .calm ? nil
          : (settings.motion == .lively ? V.M.settle : V.M.move)), value: app.unlocked)
```

两处**不是同一套取值**：`standard` 这里给 `.snap`、线上给 `.move`。

这正是"写了但没接上"的第二种危害 —— **不只没人用，还在无人察觉的情况下漂了**。
如果有人图省事把那行三元换成 `settings.motion.resultAnimation`，
开锁结果的动画会从 `.move` 悄悄变成 `.snap`（更急、更硬），而没有任何测试会发现。

## 3. 修法：对齐到线上行为，并让唯一消费点调用它

```swift
// SettingsModel.swift（新）
case .standard: return V.M.move      // 对齐线上实际行为
```

```swift
// LockKeeperApp.swift（新）
.animation(reduceMotion ? nil : settings.motion.resultAnimation, value: app.unlocked)
```

两个收益：

| 收益 | 说明 |
|---|---|
| 映射只有一处 | 不会再出现"两套取值" |
| **消掉嵌套三元** | 本仓纪律要求枚举分支用 `switch` 而不是三元 —— 那段内联写法正是反例 |

行为**完全不变**（因为对齐的是线上那套值）。

## 4. 顺带修一条过期注释

```swift
// BatteryCare.swift（旧）
/// 动效令牌 (DesignSystem.Motion) 每次求值都问这里,
```

全仓根本没有 `DesignSystem.Motion` 这个类型（grep 只命中这条注释本身）。改成实际存在的 `V.M` / `V.Motion`。

## 5. 一个**记录不改**的观察

「动效强度」（calm / standard / lively）目前**只影响一处**：`LockKeeperApp` 里开锁闸门 → 主界面的切换动画。
其余所有 `.animation(V.M.*)` 用的都是静态令牌，不随档位变。

要让它全面生效，得把 `V.M` 从 `static let` 改成"按档位求值"——那会改变全 App 每一处动画的时长/曲线，
属设计决定，且有 reduce-motion 叠加后的多次组合需要真机验证。**记录，不改。**

## 6. 方法论

**"写了但没接上"的第二种危害：它会漂。**

| 阶段 | 状态 |
|---|---|
| 刚写完 | 与线上一致 |
| 线上改了（直接改内联那处） | **未使用的那份开始漂** |
| 后来者"顺手复用" | **静默改变行为** |

所以对"零调用的辅助函数"，处置不只有"删掉"一种 ——
**如果它承载的是本该唯一化的映射，正确做法是"对齐 + 接上"**（本轮）。
删掉也行，但会丢掉那次唯一化的机会。
