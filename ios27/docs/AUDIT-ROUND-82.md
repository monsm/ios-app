# AUDIT-ROUND-82 · 第八十二轮：「彻底停止轮询」其实只是每 2 秒醒一次

> CI：`3479121` 已验证（build + golden）；`e150d03` / `816aa3f` 待回执。本轮本地提交。

## 1. 缺陷：注释说"彻底停止"，实现只是空转

```swift
private func pollOnce() async {
    // SEC-04：本机未解锁 / 空壳模式时**彻底停止轮询**，连 RSSI 都不采（不留可推断的无线电痕迹）。
    guard AppLock.shared.unlocked, !AppLock.shared.decoy else { armed = false; return }
```

而控制器的生命周期是：

| 方法 | 实际行为 |
|---|---|
| `start()` | 起一个 `while !Task.isCancelled { pollOnce(); sleep(2s) }` |
| **`stop()`** | **不存在** |
| `onBackground()` | 只置 `wasInBackground = true`，**不停任务** |

所以"锁屏后彻底停止轮询"这件事从来没发生过：任务一直活着，每 2 秒醒一次、判一个条件、返回。

后果：

1. **耗电**：后台/锁屏期间每 2 秒唤醒一次主线程；
2. **与安全承诺不符**：注释明说"不留可推断的无线电痕迹"，而空转本身仍是可观测的定时活动；
3. 更实际的一点：`pollOnce` 里那次 `guard` 之后才判断连接 —— 空转时不做 I/O，所以没有蓝牙痕迹，
   但"彻底停止"这句话是假的。

## 2. 修法

- 新增幂等的 `stop()`（`pollTask?.cancel(); pollTask = nil`）；
- `onBackground()` 调 `stop()`；
- `pollOnce()` 在"未解锁 / 空壳"分支里 `stop()`（而不是只置 `armed = false`）；
- `onForeground()` 在**非空壳**时 `start()` 恢复；
- 退出空壳时（`AppModel.reload` 的 `else if wasDecoy` 分支）调一次 `onForeground(mac:)` 恢复 ——
  与那里已经在做的"重建通知面"对称。

## 3. 一个我差点引入的坑

第一版让 `onForeground` 无条件 `start()`。但空壳模式下 `unlocked` 也是 true ⇒ 会 start，
`pollOnce` 立刻又 stop ⇒ **每 2 秒启停一次**（比原来更糟）。
所以加 `if !AppLock.shared.decoy { start() }`，并在注释里写清为什么。

## 4. 方法论

**"停止"必须有对应的 `cancel()`，否则它只是"跳过本次工作"。**

判据：**看到注释里写"停止/关闭/暂停 某个循环/任务"，立刻去搜那个任务的 `cancel()`**；
搜不到就说明它没停 —— 而这个差别在负载低的时候**完全看不出来**，只在耗电与安全审计里显形。
