# AUDIT-ROUND-118 · 第一百一十八轮：提示条的滑入没有减弱动态守卫（扩判据后抓到 3 处）

> CI：`0bd09d4` 全绿；`f563712`（跨年修复）待回执。本轮本地提交。

## 1. 缺陷：`ToastHost` 的 `transition(.move)` 无守卫

```swift
.transition(.move(edge: .top).combined(with: .opacity))
```

用户开了「减弱动态效果」后，提示条仍然从顶部滑入。

**为什么 `reducedmotion` 闸门没抓到**：它的判据是 `.animation(` 与 `withAnimation(` ——
`transition(` 是**同一类的第三种写法**，不在覆盖内。

## 2. 扩判据，立刻抓到另外 3 处

```js
const isMotion = /\.animation\(/.test(line) || /withAnimation\(/.test(line)
  || /\.transition\(/.test(line) || /\.contentTransition\(/.test(line);
```

跑出来 3 处新遗漏：

| 位置 | 内容 | 判定 |
|---|---|---|
| `ZotpScreen:99` | `.contentTransition(.numericText())` | **真遗漏** → 修 |
| `AboutScreen:120` | `.transition(.opacity)` | **豁免**（纯透明度无位移） |
| `AppearanceScreen:473` | `.contentTransition(.numericText())` | **真遗漏** → 修 |

`AppearanceScreen` 那处尤其典型：它**下一行**已经有
`.animation(systemReduceMotion ? nil : V.M.snap, value:)` —— 作者想到了动画，
但 `contentTransition` 是另一条路径，漏了。

## 3. 修法

| 文件 | 修 |
|---|---|
| `ToastCenter` | 加 `@Environment(\.accessibilityReduceMotion)`；`reduceMotion ? .opacity : .move(...)` |
| `ZotpScreen` | 同上环境值；`.contentTransition(reduceMotion ? .identity : .numericText())` |
| `AppearanceScreen` | `.contentTransition(systemReduceMotion ? .identity : .numericText())` |
| `reducedmotion.js` | 判据扩到 `.transition(` / `.contentTransition(`；`.transition(.opacity)` 豁免 |

## 4. 我自己又踩了一次：用了未声明的标识符

给 `ZotpScreen` 加 `reduceMotion ? ...` 之后，闸门**通过了** —— 因为这个文件里根本没有
`reduceMotion` 这个环境值。我是先写用法、后想声明。

已补 `@Environment(\.accessibilityReduceMotion) private var reduceMotion`。

**`reducedmotion` 闸门抓不到这个**：它判的是"这一行里有没有含 `ReduceMotion` 的标识符"，
有就放过 —— 它不检查那个标识符是否真的存在。

而 `callsig2` 也抓不到：它只查 `X.y` 形式的成员存在性，**裸标识符不在覆盖范围**。

要补这个判据需要符号表（跨文件解析），成本高、误报风险大 ——
按本段原则（**假红多的闸门不做**）**不加**。

## 5. 方法论

**"同一语义的多种写法"是闸门最常见的漏网形态。**

| 语义 | 写法 |
|---|---|
| 动效 | `.animation(` / `withAnimation(` / **`.transition(`** / **`.contentTransition(`** |

扩判据的正确做法：**先问"这件事在 SwiftUI 里有几种写法"**，再逐个纳入。
本轮就是这样从 1 种扩到 4 种，并立刻抓到 3 处。

## 6. 顺带

`ToastCenter` 审完：`hideTask` 无 `deinit` 取消，但 `AppToast.shared` 是单例、永不释放，
所以无害（且 `show` 里每次 `cancel` 旧的）。

差集从 21 缩到 20。
