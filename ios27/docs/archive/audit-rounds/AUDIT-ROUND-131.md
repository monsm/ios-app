# AUDIT-ROUND-131 · 第一百三十一轮：命中区只有 32pt，而闸门说「无 <44pt 可点区」

> CI：`8cac90d` build + golden 全绿；`49db24a` / `cab0218` 待回执。本轮本地提交。

## 1. 缺陷：`KeysChips` 的胶囊高 32pt

```swift
.padding(.horizontal, V.S.gapMS)
.frame(height: V.Hit.min - V.S.gapMS)      // 44 - 12 = 32
```

这是分段控件的胶囊（「全部 / 密码 / 指纹 / 临时码 / 手机钥匙」）。`frame(height:)` 是**固定高度**，
所以整个按钮的可点区就是 32pt —— 低于 HIG 要求的 44pt。

## 2. 更值得记的是：闸门为什么没抓到

`a11y` 闸门的判据是：

```js
const m = /\.frame\(\s*width:\s*([0-9]+)\s*,\s*height:\s*([0-9]+)\s*\)/.exec(line);
```

**它只匹配 `.frame(width: 数字, height: 数字)` 这一种写法。** 于是这两种都看不见：

| 写法 | 闸门看得到？ |
|---|---|
| `.frame(width: 40, height: 40)` | ✅ |
| **`.frame(height: 32)`**（只有 height） | ❌ |
| **`.frame(height: V.Hit.min - V.S.gapMS)`**（令牌表达式） | ❌ |

而本仓大量使用令牌，**恰恰是"令牌表达式"这种写法最常见**。

## 3. 扩判据（三条分支）

```js
const mPair  = /\.frame\(\s*width:\s*([0-9]+)\s*,\s*height:\s*([0-9]+)\s*\)/;   // 两个数字
const mH     = /\.frame\(\s*height:\s*([0-9]+)\s*\)/;                          // 只有 height
const mMinus = /\.frame\(\s*height:\s*V\.Hit\.min\s*-\s*(V\.S\.\w+)\s*\)/;   // Hit.min 减间距
```

第三条的判定：**`V.Hit.min - V.S.gapX` 永远小于 44**（减数恒正），
除非同一行还有 `minHeight` 兜底（那种写法会让实际高度取两者较大值）。

扩完立刻抓到本轮这一处（`KeysBits:63`）。

## 4. 修法

```swift
.frame(minHeight: V.Hit.min)
```

`minHeight` 是**下限**：胶囊视觉仍是紧凑的，但可点区回到 44pt。
（这与 ROUND-88 修的 `V.H.min`/`V.H.action` 被当固定尺寸用是同一类问题 —— 令牌名里的 `min`/`action` 说的是"至少这么高"。）

## 5. 方法论

**闸门的"看不见"往往不是漏了某个文件，而是漏了某种写法。**

| 闸门类型 | 常见盲区 |
|---|---|
| 按行正则扫 | **同一语义的多种写法**（本轮的三种 `frame`） |
| 按文件扫 | 跨文件的关系 |
| 按符号扫 | 动态构造的名字 |

本段已用"扩到所有写法"这条抓到过：`transition`/`contentTransition`（ROUND-118）、
`DateFormatter` 的 4 个创建点（ROUND-126），以及本轮的 `frame` 三种写法。

判据：**扩判据前，先问"这件事在这门语言里有几种写法"**，再逐个纳入 ——
而不是只加一个"我这次遇到的写法"。
