# AUDIT-ROUND-126 · 第一百二十六轮：又找到 3 处没钉公历的 `DateFormatter`

> CI：`0fd7c63` 已验证绿（`errors=0`、`warnings=0`）；`8368291` / `24a9551` 待回执。本轮本地提交。

## 1. 上轮只修了 1 处，其实有 4 处

上轮修了 `DF.cached`。这轮把**所有 `DateFormatter()` 创建点**列出来：

| 位置 | 用途 | 钉公历？ |
|---|---|---|
| `DateFormats:29` `cached` | 通用工厂 | 上轮已修 ✅ |
| **`DateFormats:62` `localTime`** | `dateStyle`/`timeStyle` 版 | **缺** → 本轮修 |
| **`DateFormats:82` `localCached`** | 通用 `dateStyle` 工厂 | **缺** → 本轮修 |
| `TimeFormat:31` `machine` | 时间口径出口 | 已有（`f.calendar = calendar`）✅ |
| **`BackupStudioScreen:375` `stamp()`** | **备份文件名时间戳** | **缺** → 本轮修 |

## 2. 备份文件名那处最直观

```swift
f.dateFormat = "yyyyMMdd-HHmmss"
```

佛历下会生成 `25691101-153000.json` 这样的文件名 —— 用户看到 2569 年会以为是什么错误，
而备份列表**按文件名排序**（`sorted { $0.date > $1.date }` 用的是属性，但人工识别靠名字）。

`localTime` 那处虽用 `dateStyle` 而不是 `dateFormat`，**同样受历法影响** ——
`dateStyle` 只是"系统推荐的格式"，历法仍是 `Calendar.current` 的。

## 3. 加闸门（`swiftcheck.js`）

```js
const dfCount = (code.match(/\bDateFormatter\(\)/g) || []).length;
const calCount = (code.match(/\.calendar = /g) || []).length;
if (dfCount > 0 && calCount < dfCount) { … bad++ }
```

判据细节（都踩过）：

| 细节 | 为什么 |
|---|---|
| 只看**代码行**（跳过 `//`） | 头注里就写着 `DateFormatter()` 这个词，会被数进去 |
| `\bDateFormatter`（词边界） | `ISO8601DateFormatter()` 也含这个子串，但它固定格式、不受历法影响 |
| 接受任何 `.calendar = ` | `TimeFormat` 写的是 `f.calendar = calendar`（变量名不同但正确） |

双向验证：把 `BackupStudioScreen` 那行删掉 →

```
App/Features/Settings/BackupStudioScreen.swift  有 1 处 DateFormatter() 但只有 0 处设置 calendar
swiftcheck: FAIL — 1 处不平衡
```

恢复 → 21/21 全绿。

## 4. 方法论

**修一个实例后，立刻列出「所有同类创建点」—— 这是本段反复验证的做法。**

上轮我只修了 `DF.cached`（因为那是"两个工厂"里我注意到的那一个）。
这轮列全后发现**还有 3 处**，其中 1 处（备份文件名）比原缺陷更直观。

判据：**修完一处，用 grep 列出"这个 API 的所有创建点"，逐个看要不要同样处置** ——
本段用这条已抓到：`purgeSecretsForDevice` 的四族、`keepingAwake` 的三处、
`timestampIsPlausible` 的两个调用点、`transition` 的四类写法，以及本轮的 4 处 formatter。
