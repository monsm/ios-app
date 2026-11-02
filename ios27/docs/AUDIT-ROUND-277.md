# AUDIT-ROUND-277 · 第 277 轮：`SettingsStore` 30 个自定义 get/set 全量核对 —— 无缺陷

> CI：`d287a34` build ✅（`build_ok=1` / `errors=0`）；golden 仍停在 `1f84bca`（82 用例），`d287a34` 的金标还没跑完。

## 1. 为什么要扫这一族

「开关改了、重启又回默认」是本仓出现过的问题形态。
根因通常是：`get` 读存储、`set` 只改了一个本地变量（或反过来）。

## 2. 扫描方法

解析 `SettingsModel.swift` 里所有 `var x: T { get { … } set { … } }` 形态的属性，逐项检查：

| 检查 | 结果 |
|---|---|
| 共多少个自定义 get/set | **30** |
| setter 不写存储的 | 1 个 —— `recordPolicy` 委托 `QueryFilters.setPolicy`（内部有白名单 + `DB.store.set` ✅） |
| getter 不读存储的 | 3 个 —— `density` / `recordPolicy` / `quietNight`，全部**委托**给读存储的静态属性 ✅ |

**结论：30 个全部正确 —— 该读的读、该写的写。**

## 3. 顺带看到一个好设计

`densityFromStore` 是 **nonisolated** 版本，注释写清了原因：

> `V.S.gapM` 在 `body`、`init`、非隔离 `static let` 里都会被求值，而那些位置拿不到 MainActor。

即「布局令牌要能同步读偏好」这条需求，被显式地做成了一个非隔离入口，而不是到处 `MainActor.assumeIsolated`。
这与 Round 255 那个 `Task { @MainActor in … }` 是同一类处置：**隔离边界要显式处理，不要绕过**。

## 4. 方法论

**「偏好项」的正确性可以纯机械验证：get 必须读存储、set 必须写存储 —— 30 个属性 5 分钟扫完。**

| 形态 | 症状 |
|---|---|
| get 读存储 / set 只改内存 | 重启回默认 |
| get 只读内存 / set 写存储 | 别处改了本页不更新 |
| **两者都委托给同一个读存储的静态属性** | ✅ 正确（本轮的 4 个特例都是这种） |

判据：**扫描器只看「有没有出现存储调用」，出现委托就人工跟一层 —— 委托是正确写法，不是漏写。**
