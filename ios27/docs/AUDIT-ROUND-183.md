# AUDIT-ROUND-183 · 第 183 轮：`surplus` 解析出来却没人用 —— 读不全也说自己读全了

> CI：**`41edf0c` 已验证绿**；`f802bac` 待回执。

## 1. 缺陷

协议 `cmd16` 的回包里有 `KLV#04 = surplus`，`getLogs` 老老实实解析了：

```swift
let surplus = r.klvs.first(where: { $0.key == 0x04 }).map { Int(StatusParser.leHexToU32($0.val)) }
return LogPage(surplus: surplus, logs: logs)
```

**但全仓没有任何消费者。** grep `surplus` 只有三处：结构体定义、解析、返回。

而 `readLogs()` 的循环是：

```swift
for _ in 0 ..< 20 {                       // 20 页封顶
    let page = try await getLogs(...)
    if page.logs.isEmpty { break }
    if page.logs.count < 5 { break }       // 只看"这一页不满"
    startIdx = last.idxRaw &+ 1
}
```

**完全没有用 `surplus` 判断"到底读完了没有"。**

### 症状

锁里若有 400 条日志：读 20 页（100 条）后循环结束，界面显示「已读取 100 条 · 19:55」，
**用户会以为这就是全部** —— 而锁里还有 300 条更早的记录，产品里没有任何地方会说这件事。

## 2. 修法

**（a）`readLogs()` 返回剩余条数**

```swift
@discardableResult
func readLogs() async -> Int? { ... return remaining }
```

**（b）只在"可能被截断"时报**

```swift
// 只在读满 20 页时才把 surplus 带出去
let remaining: Int? = pagesRead >= 20 ? lastSurplus : nil
```

为什么加这个门：不同固件对 `KLV#04` 的语义可能是"剩余"也可能是"总数"。
**若提前读完还报一个数字，宁可不说也不要误报。**

**（c）记录页如实说明**

```swift
let more = (remaining ?? 0) > 0
    ? "；锁端还有 \(remaining ?? 0) 条更早的记录未读（点「读取」可继续）" : ""
```

## 3. 本轮另外 4 项「审过、判定正确」

| 疑点 | 结论 |
|---|---|
| `BatteryCare.sample` 会不会记假 0% | ✅ `LockStatus.powerLevel` 默认 **-1**（不是 0），且 `sample` 有 `pct >= 0 && pct <= 100` 守卫 |
| `LockStats.isSleeping` 的 `t == 0` | ✅ 已有 `guard t > 0`（从未连接不算沉睡）＋ `timestampIsPlausible` 未来值保护 |
| `Array(quickIDs)` 的 Set→Array 乱序 | ✅ `QuickPool.setSelected` 用 `all.filter{...}` 决定顺序，不依赖传入数组 |
| `DB.writeLogs` 会不会覆盖丢旧日志 | ✅ **合并**语义：按 `idxRaw` 去重、倒序、上限 300 条 |

## 4. 方法论

**「解析了但没消费」是死代码里最隐蔽的一种 —— 因为它假装功能已经完整。**

| 形态 | 危害 |
|---|---|
| 没解析 | 一眼看得出缺功能 |
| **解析了、没人用** | **看起来"数据都在"，没人会去补那一步消费者** |

`surplus` 就是典型：字段在结构体里、协议注释里、解析代码里都齐了，
唯独**最后一步"用它判断读没读完"**没人写。这种缺口靠读类型定义是发现不了的，
只能靠 **grep 字段名 → 只有生产没有消费**。

判据：**凡是"从外部协议/接口解析出来的字段"，都要能回答"谁用它做了决定"。**
答不出来的，要么补消费者，要么删字段 —— 别让它一直躺在结构体里冒充已完成。
