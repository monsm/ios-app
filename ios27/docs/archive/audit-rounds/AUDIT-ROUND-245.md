# AUDIT-ROUND-245 · 第 245 轮：**「偏差 531260264 秒」的真正来源**

> CI：`d08ae9d` build 全绿；`838fd66` / `4a3b788` 排队中。

## 1. 缺陷

`StatusParser` 把「锁端没回时钟」存成 `lockTime = 0`（不是 2010-01-01）。
而 `DeviceInfoScreen` 直接拿它算偏差：

    let drift = st.lockTime.map { Int($0 - ZKProtocol.nowProtoSeconds()) }
    if let drift, abs(drift) > 2 { … 自动校时 … }

`nowProtoSeconds()` 是相对 **2010-01-01** 的协议秒（今天约 5.3 亿）。于是 `0 - 5.3e8` ≈ **-531260264**。

**这正是用户报的「偏差 531260264 秒」。**

## 2. 比显示错误更糟的后果

`abs(drift) > 2` 恒成立 ⇒ **每次进设备页都会自动写一次锁钟**（`syncTime()` 是一个会改锁的操作）。
而写完之后固件仍然不回时钟 ⇒ 读数还是 0 ⇒ 下次进页**再写一遍**。

| 现象 | 原因 |
|---|---|
| 偏差显示 -531260264 秒 | `0 - nowProtoSeconds()` |
| 每次进页都「已自动校时」 | `abs(drift) > 2` 恒真 |
| 校时「成功」了但偏差没变 | 锁端本来就没回时钟 |

## 3. 修法（五处）

| 位置 | 修法 |
|---|---|
| `DeviceInfoScreen` 自动校时判定 | `(lockTime ?? 0) > 0` 才算偏差，否则 `nil`（不显示、不校时） |
| `DeviceInfoScreen` 校后重算 | 同上 |
| `DeviceInfoScreen.lockTimeText` | `guard t > 0 else { "—" }`（`localStr(0)` 是空串，会显示成**空白**） |
| `LockSettingsScreen.driftText` | `guard t > 0 else { "未读到锁钟" }` |
| `DoorScreen` 锁钟读数 | `flatMap { lockTime > 0 ? localStr : nil } ?? "未读到"` |

## 4. 为什么之前没抓到

Round 210 修「偏差」那条时，我把它归因为**协议秒 vs Unix 秒**的口径错，
而真正的第二个来源是**「0 不是时刻」**这个哨兵值 —— 两个来源都会产出同一个数量级的大数。

| 来源 | 表现 |
|---|---|
| 协议秒当 Unix 秒（已修） | 偏差 ≈ +5.3e8 或 -1.26e9 |
| **`lockTime == 0` 当真实时刻（本轮）** | **偏差 ≈ -5.3126e8，且会触发自动写锁** |

## 5. 方法论

**「0 是哨兵值」这件事，必须在每一个消费点都处理，不能只在解析层处理一次。**

判据：**一个字段如果有「无值」哨兵（0 / -1 / 空串），就 grep 它所有消费点，逐个确认哨兵被拦下。**
`lockTime` 的消费点有 10 处，其中 5 处没拦 —— 而其中最贵的一处会**改锁**。
