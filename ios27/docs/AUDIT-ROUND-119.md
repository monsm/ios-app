# AUDIT-ROUND-119 · 第一百一十九轮：模块排序表拖完又跳回去

> CI：`6934e3e` 全绿（`errors=0`、`warnings=0`）；`f563712` / `ca5b563` 待回执。本轮本地提交。

## 1. 缺陷：`setOrder` 把用户排序整个丢掉

```swift
static func setOrder(_ slots: [DevSlot]) {
    let clean = DevSlot.allCases.filter { slots.contains($0) }   // ← 按枚举声明顺序输出
    ...
}
```

`filter` 遍历的是 `DevSlot.allCases`（声明顺序：`status, quick, recent`），
**不是传入的 `slots`**。于是：

| 用户拖出来的顺序 | 实际写盘 |
|---|---|
| `[quick, status, recent]` | **`[status, quick, recent]`** |
| `[recent, status, quick]` | **`[status, quick, recent]`** |

**无论怎么拖，顺序都会回到枚举声明顺序。** 也就是说"模块排序"这个功能实际无效 ——
用户拖到第一位、松手、它跳回去。

## 2. 为什么 getter 掩盖了它

`order` 的 getter 会"白名单过滤 + 缺的补末尾"，看起来永远返回一个合法列表。
所以读侧一切正常，**只有写侧把顺序丢了** —— 而读侧读到的是丢过顺序的结果。

这类缺陷特别难发现：**读和写各自看都合理，只有"写进去再读出来"才暴露。**

## 3. 修法：保序去重

```swift
var seen = Set<DevSlot>()
let clean = slots.filter { seen.insert($0).inserted }
```

遍历传入顺序，只做去重（保留首次出现），不再按 `allCases` 重排。

`if clean == DevSlot.allCases { remove(orderKey) }` 这个"改回默认就删键"的优化仍然成立 ——
因为此时 `clean` 恰好等于 `allCases`。

## 4. 回归测试（含反向对照）

```swift
let given: [DevSlot] = [.quick, .recent, .status]
var seen = Set<DevSlot>()
let kept = given.filter { seen.insert($0).inserted }
XCTAssertEqual(kept, given, "保序去重不能改变顺序")

// 反向对照：旧写法确实会重排（记录"为什么改"）
let old = DevSlot.allCases.filter { given.contains($0) }
XCTAssertNotEqual(old, given, "旧实现必然丢掉用户顺序 —— 这就是被修的缺陷")
```

第二条断言比第一条更有价值：**它把"被修的缺陷"本身钉成了测试**，
以后谁改回旧写法，这条会红。

## 5. 方法论

**"读侧合理 + 写侧合理 ≠ 往返正确"。**

判据：**凡是有 get/set 一对的地方，写一个"set 进去再 get 出来"的测试** ——
本段已经用这条抓到过：

| 轮次 | 缺陷 |
|---|---|
| 52 | 字段加了但 `BackupCanonical` 不 emit（导出后读不回来） |
| **119** | **`setOrder` 丢顺序（存进去再读出来不是同一个）** |

两次都是"单看某一侧没问题"。
