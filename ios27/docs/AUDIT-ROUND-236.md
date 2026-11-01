# AUDIT-ROUND-236 · 第 236 轮：同一块电量，门页和设备页显示两个数字

> CI：**`3d37c55` build 全绿**（WebDAV 上传修复编译通过）；`dcd2888` 排队中。

## 1. 缺陷

`DoorScreen.batteryWord` 直接读原始 `powerLevel` 并自己拼 `"(p)%"`，
而全仓其余四处都走 `BatteryCare.displayPct` + `faceText`：

| 屏 | 取数方式 |
|---|---|
| 设备信息 | `displayPct` + `faceText` |
| 锁设置 | `displayPct` |
| 电池档案 | `displayPct` |
| **门页** | **原始 `powerLevel` + 自己拼百分号** ❌ |

两处差异：

| 差异 | 后果 |
|---|---|
| 不走 `displayPct` | 采样与快照「谁更新用谁」的规则只在 `displayPct` 里 ⇒ **同一块电量两个数字** |
| 不走 `faceText` | 锁侧 >80% 是**粗估档**，别处显示 `>80%`，门页却报成精确的 `87%` |

## 2. 修法

门页改为：`BatteryCare.faceText(BatteryCare.displayPct(mac, snapshot: DB.readStatus(mac)?.powerLevel ?? -1))`

行为等价性已核：`faceText(-1)` = `"--"`（与旧实现的未知分支一致），
而 `powerLevel == -1` 但**有采样**时，现在会显示采样值 —— 与其它四屏一致，信息更全。

## 3. 方法论

**「同一个事实有几种取法」是这类 bug 的根 —— 而它的信号是"有一个调用点长得不一样"。**

| 检查手法 | 结果 |
|---|---|
| grep `BatteryCare.displayPct` | 4 处 —— 看起来"统一了" |
| **grep 底层字段 `powerLevel`** | **找到第 5 处绕过者** |

判据：**验证「是否统一」要 grep 底层字段/原始来源，不是 grep 那个被推荐的封装。**
前者能找到绕过者，后者只能看到「听话的人」。
