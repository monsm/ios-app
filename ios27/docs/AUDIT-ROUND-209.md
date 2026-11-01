# AUDIT-ROUND-209 · 第 209 轮：pwdInfoMaxLen 解析了没人用 —— 密码长度上限写死成 8

> CI：`36ba138`（写放大）已验证绿；`a5450a7` / `5c5b184` 排队中。

## 1. 扫描：20 个状态字段的消费者

| 字段 | 外部消费 | 说明 |
|---|---|---|
| `firmware` / `pid` / `powerLevel` | 21 / 37 / 12 | ✅ 广泛使用 |
| `verifyMode` / `broadcastMode` / `zotpPeriod` | 4 / 6 / 3 | ✅ |
| `pinStock` / `pwdStock` / `fpStock` | 6 / 12 / 12 | ✅（`pinStock` 204/205 轮才接上） |
| `keyboardFreeze` / `keyboardErrCount` | 2 / 1 | ✅（204 轮接上） |
| **`pwdInfoMaxLen`** | **0** | ❌ **本轮修** |
| `pinInfoBinding` | 0 | 记录（语义未定，不动） |
| `fpInfoBatchNumber` | 0 | 记录（语义未定，不动） |

## 2. 缺陷

`ZKCmdBuilder.cmd0ASyncPwd` 里把上限写死：

```swift
guard addPwd.utf16.count <= 8 else { throw BLEErrorX.msg("密码最长 8 位") }   // 写死
```

而锁端在 cmd03 的 **KLV#26 `pwdInfoMaxLen`** 里明确上报自己的上限。

| 锁端上限 | 用户输 8 位 | 结果 |
|---|---|---|
| 8 | 8 位 | ✅ |
| **6** | 8 位 | 锁拒绝 → 报的是一句**与长度无关的 rc 文案**，用户不知道是「太长」 |

## 3. 修法

```swift
private func lockPwdMaxLen() async -> Int? {
    guard let v = (try? await getStatus())?.pwdInfoMaxLen, v > 0 else { return nil }   // 读不到就不拦
    return v
}
```

`pwdAdd` 与 `pwdModify` 在构建帧**之前**校验：

```swift
if let max = await lockPwdMaxLen(), pwd.utf16.count > max {
    throw BLEErrorX.msg("这把锁的密码最长 \(max) 位（锁端上报），当前 \(pwd.utf16.count) 位")
}
```

写死的 8 位 guard 保留（协议物理上限 + 没连上锁时的兜底）。

## 4. 方法论

**「锁端告诉你的限制」永远优于「代码里写死的限制」。**

| 来源 | 风险 |
|---|---|
| 写死 `8` | 换一款固件就错，且报错与原因无关 |
| **锁端上报 `pwdInfoMaxLen`** | 跟着锁走，永远对 |

判据：**凡是协议里有「能力/容量/上限」字段而我们又写了常量，就该问一句「这个常量是不是该来自那个字段」。**
本仓 `pinInfoCapacity` / `pwdInfoCapacity` 早已这么做（`capacityText`），只有「最大长度」被漏下。
