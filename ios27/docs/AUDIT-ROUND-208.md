# AUDIT-ROUND-208 · 第 208 轮：vendor 控制流逐段核对（cmd0A / cmd08 / cmd21 / cmd16 / bkey）

> CI：`ce73de4` 已验证绿；`36ba138` / `a5450a7` 排队中。

## 1. 逐段核对结果

| 环节 | vendor 写法 | 本仓 | 判定 |
|---|---|---|---|
| `cmd0A` 新增密码 | `new Li(0, pwd, …)` ⇒ delAlias = **0** | `delAlias` 默认 **0** | ✅ |
| `cmd0A` 清空全部 | `new Li(65535, "", …)` | `0xFFFF = 清空` | ✅ |
| `cmd0A` 改 / 删 | `new Li(alias, …)` / `new Li(alias, null, …)` | 同 | ✅ |
| `cmd08` 首批哨兵 | `0 == e && (u = [4294967295])` | `delPinSentinel = "ffffffff"` | ✅ |
| `cmd08` 终止 | `e >= 64` | `while i < pins.count`（=64） | ✅ |
| `cmd21` 时机 | **`syncPins` 全部批完成后**才 `setBeacomKey` | `finishPairing` 同序 | ✅ |
| `bkey` 生成 | 相邻字节 |Δ|≤2 ⇒ +6，>255 ⇒ 6 | `genBkey` 逐字同 | ✅ |
| `cmd16` 页大小 | 5 | 5 | ✅ |
| `cmd16` 方向 | `0xFFFFFFFF` 起、`idx−1` 递减 | **本轮已修**（第 207 轮） | ✅ |
| 日志条解析 | `[type][len][idx 4B LE][lockTime 4B LE]` | `dropFirst(4)/12` 同偏移 | ✅ |

**没有发现新的控制流缺陷。** 第 207 轮那个翻页方向是这条线上唯一的真问题。

## 2. 本轮追加的防御

翻页取「页内**最小** idx」而不是「最后一条」：

```swift
guard let low = page.logs.map(\.idxRaw).min(), low > 0 else { break }
startIdx = low - 1
```

vendor 写「最后一条」隐含假设固件按降序返回。用 `min()` 在降序下**完全等价**，
但若某固件页内升序，`last` 是最大 idx ⇒ 下一页原地打转；`min()` 不会。

**等价但更鲁棒**是这类改动的正确判据：不改变已有正确行为，只堵住未验证的假设。

## 3. 方法论

**对抗式对比要分三层做，漏一层就会得出"没问题"的错误结论。**

| 层 | 本轮覆盖 | 产出 |
|---|---|---|
| 字节层（编码/加密/成帧） | 第 203 轮 | 无差异 |
| **语义层（参数含义）** | 本轮（delAlias / 哨兵 / bkey） | 无差异 |
| **控制流层（顺序/方向/终止）** | 本轮 + 第 207 轮 | **1 个真 bug（翻页方向）** |

只在字节层比完就说"三方一致"，会漏掉翻页方向这种**完全不含字节差异**的逻辑错误。
