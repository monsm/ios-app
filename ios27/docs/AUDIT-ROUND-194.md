# AUDIT-ROUND-194 · 第 194 轮：`ensureConnected` 没有单飞 —— 预热与开锁互拆连接

> 来源：用户真机日志第 1–4 行。

## 1. 日志证据

```
21:06:35 [warn] 缓存 deviceId 直连失败 (连接已取消), 回退 MAC 扫描解析
21:06:35 [info] 扫描解析 MAC=fbb993c5cc95 (请靠近门锁)
21:06:35 [warn] 缓存 deviceId 直连失败 (连接已断开), 回退 MAC 扫描解析
21:06:35 [info] 扫描解析 MAC=fbb993c5cc95 (请靠近门锁)
21:06:36 [info] 扫描命中 …  （两条）
21:06:38 [info] 已连接 …      （比正常多花 3 秒）
```

**两组「直连失败」在同一秒内** —— 这不是"重试"，是**两条路径同时在建连接**，
而后进入 `ensureConnectedInner` 的那个会先执行 `if !connectedDeviceId.isEmpty { disconnect() }`，
把前一个正在建立的连接**拆掉**。两边都白跑，最后靠扫描解析重新连。

哪两条路径：`DoorScreen` 的 `.task { link.preheat() }`（预热）与用户点圆盘后的
`runUnlockChain` → `ensureConnected`（开锁）—— 进页面就预热、紧接着点开锁，必然撞上。

## 2. 修法：同 mac 的连接单飞

```swift
private var connecting: (mac: String, task: Task<Void, Error>)?

func ensureConnected(mac: String) async throws {
    let m = mac.lowercased()
    if let c = connecting, c.mac == m {
        try await c.task.value      // 已有人在连 → 等它，别再拆一次
        return
    }
    let task = Task { [self] in try await ensureConnectedInner(mac: m) }
    connecting = (m, task)
    do { try await task.value; … } catch { … }
}
```

关键点：`LockService` 是 `@MainActor`，**设置 `connecting` 之前没有 await**，
所以"检查 + 登记"是原子的，不会两个调用同时判定"没人连"。

任务完成（成功或失败）后清空 `connecting`，避免持有已完成的任务、也解开 self 的强引用环。

## 3. 顺带：连接尝试的记录只算"发起者"

`BleTelemetry.recordAttempt` 只在**真正发起连接**的那条路径上记一次；
后来等待的调用不重复记 —— 否则一次实际连接会被记成 2 条"成功"，把统计稀释。

## 4. 方法论

**"同一件事被两条路径同时做"是最难从代码看出来的 bug 之一 —— 因为两条路径各自都正确。**

| 单看 | 合起来 |
|---|---|
| `preheat()` 没错 | 拆掉了开锁的连接 |
| `runUnlockChain` 没错 | 被预热拆掉了连接 |

这类只能靠**日志里的时间相邻性**发现：两行同一秒的"直连失败"就是签名。

判据：**凡是有"预热 / 预取 / 自动重连"这类后台动作的模块，都要问一句「它会不会和前台动作同时发起同一件事」**；
会的话，加单飞。
