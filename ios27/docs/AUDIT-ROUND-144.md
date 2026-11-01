# AUDIT-ROUND-144 · 第一百四十四轮：用「100 × 365 天」算 100 年

> CI：`fdaa7f7` build + golden 全绿；`3fa85c1` / `6c9d78f` 待回执。本轮本地提交。

## 1. 缺陷：`addingTimeInterval(100 * 365 * 86400)`

```swift
let to = df.string(from: Date().addingTimeInterval(100 * 365 * 86400))
```

给指纹录入选「100 年有效期」。问题：

| 量 | 值 |
|---|---|
| `100 × 365 × 86400` 秒 | 36500 天 |
| 真实的 100 年（含闰日） | **36524–36525 天** |
| 差 | **约 24–25 天** |

行为上无所谓（"近似永久"），但**写法是错的** —— 而本仓已经为这条纪律写过注释：

> `WeekCal.shifted`：`addingTimeInterval(±86_400)` 数的是 24 小时，
> 而有夏令时的地区里切换那一天是 23 或 25 小时 …… 真的在算"时长"的调用点**不该**改到这里来。

而"加 100 年"不是时长，是**日历运算**。

## 2. 修法

```swift
let to = df.string(from: TimeFormat.calendar.date(byAdding: .year, value: 100, to: Date()) ?? Date())
```

## 3. 加闸门判据

```js
if (/\b365\s*\*\s*86400|86400\s*\*\s*365/.test(code)) { … bad++ }
```

双向验证：往 `PidMap.modelName` 注入 `let _ = 365 * 86400` → 判红；删掉 → 全绿。

## 4. 顺带核对（无缺陷）

`Store` / `StoreLedger` 的两个写锁（`ledgerWriteLock` / `keychainWriteLock`）与 `ledgerLock`：

| 检查点 | 结论 |
|---|---|
| `saveLedger` 的锁范围 | ✅ 覆盖「corrupt 检查 → 读 → 写 → diff → 遥测」全程 |
| `keychainWriteLock` 是否真用 | ✅ `StoreKeychain:135` |
| `ledgerLock` 是否真用 | ✅ `markLedgerCorrupt` / `isLedgerCorrupt` / `clear*` 四处 |
| `cacheWritable` 的孤儿防护 | ✅ 注释写明真机事故（删锁后重写日志缓存会留下孤儿） |

## 5. 方法论

**"近似"在展示层可以接受，在数据层不行。**

| 场景 | 能否用近似 |
|---|---|
| 文案写「约 100 年」 | 可以 |
| **写进协议字段的有效期** | **不行**（那是锁端会照着执行的数） |

判据：**凡是"要交给别人执行的数"，都必须用精确算法**；
只有"只给自己看"的数才可以近似。

本段同类：ROUND-135 的「23–24 点」也是"显示侧算错边界"，但那条用户能看见；
这条用户看不见（差 25 天在 100 年里），**所以更依赖审计而不是依赖用户报障**。
