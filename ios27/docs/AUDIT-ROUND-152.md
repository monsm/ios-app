# AUDIT-ROUND-152 · 第一百五十二轮：信号永远显示「0 / 4」并涂警告色

> CI：`9a1b52b` 已验证绿；`70cba7a` / `3d64e82` 待回执。本轮本地提交。

## 1. 缺陷：`LockSummary.signal` 硬编码 0

```swift
// AppModel:117（旧）
signal: 0,        // 注释写「0 = 未知」
```

而显示侧把它当成真值：

```swift
// LockStatusScreen:91-92
.init(label: "信号", value: "\(lock.signal)", unit: "/ 4",
      tint: lock.signal <= 1 ? V.C.warning : V.C.text1),
```

于是**永远显示「信号 0 / 4」并涂成警告色**。用户看到的是"信号极差"，
而实际是**从未测过** —— 一个恒定的假读数比"未知"更糟，因为它看起来像测过。

## 2. 同一个映射早就有实现

```swift
// LinkSense.swift:50-57
static func level(_ rssi: Int?) -> Int {
    guard let r = rssi else { return 0 }
    if r >= -55 { return 4 }
    if r >= -65 { return 3 }
    if r >= -75 { return 2 }
    if r >= -85 { return 1 }
    return 0
}
```

**`LockSummary.signal` 与 `LinkSenseModel.level` 是同一个语义（0–4 档，0 = 不可测）** ——
一处实现了，另一处占位。

## 3. 修法

```swift
signal: LinkSenseModel.level(LinkSenseModel.savedRSSI(mac)),
```

## 4. 顺带修了闸门 22 的一个设计缺陷（我自己撞上的）

改 `AppModel` 时，`memberfill` 报：

```
App/Shell/AppModel.swift:193  构造 KeyItem 时没传 createdAt
```

而**那条本来就是豁免项**（手机钥匙没有创建时刻）—— 我改 `signal` 时在文件上方插了几行，
行号从 189 挪到 193，**按 `file:line` 的豁免就失配了**。

这正是"用行号做豁免"的通病。改成按**构造内容特征**：

```js
const EXEMPT_PATTERNS = [
  { why: "手机钥匙无创建时刻", re: /kind:\s*\.mobile/ },
];
```

双向验证：删掉 `withDisabled` 的 `createdAt` → 仍判红；手机钥匙那条挪到哪里都仍豁免。

## 5. 方法论

**「恒定的假值」比「未知」更糟** —— 因为未知会让人去查，假值不会。

| 字段值 | 用户看到 | 后果 |
|---|---|---|
| `nil` / "未知" | 「未读到」 | 会去查 |
| **恒 0 且被当真值渲染** | **「0 / 4」+ 警告色** | **以为信号差，永远不会去查** |

判据：**凡是"恒为占位值"的字段，要么别渲染，要么渲染成"未知"。**

另一条（闸门设计）：**豁免条件不要用行号** —— 行号会被无关编辑打乱。
用"这一行/这一段的**内容特征**"做豁免，才是稳定的。
