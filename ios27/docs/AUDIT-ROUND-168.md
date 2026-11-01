# AUDIT-ROUND-168 · 第 168 轮：补上「增强对比度」的玻璃退化；产出带引用的设计符合性报告

> CI：`ad34f48` 已验证绿；`6743235` / `b5bf30b` / `8144102` 待回执（CI 落后三笔）。
> 本轮加载了 `apple-design` skill，用到它的 `code-audit.md` 与 `hig/liquid-glass.md`。

## 1. 缺陷：`VGlassSurface` 只处理了「减少透明度」，漏了「增强对比度」

`hig/liquid-glass.md › Review checklist` 第 5 条：

> **Reduce Transparency** gets an opaque fallback, **Increase Contrast gets stronger fills and borders**,
> **Reduce Motion** drops morphing and refraction animation.

我们只判了第一个：

```swift
// 旧
var solid: Bool = false      // 只有调用方传的「减少透明度」
```

后果：开了「增强对比度」的用户看到**仍是半透明玻璃** —— 而系统在这一档期望的是更实的填充与更明显的描边。
玻璃的半透明在这档就是可读性负担。

```swift
@Environment(\.colorSchemeContrast) private var contrast
private var opaque: Bool { solid || contrast == .increased }
// 描边：contrast == .increased 时 lineWidth × 2
```

Reduce Motion 那一条无需处理：我们的玻璃没有形变/折射动画（`Reduce Transparency` 分支是赋值不是动画）。

## 2. 产出：`docs/DESIGN-CONFORMANCE.md`

这是一份**带引用**的符合性报告 —— 每条规则都标了出处文件与条目，而不是"我觉得符合"。

| 章节 | 内容 |
|---|---|
| 1 原生控件 | 9 条规则核对 + 本轮完成的 5 项替换（覆盖 66 个调用点）+ 4 个保留自定义件的理由 |
| 2 液态玻璃 | `hig/liquid-glass.md` 七条清单**逐条**核对 + 6 条误用形态逐条排除 |
| 3 文字占用 | 9 处「文字被挤/被裁」修复清单 + 2 条已固化的闸门 |
| 4 布局 | 6 条规则 + `confirmationDialog` 挂载点处置 |
| 5 已知偏差 | **4 条**，含每条为什么不改 |

## 3. 报告里最重要的一条：手写 Tab 栏是 **High** 级偏差

`apple-design` 的 `code-audit.md` 原文：

> **A hand-built tab bar or toolbar** (an `HStack` pinned to the bottom, a custom `UIView` bar)
> where `TabView`, `UITabBarController`, `.toolbar`, or `UIToolbar` would do
> → **Misses the system material, its adaptations, and the iPhone Duo side placement below**

`VFloatingTabBar` 正是"an `HStack` pinned to the bottom"。

**本轮仍然不改**，但理由写清楚了：

| 理由 |
|---|
| 它是本 App 的骨架（268pt 居中胶囊 + Router），换 `TabView` 等于重做导航层 |
| 没有 iOS 27 真机可验证观感（`TabView` 的栏是**全宽**的，与居中胶囊是两种设计） |

**记录为已知偏差 + 给出严重度 + 引用**，比"悄悄不改"或"硬改"都诚实。

## 4. 顺带核对（全部通过，都写进报告了）

| 检查 | 结果 |
|---|---|
| `UIDesignRequiresCompatibility`（会让 App 跑旧设计兼容模式） | **不存在** ✅ |
| `UIScreen.main`（iOS 26 起废弃；iPhone Duo 两块屏） | 真实使用 **0** ✅ |
| `userInterfaceIdiom` / `UIDevice.current` 选布局 | **0** ✅ |
| `TextEditor`（应优先 `TextField(axis:)`） | **0** ✅ |
| `.clear` 玻璃压文字 | **0** ✅ |
| 工具栏/标签栏下铺实色底 | **0** ✅ |
| 玻璃嵌玻璃 | 无（两块一上一下，**不相邻**；参考原文限定 "nearby"） |

## 5. 方法论

**"符合性"要有可核对的出处，否则只是意见。**

这份报告的每一条都写成「规则 → 出处（skill 文件 + 条目）→ 本仓状态 → 证据」。
好处是**下一个人可以逐条复核**，而不是只能选择相信或不相信。

同时它把「不改」也写成了结论：

| 类型 | 措辞 |
|---|---|
| 已修 | 列出旧值与后果 |
| 保留自定义件 | 写清"它不是重造系统控件"的判据 |
| **不修** | **写清严重度、引用、以及为什么不修** |

第三种最容易变成沉默。沉默会被误读成"没发现"。
