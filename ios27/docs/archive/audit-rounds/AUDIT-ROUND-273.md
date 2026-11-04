# AUDIT-ROUND-273 · 第 273 轮：切锁后，A 锁的筛选条件套到了 B 锁上（还会被存进 B 的键）

> CI：build `fb152c1` ✅ / golden `6c20d1c` ✅（82 用例）；`77b60ca`（签名改动）/ `d287a34` 排队中。

## 1. 缺陷

`RecordsScreen.hydrateFilters()` 的第一行是 `guard !hydrated else { return }` + `hydrated = true`。

而 TabView **会保活**这个视图（切到别的 tab 再回来，实例不重建）。于是：

| 步骤 | 状态 |
|---|---|
| 在 A 锁下进记录页 | 从 `kf_rflt_<A>` 水合筛选，`hydrated = true` |
| 去门页切到 B 锁 | 视图仍在，`hydrated` 仍为 true |
| 回到记录页 | `onAppear → consume() → hydrateFilters()` **直接 return** ⇒ **A 的筛选原样套在 B 上** |

更糟的是第二层：`saveFilters()` 用的是**当前** mac —— 用户在 B 锁下随手改一下筛选，
就会把这份「继承来的 A 锁状态」写进 **`kf_rflt_<B>`**，把 B 锁自己记住的那份覆盖掉。

## 2. 修法

监听 `app.currentMac`，切锁即重置 `hydrated` 并 `consume()`（后者本来就依次做 `hydrateFilters()` 与 `reload()`）。

## 3. 为什么 `onChange(of: app.currentMac)` 能工作

`app` 是 `@Environment(AppModel.self)`（`@Observable`），而 `currentMac` 依赖 `overrideMac` / `lock` ——
这两个都是被观察的存储属性，切锁会改它们 ⇒ 视图重算 ⇒ `onChange` 比较到变化 ✅。

## 4. 方法论

**「只初始化一次」的 `@State` + TabView 保活 = 跨实体串状态的经典组合。**

| 形态 | 风险 |
|---|---|
| `@State private var didInit = false` | 实体切换后不再初始化 |
| **`hydrated` / `loaded` / `didLoad` 这类布尔** | **同上，且很隐蔽（数据看起来是对的，只是属于上一把锁）** |

判据：**凡是「按实体加载」的一次性标志，都必须监听实体标识变化并复位。**
查法：grep `guard !` 与 `= true` 同时出现的 `@State`，逐个问「这个视图会跨实体复用吗」。
