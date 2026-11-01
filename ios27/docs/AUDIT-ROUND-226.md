# AUDIT-ROUND-226 · 第 226 轮：改了有效期，到期提醒还按旧日期弹

> CI：`f744b28` 全绿（`project=yes / swift_files=150`）。

## 1. 缺陷

`setPwdPeriod`（手动改期与**批量延期**都走它）：

```swift
static func setPwdPeriod(_ mac: String, _ alias: Int, _ from: String, _ to: String) {
    var l = ledger(mac)
    for i in l.pwds.indices where l.pwds[i].alias == alias { l.pwds[i].from = from; l.pwds[i].to = to }
    saveLedger(mac, l)      // ← 只改台账
}
```

**完全不碰通知。** 于是：

| 操作 | 旧提醒 | 结果 |
|---|---|---|
| 把「11-10 到期」延到「次年 1-1」 | 仍在 **11-03** 弹「即将到期」 | 用户以为密码快过期了 |

## 2. 为什么这是「同族漏一处」

`cancelAlerts` 的注释里早就写着这个事故：

> **删凭证不会取消提醒** → 删了之后提醒照旧弹，「说密码临期 —— 而那条密码早已不存在」。

那一轮修的是**删**，**改**没修。判据还是同一句：**改/删都要让通知跟着走。**

## 3. 修法

```swift
static func rescheduleAlerts(mac: String, alias: Int) {
    guard let p = DB.listPwds(mac).first(where: { $0.alias == alias }) else { return }
    cancelAlerts(mac: mac, alias: alias)
    let a = alertTable(mac)["pwd:" + String(alias)] ?? CredAlert()
    scheduleAlerts(mac, p, a)
}
```

`setPwdPeriod` 在写成功后调用它（`hit` 为真才调，找不到编号不白排一遍）。

## 4. 顺带核对

| 检查 | 结论 |
|---|---|
| 删除路径取消提醒 | ✅ `delPwd` → `cancelAlerts`；`removeDevice` 也逐条取消 |
| 改提醒开关时重排 | ✅ `CredentialStudioParts` 的开关 setter 先 `saveAlert` 再 `scheduleAlerts` |
| `recordTap` 是否零调用 | ✅ 有 1 个调用点（`DoorScreen:902`），我上一版的统计脚本只数了调用行，误判为定义 |

## 5. 方法论

**「改」和「删」是同一族的两件事，修一件时必须问另一件。**

| 事件 | 副作用要不要跟着走 |
|---|---|
| 删凭证 | ✅ 取消提醒（已修） |
| **改有效期** | ✅ **重排提醒（本轮修）** |
| 改提醒档位 | ✅ 重排（已有） |

判据：**凡是有"派生数据"（通知/日历/缓存/索引）的地方，把「增删改」三件事各问一遍。**
