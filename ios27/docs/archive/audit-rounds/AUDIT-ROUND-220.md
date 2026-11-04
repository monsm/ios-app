# AUDIT-ROUND-220 · 第 220 轮：`BleTelemetry.events` 有写无读 —— 接进交互流水页

> CI：`9aee6fa` 已验证绿；`71e370d` / `f3ae3f7` 排队中。

## 1. 缺陷

`BleTelemetry.recordEvent("…", ok:)` 在**13 处**被调用：

| 调用点 | 记的是什么 |
|---|---|
| `BackupStudioKit` | 备份里有非法 skey / pin，已跳过该锁 |
| `StoreLedger` / `StoreKeychain` | 台账不可解被拒写、口令没能进钥匙串 |
| `ZKProtocol` | buildKLV 超长拒绝、帧重组缓冲超限 |
| `ZOTP` | 周期异常 |
| （本轮新增）`BackupStudioKit.restore` | 恢复时归属找不到 |

而 **`BleTelemetry.events` 全仓没有任何界面读** —— 这些"发生了什么"永远只躺在 `kf_ble_events.json` 里。

## 2. 修法

「交互流水」页新增一块**事件台账**（最近 40 条），并把它拼进复制文本（**两种复制模式都带** —— 它只写"发生了什么"，不含密钥）。

顺带避开一个坑：`BleEvent.id = at + what + ok`，**同一分钟重复事件会产生重复 id**，所以渲染用 `ForEach(Array(events.enumerated()), id: \.offset)`，不用 `ForEach(events)`。

## 3. 这条为什么重要

用户报「全新恢复后成员和凭证不关联」时，如果这条通路早就通着，**他第一次恢复完就能看到**：

> `11-01 22:5x [!!] 恢复：凭证 #3 的归属「张三」在本机找不到（既不是 id 也不是名字），已置空`

而不是等到几天后发现"怎么不关联了"。

| 信息 | 之前 | 现在 |
|---|---|---|
| 有没有丢关联 | ❌ 只有结果数字 | ✅ 事件台账 + 恢复结果行 |
| 为什么丢 | ❌ | ✅ 记了具体的归属值 |

## 4. 方法论

**"有采集无出口"是本仓最高产的一条线** —— 本轮之前已经靠它抓到 `surplus` / `keyboardFreeze` / `pwdInfoMaxLen` / `recordAttempt` / `foreignKeyHint`，现在轮到 `BleTelemetry.events` 本身。

判据：**每次看到 `recordEvent` / `append` / `insert` 这类写入，就 grep 一次它的读取口有没有 UI。**
没有 UI 的采集，等于没采集 —— 只是给磁盘增加负担。
