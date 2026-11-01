# AUDIT-ROUND-161 · 第 161 轮：修掉上一轮埋的布局回归 + 把原则写进闸门

> CI：`95a036a` 已验证绿；`18f63cd` / `e3c2cd3` 待回执。本轮本地提交。

## 1. 先修我自己埋的回归：Tab 栏长高了，底部留白没长

ROUND-158 我把浮动 Tab 栏从 `frame(height:)` 改成了 `frame(minHeight:)`（为了不裁字）。
**但 `Shell` 的底部留白是写死的**：

```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    Color.clear.frame(height: V.Tab.contentInset)   // 92pt，固定
}
```

于是字号放大时栏变高、留白不变 ⇒ **最后一屏内容被压在栏下面**（滚到底也看不到）。

## 2. 修法：留白跟着栏的实测高度走

```swift
@State private var tabBarHeight: CGFloat = V.Tab.contentInset
...
.safeAreaInset(edge: .bottom, spacing: 0) {
    Color.clear.frame(height: max(V.Tab.contentInset, tabBarHeight + V.Tab.bottom + V.S.gapS))
}
...
.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
    tabBarHeight = h
}
```

用原生 `onGeometryChange`（iOS 18+）量**实际**高度，而不是自己按字号估 —— 估算会随
字体曲线不同而错位，实测不会。

`max(V.Tab.contentInset, …)` 是兜底：首帧还没量到时保持旧值，不会出现"留白为 0、内容跳到栏下"。

## 3. 把「固定高度会裁字」写进闸门

`a11y.js` 新增一条**窄判据**（只认两个令牌名，假红率为 0）：

```js
const mFixedH = /\.frame\(\s*height:\s*V\.(Action|Tab)\.height\s*\)/.exec(line);
```

为什么这两个：

| 令牌 | 内部文字 | 为什么会裁 |
|---|---|---|
| `V.Action.height`（50） | `V.F.bodyStrong` 17pt 随 `.body` 缩放 | AX 档可到 53pt |
| `V.Tab.height`（57） | 20pt 图标 + 2 + `V.F.tab` 11pt 随 `.caption2` | AX 档文字压不下 |

双向验证：注入 `.frame(height: V.Action.height)` → 判红并给出正确文案；删掉 → 22/22 全绿。

## 4. 两个「不改」的判断（都记录了理由）

| 组件 | 原生替代品 | 为什么不换 |
|---|---|---|
| `VMiniBars` / `VAreaChart` | Swift Charts | 它是 **24 格 × 1.8pt 柱 + 5pt 辉光**的密集波形，`BarMark` 没有对应形态；换了是"换设计"不是"原生化" |
| `VSegmentedRing` / `VRingStack` | `Gauge` | 原生 `Gauge` 是**单值**环形；这两个是**多段**环（每段一个颜色 + 压暗层），系统没有对等物 |

## 5. 方法论

**改「尺寸策略」时，要连带查「依赖这个尺寸的地方」。**

我把 `height` 改成 `minHeight` 时只想着"字不被裁"，没想到**底部留白是按旧高度算的** ——
两者是一对，改一个必须改另一个。

判据：**改一个尺寸令牌的用法后，grep 这个组件的"高度"在别处有没有被假设**
（留白、对齐、遮罩、动画的起止点都算）。

另一条：**窄判据比宽判据值钱**。这条闸门只认两个令牌名，所以能做到"假红为 0"，
也就真的能长期开着；而"所有固定高度都判红"那种宽判据，第一天就会被忽略。
