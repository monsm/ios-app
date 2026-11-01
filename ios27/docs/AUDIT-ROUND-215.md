# AUDIT-ROUND-215 · 第 215 轮：自动校时「失败了也写成功」—— 审计线索被自己毁掉

> CI：`02457cb` 已验证绿；`e834943` / `edbd3b0` 排队中。

## 1. 缺陷

```swift
if AutoOpenKit.dualTimeSync(...) {
    _ = try? await LockService.shared.syncTime()     // ← 结果被丢掉
    if let st = try? await LockService.shared.getStatus(mac: mac) { DB.writeStatus(mac, st) }
    AutoOpen.audit(mac, "rc=3 → 已自动校时（0E 双确认）")   // ← 无条件写成功
}
```

校时失败（BLE 断链 / rc≠0 / 超时）时，**审计里照样写「已自动校时」**。

而这条审计是排查「自动开锁为什么时好时坏」的**唯一依据** —— 写错等于把线索毁掉。

## 2. 修法

```swift
var syncError: String?
do { _ = try await LockService.shared.syncTime() } catch { syncError = error.localizedDescription }
…
if let syncError { AutoOpen.audit(mac, "rc=3 → 自动校时失败：" + syncError) }
else            { AutoOpen.audit(mac, "rc=3 → 已自动校时（0E 双确认）") }
```

## 3. 同族扫描

| 模式 | 处数 | 判定 |
|---|---|---|
| `_ = try?`（**吞错误**） | **1**（本轮修） | ✅ 全仓已无 |
| `_ = try await execOk(...)` | 15 | ✅ **不是同类** —— `execOk` 对非 rc=0 会抛错，`_ =` 只是不要解析结果，错误照样传播 |

这条区分很重要：`_ = try await f()` 与 `_ = try? await f()` 完全不同 ——
前者是「我不需要返回值」，后者是「我不关心失败」。

## 4. 方法论

**审计日志的"成功"字样，必须来自一次被检查过的成功。**

| 写法 | 审计可信度 |
|---|---|
| `try? f()` 然后写「已…」 | ❌ 失败也写成功 |
| `do { try f(); 写成功 } catch { 写失败 }` | ✅ |

判据：**每一行「已…」审计/用户提示，都要能指出它由哪一次 `try` 的成功分支支配。**
找不到那个分支，就是在写不设防的断言。
