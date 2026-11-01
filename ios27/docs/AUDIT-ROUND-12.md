# AUDIT-ROUND-12 · 第十二轮：一个死开关 + 第 20 道闸门（以及我把它做错两次）

> 执行日期：2026-11-01 07:40 → 08:20（+08:00）
> 起点 `464d23f` → 终点 `98f752f`
> CI：build `errors=0`；golden **50 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **1 个真缺陷**（`density` 是死开关）+ **1 个并发错误**（CI 抓到） |
| 新闸门 | **第 20 道** `settings.js`（**warn-only**，见 §3） |
| 闸门 | 19 → **20** |
| 测试 | 50 条 / 6 文件 |
| 静态扫描 | P0 0 · P1 0 · P2 21 · P3 9 |

---

## 1. 真缺陷：`LayoutDensity` 是**死开关**

`外观 → 节奏 → 布局密度`（紧凑 / 标准 / 宽松）三档：

- 存进 `kf_density` ✅
- 进备份、能恢复 ✅
- 界面上给三个 chip、点了高亮 ✅
- **全仓没有任何地方读它** ❌

也就是说：用户改档位，**界面一点变化都没有**。这比不给这个开关更糟 ——
用户会以为 App 坏了，或者以为自己没点中。HIG `settings`：
"Minimize the number of settings you offer."（连给了都不生效的，更该删或修）。

### 修法

接到 `V.S` 的间距令牌上（**只缩放间距节奏**，与枚举注释的口径一致：

> "只缩放间距节奏，字号与 44pt 触达不动"

```swift
static var densityScale: CGFloat {
    switch SettingsStore.densityFromStore {
    case .compact: return 0.88
    case .relaxed: return 1.12
    case .standard: return 1.0
    }
}
private static func d(_ base: CGFloat) -> CGFloat { (base * densityScale).rounded() }
static var gapM: CGFloat { d(14.3) }   // gapXXS…gapXXL 全部过 d()
```

**命中区（`V.Hit.min` = 44pt）与字号绝不经过这里** —— 压小按钮不是"紧凑"，是点不准。

---

## 2. CI 抓到的并发错误（我引入的）

`SettingsStore` 是 `@MainActor`，而 `V.S` 的间距令牌在 `body` / `init` / 非隔离
`static let` 里都会被求值 —— 那些位置拿不到 MainActor：

```
App/Design/V7/V7Tokens.swift:333: error: main actor-isolated property 'density' can not be referenced from a nonisolated context
```

修法：加一个 **nonisolated** 直读访问器（只读 UserDefaults，不碰 `revision`）：

```swift
nonisolated static var densityFromStore: LayoutDensity {
    LayoutDensity(rawValue: DB.store.getString("kf_density")) ?? .standard
}
```

重绘仍由设置页自身的 binding 驱动（它读 `store.density`，是 @Observable 依赖）。
**注意**：这条我在本地 20 道闸门全绿时是发现不了的 —— 只有真编译器能抓到。
这正是"CI 必须真编译"的价值。

---

## 3. 第 20 道闸门：`settings.js`（**warn-only**，以及我把它做错两次）

判据：`SettingsModel` 里每个**带 setter** 的属性，必须有真实消费点
（读原始存储键 / 读该属性 / 或有一层派生）。

### 我把它做错两次，都记下来

| 版本 | 错在哪 | 后果 |
|---|---|---|
| v1 按**属性名**判 | 消费点常直接读 UserDefaults（`DB.store.getString("kf_tl_gap")`），不经过属性 | 误报 `timelineGap`/`recordPolicy`/`highContrast` 等 6 项 |
| v2 按**存储键**判 | 有些设置只被 `SettingsStore` 自己读（如 `kf_theme`），消费方读的是 `store.theme` | 误报 20 项 |

v3 同时接受「键 / 属性 / 一层派生」，并把排除名单收窄到**真正的编辑器**文件
（`AppearanceScreen` / `AccessibilityScreen` / 备份三件套 / `SettingsScreen` / `SettingsParts`），
结果：**30 个设置全部有直接消费点**。

### 为什么它是 **warn-only** 而不是判红

它只追**一层**直接消费。经 helper 的间接消费追不到 ——
例如 `recordPolicy` → `QueryFilters.policy` → `QueryFilters.load` → `RecordsScreen`。
若判红，这类正常代码会被误判。所以它输出"请人工确认"，**不判红**：
宁可不判红，也不产生假红（假红会训练人忽略闸门）。

> 这一条是刻意的设计取舍，写在闸门文件头与输出里，不是遗漏。

---

## 4. 逐个核对结果（30 项全部确认有消费）

本轮逐个验证过的几个容易误判的：

| 设置 | 真实消费点 |
|---|---|
| `recordPolicy` | `QueryFilters.load(mac:)` ← `RecordsScreen:765` |
| `timelineGap` | `RecordsScreen.timelineSpacing` 直读 `kf_tl_gap` |
| `autoRetry` | `AppModel:229`（重试次数 3 vs 1） |
| `customAccent` | `SettingsModel.accentColor` → `LockKeeperApp` `.tint()` |
| `highContrast` | `V7Tokens.highContrastOn` 驱动 hairline 描边强度 |
| `quietNight` | `BatteryCare:199` |
| `holdDuration` | `DoorScreen` 长按阈值 |
| **`density`** | **无（本轮修复后才有）** |

---

## 5. 验证链

```
$ node Gates/allgates.js
… 20 道闸门全部通过
settings: OK - 30 settings all have a direct consumer

$ git show origin/ci-log:meta.txt
commit=98f752f… errors=0  build_ok=1  archive_ok=1

$ git show origin/ci-test:meta.txt
commit=98f752f… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=50
```

---

## 6. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
SEC-01 残余（Swift `String` 无法清零）· SEC-18 残余（需真机）·
SEC-22（固件 AES-ECB 限制）· SEC-26（出口合规需法律复核）·
SEC-01 单测（未签名宿主无钥匙串权限 ⇒ CI skipped）· D-12（竖屏产品决定）。

### P3
D-11 已确认误报。D-14（DesignLab `<img>` 缺 alt）、`ForEach` 下标身份若干处、
`.toolbar(.hidden, for:)` 软废弃、VoiceOver 转子（可选优化）。

### 工具
`hig-doctor` MCP 仍不可用（第六轮）；HIG 依据 `apple-design` skill 的 123 页本地副本。

### 需要真机/人工的
SwiftUI 真实渲染与浅色主题观感、手势、触觉、BLE 回执、指纹录入、
DFU 真实续传、WebDAV 真实链路。**`density` 改完之后正好需要人眼确认三档观感差异是否恰当。**
