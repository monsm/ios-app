# AUDIT-ROUND-195 · 第 195 轮：给开锁补「凭证来源」日志 —— 让下一次流水一眼可判

> CI：`d5f0913` 已验证绿；`6b46374` / `940f4fa` 待回执。

## 1. 还差最后一步信息

用户的 `rc=2`（无效的PIN码）有两条可能：

| 可能 | 症状 |
|---|---|
| A. **配网时存的那枚 `kc.ekey` 已失效**（换 PIN / 换管理员 / 锁被重刷） | 每帧都是同一枚 ekey |
| B. 本机 PIN 池整体与锁端不一致 | 现签任何一枚都是 rc=2 |

上一轮的多枚 PIN 重试能区分它们 —— 但日志里看不出"刚才那帧到底用的是哪一枚"。

## 2. 本轮补的日志

```swift
var credSource = "无"
if !chosen.isEmpty { cred = signed(chosen);        credSource = "用户选定的 PIN 现签" }
else if !kc.ekey.isEmpty { cred = kc.ekey;         credSource = "配网时存的 ekey" }
else if let first = kc.pins.first(where: {…}) { cred = signed(first); credSource = "PIN 池第 1 枚现签" }
log("info", "开锁凭证来源 = \(credSource)（本机 PIN 池 \(kc.pins.count) 枚）")
```

## 3. 下一次流水的判读表

| 看到 | 结论 | 下一步 |
|---|---|---|
| `凭证来源 = 配网时存的 ekey` + `rc=2` + 随后 `PIN #2 rc=0` | **A 成立**：存的 ekey 失效，现签能开 | 把 `kc.ekey` 在开锁时降级为**备用**（优先现签） |
| `凭证来源 = 配网时存的 ekey` + 后面每枚 PIN 都 `rc=2` | **B 成立**：PIN 池与锁端不一致 | 需要重同步 PIN（cmd08）或重新配对 |
| `凭证来源 = 用户选定的 PIN 现签` + `rc=0` | 用户自己选对了 | — |
| `本机 PIN 池 0 枚` | 钥匙串里没有 PIN | 重新配对 |

## 4. 顺带核对：配网写 PIN 的那条链是可靠的

`finishPairing` 对**每一批** `cmd08` 都检查 `rb.rc != 0` 并抛错：

```swift
if rb.rc != 0 {
    log("error", "PIN 批次 \(n) 被锁拒收： rc=\(rb.rc) …")
    throw BLEErrorX.msg(Self.pairWarning(resumable, "PIN 批次 \(n) 失败 …"))
}
```

所以「配网写 PIN 静默失败」这个可能可以排除 —— 要么写进去了，要么配网当时就报错。

## 5. 方法论

**"能区分两种可能"比"再多试一次"更有价值。**

上一轮我加了"逐枚 PIN 试"，那是**动作**；本轮加的是**证据**（这一帧用的是哪枚）。

| 只有动作 | 动作 + 证据 |
|---|---|
| 试了 3 枚，都失败 → 不知道是 A 还是 B | 日志写着"用的是配网 ekey"，试到第 2 枚成功 → **A 确认** |

判据：**加自愈逻辑的同时，把"它选择了哪条路"也打出来** —— 否则自愈本身会变成一个黑盒。
