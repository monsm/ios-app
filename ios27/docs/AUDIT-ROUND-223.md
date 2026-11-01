# AUDIT-ROUND-223 · 第 223 轮：把「`try?` + 已…」判据机制化

> CI：**`420beb5` build/archive 全绿（errors=0 / warnings=0）**；`62a0ae5` golden **82 用例全过**。
> Round 222 那个 `build_log=no` 确认是 runner 抽风，代码无恙。

## 1. 为什么值得做成闸门

这条形状已经抓到**两个真 bug**：

| 轮次 | 代码 | 后果 |
|---|---|---|
| 214 | `try? FileManager.removeItem(...)` → `outcome = "已删除 xxx"` | 删除失败也报成功，文件"删了又回来" |
| 215 | `_ = try? await syncTime()` → `audit("已自动校时")` | 校时失败也写成功，审计线索被毁 |

两处形状**完全相同**：语句式 `try?` 把结果丢掉，后面紧跟一句「已…」。

## 2. 规则

```
语句式 try?（含 `_ = try?`） + 之后 5 行内出现 "…已…" 字符串  ⇒  FAIL
```

**排除** `if let x = try? …` / `guard let x = try? …` —— 那种是有意使用返回值，不在此列。

双向验证：注入

```swift
_ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/tmp/x"))
outcome = "已删除探针"
```

⇒ `swiftcheck: FAIL — try? 丢弃结果后紧跟「已…」文案`；移除后 22/22 绿。

## 3. 本轮另外 2 项「审过、正确」

| 检查 | 结论 |
|---|---|
| 切锁后 `lastStatus` 会不会串锁 | ✅ `reload()` 按 mac 取 `kf_snap_<mac>`，mac 空/无钥匙串时显式置 nil |
| 删掉当前锁后 `preferredMac()` 会不会指空 | ✅ 先 `ks.contains(currentMac)` 校验，否则回落 `ks.first` |

## 4. 方法论

**判据写进文档只是"记住"，写成闸门才是"不会再犯"。**

| 形态 | 效果 |
|---|---|
| 文档里的判据 | 下次读文档的人知道 |
| **闸门** | **下次写代码的人会红** |

本仓 22 道闸门里已经有 4 道是这条思路的产物（承诺对账、扩展存储属性、快照字段、文案猜颜色 + 本轮）。
