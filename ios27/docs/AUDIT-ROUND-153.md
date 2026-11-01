# AUDIT-ROUND-153 · 第一百五十三轮：电量也显示「-1 %」

> CI：`70cba7a` 已验证绿；`3d64e82` / `b0ca56e` 待回执。本轮本地提交。

## 1. 上一轮修了 `signal`，这一轮 `battery` 是同一类

```swift
// AppModel:116
battery: snap?.powerLevel ?? -1,      // -1 = 未读到
```

```swift
// LockStatusScreen:89-90（旧）
.init(label: "电量", value: "\(lock.battery)", unit: "%",
      tint: lock.battery <= 20 ? V.C.warning : V.C.text1),
```

无快照时 `battery == -1` ⇒ 显示「**-1 %**」并涂警告色。

## 2. 两处的共同形态

| 字段 | 占位值 | 旧渲染 | 新渲染 |
|---|---|---|---|
| `signal` | 0（不可测） | 「0 / 4」+ 警告色 | 「**未测**」 |
| `battery` | -1（未读到） | 「**-1 %**」+ 警告色 | 「**未知**」 |

两处都是 **`<= 阈值` 的 tint 判断把占位值当成了真值**：

```swift
tint: lock.battery <= 20 ? V.C.warning : ...   // -1 <= 20 ⇒ 警告
tint: lock.signal <= 1 ? V.C.warning : ...     // 0 <= 1  ⇒ 警告
```

## 3. 修法

| 字段 | value | unit | tint |
|---|---|---|---|
| 电量 | `battery < 0 ? "未知" : "\(battery)"` | `battery < 0 ? nil : "%"` | `battery >= 0 && battery <= 20` |
| 信号 | `signal <= 0 ? "未测" : "\(signal)"` | `signal <= 0 ? nil : "/ 4"` | `signal == 1` |

注意 tint 的改法：**把占位值从警告条件里排除**（`>= 0 &&`），而不是"把阈值调大"。

## 4. 方法论

**`value <= 阈值 ? 警告 : 正常` 这个写法有一个系统性盲区：占位值几乎总在阈值以下。**

| 占位值 | 阈值判断 | 结果 |
|---|---|---|
| `-1`（未读到） | `<= 20` | 警告（错） |
| `0`（不可测） | `<= 1` | 警告（错） |

判据：**凡是"低值即警告"的 tint，先问"占位值会不会落进来"**；
会的话，条件要写成 `valid && value <= threshold` 两段。

本段这条的战绩：152（`signal`）· **153（`battery`）** —— 同一个结构体（`LockSummary`）里两处。
这正是 §1.1「同族漏一处」：修完 `signal` 就该立刻看 `battery`。
